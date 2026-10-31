#import <UIKit/UIKit.h>
#import "LPAEngine.h"
@interface SHSignalConsoleVC : UIViewController
- (instancetype)initWithLPA:(SHLPA *)lpa queue:(NSOperationQueue *)queue;
@end
