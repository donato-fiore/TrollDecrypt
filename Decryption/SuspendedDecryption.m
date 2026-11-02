#import "SuspendedDecryption.h"
#import "MachOInspection.h"
#import "LaunchdResponse.h"
#import <mach/mach.h>
#import <spawn.h>
#import <fcntl.h>
#import <sys/stat.h>
#import <sys/file.h>
#import <sys/wait.h>
#import <signal.h>
#import <unistd.h>
#import <copyfile.h>

extern kern_return_t mach_vm_region(vm_map_read_t, mach_vm_address_t *, mach_vm_size_t *,
    vm_region_flavor_t, vm_region_info_t, mach_msg_type_number_t *, mach_port_t *);
extern kern_return_t mach_vm_read_overwrite(vm_map_read_t, mach_vm_address_t, mach_vm_size_t,
    mach_vm_address_t, mach_vm_size_t *);
extern int posix_spawnattr_set_persona_np(posix_spawnattr_t *, uid_t, uint32_t);
extern int posix_spawnattr_set_persona_uid_np(posix_spawnattr_t *, uid_t);
extern int posix_spawnattr_set_persona_gid_np(posix_spawnattr_t *, gid_t);

static volatile sig_atomic_t permissionFD = -1;
static mode_t originalMode;
static volatile sig_atomic_t suspendedPID = -1;

static void TDInterruptSuspendedDecryption(int signalNumber) {
    if (permissionFD >= 0) fchmod(permissionFD, originalMode);
    if (suspendedPID > 0) kill(suspendedPID, SIGKILL);
    _exit(128 + signalNumber);
}

BOOL TDDecryptSuspendedExecutableInHelper(NSString *bundlePath, NSString *outputPath, NSError **error) {
    NSFileManager *fm = NSFileManager.defaultManager;
    bundlePath = bundlePath.stringByResolvingSymlinksInPath;
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:[bundlePath stringByAppendingPathComponent:@"Info.plist"]];
    NSString *executable = plist[@"CFBundleExecutable"];
    NSString *identifier = plist[@"CFBundleIdentifier"];
    NSString *failure = nil;
    if (geteuid() != 0 || ![executable isKindOfClass:NSString.class] || !executable.length ||
        ![executable isEqualToString:executable.lastPathComponent] ||
        ![identifier isKindOfClass:NSString.class] || !identifier.length) {
        failure = @"The executable helper requires root access and valid bundle metadata.";
    }
    NSString *sourcePath = failure ? nil : [[bundlePath stringByAppendingPathComponent:executable] stringByResolvingSymlinksInPath];
    if (sourcePath && (![sourcePath hasPrefix:[bundlePath stringByAppendingString:@"/"]] ||
        [sourcePath isEqualToString:outputPath.stringByResolvingSymlinksInPath])) {
        failure = @"The executable source and output paths are invalid.";
    }
    NSError *inspectionError = nil;
    NSArray<TDMachOImage *> *images = failure ? nil : TDInspectMachO(sourcePath, &inspectionError);
    TDMachOImage *image = images.firstObject;
    if (!failure && (!images || images.count != 1 || image.cpuType != CPU_TYPE_ARM64 || image.fileType != MH_EXECUTE)) {
        failure = inspectionError.localizedDescription ?: @"Suspended decryption requires a single arm64 executable.";
    }
    if (!failure && image.encryption.cryptid == 0) {
        NSArray<TDMachOImage *> *outputImages = TDInspectMachO(outputPath, &inspectionError);
        if (outputImages.count == 1 && outputImages[0].encryption.cryptid == 0) return YES;
        failure = @"The unencrypted executable is missing from the output bundle.";
    }
    if (!failure && image.encryptedVMOffset == UINT64_MAX) failure = @"The encrypted range is not backed by a valid Mach-O segment.";
    if (failure) {
        if (error) *error = [NSError errorWithDomain:@"com.fiore.TDError" code:101 userInfo:@{NSLocalizedDescriptionKey:failure}];
        return NO;
    }

    int sourceFD = -1, outputFD = -1;
    mach_port_t task = MACH_PORT_NULL;
    pid_t pid = -1;
    NSString *temporaryPath = [outputPath stringByAppendingFormat:@".%@.decrypting", NSUUID.UUID.UUIDString];
    struct stat sourceStat;
    struct sigaction action = {0}, oldTerm, oldInt, oldHup;
    action.sa_handler = TDInterruptSuspendedDecryption;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, &oldTerm);
    sigaction(SIGINT, &action, &oldInt);
    sigaction(SIGHUP, &action, &oldHup);
    @try {
        do {
            sourceFD = open(sourcePath.fileSystemRepresentation, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
            // Serialize permission changes on the installed inode across simultaneous exports.
            if (sourceFD < 0 || flock(sourceFD, LOCK_EX) != 0 || fstat(sourceFD, &sourceStat) != 0 || !S_ISREG(sourceStat.st_mode)) {
                failure = @"Cannot open the installed executable."; break;
            }
            originalMode = sourceStat.st_mode & 07777;
            if ((originalMode & 0111) != 0111) {
                // Unsupported extensions are installed without execute bits. FairPlay needs the
                // installed inode, so a relocated, chmod'ed copy cannot replace this short window.
                permissionFD = sourceFD;
                if (fchmod(sourceFD, originalMode | 0111) != 0) {
                    failure = @"Cannot temporarily enable execution of the installed executable."; break;
                }
            }
            NSString *label = [NSString stringWithFormat:@"UIKitApplication:%@[%@]", identifier, NSUUID.UUID.UUIDString];
            NSDictionary *job = @{@"UserName":@"mobile", @"CFBundleIdentifier":identifier,
                @"_ManagedBy":@"com.apple.runningboard", @"Label":label,
                @"ProgramArguments":@[sourcePath], @"Program":sourcePath, @"StartSuspended":@YES};
            xpc_object_t request = _CFXPCCreateXPCObjectFromCFObject(@{@"monitor":@NO, @"plist":job});
            xpc_dictionary_set_uint64(request, "handle", 0);
            xpc_dictionary_set_uint64(request, "type", 7);
            xpc_object_t reply = NULL;
            kern_return_t launchResult = _launch_job_routine(OSLaunchdJobSelectorSubmitAndStart, request, &reply);
            if (reply && xpc_get_type(reply) == XPC_TYPE_DICTIONARY) {
                pid = (pid_t)xpc_dictionary_get_int64(reply, "pid");
            }
            suspendedPID = pid;
            if (permissionFD >= 0) {
                if (fchmod(sourceFD, originalMode) != 0) { failure = @"Cannot restore the executable's original permissions."; break; }
                permissionFD = -1;
            }
            if (launchResult != KERN_SUCCESS || pid <= 0) {
                int64_t spawnError = reply && xpc_get_type(reply) == XPC_TYPE_DICTIONARY
                    ? xpc_dictionary_get_int64(reply, "spawn-error") : 0;
                failure = [NSString stringWithFormat:@"Cannot start the executable suspended (launch=%d, spawn=%lld).", launchResult, spawnError];
                break;
            }
            kern_return_t kr = KERN_FAILURE;
            for (NSUInteger retry = 0; retry < 100; retry++) {
                kr = task_for_pid(mach_task_self(), pid, &task);
                if (kr == KERN_SUCCESS) break;
                usleep(10000);
            }
            if (kr != KERN_SUCCESS) { failure = @"Cannot read the suspended executable's task."; break; }

            // dyld has not run, so its image list cannot be used here. Match the on-disk
            // header and load commands rather than mistaking dyld or a shared-cache image for it.
            mach_vm_address_t address = 0, loadAddress = 0;
            NSMutableData *headerBuffer = [NSMutableData dataWithLength:image.headerData.length];
            for (NSUInteger region = 0; region < 4096; region++) {
                mach_vm_size_t regionSize = 0;
                vm_region_basic_info_data_64_t info;
                mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
                mach_port_t object = MACH_PORT_NULL;
                kr = mach_vm_region(task, &address, &regionSize, VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object);
                if (object != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), object);
                if (kr != KERN_SUCCESS) break;
                if ((info.protection & VM_PROT_READ) && regionSize >= image.headerData.length) {
                    mach_vm_size_t copied = 0;
                    kr = mach_vm_read_overwrite(task, address, image.headerData.length, (mach_vm_address_t)headerBuffer.mutableBytes, &copied);
                    if (kr == KERN_SUCCESS && copied == image.headerData.length && [headerBuffer isEqualToData:image.headerData]) {
                        loadAddress = address; break;
                    }
                }
                if (!regionSize || address > UINT64_MAX - regionSize) break;
                address += regionSize;
            }
            if (!loadAddress || loadAddress > UINT64_MAX - image.encryptedVMOffset - image.encryption.cryptsize) {
                failure = @"Cannot locate the suspended executable's original image."; break;
            }
            outputFD = open(temporaryPath.fileSystemRepresentation, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0600);
            if (outputFD < 0) { failure = @"Cannot write the decrypted executable."; break; }
            if (fcopyfile(sourceFD, outputFD, NULL, COPYFILE_DATA) != 0) {
                failure = @"Cannot copy the original executable into the output."; break;
            }
            uint8_t plain[16384], encrypted[16384];
            uint64_t done = 0;
            BOOL changed = NO, nonzero = NO;
            while (done < image.encryption.cryptsize) {
                size_t length = (size_t)MIN(sizeof(plain), image.encryption.cryptsize - done);
                mach_vm_size_t copied = 0;
                kr = mach_vm_read_overwrite(task, loadAddress + image.encryptedVMOffset + done, length, (mach_vm_address_t)plain, &copied);
                if (kr != KERN_SUCCESS || copied != length ||
                    pread(sourceFD, encrypted, length, image.fileOffset + image.encryption.cryptoff + done) != (ssize_t)length) {
                    failure = @"Cannot read the executable's decrypted pages."; break;
                }
                changed |= memcmp(plain, encrypted, length) != 0;
                for (size_t i = 0; i < length; i++) nonzero |= plain[i] != 0;
                size_t written = 0;
                while (written < length) {
                    ssize_t n = pwrite(outputFD, plain + written, length - written, image.fileOffset + image.encryption.cryptoff + done + written);
                    if (n < 0 && errno == EINTR) continue;
                    if (n <= 0) { failure = @"Cannot save the decrypted pages."; break; }
                    written += (size_t)n;
                }
                if (failure) break;
                done += length;
            }
            if (failure) break;
            if (!changed || !nonzero) { failure = @"The system did not return decrypted executable pages."; break; }
            uint32_t zero = 0;
            if (pwrite(outputFD, &zero, sizeof(zero), image.fileOffset + image.encryptionCommandOffset + offsetof(struct encryption_info_command, cryptid)) != sizeof(zero) ||
                fchmod(outputFD, (originalMode & 0777) | 0111) != 0 ||
                fchown(outputFD, 501, 501) != 0) {
                failure = @"Cannot finalize the decrypted executable."; break;
            }
            // Only publish after every encrypted byte was read and written successfully.
            if (rename(temporaryPath.fileSystemRepresentation, outputPath.fileSystemRepresentation) != 0) {
                failure = @"Cannot replace the output executable."; break;
            }
        } while (NO);

    } @finally {
        if (permissionFD >= 0 && fchmod(permissionFD, originalMode) != 0) {
            failure = @"Cannot restore the executable's original permissions.";
        }
        permissionFD = -1;
        if (pid > 0) kill(pid, SIGKILL);
        suspendedPID = -1;
        if (task != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), task);
        if (outputFD >= 0) close(outputFD);
        if (sourceFD >= 0) close(sourceFD);
        [fm removeItemAtPath:temporaryPath error:nil];
        sigaction(SIGTERM, &oldTerm, NULL);
        sigaction(SIGINT, &oldInt, NULL);
        sigaction(SIGHUP, &oldHup, NULL);
    }
    if (failure && error) *error = [NSError errorWithDomain:@"com.fiore.TDError" code:101 userInfo:@{NSLocalizedDescriptionKey:failure}];
    return failure == nil;
}

BOOL TDDecryptSuspendedExecutable(NSString *bundlePath, NSString *outputPath, NSError **error) {
    NSString *executable = NSBundle.mainBundle.executablePath;
    int descriptors[2];
    if (pipe(descriptors) != 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return NO;
    }
    posix_spawnattr_t attributes;
    posix_spawnattr_init(&attributes);
    int result = posix_spawnattr_set_persona_np(&attributes, 99, 1);
    if (!result) result = posix_spawnattr_set_persona_uid_np(&attributes, 0);
    if (!result) result = posix_spawnattr_set_persona_gid_np(&attributes, 0);
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addclose(&actions, descriptors[0]);
    posix_spawn_file_actions_adddup2(&actions, descriptors[1], STDERR_FILENO);
    posix_spawn_file_actions_addclose(&actions, descriptors[1]);
    char *arguments[] = {(char *)executable.fileSystemRepresentation, "--decrypt-suspended",
        (char *)bundlePath.fileSystemRepresentation, (char *)outputPath.fileSystemRepresentation, NULL};
    char *environment[] = {NULL};
    pid_t pid = -1;
    if (!result) result = posix_spawn(&pid, executable.fileSystemRepresentation, &actions, &attributes, arguments, environment);
    posix_spawn_file_actions_destroy(&actions);
    posix_spawnattr_destroy(&attributes);
    close(descriptors[1]);
    NSMutableData *diagnostics = [NSMutableData data];
    if (!result && pid > 0) {
        char buffer[4096];
        ssize_t count;
        while ((count = read(descriptors[0], buffer, sizeof(buffer))) != 0) {
            if (count < 0) { if (errno == EINTR) continue; break; }
            if (diagnostics.length < 65536) [diagnostics appendBytes:buffer length:MIN((NSUInteger)count, 65536 - diagnostics.length)];
        }
    }
    close(descriptors[0]);
    int status = 0;
    pid_t waited = -1;
    if (!result && pid > 0) {
        do { waited = waitpid(pid, &status, 0); } while (waited < 0 && errno == EINTR);
        if (waited == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0) return YES;
    }
    NSString *message = [[NSString alloc] initWithData:diagnostics encoding:NSUTF8StringEncoding];
    if (!message.length) message = [NSString stringWithFormat:@"Decryption helper failed (spawn=%d, status=%d).", result, status];
    if (error) *error = [NSError errorWithDomain:@"com.fiore.TDError" code:101 userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}
