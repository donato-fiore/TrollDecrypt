#import "MachOInspection.h"
#import <mach-o/fat.h>
#import <libkern/OSByteOrder.h>
#import <sys/mman.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>

@implementation TDMachOImage
@end

static BOOL TDInspectSlice(const uint8_t *bytes, uint64_t size, uint64_t offset,
                           NSMutableArray<TDMachOImage *> *images) {
    if (size < sizeof(struct mach_header)) return NO;
    struct mach_header header;
    memcpy(&header, bytes, sizeof(header));
    BOOL is64 = header.magic == MH_MAGIC_64;
    if (!is64 && header.magic != MH_MAGIC) return NO;
    size_t headerSize = is64 ? sizeof(struct mach_header_64) : sizeof(struct mach_header);
    if (size < headerSize || header.sizeofcmds > size - headerSize || header.sizeofcmds > 16 * 1024 * 1024 ||
        header.ncmds > header.sizeofcmds / sizeof(struct load_command)) return NO;

    TDMachOImage *image = [TDMachOImage new];
    image.fileOffset = offset;
    image.fileSize = size;
    image.cpuType = header.cputype;
    image.fileType = header.filetype;
    image.encryptedVMOffset = UINT64_MAX;
    uint64_t textVM = UINT64_MAX;
    NSMutableArray<NSValue *> *segments = [NSMutableArray array];
    uint64_t cursor = headerSize;
    uint64_t end = headerSize + header.sizeofcmds;
    for (uint32_t i = 0; i < header.ncmds; i++) {
        if (end - cursor < sizeof(struct load_command)) return NO;
        struct load_command command;
        memcpy(&command, bytes + cursor, sizeof(command));
        if (command.cmdsize < sizeof(command) || command.cmdsize > end - cursor) return NO;
        if (command.cmd == LC_ENCRYPTION_INFO || command.cmd == LC_ENCRYPTION_INFO_64) {
            size_t minimum = command.cmd == LC_ENCRYPTION_INFO_64
                ? sizeof(struct encryption_info_command_64) : sizeof(struct encryption_info_command);
            if (command.cmdsize < minimum || image.encryptionCommandOffset != 0) return NO;
            struct encryption_info_command encryption;
            memcpy(&encryption, bytes + cursor, sizeof(encryption));
            if ((uint64_t)encryption.cryptoff + encryption.cryptsize > size) return NO;
            if (encryption.cryptid && (!encryption.cryptsize || encryption.cryptoff < end)) return NO;
            image.encryption = encryption;
            image.encryptionCommandOffset = cursor;
        } else if (command.cmd == LC_SEGMENT_64) {
            if (command.cmdsize < sizeof(struct segment_command_64)) return NO;
            struct segment_command_64 segment;
            memcpy(&segment, bytes + cursor, sizeof(segment));
            if (segment.fileoff > size || segment.filesize > size - segment.fileoff ||
                segment.filesize > segment.vmsize || segment.vmaddr > UINT64_MAX - segment.vmsize) return NO;
            if (segment.fileoff == 0 && segment.filesize >= end) textVM = segment.vmaddr;
            [segments addObject:[NSValue valueWithBytes:&segment objCType:@encode(struct segment_command_64)]];
        }
        cursor += command.cmdsize;
    }
    if (cursor != end) return NO;
    image.headerData = [NSData dataWithBytes:bytes length:(NSUInteger)end];
    for (NSValue *value in segments) {
        struct segment_command_64 segment;
        [value getValue:&segment];
        uint64_t cryptEnd = (uint64_t)image.encryption.cryptoff + image.encryption.cryptsize;
        if (textVM != UINT64_MAX && segment.vmaddr >= textVM &&
            image.encryption.cryptoff >= segment.fileoff && cryptEnd <= segment.fileoff + segment.filesize) {
            image.encryptedVMOffset = segment.vmaddr - textVM + image.encryption.cryptoff - segment.fileoff;
            break;
        }
    }
    [images addObject:image];
    return YES;
}

NSArray<TDMachOImage *> *TDInspectMachO(NSString *path, NSError **error) {
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_CLOEXEC);
    struct stat st;
    if (fd < 0 || fstat(fd, &st) != 0) {
        int code = errno;
        if (fd >= 0) close(fd);
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:@{NSFilePathErrorKey:path}];
        return nil;
    }
    if (!S_ISREG(st.st_mode) || st.st_size < 4) { close(fd); return @[]; }
    uint64_t size = (uint64_t)st.st_size;
    const uint8_t *bytes = mmap(NULL, (size_t)size, PROT_READ, MAP_PRIVATE, fd, 0);
    int mapError = errno;
    close(fd);
    if (bytes == MAP_FAILED) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:mapError userInfo:@{NSFilePathErrorKey:path}];
        return nil;
    }
    uint32_t magic;
    memcpy(&magic, bytes, sizeof(magic));
    NSMutableArray<TDMachOImage *> *images = [NSMutableArray array];
    BOOL valid = YES;
    if (magic == MH_MAGIC || magic == MH_MAGIC_64) {
        valid = TDInspectSlice(bytes, size, 0, images);
    } else if (magic == FAT_CIGAM || magic == FAT_CIGAM_64 || magic == FAT_MAGIC || magic == FAT_MAGIC_64) {
        BOOL swap = magic == FAT_CIGAM || magic == FAT_CIGAM_64;
        BOOL fat64 = magic == FAT_CIGAM_64 || magic == FAT_MAGIC_64;
        if (size < sizeof(struct fat_header)) { valid = NO; }
        else {
            struct fat_header header;
            memcpy(&header, bytes, sizeof(header));
            uint32_t count = swap ? OSSwapInt32(header.nfat_arch) : header.nfat_arch;
            size_t stride = fat64 ? sizeof(struct fat_arch_64) : sizeof(struct fat_arch);
            if (!count || count > (size - sizeof(header)) / stride) valid = NO;
            for (uint32_t i = 0; valid && i < count; i++) {
                uint64_t offset, length;
                const uint8_t *entry = bytes + sizeof(header) + (uint64_t)i * stride;
                if (fat64) {
                    struct fat_arch_64 arch; memcpy(&arch, entry, sizeof(arch));
                    offset = swap ? OSSwapInt64(arch.offset) : arch.offset;
                    length = swap ? OSSwapInt64(arch.size) : arch.size;
                } else {
                    struct fat_arch arch; memcpy(&arch, entry, sizeof(arch));
                    offset = swap ? OSSwapInt32(arch.offset) : arch.offset;
                    length = swap ? OSSwapInt32(arch.size) : arch.size;
                }
                valid = offset >= sizeof(header) + (uint64_t)count * stride &&
                    offset <= size && length <= size - offset &&
                    TDInspectSlice(bytes + offset, length, offset, images);
            }
        }
    } else if (magic == MH_CIGAM || magic == MH_CIGAM_64) {
        valid = NO;
    }
    munmap((void *)bytes, (size_t)size);
    if (!valid) {
        if (error) *error = [NSError errorWithDomain:@"com.fiore.TDError" code:100
            userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Invalid or unsupported Mach-O: %@", path]}];
        return nil;
    }
    return images;
}

NSArray<NSString *> *TDEncryptedFilesInBundle(NSString *bundlePath, NSError **error) {
    bundlePath = [NSURL fileURLWithPath:bundlePath isDirectory:YES].path.stringByResolvingSymlinksInPath;
    NSFileManager *fm = NSFileManager.defaultManager;
    __block NSError *scanError = nil;
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtURL:[NSURL fileURLWithPath:bundlePath]
        includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLIsSymbolicLinkKey] options:0
        errorHandler:^BOOL(NSURL *url, NSError *failure) { scanError = failure; return NO; }];
    NSMutableArray<NSString *> *encrypted = [NSMutableArray array];
    for (NSURL *url in enumerator) {
        NSNumber *regular, *symlink;
        if (![url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:&scanError] ||
            ![url getResourceValue:&symlink forKey:NSURLIsSymbolicLinkKey error:&scanError]) break;
        if (!regular.boolValue || symlink.boolValue) continue;
        NSString *filePath = url.path.stringByResolvingSymlinksInPath;
        NSString *prefix = [bundlePath stringByAppendingString:@"/"];
        if (![filePath hasPrefix:prefix]) {
            scanError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{NSFilePathErrorKey:filePath}];
            break;
        }
        NSArray<TDMachOImage *> *images = TDInspectMachO(filePath, &scanError);
        if (!images) break;
        for (TDMachOImage *image in images) {
            if (image.encryption.cryptid != 0) {
                [encrypted addObject:[filePath substringFromIndex:prefix.length]];
                break;
            }
        }
    }
    if (scanError || !enumerator) {
        if (error) *error = scanError ?: [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError userInfo:@{NSFilePathErrorKey:bundlePath}];
        return nil;
    }
    return [encrypted sortedArrayUsingSelector:@selector(compare:)];
}

NSArray<NSString *> *TDExtensionBundles(NSString *appPath, NSError **error) {
    appPath = [NSURL fileURLWithPath:appPath isDirectory:YES].path;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray<NSString *> *extensions = [NSMutableArray array];
    for (NSString *directory in @[@"PlugIns", @"Extensions"]) {
        NSString *root = [appPath stringByAppendingPathComponent:directory];
        if (![fm fileExistsAtPath:root]) continue;
        NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:root error:error];
        if (!entries) continue;
        for (NSString *entry in entries) {
            if (![entry.pathExtension isEqualToString:@"appex"]) continue;
            NSString *path = [root stringByAppendingPathComponent:entry];
            NSString *resolved = path.stringByResolvingSymlinksInPath;
            if (![resolved hasPrefix:[appPath.stringByResolvingSymlinksInPath stringByAppendingString:@"/"]]) {
                if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{NSFilePathErrorKey:path}];
                continue;
            }
            [extensions addObject:path];
        }
    }
    return [extensions sortedArrayUsingSelector:@selector(compare:)];
}
