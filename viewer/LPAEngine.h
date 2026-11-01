#import <Foundation/Foundation.h>
#ifdef __cplusplus
#include "../shared/Protocol.hpp"
#endif
@interface SHLPA : NSObject
@property(nonatomic, copy) void (^progress)(NSString *stage);
@property(nonatomic, copy) NSString *lastWarning;
@property(nonatomic, readonly) int slot;
@property(nonatomic, copy, readonly) NSString *expectedEID;
- (instancetype)initWithSlot:(int)slot;
- (instancetype)initWithSlot:(int)slot expectedEID:(NSString *)eid;
#ifdef __cplusplus
+ (std::optional<std::vector<shjson::Slot>>)availableSlots:(NSError **)error;
#endif
+ (NSOperationQueue *)operationQueue;
+ (BOOL)automaticNotificationsEnabled;
+ (BOOL)automaticallySubmitsOperation:(NSString *)operation;
- (BOOL)submitAutomaticNotifications:(NSError **)error;
@property(nonatomic, copy) NSString *downloadIMEI;
- (BOOL)allowOwnNetworking:(NSError **)error;
- (BOOL)checkNetwork:(NSError **)error;
- (NSDictionary *)readCard:(NSError **)error;
- (BOOL)download:(NSString *)code confirmation:(NSString *)confirmation error:(NSError **)error;
- (BOOL)deleteProfile:(NSString *)iccid error:(NSError **)error;
- (BOOL)setProfile:(NSString *)iccid enabled:(BOOL)enabled error:(NSError **)error;
- (BOOL)renameProfile:(NSString *)iccid name:(NSString *)name error:(NSError **)error;
- (NSArray *)notifications:(NSError **)error;
- (BOOL)processNotification:(unsigned long)sequence
                 removeOnly:(BOOL)removeOnly
                      error:(NSError **)error;
- (BOOL)setDefaultServer:(NSString *)server error:(NSError **)error;
- (BOOL)resetCard:(NSString *)eid confirmation:(NSString *)confirmation error:(NSError **)error;
- (NSArray<NSDictionary *> *)sendAPDUs:(NSArray<NSData *> *)commands
                          stopOnStatus:(BOOL)stop
                                 error:(NSError **)error;
- (NSData *)sendDER:(NSData *)request error:(NSError **)error;
@end
