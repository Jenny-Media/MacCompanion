#import <XCTest/XCTest.h>
#import <CompanionMoonlightEngine/CompanionMoonlightVideo.h>
#include "CompanionNativeSurfaceEpoch.h"

@interface CompanionMoonlightVideo (LocalEpochGateTest)
- (BOOL)acceptPicture:(const unsigned char *)data length:(size_t)length independent:(BOOL *)independent;
@end

// Inert transport: exercises the local gate without starting native sockets,
// capturing a screen or constructing any authorization or pairing proof.
@interface CompanionEpochGateTestSession : CompanionMoonlightVideo
@end
@implementation CompanionEpochGateTestSession
- (BOOL)presentationReady { return YES; }
@end

@interface CompanionMoonlightVideoTests : XCTestCase
@end

@implementation CompanionMoonlightVideoTests
- (void)testReplacementEpochFencesOldAndUnmarkedPicturesWithoutStartingConnection {
    NSURL *fixtureURL = [[NSBundle bundleForClass:self.class] URLForResource:@"native-stream-continuity-v0.1" withExtension:@"json"];
    XCTAssertNotNil(fixtureURL);
    NSDictionary *fixture = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:fixtureURL] options:0 error:nil];
    NSString *hex = fixture[@"epoch"][@"bytesHex"];
    XCTAssertEqual(hex.length,96U);
    uint8_t bytes[48];
    for (NSUInteger index = 0; index < 48; index++) {
        unsigned byte = 0;
        XCTAssertEqual(sscanf([[hex substringWithRange:NSMakeRange(index*2,2)] UTF8String],"%2x",&byte),1);
        bytes[index] = (uint8_t)byte;
    }
    CompanionNativeSurfaceEpoch epoch;
    XCTAssertTrue(CompanionNativeEpochDecode(bytes,48,&epoch));
    CompanionEpochGateTestSession *session = [[CompanionEpochGateTestSession alloc] initWithConfiguration:[self configuration]
        view:[UIView new] event:^(CompanionMoonlightVideoEvent event, int code) { XCTFail(@"Inert gate emitted a transport event"); } error:nil];
    // KVC sets only the test's inert transport state; no native start is called.
    [session setValue:@YES forKey:@"started"];
    uint8_t frame[192]; BOOL independent = NO;
    size_t size = CompanionNativeEpochSEI(&epoch,false,frame,sizeof(frame));
    const uint8_t idr[] = {0,0,0,1,0x65,0xb8};
    memcpy(frame+size,idr,sizeof(idr)); size += sizeof(idr);
    XCTAssertTrue([session beginSurfaceReplacement:nil]);
    XCTAssertFalse([session acceptPicture:frame length:size independent:&independent], @"Frames before fresh epoch configuration must be dropped");
    XCTAssertFalse([session beginSurfaceReplacement:nil], @"Only one replacement may be in flight");
    XCTAssertTrue([session resumeSurfaceReplacementWithEpoch:[NSData dataWithBytes:bytes length:48] error:nil]);
    XCTAssertFalse([session resumeSurfaceReplacementWithEpoch:[NSData dataWithBytes:bytes length:48] error:nil]);
    XCTAssertFalse([session acceptPicture:idr length:sizeof(idr) independent:&independent]);
    XCTAssertTrue([session acceptPicture:frame length:size independent:&independent]);
    XCTAssertTrue(independent);
    CompanionNativeSurfaceEpoch stale = epoch; stale.surfaceRevision++;
    size = CompanionNativeEpochSEI(&stale,false,frame,sizeof(frame));
    memcpy(frame+size,idr,sizeof(idr)); size += sizeof(idr);
    XCTAssertFalse([session acceptPicture:frame length:size independent:&independent]);
    XCTAssertEqual(session.queuedVideoFrameCount,0U, @"Codec observation must not enqueue or authorize a picture");
    [session setValue:@NO forKey:@"started"];
    [session stopWithCompletion:^{}];
}
- (CompanionMoonlightVideoConfiguration *)configuration {
    CompanionMoonlightVideoConfiguration *config = [CompanionMoonlightVideoConfiguration new];
    config.host = @"127.0.0.1";
    config.appVersion = @"7.1.431.0";
    config.serverCodecModeSupport = 1;
    config.sessionURL = @"rtsp://127.0.0.1:9";
    config.streamKey = [NSMutableData dataWithLength:16];
    config.streamKeyID = 1;
    config.width = 1280;
    config.height = 720;
    config.framesPerSecond = 60;
    config.bitrateKbps = 10000;
    return config;
}

- (void)testRejectsEndpointSubstitutionAndInvalidKey {
    XCTAssertTrue(NSThread.isMainThread);
    CompanionMoonlightVideoConfiguration *config = [self configuration];
    config.sessionURL = @"rtsp://192.0.2.1:9";
    NSError *error;
    XCTAssertNil([[CompanionMoonlightVideo alloc] initWithConfiguration:config view:[UIView new]
        event:^(CompanionMoonlightVideoEvent event, int code) { XCTFail(@"Invalid configuration emitted callback"); } error:&error]);
    XCTAssertEqual(error.code, 1);
    config.sessionURL = @"rtsp:missing-host";
    XCTAssertNil([[CompanionMoonlightVideo alloc] initWithConfiguration:config view:[UIView new]
        event:^(CompanionMoonlightVideoEvent event, int code) { XCTFail(@"Missing host emitted callback"); } error:&error]);
    config.sessionURL = @"rtsp://127.0.0.1:9";
    config.serverCodecModeSupport = 0;
    XCTAssertNil([[CompanionMoonlightVideo alloc] initWithConfiguration:config view:[UIView new]
        event:^(CompanionMoonlightVideoEvent event, int code) { XCTFail(@"Missing codec metadata emitted callback"); } error:&error]);
    config.serverCodecModeSupport = 1;
    config.streamKey = [NSMutableData dataWithLength:15];
    XCTAssertNil([[CompanionMoonlightVideo alloc] initWithConfiguration:config view:[UIView new]
        event:^(CompanionMoonlightVideoEvent event, int code) { XCTFail(@"Invalid configuration emitted callback"); } error:&error]);
}

- (void)testStopDuringStartupDrainsBeforeReplacementAndSuppressesCallbacks {
    XCTestExpectation *drained = [self expectationWithDescription:@"Startup interrupted and drained"];
    __block CompanionMoonlightVideo *replacement;
    CompanionMoonlightVideo *first = [[CompanionMoonlightVideo alloc] initWithConfiguration:[self configuration] view:[UIView new]
        event:^(CompanionMoonlightVideoEvent event, int code) { XCTFail(@"Retired startup callback reached UI"); } error:nil];
    replacement = [[CompanionMoonlightVideo alloc] initWithConfiguration:[self configuration] view:[UIView new]
        event:^(CompanionMoonlightVideoEvent event, int code) { XCTFail(@"Retired replacement callback reached UI"); } error:nil];
    XCTAssertTrue([first start:nil]);
    NSError *busy;
    XCTAssertFalse([replacement start:&busy]);
    XCTAssertEqual(busy.code, 3);
    [first stopWithCompletion:^{
        XCTAssertTrue(NSThread.isMainThread);
        XCTAssertTrue([replacement start:nil]);
        [replacement stopWithCompletion:^{ [drained fulfill]; }];
    }];
    [self waitForExpectations:@[drained] timeout:10];
    NSError *retired;
    XCTAssertFalse([first start:&retired]);
    XCTAssertEqual(retired.code, 2);
}

- (void)testStopBeforeStartIsTerminal {
    CompanionMoonlightVideo *session = [[CompanionMoonlightVideo alloc] initWithConfiguration:[self configuration] view:[UIView new]
        event:^(CompanionMoonlightVideoEvent event, int code) { XCTFail(@"Stopped session emitted callback"); } error:nil];
    __block BOOL completed = NO;
    [session stopWithCompletion:^{ completed = YES; }];
    XCTAssertTrue(completed);
    XCTAssertFalse([session start:nil]);
}

- (void)testConnectionFailureDrainsAndAllowsNewSession {
    XCTestExpectation *drained = [self expectationWithDescription:@"Native failed startup drained"];
    __block CompanionMoonlightVideo *session;
    __block BOOL stopping = NO;
    session = [[CompanionMoonlightVideo alloc] initWithConfiguration:[self configuration] view:[UIView new]
        event:^(CompanionMoonlightVideoEvent event, int code) {
            XCTAssertTrue(NSThread.isMainThread);
            XCTAssertFalse(stopping, @"Retired session delivered a callback");
            XCTAssertEqual(event, CompanionMoonlightVideoEventFailed);
            XCTAssertNotEqual(code, 0);
            stopping = YES;
            [session stopWithCompletion:^{
                CompanionMoonlightVideo *next = [[CompanionMoonlightVideo alloc] initWithConfiguration:[self configuration]
                    view:[UIView new] event:^(CompanionMoonlightVideoEvent event, int code) {
                        XCTFail(@"Stopped replacement emitted callback");
                    } error:nil];
                XCTAssertTrue([next start:nil]);
                [next stopWithCompletion:^{ [drained fulfill]; }];
                session = nil;
            }];
        } error:nil];
    XCTAssertTrue([session start:nil]);
    [self waitForExpectations:@[drained] timeout:20];
}
@end
