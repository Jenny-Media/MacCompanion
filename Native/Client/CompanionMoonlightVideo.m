#import "CompanionMoonlightVideo.h"
#import <AVFoundation/AVFoundation.h>
#import "VideoDecoderRenderer.h"
#import "ConnectionCallbacks.h"
#include "Limelight.h"
#include <openssl/crypto.h>
#include <stdatomic.h>
#include "CompanionNativeSurfaceEpoch.h"
#include "CompanionMoonlightTerminalDiagnostic.h"

@implementation CompanionMoonlightVideoConfiguration
@end

@interface CompanionMoonlightVideo () <ConnectionCallbacks>
@property (strong, nonatomic) VideoDecoderRenderer *renderer;
@property (weak, nonatomic) UIView *renderView;
@property (copy, nonatomic) void (^event)(CompanionMoonlightVideoEvent, int);
@property (strong, nonatomic) NSLock *stateLock;
@property (nonatomic) BOOL retired;
@property (nonatomic) BOOL started;
@property (nonatomic) BOOL stopping;
@property (nonatomic) BOOL waitingForEpoch;
@property (nonatomic) int videoFormat;
@property (strong, nonatomic) NSMutableArray *stopCompletions;
@property (strong, nonatomic) dispatch_queue_t worker;
@property (strong, nonatomic, nullable) dispatch_source_t interruptTimer;
- (void)deliver:(CompanionMoonlightVideoEvent)event code:(int)code;
- (void)recordQueuedVideoFrame;
- (void)recordEngineTerminalFormat:(const char *)format;
- (void)requestReplacementKeyFrame;
- (BOOL)acceptPicture:(const unsigned char *)data length:(size_t)length independent:(BOOL *)independent;
@end

// moonlight-common-c has a process-global connection. Reserve it until Stop
// has drained, including failed startup, before allowing another generation.
static CompanionMoonlightVideo *activeSession;
static NSLock *ownerLock;

static CompanionMoonlightVideo *currentSession(void) {
    [ownerLock lock];
    CompanionMoonlightVideo *result = activeSession;
    [ownerLock unlock];
    return result;
}

@implementation CompanionMoonlightVideo {
    SERVER_INFORMATION _server;
    STREAM_CONFIGURATION _stream;
    char _host[256];
    char _version[32];
    char _sessionURL[128];
    _Atomic(uint64_t) _queuedVideoFrameCount;
    _Atomic(uint64_t) _frameEpochGeneration;
    _Atomic(int) _terminalDiagnosticCode;
    CompanionNativeSurfaceEpoch _expectedEpoch;
    BOOL _hasExpectedEpoch, _waitingForEpoch, _awaitingEpochConfiguration;
    int _videoFormat;
}

+ (void)initialize {
    if (self == CompanionMoonlightVideo.class) {
        ownerLock = [[NSLock alloc] init];
    }
}

static BOOL fail(NSError **error, NSInteger code) {
    if (error) {
        *error = [NSError errorWithDomain:@"CompanionMoonlightVideo" code:code userInfo:nil];
    }
    return NO;
}

- (instancetype)initWithConfiguration:(CompanionMoonlightVideoConfiguration *)config
                                  view:(UIView *)view
                                 event:(void (^)(CompanionMoonlightVideoEvent, int))event
                                 error:(NSError **)error {
    NSAssert(NSThread.isMainThread, @"Video composition must use the main thread");
    NSURL *url = [NSURL URLWithString:config.sessionURL];
    BOOL valid = config.host.length > 0 && [config.host lengthOfBytesUsingEncoding:NSUTF8StringEncoding] < sizeof(_host)
        && config.appVersion.length > 0 && [config.appVersion lengthOfBytesUsingEncoding:NSUTF8StringEncoding] < sizeof(_version)
        && config.sessionURL.length > 0 && [config.sessionURL lengthOfBytesUsingEncoding:NSUTF8StringEncoding] < sizeof(_sessionURL)
        && ( [url.scheme isEqualToString:@"rtsp"] || [url.scheme isEqualToString:@"rtspenc"] )
        && url.host.length > 0 && url.port != nil && url.port.intValue > 0 && url.port.intValue <= 65535
        && [url.host caseInsensitiveCompare:config.host] == NSOrderedSame
        && url.user == nil && url.password == nil
        && config.serverCodecModeSupport != 0
        && config.streamKey.length == 16 && config.width >= 320 && config.width <= 8192
        && config.height >= 240 && config.height <= 8192 && config.framesPerSecond >= 1
        && config.framesPerSecond <= 120 && config.bitrateKbps >= 500 && config.bitrateKbps <= 150000;
    if (!valid) { fail(error, 1); return nil; }
    if (!(self = [super init])) { return nil; }
    atomic_init(&_queuedVideoFrameCount,0);
    atomic_init(&_frameEpochGeneration,0);
    _stateLock = [[NSLock alloc] init];
    _stopCompletions = [[NSMutableArray alloc] init];
    _worker = dispatch_queue_create("maccompanion.moonlight.video", DISPATCH_QUEUE_SERIAL);
    _event = [event copy];
    snprintf(_host, sizeof(_host), "%s", config.host.UTF8String);
    snprintf(_version, sizeof(_version), "%s", config.appVersion.UTF8String);
    snprintf(_sessionURL, sizeof(_sessionURL), "%s", config.sessionURL.UTF8String);
    LiInitializeServerInformation(&_server);
    _server.address = _host;
    _server.serverInfoAppVersion = _version;
    _server.serverCodecModeSupport = config.serverCodecModeSupport;
    _server.rtspSessionUrl = _sessionURL;
    LiInitializeStreamConfiguration(&_stream);
    _stream.width = config.width;
    _stream.height = config.height;
    _stream.fps = config.framesPerSecond;
    _stream.bitrate = config.bitrateKbps;
    _stream.supportedVideoFormats = VIDEO_FORMAT_H264 | VIDEO_FORMAT_H265;
    _stream.audioConfiguration = AUDIO_CONFIGURATION_STEREO;
    _stream.streamingRemotely = STREAM_CFG_AUTO;
    _stream.packetSize = 1392;
    _stream.encryptionFlags = ENCFLG_ALL;
    memcpy(_stream.remoteInputAesKey, config.streamKey.bytes, 16);
    uint32_t keyID = htonl(config.streamKeyID);
    memcpy(_stream.remoteInputAesIv, &keyID, sizeof(keyID));
    _renderView = view;
    _renderer = [[VideoDecoderRenderer alloc] initWithView:view callbacks:self
                                       streamAspectRatio:(float)config.width / config.height useFramePacing:NO];
    return self;
}

static int decoderSetup(int format, int width, int height, int fps, void *context, int flags) {
    CompanionMoonlightVideo *session = currentSession();
    if (!session || (format != VIDEO_FORMAT_H264 && format != VIDEO_FORMAT_H265)
        || width < 320 || width > 8192 || height < 240 || height > 8192) {
        [session deliver:CompanionMoonlightVideoEventFailed code:-1];
        return -1;
    }
    dispatch_sync(dispatch_get_main_queue(), ^{
        if (!session.retired) {
            session.videoFormat = format;
            [session.renderer setupWithVideoFormat:format width:width height:height frameRate:fps];
        }
    });
    return 0;
}

static void decoderStart(void) {
    CompanionMoonlightVideo *session = currentSession();
    dispatch_sync(dispatch_get_main_queue(), ^{ if (!session.retired) { [session.renderer start]; } });
}

static void decoderStop(void) {
    CompanionMoonlightVideo *session = currentSession();
    dispatch_sync(dispatch_get_main_queue(), ^{ [session.renderer stop]; });
}

// The upstream renderer pulls complete frames on the main thread.
int DrSubmitDecodeUnit(PDECODE_UNIT unit) {
    if (!unit || unit->fullLength <= 0 || unit->fullLength > 67108864 || !unit->bufferList) { return DR_NEED_IDR; }
    unsigned char *data = malloc(unit->fullLength);
    if (!data) { return DR_NEED_IDR; }
    int length = 0;
    int total = 0;
    CompanionMoonlightVideo *session = currentSession();
    if (!session || session.retired) { free(data); return DR_NEED_IDR; }
    for (PLENTRY entry = unit->bufferList; entry; entry = entry->next) {
        if (!entry->data || entry->length <= 0 || entry->length > unit->fullLength - total) { free(data); return DR_NEED_IDR; }
        total += entry->length;
        if (entry->bufferType == BUFFER_TYPE_PICDATA) {
            memcpy(data + length, entry->data, entry->length);
            length += entry->length;
        }
    }
    if (total != unit->fullLength || length == 0) { free(data); return DR_NEED_IDR; }
    BOOL independent = NO;
    if (![session acceptPicture:data length:(size_t)length independent:&independent]) {
        free(data); return DR_OK;
    }
    if (session.waitingForEpoch && (!independent || unit->frameType != FRAME_TYPE_IDR)) {
        free(data); return DR_NEED_IDR;
    }
    // Parameter sets from an old epoch must not alter the decoder's state.
    // Validate the complete picture's marker before submitting any of them.
    for (PLENTRY entry = unit->bufferList; entry; entry = entry->next) {
        if (entry->bufferType == BUFFER_TYPE_PICDATA) continue;
        if (entry->length < 4) { free(data); return DR_NEED_IDR; }
        int result = [session.renderer submitDecodeBuffer:(unsigned char *)entry->data length:entry->length
                                              bufferType:entry->bufferType decodeUnit:unit];
        if (result != DR_OK) { free(data); return result; }
    }
    // Upstream takes ownership of the picture allocation, including failures.
    int result = [session.renderer submitDecodeBuffer:data length:length
                                           bufferType:BUFFER_TYPE_PICDATA decodeUnit:unit];
    if (result == DR_OK) {
        session.waitingForEpoch = NO;
        [session recordQueuedVideoFrame];
    }
    return result;
}

static void connectionStarted(void) { [currentSession() deliver:CompanionMoonlightVideoEventConnected code:0]; }
static void connectionTerminated(int code) { [currentSession() deliver:CompanionMoonlightVideoEventDisconnected code:code]; }
static void engineLogMessage(const char *format, ...) {
    [currentSession() recordEngineTerminalFormat:format];
}
- (void)recordEngineTerminalFormat:(const char *)format {
    int code = CompanionMoonlightTerminalDiagnostic(format), expected = 0;
    if (code) atomic_compare_exchange_strong(&_terminalDiagnosticCode, &expected, code);
}
- (int)terminalDiagnosticCode { return atomic_load(&_terminalDiagnosticCode); }
static void stageFailed(int stage, int code) {
    NSLog(@"MacCompanion embedded: stage failed stage=%d code=%d", stage, code);
    [currentSession() deliver:CompanionMoonlightVideoEventFailed code:code];
}
static int audioSetup(int config, const POPUS_MULTISTREAM_CONFIGURATION opus, void *context, int flags) { return 0; }
static void discardAudio(char *bytes, int length) { }

- (BOOL)start:(NSError **)error {
    NSAssert(NSThread.isMainThread, @"Start must use the main thread");
    if (self.started || self.retired) { return fail(error, 2); }
    [ownerLock lock];
    if (activeSession != nil) { [ownerLock unlock]; return fail(error, 3); }
    activeSession = self;
    [ownerLock unlock];
    self.started = YES;
    dispatch_async(self.worker, ^{
        [self.stateLock lock];
        BOOL retired = self.retired;
        [self.stateLock unlock];
        if (retired) { return; }
        DECODER_RENDERER_CALLBACKS video;
        CONNECTION_LISTENER_CALLBACKS connection;
        AUDIO_RENDERER_CALLBACKS audio;
        LiInitializeVideoCallbacks(&video);
        LiInitializeConnectionCallbacks(&connection);
        LiInitializeAudioCallbacks(&audio);
        video.setup = decoderSetup;
        video.start = decoderStart;
        video.stop = decoderStop;
        video.capabilities = CAPABILITY_PULL_RENDERER | CAPABILITY_REFERENCE_FRAME_INVALIDATION_HEVC;
        connection.connectionStarted = connectionStarted;
        connection.connectionTerminated = connectionTerminated;
        connection.stageFailed = stageFailed;
        connection.logMessage = engineLogMessage;
        audio.init = audioSetup;
        audio.decodeAndPlaySample = discardAudio;
        audio.capabilities = CAPABILITY_SUPPORTS_ARBITRARY_AUDIO_DURATION;
        int code = LiStartConnection(&self->_server, &self->_stream, &connection, &video, &audio, NULL, 0, NULL, 0);
        if (code != 0) { [self deliver:CompanionMoonlightVideoEventFailed code:code]; }
    });
    return YES;
}

- (void)deliver:(CompanionMoonlightVideoEvent)event code:(int)code {
    uint64_t generation = atomic_load_explicit(&_frameEpochGeneration,memory_order_relaxed);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (event == CompanionMoonlightVideoEventFirstFrame
            && generation != atomic_load_explicit(&self->_frameEpochGeneration,memory_order_relaxed)) return;
        if (!self.retired && currentSession() == self) { self.event(event, code); }
    });
}

- (BOOL)beginSurfaceReplacement:(NSError **)error {
    NSAssert(NSThread.isMainThread, @"Surface replacement must use the main thread");
    if (self.retired || self.stopping || !self.started || _waitingForEpoch
        || !self.presentationReady || atomic_load(&_frameEpochGeneration) == UINT64_MAX) return fail(error,4);
    _waitingForEpoch = YES;
    _awaitingEpochConfiguration = YES;
    atomic_fetch_add(&_frameEpochGeneration,1);
    for (CALayer *layer in self.renderView.layer.sublayers) {
        if ([layer isKindOfClass:AVSampleBufferDisplayLayer.class]) {
            [(AVSampleBufferDisplayLayer *)layer flushAndRemoveImage]; layer.hidden = YES;
        }
    }
    return YES;
}

- (BOOL)resumeSurfaceReplacementWithEpoch:(NSData *)bytes error:(NSError **)error {
    NSAssert(NSThread.isMainThread, @"Surface replacement must use the main thread");
    CompanionNativeSurfaceEpoch epoch;
    if (self.retired || self.stopping || !_waitingForEpoch || !_awaitingEpochConfiguration
        || !CompanionNativeEpochDecode(bytes.bytes,bytes.length,&epoch)
        || (_hasExpectedEpoch && CompanionNativeEpochEqual(&epoch,&_expectedEpoch))) return fail(error,4);
    _expectedEpoch = epoch; _hasExpectedEpoch = YES;
    _awaitingEpochConfiguration = NO;
    // The host's first new-epoch IDR may arrive while we are still fenced.
    // Request one once the new epoch is installed, using this same transport.
    [self requestReplacementKeyFrame];
    return YES;
}

- (void)requestReplacementKeyFrame { LiRequestIdrFrame(); }

- (BOOL)acceptPicture:(const unsigned char *)data length:(size_t)length independent:(BOOL *)independent {
    NSAssert(NSThread.isMainThread, @"Picture acceptance must use the main thread");
    if (_awaitingEpochConfiguration) return NO;
    if (!_hasExpectedEpoch) return !_waitingForEpoch;
    CompanionNativeSurfaceEpoch epoch; bool idr = false;
    int result = CompanionNativeEpochInspect(data,length,_videoFormat == VIDEO_FORMAT_H265,&epoch,&idr);
    *independent = idr;
    return result == 1 && CompanionNativeEpochEqual(&epoch,&_expectedEpoch);
}

- (void)stopWithCompletion:(void (^)(void))completion {
    NSAssert(NSThread.isMainThread, @"Stop must use the main thread");
    if (!self.started) { self.retired = YES; completion(); return; }
    [self.stopCompletions addObject:[completion copy]];
    if (self.stopping) { return; }
    self.stopping = YES;
    [self.stateLock lock]; self.retired = YES; [self.stateLock unlock];
    [self.renderer stop];
    // A stop immediately before LiStartConnection may precede its internal
    // interrupt reset. Repeat interruption until the startup worker drains.
    dispatch_queue_t interruptQueue = dispatch_queue_create("maccompanion.moonlight.interrupt", DISPATCH_QUEUE_SERIAL);
    self.interruptTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, interruptQueue);
    dispatch_source_set_timer(self.interruptTimer, DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC, 5 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(self.interruptTimer, ^{ LiInterruptConnection(); });
    dispatch_source_set_cancel_handler(self.interruptTimer, ^{
        // Cancellation is acknowledged after the final interrupt handler.
        // Keep the singleton reserved through native Stop and main-thread
        // decoder retirement so a late callback cannot reach a new session.
        dispatch_async(self.worker, ^{
            LiStopConnection();
            OPENSSL_cleanse(self->_stream.remoteInputAesKey, sizeof(self->_stream.remoteInputAesKey));
            OPENSSL_cleanse(self->_stream.remoteInputAesIv, sizeof(self->_stream.remoteInputAesIv));
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.renderer stop];
                self.renderer = nil;
                [ownerLock lock]; if (activeSession == self) { activeSession = nil; } [ownerLock unlock];
                self.started = NO;
                self.interruptTimer = nil;
                NSArray *completions = [self.stopCompletions copy];
                [self.stopCompletions removeAllObjects];
                for (void (^callback)(void) in completions) { callback(); }
            });
        });
    });
    dispatch_resume(self.interruptTimer);
    dispatch_async(self.worker, ^{ dispatch_source_cancel(self.interruptTimer); });
}

- (BOOL)presentationReady {
    NSAssert(NSThread.isMainThread, @"Read presentation readiness on the main thread");
    if (self.retired || self.stopping || !self.started || !self.renderView || _waitingForEpoch) return NO;
    // The pinned renderer installs one display layer directly in this view.
    // An IDR enqueue callback alone is not AVFoundation display readiness.
    for (CALayer *layer in self.renderView.layer.sublayers) {
        if ([layer isKindOfClass:AVSampleBufferDisplayLayer.class]) {
            AVSampleBufferDisplayLayer *video = (AVSampleBufferDisplayLayer *)layer;
            return !video.hidden && video.isReadyForDisplay && video.status != AVQueuedSampleBufferRenderingStatusFailed;
        }
    }
    return NO;
}

- (int)decodedWidth {
    NSAssert(NSThread.isMainThread, @"Read decoded geometry on the main thread");
    return [self.renderer companionDecodedWidth];
}
- (int)decodedHeight {
    NSAssert(NSThread.isMainThread, @"Read decoded geometry on the main thread");
    return [self.renderer companionDecodedHeight];
}
- (uint64_t)queuedVideoFrameCount {
    return atomic_load_explicit(&_queuedVideoFrameCount, memory_order_relaxed);
}
- (void)recordQueuedVideoFrame {
    atomic_fetch_add_explicit(&_queuedVideoFrameCount, 1, memory_order_relaxed);
}
- (void)videoContentShown { [self deliver:CompanionMoonlightVideoEventFirstFrame code:0]; }
- (void)connectionStarted { }
- (void)connectionTerminated:(int)code { }
- (void)stageStarting:(const char *)name { }
- (void)stageComplete:(const char *)name { }
- (void)stageFailed:(const char *)name withError:(int)code portTestFlags:(int)flags { }
- (void)launchFailed:(NSString *)message { }
- (void)rumble:(unsigned short)number lowFreqMotor:(unsigned short)low highFreqMotor:(unsigned short)high { }
- (void)connectionStatusUpdate:(int)status { }
- (void)setHdrMode:(bool)enabled { }
- (void)rumbleTriggers:(uint16_t)number leftTrigger:(uint16_t)left rightTrigger:(uint16_t)right { }
- (void)setMotionEventState:(uint16_t)number motionType:(uint8_t)type reportRateHz:(uint16_t)rate { }
- (void)setControllerLed:(uint16_t)number r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b { }
@end
