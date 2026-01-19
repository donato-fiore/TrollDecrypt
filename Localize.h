#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Localize : NSObject

+ (NSString *)localizedStringForKey:(NSString *)key;
+ (NSString *)localizedStringForKey:(NSString *)key fallback:(NSString *)fallback;

@end

NS_ASSUME_NONNULL_END