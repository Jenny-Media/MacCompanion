#import <Foundation/Foundation.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>

NS_ASSUME_NONNULL_BEGIN
/// Private owned-child spawn context; never an Agent or remote protocol payload.
API_AVAILABLE(macos(14.0))
@interface CompanionSelectedCaptureContext : NSObject
@property(nonatomic, readonly) NSInteger sourcePixelWidth, sourcePixelHeight, encodedWidth, encodedHeight;
@property(nonatomic, readonly) CGRect sourceRect;
+ (nullable instancetype)loadManagedContextForDisplay:(CGDirectDisplayID)displayID error:(NSError **)error;
- (BOOL)isCurrentSelection;
/// Bounded fresh resolution; preflights permission and never asks for it.
- (nullable SCContentFilter *)resolveFilter:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
