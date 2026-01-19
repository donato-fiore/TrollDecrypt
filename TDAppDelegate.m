#import "TDAppDelegate.h"
#import "TDRootViewController.h"

@implementation TDAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    _window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    TDRootViewController *rootVC = [[TDRootViewController alloc] init];
    _window.rootViewController = rootVC;
    [_window makeKeyAndVisible];
    return YES;
}

@end
