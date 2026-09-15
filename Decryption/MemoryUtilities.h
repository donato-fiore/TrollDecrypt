

#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <mach-o/loader.h>
#import <mach-o/dyld_images.h>

typedef struct MainImageInfo {
    uint64_t loadAddress;     // main executable Mach-O header address
    NSString *path;           // main executable path
    BOOL     ok;
} MainImageInfo_t;

// Whether a Mach-O on disk still carries a live LC_ENCRYPTION_INFO command.
// TDEncryptionStateUnknown means the file could not be classified (fat binary,
// unreadable, ...) and the caller should fall back to inspecting the process.
typedef NS_ENUM(NSInteger, TDEncryptionState) {
    TDEncryptionStateUnknown = -1,
    TDEncryptionStateDecrypted,
    TDEncryptionStateEncrypted
};

NSString *NSStringFromMainImageInfo(MainImageInfo_t info);

TDEncryptionState encryptionStateOfImageAtPath(NSString *path);

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
