#import <Foundation/Foundation.h>

#define ROOT_OUTPUT_PATH @"/var/mobile/Documents/TrollDecrypt"

@class LSApplicationProxy;

typedef NS_ENUM(NSInteger, TDDecryptionOutputMode) {
    TDDecryptionOutputModeFullIPA = 0,
    TDDecryptionOutputModeAppBundleOnly,
    TDDecryptionOutputModeMainBinaryOnly,
};

typedef struct {
    TDDecryptionOutputMode outputMode;
} TDDecryptionTaskOptions;

TDDecryptionTaskOptions TDDecryptionTaskOptionsMake(TDDecryptionOutputMode outputMode);
TDDecryptionTaskOptions TDDecryptionTaskDefaultOptions(void);

@interface TDDecryptionTask : NSObject

@property (nonatomic, strong) LSApplicationProxy *applicationProxy;
@property (nonatomic, copy) void (^progressHandler)(NSString *progress);
// @property (nonatomic, copy) void (^completionHandler)(BOOL success, NSURL *outputURL, NSError *error);

- (instancetype)initWithApplicationProxy:(LSApplicationProxy *)application;
- (void)executeWithCompletionHandler:(void (^)(BOOL success, NSURL *outputURL, NSError *error))completionHandler;
- (void)executeWithCompletionHandler:(void (^)(BOOL success, NSURL *outputURL, NSError *error))completionHandler options:(TDDecryptionTaskOptions)options;

@end




@interface MFFileArchiveDirectory : NSObject

+ (instancetype)archiveDirectory;
- (bool)inputWithURL:(NSURL *)url;

@end

@interface MFFileArchive : NSObject

+ (instancetype)archive;
- (NSMutableData *)compressFolder:(NSURL *)folderURL error:(NSError **)error;


@end
