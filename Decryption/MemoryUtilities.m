#import "MemoryUtilities.h"

#define MAX_DYLD_INFO_RETRIES 300
#define DYLD_INFO_RETRY_DELAY_US 10000

#define MALLOC_CHUNK_SIZE (1 << 20) // 1 MB

kern_return_t mach_vm_read_overwrite(vm_map_read_t target_task, mach_vm_address_t address, mach_vm_size_t size, mach_vm_address_t data, mach_vm_size_t *outsize);
kern_return_t mach_vm_region(vm_map_read_t target_task, mach_vm_address_t *address, mach_vm_size_t *size, vm_region_flavor_t flavor, vm_region_info_t info, mach_msg_type_number_t *infoCnt, mach_port_t *object_name);

static void removePrefix(char *str, const char *prefix) {
    size_t len_str = strlen(str);
    size_t len_prefix = strlen(prefix);

    if (len_str >= len_prefix && strncmp(str, prefix, len_prefix) == 0) {
        memmove(str, str + len_prefix, len_str - len_prefix + 1);
    }
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

    // Optional: validate region readability (your mach_vm_region check)
    kern_return_t kr;
    mach_vm_address_t regionAddress = address;
    mach_vm_size_t regionSize = 0;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t objectName = MACH_PORT_NULL;

    kr = mach_vm_region((task_t)task, &regionAddress, &regionSize,
                        VM_REGION_BASIC_INFO_64,
                        (vm_region_info_t)&info, &infoCount, &objectName);

    if (kr != KERN_SUCCESS || !(info.protection & VM_PROT_READ)) {
        NSLog(@"mach_vm_region failed or region not readable (kr=%d)", kr);
        return NO;
    }

    if (address + size > regionAddress + regionSize) {
        NSLog(@"read request exceeds region bounds");
        return NO;
    }

    mach_vm_size_t outSize = 0;
    kr = mach_vm_read_overwrite((task_t)task, address, size,
                                (mach_vm_address_t)buffer, &outSize);

    if (kr != KERN_SUCCESS || outSize != size) {
        NSLog(@"mach_vm_read_overwrite failed (kr=%d out=%llu want=%zu)",
              kr, outSize, size);
        return NO;
    }

    return YES;
}

NSString *NSStringFromMainImageInfo(MainImageInfo_t info) {
    return [NSString stringWithFormat:@"MainImageInfo: loadAddress=0x%llx, path=%@, ok=%d",
            info.loadAddress, info.path, info.ok];
}

MainImageInfo_t imageInfoForPIDWithRetry(const char *sourcePath, vm_map_t task, pid_t pid) {
    for (int i = 0; i < MAX_DYLD_INFO_RETRIES; i++) {
        task_dyld_info_data_t taskInfo;
        mach_msg_type_number_t count = TASK_DYLD_INFO_COUNT;
        kern_return_t kr = task_info((task_t)task, TASK_DYLD_INFO, (task_info_t)&taskInfo, &count);
        if (kr != KERN_SUCCESS || taskInfo.all_image_info_addr == 0) {
            usleep(DYLD_INFO_RETRY_DELAY_US);
            continue;
        }

        struct dyld_all_image_infos infos = {0};
        if (!readProcessMemory(task, taskInfo.all_image_info_addr, &infos, sizeof(infos))) {
            usleep(DYLD_INFO_RETRY_DELAY_US);
            continue;
        }

        // dyld not ready yet
        if (infos.infoArrayCount == 0 || infos.infoArray == NULL || infos.dyldImageLoadAddress == NULL) {
            usleep(DYLD_INFO_RETRY_DELAY_US);
            continue;
        }

        mach_vm_size_t imageInfoSize = sizeof(struct dyld_image_info) * infos.infoArrayCount;
        void *imageInfoData = malloc(imageInfoSize);
        if (!readProcessMemory(task, (mach_vm_address_t)infos.infoArray, imageInfoData, imageInfoSize)) {
            NSLog(@"failed to read dyld_image_info array for pid %d", pid);
            free(imageInfoData);
            usleep(DYLD_INFO_RETRY_DELAY_US);
            continue;
        }

        struct dyld_image_info *imageInfos = (struct dyld_image_info *)imageInfoData;
        NSLog(@"dyld has %u images for pid %d", infos.infoArrayCount, pid);
        NSLog(@"dyld main executable load address: 0x%llx", (uint64_t)infos.dyldImageLoadAddress);

        NSLog(@"expecting main executable path: %s", sourcePath);
        for (uint32_t j = 0; j < infos.infoArrayCount; j++) {
            char pathBuffer[PATH_MAX] = {0};
            if (!readProcessMemory(task, (uint64_t)imageInfos[j].imageFilePath, pathBuffer, sizeof(pathBuffer) - 1)) {
                NSLog(@"failed to read image file path for pid %d", pid);
                continue;
            }

            // sometimes pathbuffer is /private prefixed
            // sometimes sourcePath is /private prefixed
            bool match = strcmp(pathBuffer, sourcePath) == 0;
            if (!match) removePrefix(pathBuffer, "/private");

            if (strcmp(pathBuffer, sourcePath) == 0) {
                NSString *pathString = [NSString stringWithUTF8String:pathBuffer];
                NSLog(@"found main executable image for pid %d: %@", pid, pathString);
                MainImageInfo_t result = {
                    .loadAddress = (mach_vm_address_t)imageInfos[j].imageLoadAddress,
                    .path = pathString,
                    .ok = YES
                };

                free(imageInfoData);
                return result;
            }
        }
    }

    NSLog(@"dyld images not ready for pid %d (timed out)", pid);
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