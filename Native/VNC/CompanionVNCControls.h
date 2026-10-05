#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
/// Locally captured tap/press-and-slide chrome, independent of remote gestures.
@interface CompanionVNCControls : UIView
@property(nonatomic, copy) NSString *macName;
@property(nonatomic, copy) NSArray<NSDictionary *> *quickActions;
@property(nonatomic) BOOL trackpad;
@property(nonatomic) BOOL fullscreen, inputOnly;
@property(nonatomic) CGFloat bottomInset;
@property(nonatomic, readonly) UIButton *button;
@property(nonatomic, copy, nullable) void (^actionHandler)(NSDictionary *);
@property(nonatomic, copy, nullable) void (^openingHandler)(void);
- (void)close;
@end
NS_ASSUME_NONNULL_END
