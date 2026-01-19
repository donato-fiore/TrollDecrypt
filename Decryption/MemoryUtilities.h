

#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <mach-o/loader.h>
#import <mach-o/dyld_images.h>

typedef struct MainImageInfo {
    uint64_t loadAddress;     // main executable Mach-O header address
    NSString *path;           // main executable path
    BOOL     ok;
} MainImageInfo_t;

NSString *NSStringFromMainImageInfo(MainImageInfo_t info);

MainImageInfo_t imageInfoForPIDWithRetry(const char *sourcePath, vm_map_t task, pid_t pid);

BOOL readEncryptionInfo(vm_map_t task, uint64_t address,
                        struct encryption_info_command *encryptionInfo,
                        uint64_t *loadCommandAddress);

BOOL rebuildDecryptedImageAtPath(NSString *sourcePath,
                                 vm_map_t task,
                                 uint64_t loadAddress,
                                 struct encryption_info_command *encryptionInfo,
                                 uint64_t loadCommandAddress,
                                 NSString *outputPath);