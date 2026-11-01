#import <Foundation/Foundation.h>
#ifdef __cplusplus
#include "../shared/Protocol.hpp"
#endif
@interface SHBridge : NSObject
+ (instancetype)shared;
- (void)start;
- (BOOL)connected;
#ifdef __cplusplus
- (std::optional<shjson::Reply>)request:(const shjson::Request &)body error:(NSError **)error;
#endif
@end
