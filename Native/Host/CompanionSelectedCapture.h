#import <Foundation/Foundation.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Local stream abstraction; it provides no selection, approval or input authority.
@protocol CompanionSelectedCaptureSession <NSObject>
- (BOOL)addStreamOutput:(id<SCStreamOutput>)output type:(SCStreamOutputType)type
    sampleHandlerQueue:(dispatch_queue_t)queue error:(NSError **)error;
- (BOOL)removeStreamOutput:(id<SCStreamOutput>)output type:(SCStreamOutputType)type error:(NSError **)error;
- (void)startCaptureWithCompletionHandler:(void (^)(NSError * _Nullable))completion;
- (void)stopCaptureWithCompletionHandler:(void (^)(NSError * _Nullable))completion;
- (void)updateContentFilter:(SCContentFilter *)filter completionHandler:(void (^)(NSError * _Nullable))completion;
- (void)updateConfiguration:(SCStreamConfiguration *)configuration completionHandler:(void (^)(NSError * _Nullable))completion;
@end

typedef BOOL (^CompanionSelectedCaptureCurrent)(void);
typedef BOOL (^CompanionSelectedCaptureFrame)(CMSampleBufferRef sample);
typedef void (^CompanionSelectedCaptureTerminal)(NSError * _Nullable error);

/// Inert until start. The local caller retains selection and Control authority.
API_AVAILABLE(macos(14.0))
@interface CompanionSelectedCapture : NSObject <SCStreamOutput, SCStreamDelegate>
- (nullable instancetype)initWithFilter:(SCContentFilter *)filter
    sourceRect:(CGRect)sourceRect
    sourcePixelWidth:(NSInteger)sourceWidth sourcePixelHeight:(NSInteger)sourceHeight
    encodedWidth:(NSInteger)width encodedHeight:(NSInteger)height pixelFormat:(OSType)pixelFormat
    isCurrent:(CompanionSelectedCaptureCurrent)isCurrent error:(NSError **)error;
- (void)startWithFrame:(CompanionSelectedCaptureFrame)frame terminal:(CompanionSelectedCaptureTerminal)terminal;
/// Retains the stream and encoded canvas. Delivery is fenced until both updates
/// succeed and a fresh sample agrees with the new, locally authorized selection.
- (void)updateFilter:(SCContentFilter *)filter sourceRect:(CGRect)sourceRect
    sourcePixelWidth:(NSInteger)sourceWidth sourcePixelHeight:(NSInteger)sourceHeight
    isCurrent:(CompanionSelectedCaptureCurrent)isCurrent
    completion:(void (^)(NSError * _Nullable))completion;
/// Fences further delivery before asynchronous stream stop; terminal follows acknowledgement.
- (void)stop;
@end

NS_ASSUME_NONNULL_END
