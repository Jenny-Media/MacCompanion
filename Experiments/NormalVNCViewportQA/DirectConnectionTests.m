#import <XCTest/XCTest.h>
#import "CompanionVNCSession.h"
#import "CompanionVNCViewer.h"
#import "CompanionVNCDirectConnection.h"
#import "CompanionVNCDisplayLayout.h"
#import <sys/socket.h>
#import <unistd.h>
#import <rfb/rfbclient.h>

@interface CompanionVNCSession (DisplayTests)
- (rfbBool)displayLayout:(rfbClient *)client;
- (void)configureClient:(rfbClient *)client;
@end

@interface DirectConnectionTests : XCTestCase
@end
@implementation DirectConnectionTests
- (void)testProductionLibraryAdvertisesAndDispatchesDisplayMetadata {
    NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:@"direct-screen-sharing-v1" withExtension:@"json"];
    NSDictionary *profile = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
    NSString *hex = profile[@"displayLayoutCases"][0][@"bodyHex"];
    NSMutableData *body = [NSMutableData new];
    for (NSUInteger i = 0; i < hex.length; i += 2) {
        unsigned value = 0; [[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i, 2)]] scanHexInt:&value];
        uint8_t byte = value; [body appendBytes:&byte length:1];
    }
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, pair), 0);
    struct timeval timeout = {.tv_sec = 1}; setsockopt(pair[1], SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    rfbClient *client = rfbGetClient(8, 3, 4); client->sock = pair[0]; client->width = 4072; client->height = 1067;
    CompanionVNCSession *session = [CompanionVNCSession new]; [session configureClient:client]; [session setValue:@YES forKey:@"running"];
    client->supportedMessages.client2server[0] |= (1 << rfbSetPixelFormat) | (1 << rfbSetEncodings) | (1 << rfbFramebufferUpdateRequest);
    XCTAssertTrue(SetFormatAndEncodings(client));
    uint8_t format[20], header[4], encodings[MAX_ENCODINGS * 4];
    XCTAssertEqual(recv(pair[1], format, sizeof(format), MSG_WAITALL), sizeof(format));
    XCTAssertEqual(recv(pair[1], header, sizeof(header), MSG_WAITALL), sizeof(header));
    size_t count = CompanionVNCBE16(header + 2); XCTAssertLessThanOrEqual(count, MAX_ENCODINGS);
    XCTAssertEqual(recv(pair[1], encodings, count * 4, MSG_WAITALL), count * 4);
    NSMutableArray *vendor = [NSMutableArray new];
    for (size_t i = 0; i < count; i++) {
        uint32_t value = CompanionVNCBE32(encodings + i * 4);
        if (value == 1101 || value == 1105) [vendor addObject:@(value)];
    }
    XCTAssertEqualObjects(vendor, profile[@"displayMetadataNegotiation"][@"requiredEncodingsInOrder"]);
    XCTestExpectation *delivered = [self expectationWithDescription:@"Real library extension dispatch"];
    session.displayLayoutHandler = ^(NSDictionary *layout) { XCTAssertEqual([layout[@"views"] count], 2); [delivered fulfill]; };
    const uint8_t message[] = {0, 0, 0, 1, 0, 0, 0, 0, 0x0f, 0xe8, 0x04, 0x2b, 0, 0, 4, 0x51};
    const uint8_t length[] = {(uint8_t)(body.length >> 8), (uint8_t)body.length};
    uint8_t legacy[sizeof(message)]; memcpy(legacy, message, sizeof(message)); legacy[15] = 0x4d;
    write(pair[1], legacy, sizeof(legacy)); write(pair[1], length, 2); write(pair[1], body.bytes, body.length);
    XCTAssertTrue(HandleRFBServerMessage(client)); // legacy body is consumed without publishing geometry
    write(pair[1], message, sizeof(message)); write(pair[1], length, 2); write(pair[1], body.bytes, body.length);
    XCTAssertTrue(HandleRFBServerMessage(client));
    [self waitForExpectations:@[delivered] timeout:1];
    [session stop]; [session setValue:@NO forKey:@"running"]; session.displayLayoutHandler = nil;
    close(pair[1]); rfbClientCleanup(client);
}
- (void)testNativeDisplayMetadataConsumesOnlyItsBodyAndDropsRetiredCallbacks {
    NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:@"direct-screen-sharing-v1" withExtension:@"json"];
    NSDictionary *profile = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
    NSString *hex = profile[@"displayLayoutCases"][0][@"bodyHex"];
    NSMutableData *body = [NSMutableData new];
    for (NSUInteger i = 0; i < hex.length; i += 2) {
        unsigned value = 0; [[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i, 2)]] scanHexInt:&value];
        uint8_t byte = value; [body appendBytes:&byte length:1];
    }
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, pair), 0);
    rfbClient *client = rfbGetClient(8, 3, 4); client->sock = pair[0];
    CompanionVNCSession *session = [CompanionVNCSession new]; [session setValue:@YES forKey:@"running"];
    uint8_t prefix[2] = {(uint8_t)(body.length >> 8), (uint8_t)body.length};
    write(pair[1], prefix, 2); write(pair[1], body.bytes, body.length); write(pair[1], "X", 1);
    XCTestExpectation *layout = [self expectationWithDescription:@"Native display metadata"];
    session.displayLayoutHandler = ^(NSDictionary *value) {
        XCTAssertEqual([value[@"views"] count], 2);
        XCTAssertEqualObjects(value[@"views"][1][@"id"], @2);
        XCTAssertEqualWithAccuracy([value[@"aspectRatio"] doubleValue], 4072.0 / 1067, .000001);
        [layout fulfill];
    };
    XCTAssertTrue([session displayLayout:client]);
    char next; XCTAssertTrue(ReadFromRFBServer(client, &next, 1)); XCTAssertEqual(next, 'X');
    [self waitForExpectations:@[layout] timeout:1];
    XCTestExpectation *retired = [self expectationWithDescription:@"Stopped owner drops display metadata"]; retired.inverted = YES;
    session.displayLayoutHandler = ^(NSDictionary *value) { [retired fulfill]; };
    write(pair[1], prefix, 2); write(pair[1], body.bytes, body.length);
    XCTAssertTrue([session displayLayout:client]); [session stop];
    [self waitForExpectations:@[retired] timeout:.1];
    [session setValue:@NO forKey:@"running"]; session.displayLayoutHandler = nil;
    close(pair[1]); rfbClientCleanup(client);
}
- (NSString *)syntheticLogin {
    NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:@"direct-screen-sharing-v1" withExtension:@"json"];
    NSDictionary *p = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
    return p[@"loginCases"][0][@"value"];
}
- (void)testNativeClientRejectsNoAuthentication {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, pair), 0);
    int peer = pair[1];
    int yes = 1; setsockopt(pair[1], SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        write(peer, "RFB 003.008\n", 12);
        char version[12]; recv(peer, version, 12, MSG_WAITALL);
        const char noAuth[2] = {1, 1}; write(peer, noAuth, 2);
        char reply; recv(peer, &reply, 1, 0); close(peer);
    });
    CompanionVNCSession *session = [CompanionVNCSession new];
    XCTestExpectation *ended = [self expectationWithDescription:@"Unauthenticated peer rejected"];
    __weak CompanionVNCSession *weakSession = session;
    session.stateHandler = ^(NSString *state, NSDictionary *stats) {
        XCTAssertNotEqualObjects(state, @"Connected");
        // Several queued status reports can observe the same terminal owner.
        // Consume this one-shot expectation before fulfilling it.
        if (!weakSession.running) {
            XCTAssertEqualObjects(stats[@"credentialRequests"], @0);
            weakSession.stateHandler = nil; [ended fulfill];
        }
    };
    [session connectSocket:pair[0] username:[self syntheticLogin] password:[self syntheticLogin]];
    [self waitForExpectations:@[ended] timeout:3]; session.stateHandler = nil;
}
- (void)testStopInterruptsStalledHandshake {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, pair), 0);
    CompanionVNCSession *session = [CompanionVNCSession new];
    XCTestExpectation *ended = [self expectationWithDescription:@"Stalled handshake cancelled"];
    session.stateHandler = ^(NSString *state, NSDictionary *stats) {
        XCTAssertNotEqualObjects(state, @"Connected");
        if (!session.running) [ended fulfill];
    };
    [session connectSocket:pair[0] username:[self syntheticLogin] password:[self syntheticLogin]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [session stop]; });
    [self waitForExpectations:@[ended] timeout:2]; close(pair[1]); session.stateHandler = nil;
}
- (void)testRetiredViewerOwnerCannotDeliverStatusIntoReplacement {
    CompanionVNCViewer *viewer = [CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    CompanionVNCSession *old = viewer.session;
    void (^late)(NSString *, NSDictionary *) = [old.stateHandler copy];
    [viewer prepareConnection];
    __block BOOL disconnected = NO; viewer.disconnectHandler = ^{ disconnected = YES; };
    late(@"Disconnected", @{});
    XCTAssertFalse(disconnected); XCTAssertNotEqual(viewer.session, old);
}
- (void)testDirectScreenSharingGreetingWithoutCompanionHost {
    XCTestExpectation *greeting = [self expectationWithDescription:@"Built-in Screen Sharing responds directly"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int fd = CompanionVNCConnectLocal(@"127.0.0.1", ^{ return NO; }, ^BOOL(int value) { return YES; });
        XCTAssertGreaterThanOrEqual(fd, 0);
        if (fd >= 0) {
            struct timeval timeout = {.tv_sec = 2}; setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
            char bytes[12] = {0}; XCTAssertEqual(recv(fd, bytes, 12, MSG_WAITALL), 12);
            XCTAssertEqual(memcmp(bytes, "RFB ", 4), 0); close(fd);
        }
        // No authentication response, real credential, framebuffer or input request.
        [greeting fulfill];
    });
    [self waitForExpectations:@[greeting] timeout:20];
}
@end
