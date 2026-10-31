#import <UIKit/UIKit.h>
@interface SHErrorDetailsVC : UIViewController
+ (void)showError:(NSError *)error from:(UIViewController *)controller;
@end
