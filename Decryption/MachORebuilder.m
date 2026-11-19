#import "MachORebuilder.h"
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>

static BOOL TDRebuildError(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:@"com.fiore.TDError" code:103
        userInfo:@{NSLocalizedDescriptionKey:message}];
    return NO;
}

TDMachOImage *TDImageMatchingLoadedHeader(NSArray<TDMachOImage *> *images, NSData *header, NSError **error) {
    TDMachOImage *match = nil;
    for (TDMachOImage *image in images) {
        if (!header.length || header.length != image.headerData.length) continue;
        NSMutableData *normalized = header.mutableCopy;
        // The kernel may have cleared cryptid in memory. All other header/load-command
        // bytes must match the on-disk slice, so a different architecture/build is rejected.
        uint64_t offset = image.encryptionCommandOffset;
        if (offset) {
            if (offset > normalized.length || sizeof(struct encryption_info_command) > normalized.length - offset) continue;
            uint32_t cryptid = image.encryption.cryptid;
            memcpy((uint8_t *)normalized.mutableBytes + offset + offsetof(struct encryption_info_command, cryptid),
                &cryptid, sizeof(cryptid));
        }
        if (![normalized isEqualToData:image.headerData]) continue;
        if (match) {
            TDRebuildError(error, @"More than one Mach-O slice matches the loaded image.");
            return nil;
        }
        match = image;
    }
    if (!match) TDRebuildError(error, @"No on-disk Mach-O slice matches the target's loaded header.");
    return match;
}

static BOOL TDReadAt(int fd, void *buffer, size_t size, uint64_t offset) {
    size_t done = 0;
    while (done < size) {
        ssize_t count = pread(fd, (uint8_t *)buffer + done, size - done, (off_t)(offset + done));
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return NO;
        done += (size_t)count;
    }
    return YES;
}

static BOOL TDWriteAt(int fd, const void *buffer, size_t size, uint64_t offset) {
    size_t done = 0;
    while (done < size) {
        ssize_t count = pwrite(fd, (const uint8_t *)buffer + done, size - done, (off_t)(offset + done));
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return NO;
        done += (size_t)count;
    }
    return YES;
}

BOOL TDRebuildMachOSlice(NSString *sourcePath, TDMachOImage *image, NSString *stagedPath,
                        BOOL (^readMemory)(uint64_t offset, void *buffer, size_t size), NSError **error) {
    int sourceFD = open(sourcePath.fileSystemRepresentation, O_RDONLY | O_CLOEXEC);
    int outputFD = -1;
    struct stat sourceStat, outputStat;
    @try {
        if (sourceFD < 0 || fstat(sourceFD, &sourceStat) != 0 || !S_ISREG(sourceStat.st_mode) ||
            sourceStat.st_size < 0 || !image.fileSize || !image.headerData.length ||
            image.fileOffset > (uint64_t)sourceStat.st_size || image.fileSize > (uint64_t)sourceStat.st_size - image.fileOffset ||
            image.headerData.length > image.fileSize) {
            return TDRebuildError(error, @"The selected Mach-O slice is outside the source file.");
        }
        BOOL encrypted = image.encryption.cryptid != 0;
        uint64_t cryptoff = image.encryption.cryptoff, cryptsize = image.encryption.cryptsize;
        if (encrypted && (!readMemory || !cryptsize || cryptoff < image.headerData.length ||
            cryptoff > image.fileSize || cryptsize > image.fileSize - cryptoff ||
            !image.encryptionCommandOffset || image.encryptionCommandOffset > image.headerData.length ||
            sizeof(struct encryption_info_command) > image.headerData.length - image.encryptionCommandOffset ||
            image.encryptedVMOffset == UINT64_MAX || image.encryptedVMOffset > UINT64_MAX - cryptsize)) {
            return TDRebuildError(error, @"The selected Mach-O slice has an invalid encrypted range.");
        }
        NSMutableData *header = [NSMutableData dataWithLength:image.headerData.length];
        if (!TDReadAt(sourceFD, header.mutableBytes, header.length, image.fileOffset) ||
            ![header isEqualToData:image.headerData]) {
            return TDRebuildError(error, @"The source Mach-O header changed after inspection.");
        }
        // Check inode identity before truncating: the installed file must never be an output.
        outputFD = open(stagedPath.fileSystemRepresentation, O_WRONLY | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0600);
        if (outputFD < 0 || fstat(outputFD, &outputStat) != 0 || !S_ISREG(outputStat.st_mode) ||
            (sourceStat.st_dev == outputStat.st_dev && sourceStat.st_ino == outputStat.st_ino)) {
            return TDRebuildError(error, @"Cannot open a separate staging file for the Mach-O slice.");
        }
        if (ftruncate(outputFD, (off_t)image.fileSize) != 0) {
            return TDRebuildError(error, @"Cannot size the staged Mach-O slice.");
        }
        uint8_t plain[16384], original[16384];
        for (uint64_t done = 0; done < image.fileSize;) {
            size_t length = (size_t)MIN(sizeof(original), image.fileSize - done);
            if (!TDReadAt(sourceFD, original, length, image.fileOffset + done) ||
                !TDWriteAt(outputFD, original, length, done)) {
                return TDRebuildError(error, @"Cannot copy the selected Mach-O slice.");
            }
            done += length;
        }
        if (encrypted) {
            BOOL changed = NO, nonzero = NO;
            for (uint64_t done = 0; done < cryptsize;) {
                size_t length = (size_t)MIN(sizeof(plain), cryptsize - done);
                if (!readMemory(image.encryptedVMOffset + done, plain, length) ||
                    !TDReadAt(sourceFD, original, length, image.fileOffset + cryptoff + done)) {
                    return TDRebuildError(error, @"Cannot read the selected slice's decrypted pages.");
                }
                changed |= memcmp(plain, original, length) != 0;
                for (size_t i = 0; i < length; i++) nonzero |= plain[i] != 0;
                if (!TDWriteAt(outputFD, plain, length, cryptoff + done)) {
                    return TDRebuildError(error, @"Cannot write the selected slice's decrypted pages.");
                }
                done += length;
            }
            if (!changed || !nonzero) return TDRebuildError(error, @"The system returned ciphertext or zero pages instead of decrypted data.");
            uint32_t zero = 0;
            if (!TDWriteAt(outputFD, &zero, sizeof(zero),
                image.encryptionCommandOffset + offsetof(struct encryption_info_command, cryptid))) {
                return TDRebuildError(error, @"Cannot clear the decrypted slice's encryption flag.");
            }
        }
        if (fchmod(outputFD, sourceStat.st_mode & 0777) != 0) {
            return TDRebuildError(error, @"Cannot restore the output executable's permissions.");
        }
        return YES;
    } @finally {
        if (outputFD >= 0) close(outputFD);
        if (sourceFD >= 0) close(sourceFD);
    }
}
