#import <Foundation/Foundation.h>
@interface SHQRDecoder : NSObject
+ (NSString *)activationCodeFromPayload:(NSString *)payload;
+ (NSString *)decode:(NSData *)data error:(NSError **)error;
@end
