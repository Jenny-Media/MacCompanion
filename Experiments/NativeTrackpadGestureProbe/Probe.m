#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>
#include <rfb/rfbclient.h>
#include <math.h>
#include <stdarg.h>
#include <signal.h>

// Disposable loopback experiment. Nothing in this directory enters an iOS target.
// Authentication is the existing, pinned LibVNCClient ARD implementation.
static char ownerTag;
static void QuietLog(const char *format, ...) { (void)format; }
static NSUInteger appMagnifyCount;
static BOOL IsNetworkMagnification(NSEvent *event) {
    return event.type == NSEventTypeMagnify &&
        CGEventGetIntegerValueField(event.CGEvent, kCGEventSourceUnixProcessID) > 0 &&
        CGEventGetIntegerValueField(event.CGEvent, (CGEventField)133) == 4;
}

@interface ProbeApplication : NSApplication
@end
@implementation ProbeApplication
- (void)sendEvent:(NSEvent *)event {
    // Magnification owns phase/magnification; querying those on MouseMoved throws.
    // This observes only our own app's gesture delivery, never keys or text.
    if (IsNetworkMagnification(event) ||
        ((event.type == NSEventTypeBeginGesture || event.type == NSEventTypeEndGesture) &&
         CGEventGetIntegerValueField(event.CGEvent, kCGEventSourceUnixProcessID) > 0)) {
        BOOL magnify = event.type == NSEventTypeMagnify;
        if (magnify) appMagnifyCount++;
        printf("OWN_APP_GESTURE type=%lu phase=%lu delta=%.6f cg_type=%u subtype=%lld source_pid=%lld window=%ld local=(%.1f,%.1f) cg=(%.1f,%.1f) phase132=%lld mask133=%lld\n",
               (unsigned long)event.type, magnify ? (unsigned long)event.phase : 0,
               magnify ? event.magnification : 0.0, (unsigned)CGEventGetType(event.CGEvent),
               (long long)CGEventGetIntegerValueField(event.CGEvent, (CGEventField)110),
               (long long)CGEventGetIntegerValueField(event.CGEvent, kCGEventSourceUnixProcessID),
               (long)event.windowNumber, event.locationInWindow.x, event.locationInWindow.y,
               CGEventGetLocation(event.CGEvent).x, CGEventGetLocation(event.CGEvent).y,
               (long long)CGEventGetIntegerValueField(event.CGEvent, (CGEventField)132),
               (long long)CGEventGetIntegerValueField(event.CGEvent, (CGEventField)133));
        fflush(stdout);
    }
    [super sendEvent:event];
}
@end

@interface GestureReceiver : NSView
@property double scale;
@property NSUInteger received;
@property BOOL verifying;
@property(copy) void (^result)(NSString *);
@end
@implementation GestureReceiver
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) _scale = 1;
    return self;
}
- (BOOL)acceptsFirstResponder { return YES; }
- (void)drawRect:(NSRect)dirty {
    [NSColor.controlBackgroundColor setFill]; NSRectFill(self.bounds);
    NSRect square = NSMakeRect(NSMidX(self.bounds) - 45 * self.scale,
                              NSMidY(self.bounds) - 45 * self.scale,
                              90 * self.scale, 90 * self.scale);
    [NSColor.systemBlueColor setFill];
    [[NSBezierPath bezierPathWithRoundedRect:square xRadius:12 yRadius:12] fill];
}
- (void)magnifyWithEvent:(NSEvent *)event {
    // A physical pinch on this Mac must not satisfy the network-delivery proof.
    // Corroborate the logged source PID with the built-in ScreensharingAgent.
    if (!self.verifying || !IsNetworkMagnification(event)) return;
    self.received++;
    self.scale = fmax(.5, fmin(2, self.scale * (1 + event.magnification)));
    self.needsDisplay = YES;
    // Only this view's magnification is recorded. No keys, text, or global monitor.
    printf("NATIVE_MAGNIFY count=%lu phase=%lu delta=%.6f cg_type=%u subtype=%lld source_pid=%lld\n",
           (unsigned long)self.received, (unsigned long)event.phase,
           event.magnification, (unsigned)CGEventGetType(event.CGEvent),
           (long long)CGEventGetIntegerValueField(event.CGEvent, (CGEventField)110),
           (long long)CGEventGetIntegerValueField(event.CGEvent, kCGEventSourceUnixProcessID));
    fflush(stdout);
    if (self.result) self.result([NSString stringWithFormat:@"Received %lu network magnify events · scale %.3f",
                                 (unsigned long)self.received, self.scale]);
}
@end

@interface Probe : NSObject <NSApplicationDelegate, NSWindowDelegate>
@property NSWindow *window;
@property NSTextField *user, *status;
@property NSSecureTextField *password;
@property NSButton *connect, *test;
@property GestureReceiver *receiver;
@property dispatch_queue_t queue;
@property rfbClient *client; // Owned and accessed on queue only.
@property(copy) NSString *authUser, *authPassword; // Queue-local; cleared after handshake.
@property NSInteger wireVersion;
- (rfbCredential *)credential:(int)type;
@end

static rfbCredential *Credential(rfbClient *client, int type) {
    Probe *probe = (__bridge Probe *)rfbClientGetClientData(client, &ownerTag);
    return [probe credential:type];
}
static void Append16(NSMutableData *data, uint16_t value) {
    uint16_t be = CFSwapInt16HostToBig(value); [data appendBytes:&be length:2];
}
static void Append32(NSMutableData *data, uint32_t value) {
    uint32_t be = CFSwapInt32HostToBig(value); [data appendBytes:&be length:4];
}
static void Append64(NSMutableData *data, uint64_t value) {
    uint64_t be = CFSwapInt64HostToBig(value); [data appendBytes:&be length:8];
}
static BOOL SendPayload(rfbClient *client, NSData *body) {
    NSMutableData *message = [NSMutableData data];
    const uint8_t prefix[] = {0x17, 0}; [message appendBytes:prefix length:2];
    Append16(message, (uint16_t)body.length); [message appendData:body];
    return WriteToRFBServer(client, message.bytes, (unsigned int)message.length);
}
static BOOL SendBoundary(rfbClient *client, uint16_t kind, uint16_t x, uint16_t y) {
    NSMutableData *body = [NSMutableData data];
    // Apple's client uses v1 for these boundaries even with v2 magnification.
    // This field is NSEvent.subtype (Touch = 3), not the magnification mask (4).
    Append16(body, 1); Append16(body, kind); Append32(body, NSEventSubtypeTouch);
    Append16(body, x); Append16(body, y);
    return SendPayload(client, body);
}
static BOOL SendMagnification(rfbClient *client, uint16_t version, double delta, uint64_t phase,
                              uint16_t x, uint16_t y) {
    NSMutableData *body = [NSMutableData data]; uint64_t bits;
    memcpy(&bits, &delta, sizeof(bits));
    Append16(body, version); Append16(body, 3); Append64(body, bits);
    Append16(body, x); Append16(body, y);
    if (version >= 2) { Append64(body, phase); Append64(body, 4); }
    return SendPayload(client, body);
}

@implementation Probe
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.queue = dispatch_queue_create("native-gesture-loopback", DISPATCH_QUEUE_SERIAL);
    self.wireVersion = 2; // Matches the installed Apple client's magnification sender.
    rfbClientLog = QuietLog; rfbClientErr = QuietLog;
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 490)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Native Trackpad Gesture Probe"; self.window.delegate = self;
    NSView *content = self.window.contentView;
    NSTextField *heading = [NSTextField labelWithString:@"Built-in Screen Sharing · loopback only"];
    heading.frame = NSMakeRect(24, 444, 512, 24); [content addSubview:heading];
    NSTextField *explanation = [NSTextField wrappingLabelWithString:
        @"Sign in to this Mac to send one small pinch to the blue test square. Credentials are not saved. No screenshots or terminal input are collected."];
    explanation.frame = NSMakeRect(24, 382, 512, 52); [content addSubview:explanation];
    self.user = [[NSTextField alloc] initWithFrame:NSMakeRect(24, 344, 248, 28)];
    self.user.placeholderString = @"Mac account"; self.user.stringValue = NSUserName();
    [content addSubview:self.user];
    self.password = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(288, 344, 248, 28)];
    self.password.placeholderString = @"Mac password"; [content addSubview:self.password];
    self.connect = [NSButton buttonWithTitle:@"Sign In and Verify" target:self action:@selector(connectAction:)];
    self.connect.frame = NSMakeRect(24, 300, 240, 32); [content addSubview:self.connect];
    self.test = [NSButton buttonWithTitle:@"Verify Again" target:self action:@selector(testAction:)];
    self.test.frame = NSMakeRect(288, 300, 248, 32); self.test.enabled = NO; [content addSubview:self.test];
    self.receiver = [[GestureReceiver alloc] initWithFrame:NSMakeRect(24, 76, 512, 204)];
    [content addSubview:self.receiver];
    self.status = [NSTextField wrappingLabelWithString:@"Ready. The probe connects only to 127.0.0.1:5900."];
    self.status.frame = NSMakeRect(24, 16, 512, 50); [content addSubview:self.status];
    __weak Probe *weak = self;
    self.receiver.result = ^(NSString *result) { weak.status.stringValue = result; };
    [self.window center]; [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES]; [self.window makeFirstResponder:self.password];
    // Fixed local diagnostic commands let later bounded tests reuse this login.
    // This is an inherited process pipe, not a listening socket or saved credential.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        char command[32];
        while (fgets(command, sizeof(command), stdin)) {
            if (!strcmp(command, "verify-v1\n") || !strcmp(command, "verify-v2\n")) {
                NSInteger version = !strcmp(command, "verify-v2\n") ? 2 : 1;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!self.test.enabled) return;
                    self.wireVersion = version;
                    [self.window makeKeyAndOrderFront:nil]; [NSApp activateIgnoringOtherApps:YES];
                    [self testAction:nil];
                });
            }
        }
    });
}
- (rfbCredential *)credential:(int)type {
    if (type != rfbCredentialTypeUser) return NULL;
    rfbCredential *credential = calloc(1, sizeof(*credential));
    if (credential) {
        credential->userCredential.username = strdup(self.authUser.UTF8String);
        credential->userCredential.password = strdup(self.authPassword.UTF8String);
    }
    return credential;
}
- (void)connectAction:(id)sender {
    NSString *user = self.user.stringValue, *password = self.password.stringValue;
    if (!user.length || !password.length || [user lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 63 ||
        [password lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 63) {
        self.status.stringValue = @"Enter this Mac's account and password (at most 63 UTF-8 bytes each)."; return;
    }
    self.password.stringValue = @""; self.connect.enabled = NO;
    self.status.stringValue = @"Signing in to built-in Screen Sharing…";
    dispatch_async(self.queue, ^{
        self.authUser = user; self.authPassword = password;
        rfbClient *client = rfbGetClient(8, 3, 4);
        BOOL success = NO;
        if (client) {
            free(client->serverHost); client->serverHost = strdup("127.0.0.1");
            client->serverPort = 5900; client->connectTimeout = 5; client->readTimeout = 5;
            client->appData.shareDesktop = TRUE;
            client->GetCredential = Credential;
            rfbClientSetClientData(client, &ownerTag, (__bridge void *)self);
            uint32_t schemes[] = {rfbARD}; SetClientAuthSchemes(client, schemes, 1);
            // No framebuffer allocation, rendering, or capture is needed.
            success = ConnectToRFBServer(client, "127.0.0.1", 5900) && InitialiseRFBConnection(client);
            if (success) {
                client->width = client->si.framebufferWidth; client->height = client->si.framebufferHeight;
                // Complete normal client format/encoding setup. A zero-area update
                // runs the server's control-availability path without requesting pixels.
                success = SetFormatAndEncodings(client) && SendFramebufferUpdateRequest(client, 0, 0, 0, 0, FALSE);
            }
            if (!success) rfbClientCleanup(client);
        }
        self.authUser = nil; self.authPassword = nil;
        self.client = success ? client : NULL;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.test.enabled = success; self.connect.enabled = !success;
            self.status.stringValue = success ? @"Signed in. Verifying native magnification…" : @"Screen Sharing login failed. No gesture was sent.";
            printf("LOOPBACK_AUTH %s\n", success ? "OK" : "FAILED"); fflush(stdout);
            if (success) [self testAction:nil];
        });
    });
}
- (void)testAction:(id)sender {
    [self.window makeFirstResponder:self.receiver];
    appMagnifyCount = 0;
    self.receiver.verifying = YES;
    self.receiver.received = 0; self.receiver.scale = 1; self.receiver.needsDisplay = YES;
    self.test.enabled = NO;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        // Never deliver the probe gesture while another app or window is active.
        if (!NSApp.active || NSApp.keyWindow != self.window) {
            self.receiver.verifying = NO;
            self.status.stringValue = @"Verification cancelled because the probe is no longer active.";
            self.test.enabled = YES; return;
        }
        NSPoint point = [self.receiver convertPoint:NSMakePoint(NSMidX(self.receiver.bounds), NSMidY(self.receiver.bounds)) toView:nil];
        point = [self.window convertPointToScreen:point];
        // This first proof is deliberately limited to one display. Apple's agent
        // converts framebuffer pixels to AppKit points using its HiDPI mapping.
        if (NSScreen.screens.count != 1) {
            self.receiver.verifying = NO;
            self.status.stringValue = @"This bounded probe requires one display; multiple-display mapping needs a separate proof.";
            self.test.enabled = YES; return;
        }
        CGFloat primaryHeight = NSScreen.screens.firstObject.frame.size.height;
        CGFloat primaryWidth = NSScreen.screens.firstObject.frame.size.width;
        CGFloat top = primaryHeight - point.y;
        self.status.stringValue = @"Sending a bounded pinch to the test square…";
        dispatch_async(self.queue, ^{
            rfbClient *client = self.client;
            CGFloat actualX = client ? point.x * client->width / primaryWidth : -1;
            CGFloat actualY = client ? top * client->height / primaryHeight : -1;
            if (!client || actualX < 0 || actualY < 0 || actualX >= client->width || actualY >= client->height) {
                dispatch_async(dispatch_get_main_queue(), ^{ self.receiver.verifying = NO; self.status.stringValue = @"Test square is outside the shared display."; self.test.enabled = YES; }); return;
            }
            uint16_t x = (uint16_t)actualX, y = (uint16_t)actualY;
            uint16_t version = (uint16_t)self.wireVersion;
            BOOL success = SendFramebufferUpdateRequest(client, 0, 0, 0, 0, FALSE) &&
                SendPointerEvent(client, x, y, 0);
            // First check ordinary input reaches this same view. No click or key.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                NSPoint mouse = NSEvent.mouseLocation;
                BOOL reached = fabs(mouse.x - point.x) < 12 && fabs(mouse.y - point.y) < 12;
                printf("POINTER_REACHED_OWN_VIEW %s\n", reached ? "YES" : "NO"); fflush(stdout);
            });
            [NSThread sleepForTimeInterval:.25];
            success = success && SendBoundary(client, 1, x, y);
            success = success && SendMagnification(client, version, 0, 1, x, y);
            for (int i = 0; success && i < 3; i++) {
                [NSThread sleepForTimeInterval:.08];
                success = SendMagnification(client, version, .05, 2, x, y);
            }
            // Balance the gesture even if an update failed.
            BOOL ended = SendMagnification(client, version, 0, 4, x, y);
            BOOL boundaryEnded = SendBoundary(client, 2, x, y);
            printf("GESTURE_SEND version=%u %s\n", version, success && ended && boundaryEnded ? "OK" : "FAILED"); fflush(stdout);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                self.receiver.verifying = NO;
                self.test.enabled = YES;
                if (!self.receiver.received) self.status.stringValue = appMagnifyCount ?
                    @"Native magnification reached the app, but did not reach the blue test view. Checking gesture routing." :
                    @"The test view received no magnification. Socket writes alone do not prove delivery.";
            });
        });
    });
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }
- (void)applicationWillTerminate:(NSNotification *)notification {
    dispatch_sync(self.queue, ^{ if (self.client) rfbClientCleanup(self.client); self.client = NULL; });
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        [ProbeApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        Probe *delegate = [Probe new]; NSApp.delegate = delegate; [NSApp run];
    }
    return 0;
}
