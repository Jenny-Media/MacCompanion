#import "CompanionVNCTapGesture.h"
#import <UIKit/UIGestureRecognizerSubclass.h>
@implementation CompanionVNCTapGesture { CGPoint _start; NSTimeInterval _time; }
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (event.allTouches.count != 1) { self.state = UIGestureRecognizerStateFailed; return; }
    UITouch *touch = touches.anyObject; _start = [touch locationInView:self.view]; _time = touch.timestamp;
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = touches.anyObject; CGPoint p = [touch locationInView:self.view];
    if (hypot(p.x - _start.x, p.y - _start.y) > 18 || event.allTouches.count != 1) self.state = UIGestureRecognizerStateFailed;
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = touches.anyObject; CGPoint p = [touch locationInView:self.view];
    self.state = touch.timestamp - _time <= .3 && hypot(p.x - _start.x, p.y - _start.y) <= 18 ? UIGestureRecognizerStateRecognized : UIGestureRecognizerStateFailed;
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event { self.state = UIGestureRecognizerStateFailed; }
@end
