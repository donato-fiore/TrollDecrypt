#import "MachOInspection.h"
#import <mach-o/fat.h>
#import <libkern/OSByteOrder.h>
#import <xpc/xpc.h>
#import "LaunchdResponse.h"
#import "DecryptionOutput.h"
#import <fcntl.h>
#import <unistd.h>

#define CHECK(condition) do { if (!(condition)) { fprintf(stderr, "Failed at line %d: %s\n", __LINE__, #condition); return 1; } } while (0)

int main(void) {
    @autoreleasepool {
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *app = [root stringByAppendingPathComponent:@"Example.app"];
        NSString *originalDirectory = fm.currentDirectoryPath;
        @try {
            CHECK(NIL_LAUNCHD_RESPONSE.pid == -1);
            xpc_object_t response = xpc_dictionary_create(NULL, NULL, 0);
            CHECK(responseFromXPCObject(response).pid == -1);
            xpc_dictionary_set_int64(response, "pid", -3);
            CHECK(responseFromXPCObject(response).pid == -1);
            xpc_dictionary_set_int64(response, "pid", 42);
            CHECK(responseFromXPCObject(response).pid == 42);
            NSMutableData *binary = [NSMutableData dataWithLength:8192];
            struct mach_header_64 header = {.magic=MH_MAGIC_64, .cputype=CPU_TYPE_ARM64, .filetype=MH_EXECUTE,
                .ncmds=2, .sizeofcmds=sizeof(struct segment_command_64)+sizeof(struct encryption_info_command_64)};
            struct segment_command_64 segment = {.cmd=LC_SEGMENT_64, .cmdsize=sizeof(segment),
                .vmaddr=0x100000000, .vmsize=8192, .filesize=8192};
            struct encryption_info_command_64 encryption = {.cmd=LC_ENCRYPTION_INFO_64,
                .cmdsize=sizeof(encryption), .cryptoff=4096, .cryptsize=4096, .cryptid=1};
            memcpy(binary.mutableBytes, &header, sizeof(header));
            memcpy((uint8_t *)binary.mutableBytes+sizeof(header), &segment, sizeof(segment));
            NSUInteger encOffset = sizeof(header)+sizeof(segment);
            memcpy((uint8_t *)binary.mutableBytes+encOffset, &encryption, sizeof(encryption));
            NSArray *relativePaths = @[@"PlugIns/Widget.appex/Widget", @"Extensions/Shortcuts.appex/Shortcuts"];
            for (NSString *relative in relativePaths) {
                NSString *file = [app stringByAppendingPathComponent:relative];
                CHECK([fm createDirectoryAtPath:file.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil]);
                CHECK([binary writeToFile:file atomically:YES]);
            }
            NSError *error = nil;
            CHECK(TDExtensionBundles(app, &error).count == 2);
            CHECK(TDEncryptedFilesInBundle(app, &error).count == 2);
            NSString *alias = [root stringByAppendingPathComponent:@"Alias.app"];
            CHECK([fm createSymbolicLinkAtPath:alias withDestinationPath:app error:nil]);
            CHECK([TDEncryptedFilesInBundle(alias, &error) isEqualToArray:[relativePaths sortedArrayUsingSelector:@selector(compare:)]]);
            CHECK([fm changeCurrentDirectoryPath:root]);
            CHECK([TDEncryptedFilesInBundle(@"Example.app", &error) isEqualToArray:[relativePaths sortedArrayUsingSelector:@selector(compare:)]]);
            CHECK(TDExtensionBundles(@"Example.app", &error).count == 2);
            CHECK([fm changeCurrentDirectoryPath:originalDirectory]);
            NSString *widget = [app stringByAppendingPathComponent:relativePaths[0]];
            NSString *candidateSource = [root stringByAppendingPathComponent:@"encrypted-source"];
            CHECK([binary writeToFile:candidateSource atomically:YES]);
            CHECK(!TDWriteDecryptionOutput(candidateSource, candidateSource, ^BOOL(NSString *stagedPath, NSError **attemptError) {
                abort();
            }, &error));
            NSString *sourceAlias = [root stringByAppendingPathComponent:@"source-alias"];
            CHECK([fm createSymbolicLinkAtPath:sourceAlias withDestinationPath:candidateSource error:nil]);
            CHECK(!TDWriteDecryptionOutput(sourceAlias, widget, ^BOOL(NSString *stagedPath, NSError **attemptError) {
                int fd = open(stagedPath.fileSystemRepresentation, O_WRONLY | O_TRUNC);
                if (fd >= 0) { write(fd, "partial", 7); close(fd); }
                return NO;
            }, &error));
            CHECK([[NSData dataWithContentsOfFile:candidateSource] isEqualToData:binary]);
            CHECK([[NSData dataWithContentsOfFile:widget] isEqualToData:binary]);
            CHECK(!TDWriteDecryptionOutput(candidateSource, widget, ^BOOL(NSString *stagedPath, NSError **attemptError) {
                [@"truncated, patched data" writeToFile:stagedPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
                return NO;
            }, &error));
            CHECK([[NSData dataWithContentsOfFile:widget] isEqualToData:binary]);
            CHECK(!TDWriteDecryptionOutput(candidateSource, widget, ^BOOL(NSString *stagedPath, NSError **attemptError) {
                [@"partial data" writeToFile:stagedPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
                @throw [NSException exceptionWithName:@"SimulatedFailure" reason:@"Failed after writing" userInfo:nil];
            }, &error));
            CHECK([[NSData dataWithContentsOfFile:widget] isEqualToData:binary]);
            CHECK(!TDWriteDecryptionOutput(candidateSource, widget, ^BOOL(NSString *stagedPath, NSError **attemptError) {
                NSMutableData *patched = [NSMutableData dataWithContentsOfFile:stagedPath];
                ((struct encryption_info_command_64 *)((uint8_t *)patched.mutableBytes+encOffset))->cryptid = 0;
                [patched writeToFile:stagedPath atomically:YES];
                return NO;
            }, &error));
            CHECK([[NSData dataWithContentsOfFile:widget] isEqualToData:binary]);
            CHECK(!TDWriteDecryptionOutput(candidateSource, widget, ^BOOL(NSString *stagedPath, NSError **attemptError) {
                return [@"invalid output" writeToFile:stagedPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
            }, &error));
            CHECK([[NSData dataWithContentsOfFile:widget] isEqualToData:binary]);
            NSMutableData *successful = binary.mutableCopy;
            ((struct encryption_info_command_64 *)((uint8_t *)successful.mutableBytes+encOffset))->cryptid = 0;
            memset((uint8_t *)successful.mutableBytes+4096, 0xAA, 4096);
            CHECK(TDWriteDecryptionOutput(candidateSource, [root stringByAppendingPathComponent:@"next-output"], ^BOOL(NSString *stagedPath, NSError **attemptError) {
                return [successful writeToFile:stagedPath atomically:YES];
            }, &error));
            CHECK([[NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"next-output"]] isEqualToData:successful]);
            for (NSString *path in [fm enumeratorAtPath:root]) CHECK(![path hasSuffix:@".staged"]);
            NSArray<TDMachOImage *> *images = TDInspectMachO(widget, &error);
            CHECK(images.count == 1 && images[0].encryption.cryptid == 1);
            CHECK(images[0].encryptedVMOffset == 4096 && images[0].fileSize == 8192);

            NSMutableData *malformed = binary.mutableCopy;
            ((struct segment_command_64 *)((uint8_t *)malformed.mutableBytes+sizeof(header)))->cmdsize = 0;
            CHECK([malformed writeToFile:widget atomically:YES]);
            CHECK(TDInspectMachO(widget, &error) == nil && error != nil);
            CHECK(TDEncryptedFilesInBundle(app, &error) == nil);
            malformed = binary.mutableCopy;
            ((struct encryption_info_command_64 *)((uint8_t *)malformed.mutableBytes+encOffset))->cryptsize = UINT32_MAX;
            CHECK([malformed writeToFile:widget atomically:YES]);
            CHECK(TDInspectMachO(widget, &error) == nil);

            NSMutableData *fat = [NSMutableData dataWithLength:4096+binary.length];
            struct fat_header fh = {.magic=FAT_CIGAM, .nfat_arch=OSSwapHostToBigInt32(1)};
            struct fat_arch arch = {.cputype=OSSwapHostToBigInt32(CPU_TYPE_ARM64),
                .offset=OSSwapHostToBigInt32(4096), .size=OSSwapHostToBigInt32((uint32_t)binary.length), .align=OSSwapHostToBigInt32(12)};
            memcpy(fat.mutableBytes, &fh, sizeof(fh));
            memcpy((uint8_t *)fat.mutableBytes+sizeof(fh), &arch, sizeof(arch));
            memcpy((uint8_t *)fat.mutableBytes+4096, binary.bytes, binary.length);
            CHECK([fat writeToFile:widget atomically:YES]);
            images = TDInspectMachO(widget, &error);
            CHECK(images.count == 1 && images[0].fileOffset == 4096 && images[0].encryption.cryptid == 1);
            ((struct fat_arch *)((uint8_t *)fat.mutableBytes+sizeof(fh)))->offset = OSSwapHostToBigInt32(UINT32_MAX);
            CHECK([fat writeToFile:widget atomically:YES]);
            CHECK(TDInspectMachO(widget, &error) == nil);

            ((struct encryption_info_command_64 *)((uint8_t *)binary.mutableBytes+encOffset))->cryptid = 0;
            CHECK([binary writeToFile:widget atomically:YES]);
            CHECK(TDEncryptedFilesInBundle(app, &error).count == 1);
            CHECK([binary writeToFile:[app stringByAppendingPathComponent:relativePaths[1]] atomically:YES]);
            CHECK(TDEncryptedFilesInBundle(app, &error).count == 0);
            NSString *resource = [app stringByAppendingPathComponent:@"resource.bin"];
            CHECK([[@"ordinary resource" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:resource atomically:YES]);
            CHECK(TDInspectMachO(resource, &error).count == 0);

            NSString *outside = [root stringByAppendingPathComponent:@"Outside.appex"];
            CHECK([fm createDirectoryAtPath:outside withIntermediateDirectories:YES attributes:nil error:nil]);
            CHECK([fm createSymbolicLinkAtPath:[app stringByAppendingPathComponent:@"PlugIns/Outside.appex"] withDestinationPath:outside error:nil]);
            error = nil;
            CHECK(TDExtensionBundles(app, &error).count == 2 && error != nil);
            puts("Mach-O inspection and extension discovery tests passed.");
        } @finally {
            [fm changeCurrentDirectoryPath:originalDirectory];
            [fm removeItemAtPath:root error:nil];
        }
    }
    return 0;
}
