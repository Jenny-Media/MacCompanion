#import "BenchmarkJournal.h"
#include <math.h>
@implementation MCBenchmarkJournal {
    NSURL *_url;
    NSUInteger _maximumBytes, _sequence, _droppedSamples;
    NSLock *_lock;
    dispatch_queue_t _queue;
    __weak id _owner;
    NSString *_token;
    BOOL _busy, _full;
}
- (instancetype)initWithURL:(NSURL *)url maximumBytes:(NSUInteger)maximumBytes {
    if ((self = [super init])) {
        _url = url; _maximumBytes = maximumBytes; _lock = [NSLock new];
        _queue = dispatch_queue_create("media.jenny.maccompanion.prototype.numeric-journal", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}
- (BOOL)full { [_lock lock]; BOOL result = _full; [_lock unlock]; return result; }
- (NSUInteger)droppedSamples { [_lock lock]; NSUInteger result = _droppedSamples; [_lock unlock]; return result; }
- (void)beginOwner:(id)owner {
    [_lock lock]; if (_owner != owner) { _owner = owner; _token = NSUUID.UUID.UUIDString; _sequence = 0; } [_lock unlock];
}
- (void)endOwner:(id)owner { [_lock lock]; if (_owner == owner) { _owner = nil; _token = nil; } [_lock unlock]; }
+ (NSDictionary *)numbers:(NSDictionary *)source keys:(NSArray<NSString *> *)keys {
    NSMutableDictionary *result = [NSMutableDictionary new];
    for (NSString *key in keys) {
        id value = source[key];
        if ([value isKindOfClass:NSNumber.class] && isfinite([value doubleValue])) result[key] = value;
    }
    return result;
}
+ (NSDictionary *)filteredCounters:(NSDictionary *)counters {
    NSMutableDictionary *result = [[self numbers:counters keys:@[@"framebufferWidth", @"framebufferHeight", @"presentedFrames", @"serverMessages", @"updateRects", @"decoderFailures", @"sessionPaused", @"sessionInputReady", @"backgroundPauses", @"retainedResumes", @"connectionStarts", @"cursorShapeUpdates", @"cursorPositionUpdates", @"cursorPublications", @"framebufferAllocations", @"probeRequests", @"probeAccepted", @"probeTimedOut", @"probeAwaiting", @"probeWidth", @"probeHeight", @"sampleUptime"]] mutableCopy];
    if ([counters[@"probeOutcome"] isKindOfClass:NSNumber.class] && isfinite([counters[@"probeOutcome"] doubleValue])) result[@"probeOutcome"] = counters[@"probeOutcome"];
    [result addEntriesFromDictionary:[self numbers:counters keys:@[@"sessionRunning", @"sessionEstablished"]]];
    [result addEntriesFromDictionary:[self numbers:counters keys:@[@"failureStage", @"baselineReceivedPixels", @"baselineExpectedPixels", @"layoutWidth", @"layoutHeight", @"layoutCount", @"layoutVirtual", @"probeLayoutResizes"]]];
    for (NSString *group in @[@"pipeline", @"desktopSSH"]) {
        id source = counters[group]; if (![source isKindOfClass:NSDictionary.class]) continue;
        NSArray *keys = [group isEqualToString:@"pipeline"]
            ? @[@"workerCPUTotalMS", @"frameCopyTotalMS", @"frameCopyMaxMS", @"frameMainQueueMaxMS", @"frameCallbackMaxMS", @"unreadBytesLatest", @"unreadBytesMax"]
            : @[@"inboundBytes", @"outboundBytes", @"inboundQueuedBytes", @"inboundPeakQueuedBytes", @"inboundWriteMaxMS", @"outboundWriteMaxMS"];
        result[group] = [self numbers:source keys:keys];
    }
    return result;
}
- (void)appendCounters:(NSDictionary *)counters owner:(id)owner {
    NSDictionary *safe = [MCBenchmarkJournal filteredCounters:counters];
    [_lock lock];
    if (_owner != owner || !_token || _busy || _full) { _droppedSamples++; [_lock unlock]; return; }
    _busy = YES; NSString *token = _token; NSUInteger sequence = ++_sequence;
    NSNumber *captured = safe[@"sampleUptime"] ?: @(NSProcessInfo.processInfo.systemUptime);
    NSDictionary *row = @{@"schema": @1, @"owner": token, @"sequence": @(sequence), @"uptime": captured,
                          @"writtenUptime": @(NSProcessInfo.processInfo.systemUptime), @"counters": safe};
    [_lock unlock];
    dispatch_async(_queue, ^{
        NSData *encoded = [NSJSONSerialization dataWithJSONObject:row options:NSJSONWritingSortedKeys error:NULL];
        NSMutableData *data = [encoded mutableCopy]; [data appendBytes:"\n" length:1];
        [self->_lock lock];
        BOOL current = self->_owner == owner && [self->_token isEqualToString:token];
        [self->_lock unlock];
        if (current && data) {
            NSFileManager *fm = NSFileManager.defaultManager;
            [fm createDirectoryAtURL:self->_url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL];
            if (![fm fileExistsAtPath:self->_url.path]) [fm createFileAtPath:self->_url.path contents:nil attributes:@{NSFilePosixPermissions: @0600}];
            NSFileHandle *file = [NSFileHandle fileHandleForWritingToURL:self->_url error:NULL];
            unsigned long long size = 0;
            BOOL usable = file && [file seekToEndReturningOffset:&size error:NULL];
            BOOL fits = usable && size <= self->_maximumBytes && data.length <= self->_maximumBytes - size;
            BOOL written = fits && [file writeData:data error:NULL];
            [file closeAndReturnError:NULL];
            [self->_lock lock]; if (usable && !fits) self->_full = YES; if (!written) self->_droppedSamples++; [self->_lock unlock];
        }
        [self->_lock lock]; self->_busy = NO; [self->_lock unlock];
    });
}
- (void)flush:(void (^)(void))completion { dispatch_async(_queue, completion); }
@end
