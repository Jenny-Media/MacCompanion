#import "VNCSession.h"
#import <rfb/rfbclient.h>
#import <netdb.h>
#import <arpa/inet.h>
#import <sys/socket.h>

static char ownerTag;
static _Thread_local int protocolFailure;
static _Thread_local int protocolStage;
// Classify only upstream constant format strings. Never format or retain arguments.
static void QuietLog(const char *format, ...) {
    if (!strncmp(format, "VNC server supports protocol version", 36)) protocolStage = 1;
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

@interface VNCSession () {
    NSLock *_lock;
    NSMutableArray<NSDictionary *> *_events;
    dispatch_queue_t _worker;
    BOOL _running, _stopping, _framePending, _overflow, _inputReady;
    NSString *_username, *_password;
    uint8_t *_pixels;
    NSUInteger _connections, _updates, _resizes, _inputs, _viewChanges;
    NSInteger _generation;
    NSInteger _failureStage, _credentialRequests;
    BOOL _probeOnly;
    BOOL _dirty;
    double _lastFrame;
    NSMutableSet<NSNumber *> *_heldKeys;
    NSInteger _lastX, _lastY;
    NSInteger _queuedPointerMask;
}
- (rfbCredential *)credential:(int)type;
- (rfbBool)allocate:(rfbClient *)client;
- (void)updated;
- (void)publishFrame:(rfbClient *)client;
- (void)report:(NSString *)state;
- (void)begin:(NSString *)host port:(int)port user:(NSString *)user password:(NSString *)password fixture:(BOOL)fixture;
@end

static VNCSession *Owner(rfbClient *client) {
    return (__bridge VNCSession *)rfbClientGetClientData(client, &ownerTag);
}
static rfbBool Allocate(rfbClient *client) { return [Owner(client) allocate:client]; }
static void Updated(rfbClient *client, int x, int y, int w, int h) { [Owner(client) updated]; }
static rfbCredential *Credential(rfbClient *client, int type) { return [Owner(client) credential:type]; }

// Resolve once and connect to the numeric address. This experiment accepts LAN addresses only.
static NSString *LocalAddress(NSString *host) {
    struct addrinfo hints = {.ai_family = AF_INET, .ai_socktype = SOCK_STREAM}, *result = NULL;
    if (getaddrinfo(host.UTF8String, NULL, &hints, &result) != 0) return nil;
    NSString *answer = nil;
    for (struct addrinfo *p = result; p; p = p->ai_next) {
        struct sockaddr_in *a = (struct sockaddr_in *)p->ai_addr;
        uint32_t ip = ntohl(a->sin_addr.s_addr);
        BOOL local = (ip >> 24) == 10 || (ip >> 24) == 127 || (ip >> 16) == 0xC0A8 ||
            (ip >> 20) == 0xAC1 || (ip >> 16) == 0xA9FE;
        if (local) {
            char buffer[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &a->sin_addr, buffer, sizeof(buffer));
            answer = [NSString stringWithUTF8String:buffer];
            break;
        }
    }
    freeaddrinfo(result);
    return answer;
}

@implementation VNCSession
- (instancetype)init {
    if ((self = [super init])) {
        _lock = [NSLock new]; _events = [NSMutableArray new]; _heldKeys = [NSMutableSet new];
        _worker = dispatch_queue_create("prototype.rfb.owner", DISPATCH_QUEUE_SERIAL);
        rfbClientLog = QuietLog; rfbClientErr = QuietLog;
    }
    return self;
}
- (BOOL)running { [_lock lock]; BOOL r = _running; [_lock unlock]; return r; }
- (void)connectHost:(NSString *)host username:(NSString *)username password:(NSString *)password {
    [self begin:host port:5900 user:username password:password fixture:NO];
}
#if TARGET_OS_SIMULATOR
- (void)connectFixture { [self begin:@"127.0.0.1" port:5905 user:@"" password:@"" fixture:YES]; }
- (void)probeMacHandshake {
    _probeOnly = YES;
    [self begin:@"127.0.0.1" port:5900 user:@"" password:@"" fixture:NO];
}
#endif
- (void)begin:(NSString *)host port:(int)port user:(NSString *)user password:(NSString *)password fixture:(BOOL)fixture {
    [_lock lock];
    if (_running) { [_lock unlock]; return; }
    _running = YES; _stopping = NO; _overflow = NO; _framePending = NO; _inputReady = NO; _failureStage = 0;
    [_events removeAllObjects]; _queuedPointerMask = 0; _generation++; _connections++;
    NSInteger generation = _generation;
    [_lock unlock];
    [self report:@"Connecting"];
    dispatch_async(_worker, ^{
        @autoreleasepool {
            protocolFailure = 0; protocolStage = 0;
            NSString *address = LocalAddress(host);
            if (!address) { [self finish:@"Use a local IPv4 address or a Mac .local hostname"]; return; }
            self->_username = user; self->_password = password;
            rfbClient *client = rfbGetClient(8, 3, 4);
            if (!client) { [self finish:@"Client allocation failed"]; return; }
            rfbClientSetClientData(client, &ownerTag, (__bridge void *)self);
            free(client->serverHost);
            client->serverHost = strdup(address.UTF8String); client->serverPort = port;
            client->MallocFrameBuffer = Allocate; client->GotFrameBufferUpdate = Updated;
            client->GetCredential = Credential;
            client->canHandleNewFBSize = TRUE;
            client->connectTimeout = 8; client->readTimeout = 8;
            client->format.redShift = 16; client->format.greenShift = 8; client->format.blueShift = 0;
            client->format.bigEndian = FALSE; client->format.depth = 24;
            client->appData.encodingsString = "zrle zlib hextile raw";
            uint32_t schemes[] = {rfbARD};
#if TARGET_OS_SIMULATOR
            if (fixture) schemes[0] = rfbNoAuth;
#endif
            SetClientAuthSchemes(client, schemes, 1);
            int argc = 1; char *argv[] = {"VNCPrototype", NULL};
            // rfbInitClient frees the rfbClient on failure; framebuffer ownership is ours.
            BOOL connected = rfbInitClient(client, &argc, argv);
            self->_username = nil; self->_password = nil;
            if (!connected) {
                [self->_lock lock]; self->_failureStage = protocolFailure; [self->_lock unlock];
                NSArray *failures = @[@"Connection or handshake failed", @"Network read timed out",
                    @"Mac authentication method unsupported", @"ARD key generation failed",
                    @"ARD shared key failed", @"ARD key hashing failed", @"ARD credential encryption failed",
                    @"Credentials not supplied", @"Mac rejected login or Screen Sharing access", @"Desktop exceeds framebuffer limit"];
                [self finish:failures[MIN((NSUInteger)self->_failureStage, failures.count - 1)]];
                return;
            }
            [self->_lock lock]; self->_inputReady = !self->_stopping; [self->_lock unlock];
            [self report:@"Connected"];
            BOOL healthy = YES;
            while (healthy) {
                @autoreleasepool {
                    [self->_lock lock]; BOOL stopping = self->_stopping || self->_overflow;
                    NSArray *events = [self->_events copy]; [self->_events removeAllObjects];
                    [self->_lock unlock];
                    if (stopping) break;
                    for (NSDictionary *event in events) {
                        if (event[@"key"]) {
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
                    if (ready < 0 || (ready > 0 && !HandleRFBServerMessage(client))) { healthy = NO; break; }
                    [self publishFrame:client];
                }
            }
            // A disconnect cancels queued input and releases every key/button actually sent.
            for (NSNumber *key in self->_heldKeys) SendKeyEvent(client, key.unsignedIntValue, FALSE);
            [self->_heldKeys removeAllObjects];
            SendPointerEvent(client, (int)self->_lastX, (int)self->_lastY, 0);
            rfbClientCleanup(client);
            [self finish:self->_overflow ? @"Input queue full; disconnected safely" : healthy ? @"Disconnected" : @"Connection ended — reconnect"];
            (void)generation;
        }
    });
}
- (void)finish:(NSString *)state {
    free(_pixels); _pixels = NULL; _username = nil; _password = nil;
    [_lock lock]; _running = NO; _inputReady = NO; [_events removeAllObjects]; [_lock unlock];
    [self report:state];
}
- (rfbCredential *)credential:(int)type {
    if (type != rfbCredentialTypeUser) return NULL;
    protocolStage = 3;
    [_lock lock]; _credentialRequests++; [_lock unlock];
    if (_probeOnly) return NULL;
    [self report:@"Authenticating with macOS"];
    rfbCredential *credential = calloc(1, sizeof(rfbCredential));
    if (credential) {
        credential->userCredential.username = strdup(_username.UTF8String ?: "");
        credential->userCredential.password = strdup(_password.UTF8String ?: "");
    }
    return credential;
}
- (rfbBool)allocate:(rfbClient *)client {
    uint64_t bytes = (uint64_t)client->width * client->height * 4;
    if (client->width <= 0 || client->height <= 0 || client->width > 8192 || client->height > 8192 || bytes > 64 * 1024 * 1024) { protocolFailure = 9; return FALSE; }
    uint8_t *pixels = calloc(1, (size_t)bytes);
    if (!pixels) return FALSE;
    free(_pixels); _pixels = pixels; client->frameBuffer = pixels;
    protocolStage = 5;
    [_lock lock]; _resizes++; [_lock unlock]; _dirty = NO;
    return TRUE;
}
- (void)updated { _dirty = YES; [_lock lock]; _updates++; [_lock unlock]; }
- (void)publishFrame:(rfbClient *)client {
    double now = NSProcessInfo.processInfo.systemUptime;
    if (!_dirty || now - _lastFrame < 1.0 / 30) return;
    [_lock lock];
    if (_framePending || _stopping) { [_lock unlock]; return; }
    _framePending = YES; NSInteger generation = _generation; [_lock unlock];
    _dirty = NO; _lastFrame = now;
    NSData *copy = [NSData dataWithBytes:client->frameBuffer length:(NSUInteger)client->width * client->height * 4];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)copy);
    CGColorSpaceRef colors = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate(client->width, client->height, 8, 32, client->width * 4, colors,
        (CGBitmapInfo)kCGBitmapByteOrder32Little | (CGBitmapInfo)kCGImageAlphaNoneSkipFirst, provider, NULL, NO, kCGRenderingIntentDefault);
    UIImage *frame = image ? [UIImage imageWithCGImage:image] : nil;
    if (image) CGImageRelease(image); CGColorSpaceRelease(colors); CGDataProviderRelease(provider);
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_lock lock]; BOOL valid = generation == self->_generation && self->_running && !self->_stopping;
        if (generation == self->_generation) self->_framePending = NO; [self->_lock unlock];
        if (valid && frame && self.frameHandler) self.frameHandler(frame);
    });
    if (_updates % 30 == 0) [self report:@"Connected"];
}
- (void)report:(NSString *)state {
    // No endpoints, names, credentials, pixels, or typed content in diagnostics.
    [_lock lock];
    NSDictionary *stats = @{@"connectionStarts": @(_connections), @"updateRects": @(_updates),
        @"framebufferAllocations": @(_resizes), @"inputEvents": @(_inputs), @"viewChanges": @(_viewChanges),
        @"failureStage": @(_failureStage), @"credentialRequests": @(_credentialRequests), @"handshakeStage": @(protocolStage)};
    [_lock unlock];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.stateHandler) self.stateHandler(state, stats);
        NSURL *url = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        NSData *data = [NSJSONSerialization dataWithJSONObject:stats options:0 error:nil];
        [data writeToURL:[url URLByAppendingPathComponent:@"counters.json"] atomically:YES];
    });
}
- (void)stop { [_lock lock]; _stopping = YES; [_events removeAllObjects]; [_lock unlock]; }
- (void)enqueue:(NSDictionary *)event {
    [_lock lock];
    if (_running && _inputReady && !_stopping) {
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
- (void)text:(NSString *)text {
    // Send committed Unicode scalars; NSString enumeration keeps surrogate pairs intact.
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *s, NSRange range, NSRange enclosing, BOOL *stop) {
        NSData *scalars = [s dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
        const uint32_t *p = scalars.bytes;
        for (NSUInteger i = 0; i < scalars.length / 4; i++) {
            uint32_t scalar = p[i]; uint32_t key = scalar == 10 ? 0xff0d : scalar < 256 ? scalar : 0x01000000 | scalar;
            [self key:key down:YES]; [self key:key down:NO];
        }
    }];
}
- (void)viewChanged {
    [_lock lock]; _viewChanges++; [_lock unlock];
}
@end
