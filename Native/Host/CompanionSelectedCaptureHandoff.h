#import <Foundation/Foundation.h>
#import "CompanionSelectedCaptureContext.h"

NS_ASSUME_NONNULL_BEGIN

/// An inert private child command. Parsing grants no capture or input authority.
API_AVAILABLE(macos(14.0))
@interface CompanionSelectedCaptureHandoffCommand : NSObject
@property(nonatomic, readonly) NSString *transportOperationID, *operationID, *action;
@property(nonatomic, readonly, nullable) NSString *previousOperationID;
@property(nonatomic, readonly) uint64_t sequence, expiresAtMonotonicNanoseconds;
@property(nonatomic, readonly, nullable) CompanionSelectedCaptureContext *context;
+ (nullable instancetype)parseData:(NSData *)data now:(uint64_t)now error:(NSError **)error;
@end

typedef void (^CompanionCaptureHandoffCompletion)(NSError * _Nullable);
typedef void (^CompanionCaptureHandoffPause)(CompanionCaptureHandoffCompletion);
typedef void (^CompanionCaptureHandoffSelect)(CompanionSelectedCaptureContext *, CompanionCaptureHandoffCompletion);

/// Retains no authorization. The parent owns Control, process and original
/// expiry; this owner serializes only the already admitted child's capture.
/// Stop fences replies immediately and waits for pending platform work.
API_AVAILABLE(macos(14.0))
@interface CompanionSelectedCaptureHandoff : NSObject
@property(nonatomic, readonly) BOOL isDeliveryAllowed;
@property(nonatomic, readonly) BOOL isRetired;
- (nullable instancetype)initWithDirectory:(NSString *)directory
    initialContext:(CompanionSelectedCaptureContext *)context
    pause:(CompanionCaptureHandoffPause)pause select:(CompanionCaptureHandoffSelect)select
    terminal:(void (^)(NSError * _Nullable))terminal error:(NSError **)error;
- (void)start;
- (void)stop;
/// Completion follows the terminal callback and all pending platform work.
/// Repeated callers each complete once without reopening this owner.
- (void)stopWithCompletion:(nullable dispatch_block_t)completion;
@end

NS_ASSUME_NONNULL_END
