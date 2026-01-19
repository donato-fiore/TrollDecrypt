#import <MobileCoreServices/MobileCoreServices.h>

@protocol LSApplicationWorkspaceObserverProtocol <NSObject>
@optional
- (void)applicationsDidInstall:(NSArray <LSApplicationProxy *>*)apps;
- (void)applicationsDidUninstall:(NSArray <LSApplicationProxy *>*)apps;
@end