import AppKit
import XCTest
import Crypto
import NIO
import NIOSSH
import Citadel
import SwiftTerm
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

private final class InputTestWindow: NSWindow {
    var inputKeyWindow = false
    override var isKeyWindow: Bool { inputKeyWindow }
}
private final class InputTestScroll: NSEvent {
    nonisolated(unsafe) var owner: NSWindow?
    override var window: NSWindow? { owner }
    override var type: NSEvent.EventType { .scrollWheel }
    override var locationInWindow: NSPoint { NSPoint(x: 100, y: 100) }
    override var scrollingDeltaY: CGFloat { 1 }
    override var hasPreciseScrollingDeltas: Bool { false }
    override var modifierFlags: NSEvent.ModifierFlags { [] }
}
@MainActor private final class InputCapture: NSObject, @preconcurrency TerminalViewDelegate {
    var sent: [UInt8] = []
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        guard let surface = source as? MacRemoteTerminalSurface, surface.admitGeneratedOutput(data) else { return }
        sent += data
    }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
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
        registry.update(id: desktop, macID: otherMachine, mode: .terminal, phase: .disconnected, window: window)
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
        let session = MacVNCSession(mac: mac, removeSavedLogin: { _ in throw DesktopCredentialStoreV1.StoreFailure.unavailable })
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
        let owner = MacVNCSession(mac: snapshot)
        XCTAssertEqual(owner.mac.name, "Original"); XCTAssertEqual(owner.mac.addresses, ["mac.local"])
        owner.close()
    }

    func testMacModeFallbackPreservesSharedDefaultsAndRestoredWindowIdentity() throws {
        let directory = try XCTUnwrap(ProcessInfo.processInfo.environment["MACCOMPANION_NATIVE_FIXTURE_DIRECTORY"])
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: directory).appending(path: "native-macos-client-v1.json"))) as! [String: Any]
        let modes = try XCTUnwrap(fixture["connectionModes"] as? [String: Any])
        XCTAssertEqual(MacConnectionMode.allCases.map(\.rawValue), modes["supported"] as? [String])
        // macOS reads a compatible iPhone record, edits unrelated fields, then
        // persists it without silently changing the iPhone's Trackpad default.
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "macs.json")
        let library = DirectMacLibraryV1(url: url, removeLogin: { _ in })
        for value in try XCTUnwrap(modes["sharedDefaults"] as? [[String: String]]) {
            let shared = try XCTUnwrap(DirectMacConnection(rawValue: try XCTUnwrap(value["shared"])))
            let id = UUID()
            XCTAssertTrue(library.save(id: id, name: "Original", addresses: ["fixture.local"], preferredConnection: shared))
            var preference = MacConnectionPreference(shared)
            XCTAssertEqual(preference.mode.rawValue, value["native"])
            XCTAssertTrue(library.save(id: id, name: "Renamed", addresses: ["other.local"], preferredConnection: preference.shared))
            let reloaded = DirectMacLibraryV1(url: url, removeLogin: { _ in })
            XCTAssertEqual(reloaded.macs.first { $0.id == id }?.preferredConnection, shared)
            for selected in MacConnectionMode.allCases {
                preference.mode = selected
                XCTAssertEqual(preference.shared, selected.shared)
            }
        }
        for value in try XCTUnwrap(modes["restoredWindows"] as? [[String: String]]) {
            let id = UUID(), machine = UUID()
            let data = try JSONSerialization.data(withJSONObject: ["id": id.uuidString, "macID": machine.uuidString, "mode": try XCTUnwrap(value["stored"])])
            let request = try JSONDecoder().decode(MacSessionRequest.self, from: data)
            XCTAssertEqual(request.id, id); XCTAssertEqual(request.macID, machine)
            XCTAssertEqual(request.mode.rawValue, value["native"])
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: String]
            XCTAssertEqual(encoded["mode"], value["native"])
        }
        XCTAssertThrowsError(try JSONDecoder().decode(MacConnectionMode.self, from: Data("\"unknown\"".utf8)))
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
    func testTerminalClipboardLockAndHeldInputCleanupOverRealSSH() async throws {
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
        first.answerTrust(true); try await wait { first.connected || !first.connecting }
        XCTAssertTrue(first.connected, first.status)
        second.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { second.connected || !second.connecting }
        XCTAssertTrue(second.connected, second.status)
        let record = try XCTUnwrap(records.connections.first)
        let view = MacRemoteTerminalSurface(frame: CGRect(x: 0, y: 0, width: 700, height: 440), font: .monospacedSystemFont(ofSize: 14, weight: .regular))
        let coordinator = MacTerminalSurface.Coordinator(session: first)
        view.session = first; view.terminalDelegate = coordinator
        first.suspendInput = { [weak view] in view?.releaseHeldInput() }
        let window = InputTestWindow(contentRect: view.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view; window.inputKeyWindow = true
        defer { window.close(); view.detachInputGate() }
        window.makeFirstResponder(view)
        var allowed = true
        view.accessAllowed = { allowed }
        let pasteboard = NSPasteboard(name: .init("synthetic-copy-" + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        view.copyPasteboard = pasteboard
        view.feed(text: "synthetic-private-output")
        view.selectAll(); view.copy(view)
        XCTAssertTrue(try XCTUnwrap(pasteboard.string(forType: .string)).contains("synthetic-private-output"))
        pasteboard.clearContents(); pasteboard.setString("synthetic-sentinel", forType: .string)
        allowed = false
        view.copy(view)
        XCTAssertEqual(pasteboard.string(forType: .string), "synthetic-sentinel", "Copy must check lock at execution even while selection/responder remain")
        let copy = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "")
        XCTAssertFalse(view.validateUserInterfaceItem(copy))
        view.lockLocalActions()
        XCTAssertNil(view.getSelection()); XCTAssertFalse(window.firstResponder === view)

        // Find uses a window field editor, which has its own Copy action.
        // Exercise that real AppKit responder with private synthetic text.
        allowed = true
        let field = NSTextField(string: "synthetic-private-find")
        view.addSubview(field); field.selectText(nil)
        XCTAssertTrue((window.firstResponder as? NSTextView)?.isFieldEditor == true)
        allowed = false; view.lockLocalActions()
        XCTAssertEqual(field.stringValue, "")
        XCTAssertFalse((window.firstResponder as? NSTextView)?.isFieldEditor == true)
        field.removeFromSuperview()

        allowed = true; window.makeFirstResponder(view)
        view.feed(text: "\u{1b}[>10u\u{1b}[?1000h\u{1b}[?1006h")
        XCTAssertTrue(view.getTerminal().keyboardEnhancementFlags.contains(.reportEvents))
        func key(_ type: NSEvent.EventType, repeatKey: Bool = false) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "\u{f700}", charactersIgnoringModifiers: "\u{f700}", isARepeat: repeatKey, keyCode: 126))
        }
        let press = Array("\u{1b}[A".utf8), release = Array("\u{1b}[1;1:3A".utf8)
        view.keyDown(with: try key(.keyDown))
        try await wait("admitted Kitty press") { record.received == press }
        window.makeFirstResponder(window)
        view.keyUp(with: try key(.keyUp))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        try await wait("one Kitty release on focus loss") { record.received == press + release }
        window.makeFirstResponder(view)
        view.keyDown(with: try key(.keyDown)); view.keyUp(with: try key(.keyUp))
        window.makeFirstResponder(window)
        try await wait("normal key-up removes held entry") { record.received == press + release + press + release }

        // Only the first owner's outstanding press may be released while local
        // input is suspended. Protocol cursor replies are never held keys.
        window.makeFirstResponder(view)
        view.feed(text: "\u{1b}[6n")
        try await wait("cursor protocol reply") { record.received.count > 2 * (press.count + release.count) }
        let before = record.received
        view.keyDown(with: try key(.keyDown))
        try await wait("press before lock") { record.received == before + press }
        allowed = false; first.background(); view.lockLocalActions()
        second.send([66])
        try await wait("locked cleanup reaches original SSH only") {
            record.received == before + press + release && records.connections[1].received == [66]
        }
        XCTAssertTrue(second.connected)
        allowed = true; first.foreground()
        try await wait("foreground resumes") { !first.suspended }
        window.makeFirstResponder(view)
        let mouse = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 100, y: 100),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let beforeMouse = record.received
        view.mouseDown(with: mouse)
        try await wait("admitted SGR button press") { record.received.count > beforeMouse.count }
        let mousePress = Array(record.received.dropFirst(beforeMouse.count))
        XCTAssertEqual(mousePress.last, 77)
        let mouseRelease = Array(mousePress.dropLast()) + [UInt8(109)]
        window.inputKeyWindow = false
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        try await wait("SGR release on key-window loss") { record.received == beforeMouse + mousePress + mouseRelease }
        view.releaseHeldInput()

        first.stop()
        first.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { first.connected || !first.connecting }
        XCTAssertTrue(first.connected, first.status)
        XCTAssertEqual(records.connections.count, 3)
        view.releaseHeldInput(); first.resize(columns: 101, rows: 31)
        try await wait("replacement shell ready") { records.connections[2].size == [101, 31] }
        XCTAssertTrue(records.connections[2].received.isEmpty, "Retired reports must never replay into a replacement SSH shell")
        first.stop(); second.stop(); try await server.close()
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
        if !checkNativeFocus { try await verifyPointerAdmission(session: first) }
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

    private func verifyPointerAdmission(session: DirectTerminalSession) async throws {
        let directory = try XCTUnwrap(ProcessInfo.processInfo.environment["MACCOMPANION_NATIVE_FIXTURE_DIRECTORY"])
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: directory).appending(path: "native-macos-client-v1.json"))) as! [String: Any]
        let cases = try XCTUnwrap(fixture["terminalInputAdmission"] as? [[String: Bool]])
        let view = MacRemoteTerminalSurface(frame: CGRect(x: 0, y: 0, width: 700, height: 440), font: .monospacedSystemFont(ofSize: 14, weight: .regular))
        view.session = session
        let capture = InputCapture(); view.terminalDelegate = capture
        let window = InputTestWindow(contentRect: view.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { window.close() }
        view.feed(text: "\u{1b}[?1000h\u{1b}[?1006h")
        let scroll = InputTestScroll(); scroll.owner = window
        for value in cases {
            window.inputKeyWindow = try XCTUnwrap(value["keyWindow"])
            let responder = try XCTUnwrap(value["terminalResponder"])
            window.makeFirstResponder(responder ? view : window)
            XCTAssertEqual(window.firstResponder === view, responder)
            capture.sent = []
            let admitted = view.filterInputEvent(scroll)
            XCTAssertEqual(admitted != nil, value["admitted"])
            if let admitted { view.scrollWheel(with: admitted) }
            XCTAssertEqual(!capture.sent.isEmpty, value["admitted"])
        }
        window.inputKeyWindow = false
        window.makeFirstResponder(window)
        view.feed(text: "\u{1b}[?1004h")
        capture.sent = []
        let click = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 100, y: 100),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        view.mouseDown(with: click)
        XCTAssertTrue(capture.sent.isEmpty, "A mouse press in an inactive window cannot report remote input")
        XCTAssertFalse(window.firstResponder === view, "A rejected click cannot emit a remote focus report")
        view.feed(text: "\u{1b}[?1003h")
        let movement = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: 100, y: 100),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 0, pressure: 0))
        view.mouseMoved(with: movement)
        XCTAssertTrue(capture.sent.isEmpty, "SwiftTerm's synthesized movement must be gated independently of monitor ordering")
        view.feed(text: "\u{1b}[c")
        XCTAssertFalse(capture.sent.isEmpty, "Terminal protocol replies must continue in background windows")
        // Another control in this window must retain its own wheel events.
        let container = NSView(frame: view.bounds)
        window.contentView = container; container.addSubview(view)
        let other = NSView(frame: view.bounds); container.addSubview(other)
        XCTAssertNotNil(view.filterInputEvent(scroll))
        // OSC133 cursor navigation otherwise queues arrow keys until the
        // double-click delay, after this window may have lost input focus.
        let semanticView = MacRemoteTerminalSurface(frame: view.frame, font: view.font)
        semanticView.session = session; semanticView.terminalDelegate = capture
        window.contentView = semanticView; window.inputKeyWindow = true
        window.makeFirstResponder(semanticView)
        semanticView.feed(text: "\u{1b}]133;A;cl=line\u{7}>\u{1b}]133;B\u{7}hello")
        let terminal = semanticView.getTerminal()
        let point = NSPoint(x: 1.5 * semanticView.frame.width / CGFloat(terminal.cols),
                            y: semanticView.frame.height - 0.5 * semanticView.frame.height / CGFloat(terminal.rows))
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 3, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 4, clickCount: 1, pressure: 0))
        capture.sent = []
        semanticView.mouseDown(with: down); semanticView.mouseUp(with: up)
        window.inputKeyWindow = false; window.makeFirstResponder(window)
        try await Task.sleep(for: .seconds(NSEvent.doubleClickInterval + 0.1))
        XCTAssertTrue(capture.sent.isEmpty, "A prompt click cannot queue cursor keys into a background connection")
    }
}
