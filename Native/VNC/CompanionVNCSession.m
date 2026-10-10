#import "CompanionVNCSession.h"
#import "CompanionVNCFramebufferBounds.h"
#import "CompanionVNCCoverage.h"
#import "CompanionVNCKeyboard.h"
#import "CompanionVNCCursor.h"
#import "CompanionVNCDirectConnection.h"
#import "CompanionVNCDirectEndpoint.h"
#import "CompanionVNCDisplayLayout.h"
#import "CompanionVNCGestures.h"
#import "CompanionVNCReadiness.h"
#import <stdarg.h>
#import <rfb/rfbclient.h>
#import <netdb.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <unistd.h>

static char ownerTag;
static CompanionVNCImage *PlatformImage(CGImageRef image) {
#if TARGET_OS_OSX
    return [[NSImage alloc] initWithCGImage:image size:NSMakeSize(CGImageGetWidth(image), CGImageGetHeight(image))];
#else
    return [UIImage imageWithCGImage:image];
#endif
}
static _Thread_local int protocolFailure;
static _Thread_local int protocolStage;
static _Thread_local BOOL decoderFailed, appleGestureBanner;
// Classify upstream constants. Only the known banner reads numeric arguments;
// never format or retain server strings, credentials or other arguments.
static void QuietLog(const char *format, ...) {
    // Upstream 0.9.15's ZRLE tile failure logs this constant but returns TRUE.
    // Never format its arguments or accept the resulting rectangle as pixels.
    if (!strcmp(format, "ZRLE decoding failed (%d)\n")) decoderFailed = YES;
    if (!strcmp(format, "VNC server supports protocol version %d.%d (viewer %d.%d)\n")) {
        va_list args; va_start(args, format);
        int major = va_arg(args, int), minor = va_arg(args, int); va_end(args);
        appleGestureBanner = major == 3 && minor == 889; protocolStage = 1;
    }
    else if (!strcmp(format, "Selected Security Scheme %d\n")) protocolStage = 2;
    else if (!strcmp(format, "VNC authentication succeeded\n")) protocolStage = 4;
    if (!strcmp(format, "HandleARDAuth: generating keypair failed\n")) protocolFailure = 3;
    else if (!strcmp(format, "HandleARDAuth: creating shared key failed\n")) protocolFailure = 4;
    else if (!strcmp(format, "HandleARDAuth: hashing shared key failed\n")) protocolFailure = 5;
    else if (!strcmp(format, "HandleARDAuth: encrypting credentials failed\n")) protocolFailure = 6;
    else if (!strcmp(format, "HandleARDAuth: reading credential failed\n")) protocolFailure = 7;
    else if (!strcmp(format, "VNC connection failed: %s\n") || !strncmp(format, "VNC authentication failed", 25)) protocolFailure = 8;
    else if (!strncmp(format, "Unknown authentication scheme", 29)) protocolFailure = 2;
    else if (!strcmp(format, "Connection timed out\n") && !protocolFailure) protocolFailure = 1;
}

@interface CompanionVNCSession () {
    NSLock *_lock;
    NSMutableArray<NSDictionary *> *_events;
    dispatch_queue_t _worker;
    BOOL _running, _stopping, _framePending, _overflow, _inputReady, _inputOnly, _modeChanged;
    BOOL _paused, _releaseInputRequested, _resumeRequested, _awaitingResumeFrame;
    NSUInteger _presentationEpoch;
    dispatch_semaphore_t _wake;
    void (^_pauseCompletion)(void);
    NSString *_username, *_password;
    uint8_t *_pixels;
    NSUInteger _connections, _updates, _resizes, _inputs, _viewChanges, _presentedFrames;
    NSInteger _generation;
    int _socket;
    NSInteger _failureStage, _credentialRequests;
    NSInteger _framebufferWidth, _framebufferHeight;
    BOOL _probeOnly;
    BOOL _dirty, _extensionFailed, _layoutPending, _metadataCallback, _baselinePresented;
    CompanionVNCCoverage _coverage;
    CompanionVNCDisplayLayout _coverageLayout;
    BOOL _coverageLayoutValid;
    double _baselineStarted, _lastFullRefresh;
    NSUInteger _fullRefreshRetries, _receivedPixels, _expectedPixels;
    NSUInteger _decoderFailures;
    NSDictionary *_latestLayout;
    NSDictionary *_layoutDiagnostics;
    NSUInteger _layoutMessages;
    double _lastFrame;
    NSMutableSet<NSNumber *> *_heldKeys;
    NSInteger _lastX, _lastY;
    NSInteger _queuedPointerMask;
    BOOL _appleGestureServer, _nativeGestureLayout, _queuedMagnification;
    NSUInteger _gestureEpoch, _sentMagnificationEpoch;
    CompanionVNCMagnification _sentMagnification;
    BOOL _queuedScroll;
    CompanionVNCScroll _sentScroll;
    NSUInteger _sentScrollEpoch;
    int _scrollWidth, _scrollHeight;
    int _magnificationWidth, _magnificationHeight;
    CompanionVNCImage *_cursorImage;
    CGPoint _cursorHotspot, _cursorPosition;
    BOOL _cursorPositionKnown, _cursorPending, _cursorDirty;
    NSUInteger _cursorShapes, _cursorPositions, _pauses, _resumes, _resumeFrames;
}
- (rfbCredential *)credential:(int)type;
- (rfbBool)allocate:(rfbClient *)client;
- (void)updatedX:(int)x y:(int)y width:(int)width height:(int)height;
- (BOOL)resetBaseline:(rfbClient *)client;
- (void)applyCoverageLayout:(rfbClient *)client;
- (void)publishFrame:(rfbClient *)client;
- (void)cursorShape:(rfbClient *)client x:(int)x y:(int)y width:(int)width height:(int)height bytesPerPixel:(int)bytes;
- (rfbBool)cursorPosition:(rfbClient *)client x:(int)x y:(int)y;
- (void)publishCursor;
- (void)report:(NSString *)state;
- (void)beginSocket:(int)socket addresses:(NSArray<NSString *> *)addresses port:(NSInteger)port user:(NSString *)user password:(NSString *)password;
- (BOOL)registerSocket:(int)socket;
- (void)processConnectedClient:(rfbClient *)client;
- (void)cancelNativeGesturesLocked;
- (BOOL)releaseMagnification:(rfbClient *)client;
- (BOOL)sendMagnificationEvent:(NSDictionary *)event client:(rfbClient *)client;
- (BOOL)releaseScroll:(rfbClient *)client;
- (BOOL)sendScrollEvent:(NSDictionary *)event client:(rfbClient *)client;
- (rfbBool)displayLayout:(rfbClient *)client;
- (rfbBool)displayLayout:(rfbClient *)client encoding:(int)encoding;
@end

static CompanionVNCSession *Owner(rfbClient *client) {
    return (__bridge CompanionVNCSession *)rfbClientGetClientData(client, &ownerTag);
}
static rfbBool Allocate(rfbClient *client) { return [Owner(client) allocate:client]; }
static void Updated(rfbClient *client, int x, int y, int w, int h) { [Owner(client) updatedX:x y:y width:w height:h]; }
static rfbCredential *Credential(rfbClient *client, int type) { return [Owner(client) credential:type]; }
static void CursorShape(rfbClient *client, int x, int y, int width, int height, int bytes) {
    [Owner(client) cursorShape:client x:x y:y width:width height:height bytesPerPixel:bytes];
}
static rfbBool CursorPosition(rfbClient *client, int x, int y) { return [Owner(client) cursorPosition:client x:x y:y]; }
static rfbBool AppleLayout(rfbClient *client, rfbFramebufferUpdateRectHeader *rect) {
    if (rect->encoding != 1101 && rect->encoding != 1105) return FALSE;
    return [Owner(client) displayLayout:client encoding:rect->encoding];
}
// 1101 enables the server's display-info delivery; 1105 selects the newer
// layout format. Requesting 1105 alone leaves its send-display-info gate off.
static int layoutEncodings[] = {1101, 1105, 0};
static rfbClientProtocolExtension layoutExtension = {.encodings = layoutEncodings, .handleEncoding = AppleLayout};

@implementation CompanionVNCSession
- (void)dealloc { free(_pixels); CompanionVNCCoverageFree(&_coverage); }
- (instancetype)init {
    if ((self = [super init])) {
        _lock = [NSLock new]; _events = [NSMutableArray new]; _heldKeys = [NSMutableSet new];
        _worker = dispatch_queue_create("media.jenny.maccompanion.rfb.owner", DISPATCH_QUEUE_SERIAL);
        _socket = -1; _wake = dispatch_semaphore_create(0);
        rfbClientLog = QuietLog; rfbClientErr = QuietLog;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ rfbClientRegisterExtension(&layoutExtension); });
    }
    return self;
}
- (BOOL)running { [_lock lock]; BOOL r = _running; [_lock unlock]; return r; }
- (BOOL)connected { [_lock lock]; BOOL ready = _running && _inputReady && !_paused && !_stopping; [_lock unlock]; return ready; }
- (BOOL)inputOnly { [_lock lock]; BOOL value = _inputOnly; [_lock unlock]; return value; }
- (void)setInputOnly:(BOOL)value {
    [_lock lock]; if (_inputOnly != value) { [self cancelNativeGesturesLocked]; _inputOnly = value; _modeChanged = YES; _presentationEpoch++; }
    [_lock unlock]; dispatch_semaphore_signal(_wake);
}
- (BOOL)nativeMagnificationSupported {
    [_lock lock]; BOOL supported = _appleGestureServer && _nativeGestureLayout; [_lock unlock]; return supported;
}
- (BOOL)nativeScrollingSupported { return self.nativeMagnificationSupported; }
// Called under the queue lock. Copied events are retired by the same epoch.
- (void)cancelNativeGesturesLocked {
    _gestureEpoch++; _queuedMagnification = NO; _queuedScroll = NO;
    NSIndexSet *gestures = [_events indexesOfObjectsPassingTest:^BOOL(NSDictionary *event, NSUInteger index, BOOL *stop) { return event[@"magnifyPhase"] != nil || event[@"scrollPhase"] != nil; }];
    [_events removeObjectsAtIndexes:gestures];
}
- (void)cancelNativeGestures {
    [_lock lock]; [self cancelNativeGesturesLocked]; [_lock unlock]; dispatch_semaphore_signal(_wake);
}
- (BOOL)queueMagnification:(unsigned)phase delta:(double)delta x:(NSInteger)x y:(NSInteger)y {
    [_lock lock];
    BOOL ready = _running && _inputReady && _inputOnly && !_paused && !_stopping && !_overflow
        && _appleGestureServer && _nativeGestureLayout;
    BOOL valid = isfinite(delta) && fabs(delta) <= .5 && (phase == 2 || delta == 0)
        && (phase == 1 ? !_queuedMagnification && !_queuedScroll && x >= 0 && y >= 0 && x < _framebufferWidth && y < _framebufferHeight : _queuedMagnification);
    BOOL accepted = ready && valid && _events.count < 512;
    if (accepted) {
        [_events addObject:@{@"magnifyPhase": @(phase), @"delta": @(delta), @"x": @(x), @"y": @(y), @"gestureEpoch": @(_gestureEpoch)}];
        _queuedMagnification = phase != CompanionVNCMagnifyEnded;
    } else if (phase != CompanionVNCMagnifyBegan || (ready && _events.count >= 512)) {
        // End delivery cannot depend on finding space in a full input queue.
        [self cancelNativeGesturesLocked];
    }
    [_lock unlock]; dispatch_semaphore_signal(_wake); return accepted;
}
- (BOOL)beginMagnificationX:(NSInteger)x y:(NSInteger)y { return [self queueMagnification:1 delta:0 x:x y:y]; }
- (BOOL)changeMagnification:(double)delta { return [self queueMagnification:2 delta:delta x:0 y:0]; }
- (void)endMagnification { (void)[self queueMagnification:4 delta:0 x:0 y:0]; }
- (BOOL)releaseMagnification:(rfbClient *)client {
    if (!_sentMagnification.active) return YES;
    uint8_t bytes[52]; size_t count = CompanionVNCMagnificationPacket(&_sentMagnification, 4, 0, 0, 0,
        _magnificationWidth, _magnificationHeight, bytes, sizeof(bytes));
    return count && WriteToRFBServer(client, (char *)bytes, (unsigned int)count);
}
- (BOOL)sendMagnificationEvent:(NSDictionary *)event client:(rfbClient *)client {
    NSUInteger epoch = [event[@"gestureEpoch"] unsignedIntegerValue];
    [_lock lock]; BOOL valid = epoch == _gestureEpoch && _inputOnly && _inputReady && !_paused && !_stopping
        && _appleGestureServer && _nativeGestureLayout; [_lock unlock];
    if (!valid) return YES; // A discarded event cannot start or resume a gesture.
    unsigned phase = [event[@"magnifyPhase"] unsignedIntValue];
    if (phase == 1) {
        if (![self releaseMagnification:client]) return NO;
        _magnificationWidth = client->width; _magnificationHeight = client->height; _sentMagnificationEpoch = epoch;
    } else if (!_sentMagnification.active || _sentMagnificationEpoch != epoch) return YES;
    uint8_t bytes[52]; size_t count = CompanionVNCMagnificationPacket(&_sentMagnification, phase, [event[@"delta"] doubleValue],
        [event[@"x"] intValue], [event[@"y"] intValue], _magnificationWidth, _magnificationHeight, bytes, sizeof(bytes));
    // The state marks begin before writing so even a failed partial group gets a release attempt.
    return count && WriteToRFBServer(client, (char *)bytes, (unsigned int)count);
}
- (BOOL)queueScroll:(unsigned)phase dx:(double)dx dy:(double)dy x:(NSInteger)x y:(NSInteger)y {
    [_lock lock];
    BOOL ready = _running && _inputReady && !_paused && !_stopping && !_overflow
        && _appleGestureServer && _nativeGestureLayout;
    BOOL valid = (phase == 1 || phase == 2 || phase == 4) && isfinite(dx) && isfinite(dy)
        && fabs(dx) <= 2048 && fabs(dy) <= 2048 && (phase == 2 || (dx == 0 && dy == 0))
        && (phase == 1 ? !_queuedScroll && !_queuedMagnification && x >= 0 && y >= 0
            && x < _framebufferWidth && y < _framebufferHeight : _queuedScroll);
    BOOL accepted = ready && valid && _events.count < 512;
    if (accepted) {
        [_events addObject:@{@"scrollPhase": @(phase), @"dx": @(dx), @"dy": @(dy), @"x": @(x), @"y": @(y), @"gestureEpoch": @(_gestureEpoch)}];
        _queuedScroll = phase != 4;
    } else if (phase != 1 || (ready && _events.count >= 512)) [self cancelNativeGesturesLocked];
    [_lock unlock]; dispatch_semaphore_signal(_wake); return accepted;
}
- (BOOL)beginScrollX:(NSInteger)x y:(NSInteger)y { return [self queueScroll:1 dx:0 dy:0 x:x y:y]; }
- (BOOL)changeScrollX:(double)dx y:(double)dy { return [self queueScroll:2 dx:dx dy:dy x:0 y:0]; }
- (void)endScroll { (void)[self queueScroll:4 dx:0 dy:0 x:0 y:0]; }
- (BOOL)releaseScroll:(rfbClient *)client {
    if (!_sentScroll.active) return YES;
    uint8_t bytes[58]; size_t count = CompanionVNCScrollPacket(&_sentScroll, 4, 0, 0, 0, 0,
        _scrollWidth, _scrollHeight, bytes, sizeof(bytes));
    return count && WriteToRFBServer(client, (char *)bytes, (unsigned int)count);
}
- (BOOL)sendScrollEvent:(NSDictionary *)event client:(rfbClient *)client {
    NSUInteger epoch = [event[@"gestureEpoch"] unsignedIntegerValue];
    [_lock lock]; BOOL valid = epoch == _gestureEpoch && _inputReady && !_paused && !_stopping
        && _appleGestureServer && _nativeGestureLayout; [_lock unlock];
    if (!valid) return YES;
    unsigned phase = [event[@"scrollPhase"] unsignedIntValue];
    if (phase == 1) {
        if (![self releaseScroll:client]) return NO;
        _scrollWidth = client->width; _scrollHeight = client->height; _sentScrollEpoch = epoch;
    } else if (!_sentScroll.active || _sentScrollEpoch != epoch) return YES;
    uint8_t bytes[58]; size_t count = CompanionVNCScrollPacket(&_sentScroll, phase,
        [event[@"dx"] doubleValue], [event[@"dy"] doubleValue], [event[@"x"] intValue], [event[@"y"] intValue],
        _scrollWidth, _scrollHeight, bytes, sizeof(bytes));
    return count && WriteToRFBServer(client, (char *)bytes, (unsigned int)count);
}
- (BOOL)tryClickX:(NSInteger)x y:(NSInteger)y mask:(NSInteger)mask {
    [_lock lock]; BOOL accept = _running && _inputReady && !_paused && !_stopping && !_overflow && _events.count <= 510;
    if (accept) {
        [_events addObject:@{@"x": @(x), @"y": @(y), @"mask": @(mask), @"motion": @NO}];
        [_events addObject:@{@"x": @(x), @"y": @(y), @"mask": @0, @"motion": @NO}]; _queuedPointerMask = 0;
    }
    [_lock unlock]; return accept;
}
- (void)pauseWithCompletion:(void (^)(void))completion {
    [_lock lock];
    if (!_running || !_inputReady || _stopping || _paused) { [_lock unlock]; if (completion) completion(); return; }
    [self cancelNativeGesturesLocked];
    _paused = YES; _pauses++; _inputReady = NO; _releaseInputRequested = YES; _presentationEpoch++;
    [_events removeAllObjects]; _queuedPointerMask = 0; _pauseCompletion = [completion copy];
    [_lock unlock]; dispatch_semaphore_signal(_wake);
}
- (void)resume {
    [_lock lock];
    if (_running && _paused && !_stopping) {
        _paused = NO; _resumes++; _resumeRequested = YES; _awaitingResumeFrame = !_inputOnly; if (_inputOnly) _inputReady = YES; _presentationEpoch++;
    }
    [_lock unlock]; dispatch_semaphore_signal(_wake);
}
- (void)connectSocket:(int)socket username:(NSString *)username password:(NSString *)password {
    [self beginSocket:socket addresses:nil port:5900 user:username password:password];
}
- (void)connectHost:(NSString *)host username:(NSString *)username password:(NSString *)password {
    [self connectAddresses:@[host] port:5900 username:username password:password];
}
- (void)connectAddresses:(NSArray<NSString *> *)addresses port:(NSInteger)port username:(NSString *)username password:(NSString *)password {
    [self beginSocket:-1 addresses:[addresses copy] port:port user:username password:password];
}
- (BOOL)registerSocket:(int)socket {
    [_lock lock];
    BOOL accept = socket < 0 || !_stopping;
    // A separate descriptor keeps Stop's shutdown safe even when LibVNCClient
    // closes its descriptor internally on a failed handshake.
    if (accept) { if (_socket >= 0) close(_socket); _socket = socket >= 0 ? dup(socket) : -1; }
    [_lock unlock]; return accept;
}
- (void)beginSocket:(int)socket addresses:(NSArray<NSString *> *)addresses port:(NSInteger)port user:(NSString *)user password:(NSString *)password {
    [_lock lock];
    if (_running) { [_lock unlock]; if (socket >= 0) close(socket); return; }
    [self cancelNativeGesturesLocked]; _appleGestureServer = NO; _nativeGestureLayout = NO;
    _sentMagnification = (CompanionVNCMagnification){0}; _sentScroll = (CompanionVNCScroll){0};
    _running = YES; _stopping = NO; _overflow = NO; _framePending = NO; _cursorPending = NO; _layoutPending = NO; _latestLayout = nil; _inputReady = NO; _failureStage = 0;
    _layoutDiagnostics = @{}; _layoutMessages = 0; _baselinePresented = NO; _coverageLayoutValid = NO; _metadataCallback = NO;
    _paused = NO; _releaseInputRequested = NO; _resumeRequested = NO; _awaitingResumeFrame = NO; _presentationEpoch++;
    [_events removeAllObjects]; _queuedPointerMask = 0; _generation++; _connections++;
    NSInteger generation = _generation;
    [_lock unlock];
    [self report:@"Connecting"];
    dispatch_async(_worker, ^{
        @autoreleasepool {
            protocolFailure = 0; protocolStage = 0;
            NSData *u = [user dataUsingEncoding:NSUTF8StringEncoding], *p = [password dataUsingEncoding:NSUTF8StringEncoding];
            if (!CompanionVNCLoginBytes(u.bytes, u.length) || !CompanionVNCLoginBytes(p.bytes, p.length)) {
                if (socket >= 0) close(socket);
                [self finish:@"Enter a Mac login of 1–63 UTF-8 bytes per field"]; return;
            }
            int connection = socket;
            NSInteger routeFailure = 0;
            if (addresses) connection = CompanionVNCConnectAddresses(addresses, port, ^{
                [self->_lock lock]; BOOL stopped = self->_stopping; [self->_lock unlock]; return stopped;
            }, ^BOOL(int fd) { return [self registerSocket:fd]; }, ^(NSUInteger index, NSUInteger count) {
                [self report:count > 1 ? [NSString stringWithFormat:@"Contacting Mac · address %lu of %lu", (unsigned long)index, (unsigned long)count] : @"Contacting Mac"];
            }, &routeFailure);
            else if (![self registerSocket:connection]) { close(connection); [self finish:@"Disconnected"]; return; }
            if (connection < 0) {
                [self->_lock lock]; self->_failureStage = routeFailure; [self->_lock unlock];
                [self finish:routeFailure == 10 ? @"Address unavailable. Check the address, DNS or VPN connection." : @"Mac did not respond. Check Screen Sharing, VPN access and the port."]; return;
            }
            [self report:@"Signing in"];
            self->_cursorImage = nil; self->_cursorHotspot = CGPointZero; self->_cursorPosition = CGPointZero;
            self->_cursorPositionKnown = NO; self->_cursorDirty = YES;
            self->_extensionFailed = NO;
            self->_username = user; self->_password = password;
            rfbClient *client = rfbGetClient(8, 3, 4);
            if (!client) { [self->_lock lock]; self->_failureStage = 100; [self->_lock unlock]; [self registerSocket:-1]; close(connection); [self finish:@"Client allocation failed"]; return; }
            [self configureClient:client]; client->sock = connection;
            uint32_t schemes[] = {rfbARD};

            SetClientAuthSchemes(client, schemes, 1);
            int argc = 1; char *argv[] = {"MacCompanion", NULL};
            // rfbInitClient frees the rfbClient on failure; framebuffer ownership is ours.
            BOOL connected = rfbInitClient(client, &argc, argv);
            self->_username = nil; self->_password = nil;
            if (!connected) {
                [self registerSocket:-1];
                [self->_lock lock]; self->_failureStage = protocolFailure; [self->_lock unlock];
                NSArray *failures = @[@"Connection or handshake failed", @"Network read timed out",
                    @"Mac authentication method unsupported", @"ARD key generation failed",
                    @"ARD shared key failed", @"ARD key hashing failed", @"ARD credential encryption failed",
                    @"Credentials not supplied", @"Mac rejected login or Screen Sharing access", @"Desktop exceeds framebuffer limit"];
                [self finish:failures[MIN((NSUInteger)self->_failureStage, failures.count - 1)]];
                return;
            }
            [self->_lock lock]; self->_appleGestureServer = appleGestureBanner; self->_inputReady = !self->_stopping; BOOL active = self->_inputReady; [self->_lock unlock];
            if (active) [self report:self.inputOnly ? @"Connected" : @"Opening desktop"];
            [self processConnectedClient:client];
            (void)generation;
        }
    });
}
- (void)processConnectedClient:(rfbClient *)client {
    BOOL healthy = YES;
    while (healthy) {
        @autoreleasepool {
            [self->_lock lock]; BOOL stopping = self->_stopping || self->_overflow;
            BOOL paused = self->_paused, release = self->_releaseInputRequested, resume = self->_resumeRequested;
            BOOL inputOnly = self->_inputOnly, modeChanged = self->_modeChanged; self->_modeChanged = NO;
            self->_releaseInputRequested = NO; self->_resumeRequested = NO;
            void (^completion)(void) = release ? self->_pauseCompletion : nil;
            if (release) self->_pauseCompletion = nil;
            NSUInteger gestureEpoch = self->_gestureEpoch;
            NSArray *events = [self->_events copy]; [self->_events removeAllObjects];
            [self->_lock unlock];
            if (stopping) break;
            if (self->_sentMagnification.active && (release || paused || !inputOnly || gestureEpoch != self->_sentMagnificationEpoch)) {
                healthy = [self releaseMagnification:client]; if (!healthy) break;
            }
            if (self->_sentScroll.active && (release || paused || gestureEpoch != self->_sentScrollEpoch)) {
                healthy = [self releaseScroll:client]; if (!healthy) break;
            }
            if (release) {
                for (NSNumber *key in self->_heldKeys) if (!SendKeyEvent(client, key.unsignedIntValue, FALSE)) healthy = NO;
                [self->_heldKeys removeAllObjects];
                if (!SendPointerEvent(client, (int)self->_lastX, (int)self->_lastY, 0)) healthy = NO;
                if (completion) dispatch_async(dispatch_get_main_queue(), completion);
            }
            if (!healthy) break;
            if (paused) {
                // No polling, decoding, or update requests while hidden. Stop/resume wake the owner.
                dispatch_semaphore_wait(self->_wake, DISPATCH_TIME_FOREVER); continue;
            }
            // LibVNCClient normally requests another frame automatically after every update.
            // On the sole socket owner, mask only update requests and use an empty rectangle
            // so even a server capability refresh cannot ask for desktop pixels in input-only.
            unsigned char *requests = &client->supportedMessages.client2server[rfbFramebufferUpdateRequest / 8];
            unsigned char bit = 1 << (rfbFramebufferUpdateRequest % 8);
            if (inputOnly) {
                *requests &= ~bit; rfbRectangle empty = {0, 0, 0, 0}; rfbClientSetUpdateRect(client, &empty);
                if (resume || modeChanged) [self report:@"Connected"];
            } else {
                *requests |= bit; rfbClientSetUpdateRect(client, NULL);
            }
            if (!inputOnly && (resume || modeChanged)) {
                if (![self resetBaseline:client] || !SendFramebufferUpdateRequest(client, 0, 0, client->width, client->height, FALSE)) { healthy = NO; break; }
            }
            if (!inputOnly && !CompanionVNCCoverageReady(&self->_coverage)) {
                double now = NSProcessInfo.processInfo.systemUptime;
                if (now - self->_baselineStarted >= 8) { [self->_lock lock]; self->_failureStage = 102; [self->_lock unlock]; healthy = NO; break; }
                if (self->_fullRefreshRetries < 2 && now - self->_lastFullRefresh >= 1) {
                    if (!SendFramebufferUpdateRequest(client, 0, 0, client->width, client->height, FALSE)) { healthy = NO; break; }
                    [self->_lock lock]; self->_fullRefreshRetries++; [self->_lock unlock]; self->_lastFullRefresh = now;
                }
            }
            for (NSDictionary *event in events) {
                [self->_lock lock]; BOOL acceptsInput = self->_inputReady && !self->_paused && !self->_stopping; [self->_lock unlock];
                if (!acceptsInput) break;
                if (event[@"magnifyPhase"]) {
                    healthy = [self sendMagnificationEvent:event client:client];
                } else if (event[@"scrollPhase"]) {
                    healthy = [self sendScrollEvent:event client:client];
                } else if (event[@"key"]) {
                    uint32_t key = [event[@"key"] unsignedIntValue]; BOOL down = [event[@"down"] boolValue];
                    healthy = SendKeyEvent(client, key, down);
                    if (down) [self->_heldKeys addObject:@(key)]; else [self->_heldKeys removeObject:@(key)];
                } else {
                    self->_lastX = MAX(0, MIN(client->width - 1, [event[@"x"] integerValue]));
                    self->_lastY = MAX(0, MIN(client->height - 1, [event[@"y"] integerValue]));
                    healthy = SendPointerEvent(client, (int)self->_lastX, (int)self->_lastY, [event[@"mask"] intValue]);
                }
                [self->_lock lock]; self->_inputs++; [self->_lock unlock];
                if (!healthy) break;
            }
            if (!healthy) break;
            int ready = WaitForMessage(client, 10000);
            if (ready < 0 || (ready > 0 && !HandleRFBServerMessage(client)) || self->_extensionFailed) { healthy = NO; break; }
            [self publishFrame:client];
            [self publishCursor];
        }
    }
    // A disconnect cancels queued input and releases every gesture/key/button actually sent.
    [self releaseMagnification:client]; [self releaseScroll:client];
    for (NSNumber *key in self->_heldKeys) SendKeyEvent(client, key.unsignedIntValue, FALSE);
    [self->_heldKeys removeAllObjects];
    SendPointerEvent(client, (int)self->_lastX, (int)self->_lastY, 0);
    [self registerSocket:-1]; rfbClientCleanup(client);
    if (self->_overflow) { [self->_lock lock]; self->_failureStage = 101; [self->_lock unlock]; }
    [self finish:self->_overflow ? @"Input queue full; disconnected safely" : self->_failureStage == 103 ? @"Desktop image could not be decoded — reconnect" : self->_failureStage == 102 ? @"Desktop did not finish loading — reconnect" : healthy ? @"Disconnected" : @"Connection ended — reconnect"];

}
- (void)configureClient:(rfbClient *)client {
    decoderFailed = NO; appleGestureBanner = NO;
    rfbClientSetClientData(client, &ownerTag, (__bridge void *)self);
    free(client->serverHost);
    client->serverHost = strdup("selected-desktop"); client->listenSpecified = TRUE;
    client->MallocFrameBuffer = Allocate; client->GotFrameBufferUpdate = Updated;
    client->GetCredential = Credential;
    client->GotCursorShape = CursorShape; client->HandleCursorPos = CursorPosition;
    client->appData.useRemoteCursor = TRUE;
    client->canHandleNewFBSize = TRUE;
    client->connectTimeout = 8; client->readTimeout = 8;
    client->format.redShift = 16; client->format.greenShift = 8; client->format.blueShift = 0;
    client->format.bigEndian = FALSE; client->format.depth = 24;
    client->appData.encodingsString = "zlib hextile raw";
}
- (void)finish:(NSString *)state {
    [self registerSocket:-1];
    free(_pixels); _pixels = NULL; CompanionVNCCoverageFree(&_coverage); _username = nil; _password = nil;
    _cursorImage = nil; _cursorPositionKnown = NO; _cursorDirty = NO;
    [_lock lock]; [self cancelNativeGesturesLocked]; _appleGestureServer = NO; _nativeGestureLayout = NO; _running = NO; _inputReady = NO; [_events removeAllObjects]; [_lock unlock];
    [self report:state];
}
- (rfbCredential *)credential:(int)type {
    if (type != rfbCredentialTypeUser) return NULL;
    protocolStage = 3;
    [_lock lock]; _credentialRequests++; [_lock unlock];

    [self report:@"Authenticating with macOS"];
    rfbCredential *credential = calloc(1, sizeof(rfbCredential));
    if (credential) {
        credential->userCredential.username = strdup(_username.UTF8String ?: "");
        credential->userCredential.password = strdup(_password.UTF8String ?: "");
    }
    return credential;
}
- (rfbBool)allocate:(rfbClient *)client {
    [_lock lock]; [self cancelNativeGesturesLocked];
    _framebufferWidth = client->width; _framebufferHeight = client->height;
    _nativeGestureLayout = CompanionVNCNativeGesturesSupported(YES, _coverageLayoutValid, client->width, client->height, _coverageLayout.width, _coverageLayout.height);
    [_lock unlock];
    size_t bytes;
    if (!CompanionVNCFramebufferByteCount(client->width, client->height, &bytes)) { protocolFailure = 9; return FALSE; }
    uint8_t *pixels = calloc(1, (size_t)bytes);
    if (!pixels) return FALSE;
    if (![self resetBaseline:client]) { free(pixels); return FALSE; }
    free(_pixels); _pixels = pixels; client->frameBuffer = pixels;
    protocolStage = 5;
    [_lock lock]; _resizes++; [_lock unlock]; _dirty = NO;
    _cursorImage = nil; _cursorHotspot = CGPointZero; _cursorPositionKnown = NO; _cursorDirty = YES;
    return TRUE;
}
- (BOOL)resetBaseline:(rfbClient *)client {
    if (!CompanionVNCCoverageReset(&_coverage, client->width, client->height)) return NO;
    _baselineStarted = _lastFullRefresh = NSProcessInfo.processInfo.systemUptime;
    _dirty = NO;
    [_lock lock]; _fullRefreshRetries = 0; _baselinePresented = NO; _presentationEpoch++; [_lock unlock];
    [self applyCoverageLayout:client]; return YES;
}
- (void)applyCoverageLayout:(rfbClient *)client {
    // Only exact backing geometry can omit gaps. Unknown/scaled layouts keep full coverage.
    CompanionVNCCoverageClearRequirements(&_coverage);
    if (_coverageLayoutValid && _coverageLayout.width == client->width && _coverageLayout.height == client->height) {
        for (NSUInteger i = 0; i < _coverageLayout.count; i++) {
            CompanionVNCDisplay d = _coverageLayout.displays[i];
            CompanionVNCCoverageRect(&_coverage, d.x, d.y, d.width, d.height, true);
        }
    } else { CompanionVNCCoverageRect(&_coverage,0,0,client->width,client->height,true); }
    [_lock lock]; _receivedPixels = _coverage.received; _expectedPixels = _coverage.expected; [_lock unlock];
}
- (void)updatedX:(int)x y:(int)y width:(int)width height:(int)height {
    if (decoderFailed) {
        decoderFailed = NO; _extensionFailed = YES;
        [_lock lock]; _decoderFailures++; _failureStage = 103; [_lock unlock];
        return;
    }
    if (_metadataCallback) { _metadataCallback = NO; return; }
    if (!CompanionVNCCoverageReady(&_coverage)) CompanionVNCCoverageRect(&_coverage, x, y, width, height, false);
    _dirty = YES;
    [_lock lock]; _updates++; _receivedPixels = _coverage.received; _expectedPixels = _coverage.expected; [_lock unlock];
}
- (rfbBool)displayLayout:(rfbClient *)client {
    return [self displayLayout:client encoding:1105];
}
- (rfbBool)displayLayout:(rfbClient *)client encoding:(int)encoding {
    _metadataCallback = YES;
    uint8_t prefix[2];
    if (!ReadFromRFBServer(client, (char *)prefix, 2)) { _extensionFailed = YES; return TRUE; }
    size_t length = CompanionVNCBE16(prefix);
    NSMutableData *body = [NSMutableData dataWithLength:length];
    if (length && !ReadFromRFBServer(client, body.mutableBytes, (unsigned int)length)) { _extensionFailed = YES; return TRUE; }
    CompanionVNCDisplayLayout decoded = {0};
    NSMutableArray *views = [NSMutableArray new];
    CGFloat aspect = 0;
    BOOL parsed = encoding == 1105 && CompanionVNCDecodeDisplayLayout(body.bytes, length, &decoded);
    // Retain only numeric geometry, never the opaque payload or framebuffer.
    const uint8_t *p = body.bytes;
    NSMutableDictionary *geometry = [@{@"encoding": @(encoding), @"bodyLength": @(length), @"parsed": @(parsed)} mutableCopy];
    if (length >= 20) {
        geometry[@"version"] = @(CompanionVNCBE16(p));
        geometry[@"scaledWidth"] = @(CompanionVNCBE16(p + 2));
        geometry[@"scaledHeight"] = @(CompanionVNCBE16(p + 4));
        geometry[@"backingWidth"] = @(CompanionVNCBE16(p + 6));
        geometry[@"backingHeight"] = @(CompanionVNCBE16(p + 8));
        geometry[@"declaredCount"] = @(CompanionVNCBE16(p + 18));
        NSMutableArray *records = [NSMutableArray new];
        for (NSUInteger i = 0; i < MIN((length - 20) / 56, 32); i++) {
            const uint8_t *r = p + 20 + i * 56;
            [records addObject:@{@"rect20": @[@(CompanionVNCBE16(r + 20)), @(CompanionVNCBE16(r + 22)), @(CompanionVNCBE16(r + 24)), @(CompanionVNCBE16(r + 26))],
                @"rect28": @[@(CompanionVNCBE16(r + 28)), @(CompanionVNCBE16(r + 30)), @(CompanionVNCBE16(r + 32)), @(CompanionVNCBE16(r + 34))]}];
        }
        geometry[@"records"] = records;
    }
    [_lock lock]; _layoutMessages++; _layoutDiagnostics = geometry; [_lock unlock];
    if (encoding == 1101) { [self report:@"Connected"]; return TRUE; }
    BOOL changed = _coverageLayoutValid && (!parsed || _coverageLayout.width != decoded.width || _coverageLayout.height != decoded.height || _coverageLayout.count != decoded.count || memcmp(_coverageLayout.displays, decoded.displays, sizeof(CompanionVNCDisplay) * decoded.count) != 0);
    _coverageLayoutValid = parsed; if (parsed) _coverageLayout = decoded;
    [_lock lock];
    BOOL gestureLayout = CompanionVNCNativeGesturesSupported(YES, parsed, client->width, client->height, parsed ? decoded.width : 0, parsed ? decoded.height : 0);
    if (changed || _nativeGestureLayout != gestureLayout) [self cancelNativeGesturesLocked];
    _nativeGestureLayout = gestureLayout; [_lock unlock];
    if (changed && _coverage.seen) {
        // Hot-plug/rearrangement also retires the old baseline without blanking its image.
        if (![self resetBaseline:client] || !SendFramebufferUpdateRequest(client,0,0,client->width,client->height,FALSE)) _extensionFailed = YES;
    } else { [self applyCoverageLayout:client]; }
    if (parsed) {
        aspect = (CGFloat)decoded.width / decoded.height;
        for (NSUInteger i = 0; i < decoded.count; i++) {
            CompanionVNCDisplay d = decoded.displays[i];
            [views addObject:@{@"id": @(d.id), @"title": [NSString stringWithFormat:@"Display %lu", (unsigned long)i + 1],
                @"pixelWidth": @(d.width), @"pixelHeight": @(d.height),
                @"x": @((double)d.x / decoded.width), @"y": @((double)d.y / decoded.height),
                @"width": @((double)d.width / decoded.width), @"height": @((double)d.height / decoded.height)}];
        }
    }
    CGFloat scale = parsed && CompanionVNCBE16(p + 2) > 0 ? (CGFloat)decoded.width / CompanionVNCBE16(p + 2) : 2;
    NSDictionary *layout = @{@"aspectRatio": @(aspect), @"backingScale": @(scale), @"views": views};
    [self report:@"Connected"];
    [_lock lock]; NSInteger generation = _generation; NSUInteger epoch = _presentationEpoch; _latestLayout = layout;
    if (_layoutPending) { [_lock unlock]; return TRUE; }
    _layoutPending = YES; [_lock unlock];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_lock lock]; BOOL valid = generation == self->_generation && epoch == self->_presentationEpoch && self->_running && !self->_stopping && !self->_paused;
        NSDictionary *latest = self->_latestLayout;
        if (generation == self->_generation) { self->_layoutPending = NO; self->_latestLayout = nil; }
        [self->_lock unlock];
        if (valid && self.displayLayoutHandler) self.displayLayoutHandler(latest);
    });
    return TRUE;
}
- (void)cursorShape:(rfbClient *)client x:(int)x y:(int)y width:(int)width height:(int)height bytesPerPixel:(int)bytes {
    _cursorImage = nil; _cursorHotspot = CGPointZero; _cursorDirty = YES;
    [_lock lock]; _cursorShapes++; [_lock unlock];
    if (width <= 0 || height <= 0 || width > 256 || height > 256 || bytes != 4) return;
    NSUInteger count = (NSUInteger)width * height;
    NSMutableData *rgba = [NSMutableData dataWithLength:count * 4];
    if (!CompanionVNCCursorRGBA(width, height, bytes, x, y, client->rcSource, count * 4,
        client->rcMask, count, rgba.mutableBytes, rgba.length)) return;
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)rgba);
    CGColorSpaceRef colors = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate(width, height, 8, 32, width * 4, colors,
        (CGBitmapInfo)kCGBitmapByteOrder32Big | (CGBitmapInfo)kCGImageAlphaPremultipliedLast, provider, NULL, NO, kCGRenderingIntentDefault);
    if (image) { _cursorImage = PlatformImage(image); _cursorHotspot = CGPointMake(x, y); CGImageRelease(image); }
    CGColorSpaceRelease(colors); CGDataProviderRelease(provider);
}
- (rfbBool)cursorPosition:(rfbClient *)client x:(int)x y:(int)y {
    _cursorPositionKnown = x >= 0 && y >= 0 && x < client->width && y < client->height;
    _cursorPosition = CGPointMake(x, y); _cursorDirty = YES;
    [_lock lock]; _cursorPositions++; [_lock unlock];
    return TRUE;
}
- (void)publishCursor {
    if (!_cursorDirty) return;
    [_lock lock];
    if (_cursorPending || _stopping || _paused) { [_lock unlock]; return; }
    _cursorPending = YES; NSInteger generation = _generation; NSUInteger epoch = _presentationEpoch; [_lock unlock];
    _cursorDirty = NO;
    CompanionVNCImage *image = _cursorImage; CGPoint hotspot = _cursorHotspot, position = _cursorPosition;
    BOOL known = _cursorPositionKnown;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_lock lock]; BOOL valid = generation == self->_generation && epoch == self->_presentationEpoch && self->_running && !self->_stopping && !self->_paused;
        if (generation == self->_generation) self->_cursorPending = NO; [self->_lock unlock];
        if (valid && self.cursorHandler) self.cursorHandler(image, hotspot, position, known);
    });
}
- (void)publishFrame:(rfbClient *)client {
    double now = NSProcessInfo.processInfo.systemUptime;
    if (_extensionFailed || !_dirty || !CompanionVNCCoverageReady(&_coverage) || now - _lastFrame < 1.0 / 30) return;
    [_lock lock];
    if (_framePending || _stopping || _paused || _inputOnly) { [_lock unlock]; return; }
    _framePending = YES; NSInteger generation = _generation; NSUInteger epoch = _presentationEpoch; [_lock unlock];
    _dirty = NO; _lastFrame = now;
    NSData *copy = [NSData dataWithBytes:client->frameBuffer length:(NSUInteger)client->width * client->height * 4];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)copy);
    CGColorSpaceRef colors = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate(client->width, client->height, 8, 32, client->width * 4, colors,
        (CGBitmapInfo)kCGBitmapByteOrder32Little | (CGBitmapInfo)kCGImageAlphaNoneSkipFirst, provider, NULL, NO, kCGRenderingIntentDefault);
    CompanionVNCImage *frame = image ? PlatformImage(image) : nil;
    if (image) CGImageRelease(image); CGColorSpaceRelease(colors); CGDataProviderRelease(provider);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_lock lock]; BOOL valid = generation == self->_generation && epoch == self->_presentationEpoch && self->_running && !self->_stopping && !self->_paused;
        if (generation == self->_generation) self->_framePending = NO; [self->_lock unlock];
        if (valid && frame && self.frameHandler) self.frameHandler(frame);
        if (valid && frame) {
            [self->_lock lock]; BOOL firstBaseline = !self->_baselinePresented; self->_baselinePresented = YES; self->_presentedFrames++;
            BOOL resumed = self->_awaitingResumeFrame;
            if (resumed) { self->_resumeFrames++; self->_awaitingResumeFrame = NO; self->_inputReady = YES; }
            [self->_lock unlock];
            if (resumed || firstBaseline) [self report:@"Connected"];
        }
    });
    if (_presentedFrames > 0 && _updates % 30 == 0) [self report:@"Connected"];
}
- (void)report:(NSString *)state {
    // No endpoints, names, credentials, pixels, or typed content in diagnostics.
    [_lock lock];
    if ([state isEqualToString:@"Connected"] && !CompanionVNCConnectionReady(
        _running, _inputReady, _inputOnly, _paused, _stopping, _overflow,
        _awaitingResumeFrame, _baselinePresented)) { [_lock unlock]; return; }
    NSInteger generation = _generation; NSUInteger epoch = _presentationEpoch; BOOL intermediate = _running;
    NSDictionary *stats = @{@"connectionStarts": @(_connections), @"updateRects": @(_updates),
        @"framebufferAllocations": @(_resizes), @"inputEvents": @(_inputs), @"viewChanges": @(_viewChanges), @"presentedFrames": @(_presentedFrames),
        @"baselineReady": @(_baselinePresented), @"baselineReceivedPixels": @(_receivedPixels), @"baselineExpectedPixels": @(_expectedPixels), @"fullRefreshRetries": @(_fullRefreshRetries),
        @"decoderFailures": @(_decoderFailures),
        @"failureStage": @(_failureStage), @"credentialRequests": @(_credentialRequests), @"handshakeStage": @(protocolStage),
        @"framebufferWidth": @(_framebufferWidth), @"framebufferHeight": @(_framebufferHeight),
        @"displayLayoutMessages": @(_layoutMessages), @"displayLayout": _layoutDiagnostics ?: @{},
        @"backgroundPauses": @(_pauses), @"retainedResumes": @(_resumes), @"resumeFrames": @(_resumeFrames),
        @"cursorShapeUpdates": @(_cursorShapes), @"cursorPositionUpdates": @(_cursorPositions)};
    [_lock unlock];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_lock lock]; BOOL current = generation == self->_generation && !(intermediate && (self->_stopping || epoch != self->_presentationEpoch)); [self->_lock unlock];
        if (current && self.stateHandler) self.stateHandler(state, stats);
    });
}
- (void)stop {
    [_lock lock]; [self cancelNativeGesturesLocked]; _stopping = YES; _presentationEpoch++; [_events removeAllObjects]; NSInteger generation = _generation;
    void (^completion)(void) = _pauseCompletion; _pauseCompletion = nil;
    if (!_inputReady && _socket >= 0) shutdown(_socket, SHUT_RDWR);
    [_lock unlock];
    dispatch_semaphore_signal(_wake);
    if (completion) dispatch_async(dispatch_get_main_queue(), completion);
    // Give the owner a short opportunity to release sent keys, then unblock any
    // stalled partial-frame read. This never affects a newer connection.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self->_lock lock];
        if (self->_generation == generation && self->_stopping && self->_socket >= 0) shutdown(self->_socket, SHUT_RDWR);
        [self->_lock unlock];
    });
}
- (void)enqueue:(NSDictionary *)event {
    [_lock lock];
    if (_running && _inputReady && !_paused && !_stopping) {
        // Coalesce only motion with identical button state, preserving key/button ordering.
        NSDictionary *last = _events.lastObject;
        if (event[@"mask"]) {
            NSInteger mask = [event[@"mask"] integerValue];
            BOOL motion = mask == _queuedPointerMask;
            _queuedPointerMask = mask;
            NSMutableDictionary *annotated = [event mutableCopy]; annotated[@"motion"] = @(motion); event = annotated;
            if (motion && [last[@"motion"] boolValue] && [event[@"mask"] isEqual:last[@"mask"]]) [_events removeLastObject];
        }
        if (_events.count >= 512) _overflow = YES; else [_events addObject:event];
    }
    [_lock unlock];
}
- (void)pointerX:(NSInteger)x y:(NSInteger)y mask:(NSInteger)mask {
    [self enqueue:@{@"x": @(x), @"y": @(y), @"mask": @(mask)}];
}
- (void)key:(uint32_t)key down:(BOOL)down { [self enqueue:@{@"key": @(key), @"down": @(down)}]; }
- (void)keyEvents:(NSArray<NSDictionary *> *)events {
    [_lock lock];
    if (_running && _inputReady && !_paused && !_stopping && !_overflow) {
        if (!CompanionVNCKeyGroupFits(_events.count, events.count, 512)) _overflow = YES;
        else [_events addObjectsFromArray:events];
    }
    [_lock unlock];
}
- (void)viewChanged {
    [_lock lock]; _viewChanges++; [_lock unlock];
}
- (BOOL)tryKeyEvents:(NSArray<NSDictionary *> *)events {
    [_lock lock];
    BOOL allowed = _running && _inputReady && !_paused && !_stopping && !_overflow
        && events.count > 0 && CompanionVNCKeyGroupFits(_events.count, events.count, 512);
    if (allowed) [_events addObjectsFromArray:events];
    [_lock unlock]; return allowed;
}
@end
