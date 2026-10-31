#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
@interface SHQRDecoder : NSObject
+ (NSString *)activationCodeFromPayload:(NSString *)payload;
+ (NSString *)decode:(NSData *)data error:(NSError **)error;
+ (NSString *)decodePixelBuffer:(CVPixelBufferRef)pixelBuffer
                 detectedQRCode:(BOOL *)detected
                          error:(NSError **)error;
@end
