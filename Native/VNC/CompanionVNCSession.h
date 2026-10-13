#import <TargetConditionals.h>
#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
typedef NSImage CompanionVNCImage;
#else
#import <UIKit/UIKit.h>
typedef UIImage CompanionVNCImage;
#endif

@interface CompanionVNCSession : NSObject
@property(nonatomic, copy) void (^frameHandler)(CompanionVNCImage *image);
@property(nonatomic, copy) void (^cursorHandler)(CompanionVNCImage *image, CGPoint hotspot, CGPoint position, BOOL positionKnown);
@property(nonatomic, copy) void (^stateHandler)(NSString *state, NSDictionary *counters);
@property(nonatomic, copy) void (^displayLayoutHandler)(NSDictionary *layout);
@property(nonatomic, readonly) BOOL running;
/// Fresh numeric/boolean diagnostics; never includes screen or input content.
@property(nonatomic, readonly) NSDictionary *diagnosticCounters;
/// Authenticated transport, including paused or fresh-frame-waiting states.
@property(nonatomic, readonly) BOOL established;
@property(nonatomic, readonly) BOOL connected;
// A complete Desktop baseline presented by this owner, independent of retained UI pixels.
@property(nonatomic, readonly) BOOL desktopFrameReady;
@property(nonatomic) BOOL inputOnly;
@property(nonatomic, readonly) BOOL nativeMagnificationSupported;
- (BOOL)beginMagnificationX:(NSInteger)x y:(NSInteger)y;
- (BOOL)changeMagnification:(double)delta;
- (void)endMagnification;
- (void)cancelNativeGestures;
@property(nonatomic, readonly) BOOL nativeScrollingSupported;
- (BOOL)beginScrollX:(NSInteger)x y:(NSInteger)y;
- (BOOL)changeScrollX:(double)dx y:(double)dy;
- (void)endScroll;
- (BOOL)tryClickX:(NSInteger)x y:(NSInteger)y mask:(NSInteger)mask;
- (void)pauseWithCompletion:(void (^)(void))completion;
- (void)resume;
/// Local snapshot review closes input while the socket continues receiving.
- (BOOL)suspendInputForReview:(void (^)(void))completion;
- (void)resumeInputAfterReview;
/// Brief inactivity releases held input without resetting an established baseline.
- (void)suspendInputForInterruption;
- (void)resumeInputAfterInterruption;
- (void)connectSocket:(int)socket username:(NSString *)username password:(NSString *)password;
- (void)connectHost:(NSString *)host username:(NSString *)username password:(NSString *)password;
- (void)connectAddresses:(NSArray<NSString *> *)addresses port:(NSInteger)port username:(NSString *)username password:(NSString *)password;
- (void)stop;
- (void)pointerX:(NSInteger)x y:(NSInteger)y mask:(NSInteger)mask;
- (void)key:(uint32_t)key down:(BOOL)down;
- (void)keyEvents:(NSArray<NSDictionary *> *)events;
- (BOOL)tryKeyEvents:(NSArray<NSDictionary *> *)events;
#if TARGET_OS_IOS
/// Mode-specific input admission, including the current Desktop baseline.
@property(nonatomic, readonly) BOOL composedTextReady;
/// Completion acknowledges local writes only, never remote application consumption.
- (BOOL)tryComposedTextEvents:(NSArray<NSDictionary *> *)events completion:(void (^)(BOOL written))completion;
#endif
- (void)viewChanged;

@end
