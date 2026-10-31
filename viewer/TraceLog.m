#import "TraceLog.h"
#import "Localization.h"
@interface SHTraceLog ()
@property(nonatomic, strong) NSMutableArray<NSString *> *lines;
@property(nonatomic) NSUInteger bytes;
@property(nonatomic) NSUInteger dropped;
@property(nonatomic) BOOL notificationPending;
@property(nonatomic, strong) NSDateFormatter *clock;
@end
@implementation SHTraceLog
+ (instancetype)shared {
    static SHTraceLog *log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        log = [self new];
        log.lines = [NSMutableArray array];
        log.clock = [NSDateFormatter new];
        log.clock.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        log.clock.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        log.clock.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSS'Z'";
    });
    return log;
}
- (void)event:(NSString *)english {
    @synchronized(self) {
        NSString *line =
            [NSString stringWithFormat:@"%@  %@", [self.clock stringFromDate:NSDate.date],
                                       SHEnglish(english)];
        [self.lines addObject:line];
        self.bytes += [line lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        while (self.bytes > 4 * 1024 * 1024 && self.lines.count > 1) {
            self.bytes -= [self.lines[0] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
            [self.lines removeObjectAtIndex:0];
            self.dropped++;
        }
        if (!self.notificationPending) {
            self.notificationPending = YES;
            dispatch_after(
                dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                    @synchronized(self) {
                        self.notificationPending = NO;
                    }
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"SHLog" object:nil];
                });
        }
    }
}
- (void)error:(NSError *)error {
    if (!error)
        return;
    // OS error descriptions follow the system language. Log stable domain/code instead.
    NSString *detail = error.userInfo[@"SHErrorEnglish"];
    [self event:[NSString
                    stringWithFormat:@"ERROR domain=%@ code=%ld%@", error.domain, (long)error.code,
                                     detail.length ? [@" " stringByAppendingString:detail] : @""]];
}
- (void)frame:(NSString *)label data:(NSData *)data {
    [self event:[NSString stringWithFormat:@"%@ length=%lu", label, (unsigned long)data.length]];
    const uint8_t *bytes = data.bytes;
    for (NSUInteger offset = 0; offset < data.length; offset += 1024) {
        NSUInteger length = MIN((NSUInteger)1024, data.length - offset);
        NSMutableString *hex = [NSMutableString stringWithCapacity:length * 2];
        for (NSUInteger i = 0; i < length; i++)
            [hex appendFormat:@"%02X", bytes[offset + i]];
        [self event:[NSString stringWithFormat:@"%@ offset=%lu HEX %@", label,
                                               (unsigned long)offset, hex]];
    }
}
- (NSString *)text {
    @synchronized(self) {
        NSString *header =
            @"SIMHarbor trace | UTC | APDU + application-level HTTPS | memory only | 4 MiB retention\nRaw payloads may contain activation credentials and card identifiers.\n";
        if (self.dropped)
            header = [header stringByAppendingFormat:@"RETENTION: %lu earlier records evicted.\n",
                                                     (unsigned long)self.dropped];
        return [header stringByAppendingString:[self.lines componentsJoinedByString:@"\n"]];
    }
}
- (void)clear {
    @synchronized(self) {
        [self.lines removeAllObjects];
        self.bytes = 0;
        self.dropped = 0;
    }
    [self event:@"Log cleared."];
}
@end
