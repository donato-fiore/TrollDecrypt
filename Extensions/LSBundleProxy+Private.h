#import <Foundation/Foundation.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <CoreServices/_LSLazyPropertyList.h>

@interface LSBundleProxy (Private)

@property (copy, nonatomic) _LSLazyPropertyList *_infoDictionary;

@end