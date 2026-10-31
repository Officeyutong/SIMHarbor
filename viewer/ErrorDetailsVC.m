#import "ErrorDetailsVC.h"
#import "ErrorDiagnostics.h"
#import "Localization.h"

static NSError *SHLatestOperationError;
static NSString *const SHErrorChanged = @"SHErrorDetailsChanged";
@interface SHErrorDetailsVC ()
@property(nonatomic, strong) UITextView *textView;
@end

@implementation SHErrorDetailsVC
+ (void)showError:(NSError *)error from:(UIViewController *)controller {
    NSAssert(NSThread.isMainThread, @"Present errors on the main thread");
    SHLatestOperationError = error;
    [[NSNotificationCenter defaultCenter] postNotificationName:SHErrorChanged object:nil];
    UITabBarController *tabs = controller.tabBarController;
    for (UINavigationController *nav in tabs.viewControllers) {
        if ([nav isKindOfClass:UINavigationController.class] &&
            [nav.viewControllers.firstObject isKindOfClass:self]) {
            tabs.selectedViewController = nav;
            [nav popToRootViewControllerAnimated:NO];
            break;
        }
    }
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = SHL(@"Error details");
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.textView = [UITextView new];
    self.textView.editable = NO;
    self.textView.selectable = YES;
    self.textView.adjustsFontForContentSizeCategory = YES;
    self.textView.backgroundColor = UIColor.systemBackgroundColor;
    self.textView.textContainerInset = UIEdgeInsetsMake(18, 16, 28, 16);
    self.textView.accessibilityIdentifier = @"error.details.text";
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.textView];
    [NSLayoutConstraint activateConstraints:@[
        [self.textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.textView.bottomAnchor
            constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]
    ]];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:SHL(@"Copy")
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(copyError)],
        [[UIBarButtonItem alloc] initWithTitle:SHL(@"Clear")
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(clearError)]
    ];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(update)
                                                 name:SHErrorChanged
                                               object:nil];
    [self update];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self update];
}
- (void)update {
    NSString *summary = SHLatestOperationError ? SHErrorSummary(SHLatestOperationError)
                                               : SHL(@"No errors recorded in this session.");
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc]
        initWithString:summary
            attributes:@{
                NSFontAttributeName : [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline],
                NSForegroundColorAttributeName : UIColor.labelColor
            }];
    if (SHLatestOperationError) {
        [text appendAttributedString:
                  [[NSAttributedString alloc]
                      initWithString:[@"\n\n" stringByAppendingString:SHErrorReport(
                                                                          SHLatestOperationError)]
                          attributes:@{
                              NSFontAttributeName :
                                  [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular],
                              NSForegroundColorAttributeName : UIColor.labelColor
                          }]];
    }
    self.textView.attributedText = text;
    self.tabBarItem.badgeValue = nil;
    self.navigationController.tabBarItem.badgeValue = SHLatestOperationError ? @"1" : nil;
}
- (void)copyError {
    UIPasteboard.generalPasteboard.string = self.textView.text;
}
- (void)clearError {
    SHLatestOperationError = nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:SHErrorChanged object:nil];
}
@end
