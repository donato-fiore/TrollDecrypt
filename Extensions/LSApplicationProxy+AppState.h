#import <MobileCoreServices/MobileCoreServices.h>

@interface _LSApplicationState : NSObject 
@property (readonly, nonatomic, getter=isInstalled) BOOL installed;
@property (readonly, nonatomic, getter=isPlaceholder) BOOL placeholder;
@end

@interface LSApplicationProxy (AppState)
@property (nonatomic, readonly) _LSApplicationState *appState;
@end