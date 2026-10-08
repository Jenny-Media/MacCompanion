#import <UIKit/UIKit.h>

@interface CompanionVNCSession : NSObject
@property(nonatomic, copy) void (^frameHandler)(UIImage *image);
@property(nonatomic, copy) void (^cursorHandler)(UIImage *image, CGPoint hotspot, CGPoint position, BOOL positionKnown);
@property(nonatomic, copy) void (^stateHandler)(NSString *state, NSDictionary *counters);
@property(nonatomic, copy) void (^displayLayoutHandler)(NSDictionary *layout);
@property(nonatomic, readonly) BOOL running;
@property(nonatomic, readonly) BOOL connected;
@property(nonatomic) BOOL inputOnly;
@property(nonatomic, readonly) BOOL nativeMagnificationSupported;
- (BOOL)beginMagnificationX:(NSInteger)x y:(NSInteger)y;
- (BOOL)changeMagnification:(double)delta;
- (void)endMagnification;
- (void)cancelMagnification;
- (BOOL)tryClickX:(NSInteger)x y:(NSInteger)y mask:(NSInteger)mask;
- (void)pauseWithCompletion:(void (^)(void))completion;
- (void)resume;
- (void)connectSocket:(int)socket username:(NSString *)username password:(NSString *)password;
- (void)connectHost:(NSString *)host username:(NSString *)username password:(NSString *)password;
- (void)connectAddresses:(NSArray<NSString *> *)addresses port:(NSInteger)port username:(NSString *)username password:(NSString *)password;
- (void)stop;
- (void)pointerX:(NSInteger)x y:(NSInteger)y mask:(NSInteger)mask;
- (void)key:(uint32_t)key down:(BOOL)down;
- (void)keyEvents:(NSArray<NSDictionary *> *)events;
- (BOOL)tryKeyEvents:(NSArray<NSDictionary *> *)events;
- (void)viewChanged;

@end
