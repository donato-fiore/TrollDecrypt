#import "LSBundleProxy+TrollDecrypt.h"
#import "LSBundleProxy+Private.h"
#import <mach/mach_error.h>

@implementation LSBundleProxy (TrollDecrypt)

- (NSString *)td_canonicalExecutablePath {
    NSString *canonicalPath = nil;
    if ([self respondsToSelector:@selector(canonicalExecutablePath)]) {
        canonicalPath = [self performSelector:@selector(canonicalExecutablePath)];
    }

    if (!canonicalPath) {
        NSDictionary *infoPlist = [[self _infoDictionary] _expensiveDictionaryRepresentation];

        NSString *executableName = [infoPlist objectForKey:@"CFBundleExecutable"];
        canonicalPath = [self.bundleURL.path stringByAppendingPathComponent:executableName];
    }

    return canonicalPath;
}

- (LaunchdResponse_t)td_launchProcess {
    NSString *canonicalPath = [self td_canonicalExecutablePath];

    NSLog(@"Launching application %@ at path %@", self.bundleIdentifier, canonicalPath);

    NSDictionary *plist = @{
        @"UserName": @"mobile",
        @"CFBundleIdentifier": self.bundleIdentifier,
        @"_ManagedBy": @"com.apple.runningboard",
        @"Label": [self _UIKitApplicationLabel],
        @"ProgramArguments": @[
            canonicalPath
        ],
        @"Program": canonicalPath,
    };

    NSDictionary *requestDict = @{
        @"monitor": @NO,
        @"plist": plist,
    };

    xpc_object_t request = _CFXPCCreateXPCObjectFromCFObject(requestDict);
    xpc_dictionary_set_uint64(request, "handle", 0);
    xpc_dictionary_set_uint64(request, "type", 7);

    xpc_object_t response = NULL;
    kern_return_t kr = _launch_job_routine(OSLaunchdJobSelectorSubmitAndStart, request, &response);
    NSLog(@"launch_job_routine returned: %s", mach_error_string(kr));

    if (kr != KERN_SUCCESS || xpc_get_type(response) != XPC_TYPE_DICTIONARY) return NIL_LAUNCHD_RESPONSE;

    return responseFromXPCObject(response);
}

- (NSString *)_UIKitApplicationLabel {
    NSString *uuid = [[NSUUID UUID] UUIDString];
    return [NSString stringWithFormat:UIKitApplicationLabelFormat, self.bundleIdentifier, [uuid substringToIndex:6]];
}

@end