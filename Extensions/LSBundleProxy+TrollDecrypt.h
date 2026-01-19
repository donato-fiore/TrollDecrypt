#import <MobileCoreServices/LSBundleProxy.h>
#import <MobileCoreServices/LSPlugInKitProxy.h>
#import "../Decryption/LaunchdResponse.h"

#define UIKitApplicationLabelFormat @"UIKitApplication:%@[%@][rb-legacy]"

@interface LSBundleProxy (TrollDecrypt)

- (NSString *)td_canonicalExecutablePath;
- (LaunchdResponse_t)td_launchProcess;

@end