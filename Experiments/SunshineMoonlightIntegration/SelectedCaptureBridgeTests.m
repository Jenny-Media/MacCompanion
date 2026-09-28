#import "av_video.h"
#include <stdlib.h>

static void Require(BOOL value) { if (!value) abort(); }

int main(void) {
  @autoreleasepool {
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
    puts("Selected Sunshine bridge: bounded failure wakeup, latched failure and invalid source rejection passed; no capture started.");
  }
  return 0;
}
