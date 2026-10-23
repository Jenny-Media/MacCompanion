#import <TargetConditionals.h>
#if TARGET_OS_IOS && DEBUG
#import <UIKit/UIKit.h>
/// Local-only, opt-in workspace for posture acceptance without a remote Mac.
UIViewController *CompanionVNCDuoSampleWorkspace(void);
#endif
