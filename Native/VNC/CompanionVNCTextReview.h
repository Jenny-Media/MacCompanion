#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
/// A local-only, temporary image/text surface. It has no remote input owner.
@interface CompanionVNCTextReview : UIViewController
- (instancetype)initWithImage:(UIImage *)image visibleRect:(CGRect)visibleRect;
@property(nonatomic, copy, nullable) void (^returnHandler)(void);
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
