#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>
#import "CompanionVNCSession.h"
#import <rfb/rfbclient.h>

@interface CompanionVNCSession (NativeMacFrameDiagnosis)
- (void)configureClient:(rfbClient *)client;
- (rfbBool)allocate:(rfbClient *)client;
- (void)publishFrame:(rfbClient *)client;
- (void)report:(NSString *)state;
@end

@interface VNCFrameTests : XCTestCase
@end
@implementation VNCFrameTests
- (void)testAuthenticatedInputOnlyReportsConnectedWithoutPresentingPixels {
    CompanionVNCSession *session = [CompanionVNCSession new];
    session.inputOnly = YES;
    [session setValue:@YES forKey:@"running"];
    [session setValue:@YES forKey:@"inputReady"];
    XCTestExpectation *ready = [self expectationWithDescription:@"Trackpad readiness without pixels"];
    session.stateHandler = ^(NSString *state, NSDictionary *counters) {
        XCTAssertEqualObjects(state, @"Connected");
        XCTAssertEqualObjects(counters[@"baselineReady"], @NO);
        XCTAssertEqualObjects(counters[@"presentedFrames"], @0);
        [ready fulfill];
    };
    [session report:@"Connected"];
    [self waitForExpectations:@[ready] timeout:1];
    session.inputOnly = NO;
    XCTestExpectation *desktop = [self expectationWithDescription:@"Desktop still waits for pixels"]; desktop.inverted = YES;
    session.stateHandler = ^(NSString *state, NSDictionary *counters) { [desktop fulfill]; };
    [session report:@"Connected"];
    [self waitForExpectations:@[desktop] timeout:.05];
    session.stateHandler = nil; [session setValue:@NO forKey:@"running"];
}
- (void)testNativeNSImageContainsCompleteRFBPixelsAndResizeWaitsForNewBaseline {
    CompanionVNCSession *session = [CompanionVNCSession new];
    rfbClient *client = rfbGetClient(8, 3, 4);
    [session configureClient:client]; client->width = 2; client->height = 2;
    XCTAssertTrue([session allocate:client]); [session setValue:@YES forKey:@"running"];
    for (NSUInteger i = 0; i < 16; i += 4) { client->frameBuffer[i] = 0; client->frameBuffer[i + 1] = 0; client->frameBuffer[i + 2] = 255; }
    XCTestExpectation *frame = [self expectationWithDescription:@"Native red image"];
    session.frameHandler = ^(NSImage *image) {
        CGImageRef cg = [image CGImageForProposedRect:NULL context:nil hints:nil];
        XCTAssertEqual(CGImageGetWidth(cg), 2); XCTAssertEqual(CGImageGetHeight(cg), 2);
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithCGImage:cg];
        NSColor *pixel = [[bitmap colorAtX:0 y:0] colorUsingColorSpace:NSColorSpace.deviceRGBColorSpace];
        XCTAssertGreaterThan(pixel.redComponent, .99); XCTAssertLessThan(pixel.blueComponent, .01);
        [frame fulfill];
    };
    client->GotFrameBufferUpdate(client, 0, 0, 2, 2); [session publishFrame:client];
    [self waitForExpectations:@[frame] timeout:1];
    XCTAssertEqualObjects([session valueForKey:@"baselinePresented"], @YES);
    client->width = 4; client->height = 4; XCTAssertTrue([session allocate:client]);
    XCTestExpectation *incomplete = [self expectationWithDescription:@"Resize needs complete pixels"]; incomplete.inverted = YES;
    session.frameHandler = ^(NSImage *image) { [incomplete fulfill]; };
    client->GotFrameBufferUpdate(client, 0, 0, 4, 1); [session publishFrame:client];
    [self waitForExpectations:@[incomplete] timeout:.05];
    XCTAssertEqualObjects([session valueForKey:@"baselinePresented"], @NO);
    session.frameHandler = nil; [session setValue:@NO forKey:@"running"];
    client->frameBuffer = NULL; rfbClientCleanup(client);
}
- (void)testStoppedGenerationCannotDeliverQueuedNativeImage {
    CompanionVNCSession *session = [CompanionVNCSession new];
    rfbClient *client = rfbGetClient(8, 3, 4);
    [session configureClient:client]; client->width = 2; client->height = 2;
    XCTAssertTrue([session allocate:client]); [session setValue:@YES forKey:@"running"];
    XCTestExpectation *late = [self expectationWithDescription:@"Stopped image is fenced"]; late.inverted = YES;
    session.frameHandler = ^(NSImage *image) { [late fulfill]; };
    client->GotFrameBufferUpdate(client, 0, 0, 2, 2); [session publishFrame:client]; [session stop];
    [self waitForExpectations:@[late] timeout:.05];
    session.frameHandler = nil; client->frameBuffer = NULL; rfbClientCleanup(client);
}
@end
