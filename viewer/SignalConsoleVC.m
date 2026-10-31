#import "SignalConsoleVC.h"
#import "SignalCodec.h"
#import "Localization.h"
#import "TraceLog.h"
#import "../shared/Wire.h"
@interface SHSignalConsoleVC ()
@property(nonatomic, strong) SHLPA *lpa;
@property(nonatomic, strong) NSOperationQueue *queue;
@property(nonatomic, strong) UISegmentedControl *mode;
@property(nonatomic, strong) UITextView *input;
@property(nonatomic, strong) UITextView *output;
@property(nonatomic, strong) UISwitch *stop;
@property(nonatomic, strong) UIButton *send;
@property(nonatomic, strong) UIButton *example;
@property(nonatomic, strong) UILabel *help;
@property(nonatomic) BOOL busy;
@property(nonatomic) UIBackgroundTaskIdentifier background;
@end
@implementation SHSignalConsoleVC
- (instancetype)initWithLPA:(SHLPA *)lpa queue:(NSOperationQueue *)queue {
    if ((self = [super init])) {
        _lpa = lpa;
        _queue = queue;
        _background = UIBackgroundTaskInvalid;
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SHL(@"Signal console");
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [self.view addSubview:scroll];
    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 14;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [scroll.trailingAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor
                                            constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor
                                             constant:-20],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor
                                           constant:-30],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-40]
    ]];
    self.mode = [[UISegmentedControl alloc] initWithItems:@[ SHL(@"Raw APDU"), @"ES10 DER" ]];
    self.mode.selectedSegmentIndex = 0;
    [self.mode addTarget:self
                  action:@selector(modeChanged)
        forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:self.mode];
    self.help = [UILabel new];
    self.help.numberOfLines = 0;
    self.help.font = [UIFont systemFontOfSize:14];
    [stack addArrangedSubview:self.help];
    self.input = [self textBox];
    self.input.editable = YES;
    self.input.accessibilityLabel = SHL(@"Signal input");
    self.input.autocorrectionType = UITextAutocorrectionTypeNo;
    self.input.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.input.smartQuotesType = UITextSmartQuotesTypeNo;
    self.input.smartDashesType = UITextSmartDashesTypeNo;
    UIToolbar *toolbar = [UIToolbar new];
    [toolbar sizeToFit];
    toolbar.items = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                      target:nil
                                                      action:nil],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(endEditing)]
    ];
    self.input.inputAccessoryView = toolbar;
    [stack addArrangedSubview:self.input];
    [self.input.heightAnchor constraintEqualToConstant:180].active = YES;
    self.example = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.example setTitle:SHL(@"Fill Get EID example") forState:UIControlStateNormal];
    [self.example addTarget:self
                     action:@selector(fillExample)
           forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:self.example];
    self.stop = [UISwitch new];
    self.stop.on = YES;
    UILabel *stopLabel = [UILabel new];
    stopLabel.text = SHL(@"Stop batch on SW other than 9000");
    stopLabel.numberOfLines = 0;
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:@[ stopLabel, self.stop ]];
    row.spacing = 10;
    [stack addArrangedSubview:row];
    self.send = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.send setTitle:SHL(@"Send signal") forState:UIControlStateNormal];
    self.send.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [self.send addTarget:self
                  action:@selector(confirmSend)
        forControlEvents:UIControlEventTouchUpInside];
    [stack addArrangedSubview:self.send];
    self.output = [self textBox];
    self.output.editable = NO;
    self.output.accessibilityLabel = SHL(@"Signal response");
    [stack addArrangedSubview:self.output];
    [self.output.heightAnchor constraintEqualToConstant:220].active = YES;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:SHL(@"Copy response")
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(copyResponse)];
    [self modeChanged];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboard:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
}
- (UITextView *)textBox {
    UITextView *v = [UITextView new];
    v.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    v.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    v.layer.cornerRadius = 12;
    v.textContainerInset = UIEdgeInsetsMake(12, 10, 12, 10);
    return v;
}
- (void)keyboard:(NSNotification *)note {
    CGRect frame = [self.view convertRect:[note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue]
                                 fromView:nil];
    UIScrollView *scroll = (UIScrollView *)self.view.subviews.firstObject;
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(frame) -
                                 self.view.safeAreaInsets.bottom);
    scroll.contentInset = UIEdgeInsetsMake(0, 0, overlap, 0);
    scroll.scrollIndicatorInsets = scroll.contentInset;
}
- (void)modeChanged {
    self.help.text = SHL(
        self.mode.selectedSegmentIndex == 0
            ? @"One short APDU per line, up to 64. Hex and spaces only; lines starting with # are comments. Use CLA 00/80; the app binds the channel. Responses are raw: no automatic 61xx/6Cxx retry."
            : @"Enter one complete DER TLV. The app sends STORE DATA blocks using the configured MSS and collects 61xx responses. The trace shows every APDU and status word.");
    self.stop.enabled = self.mode.selectedSegmentIndex == 0;
}
- (void)fillExample {
    if (self.busy)
        return;
    self.input.text = self.mode.selectedSegmentIndex == 0 ? @"80 E2 91 00 06 BF 3E 03 5C 01 5A"
                                                          : @"BF 3E 03 5C 01 5A";
}
- (void)endEditing {
    [self.view endEditing:YES];
}
- (void)copyResponse {
    UIPasteboard.generalPasteboard.string = self.output.text;
}
- (void)alert:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:SHL(@"Signal console")
                                                               message:message
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:SHL(@"OK")
                                          style:UIAlertActionStyleDefault
                                        handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}
- (NSData *)decode:(NSString *)text limit:(NSUInteger)limit error:(NSError **)error {
    NSMutableData *buffer = [NSMutableData dataWithLength:limit];
    size_t length = 0;
    const char *issue = SHDecodeHex(text.UTF8String, buffer.mutableBytes, limit, &length);
    if (issue) {
        if (error)
            *error = SHError(20, @(issue));
        return nil;
    }
    buffer.length = length;
    return buffer;
}
- (void)confirmSend {
    if (self.busy)
        return;
    [self endEditing];
    NSError *error = nil;
    BOOL der = self.mode.selectedSegmentIndex == 1;
    NSMutableArray<NSData *> *commands = [NSMutableArray array];
    NSData *request = nil;
    if (der) {
        NSInteger mss = [NSUserDefaults.standardUserDefaults integerForKey:@"SHMSS"];
        if (mss < 6 || mss > 255)
            mss = 120;
        request = [self decode:self.input.text limit:65536 error:&error];
        if (request) {
            const char *issue = SHValidateDER(request.bytes, request.length, (size_t)mss * 256);
            if (issue)
                error = SHError(20, @(issue));
        }
    } else {
        for (NSString *line in [self.input.text
                 componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
            NSString *trim =
                [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (!trim.length || [trim hasPrefix:@"#"])
                continue;
            NSData *d = [self decode:trim limit:261 error:&error];
            if (!d)
                break;
            const char *issue = SHValidateAPDU(d.bytes, d.length);
            if (issue) {
                error = SHError(20, @(issue));
                break;
            }
            [commands addObject:d];
            if (commands.count > 64) {
                error = SHError(20, @"Enter between 1 and 64 APDUs.");
                break;
            }
        }
        if (!error && !commands.count)
            error = SHError(20, @"Enter a signal before sending.");
    }
    if (error) {
        [self alert:error.localizedDescription];
        return;
    }
    UIAlertController *a = [UIAlertController
        alertControllerWithTitle:SHL(@"Send custom signal?")
                         message:
                             SHL(@"Commands run on the current removable eUICC's ISD-R. They can change or erase profiles. Confirm the bytes before sending. The app will close the channel afterward.")
                  preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:SHL(@"Cancel")
                                          style:UIAlertActionStyleCancel
                                        handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:SHL(@"Send")
                                          style:UIAlertActionStyleDestructive
                                        handler:^(UIAlertAction *action) {
                                            [self execute:commands der:request stop:self.stop.on];
                                        }]];
    [self presentViewController:a animated:YES completion:nil];
}
- (void)working:(BOOL)busy {
    self.busy = busy;
    self.input.editable = !busy;
    self.mode.enabled = !busy;
    self.send.enabled = !busy;
    self.example.enabled = !busy;
    self.stop.enabled = !busy && self.mode.selectedSegmentIndex == 0;
    self.navigationItem.hidesBackButton = busy;
    self.navigationController.interactivePopGestureRecognizer.enabled = !busy;
    self.tabBarController.tabBar.userInteractionEnabled = !busy;
    self.navigationItem.prompt = busy ? SHL(@"Working. Keep the app in the foreground…") : nil;
    UIApplication.sharedApplication.idleTimerDisabled = busy;
    if (busy)
        self.background =
            [UIApplication.sharedApplication beginBackgroundTaskWithExpirationHandler:^{
                [[SHTraceLog shared]
                    event:@"Custom signal background time is ending. Return to the app."];
            }];
    else if (self.background != UIBackgroundTaskInvalid) {
        [UIApplication.sharedApplication endBackgroundTask:self.background];
        self.background = UIBackgroundTaskInvalid;
    }
}
- (void)execute:(NSArray *)commands der:(NSData *)der stop:(BOOL)stop {
    [self working:YES];
    self.output.text = @"";
    [self.queue addOperationWithBlock:^{
        NSError *error = nil;
        NSMutableString *output = [NSMutableString string];
        if (der) {
            NSData *response = [self.lpa sendDER:der error:&error];
            if (response)
                [output
                    appendFormat:@"ES10 DER RESPONSE (%lu bytes)\n%@\nStatus words: see Logs.\n",
                                 (unsigned long)response.length, SHHex(response)];
        } else {
            NSArray *responses = [self.lpa sendAPDUs:commands stopOnStatus:stop error:&error];
            NSUInteger index = 0;
            for (NSDictionary *r in responses)
                [output appendFormat:@"#%lu\nTX %@\nRX %@\nSW %@\n\n", (unsigned long)++index,
                                     r[@"tx"], r[@"rx"], r[@"sw"]];
        }
        if (error) {
            [[SHTraceLog shared] error:error];
            [output
                appendString:@"INCOMPLETE: see Logs. Commands are never retried automatically.\n"];
        } else
            [[SHTraceLog shared] event:@"Custom signal operation completed."];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self working:NO];
            self.output.text = output;
            if (error)
                [self alert:error.localizedDescription];
        });
    }];
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}
@end
