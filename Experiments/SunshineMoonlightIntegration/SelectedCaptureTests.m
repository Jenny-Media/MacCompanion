#import "CompanionSelectedCapture.h"
#import <mach/mach_time.h>
#include <stdatomic.h>

@interface CompanionSelectedCapture (LocalTestTransport)
- (instancetype)initWithFactory:(id<CompanionSelectedCaptureSession> (^)(id<SCStreamOutput, SCStreamDelegate>, SCStreamConfiguration *))factory
    sourceRect:(CGRect)sourceRect sourcePixelWidth:(NSInteger)sourceWidth sourcePixelHeight:(NSInteger)sourceHeight
    encodedWidth:(NSInteger)width encodedHeight:(NSInteger)height pixelFormat:(OSType)pixelFormat
    isCurrent:(CompanionSelectedCaptureCurrent)isCurrent error:(NSError **)error;
@end

static void Require(BOOL value) { if (!value) abort(); }
static void Wait(dispatch_semaphore_t signal) { Require(dispatch_semaphore_wait(signal, dispatch_time(DISPATCH_TIME_NOW, 2000000000)) == 0); }

@interface SelectedTestSession : NSObject <CompanionSelectedCaptureSession>
@property(strong) id<SCStreamOutput, SCStreamDelegate> output;
@property(strong) dispatch_queue_t queue;
@property(strong) dispatch_semaphore_t startEntered, stopEntered;
@property(copy) void (^startCompletion)(NSError *);
@property(copy) void (^stopCompletion)(NSError *);
@property(atomic) NSInteger starts, stops, removals;
@property(strong) dispatch_semaphore_t filterEntered, configurationEntered;
@property(copy) void (^filterCompletion)(NSError *), (^configurationCompletion)(NSError *);
@property(strong) SCStreamConfiguration *updatedConfiguration;
- (void)completeStart;
- (void)completeStop;
- (void)emit:(CMSampleBufferRef)sample;
- (void)flush;
@end

@implementation SelectedTestSession
- (instancetype)init { self = [super init]; if (self) {
  _startEntered = dispatch_semaphore_create(0); _stopEntered = dispatch_semaphore_create(0);
  _filterEntered = dispatch_semaphore_create(0); _configurationEntered = dispatch_semaphore_create(0);
} return self; }
- (BOOL)addStreamOutput:(id<SCStreamOutput>)output type:(SCStreamOutputType)type sampleHandlerQueue:(dispatch_queue_t)queue error:(NSError **)error {
  (void)error; Require(type == SCStreamOutputTypeScreen); self.output = (id)output; self.queue = queue; return YES;
}
- (BOOL)removeStreamOutput:(id<SCStreamOutput>)output type:(SCStreamOutputType)type error:(NSError **)error {
  (void)error; Require(output == self.output && type == SCStreamOutputTypeScreen); self.output = nil; self.removals += 1; return YES;
}
- (void)startCaptureWithCompletionHandler:(void (^)(NSError *))completion { self.starts += 1; self.startCompletion = completion; dispatch_semaphore_signal(self.startEntered); }
- (void)stopCaptureWithCompletionHandler:(void (^)(NSError *))completion { self.stops += 1; self.stopCompletion = completion; dispatch_semaphore_signal(self.stopEntered); }
- (void)updateContentFilter:(SCContentFilter *)filter completionHandler:(void (^)(NSError *))completion {
  Require(filter != nil && self.filterCompletion == nil); self.filterCompletion = completion; dispatch_semaphore_signal(self.filterEntered);
}
- (void)updateConfiguration:(SCStreamConfiguration *)configuration completionHandler:(void (^)(NSError *))completion {
  Require(configuration != nil && self.configurationCompletion == nil); self.updatedConfiguration = configuration;
  self.configurationCompletion = completion; dispatch_semaphore_signal(self.configurationEntered);
}
- (void)completeStart { void (^completion)(NSError *) = self.startCompletion; self.startCompletion = nil; Require(completion != nil); completion(nil); [self flush]; }
- (void)completeStop { void (^completion)(NSError *) = self.stopCompletion; self.stopCompletion = nil; Require(completion != nil); completion(nil); [self flush]; }
- (void)emit:(CMSampleBufferRef)sample {
  id<SCStreamOutput> output = self.output;
  CFRetain(sample);
  dispatch_async(self.queue, ^{ [output stream:(SCStream *)self didOutputSampleBuffer:sample ofType:SCStreamOutputTypeScreen]; CFRelease(sample); });
  [self flush];
}
- (void)flush { dispatch_sync(self.queue, ^{}); }
@end

static CompanionSelectedCapture *Capture(SelectedTestSession *session, CompanionSelectedCaptureCurrent current) {
  NSError *error = nil;
  CompanionSelectedCapture *capture = [[CompanionSelectedCapture alloc] initWithFactory:^id<CompanionSelectedCaptureSession>(id<SCStreamOutput, SCStreamDelegate> output, SCStreamConfiguration *configuration) {
    (void)output;
    Require(configuration.width == 320 && configuration.height == 240 && configuration.scalesToFit && configuration.preservesAspectRatio);
    Require(configuration.ignoreShadowsSingleWindow && configuration.ignoreShadowsDisplay && !configuration.capturesAudio);
    return session;
  } sourceRect:CGRectNull sourcePixelWidth:640 sourcePixelHeight:360 encodedWidth:320 encodedHeight:240
    pixelFormat:kCVPixelFormatType_32BGRA isCurrent:current error:&error];
  Require(capture != nil && error == nil && session.starts == 0 && session.stops == 0);
  return capture;
}

static CMSampleBufferRef Sample(NSInteger width, NSInteger height, NSInteger status, NSInteger alteration) CF_RETURNS_RETAINED {
  CVPixelBufferRef pixels = nil;
  Require(CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &pixels) == kCVReturnSuccess);
  CMVideoFormatDescriptionRef format = nil;
  Require(CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pixels, &format) == noErr);
  CMSampleTimingInfo timing = { CMTimeMake(1,60), CMTimeMake(1,60), kCMTimeInvalid };
  CMSampleBufferRef sample = nil;
  Require(CMSampleBufferCreateReadyWithImageBuffer(kCFAllocatorDefault, pixels, format, &timing, &sample) == noErr);
  CFRelease(format); CFRelease(pixels);
  NSMutableDictionary *info = (__bridge NSMutableDictionary *)CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sample, YES), 0);
  info[SCStreamFrameInfoStatus] = @(status);
  info[SCStreamFrameInfoDisplayTime] = @(mach_absolute_time());
  info[SCStreamFrameInfoScaleFactor] = @2;
  info[SCStreamFrameInfoContentScale] = @0.5;
  CGRect rect = CGRectMake(0,15,160,90);
  if (alteration == 1) rect.origin.x = 2;
  if (alteration == 2) rect.size.width = 150;
  info[SCStreamFrameInfoContentRect] = CFBridgingRelease(CGRectCreateDictionaryRepresentation(rect));
  if (alteration == 3) info[SCStreamFrameInfoContentScale] = @0;
  if (alteration == 4) info[SCStreamFrameInfoScaleFactor] = @0;
  if (alteration == 5) [info removeObjectForKey:SCStreamFrameInfoContentRect];
  if (alteration == 6) info[SCStreamFrameInfoDisplayTime] = @0;
  if (alteration == 7) info[SCStreamFrameInfoDisplayTime] = @(UINT64_MAX);
  if (alteration == 8) info[SCStreamFrameInfoStatus] = @0.5;
  if (alteration == 9) info[SCStreamFrameInfoStatus] = @NO;
  if (alteration == 12) info[SCStreamFrameInfoScaleFactor] = @YES;
  if (alteration == 13) info[SCStreamFrameInfoContentScale] = @YES;
  if (alteration == 14 || alteration == 15) {
    mach_timebase_info_data_t scale = {0};
    Require(mach_timebase_info(&scale) == KERN_SUCCESS && scale.numer && scale.denom);
    uint64_t futureNanoseconds = alteration == 14 ? 50000000ULL : 500000000ULL;
    uint64_t futureTicks = (uint64_t)((__uint128_t)futureNanoseconds * scale.denom / scale.numer);
    info[SCStreamFrameInfoDisplayTime] = @(mach_absolute_time() + futureTicks);
  }
  return sample;
}

static void AcceptScheduledDisplaySample(void) {
  SelectedTestSession *session = [SelectedTestSession new];
  CompanionSelectedCapture *capture = Capture(session, ^BOOL { return YES; });
  __block NSInteger frames = 0;
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  [capture startWithFrame:^BOOL(CMSampleBufferRef sample) { (void)sample; frames += 1; return YES; } terminal:^(NSError *error) {
    Require(error == nil); dispatch_semaphore_signal(done);
  }];
  Wait(session.startEntered); [session completeStart];
  CMSampleBufferRef sample = Sample(320,240,SCFrameStatusComplete,14);
  [session emit:sample]; CFRelease(sample); Require(frames == 1);
  [capture stop]; Wait(session.stopEntered); [session completeStop]; Wait(done);
}

static void DeniedBeforeStart(void) {
  SelectedTestSession *session = [SelectedTestSession new];
  CompanionSelectedCapture *capture = Capture(session, ^BOOL { return NO; });
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  [capture startWithFrame:^BOOL(CMSampleBufferRef sample) { (void)sample; abort(); } terminal:^(NSError *error) {
    Require(error.code == 4); dispatch_semaphore_signal(done);
  }];
  Wait(done); Require(session.starts == 0 && session.stops == 0 && session.removals == 1);
}

static void StopJoinsPendingStart(void) {
  SelectedTestSession *session = [SelectedTestSession new];
  CompanionSelectedCapture *capture = Capture(session, ^BOOL { return YES; });
  __block NSInteger terminals = 0;
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  [capture startWithFrame:^BOOL(CMSampleBufferRef sample) { (void)sample; abort(); } terminal:^(NSError *error) {
    Require(error == nil); terminals += 1; dispatch_semaphore_signal(done);
  }];
  Wait(session.startEntered); [capture stop]; [session flush];
  Require(session.stops == 0 && terminals == 0);
  CMSampleBufferRef sample = Sample(320,240,SCFrameStatusComplete,0);
  [session emit:sample]; CFRelease(sample);
  [session completeStart]; Wait(session.stopEntered);
  Require(terminals == 0);
  sample = Sample(320,240,SCFrameStatusComplete,0); [session emit:sample]; CFRelease(sample);
  [capture stop]; [session flush]; Require(session.stops == 1);
  [session completeStop]; Wait(done); Require(terminals == 1 && session.removals == 1);
  [capture stop]; [session flush]; Require(session.stops == 1 && terminals == 1);
}

static void FrameBeforeStartReplyCanFinishCapture(void) {
  SelectedTestSession *session = [SelectedTestSession new];
  CompanionSelectedCapture *capture = Capture(session, ^BOOL { return YES; });
  __block NSInteger frames = 0;
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  [capture startWithFrame:^BOOL(CMSampleBufferRef sample) { (void)sample; frames += 1; return NO; } terminal:^(NSError *error) {
    Require(error == nil); dispatch_semaphore_signal(done);
  }];
  Wait(session.startEntered);
  CMSampleBufferRef sample = Sample(320,240,SCFrameStatusComplete,0); [session emit:sample]; CFRelease(sample);
  Require(frames == 1 && session.stops == 0);
  [session completeStart]; Wait(session.stopEntered); [session completeStop]; Wait(done);
  Require(frames == 1 && session.stops == 1);
}

static void RevocationFencesFrame(void) {
  SelectedTestSession *session = [SelectedTestSession new];
  __block atomic_bool current; atomic_init(&current, true);
  CompanionSelectedCapture *capture = Capture(session, ^BOOL { return atomic_load(&current); });
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  [capture startWithFrame:^BOOL(CMSampleBufferRef sample) { (void)sample; abort(); } terminal:^(NSError *error) {
    Require(error.code == 4); dispatch_semaphore_signal(done);
  }];
  Wait(session.startEntered); [session completeStart]; atomic_store(&current, false);
  CMSampleBufferRef sample = Sample(320,240,SCFrameStatusComplete,0); [session emit:sample]; CFRelease(sample);
  Wait(session.stopEntered); [session completeStop]; Wait(done);
}

static void RejectChangedCompleteSample(NSInteger alteration) {
  SelectedTestSession *session = [SelectedTestSession new];
  CompanionSelectedCapture *capture = Capture(session, ^BOOL { return YES; });
  __block NSInteger frames = 0;
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  [capture startWithFrame:^BOOL(CMSampleBufferRef sample) { (void)sample; frames += 1; return YES; } terminal:^(NSError *error) {
    Require(error.code == 6); dispatch_semaphore_signal(done);
  }];
  Wait(session.startEntered); [session completeStart];
  CMSampleBufferRef idle = Sample(320,240,SCFrameStatusIdle,0); [session emit:idle]; CFRelease(idle); Require(frames == 0);
  CMSampleBufferRef first = Sample(320,240,SCFrameStatusComplete,0); [session emit:first]; Require(frames == 1);
  CMSampleBufferRef changed = alteration == 10 ? Sample(640,480,SCFrameStatusComplete,0)
    : alteration == 11 ? (CMSampleBufferRef)CFRetain(first) : Sample(320,240,SCFrameStatusComplete,alteration);
  [session emit:changed]; CFRelease(changed); CFRelease(first);
  Wait(session.stopEntered); Require(frames == 1);
  [session completeStop]; Wait(done); Require(session.removals == 1);
}

static void RequireCenteredCapturePlacement(NSString *fixturePath) {
  NSDictionary *fixture = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:fixturePath] options:0 error:nil];
  NSArray *cases = fixture[@"capturePlacementCases"];
  Require(cases.count == 3);
  for (NSDictionary *value in cases) {
    SelectedTestSession *session = [SelectedTestSession new];
    NSError *error = nil;
    CompanionSelectedCapture *capture = [[CompanionSelectedCapture alloc] initWithFactory:^id<CompanionSelectedCaptureSession>(id<SCStreamOutput, SCStreamDelegate> output, SCStreamConfiguration *configuration) {
      (void)output;
      NSArray *rect = value[@"destinationRect"];
      CGRect expected = CGRectMake([rect[0] doubleValue], [rect[1] doubleValue], [rect[2] doubleValue], [rect[3] doubleValue]);
      Require(CGRectEqualToRect(configuration.destinationRect, expected));
      return session;
    } sourceRect:CGRectNull sourcePixelWidth:[value[@"sourceWidth"] integerValue] sourcePixelHeight:[value[@"sourceHeight"] integerValue]
      encodedWidth:[value[@"encodedWidth"] integerValue] encodedHeight:[value[@"encodedHeight"] integerValue]
      pixelFormat:kCVPixelFormatType_32BGRA isCurrent:^BOOL { return YES; } error:&error];
    Require(capture != nil && error == nil && session.starts == 0);
  }
}

static void CompleteUpdate(SelectedTestSession *session, BOOL configuration, NSError *error) {
  void (^completion)(NSError *) = configuration ? session.configurationCompletion : session.filterCompletion;
  if (configuration) session.configurationCompletion = nil; else session.filterCompletion = nil;
  Require(completion != nil); completion(error); [session flush];
}

static void ReconfigureStream(NSString *name) {
  SelectedTestSession *session = [SelectedTestSession new];
  __block atomic_bool newCurrent; atomic_init(&newCurrent, true);
  CompanionSelectedCapture *capture = Capture(session, ^BOOL { return YES; });
  __block NSInteger frames = 0, updates = 0, terminals = 0;
  __block NSError *updateError = nil, *terminalError = nil;
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  [capture startWithFrame:^BOOL(CMSampleBufferRef sample) { (void)sample; frames += 1; return YES; }
      terminal:^(NSError *error) { terminalError = error; terminals += 1; dispatch_semaphore_signal(done); }];
  Wait(session.startEntered); [session completeStart];
  CMSampleBufferRef oldSample = Sample(320,240,SCFrameStatusComplete,
      [name isEqual:@"switch-drops-scheduled-old-sample"] ? 14 : 0);
  BOOL invalid = [name isEqual:@"invalid-update-cannot-change-canvas-or-owner"];
  // The injected session never uses this object as a real platform filter.
  SCContentFilter *filter = (SCContentFilter *)[NSObject new];
  [capture updateFilter:filter sourceRect:CGRectNull sourcePixelWidth:invalid ? 0 : 480 sourcePixelHeight:640
      isCurrent:^BOOL { return atomic_load(&newCurrent); } completion:^(NSError *error) {
        updateError = error; updates += 1;
      }];
  [session flush];
  if (invalid) {
    Require(updates == 1 && updateError.code == 1 && session.filterCompletion == nil && terminals == 0);
    [session emit:oldSample]; Require(frames == 1);
    [capture stop]; Wait(session.stopEntered); [session completeStop]; Wait(done);
    CFRelease(oldSample); return;
  }
  Wait(session.filterEntered);
  [session emit:oldSample]; Require(frames == 0 && updates == 0);
  if ([name isEqual:@"concurrent-update-denied-without-changing-first-update"]) {
    __block NSInteger denied = 0;
    [capture updateFilter:filter sourceRect:CGRectNull sourcePixelWidth:640 sourcePixelHeight:360
        isCurrent:^BOOL { return YES; } completion:^(NSError *error) { Require(error.code == 1); denied += 1; }];
    [session flush]; Require(denied == 1 && updates == 0);
  }
  BOOL stop = [name hasPrefix:@"stop-"];
  NSError *failure = [NSError errorWithDomain:@"Synthetic.Update" code:1 userInfo:nil];
  BOOL configurationStop = [name isEqual:@"stop-during-configuration-joins-before-terminal"];
  if ([name isEqual:@"platform-stop-during-update-cannot-reopen-stream"]) {
    [session.output stream:(SCStream *)session didStopWithError:failure]; [session flush];
    Require(terminals == 0 && updates == 0 && session.stops == 0);
    CompleteUpdate(session, NO, nil); Wait(done);
    Require(updates == 1 && updateError.code == 5 && terminalError.code == 5 && session.stops == 0);
    Require(session.configurationCompletion == nil && session.removals == 1);
    CFRelease(oldSample); return;
  }
  if (stop && !configurationStop) {
    [capture stop]; [session flush]; Require(session.stops == 0 && terminals == 0 && updates == 0);
  }
  BOOL filterFailure = [name isEqual:@"switch-filter-failure-drains"];
  CompleteUpdate(session, NO, filterFailure ? failure : nil);
  if ((stop && !configurationStop) || filterFailure) {
    Wait(session.stopEntered); Require(terminals == 0 && updates == 0 && session.configurationCompletion == nil);
    [session emit:oldSample]; Require(frames == 0);
    [session completeStop]; Wait(done);
    Require(updates == 1 && updateError != nil && terminals == 1 && session.removals == 1);
    Require(stop ? terminalError == nil : terminalError.code == 7);
    CFRelease(oldSample); return;
  }
  Wait(session.configurationEntered);
  Require(session.updatedConfiguration.width == 320 && session.updatedConfiguration.height == 240);
  Require(CGRectEqualToRect(session.updatedConfiguration.destinationRect, CGRectMake(70,0,180,240)));
  [session emit:oldSample]; Require(frames == 0 && updates == 0);
  if (configurationStop) {
    [capture stop]; [session flush]; Require(terminals == 0 && updates == 0 && session.stops == 0);
    CompleteUpdate(session, YES, nil); Wait(session.stopEntered);
    Require(terminals == 0 && updates == 0);
    [session emit:oldSample]; Require(frames == 0);
    [session completeStop]; Wait(done);
    Require(updates == 1 && updateError != nil && terminalError == nil && terminals == 1 && session.removals == 1);
    CFRelease(oldSample); return;
  }
  BOOL configurationFailure = [name isEqual:@"switch-configuration-failure-drains"];
  CompleteUpdate(session, YES, configurationFailure ? failure : nil);
  if (configurationFailure) {
    Wait(session.stopEntered); Require(updates == 0 && terminals == 0);
    [session completeStop]; Wait(done);
    Require(updates == 1 && updateError.code == 8 && terminalError.code == 8);
    CFRelease(oldSample); return;
  }
  Require(updates == 1 && updateError == nil && session.starts == 1 && session.stops == 0);
  // This frame has the old timestamp and old geometry. It must be dropped
  // before geometry validation, rather than terminating the new selection.
  [session emit:oldSample]; Require(frames == 0 && terminals == 0 && session.stops == 0);
  CFRelease(oldSample);
  BOOL revoked = [name isEqual:@"switch-revalidates-new-owner-before-delivery"];
  if (revoked) atomic_store(&newCurrent, false);
  CMSampleBufferRef newSample = Sample(320,240,SCFrameStatusComplete,0);
  NSMutableDictionary *info = (__bridge NSMutableDictionary *)CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(newSample, YES),0);
  mach_timebase_info_data_t timebase = {0};
  Require(mach_timebase_info(&timebase) == KERN_SUCCESS && timebase.numer && timebase.denom);
  info[SCStreamFrameInfoDisplayTime] = @(mach_absolute_time() + (uint64_t)((__uint128_t)100000000 * timebase.denom / timebase.numer));
  info[SCStreamFrameInfoContentRect] = CFBridgingRelease(CGRectCreateDictionaryRepresentation(CGRectMake(35,0,90,120)));
  [session emit:newSample]; CFRelease(newSample);
  Require(frames == (revoked ? 0 : 1));
  if (!revoked) [capture stop];
  Wait(session.stopEntered); [session completeStop]; Wait(done);
  Require(terminalError == nil || (revoked && terminalError.code == 4));
  Require(terminals == 1 && session.starts == 1 && session.stops == 1 && session.removals == 1);
}

static void RequireIndexedContinuity(NSString *path) {
  NSDictionary *fixture = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:0 error:nil];
  NSArray *cases = fixture[@"streamCases"];
  Require(cases.count == 14);
  for (NSString *name in cases) ReconfigureStream(name);
}

int main(int argc, const char **argv) {
  @autoreleasepool {
    Require(argc == 3);
    RequireCenteredCapturePlacement([NSString stringWithUTF8String:argv[1]]);
    DeniedBeforeStart(); StopJoinsPendingStart(); FrameBeforeStartReplyCanFinishCapture(); RevocationFencesFrame();
    AcceptScheduledDisplaySample();
    for (NSInteger alteration = 1; alteration <= 13; alteration++) RejectChangedCompleteSample(alteration);
    RejectChangedCompleteSample(15);
    RequireIndexedContinuity([NSString stringWithUTF8String:argv[2]]);
    puts("Selected capture: 19 lifecycle/sample, 3 indexed placement and 14 indexed continuity cases passed; synthetic samples, no capture permission or input effects.");
  }
  return 0;
}
