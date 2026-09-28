#import <XCTest/XCTest.h>
#import <CompanionMoonlightEngine/CompanionMoonlightVideo.h>

@interface CompanionMoonlightVideoTests : XCTestCase
@end

@implementation CompanionMoonlightVideoTests
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
