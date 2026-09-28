// Disposable signed-app experiment. Never link into a release target.
#import <AppKit/AppKit.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#import <CoreVideo/CoreVideo.h>
#import <mach/mach_time.h>
#include <math.h>
#import <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#import "CompanionSelectedCapture.h"
#import "CompanionSelectedCaptureContext.h"

static NSWindow *testWindow;
static CompanionSelectedCapture *capture;
static NSString *reportPath;
static NSString *privateDirectory;
static atomic_bool current = true;
static BOOL completed = NO;
static BOOL applicationMode = NO;
static BOOL preflight = NO;
static BOOL selectedWindow = NO;
static BOOL contextLoaded = NO;
static BOOL contextCurrent = NO;
static NSInteger filterCode = 0;
static NSDictionary *currentFacts;
static BOOL receivedFrame = NO;
static BOOL redCenter = NO;
static NSInteger terminalCode = 0;

static void Finish(NSString *reason) {
  if (completed) return;
  completed = YES;
  atomic_store(&current, false);
  NSDictionary *report = @{ @"profile": @"maccompanion.selected-capture-live-probe.v0.1",
    @"kind": applicationMode ? @"application" : @"window",
    @"preflight": @(preflight), @"selectedWindow": @(selectedWindow),
    @"contextLoaded": @(contextLoaded),
    @"contextCurrent": @(contextCurrent), @"filterCode": @(filterCode),
    @"currentFacts": currentFacts ?: @{},
    @"receivedFrame": @(receivedFrame), @"redCenter": @(redCenter),
    @"terminalCode": @(terminalCode), @"result": reason };
  NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingSortedKeys error:nil];
  [data writeToFile:reportPath atomically:YES];
  if (privateDirectory) [[NSFileManager defaultManager] removeItemAtPath:privateDirectory error:nil];
  [testWindow orderOut:nil];
  [NSApp terminate:nil];
}

static uint64_t MonotonicNow(void) {
  mach_timebase_info_data_t timebase;
  if (mach_timebase_info(&timebase) != KERN_SUCCESS || !timebase.denom) return 0;
  return (uint64_t)((__uint128_t)mach_absolute_time() * timebase.numer / timebase.denom);
}

static CompanionSelectedCaptureContext *MakeContext(SCWindow *window, CGRect bounds, double scale,
                                                    NSInteger width, NSInteger height, CGDirectDisplayID displayID) {
  char template[] = "/private/tmp/maccompanion-selected-live-context.XXXXXX";
  char *directory = mkdtemp(template);
  if (!directory) return nil;
  privateDirectory = [NSString stringWithUTF8String:directory];
  NSRunningApplication *application = NSRunningApplication.currentApplication;
  NSString *operation = NSUUID.UUID.UUIDString;
  uint64_t deadline = MonotonicNow() + 10000000000ULL;
  if (!application.launchDate || !application.bundleIdentifier || !deadline) return nil;
  NSDictionary *record = @{ @"profile": @"maccompanion.selected-capture-context.v0.1",
    @"operationID": operation, @"kind": applicationMode ? @"application" : @"window", @"displayID": @(displayID),
    @"windowID": @(applicationMode ? 0 : window.windowID), @"processID": @(application.processIdentifier),
    @"bundleIdentifier": application.bundleIdentifier,
    @"processLaunchMilliseconds": @((uint64_t)floor(application.launchDate.timeIntervalSince1970 * 1000)),
    @"expiresAtMonotonicNanoseconds": @(deadline),
    @"boundsX": @(bounds.origin.x), @"boundsY": @(bounds.origin.y),
    @"boundsWidth": @(bounds.size.width), @"boundsHeight": @(bounds.size.height),
    @"backingScale": @(scale),
    @"sourcePixelWidth": @(width), @"sourcePixelHeight": @(height),
    @"encodedWidth": @(width), @"encodedHeight": @(height) };
  NSData *data = [NSJSONSerialization dataWithJSONObject:record
    options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes error:nil];
  NSString *path = [privateDirectory stringByAppendingPathComponent:@"selected-capture.json"];
  if (!data || data.length > 4096 || ![data writeToFile:path atomically:YES]
      || chmod(path.fileSystemRepresentation,0600) != 0) return nil;
  setenv("MACCOMPANION_MANAGED_ENROLLMENT","1",1);
  setenv("SUNSHINE_APPDATA",privateDirectory.fileSystemRepresentation,1);
  setenv("MACCOMPANION_NATIVE_SELECTION_PATH",path.fileSystemRepresentation,1);
  setenv("MACCOMPANION_NATIVE_OPERATION",operation.UTF8String,1);
  NSString *mode = [NSString stringWithFormat:@"%ldx%ldx60",(long)width,(long)height];
  setenv("MACCOMPANION_NATIVE_MODE",mode.UTF8String,1);
  return [CompanionSelectedCaptureContext loadManagedContextForDisplay:displayID error:nil];
}

static BOOL IsRedCenter(CMSampleBufferRef sample) {
  CVPixelBufferRef buffer = CMSampleBufferGetImageBuffer(sample);
  if (!buffer || CVPixelBufferGetPixelFormatType(buffer) != kCVPixelFormatType_32BGRA
      || CVPixelBufferLockBaseAddress(buffer,kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess) return NO;
  const size_t width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer);
  const size_t stride = CVPixelBufferGetBytesPerRow(buffer);
  const uint8_t *bytes = CVPixelBufferGetBaseAddress(buffer);
  BOOL red = width > 0 && height > 0 && bytes != NULL && stride >= width * 4;
  if (red) {
    const uint8_t *center = bytes + height / 2 * stride + width / 2 * 4;
    red = center[2] > 180 && center[1] < 100 && center[0] < 100;
  }
  CVPixelBufferUnlockBaseAddress(buffer,kCVPixelBufferLock_ReadOnly);
  return red;
}

static void ResolveAndStart(void) {
  preflight = CGPreflightScreenCaptureAccess();
  if (!preflight) { Finish(@"permission-unavailable"); return; }
  [SCShareableContent getShareableContentExcludingDesktopWindows:YES onScreenWindowsOnly:YES
    completionHandler:^(SCShareableContent *content, NSError *error) {
      dispatch_async(dispatch_get_main_queue(), ^{
        if (completed) return;
        if (error || !content) { Finish(@"catalog-unavailable"); return; }
        SCWindow *selected = nil;
        for (SCWindow *candidate in content.windows) {
          if (candidate.windowID == testWindow.windowNumber && candidate.onScreen) { selected = candidate; break; }
        }
        if (!selected) { Finish(@"owned-window-unavailable"); return; }
        selectedWindow = YES;
        CGDirectDisplayID displayID = 0; uint32_t displayCount = 0;
        if (CGGetDisplaysWithPoint(CGPointMake(CGRectGetMidX(selected.frame),CGRectGetMidY(selected.frame)),
            1,&displayID,&displayCount) != kCGErrorSuccess || displayCount != 1 || !displayID) {
          Finish(@"display-unavailable"); return;
        }
        CGRect displayBounds = CGDisplayBounds(displayID);
        double scale = fmax(CGDisplayPixelsWide(displayID)/displayBounds.size.width,
            CGDisplayPixelsHigh(displayID)/displayBounds.size.height);
        CGRect captureBounds = selected.frame;
        if (applicationMode) {
          NSArray *visible = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly,kCGNullWindowID));
          CGRect combined = CGRectNull;
          for (NSDictionary *facts in visible) {
            if ([facts[(__bridge NSString *)kCGWindowOwnerPID] intValue] != getpid()
                || ![facts[(__bridge NSString *)kCGWindowIsOnscreen] boolValue]) continue;
            CGRect frame;
            if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)facts[(__bridge NSString *)kCGWindowBounds],&frame)) continue;
            CGRect clipped = CGRectIntersection(frame,displayBounds);
            if (clipped.size.width <= 0 || clipped.size.height <= 0) continue;
            combined = CGRectIsNull(combined) ? clipped : CGRectUnion(combined,clipped);
          }
          if (CGRectIsNull(combined)) { Finish(@"application-bounds-unavailable"); return; }
          captureBounds = CGRectIntersection(CGRectInset(combined,-24,-24),displayBounds);
        }
        NSInteger width = (NSInteger)ceil(captureBounds.size.width * scale);
        NSInteger height = (NSInteger)ceil(captureBounds.size.height * scale);
        if (width < 320 || height < 240) { Finish(@"invalid-window-size"); return; }
        CompanionSelectedCaptureContext *context = MakeContext(selected,captureBounds,scale,width,height,displayID);
        contextLoaded = context != nil;
        if (!context) { Finish(@"context-unavailable"); return; }
        NSArray *windowFacts = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow,selected.windowID));
        BOOL windowVisible = NO, windowBoundsMatch = NO, windowOwnerMatch = NO;
        for (NSDictionary *facts in windowFacts) {
          if ([facts[(__bridge NSString *)kCGWindowNumber] unsignedIntValue] != selected.windowID) continue;
          windowVisible = [facts[(__bridge NSString *)kCGWindowIsOnscreen] boolValue];
          windowOwnerMatch = [facts[(__bridge NSString *)kCGWindowOwnerPID] intValue] == getpid();
          CGRect actual;
          windowBoundsMatch = CGRectMakeWithDictionaryRepresentation(
            (__bridge CFDictionaryRef)facts[(__bridge NSString *)kCGWindowBounds],&actual)
            && CGRectEqualToRect(actual,selected.frame);
        }
        double actualScale = fmax(CGDisplayPixelsWide(displayID)/displayBounds.size.width,
            CGDisplayPixelsHigh(displayID)/displayBounds.size.height);
        double declaredScale = scale;
        NSRunningApplication *running = [NSRunningApplication runningApplicationWithProcessIdentifier:getpid()];
        currentFacts = @{ @"windowVisible": @(windowVisible), @"windowBoundsMatch": @(windowBoundsMatch),
          @"windowOwnerMatch": @(windowOwnerMatch), @"displayScaleMatch": @(actualScale == declaredScale),
          @"displayUnrotated": @(CGDisplayRotation(displayID) == 0),
          @"processPresent": @(running != nil), @"processLaunchPresent": @(running.launchDate != nil),
          @"processBundleMatch": @([running.bundleIdentifier isEqual:NSBundle.mainBundle.bundleIdentifier]) };
        contextCurrent = [context isCurrentSelection];
        NSError *filterError = nil;
        SCContentFilter *filter = [context resolveFilter:&filterError];
        filterCode = filterError.code;
        if (!filter) { Finish(@"context-filter-unavailable"); return; }
        NSError *constructionError = nil;
        capture = [[CompanionSelectedCapture alloc] initWithFilter:filter sourceRect:context.sourceRect
          sourcePixelWidth:context.sourcePixelWidth sourcePixelHeight:context.sourcePixelHeight
          encodedWidth:context.encodedWidth encodedHeight:context.encodedHeight
          pixelFormat:kCVPixelFormatType_32BGRA isCurrent:^BOOL {
            return atomic_load(&current) && [context isCurrentSelection];
          }
          error:&constructionError];
        if (!capture) { Finish(@"adapter-unavailable"); return; }
        [capture startWithFrame:^BOOL(CMSampleBufferRef sample) {
          BOOL red = IsRedCenter(sample);
          dispatch_async(dispatch_get_main_queue(), ^{
            if (completed) return;
            receivedFrame = YES;
            redCenter = red;
            [capture stop];
          });
          return YES;
        } terminal:^(NSError *terminalError) {
          dispatch_async(dispatch_get_main_queue(), ^{
            if (completed) return;
            terminalCode = terminalError.code;
            Finish(receivedFrame && redCenter && !terminalError ? @"selected-red-frame" : @"capture-failed");
          });
        }];
      });
    }];
}

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    if ((argc != 2 && argc != 3) || argv[1][0] != '/') return 2;
    if (argc == 3) {
      if (strcmp(argv[2],"application") != 0) return 2;
      applicationMode = YES;
    }
    reportPath = [NSString stringWithUTF8String:argv[1]];
    NSApplication *app = [NSApplication sharedApplication];
    [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
    testWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 640, 360)
      styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    testWindow.title = @"MacCompanion Selected Capture Test";
    testWindow.backgroundColor = NSColor.redColor;
    [testWindow makeKeyAndOrderFront:nil];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500000000), dispatch_get_main_queue(), ^{ ResolveAndStart(); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10000000000LL), dispatch_get_main_queue(), ^{
      if (!completed) { atomic_store(&current, false); [capture stop]; Finish(@"timeout"); }
    });
    [app run];
  }
  return 0;
}
