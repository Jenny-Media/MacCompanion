#import "av_video.h"
#import <mach/mach_time.h>
#include <stdlib.h>
#include <unistd.h>

@interface AVVideo (CaptureOwnerProbe)
- (void)selectedCaptureDidTerminate:(CompanionSelectedCapture *)stream error:(NSError *)error completion:(dispatch_block_t)completion;
@end
@interface CompanionSelectedCaptureHandoff (CaptureOwnerProbe)
- (dispatch_queue_t)deliveryQueue;
- (void)consumeData:(NSData *)data now:(uint64_t)now;
@end
@interface InertBridgeStream : NSObject
@property NSUInteger stops;
- (void)stop;
@end
@implementation InertBridgeStream
- (void)stop { self.stops++; }
@end

static void Require(BOOL value) { if (!value) abort(); }

static NSData *Canonical(id value) {
  return [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes error:nil];
}
static void ProbeOwnerHandoff(NSDictionary *fixture) {
  Require([fixture[@"captureOwnerLifecycleCases"] count] == 3);
  mach_timebase_info_data_t scale; Require(mach_timebase_info(&scale) == KERN_SUCCESS && scale.denom);
  uint64_t now = (uint64_t)((__uint128_t)mach_absolute_time() * scale.numer / scale.denom);
  NSMutableDictionary *initial = [fixture[@"childHandoff"][@"initialContext"] mutableCopy];
  initial[@"expiresAtMonotonicNanoseconds"] = @(now + 30000000000ULL);
  CompanionSelectedCaptureContext *context = [CompanionSelectedCaptureContext parseData:Canonical(initial)
      operationID:initial[@"operationID"] displayID:[initial[@"displayID"] unsignedIntValue] now:now error:nil];
  Require(context != nil);
  char template[] = "/private/tmp/maccompanion-bridge-owner.XXXXXX";
  char *folder = mkdtemp(template); Require(folder != NULL);
  NSString *directory = [NSString stringWithUTF8String:folder];
  AVVideo *bridge = [AVVideo new]; bridge.selectedStreams = [NSMutableArray new];
  InertBridgeStream *oldStream = [InertBridgeStream new];
  [bridge.selectedStreams addObject:(id)oldStream];
  __block CompanionCaptureHandoffCompletion pendingPause = nil;
  __block NSUInteger terminals = 0;
  CompanionSelectedCaptureHandoff *oldOwner = [[CompanionSelectedCaptureHandoff alloc]
      initWithDirectory:directory initialContext:context
      pause:^(CompanionCaptureHandoffCompletion completion) { pendingPause = completion; }
      select:^(CompanionSelectedCaptureContext *next, CompanionCaptureHandoffCompletion completion) { (void)next; completion(nil); }
      terminal:^(NSError *error) { Require(error == nil); terminals++; } error:nil];
  Require(oldOwner != nil); bridge.selectedHandoff = oldOwner; [oldOwner start];
  NSMutableDictionary *pause = [fixture[@"childHandoff"][@"pause"] mutableCopy];
  pause[@"expiresAtMonotonicNanoseconds"] = initial[@"expiresAtMonotonicNanoseconds"];
  dispatch_sync(oldOwner.deliveryQueue, ^{ [oldOwner consumeData:Canonical(pause) now:now]; });
  Require(pendingPause != nil);
  dispatch_semaphore_t probeFinished = dispatch_semaphore_create(0);
  [bridge selectedCaptureDidTerminate:(id)oldStream error:nil completion:^{ dispatch_semaphore_signal(probeFinished); }];
  dispatch_sync(oldOwner.deliveryQueue, ^{});
  Require(oldOwner.isRetired && terminals == 0 && bridge.selectedHandoff == oldOwner);
  Require(dispatch_semaphore_wait(probeFinished, DISPATCH_TIME_NOW) != 0);
  pendingPause(nil);
  Require(dispatch_semaphore_wait(probeFinished, dispatch_time(DISPATCH_TIME_NOW,1000000000)) == 0);
  Require(terminals == 1 && bridge.selectedHandoff == nil && !bridge.selectedCaptureFailed);
  InertBridgeStream *newStream = [InertBridgeStream new];
  [bridge.selectedStreams addObject:(id)newStream];
  CompanionSelectedCaptureHandoff *newOwner = [[CompanionSelectedCaptureHandoff alloc]
      initWithDirectory:directory initialContext:context
      pause:^(CompanionCaptureHandoffCompletion completion) { completion(nil); }
      select:^(CompanionSelectedCaptureContext *next, CompanionCaptureHandoffCompletion completion) { (void)next; completion(nil); }
      terminal:^(NSError *error) { Require(error == nil); terminals++; } error:nil];
  Require(newOwner != nil && newOwner != oldOwner); bridge.selectedHandoff = newOwner;
  [newOwner start]; dispatch_sync(newOwner.deliveryQueue, ^{}); Require(newOwner.isDeliveryAllowed);
  [bridge selectedCaptureDidTerminate:(id)oldStream error:[NSError errorWithDomain:@"stale" code:1 userInfo:nil]
      completion:^{ dispatch_semaphore_signal(probeFinished); }];
  Require(dispatch_semaphore_wait(probeFinished, DISPATCH_TIME_NOW) == 0);
  Require(bridge.selectedHandoff == newOwner && newOwner.isDeliveryAllowed && newStream.stops == 0 && !bridge.selectedCaptureFailed);
  [bridge selectedCaptureDidTerminate:(id)newStream error:nil completion:^{ dispatch_semaphore_signal(probeFinished); }];
  Require(dispatch_semaphore_wait(probeFinished, dispatch_time(DISPATCH_TIME_NOW,1000000000)) == 0);
  Require(terminals == 2 && bridge.selectedHandoff == nil);
  pendingPause = nil;
  Require([[NSFileManager defaultManager] removeItemAtPath:directory error:nil]);
}

int main(int argc, const char **argv) {
  @autoreleasepool {
    Require(argc == 2);
    NSDictionary *fixture = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]] options:0 error:nil];
    ProbeOwnerHandoff(fixture);
    // No display initializer and no platform stream. This deliberately corrupts
    // the local output size to exercise failure before any capture can start.
    AVVideo *capture = [AVVideo new];
    SCContentFilter *inertFilter = (SCContentFilter *)[NSObject new];
    capture.selectedFilter = inertFilter;
    capture.selectedEncodedWidth = 320; capture.selectedEncodedHeight = 240;
    capture.frameWidth = 321; capture.frameHeight = 240;
    dispatch_semaphore_t signal = [capture capture:^bool(CMSampleBufferRef sample) { (void)sample; abort(); }];
    Require(signal != nil && dispatch_semaphore_wait(signal, dispatch_time(DISPATCH_TIME_NOW, 1000000000)) == 0);
    Require(capture.selectedCaptureFailed);
    // Correcting size cannot revive a failed source in the same capture owner.
    capture.frameWidth = 320;
    signal = [capture capture:^bool(CMSampleBufferRef sample) { (void)sample; abort(); }];
    Require(dispatch_semaphore_wait(signal, dispatch_time(DISPATCH_TIME_NOW, 1000000000)) == 0 && capture.selectedCaptureFailed);
    AVVideo *invalid = [[AVVideo alloc] initWithSelectedFilter:inertFilter sourceRect:CGRectNull
        sourcePixelWidth:0 sourcePixelHeight:360 encodedWidth:320 encodedHeight:240 isCurrent:^BOOL { return YES; }];
    Require(invalid == nil);
    puts("Selected Sunshine bridge: joined probe handoff retirement, fresh next owner, stale terminal fencing, bounded failure wakeup and latched rejection passed; no capture started.");
  }
  return 0;
}
