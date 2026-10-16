import XCTest
import Foundation
#if os(iOS)
@testable import Mac_Companion
#elseif os(visionOS)
@testable import MacCompanionVision
#else
@testable import MacCompanion
#endif

@MainActor final class CredentialFormLifecycleTests: XCTestCase {
    func testIndexedReturnsAndMethodAccountIsolation() throws {
        struct Row: Decodable { let id: String; let events: [String]; let account: String; let password: String; let remember: Bool }
        struct Fixture: Decodable { let credentialFormReturnCases: [Row] }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-files-v1", withExtension: "json"))
        let rows = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).credentialFormReturnCases
        let saved = TerminalSecretStore.Login(username: "synthetic", password: "synthetic-only")
        for row in rows {
            var draft = DirectFilesLoginDraft()
            for event in row.events {
                switch event {
                case "initialize": draft.initialize(saved: saved)
                case "clear": draft.password = ""
                case "save-off": draft.remember = false
                case "key": draft.loadKeyAccount("synthetic-key", preferSelected: true)
                case "empty-key": draft.selectMethod(.sshKey)
                case "remove-key": draft.loadKeyAccount(nil, preferSelected: false)
                case "password": draft.selectMethod(.password)
                case "connect-key", "connect-password":
                    let attempt = draft.authenticationAttempt(account: draft.username, password: draft.method == .password ? draft.password : nil, remember: draft.remember)
                    XCTAssertNotNil(attempt, row.id)
                    draft.authenticationSucceeded(attempt, retention: event == "connect-password" && draft.remember ? .saved : .notRequested)
                case "begin-only": XCTAssertNotNil(draft.authenticationAttempt(account: draft.username, password: draft.password, remember: draft.remember))
                case "end": draft.passwordSessionEnded()
                case "suspend": draft.suspend()
                case "restore", "locked-restore":
                    draft.resume(); draft.restorePassword(active: true, allowed: event != "locked-restore", signIn: true) { saved }
                default: XCTFail(event)
                }
            }
            XCTAssertEqual(draft.username, row.account == "saved" ? saved.username : "", row.id)
            XCTAssertEqual(draft.password, row.password == "saved" ? saved.password : "", row.id)
            XCTAssertEqual(draft.remember, row.remember, row.id)
        }
    }
    func testLateAuthenticationCannotOverwriteNewDraftOrRestoreForgottenPassword() {
        var draft = DirectFilesLoginDraft()
        let saved = TerminalSecretStore.Login(username: "synthetic", password: "synthetic-only")
        draft.initialize(saved: saved)
        let pending = draft.authenticationAttempt(account: draft.username, password: draft.password, remember: true)
        draft.password = "edited-only"
        draft.authenticationSucceeded(pending, retention: .saved)
        XCTAssertEqual(draft.password, "edited-only")
        draft.selectMethod(.sshKey); draft.loadKeyAccount("synthetic-key", preferSelected: false)
        let key = draft.authenticationAttempt(account: draft.username, password: nil, remember: true)
        draft.authenticationSucceeded(key, retention: .notRequested)
        draft.selectMethod(.password)
        draft.restorePassword(active: true, allowed: true, signIn: true) { XCTFail("An edited password is not a saved credential"); return saved }
        XCTAssertEqual(draft.password, "")
    }
}
