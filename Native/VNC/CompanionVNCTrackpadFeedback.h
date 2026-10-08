#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN
/// Local touch feedback only. Never sends or records remote input.
@interface CompanionVNCTrackpadFeedback : UIView
- (instancetype)initWithSurface:(UIView *)surface;
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL showsTouchPoints;
@property(nonatomic) BOOL hapticsEnabled;
@property(nonatomic, copy, nullable) BOOL (^touchesAllowed)(void);
- (void)clickAtPoint:(CGPoint)point;
- (void)setDragging:(BOOL)dragging;
/// Forget current fingers; a new touch is required to show feedback again.
- (void)cancelTouches;
@end
NS_ASSUME_NONNULL_END
