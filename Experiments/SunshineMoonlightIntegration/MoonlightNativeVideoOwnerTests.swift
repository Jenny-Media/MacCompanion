import CompanionClientPlatform
import CompanionInteractiveShared
import CompanionMoonlightEngine
@testable import CompanionMoonlightAdapter
import XCTest
import UIKit

@MainActor
private final class ControlledNativeDriver: UIKitClientNativeVideoDriverV0 {
    var event: (@MainActor (UIKitClientNativeVideoEventV0) -> Void)?
    var view: UIView?
    var stops = 0
    var starts = 0
    func start(view: UIView, event: @escaping @MainActor (UIKitClientNativeVideoEventV0) -> Void) throws {
        starts += 1
        self.view = view
        self.event = event
    }
    func stop() async { stops += 1 }
}

@MainActor
private final class NativeOwnerTestClock {
    var now: UInt64 = 10
}

@MainActor
private final class NativeOwnerReference {
    weak var owner: UIKitClientNativeVideoOwnerV0?
}

@MainActor
final class MoonlightNativeVideoOwnerTests: XCTestCase {
    private func binding() throws -> InteractiveNativeVideoBindingV0 {
        try .init(hostID: UUID(), hostFingerprint: Data(repeating: 1, count: 32),
                  clientID: UUID(), primaryConnectionID: Data(repeating: 2, count: 16),
                  interactiveSessionID: UUID(), authorizationEpoch: 1,
                  grantRevision: 1, policyRevision: 1, controlGeneration: UUID(),
                  expiresAtMonotonicMilliseconds: 1000)
    }

    private func descriptor() throws -> InteractiveNativeVideoSurfaceV0 {
        try .init(surfaceID: UUID(), surfaceRevision: 1, coordinateSpaceRevision: 1,
                  encodedWidth: 1280, encodedHeight: 720)
    }

    private func surface() -> UIKitClientLiveSurfaceViewV0 {
        .init(mode: .directTouch, onPayloads: { _ in XCTFail("Unacknowledged native frame enabled input") },
              onFailure: { _ in XCTFail("Unexpected surface error") })
    }

    func testCurrentFrameDisplaysButCannotEnableKeyboardOrInput() async throws {
        let current = try binding(), driver = ControlledNativeDriver(), surface = surface()
        let owner = try UIKitClientNativeVideoOwnerV0(binding: current, descriptor: descriptor(),
            surface: surface, driver: driver, current: { current }, nowMonotonicMilliseconds: { 10 }, changed: { _, _ in })
        try owner.start()
        XCTAssertEqual(driver.view?.isHidden, true)
        driver.event?(.connected)
        XCTAssertEqual(owner.lifecycle.phase, .connected)
        driver.event?(.firstFrame(width: 1280, height: 720))
        XCTAssertEqual(owner.lifecycle.phase, .displaying)
        XCTAssertEqual(driver.view?.isHidden, false)
        surface.setInputEnabled(true)
        XCTAssertFalse(surface.isUserInteractionEnabled)
        surface.toggleSoftwareKeyboard()
        XCTAssertFalse(surface.isSoftwareKeyboardVisible)
        await owner.close()
        XCTAssertEqual(driver.stops, 1)
        XCTAssertFalse(surface.hasUnverifiedExternalVideo)
    }

    func testWrongDimensionsFailVisiblyAndDrain() async throws {
        let current = try binding(), driver = ControlledNativeDriver(), surface = surface()
        let owner = try UIKitClientNativeVideoOwnerV0(binding: current, descriptor: descriptor(),
            surface: surface, driver: driver, current: { current }, nowMonotonicMilliseconds: { 10 }, changed: { _, _ in })
        try owner.start()
        driver.event?(.connected)
        driver.event?(.firstFrame(width: 1920, height: 1080))
        XCTAssertEqual(owner.lifecycle.failure, .incompatibleFrame)
        XCTAssertEqual(driver.view?.isHidden, true)
        await owner.close()
        XCTAssertEqual(owner.lifecycle.failure, .incompatibleFrame)
        XCTAssertEqual(driver.stops, 1)
    }

    func testDecoderCannotRevealAFrameBeforeConnectionAdmission() async throws {
        let current = try binding(), driver = ControlledNativeDriver(), surface = surface()
        let owner = try UIKitClientNativeVideoOwnerV0(binding: current, descriptor: descriptor(),
            surface: surface, driver: driver, current: { current }, nowMonotonicMilliseconds: { 10 }, changed: { _, _ in })
        try owner.start()
        // Model a renderer that unhides its UIView immediately before callback.
        driver.view?.isHidden = false
        driver.event?(.firstFrame(width: 1280, height: 720))
        XCTAssertEqual(driver.view?.isHidden, true)
        XCTAssertEqual(owner.lifecycle.failure, .connectionFailed)
        await owner.close()
        XCTAssertEqual(driver.stops, 1)
    }

    func testAdmissionRevokedByStatusConsumerCannotStartDriver() async throws {
        let original = try binding(), driver = ControlledNativeDriver(), surface = surface()
        var current: InteractiveNativeVideoBindingV0? = original
        let owner = try UIKitClientNativeVideoOwnerV0(binding: original, descriptor: descriptor(),
            surface: surface, driver: driver, current: { current }, nowMonotonicMilliseconds: { 10 }, changed: { phase, _ in
                if phase == .connecting { current = nil }
            })
        XCTAssertThrowsError(try owner.start())
        XCTAssertEqual(driver.starts, 0)
        XCTAssertEqual(owner.lifecycle.failure, .authorizationLost)
        await owner.close()
    }

    func testRevocationBlanksBeforeNativeStopAndRejectsLateFrame() async throws {
        let original = try binding(), driver = ControlledNativeDriver(), surface = surface()
        var current: InteractiveNativeVideoBindingV0? = original
        let owner = try UIKitClientNativeVideoOwnerV0(binding: original, descriptor: descriptor(),
            surface: surface, driver: driver, current: { current }, nowMonotonicMilliseconds: { 10 }, changed: { _, _ in })
        try owner.start()
        driver.event?(.connected)
        driver.event?(.firstFrame(width: 1280, height: 720))
        current = nil
        owner.refresh()
        XCTAssertEqual(driver.view?.isHidden, true)
        XCTAssertEqual(owner.lifecycle.failure, .authorizationLost)
        driver.event?(.firstFrame(width: 1280, height: 720))
        await owner.close()
        XCTAssertEqual(driver.view?.isHidden, true)
        XCTAssertEqual(driver.stops, 1)
    }

    func testBackgroundImmediatelyRevokesAndCannotResumeDisplayedGeneration() async throws {
        let current = try binding(), driver = ControlledNativeDriver(), surface = surface()
        let owner = try UIKitClientNativeVideoOwnerV0(binding: current, descriptor: descriptor(),
            surface: surface, driver: driver, current: { current },
            nowMonotonicMilliseconds: { 10 }, changed: { _, _ in })
        try owner.start()
        driver.event?(.connected)
        driver.event?(.firstFrame(width: 1280, height: 720))
        XCTAssertEqual(owner.lifecycle.phase, .displaying)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertEqual(owner.lifecycle.failure, .authorizationLost)
        XCTAssertFalse(owner.allowsInput)
        XCTAssertEqual(driver.view?.isHidden, true)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        driver.event?(.firstFrame(width: 1280, height: 720))
        owner.refresh()
        XCTAssertEqual(owner.lifecycle.failure, .authorizationLost)
        XCTAssertFalse(owner.allowsInput)
        await owner.close()
        XCTAssertEqual(driver.stops, 1)
    }

    func testExpiryIsNotExtendedByDisplayingAFrame() async throws {
        let current = try binding(), driver = ControlledNativeDriver(), surface = surface()
        let clock = NativeOwnerTestClock()
        let owner = try UIKitClientNativeVideoOwnerV0(binding: current, descriptor: descriptor(),
            surface: surface, driver: driver, current: { current }, nowMonotonicMilliseconds: { clock.now }, changed: { _, _ in })
        try owner.start()
        driver.event?(.connected)
        driver.event?(.firstFrame(width: 1280, height: 720))
        clock.now = 1000
        owner.refresh()
        XCTAssertEqual(owner.lifecycle.failure, .expired)
        XCTAssertEqual(driver.view?.isHidden, true)
        await owner.close()
    }

    func testRevocationStatusConsumerCanRefreshWithoutRecursiveTeardown() async throws {
        let original = try binding(), driver = ControlledNativeDriver(), surface = surface()
        var current: InteractiveNativeVideoBindingV0? = original
        let reference = NativeOwnerReference()
        let owner = try UIKitClientNativeVideoOwnerV0(binding: original, descriptor: descriptor(),
            surface: surface, driver: driver, current: { current }, nowMonotonicMilliseconds: { 10 },
            changed: { _, failure in
                if failure == .authorizationLost { reference.owner?.refresh() }
            })
        reference.owner = owner
        try owner.start()
        current = nil
        owner.refresh()
        XCTAssertEqual(owner.lifecycle.failure, .authorizationLost)
        XCTAssertEqual(driver.view?.isHidden, true)
        await owner.close()
        XCTAssertEqual(driver.stops, 1)
    }

    func testNativeMoonlightFailureDrainsThroughNormalSurfaceOwner() async throws {
        let config = CompanionMoonlightVideoConfiguration()
        config.host = "127.0.0.1"; config.appVersion = "7.1.431.0"
        config.serverCodecModeSupport = 1; config.sessionURL = "rtsp://127.0.0.1:9"
        config.streamKey = Data(repeating: 0, count: 16); config.streamKeyID = 1
        config.width = 1280; config.height = 720; config.framesPerSecond = 60; config.bitrateKbps = 10000
        let current = try binding(), surface = surface()
        let failed = expectation(description: "Native failure reached normal owner")
        var reported = false
        let owner = try UIKitClientNativeVideoOwnerV0(binding: current, descriptor: descriptor(),
            surface: surface, driver: MoonlightNativeVideoDriverV0(configuration: config),
            current: { current }, nowMonotonicMilliseconds: { 10 }, changed: { _, failure in
                if failure == .connectionFailed && !reported { reported = true; failed.fulfill() }
            })
        try owner.start()
        await fulfillment(of: [failed], timeout: 20)
        await owner.close()
        XCTAssertEqual(owner.lifecycle.failure, .connectionFailed)
        XCTAssertFalse(surface.hasUnverifiedExternalVideo)
    }
}

@MainActor
final class MoonlightNativeLaunchTests: XCTestCase {
    func testEphemeralIdentityHasClientPurposeAndRetirementIsTerminal() throws {
        let first = try CompanionNativeTLS.create(), second = try CompanionNativeTLS.create()
        let der = try XCTUnwrap(first.certificateDER)
        XCTAssertNotEqual(der, second.certificateDER)
        XCTAssertTrue(CompanionNativeTLS.validateCertificateDER(der, server: false))
        XCTAssertFalse(CompanionNativeTLS.validateCertificateDER(der, server: true))
        XCTAssertFalse(CompanionNativeTLS.validateCertificateDER(der + Data([0]), server: false))
        first.retire(); second.retire()
        XCTAssertNil(first.certificateDER)
        XCTAssertThrowsError(try first.requestPath("/serverinfo"))
        XCTAssertThrowsError(try first.bindAddress("127.0.0.1", portBase: 58989, hostCertificateDER: der))
    }
    func testNativeResponseRejectsEntitiesDuplicatesErrorsAndDeepNesting() throws {
        let valid = "<root status_code=\"200\"><PairStatus>1</PairStatus><appversion>7.1.431.-1</appversion></root>"
        XCTAssertEqual(try NativeLaunchXML.parse(Data(valid.utf8)).fields["PairStatus"], "1")
        for xml in [
            "<!DOCTYPE root [<!ENTITY x SYSTEM \"file:///private/test\">]><root status_code=\"200\"><PairStatus>&x;</PairStatus></root>",
            "<root status_code=\"200\"><PairStatus>1</PairStatus><PairStatus>1</PairStatus></root>",
            "<root status_code=\"401\"><PairStatus>1</PairStatus></root>",
            "<root status_code=\"200\"><nested><value>1</value></nested></root>",
            "<root status_code=\"200\"><PairStatus>" + String(repeating: "1", count: 4097) + "</PairStatus></root>"
        ] { XCTAssertThrowsError(try NativeLaunchXML.parse(Data(xml.utf8))) }
        let apps = try NativeLaunchXML.parse(Data("<root status_code=\"200\"><App><AppTitle>Desktop</AppTitle><ID>1</ID></App></root>".utf8))
        XCTAssertEqual(apps.apps, [["AppTitle": "Desktop", "ID": "1"]])
    }
    func testEncryptedStreamRejectsHostPortCredentialsAndExtraURLFields() {
        XCTAssertTrue(NativeLaunchValidationV0.validStreamURL("rtspenc://127.0.0.1:59010", address: "127.0.0.1", port: 59010))
        for value in ["rtsp://127.0.0.1:59010", "rtspenc://192.0.2.1:59010", "rtspenc://127.0.0.1:59011",
                      "rtspenc://user@127.0.0.1:59010", "rtspenc://127.0.0.1:59010?x=1", "rtspenc://127.0.0.1:59010/other"] {
            XCTAssertFalse(NativeLaunchValidationV0.validStreamURL(value, address: "127.0.0.1", port: 59010))
        }
        XCTAssertTrue(NativeLaunchValidationV0.validVersion("7.1.431.-1"))
        XCTAssertFalse(NativeLaunchValidationV0.validVersion("7.1.431.0.extra"))
    }
}
