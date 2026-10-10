import AppKit
import SwiftUI
import Crypto
import Citadel
import NIO
import NIOSSH
import XCTest
@testable import MacCompanion

@MainActor final class NativeClientPolishTests: XCTestCase {
    func testDiscoveryGroupsServicesByCanonicalHostWithoutJoiningEqualNames() {
        let desktop = DirectMacDetectedIdentity(name: "Synthetic", host: "fixture.local.", addresses: [], port: 5900, connection: .desktop, modelIdentifier: "Mac16,10")
        let terminal = DirectMacDetectedIdentity(name: "Synthetic", host: "FIXTURE.local", addresses: [], port: 2222, connection: .terminal, modelIdentifier: "Mac16,10")
        let other = DirectMacDetectedIdentity(name: "Synthetic", host: "different.local.", addresses: [], port: 22, connection: .terminal)
        let groups = DirectMacDiscoveryItem.group([terminal, other, desktop])
        XCTAssertEqual(groups.count, 2)
        let combined = groups.first { $0.id == "fixture.local" }
        XCTAssertEqual(combined?.services.count, 2); XCTAssertEqual(combined?.family, .macMini)
        XCTAssertEqual(combined?.services.first { $0.connection == .terminal }?.port, 2222)
        XCTAssertEqual(DirectMacDiscoveryItem.group([desktop, terminal.replacingModel("MacBookPro18,1")]).first?.family, .unknown)
    }
    func testNativeAutofillValueChangesReachBindingsAndSurviveUnrelatedRedraws() {
        var username = "", password = ""
        let pair = MacCredentialFields(username: Binding(get: { username }, set: { username = $0 }),
            password: Binding(get: { password }, set: { password = $0 }), prefix: "synthetic")
        let view = MacCredentialFields.Fields(), coordinator = pair.makeCoordinator()
        coordinator.attach(view); coordinator.update(view)
        // Autofill assigns native values without keyboard events or Return.
        view.account.stringValue = "synthetic-account"
        view.secret.stringValue = "synthetic-only"
        XCTAssertEqual(username, "synthetic-account"); XCTAssertEqual(password, "synthetic-only")
        coordinator.update(view)
        XCTAssertEqual(view.account.stringValue, username); XCTAssertEqual(view.secret.stringValue, password)
        password = ""; coordinator.update(view)
        XCTAssertEqual(view.secret.stringValue, "", "Explicit clearing on lock or connection must reach the native secure field")
        coordinator.detach(); view.clear()
    }
    func testTerminalLifecycleResumesOnWakeWithoutAccessChangeAndHonorsLock() async throws {
        var suspended = false, allowed = true, resumes = 0
        let host = NSHostingView(rootView: Color.clear.modifier(MacTerminalLifecycle(canResume: { allowed },
            suspend: { suspended = true }, resume: { suspended = false; resumes += 1 })))
        let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host; host.layoutSubtreeIfNeeded()
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(30))
        NotificationCenter.default.post(name: DirectClientPlatformV1.didEnterBackground, object: nil)
        XCTAssertTrue(suspended)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        XCTAssertFalse(suspended); XCTAssertEqual(resumes, 1, "App access stayed true throughout sleep/wake")
        NotificationCenter.default.post(name: DirectClientPlatformV1.didEnterBackground, object: nil)
        allowed = false
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        XCTAssertTrue(suspended); XCTAssertEqual(resumes, 1, "System wake cannot bypass app unlock")
        allowed = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        XCTAssertFalse(suspended); XCTAssertEqual(resumes, 2)
    }
    func testDiscoveryChoiceReplacesComputerAndItsServicePorts() throws {
        let computers = DirectMacDiscoveryItem.group([
            .init(name: "Computer A", host: "a.local.", addresses: [], port: 5999, connection: .desktop),
            .init(name: "Computer B", host: "b.local.", addresses: [], port: 2222, connection: .terminal)])
        var selection = MacDiscoverySelection(try XCTUnwrap(computers.first { $0.name == "Computer A" }))
        XCTAssertEqual(selection.desktopPort, 5999)
        selection = MacDiscoverySelection(try XCTUnwrap(computers.first { $0.name == "Computer B" }))
        let saved = try DirectMacRecordV1.normalized(name: selection.name, addresses: [selection.address], port: selection.desktopPort, sshPort: selection.terminalPort)
        XCTAssertEqual(saved.name, "Computer B"); XCTAssertEqual(saved.addresses, ["b.local."])
        XCTAssertEqual(saved.port, 5900); XCTAssertEqual(saved.sshPort, 2222, "Ports belong to the selected computer")
    }
    func testCustomActionBoundaryAllowsStandardsAndPreservesProfileOnRejectedSave() throws {
        let original = try VNCSessionPreferences.profileActions(.desktop)
        defer { try? VNCSessionPreferences.saveProfile(original, mode: .desktop) }
        let custom = (0..<VNCQuickAction.maximumCustomCount).map { VNCQuickAction(title: "Synthetic \($0)", kind: .text, text: "synthetic") }
        var actions = DirectControlMode.desktop.defaults.filter { $0.kind != .mode } + custom
        XCTAssertFalse(VNCQuickAction.canAddCustom(to: actions))
        XCTAssertLessThan(actions.count, VNCQuickAction.maximumCount, "A standard action still fits")
        actions.append(.init(title: "Escape", kind: .escape))
        try VNCSessionPreferences.saveProfile(actions, mode: .desktop)
        let saved = try VNCSessionPreferences.profileActions(.desktop)
        XCTAssertEqual(saved, actions)
        XCTAssertThrowsError(try VNCSessionPreferences.saveProfile(saved + [.init(title: "Extra", kind: .text, text: "synthetic")], mode: .desktop))
        XCTAssertEqual(try VNCSessionPreferences.profileActions(.desktop), saved)
        actions.removeLast(); actions.removeLast()
        XCTAssertTrue(VNCQuickAction.canAddCustom(to: actions), "Removing one custom action restores custom capacity")
    }
    private func isolatedKeys(_ run: () async throws -> Void) async throws {
        let namedID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let named = try TerminalKeyLibraryStore.load(), files = try MacSSHKeyFileStore.load()
        defer {
            try? TerminalSecretStore.write(JSONEncoder().encode(named), id: namedID, kind: "key-library-v2")
            try? TerminalSecretStore.write(JSONEncoder().encode(files), id: MacSSHKeyFileStore.storageID, kind: MacSSHKeyFileStore.kind)
        }
        try TerminalSecretStore.write(JSONEncoder().encode(TerminalKeyLibraryStore.Library()), id: namedID, kind: "key-library-v2")
        try TerminalSecretStore.write(JSONEncoder().encode(MacSSHKeyFileStore.Library()), id: MacSSHKeyFileStore.storageID, kind: MacSSHKeyFileStore.kind)
        try await run()
    }
    private func access() async throws -> (DirectProAccess, UserDefaults, String) {
        let suite = UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let access = DirectProAccess(defaults: defaults); await access.refresh()
        return (access, defaults, suite)
    }
    func testKeyFileReferencesPreserveOriginalAndRejectChangedOrMissingKeys() async throws {
        try await isolatedKeys {
            let (access, defaults, suite) = try await self.access()
            defer { defaults.removePersistentDomain(forName: suite) }
            let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let url = folder.appending(path: "id_ed25519"), originalKey = Curve25519.Signing.PrivateKey()
            let bytes = Data(originalKey.makeSSHRepresentation().utf8); try bytes.write(to: url)
            let id = try MacSSHKeyFileStore.add(url: url, name: "Synthetic File", passphrase: "", access: access)
            let file = try XCTUnwrap(MacSSHKeyFileStore.load().files.first { $0.id == id })
            XCTAssertEqual(try file.read(passphrase: "").seed, originalKey.rawRepresentation)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
            XCTAssertTrue(try TerminalKeyLibraryStore.load().keys.isEmpty, "Referencing must not import the private key")
            let stored = try XCTUnwrap(TerminalSecretStore.read(MacSSHKeyFileStore.storageID, kind: MacSSHKeyFileStore.kind))
            let json = try XCTUnwrap(String(data: stored, encoding: .utf8))
            XCTAssertFalse(json.contains("seed")); XCTAssertFalse(json.contains("passphrase"))
            try Data(Curve25519.Signing.PrivateKey().makeSSHRepresentation().utf8).write(to: url)
            XCTAssertThrowsError(try file.read(passphrase: "")) { XCTAssertTrue($0 is MacSSHKeyFileStore.Failure) }
            try FileManager.default.removeItem(at: url)
            XCTAssertThrowsError(try file.read(passphrase: ""))
        }
    }
    func testEncryptedFileNeedsPassphraseAgainAndNeverRestoresOldImportedSelection() async throws {
        try await isolatedKeys {
            let (access, defaults, suite) = try await self.access()
            defer { defaults.removePersistentDomain(forName: suite) }
            let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: url) }
            let privateKey = Curve25519.Signing.PrivateKey()
            let key = TerminalSSHKey(seed: privateKey.rawRepresentation), machine = UUID()
            let imported = try TerminalKeyLibraryStore.addForUser(key, name: "Synthetic Imported", access: access)
            try TerminalKeyLibraryStore.associate(imported, macID: machine, username: "old-account")
            try Data(privateKey.makeEncryptedSSHRepresentation(passphrase: "synthetic-only").utf8).write(to: url)
            let referenced = try MacSSHKeyFileStore.add(url: url, name: "Synthetic File", passphrase: "synthetic-only", access: access)
            XCTAssertEqual(imported, referenced, "A key keeps its free-key identity across both storage methods")
            try MacSSHKeyFileStore.associate(referenced, macID: machine, username: "new-account", access: access)
            let file = try XCTUnwrap(MacSSHKeyFileStore.selected(machine)?.file)
            XCTAssertThrowsError(try file.read(passphrase: ""))
            XCTAssertEqual(try file.read(passphrase: "synthetic-only").seed, key.seed)
            XCTAssertNil(try TerminalKeyLibraryStore.selected(machine))
            try MacSSHKeyFileStore.remove(referenced)
            XCTAssertNil(try MacSSHKeyFileStore.selected(machine)); XCTAssertNil(try TerminalKeyLibraryStore.selected(machine))
            XCTAssertEqual(try TerminalKeyLibraryStore.load().keys.count, 1, "Removing a reference keeps an explicitly imported copy")
        }
    }
    func testSuccessfulDiskKeySSHLoginDoesNotImportTheKey() async throws {
        try await isolatedKeys {
            let (access, defaults, suite) = try await self.access()
            defer { defaults.removePersistentDomain(forName: suite) }
            let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: url) }
            let original = Curve25519.Signing.PrivateKey()
            try Data(original.makeSSHRepresentation().utf8).write(to: url)
            let fileID = try MacSSHKeyFileStore.add(url: url, name: "Synthetic File", passphrase: "", access: access)
            let record = SSHTestRecord(), hostKey = NIOSSHPrivateKey(ed25519Key: .init())
            let publicKey = NIOSSHPrivateKey(ed25519Key: original).publicKey
            let server = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton).childChannelInitializer { channel in
                record.openedTransport(channel)
                return channel.pipeline.addHandler(NIOSSHHandler(role: .server(.init(hostKeys: [hostKey], userAuthDelegate: SSHTestAuth(record, publicKey: publicKey))), allocator: channel.allocator,
                    inboundChildChannelInitializer: { child, _ in child.pipeline.addHandler(SSHTestPTY(record)) }))
            }.bind(host: "127.0.0.1", port: 0).get()
            defer { Task { try? await server.close() } }
            let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic File Login", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
            try MacSSHKeyFileStore.associate(fileID, macID: mac.id, username: "old-account", access: access)
            let session = DirectTerminalSession(mac: mac)
            defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
            let file = try XCTUnwrap(MacSSHKeyFileStore.selected(mac.id)?.file)
            session.connect(username: "synthetic", password: "", remember: false, key: try file.read(passphrase: ""), keyFileID: fileID)
            try await self.wait { session.trust != nil || !session.connecting }
            XCTAssertNotNil(session.trust, session.status); XCTAssertEqual(record.keyRequests, 0)
            session.answerTrust(true)
            try await self.wait { session.connected || !session.connecting }
            XCTAssertTrue(session.connected, session.status); XCTAssertGreaterThan(record.keyRequests, 0)
            XCTAssertEqual(record.passwordRequests, 0)
            XCTAssertTrue(try TerminalKeyLibraryStore.load().keys.isEmpty)
            XCTAssertNil(try TerminalSecretStore.sshKey(mac.id))
            XCTAssertEqual(try MacSSHKeyFileStore.selected(mac.id)?.username, "synthetic")
            XCTAssertEqual(try file.read(passphrase: "").seed, original.rawRepresentation)
            session.stop(); try await server.close()
        }
    }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<500 { if condition() { return }; try await Task.sleep(for: .milliseconds(10)) }
        XCTFail("Timed out waiting for the synthetic SSH login"); throw POSIXError(.ETIMEDOUT)
    }
    func testFileAndImportedCopiesCountOnceAndCreationRechecksFreshPolicy() async throws {
        try await isolatedKeys {
            let (access, defaults, suite) = try await self.access()
            defer { defaults.removePersistentDomain(forName: suite) }
            let url = URL.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: url) }
            let original = Curve25519.Signing.PrivateKey()
            try Data(original.makeSSHRepresentation().utf8).write(to: url)
            let fileID = try MacSSHKeyFileStore.add(url: url, name: "Synthetic File", passphrase: "", access: access)
            let importedID = try TerminalKeyLibraryStore.addForUser(.init(seed: original.rawRepresentation), name: "Same Key", access: access)
            XCTAssertEqual(fileID, importedID)
            XCTAssertThrowsError(try TerminalKeyLibraryStore.addForUser(.create(), name: "Second Key", access: access))
            try Data(Curve25519.Signing.PrivateKey().makeSSHRepresentation().utf8).write(to: url)
            XCTAssertThrowsError(try MacSSHKeyFileStore.add(url: url, name: "Second File", passphrase: "", access: access))
            let file = try XCTUnwrap(MacSSHKeyFileStore.load().files.first)
            XCTAssertTrue(try MacSSHKeyFileStore.canUse(file, access: access))
            try MacSSHKeyFileStore.remove(fileID)
            XCTAssertThrowsError(try MacSSHKeyFileStore.canUse(file, access: access), "A stale window cannot use a removed file reference")
        }
    }
    func testRetainedDiskFreeKeyCanBeChangedAndImportedSelectionDoesNotReplaceIt() async throws {
        try await isolatedKeys {
            let (access, defaults, suite) = try await self.access()
            defer { defaults.removePersistentDomain(forName: suite) }
            let keyA = TerminalSSHKey.create(), keyB = TerminalSSHKey.create()
            let fileA = MacSSHKeyFileReference(id: UUID(), name: "Retained A", bookmark: Data([1]), fingerprint: keyA.fingerprint)
            let fileB = MacSSHKeyFileReference(id: UUID(), name: "Retained B", bookmark: Data([2]), fingerprint: keyB.fingerprint)
            let imported = TerminalNamedKey(id: UUID(), name: "Retained Imported", key: .create())
            // Simulate multiple retained identities after trial expiry. Admission
            // reads validated metadata and must not resolve or import private files.
            try TerminalSecretStore.write(JSONEncoder().encode(MacSSHKeyFileStore.Library(files: [fileA, fileB])), id: MacSSHKeyFileStore.storageID, kind: MacSSHKeyFileStore.kind)
            try TerminalSecretStore.write(JSONEncoder().encode(TerminalKeyLibraryStore.Library(keys: [imported])), id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, kind: "key-library-v2")
            XCTAssertFalse(access.hasPro)
            try MacSSHKeyFileStore.chooseFreeKey(fileA.id, access: access)
            XCTAssertTrue(try MacSSHKeyFileStore.canUse(fileA, access: access))
            XCTAssertFalse(try MacSSHKeyFileStore.canUse(fileB, access: access))
            try MacSSHKeyFileStore.chooseFreeKey(fileB.id, access: access)
            XCTAssertTrue(try MacSSHKeyFileStore.canUse(fileB, access: access))
            XCTAssertFalse(try TerminalKeyLibraryStore.canUse(imported, access: access))
            XCTAssertTrue(try MacSSHKeyFileStore.canUse(fileB, access: access), "Denied imported selection must not silently replace the disk free key")
            XCTAssertThrowsError(try MacSSHKeyFileStore.chooseFreeKey(UUID(), access: access))
            XCTAssertTrue(try MacSSHKeyFileStore.canUse(fileB, access: access), "A stale choice leaves the free identity unchanged")
            XCTAssertEqual(try TerminalKeyLibraryStore.userKeyIDs().count, 3)
            XCTAssertFalse(access.canAddKey(count: try TerminalKeyLibraryStore.userKeyIDs().count))
            XCTAssertThrowsError(try TerminalKeyLibraryStore.addForUser(.create(), name: "New Identity", access: access))
            XCTAssertEqual(try TerminalKeyLibraryStore.addForUser(keyB, name: "Same Identity", access: access), fileB.id)
            XCTAssertEqual(try TerminalKeyLibraryStore.userKeyIDs().count, 3, "Importing an existing reference does not consume another slot")
            try MacSSHKeyFileStore.chooseFreeKey(fileB.id, access: access)
            XCTAssertTrue(try MacSSHKeyFileStore.canUse(fileB, access: access), "Free choice uses the canonical imported identity")
        }
    }
}

private extension DirectMacDetectedIdentity {
    func replacingModel(_ model: String) -> Self { var copy = self; copy.modelIdentifier = model; return copy }
}
