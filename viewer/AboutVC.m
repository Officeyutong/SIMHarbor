#import "AboutVC.h"
#import "Localization.h"

@interface SHLicensesVC : UIViewController
@property(nonatomic,strong) UITextView *text;
@end
@implementation SHLicensesVC
- (void)viewDidLoad {
    [super viewDidLoad];self.title=SHL(@"Open-source licenses");self.view.backgroundColor=UIColor.systemBackgroundColor;
    self.text=[[UITextView alloc]initWithFrame:self.view.bounds];self.text.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;self.text.editable=NO;
    self.text.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];self.text.textContainerInset=UIEdgeInsetsMake(18,16,30,16);
    NSMutableArray *parts=[NSMutableArray array];
    for(NSString *name in @[@"THIRD_PARTY_NOTICES",@"LICENSE-LGPL-2.1",@"LICENSE-Frida-Gum",@"LICENSE-Capstone",@"LICENSE-Capstone-LLVM"]){
        NSString *path=[NSBundle.mainBundle pathForResource:name ofType:@"txt"];
        NSString *body=path?[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil]:nil;
        if(body)[parts addObject:[NSString stringWithFormat:@"%@\n\n%@",name,body]];
    }
    self.text.text=[parts componentsJoinedByString:@"\n\n────────────────────\n\n"];[self.view addSubview:self.text];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:SHL(@"Copy") style:UIBarButtonItemStylePlain target:self action:@selector(copyLicenses)];
}
- (void)copyLicenses {UIPasteboard.generalPasteboard.string=self.text.text;}
@end

@implementation SHAboutVC
- (instancetype)init {return [super initWithStyle:UITableViewStyleInsetGrouped];}
- (NSURL*)developerURL {return [NSURL URLWithString:@"https://github.com/officeyutong"];}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=SHL(@"About");self.navigationController.navigationBar.prefersLargeTitles=YES;
    self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=58;
    UIView *header=[[UIView alloc]initWithFrame:CGRectMake(0,0,self.view.bounds.size.width,190)];
    UIImageView *icon=[[UIImageView alloc]initWithImage:[UIImage imageNamed:@"Icon60@3x.png"]];icon.layer.cornerRadius=18;icon.clipsToBounds=YES;
    UILabel *name=[UILabel new];name.text=@"SIMHarbor";name.font=[UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];name.adjustsFontForContentSizeCategory=YES;
    UILabel *summary=[UILabel new];summary.text=SHL(@"Removable eUICC profile manager");summary.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];summary.adjustsFontForContentSizeCategory=YES;summary.textColor=UIColor.secondaryLabelColor;summary.textAlignment=NSTextAlignmentCenter;summary.numberOfLines=0;
    UIStackView *stack=[[UIStackView alloc]initWithArrangedSubviews:@[icon,name,summary]];stack.axis=UILayoutConstraintAxisVertical;stack.alignment=UIStackViewAlignmentCenter;stack.spacing=10;stack.translatesAutoresizingMaskIntoConstraints=NO;[header addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[icon.widthAnchor constraintEqualToConstant:72],[icon.heightAnchor constraintEqualToConstant:72],[stack.topAnchor constraintEqualToAnchor:header.topAnchor constant:12],[stack.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:24],[stack.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-24]]];self.tableView.tableHeaderView=header;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView {return 2;}
- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section {return 3;}
- (NSString*)tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section {return section==0?SHL(@"Application"):SHL(@"Resources");}
- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)index {
    UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];cell.textLabel.numberOfLines=0;cell.detailTextLabel.numberOfLines=0;cell.selectionStyle=UITableViewCellSelectionStyleNone;
    if(index.section==0){
        NSArray *labels=@[SHL(@"Version"),SHL(@"Build"),SHL(@"Developer")];NSArray *keys=@[@"CFBundleShortVersionString",@"CFBundleVersion"];
        cell.textLabel.text=labels[index.row];cell.detailTextLabel.text=index.row==2?@"officeyutong":([NSBundle.mainBundle objectForInfoDictionaryKey:keys[index.row]]?:@"—");
        cell.accessibilityIdentifier=@[@"about.version",@"about.build",@"about.developer"][index.row];
    }else{
        cell.selectionStyle=UITableViewCellSelectionStyleDefault;cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;
        cell.textLabel.text=@[@"GitHub",SHL(@"Offline documentation"),SHL(@"Open-source licenses")][index.row];
        if(index.row==0)cell.detailTextLabel.text=@"github.com/officeyutong";
        cell.imageView.image=[UIImage systemImageNamed:@[@"link",@"book.closed",@"doc.text"][index.row]];
        cell.accessibilityIdentifier=@[@"about.github",@"about.documents",@"about.licenses"][index.row];
    }
    return cell;
}
- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)index {
    [tableView deselectRowAtIndexPath:index animated:YES];if(index.section!=1)return;
    if(index.row==0){
        [UIApplication.sharedApplication openURL:self.developerURL options:@{} completionHandler:^(BOOL success){
            if(success)return;dispatch_async(dispatch_get_main_queue(),^{UIAlertController *alert=[UIAlertController alertControllerWithTitle:SHL(@"GitHub link") message:SHL(@"Unable to open this link.") preferredStyle:UIAlertControllerStyleAlert];[alert addAction:[UIAlertAction actionWithTitle:SHL(@"OK") style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:alert animated:YES completion:nil];});
        }];
    }else if(index.row==1){
        UINavigationController *documents=self.tabBarController.viewControllers[2];[documents popToRootViewControllerAnimated:NO];self.tabBarController.selectedIndex=2;
    }else [self.navigationController pushViewController:[SHLicensesVC new] animated:YES];
}
@end
