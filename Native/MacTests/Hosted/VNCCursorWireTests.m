#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "CompanionVNCSession.h"
#import <rfb/rfbclient.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <unistd.h>

@interface CompanionVNCSession (NativeCursorWireDiagnosis)
- (void)configureClient:(rfbClient *)client;
- (void)publishCursor;
@end

@interface VNCCursorWireTests : XCTestCase
@end
@implementation VNCCursorWireTests
- (NSDictionary *)profile {
    NSString *root = NSProcessInfo.processInfo.environment[@"MACCOMPANION_NATIVE_FIXTURE_DIRECTORY"];
    XCTAssertNotNil(root);
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:
        [NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"manifest.json"]] options:0 error:NULL];
    NSDictionary *entry = nil;
    for (NSDictionary *candidate in manifest[@"fixtures"]) {
        if ([candidate[@"path"] isEqual:@"vnc-desktop-tunnel-v0.1.json"]) entry = candidate;
    }
    XCTAssertEqualObjects(entry[@"expect"], @"valid");
    return [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:
        [root stringByAppendingPathComponent:entry[@"path"]]] options:0 error:NULL];
}
- (rfbClient *)clientFor:(CompanionVNCSession *)session peer:(int *)peer {
    int sockets[2]; XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, sockets), 0);
    struct timeval timeout = {1, 0}; setsockopt(sockets[1], SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    rfbClient *client = rfbGetClient(8, 3, 4);
    [session configureClient:client]; client->sock = sockets[0]; *peer = sockets[1];
    client->width = 100; client->height = 100;
    [session setValue:@YES forKey:@"running"];
    return client;
}
- (void)testActualSetEncodingsRequestsCursorShapesDespiteExplicitPixelEncodingList {
    CompanionVNCSession *session = [CompanionVNCSession new]; int peer;
    rfbClient *client = [self clientFor:session peer:&peer];
    // The handshake normally establishes these standard supported-message bits.
    client->supportedMessages.client2server[rfbSetPixelFormat / 8] |= 1 << (rfbSetPixelFormat % 8);
    client->supportedMessages.client2server[rfbSetEncodings / 8] |= 1 << (rfbSetEncodings % 8);
    XCTAssertTrue(SetFormatAndEncodings(client));
    uint8_t format[sz_rfbSetPixelFormatMsg], header[sz_rfbSetEncodingsMsg];
    XCTAssertEqual(recv(peer, format, sizeof(format), MSG_WAITALL), sizeof(format));
    XCTAssertEqual(format[0], rfbSetPixelFormat); XCTAssertEqual(format[4], 32);
    XCTAssertEqual(format[6], 0); XCTAssertEqual(format[14], 16); XCTAssertEqual(format[15], 8); XCTAssertEqual(format[16], 0);
    XCTAssertEqual(recv(peer, header, sizeof(header), MSG_WAITALL), sizeof(header));
    XCTAssertEqual(header[0], rfbSetEncodings);
    NSUInteger count = ((NSUInteger)header[2] << 8) | header[3]; XCTAssertLessThan(count, 128);
    NSMutableArray *actual = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; i++) {
        uint32_t encoding; XCTAssertEqual(recv(peer, &encoding, 4, MSG_WAITALL), 4);
        [actual addObject:@((int32_t)ntohl(encoding))];
    }
    for (NSNumber *encoding in [self profile][@"cursorNegotiationEncodings"]) XCTAssertTrue([actual containsObject:encoding]);
    [session setValue:@NO forKey:@"running"]; rfbClientCleanup(client); close(peer);
}
- (NSData *)updateFor:(NSDictionary *)vector {
    NSArray *size = vector[@"size"], *hot = vector[@"hotspot"];
    uint16_t x = [hot[0] unsignedShortValue], y = [hot[1] unsignedShortValue];
    uint16_t w = [size[0] unsignedShortValue], h = [size[1] unsignedShortValue];
    uint32_t encoding = htonl((uint32_t)[vector[@"encoding"] intValue]);
    uint8_t prefix[] = {rfbFramebufferUpdate, 0, 0, 1, x >> 8, x & 255, y >> 8, y & 255,
                       w >> 8, w & 255, h >> 8, h & 255};
    NSMutableData *data = [NSMutableData dataWithBytes:prefix length:sizeof(prefix)];
    [data appendBytes:&encoding length:4];
    for (NSNumber *number in vector[@"payload"]) { uint8_t value = number.unsignedCharValue; [data appendBytes:&value length:1]; }
    return data;
}
- (void)assertImage:(NSImage *)image vector:(NSDictionary *)vector {
    if (!image) { XCTFail(@"Decoded cursor image is missing"); return; }
    CGImageRef cg = [image CGImageForProposedRect:NULL context:nil hints:nil];
    NSArray *size = vector[@"size"], *expected = vector[@"rgba"];
    XCTAssertEqual(CGImageGetWidth(cg), [size[0] unsignedIntegerValue]);
    XCTAssertEqual(CGImageGetHeight(cg), [size[1] unsignedIntegerValue]);
    NSData *pixels = CFBridgingRelease(CGDataProviderCopyData(CGImageGetDataProvider(cg)));
    XCTAssertEqual(pixels.length, expected.count);
    const uint8_t *bytes = pixels.bytes;
    for (NSUInteger i = 0; i < expected.count; i++) XCTAssertEqual(bytes[i], [expected[i] unsignedCharValue]);
}
- (void)testActualXCursorAndRichCursorMessagesReachNativeImagesWithoutVideoUpdates {
    for (NSDictionary *vector in [self profile][@"cursorWireCases"]) {
        CompanionVNCSession *session = [CompanionVNCSession new]; int peer;
        rfbClient *client = [self clientFor:session peer:&peer];
        XCTestExpectation *shape = [self expectationWithDescription:vector[@"name"]];
        session.cursorHandler = ^(NSImage *image, CGPoint hotspot, CGPoint position, BOOL known) {
            XCTAssertNotNil(image); [self assertImage:image vector:vector];
            XCTAssertEqual(hotspot.x, [vector[@"hotspot"][0] doubleValue]);
            XCTAssertEqual(hotspot.y, [vector[@"hotspot"][1] doubleValue]); XCTAssertFalse(known);
            [shape fulfill];
        };
        session.frameHandler = ^(NSImage *image) { XCTFail(@"Cursor messages must not fabricate framebuffer updates"); };
        NSData *packet = [self updateFor:vector]; XCTAssertEqual(send(peer, packet.bytes, packet.length, 0), packet.length);
        XCTAssertTrue(HandleRFBServerMessage(client)); [session publishCursor];
        [self waitForExpectations:@[shape] timeout:1];
        session.cursorHandler = nil; session.frameHandler = nil;
        [session setValue:@NO forKey:@"running"]; rfbClientCleanup(client); close(peer);
    }
}
- (void)testInvalidHotspotClearsShapeAndStoppedPresentationIsFenced {
    CompanionVNCSession *session = [CompanionVNCSession new]; int peer;
    rfbClient *client = [self clientFor:session peer:&peer];
    NSMutableDictionary *vector = [[self profile][@"cursorWireCases"][0] mutableCopy];
    vector[@"hotspot"] = @[@99, @0];
    XCTestExpectation *fallback = [self expectationWithDescription:@"Invalid shape uses local fallback"];
    session.cursorHandler = ^(NSImage *image, CGPoint hotspot, CGPoint position, BOOL known) {
        XCTAssertNil(image); XCTAssertTrue(CGPointEqualToPoint(hotspot, CGPointZero)); [fallback fulfill];
    };
    NSData *packet = [self updateFor:vector]; XCTAssertEqual(send(peer, packet.bytes, packet.length, 0), packet.length);
    XCTAssertTrue(HandleRFBServerMessage(client)); [session publishCursor];
    [self waitForExpectations:@[fallback] timeout:1];
    session.cursorHandler = ^(NSImage *image, CGPoint hotspot, CGPoint position, BOOL known) { XCTFail(@"Stopped cursor callback must be fenced"); };
    vector[@"hotspot"] = @[@1, @0]; packet = [self updateFor:vector];
    XCTAssertEqual(send(peer, packet.bytes, packet.length, 0), packet.length);
    XCTAssertTrue(HandleRFBServerMessage(client)); [session publishCursor]; [session stop];
    XCTestExpectation *turn = [self expectationWithDescription:@"Drain queued presentation"];
    dispatch_async(dispatch_get_main_queue(), ^{ [turn fulfill]; });
    [self waitForExpectations:@[turn] timeout:1];
    session.cursorHandler = nil; rfbClientCleanup(client); close(peer);
}
- (void)testEmptyCursorWireReportsClearAPreviouslyValidShape {
    NSDictionary *profile = [self profile];
    for (NSDictionary *sequence in profile[@"cursorWireSequences"]) {
        NSDictionary *initial = nil;
        for (NSDictionary *candidate in profile[@"cursorWireCases"]) {
            if ([candidate[@"name"] isEqual:sequence[@"initialCase"]]) initial = candidate;
        }
        XCTAssertNotNil(initial);
        CompanionVNCSession *session = [CompanionVNCSession new]; int peer;
        rfbClient *client = [self clientFor:session peer:&peer];
        XCTestExpectation *valid = [self expectationWithDescription:@"Initial cursor"];
        session.cursorHandler = ^(NSImage *image, CGPoint hotspot, CGPoint position, BOOL known) {
            XCTAssertNotNil(image); [self assertImage:image vector:initial]; [valid fulfill];
        };
        NSData *packet = [self updateFor:initial];
        XCTAssertEqual(send(peer, packet.bytes, packet.length, 0), packet.length);
        XCTAssertTrue(HandleRFBServerMessage(client)); [session publishCursor];
        [self waitForExpectations:@[valid] timeout:1];
        XCTestExpectation *cleared = [self expectationWithDescription:sequence[@"name"]];
        session.cursorHandler = ^(NSImage *image, CGPoint hotspot, CGPoint position, BOOL known) {
            XCTAssertNil(image); XCTAssertTrue(CGPointEqualToPoint(hotspot, CGPointZero)); [cleared fulfill];
        };
        packet = [self updateFor:sequence[@"clear"]];
        XCTAssertEqual(send(peer, packet.bytes, packet.length, 0), packet.length);
        XCTAssertTrue(HandleRFBServerMessage(client)); [session publishCursor];
        [self waitForExpectations:@[cleared] timeout:1];
        session.cursorHandler = nil; [session setValue:@NO forKey:@"running"]; rfbClientCleanup(client); close(peer);
    }
}
@end
