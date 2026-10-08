#import "CompanionVNCTransport.h"
#import <sys/socket.h>
#import <unistd.h>

@implementation CompanionVNCTransport {
    int _client, _peer;
    NSLock *_lock;
    BOOL _stopped, _started;
    dispatch_queue_t _read, _write;
}
- (instancetype)init {
    if ((self = [super init])) {
        _client = -1; _peer = -1;
        int sockets[2];
        if (socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) != 0) return nil;
        _client = sockets[0]; _peer = sockets[1];
        int noSignal = 1; setsockopt(_peer, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
        setsockopt(_client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
        _lock = [NSLock new];
        _read = dispatch_queue_create("media.jenny.maccompanion.rfb.read", DISPATCH_QUEUE_SERIAL);
        _write = dispatch_queue_create("media.jenny.maccompanion.rfb.write", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}
- (int)takeClientSocket {
    [_lock lock]; int fd = _client; _client = -1; [_lock unlock]; return fd;
}
- (void)start {
    [_lock lock]; if (_started || _stopped) { [_lock unlock]; return; } _started = YES; [_lock unlock];
    dispatch_async(_read, ^{
        uint8_t bytes[16384];
        for (;;) {
            ssize_t length = read(self->_peer, bytes, sizeof(bytes));
            if (length <= 0) break;
            NSData *data = [NSData dataWithBytes:bytes length:(NSUInteger)length];
            dispatch_semaphore_t done = dispatch_semaphore_create(0);
            __block BOOL accepted = NO;
            void (^outbound)(NSData *, void (^)(BOOL)) = self.outbound;
            if (!outbound) break;
            outbound(data, ^(BOOL success) { accepted = success; dispatch_semaphore_signal(done); });
            // One chunk in flight. Timeout cancels the transport; no data retry.
            if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC)) != 0 || !accepted) break;
        }
        [self stop]; if (self.ended) self.ended();
    });
}
- (void)receiveData:(NSData *)data completion:(void (^)(BOOL))completion {
    dispatch_async(_write, ^{
        const uint8_t *bytes = data.bytes; NSUInteger remaining = data.length;
        while (remaining) {
            ssize_t count = write(self->_peer, bytes, remaining);
            if (count <= 0) { completion(NO); return; }
            bytes += count; remaining -= count;
        }
        completion(YES);
    });
}
- (void)stop {
    [_lock lock]; BOOL first = !_stopped; _stopped = YES; [_lock unlock];
    if (first) shutdown(_peer, SHUT_RDWR);
}
- (void)dealloc {
    if (_client >= 0) close(_client);
    if (_peer >= 0) close(_peer);
}
@end
