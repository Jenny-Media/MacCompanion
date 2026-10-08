import XCTest
import UIKit
import Citadel
@testable import Mac_Companion

@MainActor final class RecoveryTests: XCTestCase {
    func testIndexedRecoveryFixtureUsesTypedErrorsAndHonestSetupOutcomes() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let recovery = try XCTUnwrap(fixture["errorRecovery"] as? [String: Any])
        for field in ["classifyVendorText", "replayInput", "replaySetupCommand"] { XCTAssertEqual(recovery[field] as? Bool, false) }
        for row in try XCTUnwrap(recovery["cases"] as? [[String: Any]]) {
            let error: Error
            switch row["input"] as? String {
            case "authRejected": error = SSHClientError.allAuthenticationOptionsFailed
            case "unsupportedAuth": error = SSHClientError.unsupportedPrivateKeyAuthentication
            case "dns": error = TerminalConnectionFailure.lookup
            case "tcp": error = TerminalConnectionFailure.socket
            case "changedKey": error = TerminalSecretStore.Failure.changedKey
            case "rejectedTrust": error = TerminalSecretStore.Failure.rejectedKey
            default: error = NSError(domain: "Authentication failed; missing authorized_keys", code: 8)
            }
            XCTAssertEqual(DirectTerminalSession.reason(for: error, keyLogin: row["keyLogin"] as? Bool == true).rawValue, row["reason"] as? String)
        }
        for row in try XCTUnwrap(recovery["setupCases"] as? [[String: Any]]) {
            let phase = try XCTUnwrap(TerminalSetupPhase(rawValue: try XCTUnwrap(row["phase"] as? String)))
            XCTAssertEqual(phase.failure.rawValue, row["reason"] as? String)
            XCTAssertEqual(phase.mayBeInstalled, row["mayBeInstalled"] as? Bool)
        }
        for row in try XCTUnwrap(recovery["desktopCases"] as? [[String: Any]]) {
            XCTAssertEqual(DirectRecoveryBridgeV1.desktopReason(stage: try XCTUnwrap(row["stage"] as? Int), hadFrame: row["hadFrame"] as? Bool == true).rawValue, row["reason"] as? String)
        }

    }
    func testSavedLoginWriteFailureLeavesEditableFieldsAndStopsProgress() {
        let viewer = CompanionVNCViewer(); viewer.loadViewIfNeeded()
        viewer.setValue(true, forKey: "starting")
        viewer.showLoginRetentionFailure()
        XCTAssertEqual(viewer.value(forKey: "starting") as? Bool, false)
        XCTAssertFalse((viewer.value(forKey: "loginFields") as? UIView)?.isHidden ?? true)
        viewer.stop()
    }
    func testInlineDesktopErrorRetainsDiagnosticDetailsUntilLoginIsEdited() throws {
        let viewer = CompanionVNCViewer(); viewer.servicePort = 5901; viewer.loadViewIfNeeded()
        defer { viewer.stop() }
        viewer.showRecoveryStage(7)
        let details = try XCTUnwrap(viewer.value(forKey: "loginIssueDetails") as? String)
        XCTAssertTrue(details.contains("allowed to use the sharing service"))
        XCTAssertTrue(details.contains("Port: 5901")); XCTAssertTrue(details.contains("Stage: 7"))
        _ = viewer.perform(NSSelectorFromString("loginEdited"))
        XCTAssertNil(viewer.value(forKey: "loginIssueDetails"))
    }
    func testSavedMacRetryRereadsWithoutReplacingMalformedData() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "macs.json"), malformed = Data("unreadable existing data".utf8)
        try malformed.write(to: url)
        let library = DirectMacLibraryV1(url: url, removeLogin: { _ in })
        XCTAssertFalse(library.readable); XCTAssertEqual(library.recovery?.reason, .savedDataUnavailable)
        library.reload(); XCTAssertEqual(try Data(contentsOf: url), malformed)
        XCTAssertFalse(library.save(id: nil, name: "New", address: "127.0.0.1"))
        try Data("{\"version\":3,\"macs\":[]}".utf8).write(to: url)
        library.reload(); XCTAssertTrue(library.readable); XCTAssertNil(library.recovery)
    }
    func testLoginProgressHidesFormAndRestoresTheSameDraftAfterValidationFailure() {
        let viewer = CompanionVNCViewer(); viewer.loadViewIfNeeded()
        defer { viewer.stop() }
        let canvas = viewer.value(forKey: "canvas") as? UIView
        let fields = viewer.value(forKey: "loginFields") as? UIView
        let login = viewer.value(forKey: "loginScroll") as? UIScrollView
        let password = viewer.value(forKey: "password") as? UITextField
        password?.text = "synthetic-draft-only"
        XCTAssertTrue(canvas?.isHidden == true)
        XCTAssertFalse(login?.isHidden ?? true)
        viewer.setValue(true, forKey: "starting")
        _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
        XCTAssertTrue(fields?.isHidden == true); XCTAssertFalse(fields?.isUserInteractionEnabled ?? true)
        viewer.showInvalidLogin()
        XCTAssertFalse(fields?.isHidden ?? true)
        XCTAssertTrue((viewer.value(forKey: "password") as? UITextField) === password)
        XCTAssertEqual(password?.text, "synthetic-draft-only")
        let visibility = viewer.value(forKey: "passwordVisibility") as? UIButton
        _ = viewer.perform(NSSelectorFromString("togglePassword"))
        XCTAssertFalse(password?.isSecureTextEntry ?? true)
        XCTAssertEqual(visibility?.accessibilityLabel, "Hide Password")
        XCTAssertNotNil(visibility?.image(for: .normal))
    }

}
