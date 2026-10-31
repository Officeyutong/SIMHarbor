#import "TraceLog.h"
#import "Localization.h"
#import "Bridge.h"
#import "../shared/Wire.h"
#import <arpa/inet.h>
#import <Security/Security.h>
@interface SHBridge(){int _peer;NSRecursiveLock*_lock;}
@end
@implementation SHBridge
+ (instancetype)shared{static SHBridge*b;static dispatch_once_t once;dispatch_once(&once,^{b=[SHBridge new];b->_peer=-1;b->_lock=[NSRecursiveLock new];});return b;}
- (BOOL)connected{[_lock lock];BOOL yes=_peer>=0;[_lock unlock];return yes;}
- (void)start{static dispatch_once_t once;dispatch_once(&once,^{dispatch_async(dispatch_get_global_queue(0,0),^{
 int server=socket(AF_INET,SOCK_STREAM,0),yes=1;setsockopt(server,SOL_SOCKET,SO_REUSEADDR,&yes,sizeof yes);setsockopt(server,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof yes);
 struct sockaddr_in addr={0};addr.sin_len=sizeof addr;addr.sin_family=AF_INET;addr.sin_port=htons(SH_PORT);addr.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
 if(bind(server,(struct sockaddr*)&addr,sizeof addr)||listen(server,2)){[[SHTraceLog shared]event:@"IPC listener failed to start."];close(server);return;}[[SHTraceLog shared]event:@"IPC listener started on loopback port 18099."];
 while(1){@autoreleasepool{int fd=accept(server,NULL,NULL);if(fd<0)continue;setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof yes);struct timeval timeout={5,0};setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof timeout);setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,sizeof timeout);
 unsigned char bytes[32];if(SecRandomCopyBytes(kSecRandomDefault,sizeof bytes,bytes)!=errSecSuccess){close(fd);continue;}NSString*nonce=SHHex([NSData dataWithBytes:bytes length:32]);BOOL ok=SHWrite(fd,@{@"nonce":nonce});NSDictionary*reply=ok?SHRead(fd):nil;
 if(!SHSame(reply[@"mac"],SHMAC(@"commcenter:",nonce))||!SHWrite(fd,@{@"mac":SHMAC(@"app:",nonce)})){close(fd);continue;}
 [self->_lock lock];if(self->_peer>=0){char b;ssize_t n=recv(self->_peer,&b,1,MSG_PEEK|MSG_DONTWAIT);if(n==0||(n<0&&errno!=EAGAIN&&errno!=EWOULDBLOCK)){close(self->_peer);self->_peer=-1;}}
 if(self->_peer>=0)close(fd);else{timeout.tv_sec=35;setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof timeout);self->_peer=fd;[[SHTraceLog shared]event:@"IPC peer authenticated."];}[self->_lock unlock];
 }}});});}
- (NSDictionary*)request:(NSDictionary*)body error:(NSError**)error{[_lock lock];NSMutableDictionary*q=[body mutableCopy];q[@"id"]=NSUUID.UUID.UUIDString;NSDictionary*r=nil;
 NSString*op=q[@"op"]?:@"unknown";NSString*trace=[NSString stringWithFormat:@"IPC TX id=%@ op=%@",q[@"id"],op];[[SHTraceLog shared]event:trace];
 if([op isEqual:@"transmit"])[[SHTraceLog shared]frame:[@"APDU TX " stringByAppendingString:q[@"id"]]data:SHUnhex(q[@"hex"])];
 else if([op isEqual:@"open"])[[SHTraceLog shared]event:[NSString stringWithFormat:@"CHANNEL OPEN slot=%@ AID=%@",q[@"slot"],q[@"aid"]]];
 if(_peer>=0&&SHWrite(_peer,q))r=SHRead(_peer);
 if(![r[@"id"]isEqual:q[@"id"]]){if(_peer>=0)close(_peer);_peer=-1;r=nil;}
 if([op isEqual:@"transmit"]&&r[@"hex"]){NSData*rx=SHUnhex(r[@"hex"]);[[SHTraceLog shared]frame:[@"APDU RX " stringByAppendingString:q[@"id"]]data:rx];if(rx.length>=2){const uint8_t*b=rx.bytes;[[SHTraceLog shared]event:[NSString stringWithFormat:@"APDU SW=%02X%02X",b[rx.length-2],b[rx.length-1]]];}}
 else if(r){NSData*d=[NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingSortedKeys error:nil];[[SHTraceLog shared]event:[NSString stringWithFormat:@"IPC RX %@",[[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding]]];}
 NSString*message=!r?@"Card service is disconnected. Keep the app in the foreground and refresh later.":![r[@"ok"]boolValue]?(r[@"error"]?:@"Card operation failed"):nil;
 if(message){[[SHTraceLog shared]event:[@"IPC ERROR " stringByAppendingString:message]];if(error){int code=0;NSString*display=SHL(message);if(sscanf(message.UTF8String,"Card transport failed (%d).",&code)==1)display=[NSString stringWithFormat:SHL(@"Card transport failed (%d)."),code];*error=[NSError errorWithDomain:@"SIMHarbor" code:1 userInfo:@{NSLocalizedDescriptionKey:display,@"SHErrorEnglish":message}];}}[_lock unlock];return message?nil:r;}
@end
