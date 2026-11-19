

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

NSData *readLoadedImageHeader(vm_map_t task, uint64_t address);

@class TDMachOImage;
BOOL rebuildDecryptedImageAtPath(NSString *sourcePath, vm_map_t task,
                                 uint64_t loadAddress, TDMachOImage *image,
                                 NSString *outputPath, NSError **error);
