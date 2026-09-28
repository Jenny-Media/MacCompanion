#import "CompanionSelectedCapture.h"
#import <mach/mach_time.h>
#include <math.h>

@interface SCStream (CompanionSelectedCaptureSession) <CompanionSelectedCaptureSession>
@end

typedef NS_ENUM(NSInteger, CompanionSelectedPhase) {
  CompanionSelectedCreated, CompanionSelectedStarting, CompanionSelectedStreaming,
  CompanionSelectedStopping, CompanionSelectedStopped
};

static NSError *SelectedError(NSInteger code) {
  // Fixed codes only: never put selection identifiers, window metadata or pixels in errors.
  if (getenv("MACCOMPANION_NATIVE_SELECTION_PATH")) fprintf(stderr,"selected-capture-stream-error=%ld\n",(long)code);
  return [NSError errorWithDomain:@"MacCompanion.SelectedCapture" code:code userInfo:nil];
}

static BOOL SampleRejected(int stage) {
  if (getenv("MACCOMPANION_NATIVE_SELECTION_PATH")) fprintf(stderr,"selected-capture-sample-rejected=%d\n",stage);
  return NO;
}

static BOOL PositiveRect(CGRect rect) {
  return isfinite(rect.origin.x) && isfinite(rect.origin.y) && isfinite(rect.size.width)
    && isfinite(rect.size.height) && rect.size.width > 0 && rect.size.height > 0;
}

@interface CompanionSelectedCapture () {
  dispatch_queue_t _queue;
  id<CompanionSelectedCaptureSession> _session;
  CompanionSelectedCaptureCurrent _isCurrent;
  CompanionSelectedCaptureFrame _frame;
  CompanionSelectedCaptureTerminal _terminal;
  CompanionSelectedPhase _phase;
  NSError *_terminalError;
  NSInteger _width, _height, _sourceWidth, _sourceHeight;
  OSType _pixelFormat;
  CGColorRef _backgroundColor;
  uint64_t _lastDisplayTime;
  BOOL _startPending;
}
// Injectable local stream transport, used by deterministic lifecycle tests.
// It confers no authority and is not a wire entry point.
- (instancetype)initWithFactory:(id<CompanionSelectedCaptureSession> (^)(id<SCStreamOutput, SCStreamDelegate>, SCStreamConfiguration *))factory
    sourceRect:(CGRect)sourceRect sourcePixelWidth:(NSInteger)sourceWidth sourcePixelHeight:(NSInteger)sourceHeight
    encodedWidth:(NSInteger)width encodedHeight:(NSInteger)height pixelFormat:(OSType)pixelFormat
    isCurrent:(CompanionSelectedCaptureCurrent)isCurrent error:(NSError **)error;
@end

@implementation CompanionSelectedCapture

- (instancetype)initWithFilter:(SCContentFilter *)filter sourceRect:(CGRect)sourceRect
    sourcePixelWidth:(NSInteger)sourceWidth sourcePixelHeight:(NSInteger)sourceHeight
    encodedWidth:(NSInteger)width encodedHeight:(NSInteger)height pixelFormat:(OSType)pixelFormat
    isCurrent:(CompanionSelectedCaptureCurrent)isCurrent error:(NSError **)error {
  if (!filter) { if (error) *error = SelectedError(1); return nil; }
  return [self initWithFactory:^id<CompanionSelectedCaptureSession>(id<SCStreamOutput, SCStreamDelegate> output, SCStreamConfiguration *configuration) {
    return (id<CompanionSelectedCaptureSession>)[[SCStream alloc] initWithFilter:filter configuration:configuration delegate:output];
  } sourceRect:sourceRect sourcePixelWidth:sourceWidth sourcePixelHeight:sourceHeight
    encodedWidth:width encodedHeight:height pixelFormat:pixelFormat isCurrent:isCurrent error:error];
}

- (instancetype)initWithFactory:(id<CompanionSelectedCaptureSession> (^)(id<SCStreamOutput, SCStreamDelegate>, SCStreamConfiguration *))factory
    sourceRect:(CGRect)sourceRect sourcePixelWidth:(NSInteger)sourceWidth sourcePixelHeight:(NSInteger)sourceHeight
    encodedWidth:(NSInteger)width encodedHeight:(NSInteger)height pixelFormat:(OSType)pixelFormat
    isCurrent:(CompanionSelectedCaptureCurrent)isCurrent error:(NSError **)error {
  self = [super init];
  if (!self) return nil;
  if (!factory || !isCurrent || sourceWidth < 1 || sourceWidth > 32768 || sourceHeight < 1 || sourceHeight > 32768
      || width < 320 || width > 8192 || height < 240 || height > 8192
      || (!CGRectIsNull(sourceRect) && (!PositiveRect(sourceRect) || sourceRect.origin.x < 0 || sourceRect.origin.y < 0))
      || (pixelFormat != kCVPixelFormatType_32BGRA && pixelFormat != kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
          && pixelFormat != kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)) {
    if (error) *error = SelectedError(1);
    return nil;
  }
  _queue = dispatch_queue_create("MacCompanion.selectedCapture", DISPATCH_QUEUE_SERIAL);
  _width = width; _height = height; _sourceWidth = sourceWidth; _sourceHeight = sourceHeight;
  _pixelFormat = pixelFormat; _isCurrent = [isCurrent copy]; _phase = CompanionSelectedCreated;
  SCStreamConfiguration *configuration = [[SCStreamConfiguration alloc] init];
  configuration.width = width; configuration.height = height; configuration.pixelFormat = pixelFormat;
  configuration.minimumFrameInterval = CMTimeMake(1, 60); configuration.queueDepth = 3;
  configuration.scalesToFit = YES; configuration.preservesAspectRatio = YES;
  configuration.ignoreShadowsSingleWindow = YES; configuration.ignoreShadowsDisplay = YES;
  configuration.capturesAudio = NO;
  // SCStreamConfiguration declares this property assign. Keep the color alive
  // through SCStream's copy and the capture session's entire lifetime.
  _backgroundColor = CGColorCreateGenericRGB(0, 0, 0, 1);
  configuration.backgroundColor = _backgroundColor;
  if (!CGRectIsNull(sourceRect)) configuration.sourceRect = sourceRect;
  _session = factory(self, configuration);
  NSError *registrationError = nil;
  if (!_session || ![_session addStreamOutput:self type:SCStreamOutputTypeScreen sampleHandlerQueue:_queue error:&registrationError]) {
    if (error) *error = SelectedError(2);
    return nil;
  }
  return self;
}

- (void)dealloc {
  _session = nil;
  if (_backgroundColor) CGColorRelease(_backgroundColor);
}

- (void)startWithFrame:(CompanionSelectedCaptureFrame)frame terminal:(CompanionSelectedCaptureTerminal)terminal {
  dispatch_async(_queue, ^{
    if (self->_phase != CompanionSelectedCreated || !frame || !terminal) {
      if (terminal) terminal(SelectedError(3));
      return;
    }
    self->_frame = [frame copy]; self->_terminal = [terminal copy];
    if (!self->_isCurrent()) { [self finish:SelectedError(4) alreadyStopped:YES]; return; }
    self->_phase = CompanionSelectedStarting;
    self->_startPending = YES;
    [self->_session startCaptureWithCompletionHandler:^(NSError *error) {
      dispatch_async(self->_queue, ^{
        self->_startPending = NO;
        // Stop owns the terminal state even if start's completion arrives later.
        if (self->_phase == CompanionSelectedStopping) { [self stopSession]; return; }
        if (self->_phase != CompanionSelectedStarting) return;
        if (error || !self->_isCurrent()) { [self finish:SelectedError(error ? 2 : 4) alreadyStopped:NO]; return; }
        self->_phase = CompanionSelectedStreaming;
      });
    }];
  });
}

- (void)stop {
  dispatch_async(_queue, ^{ [self finish:nil alreadyStopped:self->_phase == CompanionSelectedCreated]; });
}

- (void)finish:(NSError *)error alreadyStopped:(BOOL)alreadyStopped {
  if (_phase == CompanionSelectedStopping || _phase == CompanionSelectedStopped) return;
  _phase = CompanionSelectedStopping;
  _frame = nil;
  _terminalError = error;
  if (alreadyStopped) { [self stopped]; return; }
  // Fence now, but join the in-flight start before asking the platform to stop.
  // Otherwise an early stop acknowledgement could precede a successful start.
  if (_startPending) return;
  [self stopSession];
}

- (void)stopSession {
  [_session stopCaptureWithCompletionHandler:^(NSError *stopError) {
    dispatch_async(self->_queue, ^{
      if (self->_phase != CompanionSelectedStopping) return;
      if (!self->_terminalError && stopError) self->_terminalError = SelectedError(5);
      [self stopped];
    });
  }];
}

- (void)stopped {
  _phase = CompanionSelectedStopped;
  NSError *removalError = nil;
  [_session removeStreamOutput:self type:SCStreamOutputTypeScreen error:&removalError];
  _session = nil; _isCurrent = nil;
  CompanionSelectedCaptureTerminal terminal = _terminal;
  _terminal = nil;
  if (terminal) terminal(_terminalError);
}

- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
  dispatch_async(_queue, ^{
    if ((id)stream != self->_session || self->_phase == CompanionSelectedStopped) return;
    if (self->_phase == CompanionSelectedStopping) { [self stopped]; return; }
    [self finish:SelectedError(5) alreadyStopped:YES];
  });
}

- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample ofType:(SCStreamOutputType)type {
  // ScreenCaptureKit invokes this on the registered serial queue.
  if ((id)stream != _session || type != SCStreamOutputTypeScreen
      || (_phase != CompanionSelectedStarting && _phase != CompanionSelectedStreaming)) return;
  if (!_isCurrent()) { [self finish:SelectedError(4) alreadyStopped:NO]; return; }
  if (!sample || !CMSampleBufferIsValid(sample) || !CMSampleBufferDataIsReady(sample)) {
    [self finish:SelectedError(6) alreadyStopped:NO]; return;
  }
  CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sample, NO);
  NSDictionary *info = attachments && CFArrayGetCount(attachments) == 1 ? (__bridge NSDictionary *)CFArrayGetValueAtIndex(attachments, 0) : nil;
  NSNumber *status = info[SCStreamFrameInfoStatus];
  if (![status isKindOfClass:[NSNumber class]] || CFGetTypeID((__bridge CFTypeRef)status) == CFBooleanGetTypeID()
      || !isfinite(status.doubleValue) || status.doubleValue != status.integerValue) {
    SampleRejected(1);
    [self finish:SelectedError(6) alreadyStopped:NO]; return;
  }
  if (status.integerValue == SCFrameStatusIdle || status.integerValue == SCFrameStatusBlank) return;
  if (status.integerValue != SCFrameStatusComplete || ![self sampleMatches:sample info:info]) {
    if (status.integerValue != SCFrameStatusComplete) SampleRejected(2);
    [self finish:SelectedError(6) alreadyStopped:NO]; return;
  }
  if (!_frame(sample)) [self finish:nil alreadyStopped:NO];
}

- (BOOL)sampleMatches:(CMSampleBufferRef)sample info:(NSDictionary *)info {
  CVPixelBufferRef pixels = CMSampleBufferGetImageBuffer(sample);
  CMVideoFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sample);
  if (!pixels || !format || CVPixelBufferGetWidth(pixels) != (size_t)_width || CVPixelBufferGetHeight(pixels) != (size_t)_height
      || CVPixelBufferGetPixelFormatType(pixels) != _pixelFormat) {
    return SampleRejected(3);
  }
  CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(format);
  CGRect aperture = CMVideoFormatDescriptionGetCleanAperture(format, YES);
  if (dimensions.width != _width || dimensions.height != _height
      || !CGRectEqualToRect(aperture, CGRectMake(0, 0, _width, _height))) {
    return SampleRejected(4);
  }
  NSNumber *displayTime = info[SCStreamFrameInfoDisplayTime];
  NSNumber *scale = info[SCStreamFrameInfoScaleFactor], *contentScale = info[SCStreamFrameInfoContentScale];
  NSDictionary *rectObject = info[SCStreamFrameInfoContentRect];
  CGRect rect;
  if (![displayTime isKindOfClass:[NSNumber class]] || ![scale isKindOfClass:[NSNumber class]]
      || ![contentScale isKindOfClass:[NSNumber class]] || ![rectObject isKindOfClass:[NSDictionary class]]
      || CFGetTypeID((__bridge CFTypeRef)displayTime) == CFBooleanGetTypeID()
      || CFGetTypeID((__bridge CFTypeRef)scale) == CFBooleanGetTypeID()
      || CFGetTypeID((__bridge CFTypeRef)contentScale) == CFBooleanGetTypeID()
      || !CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)rectObject, &rect) || !PositiveRect(rect)
      || !isfinite(scale.doubleValue) || scale.doubleValue < 1 || scale.doubleValue > 4
      || !isfinite(contentScale.doubleValue) || contentScale.doubleValue <= 0 || contentScale.doubleValue > 4) {
    return SampleRejected(5);
  }
  uint64_t ticks = displayTime.unsignedLongLongValue, now = mach_absolute_time();
  mach_timebase_info_data_t timebase = {0};
  if (!ticks) return SampleRejected(61);
  if (ticks <= _lastDisplayTime) return SampleRejected(62);
  if (mach_timebase_info(&timebase) != KERN_SUCCESS || !timebase.denom) return SampleRejected(63);
  if (ticks > now && ((__uint128_t)(ticks - now) * timebase.numer / timebase.denom) > 100000000) return SampleRejected(64);
  if (ticks <= now && ((__uint128_t)(now - ticks) * timebase.numer / timebase.denom) > 2000000000) return SampleRejected(65);
  double aspectScale = fmin((double)_width / _sourceWidth, (double)_height / _sourceHeight);
  double expectedWidth = _sourceWidth * aspectScale, expectedHeight = _sourceHeight * aspectScale;
  double factor = scale.doubleValue;
  if (fabs(rect.origin.x * factor - (_width - expectedWidth) / 2) > 1
      || fabs(rect.origin.y * factor - (_height - expectedHeight) / 2) > 1
      || fabs(rect.size.width * factor - expectedWidth) > 1 || fabs(rect.size.height * factor - expectedHeight) > 1) {
    return SampleRejected(7);
  }
  _lastDisplayTime = ticks;
  return YES;
}
@end
