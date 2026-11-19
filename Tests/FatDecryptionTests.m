#import "MachORebuilder.h"
#import "DecryptionOutput.h"
#import "MemoryUtilities.h"
#import <mach-o/fat.h>
#import <libkern/OSByteOrder.h>
#import <sys/stat.h>
#import <unistd.h>

#define CHECK(condition) do { if (!(condition)) { fprintf(stderr, "Failed at line %d: %s\n", __LINE__, #condition); return 1; } } while (0)

static NSData *arm64Slice(cpu_subtype_t subtype, uint8_t identity) {
    NSMutableData *data = [NSMutableData dataWithLength:0xe000];
    memset(data.mutableBytes, 0x73, data.length);
    struct segment_command_64 text = {.cmd=LC_SEGMENT_64, .cmdsize=sizeof(text),
        .vmaddr=0x100000000, .vmsize=0x4000, .fileoff=0, .filesize=0x4000};
    memcpy(text.segname, "__TEXT", 6);
    // Deliberately different VM/file offsets: cryptoff alone is not a VM offset.
    struct segment_command_64 content = {.cmd=LC_SEGMENT_64, .cmdsize=sizeof(content),
        .vmaddr=0x100009000, .vmsize=0x9000, .fileoff=0x4000, .filesize=0x9000};
    struct encryption_info_command_64 encryption = {.cmd=LC_ENCRYPTION_INFO_64, .cmdsize=sizeof(encryption),
        .cryptoff=0x4000, .cryptsize=0x9000, .cryptid=1};
    struct uuid_command uuid = {.cmd=LC_UUID, .cmdsize=sizeof(uuid)};
    memset(uuid.uuid, identity, sizeof(uuid.uuid));
    struct mach_header_64 header = {.magic=MH_MAGIC_64, .cputype=CPU_TYPE_ARM64, .cpusubtype=subtype,
        .filetype=MH_DYLIB, .ncmds=4, .sizeofcmds=sizeof(text)+sizeof(content)+sizeof(encryption)+sizeof(uuid)};
    uint8_t *cursor = data.mutableBytes;
    memcpy(cursor, &header, sizeof(header)); cursor += sizeof(header);
    memcpy(cursor, &text, sizeof(text)); cursor += sizeof(text);
    memcpy(cursor, &content, sizeof(content)); cursor += sizeof(content);
    memcpy(cursor, &encryption, sizeof(encryption)); cursor += sizeof(encryption);
    memcpy(cursor, &uuid, sizeof(uuid));
    return data;
}

static NSData *arm32Slice(void) {
    NSMutableData *data = [NSMutableData dataWithLength:8192];
    struct mach_header header = {.magic=MH_MAGIC, .cputype=CPU_TYPE_ARM, .cpusubtype=CPU_SUBTYPE_ARM_V7,
        .filetype=MH_DYLIB, .ncmds=1, .sizeofcmds=sizeof(struct encryption_info_command)};
    struct encryption_info_command encryption = {.cmd=LC_ENCRYPTION_INFO, .cmdsize=sizeof(encryption),
        .cryptoff=4096, .cryptsize=4096, .cryptid=1};
    memcpy(data.mutableBytes, &header, sizeof(header));
    memcpy((uint8_t *)data.mutableBytes + sizeof(header), &encryption, sizeof(encryption));
    return data;
}

static NSData *fatContainer(NSArray<NSData *> *slices, BOOL wide, BOOL swap) {
    NSMutableData *data = [NSMutableData dataWithLength:16384];
    struct fat_header header = {.magic=wide ? (swap ? FAT_CIGAM_64 : FAT_MAGIC_64) : (swap ? FAT_CIGAM : FAT_MAGIC),
        .nfat_arch=swap ? OSSwapInt32((uint32_t)slices.count) : (uint32_t)slices.count};
    memcpy(data.mutableBytes, &header, sizeof(header));
    for (NSUInteger i = 0; i < slices.count; i++) {
        NSData *slice = slices[i];
        uint64_t offset = (data.length + 16383) & ~16383ULL;
        [data setLength:(NSUInteger)(offset + slice.length)];
        memcpy((uint8_t *)data.mutableBytes + offset, slice.bytes, slice.length);
        struct mach_header mh; memcpy(&mh, slice.bytes, sizeof(mh));
        if (wide) {
            struct fat_arch_64 arch = {.cputype=swap ? OSSwapInt32(mh.cputype) : mh.cputype,
                .cpusubtype=swap ? OSSwapInt32(mh.cpusubtype) : mh.cpusubtype,
                .offset=swap ? OSSwapInt64(offset) : offset, .size=swap ? OSSwapInt64(slice.length) : slice.length,
                .align=swap ? OSSwapInt32(14) : 14};
            memcpy((uint8_t *)data.mutableBytes + sizeof(header) + i * sizeof(arch), &arch, sizeof(arch));
        } else {
            struct fat_arch arch = {.cputype=swap ? OSSwapInt32(mh.cputype) : mh.cputype,
                .cpusubtype=swap ? OSSwapInt32(mh.cpusubtype) : mh.cpusubtype,
                .offset=swap ? OSSwapInt32((uint32_t)offset) : (uint32_t)offset,
                .size=swap ? OSSwapInt32((uint32_t)slice.length) : (uint32_t)slice.length,
                .align=swap ? OSSwapInt32(14) : 14};
            memcpy((uint8_t *)data.mutableBytes + sizeof(header) + i * sizeof(arch), &arch, sizeof(arch));
        }
    }
    return data;
}

int main(void) {
    @autoreleasepool {
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        CHECK([fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil]);
        @try {
            NSString *source = [root stringByAppendingPathComponent:@"FAT.framework"];
            NSString *output = [root stringByAppendingPathComponent:@"Output"];
            NSData *native = arm64Slice(CPU_SUBTYPE_ARM64_ALL, 0x12);
            NSData *other = arm64Slice(CPU_SUBTYPE_ARM64E, 0x34);
            NSMutableData *plain = [NSMutableData dataWithLength:0x9000];
            for (NSUInteger i = 0; i < plain.length; i++) ((uint8_t *)plain.mutableBytes)[i] = (uint8_t)(i * 17 + 3);
            // Thin, one-slice FAT, and multi-slice FAT32/FAT64 in both byte orders.
            NSArray<NSData *> *inputs = @[native, fatContainer(@[native], NO, YES),
                fatContainer(@[arm32Slice(), other, native], NO, YES),
                fatContainer(@[native, arm32Slice(), other], YES, YES),
                fatContainer(@[other, native, arm32Slice()], NO, NO),
                fatContainer(@[arm32Slice(), native, other], YES, NO)];
            for (NSData *input in inputs) {
                CHECK([input writeToFile:source atomically:YES]);
                CHECK(chmod(source.fileSystemRepresentation, 0755) == 0);
                NSError *error = nil;
                NSArray<TDMachOImage *> *images = TDInspectMachO(source, &error);
                CHECK(images.count > 0);
                struct mach_header_64 mh; memcpy(&mh, native.bytes, sizeof(mh));
                NSData *loaded = [native subdataWithRange:NSMakeRange(0, sizeof(mh)+mh.sizeofcmds)];
                TDMachOImage *image = TDImageMatchingLoadedHeader(images, loaded, &error);
                CHECK(image && image.encryptedVMOffset == 0x9000);
                CHECK(image.encryption.cryptoff == 0x4000 && image.fileSize == native.length);
                __block NSUInteger reads = 0;
                CHECK(TDWriteDecryptionOutput(source, output, ^BOOL(NSString *staged, NSError **failure) {
                    return TDRebuildMachOSlice(source, image, staged, ^BOOL(uint64_t offset, void *buffer, size_t size) {
                        reads++;
                        if (offset < 0x9000 || offset - 0x9000 > plain.length || size > plain.length - (offset - 0x9000)) return NO;
                        memcpy(buffer, (const uint8_t *)plain.bytes + offset - 0x9000, size);
                        return YES;
                    }, failure);
                }, &error));
                CHECK(reads == 3); // includes a final partial buffer
                NSMutableData *expected = native.mutableCopy;
                memcpy((uint8_t *)expected.mutableBytes + 0x4000, plain.bytes, plain.length);
                uint32_t zero = 0;
                memcpy((uint8_t *)expected.mutableBytes + image.encryptionCommandOffset + offsetof(struct encryption_info_command, cryptid), &zero, sizeof(zero));
                CHECK([[NSData dataWithContentsOfFile:output] isEqualToData:expected]);
                CHECK([[NSData dataWithContentsOfFile:source] isEqualToData:input]);
                NSArray<TDMachOImage *> *written = TDInspectMachO(output, &error);
                CHECK(written.count == 1 && written[0].fileOffset == 0 && written[0].encryption.cryptid == 0);
                struct stat st; CHECK(stat(output.fileSystemRepresentation, &st) == 0 && (st.st_mode & 0777) == 0755);

                // Exercise the production Mach VM reader and header lookup against this task.
                NSMutableData *mapped = [NSMutableData dataWithLength:0x12000];
                memcpy(mapped.mutableBytes, loaded.bytes, loaded.length);
                memcpy((uint8_t *)mapped.mutableBytes + 0x9000, plain.bytes, plain.length);
                uint64_t address = (uint64_t)mapped.bytes;
                CHECK([readLoadedImageHeader(mach_task_self(), address) isEqualToData:loaded]);
                CHECK(TDWriteDecryptionOutput(source, output, ^BOOL(NSString *staged, NSError **failure) {
                    return rebuildDecryptedImageAtPath(source, mach_task_self(), address, image, staged, failure);
                }, &error));
                CHECK([[NSData dataWithContentsOfFile:output] isEqualToData:expected]);

                NSMutableData *clearedHeader = loaded.mutableCopy;
                memcpy((uint8_t *)clearedHeader.mutableBytes + image.encryptionCommandOffset + offsetof(struct encryption_info_command, cryptid), &zero, sizeof(zero));
                CHECK(TDImageMatchingLoadedHeader(images, clearedHeader, &error) == image);
                NSMutableData *wrongHeader = loaded.mutableCopy;
                ((struct mach_header_64 *)wrongHeader.mutableBytes)->cpusubtype = 99;
                CHECK(TDImageMatchingLoadedHeader(images, wrongHeader, &error) == nil);
                wrongHeader = loaded.mutableCopy;
                ((uint8_t *)wrongHeader.mutableBytes)[wrongHeader.length - 1] ^= 1; // different UUID
                CHECK(TDImageMatchingLoadedHeader(images, wrongHeader, &error) == nil);
                CHECK(TDImageMatchingLoadedHeader(@[image, image], loaded, &error) == nil);
                CHECK(TDImageMatchingLoadedHeader(images, [loaded subdataWithRange:NSMakeRange(0, 12)], &error) == nil);

                // Ciphertext, zero pages, failed reads and exceptions must retain the old output.
                for (NSUInteger mode = 0; mode < 4; mode++) {
                    __block NSUInteger calls = 0;
                    CHECK(!TDWriteDecryptionOutput(source, output, ^BOOL(NSString *staged, NSError **failure) {
                        return TDRebuildMachOSlice(source, image, staged, ^BOOL(uint64_t offset, void *buffer, size_t size) {
                            calls++;
                            if (mode == 2 && calls == 2) return NO;
                            if (mode == 3) @throw [NSException exceptionWithName:@"ReadFailure" reason:@"Read interrupted" userInfo:nil];
                            memset(buffer, mode == 0 ? 0x73 : (mode == 1 ? 0 : 0xAB), size);
                            return YES;
                        }, failure);
                    }, &error));
                    CHECK([[NSData dataWithContentsOfFile:output] isEqualToData:expected]);
                    CHECK([[NSData dataWithContentsOfFile:source] isEqualToData:input]);
                }
                CHECK(!TDRebuildMachOSlice(source, image, source, ^BOOL(uint64_t offset, void *buffer, size_t size) {
                    abort();
                }, &error));
                CHECK([[NSData dataWithContentsOfFile:source] isEqualToData:input]);
                for (NSString *entry in [fm contentsOfDirectoryAtPath:root error:nil]) CHECK(![entry hasSuffix:@".staged"]);
            }
            // If the loaded slice is already decrypted, discard encrypted unused architectures.
            NSMutableData *clear = native.mutableCopy;
            CHECK([native writeToFile:source atomically:YES]);
            TDMachOImage *image = TDInspectMachO(source, nil).firstObject;
            uint32_t zero = 0;
            memcpy((uint8_t *)clear.mutableBytes + image.encryptionCommandOffset + offsetof(struct encryption_info_command, cryptid), &zero, sizeof(zero));
            CHECK([fatContainer(@[arm32Slice(), clear], NO, YES) writeToFile:source atomically:YES]);
            NSArray<TDMachOImage *> *images = TDInspectMachO(source, nil);
            image = TDImageMatchingLoadedHeader(images, [clear subdataWithRange:NSMakeRange(0, image.headerData.length)], nil);
            CHECK(image != nil);
            CHECK(TDWriteDecryptionOutput(source, output, ^BOOL(NSString *staged, NSError **failure) {
                return TDRebuildMachOSlice(source, image, staged, nil, failure);
            }, nil));
            CHECK([[NSData dataWithContentsOfFile:output] isEqualToData:clear]);
            puts("FAT slice selection, VM offsets, reconstruction and failure retention tests passed.");
        } @finally {
            [fm removeItemAtPath:root error:nil];
        }
    }
    return 0;
}
