#import "CompanionSelectedCapture.h"
#import <mach/mach_time.h>
#include "../Client/CompanionNativeSurfaceEpoch.h"
#include <math.h>

@interface SCStream (CompanionSelectedCaptureSession) <CompanionSelectedCaptureSession>
@end

typedef NS_ENUM(NSInteger, CompanionSelectedPhase) {
  CompanionSelectedCreated, CompanionSelectedStarting, CompanionSelectedStreaming, CompanionSelectedPaused, CompanionSelectedUpdating,
  CompanionSelectedStopping, CompanionSelectedStopped
};
static const void *SelectedCaptureQueueKey = &SelectedCaptureQueueKey;

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

static BOOL PlacementMatches(CGRect rect, double factor, NSInteger width, NSInteger height,
    NSInteger sourceWidth, NSInteger sourceHeight) {
  if (sourceWidth < 1 || sourceHeight < 1) return NO;
  double aspectScale = fmin((double)width / sourceWidth, (double)height / sourceHeight);
  double expectedWidth = sourceWidth * aspectScale, expectedHeight = sourceHeight * aspectScale;
  return fabs(rect.origin.x * factor - (width - expectedWidth) / 2) <= 1
    && fabs(rect.origin.y * factor - (height - expectedHeight) / 2) <= 1
    && fabs(rect.size.width * factor - expectedWidth) <= 1
    && fabs(rect.size.height * factor - expectedHeight) <= 1;
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
  uint64_t _minimumDisplayTime;
  uint64_t _placementDeadline, _placementGeneration;
  BOOL _awaitingPlacement;
  NSInteger _previousSourceWidth, _previousSourceHeight;
  unsigned _discardedPlacementReasons;
  BOOL _startPending;
  BOOL _updatePending, _stopRequested, _platformStopped;
  NSData *_frameEpoch;
  void (^_updateCompletion)(NSError *);
}
// Injectable local stream transport, used by deterministic lifecycle tests.
// It confers no authority and is not a wire entry point.
- (instancetype)initWithFactory:(id<CompanionSelectedCaptureSession> (^)(id<SCStreamOutput, SCStreamDelegate>, SCStreamConfiguration *))factory
    sourceRect:(CGRect)sourceRect sourcePixelWidth:(NSInteger)sourceWidth sourcePixelHeight:(NSInteger)sourceHeight
    encodedWidth:(NSInteger)width encodedHeight:(NSInteger)height pixelFormat:(OSType)pixelFormat
    isCurrent:(CompanionSelectedCaptureCurrent)isCurrent error:(NSError **)error;
@end

@implementation CompanionSelectedCapture

- (SCStreamConfiguration *)configurationForSourceRect:(CGRect)sourceRect
    sourcePixelWidth:(NSInteger)sourceWidth sourcePixelHeight:(NSInteger)sourceHeight {
  SCStreamConfiguration *configuration = [[SCStreamConfiguration alloc] init];
  configuration.width = _width; configuration.height = _height; configuration.pixelFormat = _pixelFormat;
  configuration.minimumFrameInterval = CMTimeMake(1, 60); configuration.queueDepth = 3;
  configuration.scalesToFit = YES; configuration.preservesAspectRatio = YES;
  double aspectScale = fmin((double)_width / sourceWidth, (double)_height / sourceHeight);
  double contentWidth = sourceWidth * aspectScale, contentHeight = sourceHeight * aspectScale;
  configuration.destinationRect = CGRectMake((_width - contentWidth) / 2,
      (_height - contentHeight) / 2, contentWidth, contentHeight);
  configuration.ignoreShadowsSingleWindow = YES; configuration.ignoreShadowsDisplay = YES;
  configuration.capturesAudio = NO; configuration.backgroundColor = _backgroundColor;
  if (!CGRectIsNull(sourceRect)) configuration.sourceRect = sourceRect;
  return configuration;
}

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
  dispatch_queue_set_specific(_queue, SelectedCaptureQueueKey, (__bridge void *)self, NULL);
  _width = width; _height = height; _sourceWidth = sourceWidth; _sourceHeight = sourceHeight;
  _pixelFormat = pixelFormat; _isCurrent = [isCurrent copy]; _phase = CompanionSelectedCreated;
  // ScreenCaptureKit's default independent-window placement is top-left.
  // Chroma-aligned output can have small padding even for a nearly matching
  // aspect ratio. Establish the same centered content rectangle that the
  // sample validator and input mapper require, rather than assuming centering.
  // SCStreamConfiguration declares this property assign. Keep the color alive
  // through SCStream's copy and the capture session's entire lifetime.
  _backgroundColor = CGColorCreateGenericRGB(0, 0, 0, 1);
  SCStreamConfiguration *configuration = [self configurationForSourceRect:sourceRect
      sourcePixelWidth:sourceWidth sourcePixelHeight:sourceHeight];
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
        if (self->_phase != CompanionSelectedStarting && self->_phase != CompanionSelectedStopping) return;
        self->_startPending = NO;
        // Stop owns the terminal state even if start's completion arrives later.
        if (self->_phase == CompanionSelectedStopping) {
          if (self->_platformStopped) [self stopped]; else [self stopSession];
          return;
        }
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

- (BOOL)configureInitialEpoch:(NSData *)epoch error:(NSError **)error {
  if (dispatch_get_specific(SelectedCaptureQueueKey) == (__bridge void *)self) {
    if (error) *error = SelectedError(3); return NO;
  }
  CompanionNativeSurfaceEpoch decoded;
  if (!CompanionNativeEpochDecode(epoch.bytes, epoch.length, &decoded)) {
    if (error) *error = SelectedError(1); return NO;
  }
  NSData *ownedEpoch = [epoch copy];
  __block BOOL configured = NO;
  dispatch_sync(_queue, ^{
    if (self->_phase == CompanionSelectedCreated) {
      self->_frameEpoch = ownedEpoch; configured = YES;
    }
  });
  if (!configured && error) *error = SelectedError(3);
  return configured;
}

- (void)pauseDeliveryWithCompletion:(void (^)(NSError *))completion {
  dispatch_async(_queue, ^{
    if (!completion) return;
    if (self->_phase != CompanionSelectedStreaming && self->_phase != CompanionSelectedPaused) {
      completion(SelectedError(3)); return;
    }
    self->_phase = CompanionSelectedPaused;
    completion(nil);
  });
}

- (void)updateFilter:(SCContentFilter *)filter sourceRect:(CGRect)sourceRect
    sourcePixelWidth:(NSInteger)sourceWidth sourcePixelHeight:(NSInteger)sourceHeight
    isCurrent:(CompanionSelectedCaptureCurrent)isCurrent completion:(void (^)(NSError *))completion {
  [self updateFilter:filter sourceRect:sourceRect sourcePixelWidth:sourceWidth sourcePixelHeight:sourceHeight
      isCurrent:isCurrent frameEpoch:nil completion:completion];
}

- (void)updateFilter:(SCContentFilter *)filter sourceRect:(CGRect)sourceRect
    sourcePixelWidth:(NSInteger)sourceWidth sourcePixelHeight:(NSInteger)sourceHeight
    isCurrent:(CompanionSelectedCaptureCurrent)isCurrent frameEpoch:(NSData *)epoch completion:(void (^)(NSError *))completion {
  NSData *ownedEpoch = [epoch copy];
  dispatch_async(_queue, ^{
    CompanionNativeSurfaceEpoch decoded;
    if ((self->_phase != CompanionSelectedStreaming && self->_phase != CompanionSelectedPaused)
        || !filter || !isCurrent || !completion
        || (ownedEpoch && !CompanionNativeEpochDecode(ownedEpoch.bytes, ownedEpoch.length, &decoded))
        || sourceWidth < 1 || sourceWidth > 32768 || sourceHeight < 1 || sourceHeight > 32768
        || (!CGRectIsNull(sourceRect) && (!PositiveRect(sourceRect) || sourceRect.origin.x < 0 || sourceRect.origin.y < 0))) {
      if (completion) completion(SelectedError(1));
      return;
    }
    // Reserve before platform callbacks. A second request cannot change this
    // request's selection, completion or geometry while it is suspended.
    self->_phase = CompanionSelectedUpdating;
    self->_awaitingPlacement = NO;
    self->_placementGeneration += 1;
    self->_updatePending = YES;
    self->_updateCompletion = [completion copy];
    if (!isCurrent()) { [self updateFinished:SelectedError(4)]; return; }
    SCStreamConfiguration *configuration = [self configurationForSourceRect:sourceRect
        sourcePixelWidth:sourceWidth sourcePixelHeight:sourceHeight];
    [self->_session updateContentFilter:filter completionHandler:^(NSError *filterError) {
      dispatch_async(self->_queue, ^{
        if (self->_phase != CompanionSelectedUpdating && self->_phase != CompanionSelectedStopping) return;
        if (self->_phase == CompanionSelectedStopping || filterError) {
          [self updateFinished:filterError ? SelectedError(7) : SelectedError(3)]; return;
        }
        if (!isCurrent()) { [self updateFinished:SelectedError(4)]; return; }
        [self->_session updateConfiguration:configuration completionHandler:^(NSError *configurationError) {
          dispatch_async(self->_queue, ^{
            if (self->_phase != CompanionSelectedUpdating && self->_phase != CompanionSelectedStopping) return;
            if (self->_phase == CompanionSelectedStopping || configurationError || !isCurrent()) {
              [self updateFinished:SelectedError(configurationError ? 8 : 4)]; return;
            }
            self->_previousSourceWidth = self->_sourceWidth; self->_previousSourceHeight = self->_sourceHeight;
            self->_sourceWidth = sourceWidth; self->_sourceHeight = sourceHeight;
            self->_isCurrent = [isCurrent copy];
            self->_frameEpoch = ownedEpoch;
            // Drop queued samples from before both platform completions, even
            // if the previous view happened to have identical dimensions.
            mach_timebase_info_data_t timebase = {0};
            if (mach_timebase_info(&timebase) != KERN_SUCCESS || !timebase.numer || !timebase.denom) {
              [self updateFinished:SelectedError(8)]; return;
            }
            uint64_t lead = (uint64_t)(((__uint128_t)100000000 * timebase.denom + timebase.numer - 1) / timebase.numer);
            uint64_t settlement = (uint64_t)(((__uint128_t)2000000000 * timebase.denom + timebase.numer - 1) / timebase.numer);
            uint64_t ticks = mach_absolute_time();
            if (ticks > UINT64_MAX - lead || ticks > UINT64_MAX - settlement) { [self updateFinished:SelectedError(8)]; return; }
            self->_minimumDisplayTime = ticks + lead;
            self->_placementDeadline = ticks + settlement;
            self->_awaitingPlacement = YES;
            self->_discardedPlacementReasons = 0;
            uint64_t generation = ++self->_placementGeneration;
            self->_phase = CompanionSelectedStreaming;
            __weak CompanionSelectedCapture *weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2000000000), self->_queue, ^{
              CompanionSelectedCapture *owner = weakSelf;
              if (!owner || owner->_phase != CompanionSelectedStreaming || !owner->_awaitingPlacement
                  || owner->_placementGeneration != generation) return;
              [owner finish:SelectedError(owner->_isCurrent() ? 9 : 4) alreadyStopped:NO];
            });
            [self updateFinished:nil];
          });
        }];
      });
    }];
  });
}

- (void)updateFinished:(NSError *)error {
  if (!_updatePending) return;
  _updatePending = NO;
  if (_phase == CompanionSelectedStopping) {
    if (_platformStopped) [self stopped]; else [self stopSession];
    return;
  }
  if (error) { [self finish:error alreadyStopped:NO]; return; }
  void (^completion)(NSError *) = _updateCompletion;
  _updateCompletion = nil;
  if (completion) completion(nil);
}

- (void)finish:(NSError *)error alreadyStopped:(BOOL)alreadyStopped {
  if (_phase == CompanionSelectedStopping || _phase == CompanionSelectedStopped) return;
  _phase = CompanionSelectedStopping;
  _frame = nil;
  _terminalError = error;
  _platformStopped = alreadyStopped;
  // Fence now, but join the in-flight start before asking the platform to stop.
  // Otherwise an early stop acknowledgement could precede a successful start.
  if (_startPending || _updatePending) return;
  if (_platformStopped) { [self stopped]; return; }
  [self stopSession];
}

- (void)stopSession {
  if (_stopRequested) return;
  _stopRequested = YES;
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
  void (^updateCompletion)(NSError *) = _updateCompletion;
  _updateCompletion = nil;
  if (updateCompletion) updateCompletion(_terminalError ?: SelectedError(3));
  CompanionSelectedCaptureTerminal terminal = _terminal;
  _terminal = nil;
  if (terminal) terminal(_terminalError);
}

- (void)stream:(SCStream *)stream didStopWithError:(NSError *)error {
  dispatch_async(_queue, ^{
    if ((id)stream != self->_session || self->_phase == CompanionSelectedStopped) return;
    if (self->_phase == CompanionSelectedStopping) {
      self->_platformStopped = YES;
      if (!self->_startPending && !self->_updatePending) [self stopped];
      return;
    }
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
  if (_minimumDisplayTime) {
    NSNumber *displayTime = info[SCStreamFrameInfoDisplayTime];
    if (![displayTime isKindOfClass:[NSNumber class]] || CFGetTypeID((__bridge CFTypeRef)displayTime) == CFBooleanGetTypeID()
        || !isfinite(displayTime.doubleValue) || displayTime.doubleValue < 1) {
      [self finish:SelectedError(6) alreadyStopped:NO]; return;
    }
    if (displayTime.unsignedLongLongValue <= _minimumDisplayTime) return;
  }
  if (_awaitingPlacement && mach_absolute_time() >= _placementDeadline) {
    [self finish:SelectedError(9) alreadyStopped:NO]; return;
  }
  int rejection = status.integerValue == SCFrameStatusComplete ? [self sampleRejection:sample info:info] : 2;
  if (rejection) {
    // A timestamp cutover alone does not establish that platform placement has
    // settled. Reject pixels while awaiting the first exact new geometry; do
    // not tag, encode, refresh evidence or admit input from this sample.
    if (rejection == 7 && _awaitingPlacement && mach_absolute_time() < _placementDeadline) {
      CGRect rect; CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)info[SCStreamFrameInfoContentRect], &rect);
      int reason = PlacementMatches(rect, [info[SCStreamFrameInfoScaleFactor] doubleValue], _width, _height,
          _previousSourceWidth, _previousSourceHeight) ? 1 : 2;
      unsigned bit = 1u << reason;
      if (!(_discardedPlacementReasons & bit)) {
        _discardedPlacementReasons |= bit;
        if (getenv("MACCOMPANION_NATIVE_SELECTION_PATH")) fprintf(stderr,"selected-capture-placement-discarded=%d\n",reason);
      }
      return;
    }
    SampleRejected(rejection);
    [self finish:SelectedError(6) alreadyStopped:NO]; return;
  }
  _awaitingPlacement = NO;
  if (_frameEpoch) {
    CMSetAttachment(sample, CFSTR(CompanionNativeSurfaceEpochAttachment), (__bridge CFDataRef)_frameEpoch,
        kCMAttachmentMode_ShouldNotPropagate);
  }
  if (!_frame(sample)) [self finish:nil alreadyStopped:NO];
}

- (int)sampleRejection:(CMSampleBufferRef)sample info:(NSDictionary *)info {
  CVPixelBufferRef pixels = CMSampleBufferGetImageBuffer(sample);
  CMVideoFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sample);
  if (!pixels || !format || CVPixelBufferGetWidth(pixels) != (size_t)_width || CVPixelBufferGetHeight(pixels) != (size_t)_height
      || CVPixelBufferGetPixelFormatType(pixels) != _pixelFormat) {
    return 3;
  }
  CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(format);
  CGRect aperture = CMVideoFormatDescriptionGetCleanAperture(format, YES);
  if (dimensions.width != _width || dimensions.height != _height
      || !CGRectEqualToRect(aperture, CGRectMake(0, 0, _width, _height))) {
    return 4;
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
    return 5;
  }
  uint64_t ticks = displayTime.unsignedLongLongValue, now = mach_absolute_time();
  mach_timebase_info_data_t timebase = {0};
  if (!ticks) return 61;
  if (ticks <= _lastDisplayTime) return 62;
  if (mach_timebase_info(&timebase) != KERN_SUCCESS || !timebase.denom) return 63;
  if (ticks > now && ((__uint128_t)(ticks - now) * timebase.numer / timebase.denom) > 100000000) return 64;
  if (ticks <= now && ((__uint128_t)(now - ticks) * timebase.numer / timebase.denom) > 2000000000) return 65;
  if (!PlacementMatches(rect, scale.doubleValue, _width, _height, _sourceWidth, _sourceHeight)) return 7;
  _lastDisplayTime = ticks;
  return 0;
}
@end
