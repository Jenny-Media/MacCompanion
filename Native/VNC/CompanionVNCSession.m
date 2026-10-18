#import "CompanionVNCSession.h"
#import "CompanionVNCDesktopSize.h"
#import "CompanionVNCFramebufferBounds.h"
#import "CompanionVNCCoverage.h"
#import "CompanionVNCKeyboard.h"
#import "CompanionVNCCursor.h"
#import "CompanionVNCAppleCursor.h"
#import "CompanionVNCAppleUpdates.h"
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
#import <sys/ioctl.h>
#import <time.h>

// Public per-thread CPU clock: elapsed read/decode time also includes blocking.
static double WorkerCPUTimeMS(void) {
    struct timespec value;
    return clock_gettime(CLOCK_THREAD_CPUTIME_ID, &value) == 0 ? value.tv_sec * 1000.0 + value.tv_nsec / 1000000.0 : -1;
}
static NSUInteger UnreadRFBBytes(rfbClient *client) {
    int bytes = 0;
    if (ioctl(client->sock, FIONREAD, &bytes) != 0 || bytes < 0) bytes = 0;
    return (NSUInteger)bytes + client->buffered;
}
typedef struct {
    uint64_t socketBytes, deliveredBytes;
    double waitMS;
} CompanionVNCSwitchReadSnapshot;
static uint64_t ReadCounterDelta(uint64_t end, uint64_t start) { return end >= start ? end - start : 0; }
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
    CompanionVNCDesktopSize _desktopResizeSize;
    BOOL _desktopResizePending, _desktopResizeAwaiting, _desktopResizeSelection, _desktopResizeVirtualLayout;
    uint32_t _desktopResizeDisplayID;
    int _desktopResizePixelWidth, _desktopResizePixelHeight;
    NSUInteger _desktopResizeRequests, _desktopResizeAccepted, _desktopResizeTimedOut, _desktopResizeOutcome, _desktopResizeLayoutResizes, _desktopResizeNoops, _desktopResizeMetadataRequests;
    NSArray *_desktopResizeDisplays;
    CompanionVNCDisplayLayout _desktopCatalogueLayout;
    NSDictionary *_desktopCatalogue;
    BOOL _desktopResizeLayoutSeen, _desktopResizeLateEligible;
    NSUInteger _desktopResizeLayoutProbes, _desktopResizeLayoutsAtWrite, _physicalLayoutAdoptions, _selectionDeliveryPreserved;
    double _desktopResizeStarted, _desktopResizeLayoutMS, _desktopResizeCompleteMS;
    NSMutableArray<NSDictionary *> *_events;
#if TARGET_OS_IOS
    NSMutableDictionary<NSString *, void (^)(BOOL)> *_composedTextReplies;
#endif
    dispatch_queue_t _worker;
    BOOL _running, _established, _stopping, _framePending, _overflow, _inputReady, _inputOnly, _modeChanged;
    BOOL _paused, _releaseInputRequested, _resumeRequested, _awaitingResumeFrame;
    BOOL _reviewInputSuspended, _interruptionInputSuspended, _displayHandoffInputBlocked, _desktopResizeHandoff;
    void (^_reviewReleaseCompletion)(void);
    NSUInteger _presentationEpoch, _inputEpoch;
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
    double _baselineStarted, _lastFullRefresh, _baselineLastProgress;
    BOOL _baselineRequestSent, _routinePullPausedForSwitch;
    NSUInteger _fullRefreshRequests, _coalescedFullRefreshes, _routinePullRestarts;
    NSMutableArray<NSDictionary *> *_desktopSwitchSamples;
    double _desktopResizeAdmitted, _desktopResizeQueueMS, _desktopResizeCPUMSAtWrite, _desktopResizePreLayoutCPU;
    NSUInteger _desktopResizeUnreadAtWrite, _desktopResizeRectsAtWrite, _desktopResizePreLayoutRects, _desktopResizeRefreshRequests;
    BOOL _desktopResizeSampleRecorded, _desktopResizeMetricsReady, _readMeasurementsInstalled;
    CompanionVNCSwitchReadSnapshot _desktopReadAtWrite, _desktopReadAtLayout, _desktopReadAtFrame;
    double _outerSocketWaitMS, _desktopResizeProcessingCPUMS, _desktopResizeCopyMS, _desktopResizeMainQueueMS, _desktopResizeFrameCallbackMS;
    BOOL _desktopResizeProcessingClockAvailable;
#if TARGET_OS_OSX || TARGET_OS_IOS
    CompanionVNCReadMetrics _socketReadMetrics;
    CompanionVNCReadService _readService;
#endif
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
    BOOL _cursorPositionKnown, _cursorPositionDirty, _cursorPending, _cursorDirty, _cursorImageAvailable;
    BOOL _localPointerInteractionActive, _readingServerMessage;
    NSUInteger _pointerRevision, _cursorPositionRevision, _serverMessagePointerRevision;
    CompanionVNCImage *_pendingCursorImage;
    CGPoint _pendingCursorHotspot, _pendingCursorPosition;
    BOOL _pendingCursorPositionKnown;
    NSUInteger _pendingCursorEpoch, _pendingCursorPositionRevision;
    double _pendingCursorReceivedAt;
    NSUInteger _serverMessages, _bufferedReadDispatches, _readServiceEvents;
    double _serverMessageTotalMS, _serverMessageMaxMS, _cursorQueueMaxMS;
    NSUInteger _workerCPUSamples, _interactiveMessages, _pixelMessages, _cursorOnlyMessages;
    NSUInteger _unreadBytesLatest, _unreadBytesMax, _interactiveUnreadBytesMax;
    double _workerCPUTotalMS, _workerCPUMaxMS, _interactiveWallMS, _interactiveCPUMS, _interactiveMessageMaxMS;
    double _pixelMessageMaxMS, _cursorOnlyMessageMaxMS, _frameCopyTotalMS, _frameCopyMaxMS, _frameMainQueueMaxMS, _frameCallbackMaxMS;
    NSDictionary *_reportedCounters;
    NSUInteger _handshakeStage;
    NSUInteger _cursorShapes, _cursorPositions, _pauses, _resumes, _resumeFrames;
    NSMutableDictionary<NSNumber *, NSDictionary *> *_appleCursorCache;
    NSMutableArray<NSNumber *> *_appleCursorOrder;
    NSUInteger _appleCursorBytes, _appleCursorStores, _appleCursorSelections, _appleCursorMisses;
    NSUInteger _standardCursorReports, _visibleCursorImages, _cursorPublications, _cursorPositionPublications, _cursorPositionsSuppressed;
    BOOL _automaticUpdatesActive, _automaticUpdatePending, _desktopRefreshPending;
    int _automaticUpdateWidth, _automaticUpdateHeight;
    NSUInteger _automaticUpdateStarts, _automaticUpdateStops;
}
- (rfbCredential *)credential:(int)type;
- (rfbBool)allocate:(rfbClient *)client;
- (void)updatedX:(int)x y:(int)y width:(int)width height:(int)height;
- (BOOL)resetBaseline:(rfbClient *)client;
- (void)applyCoverageLayout:(rfbClient *)client;
- (void)publishFrame:(rfbClient *)client;
- (void)cursorShape:(rfbClient *)client x:(int)x y:(int)y width:(int)width height:(int)height bytesPerPixel:(int)bytes;
- (rfbBool)cursorPosition:(rfbClient *)client x:(int)x y:(int)y;
- (rfbBool)appleCursorPosition:(rfbClient *)client x:(int)x y:(int)y;
- (void)publishCursor;
- (BOOL)handleServerMessage:(rfbClient *)client;
- (BOOL)installDesktopReadService:(rfbClient *)client;
- (CompanionVNCSwitchReadSnapshot)switchReadSnapshot;
- (NSDictionary *)pipelineCountersLocked;
- (void)retirePointerInteractionLocked;
- (BOOL)configureDesktopUpdates:(rfbClient *)client;
- (BOOL)stopAutomaticUpdates:(rfbClient *)client;
- (void)configureFramebufferRequests:(rfbClient *)client;
- (BOOL)requestFullDesktop:(rfbClient *)client;
- (BOOL)maintainDesktopBaseline:(rfbClient *)client now:(double)now;
- (BOOL)resumeDesktopPull:(rfbClient *)client;
- (void)recordDesktopSwitchLocked:(double)now;
- (BOOL)waitingForDesktopLayout;
- (BOOL)requestPendingDesktopLayout:(rfbClient *)client;
- (void)report:(NSString *)state;
- (void)beginSocket:(int)socket addresses:(NSArray<NSString *> *)addresses port:(NSInteger)port user:(NSString *)user password:(NSString *)password;
- (BOOL)registerSocket:(int)socket;
- (void)processConnectedClient:(rfbClient *)client;
- (BOOL)sendInputEvents:(NSArray<NSDictionary *> *)events client:(rfbClient *)client inputEpoch:(NSUInteger)inputEpoch;
- (BOOL)servicePendingInput:(rfbClient *)client;
#if TARGET_OS_IOS
- (BOOL)writeKeyEvent:(uint32_t)key down:(BOOL)down client:(rfbClient *)client;
- (void)cancelComposedTextLocked;
#endif
- (void)cancelNativeGesturesLocked;
- (BOOL)releaseMagnification:(rfbClient *)client;
- (BOOL)sendMagnificationEvent:(NSDictionary *)event client:(rfbClient *)client;
- (BOOL)releaseScroll:(rfbClient *)client;
- (BOOL)sendScrollEvent:(NSDictionary *)event client:(rfbClient *)client;
- (rfbBool)displayLayout:(rfbClient *)client;
- (rfbBool)displayLayout:(rfbClient *)client encoding:(int)encoding;
- (rfbBool)appleCursor:(rfbClient *)client rect:(rfbFramebufferUpdateRectHeader *)rect;
@end

static CompanionVNCSession *Owner(rfbClient *client) {
    return (__bridge CompanionVNCSession *)rfbClientGetClientData(client, &ownerTag);
}
#if TARGET_OS_OSX || TARGET_OS_IOS
static rfbBool ServicePendingInput(rfbClient *client) { return [Owner(client) servicePendingInput:client]; }
#endif
static rfbBool Allocate(rfbClient *client) { return [Owner(client) allocate:client]; }
static void Updated(rfbClient *client, int x, int y, int w, int h) { [Owner(client) updatedX:x y:y width:w height:h]; }
static rfbCredential *Credential(rfbClient *client, int type) { return [Owner(client) credential:type]; }
static void CursorShape(rfbClient *client, int x, int y, int width, int height, int bytes) {
    CompanionVNCSession *owner = Owner(client);
    [owner cursorShape:client x:x y:y width:width height:height bytesPerPixel:bytes];
    [owner publishCursor];
}
static rfbBool CursorPosition(rfbClient *client, int x, int y) {
    CompanionVNCSession *owner = Owner(client);
    rfbBool handled = [owner cursorPosition:client x:x y:y];
    if (handled) [owner publishCursor];
    return handled;
}
static rfbBool AppleLayout(rfbClient *client, rfbFramebufferUpdateRectHeader *rect) {
#if TARGET_OS_OSX || TARGET_OS_IOS
    if (rect->encoding == 1100) {
        // Header-only Apple CursorPos, distinct from standard PointerPos (-232).
        CompanionVNCSession *owner = Owner(client);
        return [owner appleCursorPosition:client x:rect->r.x y:rect->r.y];
    }
    if (rect->encoding == 1104) {
        CompanionVNCSession *owner = Owner(client);
        rfbBool handled = [owner appleCursor:client rect:rect];
        if (handled) [owner publishCursor];
        return handled;
    }
#endif
    if (rect->encoding != 1101 && rect->encoding != 1105) return FALSE;
    return [Owner(client) displayLayout:client encoding:rect->encoding];
}
// 1101 enables the server's display-info delivery; 1105 selects the newer
// layout format. Requesting 1105 alone leaves its send-display-info gate off.
static int layoutEncodings[] = {1101,
#if TARGET_OS_OSX || TARGET_OS_IOS
    1100, 1104,
#endif
    1105, 0};
static rfbClientProtocolExtension layoutExtension = {.encodings = layoutEncodings, .handleEncoding = AppleLayout};

@implementation CompanionVNCSession
- (BOOL)desktopSizeAvailable {
    [_lock lock];
    BOOL available = _running && _established && _inputReady && _appleGestureServer && _coverageLayoutValid
        && !_inputOnly && !_paused && !_stopping && !_reviewInputSuspended && !_displayHandoffInputBlocked && !_interruptionInputSuspended
        && !_localPointerInteractionActive && !_desktopResizeAwaiting && !_desktopResizePending;
    [_lock unlock]; return available;
}
- (BOOL)requestDesktopSizePreset:(NSInteger)preset {
    CompanionVNCDesktopSize size;
    if (preset < 1 || preset > 3 || !CompanionVNCDesktopSizeForPreset((int)preset, &size) || !self.desktopSizeAvailable) return NO;
    return [self requestDesktopSizeWidth:size.width height:size.height];
}
- (BOOL)requestDesktopSizePresetForHandoff:(NSInteger)preset {
    CompanionVNCDesktopSize size;
    if (!CompanionVNCDesktopSizeForPreset((int)preset, &size) || !self.desktopFrameReady) return NO;
    return [self requestDesktopSizeWidth:size.width height:size.height handoff:YES];
}
// A desktop-size change is owned by this same authenticated socket and input epoch.
- (BOOL)requestDesktopSizeWidth:(double)width height:(double)height {
    return [self requestDesktopSizeWidth:width height:height handoff:NO];
}
- (BOOL)requestDesktopSizeWidth:(double)width height:(double)height handoff:(BOOL)handoff {
    CompanionVNCDesktopSize size;
    if (!CompanionVNCDesktopSizeForViewport(width, height, &size)) return NO;
    [_lock lock];
    BOOL permitted = _running && _established && _inputReady && _appleGestureServer && !_inputOnly
        && !_paused && !_stopping && !_reviewInputSuspended && (handoff ? _displayHandoffInputBlocked && _coverageLayoutValid : !_displayHandoffInputBlocked) && !_interruptionInputSuspended
        && !_localPointerInteractionActive && !_desktopResizeAwaiting && !_desktopResizePending;
    if (permitted) {
        _desktopResizeHandoff = handoff; _desktopResizeLateEligible = YES;
        _desktopResizeAdmitted = NSProcessInfo.processInfo.systemUptime; _desktopResizeSampleRecorded = NO;
        _desktopResizeSize = size; _desktopResizeSelection = NO; _desktopResizePending = YES; _desktopResizeOutcome = 1;
        _inputReady = NO; _releaseInputRequested = YES; _inputEpoch++; _presentationEpoch++;
        [_events removeAllObjects]; [self cancelNativeGesturesLocked]; [self retirePointerInteractionLocked];
    }
    [_lock unlock]; dispatch_semaphore_signal(_wake); return permitted;
}
- (NSDictionary *)desktopDisplayLayout {
    [_lock lock]; NSDictionary *value = _desktopCatalogue ?: @{}; [_lock unlock]; return value;
}
- (BOOL)requestDesktopDisplayID:(uint32_t)identifier {
    [_lock lock];
    NSDictionary *display = nil;
    for (NSDictionary *candidate in _desktopResizeDisplays) if ([candidate[@"id"] unsignedIntValue] == identifier) display = candidate;
    BOOL permitted = (display || (identifier == 0 && _desktopCatalogueLayout.count)) && _coverageLayoutValid && _running && _established && _inputReady && _appleGestureServer && !_inputOnly
        && !_paused && !_stopping && !_reviewInputSuspended && !_displayHandoffInputBlocked && !_interruptionInputSuspended
        && !_localPointerInteractionActive && !_desktopResizeAwaiting && !_desktopResizePending;
    if (permitted && !_desktopResizeVirtualLayout && _baselinePresented && _expectedPixels > 0 && _receivedPixels == _expectedPixels
        && _coverageLayout.width == _framebufferWidth && _coverageLayout.height == _framebufferHeight
        && CompanionVNCDesktopSelectionMatches(&_coverageLayout, &_desktopCatalogueLayout, identifier)) {
        // A server need not announce a layout that is already active. Keep its
        // proven pixels/input and avoid waiting for an acknowledgement it won't send.
        _desktopResizeOutcome = 2; _desktopResizeNoops++;
        [_lock unlock]; [self report:@"Connected"]; return YES;
    }
    if (permitted) {
        _desktopResizeAdmitted = NSProcessInfo.processInfo.systemUptime; _desktopResizeSampleRecorded = NO;
        _desktopResizeLateEligible = NO; _desktopResizeHandoff = NO;
        _desktopResizeDisplayID = identifier; _desktopResizeSelection = YES; _desktopResizePending = YES; _desktopResizeOutcome = 1;
        _desktopResizePixelWidth = identifier ? [display[@"pixelWidth"] intValue] : _desktopCatalogueLayout.width;
        _desktopResizePixelHeight = identifier ? [display[@"pixelHeight"] intValue] : _desktopCatalogueLayout.height;
        _desktopResizeLayoutSeen = NO;
        _inputReady = NO; _releaseInputRequested = YES; _inputEpoch++; _presentationEpoch++;
        [_events removeAllObjects]; [self cancelNativeGesturesLocked]; [self retirePointerInteractionLocked];
    }
    [_lock unlock]; dispatch_semaphore_signal(_wake); return permitted;
}
- (BOOL)processDesktopSizeChange:(rfbClient *)client {
    [_lock lock];
    // A UI request can arrive after this loop iteration captured its release
    // flags. Wait for the next iteration to actually release sent input first.
    if (_desktopResizePending && _releaseInputRequested) { [_lock unlock]; return YES; }
    BOOL pending = _desktopResizePending;
    BOOL allowed = _running && _established && _appleGestureServer && !_inputOnly && !_paused
        && !_stopping && !_reviewInputSuspended && (!_displayHandoffInputBlocked || _desktopResizeHandoff) && !_interruptionInputSuspended;
    if (pending) _desktopResizePending = NO;
    BOOL cancel = (_desktopResizeAwaiting && !allowed) || (pending && (!allowed || !_coverageLayoutValid));
    BOOL exactRequestedLayout = _desktopResizeLayoutSeen && _coverageLayoutValid
        && _coverageLayout.width == _desktopResizePixelWidth && _coverageLayout.height == _desktopResizePixelHeight
        && (_desktopResizeSelection
            ? CompanionVNCDesktopSelectionMatches(&_coverageLayout, &_desktopCatalogueLayout, _desktopResizeDisplayID)
            : (_coverageLayout.count == 1 && _desktopResizeVirtualLayout));
    double layoutAge = NSProcessInfo.processInfo.systemUptime - _desktopResizeStarted;
    BOOL timedOut = _desktopResizeAwaiting && (_desktopResizeSelection
        ? CompanionVNCDesktopLayoutTimedOut(layoutAge, exactRequestedLayout)
        : CompanionVNCVirtualLayoutTimedOut(layoutAge, exactRequestedLayout));
    if (cancel || timedOut) {
        if (cancel) _desktopResizeLateEligible = NO;
        BOOL differentVirtualSize = timedOut && !_desktopResizeSelection && _desktopResizeVirtualLayout && _coverageLayoutValid
            && _coverageLayout.count == 1 && _coverageLayout.width == client->width && _coverageLayout.height == client->height
            && (client->width != _desktopResizePixelWidth || client->height != _desktopResizePixelHeight);
        _desktopResizeAwaiting = NO; _desktopResizeTimedOut++; _desktopResizeOutcome = differentVirtualSize ? 4 : 3;
        [self recordDesktopSwitchLocked:NSProcessInfo.processInfo.systemUptime];
    }
    if (pending && allowed && _coverageLayoutValid) {
        _desktopResizeLayoutSeen = NO; _desktopResizeLayoutProbes = 0; _desktopResizeLayoutsAtWrite = _layoutMessages; _desktopResizeAwaiting = YES; _desktopResizeStarted = NSProcessInfo.processInfo.systemUptime; _desktopResizeLayoutMS = _desktopResizeCompleteMS = 0; _desktopResizeRequests++;
        _desktopResizeQueueMS = MAX(0, (_desktopResizeStarted - _desktopResizeAdmitted) * 1000);
        _desktopResizeRefreshRequests = _desktopResizePreLayoutRects = 0; _desktopResizePreLayoutCPU = 0;
        _desktopResizeMetricsReady = _desktopResizeProcessingClockAvailable = NO;
        _desktopResizeProcessingCPUMS = _desktopResizeCopyMS = _desktopResizeMainQueueMS = _desktopResizeFrameCallbackMS = 0;
        _desktopReadAtWrite = _desktopReadAtLayout = _desktopReadAtFrame = (CompanionVNCSwitchReadSnapshot){0};
        if (!_desktopResizeSelection) { _desktopResizePixelWidth = _desktopResizeSize.width * 2; _desktopResizePixelHeight = _desktopResizeSize.height * 2; }
    }
    BOOL send = pending && allowed && _coverageLayoutValid;
    CompanionVNCDesktopSize size = _desktopResizeSize; BOOL selection = _desktopResizeSelection; uint32_t identifier = _desktopResizeDisplayID;
    BOOL keepDelivery = send && selection && !_desktopResizeVirtualLayout && _automaticUpdatesActive;
    [_lock unlock];
    if (cancel || timedOut) {
        if (![self resetBaseline:client]) return NO;
        _desktopRefreshPending = YES;
    }
    if (send) {
        // Physical selection reports its new geometry on the existing update
        // stream. Keep that stream alive; renew only after matching metadata.
        if ((!keepDelivery && ![self stopAutomaticUpdates:client]) || ![self resetBaseline:client]) return NO;
        uint8_t packet[CompanionVNCDesktopPacketBytes]; size_t length = selection ? 8 : CompanionVNCDesktopPacketBytes;
        if (selection) CompanionVNCDesktopSelectionPacket(identifier, packet);
        else if (!CompanionVNCDesktopDisplayPacket(size, packet, sizeof(packet))) return NO;
        CompanionVNCSwitchReadSnapshot readSnapshot = [self switchReadSnapshot];
        [_lock lock]; _desktopResizeUnreadAtWrite = UnreadRFBBytes(client); _desktopResizeRectsAtWrite = _updates; _desktopResizeCPUMSAtWrite = WorkerCPUTimeMS();
        _desktopReadAtWrite = readSnapshot; [_lock unlock];
        if (!WriteToRFBServer(client, (char *)packet, (unsigned int)length)) return NO;
        if (keepDelivery) { [_lock lock]; _selectionDeliveryPreserved++; [_lock unlock]; }
        _desktopRefreshPending = YES;
    }
    return YES;
}

- (void)dealloc { free(_pixels); CompanionVNCCoverageFree(&_coverage); }
- (instancetype)init {
    if ((self = [super init])) {
        _lock = [NSLock new]; _events = [NSMutableArray new]; _heldKeys = [NSMutableSet new]; _desktopSwitchSamples = [NSMutableArray new];
#if TARGET_OS_IOS
        _composedTextReplies = [NSMutableDictionary new];
#endif
        _worker = dispatch_queue_create("media.jenny.maccompanion.rfb.owner", DISPATCH_QUEUE_SERIAL);
        _socket = -1; _wake = dispatch_semaphore_create(0);
        rfbClientLog = QuietLog; rfbClientErr = QuietLog;
        static dispatch_once_t once;
        dispatch_once(&once, ^{ rfbClientRegisterExtension(&layoutExtension); });
    }
    return self;
}
- (BOOL)running { [_lock lock]; BOOL r = _running; [_lock unlock]; return r; }
- (BOOL)established { [_lock lock]; BOOL value = _running && _established && !_stopping; [_lock unlock]; return value; }
- (BOOL)connected { [_lock lock]; BOOL ready = _running && _inputReady && !_paused && !_stopping; [_lock unlock]; return ready; }
- (BOOL)desktopFrameReady {
    [_lock lock];
    BOOL ready = !_inputOnly && CompanionVNCConnectionReady(_running, _inputReady, _inputOnly,
        _paused, _stopping, _overflow, _awaitingResumeFrame, _baselinePresented);
    [_lock unlock]; return ready;
}
- (BOOL)displayHandoffInputBlocked { [_lock lock]; BOOL value = _displayHandoffInputBlocked; [_lock unlock]; return value; }
- (void)setDisplayHandoffInputBlocked:(BOOL)value {
    [_lock lock];
    if (_displayHandoffInputBlocked != value) {
        _displayHandoffInputBlocked = value; _inputEpoch++;
        if (!value) _desktopResizeHandoff = NO;
        if (value) {
            [self retirePointerInteractionLocked]; [self cancelNativeGesturesLocked];
            _releaseInputRequested = YES; [_events removeAllObjects]; _queuedPointerMask = 0;
#if TARGET_OS_IOS
            [self cancelComposedTextLocked];
#endif
        }
    }
    [_lock unlock]; dispatch_semaphore_signal(_wake);
}
- (BOOL)inputOnly { [_lock lock]; BOOL value = _inputOnly; [_lock unlock]; return value; }
- (void)setInputOnly:(BOOL)value {
    [_lock lock];
    if (_inputOnly != value) {
        [self retirePointerInteractionLocked]; [self cancelNativeGesturesLocked]; _inputOnly = value; _modeChanged = YES; _presentationEpoch++; _inputEpoch++;
        if (_established) {
            // The owner releases the old mode before admitting input in the new one.
            _inputReady = NO; _awaitingResumeFrame = !value; _releaseInputRequested = YES;
            [_events removeAllObjects]; _queuedPointerMask = 0;
        }
#if TARGET_OS_IOS
        [self cancelComposedTextLocked];
#endif
    }
    [_lock unlock]; dispatch_semaphore_signal(_wake);
}
// Track gesture activity independently from incoming host observations.
- (BOOL)localPointerInteractionActive {
    [_lock lock]; BOOL active = _localPointerInteractionActive; [_lock unlock]; return active;
}
- (void)setLocalPointerInteractionActive:(BOOL)active {
    [_lock lock];
    active = active && _running && _inputReady && !_reviewInputSuspended && !_displayHandoffInputBlocked && !_interruptionInputSuspended && !_paused && !_stopping && !_overflow;
    if (_localPointerInteractionActive != active) { _localPointerInteractionActive = active; _pointerRevision++; }
    [_lock unlock];
}
- (void)retirePointerInteractionLocked { _localPointerInteractionActive = NO; _pointerRevision++; }

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
    BOOL ready = _running && _inputReady && _inputOnly && !_reviewInputSuspended && !_displayHandoffInputBlocked && !_interruptionInputSuspended && !_paused && !_stopping && !_overflow
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
    [_lock lock]; BOOL valid = epoch == _gestureEpoch && _inputOnly && _inputReady && !_reviewInputSuspended && !_displayHandoffInputBlocked && !_interruptionInputSuspended && !_paused && !_stopping
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
    BOOL ready = _running && _inputReady && !_reviewInputSuspended && !_displayHandoffInputBlocked && !_interruptionInputSuspended && !_paused && !_stopping && !_overflow
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
    [_lock lock]; BOOL valid = epoch == _gestureEpoch && _inputReady && !_reviewInputSuspended && !_displayHandoffInputBlocked && !_interruptionInputSuspended && !_paused && !_stopping
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
    [_lock lock]; BOOL accept = _running && _inputReady && !_reviewInputSuspended && !_displayHandoffInputBlocked && !_interruptionInputSuspended && !_paused && !_stopping && !_overflow && _events.count <= 510;
    if (accept) {
        [_events addObject:@{@"x": @(x), @"y": @(y), @"mask": @(mask), @"motion": @NO}];
        [_events addObject:@{@"x": @(x), @"y": @(y), @"mask": @0, @"motion": @NO}]; _queuedPointerMask = 0; _pointerRevision++;
    }
    [_lock unlock]; return accept;
}
- (BOOL)suspendInputForReview:(void (^)(void))completion {
    [_lock lock];
    if (_inputOnly || _displayHandoffInputBlocked || _reviewInputSuspended || _interruptionInputSuspended || !CompanionVNCConnectionReady(_running, _inputReady, _inputOnly,
        _paused, _stopping, _overflow, _awaitingResumeFrame, _baselinePresented)) {
        [_lock unlock]; return NO;
    }
    _desktopResizeLateEligible = NO;
    [self retirePointerInteractionLocked]; _reviewInputSuspended = YES; _releaseInputRequested = YES; _inputEpoch++;
#if TARGET_OS_IOS
    [self cancelComposedTextLocked];
#endif
    [self cancelNativeGesturesLocked]; [_events removeAllObjects]; _queuedPointerMask = 0;
    _reviewReleaseCompletion = [completion copy];
    [_lock unlock]; dispatch_semaphore_signal(_wake); return YES;
}
- (void)resumeInputAfterReview {
    [_lock lock];
    // Review never pauses reception. The current baseline already incorporates
    // live updates; do not discard it or request every unchanged pixel again.
    // Real resize/replacement/background gates keep their existing readiness.
    _reviewInputSuspended = NO; _reviewReleaseCompletion = nil;
    [_lock unlock]; dispatch_semaphore_signal(_wake);
}
- (void)pauseWithCompletion:(void (^)(void))completion {
    [_lock lock];
    if (!_running || !_established || _stopping || _paused) { [_lock unlock]; if (completion) completion(); return; }
    [self cancelNativeGesturesLocked];
    _desktopResizeLateEligible = NO;
    [self retirePointerInteractionLocked]; _paused = YES; _inputEpoch++; _pauses++; _inputReady = NO; _releaseInputRequested = YES; _presentationEpoch++;
    [_events removeAllObjects]; _queuedPointerMask = 0; _pauseCompletion = [completion copy];
#if TARGET_OS_IOS
    [self cancelComposedTextLocked];
#endif
    [_lock unlock]; dispatch_semaphore_signal(_wake);
}
- (void)suspendInputForInterruption {
    [_lock lock];
    if (_running && !_paused && !_stopping && !_interruptionInputSuspended) {
        _desktopResizeLateEligible = NO;
        [self retirePointerInteractionLocked]; _interruptionInputSuspended = YES; _releaseInputRequested = YES; _inputEpoch++;
#if TARGET_OS_IOS
        [self cancelComposedTextLocked];
#endif
        [self cancelNativeGesturesLocked]; [_events removeAllObjects]; _queuedPointerMask = 0;
    }
    [_lock unlock]; dispatch_semaphore_signal(_wake);
}
- (void)resumeInputAfterInterruption {
    [_lock lock];
    // An interruption never owns the independent review gate or its refresh.
    // Pending releases still precede newly queued input on the socket owner.
    _interruptionInputSuspended = NO;
    [_lock unlock]; dispatch_semaphore_signal(_wake);
}
- (void)resume {
    [_lock lock];
    if (_running && _paused && !_stopping) {
        _paused = NO; _interruptionInputSuspended = NO; _resumes++; _resumeRequested = YES; _awaitingResumeFrame = !_inputOnly; if (_inputOnly) _inputReady = YES; _presentationEpoch++;
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
    [self retirePointerInteractionLocked]; [self cancelNativeGesturesLocked]; _appleGestureServer = NO; _nativeGestureLayout = NO;
    _sentMagnification = (CompanionVNCMagnification){0}; _sentScroll = (CompanionVNCScroll){0};
    _running = YES; _established = NO; _stopping = NO; _overflow = NO; _framePending = NO; _cursorPending = NO; _pendingCursorImage = nil; _layoutPending = NO; _latestLayout = nil; _inputReady = NO; _failureStage = 0;
    _desktopCatalogue = nil; _desktopResizeDisplays = nil; memset(&_desktopCatalogueLayout, 0, sizeof(_desktopCatalogueLayout));
    _desktopResizePending = _desktopResizeAwaiting = _desktopResizeSelection = _desktopResizeVirtualLayout = _desktopResizeLayoutSeen = NO;
    _desktopResizeRequests = _desktopResizeAccepted = _desktopResizeTimedOut = _desktopResizeOutcome = _desktopResizeLayoutResizes = _desktopResizeNoops = _desktopResizeMetadataRequests = 0;
    _desktopResizeLayoutMS = _desktopResizeCompleteMS = 0;
    _desktopResizeLayoutProbes = _desktopResizeLayoutsAtWrite = _physicalLayoutAdoptions = _selectionDeliveryPreserved = 0;
    [_desktopSwitchSamples removeAllObjects]; _desktopResizeAdmitted = _desktopResizeQueueMS = 0;
    _desktopResizeSampleRecorded = YES; _routinePullPausedForSwitch = _baselineRequestSent = NO;
    _desktopResizeMetricsReady = _desktopResizeProcessingClockAvailable = _readMeasurementsInstalled = NO;
    _desktopReadAtWrite = _desktopReadAtLayout = _desktopReadAtFrame = (CompanionVNCSwitchReadSnapshot){0};
    _desktopResizeProcessingCPUMS = _desktopResizeCopyMS = _desktopResizeMainQueueMS = _desktopResizeFrameCallbackMS = 0;
    _fullRefreshRequests = _coalescedFullRefreshes = _routinePullRestarts = 0;
    _desktopResizeUnreadAtWrite = _desktopResizeRefreshRequests = _desktopResizePreLayoutRects = 0; _desktopResizePreLayoutCPU = 0;
    _desktopResizeDisplayID = 0; _desktopResizePixelWidth = _desktopResizePixelHeight = 0;
    _desktopResizeHandoff = _desktopResizeLateEligible = NO;
    _handshakeStage = 0; _layoutDiagnostics = @{}; _layoutMessages = 0; _baselinePresented = NO; _coverageLayoutValid = NO; _metadataCallback = NO;
    _paused = NO; _reviewInputSuspended = NO; _interruptionInputSuspended = NO; _reviewReleaseCompletion = nil;
    _releaseInputRequested = NO; _resumeRequested = NO; _awaitingResumeFrame = NO; _presentationEpoch++;
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
            self->_cursorPositionKnown = NO; self->_cursorPositionDirty = NO; self->_cursorDirty = YES;
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
            [self->_lock lock]; self->_appleGestureServer = appleGestureBanner; self->_established = !self->_stopping; self->_inputReady = self->_established; BOOL active = self->_established; [self->_lock unlock];
            if (active) [self report:self.inputOnly ? @"Connected" : @"Opening desktop"];
            [self processConnectedClient:client];
            (void)generation;
        }
    });
}
- (void)processConnectedClient:(rfbClient *)client {
    BOOL healthy = YES;
#if TARGET_OS_OSX || TARGET_OS_IOS
    // Preconnected SSH socket pairs otherwise retain blocking read semantics.
    // The optional hook is absent throughout the RFB authentication handshake.
    healthy = [self installDesktopReadService:client];
#endif
    while (healthy) {
        @autoreleasepool {
            [self->_lock lock]; BOOL stopping = self->_stopping || self->_overflow;
            BOOL paused = self->_paused, release = self->_releaseInputRequested, resume = self->_resumeRequested;
            BOOL inputOnly = self->_inputOnly, modeChanged = self->_modeChanged; self->_modeChanged = NO;
            self->_releaseInputRequested = NO; self->_resumeRequested = NO;
            void (^completion)(void) = release ? self->_pauseCompletion : nil;
            void (^reviewCompletion)(void) = release ? self->_reviewReleaseCompletion : nil;
            if (release) self->_reviewReleaseCompletion = nil;
            if (release) self->_pauseCompletion = nil;
            NSUInteger gestureEpoch = self->_gestureEpoch, presentationEpoch = self->_presentationEpoch, inputEpoch = self->_inputEpoch;
            NSArray *events = [self->_events copy]; [self->_events removeAllObjects];
            [self->_lock unlock];
            if (stopping) break;
            if (resume || modeChanged) self->_automaticUpdatePending = YES;
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
            }
            if (!healthy) break;
            // Release actually-sent input first, then disable server delivery
            // before acknowledging pause. A blocked subscription write cannot
            // take Stop's release budget away from held keys or buttons.
            healthy = [self processDesktopSizeChange:client]; if (!healthy) break;
            healthy = [self configureDesktopUpdates:client]; if (!healthy) break;
            healthy = [self requestPendingDesktopLayout:client]; if (!healthy) break;
            if (completion) dispatch_async(dispatch_get_main_queue(), completion);
            if (reviewCompletion) dispatch_async(dispatch_get_main_queue(), reviewCompletion);
            if (paused) {
                // No polling, decoding, or update requests while hidden. Stop/resume wake the owner.
                dispatch_semaphore_wait(self->_wake, DISPATCH_TIME_FOREVER); continue;
            }
            // LibVNCClient normally requests another frame automatically after every update.
            // On the sole socket owner, mask only update requests and use an empty rectangle
            // so even a server capability refresh cannot ask for desktop pixels in input-only.
            if (inputOnly) {
                if (resume || modeChanged) {
                    [self->_lock lock];
                    BOOL current = presentationEpoch == self->_presentationEpoch && self->_running && self->_established
                        && self->_inputOnly && !self->_paused && !self->_stopping && !self->_overflow;
                    if (current) { self->_inputReady = YES; self->_awaitingResumeFrame = NO; }
                    [self->_lock unlock];
                    if (current) [self report:@"Connected"];
                }
            }
            if (resume || modeChanged) { self->_cursorPositionKnown = NO; self->_cursorPositionDirty = NO; self->_cursorDirty = YES; }
            if (!inputOnly && (resume || modeChanged)) {
                if (![self resetBaseline:client]) { healthy = NO; break; }
                self->_desktopRefreshPending = YES;
            }
            if (!inputOnly && ![self maintainDesktopBaseline:client now:NSProcessInfo.processInfo.systemUptime]) { healthy = NO; break; }
            healthy = [self sendInputEvents:events client:client inputEpoch:inputEpoch];
            if (!healthy) break;
            // ReadFromRFBServer can read ahead into LibVNCClient's own buffer.
            // WaitForMessage only selects the socket; it cannot see those bytes.
            BOOL buffered = client->buffered > 0;
            double waitStarted = NSProcessInfo.processInfo.systemUptime;
            int ready = buffered ? 1 : WaitForMessage(client, 10000);
            if (!buffered) self->_outerSocketWaitMS += MAX(0, (NSProcessInfo.processInfo.systemUptime - waitStarted) * 1000);
            if (buffered) { [self->_lock lock]; self->_bufferedReadDispatches++; [self->_lock unlock]; }
            if (ready < 0) { healthy = NO; break; }
            if (ready > 0) {
                if (![self handleServerMessage:client]) { healthy = NO; break; }
            }
            if (self->_extensionFailed) { healthy = NO; break; }
            [self publishFrame:client];
            [self publishCursor];
        }
    }
    // A disconnect cancels queued input and releases every gesture/key/button actually sent.
    [self releaseMagnification:client]; [self releaseScroll:client];
    for (NSNumber *key in self->_heldKeys) SendKeyEvent(client, key.unsignedIntValue, FALSE);
    [self->_heldKeys removeAllObjects];
    SendPointerEvent(client, (int)self->_lastX, (int)self->_lastY, 0);
    [self stopAutomaticUpdates:client];
#if TARGET_OS_OSX || TARGET_OS_IOS
    CompanionVNCSetReadService(client, NULL);
#endif
    [self registerSocket:-1]; rfbClientCleanup(client);
    if (self->_overflow) { [self->_lock lock]; self->_failureStage = 101; [self->_lock unlock]; }
    [self finish:self->_overflow ? @"Input queue full; disconnected safely" : self->_failureStage == 103 ? @"Desktop image could not be decoded — reconnect" : self->_failureStage == 102 ? @"Desktop did not finish loading — reconnect" : healthy ? @"Disconnected" : @"Connection ended — reconnect"];

}
// Installed by the sole owner only after the existing RFB handshake succeeds.
- (BOOL)installDesktopReadService:(rfbClient *)client {
#if TARGET_OS_OSX || TARGET_OS_IOS
    if (!SetNonBlocking(client->sock)) return NO;
    _socketReadMetrics = (CompanionVNCReadMetrics){0}; _outerSocketWaitMS = 0;
    _readService = (CompanionVNCReadService){.service = ServicePendingInput, .metrics = &_socketReadMetrics};
    CompanionVNCSetReadService(client, &_readService);
    [_lock lock]; _readMeasurementsInstalled = YES; [_lock unlock];
#endif
    return YES;
}
// The raw descriptor is owner-only; the main thread uses captured snapshots.
- (CompanionVNCSwitchReadSnapshot)switchReadSnapshot {
    CompanionVNCSwitchReadSnapshot value = {0};
#if TARGET_OS_OSX || TARGET_OS_IOS
    value.socketBytes = _socketReadMetrics.socketBytes; value.deliveredBytes = _socketReadMetrics.deliveredBytes;
    value.waitMS = _socketReadMetrics.waitMS + _outerSocketWaitMS;
#endif
    return value;
}
- (BOOL)sendInputEvents:(NSArray<NSDictionary *> *)events client:(rfbClient *)client inputEpoch:(NSUInteger)inputEpoch {
    BOOL healthy = YES;
    for (NSDictionary *event in events) {
        [self->_lock lock]; BOOL currentBatch = inputEpoch == self->_inputEpoch; BOOL acceptsInput = self->_inputReady && !self->_reviewInputSuspended && !self->_displayHandoffInputBlocked && !self->_interruptionInputSuspended && !self->_paused && !self->_stopping;
#if TARGET_OS_IOS
        NSString *textID = event[@"composedTextID"];
        if (textID) acceptsInput = acceptsInput && [self composedTextReadyLocked];
        BOOL retiredText = textID && !self->_composedTextReplies[textID];
#endif
        [self->_lock unlock];
        if (!currentBatch) break; // Never revive the copied batch after a quick return.
#if TARGET_OS_IOS
        // Pause can retire a group while this copied batch is blocked
        // in a write. Resume never makes that group eligible again.
        if (retiredText) continue;
#endif
        if (!acceptsInput) {
#if TARGET_OS_IOS
            [self cancelComposedText];
#endif
            break;
        }
        if (event[@"magnifyPhase"]) {
            healthy = [self sendMagnificationEvent:event client:client];
        } else if (event[@"scrollPhase"]) {
            healthy = [self sendScrollEvent:event client:client];
        } else if (event[@"key"]) {
            uint32_t key = [event[@"key"] unsignedIntValue]; BOOL down = [event[@"down"] boolValue];
#if TARGET_OS_IOS
            healthy = [self writeKeyEvent:key down:down client:client];
#else
            healthy = SendKeyEvent(client, key, down);
#endif
            if (down) [self->_heldKeys addObject:@(key)]; else [self->_heldKeys removeObject:@(key)];
        } else {
            self->_lastX = MAX(0, MIN(client->width - 1, [event[@"x"] integerValue]));
            self->_lastY = MAX(0, MIN(client->height - 1, [event[@"y"] integerValue]));
            healthy = SendPointerEvent(client, (int)self->_lastX, (int)self->_lastY, [event[@"mask"] intValue]);
        }
        [self->_lock lock]; self->_inputs++; [self->_lock unlock];
#if TARGET_OS_IOS
        if (healthy && [event[@"composedTextEnd"] boolValue]) [self completeComposedText:textID written:YES];
#endif
        if (!healthy) break;
    }
    return healthy;
}
- (BOOL)servicePendingInput:(rfbClient *)client {
    // Invoked synchronously by the existing parser on its sole socket owner.
    // Boundaries requiring release/reconfiguration remain on the outer loop.
    [_lock lock];
    BOOL allowed = _running && _established && _inputReady && !_reviewInputSuspended && !_displayHandoffInputBlocked && !_interruptionInputSuspended
        && !_paused && !_stopping && !_overflow && !_releaseInputRequested && !_resumeRequested && !_modeChanged;
    NSArray *events = allowed && _events.count ? [_events copy] : nil;
    NSUInteger epoch = _inputEpoch, before = _inputs;
    if (events) [_events removeAllObjects];
    [_lock unlock];
    if (!events) return YES;
    BOOL healthy = [self sendInputEvents:events client:client inputEpoch:epoch];
    [_lock lock]; _readServiceEvents += _inputs - before; [_lock unlock];
    return healthy;
}
- (void)configureClient:(rfbClient *)client {
    _automaticUpdatesActive = NO; _automaticUpdatePending = YES; _desktopRefreshPending = NO;
    _automaticUpdateWidth = _automaticUpdateHeight = 0;
    _appleCursorCache = [NSMutableDictionary new]; _appleCursorOrder = [NSMutableArray new]; _appleCursorBytes = 0;
    _cursorImage = nil; _cursorHotspot = CGPointZero; _cursorPositionKnown = NO; _cursorPositionDirty = NO; _cursorDirty = YES;
    [_lock lock]; _cursorImageAvailable = NO; [_lock unlock];
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
// Never let a server capability refresh turn an input-only update into pixels.
// Automatic delivery supplements response-driven incremental requests. Paused,
// input-only and switching owners temporarily suppress the routine pull chain.
- (void)configureFramebufferRequests:(rfbClient *)client {
    [_lock lock];
    BOOL switchBaseline = _appleGestureServer && _automaticUpdatesActive && (_desktopResizeAwaiting || _routinePullPausedForSwitch) && !_baselinePresented;
    if (switchBaseline) _routinePullPausedForSwitch = YES;
    BOOL suppress = _inputOnly || _paused || _desktopResizePending || (_desktopResizeAwaiting && !_desktopResizeLayoutSeen) || switchBaseline;
    [_lock unlock];
    unsigned char *requests = &client->supportedMessages.client2server[rfbFramebufferUpdateRequest / 8];
    unsigned char bit = 1 << (rfbFramebufferUpdateRequest % 8);
    if (suppress) {
        *requests &= ~bit;
        rfbRectangle empty = {0, 0, 0, 0}; rfbClientSetUpdateRect(client, &empty);
    } else { *requests |= bit; rfbClientSetUpdateRect(client, NULL); }
}
- (BOOL)maintainDesktopBaseline:(rfbClient *)client now:(double)now {
    if ([self waitingForDesktopLayout]) return YES;
    [_lock lock]; BOOL allowed = _running && _established && !_inputOnly && !_paused && !_stopping;
    BOOL presented = _baselinePresented; [_lock unlock];
    if (!allowed) return YES;
    if (!CompanionVNCCoverageReady(&_coverage) && now - _baselineStarted >= 8) {
        [_lock lock]; _failureStage = 102; [_lock unlock]; return NO;
    }
    if (_desktopRefreshPending) {
        // A subscription rearm does not need another full copy of the same
        // incomplete baseline. Real reset/resize clears _baselineRequestSent.
        if (_baselineRequestSent && !presented) { [_lock lock]; _coalescedFullRefreshes++; [_lock unlock]; }
        else { if (![self requestFullDesktop:client]) return NO; _lastFullRefresh = now; }
        _desktopRefreshPending = NO;
    }
    if (!CompanionVNCCoverageReady(&_coverage)) {
        int action = CompanionVNCBaselineRefreshAction(now - _baselineStarted, now - _lastFullRefresh, now - _baselineLastProgress, (unsigned)_fullRefreshRetries);
        if (action == CompanionVNCBaselineExpired) { [_lock lock]; _failureStage = 102; [_lock unlock]; return NO; }
        if (action == CompanionVNCBaselineRetry) {
            if (![self requestFullDesktop:client]) return NO;
            [_lock lock]; _fullRefreshRetries++; [_lock unlock]; _lastFullRefresh = now;
        }
    }
    return [self resumeDesktopPull:client];
}
- (BOOL)resumeDesktopPull:(rfbClient *)client {
    [_lock lock];
    BOOL send = _routinePullPausedForSwitch && _running && _established && _inputReady && _baselinePresented
        && !_desktopResizeAwaiting && !_desktopResizePending && !_paused && !_inputOnly && !_stopping && !_overflow;
    if (send) _routinePullPausedForSwitch = NO;
    [_lock unlock];
    if (!send) return YES;
    [self configureFramebufferRequests:client];
    BOOL sent = SendIncrementalFramebufferUpdateRequest(client);
    if (sent) { [_lock lock]; _routinePullRestarts++; [_lock unlock]; }
    return sent;
}
- (void)recordDesktopSwitchLocked:(double)now {
    if (_desktopResizeSampleRecorded || !_desktopResizeAdmitted || _desktopResizeStarted < _desktopResizeAdmitted) return;
    _desktopResizeSampleRecorded = YES;
    double complete = _desktopResizeCompleteMS > 0 ? _desktopResizeCompleteMS : MAX(0, (now - _desktopResizeStarted) * 1000);
    BOOL measured = _desktopResizeMetricsReady;
    NSDictionary *sample = @{@"sequence": @(_desktopResizeRequests), @"displayID": @(_desktopResizeSelection ? _desktopResizeDisplayID : 0),
        @"width": @(_desktopResizePixelWidth), @"height": @(_desktopResizePixelHeight), @"outcome": @(_desktopResizeOutcome),
        @"ownerQueueMS": @(_desktopResizeQueueMS), @"layoutMS": @(_desktopResizeLayoutMS), @"completeMS": @(complete),
        @"totalMS": @(_desktopResizeQueueMS + complete), @"freshImageMS": @(_desktopResizeLayoutSeen ? MAX(0, complete - _desktopResizeLayoutMS) : 0),
        @"metadataRequests": @(_desktopResizeLayoutProbes), @"layoutMessages": @(_layoutMessages - _desktopResizeLayoutsAtWrite),
        @"lastLayoutParsed": @([_layoutDiagnostics[@"parsed"] boolValue]), @"lastLayoutCurrentID": _layoutDiagnostics[@"currentDisplayID"] ?: @0,
        @"unreadBytesAtWrite": @(_desktopResizeUnreadAtWrite), @"pixelRectsBeforeLayout": @(_desktopResizePreLayoutRects),
        @"cpuBeforeLayoutMS": @(_desktopResizePreLayoutCPU), @"fullRefreshRequests": @(_desktopResizeRefreshRequests), @"retries": @(_fullRefreshRetries),
        @"readMeasurementsAvailable": @(measured), @"processingClockAvailable": @(_desktopResizeProcessingClockAvailable),
        @"rfbBytes": @(measured ? ReadCounterDelta(_desktopReadAtFrame.deliveredBytes, _desktopReadAtWrite.deliveredBytes) : 0),
        @"freshRfbBytes": @(measured ? ReadCounterDelta(_desktopReadAtFrame.deliveredBytes, _desktopReadAtLayout.deliveredBytes) : 0),
        @"socketReadBytes": @(measured ? ReadCounterDelta(_desktopReadAtFrame.socketBytes, _desktopReadAtWrite.socketBytes) : 0),
        @"socketWaitMS": @(measured ? MAX(0, _desktopReadAtFrame.waitMS - _desktopReadAtWrite.waitMS) : 0),
        @"freshSocketWaitMS": @(measured ? MAX(0, _desktopReadAtFrame.waitMS - _desktopReadAtLayout.waitMS) : 0),
        @"processingCPUMS": @(_desktopResizeProcessingCPUMS),
        @"freshProcessingCPUMS": @(_desktopResizeProcessingClockAvailable ? MAX(0, _desktopResizeProcessingCPUMS - _desktopResizePreLayoutCPU) : 0),
        @"frameCopyMS": @(_desktopResizeCopyMS), @"presentationQueueMS": @(_desktopResizeMainQueueMS), @"frameCallbackMS": @(_desktopResizeFrameCallbackMS)};
    while (_desktopSwitchSamples.count >= 12) [_desktopSwitchSamples removeObjectAtIndex:0];
    [_desktopSwitchSamples addObject:sample];
}
- (BOOL)requestPendingDesktopLayout:(rfbClient *)client {
    [_lock lock];
    double elapsed = NSProcessInfo.processInfo.systemUptime - _desktopResizeStarted;
    double nextAge = _desktopResizeLayoutProbes == 0 ? 0 : _desktopResizeLayoutProbes == 1 ? 0.5 : 1.5;
    BOOL send = _running && _established && !_paused && !_stopping && !_inputOnly
        && !_reviewInputSuspended && (!_displayHandoffInputBlocked || _desktopResizeHandoff) && !_interruptionInputSuspended
        && _desktopResizeAwaiting && !_desktopResizeLayoutSeen && _desktopResizeLayoutProbes < 3
        && isfinite(elapsed) && elapsed >= nextAge && elapsed < (_desktopResizeSelection ? 6 : 20);
    if (send) _desktopResizeLayoutProbes++;
    [_lock unlock];
    if (!send) return YES;
    // A host may consume the first tiny request before its asynchronous handoff.
    // Retry at bounded ages without selecting again or requesting old bulk pixels.
    client->supportedMessages.client2server[rfbFramebufferUpdateRequest / 8] |= 1 << (rfbFramebufferUpdateRequest % 8);
    BOOL sent = SendFramebufferUpdateRequest(client, 0, 0, 1, 1, FALSE);
    [self configureFramebufferRequests:client];
    if (sent) { [_lock lock]; _desktopResizeMetadataRequests++; [_lock unlock]; }
    return sent;
}
- (BOOL)waitingForDesktopLayout {
    [_lock lock]; BOOL waiting = _desktopResizePending || (_desktopResizeAwaiting && !_desktopResizeLayoutSeen); [_lock unlock]; return waiting;
}
- (BOOL)requestFullDesktop:(rfbClient *)client {
    [_lock lock]; BOOL permitted = _running && !_paused && !_inputOnly && !_stopping
        && !_desktopResizePending && (!_desktopResizeAwaiting || _desktopResizeLayoutSeen); [_lock unlock];
    if (!permitted) return YES;
    // The bit mask suppresses only the library's routine requests. An explicit
    // baseline refresh must reach the wire even in automatic-update mode.
    client->supportedMessages.client2server[rfbFramebufferUpdateRequest / 8] |= 1 << (rfbFramebufferUpdateRequest % 8);
    BOOL sent = SendFramebufferUpdateRequest(client, 0, 0, client->width, client->height, FALSE);
    [self configureFramebufferRequests:client];
    if (sent) {
        _baselineRequestSent = YES;
        [_lock lock]; _fullRefreshRequests++; if (_desktopResizeAwaiting) _desktopResizeRefreshRequests++; [_lock unlock];
    }
    return sent;
}
- (BOOL)stopAutomaticUpdates:(rfbClient *)client {
    if (!_automaticUpdatesActive) return YES;
    uint8_t packet[16];
    BOOL sent = CompanionVNCAppleUpdatePacket(_automaticUpdateWidth, _automaticUpdateHeight, false, packet)
        && WriteToRFBServer(client, (char *)packet, sizeof(packet));
    [_lock lock]; _automaticUpdatesActive = NO; if (sent) _automaticUpdateStops++; [_lock unlock];
    _automaticUpdatePending = YES;
    return sent;
}
- (BOOL)configureDesktopUpdates:(rfbClient *)client {
    [_lock lock];
    BOOL activeOwner = _running && _established && !_paused && !_inputOnly && !_stopping && _appleGestureServer;
    BOOL waitingPhysicalSelection = activeOwner && !_desktopResizePending && _desktopResizeAwaiting
        && _desktopResizeSelection && !_desktopResizeVirtualLayout && !_desktopResizeLayoutSeen;
    BOOL keepDelivery = waitingPhysicalSelection && _automaticUpdatesActive && _coverageLayoutValid
        && _coverageLayout.width == client->width && _coverageLayout.height == client->height;
    BOOL permitted = activeOwner && !_desktopResizePending && (!_desktopResizeAwaiting || _desktopResizeLayoutSeen);
    [_lock unlock];
#if !(TARGET_OS_OSX || TARGET_OS_IOS)
    // Only clients advertising and rendering Apple cached cursors opt in.
    permitted = keepDelivery = NO;
#endif
    if (keepDelivery) {
        // Do not silence pending layout metadata, or arm a guessed/new rectangle.
        // The routine request chain remains masked and old pixels stay unusable.
        [self configureFramebufferRequests:client]; return YES;
    }
    BOOL eligible = permitted && _coverageLayoutValid && _coverageLayout.width == client->width
        && _coverageLayout.height == client->height;
    if (!eligible) {
        if (![self stopAutomaticUpdates:client]) return NO;
    } else if (!_automaticUpdatesActive || _automaticUpdatePending
               || _automaticUpdateWidth != client->width || _automaticUpdateHeight != client->height) {
        uint8_t packet[16];
        if (!CompanionVNCAppleUpdatePacket(client->width, client->height, true, packet)
            || !WriteToRFBServer(client, (char *)packet, sizeof(packet))) return NO;
        _automaticUpdateWidth = client->width; _automaticUpdateHeight = client->height;
        _automaticUpdatePending = NO; _desktopRefreshPending = YES;
        [_lock lock]; _automaticUpdatesActive = YES; _automaticUpdateStarts++; [_lock unlock];
    }
    [self configureFramebufferRequests:client]; return YES;
}
- (void)finish:(NSString *)state {
    [_lock lock];
    if (_desktopResizeAwaiting || _desktopResizePending) { _desktopResizeOutcome = 3; _desktopResizeAwaiting = NO; _desktopResizePending = NO; [self recordDesktopSwitchLocked:NSProcessInfo.processInfo.systemUptime]; }
    [_lock unlock];
    [self registerSocket:-1];
    free(_pixels); _pixels = NULL; CompanionVNCCoverageFree(&_coverage); _username = nil; _password = nil;
    _cursorImage = nil; _cursorPositionKnown = NO; _cursorPositionDirty = NO; _cursorDirty = NO;
    [_appleCursorCache removeAllObjects]; [_appleCursorOrder removeAllObjects]; _appleCursorBytes = 0;
    [_lock lock]; _cursorImageAvailable = NO; [self retirePointerInteractionLocked]; [self cancelNativeGesturesLocked]; _appleGestureServer = NO; _nativeGestureLayout = NO; _running = NO; _established = NO; _inputReady = NO; _reviewInputSuspended = NO; _interruptionInputSuspended = NO; _reviewReleaseCompletion = nil; [_events removeAllObjects];
#if TARGET_OS_IOS
    [self cancelComposedTextLocked];
#endif
    [_lock unlock];
    [self report:state];
}
- (rfbCredential *)credential:(int)type {
    if (type != rfbCredentialTypeUser) return NULL;
    protocolStage = 3;
    [_lock lock]; _handshakeStage = 3; _credentialRequests++; [_lock unlock];

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
    _automaticUpdatePending = YES; if (_established && !_inputOnly) _desktopRefreshPending = YES;
    _nativeGestureLayout = CompanionVNCNativeGesturesSupported(YES, _coverageLayoutValid, client->width, client->height, _coverageLayout.width, _coverageLayout.height);
    [_lock unlock];
    size_t bytes;
    if (!CompanionVNCFramebufferByteCount(client->width, client->height, &bytes)) { protocolFailure = 9; return FALSE; }
    uint8_t *pixels = calloc(1, (size_t)bytes);
    if (!pixels) return FALSE;
    if (![self resetBaseline:client]) { free(pixels); return FALSE; }
    free(_pixels); _pixels = pixels; client->frameBuffer = pixels;
    protocolStage = 5;
    [_lock lock]; _handshakeStage = 5; _resizes++; [_lock unlock]; _dirty = NO;
    _cursorPositionKnown = NO; _cursorPositionDirty = NO; _cursorDirty = YES;
    return TRUE;
}
- (BOOL)resetBaseline:(rfbClient *)client {
    // Retire input and presentation before changing coverage on the socket owner.
    [_lock lock]; [self retirePointerInteractionLocked]; _fullRefreshRetries = 0; _baselinePresented = NO; _presentationEpoch++;
    if (_established && !_inputOnly) {
        _releaseInputRequested = _releaseInputRequested || _inputReady;
        _inputReady = NO; _awaitingResumeFrame = YES;
#if TARGET_OS_IOS
        [self cancelComposedTextLocked];
#endif
        [self cancelNativeGesturesLocked]; [_events removeAllObjects]; _queuedPointerMask = 0;
    }
    [_lock unlock];
    if (!CompanionVNCCoverageReset(&_coverage, client->width, client->height)) return NO;
    _baselineStarted = _lastFullRefresh = _baselineLastProgress = NSProcessInfo.processInfo.systemUptime;
    _baselineRequestSent = NO;
    _dirty = NO; _cursorPositionKnown = NO; _cursorPositionDirty = NO; _cursorDirty = YES;
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
    size_t before = _coverage.received;
    if (!CompanionVNCCoverageReady(&_coverage)) CompanionVNCCoverageRect(&_coverage, x, y, width, height, false);
    if (_coverage.received > before) _baselineLastProgress = NSProcessInfo.processInfo.systemUptime;
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
    BOOL selectedCatalogue = NO;
    if (!parsed && encoding == 1105) {
        [_lock lock];
        if (_desktopResizeSelection && !_desktopResizePending && _desktopResizeDisplayID && _desktopResizeRequests > 0) {
            selectedCatalogue = CompanionVNCDecodeSelectedDisplayLayout(body.bytes, length, _desktopResizeDisplayID, &_desktopCatalogueLayout, &decoded);
            parsed = selectedCatalogue;
        }
        [_lock unlock];
    }
    BOOL probeNewVirtual = parsed && length >= 18 && (CompanionVNCBE32((const uint8_t *)body.bytes + 14) & 1) != 0;
    [_lock lock];
    BOOL previousPhysicalCatalogue = _coverageLayoutValid && _desktopCatalogueLayout.count > 0 && !_desktopResizeVirtualLayout;
    BOOL physicalCatalogueRecovery = parsed && !selectedCatalogue && previousPhysicalCatalogue && !probeNewVirtual
        && CompanionVNCBE32((const uint8_t *)body.bytes + 10) == UINT32_MAX
        && _running && _established && _appleGestureServer && !_inputOnly && !_paused && !_stopping
        && !_desktopResizePending && !_desktopResizeAwaiting && (!_desktopResizeSelection || _desktopResizeDisplayID == 0);
    BOOL probeVirtualChanged = encoding == 1105 && _desktopResizeRequests > 0 && _desktopResizeVirtualLayout != probeNewVirtual;
    if (encoding == 1105) _desktopResizeVirtualLayout = probeNewVirtual;
    [_lock unlock];
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
        geometry[@"currentDisplayID"] = @(CompanionVNCBE32(p + 10));
        geometry[@"normalizedSelectedStream"] = @(selectedCatalogue);
        NSMutableArray *records = [NSMutableArray new];
        for (NSUInteger i = 0; i < MIN((length - 20) / 56, 32); i++) {
            const uint8_t *r = p + 20 + i * 56;
            [records addObject:@{@"id": @(CompanionVNCBE32(r + 16)), @"rect20": @[@(CompanionVNCBE16(r + 20)), @(CompanionVNCBE16(r + 22)), @(CompanionVNCBE16(r + 24)), @(CompanionVNCBE16(r + 26))],
                @"rect28": @[@(CompanionVNCBE16(r + 28)), @(CompanionVNCBE16(r + 30)), @(CompanionVNCBE16(r + 32)), @(CompanionVNCBE16(r + 34))]}];
        }
        geometry[@"records"] = records;
    }
    [_lock lock]; _layoutMessages++; _layoutDiagnostics = geometry; [_lock unlock];
    if (encoding == 1101) { [self report:@"Connected"]; return TRUE; }
    // A same-geometry layout can signal an agent handoff that dropped arming.
    _automaticUpdatePending = YES;
    BOOL changed = _coverageLayoutValid && (!parsed || _coverageLayout.width != decoded.width || _coverageLayout.height != decoded.height || _coverageLayout.count != decoded.count || memcmp(_coverageLayout.displays, decoded.displays, sizeof(CompanionVNCDisplay) * decoded.count) != 0);
    changed = changed || probeVirtualChanged;
    _coverageLayoutValid = parsed; if (parsed) _coverageLayout = decoded;
    // A display-info response can announce a new canvas without DesktopSize.
    // Explicit changes and validated physical All Displays recovery stay on this socket owner.
    [_lock lock];
    BOOL lateResultAllowed = _desktopResizeSelection || (_desktopResizeLateEligible && NSProcessInfo.processInfo.systemUptime - _desktopResizeStarted <= 30
        && !_paused && !_stopping && !_reviewInputSuspended && !_interruptionInputSuspended);
    BOOL probeLayoutCandidate = _desktopResizeRequests > 0 && (_desktopResizeAwaiting || (lateResultAllowed && (_desktopResizeOutcome == 3 || _desktopResizeOutcome == 4)))
        && parsed
        && (_desktopResizeSelection ? CompanionVNCDesktopSelectionMatches(&decoded, &_desktopCatalogueLayout, _desktopResizeDisplayID)
            : (decoded.count == 1 && _desktopResizeVirtualLayout))
        && (_desktopResizeSelection || (uint64_t)decoded.width * decoded.height <= 6000000);
    BOOL lateVirtual = probeLayoutCandidate && !_desktopResizeSelection && !_desktopResizeAwaiting
        && (_desktopResizeOutcome == 3 || _desktopResizeOutcome == 4) && _desktopResizeLateEligible && !_paused && !_stopping && !_reviewInputSuspended && !_interruptionInputSuspended
        && NSProcessInfo.processInfo.systemUptime - _desktopResizeStarted <= 30
        && decoded.width == _desktopResizePixelWidth && decoded.height == _desktopResizePixelHeight;
    if (lateVirtual) {
        _desktopResizeAwaiting = YES; _desktopResizeOutcome = 1; _desktopResizeSampleRecorded = NO;
    }
    BOOL firstMatchingLayout = probeLayoutCandidate && !_desktopResizeLayoutSeen;
    if (probeLayoutCandidate) {
        _desktopResizeLayoutSeen = YES;
        if (firstMatchingLayout) {
            _desktopResizeLayoutMS = (NSProcessInfo.processInfo.systemUptime - _desktopResizeStarted) * 1000;
            _desktopReadAtLayout = [self switchReadSnapshot];
            _desktopResizePreLayoutRects = _updates - _desktopResizeRectsAtWrite;
            double cpu = WorkerCPUTimeMS();
            _desktopResizePreLayoutCPU = cpu >= 0 && _desktopResizeCPUMSAtWrite >= 0 ? MAX(0, cpu - _desktopResizeCPUMSAtWrite) : 0;
        }
    }
    [_lock unlock];
    BOOL probeAdoptedLayout = NO;
    if ((probeLayoutCandidate || physicalCatalogueRecovery) && (client->width != decoded.width || client->height != decoded.height)) {
        size_t bytes;
        if (!CompanionVNCFramebufferByteCount(decoded.width, decoded.height, &bytes)
            || ![self stopAutomaticUpdates:client]) { _extensionFailed = YES; return TRUE; }
        client->width = decoded.width; client->height = decoded.height;
        if (![self allocate:client]) { _extensionFailed = YES; return TRUE; }
        rfbClientSetUpdateRect(client, NULL); _desktopRefreshPending = YES; probeAdoptedLayout = YES;
        [_lock lock]; if (probeLayoutCandidate) _desktopResizeLayoutResizes++; else _physicalLayoutAdoptions++; [_lock unlock];
    }
    [_lock lock];
    BOOL gestureLayout = CompanionVNCNativeGesturesSupported(YES, parsed, client->width, client->height, parsed ? decoded.width : 0, parsed ? decoded.height : 0);
    if (changed || _nativeGestureLayout != gestureLayout) [self cancelNativeGesturesLocked];
    _nativeGestureLayout = gestureLayout; [_lock unlock];
    if ((changed || firstMatchingLayout) && _coverage.seen && !probeAdoptedLayout) {
        // Hot-plug/rearrangement also retires the old baseline without blanking its image.
        if (![self resetBaseline:client]) _extensionFailed = YES;
        else _desktopRefreshPending = YES;
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
    if (selectedCatalogue) {
        scale = 2;
        for (NSUInteger i = 0; i < CompanionVNCBE16(p + 18); i++) {
            const uint8_t *record = p + 20 + i * 56;
            if (CompanionVNCBE32(record + 16) != decoded.displays[0].id) continue;
            int32_t logicalWidth = (int16_t)CompanionVNCBE16(record + 26) - (int16_t)CompanionVNCBE16(record + 22);
            CGFloat candidate = logicalWidth > 0 ? (CGFloat)decoded.width / logicalWidth : 0;
            if (isfinite(candidate) && candidate >= 1 && candidate <= 4) scale = candidate;
        }
    }
    NSDictionary *layout = @{@"aspectRatio": @(aspect), @"backingScale": @(scale), @"views": views, @"virtual": @(_desktopResizeVirtualLayout)};
    [self report:@"Connected"];
    [_lock lock]; NSInteger generation = _generation; NSUInteger epoch = _presentationEpoch; _latestLayout = layout;
    // A selected stream has its own origin/geometry; keep the full catalogue for switching.
    if (parsed && (!_desktopCatalogue || (!_desktopResizeAwaiting && !_desktopResizePending
        && (!_desktopResizeSelection || _desktopResizeDisplayID == 0)))) {
        _desktopCatalogueLayout = decoded; _desktopCatalogue = layout; _desktopResizeDisplays = [views copy];
    }
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
    [_lock lock]; _cursorImageAvailable = NO; _cursorShapes++; _standardCursorReports++; [_lock unlock];
    if (width <= 0 || height <= 0 || width > 256 || height > 256 || bytes != 4) return;
    NSUInteger count = (NSUInteger)width * height;
    NSMutableData *rgba = [NSMutableData dataWithLength:count * 4];
    if (!CompanionVNCCursorRGBA(width, height, bytes, x, y, client->rcSource, count * 4,
        client->rcMask, count, rgba.mutableBytes, rgba.length)) return;
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)rgba);
    CGColorSpaceRef colors = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate(width, height, 8, 32, width * 4, colors,
        (CGBitmapInfo)kCGBitmapByteOrder32Big | (CGBitmapInfo)kCGImageAlphaPremultipliedLast, provider, NULL, NO, kCGRenderingIntentDefault);
    if (image) { [_lock lock]; _cursorImageAvailable = YES; _visibleCursorImages++; [_lock unlock]; _cursorImage = PlatformImage(image); _cursorHotspot = CGPointMake(x, y); CGImageRelease(image); }
    CGColorSpaceRelease(colors); CGDataProviderRelease(provider);
}
- (rfbBool)appleCursor:(rfbClient *)client rect:(rfbFramebufferUpdateRectHeader *)rect {
    _metadataCallback = YES;
    uint8_t header[8];
    if (!ReadFromRFBServer(client, (char *)header, sizeof(header))) { _extensionFailed = YES; return FALSE; }
    uint32_t identifier = ((uint32_t)header[0] << 24) | ((uint32_t)header[1] << 16) | ((uint32_t)header[2] << 8) | header[3];
    uint32_t length = ((uint32_t)header[4] << 24) | ((uint32_t)header[5] << 16) | ((uint32_t)header[6] << 8) | header[7];
    NSNumber *key = @(identifier);
    if (length) {
        int width = rect->r.w, height = rect->r.h, x = rect->r.x, y = rect->r.y;
        if (length > 512 * 1024 || width < 1 || height < 1 || width > 256 || height > 256 || x >= width || y >= height) {
            _extensionFailed = YES; return FALSE;
        }
        NSMutableData *compressed = [NSMutableData dataWithLength:length];
        NSMutableData *rgba = [NSMutableData dataWithLength:(NSUInteger)width * height * 4];
        if (!ReadFromRFBServer(client, compressed.mutableBytes, length)
            || !CompanionVNCAppleCursorRGBA(width, height, x, y, compressed.bytes, length, rgba.mutableBytes, rgba.length)) {
            _extensionFailed = YES; return FALSE;
        }
        CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)rgba);
        CGColorSpaceRef colors = CGColorSpaceCreateDeviceRGB();
        CGImageRef cg = CGImageCreate(width, height, 8, 32, width * 4, colors,
            (CGBitmapInfo)kCGBitmapByteOrder32Big | (CGBitmapInfo)kCGImageAlphaPremultipliedLast, provider, NULL, NO, kCGRenderingIntentDefault);
        CompanionVNCImage *image = cg ? PlatformImage(cg) : nil;
        if (cg) CGImageRelease(cg); CGColorSpaceRelease(colors); CGDataProviderRelease(provider);
        if (!image) { _extensionFailed = YES; return FALSE; }
        _appleCursorBytes -= [_appleCursorCache[key][@"bytes"] unsignedIntegerValue];
        [_appleCursorOrder removeObject:key];
        while (_appleCursorOrder.count && (_appleCursorOrder.count >= 64 || _appleCursorBytes + rgba.length > 4 * 1024 * 1024)) {
            NSNumber *oldest = _appleCursorOrder.firstObject;
            _appleCursorBytes -= [_appleCursorCache[oldest][@"bytes"] unsignedIntegerValue];
            [_appleCursorCache removeObjectForKey:oldest]; [_appleCursorOrder removeObjectAtIndex:0];
        }
        _appleCursorCache[key] = @{@"image": image, @"x": @(x), @"y": @(y), @"bytes": @(rgba.length)};
        _appleCursorBytes += rgba.length;
        [_lock lock]; _appleCursorStores++; _visibleCursorImages++; [_lock unlock];
    } else { [_lock lock]; _appleCursorSelections++; [_lock unlock]; }
    NSDictionary *selected = _appleCursorCache[key];
    _cursorImage = selected[@"image"];
    _cursorHotspot = selected ? CGPointMake([selected[@"x"] doubleValue], [selected[@"y"] doubleValue]) : CGPointZero;
    if (selected) { [_appleCursorOrder removeObject:key]; [_appleCursorOrder addObject:key]; }
    else { [_lock lock]; _appleCursorMisses++; [_lock unlock]; }
    _cursorDirty = YES;
    [_lock lock]; _cursorImageAvailable = selected != nil; _cursorShapes++; [_lock unlock];
    return TRUE;
}
- (rfbBool)appleCursorPosition:(rfbClient *)client x:(int)x y:(int)y {
    _metadataCallback = YES;
    rfbBool handled = [self cursorPosition:client x:x y:y];
    if (handled) [self publishCursor];
    return handled;
}
- (BOOL)handleServerMessage:(rfbClient *)client {
    // A partial desktop message may finish after newer local movement. All of
    // its position rectangles retain the revision from before that read began.
    [_lock lock]; _serverMessagePointerRevision = _pointerRevision; _readingServerMessage = YES;
    BOOL interactive = _baselinePresented; NSUInteger updates = _updates, cursors = _cursorPositions + _cursorShapes; [_lock unlock];
    NSUInteger before = UnreadRFBBytes(client);
    double cpuStarted = WorkerCPUTimeMS(), started = NSProcessInfo.processInfo.systemUptime;
    BOOL handled = HandleRFBServerMessage(client);
    double elapsedMS = (NSProcessInfo.processInfo.systemUptime - started) * 1000, cpuEnded = WorkerCPUTimeMS();
    double cpuMS = cpuStarted >= 0 && cpuEnded >= cpuStarted ? cpuEnded - cpuStarted : 0;
    NSUInteger after = UnreadRFBBytes(client);
    [_lock lock]; _readingServerMessage = NO; _serverMessages++; _serverMessageTotalMS += elapsedMS;
    _serverMessageMaxMS = MAX(_serverMessageMaxMS, elapsedMS);
    if (cpuStarted >= 0 && cpuEnded >= cpuStarted) { _workerCPUSamples++; _workerCPUTotalMS += cpuMS; _workerCPUMaxMS = MAX(_workerCPUMaxMS, cpuMS); }
    _unreadBytesLatest = after; _unreadBytesMax = MAX(_unreadBytesMax, MAX(before, after));
    if (interactive) {
        _interactiveMessages++; _interactiveWallMS += elapsedMS; _interactiveCPUMS += cpuMS;
        _interactiveMessageMaxMS = MAX(_interactiveMessageMaxMS, elapsedMS);
        _interactiveUnreadBytesMax = MAX(_interactiveUnreadBytesMax, MAX(before, after));
    }
    if (_updates != updates) { _pixelMessages++; _pixelMessageMaxMS = MAX(_pixelMessageMaxMS, elapsedMS); }
    else if (_cursorPositions + _cursorShapes != cursors) { _cursorOnlyMessages++; _cursorOnlyMessageMaxMS = MAX(_cursorOnlyMessageMaxMS, elapsedMS); }
    [_lock unlock]; return handled;
}
// Caller owns _lock. Fixed aggregates only; no packet, endpoint or input content.
- (NSDictionary *)pipelineCountersLocked {
    return @{@"bufferedReadDispatches": @(_bufferedReadDispatches), @"inputEventsDuringRead": @(_readServiceEvents), @"messageReadActive": @(_readingServerMessage), @"workerCPUSamples": @(_workerCPUSamples), @"workerCPUTotalMS": @(_workerCPUTotalMS), @"workerCPUMaxMS": @(_workerCPUMaxMS),
        @"interactiveMessages": @(_interactiveMessages), @"interactiveWallMS": @(_interactiveWallMS), @"interactiveCPUMS": @(_interactiveCPUMS),
        @"interactiveMessageMaxMS": @(_interactiveMessageMaxMS), @"unreadBytesLatest": @(_unreadBytesLatest), @"unreadBytesMax": @(_unreadBytesMax),
        @"interactiveUnreadBytesMax": @(_interactiveUnreadBytesMax), @"pixelMessages": @(_pixelMessages), @"pixelMessageMaxMS": @(_pixelMessageMaxMS),
        @"cursorOnlyMessages": @(_cursorOnlyMessages), @"cursorOnlyMessageMaxMS": @(_cursorOnlyMessageMaxMS),
        @"frameCopyTotalMS": @(_frameCopyTotalMS), @"frameCopyMaxMS": @(_frameCopyMaxMS), @"frameMainQueueMaxMS": @(_frameMainQueueMaxMS),
        @"frameCallbackMaxMS": @(_frameCallbackMaxMS), @"localPointerInteractionActive": @(_localPointerInteractionActive)};
}
- (rfbBool)cursorPosition:(rfbClient *)client x:(int)x y:(int)y {
    _cursorPositionKnown = x >= 0 && y >= 0 && x < client->width && y < client->height;
    _cursorPosition = CGPointMake(x, y); _cursorPositionDirty = YES; _cursorDirty = YES;
    [_lock lock]; _cursorPositions++;
    _cursorPositionRevision = _readingServerMessage ? _serverMessagePointerRevision : _pointerRevision;
    [_lock unlock]; return TRUE;
}
- (void)publishCursor {
    if (!_cursorDirty) return;
    [_lock lock];
    if (_stopping || _paused || _resumeRequested || _modeChanged) { [_lock unlock]; return; }
    // Images can change without a position report. Keep an undelivered fresh
    // position while coalescing shapes, but never replay a consumed coordinate.
    if (!_cursorPending || _pendingCursorEpoch != _presentationEpoch) _pendingCursorPositionKnown = NO;
    _pendingCursorImage = _cursorImage; _pendingCursorHotspot = _cursorHotspot;
    if (_cursorPositionDirty) {
        _pendingCursorPosition = _cursorPosition; _pendingCursorPositionKnown = _cursorPositionKnown;
        _pendingCursorPositionRevision = _cursorPositionRevision; _cursorPositionDirty = NO;
    }
    _pendingCursorEpoch = _presentationEpoch; _pendingCursorReceivedAt = NSProcessInfo.processInfo.systemUptime; _cursorDirty = NO;
    if (_cursorPending) { [_lock unlock]; return; }
    _cursorPending = YES; NSInteger generation = _generation; [_lock unlock];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_lock lock];
        if (generation != self->_generation) { [self->_lock unlock]; return; }
        BOOL valid = self->_pendingCursorEpoch == self->_presentationEpoch && self->_running
            && !self->_stopping && !self->_paused && !self->_resumeRequested && !self->_modeChanged;
        CompanionVNCImage *image = self->_pendingCursorImage;
        CGPoint hotspot = self->_pendingCursorHotspot, position = self->_pendingCursorPosition;
        BOOL fresh = self->_pendingCursorPositionKnown;
        BOOL known = fresh && !self->_reviewInputSuspended && !self->_interruptionInputSuspended;
        // A read begun before newer local input cannot reconcile the pointer.
        // This rejects a local race; it does not establish host-report freshness.
        known = known && self->_pendingCursorPositionRevision == self->_pointerRevision && !self->_localPointerInteractionActive;
        self->_pendingCursorImage = nil; self->_pendingCursorPositionKnown = NO; self->_cursorPending = NO;
        if (valid && self.cursorHandler) {
            self->_cursorPublications++;
            if (known) self->_cursorPositionPublications++;
            else if (fresh) self->_cursorPositionsSuppressed++;
            self->_cursorQueueMaxMS = MAX(self->_cursorQueueMaxMS,
                (NSProcessInfo.processInfo.systemUptime - self->_pendingCursorReceivedAt) * 1000);
        }
        [self->_lock unlock];
        if (valid && self.cursorHandler) self.cursorHandler(image, hotspot, position, known);
    });
}
- (void)publishFrame:(rfbClient *)client {
    [_lock lock];
    BOOL probeCandidateFrame = _desktopResizeLayoutSeen && client->width == _desktopResizePixelWidth && client->height == _desktopResizePixelHeight
        && _coverageLayoutValid && _coverageLayout.width == client->width && _coverageLayout.height == client->height
        && (_desktopResizeSelection ? (_desktopResizeLayoutSeen && CompanionVNCDesktopSelectionMatches(&_coverageLayout, &_desktopCatalogueLayout, _desktopResizeDisplayID))
            : (_coverageLayout.count == 1 && _desktopResizeVirtualLayout));
    BOOL probeHold = _desktopResizePending || (_desktopResizeAwaiting && !probeCandidateFrame);
    [_lock unlock];
    if (probeHold) return;
    double now = NSProcessInfo.processInfo.systemUptime;
    if (_extensionFailed || !_dirty || !CompanionVNCCoverageReady(&_coverage) || now - _lastFrame < 1.0 / 30) return;
    [_lock lock];
    // A frame arriving before the owner consumes the refresh request belongs to
    // the old baseline. It cannot reopen input after local review or background.
    if (_framePending || _stopping || _paused || _inputOnly || _resumeRequested) { [_lock unlock]; return; }
    _framePending = YES; NSInteger generation = _generation; NSUInteger epoch = _presentationEpoch; [_lock unlock];
    _dirty = NO; _lastFrame = now;
    double copyStarted = NSProcessInfo.processInfo.systemUptime, cpuAtFreshPixels = WorkerCPUTimeMS();
    CompanionVNCSwitchReadSnapshot readAtFreshPixels = [self switchReadSnapshot];
    NSData *copy = [NSData dataWithBytes:client->frameBuffer length:(NSUInteger)client->width * client->height * 4];
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)copy);
    CGColorSpaceRef colors = CGColorSpaceCreateDeviceRGB();
    CGImageRef image = CGImageCreate(client->width, client->height, 8, 32, client->width * 4, colors,
        (CGBitmapInfo)kCGBitmapByteOrder32Little | (CGBitmapInfo)kCGImageAlphaNoneSkipFirst, provider, NULL, NO, kCGRenderingIntentDefault);
    CompanionVNCImage *frame = image ? PlatformImage(image) : nil;
    if (image) CGImageRelease(image); CGColorSpaceRelease(colors); CGDataProviderRelease(provider);
    double queuedAt = NSProcessInfo.processInfo.systemUptime, copyMS = (queuedAt - copyStarted) * 1000;
    [_lock lock]; _frameCopyTotalMS += copyMS; _frameCopyMaxMS = MAX(_frameCopyMaxMS, copyMS);
    [_lock unlock];
    dispatch_async(dispatch_get_main_queue(), ^{
        double deliveredAt = NSProcessInfo.processInfo.systemUptime;
        [self->_lock lock]; BOOL valid = generation == self->_generation && epoch == self->_presentationEpoch && self->_running && !self->_stopping && !self->_paused;
        if (generation == self->_generation) self->_framePending = NO; [self->_lock unlock];
        if (valid && frame && self.frameHandler) self.frameHandler(frame);
        double callbackMS = (NSProcessInfo.processInfo.systemUptime - deliveredAt) * 1000;
        if (valid && frame) {
            [self->_lock lock];
            // The socket owner can reset the baseline while frameHandler lays out UI.
            valid = generation == self->_generation && epoch == self->_presentationEpoch && self->_running && !self->_stopping && !self->_paused;
            if (!valid) { [self->_lock unlock]; return; }
            self->_frameMainQueueMaxMS = MAX(self->_frameMainQueueMaxMS, (deliveredAt - queuedAt) * 1000);
            self->_frameCallbackMaxMS = MAX(self->_frameCallbackMaxMS, callbackMS);
            BOOL firstBaseline = !self->_baselinePresented; self->_baselinePresented = YES; self->_presentedFrames++;
            if (self->_desktopResizeAwaiting && probeCandidateFrame) {
                self->_desktopResizeAwaiting = NO; self->_desktopResizeAccepted++; self->_desktopResizeOutcome = 2;
                self->_desktopResizeCompleteMS = (deliveredAt - self->_desktopResizeStarted) * 1000;
                // Capture the metrics belonging to this accepted frame, even if
                // another frame was queued while frameHandler was presenting.
                self->_desktopReadAtFrame = readAtFreshPixels; self->_desktopResizeMetricsReady = self->_readMeasurementsInstalled;
                self->_desktopResizeCopyMS = copyMS;
                self->_desktopResizeProcessingClockAvailable = self->_desktopResizeCPUMSAtWrite >= 0 && cpuAtFreshPixels >= self->_desktopResizeCPUMSAtWrite;
                self->_desktopResizeProcessingCPUMS = self->_desktopResizeProcessingClockAvailable ? cpuAtFreshPixels - self->_desktopResizeCPUMSAtWrite : 0;
                self->_desktopResizeMainQueueMS = MAX(0, (deliveredAt - queuedAt) * 1000);
                self->_desktopResizeFrameCallbackMS = callbackMS;
                [self recordDesktopSwitchLocked:deliveredAt];
            }
            BOOL resumed = self->_awaitingResumeFrame;
            if (resumed) { self->_resumeFrames++; self->_awaitingResumeFrame = NO; self->_inputReady = YES; }
            [self->_lock unlock];
            if (resumed || firstBaseline) [self report:@"Connected"];
        }
    });
    if (_presentedFrames > 0 && _updates % 30 == 0) [self report:@"Connected"];
}
- (NSDictionary *)diagnosticCounters {
    [_lock lock];
    NSMutableDictionary *stats = [_reportedCounters mutableCopy] ?: [NSMutableDictionary new];
    [stats addEntriesFromDictionary:@{
        @"cursorShapeUpdates": @(_cursorShapes), @"cursorPositionUpdates": @(_cursorPositions),
        @"cursorPositionPublications": @(_cursorPositionPublications), @"cursorPositionsSuppressed": @(_cursorPositionsSuppressed),
        @"standardCursorReports": @(_standardCursorReports), @"decodedCursorImages": @(_visibleCursorImages),
        @"serverMessages": @(_serverMessages), @"serverMessageTotalMS": @(_serverMessageTotalMS),
        @"serverMessageMaxMS": @(_serverMessageMaxMS), @"cursorQueueMaxMS": @(_cursorQueueMaxMS),
        @"automaticDesktopUpdates": @(_automaticUpdatesActive),
        @"automaticUpdateStarts": @(_automaticUpdateStarts), @"automaticUpdateStops": @(_automaticUpdateStops),
        @"appleCursorStores": @(_appleCursorStores), @"appleCursorSelections": @(_appleCursorSelections),
        @"appleCursorCacheMisses": @(_appleCursorMisses), @"cursorPublications": @(_cursorPublications),
        @"cursorCachedImage": @(_cursorImageAvailable), @"inputEvents": @(_inputs),
        @"presentedFrames": @(_presentedFrames), @"backgroundPauses": @(_pauses), @"retainedResumes": @(_resumes),
        @"sessionInputReady": @(_inputReady), @"sessionReviewBlocked": @(_reviewInputSuspended), @"sessionDisplayHandoffBlocked": @(_displayHandoffInputBlocked),
        @"sessionInterruptionBlocked": @(_interruptionInputSuspended), @"sessionPaused": @(_paused)}];
    stats[@"sampleUptime"] = @(NSProcessInfo.processInfo.systemUptime);
    stats[@"probeRequests"] = @(_desktopResizeRequests); stats[@"probeAccepted"] = @(_desktopResizeAccepted);
    stats[@"switches"] = [_desktopSwitchSamples copy] ?: @[];
    stats[@"fullRefreshRequests"] = @(_fullRefreshRequests); stats[@"coalescedFullRefreshes"] = @(_coalescedFullRefreshes);
    stats[@"routinePullRestarts"] = @(_routinePullRestarts); stats[@"fullRefreshRetries"] = @(_fullRefreshRetries); stats[@"baselineReady"] = @(_baselinePresented);
    stats[@"probeNoops"] = @(_desktopResizeNoops); stats[@"probeMetadataRequests"] = @(_desktopResizeMetadataRequests); stats[@"probeLayoutMS"] = @(_desktopResizeLayoutMS); stats[@"probeCompleteMS"] = @(_desktopResizeCompleteMS);
    stats[@"probeLayoutSeen"] = @(_desktopResizeLayoutSeen); stats[@"probeDisplayID"] = @(_desktopResizeDisplayID);
    stats[@"probeTimedOut"] = @(_desktopResizeTimedOut); stats[@"probeAwaiting"] = @(_desktopResizeAwaiting || _desktopResizePending);
    stats[@"probeOutcome"] = @(_desktopResizeOutcome);
    stats[@"sessionRunning"] = @(_running); stats[@"sessionEstablished"] = @(_established);
    stats[@"probeWidth"] = @(_desktopResizePixelWidth); stats[@"probeHeight"] = @(_desktopResizePixelHeight);
    stats[@"framebufferWidth"] = @(_framebufferWidth); stats[@"framebufferHeight"] = @(_framebufferHeight);
    stats[@"framebufferAllocations"] = @(_resizes); stats[@"failureStage"] = @(_failureStage);
    stats[@"baselineReceivedPixels"] = @(_receivedPixels); stats[@"baselineExpectedPixels"] = @(_expectedPixels);
    stats[@"layoutWidth"] = @(_coverageLayoutValid ? _coverageLayout.width : 0); stats[@"layoutHeight"] = @(_coverageLayoutValid ? _coverageLayout.height : 0);
    stats[@"layoutCount"] = @(_coverageLayoutValid ? _coverageLayout.count : 0); stats[@"layoutVirtual"] = @(_desktopResizeVirtualLayout);
    stats[@"probeLayoutResizes"] = @(_desktopResizeLayoutResizes);
    stats[@"physicalLayoutAdoptions"] = @(_physicalLayoutAdoptions);
    stats[@"selectionDeliveryPreserved"] = @(_selectionDeliveryPreserved);
    stats[@"pipeline"] = [self pipelineCountersLocked];
    [_lock unlock]; return stats;
}
- (void)report:(NSString *)state {
    // No endpoints, names, credentials, pixels, or typed content in diagnostics.
    [_lock lock];
    if ([state isEqualToString:@"Connected"] && !CompanionVNCConnectionReady(
        _running, _inputReady, _inputOnly, _paused, _stopping, _overflow,
        _awaitingResumeFrame, _baselinePresented)) { [_lock unlock]; return; }
    NSInteger generation = _generation; NSUInteger epoch = _presentationEpoch; BOOL intermediate = _running;
    NSDictionary *stats = @{@"pipeline": [self pipelineCountersLocked], @"connectionStarts": @(_connections), @"updateRects": @(_updates),
        @"framebufferAllocations": @(_resizes), @"inputEvents": @(_inputs), @"viewChanges": @(_viewChanges), @"presentedFrames": @(_presentedFrames),
        @"baselineReady": @(_baselinePresented), @"baselineReceivedPixels": @(_receivedPixels), @"baselineExpectedPixels": @(_expectedPixels), @"fullRefreshRetries": @(_fullRefreshRetries),
        @"decoderFailures": @(_decoderFailures),
        @"failureStage": @(_failureStage), @"credentialRequests": @(_credentialRequests), @"handshakeStage": @(_handshakeStage),
        @"framebufferWidth": @(_framebufferWidth), @"framebufferHeight": @(_framebufferHeight),
        @"displayLayoutMessages": @(_layoutMessages), @"displayLayout": _layoutDiagnostics ?: @{},
        @"backgroundPauses": @(_pauses), @"retainedResumes": @(_resumes), @"resumeFrames": @(_resumeFrames),
        @"cursorShapeUpdates": @(_cursorShapes), @"cursorPositionUpdates": @(_cursorPositions),
        @"cursorPositionPublications": @(_cursorPositionPublications), @"cursorPositionsSuppressed": @(_cursorPositionsSuppressed),
        @"standardCursorReports": @(_standardCursorReports), @"decodedCursorImages": @(_visibleCursorImages),
        @"serverMessages": @(_serverMessages), @"serverMessageTotalMS": @(_serverMessageTotalMS),
        @"serverMessageMaxMS": @(_serverMessageMaxMS), @"cursorQueueMaxMS": @(_cursorQueueMaxMS),
        @"automaticDesktopUpdates": @(_automaticUpdatesActive),
        @"automaticUpdateStarts": @(_automaticUpdateStarts), @"automaticUpdateStops": @(_automaticUpdateStops),
        @"appleCursorStores": @(_appleCursorStores), @"appleCursorSelections": @(_appleCursorSelections),
        @"appleCursorCacheMisses": @(_appleCursorMisses), @"cursorPublications": @(_cursorPublications)};
    _reportedCounters = stats;
    [_lock unlock];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_lock lock]; BOOL current = generation == self->_generation && !(intermediate && (self->_stopping || epoch != self->_presentationEpoch)); [self->_lock unlock];
        if (current && self.stateHandler) self.stateHandler(state, stats);
    });
}
- (void)stop {
    [_lock lock]; _desktopResizeLateEligible = NO; [self retirePointerInteractionLocked]; [self cancelNativeGesturesLocked]; _stopping = YES; _presentationEpoch++; [_events removeAllObjects]; NSInteger generation = _generation;
    void (^completion)(void) = _pauseCompletion; _pauseCompletion = nil;
    // A temporary input gate must not close an authenticated transport before
    // its owner releases sent input. Handshakes have no held input to release.
    if (!_established && _socket >= 0) shutdown(_socket, SHUT_RDWR);
#if TARGET_OS_IOS
    [self cancelComposedTextLocked];
#endif
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
    if (_running && _inputReady && !_reviewInputSuspended && !_displayHandoffInputBlocked && !_interruptionInputSuspended && !_paused && !_stopping) {
        // Coalesce only motion with identical button state, preserving key/button ordering.
        NSDictionary *last = _events.lastObject;
        if (event[@"mask"]) {
            NSInteger mask = [event[@"mask"] integerValue];
            BOOL motion = mask == _queuedPointerMask;
            _queuedPointerMask = mask;
            NSMutableDictionary *annotated = [event mutableCopy]; annotated[@"motion"] = @(motion); event = annotated;
            if (motion && [last[@"motion"] boolValue] && [event[@"mask"] isEqual:last[@"mask"]]) [_events removeLastObject];
        }
        if (_events.count >= 512) _overflow = YES;
        else {
            [_events addObject:event];
            if (event[@"mask"]) {
                _pointerRevision++;
            }
        }
    }
    [_lock unlock];
}
- (void)pointerX:(NSInteger)x y:(NSInteger)y mask:(NSInteger)mask {
    [self enqueue:@{@"x": @(x), @"y": @(y), @"mask": @(mask)}];
}
- (void)key:(uint32_t)key down:(BOOL)down { [self enqueue:@{@"key": @(key), @"down": @(down)}]; }
- (void)keyEvents:(NSArray<NSDictionary *> *)events {
    [_lock lock];
    if (_running && _inputReady && !_reviewInputSuspended && !_displayHandoffInputBlocked && !_interruptionInputSuspended && !_paused && !_stopping && !_overflow) {
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
    BOOL allowed = _running && _inputReady && !_reviewInputSuspended && !_displayHandoffInputBlocked && !_interruptionInputSuspended && !_paused && !_stopping && !_overflow
        && events.count > 0 && CompanionVNCKeyGroupFits(_events.count, events.count, 512);
    if (allowed) [_events addObjectsFromArray:events];
    [_lock unlock]; return allowed;
}
#if TARGET_OS_IOS
- (BOOL)writeKeyEvent:(uint32_t)key down:(BOOL)down client:(rfbClient *)client {
    return SendKeyEvent(client, key, down);
}
- (BOOL)composedTextReadyLocked {
    return !_reviewInputSuspended && !_displayHandoffInputBlocked && !_interruptionInputSuspended && CompanionVNCConnectionReady(_running, _inputReady, _inputOnly,
        _paused, _stopping, _overflow, _awaitingResumeFrame, _baselinePresented);
}
- (BOOL)composedTextReady {
    [_lock lock]; BOOL ready = [self composedTextReadyLocked]; [_lock unlock]; return ready;
}
- (BOOL)tryComposedTextEvents:(NSArray<NSDictionary *> *)events completion:(void (^)(BOOL))completion {
    [_lock lock];
    BOOL allowed = completion && [self composedTextReadyLocked]
        && events.count > 0 && CompanionVNCKeyGroupFits(_events.count, events.count, 512);
    if (allowed) {
        NSString *identifier = NSUUID.UUID.UUIDString;
        _composedTextReplies[identifier] = [completion copy];
        NSMutableArray *group = [NSMutableArray arrayWithCapacity:events.count];
        for (NSDictionary *event in events) {
            NSMutableDictionary *annotated = [event mutableCopy]; annotated[@"composedTextID"] = identifier;
            [group addObject:annotated];
        }
        group.lastObject[@"composedTextEnd"] = @YES; [_events addObjectsFromArray:group];
    }
    [_lock unlock]; return allowed;
}
- (void)completeComposedText:(NSString *)identifier written:(BOOL)written {
    [_lock lock]; void (^reply)(BOOL) = _composedTextReplies[identifier];
    [_composedTextReplies removeObjectForKey:identifier]; [_lock unlock];
    if (reply) dispatch_async(dispatch_get_main_queue(), ^{ reply(written); });
}
- (void)cancelComposedText {
    [_lock lock]; [self cancelComposedTextLocked]; [_lock unlock];
}
// Called under the queue lock so retiring input and its copied groups is atomic.
- (void)cancelComposedTextLocked {
    NSArray *replies = _composedTextReplies.allValues; [_composedTextReplies removeAllObjects];
    if (replies.count) _releaseInputRequested = YES;
    for (void (^reply)(BOOL) in replies) dispatch_async(dispatch_get_main_queue(), ^{ reply(NO); });
}
#endif
@end
