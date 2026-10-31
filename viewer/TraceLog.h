#import <Foundation/Foundation.h>
@interface SHTraceLog : NSObject
+ (instancetype)shared;
- (void)event:(NSString *)english;
- (void)error:(NSError *)error;
- (void)frame:(NSString *)label data:(NSData *)data;
- (NSString *)text;
- (void)clear;
@end
