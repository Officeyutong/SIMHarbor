#import "Localization.h"
#import "QRDecoder.h"
#import <Vision/Vision.h>
@implementation SHQRDecoder
+ (NSString*)activationCodeFromPayload:(NSString*)payload{
 if(![payload isKindOfClass:NSString.class])return nil;
 NSMutableCharacterSet *outer=[NSCharacterSet.whitespaceAndNewlineCharacterSet mutableCopy];[outer addCharactersInString:@"\uFEFF"];
 NSString *value=[payload stringByTrimmingCharactersInSet:outer];
 if(![value.lowercaseString hasPrefix:@"lpa:1$"])return nil;
 NSArray *parts=[value componentsSeparatedByString:@"$"];
 if(parts.count<3||![parts[1]length]||![parts[2]length]||[parts[1]rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/:@?# \t\r\n"]].location!=NSNotFound)return nil;
 return [@"LPA:" stringByAppendingString:[value substringFromIndex:4]];
}
+ (NSString*)decode:(NSData*)data error:(NSError**)error{
 if(!data.length||data.length>24*1024*1024){if(error)*error=[NSError errorWithDomain:@"SIMHarbor" code:5 userInfo:@{NSLocalizedDescriptionKey:SHL(@"Unable to read this image. Choose a clear QR code image.")}];return nil;}
 VNDetectBarcodesRequest*request=[VNDetectBarcodesRequest new];request.symbologies=@[VNBarcodeSymbologyQR];request.usesCPUOnly=YES;
 VNImageRequestHandler*handler=[[VNImageRequestHandler alloc]initWithData:data options:@{}];if(![handler performRequests:@[request]error:error])return nil;
 for(VNBarcodeObservation*o in request.results){NSString*s=[self activationCodeFromPayload:o.payloadStringValue];if(s)return s;}
 if(error)*error=[NSError errorWithDomain:@"SIMHarbor" code:5 userInfo:@{NSLocalizedDescriptionKey:SHL(@"No valid eSIM activation QR code was found in the image.")}];return nil;
}
@end
