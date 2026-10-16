#if os(iOS)
import XCTest
import UIKit
@testable import Mac_Companion

@MainActor final class DesktopCredentialRecoveryTests: XCTestCase {
    func testUnsavedRecoverySurvivesPauseButEndsWithBlankForm() throws {
        let state = DirectDesktopLoginState(macID: nil, username: "", password: "")
        state.readSaved = { XCTFail("An unsaved session must not read Keychain"); return nil }
        state.edit(username: "synthetic", password: "synthetic-only", remember: false)
        XCTAssertEqual(state.beginLogin()["password"], "synthetic-only")
        state.authenticated()
        XCTAssertEqual(state.password, "")
        state.suspend(); state.resume(active: true, allowed: true)
        XCTAssertEqual(state.loginForResume()?["password"], "synthetic-only")
        XCTAssertEqual(state.password, "")
        state.ended(active: true, allowed: true)
        XCTAssertNil(state.loginForResume()); XCTAssertEqual(state.username, ""); XCTAssertEqual(state.password, "")
    }
    func testSavedReturnDefersReadWhileLockedAndManualClearWins() {
        let state = DirectDesktopLoginState(macID: nil, username: "synthetic", password: "synthetic-only")
        var reads = 0
        state.readSaved = { reads += 1; return .init(username: "synthetic", password: "synthetic-only") }
        _ = state.beginLogin(); state.authenticated()
        XCTAssertEqual(reads, 1); XCTAssertEqual(state.password, "")
        state.suspend(); state.ended(active: false, allowed: false)
        XCTAssertEqual(reads, 1); XCTAssertEqual(state.password, "")
        state.resume(active: true, allowed: true)
        XCTAssertEqual(reads, 2); XCTAssertEqual(state.password, "synthetic-only")
        state.edit(username: "synthetic", password: "", remember: true)
        state.suspend(); state.resume(active: true, allowed: true)
        XCTAssertEqual(reads, 2); XCTAssertEqual(state.password, "")
    }
    func testFailedInitialAttemptKeepsDraftAndExplicitEndRetiresRecovery() {
        let state = DirectDesktopLoginState(macID: nil, username: "", password: "")
        state.edit(username: "synthetic", password: "synthetic-only", remember: false)
        _ = state.beginLogin(); state.ended(active: true, allowed: true)
        XCTAssertEqual(state.username, "synthetic"); XCTAssertEqual(state.password, "synthetic-only")
        _ = state.beginLogin(); state.authenticated(); state.invalidate()
        XCTAssertNil(state.loginForResume()); XCTAssertEqual(state.username, ""); XCTAssertEqual(state.password, "")
    }
    func testActualViewerResumesUsingPrivateLoginThenClearsUnsavedReturn() throws {
        let viewer = CompanionVNCViewer()
        viewer.loadViewIfNeeded()
        defer { viewer.stop() }
        viewer.reloadAccessUsername("synthetic", password: "synthetic-only")
        let remember = try XCTUnwrap(viewer.value(forKey: "remember") as? UISwitch)
        remember.isOn = false; remember.sendActions(for: .valueChanged)
        var requests: [[String]] = []
        viewer.connectHandler = { user, password, _ in requests.append([user, password]) }
        viewer.perform(NSSelectorFromString("start"))
        let state = try XCTUnwrap(viewer.value(forKey: "credentialState") as? DirectDesktopLoginState)
        state.authenticated()
        viewer.perform(NSSelectorFromString("renderCredentialForm"))
        viewer.session.setValue(true, forKey: "running")
        viewer.session.setValue(true, forKey: "established")
        viewer.background()
        viewer.session.setValue(false, forKey: "running")
        viewer.foregrounded()
        XCTAssertEqual(requests, Array(repeating: ["synthetic", "synthetic-only"], count: 2), "Automatic replacement must not use cleared text controls")
        viewer.showConnectionFailureStage(102)
        let account = try XCTUnwrap(viewer.value(forKey: "username") as? UITextField)
        let password = try XCTUnwrap(viewer.value(forKey: "password") as? UITextField)
        XCTAssertEqual(account.text, ""); XCTAssertEqual(password.text, "")
        XCTAssertNil(state.loginForResume())
        XCTAssertEqual(requests.count, 2, "Returning to sign-in must not reconnect")
    }
}
#endif
