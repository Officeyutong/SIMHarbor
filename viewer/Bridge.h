#import <Foundation/Foundation.h>
@interface SHBridge : NSObject
+ (instancetype)shared;
- (void)start;
- (BOOL)connected;
- (NSDictionary *)request:(NSDictionary *)body error:(NSError **)error;
@end
