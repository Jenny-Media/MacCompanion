import AppKit
import XCTest
import Crypto
import NIO
import NIOSSH
import Citadel
@testable import MacCompanion

private final class MemoryCloud: DirectCloudTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]
    private var unavailable = false
    var offline: Bool {
        get { lock.lock(); defer { lock.unlock() }; return unavailable }
        set { lock.lock(); unavailable = newValue; lock.unlock() }
    }
    func read() throws -> [Data] {
        lock.lock(); defer { lock.unlock() }
        if unavailable { throw DirectCloudError.storage }
        return Array(storage.values)
    }
    func write(_ data: Data, account: String) throws {
        lock.lock(); defer { lock.unlock() }
        if unavailable { throw DirectCloudError.storage }
        storage[account] = data
    }
    func removeAll() throws { lock.lock(); defer { lock.unlock() }; storage = [:] }
}

private final class SSHConnections: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [SSHTestRecord] = []
    func accepted(_ channel: Channel) -> SSHTestRecord {
        let record = SSHTestRecord(); record.openedTransport(channel)
        lock.lock(); records.append(record); lock.unlock(); return record
    }
    var connections: [SSHTestRecord] { lock.lock(); defer { lock.unlock() }; return records }
}

@MainActor final class NativeClientTests: XCTestCase {
    func testConnectionRegistryTracksOwnersAndClosingPreservesOtherModes() throws {
        let registry = MacConnectionRegistry(), machine = UUID(), otherMachine = UUID()
        let desktop = UUID(), terminal = UUID(), otherTerminal = UUID()
        let window = MacWindowHandle()
        registry.update(id: desktop, macID: machine, mode: .desktop, phase: .connecting, window: window)
        registry.update(id: terminal, macID: machine, mode: .terminal, phase: .connected, window: window)
        registry.update(id: otherTerminal, macID: otherMachine, mode: .terminal, phase: .connected, window: window)
        registry.update(id: desktop, macID: machine, mode: .desktop, phase: .connected, window: window)
        XCTAssertEqual(registry.connections(for: machine).map(\.phase), [.connected, .connected])
        // A stale update cannot retarget the UUID to another machine or mode.
        registry.update(id: desktop, macID: otherMachine, mode: .trackpad, phase: .disconnected, window: window)
        XCTAssertEqual(registry.connections(for: machine).count, 2)
        registry.remove(desktop)
        XCTAssertEqual(registry.connections(for: machine).map(\.id), [terminal])
        XCTAssertEqual(registry.connections(for: otherMachine).map(\.id), [otherTerminal])
    }
    func testVNCLoginRetentionMatchesIPhoneBeforeDial() throws {
        let id = UUID(), login = DesktopCredentialStoreV1.Login(username: "synthetic", password: "synthetic-only")
        try DesktopCredentialStoreV1.save(login, hostID: id)
        defer { try? DesktopCredentialStoreV1.remove(id) }
        for invalid in [String(repeating: "x", count: 64), "\0", String(repeating: "你", count: 22)] {
            XCTAssertThrowsError(try MacLoginPolicy.prepareVNC(username: invalid, password: login.password, remember: false, macID: id))
            XCTAssertEqual(try DesktopCredentialStoreV1.readChecked(id)?.password, login.password)
        }
        try MacLoginPolicy.prepareVNC(username: login.username, password: login.password, remember: true, macID: id)
        XCTAssertNotNil(try DesktopCredentialStoreV1.readChecked(id))
        try MacLoginPolicy.prepareVNC(username: login.username, password: login.password, remember: false, macID: id)
        XCTAssertNil(try DesktopCredentialStoreV1.readChecked(id))
    }
    func testVNCLoginRemovalFailureDoesNotStartItsConnection() {
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic", addresses: ["127.0.0.1"])
        let session = MacVNCSession(mac: mac, inputOnly: false, removeSavedLogin: { _ in throw DesktopCredentialStoreV1.StoreFailure.unavailable })
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        XCTAssertFalse(session.connecting); XCTAssertFalse(session.connected)
        XCTAssertEqual(session.recovery?.reason, .removeFailed)
        session.close()
    }
    func testNewSSHLoginRechecksTheDisplayedKeyAgainstCurrentFreeKeyChoice() throws {
        let suite = UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let access = DirectProAccess(defaults: defaults)
        let first = TerminalNamedKey(id: UUID(), name: "First", key: .create())
        let second = TerminalNamedKey(id: UUID(), name: "Second", key: .create())
        let entries = [first, second]
        access.chooseFreeKey(first.id)
        XCTAssertTrue(try MacLoginPolicy.canUseSSHKey(first.key, access: access, keys: { entries }))
        XCTAssertFalse(try MacLoginPolicy.canUseSSHKey(second.key, access: access, keys: { entries }))
        access.chooseFreeKey(second.id)
        XCTAssertFalse(try MacLoginPolicy.canUseSSHKey(first.key, access: access, keys: { entries }))
        XCTAssertTrue(try MacLoginPolicy.canUseSSHKey(second.key, access: access, keys: { entries }))
        XCTAssertThrowsError(try MacLoginPolicy.canUseSSHKey(first.key, access: access, keys: { [second] }))
        XCTAssertThrowsError(try MacLoginPolicy.canUseSSHKey(first.key, access: access, keys: { throw TerminalSecretStore.Failure.storage }))
    }
    private func wait(_ message: String = "operation", _ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 { if condition() { return }; try await Task.sleep(for: .milliseconds(10)) }
        XCTFail("Native client timed out: \(message)"); throw POSIXError(.ETIMEDOUT)
    }
    func testCompatibleCloudRecordsOfflineRecoveryConflictAndDeletion() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let suiteA = UUID().uuidString, suiteB = UUID().uuidString
        let a = try XCTUnwrap(UserDefaults(suiteName: suiteA)), b = try XCTUnwrap(UserDefaults(suiteName: suiteB))
        defer { a.removePersistentDomain(forName: suiteA); b.removePersistentDomain(forName: suiteB); try? FileManager.default.removeItem(at: directory) }
        let libraryA = DirectMacLibraryV1(url: directory.appending(path: "a.json"), removeLogin: { _ in })
        let libraryB = DirectMacLibraryV1(url: directory.appending(path: "b.json"), removeLogin: { _ in })
        let id = UUID(), transport = MemoryCloud()
        // Two devices have independent preference stores and notification
        // centers. Avoid treating the other simulated device's apply as a new
        // local user edit in this single hosted process.
        let cloudA = DirectCloudSyncV1(defaults: a, url: directory.appending(path: "journal-a.json"), transport: transport, writerID: UUID(), applyPreferences: { _, _ in })
        let cloudB = DirectCloudSyncV1(defaults: b, url: directory.appending(path: "journal-b.json"), transport: transport, writerID: UUID(), applyPreferences: { _, _ in })
        cloudA.attach(libraryA); cloudB.attach(libraryB)
        defer { cloudA.setEnabled(false); cloudB.setEnabled(false); VNCSessionPreferences.clear(id) }
        XCTAssertFalse(cloudA.enabled); XCTAssertFalse(cloudB.enabled)
        XCTAssertTrue(libraryA.save(id: id, name: "Synthetic Mac", addresses: ["100.100.1.2", "mac.local"], port: 5901, sshPort: 2222, preferredConnection: .terminal))
        cloudA.setEnabled(true); try await wait { !cloudA.busy }
        cloudB.setEnabled(true); try await wait { !cloudB.busy }
        XCTAssertEqual(libraryA.macs, libraryB.macs)
        for bytes in try transport.read() {
            let version = try JSONDecoder().decode(DirectCloudVersion.self, from: bytes)
            XCTAssertEqual(version.schema, 1); try version.validate()
            let text = String(decoding: bytes, as: UTF8.self)
            for forbidden in ["password", "privateKey", "seed", "username", "host-key"] { XCTAssertFalse(text.contains(forbidden)) }
        }
        transport.offline = true
        XCTAssertTrue(libraryA.save(id: id, name: "Offline A", addresses: ["100.100.1.3"]))
        try await wait { !cloudA.busy }; XCTAssertEqual(cloudA.recovery?.reason, .cloudUnavailable)
        XCTAssertEqual(libraryA.macs.first?.name, "Offline A")
        XCTAssertTrue(libraryB.save(id: id, name: "Offline B", addresses: ["100.100.1.4"]))
        try await wait { !cloudB.busy }
        transport.offline = false
        cloudA.refresh(); try await wait { !cloudA.busy }
        cloudB.refresh(); try await wait { !cloudB.busy }
        cloudA.refresh(); try await wait { !cloudA.busy }
        XCTAssertEqual(libraryA.macs, libraryB.macs)
        let versions = try transport.read().map { try JSONDecoder().decode(DirectCloudVersion.self, from: $0) }
        let winner = try XCTUnwrap(DirectCloudVersion.winners(versions)[id])
        // Upload a valid, newer deletion using the same format used by iPhone.
        let deletion = DirectCloudVersion(id: id, writer: UUID(), revision: winner.revision + 1, mac: nil, preferences: nil)
        try transport.write(JSONEncoder().encode(deletion), account: deletion.account)
        cloudA.refresh(); try await wait { !cloudA.busy }; cloudB.refresh(); try await wait { !cloudB.busy }
        XCTAssertTrue(libraryA.macs.isEmpty); XCTAssertTrue(libraryB.macs.isEmpty)
    }

    func testMacCloudStorageRefusesAnUnadmittedSharedGroup() {
        // The QA app is deliberately not admitted to the signed
        // iPhone group. Failure must remain visible rather than silently using a
        // different sync store. This does not prove signed iCloud delivery.
        XCTAssertThrowsError(try DirectCloudKeychain(service: "synthetic-only." + UUID().uuidString).read())
    }

    func testFreshWindowIdentityAllowsSameMacMultipleModesAndRepeatedMode() throws {
        let mac = UUID()
        let first = MacSessionRequest(macID: mac, mode: .desktop)
        let second = MacSessionRequest(macID: mac, mode: .terminal)
        let third = MacSessionRequest(macID: mac, mode: .desktop)
        XCTAssertEqual(Set([first, second, third]).count, 3)
        XCTAssertEqual(try JSONDecoder().decode(MacSessionRequest.self, from: JSONEncoder().encode(second)), second)
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = DirectMacLibraryV1(url: folder.appending(path: "macs.json"))
        XCTAssertTrue(library.save(id: mac, name: "Original", address: "mac.local"))
        let snapshot = try XCTUnwrap(library.macs.first)
        XCTAssertTrue(library.save(id: mac, name: "Renamed", address: "other.local"))
        let owner = MacVNCSession(mac: snapshot, inputOnly: false)
        XCTAssertEqual(owner.mac.name, "Original"); XCTAssertEqual(owner.mac.addresses, ["mac.local"])
        owner.close()
    }

    func testOwnWindowCloseIsDeliveredOnce() {
        var firstClosed = 0, secondClosed = 0
        let first = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let second = NSWindow(contentRect: NSRect(x: 350, y: 0, width: 320, height: 240), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        first.isReleasedWhenClosed = false; second.isReleasedWhenClosed = false
        let firstObserver = MacWindowLifetime.Observer { firstClosed += 1 }
        let secondObserver = MacWindowLifetime.Observer { secondClosed += 1 }
        first.contentView = firstObserver; second.contentView = secondObserver
        first.close(); firstObserver.finish()
        XCTAssertEqual(firstClosed, 1); XCTAssertEqual(secondClosed, 0)
        second.close(); secondObserver.finish(); XCTAssertEqual(secondClosed, 1)
    }

    func testRealSSHIndependentSessionsResizeCloseAndRecovery() async throws {
        try await runTwoSessions(checkNativeFocus: false)
    }
    func testNativeTerminalWindowFocusRoutesOnlyItsOwnInput() async throws {
        try await runTwoSessions(checkNativeFocus: true)
    }
    private func runTwoSessions(checkNativeFocus: Bool) async throws {
        let records = SSHConnections(), hostKey = NIOSSHPrivateKey(ed25519Key: .init())
        let server = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton).childChannelInitializer { channel in
            let record = records.accepted(channel)
            return channel.pipeline.addHandler(NIOSSHHandler(role: .server(.init(hostKeys: [hostKey], userAuthDelegate: SSHTestAuth(record))), allocator: channel.allocator,
                inboundChildChannelInitializer: { child, _ in child.pipeline.addHandler(SSHTestPTY(record)) }))
        }.bind(host: "127.0.0.1", port: 0).get()
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic SSH", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let first = DirectTerminalSession(mac: mac), second = DirectTerminalSession(mac: mac)
        defer { first.stop(); second.stop(); try? TerminalSecretStore.remove(mac.id) }
        first.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { first.trust != nil || !first.connecting }
        XCTAssertNotNil(first.trust, first.status); XCTAssertEqual(records.connections.first?.passwordRequests, 0)
        first.answerTrust(true); try await wait { first.connected || !first.connecting }
        guard first.connected else { XCTFail(first.status); throw POSIXError(.ENOTCONN) }
        second.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { second.connected || !second.connecting }
        guard second.connected, records.connections.count == 2 else { XCTFail(second.status); throw POSIXError(.ENOTCONN) }
        let viewA = MacRemoteTerminalSurface(frame: CGRect(x: 0, y: 0, width: 700, height: 440), font: .monospacedSystemFont(ofSize: 14, weight: .regular))
        let viewB = MacRemoteTerminalSurface(frame: viewA.frame, font: viewA.font)
        viewA.session = first; viewB.session = second
        let coordinatorA = MacTerminalSurface.Coordinator(session: first), coordinatorB = MacTerminalSurface.Coordinator(session: second)
        viewA.terminalDelegate = coordinatorA; viewB.terminalDelegate = coordinatorB
        first.received = { [weak viewA] in viewA?.feed(byteArray: $0[...]) }
        second.received = { [weak viewB] in viewB?.feed(byteArray: $0[...]) }
        let windowA = NSWindow(contentRect: viewA.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        let windowB = NSWindow(contentRect: viewB.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        windowA.isReleasedWhenClosed = false; windowB.isReleasedWhenClosed = false
        windowA.contentView = viewA; windowB.contentView = viewB
        defer { windowA.close(); windowB.close(); viewA.detachInputGate(); viewB.detachInputGate() }
        if checkNativeFocus {
            let application = NSApplication.shared
            application.setActivationPolicy(.regular); application.activate(ignoringOtherApps: true)
            windowA.makeKeyAndOrderFront(nil); windowA.makeFirstResponder(viewA)
            for _ in 0..<100 {
                if windowA.isKeyWindow && windowA.firstResponder === viewA { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            guard windowA.isKeyWindow && windowA.firstResponder === viewA else {
                throw XCTSkip("The hosted test app cannot obtain native key-window focus in this session. Native UI keyboard acceptance remains open.")
            }
            viewA.insertText("A", replacementRange: NSRange(location: 0, length: 0))
            viewB.insertText("MUST-NOT-ROUTE", replacementRange: NSRange(location: 0, length: 0))
            try await wait("first focused input") { records.connections[0].received == [65] }
            XCTAssertTrue(records.connections[1].received.isEmpty)
            windowB.makeKeyAndOrderFront(nil); windowB.makeFirstResponder(viewB)
            try await wait("second window focus") { windowB.isKeyWindow && windowB.firstResponder === viewB }
            viewB.insertText("B", replacementRange: NSRange(location: 0, length: 0))
        } else {
            first.send([65]); second.send([66])
            try await wait("independent first input") { records.connections[0].received == [65] }
        }
        try await wait("second input") { records.connections[1].received == [66] }
        first.resize(columns: 101, rows: 31); second.resize(columns: 120, rows: 40)
        try await wait("independent resize") { records.connections[0].size == [101, 31] && records.connections[1].size == [120, 40] }
        first.stop(); windowA.close()
        XCTAssertTrue(second.connected)
        try await records.connections[1].emit("background output survives")
        if checkNativeFocus { viewB.insertText("C", replacementRange: NSRange(location: 0, length: 0)) }
        else { second.send([67]) }
        try await wait("second input after first closes") { records.connections[1].received == [66, 67] }
        try await records.connections[1].finish(status: nil, transportFailed: true)
        try await wait("lost SSH connection") { !second.connected }; XCTAssertNotNil(second.recovery)
        second.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { second.connected || !second.connecting }; XCTAssertTrue(second.connected, second.status)
        XCTAssertEqual(records.connections.count, 3)
        XCTAssertTrue(records.connections[2].received.isEmpty, "Input from the retired shell must not replay")
        second.stop(); try await server.close()
    }
}
