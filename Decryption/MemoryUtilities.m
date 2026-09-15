#import "MemoryUtilities.h"

#define MAX_DYLD_INFO_RETRIES 300
#define DYLD_INFO_RETRY_DELAY_US 10000

#define MALLOC_CHUNK_SIZE (1 << 20) // 1 MB

kern_return_t mach_vm_read_overwrite(vm_map_read_t target_task, mach_vm_address_t address, mach_vm_size_t size, mach_vm_address_t data, mach_vm_size_t *outsize);
kern_return_t mach_vm_region(vm_map_read_t target_task, mach_vm_address_t *address, mach_vm_size_t *size, vm_region_flavor_t flavor, vm_region_info_t info, mach_msg_type_number_t *infoCnt, mach_port_t *object_name);

// <libproc.h> is not shipped in the iPhoneOS SDK.
extern int proc_regionfilename(int pid, uint64_t address, void *buffer, uint32_t buffersize);

static void removePrefix(char *str, const char *prefix) {
    size_t len_str = strlen(str);
    size_t len_prefix = strlen(prefix);

    if (len_str >= len_prefix && strncmp(str, prefix, len_prefix) == 0) {
        memmove(str, str + len_prefix, len_str - len_prefix + 1);
    }
}

// Mach-O images can be reported either with or without the /private prefix
// depending on who resolved the path, so compare both spellings.
static bool imagePathsMatch(char *candidate, const char *expected) {
    if (strcmp(candidate, expected) == 0) return true;
    removePrefix(candidate, "/private");
    return strcmp(candidate, expected) == 0;
}

static bool readFully(int fd, void *buffer, size_t size) {
    size_t totalRead = 0;
    while (totalRead < size) {
        ssize_t bytesRead = read(fd, (uint8_t *)buffer + totalRead, size - totalRead);
        if (bytesRead <= 0) {
            return NO;
        }
        totalRead += bytesRead;
    }
    return YES;
}

static bool writeFully(int fd, const void *buffer, size_t size) {
    size_t totalWritten = 0;
    while (totalWritten < size) {
        ssize_t bytesWritten = write(fd, (const uint8_t *)buffer + totalWritten, size - totalWritten);
        if (bytesWritten <= 0) {
            return NO;
        }
        totalWritten += bytesWritten;
    }
    return YES;
}

static BOOL readProcessMemory(vm_map_t task, uint64_t address, void *buffer, size_t size) {
    if (!buffer || size == 0) {
        NSLog(@"invalid buffer or size");
        return NO;
    }

    mach_vm_size_t outSize = 0;
    kern_return_t kr = mach_vm_read_overwrite((task_t)task, address, size,
                                              (mach_vm_address_t)buffer, &outSize);
    if (kr == KERN_SUCCESS && outSize == size) {
        return YES;
    }

    // A single read is refused when the range straddles a VM region boundary,
    // which happens routinely for the crypt region of a large __TEXT segment.
    // Retry page by page before giving up.
    size_t pageSize = (size_t)getpagesize();
    size_t done = 0;
    while (done < size) {
        uint64_t chunkAddress = address + done;
        size_t chunk = pageSize - (size_t)(chunkAddress & (pageSize - 1));
        if (chunk > size - done) chunk = size - done;

        outSize = 0;
        kr = mach_vm_read_overwrite((task_t)task, chunkAddress, chunk,
                                    (mach_vm_address_t)((uint8_t *)buffer + done), &outSize);
        if (kr != KERN_SUCCESS || outSize != chunk) {
            NSLog(@"mach_vm_read_overwrite failed at 0x%llx (kr=%d out=%llu want=%zu)",
                  chunkAddress, kr, outSize, chunk);
            return NO;
        }

        done += chunk;
    }

    return YES;
}

// Reads a NUL terminated string out of the target process. Unlike a fixed size
// read this tolerates the string sitting at the tail of a mapped region.
static BOOL readProcessString(vm_map_t task, uint64_t address, char *buffer, size_t size) {
    if (!buffer || size == 0) return NO;

    memset(buffer, 0, size);

    size_t pageSize = (size_t)getpagesize();
    size_t done = 0;
    while (done < size - 1) {
        uint64_t chunkAddress = address + done;
        size_t chunk = pageSize - (size_t)(chunkAddress & (pageSize - 1));
        if (chunk > size - 1 - done) chunk = size - 1 - done;

        mach_vm_size_t outSize = 0;
        kern_return_t kr = mach_vm_read_overwrite((task_t)task, chunkAddress, chunk,
                                                  (mach_vm_address_t)(buffer + done), &outSize);
        if (kr != KERN_SUCCESS || outSize != chunk) {
            return done > 0;
        }

        if (memchr(buffer + done, 0, chunk)) return YES;
        done += chunk;
    }

    return YES;
}

TDEncryptionState encryptionStateOfImageAtPath(NSString *path) {
    int fd = open(path.UTF8String, O_RDONLY);
    if (fd < 0) return TDEncryptionStateUnknown;

    struct mach_header_64 header = {0};
    if (!readFully(fd, &header, sizeof(header))) {
        close(fd);
        return TDEncryptionStateUnknown;
    }

    // Fat binaries would need per-slice offsets that the rebuild path does not
    // model, so leave them to the in-process inspection.
    if (header.magic != MH_MAGIC_64 && header.magic != MH_MAGIC) {
        close(fd);
        return TDEncryptionStateUnknown;
    }

    uint64_t offset = (header.magic == MH_MAGIC_64) ? sizeof(struct mach_header_64)
                                                    : sizeof(struct mach_header);
    TDEncryptionState state = TDEncryptionStateDecrypted;
    for (uint32_t i = 0; i < header.ncmds; i++) {
        if (lseek(fd, (off_t)offset, SEEK_SET) < 0) { state = TDEncryptionStateUnknown; break; }

        struct load_command loadCommand = {0};
        if (!readFully(fd, &loadCommand, sizeof(loadCommand))) { state = TDEncryptionStateUnknown; break; }
        if (loadCommand.cmdsize < sizeof(loadCommand)) { state = TDEncryptionStateUnknown; break; }

        if (loadCommand.cmd == LC_ENCRYPTION_INFO || loadCommand.cmd == LC_ENCRYPTION_INFO_64) {
            if (lseek(fd, (off_t)offset, SEEK_SET) < 0) { state = TDEncryptionStateUnknown; break; }

            struct encryption_info_command encryptionInfo = {0};
            if (!readFully(fd, &encryptionInfo, sizeof(encryptionInfo))) { state = TDEncryptionStateUnknown; break; }

            state = encryptionInfo.cryptid == 0 ? TDEncryptionStateDecrypted : TDEncryptionStateEncrypted;
            break;
        }

        offset += loadCommand.cmdsize;
    }

    close(fd);
    return state;
}

NSString *NSStringFromMainImageInfo(MainImageInfo_t info) {
    return [NSString stringWithFormat:@"MainImageInfo: loadAddress=0x%llx, path=%@, ok=%d",
            info.loadAddress, info.path, info.ok];
}

// Legacy lookup: dyld publishes every loaded image in dyld_all_image_infos.
// dyld stopped populating that array on iOS 26, so this can legitimately come
// back empty on a perfectly healthy process.
static MainImageInfo_t imageInfoFromDyldImageArray(const char *sourcePath, vm_map_t task, pid_t pid) {
    MainImageInfo_t notFound = {.ok = NO};

    task_dyld_info_data_t taskInfo;
    mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
    kern_return_t kr = task_info((task_t)task, TASK_DYLD_INFO, (task_info_t)&taskInfo, &count);
    if (kr != KERN_SUCCESS || taskInfo.all_image_info_addr == 0) {
        return notFound;
    }

    struct dyld_all_image_infos infos = {0};
    if (!readProcessMemory(task, taskInfo.all_image_info_addr, &infos, sizeof(infos))) {
        return notFound;
    }

    if (infos.infoArrayCount == 0 || infos.infoArray == NULL) {
        return notFound;
    }

    mach_vm_size_t imageInfoSize = sizeof(struct dyld_image_info) * infos.infoArrayCount;
    void *imageInfoData = malloc(imageInfoSize);
    if (!imageInfoData) return notFound;

    if (!readProcessMemory(task, (mach_vm_address_t)infos.infoArray, imageInfoData, imageInfoSize)) {
        NSLog(@"failed to read dyld_image_info array for pid %d", pid);
        free(imageInfoData);
        return notFound;
    }

    struct dyld_image_info *imageInfos = (struct dyld_image_info *)imageInfoData;
    for (uint32_t j = 0; j < infos.infoArrayCount; j++) {
        char pathBuffer[PATH_MAX] = {0};
        if (!readProcessString(task, (uint64_t)imageInfos[j].imageFilePath, pathBuffer, sizeof(pathBuffer))) {
            continue;
        }

        if (imagePathsMatch(pathBuffer, sourcePath)) {
            MainImageInfo_t result = {
                .loadAddress = (mach_vm_address_t)imageInfos[j].imageLoadAddress,
                .path = [NSString stringWithUTF8String:pathBuffer],
                .ok = YES
            };

            NSLog(@"found image via dyld image array for pid %d: %@", pid, result.path);
            free(imageInfoData);
            return result;
        }
    }

    free(imageInfoData);
    return notFound;
}

// iOS 26 lookup: walk the task's VM map and identify each mapped Mach-O header
// by the file backing its region. This does not depend on dyld bookkeeping and
// works as soon as the kernel has mapped the image.
static MainImageInfo_t imageInfoByScanningRegions(const char *sourcePath, vm_map_t task, pid_t pid) {
    mach_vm_address_t address = 0;
    mach_vm_size_t size = 0;

    while (true) {
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t objectName = MACH_PORT_NULL;

        kern_return_t kr = mach_vm_region((task_t)task, &address, &size, VM_REGION_BASIC_INFO_64,
                                          (vm_region_info_t)&info, &infoCount, &objectName);
        if (kr != KERN_SUCCESS) break;

        if ((info.protection & VM_PROT_READ) && size >= sizeof(struct mach_header_64)) {
            struct mach_header_64 header = {0};
            if (readProcessMemory(task, address, &header, sizeof(header)) &&
                header.magic == MH_MAGIC_64 &&
                (header.filetype == MH_EXECUTE || header.filetype == MH_DYLIB || header.filetype == MH_BUNDLE)) {

                char pathBuffer[PATH_MAX] = {0};
                if (proc_regionfilename(pid, address, pathBuffer, (uint32_t)sizeof(pathBuffer)) > 0 &&
                    imagePathsMatch(pathBuffer, sourcePath)) {
                    MainImageInfo_t result = {
                        .loadAddress = address,
                        .path = [NSString stringWithUTF8String:pathBuffer],
                        .ok = YES
                    };

                    NSLog(@"found image via region scan for pid %d: %@", pid, result.path);
                    return result;
                }
            }
        }

        address += size;
    }

    return (MainImageInfo_t){.ok = NO};
}

MainImageInfo_t imageInfoForPIDWithRetry(const char *sourcePath, vm_map_t task, pid_t pid) {
    NSLog(@"looking for image %s in pid %d", sourcePath, pid);

    for (int i = 0; i < MAX_DYLD_INFO_RETRIES; i++) {
        MainImageInfo_t info = imageInfoFromDyldImageArray(sourcePath, task, pid);
        if (info.ok) return info;

        info = imageInfoByScanningRegions(sourcePath, task, pid);
        if (info.ok) return info;

        usleep(DYLD_INFO_RETRY_DELAY_US);
    }

    NSLog(@"image %s not found in pid %d (timed out)", sourcePath, pid);
    return (MainImageInfo_t){.ok = NO};
}

BOOL readEncryptionInfo(vm_map_t task, uint64_t address,
                        struct encryption_info_command *encryptionInfo,
                        uint64_t *loadCommandAddress) {
    if (!encryptionInfo || !loadCommandAddress) {
        NSLog(@"invlaid encryptionInfo or loadCommandAddress");
        return NO;
    }

    struct mach_header_64 machHeader;
    if (!readProcessMemory(task, address, &machHeader, sizeof(machHeader))) {
        NSLog(@"failed to read mach header");
        return NO;
    }

    uint64_t offset = 0;
    switch (machHeader.magic) {
        case MH_MAGIC_64:
            offset = sizeof(struct mach_header_64);
            break;
        case MH_MAGIC:
            offset = sizeof(struct mach_header);
            break;
        default:
            NSLog(@"unknown Mach-O magic: 0x%x", machHeader.magic);
            return NO;
    }

    if (machHeader.ncmds == 0) {
        NSLog(@"no load commands found");
        return NO;
    }

    for (uint32_t i = 0; i < machHeader.ncmds; i++) {
        struct load_command loadCommand;
        if (!readProcessMemory(task, address + offset, &loadCommand, sizeof(loadCommand))) {
            NSLog(@"failed to read load command");
            return NO;
        }

        if (loadCommand.cmd == LC_ENCRYPTION_INFO || loadCommand.cmd == LC_ENCRYPTION_INFO_64) {
            struct encryption_info_command encInfo;
            if (!readProcessMemory(task, address + offset, &encInfo, sizeof(encInfo))) {
                NSLog(@"failed to read encryption info command");
                return NO;
            }

            *encryptionInfo = encInfo;
            *loadCommandAddress = address + offset;
            return YES;
        }

        offset += loadCommand.cmdsize;
    }

    return YES;
}

BOOL rebuildDecryptedImageAtPath(NSString *sourcePath,
                                 vm_map_t task,
                                 uint64_t loadAddress,
                                 struct encryption_info_command *encryptionInfo,
                                 uint64_t loadCommandAddress,
                                 NSString *outputPath) {
    if (!encryptionInfo) {
        NSLog(@"encryptionInfo is NULL");
        return NO;
    }

    uint32_t cryptoff  = encryptionInfo->cryptoff;
    uint32_t cryptsize = encryptionInfo->cryptsize;

    NSLog(@"Rebuilding decrypted image: %@", sourcePath);
    NSLog(@"Load address: 0x%llx", loadAddress);
    NSLog(@"cryptoff=0x%x cryptsize=0x%x cryptid=%d",
          cryptoff, cryptsize, encryptionInfo->cryptid);

    int fd = open(sourcePath.UTF8String, O_RDONLY);
    if (fd < 0) {
        NSLog(@"open source failed (%d): %@", errno, sourcePath);
        return NO;
    }

    off_t fileSize = lseek(fd, 0, SEEK_END);
    if (fileSize < 0) {
        NSLog(@"lseek end failed (%d)", errno);
        close(fd);
        return NO;
    }

    lseek(fd, 0, SEEK_SET);

    uint64_t cryptEnd = (uint64_t)cryptoff + (uint64_t)cryptsize;
    if (cryptEnd > (uint64_t)fileSize) {
        NSLog(@"crypt region outside file: cryptEnd=0x%llx fileSize=0x%llx",
              cryptEnd, (uint64_t)fileSize);
        close(fd);
        return NO;
    }

    // NSString *debugOutputPath = [outputPath stringByAppendingString:@".decrypted"];
    int outputFd = open(outputPath.UTF8String, O_RDWR | O_CREAT | O_TRUNC, 0644);
    if (outputFd < 0) {
        NSLog(@"open output failed (%d): %@", errno, outputPath);
        close(fd);
        return NO;
    }

    // Leading [0, cryptoff)
    if (lseek(fd, 0, SEEK_SET) < 0) {
        NSLog(@"lseek set failed (%d)", errno);
        close(fd);
        close(outputFd);
        return NO;
    }

    if (cryptoff > 0) {
        void *leading = malloc(cryptoff);
        if (!leading) {
            NSLog(@"malloc leading failed");
            close(fd);
            close(outputFd);
            return NO;
        }

        if (!readFully(fd, leading, cryptoff)) {
            NSLog(@"read leading failed (%d)", errno);
            free(leading);
            close(fd);
            close(outputFd);
            return NO;
        }

        if (!writeFully(outputFd, leading, cryptoff)) {
            NSLog(@"write leading failed (%d)", errno);
            free(leading);
            close(fd);
            close(outputFd);
            return NO;
        }

        free(leading);
    }

    // [cryptoff .. cryptoff+cryptsize)
    if (cryptsize > 0) {
        void *decrypted = malloc(cryptsize);
        if (!decrypted) {
            NSLog(@"malloc decrypted failed");
            close(fd);
            close(outputFd);
            return NO;
        }

        // IMPORTANT: read from mapped memory at loadAddress + cryptoff
        if (!readProcessMemory(task, loadAddress + (uint64_t)cryptoff, decrypted, cryptsize)) {
            NSLog(@"failed to read decrypted bytes from task memory");
            free(decrypted);
            close(fd);
            close(outputFd);
            return NO;
        }

        if (!writeFully(outputFd, decrypted, cryptsize)) {
            NSLog(@"write decrypted failed (%d)", errno);
            free(decrypted);
            close(fd);
            close(outputFd);
            return NO;
        }

        free(decrypted);
    }

    // Trailing [cryptEnd, EOF)
    uint64_t trailingSize = (uint64_t)fileSize - cryptEnd;
    if (trailingSize > 0) {
        uint8_t *buf = malloc(MALLOC_CHUNK_SIZE);
        if (!buf) {
            NSLog(@"malloc trailing buf failed");
            close(fd);
            close(outputFd);
            return NO;
        }

        if (lseek(fd, (off_t)cryptEnd, SEEK_SET) < 0) {
            NSLog(@"lseek to trailing failed (%d)", errno);
            free(buf);
            close(fd);
            close(outputFd);
            return NO;
        }

        uint64_t left = trailingSize;
        while (left > 0) {
            size_t toRead = (left > MALLOC_CHUNK_SIZE) ? MALLOC_CHUNK_SIZE : (size_t)left;

            if (!readFully(fd, buf, toRead)) {
                NSLog(@"read trailing failed (%d)", errno);
                free(buf);
                close(fd);
                close(outputFd);
                return NO;
            }

            if (!writeFully(outputFd, buf, toRead)) {
                NSLog(@"write trailing failed (%d)", errno);
                free(buf);
                close(fd);
                close(outputFd);
                return NO;
            }

            left -= toRead;
        }

        free(buf);
    }

    if (loadCommandAddress) {
        off_t cmdOff = (off_t)((uint64_t)loadCommandAddress - (uint64_t)loadAddress);

        if (lseek(outputFd, cmdOff, SEEK_SET) < 0) {
            NSLog(@"lseek to enc cmd failed (%d)", errno);
            close(fd);
            close(outputFd);
            return NO;
        }

        struct encryption_info_command outputEncInfo = {0};
        if (!readFully(outputFd, &outputEncInfo, sizeof(outputEncInfo))) {
            NSLog(@"read enc cmd failed (%d)", errno);
            close(fd);
            close(outputFd);
            return NO;
        }

        outputEncInfo.cryptid = 0;

        if (lseek(outputFd, cmdOff, SEEK_SET) < 0) {
            NSLog(@"lseek back to enc cmd failed (%d)", errno);
            close(fd);
            close(outputFd);
            return NO;
        }

        if (!writeFully(outputFd, &outputEncInfo, sizeof(outputEncInfo))) {
            NSLog(@"write enc cmd failed (%d)", errno);
            close(fd);
            close(outputFd);
            return NO;
        }
    }

    close(fd);
    close(outputFd);


    return YES;
}