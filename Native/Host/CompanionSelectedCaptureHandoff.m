#import "CompanionSelectedCaptureHandoff.h"
#import <mach/mach_time.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <sys/stat.h>
#include <unistd.h>

static NSError *HandoffError(NSInteger code) {
  // Fixed local codes distinguish handoff retirement from selection loss.
  // No command, receipt, path, identity, metadata or input is formatted.
  if (getenv("MACCOMPANION_NATIVE_SELECTION_PATH")) fprintf(stderr,"selected-capture-handoff-error=%ld\n",(long)code);
  return [NSError errorWithDomain:@"MacCompanion.CaptureHandoff" code:code userInfo:nil];
}
static uint64_t HandoffNow(void) {
  mach_timebase_info_data_t scale;
  if (mach_timebase_info(&scale) != KERN_SUCCESS || !scale.denom) return UINT64_MAX;
  return (uint64_t)((__uint128_t)mach_absolute_time() * scale.numer / scale.denom);
}
static BOOL HandoffInteger(id value, uint64_t minimum, uint64_t maximum) {
  if (![value isKindOfClass:[NSNumber class]] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NO;
  // Deadline values are exact native UInt64 integers; do not convert via double.
  const char *type = [value objCType];
  if (!strcmp(type,@encode(float)) || !strcmp(type,@encode(double))) return NO;
  if ([value longLongValue] < 0) return NO;
  uint64_t number = [value unsignedLongLongValue];
  return number >= minimum && number <= maximum;
}
static BOOL HandoffUUID(id value) {
  return [value isKindOfClass:[NSString class]] &&
    [[[[NSUUID alloc] initWithUUIDString:value] UUIDString] isEqual:value];
}
static NSData *HandoffJSON(id object) {
  return [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes error:nil];
}
static BOOL HandoffSafeRecord(struct stat facts, off_t maximum) {
  return S_ISREG(facts.st_mode) && facts.st_uid == geteuid() && facts.st_nlink == 1
    && (facts.st_mode & 0777) == 0600 && facts.st_size > 0 && facts.st_size <= maximum;
}

@implementation CompanionSelectedCaptureHandoffCommand
+ (instancetype)parseData:(NSData *)data now:(uint64_t)now error:(NSError **)error {
  NSDictionary *value = data.length && data.length <= 8192 ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  BOOL select = [value isKindOfClass:[NSDictionary class]] && [value[@"action"] isEqual:@"select"];
  NSMutableSet *keys = [NSMutableSet setWithArray:@[@"profile",@"transportOperationID",@"operationID",@"sequence",@"action",@"expiresAtMonotonicNanoseconds"]];
  if (select) [keys addObjectsFromArray:@[@"previousOperationID",@"context"]];
  if (![value isKindOfClass:[NSDictionary class]] || ![[NSSet setWithArray:value.allKeys] isEqual:keys]
      || ![HandoffJSON(value) isEqual:data] || ![value[@"profile"] isEqual:@"maccompanion.capture-handoff.v1"]
      || (!select && ![value[@"action"] isEqual:@"pause"])
      || !HandoffUUID(value[@"transportOperationID"]) || !HandoffUUID(value[@"operationID"])
      || !HandoffInteger(value[@"sequence"],1,9007199254740991ULL)
      || !HandoffInteger(value[@"expiresAtMonotonicNanoseconds"],1,INT64_MAX)
      || [value[@"expiresAtMonotonicNanoseconds"] unsignedLongLongValue] <= now
      || [value[@"expiresAtMonotonicNanoseconds"] unsignedLongLongValue] - now > 14400000000000ULL) {
    if (error) *error = HandoffError(1); return nil;
  }
  CompanionSelectedCaptureContext *context = nil;
  if (select) {
    NSDictionary *record = value[@"context"];
    if (!HandoffUUID(value[@"previousOperationID"]) || [value[@"previousOperationID"] isEqual:value[@"operationID"]]
        || ![record isKindOfClass:[NSDictionary class]] || ![record[@"profile"] isEqual:@"maccompanion.selected-capture-context.v0.2"]
        || !HandoffInteger(record[@"displayID"],1,UINT32_MAX)) { if (error) *error = HandoffError(2); return nil; }
    context = [CompanionSelectedCaptureContext parseData:HandoffJSON(record) operationID:value[@"operationID"]
        displayID:[record[@"displayID"] unsignedIntValue] now:now error:error];
    if (!context || context.expiresAtMonotonicNanoseconds != [value[@"expiresAtMonotonicNanoseconds"] unsignedLongLongValue]) {
      if (error) *error = HandoffError(3); return nil;
    }
  }
  CompanionSelectedCaptureHandoffCommand *command = [self new];
  command->_transportOperationID = [value[@"transportOperationID"] copy]; command->_operationID = [value[@"operationID"] copy];
  command->_action = [value[@"action"] copy]; command->_sequence = [value[@"sequence"] unsignedLongLongValue];
  command->_expiresAtMonotonicNanoseconds = [value[@"expiresAtMonotonicNanoseconds"] unsignedLongLongValue];
  command->_previousOperationID = [value[@"previousOperationID"] copy]; command->_context = context;
  return command;
}
@end

typedef NS_ENUM(NSUInteger, HandoffPhase) { HandoffInert, HandoffActive, HandoffPausing, HandoffPaused, HandoffSelecting, HandoffStopping, HandoffStopped };

@interface CompanionSelectedCaptureHandoff () {
  int _directory;
  dispatch_queue_t _queue;
  dispatch_source_t _timer;
  HandoffPhase _phase;
  CompanionSelectedCaptureContext *_context;
  NSString *_transport;
  uint64_t _sequence, _handoffDeadline;
  NSData *_lastCommand, *_lastReceipt;
  BOOL _pending;
  NSError *_failure;
  CompanionCaptureHandoffPause _pause;
  CompanionCaptureHandoffSelect _select;
  void (^_terminal)(NSError * _Nullable);
  NSLock *_publicationLock;
  BOOL _stopRequested, _deliveryAllowed;
  NSMutableArray<dispatch_block_t> *_stopCompletions;
}
- (void)consumeData:(NSData *)data now:(uint64_t)now;
- (void)tick;
- (void)finish:(NSError * _Nullable)error;
- (dispatch_queue_t)deliveryQueue;
- (void)checkExpiryAt:(uint64_t)now;
@end

@implementation CompanionSelectedCaptureHandoff
- (instancetype)initWithDirectory:(NSString *)path initialContext:(CompanionSelectedCaptureContext *)context
    pause:(CompanionCaptureHandoffPause)pause select:(CompanionCaptureHandoffSelect)select
    terminal:(void (^)(NSError * _Nullable))terminal error:(NSError **)error {
  self = [super init]; if (!self) return nil;
  _directory = -1;
  _publicationLock = [NSLock new];
  _stopCompletions = [NSMutableArray new];
  if (!context.frameEpoch || !pause || !select || !terminal || ![path hasPrefix:@"/"] || path.length >= PATH_MAX) {
    if (error) *error = HandoffError(4); return nil;
  }
  int fd = open("/",O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
  NSArray *parts = [path componentsSeparatedByString:@"/"];
  for (NSUInteger index = 1; fd >= 0 && index < parts.count; index++) {
    NSString *part = parts[index];
    if (!part.length || [part isEqual:@"."] || [part isEqual:@".."]) { close(fd); fd = -1; break; }
    int next = openat(fd,part.fileSystemRepresentation,O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    close(fd); fd = next;
  }
  struct stat facts;
  if (fd < 0 || fstat(fd,&facts) || !S_ISDIR(facts.st_mode) || facts.st_uid != geteuid() || (facts.st_mode & 0777) != 0700) {
    if (fd >= 0) close(fd); if (error) *error = HandoffError(5); return nil;
  }
  _directory = fd; _context = context; _transport = context.operationID;
  _pause = [pause copy]; _select = [select copy]; _terminal = [terminal copy];
  _queue = dispatch_queue_create("media.jenny.maccompanion.capture-handoff",DISPATCH_QUEUE_SERIAL);
  return self;
}
- (void)dealloc { if (_directory >= 0) close(_directory); }
- (dispatch_queue_t)deliveryQueue { return _queue; }
- (BOOL)isDeliveryAllowed {
  [_publicationLock lock]; BOOL allowed = _deliveryAllowed && !_stopRequested; [_publicationLock unlock];
  return allowed;
}
- (BOOL)stopRequested {
  [_publicationLock lock]; BOOL stopped = _stopRequested; [_publicationLock unlock]; return stopped;
}
- (BOOL)isRetired { return [self stopRequested]; }
- (void)setDeliveryAllowed:(BOOL)allowed {
  [_publicationLock lock]; _deliveryAllowed = allowed && !_stopRequested; [_publicationLock unlock];
}
- (void)start {
  dispatch_async(_queue, ^{
    if (self->_phase != HandoffInert || [self stopRequested]) { [self finish:nil]; return; }
    self->_phase = HandoffActive;
    [self setDeliveryAllowed:YES];
    self->_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,self->_queue);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self->_timer, ^{ [weakSelf tick]; });
    dispatch_source_set_timer(self->_timer,dispatch_time(DISPATCH_TIME_NOW,0),20000000,2000000);
    dispatch_resume(self->_timer);
  });
}
- (void)stop {
  [self stopWithCompletion:nil];
}
- (void)stopWithCompletion:(dispatch_block_t)completion {
  [_publicationLock lock]; _stopRequested = YES; _deliveryAllowed = NO; [_publicationLock unlock];
  dispatch_async(_queue, ^{
    if (self->_phase == HandoffStopped) { if (completion) completion(); return; }
    if (completion) [self->_stopCompletions addObject:[completion copy]];
    [self finish:nil];
  });
}
- (void)finish:(NSError *)error {
  if (_phase == HandoffStopped) return;
  if (_phase != HandoffStopping) { _phase = HandoffStopping; _failure = error; }
  [_publicationLock lock]; _stopRequested = YES; _deliveryAllowed = NO; [_publicationLock unlock];
  if (_timer) { dispatch_source_cancel(_timer); _timer = nil; }
  if (_pending) return;
  _phase = HandoffStopped;
  void (^terminal)(NSError *) = _terminal;
  _terminal = nil; _pause = nil; _select = nil; _lastReceipt = nil;
  if (terminal) terminal(_failure);
  NSArray<dispatch_block_t> *completions = [_stopCompletions copy];
  [_stopCompletions removeAllObjects];
  for (dispatch_block_t completion in completions) completion();
}
- (BOOL)writeReceipt:(NSData *)bytes {
  // Hold publication through rename. Stop returns only after any earlier reply
  // publication, and every later publication observes its synchronous fence.
  [_publicationLock lock];
  if (_stopRequested || _phase == HandoffStopping || _phase == HandoffStopped || !bytes || bytes.length > 1024) {
    [_publicationLock unlock]; return NO;
  }
  int existing = openat(_directory,"capture-handoff-receipt.json",O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
  struct stat facts;
  BOOL safe = existing < 0 ? errno == ENOENT : fstat(existing,&facts) == 0 && HandoffSafeRecord(facts,1024);
  if (safe && existing >= 0 && facts.st_size == (off_t)bytes.length) {
    NSMutableData *current = [NSMutableData dataWithLength:bytes.length];
    ssize_t count = read(existing,current.mutableBytes,current.length);
    struct stat after, named;
    BOOL unchanged = count == (ssize_t)current.length && fstat(existing,&after) == 0
      && fstatat(_directory,"capture-handoff-receipt.json",&named,AT_SYMLINK_NOFOLLOW) == 0
      && HandoffSafeRecord(after,1024) && HandoffSafeRecord(named,1024)
      && facts.st_dev == named.st_dev && facts.st_ino == named.st_ino
      && after.st_size == facts.st_size && after.st_mode == facts.st_mode && after.st_uid == facts.st_uid
      && after.st_mtimespec.tv_sec == facts.st_mtimespec.tv_sec && after.st_mtimespec.tv_nsec == facts.st_mtimespec.tv_nsec
      && after.st_ctimespec.tv_sec == facts.st_ctimespec.tv_sec && after.st_ctimespec.tv_nsec == facts.st_ctimespec.tv_nsec;
    if (!unchanged) { close(existing); [_publicationLock unlock]; return NO; }
    if ([current isEqual:bytes]) {
      close(existing); [_publicationLock unlock]; return YES;
    }
  }
  if (existing >= 0) close(existing);
  if (!safe) { [_publicationLock unlock]; return NO; }
  NSString *temporary = [@"capture-receipt-" stringByAppendingString:NSUUID.UUID.UUIDString];
  int fd = openat(_directory,temporary.fileSystemRepresentation,O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,0600);
  if (fd < 0) { [_publicationLock unlock]; return NO; }
  ssize_t count = write(fd,bytes.bytes,bytes.length);
  BOOL okay = count == (ssize_t)bytes.length;
  if (close(fd)) okay = NO;
  if (okay) okay = renameat(_directory,temporary.fileSystemRepresentation,_directory,"capture-handoff-receipt.json") == 0;
  if (!okay) unlinkat(_directory,temporary.fileSystemRepresentation,0);
  [_publicationLock unlock];
  return okay;
}
- (void)reply:(CompanionSelectedCaptureHandoffCommand *)command result:(NSString *)result {
  if ([self stopRequested] || _phase == HandoffStopping || _phase == HandoffStopped) return;
  NSData *data = HandoffJSON(@{@"profile":@"maccompanion.capture-handoff-receipt.v1",@"transportOperationID":command.transportOperationID,
    @"operationID":command.operationID,@"sequence":@(command.sequence),@"action":command.action,@"result":result});
  if (![self writeReceipt:data]) { [self finish:HandoffError(6)]; return; }
  _lastReceipt = data;
}
- (void)tick {
  if ([self stopRequested] || _phase == HandoffStopping || _phase == HandoffStopped) return;
  uint64_t now = HandoffNow();
  [self checkExpiryAt:now];
  if ([self stopRequested]) return;
  int fd = openat(_directory,"capture-handoff-command.json",O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK);
  if (fd < 0) { if (errno != ENOENT) [self finish:HandoffError(8)]; return; }
  struct stat facts, after;
  BOOL safe = fstat(fd,&facts) == 0 && S_ISREG(facts.st_mode) && facts.st_uid == geteuid()
    && facts.st_nlink <= 1 && (facts.st_mode & 0777) == 0600 && facts.st_size > 0 && facts.st_size <= 8192;
  NSMutableData *data = safe ? [NSMutableData dataWithLength:(NSUInteger)facts.st_size] : nil;
  ssize_t count = safe ? read(fd,data.mutableBytes,data.length) : -1;
  safe = safe && count == (ssize_t)data.length && fstat(fd,&after) == 0 && after.st_size == facts.st_size
    && after.st_nlink <= 1 && after.st_mode == facts.st_mode && after.st_uid == facts.st_uid
    && after.st_mtimespec.tv_sec == facts.st_mtimespec.tv_sec && after.st_mtimespec.tv_nsec == facts.st_mtimespec.tv_nsec;
  close(fd);
  if (!safe) { [self finish:HandoffError(9)]; return; }
  struct stat named;
  if (fstatat(_directory,"capture-handoff-command.json",&named,AT_SYMLINK_NOFOLLOW) != 0
      || !HandoffSafeRecord(named,8192)) { [self finish:HandoffError(9)]; return; }
  if (named.st_dev != facts.st_dev || named.st_ino != facts.st_ino) return;
  if (after.st_nlink != 1 || after.st_ctimespec.tv_sec != facts.st_ctimespec.tv_sec
      || after.st_ctimespec.tv_nsec != facts.st_ctimespec.tv_nsec) { [self finish:HandoffError(9)]; return; }
  [self consumeData:data now:now];
}
- (void)checkExpiryAt:(uint64_t)now {
  if (_phase != HandoffStopped && _phase != HandoffStopping &&
      (now >= _context.expiresAtMonotonicNanoseconds || (_handoffDeadline && now >= _handoffDeadline))) [self finish:HandoffError(7)];
}
- (void)consumeData:(NSData *)data now:(uint64_t)now {
  if ([self stopRequested] || _phase == HandoffStopping || _phase == HandoffStopped) return;
  NSError *error = nil;
  CompanionSelectedCaptureHandoffCommand *command = [CompanionSelectedCaptureHandoffCommand parseData:data now:now error:&error];
  if (!command || ![command.transportOperationID isEqual:_transport]
      || command.expiresAtMonotonicNanoseconds != _context.expiresAtMonotonicNanoseconds
      || command.sequence < _sequence) { [self finish:error ?: HandoffError(10)]; return; }
  if (command.sequence == _sequence) {
    if (![data isEqual:_lastCommand]) { [self finish:HandoffError(11)]; return; }
    if (_lastReceipt && ![self writeReceipt:_lastReceipt]) [self finish:HandoffError(6)];
    return;
  }
  if (_pending) { [self finish:HandoffError(12)]; return; }
  BOOL pause = [command.action isEqual:@"pause"];
  if (pause ? (_phase != HandoffActive || ![command.operationID isEqual:_context.operationID]) :
      (_phase != HandoffPaused || ![command.previousOperationID isEqual:_context.operationID]
       || command.context.encodedWidth != _context.encodedWidth || command.context.encodedHeight != _context.encodedHeight
       || [command.context.frameEpoch isEqual:_context.frameEpoch])) { [self finish:HandoffError(13)]; return; }
  _sequence = command.sequence; _lastCommand = [data copy]; _lastReceipt = nil; _pending = YES;
  [self setDeliveryAllowed:NO];
  if (pause) {
    _phase = HandoffPausing;
    _handoffDeadline = MIN(_context.expiresAtMonotonicNanoseconds,now + 15000000000ULL);
  } else _phase = HandoffSelecting;
  void (^completion)(NSError *) = ^(NSError *failure) {
    dispatch_async(self->_queue, ^{
      // A duplicate platform completion cannot acknowledge a later command.
      if (!self->_pending || self->_sequence != command.sequence) return;
      self->_pending = NO;
      if ([self stopRequested] || self->_phase == HandoffStopping) { [self finish:nil]; return; }
      uint64_t completed = HandoffNow();
      if (failure || completed >= self->_handoffDeadline || completed >= self->_context.expiresAtMonotonicNanoseconds) {
        [self finish:failure ?: HandoffError(7)]; return;
      }
      if (pause) self->_phase = HandoffPaused;
      else { self->_context = command.context; self->_phase = HandoffActive; self->_handoffDeadline = 0; [self setDeliveryAllowed:YES]; }
      [self reply:command result:pause ? @"paused" : @"selected"];
    });
  };
  if (pause) _pause(completion); else _select(command.context,completion);
}
@end
