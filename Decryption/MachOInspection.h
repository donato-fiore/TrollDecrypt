#import <Foundation/Foundation.h>
#import <mach-o/loader.h>

@interface TDMachOImage : NSObject
@property (nonatomic, copy) NSData *headerData;
@property (nonatomic) uint64_t fileOffset;
@property (nonatomic) uint64_t fileSize;
@property (nonatomic) cpu_type_t cpuType;
@property (nonatomic) uint32_t fileType;
@property (nonatomic) struct encryption_info_command encryption;
@property (nonatomic) uint64_t encryptionCommandOffset;
@property (nonatomic) uint64_t encryptedVMOffset;
@end

// An empty array identifies a resource file; nil identifies an unreadable or malformed image.
NSArray<TDMachOImage *> *TDInspectMachO(NSString *path, NSError **error);
NSArray<NSString *> *TDEncryptedFilesInBundle(NSString *bundlePath, NSError **error);
NSArray<NSString *> *TDExtensionBundles(NSString *appPath, NSError **error);
