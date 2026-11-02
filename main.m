#import <Foundation/Foundation.h>
#import "TDAppDelegate.h"
#import "Decryption/SuspendedDecryption.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        if (argc == 4 && strcmp(argv[1], "--decrypt-suspended") == 0) {
            NSError *error = nil;
            BOOL success = TDDecryptSuspendedExecutableInHelper(@(argv[2]), @(argv[3]), &error);
            if (!success) fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
            return success ? 0 : 1;
        }
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(TDAppDelegate.class));
    }
}
