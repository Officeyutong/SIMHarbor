#import "../shared/JSONFoundation.h"
#import "FirmwareReportVC.h"
#import "Bridge.h"
#import "Localization.h"
@interface SHFirmwareReportVC ()
@property(nonatomic, strong) NSOperationQueue *queue;
@property(nonatomic, strong) UITextView *text;
@property(nonatomic) BOOL loading;
@end
@implementation SHFirmwareReportVC
- (instancetype)initWithQueue:(NSOperationQueue *)queue {
    if ((self = [super init]))
        _queue = queue;
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SHL(@"Firmware resolver");
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.text = [[UITextView alloc] initWithFrame:self.view.bounds];
    self.text.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.text.editable = NO;
    self.text.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.text.textContainerInset = UIEdgeInsetsMake(18, 14, 30, 14);
    [self.view addSubview:self.text];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                      target:self
                                                      action:@selector(loadReport)],
        [[UIBarButtonItem alloc] initWithTitle:SHL(@"Copy")
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(copyReport)]
    ];
    [self loadReport];
}
- (void)loadReport {
    if (self.loading)
        return;
    self.loading = YES;
    self.navigationItem.rightBarButtonItems[0].enabled = NO;
    [self.queue addOperationWithBlock:^{
        NSError *error = nil;
        auto reply = [[SHBridge shared] request:shjson::Request::make(shjson::Operation::Resolver)
                                          error:&error];
        auto report = shjson::body<shjson::ResolverReply>(reply);
        NSString *body = report ? SHString(shjson::dump(shjson::JSON(report->report), true))
                                : error.localizedDescription;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.loading = NO;
            self.navigationItem.rightBarButtonItems[0].enabled = YES;
            self.text.text = [NSString
                stringWithFormat:
                    @"%@\n\n%@",
                    SHL(@"Compatibility is detected at runtime from signatures, instructions and live objects. Device models, iOS versions and UUIDs are not allowlisted."),
                    body ?: SHL(@"Read failed")];
        });
    }];
}
- (void)copyReport {
    UIPasteboard.generalPasteboard.string = self.text.text;
}
@end
