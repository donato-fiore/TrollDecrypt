#import "TDAppDelegate.h"
#import "TDRootViewController.h"
#import "TDUtils.h"

@implementation TDAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  _window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
  _rootViewController = [[UINavigationController alloc]
      initWithRootViewController:[[TDRootViewController alloc] init]];
  _window.rootViewController = _rootViewController;
  [_window makeKeyAndVisible];
  return YES;
}

- (BOOL)application:(UIApplication *)application
            openURL:(NSURL *)url
            options:
                (NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
  if ([url.scheme isEqualToString:@"trolldecrypt"] &&
      [url.host isEqualToString:@"decrypt"]) {
    NSURLComponents *components = [NSURLComponents componentsWithURL:url
                                             resolvingAgainstBaseURL:NO];
    __block NSString *bundleID = nil;
    [components.queryItems
        enumerateObjectsUsingBlock:^(NSURLQueryItem *item, NSUInteger idx,
                                     BOOL *stop) {
          if ([item.name isEqualToString:@"id"]) {
            bundleID = item.value;
            *stop = YES;
          }
        }];

    if (bundleID == nil)
      return NO;

    for (NSDictionary *app in appList()) {
      if ([app[@"bundleID"] isEqualToString:bundleID]) {
        decryptApp(app);
        return YES;
      }
    }
    return NO;
  }
  return NO;
}

@end
