#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TDErrorCode) {
    TDErrorCodeUnknown = -1,
    TDErrorCodeApplicationBundleCopyFailed,
    TDErrorCodeBinaryDecryptionFailed,
    TDErrorCodeLaunchFailed,
    TDErrorCodeIPAConstructionFailed,
    TDErrorCodeAppBundleOutputFailed
};

@interface TDError : NSError

+ (instancetype)errorWithCode:(TDErrorCode)code;

@end
