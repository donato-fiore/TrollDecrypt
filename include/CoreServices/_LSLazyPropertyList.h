#import <Foundation/Foundation.h>

@class LSPropertyList;

@interface _LSLazyPropertyList : /* LSPropertyList */ NSObject

- (NSDictionary *)_expensiveDictionaryRepresentation;

@end