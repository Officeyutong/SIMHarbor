#import "DocumentsVC.h"
#import "Localization.h"

static UIFont *DocCodeFont(void) {
    return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:
        [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular]];
}
// The bundled manual uses a small Markdown subset. Native attributed text keeps
// the reader offline and selectable, without JavaScript or a WebKit subprocess.
static NSAttributedString *DocInline(NSString *text, UIFont *font, UIColor *color) {
    NSMutableAttributedString *result=[NSMutableAttributedString new];
    NSRegularExpression *pattern=[NSRegularExpression regularExpressionWithPattern:@"(`[^`]+`|\\*\\*[^*]+\\*\\*)" options:0 error:nil];
    NSUInteger start=0;
    for(NSTextCheckingResult *match in [pattern matchesInString:text options:0 range:NSMakeRange(0,text.length)]){
        if(match.range.location>start)[result appendAttributedString:[[NSAttributedString alloc]initWithString:
            [text substringWithRange:NSMakeRange(start,match.range.location-start)] attributes:@{NSFontAttributeName:font,NSForegroundColorAttributeName:color}]];
        NSString *token=[text substringWithRange:match.range];BOOL code=[token hasPrefix:@"`"];
        NSString *value=[token substringWithRange:NSMakeRange(code?1:2,token.length-(code?2:4))];
        UIFont *styled=code?DocCodeFont():[UIFont fontWithDescriptor:[font.fontDescriptor fontDescriptorWithSymbolicTraits:UIFontDescriptorTraitBold]size:font.pointSize];
        NSMutableDictionary *attributes=[@{NSFontAttributeName:styled?:font,NSForegroundColorAttributeName:color}mutableCopy];
        if(code)attributes[NSBackgroundColorAttributeName]=UIColor.tertiarySystemFillColor;
        [result appendAttributedString:[[NSAttributedString alloc]initWithString:value attributes:attributes]];start=NSMaxRange(match.range);
    }
    if(start<text.length)[result appendAttributedString:[[NSAttributedString alloc]initWithString:[text substringFromIndex:start]attributes:@{NSFontAttributeName:font,NSForegroundColorAttributeName:color}]];
    return result;
}
static NSAttributedString *DocRender(NSString *markdown) {
    NSMutableAttributedString *result=[NSMutableAttributedString new];BOOL code=NO;
    for(NSString *source in [markdown componentsSeparatedByString:@"\n"]){
        NSString *line=source;UIFont *font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];UIColor *color=UIColor.labelColor;
        NSMutableParagraphStyle *style=[NSMutableParagraphStyle new];style.paragraphSpacing=8;style.lineSpacing=3;
        if([line hasPrefix:@"```"]){code=!code;continue;}
        if(code){font=DocCodeFont();style.paragraphSpacing=2;style.lineSpacing=2;}
        else if([line hasPrefix:@"### "]){line=[line substringFromIndex:4];font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];style.paragraphSpacingBefore=12;}
        else if([line hasPrefix:@"## "]){line=[line substringFromIndex:3];font=[UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];style.paragraphSpacingBefore=16;}
        else if([line hasPrefix:@"# "]){line=[line substringFromIndex:2];font=[UIFont preferredFontForTextStyle:UIFontTextStyleTitle1];style.paragraphSpacingBefore=8;}
        else if([line hasPrefix:@"- "]){line=[@"• "stringByAppendingString:[line substringFromIndex:2]];style.headIndent=16;}
        else if([line hasPrefix:@"> "]){line=[line substringFromIndex:2];color=UIColor.secondaryLabelColor;}
        else if([line hasPrefix:@"|"]){
            if([line rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"|-: "].invertedSet].location==NSNotFound)continue;
            NSMutableArray *columns=[NSMutableArray array];NSArray *parts=[line componentsSeparatedByString:@"|"];
            for(NSUInteger i=1;i+1<parts.count;i++)[columns addObject:[parts[i]stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]];
            if(columns.count)line=[columns componentsJoinedByString:@"\n"];
        }
        NSMutableAttributedString *paragraph=[[NSMutableAttributedString alloc]initWithAttributedString:code?
            [[NSAttributedString alloc]initWithString:line attributes:@{NSFontAttributeName:font,NSForegroundColorAttributeName:color}]:DocInline(line,font,color)];
        [paragraph appendAttributedString:[[NSAttributedString alloc]initWithString:@"\n"]];
        [paragraph addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0,paragraph.length)];[result appendAttributedString:paragraph];
    }
    return result;
}

@interface SHDocumentsVC ()
@property(nonatomic,copy) NSString *markdown;
@property(nonatomic,strong) UITextView *textView;
@end
@implementation SHDocumentsVC
- (void)viewDidLoad {
    [super viewDidLoad];self.title=SHL(@"User guide");self.navigationController.navigationBar.prefersLargeTitles=YES;
    self.view.backgroundColor=UIColor.systemBackgroundColor;
    NSString *filename=[@"Documentation-" stringByAppendingString:SHResolvedLanguage()];
    NSString *path=[NSBundle.mainBundle pathForResource:filename ofType:@"json"];
    NSData *data=path?[NSData dataWithContentsOfFile:path]:nil;
    id articles=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    if([articles isKindOfClass:NSArray.class]&&[articles count]==1){
        id article=[articles firstObject];
        if([article isKindOfClass:NSDictionary.class]&&[article[@"id"]isEqual:@"guide"]&&[article[@"body"]isKindOfClass:NSString.class])self.markdown=article[@"body"];
    }
    self.textView=[[UITextView alloc]initWithFrame:CGRectZero];self.textView.translatesAutoresizingMaskIntoConstraints=NO;
    self.textView.editable=NO;self.textView.selectable=YES;self.textView.backgroundColor=UIColor.systemBackgroundColor;
    self.textView.textContainerInset=UIEdgeInsetsMake(18,18,30,18);[self.view addSubview:self.textView];
    [NSLayoutConstraint activateConstraints:@[
        [self.textView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [self.textView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [self.textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.textView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]]];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:SHL(@"Copy") style:UIBarButtonItemStylePlain target:self action:@selector(copyGuide)];
    self.navigationItem.rightBarButtonItem.enabled=self.markdown!=nil;
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(render) name:UIContentSizeCategoryDidChangeNotification object:nil];[self render];
}
- (void)render {
    CGPoint offset=self.textView.contentOffset;
    self.textView.attributedText=DocRender(self.markdown?:SHL(@"Unable to load the user guide."));
    [self.textView setContentOffset:offset animated:NO];
}
- (void)copyGuide {if(self.markdown)UIPasteboard.generalPasteboard.string=self.textView.text;}
- (void)dealloc {[[NSNotificationCenter defaultCenter]removeObserver:self];}
@end
