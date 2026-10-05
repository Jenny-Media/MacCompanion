#import <Foundation/Foundation.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>

NS_ASSUME_NONNULL_BEGIN
/// Private owned-child spawn context; never an Agent or remote protocol payload.
API_AVAILABLE(macos(14.0))
@interface CompanionSelectedCaptureContext : NSObject
@property(nonatomic, readonly) NSInteger sourcePixelWidth, sourcePixelHeight, encodedWidth, encodedHeight;
@property(nonatomic, readonly) CGRect sourceRect;
@property(nonatomic, readonly) NSString *operationID;
@property(nonatomic, readonly) uint64_t expiresAtMonotonicNanoseconds;
@property(nonatomic, readonly, nullable) NSData *frameEpoch;
+ (nullable instancetype)loadManagedContextForDisplay:(CGDirectDisplayID)displayID error:(NSError **)error;
/// Local controlled handoff only; parsing creates no selection authority.
+ (nullable instancetype)parseData:(NSData *)data operationID:(NSString *)operation displayID:(CGDirectDisplayID)displayID
    now:(uint64_t)now error:(NSError **)error;
- (BOOL)isCurrentSelection;
/// Bounded fresh resolution; preflights permission and never asks for it.
- (nullable SCContentFilter *)resolveFilter:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
