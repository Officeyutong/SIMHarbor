#import "AboutVC.h"
#import "FirmwareReportVC.h"
#import "DocumentsVC.h"
#import "TraceLog.h"
#import "SignalConsoleVC.h"
#import "Localization.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <PhotosUI/PhotosUI.h>
#import "QRDecoder.h"
#import "Bridge.h"
#import "LPAEngine.h"
#import "ManagementVC.h"
static UIColor*Accent(void){return [UIColor colorWithRed:0.02 green:0.55 blue:0.56 alpha:1];}
static void Record(NSString*s){[[SHTraceLog shared]event:SHEnglish(s)];}


@interface ScannerVC:UIViewController<AVCaptureMetadataOutputObjectsDelegate>
@property(nonatomic,strong) AVCaptureSession*session;
@property(nonatomic,strong) AVCaptureVideoPreviewLayer*preview;
@property(nonatomic,copy) void(^result)(NSString*);
@property(nonatomic) BOOL delivered;
@property(atomic) BOOL closed;
@property(nonatomic,strong) AVCaptureDevice *camera;
@property(nonatomic,strong) UIView *focusIndicator;
@property(nonatomic) NSUInteger focusGeneration;
@property(nonatomic,strong) dispatch_queue_t captureQueue;
@property(nonatomic,strong) UILabel*hint;
@end
@implementation ScannerVC
- (void)viewDidLoad{[super viewDidLoad];self.captureQueue=dispatch_queue_create("com.simharbor.camera",DISPATCH_QUEUE_SERIAL);self.title=SHL(@"Scan activation code");self.view.backgroundColor=UIColor.blackColor;self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];self.hint=[UILabel new];self.hint.text=SHL(@"Tap the QR code to focus. Move farther away if blurred.");self.hint.textColor=UIColor.whiteColor;self.hint.textAlignment=NSTextAlignmentCenter;self.hint.numberOfLines=0;self.hint.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:self.hint];[NSLayoutConstraint activateConstraints:@[[self.hint.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:24],[self.hint.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-24],[self.hint.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-60]]];
 [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL allowed){dispatch_async(dispatch_get_main_queue(),^{if(self.closed)return;if(!allowed){self.hint.text=SHL(@"Allow camera access in Settings, or enter the activation code manually.");return;}[self start];});}];}
- (void)start{self.session=[AVCaptureSession new];NSError*e=nil;AVCaptureDevice*camera=[AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:AVCaptureDevicePositionBack]?:[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];AVCaptureDeviceInput*input=[AVCaptureDeviceInput deviceInputWithDevice:camera error:&e];AVCaptureMetadataOutput*out=[AVCaptureMetadataOutput new];if(!input||![self.session canAddInput:input]||![self.session canAddOutput:out]){self.hint.text=SHL(@"Unable to start the camera. Enter the code manually.");return;}self.camera=camera;[self.session addInput:input];[self.session addOutput:out];[out setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];out.metadataObjectTypes=@[AVMetadataObjectTypeQRCode];self.preview=[AVCaptureVideoPreviewLayer layerWithSession:self.session];self.preview.videoGravity=AVLayerVideoGravityResizeAspectFill;[self.view.layer insertSublayer:self.preview atIndex:0];self.preview.frame=self.view.bounds;
 UIView*frame=[UIView new];frame.userInteractionEnabled=NO;frame.layer.borderColor=[UIColor colorWithRed:0.2 green:0.95 blue:0.85 alpha:1].CGColor;frame.layer.borderWidth=2;frame.layer.cornerRadius=24;frame.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:frame];[NSLayoutConstraint activateConstraints:@[[frame.widthAnchor constraintEqualToConstant:260],[frame.heightAnchor constraintEqualToConstant:260],[frame.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],[frame.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:-30]]];self.focusIndicator=[[UIView alloc]initWithFrame:CGRectMake(0,0,78,78)];self.focusIndicator.userInteractionEnabled=NO;self.focusIndicator.layer.borderColor=UIColor.systemYellowColor.CGColor;self.focusIndicator.layer.borderWidth=2;self.focusIndicator.layer.cornerRadius=10;self.focusIndicator.alpha=0;[self.view addSubview:self.focusIndicator];
 UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tapToFocus:)];tap.cancelsTouchesInView=NO;[self.view addGestureRecognizer:tap];
 [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(subjectAreaChanged:) name:AVCaptureDeviceSubjectAreaDidChangeNotification object:camera];
 dispatch_async(self.captureQueue,^{[self configureFocusAtDevicePoint:CGPointMake(.5,.5) continuous:YES];if(!self.closed)[self.session startRunning];});}
- (void)configureFocusAtDevicePoint:(CGPoint)point continuous:(BOOL)continuous{
 AVCaptureDevice *camera=self.camera;if(self.closed||!camera)return;
 NSError *error=nil;if(![camera lockForConfiguration:&error]){dispatch_async(dispatch_get_main_queue(),^{if(!self.closed)self.hint.text=SHL(@"Unable to focus. Tap to try again.");});return;}
 AVCaptureFocusMode focus=continuous?AVCaptureFocusModeContinuousAutoFocus:AVCaptureFocusModeAutoFocus;
 if(![camera isFocusModeSupported:focus])focus=AVCaptureFocusModeContinuousAutoFocus;
 if([camera isFocusModeSupported:focus]){if(camera.focusPointOfInterestSupported)camera.focusPointOfInterest=point;camera.focusMode=focus;}
 AVCaptureExposureMode exposure=continuous?AVCaptureExposureModeContinuousAutoExposure:AVCaptureExposureModeAutoExpose;
 if(![camera isExposureModeSupported:exposure])exposure=AVCaptureExposureModeContinuousAutoExposure;
 if([camera isExposureModeSupported:exposure]){if(camera.exposurePointOfInterestSupported)camera.exposurePointOfInterest=point;camera.exposureMode=exposure;}
 if(camera.autoFocusRangeRestrictionSupported)camera.autoFocusRangeRestriction=AVCaptureAutoFocusRangeRestrictionNone;
 camera.subjectAreaChangeMonitoringEnabled=!continuous;[camera unlockForConfiguration];
}
- (void)focusAtViewPoint:(CGPoint)point{
 if(self.closed||self.delivered||!self.camera||!CGRectContainsPoint(self.preview.frame,point))return;
 CGPoint devicePoint=[self.preview captureDevicePointOfInterestForPoint:point];
 NSUInteger generation=++self.focusGeneration;[self.focusIndicator.layer removeAllAnimations];self.focusIndicator.center=point;self.focusIndicator.alpha=1;self.focusIndicator.transform=CGAffineTransformMakeScale(1.25,1.25);
 [UIView animateWithDuration:.18 animations:^{self.focusIndicator.transform=CGAffineTransformIdentity;}];
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{if(!self.closed&&generation==self.focusGeneration)[UIView animateWithDuration:.25 animations:^{self.focusIndicator.alpha=0;}];});
 self.hint.text=SHL(@"Tap the QR code to focus. Move farther away if blurred.");
 dispatch_async(self.captureQueue,^{[self configureFocusAtDevicePoint:devicePoint continuous:NO];});
}
- (void)tapToFocus:(UITapGestureRecognizer*)gesture{if(gesture.state==UIGestureRecognizerStateEnded)[self focusAtViewPoint:[gesture locationInView:self.view]];}
- (void)subjectAreaChanged:(NSNotification*)notification{dispatch_async(self.captureQueue,^{[self configureFocusAtDevicePoint:CGPointMake(.5,.5) continuous:YES];});}
- (void)viewDidLayoutSubviews{[super viewDidLayoutSubviews];self.preview.frame=self.view.bounds;}
- (void)viewDidDisappear:(BOOL)a{[super viewDidDisappear:a];self.closed=YES;[[NSNotificationCenter defaultCenter]removeObserver:self name:AVCaptureDeviceSubjectAreaDidChangeNotification object:self.camera];dispatch_async(self.captureQueue,^{[self.session stopRunning];});}
- (void)finishWithCode:(NSString*)code{
 if(self.delivered||self.closed)return;
 self.delivered=YES;
 void(^result)(NSString*)=self.result;self.result=nil;
 UIViewController *container=self.navigationController?:self;
 [container dismissViewControllerAnimated:YES completion:^{if(result)result(code);}];
}
- (void)cancel{[self finishWithCode:nil];}
- (void)metadataOutput:(AVCaptureMetadataOutput*)out didOutputMetadataObjects:(NSArray*)objects fromConnection:(AVCaptureConnection*)connection{
 if(self.delivered||self.closed)return;
 for(AVMetadataMachineReadableCodeObject *object in objects){
  NSString *code=[SHQRDecoder activationCodeFromPayload:object.stringValue];
  if(code){[self finishWithCode:code];return;}
 }
 if(objects.count)self.hint.text=SHL(@"This is not an eSIM activation QR code. Scan the code provided by your operator.");
}
@end

@interface LogsVC:UIViewController
@property(nonatomic,strong) UITextView*text;
@end
@implementation LogsVC
- (void)viewDidLoad{[super viewDidLoad];self.title=SHL(@"Operation log");self.view.backgroundColor=UIColor.systemBackgroundColor;self.text=[[UITextView alloc]initWithFrame:self.view.bounds];self.text.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;self.text.editable=NO;self.text.font=[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];[self.view addSubview:self.text];self.navigationItem.rightBarButtonItems=@[
 [[UIBarButtonItem alloc]initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(shareLog)],
 [[UIBarButtonItem alloc]initWithTitle:SHL(@"Copy") style:UIBarButtonItemStylePlain target:self action:@selector(copyLog)],
 [[UIBarButtonItem alloc]initWithTitle:SHL(@"Clear") style:UIBarButtonItemStylePlain target:self action:@selector(clearLog)]];
 [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(update) name:@"SHLog" object:nil];[self update];}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];self.text.text=[[SHTraceLog shared]text];}
- (void)update{if(self.isViewLoaded&&self.view.window)self.text.text=[[SHTraceLog shared]text];}
- (void)copyLog{UIPasteboard.generalPasteboard.string=[[SHTraceLog shared]text];}
- (void)clearLog{[[SHTraceLog shared]clear];}
- (void)shareLog{NSString*text=[[SHTraceLog shared]text];NSURL*file=[NSURL fileURLWithPath:[NSTemporaryDirectory()stringByAppendingPathComponent:[NSString stringWithFormat:@"SIMHarbor-%@.log",NSUUID.UUID.UUIDString]]];NSError*e=nil;if(![text writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:&e]){[[SHTraceLog shared]error:e];return;}UIActivityViewController*sheet=[[UIActivityViewController alloc]initWithActivityItems:@[file]applicationActivities:nil];sheet.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItems[0];sheet.completionWithItemsHandler=^(UIActivityType type,BOOL completed,NSArray*items,NSError*error){[[NSFileManager defaultManager]removeItemAtURL:file error:nil];};[self presentViewController:sheet animated:YES completion:nil];}
- (void)dealloc{[[NSNotificationCenter defaultCenter]removeObserver:self];}
@end

@interface RootVC:UITableViewController<PHPickerViewControllerDelegate>
@property(nonatomic,strong) SHLPA*lpa;
@property(nonatomic,strong) NSOperationQueue*queue;
@property(nonatomic,strong) NSDictionary*card;
@property(nonatomic,strong) UILabel*statusLabel;
@property(nonatomic,strong) UILabel*cardLabel;
@property(nonatomic,strong) UIActivityIndicatorView*spinner;
@property(nonatomic,strong) UIButton*scanButton;
@property(nonatomic,strong) UIButton*codeButton;
@property(nonatomic) BOOL busy;
@property(nonatomic,copy) NSString *pendingActivationCode;
@property(nonatomic) UIBackgroundTaskIdentifier background;
@end
@implementation RootVC
- (instancetype)init{return [super initWithStyle:UITableViewStyleInsetGrouped];}
- (void)viewDidLoad{[super viewDidLoad];self.title=SHL(@"SIMHarbor");self.navigationController.navigationBar.prefersLargeTitles=YES;self.view.tintColor=Accent();self.tableView.backgroundColor=UIColor.systemGroupedBackgroundColor;self.tableView.rowHeight=90;self.lpa=[SHLPA new];self.queue=[NSOperationQueue new];self.queue.maxConcurrentOperationCount=1;self.background=UIBackgroundTaskInvalid;
 __weak RootVC*weak=self;self.lpa.progress=^(NSString*s){dispatch_async(dispatch_get_main_queue(),^{weak.statusLabel.text=s;});};
 self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithImage:[UIImage systemImageNamed:@"info.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(info)];self.refreshControl=[UIRefreshControl new];[self.refreshControl addTarget:self action:@selector(refreshCard) forControlEvents:UIControlEventValueChanged];
 UIView*header=[[UIView alloc]initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,242)];UIView*panel=[UIView new];panel.backgroundColor=[UIColor colorWithRed:0.025 green:0.17 blue:0.23 alpha:1];panel.layer.cornerRadius=24;panel.translatesAutoresizingMaskIntoConstraints=NO;[header addSubview:panel];
 UIImageView*icon=[[UIImageView alloc]initWithImage:[UIImage imageNamed:@"Icon60@3x.png"]];icon.layer.cornerRadius=13;icon.clipsToBounds=YES;icon.translatesAutoresizingMaskIntoConstraints=NO;[panel addSubview:icon];
 UILabel*brand=[UILabel new];brand.text=@"SIMHarbor";brand.textColor=UIColor.whiteColor;brand.font=[UIFont systemFontOfSize:23 weight:UIFontWeightBold];brand.translatesAutoresizingMaskIntoConstraints=NO;[panel addSubview:brand];
 self.cardLabel=[UILabel new];self.cardLabel.text=SHL(@"Removable eUICC · Waiting for connection");self.cardLabel.textColor=[UIColor colorWithWhite:0.85 alpha:1];self.cardLabel.font=[UIFont systemFontOfSize:13 weight:UIFontWeightMedium];self.cardLabel.translatesAutoresizingMaskIntoConstraints=NO;[panel addSubview:self.cardLabel];
 self.statusLabel=[UILabel new];self.statusLabel.text=SHL(@"Connecting to the card service…");self.statusLabel.textColor=[UIColor colorWithRed:0.35 green:0.95 blue:0.82 alpha:1];self.statusLabel.font=[UIFont systemFontOfSize:13];self.statusLabel.numberOfLines=2;self.statusLabel.translatesAutoresizingMaskIntoConstraints=NO;[panel addSubview:self.statusLabel];
 self.spinner=[[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];self.spinner.color=UIColor.whiteColor;self.spinner.translatesAutoresizingMaskIntoConstraints=NO;[panel addSubview:self.spinner];
 self.scanButton=[self action:SHL(@" Scan QR") symbol:@"qrcode.viewfinder" selector:@selector(scan)];self.codeButton=[self action:SHL(@" Enter code") symbol:@"plus" selector:@selector(manual)];UIStackView*actions=[[UIStackView alloc]initWithArrangedSubviews:@[self.scanButton,self.codeButton]];actions.axis=UILayoutConstraintAxisHorizontal;actions.spacing=12;actions.distribution=UIStackViewDistributionFillEqually;actions.translatesAutoresizingMaskIntoConstraints=NO;[header addSubview:actions];
 [NSLayoutConstraint activateConstraints:@[[panel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],[panel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],[panel.topAnchor constraintEqualToAnchor:header.topAnchor constant:8],[panel.heightAnchor constraintEqualToConstant:150],[icon.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:20],[icon.topAnchor constraintEqualToAnchor:panel.topAnchor constant:20],[icon.widthAnchor constraintEqualToConstant:52],[icon.heightAnchor constraintEqualToConstant:52],[brand.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:14],[brand.topAnchor constraintEqualToAnchor:icon.topAnchor constant:1],[self.cardLabel.leadingAnchor constraintEqualToAnchor:brand.leadingAnchor],[self.cardLabel.topAnchor constraintEqualToAnchor:brand.bottomAnchor constant:5],[self.statusLabel.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:20],[self.statusLabel.trailingAnchor constraintEqualToAnchor:self.spinner.leadingAnchor constant:-8],[self.statusLabel.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-18],[self.spinner.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-20],[self.spinner.centerYAnchor constraintEqualToAnchor:self.statusLabel.centerYAnchor],[actions.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor],[actions.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],[actions.topAnchor constraintEqualToAnchor:panel.bottomAnchor constant:16],[actions.heightAnchor constraintEqualToConstant:48]]];self.tableView.tableHeaderView=header;
 [[SHBridge shared]start];dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{[weak refreshCard];});}
- (UIButton*)action:(NSString*)title symbol:(NSString*)symbol selector:(SEL)sel{UIButton*b=[UIButton buttonWithType:UIButtonTypeSystem];b.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;b.layer.cornerRadius=15;b.titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];[b setTitle:title forState:UIControlStateNormal];[b setImage:[UIImage systemImageNamed:symbol]forState:UIControlStateNormal];[b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];return b;}
- (void)setWorking:(BOOL)b{self.busy=b;self.scanButton.enabled=!b;self.codeButton.enabled=!b;self.tabBarController.tabBar.userInteractionEnabled=!b;if(b){[self.spinner startAnimating];UIApplication.sharedApplication.idleTimerDisabled=YES;self.background=[UIApplication.sharedApplication beginBackgroundTaskWithExpirationHandler:^{Record(SHL(@"Background time is ending. Return to the app."));}];}else{[self.spinner stopAnimating];UIApplication.sharedApplication.idleTimerDisabled=NO;[self.refreshControl endRefreshing];if(self.background!=UIBackgroundTaskInvalid){[UIApplication.sharedApplication endBackgroundTask:self.background];self.background=UIBackgroundTaskInvalid;}}[self.tableView reloadData];if(!b)dispatch_async(dispatch_get_main_queue(),^{[self presentPendingActivationCode];});}
- (void)message:(NSString*)title detail:(NSString*)text{UIAlertController*a=[UIAlertController alertControllerWithTitle:title message:text preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:SHL(@"OK") style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];}
- (void)refreshCard{if(self.busy){[self.refreshControl endRefreshing];return;}[self setWorking:YES];[self.queue addOperationWithBlock:^{NSError*e=nil;NSDictionary*r=[self.lpa readCard:&e];dispatch_async(dispatch_get_main_queue(),^{[self setWorking:NO];if(r){self.card=r;self.cardLabel.text=[NSString stringWithFormat:SHL(@"Removable eUICC · %lu profiles"),(unsigned long)[r[@"profiles"]count]];self.statusLabel.text=SHL(@"Connected · Pull to refresh");Record(SHL(@"Profile list updated."));[self.tableView reloadData];}else{self.statusLabel.text=e.localizedDescription;[[SHTraceLog shared]error:e];}});}];}
- (NSInteger)numberOfSectionsInTableView:(UITableView*)table{return 1;}
- (NSInteger)tableView:(UITableView*)t numberOfRowsInSection:(NSInteger)s{return [self.card[@"profiles"]count]?:1;}
- (NSString*)tableView:(UITableView*)t titleForHeaderInSection:(NSInteger)s{return SHL(@"Profiles on the card");}
- (NSString*)tableView:(UITableView*)t titleForFooterInSection:(NSInteger)s{return SHL(@"Downloaded profiles remain disabled. Deletion permanently removes the profile from the card.");}
- (UITableViewCell*)tableView:(UITableView*)t cellForRowAtIndexPath:(NSIndexPath*)i{UITableViewCell*c=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];NSArray*items=self.card[@"profiles"];if(!items.count){c.textLabel.text=self.card?SHL(@"No profiles on this card"):SHL(@"Pull to read the card");c.detailTextLabel.text=SHL(@"Scan a QR code or enter an activation code to add a profile");c.imageView.image=[UIImage systemImageNamed:@"simcard"];c.selectionStyle=UITableViewCellSelectionStyleNone;return c;}NSDictionary*p=items[i.row];c.textLabel.text=p[@"name"];c.textLabel.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];NSString*iccid=p[@"iccid"];NSString*tail=iccid.length>6?[iccid substringFromIndex:iccid.length-6]:iccid;c.detailTextLabel.text=[NSString stringWithFormat:SHL(@"%@ · Ending in %@\n%@"),p[@"provider"],tail,[p[@"enabled"]boolValue]?SHL(@"Enabled"):SHL(@"Disabled")];c.detailTextLabel.numberOfLines=2;c.detailTextLabel.textColor=UIColor.secondaryLabelColor;c.imageView.image=[UIImage systemImageNamed:[p[@"enabled"]boolValue]?@"simcard.fill":@"simcard"];c.imageView.tintColor=Accent();c.accessoryType=UITableViewCellAccessoryDisclosureIndicator;c.selectionStyle=self.busy?UITableViewCellSelectionStyleNone:UITableViewCellSelectionStyleDefault;return c;}
- (void)tableView:(UITableView*)t didSelectRowAtIndexPath:(NSIndexPath*)i{[t deselectRowAtIndexPath:i animated:YES];if(self.busy||![self.card[@"profiles"]count])return;NSDictionary*p=self.card[@"profiles"][i.row];UIAlertController*a=[UIAlertController alertControllerWithTitle:p[@"name"] message:[NSString stringWithFormat:@"%@\nICCID %@\n%@",p[@"provider"],p[@"iccid"],[p[@"enabled"]boolValue]?SHL(@"Enabled. Disable this profile before deleting it."):SHL(@"Disabled")] preferredStyle:UIAlertControllerStyleActionSheet];[a addAction:[UIAlertAction actionWithTitle:[p[@"enabled"]boolValue]?SHL(@"Disable this profile"):SHL(@"Enable this profile") style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){[self confirmState:p];}]];[a addAction:[UIAlertAction actionWithTitle:SHL(@"Rename profile") style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){[self renameProfileUI:p];}]];if(![p[@"enabled"]boolValue])[a addAction:[UIAlertAction actionWithTitle:SHL(@"Delete this eSIM") style:UIAlertActionStyleDestructive handler:^(UIAlertAction*x){[self confirmDelete:p];}]];[a addAction:[UIAlertAction actionWithTitle:SHL(@"Copy ICCID") style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){UIPasteboard.generalPasteboard.string=p[@"iccid"];}]];[a addAction:[UIAlertAction actionWithTitle:SHL(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.sourceView=[t cellForRowAtIndexPath:i];a.popoverPresentationController.sourceRect=[t cellForRowAtIndexPath:i].bounds;[self presentViewController:a animated:YES completion:nil];}
- (void)confirmState:(NSDictionary*)p{BOOL enabled=![p[@"enabled"]boolValue];UIAlertController*a=[UIAlertController alertControllerWithTitle:enabled?SHL(@"Enable this eSIM?"):SHL(@"Disable this eSIM?")message:enabled?SHL(@"This switches the active profile and may briefly interrupt cellular connectivity."):SHL(@"This stops using the profile and may leave the removable card without cellular connectivity.")preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:SHL(@"Cancel")style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:enabled?SHL(@"Enable"):SHL(@"Disable")style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){[self perform:^{NSError*e=nil;[self.lpa setProfile:p[@"iccid"]enabled:enabled error:&e];return e;}success:enabled?SHL(@"Profile enabled"):SHL(@"Profile disabled")];}]];[self presentViewController:a animated:YES completion:nil];}
- (void)renameProfileUI:(NSDictionary*)p{UIAlertController*a=[UIAlertController alertControllerWithTitle:SHL(@"Rename profile")message:SHL(@"Leave blank to restore the original name.")preferredStyle:UIAlertControllerStyleAlert];[a addTextFieldWithConfigurationHandler:^(UITextField*f){f.text=p[@"name"];}];[a addAction:[UIAlertAction actionWithTitle:SHL(@"Cancel")style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:SHL(@"Save")style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){[self perform:^{NSError*e=nil;[self.lpa renameProfile:p[@"iccid"]name:a.textFields[0].text?:@"" error:&e];return e;}success:SHL(@"Nickname updated")];}]];[self presentViewController:a animated:YES completion:nil];}
- (void)confirmDelete:(NSDictionary*)p{UIAlertController*a=[UIAlertController alertControllerWithTitle:SHL(@"Delete profile?") message:[NSString stringWithFormat:SHL(@"Remove “%@” from the card. Your operator determines whether it can be downloaded again."),p[@"name"]] preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:SHL(@"Keep") style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:SHL(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction*x){[self perform:^{NSError*e=nil;BOOL ok=[self.lpa deleteProfile:p[@"iccid"]error:&e];return e?:(!ok?[NSError errorWithDomain:@"SIMHarbor" code:1 userInfo:@{NSLocalizedDescriptionKey:SHL(@"Delete failed")}]:nil);} success:SHL(@"Profile deleted")];}]];[self presentViewController:a animated:YES completion:nil];}
- (void)perform:(NSError*(^)(void))work success:(NSString*)success{if(self.busy)return;[self setWorking:YES];[self.queue addOperationWithBlock:^{NSError*e=work();NSString*warning=self.lpa.lastWarning;dispatch_async(dispatch_get_main_queue(),^{[self setWorking:NO];if(e)[[SHTraceLog shared]error:e];else Record(success);[self message:e?SHL(@"Operation incomplete"):success detail:e?e.localizedDescription:(warning?:SHL(@"Operation completed."))];[self refreshCard];});}];}
- (void)scan{if(self.busy)return;UIAlertController*a=[UIAlertController alertControllerWithTitle:SHL(@"Read activation QR code") message:nil preferredStyle:UIAlertControllerStyleActionSheet];[a addAction:[UIAlertAction actionWithTitle:SHL(@"Scan with camera") style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){[self camera];}]];[a addAction:[UIAlertAction actionWithTitle:SHL(@"Choose an image") style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){PHPickerConfiguration*config=[PHPickerConfiguration new];config.filter=PHPickerFilter.imagesFilter;config.selectionLimit=1;PHPickerViewController*p=[[PHPickerViewController alloc]initWithConfiguration:config];p.delegate=self;[self presentViewController:p animated:YES completion:nil];}]];[a addAction:[UIAlertAction actionWithTitle:SHL(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.sourceView=self.scanButton;a.popoverPresentationController.sourceRect=self.scanButton.bounds;[self presentViewController:a animated:YES completion:nil];}
- (void)camera{ScannerVC*s=[ScannerVC new];__weak RootVC*w=self;s.result=^(NSString*code){if(code)[w input:code];};[self presentViewController:[[UINavigationController alloc]initWithRootViewController:s]animated:YES completion:nil];}
- (void)picker:(PHPickerViewController*)picker didFinishPicking:(NSArray<PHPickerResult*>*)results{[picker dismissViewControllerAnimated:YES completion:^{if(!results.count)return;[results.firstObject.itemProvider loadDataRepresentationForTypeIdentifier:@"public.image" completionHandler:^(NSData*data,NSError*error){NSError*e=error;NSString*value=data?[SHQRDecoder decode:data error:&e]:nil;dispatch_async(dispatch_get_main_queue(),^{if(value)[self input:value];else [self message:SHL(@"Unable to read QR code") detail:e.localizedDescription?:SHL(@"Choose an image containing an activation QR code.")];});}];}];}

- (void)manual{[self input:@""];}
- (void)input:(NSString*)code{
 self.pendingActivationCode=code?:@"";
 [self presentPendingActivationCode];
}
- (void)presentPendingActivationCode{
 if(self.pendingActivationCode==nil||self.busy||!self.viewIfLoaded.window||self.navigationController.topViewController!=self||self.presentedViewController)return;
 NSString *code=self.pendingActivationCode;
 self.pendingActivationCode=nil;
 UIAlertController*a=[UIAlertController alertControllerWithTitle:SHL(@"Add eSIM") message:SHL(@"Download to the removable card. The profile remains disabled.") preferredStyle:UIAlertControllerStyleAlert];[a addTextFieldWithConfigurationHandler:^(UITextField*t){t.placeholder=SHL(@"LPA:1$server$activation-token");t.text=code;t.autocapitalizationType=UITextAutocapitalizationTypeNone;t.autocorrectionType=UITextAutocorrectionTypeNo;t.clearButtonMode=UITextFieldViewModeWhileEditing;}];[a addTextFieldWithConfigurationHandler:^(UITextField*t){t.placeholder=SHL(@"Confirmation code (if required)");t.secureTextEntry=YES;}];[a addTextFieldWithConfigurationHandler:^(UITextField*t){t.placeholder=SHL(@"IMEI (optional, 15 digits)");t.keyboardType=UIKeyboardTypeNumberPad;}];[a addAction:[UIAlertAction actionWithTitle:SHL(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:SHL(@"Download and install") style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){NSString*activation=a.textFields[0].text?:@"",*confirmation=a.textFields[1].text?:@"";self.lpa.downloadIMEI=a.textFields[2].text;a.textFields[0].text=@"";a.textFields[1].text=@"";[self downloadCode:activation confirmation:confirmation];}]];[self presentViewController:a animated:YES completion:nil];}
- (void)downloadCode:(NSString*)activation confirmation:(NSString*)confirmation{
 void(^begin)(void)=^{[self perform:^{NSError*e=nil;BOOL ok=[self.lpa download:activation confirmation:confirmation error:&e];return e?:(!ok?[NSError errorWithDomain:@"SIMHarbor" code:1 userInfo:@{NSLocalizedDescriptionKey:SHL(@"Download failed")}]:nil);}success:SHL(@"eSIM installed")];};
 if([NSUserDefaults.standardUserDefaults boolForKey:@"SHNetworkConsent"]){begin();return;}
 UIAlertController*a=[UIAlertController alertControllerWithTitle:SHL(@"Allow SIMHarbor network access?") message:SHL(@"Downloading eSIMs requires your operator's server. Allow this app to use Wi-Fi and cellular data.") preferredStyle:UIAlertControllerStyleAlert];
 [a addAction:[UIAlertAction actionWithTitle:SHL(@"Not now") style:UIAlertActionStyleCancel handler:nil]];[a addAction:[UIAlertAction actionWithTitle:SHL(@"Allow and download") style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){NSError*e=nil;if([self.lpa allowOwnNetworking:&e])begin();else [self message:SHL(@"Unable to update network access") detail:e.localizedDescription];}]];[self presentViewController:a animated:YES completion:nil];
}
- (void)info{if(self.busy)return;UIAlertController*a=[UIAlertController alertControllerWithTitle:SHL(@"Card management")message:nil preferredStyle:UIAlertControllerStyleActionSheet];[a addAction:[UIAlertAction actionWithTitle:SHL(@"Card info and settings")style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){[self.navigationController pushViewController:[[SHManagementVC alloc]initWithLPA:self.lpa queue:self.queue notifications:NO]animated:YES];}]];[a addAction:[UIAlertAction actionWithTitle:SHL(@"Notifications")style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){[self.navigationController pushViewController:[[SHManagementVC alloc]initWithLPA:self.lpa queue:self.queue notifications:YES]animated:YES];}]];[a addAction:[UIAlertAction actionWithTitle:SHL(@"Firmware resolver") style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){[self.navigationController pushViewController:[[SHFirmwareReportVC alloc]initWithQueue:self.queue]animated:YES];}]];[a addAction:[UIAlertAction actionWithTitle:SHL(@"Signal console") style:UIAlertActionStyleDefault handler:^(UIAlertAction*x){[self.navigationController pushViewController:[[SHSignalConsoleVC alloc]initWithLPA:self.lpa queue:self.queue]animated:YES];}]];[a addAction:[UIAlertAction actionWithTitle:SHL(@"Cancel")style:UIAlertActionStyleCancel handler:nil]];a.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;[self presentViewController:a animated:YES completion:nil];}
- (void)viewWillAppear:(BOOL)animated{[super viewWillAppear:animated];if(self.card&&!self.busy)[self refreshCard];}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];[self presentPendingActivationCode];}

@end
@interface AppDelegate:UIResponder<UIApplicationDelegate>
@property(nonatomic,strong) UIWindow*window;
@end
@implementation AppDelegate
- (void)buildUI{self.window=[[UIWindow alloc]initWithFrame:UIScreen.mainScreen.bounds];RootVC*root=[RootVC new];UINavigationController*cards=[[UINavigationController alloc]initWithRootViewController:root];cards.tabBarItem=[[UITabBarItem alloc]initWithTitle:SHL(@"Profiles") image:[UIImage systemImageNamed:@"simcard.2"] tag:0];UINavigationController*logs=[[UINavigationController alloc]initWithRootViewController:[LogsVC new]];logs.tabBarItem=[[UITabBarItem alloc]initWithTitle:SHL(@"Logs") image:[UIImage systemImageNamed:@"clock.arrow.circlepath"] tag:1];UITabBarController*tabs=[UITabBarController new];UINavigationController*documents=[[UINavigationController alloc]initWithRootViewController:[SHDocumentsVC new]];documents.tabBarItem=[[UITabBarItem alloc]initWithTitle:SHL(@"Documents")image:[UIImage systemImageNamed:@"book.closed"]tag:2];UINavigationController *about=[[UINavigationController alloc]initWithRootViewController:[SHAboutVC new]];about.tabBarItem=[[UITabBarItem alloc]initWithTitle:SHL(@"About") image:[UIImage systemImageNamed:@"info.circle"] tag:3];tabs.viewControllers=@[cards,logs,documents,about];tabs.tabBar.tintColor=Accent();self.window.rootViewController=tabs;[self.window makeKeyAndVisible];}
- (BOOL)application:(UIApplication*)app didFinishLaunchingWithOptions:(NSDictionary*)options{[[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(buildUI)name:@"SHLanguageChanged"object:nil];[self buildUI];return YES;}
@end
static int SHQRCheck(void){@autoreleasepool{
 NSString *expected=@"LPA:1$example.invalid$SIMHarbor-QR-test";
 for(NSString *payload in @[expected,@"  LPA:1$example.invalid$SIMHarbor-QR-test\n",@"lpa:1$example.invalid$SIMHarbor-QR-test",@"\uFEFFLPA:1$example.invalid$SIMHarbor-QR-test"]){
  if(![[SHQRDecoder activationCodeFromPayload:payload]isEqual:expected]){fprintf(stderr,"QR normalization failed\n");return 1;}
 }
 for(NSString *payload in @[@"https://example.invalid",@"LPA:1$",@"LPA:1$$token",@"LPA:1$example.invalid$",@"LPA:1$https://example.invalid$token"]){
  if([SHQRDecoder activationCodeFromPayload:payload]){fprintf(stderr,"Invalid QR accepted\n");return 1;}
 }
 NSData *data=[NSData dataWithContentsOfFile:[NSBundle.mainBundle pathForResource:@"QRFixture" ofType:@"png"]];NSError *error=nil;
 NSString *value=[SHQRDecoder decode:data error:&error];
 if([value isEqual:expected]){printf("Native QR image decoding and payload normalization OK\n");return 0;}
 fprintf(stderr,"QR check failed: %s\n",error.localizedDescription.UTF8String);return 1;
}}
static int SHNetworkCheck(void){@autoreleasepool{NSError*e=nil;SHLPA*lpa=[SHLPA new];if(![lpa checkNetwork:&e]){fprintf(stderr,"Network check failed: %s\n",e.localizedDescription.UTF8String);return 1;}printf("Native TLS transport OK\n");return 0;}}
static int SHDiagnose(int argc,char**argv){
 @autoreleasepool{
  [[SHBridge shared]start];for(int i=0;i<75&&![[SHBridge shared]connected];i++)[NSThread sleepForTimeInterval:0.2];
  if(strcmp(argv[1],"--resolver-check")==0){NSError*error=nil;NSDictionary*reply=nil;for(int i=0;i<90;i++){reply=[[SHBridge shared]request:@{@"op":@"resolver"}error:&error];if(reply[@"report"]&&![reply[@"report"][@"state"]isEqual:@"initializing"])break;[NSThread sleepForTimeInterval:1];}if(!reply){fprintf(stderr,"Resolver unavailable\n");return 15;}NSData*data=[NSJSONSerialization dataWithJSONObject:reply[@"report"] options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];fwrite(data.bytes,1,data.length,stdout);printf("\n");return [reply[@"report"][@"codeResolved"]boolValue]?0:15;}
  NSError*e=nil;NSDictionary*state=nil;for(int i=0;i<20;i++){state=[[SHBridge shared]request:@{@"op":@"status"}error:&e];if([state[@"ready"]boolValue])break;[NSThread sleepForTimeInterval:1];}if(!state||![state[@"ready"]boolValue]){fprintf(stderr,"Bridge unavailable: %s\n",(e.localizedDescription?:state.description).UTF8String);return 2;}
  SHLPA*lpa=[SHLPA new];lpa.progress=^(NSString*stage){fprintf(stderr,"%s\n",SHEnglish(stage).UTF8String);};NSDictionary*before=[lpa readCard:&e];if(!before){fprintf(stderr,"%s\n",e.localizedDescription.UTF8String);return 3;}
  printf("Native card read OK: %lu profiles\n",(unsigned long)[before[@"profiles"]count]);fflush(stdout);
  if(strcmp(argv[1],"--snapshot-check")==0){NSData*data=[NSJSONSerialization dataWithJSONObject:before options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:nil];fwrite(data.bytes,1,data.length,stdout);printf("\n");return 0;}
  if(strcmp(argv[1],"--diagnose")==0){NSArray*notes=[lpa notifications:&e];if(!notes){fprintf(stderr,"Notification read failed: %s\n",e.localizedDescription.UTF8String);return 14;}printf("Native management read OK: %lu notifications; firmware=%s RSP=%s\n",(unsigned long)notes.count,[before[@"firmware"]UTF8String],[before[@"rspVersion"]UTF8String]);}
  if(strcmp(argv[1],"--restore-switch-baseline")==0){NSArray*original=[NSUserDefaults.standardUserDefaults arrayForKey:@"SHTestSwitchBaseline"];if(!original.count){fprintf(stderr,"No saved switch baseline\n");return 10;}for(NSDictionary*p in original)if([p[@"enabled"]boolValue]){if(![lpa setProfile:p[@"iccid"]enabled:YES error:&e]){fprintf(stderr,"Restore failed: %s\n",e.localizedDescription.UTF8String);return 11;}}
   NSDictionary*r=[lpa readCard:&e];NSMutableSet*ids=[NSMutableSet set];for(NSDictionary*p in original)[ids addObject:p[@"iccid"]];NSMutableArray*extra=[NSMutableArray array];for(NSDictionary*p in r[@"profiles"])if(![ids containsObject:p[@"iccid"]])[extra addObject:p];if(extra.count==1&&[extra[0][@"provider"]isEqual:@"CMLink"]&&![extra[0][@"enabled"]boolValue]){if(![lpa deleteProfile:extra[0][@"iccid"]error:&e])return 12;}
   NSDictionary*final=[lpa readCard:&e];if(![final[@"profiles"]isEqual:original]){fprintf(stderr,"Baseline differs after restore\n");return 13;}[NSUserDefaults.standardUserDefaults removeObjectForKey:@"SHTestSwitchBaseline"];printf("Original profile baseline restored and test profile removed\n");return 0;
  }

  if(argc>=3&&(strcmp(argv[1],"--verify-roundtrip")==0||strcmp(argv[1],"--verify-switch-roundtrip")==0)){
   NSString*secret=[NSString stringWithContentsOfFile:@(argv[2]) encoding:NSUTF8StringEncoding error:&e];if(!secret||![lpa download:secret confirmation:nil error:&e]){fprintf(stderr,"Download failed: %s\n",e.localizedDescription.UTF8String);return 4;}
   secret=nil;NSDictionary*after=[lpa readCard:&e];NSMutableArray*added=[NSMutableArray array];NSMutableSet*ids=[NSMutableSet set];for(NSDictionary*p in before[@"profiles"])[ids addObject:p[@"iccid"]];for(NSDictionary*p in after[@"profiles"])if(![ids containsObject:p[@"iccid"]])[added addObject:p];
   if(added.count!=1||[added[0][@"enabled"]boolValue]){fprintf(stderr,"Installed profile verification failed; no deletion attempted.\n");return 5;}
   printf("Native download verified: one new disabled profile\n");fflush(stdout);
   BOOL switchPassed=YES;BOOL switchTest=strcmp(argv[1],"--verify-switch-roundtrip")==0;
   if(switchTest){[NSUserDefaults.standardUserDefaults setObject:before[@"profiles"]forKey:@"SHTestSwitchBaseline"];[NSUserDefaults.standardUserDefaults synchronize];
    @try{if(![lpa renameProfile:added[0][@"iccid"]name:@"SIMHarbor Test" error:&e]){switchPassed=NO;fprintf(stderr,"Rename failed: %s\n",e.localizedDescription.UTF8String);}else printf("Native rename OK\n");
     if(![lpa setProfile:added[0][@"iccid"]enabled:YES error:&e]){switchPassed=NO;fprintf(stderr,"Enable failed: %s\n",e.localizedDescription.UTF8String);}else{printf("Native enable verified\n");fflush(stdout);if(![lpa setProfile:added[0][@"iccid"]enabled:NO error:&e]){switchPassed=NO;fprintf(stderr,"Disable failed: %s\n",e.localizedDescription.UTF8String);}else printf("Native disable verified\n");}
    }@finally{for(NSDictionary*p in before[@"profiles"])if([p[@"enabled"]boolValue]){NSError*restore=nil;if(![lpa setProfile:p[@"iccid"]enabled:YES error:&restore]){fprintf(stderr,"ORIGINAL LINE RESTORE FAILED: %s\n",restore.localizedDescription.UTF8String);return 8;}}printf("Original enabled line restored\n");fflush(stdout);}
   }

   if(![lpa deleteProfile:added[0][@"iccid"]error:&e]){fprintf(stderr,"Cleanup delete failed: %s\n",e.localizedDescription.UTF8String);return 6;}
   NSDictionary*final=[lpa readCard:&e];if(![final[@"profiles"]isEqual:before[@"profiles"]]){fprintf(stderr,"Profile baseline differs after delete.\n");return 7;}printf("Native delete verified: original profile list restored\n");[NSUserDefaults.standardUserDefaults removeObjectForKey:@"SHTestSwitchBaseline"];if(!switchPassed)return 9;
  }
  return 0;
 }
}
int main(int argc,char*argv[]){if(argc>1&&strcmp(argv[1],"--allow-network")==0){@autoreleasepool{NSError*e=nil;if([[SHLPA new]allowOwnNetworking:&e]){printf("Own-app wireless policy updated\n");return 0;}fprintf(stderr,"%s\n",e.localizedDescription.UTF8String);return 1;}}if(argc>1&&strcmp(argv[1],"--network-check")==0)return SHNetworkCheck();if(argc>1&&strcmp(argv[1],"--qr-check")==0)return SHQRCheck();if(argc>1&&(strcmp(argv[1],"--snapshot-check")==0||strcmp(argv[1],"--resolver-check")==0||strcmp(argv[1],"--restore-switch-baseline")==0||strcmp(argv[1],"--diagnose")==0||(strcmp(argv[1],"--verify-roundtrip")==0||strcmp(argv[1],"--verify-switch-roundtrip")==0)))return SHDiagnose(argc,argv);@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(AppDelegate.class));}}
