#import <UIKit/UIKit.h>
#import "LPAEngine.h"
@interface SHManagementVC:UITableViewController
- (instancetype)initWithLPA:(SHLPA*)lpa queue:(NSOperationQueue*)queue notifications:(BOOL)notifications;
@end
