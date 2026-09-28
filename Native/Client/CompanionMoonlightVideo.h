#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Transport parameters returned by a separately authorized engine launch.
/// This component does not discover, pair, approve, or launch a host application.
@interface CompanionMoonlightVideoConfiguration : NSObject
@property (copy, nonatomic) NSString *host;
@property (copy, nonatomic) NSString *appVersion;
@property (nonatomic) uint32_t serverCodecModeSupport;
@property (copy, nonatomic) NSString *sessionURL;
@property (copy, nonatomic) NSData *streamKey;
@property (nonatomic) uint32_t streamKeyID;
@property (nonatomic) int width;
@property (nonatomic) int height;
@property (nonatomic) int framesPerSecond;
@property (nonatomic) int bitrateKbps;
@end

typedef NS_ENUM(NSInteger, CompanionMoonlightVideoEvent) {
    CompanionMoonlightVideoEventConnected,
    CompanionMoonlightVideoEventFirstFrame,
    CompanionMoonlightVideoEventFailed,
    CompanionMoonlightVideoEventDisconnected,
};

/// One video-only Moonlight session. All public calls and callbacks use the
/// main thread. Stop completes after native sockets and decoding have drained.
/// Input remains in MacCompanion's authenticated Control transport.
@interface CompanionMoonlightVideo : NSObject
@property (readonly, nonatomic) BOOL presentationReady;
@property (readonly, nonatomic) int decodedWidth;
@property (readonly, nonatomic) int decodedHeight;
/// Complete picture samples accepted by the local display layer. Contains no pixels.
@property (readonly, nonatomic) uint64_t queuedVideoFrameCount;
- (nullable instancetype)initWithConfiguration:(CompanionMoonlightVideoConfiguration *)configuration
                                          view:(UIView *)view
                                         event:(void (^)(CompanionMoonlightVideoEvent event, int code))event
                                         error:(NSError **)error;
- (BOOL)start:(NSError **)error;
- (void)stopWithCompletion:(void (^)(void))completion;
@end

NS_ASSUME_NONNULL_END
