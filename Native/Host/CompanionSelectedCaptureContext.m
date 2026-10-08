#import "CompanionSelectedCaptureContext.h"
#import <AppKit/AppKit.h>
#import <mach/mach_time.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <math.h>
#include <sys/stat.h>
#include <unistd.h>
#include "../Client/CompanionNativeSurfaceEpoch.h"

static NSError *ContextError(NSInteger code) {
  // The managed child has no user-facing diagnostic channel. Fixed codes
  // identify the failed check without logging window metadata or pixels.
  if (getenv("MACCOMPANION_NATIVE_SELECTION_PATH")) fprintf(stderr,"selected-capture-context-error=%ld\n",(long)code);
  return [NSError errorWithDomain:@"MacCompanion.SelectedCaptureContext" code:code userInfo:nil];
}
// Closed local classification only. The same rejection still occurs immediately;
// no window, process, geometry, identity, pixel or input material is emitted.
static BOOL ContextInvalidSelection(unsigned code) {
  if (getenv("MACCOMPANION_NATIVE_SELECTION_PATH")) fprintf(stderr,"selected-capture-validation-error=%u\n",code);
  return NO;
}
static uint64_t ContextNow(void) {
  mach_timebase_info_data_t timebase;
  if (mach_timebase_info(&timebase) != KERN_SUCCESS || !timebase.denom) return UINT64_MAX;
  return (uint64_t)((__uint128_t)mach_absolute_time() * timebase.numer / timebase.denom);
}
static BOOL ContextRect(CGRect rect) {
  return isfinite(rect.origin.x) && isfinite(rect.origin.y) && isfinite(rect.size.width)
    && isfinite(rect.size.height) && rect.size.width > 0 && rect.size.height > 0;
}
static BOOL ContextNumber(id value, double minimum, double maximum, BOOL integer) {
  if (![value isKindOfClass:[NSNumber class]] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NO;
  double number = [value doubleValue];
  return isfinite(number) && number >= minimum && number <= maximum && (!integer || number == floor(number));
}
static NSData *ContextEpoch(id hex) {
  if (![hex isKindOfClass:[NSString class]] || [hex length] != 96) return nil;
  uint8_t bytes[48];
  for (NSUInteger index = 0; index < 96; index++) {
    unichar digit = [hex characterAtIndex:index];
    int value = digit >= '0' && digit <= '9' ? digit - '0' : digit >= 'a' && digit <= 'f' ? digit - 'a' + 10 : -1;
    if (value < 0) return nil;
    if (index % 2 == 0) bytes[index/2] = (uint8_t)(value << 4); else bytes[index/2] |= (uint8_t)value;
  }
  CompanionNativeSurfaceEpoch decoded;
  return CompanionNativeEpochDecode(bytes,sizeof(bytes),&decoded) ? [NSData dataWithBytes:bytes length:sizeof(bytes)] : nil;
}

static BOOL ContextAbsoluteLiteralPath(NSString *path) {
  if (![path hasPrefix:@"/"] || path.length < 2 || path.length >= PATH_MAX) return NO;
  NSArray<NSString *> *components = [path componentsSeparatedByString:@"/"];
  for (NSUInteger index = 1; index < components.count; index++) {
    NSString *component = components[index];
    if (!component.length || [component isEqual:@"."] || [component isEqual:@".."]) return NO;
  }
  return YES;
}

static int ContextDirectory(NSString *path) {
  int directory = open("/",O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  if (directory < 0) {
    if (getenv("MACCOMPANION_NATIVE_SELECTION_PATH")) fprintf(stderr,"selected-capture-directory-error=0:%d\n",errno);
    return -1;
  }
  NSUInteger depth = 0;
  for (NSString *component in path.pathComponents) {
    if ([component isEqual:@"/"]) continue;
    depth++;
    int next = openat(directory,component.fileSystemRepresentation,O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    int openError = errno;
    close(directory);
    if (next < 0) {
      if (getenv("MACCOMPANION_NATIVE_SELECTION_PATH")) fprintf(stderr,"selected-capture-directory-error=%lu:%d\n",(unsigned long)depth,openError);
      return -1;
    }
    directory = next;
  }
  return directory;
}

@interface CompanionSelectedCaptureContext () {
  NSString *_kind, *_bundleIdentifier;
  CGDirectDisplayID _displayID;
  CGWindowID _windowID;
  pid_t _processID;
  uint64_t _processLaunchMilliseconds, _expiry;
  CGRect _bounds;
  double _backingScale;
}
+ (instancetype)parseData:(NSData *)data operationID:(NSString *)operation displayID:(CGDirectDisplayID)displayID
    now:(uint64_t)now error:(NSError **)error;
+ (CGRect)applicationBoundsForWindows:(NSArray<NSDictionary *> *)windows processID:(pid_t)processID
    displayBounds:(CGRect)displayBounds;
@end

@implementation CompanionSelectedCaptureContext

+ (instancetype)loadManagedContextForDisplay:(CGDirectDisplayID)displayID error:(NSError **)error {
  const char *managed = getenv("MACCOMPANION_MANAGED_ENROLLMENT");
  const char *path = getenv("MACCOMPANION_NATIVE_SELECTION_PATH");
  const char *parent = getenv("SUNSHINE_APPDATA");
  const char *operation = getenv("MACCOMPANION_NATIVE_OPERATION");
  const char *mode = getenv("MACCOMPANION_NATIVE_MODE");
  NSString *recordPath = path ? [NSString stringWithUTF8String:path] : nil;
  NSString *parentPath = parent ? [NSString stringWithUTF8String:parent] : nil;
  if (!managed || strcmp(managed,"1") || !operation || !mode
      || !ContextAbsoluteLiteralPath(recordPath) || !ContextAbsoluteLiteralPath(parentPath)
      || ![recordPath.lastPathComponent isEqual:@"selected-capture.json"]
      || ![recordPath.stringByDeletingLastPathComponent isEqual:parentPath]) {
    if (error) *error = ContextError(11); return nil;
  }
  int directory = ContextDirectory(parentPath);
  struct stat directoryFacts;
  if (directory < 0) { if (error) *error = ContextError(14); return nil; }
  BOOL safe = fstat(directory,&directoryFacts) == 0 && S_ISDIR(directoryFacts.st_mode)
    && directoryFacts.st_uid == geteuid() && (directoryFacts.st_mode & 0777) == 0700;
  int descriptor = safe ? openat(directory,"selected-capture.json",O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK) : -1;
  close(directory);
  struct stat facts;
  if (descriptor < 0) { if (error) *error = ContextError(15); return nil; }
  safe = fstat(descriptor,&facts) == 0 && S_ISREG(facts.st_mode) && facts.st_uid == geteuid()
    && facts.st_nlink == 1 && (facts.st_mode & 0777) == 0600 && facts.st_size > 0 && facts.st_size <= 4096;
  NSMutableData *data = safe ? [NSMutableData dataWithLength:(NSUInteger)facts.st_size] : nil;
  ssize_t count = safe ? read(descriptor,data.mutableBytes,data.length) : -1;
  struct stat after;
  safe = safe && count == (ssize_t)data.length && fstat(descriptor,&after) == 0
    && after.st_size == facts.st_size && after.st_nlink == 1 && after.st_uid == facts.st_uid
    && after.st_mode == facts.st_mode;
  close(descriptor);
  if (!safe) { if (error) *error = ContextError(16); return nil; }
  CompanionSelectedCaptureContext *context = [self parseData:data operationID:[NSString stringWithUTF8String:operation]
    displayID:displayID now:ContextNow() error:error];
  NSString *expectedMode = [NSString stringWithFormat:@"%ldx%ldx60", (long)context.encodedWidth, (long)context.encodedHeight];
  if (!context || ![expectedMode isEqual:[NSString stringWithUTF8String:mode]]) {
    if (error) *error = ContextError(10); return nil;
  }
  return context;
}

+ (instancetype)parseData:(NSData *)data operationID:(NSString *)operation displayID:(CGDirectDisplayID)displayID
    now:(uint64_t)now error:(NSError **)error {
  NSDictionary *value = data.length > 0 && data.length <= 4096 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  BOOL continuity = [value isKindOfClass:[NSDictionary class]] && [value[@"profile"] isEqual:@"maccompanion.selected-capture-context.v0.2"];
  BOOL desktop = continuity && [value[@"kind"] isEqual:@"desktop"];
  NSData *epoch = continuity ? ContextEpoch(value[@"frameEpochHex"]) : nil;
  NSMutableSet *keys = [NSMutableSet setWithArray:@[@"profile",@"operationID",@"kind",@"displayID",@"windowID",@"processID",@"bundleIdentifier",
    @"processLaunchMilliseconds",@"expiresAtMonotonicNanoseconds",@"boundsX",@"boundsY",@"boundsWidth",@"boundsHeight",
    @"backingScale",@"sourcePixelWidth",@"sourcePixelHeight",@"encodedWidth",@"encodedHeight"]];
  if (continuity) [keys addObject:@"frameEpochHex"];
  if (![value isKindOfClass:[NSDictionary class]] || ![[NSSet setWithArray:value.allKeys] isEqual:keys]
      || ![data isEqual:[NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes error:nil]]
      || (!continuity && ![value[@"profile"] isEqual:@"maccompanion.selected-capture-context.v0.1"])
      || (continuity && !epoch)
      || ![[[NSUUID alloc] initWithUUIDString:operation] UUIDString] || ![value[@"operationID"] isEqual:operation]
      || (![value[@"kind"] isEqual:@"window"] && ![value[@"kind"] isEqual:@"application"] && !desktop)
      || !ContextNumber(value[@"displayID"],1,UINT32_MAX,YES) || [value[@"displayID"] unsignedIntValue] != displayID
      || !ContextNumber(value[@"windowID"],0,UINT32_MAX,YES) || !ContextNumber(value[@"processID"],desktop ? 0 : 1,INT32_MAX,YES)
      || !ContextNumber(value[@"processLaunchMilliseconds"],desktop ? 0 : 1,9007199254740991.0,YES)
      || !ContextNumber(value[@"expiresAtMonotonicNanoseconds"],1,(double)UINT64_MAX,YES)
      || ![value[@"bundleIdentifier"] isKindOfClass:[NSString class]] || (!desktop && [value[@"bundleIdentifier"] length] < 1)
      || [value[@"bundleIdentifier"] length] > 255
      || !ContextNumber(value[@"boundsX"],-DBL_MAX,DBL_MAX,NO) || !ContextNumber(value[@"boundsY"],-DBL_MAX,DBL_MAX,NO)
      || !ContextNumber(value[@"boundsWidth"],1,32768,NO) || !ContextNumber(value[@"boundsHeight"],1,32768,NO)
      || !ContextNumber(value[@"backingScale"],1,4,NO)
      || !ContextNumber(value[@"sourcePixelWidth"],1,32768,YES) || !ContextNumber(value[@"sourcePixelHeight"],1,32768,YES)
      || !ContextNumber(value[@"encodedWidth"],320,1920,YES) || !ContextNumber(value[@"encodedHeight"],240,1200,YES)) {
    if (error) *error = ContextError(10); return nil;
  }
  uint64_t expiry = [value[@"expiresAtMonotonicNanoseconds"] unsignedLongLongValue];
  BOOL window = [value[@"kind"] isEqual:@"window"];
  if (expiry <= now || expiry - now > 14400000000000ULL
      || (window ? [value[@"windowID"] unsignedIntValue] == 0 : [value[@"windowID"] unsignedIntValue] != 0)
      || (desktop && ([value[@"processID"] intValue] != 0 || [value[@"processLaunchMilliseconds"] unsignedLongLongValue] != 0
          || [value[@"bundleIdentifier"] length] != 0))
      || ceil([value[@"boundsWidth"] doubleValue] * [value[@"backingScale"] doubleValue]) != [value[@"sourcePixelWidth"] integerValue]
      || ceil([value[@"boundsHeight"] doubleValue] * [value[@"backingScale"] doubleValue]) != [value[@"sourcePixelHeight"] integerValue]) {
    if (error) *error = ContextError(10); return nil;
  }
  CompanionSelectedCaptureContext *context = [self new];
  context->_operationID = [operation copy]; context->_expiresAtMonotonicNanoseconds = expiry; context->_frameEpoch = epoch;
  context->_kind = [value[@"kind"] copy]; context->_bundleIdentifier = [value[@"bundleIdentifier"] copy];
  context->_displayID = displayID; context->_windowID = [value[@"windowID"] unsignedIntValue]; context->_processID = [value[@"processID"] intValue];
  context->_processLaunchMilliseconds = [value[@"processLaunchMilliseconds"] unsignedLongLongValue]; context->_expiry = expiry;
  context->_bounds = CGRectMake([value[@"boundsX"] doubleValue],[value[@"boundsY"] doubleValue],
    [value[@"boundsWidth"] doubleValue],[value[@"boundsHeight"] doubleValue]); context->_backingScale = [value[@"backingScale"] doubleValue];
  context->_sourcePixelWidth = [value[@"sourcePixelWidth"] integerValue]; context->_sourcePixelHeight = [value[@"sourcePixelHeight"] integerValue];
  context->_encodedWidth = [value[@"encodedWidth"] integerValue]; context->_encodedHeight = [value[@"encodedHeight"] integerValue];
  CGRect displayBounds = CGDisplayBounds(displayID);
  context->_sourceRect = window || desktop ? CGRectNull : CGRectMake(context->_bounds.origin.x-displayBounds.origin.x,
    context->_bounds.origin.y-displayBounds.origin.y,context->_bounds.size.width,context->_bounds.size.height);
  return context;
}

- (BOOL)isCurrentSelection {
  if (ContextNow() >= _expiry) return ContextInvalidSelection(1);
  if (!CGDisplayIsActive(_displayID) || CGDisplayRotation(_displayID) != 0) return ContextInvalidSelection(2);
  CGRect displayBounds = CGDisplayBounds(_displayID);
  if (!ContextRect(displayBounds)) return ContextInvalidSelection(3);
  if ([_kind isEqual:@"desktop"]) {
    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(_displayID);
    if (!mode) return ContextInvalidSelection(4);
    size_t width = CGDisplayModeGetPixelWidth(mode), height = CGDisplayModeGetPixelHeight(mode);
    CFRelease(mode);
    double scale = fmax(width/displayBounds.size.width, height/displayBounds.size.height);
    BOOL current = CGRectEqualToRect(displayBounds,_bounds) && width == (size_t)_sourcePixelWidth && height == (size_t)_sourcePixelHeight
      && isfinite(scale) && scale == _backingScale;
    return current ? YES : ContextInvalidSelection(5);
  }
  double scale = fmax(CGDisplayPixelsWide(_displayID)/displayBounds.size.width, CGDisplayPixelsHigh(_displayID)/displayBounds.size.height);
  if (scale != _backingScale) return ContextInvalidSelection(6);
  NSRunningApplication *application = [NSRunningApplication runningApplicationWithProcessIdentifier:_processID];
  double launched = application.launchDate.timeIntervalSince1970 * 1000;
  if (!application || application.terminated || ![application.bundleIdentifier isEqual:_bundleIdentifier]
      || !isfinite(launched) || launched <= 0 || floor(launched) != _processLaunchMilliseconds) return ContextInvalidSelection(7);
  NSArray *windows = CFBridgingRelease(CGWindowListCopyWindowInfo(_windowID ? kCGWindowListOptionIncludingWindow : kCGWindowListOptionOnScreenOnly, _windowID));
  if (!windows) return ContextInvalidSelection(8);
  if (!_windowID) {
    BOOL current = CGRectEqualToRect([CompanionSelectedCaptureContext applicationBoundsForWindows:windows
      processID:_processID displayBounds:displayBounds], _bounds);
    return current ? YES : ContextInvalidSelection(12);
  }
  for (NSDictionary *window in windows) {
    if ([window[(__bridge NSString *)kCGWindowOwnerPID] intValue] != _processID || ![window[(__bridge NSString *)kCGWindowIsOnscreen] boolValue]) continue;
    CGRect frame;
    if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)window[(__bridge NSString *)kCGWindowBounds],&frame) || !ContextRect(frame)) continue;
    if (_windowID) {
      if ([window[(__bridge NSString *)kCGWindowNumber] unsignedIntValue] != _windowID) return ContextInvalidSelection(9);
      if (!CGRectEqualToRect(frame,_bounds)) return ContextInvalidSelection(10);
      CGDirectDisplayID centerDisplay = 0; uint32_t count = 0;
      BOOL current = CGGetDisplaysWithPoint(CGPointMake(CGRectGetMidX(frame),CGRectGetMidY(frame)),1,&centerDisplay,&count) == kCGErrorSuccess
        && count == 1 && centerDisplay == _displayID;
      return current ? YES : ContextInvalidSelection(11);
    }
  }
  return ContextInvalidSelection(9);
}

+ (CGRect)applicationBoundsForWindows:(NSArray<NSDictionary *> *)windows processID:(pid_t)processID
    displayBounds:(CGRect)displayBounds {
  if (!ContextRect(displayBounds)) return CGRectNull;
  CGRect unionBounds = CGRectNull;
  for (NSDictionary *window in windows) {
    NSNumber *layer = window[(__bridge NSString *)kCGWindowLayer];
    if (![layer isKindOfClass:[NSNumber class]] || layer.integerValue != 0
        || [window[(__bridge NSString *)kCGWindowOwnerPID] intValue] != processID
        || ![window[(__bridge NSString *)kCGWindowIsOnscreen] boolValue]) continue;
    CGRect frame;
    if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)window[(__bridge NSString *)kCGWindowBounds],&frame)
        || !ContextRect(frame)) continue;
    CGRect clipped = CGRectIntersection(frame,displayBounds);
    if (ContextRect(clipped)) unionBounds = CGRectIsNull(unionBounds) ? clipped : CGRectUnion(unionBounds,clipped);
  }
  return CGRectIsNull(unionBounds) ? CGRectNull
      : CGRectIntersection(CGRectInset(unionBounds,-24,-24),displayBounds);
}

- (SCContentFilter *)resolveFilter:(NSError **)error {
  if (!CGPreflightScreenCaptureAccess() || ![self isCurrentSelection]) { if (error) *error = ContextError(12); return nil; }
  dispatch_semaphore_t ready = dispatch_semaphore_create(0);
  __block SCShareableContent *content = nil;
  [SCShareableContent getShareableContentExcludingDesktopWindows:YES onScreenWindowsOnly:YES completionHandler:^(SCShareableContent *result, NSError *failure) {
    if (!failure) content = result;
    dispatch_semaphore_signal(ready);
  }];
  if (dispatch_semaphore_wait(ready,dispatch_time(DISPATCH_TIME_NOW,2000000000)) != 0 || !content || ![self isCurrentSelection]) {
    if (error) *error = ContextError(13); return nil;
  }
  if (_windowID) {
    for (SCWindow *window in content.windows) {
      if (window.windowID == _windowID && window.onScreen && window.owningApplication.processID == _processID
          && [window.owningApplication.bundleIdentifier isEqual:_bundleIdentifier] && CGRectEqualToRect(window.frame,_bounds)) {
        return [[SCContentFilter alloc] initWithDesktopIndependentWindow:window];
      }
    }
  } else {
    for (SCDisplay *display in content.displays) {
      if (display.displayID != _displayID) continue;
      if ([_kind isEqual:@"desktop"]) {
        return [[SCContentFilter alloc] initWithDisplay:display excludingWindows:@[]];
      }
      for (SCRunningApplication *application in content.applications) {
        if (application.processID == _processID && [application.bundleIdentifier isEqual:_bundleIdentifier]) {
          return [[SCContentFilter alloc] initWithDisplay:display includingApplications:@[application] exceptingWindows:@[]];
        }
      }
    }
  }
  if (error) *error = ContextError(13); return nil;
}
@end
