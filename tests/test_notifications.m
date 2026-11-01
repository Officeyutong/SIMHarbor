#import "../viewer/LPAEngine.h"
#import "../viewer/Localization.h"

@interface SHLPA (NotificationCheck)
- (void)finishAutomaticNotifications;
@end

// Fixture-only transport: no card, HTTP or profile operations are performed.
@interface SHNotificationFixture : SHLPA
@property(nonatomic, copy) NSArray *pending;
@property(nonatomic, strong) NSMutableArray *attempted;
@property(nonatomic, strong) NSMutableArray *removed;
@property(nonatomic) NSUInteger reads;
@property(nonatomic, strong) NSNumber *failingSequence;
@property(nonatomic) BOOL failListing;
@end
@implementation SHNotificationFixture
- (NSArray *)notifications:(NSError **)error {
    self.reads++;
    self.lastWarning = nil; // Real channel opening resets per-session warnings.
    if (self.failListing) {
        if (error)
            *error = SHError(1, @"Failed to read notifications");
        return nil;
    }
    return self.pending;
}
- (BOOL)processNotification:(unsigned long)sequence
                 removeOnly:(BOOL)remove
                      error:(NSError **)error {
    NSAssert(!remove, @"Automatic submission must notify before removing");
    self.lastWarning = nil;
    [self.attempted addObject:@(sequence)];
    if ([@(sequence) isEqual:self.failingSequence]) {
        if (error)
            *error = [NSError errorWithDomain:NSURLErrorDomain
                                         code:NSURLErrorTimedOut
                                     userInfo:nil];
        return NO;
    }
    [self.removed addObject:@(sequence)];
    return YES;
}
@end
static SHNotificationFixture *fixture(void) {
    SHNotificationFixture *engine = [[SHNotificationFixture alloc] initWithSlot:1
                                                                    expectedEID:@"fixture-card"];
    engine.attempted = [NSMutableArray array];
    engine.removed = [NSMutableArray array];
    engine.pending = @[
        @{@"sequence" : @4,
          @"operation" : @"Disable",
          @"iccid" : @"fixture-old-line"},
        @{@"sequence" : @1,
          @"operation" : @"Install"},
        @{@"sequence" : @3,
          @"operation" : @"Enable",
          @"iccid" : @"fixture-new-line"},
        @{@"sequence" : @2,
          @"operation" : @"Delete"},
        @{@"sequence" : @5,
          @"operation" : @"Other"}
    ];
    return engine;
}
int SHNotificationCheck(void) {
    @autoreleasepool {
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        NSArray *keys =
            @[ @"SHNotifyAuto", @"SHNotifyDownload", @"SHNotifyDelete", @"SHNotifySwitch" ];
        NSMutableDictionary *original = [NSMutableDictionary dictionary];
        for (NSString *key in keys) {
            original[key] = [defaults objectForKey:key] ?: NSNull.null;
            [defaults removeObjectForKey:key];
        }
        @try {
            NSError *error = nil;
            SHNotificationFixture *engine = fixture();
            if (![SHLPA automaticNotificationsEnabled] ||
                ![engine submitAutomaticNotifications:&error] || error ||
                ![engine.attempted isEqual:@[ @1, @2, @3, @4 ]] ||
                ![engine.removed isEqual:engine.attempted])
                return 1;
            [defaults setBool:NO forKey:@"SHNotifyAuto"];
            engine = fixture();
            if (![engine submitAutomaticNotifications:&error] || engine.reads ||
                engine.attempted.count)
                return 2;
            [defaults setBool:YES forKey:@"SHNotifyAuto"];
            [defaults setBool:NO forKey:@"SHNotifySwitch"];
            engine = fixture();
            if (![engine submitAutomaticNotifications:&error] ||
                ![engine.attempted isEqual:@[ @1, @2 ]])
                return 3;
            [defaults setBool:NO forKey:@"SHNotifyDownload"];
            [defaults setBool:NO forKey:@"SHNotifyDelete"];
            engine = fixture();
            if (![engine submitAutomaticNotifications:&error] || engine.reads)
                return 4;
            for (NSString *key in keys)
                [defaults removeObjectForKey:key];
            engine = fixture();
            engine.failingSequence = @2;
            if ([engine submitAutomaticNotifications:&error] || error.code != NSURLErrorTimedOut ||
                ![engine.attempted isEqual:@[ @1, @2 ]] || ![engine.removed isEqual:@[ @1 ]])
                return 5;
            engine = fixture();
            engine.failListing = YES;
            engine.lastWarning = @"fixture-existing-warning";
            [engine finishAutomaticNotifications];
            if (engine.attempted.count ||
                ![engine.lastWarning containsString:@"fixture-existing-warning"] ||
                ![engine.lastWarning
                    containsString:
                        SHL(@"The profile operation completed, but some operator notifications are pending. Open Notifications to retry.")])
                return 6;
            engine = fixture();
            engine.lastWarning = @"fixture-existing-warning";
            [engine finishAutomaticNotifications];
            if (![engine.lastWarning isEqual:@"fixture-existing-warning"])
                return 7;
            engine = fixture();
            engine.pending = @[];
            if (![engine submitAutomaticNotifications:&error] || engine.attempted.count)
                return 8;
        } @finally {
            for (NSString *key in keys) {
                id value = original[key];
                if (value == NSNull.null)
                    [defaults removeObjectForKey:key];
                else
                    [defaults setObject:value forKey:key];
            }
        }
        printf(
            "PASS: automatic notification defaults, opt-outs, paired switch events, ordered submission, failure retention and warning preservation (fixtures only)\n");
        return 0;
    }
}
