#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *const CompanionVNCControlsHapticsPreference;
/// Locally captured tap/press-and-slide chrome, independent of remote gestures.
@interface CompanionVNCControls : UIView
@property(nonatomic, copy) NSString *macName;
@property(nonatomic, copy) NSArray<NSDictionary *> *quickActions;
/// Optional session-specific categories; nil retains the Desktop categories.
@property(nonatomic, copy, nullable) NSArray<NSDictionary *> *categoryActions;
@property(nonatomic) BOOL trackpad;
@property(nonatomic) BOOL hapticsEnabled;
@property(nonatomic) BOOL fullscreen, inputOnly;
@property(nonatomic) CGFloat bottomInset;
@property(nonatomic, readonly) UIButton *button;
@property(nonatomic, copy, nullable) void (^actionHandler)(NSDictionary *);
@property(nonatomic, copy, nullable) void (^openingHandler)(void);
- (void)close;
- (void)cancelSlideForLayoutChange;
@end
NS_ASSUME_NONNULL_END
