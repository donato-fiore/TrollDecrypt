#import "MemoryUtilities.h"
#import "MachORebuilder.h"

#define MAX_DYLD_INFO_RETRIES 300
#define DYLD_INFO_RETRY_DELAY_US 10000

kern_return_t mach_vm_read_overwrite(vm_map_read_t target_task, mach_vm_address_t address, mach_vm_size_t size, mach_vm_address_t data, mach_vm_size_t *outsize);
kern_return_t mach_vm_region(vm_map_read_t target_task, mach_vm_address_t *address, mach_vm_size_t *size, vm_region_flavor_t flavor, vm_region_info_t info, mach_msg_type_number_t *infoCnt, mach_port_t *object_name);

static void removePrefix(char *str, const char *prefix) {
    size_t len_str = strlen(str);
    size_t len_prefix = strlen(prefix);

    if (len_str >= len_prefix && strncmp(str, prefix, len_prefix) == 0) {
        memmove(str, str + len_prefix, len_str - len_prefix + 1);
    }
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

NSData *readLoadedImageHeader(vm_map_t task, uint64_t address) {
    struct mach_header_64 header = {0};
    if (!readProcessMemory(task, address, &header, sizeof(header))) return nil;
    if (header.magic != MH_MAGIC_64 && header.magic != MH_MAGIC) return nil;
    size_t headerSize = header.magic == MH_MAGIC_64 ? sizeof(header) : sizeof(struct mach_header);
    if (header.sizeofcmds > 16 * 1024 * 1024 ||
        header.ncmds > header.sizeofcmds / sizeof(struct load_command)) return nil;
    size_t length = headerSize + header.sizeofcmds;
    if (address > UINT64_MAX - length) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:length];
    return readProcessMemory(task, address, data.mutableBytes, data.length) ? data : nil;
}

BOOL rebuildDecryptedImageAtPath(NSString *sourcePath, vm_map_t task,
                                 uint64_t loadAddress, TDMachOImage *image,
                                 NSString *outputPath, NSError **error) {
    return TDRebuildMachOSlice(sourcePath, image, outputPath, ^BOOL(uint64_t offset, void *buffer, size_t size) {
        if (loadAddress > UINT64_MAX - offset || loadAddress + offset > UINT64_MAX - size) return NO;
        return readProcessMemory(task, loadAddress + offset, buffer, size);
    }, error);
}
