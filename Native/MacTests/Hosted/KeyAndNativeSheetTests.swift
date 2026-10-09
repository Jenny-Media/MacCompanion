import AppKit
import Crypto
import Citadel
import XCTest
@testable import MacCompanion

@MainActor final class KeyAndNativeSheetTests: XCTestCase {
    func testRemovingThePreferredKeyRestoresPasswordAccountWithoutResettingIncidentalReloads() {
        var login = TerminalLoginSelection()
        login.loadPasswordAccount("synthetic-password-account")
        login.loadKeyAccount("synthetic-key-account", preferSelected: true)
        login.loadKeyAccount(nil, preferSelected: true)
        XCTAssertEqual(login.method, .password); XCTAssertEqual(login.username, "synthetic-password-account")
        login.username = "edited-password-account"
        login.loadKeyAccount("another-key-account", preferSelected: false)
        XCTAssertEqual(login.method, .password); XCTAssertEqual(login.username, "edited-password-account")
        login.select(.sshKey)
        login.loadKeyAccount(nil, preferSelected: false)
        XCTAssertEqual(login.method, .sshKey, "An incidental reload must preserve an explicit method choice")
    }
    func testTwoKeyManagersCannotCreateTwoFreeKeysFromCachedEmptyLibraries() async throws {
        let suite = UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let access = DirectProAccess(defaults: defaults)
        await access.refresh()
        XCTAssertTrue(access.ready); XCTAssertFalse(access.hasPro)
        let storageID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let original = try TerminalKeyLibraryStore.load()
        defer { try? TerminalSecretStore.write(JSONEncoder().encode(original), id: storageID, kind: "key-library-v2") }
        try TerminalSecretStore.write(JSONEncoder().encode(TerminalKeyLibraryStore.Library()), id: storageID, kind: "key-library-v2")
        let first = TerminalKeyLibrary(), second = TerminalKeyLibrary()
        first.reload(); second.reload()
        XCTAssertTrue(first.keys.isEmpty); XCTAssertTrue(second.keys.isEmpty)
        let key = TerminalSSHKey.create()
        let id = try TerminalKeyLibraryStore.addForUser(key, name: "Synthetic First", access: access)
        XCTAssertTrue(second.keys.isEmpty, "The second view still has its stale snapshot")
        XCTAssertThrowsError(try TerminalKeyLibraryStore.addForUser(.create(), name: "Synthetic Second", access: access)) { error in
            XCTAssertTrue(error is TerminalKeyLibraryStore.CreationFailure)
        }
        XCTAssertEqual(try TerminalKeyLibraryStore.load().keys.map(\.id), [id])
        XCTAssertEqual(try TerminalKeyLibraryStore.addForUser(key, name: "Duplicate", access: access), id)
    }
    func testExtensionlessLocalKeyImportPreservesOriginalAndSupportsEncryption() throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString).appending(path: ".ssh")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let key = Curve25519.Signing.PrivateKey(), url = folder.appending(path: "id_ed25519")
        for text in [key.makeSSHRepresentation(), try key.makeEncryptedSSHRepresentation(passphrase: "synthetic-only")] {
            let original = Data(text.utf8)
            try original.write(to: url)
            let imported = try TerminalSSHKey.importOpenSSH(TerminalSSHKey.readOpenSSHFile(url), passphrase: "synthetic-only")
            XCTAssertEqual(imported.seed, key.rawRepresentation)
            XCTAssertEqual(try Data(contentsOf: url), original)
        }
        try Data(repeating: 65, count: 32769).write(to: url)
        XCTAssertThrowsError(try TerminalSSHKey.readOpenSSHFile(url))
        try Data([0xff]).write(to: url)
        XCTAssertThrowsError(try TerminalSSHKey.readOpenSSHFile(url))
    }
    func testLocalKeyPickerShowsHiddenFolderAndAcceptsExtensionlessFiles() throws {
        let home = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let ssh = home.appending(path: ".ssh")
        try FileManager.default.createDirectory(at: ssh, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let panel = MacSSHKeyFilePicker.makePanel(sshFolder: true, home: home)
        XCTAssertEqual(panel.directoryURL?.standardizedFileURL, ssh.standardizedFileURL)
        XCTAssertTrue(panel.showsHiddenFiles); XCTAssertTrue(panel.canChooseFiles)
        XCTAssertTrue(panel.allowedContentTypes.isEmpty); XCTAssertTrue(panel.allowsOtherFileTypes)
        XCTAssertFalse(panel.canChooseDirectories); XCTAssertFalse(panel.allowsMultipleSelection)
    }
    func testBackgroundCancelsNativeLinkSheetsAndRejectsLateOpen() async throws {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 700, height: 440), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let links = MacTerminalLinkConfirmation()
        var opened = false
        links.present(try XCTUnwrap(URL(string: "https://example.invalid/synthetic-private-url")), in: window, canOpen: { true }, open: { _ in opened = true })
        let alert = try XCTUnwrap(links.alert)
        XCTAssertTrue(alert.informativeText.contains("synthetic-private-url"))
        NotificationCenter.default.post(name: DirectClientPlatformV1.didEnterBackground, object: nil)
        XCTAssertNil(links.alert); XCTAssertEqual(alert.informativeText, ""); XCTAssertFalse(alert.window.isVisible)
        window.endSheet(alert.window, returnCode: .alertFirstButtonReturn)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(opened, "A late confirmation after cancellation cannot open a browser")
    }
    func testBackgroundCancelsLocalKeyPickerWithoutReadingOrImportingAKey() async throws {
        let home = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: home.appending(path: ".ssh"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 700, height: 440), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let picker = MacSSHKeyFilePicker()
        var completed = false
        picker.choose(in: window, sshFolder: true, home: home) { _ in completed = true }
        let panel = try XCTUnwrap(picker.panel)
        NotificationCenter.default.post(name: DirectClientPlatformV1.didEnterBackground, object: nil)
        XCTAssertNil(picker.panel); XCTAssertFalse(panel.isVisible)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(panel.isVisible); XCTAssertFalse(completed)
    }
    func testClosingOneWindowCancelsOnlyItsLinkConfirmation() throws {
        let first = NSWindow(), second = NSWindow()
        first.isReleasedWhenClosed = false; second.isReleasedWhenClosed = false
        defer { first.close(); second.close() }
        let a = MacTerminalLinkConfirmation(), b = MacTerminalLinkConfirmation()
        let url = try XCTUnwrap(URL(string: "https://example.invalid/synthetic"))
        a.present(url, in: first, canOpen: { true }, open: { _ in XCTFail("Unexpected browser open") })
        b.present(url, in: second, canOpen: { true }, open: { _ in XCTFail("Unexpected browser open") })
        first.close()
        XCTAssertNil(a.alert); XCTAssertNotNil(b.alert)
        b.cancel()
    }
}
