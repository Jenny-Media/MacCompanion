#import <UIKit/UIKit.h>

@interface VNCSession : NSObject
@property(nonatomic, copy) void (^frameHandler)(UIImage *image);
@property(nonatomic, copy) void (^stateHandler)(NSString *state, NSDictionary *counters);
@property(nonatomic, readonly) BOOL running;
- (void)connectHost:(NSString *)host username:(NSString *)username password:(NSString *)password;
- (void)stop;
- (void)pointerX:(NSInteger)x y:(NSInteger)y mask:(NSInteger)mask;
- (void)key:(uint32_t)key down:(BOOL)down;
- (void)text:(NSString *)text;
- (void)viewChanged;
#if TARGET_OS_SIMULATOR
- (void)connectFixture;
- (void)probeMacHandshake;
#endif
@end
