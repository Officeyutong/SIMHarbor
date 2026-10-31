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

@interface SHDocumentArticleVC : UIViewController
@property(nonatomic,strong) NSDictionary *article;
@property(nonatomic,strong) UITextView *textView;
@end
@implementation SHDocumentArticleVC
- (void)viewDidLoad {
    [super viewDidLoad];self.title=self.article[@"title"];self.navigationItem.largeTitleDisplayMode=UINavigationItemLargeTitleDisplayModeNever;
    self.view.backgroundColor=UIColor.systemBackgroundColor;self.textView=[[UITextView alloc]initWithFrame:CGRectZero];
    self.textView.translatesAutoresizingMaskIntoConstraints=NO;self.textView.editable=NO;self.textView.selectable=YES;
    self.textView.backgroundColor=UIColor.systemBackgroundColor;self.textView.textContainerInset=UIEdgeInsetsMake(18,18,30,18);
    [self.view addSubview:self.textView];[NSLayoutConstraint activateConstraints:@[
        [self.textView.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [self.textView.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [self.textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.textView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor]]];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithTitle:SHL(@"Copy")style:UIBarButtonItemStylePlain target:self action:@selector(copyArticle)];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(render)name:UIContentSizeCategoryDidChangeNotification object:nil];[self render];
}
- (void)render {CGPoint offset=self.textView.contentOffset;self.textView.attributedText=DocRender(self.article[@"body"]?:@"");[self.textView setContentOffset:offset animated:NO];}
- (void)copyArticle {UIPasteboard.generalPasteboard.string=self.textView.text;}
- (void)dealloc {[[NSNotificationCenter defaultCenter]removeObserver:self];}
@end

@interface SHDocumentsVC () <UISearchResultsUpdating>
@property(nonatomic,strong) NSArray<NSDictionary *> *articles;
@property(nonatomic,strong) NSArray<NSDictionary *> *filtered;
@property(nonatomic,strong) UISearchController *search;
@property(nonatomic) BOOL failed;
@end
@implementation SHDocumentsVC
- (instancetype)init {return [super initWithStyle:UITableViewStyleInsetGrouped];}
- (void)viewDidLoad {
    [super viewDidLoad];self.title=SHL(@"Documents");self.tableView.rowHeight=UITableViewAutomaticDimension;self.tableView.estimatedRowHeight=96;
    self.navigationController.navigationBar.prefersLargeTitles=YES;
    NSString *filename=[@"Documentation-"stringByAppendingString:SHResolvedLanguage()];
    NSString *path=[NSBundle.mainBundle pathForResource:filename ofType:@"json"];NSData *data=path?[NSData dataWithContentsOfFile:path]:nil;
    id articles=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    self.failed=![articles isKindOfClass:NSArray.class]||![articles count];self.articles=self.failed?@[]:articles;self.filtered=self.articles;
    self.search=[[UISearchController alloc]initWithSearchResultsController:nil];self.search.searchResultsUpdater=self;
    self.search.obscuresBackgroundDuringPresentation=NO;self.search.searchBar.placeholder=SHL(@"Search documents");
    self.navigationItem.searchController=self.search;self.navigationItem.hidesSearchBarWhenScrolling=NO;self.definesPresentationContext=YES;
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {return self.filtered.count?:1;}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {return SHL(@"Bundled for offline reading. No card or network connection is required.");}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];cell.textLabel.adjustsFontForContentSizeCategory=YES;cell.textLabel.numberOfLines=0;
    cell.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];cell.detailTextLabel.adjustsFontForContentSizeCategory=YES;cell.detailTextLabel.numberOfLines=0;
    if(!self.filtered.count){cell.textLabel.text=SHL(self.failed?@"Unable to load documentation.":@"No matching documents.");cell.selectionStyle=UITableViewCellSelectionStyleNone;return cell;}
    NSDictionary *article=self.filtered[index.row];cell.textLabel.text=article[@"title"];cell.detailTextLabel.text=article[@"summary"];
    cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return cell;
}
- (void)updateSearchResultsForSearchController:(UISearchController *)controller {
    NSString *query=[controller.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    self.filtered=!query.length?self.articles:[self.articles filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *article,NSDictionary *bindings){
        return [article[@"title"]localizedCaseInsensitiveContainsString:query]||[article[@"summary"]localizedCaseInsensitiveContainsString:query]||[article[@"body"]localizedCaseInsensitiveContainsString:query];
    }]];[self.tableView reloadData];
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];if(!self.filtered.count)return;
    NSDictionary *article=self.filtered[index.row];self.search.active=NO;SHDocumentArticleVC *reader=[SHDocumentArticleVC new];reader.article=article;
    [self.navigationController pushViewController:reader animated:YES];
}
@end
