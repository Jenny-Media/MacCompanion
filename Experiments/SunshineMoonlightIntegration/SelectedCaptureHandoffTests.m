#import "CompanionSelectedCaptureHandoff.h"
#import <mach/mach_time.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

@interface CompanionSelectedCaptureHandoff (LocalContractProbe)
- (dispatch_queue_t)deliveryQueue;
- (void)consumeData:(NSData *)data now:(uint64_t)now;
- (void)checkExpiryAt:(uint64_t)now;
- (void)tick;
@end
// Only the separately compiled test object redirects read(2). The production
// implementation is unchanged; this forces an atomic rename after its actual
// POSIX read, without adding a runtime test hook to the capture child.
static dispatch_block_t ReadCheckpoint;
ssize_t CompanionHandoffReadForTest(int fd, void *buffer, size_t count) {
  ssize_t result = read(fd,buffer,count);
  dispatch_block_t checkpoint = ReadCheckpoint;
  ReadCheckpoint = nil;
  if (checkpoint) checkpoint();
  return result;
}
#define Require(condition) do { if (!(condition)) { fprintf(stderr,"Capture handoff check failed at line %d\n",__LINE__); abort(); } } while (0)
static NSData *Canonical(id value) {
  NSData *data = [NSJSONSerialization dataWithJSONObject:value options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes error:nil];
  Require(data != nil); return data;
}
static uint64_t Now(void) {
  mach_timebase_info_data_t scale; Require(mach_timebase_info(&scale) == KERN_SUCCESS && scale.denom);
  return (uint64_t)((__uint128_t)mach_absolute_time() * scale.numer / scale.denom);
}
static void Flush(CompanionSelectedCaptureHandoff *owner) { dispatch_sync(owner.deliveryQueue, ^{}); }
static void Submit(CompanionSelectedCaptureHandoff *owner, NSDictionary *command, uint64_t now) {
  dispatch_sync(owner.deliveryQueue, ^{ [owner consumeData:Canonical(command) now:now]; });
}
static void Write(NSString *path, NSData *data) {
  int fd = open(path.fileSystemRepresentation,O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,0600); Require(fd >= 0);
  Require(write(fd,data.bytes,data.length) == (ssize_t)data.length); Require(close(fd) == 0);
}
static void Deny(NSDictionary *base, NSString *key, id value, uint64_t now) {
  NSMutableDictionary *changed = [base mutableCopy];
  if (value) changed[key] = value; else [changed removeObjectForKey:key];
  Require([CompanionSelectedCaptureHandoffCommand parseData:Canonical(changed) now:now error:nil] == nil);
}
int main(int argc, const char **argv) {
  @autoreleasepool {
    Require(argc == 2);
    NSDictionary *fixture = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:[NSString stringWithUTF8String:argv[1]]] options:0 error:nil];
    Require([fixture[@"childHandoffCases"] count] == 14);
    NSDictionary *indexed = fixture[@"childHandoff"];
    uint64_t fixtureNow = [indexed[@"nowMonotonicNanoseconds"] unsignedLongLongValue];
    for (NSString *name in @[@"pause",@"select"]) {
      NSDictionary *record = indexed[name];
      Require([CompanionSelectedCaptureHandoffCommand parseData:Canonical(record) now:fixtureNow error:nil] != nil);
      Deny(record,@"sequence",@NO,fixtureNow); Deny(record,@"sequence",@0,fixtureNow);
      Deny(record,@"sequence",@1.5,fixtureNow); Deny(record,@"sequence",@9007199254740992ULL,fixtureNow);
      Deny(record,@"extra",@1,fixtureNow); Deny(record,@"operationID",@"bad",fixtureNow);
      Deny(record,@"transportOperationID",@"bad",fixtureNow);
      Deny(record,@"expiresAtMonotonicNanoseconds",@(fixtureNow),fixtureNow);
      Deny(record,@"expiresAtMonotonicNanoseconds",@(fixtureNow+14400000000001ULL),fixtureNow);
      Deny(record,@"action",@"resume",fixtureNow);
      NSMutableData *spaced = [Canonical(record) mutableCopy]; [spaced appendBytes:" " length:1];
      Require([CompanionSelectedCaptureHandoffCommand parseData:spaced now:fixtureNow error:nil] == nil);
    }
    Deny(indexed[@"select"],@"previousOperationID",indexed[@"select"][@"operationID"],fixtureNow);
    Deny(indexed[@"select"],@"context",nil,fixtureNow);
    // Rebase only monotonic time; all scope, epoch and command identities come
    // from the sole indexed fixture. No capture permissions or input effects.
    uint64_t now = Now(), expiry = now + 30000000000ULL;
    NSMutableDictionary *initial = [indexed[@"initialContext"] mutableCopy]; initial[@"expiresAtMonotonicNanoseconds"] = @(expiry);
    NSMutableDictionary *pause = [indexed[@"pause"] mutableCopy]; pause[@"expiresAtMonotonicNanoseconds"] = @(expiry);
    NSMutableDictionary *select = [indexed[@"select"] mutableCopy]; select[@"expiresAtMonotonicNanoseconds"] = @(expiry);
    NSMutableDictionary *next = [select[@"context"] mutableCopy]; next[@"expiresAtMonotonicNanoseconds"] = @(expiry); select[@"context"] = next;
    CompanionSelectedCaptureContext *context = [CompanionSelectedCaptureContext parseData:Canonical(initial)
        operationID:initial[@"operationID"] displayID:[initial[@"displayID"] unsignedIntValue] now:now error:nil]; Require(context != nil);
    for (NSString *scenario in @[@"success",@"altered-duplicate",@"before-pause",@"wrong-transport",@"changed-canvas",@"same-epoch",
                                @"stop-pause",@"stop-select",@"timeout",@"unsafe-command",@"unsafe-receipt",@"symlink-directory"]) {
      char template[] = "/private/tmp/maccompanion-capture-handoff.XXXXXX";
      char *folder = mkdtemp(template); Require(folder != NULL);
      NSString *directory = [NSString stringWithUTF8String:folder];
      NSString *receiptPath = [directory stringByAppendingPathComponent:@"capture-handoff-receipt.json"];
      NSString *commandPath = [directory stringByAppendingPathComponent:@"capture-handoff-command.json"];
      __block NSUInteger pauses = 0, selections = 0, terminals = 0, stopsCompleted = 0;
      __block CompanionCaptureHandoffCompletion pauseCompletion = nil, selectCompletion = nil;
      dispatch_semaphore_t terminal = dispatch_semaphore_create(0);
      NSString *alias = [directory stringByAppendingString:@".alias"];
      if ([scenario isEqual:@"symlink-directory"]) Require(symlink(folder,alias.fileSystemRepresentation) == 0);
      CompanionSelectedCaptureHandoff *owner = [[CompanionSelectedCaptureHandoff alloc]
        initWithDirectory:[scenario isEqual:@"symlink-directory"] ? alias : directory initialContext:context
        pause:^(CompanionCaptureHandoffCompletion completion) { pauses++; pauseCompletion = [completion copy]; }
        select:^(CompanionSelectedCaptureContext *selected, CompanionCaptureHandoffCompletion completion) {
          Require([selected.operationID isEqual:select[@"operationID"]]); selections++; selectCompletion = [completion copy];
        } terminal:^(NSError *error) { (void)error; terminals++; dispatch_semaphore_signal(terminal); } error:nil];
      if ([scenario isEqual:@"symlink-directory"]) {
        Require(owner == nil); Require(unlink(alias.fileSystemRepresentation) == 0); Require(rmdir(folder) == 0); continue;
      }
      Require(owner != nil); [owner start]; Flush(owner); Require(owner.isDeliveryAllowed);
      if ([scenario isEqual:@"before-pause"]) Submit(owner,select,now);
      else if ([scenario isEqual:@"wrong-transport"]) {
        NSMutableDictionary *bad = [pause mutableCopy]; bad[@"transportOperationID"] = select[@"operationID"]; Submit(owner,bad,now);
      } else if ([scenario isEqual:@"unsafe-command"]) {
        Write(commandPath,Canonical(pause)); Require(chmod(commandPath.fileSystemRepresentation,0644) == 0);
      } else {
        Submit(owner,pause,now); Require(pauses == 1 && !owner.isDeliveryAllowed);
        Require(![[NSFileManager defaultManager] fileExistsAtPath:receiptPath]);
        if ([scenario isEqual:@"stop-pause"]) {
          [owner stop]; Require(!owner.isDeliveryAllowed); Flush(owner); Require(terminals == 0); pauseCompletion(nil); Flush(owner);
          Require(![[NSFileManager defaultManager] fileExistsAtPath:receiptPath]);
        } else {
          if ([scenario isEqual:@"unsafe-receipt"]) {
            NSString *outside = [directory stringByAppendingPathComponent:@"receipt-target"]; Write(outside,[NSData data]);
            Require(symlink(outside.fileSystemRepresentation,receiptPath.fileSystemRepresentation) == 0);
          }
          pauseCompletion(nil); Flush(owner);
          if ([scenario isEqual:@"unsafe-receipt"]) { Require(!owner.isDeliveryAllowed); }
          else {
            Require([[NSFileManager defaultManager] fileExistsAtPath:receiptPath]);
            struct stat receiptBefore, receiptAfter;
            Require(stat(receiptPath.fileSystemRepresentation,&receiptBefore) == 0);
            Submit(owner,pause,now+1000000000ULL); Require(pauses == 1); // Retry cannot extend original handoff.
            Require(stat(receiptPath.fileSystemRepresentation,&receiptAfter) == 0);
            Require(receiptBefore.st_dev == receiptAfter.st_dev && receiptBefore.st_ino == receiptAfter.st_ino);
            if ([scenario isEqual:@"timeout"]) {
              dispatch_sync(owner.deliveryQueue, ^{ [owner checkExpiryAt:now+15000000000ULL]; });
            } else if ([scenario isEqual:@"altered-duplicate"]) {
              NSMutableDictionary *bad = [pause mutableCopy]; bad[@"action"] = @"select"; bad[@"context"] = next;
              bad[@"previousOperationID"] = pause[@"operationID"]; bad[@"operationID"] = select[@"operationID"]; Submit(owner,bad,now);
            } else {
              NSMutableDictionary *record = [select mutableCopy]; NSMutableDictionary *newContext = [next mutableCopy];
              if ([scenario isEqual:@"changed-canvas"]) newContext[@"encodedWidth"] = @1280;
              if ([scenario isEqual:@"same-epoch"]) newContext[@"frameEpochHex"] = initial[@"frameEpochHex"];
              record[@"context"] = newContext; Submit(owner,record,now);
              if ([scenario isEqual:@"success"] || [scenario isEqual:@"stop-select"]) {
                Require(selections == 1 && !owner.isDeliveryAllowed);
                if ([scenario isEqual:@"stop-select"]) {
                  [owner stopWithCompletion:^{ Require(terminals == 1); stopsCompleted++; }];
                  [owner stopWithCompletion:^{ Require(terminals == 1); stopsCompleted++; }];
                  Flush(owner); Require(terminals == 0 && stopsCompleted == 0);
                  selectCompletion(nil); Flush(owner); Require(stopsCompleted == 2);
                  NSDictionary *receipt = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:receiptPath] options:0 error:nil];
                  Require([receipt[@"result"] isEqual:@"paused"]);
                } else {
                  selectCompletion(nil); Flush(owner); Require(owner.isDeliveryAllowed);
                  NSDictionary *receipt = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:receiptPath] options:0 error:nil];
                  Require([receipt[@"result"] isEqual:@"selected"] && [receipt[@"operationID"] isEqual:select[@"operationID"]]);
                  Submit(owner,record,now); Require(selections == 1); [owner stop]; Flush(owner);
                }
                selectCompletion(nil); Flush(owner); // Duplicate late completion cannot reopen after Stop.
              }
            }
          }
        }
      }
      Require(dispatch_semaphore_wait(terminal,dispatch_time(DISPATCH_TIME_NOW,1000000000)) == 0);
      [owner stop]; Flush(owner); Require(terminals == 1 && !owner.isDeliveryAllowed);
      [owner stopWithCompletion:^{ Require(terminals == 1); stopsCompleted++; }];
      Flush(owner); Require(stopsCompleted == ([scenario isEqual:@"stop-select"] ? 3u : 1u));
      pauseCompletion = nil; selectCompletion = nil; owner = nil;
      Require([[NSFileManager defaultManager] removeItemAtPath:directory error:nil]);
    }
    Require([fixture[@"childHandoffCases"] containsObject:@"atomic-command-replacement-discards-old-snapshot"]);
    for (NSString *scenario in @[@"atomic",@"same-inode",@"unsafe-mode",@"hardlink",@"symlink",@"missing"]) {
      char template[] = "/private/tmp/maccompanion-command-race.XXXXXX";
      char *folder = mkdtemp(template); Require(folder != NULL);
      NSString *directory = [NSString stringWithUTF8String:folder];
      NSString *commandPath = [directory stringByAppendingPathComponent:@"capture-handoff-command.json"];
      NSString *replacementPath = [directory stringByAppendingPathComponent:@"replacement.json"];
      __block NSUInteger pauses = 0, terminals = 0;
      __block CompanionCaptureHandoffCompletion completion = nil;
      CompanionSelectedCaptureHandoff *owner = [[CompanionSelectedCaptureHandoff alloc] initWithDirectory:directory initialContext:context
        pause:^(CompanionCaptureHandoffCompletion done) { pauses++; completion = [done copy]; }
        select:^(CompanionSelectedCaptureContext *selected, CompanionCaptureHandoffCompletion done) { (void)selected; (void)done; Require(NO); }
        terminal:^(NSError *error) { (void)error; terminals++; } error:nil];
      Require(owner != nil); [owner start]; Flush(owner);
      dispatch_sync(owner.deliveryQueue, ^{
        Write(commandPath,[@"{}" dataUsingEncoding:NSUTF8StringEncoding]);
        Write(replacementPath,Canonical(pause));
        ReadCheckpoint = ^{
          if ([scenario isEqual:@"same-inode"]) {
            int fd = open(commandPath.fileSystemRepresentation,O_WRONLY | O_TRUNC | O_CLOEXEC); Require(fd >= 0);
            Require(write(fd,"[]",2) == 2); Require(close(fd) == 0);
          } else if ([scenario isEqual:@"missing"]) Require(unlink(commandPath.fileSystemRepresentation) == 0);
          else {
            if ([scenario isEqual:@"unsafe-mode"]) Require(chmod(replacementPath.fileSystemRepresentation,0644) == 0);
            if ([scenario isEqual:@"hardlink"]) Require(link(replacementPath.fileSystemRepresentation,
                [[directory stringByAppendingPathComponent:@"alias"] fileSystemRepresentation]) == 0);
            if ([scenario isEqual:@"symlink"]) {
              Require(unlink(commandPath.fileSystemRepresentation) == 0);
              Require(symlink(replacementPath.fileSystemRepresentation,commandPath.fileSystemRepresentation) == 0);
            } else Require(rename(replacementPath.fileSystemRepresentation,commandPath.fileSystemRepresentation) == 0);
          }
        };
        [owner tick]; ReadCheckpoint = nil;
        Require(pauses == 0);
        if ([scenario isEqual:@"atomic"]) {
          Require(terminals == 0 && !owner.isRetired);
          [owner tick]; Require(pauses == 1 && terminals == 0);
        } else Require(terminals == 1 && owner.isRetired);
      });
      [owner stop]; Flush(owner);
      if (completion) { completion(nil); Flush(owner); }
      Require(terminals == 1); owner = nil;
      Require([[NSFileManager defaultManager] removeItemAtPath:directory error:nil]);
    }
    puts("Capture handoff: indexed closed commands, predecessor/canvas/epoch, serial pause, deadline, Stop/late callbacks and unsafe file cases passed; no capture or input effects.");
  }
  return 0;
}
