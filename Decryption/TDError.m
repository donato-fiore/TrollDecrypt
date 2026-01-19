#import "TDError.h"

@implementation TDError

+ (instancetype)errorWithCode:(TDErrorCode)code {
    NSDictionary *userInfo = @{
        NSLocalizedDescriptionKey: [self descriptionForErrorCode:code]
    };
    return [super errorWithDomain:@"com.fiore.TDError" code:code userInfo:userInfo];
}

+ (NSString *)descriptionForErrorCode:(TDErrorCode)code {
    switch (code) {
        case TDErrorCodeApplicationBundleCopyFailed:
            return @"Application bundle copy failed";
        case TDErrorCodeBinaryDecryptionFailed:
            return @"Binary decryption failed";
        case TDErrorCodeLaunchFailed:
            return @"Application launch failed";
        case TDErrorCodeIPAConstructionFailed:
            return @"IPA construction failed";
        case TDErrorCodeUnknown:
        default:
            return @"Unknown error";
    }
}

@end
