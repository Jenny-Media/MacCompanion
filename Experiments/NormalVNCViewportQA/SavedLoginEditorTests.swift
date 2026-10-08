import XCTest
@testable import Mac_Companion

@MainActor final class SavedLoginEditorTests: XCTestCase {
    func testExplicitSaveKeepsServicesAndMacsIndependentAndCancelKeepsOriginal() throws {
        let first = UUID(), second = UUID()
        defer { try? DesktopCredentialStoreV1.remove(first); try? DesktopCredentialStoreV1.remove(second); try? TerminalSecretStore.remove(first) }
        try DesktopCredentialStoreV1.save(.init(username: "old-desktop", password: "synthetic-old"), hostID: first)
        try DesktopCredentialStoreV1.save(.init(username: "other-mac", password: "synthetic-other"), hostID: second)
        try TerminalSecretStore.save(.init(username: "old-terminal", password: "synthetic-terminal"), id: first)
        let desktop = DirectSavedLoginDraft(macID: first, service: .desktop); desktop.load()
        desktop.username = "new-desktop"; desktop.password = "synthetic-new"
        XCTAssertEqual(try DesktopCredentialStoreV1.readChecked(first)?.username, "old-desktop")
        desktop.clear()
        XCTAssertEqual(try DesktopCredentialStoreV1.readChecked(first)?.password, "synthetic-old")
        desktop.load(); desktop.username = "new-desktop"; desktop.password = "synthetic-new"; XCTAssertTrue(desktop.save())
        XCTAssertEqual(try DesktopCredentialStoreV1.readChecked(first)?.username, "new-desktop")
        XCTAssertEqual(try DesktopCredentialStoreV1.readChecked(second)?.username, "other-mac")
        XCTAssertEqual(try TerminalSecretStore.login(first)?.username, "old-terminal")
        let terminal = DirectSavedLoginDraft(macID: first, service: .terminal); terminal.load(); terminal.username = "new-terminal"
        XCTAssertTrue(terminal.save()); XCTAssertEqual(try TerminalSecretStore.login(first)?.username, "new-terminal")
        XCTAssertEqual(try DesktopCredentialStoreV1.readChecked(first)?.username, "new-desktop")
    }
    func testUnreadableDataBlocksSaveAndWriteFailureKeepsDraft() {
        var writes = 0
        let unreadable = DirectSavedLoginDraft(macID: UUID(), service: .desktop,
            read: { throw DesktopCredentialStoreV1.StoreFailure.unavailable }, write: { _ in writes += 1 })
        unreadable.load(); unreadable.username = "draft"; unreadable.password = "synthetic"
        XCTAssertFalse(unreadable.save()); XCTAssertEqual(writes, 0); XCTAssertEqual(unreadable.recovery?.reason, .savedDataUnavailable)
        let failing = DirectSavedLoginDraft(macID: UUID(), service: .terminal,
            read: { .init(username: "old", password: "synthetic-old") }, write: { _ in throw TerminalSecretStore.Failure.storage })
        failing.load(); failing.username = "draft"; failing.password = "synthetic-new"
        XCTAssertFalse(failing.save()); XCTAssertEqual(failing.username, "draft"); XCTAssertEqual(failing.password, "synthetic-new")
        XCTAssertEqual(failing.recovery?.reason, .saveFailed)
    }
    func testServiceBoundsAndBackgroundDraftClearing() throws {
        let draft = DirectSavedLoginDraft(macID: UUID(), service: .desktop, read: { nil }, write: { _ in XCTFail("No save requested") })
        draft.load(); draft.username = "account"; draft.password = String(repeating: "😀", count: 16)
        XCTAssertFalse(draft.valid); draft.password = "synthetic"; XCTAssertTrue(draft.valid)
        draft.clear(); XCTAssertTrue(draft.password.isEmpty); XCTAssertTrue(draft.username.isEmpty); XCTAssertFalse(draft.valid)
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let policy = try XCTUnwrap(fixture["savedLoginEditing"] as? [String: Bool])
        XCTAssertEqual(policy["explicitSave"], true); XCTAssertEqual(policy["syncCredentials"], false); XCTAssertEqual(policy["connectOnSave"], false)
    }
}
