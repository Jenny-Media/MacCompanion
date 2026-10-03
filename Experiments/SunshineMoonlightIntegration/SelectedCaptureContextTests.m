#import "CompanionSelectedCaptureContext.h"
#import <mach/mach_time.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

@interface CompanionSelectedCaptureContext (LocalContractProbe)
+ (instancetype)parseData:(NSData *)data operationID:(NSString *)operation displayID:(CGDirectDisplayID)displayID
    now:(uint64_t)now error:(NSError **)error;
+ (CGRect)applicationBoundsForWindows:(NSArray<NSDictionary *> *)windows processID:(pid_t)processID
    displayBounds:(CGRect)displayBounds;
@end

#define Require(condition) do { if (!(condition)) { fprintf(stderr,"Selected context check failed at line %d\n",__LINE__); abort(); } } while (0)
static NSData *Canonical(NSDictionary *value) {
  NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes error:nil];
  Require(data != nil); return data;
}
static uint64_t Now(void) {
  mach_timebase_info_data_t scale;
  Require(mach_timebase_info(&scale) == KERN_SUCCESS && scale.denom);
  return (uint64_t)((__uint128_t)mach_absolute_time() * scale.numer / scale.denom);
}
static NSString *const Operation = @"AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE";
static void Deny(NSDictionary *base, NSString *field, id value, uint64_t now) {
  NSMutableDictionary *changed = [base mutableCopy];
  if (value) changed[field] = value; else [changed removeObjectForKey:field];
  Require([CompanionSelectedCaptureContext parseData:Canonical(changed) operationID:Operation displayID:1 now:now error:nil] == nil);
}

int main(int argc, const char **argv) {
  @autoreleasepool {
    Require(argc == 2);
    NSData *fixtureData = [NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]];
    NSDictionary *fixture = [NSJSONSerialization JSONObjectWithData:fixtureData options:0 error:nil];
    for (NSDictionary *row in fixture[@"applicationCropCases"]) {
      NSArray *display = row[@"displayBounds"];
      CGRect displayBounds = CGRectMake([display[0] doubleValue],[display[1] doubleValue],
          [display[2] doubleValue],[display[3] doubleValue]);
      NSMutableArray *windows = [NSMutableArray array];
      for (NSDictionary *item in row[@"windows"]) {
        NSArray *b = item[@"bounds"];
        CGRect frame = CGRectMake([b[0] doubleValue],[b[1] doubleValue],[b[2] doubleValue],[b[3] doubleValue]);
        [windows addObject:@{(__bridge NSString *)kCGWindowOwnerPID:item[@"processID"],
          (__bridge NSString *)kCGWindowIsOnscreen:item[@"onScreen"],
          (__bridge NSString *)kCGWindowLayer:item[@"layer"],
          (__bridge NSString *)kCGWindowBounds:CFBridgingRelease(CGRectCreateDictionaryRepresentation(frame))}];
      }
      CGRect actual = [CompanionSelectedCaptureContext applicationBoundsForWindows:windows
          processID:[row[@"processID"] intValue] displayBounds:displayBounds];
      NSArray *crop = row[@"crop"];
      if ((id)crop == [NSNull null]) Require(CGRectIsNull(actual));
      else Require(CGRectEqualToRect(actual,CGRectMake([crop[0] doubleValue],[crop[1] doubleValue],
          [crop[2] doubleValue],[crop[3] doubleValue])));
    }
    NSDictionary *source = fixture[@"windowContext"];
    uint64_t fakeNow = [fixture[@"nowMonotonicNanoseconds"] unsignedLongLongValue];
    Require([CompanionSelectedCaptureContext parseData:Canonical(source) operationID:Operation displayID:1 now:fakeNow error:nil] != nil);
    Deny(source,@"operationID",@"BBBBBBBB-BBBB-4CCC-8DDD-EEEEEEEEEEEE",fakeNow);
    Deny(source,@"displayID",@2,fakeNow);
    Deny(source,@"windowID",@0,fakeNow);
    Deny(source,@"processID",@0,fakeNow);
    Deny(source,@"kind",@"desktop",fakeNow);
    Deny(source,@"sourcePixelWidth",@639,fakeNow);
    Deny(source,@"backingScale",@5,fakeNow);
    Deny(source,@"expiresAtMonotonicNanoseconds",@(fakeNow),fakeNow);
    Deny(source,@"expiresAtMonotonicNanoseconds",@(fakeNow+14400000000001ULL),fakeNow);
    Deny(source,@"windowID",@NO,fakeNow);
    Deny(source,@"extra",@1,fakeNow);
    Deny(source,@"bundleIdentifier",nil,fakeNow);
    NSMutableDictionary *changed = [source mutableCopy]; changed[@"kind"] = @"application";
    Require([CompanionSelectedCaptureContext parseData:Canonical(changed) operationID:Operation displayID:1 now:fakeNow error:nil] == nil);
    changed[@"windowID"] = @0;
    Require([CompanionSelectedCaptureContext parseData:Canonical(changed) operationID:Operation displayID:1 now:fakeNow error:nil] != nil);
    NSString *raw = [[NSString alloc] initWithData:Canonical(source) encoding:NSUTF8StringEncoding];
    NSString *duplicate = [raw stringByReplacingOccurrencesOfString:@"\"kind\":\"window\""
        withString:@"\"kind\":\"window\",\"kind\":\"window\""];
    Require(![duplicate isEqual:raw]);
    Require([CompanionSelectedCaptureContext parseData:[duplicate dataUsingEncoding:NSUTF8StringEncoding]
        operationID:Operation displayID:1 now:fakeNow error:nil] == nil);
    char template[] = "/private/tmp/maccompanion-selected-context.XXXXXX";
    char *folder = mkdtemp(template); Require(folder != NULL);
    NSString *directory = [NSString stringWithUTF8String:folder];
    NSString *path = [directory stringByAppendingPathComponent:@"selected-capture.json"];
    NSMutableDictionary *live = [source mutableCopy]; live[@"expiresAtMonotonicNanoseconds"] = @(Now()+30000000000ULL);
    NSData *bytes = Canonical(live);
    int fd = open(path.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_CLOEXEC,0600); Require(fd >= 0);
    Require(write(fd,bytes.bytes,bytes.length) == (ssize_t)bytes.length); Require(close(fd) == 0);
    setenv("MACCOMPANION_MANAGED_ENROLLMENT","1",1); setenv("MACCOMPANION_NATIVE_OPERATION",Operation.UTF8String,1);
    setenv("MACCOMPANION_NATIVE_MODE","640x360x60",1); setenv("MACCOMPANION_NATIVE_SELECTION_PATH",path.fileSystemRepresentation,1);
    setenv("SUNSHINE_APPDATA",directory.fileSystemRepresentation,1);
    NSError *loadError = nil;
    CompanionSelectedCaptureContext *loaded = [CompanionSelectedCaptureContext loadManagedContextForDisplay:1 error:&loadError];
    if (!loaded) fprintf(stderr,"Selected context rejection code %ld\n",(long)loadError.code);
    Require(loaded != nil && loaded.sourcePixelWidth == 640 && loaded.encodedHeight == 360);
    NSString *alias = [directory stringByAppendingString:@".alias"];
    Require(symlink(directory.fileSystemRepresentation,alias.fileSystemRepresentation) == 0);
    NSString *aliasPath = [alias stringByAppendingPathComponent:@"selected-capture.json"];
    setenv("MACCOMPANION_NATIVE_SELECTION_PATH",aliasPath.fileSystemRepresentation,1);
    setenv("SUNSHINE_APPDATA",alias.fileSystemRepresentation,1);
    NSError *aliasError = nil;
    Require([CompanionSelectedCaptureContext loadManagedContextForDisplay:1 error:&aliasError] == nil && aliasError.code == 14);
    setenv("MACCOMPANION_NATIVE_SELECTION_PATH",path.fileSystemRepresentation,1);
    setenv("SUNSHINE_APPDATA",directory.fileSystemRepresentation,1);
    Require(unlink(alias.fileSystemRepresentation) == 0);
    Require(![loaded isCurrentSelection]); // Synthetic PID 123 cannot authorize capture.
    Require(chmod(path.fileSystemRepresentation,0644) == 0);
    Require([CompanionSelectedCaptureContext loadManagedContextForDisplay:1 error:nil] == nil);
    Require(chmod(path.fileSystemRepresentation,0600) == 0);
    Require(chmod(folder,0755) == 0);
    Require([CompanionSelectedCaptureContext loadManagedContextForDisplay:1 error:nil] == nil);
    Require(chmod(folder,0700) == 0);
    setenv("MACCOMPANION_NATIVE_MODE","639x360x60",1);
    Require([CompanionSelectedCaptureContext loadManagedContextForDisplay:1 error:nil] == nil);
    setenv("MACCOMPANION_NATIVE_MODE","640x360x60",1);
    Require(unlink(path.fileSystemRepresentation) == 0);
    NSString *other = [directory stringByAppendingPathComponent:@"owned-record"];
    Require([bytes writeToFile:other atomically:YES]); Require(chmod(other.fileSystemRepresentation,0600) == 0);
    Require(symlink(other.fileSystemRepresentation,path.fileSystemRepresentation) == 0);
    Require([CompanionSelectedCaptureContext loadManagedContextForDisplay:1 error:nil] == nil);
    Require(unlink(path.fileSystemRepresentation) == 0);
    Require(link(other.fileSystemRepresentation,path.fileSystemRepresentation) == 0);
    Require([CompanionSelectedCaptureContext loadManagedContextForDisplay:1 error:nil] == nil);
    Require(unlink(path.fileSystemRepresentation) == 0);
    Require(unlink(other.fileSystemRepresentation) == 0);
    Require(rmdir(folder) == 0);
    puts("Private selected context: canonical scope, unsafe-file and no-fallback cases passed; no capture requested.");
  }
  return 0;
}
