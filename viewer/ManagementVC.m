#import "TraceLog.h"
#import "Localization.h"
#import "ManagementVC.h"
@interface SHManagementVC ()
@property(nonatomic, strong) SHLPA *lpa;
@property(nonatomic, strong) NSOperationQueue *queue;
@property(nonatomic, strong) NSDictionary *card;
@property(nonatomic, strong) NSArray *items;
@property(nonatomic) BOOL notificationMode;
@property(nonatomic) BOOL busy;
@end
@implementation SHManagementVC
- (instancetype)initWithLPA:(SHLPA *)lpa queue:(NSOperationQueue *)queue notifications:(BOOL)mode {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _lpa = lpa;
        _queue = queue;
        _notificationMode = mode;
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.notificationMode ? SHL(@"Notifications") : SHL(@"Card and settings");
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                      target:self
                                                      action:@selector(load)];
    if (self.notificationMode)
        self.navigationItem.rightBarButtonItems = @[
            self.navigationItem.rightBarButtonItem,
            [[UIBarButtonItem alloc] initWithTitle:SHL(@"Submit all")
                                             style:UIBarButtonItemStylePlain
                                            target:self
                                            action:@selector(processAll)]
        ];
    [self load];
}
- (void)alert:(NSString *)text {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:SHL(@"SIMHarbor")
                                                               message:text
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:SHL(@"OK")
                                          style:UIAlertActionStyleDefault
                                        handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)working:(BOOL)b {
    self.busy = b;
    self.navigationItem.prompt = b ? SHL(@"Working. Keep the app in the foreground…") : nil;
    self.navigationItem.hidesBackButton = b;
    self.navigationController.interactivePopGestureRecognizer.enabled = !b;
    for (UIBarButtonItem *item in self.navigationItem.rightBarButtonItems)
        item.enabled = !b;
    self.tableView.userInteractionEnabled = !b;
    self.tabBarController.tabBar.userInteractionEnabled = !b;
}
- (void)load {
    if (self.busy)
        return;
    [self working:YES];
    [self.queue addOperationWithBlock:^{
        NSError *e = nil;
        id r = self.notificationMode ? [self.lpa notifications:&e] : [self.lpa readCard:&e];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self working:NO];
            if (!r)
                [[SHTraceLog shared] error:e];
            if (r) {
                if (self.notificationMode)
                    self.items = r;
                else
                    self.card = r;
                [self.tableView reloadData];
            } else
                [self alert:e.localizedDescription ?: SHL(@"Read failed")];
        });
    }];
}
- (void)run:(BOOL (^)(NSError **))job {
    if (self.busy)
        return;
    [self working:YES];
    [self.queue addOperationWithBlock:^{
        NSError *e = nil;
        BOOL ok = job(&e);
        if (e)
            [[SHTraceLog shared] error:e];
        else
            [[SHTraceLog shared] event:@"Management operation completed."];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self working:NO];
            [self alert:ok ? SHL(@"Operation completed")
                           : (e.localizedDescription ?: SHL(@"Operation failed"))];
            [self load];
        });
    }];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)t {
    return self.notificationMode ? 1 : 5;
}
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    if (self.notificationMode)
        return MAX((NSUInteger)1, self.items.count);
    return s == 0 ? 8 : s == 1 ? 3 : s == 2 ? 5 : 1;
}
- (NSString *)tableView:(UITableView *)t titleForHeaderInSection:(NSInteger)s {
    if (self.notificationMode)
        return SHL(@"Tap a notification to submit or remove it");
    return @[
        SHL(@"Card information"), SHL(@"Servers"), SHL(@"Notifications and switching"),
        SHL(@"Advanced"), SHL(@"App")
    ][s];
}
- (NSString *)tableView:(UITableView *)t titleForFooterInSection:(NSInteger)s {
    if (self.notificationMode)
        return SHL(
            @"Notifications are removed after successful submission. Remove-only does not notify the operator.");
    if (s == 2)
        return SHL(
            @"Automatic submission is on by default. After installing, deleting or switching profiles, submit pending notifications for enabled categories. Failed submissions remain pending for manual retry.");
    return s == 3
               ? SHL(@"Reset removes profiles from the entire card. You may need to download them again.")
               : nil;
}
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)i {
    UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                reuseIdentifier:nil];
    c.detailTextLabel.numberOfLines = 0;
    if (self.notificationMode) {
        if (!self.items.count) {
            c.textLabel.text = SHL(@"No pending notifications");
            return c;
        }
        NSDictionary *n = self.items[i.row];
        c.textLabel.text =
            [NSString stringWithFormat:@"#%@ · %@", n[@"sequence"], SHL(n[@"operation"])];
        c.detailTextLabel.text = n[@"address"];
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return c;
    }
    if (i.section == 0) {
        NSArray *labels = @[
            @"EID", SHL(@"Free storage"), SHL(@"Free working memory"), SHL(@"Card firmware"),
            SHL(@"RSP version"), SHL(@"Profile version"), SHL(@"Profile count"),
            SHL(@"APDU block size")
        ];
        NSArray *values = @[
            self.card[@"eid"] ?: @"—",
            [NSString stringWithFormat:@"%@ bytes", self.card[@"freeBytes"] ?: @0],
            [NSString stringWithFormat:@"%@ bytes", self.card[@"freeVolatileBytes"] ?: @0],
            self.card[@"firmware"] ?: @"—", self.card[@"rspVersion"] ?: @"—",
            self.card[@"profileVersion"] ?: @"—", @([self.card[@"profiles"] count]).stringValue,
            [NSString stringWithFormat:@"%ld bytes", (long)([NSUserDefaults.standardUserDefaults
                                                                integerForKey:@"SHMSS"]
                                                                ?: 120)]
        ];
        c.textLabel.text = labels[i.row];
        c.detailTextLabel.text = values[i.row];
    } else if (i.section == 1) {
        c.textLabel.text =
            @[ SHL(@"Default SM-DP+"), SHL(@"SM-DS address"), SHL(@"HTTP CONNECT proxy") ][i.row];
        c.detailTextLabel.text=i.row==2?([NSUserDefaults.standardUserDefaults stringForKey:@"SHHTTPProxy"]?:SHL(@"Not set")):self.card[i.row?@"discoveryServer":@"defaultServer"]?:@"";
    } else if (i.section == 2) {
        NSArray *keys = @[
            @"SHNotifyAuto", @"SHNotifyDownload", @"SHNotifyDelete", @"SHNotifySwitch", @"SHRefresh"
        ];
        c.textLabel.text = @[
            SHL(@"Automatically submit notifications"), SHL(@"Submit install notifications"),
            SHL(@"Submit delete notifications"), SHL(@"Submit switch notifications"),
            SHL(@"Request refresh after switching")
        ][i.row];
        UISwitch *s = [UISwitch new];
        s.tag = i.row;
        s.accessibilityIdentifier = keys[i.row];
        s.enabled = i.row == 0 || i.row == 4 || [SHLPA automaticNotificationsEnabled];
        NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
        s.on = [d objectForKey:keys[i.row]] ? [d boolForKey:keys[i.row]] : YES;
        [s addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged];
        c.accessoryView = s;
    } else if (i.section == 3) {
        c.textLabel.text = SHL(@"Reset entire eUICC");
        c.textLabel.textColor = UIColor.systemRedColor;
    } else {
        c.textLabel.text = SHL(@"Language");
        c.detailTextLabel.text = SHL([SHLanguage() isEqual:@"system"] ? @"Follow system"
                                     : [SHLanguage() isEqual:@"en"]   ? @"English"
                                                                      : @"Simplified Chinese");
        c.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return c;
}
- (void)processAll {
    if (self.busy || !self.items.count)
        return;
    NSArray *items = [self.items copy];
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:SHL(@"Submit all notifications?")
                         message:
                             [NSString
                                 stringWithFormat:
                                     SHL(@"Submit %lu notifications and remove each after success. Stop on the first error."),
                                     (unsigned long)items.count]
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:SHL(@"Cancel")
                                          style:UIAlertActionStyleCancel
                                        handler:nil]];
    [a addAction:[UIAlertAction
                     actionWithTitle:SHL(@"Submit")
                               style:UIAlertActionStyleDefault
                             handler:^(UIAlertAction *x) {
                                 [self run:^BOOL(NSError **e) {
                                     for (NSDictionary *n in items)
                                         if (![self.lpa processNotification:[n[@"sequence"]
                                                                                unsignedLongValue]
                                                                 removeOnly:NO
                                                                      error:e])
                                             return NO;
                                     return YES;
                                 }];
                             }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)toggle:(UISwitch *)s {
    [NSUserDefaults.standardUserDefaults setBool:s.on
                                          forKey:@[
                                              @"SHNotifyAuto", @"SHNotifyDownload",
                                              @"SHNotifyDelete", @"SHNotifySwitch", @"SHRefresh"
                                          ][s.tag]];
    [self.tableView reloadData];
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)i {
    [t deselectRowAtIndexPath:i animated:YES];
    if (self.busy)
        return;
    if (self.notificationMode) {
        if (!self.items.count)
            return;
        NSDictionary *n = self.items[i.row];
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:[NSString
                                         stringWithFormat:SHL(@"Notification #%@"), n[@"sequence"]]
                             message:[NSString stringWithFormat:@"%@\n%@", SHL(n[@"operation"]),
                                                                n[@"address"]]
                      preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction
                         actionWithTitle:SHL(@"Submit and remove")
                                   style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction *x) {
                                     [self run:^BOOL(NSError **e) {
                                         return [self.lpa
                                             processNotification:[n[@"sequence"] unsignedLongValue]
                                                      removeOnly:NO
                                                           error:e];
                                     }];
                                 }]];
        [a addAction:[UIAlertAction
                         actionWithTitle:SHL(@"Remove only")
                                   style:UIAlertActionStyleDestructive
                                 handler:^(UIAlertAction *x) {
                                     UIAlertController *c = [UIAlertController
                                         alertControllerWithTitle:
                                             SHL(@"Remove without notifying the operator?")
                                                          message:SHL(@"This cannot be undone.")
                                                   preferredStyle:UIAlertControllerStyleAlert];
                                     [c addAction:[UIAlertAction
                                                      actionWithTitle:SHL(@"Cancel")
                                                                style:UIAlertActionStyleCancel
                                                              handler:nil]];
                                     [c addAction:[UIAlertAction
                                                      actionWithTitle:SHL(@"Remove")
                                                                style:UIAlertActionStyleDestructive
                                                              handler:^(UIAlertAction *y) {
                                                                  [self run:^BOOL(NSError **e) {
                                                                      return [self.lpa
                                                                          processNotification:
                                                                              [n[@"sequence"]
                                                                                  unsignedLongValue]
                                                                                   removeOnly:YES
                                                                                        error:e];
                                                                  }];
                                                              }]];
                                     [self presentViewController:c animated:YES completion:nil];
                                 }]];
        [a addAction:[UIAlertAction actionWithTitle:SHL(@"Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
        return;
    }
    if (i.section == 0 && i.row == 7) {
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:SHL(@"APDU block size")
                             message:
                                 SHL(@"Default: 120. Change only when required for card compatibility.")
                      preferredStyle:UIAlertControllerStyleAlert];
        for (NSNumber *n in @[ @120, @240, @255 ])
            [a addAction:[UIAlertAction actionWithTitle:n.stringValue
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *x) {
                                                    [NSUserDefaults.standardUserDefaults
                                                        setInteger:n.integerValue
                                                            forKey:@"SHMSS"];
                                                    [self.tableView reloadData];
                                                }]];
        [a addAction:[UIAlertAction actionWithTitle:SHL(@"Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    } else if (i.section == 1 && i.row == 0) {
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:SHL(@"Default SM-DP+")
                             message:SHL(@"Change the server address stored on the card.")
                      preferredStyle:UIAlertControllerStyleAlert];
        [a addTextFieldWithConfigurationHandler:^(UITextField *f) {
            f.text = self.card[@"defaultServer"];
            f.autocapitalizationType = UITextAutocapitalizationTypeNone;
            f.autocorrectionType = UITextAutocorrectionTypeNo;
        }];
        [a addAction:[UIAlertAction actionWithTitle:SHL(@"Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:SHL(@"Save")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *x) {
                                                [self run:^BOOL(NSError **e) {
                                                    return [self.lpa
                                                        setDefaultServer:a.textFields[0].text ?: @""
                                                                   error:e];
                                                }];
                                            }]];
        [self presentViewController:a animated:YES completion:nil];
    } else if (i.section == 1 && i.row == 2) {
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:SHL(@"HTTP CONNECT proxy")
                             message:
                                 SHL(@"Use http://host:port without credentials. Leave blank for a direct connection. TLS verification remains enabled.")
                      preferredStyle:UIAlertControllerStyleAlert];
        [a addTextFieldWithConfigurationHandler:^(UITextField *f) {
            f.text = [NSUserDefaults.standardUserDefaults stringForKey:@"SHHTTPProxy"];
            f.autocapitalizationType = UITextAutocapitalizationTypeNone;
            f.autocorrectionType = UITextAutocorrectionTypeNo;
        }];
        [a addAction:[UIAlertAction actionWithTitle:SHL(@"Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
        [a addAction:[UIAlertAction
                         actionWithTitle:SHL(@"Save")
                                   style:UIAlertActionStyleDefault
                                 handler:^(UIAlertAction *x) {
                                     NSString *v = a.textFields[0].text ?: @"";
                                     NSURL *u = [NSURL URLWithString:v];
                                     if (v.length &&
                                         (![u.scheme.lowercaseString isEqual:@"http"] ||
                                          !u.host.length || !u.port || u.user || u.password)) {
                                         [self alert:SHL(@"Invalid proxy address.")];
                                         return;
                                     }
                                     [NSUserDefaults.standardUserDefaults setObject:v
                                                                             forKey:@"SHHTTPProxy"];
                                     [self.tableView reloadData];
                                 }]];
        [self presentViewController:a animated:YES completion:nil];
    } else if (i.section == 3) {
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:SHL(@"Reset the entire card?")
                             message:
                                 SHL(@"This removes profiles and may disconnect cellular service. Type RESET to confirm.")
                      preferredStyle:UIAlertControllerStyleAlert];
        [a addTextFieldWithConfigurationHandler:^(UITextField *f) {
            f.placeholder = @"RESET";
        }];
        [a addAction:[UIAlertAction actionWithTitle:SHL(@"Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
        [a addAction:[UIAlertAction actionWithTitle:SHL(@"Reset")
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *x) {
                                                [self run:^BOOL(NSError **e) {
                                                    return [self.lpa
                                                           resetCard:self.card[@"eid"]
                                                        confirmation:a.textFields[0].text ?: @""
                                                               error:e];
                                                }];
                                            }]];
        [self presentViewController:a animated:YES completion:nil];
    } else if (i.section == 4) {
        UIAlertController *a = [UIAlertController
            alertControllerWithTitle:SHL(@"Language")
                             message:
                                 SHL(@"Interface language changes immediately. Logs remain in English.")
                      preferredStyle:UIAlertControllerStyleAlert];
        NSArray *names = @[ SHL(@"Follow system"), @"English", @"简体中文" ];
        NSArray *codes = @[ @"system", @"en", @"zh-Hans" ];
        for (NSUInteger j = 0; j < codes.count; j++)
            [a addAction:[UIAlertAction actionWithTitle:names[j]
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *x) {
                                                    SHSetLanguage(codes[j]);
                                                }]];
        [a addAction:[UIAlertAction actionWithTitle:SHL(@"Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
        [self presentViewController:a animated:YES completion:nil];
    } else if (i.section < 2) {
        UITableViewCell *c = [t cellForRowAtIndexPath:i];
        UIPasteboard.generalPasteboard.string = c.detailTextLabel.text;
        [self alert:SHL(@"Copied")];
    }
}
@end
