import XCTest
import SwiftUI
import StoreKitTest
import StoreKit
import Crypto
import NIO
import NIOSSH
import Citadel
import Darwin
import ActivityKit
import AppIntents
@testable import Mac_Companion

@MainActor private final class TerminalActivityTestBackend: RemoteSessionActivityBackend {
    var enabled = true
    var ids: [String] = []
    var attributes: RemoteSessionActivityAttributes?
    var phase: RemoteSessionActivityAttributes.Phase?
    var blocked = false
    var reply: CheckedContinuation<Void, Never>?
    func release() { blocked = false; let saved = reply; reply = nil; saved?.resume() }
    func existingIDs() -> [String] { ids }
    func start(_ attributes: RemoteSessionActivityAttributes, content: ActivityContent<RemoteSessionActivityAttributes.ContentState>) throws -> String {
        self.attributes = attributes; phase = content.state.phase; ids = ["terminal-synthetic"]; return ids[0]
    }
    func update(_ id: String, content: ActivityContent<RemoteSessionActivityAttributes.ContentState>) async { phase = content.state.phase; if blocked { await withCheckedContinuation { reply = $0 } } }
    func end(_ id: String) async { ids.removeAll { $0 == id } }
}
// Observe bytes, then forward them to the normal pipeline tail. Before the SSH
// parser exists this reproduces NIO's discarded early-banner path.
private final class SSHEarlyReadProbe: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    let record: SSHTestRecord
    init(_ record: SSHTestRecord) { self.record = record }
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        record.received(Array(unwrapInboundIn(data).readableBytesView))
        context.fireChannelRead(data)
    }
}
@MainActor private final class TerminalLoginFrameProbe: NSObject {
    private let window: UIWindow
    private var link: CADisplayLink?
    private(set) var frames = 0
    private(set) var credentialFrames = 0
    init(window: UIWindow) {
        self.window = window; super.init()
        let link = CADisplayLink(target: self, selector: #selector(sample)); self.link = link
        link.add(to: .main, forMode: .common)
    }
    func stop() { link?.invalidate(); link = nil }
    @objc private func sample() {
        frames += 1
        func visible(_ view: UIView) -> Bool {
            var parent: UIView? = view
            while let current = parent {
                if current.isHidden || current.alpha < 0.01 { return false }
                parent = current.superview
            }
            return view.window === window && !view.convert(view.bounds, to: window).intersection(window.bounds).isEmpty
        }
        func containsField(_ view: UIView) -> Bool {
            if view is UITextField, visible(view) { return true }
            return view.subviews.contains(where: containsField)
        }
        if containsField(window) { credentialFrames += 1 }
    }
}

@MainActor final class TerminalIntegrationTests:XCTestCase {
    func testSavedTerminalLoginDoesNotRevealCredentialFieldsBeforeOrAfterProgress() async throws {
        let record = SSHTestRecord(), hostKey = NIOSSHPrivateKey(ed25519Key: .init())
        let peer = try await server(record: record, key: hostKey)
        defer { _ = peer.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic saved login", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(peer.localAddress?.port))
        try TerminalSecretStore.save(.init(username: "synthetic", password: "synthetic-only"), id: mac.id)
        try TerminalSecretStore.approveHostKey(String(openSSHPublicKey: hostKey.publicKey), id: mac.id)
        let session = DirectTerminalSession(mac: mac), panel = DirectConnectionPanelHost()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first(where: { $0.activationState == .foregroundActive }))
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: DirectTerminalView(mac: mac, session: session, connectionPanel: panel, exit: {}).directAppearance()
            .background(DirectConnectionPanelAnchor(host: panel)))
        window.rootViewController = controller
        let probe = TerminalLoginFrameProbe(window: window)
        defer { probe.stop(); panel.close(); session.stop(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible(); try? TerminalSecretStore.remove(mac.id) }
        window.makeKeyAndVisible()
        try await wait { session.connected }
        try await wait { controller.presentedViewController == nil && !panel.isVisible }
        XCTAssertGreaterThan(probe.frames, 0)
        XCTAssertEqual(probe.credentialFrames, 0, "A saved auto-connect must not flash the username/password form, including while its progress sheet dismisses")
        XCTAssertEqual(record.passwordRequests, 1); XCTAssertEqual(record.shellRequests, 1)
    }

    func testDisconnectNeverReopensTerminalLoginDuringDeparture() async throws {
        for native in [true, false] { try await assertDepartureKeepsLoginHidden("disconnect", native: native) }
    }
    func testNormalShellExitNeverReopensTerminalLoginDuringDeparture() async throws {
        for native in [true, false] { try await assertDepartureKeepsLoginHidden("normal", native: native) }
    }
    func testLiveActivityDisconnectNeverReopensTerminalLoginDuringDeparture() async throws {
        for native in [true, false] { try await assertDepartureKeepsLoginHidden("activity", native: native) }
    }
    private func assertDepartureKeepsLoginHidden(_ departure: String, native: Bool) async throws {
        let record = SSHTestRecord(), hostKey = NIOSSHPrivateKey(ed25519Key: .init())
        let peer = try await server(record: record, key: hostKey)
        defer { _ = peer.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic departure", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(peer.localAddress?.port))
        try TerminalSecretStore.save(.init(username: "synthetic", password: "synthetic-only"), id: mac.id)
        try TerminalSecretStore.approveHostKey(String(openSSHPublicKey: hostKey.publicKey), id: mac.id)
        let backend = TerminalActivityTestBackend()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "terminal-departure-" + UUID().uuidString))
        defaults.set(true, forKey: VNCSessionActivityController.preferenceKey)
        let session = DirectTerminalSession(mac: mac, activityDefaults: defaults, activityBackend: backend)
        let panel = DirectConnectionPanelHost()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first(where: { $0.activationState == .foregroundActive }))
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        var exits = 0
        let host = UIHostingController(rootView: DirectTerminalView(mac: mac, session: session, connectionPanel: native ? panel : nil, exit: {
            panel.close(); exits += 1
        }).directAppearance().background(DirectConnectionPanelAnchor(host: panel)))
        window.rootViewController = host; window.makeKeyAndVisible()
        let probe = TerminalLoginFrameProbe(window: window)
        defer { probe.stop(); panel.close(); session.stop(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible(); try? TerminalSecretStore.remove(mac.id) }
        try await wait { session.connected && host.presentedViewController == nil && !panel.isVisible }
        // Keep the outgoing SwiftUI owner mounted after its exit callback. Native
        // dismissal and parent navigation can finish on a later render frame.
        switch departure {
        case "disconnect":
            func terminal(in controller: UIViewController) -> TerminalController? {
                if let terminal = controller as? TerminalController { return terminal }
                return controller.children.compactMap { terminal(in: $0) }.first
            }
            let controller = try XCTUnwrap(terminal(in: host))
            controller.controls.actionHandler?(["kind": "exit"])
        case "normal": try await record.finish(status: 0)
        default:
            await session.waitForLifecycleUpdates()
            XCTAssertEqual(backend.ids, ["terminal-synthetic"])
            NotificationCenter.default.post(name: RemoteSessionActivityActions.endRequested, object: "terminal-synthetic")
        }
        try await wait { exits == 1 && !session.connected }
        // A queued redraw, unlock or stale status action must not resurrect the form.
        NotificationCenter.default.post(name: DirectAppLockV1.unlocked, object: nil)
        NotificationCenter.default.post(name: RemoteSessionActivityActions.endRequested, object: "terminal-synthetic")
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(exits, 1, "Exit is delivered once: \(departure), native=\(native)")
        XCTAssertGreaterThan(probe.frames, 0)
        XCTAssertEqual(probe.credentialFrames, 0, "No username/password frames during \(departure), native=\(native)")
        XCTAssertFalse(panel.isVisible, "An outgoing owner must not present another login sheet")
        XCTAssertNil(host.presentedViewController)
        XCTAssertEqual(record.passwordRequests, 1); XCTAssertEqual(record.shellRequests, 1)
    }

    func testNativeTerminalLoginStillAppearsForMissingOrRejectedCredentialsAndLossOffersRecovery() async throws {
        for outcome in ["missing", "rejected", "lost"] {
            let record = SSHTestRecord(), hostKey = NIOSSHPrivateKey(ed25519Key: .init())
            let peer = try await server(record: record, key: hostKey)
            defer { _ = peer.close() }
            let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic login control", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(peer.localAddress?.port))
            if outcome != "missing" {
                try TerminalSecretStore.save(.init(username: "synthetic", password: outcome == "rejected" ? "wrong-synthetic" : "synthetic-only"), id: mac.id)
            }
            try TerminalSecretStore.approveHostKey(String(openSSHPublicKey: hostKey.publicKey), id: mac.id)
            let session = DirectTerminalSession(mac: mac), panel = DirectConnectionPanelHost()
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first(where: { $0.activationState == .foregroundActive }))
            let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
            let host = UIHostingController(rootView: DirectTerminalView(mac: mac, session: session, connectionPanel: panel,
                exit: { XCTFail("A genuine login/recovery state must remain available") }).directAppearance()
                .background(DirectConnectionPanelAnchor(host: panel)))
            window.rootViewController = host; window.makeKeyAndVisible()
            let probe = TerminalLoginFrameProbe(window: window)
            defer { probe.stop(); panel.close(); session.stop(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible(); try? TerminalSecretStore.remove(mac.id) }
            if outcome == "lost" {
                try await wait(outcome + " authenticated handoff") { session.connected && !panel.isVisible && host.presentedViewController == nil }
                try await record.finish(status: nil, transportFailed: true)
                try await wait(outcome + " visible recovery") { session.recovery?.reason == .terminalEnded && panel.isVisible }
                XCTAssertEqual(record.passwordRequests, 1); XCTAssertEqual(record.shellRequests, 1)
            } else {
                try await wait(outcome + " visible credentials") { panel.isVisible && probe.credentialFrames > 0 }
                if outcome == "rejected" {
                    XCTAssertEqual(session.recovery?.reason, .loginRejected)
                    XCTAssertGreaterThan(record.passwordRequests, 0)
                } else { XCTAssertEqual(record.passwordRequests, 0) }
            }
            XCTAssertNotNil(host.presentedViewController)
            // A mounted rejected-login owner is allowed to show credentials on
            // redraw. Retire it, as cancellation does, before closing its sheet.
            probe.stop(); window.rootViewController = nil; session.stop()
            panel.close()
            try await wait(outcome + " completed dismissal") { host.presentedViewController == nil }
        }
    }

    func testNativeConnectionSheetKeepsTerminalOwnerThroughTrustAndShellHandoff() async throws {
        let record = SSHTestRecord(), hostKey = NIOSSHPrivateKey(ed25519Key: .init())
        let peer = try await server(record: record, key: hostKey)
        defer { _ = peer.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic native sheet", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(peer.localAddress?.port))
        let session = DirectTerminalSession(mac: mac), panel = DirectConnectionPanelHost()
        var draft = DirectFilesLoginDraft(); draft.username = "synthetic"; draft.password = "synthetic-only"; draft.remember = false
        let form = DirectTerminalLoginForm(draft: draft)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first(where: { $0.activationState == .foregroundActive }))
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let controller = UIHostingController(rootView: DirectTerminalView(mac: mac, session: session, loginForm: form,
            connectionPanel: panel, loginRetentionAllowed: false, connectionEstablished: { false }, exit: {}).directAppearance()
            .background(DirectConnectionPanelAnchor(host: panel)))
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { panel.close(); session.stop(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible(); try? TerminalSecretStore.remove(mac.id) }
        try await wait { session.trust != nil && panel.isVisible }
        XCTAssertEqual(record.passwordRequests, 0, "No credentials precede explicit server trust")
        session.answerTrust(true)
        try await wait { session.connected && !panel.isVisible }
        session.send(Array("native-sheet-owner-survived".utf8))
        try await wait { String(decoding: record.received, as: UTF8.self).contains("native-sheet-owner-survived") }
        XCTAssertEqual(record.passwordRequests, 1); XCTAssertEqual(record.shellRequests, 1)
        XCTAssertNil(try TerminalSecretStore.login(mac.id))
        XCTAssertFalse(session.saveMacRequested); XCTAssertNil(session.textSendNotice, "An intentional temporary session has no save failure")
    }

    func testQuickConnectionCommitsMacOnlyAfterShellIsReadyAndControlsLoginRetention() async throws {
        for saveMac in [false, true] {
            let record = SSHTestRecord(), hostKey = NIOSSHPrivateKey(ed25519Key: .init())
            let peer = try await server(record: record, key: hostKey)
            defer { _ = peer.close() }
            let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic quick connection", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(peer.localAddress?.port))
            try TerminalSecretStore.approveHostKey(String(openSSHPublicKey: hostKey.publicKey), id: mac.id)
            let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
            let library = DirectMacLibraryV1(url: directory.appending(path: "macs.json"), removeLogin: { _ in })
            let session = DirectTerminalSession(mac: mac)
            defer { session.stop(); try? TerminalSecretStore.remove(mac.id); try? FileManager.default.removeItem(at: directory) }
            var commits = 0
            session.saveMacRequested = saveMac
            session.connectionEstablished = {
                XCTAssertEqual(record.passwordRequests, 1, "Saving cannot precede successful SSH authentication and PTY channel creation")
                XCTAssertNil(DesktopCredentialStoreV1.read(mac.id), "Login retention follows the Mac save decision")
                commits += 1
                guard saveMac else { return false }
                return library.save(id: mac.id, name: mac.name, addresses: mac.addresses, sshPort: mac.sshPort)
            }
            session.connect(username: "synthetic", password: "synthetic-only", remember: saveMac)
            XCTAssertTrue(library.macs.isEmpty)
            try await wait { session.connected && record.shellRequests == 1 }
            XCTAssertEqual(commits, 1); XCTAssertEqual(library.macs.count, saveMac ? 1 : 0)
            XCTAssertEqual(try TerminalSecretStore.login(mac.id)?.password, saveMac ? "synthetic-only" : nil)
            XCTAssertNil(session.textSendNotice, "Successful saves and intentional temporary sessions must remain quiet")
            session.background(); await session.waitForLifecycleUpdates(); session.foreground()
            try await wait { !session.suspended }
            session.send(Array("quick-connection-pause-recovery".utf8))
            try await wait { String(decoding: record.received, as: UTF8.self).contains("quick-connection-pause-recovery") }
            XCTAssertEqual(record.passwordRequests, 1); XCTAssertEqual(commits, 1)
        }
    }
    func testFailedQuickConnectionMacSaveDoesNotRetainLoginOrCloseWorkingShell() async throws {
        for remember in [false, true] {
            let record = SSHTestRecord(), hostKey = NIOSSHPrivateKey(ed25519Key: .init())
            let peer = try await server(record: record, key: hostKey)
            defer { _ = peer.close() }
            let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic save failure", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(peer.localAddress?.port))
            try TerminalSecretStore.approveHostKey(String(openSSHPublicKey: hostKey.publicKey), id: mac.id)
            let session = DirectTerminalSession(mac: mac)
            defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
            var commits = 0
            session.saveMacRequested = true
            session.connectionEstablished = { commits += 1; return false }
            session.connect(username: "synthetic", password: "synthetic-only", remember: remember)
            try await wait { session.connected }
            XCTAssertEqual(commits, 1)
            XCTAssertNil(try TerminalSecretStore.login(mac.id)); XCTAssertEqual(session.textSendNotice?.reason, .saveFailed)
            XCTAssertEqual(session.textSendNotice?.title, "Mac wasn’t saved")
            XCTAssertEqual(session.textSendNotice?.message.contains("Your login wasn’t saved."), remember)
            XCTAssertNil(session.recovery); XCTAssertTrue(session.connected)
            session.send(Array("working-after-save-failure".utf8))
            try await wait { String(decoding: record.received, as: UTF8.self).contains("working-after-save-failure") }
        }
    }

    func testHostedCredentialReturnAfterUnexpectedEndKeepsPauseRecoveryAndDoesNotReconnect() async throws {
        for remember in [true, false] {
            let record = SSHTestRecord(), hostKey = NIOSSHPrivateKey(ed25519Key: .init())
            let peer = try await server(record: record, key: hostKey)
            defer { _ = peer.close() }
            let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic credential return", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(peer.localAddress?.port))
            var draft = DirectFilesLoginDraft()
            draft.username = "synthetic"; draft.password = "synthetic-only"; draft.remember = remember
            let form = DirectTerminalLoginForm(draft: draft)
            try TerminalSecretStore.approveHostKey(String(openSSHPublicKey: hostKey.publicKey), id: mac.id)
            let session = DirectTerminalSession(mac: mac)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first(where: { $0.activationState == .foregroundActive }))
            let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
            let host = UIHostingController(rootView: DirectTerminalView(mac: mac, session: session, loginForm: form, exit: { XCTFail("An unexpected end must stay in recovery") }).directAppearance())
            window.frame = scene.coordinateSpace.bounds
            window.rootViewController = host; window.makeKeyAndVisible()
            defer { session.stop(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible(); try? TerminalSecretStore.remove(mac.id) }
            try await wait { session.connected }
            // Observe the actual view-bound owner, including its onChange
            // lifecycle, rather than assuming SwiftUI creates UITextField nodes.
            try await wait("successful-login secret cleanup") { form.draft.password.isEmpty }
            XCTAssertEqual(form.draft.username, "synthetic")
            session.background(); await session.waitForLifecycleUpdates()
            XCTAssertTrue(session.connected); session.foreground()
            try await wait { !session.suspended }
            session.send(Array("synthetic-after-pause".utf8))
            try await wait { String(decoding: record.received, as: UTF8.self).contains("synthetic-after-pause") }
            XCTAssertEqual(record.passwordRequests, 1)
            try await record.finish(status: nil, transportFailed: true)
            try await wait { !session.connected && !session.connecting }
            try await wait("view-bound credential return") {
                form.draft.username == (remember ? "synthetic" : "") && form.draft.password == (remember ? "synthetic-only" : "")
            }
            XCTAssertEqual(form.draft.remember, remember)
            XCTAssertEqual(session.recovery?.reason, .terminalEnded)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(record.passwordRequests, 1, "A return form cannot silently open a new shell")
        }
    }
    func testCustomizationBlocksUserInputButKeepsTerminalRepliesAndRetiresOldActions() async throws {
        let record = SSHTestRecord(echoInput: false), key = NIOSSHPrivateKey(ed25519Key: .init())
        let server = try await server(record: record, key: key)
        defer { _ = server.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Controls", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        try TerminalSecretStore.write(Data(String(openSSHPublicKey: key.publicKey).utf8), id: mac.id, kind: "host-key")
        let session = DirectTerminalSession(mac: mac)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let controller = TerminalController(session: session, customize: {})
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { session.stop(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { session.connected && controller.terminal.customInputEpoch() != nil }
        let before = try XCTUnwrap(controller.terminal.customInputEpoch())
        record.clearReceived(); controller.beginCustomization()
        XCTAssertNil(controller.terminal.customInputEpoch())
        controller.terminal.insertText("must not send")
        controller.send(source: controller.terminal, data: [0x78][...])
        XCTAssertTrue(record.received.isEmpty)
        try await record.emit("\u{1b}[6n")
        try await wait("cursor-position reply while editing") { String(decoding: record.received, as: UTF8.self).hasSuffix("R") }
        let reply = record.received
        XCTAssertTrue(reply.starts(with: [0x1b, 0x5b]))
        XCTAssertFalse(String(decoding: reply, as: UTF8.self).contains("must not send"))
        controller.finishCustomization()
        XCTAssertNotEqual(controller.terminal.customInputEpoch(), before)
        controller.controls.actionHandler?(["kind": "tab", "inputEpoch": before.uuidString])
        controller.terminal.insertText("q")
        try await wait { record.received == reply + [0x71] }
    }
    func testComposerUsesCurrentPTYBracketingAndNeverAddsReturnOrReplaysAfterStop() async throws {
        let record = SSHTestRecord(), key = NIOSSHPrivateKey(ed25519Key: .init())
        let server = try await server(record: record, key: key)
        defer { _ = server.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Composer", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        try TerminalSecretStore.write(Data(String(openSSHPublicKey: key.publicKey).utf8), id: mac.id, kind: "host-key")
        let session = DirectTerminalSession(mac: mac)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene), controller = TerminalController(session: session, customize: {})
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { session.stop(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait("composer PTY") { session.connected }
        controller.showTextComposer()
        try await wait("composer sheet") { controller.presentedViewController != nil }
        let draft = controller.textComposer.draft
        draft.edit("中文😀")
        XCTAssertTrue(record.received.isEmpty)
        draft.requestSend()
        try await wait("plain UTF-8 write") { record.received == Array("中文😀".utf8) }
        try await wait("successful composer dismisses") { controller.presentedViewController == nil }
        XCTAssertEqual(draft.text, ""); XCTAssertEqual(record.passwordRequests, 1)
        try await record.emit("\u{1b}[?2004h")
        try await wait("remote bracketed paste mode") { controller.terminal.getTerminal().bracketedPasteMode }
        controller.showTextComposer()
        try await wait("second composer sheet") { controller.presentedViewController != nil }
        draft.edit("one\r\n  two\r\n"); draft.requestSend()
        let reviewed = try XCTUnwrap(draft.confirmation)
        XCTAssertEqual(record.received, Array("中文😀".utf8), "Multiline review must send nothing")
        // SwiftUI dismisses an alert binding before invoking its captured action.
        draft.confirmation = nil; draft.confirmSend(reviewed); draft.requestSend()
        let expected = Array("中文😀\u{1b}[200~one\n  two\n\u{1b}[201~".utf8)
        try await wait("bracketed UTF-8 write") { record.received == expected }
        try await wait("second composer dismisses") { controller.presentedViewController == nil }
        try await Task.sleep(for: .milliseconds(50)); XCTAssertEqual(record.received, expected)
        let oldGeneration = session.composeGeneration
        controller.showTextComposer(); draft.edit("retire this draft"); session.stop()
        XCTAssertEqual(draft.text, ""); XCTAssertFalse(draft.active)
        var staleIssue: String?
        session.sendComposedText(Array("must not replay".utf8), generation: oldGeneration) { staleIssue = $0 }
        XCTAssertNotNil(staleIssue)
        try await Task.sleep(for: .milliseconds(50)); XCTAssertEqual(record.received, expected)
    }
    func testSavedTerminalLoginStartsOnEntryAndRetainsTrustGateAndSingleAttempt() async throws {
        let record = SSHTestRecord(), key = NIOSSHPrivateKey(ed25519Key: .init())
        let server = try await server(record: record, key: key)
        defer { _ = server.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Saved Login", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        try TerminalSecretStore.save(.init(username: "synthetic", password: "synthetic-only"), id: mac.id)
        let session = DirectTerminalSession(mac: mac)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: DirectTerminalView(mac: mac, session: session, exit: {}).directAppearance())
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { session.stop(); window.isHidden = true; window.rootViewController = nil; try? TerminalSecretStore.remove(mac.id) }
        try await wait("saved login starts without tapping Connect") { session.trust != nil || session.recovery != nil }
        XCTAssertNotNil(session.trust); XCTAssertEqual(record.passwordRequests, 0)
        session.answerTrust(true)
        try await wait("saved login authenticates after identity approval") { session.connected || session.recovery != nil }
        XCTAssertTrue(session.connected, session.status); XCTAssertEqual(record.passwordRequests, 1)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(session.connected); XCTAssertEqual(record.passwordRequests, 1, "Trust-sheet dismissal must not trigger a second attempt")
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        try await wait("connected terminal controls finish rendering") {
            host.view.layoutIfNeeded()
            return descendants(host.view).contains { $0 is CompanionVNCControls }
        }
        let controls = try XCTUnwrap(descendants(host.view).compactMap { $0 as? CompanionVNCControls }.first)
        controls.button.sendActions(for: .touchUpInside)
        let interruptTitle = try XCTUnwrap(DirectControlMode.terminal.defaults.first { $0.kind == .interrupt }?.title)
        let interrupt = try XCTUnwrap(descendants(controls).compactMap { $0 as? UIButton }.first { $0.configuration?.title == interruptTitle })
        interrupt.sendActions(for: .touchUpInside)
        try await wait("floating Ctrl-C reaches the PTY") { record.received.contains(3) }
        XCTAssertEqual(record.passwordRequests, 1)
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LifetimePro", withExtension: "storekit"))
        let store = try SKTestSession(contentsOf: url); store.disableDialogs = true; store.clearTransactions()
        defer { store.clearTransactions(); VNCSessionPreferences.clear(DirectControlMode.terminal.profileID) }
        let access = DirectProAccess.shared
        access.start(); await access.loadProduct()
        XCTAssertNotNil(access.product, "Synthetic StoreKit configuration must be loaded before purchase")
        _ = try await store.buyProduct(identifier: DirectProAccess.productID)
        await access.refresh()
        if case .unverified(_, let error) = await StoreKit.Transaction.latest(for: DirectProAccess.productID) {
            XCTFail("Synthetic StoreKit transaction failed native verification: \(error)")
            throw error
        }
        try await wait("synthetic StoreKit entitlement is verified") { access.hasPro }
        var saved = TerminalControlAction(title: "Synthetic action", kind: .shortcut, inMenu: false)
        saved.character = 0x62; saved.modifiers = [0xffe3]
        let controlsStore = TerminalControlsStore()
        var draft = try controlsStore.load(); draft.actions.append(saved)
        draft.pin(saved.id, in: .menu, enabled: true)
        _ = try controlsStore.save(draft)
        defer { if var restored = try? controlsStore.load() { restored.delete(saved.id); _ = try? controlsStore.save(restored) } }
        try await wait("shared controls refresh without reconnecting") { controls.quickActions.contains { $0["definitionID"] as? String == saved.id.uuidString } }
        let admittedItem = try XCTUnwrap(controls.quickActions.first { $0["definitionID"] as? String == saved.id.uuidString })
        controls.button.sendActions(for: .touchUpInside)
        let custom = try XCTUnwrap(descendants(controls).compactMap { $0 as? UIButton }.first { $0.configuration?.title == saved.title })
        custom.sendActions(for: .touchUpInside)
        try await wait("configured shortcut reaches the same PTY") { record.received.last == 0x02 }
        XCTAssertEqual(record.passwordRequests, 1, "Changing controls must not reconnect the shell")
        try await wait("the completed action panel finishes closing") {
            !descendants(controls).compactMap { $0 as? UIButton }.contains { $0.configuration?.title == saved.title }
        }
        store.clearTransactions(); await access.refresh()
        try await wait("cleared StoreKit entitlement retires Pro input") { !access.hasPro }
        controls.button.sendActions(for: .touchUpInside)
        XCTAssertFalse(descendants(controls).compactMap { $0 as? UIButton }.contains { $0.configuration?.title == saved.title })
        let count = record.received.count
        controls.actionHandler?(admittedItem)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(record.received.count, count, "A stale Pro action cannot send input after entitlement ends")
    }
    func testColdTerminalActivityReturnLoadsLoginButNeverSilentlyStartsAReplacementShell() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
        let policy = try XCTUnwrap((JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])?["recoveryPolicy"] as? [String: Any])
        XCTAssertEqual(policy["terminalColdActivityReturnRequiresExplicitConnect"] as? Bool, true)
        let record = SSHTestRecord(), key = NIOSSHPrivateKey(ed25519Key: .init())
        let server = try await server(record: record, key: key)
        defer { _ = server.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Cold Return", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        try TerminalSecretStore.save(.init(username: "synthetic", password: "synthetic-only"), id: mac.id)
        try TerminalSecretStore.write(Data(String(openSSHPublicKey: key.publicKey).utf8), id: mac.id, kind: "host-key")
        let attributes = RemoteSessionActivityAttributes(macID: mac.id, macName: mac.name, kind: .terminal)
        let route = try XCTUnwrap(RemoteSessionActivityAttributes.resumeRoute(from: attributes.resumeURL))
        XCTAssertFalse(route.automaticallyConnect)
        let selection = DirectMacSessionSelection(mac: mac, connection: .terminal, autoConnect: route.automaticallyConnect)
        let session = DirectTerminalSession(mac: mac)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: DirectTerminalView(mac: selection.mac, session: session, autoConnect: selection.autoConnect, exit: {}).directAppearance())
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { session.stop(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible(); try? TerminalSecretStore.remove(mac.id) }
        try await Task.sleep(for: .milliseconds(350))
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.post(name: DirectAppLockV1.unlocked, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(session.connecting); XCTAssertFalse(session.connected); XCTAssertEqual(record.passwordRequests, 0)
        let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "Cold Terminal return requires explicit new shell"; attachment.lifetime = .keepAlways; add(attachment)
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait("explicit new shell") { session.connected }
        XCTAssertEqual(record.passwordRequests, 1)
    }
    func testFailedSavedLoginRemainsVisibleWithoutAutomaticRetry() async throws {
        let record = SSHTestRecord(), key = NIOSSHPrivateKey(ed25519Key: .init())
        let server = try await server(record: record, key: key)
        defer { _ = server.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Rejected Login", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        try TerminalSecretStore.save(.init(username: "synthetic", password: "wrong-synthetic-only"), id: mac.id)
        try TerminalSecretStore.write(Data(String(openSSHPublicKey: key.publicKey).utf8), id: mac.id, kind: "host-key")
        let session = DirectTerminalSession(mac: mac)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: DirectTerminalView(mac: mac, session: session, exit: {}).directAppearance())
        window.makeKeyAndVisible()
        defer { session.stop(); window.isHidden = true; window.rootViewController = nil; try? TerminalSecretStore.remove(mac.id) }
        try await wait("saved login rejection remains actionable") { session.recovery != nil }
        XCTAssertFalse(session.connected); XCTAssertFalse(session.connecting)
        XCTAssertEqual(session.recovery?.reason, .loginRejected)
        XCTAssertEqual(record.passwordRequests, 1)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(session.recovery?.reason, .loginRejected); XCTAssertEqual(record.passwordRequests, 1)
        XCTAssertEqual(try TerminalSecretStore.login(mac.id)?.password, "wrong-synthetic-only", "A failed attempt must not erase the saved login")
    }
    func testConnectedSocketPreservesEarlyServerBannerUntilSSHHandlersExist() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let additions = try XCTUnwrap(fixture["clientAdditions"] as? [String: Any])
        let profile = try XCTUnwrap(additions["ssh"] as? [String: Any])
        let readBeforeParser = try XCTUnwrap(profile["automaticReadsBeforeParser"] as? Bool)
        XCTAssertFalse(readBeforeParser)
        XCTAssertEqual(profile["enableReadsAfterHandlersBeforeAuthentication"] as? Bool, true)
        for autoRead in [true, readBeforeParser] {
            let record = SSHTestRecord(), early = SSHTestRecord(), key = NIOSSHPrivateKey(ed25519Key: .init())
            let server = try await server(record: record, key: key)
            defer { _ = server.close() }
            let port = try XCTUnwrap(server.localAddress?.port)
            // Use the same already-connected-socket registration as production.
            let fd = try await Task.detached {
                let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
                guard fd >= 0 else { throw POSIXError(.ENOTCONN) }
                let address = try SocketAddress(ipAddress: "127.0.0.1", port: port)
                let result = address.withSockAddr { Darwin.connect(fd, $0, socklen_t($1)) }
                guard result == 0 else { Darwin.close(fd); throw POSIXError(.ENOTCONN) }
                return fd
            }.value
            let channel = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                .channelOption(ChannelOptions.autoRead, value: autoRead)
                .channelInitializer { $0.pipeline.addHandler(SSHEarlyReadProbe(early)) }
                .withConnectedSocket(fd).get()
            defer { _ = channel.close() }
            if autoRead {
                try await wait("banner discarded before parser attachment") { !early.received.isEmpty }
                XCTAssertTrue(String(decoding: early.received, as: UTF8.self).hasPrefix("SSH-2.0-"))
                XCTAssertEqual(record.passwordRequests, 0)
                continue
            }
            // An intentional scheduling gap used to lose the server's banner.
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(early.received.isEmpty)
            let readsPaused = try await channel.getOption(ChannelOptions.autoRead).get()
            XCTAssertFalse(readsPaused)
            var settings = SSHClientSettings(host: "127.0.0.1", port: port,
                authenticationMethod: { .passwordBased(username: "synthetic", password: "synthetic-only") },
                hostKeyValidator: .trustedKeys([key.publicKey]))
            settings.connectTimeout = .seconds(3)
            let client = try await SSHClient.connect(on: channel, settings: settings)
            let readsResumed = try await channel.getOption(ChannelOptions.autoRead).get()
            XCTAssertTrue(readsResumed)
            XCTAssertTrue(String(decoding: early.received, as: UTF8.self).hasPrefix("SSH-2.0-"))
            XCTAssertEqual(record.passwordRequests, 1)
            try await client.close()
        }
    }
    func testInstallUsesBootstrapThenFreshKeyLoginBeforeSelectionAndPreservesPassword() async throws {
        for valid in [true, false] {
            let record = SSHTestRecord(), key = TerminalSSHKey.create(), old = TerminalSSHKey.create()
            let id = try TerminalKeyLibraryStore.add(key, name: "Synthetic Target")
            let oldID = try TerminalKeyLibraryStore.add(old, name: "Synthetic Existing")
            let entry = TerminalNamedKey(id: id, name: "Synthetic Target", key: key)
            let publicKey = NIOSSHPrivateKey(ed25519Key: try Curve25519.Signing.PrivateKey(rawRepresentation: (valid ? key : old).seed)).publicKey
            let server = try await server(record: record, key: NIOSSHPrivateKey(ed25519Key: .init()), publicKey: publicKey)
            let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Install", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
            let session = DirectTerminalSession(mac: mac)
            defer { session.stop(); try? TerminalSecretStore.remove(mac.id); try? TerminalKeyLibraryStore.delete(id); try? TerminalKeyLibraryStore.delete(oldID) }
            // Save the fallback Mac password before selecting the SSH-key override.
            try TerminalSecretStore.save(.init(username: "preserved", password: "saved-synthetic"), id: mac.id)
            try TerminalKeyLibraryStore.associate(oldID, macID: mac.id, username: "original")
            session.connect(username: "synthetic", password: "synthetic-only", remember: false, installation: entry)
            try await wait("setup trust") { session.trust != nil || !session.connecting }
            XCTAssertEqual(record.passwordRequests, 0); XCTAssertEqual(record.commands, 0)
            session.answerTrust(true)
            try await wait("installation and verification") { !session.connecting }
            XCTAssertEqual(record.passwordRequests, 1); XCTAssertEqual(record.commands, 1)
            XCTAssertGreaterThan(record.keyRequests, 0)
            XCTAssertEqual(session.recovery?.reason, valid ? .setupVerified : .setupLoginUnverified)
            if !valid {
                XCTAssertTrue(session.recovery?.message.contains("automatic key-only login test failed") == true)
                XCTAssertTrue(session.recovery?.details.contains(.init(name: "Cause", value: "SSH key wasn’t accepted")) == true)
            }
            XCTAssertEqual(session.installedKey, valid ? id : nil, session.status)
            XCTAssertEqual(try TerminalKeyLibraryStore.selected(mac.id)?.id, valid ? id : oldID)
            XCTAssertEqual(try TerminalSecretStore.login(mac.id)?.password, "saved-synthetic")
            try await server.close()
        }
    }
    func testVerificationOnlyNeverInstallsOrUsesPasswordAndPreservesPriorLoginOnRejection() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let policy = try XCTUnwrap((fixture["errorRecovery"] as? [String: Any])?["verificationOnly"] as? [String: Any])
        for valid in [true, false] {
            let record = SSHTestRecord(), target = TerminalSSHKey.create(), old = TerminalSSHKey.create()
            let targetID = try TerminalKeyLibraryStore.add(target, name: "Verification Target")
            let oldID = try TerminalKeyLibraryStore.add(old, name: "Prior Login")
            let entry = TerminalNamedKey(id: targetID, name: "Verification Target", key: target)
            let pub = NIOSSHPrivateKey(ed25519Key: try Curve25519.Signing.PrivateKey(rawRepresentation: (valid ? target : old).seed)).publicKey
            let server = try await server(record: record, key: NIOSSHPrivateKey(ed25519Key: .init()), publicKey: pub)
            let mac = DirectMacRecordV1(id: UUID(), name: "Verification Mac", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
            let session = DirectTerminalSession(mac: mac)
            defer { session.stop(); try? TerminalSecretStore.remove(mac.id); try? TerminalKeyLibraryStore.delete(targetID); try? TerminalKeyLibraryStore.delete(oldID) }
            // Save the fallback Mac password before selecting the SSH-key override.
            try TerminalSecretStore.save(.init(username: "prior", password: "preserved-synthetic"), id: mac.id)
            try TerminalKeyLibraryStore.associate(oldID, macID: mac.id, username: "prior")
            session.testKeyLogin(username: "synthetic", target: entry)
            try await wait("verification trust") { session.trust != nil || !session.connecting }
            XCTAssertNotNil(session.trust); XCTAssertEqual(record.passwordRequests, 0); XCTAssertEqual(record.keyRequests, 0); XCTAssertEqual(record.commands, 0)
            XCTAssertEqual(try TerminalKeyLibraryStore.selected(mac.id)?.id, oldID)
            session.answerTrust(true)
            try await wait("verification outcome") { !session.connecting }
            XCTAssertEqual(record.passwordRequests, policy["passwordRequests"] as? Int)
            XCTAssertEqual(record.commands, policy["commands"] as? Int)
            XCTAssertGreaterThan(record.keyRequests, 0)
            XCTAssertEqual(session.recovery?.reason, valid ? .setupVerified : .keyRejected)
            XCTAssertEqual(try TerminalKeyLibraryStore.selected(mac.id)?.id, valid ? targetID : oldID)
            XCTAssertEqual(try TerminalSecretStore.login(mac.id)?.password, "preserved-synthetic")
            try await server.close()
        }
    }
    func testCancelledUnacknowledgedInstallRemainsUncertainAndRetryIsVerificationOnly() async throws {
        let record = SSHTestRecord(respondToInstall: false), target = TerminalSSHKey.create()
        let keyID = try TerminalKeyLibraryStore.add(target, name: "Unacknowledged Setup")
        let entry = TerminalNamedKey(id: keyID, name: "Unacknowledged Setup", key: target)
        let pub = NIOSSHPrivateKey(ed25519Key: try Curve25519.Signing.PrivateKey(rawRepresentation: target.seed)).publicKey
        let server = try await server(record: record, key: NIOSSHPrivateKey(ed25519Key: .init()), publicKey: pub)
        let mac = DirectMacRecordV1(id: UUID(), name: "Cancelled Setup", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectTerminalSession(mac: mac)
        defer { session.stop(); try? TerminalSecretStore.remove(mac.id); try? TerminalKeyLibraryStore.delete(keyID) }
        session.connect(username: "synthetic", password: "synthetic-only", remember: false, installation: entry)
        try await wait("setup trust") { session.trust != nil }; session.answerTrust(true)
        try await wait("unacknowledged command") { record.commands == 1 }
        XCTAssertFalse(session.requestSetupDismissal(), "Done must keep the cancellation outcome on screen")
        XCTAssertEqual(session.recovery?.reason, .setupUncertain); XCTAssertNil(try TerminalKeyLibraryStore.selected(mac.id))
        XCTAssertFalse(session.connecting)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(record.commands, 1, "Cancellation must not replay the installation")
        session.testKeyLogin(username: "synthetic", target: entry)
        try await wait("verification only after cancel") { !session.connecting }
        XCTAssertEqual(session.installedKey, keyID, session.status)
        XCTAssertEqual(record.commands, 1); XCTAssertEqual(record.passwordRequests, 1)
        try await server.close()
    }
    func testSetupDoneBeforeTrustCancelsWithoutInstallationAndRequiresASecondDismissal() async throws {
        let record = SSHTestRecord(), target = TerminalSSHKey.create()
        let entry = TerminalNamedKey(id: UUID(), name: "Cancelled Before Trust", key: target)
        let server = try await server(record: record, key: NIOSSHPrivateKey(ed25519Key: .init()))
        defer { _ = server.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Cancelled Before Trust", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectTerminalSession(mac: mac)
        defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username: "synthetic", password: "synthetic-only", remember: false, installation: entry)
        try await wait("setup trust") { session.trust != nil }
        XCTAssertFalse(session.requestSetupDismissal())
        XCTAssertEqual(session.recovery?.reason, .setupIncomplete)
        XCTAssertFalse(session.connecting); XCTAssertNil(session.trust)
        session.answerTrust(true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(record.commands, 0); XCTAssertEqual(record.passwordRequests, 0)
        XCTAssertNil(try TerminalKeyLibraryStore.selected(mac.id))
        XCTAssertTrue(session.requestSetupDismissal(), "The user may close after reviewing the cancelled outcome")
        XCTAssertEqual(session.recovery?.reason, .setupIncomplete)
    }
    private func server(record:SSHTestRecord,key:NIOSSHPrivateKey, publicKey: NIOSSHPublicKey? = nil) async throws -> Channel {
        let auth=SSHTestAuth(record, publicKey: publicKey)
        return try await ServerBootstrap(group:MultiThreadedEventLoopGroup.singleton).childChannelInitializer { channel in
            record.openedTransport(channel)
            return channel.pipeline.addHandler(NIOSSHHandler(role:.server(.init(hostKeys:[key],userAuthDelegate:auth)),allocator:channel.allocator,inboundChildChannelInitializer:{ child,type in
                child.pipeline.addHandler(SSHTestPTY(record))
            }))
        }.bind(host:"127.0.0.1",port:0).get()
    }
    private func wait(_ message: String = "synthetic SSH session", _ condition: @MainActor ()->Bool) async throws {
        for _ in 0..<500 { if condition() { return }; try await Task.sleep(for:.milliseconds(10)) }
        XCTFail("Timed out waiting for \(message)")
        throw POSIXError(.ETIMEDOUT)
    }
    func testReportedShellCompletionDistinguishesNormalExitFromLostConnection() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(fixture["terminalEndCases"] as? [[String: Any]])
        for vector in cases where vector["currentSession"] as? Bool == true {
            let name = try XCTUnwrap(vector["name"] as? String)
            let record = SSHTestRecord(), key = NIOSSHPrivateKey(ed25519Key: .init())
            let server = try await server(record: record, key: key)
            defer { _ = server.close() }
            let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Completion", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
            let defaults = UserDefaults(suiteName: "terminal-completion-" + UUID().uuidString)!
            let backend = TerminalActivityTestBackend()
            let session = DirectTerminalSession(mac: mac, activityDefaults: defaults, activityBackend: backend)
            defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
            try TerminalSecretStore.write(Data(String(openSSHPublicKey: key.publicKey).utf8), id: mac.id, kind: "host-key")
            session.connect(username: "synthetic", password: "synthetic-only", remember: false)
            try await wait(name + " connected") { session.connected }
            if vector["resizeWriteFailed"] as? Bool == true {
                var attempts = 0
                session.resizeForTesting = { _, _ in attempts += 1; throw ChannelError.ioOnClosedChannel }
                session.resize(columns: 91, rows: 29)
                try await wait(name + " failed resize") { attempts == 1 }
                XCTAssertTrue(session.connected, "An advisory failure must leave the reader alive for the peer's result")
                XCTAssertNil(session.recovery, "Do not blame layout for an unclassified shell ending")
            }
            var tail: [UInt8] = []
            session.received = { tail += $0 }
            try await record.emit("final-synthetic-output")
            try await record.finish(status: vector["exitStatus"] as? Int, signal: vector["exitSignal"] as? String, transportFailed: vector["transportFailed"] as? Bool == true)
            try await wait(name + " completed") { !session.connected }
            XCTAssertEqual(session.completedNormally, vector["returnToMacs"] as? Bool, name)
            if session.completedNormally {
                XCTAssertNil(session.recovery, name)
                XCTAssertTrue(String(decoding: tail, as: UTF8.self).contains("final-synthetic-output"), "Drain final output before dismissing")
            } else { XCTAssertEqual(session.recovery?.reason, .terminalEnded, name) }
            XCTAssertNil(session.activity); XCTAssertEqual(record.passwordRequests, 1)
            XCTAssertTrue(record.received.isEmpty, "Completion must never inject or replay input")
            session.stop(); XCTAssertFalse(session.completedNormally)
        }
    }
    func testNormalExitDismissesHostedTerminalWithoutShowingLoginAgain() async throws {
        let record = SSHTestRecord(), key = NIOSSHPrivateKey(ed25519Key: .init())
        let server = try await server(record: record, key: key)
        defer { _ = server.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Exit", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        try TerminalSecretStore.save(.init(username: "synthetic", password: "synthetic-only"), id: mac.id)
        try TerminalSecretStore.write(Data(String(openSSHPublicKey: key.publicKey).utf8), id: mac.id, kind: "host-key")
        let session = DirectTerminalSession(mac: mac)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        var exits = 0
        window.rootViewController = UIHostingController(rootView: DirectTerminalView(mac: mac, session: session, exit: { exits += 1 }).directAppearance())
        window.makeKeyAndVisible()
        defer { session.stop(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible(); try? TerminalSecretStore.remove(mac.id) }
        try await wait("hosted shell connected") { session.connected }
        var attempts = 0
        session.resizeForTesting = { _, _ in attempts += 1; throw ChannelError.ioOnClosedChannel }
        session.resize(columns: 93, rows: 31)
        try await wait("size notification rejected before shell exit") { attempts == 1 }
        XCTAssertTrue(session.connected); XCTAssertNil(session.recovery)
        try await record.finish(status: 0)
        try await wait("normal shell navigates to My Macs") { exits == 1 }
        XCTAssertNil(session.recovery); XCTAssertFalse(session.connected)
        try await Task.sleep(for: .milliseconds(100)); XCTAssertEqual(exits, 1); XCTAssertEqual(record.passwordRequests, 1)
    }
    func testOldShellCompletionCannotDismissReplacementShell() async throws {
        let record = SSHTestRecord(), key = NIOSSHPrivateKey(ed25519Key: .init())
        let server = try await server(record: record, key: key)
        defer { _ = server.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Replacement", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectTerminalSession(mac: mac)
        defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        try TerminalSecretStore.write(Data(String(openSSHPublicKey: key.publicKey).utf8), id: mac.id, kind: "host-key")
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { session.connected }
        try await record.finish(status: 0)
        session.stop()
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { session.connected }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(session.completedNormally); XCTAssertNil(session.recovery); XCTAssertTrue(session.connected)
        XCTAssertEqual(record.passwordRequests, 2); XCTAssertTrue(record.received.isEmpty)
    }
    func testEd25519AuthenticatesOnlyAfterHostTrustWithoutPasswordFallback() async throws {
        let record = SSHTestRecord(), key = TerminalSSHKey.create()
        let publicKey = NIOSSHPrivateKey(ed25519Key: try Curve25519.Signing.PrivateKey(rawRepresentation: key.seed)).publicKey
        let server = try await server(record: record, key: NIOSSHPrivateKey(ed25519Key: .init()), publicKey: publicKey)
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Key SSH", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        // Match the actual UI: authenticate with a key already selected in Login & Access.
        let keyID = try TerminalKeyLibraryStore.add(key, name: "Synthetic Authentication")
        try TerminalKeyLibraryStore.associate(keyID, macID: mac.id, username: "prior-account")
        let session = DirectTerminalSession(mac: mac)
        defer { session.stop(); try? TerminalSecretStore.remove(mac.id); try? TerminalKeyLibraryStore.delete(keyID) }
        session.connect(username: "synthetic", password: "MUST-NOT-SEND", remember: false, key: key)
        try await wait("key host trust") { session.trust != nil || !session.connecting }
        XCTAssertNotNil(session.trust); XCTAssertEqual(record.keyRequests, 0); XCTAssertEqual(record.passwordRequests, 0)
        session.answerTrust(true); try await wait("key authentication success") { session.connected || !session.connecting }
        XCTAssertTrue(session.connected, session.status); XCTAssertGreaterThan(record.keyRequests, 0); XCTAssertEqual(record.passwordRequests, 0)
        XCTAssertEqual(try TerminalSecretStore.sshKey(mac.id)?.username, "synthetic")
        session.stop()
        session.connect(username: "synthetic", password: "synthetic-only", remember: true, key: .create())
        try await wait("wrong key rejection; status: \(session.status); key requests: \(record.keyRequests)") { !session.connecting }
        XCTAssertFalse(session.connected); XCTAssertEqual(record.passwordRequests, 0)
        try await server.close()
    }
    func testShortcutSequenceReservesWholeWriteOrderAndRetiresBeforeStart() async throws {
        let record = SSHTestRecord(), key = NIOSSHPrivateKey(ed25519Key: .init())
        let peer = try await server(record: record, key: key)
        defer { _ = peer.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic sequence owner", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(peer.localAddress?.port))
        let session = DirectTerminalSession(mac: mac)
        defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { session.trust != nil }; session.answerTrust(true)
        try await wait { session.canSendUserInput }
        let epoch = try XCTUnwrap(session.customInputEpoch)
        var completed = false
        session.sendSequence([[2], [99], [13]], epoch: epoch) { XCTAssertNil($0); completed = true }
        XCTAssertTrue(session.isSendingCustomSequence)
        XCTAssertFalse(session.trySend([120]), "No-wait shortcuts must reserve ordinary input too")
        try await wait { completed && record.received == [2, 99, 13] }
        XCTAssertFalse(session.isSendingCustomSequence)
        XCTAssertTrue(session.trySend([120]))
        try await wait { record.received == [2, 99, 13, 120] }
        var stopped = false
        session.sendSequence([[97], [98]], epoch: epoch) { XCTAssertNotNil($0); stopped = true }
        session.becameInactive()
        try await wait { stopped }
        session.foreground()
        try await wait { session.canSendUserInput }
        XCTAssertNotEqual(session.customInputEpoch, epoch)
        session.sendSequence([[122]], epoch: epoch) { XCTAssertNotNil($0) }
        await Task.yield()
        XCTAssertEqual(record.received, [2, 99, 13, 120], "A retired task or stale admission cannot replay in the resumed shell")
        var valid = true, invalidated = false
        XCTAssertTrue(session.sendSequence([[65], [66]], epoch: try XCTUnwrap(session.customInputEpoch), stillValid: { valid }) { XCTAssertNotNil($0); invalidated = true })
        valid = false
        try await wait { invalidated }
        XCTAssertEqual(record.received, [2, 99, 13, 120], "A queued sequence rechecks its encoder/policy predicate before writing")
    }
    func testAcceptedComposedTextStillPrecedesNewImmediateShortcut() async throws {
        let record = SSHTestRecord(echoInput: false), key = NIOSSHPrivateKey(ed25519Key: .init())
        let peer = try await server(record: record, key: key); defer { _ = peer.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic preceding draft", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(peer.localAddress?.port))
        let session = DirectTerminalSession(mac: mac); defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { session.trust != nil }; session.answerTrust(true); try await wait { session.canSendUserInput }
        var composed = false, shortcut = false
        session.sendComposedText([112], generation: session.composeGeneration) { XCTAssertNil($0); composed = true }
        XCTAssertTrue(session.sendSequence([[97], [98]], epoch: try XCTUnwrap(session.customInputEpoch), completion: { XCTAssertNil($0); shortcut = true }))
        try await wait { composed && shortcut && record.received == [112, 97, 98] }
    }

    func testImmediateShortcutOwnsInputAndRejectsQueuedShortcutsWhileWriteIsBlocked() async throws {
        let record = SSHTestRecord(echoInput: false), key = NIOSSHPrivateKey(ed25519Key: .init())
        let peer = try await server(record: record, key: key); defer { _ = peer.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic immediate ownership", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(peer.localAddress?.port))
        let session = DirectTerminalSession(mac: mac); defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { session.trust != nil }; session.answerTrust(true); try await wait { session.canSendUserInput }
        var held: CheckedContinuation<Void, Error>?
        session.beforeWriteForTesting = { bytes in if bytes == [97] { try await withCheckedThrowingContinuation { held = $0 } } }
        defer { held?.resume(); held = nil }
        let epoch = try XCTUnwrap(session.customInputEpoch)
        var firstCompletions = 0, rejected = 0, fresh = false
        XCTAssertTrue(session.sendSequence([[97], [98]], epoch: epoch, completion: { XCTAssertNotNil($0); firstCompletions += 1 }))
        XCTAssertTrue(session.isSendingCustomSequence, "Reservation starts before the first async write")
        try await wait { held != nil }
        XCTAssertFalse(session.sendSequence([[120]], epoch: epoch, completion: { XCTAssertNotNil($0); rejected += 1 }))
        let competing: [TerminalSequenceOperation<[UInt8]>] = [.input([120]), .wait(100), .input([121])]
        XCTAssertFalse(session.sendSequencePlan(competing, epoch: epoch, resolve: { competing[$0].input }, stillValid: { true }, progress: { _ in }, completion: { XCTAssertNotNil($0); rejected += 1 }))
        XCTAssertFalse(session.trySend([122])); XCTAssertEqual(rejected, 2)
        session.cancelSequence(epoch: epoch)
        XCTAssertEqual(firstCompletions, 1); XCTAssertFalse(session.isSendingCustomSequence)
        let newEpoch = try XCTUnwrap(session.customInputEpoch)
        XCTAssertTrue(session.sendSequence([[99], [100]], epoch: newEpoch, completion: { XCTAssertNil($0); fresh = true }))
        session.cancelSequence(epoch: epoch)
        XCTAssertTrue(session.isSendingCustomSequence, "A retained Cancel cannot retire the new immediate shortcut")
        XCTAssertTrue(record.received.isEmpty)
        let pending = held; held = nil; pending?.resume()
        try await wait { fresh && record.received == [97, 99, 100] }
        XCTAssertEqual(firstCompletions, 1); XCTAssertFalse(session.isSendingCustomSequence)
        XCTAssertTrue(session.trySend([122])); try await wait { record.received == [97, 99, 100, 122] }
    }

    func testTimedShortcutUsesCurrentEncodingAndRejectsCompetingInput() async throws {
        let record = SSHTestRecord(echoInput: false), key = NIOSSHPrivateKey(ed25519Key: .init())
        let peer = try await server(record: record, key: key)
        defer { _ = peer.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic timed input", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(peer.localAddress?.port))
        let session = DirectTerminalSession(mac: mac)
        defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { session.trust != nil }; session.answerTrust(true)
        try await wait { session.canSendUserInput }
        var action = TerminalControlAction(title: "Mode transition", kind: .shortcut)
        action.steps = [.init(kind: .typeText, text: "a"), .init(kind: .wait, waitMilliseconds: 100), .init(kind: .typeText, text: "b")]
        var encoding = TerminalKeyEncoding(flags: .reportAllKeys), finished = false
        let plan = try action.terminalPlan(encoding: encoding, bracketedPaste: true)
        let epoch = try XCTUnwrap(session.customInputEpoch)
        XCTAssertTrue(session.sendSequencePlan(plan, epoch: epoch, resolve: { index in
            (try? action.terminalPlan(encoding: encoding, bracketedPaste: true))?[index].input
        }, stillValid: { true }, progress: { index in
            if index == 1 {
                XCTAssertTrue(session.isSendingCustomSequence)
                XCTAssertFalse(session.trySend([120]), "Typing cannot interleave inside a wait")
                XCTAssertTrue(session.trySend(Array("\u{1b}[0n".utf8), source: .emulatorReply), "Protocol replies must not wait behind the shortcut")
                encoding.flags = []
            }
        }, completion: { XCTAssertNil($0); finished = true }))
        try await wait { finished }
        try await wait { record.received == Array("\u{1b}[97u\u{1b}[0nb".utf8) }
        XCTAssertFalse(session.isSendingCustomSequence)
        XCTAssertTrue(session.trySend([120]))
        try await wait { record.received.last == 120 }
    }

    func testFrontendProtocolRepliesAndIntermediateOutputContinueDuringWait() async throws {
        let record = SSHTestRecord(echoInput: false), key = NIOSSHPrivateKey(ed25519Key: .init())
        let peer = try await server(record: record, key: key); defer { _ = peer.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic frontend replies", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(peer.localAddress?.port))
        try TerminalSecretStore.approveHostKey(String(openSSHPublicKey: key.publicKey), id: mac.id)
        let session = DirectTerminalSession(mac: mac)
        let controller = TerminalController(session: session, customize: {}); controller.loadViewIfNeeded()
        defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { session.canSendUserInput && controller.terminal.customInputEpoch() != nil }
        record.clearReceived()
        let plan: [TerminalSequenceOperation<[UInt8]>] = [.input([116]), .wait(2000), .input([49])]
        var waiting = false, finished = false
        XCTAssertTrue(session.sendSequencePlan(plan, epoch: try XCTUnwrap(session.customInputEpoch), resolve: { plan[$0].input }, stillValid: { true }, progress: { if $0 == 1 { waiting = true } }, completion: { XCTAssertNil($0); finished = true }))
        try await wait { waiting }
        controller.terminal.insertText("should-not-interleave")
        try await record.emit("Intermediate output is visible\r\n\u{1b}[5n\u{1b}[6n\u{1b}[?u")
        try await wait { String(decoding: record.received, as: UTF8.self).contains("\u{1b}[0n") && String(decoding: record.received, as: UTF8.self).contains("R") && String(decoding: record.received, as: UTF8.self).contains("u") }
        XCTAssertTrue(session.isSendingCustomSequence)
        XCTAssertTrue(terminalCompatibilityText(controller.terminal.getTerminal()).contains("Intermediate output is visible"))
        XCTAssertFalse(String(decoding: record.received, as: UTF8.self).contains("should-not-interleave"))
        try await wait { finished }
        XCTAssertEqual(record.received.last, 49)
    }

    func testTimedWriterCountsActualBytesAfterCompletedPrefixModeChange() async throws {
        let record = SSHTestRecord(echoInput: false, inputLimit: 8192), key = NIOSSHPrivateKey(ed25519Key: .init())
        let peer = try await server(record: record, key: key); defer { _ = peer.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic current-step encoding", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(peer.localAddress?.port))
        let session = DirectTerminalSession(mac: mac); defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { session.trust != nil }; session.answerTrust(true); try await wait { session.canSendUserInput }
        var action = TerminalControlAction(title: "Changing mode", kind: .shortcut)
        action.steps = [.init(kind: .typeText, text: String(repeating: "a", count: 4000)), .init(kind: .wait, waitMilliseconds: 100), .init(kind: .typeText, text: "b")]
        var encoding = TerminalKeyEncoding(), finished = false
        let plan = try action.terminalPlan(encoding: encoding, bracketedPaste: false)
        XCTAssertTrue(session.sendSequencePlan(plan, epoch: try XCTUnwrap(session.customInputEpoch), resolve: { try? action.resolvedSteps[$0].terminalBytes(encoding: encoding, bracketedPaste: false) }, stillValid: { true }, progress: { if $0 == 1 { encoding.flags = .reportAllKeys } }, completion: { XCTAssertNil($0); finished = true }))
        try await wait("4005 captured input bytes after mode change") { finished && record.received.count == 4005 }
        XCTAssertEqual(Array(record.received.prefix(4000)), Array(repeating: 97, count: 4000))
        XCTAssertEqual(Array(record.received.suffix(5)), Array("\u{1b}[98u".utf8))
    }

    func testCancelTimedShortcutRetiresItsSuffixAndAllowsFreshInput() async throws {
        let record = SSHTestRecord(echoInput: false), key = NIOSSHPrivateKey(ed25519Key: .init())
        let peer = try await server(record: record, key: key)
        defer { _ = peer.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic cancellation", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(peer.localAddress?.port))
        let session = DirectTerminalSession(mac: mac)
        defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { session.trust != nil }; session.answerTrust(true)
        try await wait { session.canSendUserInput }
        let epoch = try XCTUnwrap(session.customInputEpoch)
        let plan: [TerminalSequenceOperation<[UInt8]>] = [.input([116, 13]), .wait(30_000), .input([49, 13])]
        var finished = false
        XCTAssertTrue(session.sendSequencePlan(plan, epoch: epoch, resolve: { plan[$0].input }, stillValid: { true }, progress: { index in
            if index == 1 { session.cancelSequence(epoch: epoch) }
        }, completion: { XCTAssertNotNil($0); finished = true }))
        try await wait { finished }
        XCTAssertTrue(session.connected)
        XCTAssertNotEqual(session.customInputEpoch, epoch)
        XCTAssertTrue(session.trySend([122]))
        try await wait { record.received == [116, 13, 122] }
        await Task.yield()
        XCTAssertEqual(record.received, [116, 13, 122], "Canceled numeric selection must never replay")
    }

    func testCancelBlockedShortcutCompletesOnceAndKeepsNewRunOrdered() async throws {
        let record = SSHTestRecord(echoInput: false), key = NIOSSHPrivateKey(ed25519Key: .init())
        let peer = try await server(record: record, key: key); defer { _ = peer.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic blocked shortcut", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(peer.localAddress?.port))
        let session = DirectTerminalSession(mac: mac); defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { session.trust != nil }; session.answerTrust(true); try await wait { session.canSendUserInput }
        var held: CheckedContinuation<Void, Error>?
        session.beforeWriteForTesting = { bytes in
            if bytes == [97] { try await withCheckedThrowingContinuation { held = $0 } }
        }
        defer { held?.resume(); held = nil }
        let first: [TerminalSequenceOperation<[UInt8]>] = [.input([97]), .wait(100), .input([120])]
        let epoch = try XCTUnwrap(session.customInputEpoch)
        var firstCompletions = 0, secondCompletions = 0, secondWaiting = false
        XCTAssertTrue(session.sendSequencePlan(first, epoch: epoch, resolve: { first[$0].input }, stillValid: { true }, progress: { _ in }, completion: {
            XCTAssertNotNil($0); firstCompletions += 1
        }))
        try await wait { held != nil }
        session.cancelSequence(epoch: epoch)
        XCTAssertEqual(firstCompletions, 1, "Cancel completes synchronously without waiting for the non-cancellable writer")
        XCTAssertFalse(session.isSendingCustomSequence)
        XCTAssertNotEqual(session.customInputEpoch, epoch)
        let second: [TerminalSequenceOperation<[UInt8]>] = [.input([98]), .wait(500), .input([99])]
        let freshEpoch = try XCTUnwrap(session.customInputEpoch)
        XCTAssertTrue(session.sendSequencePlan(second, epoch: freshEpoch, resolve: { second[$0].input }, stillValid: { true }, progress: { if $0 == 1 { secondWaiting = true } }, completion: { XCTAssertNil($0); secondCompletions += 1 }))
        session.cancelSequence(epoch: epoch)
        XCTAssertTrue(session.isSendingCustomSequence, "An old Cancel cannot retire the new run")
        XCTAssertTrue(record.received.isEmpty, "New input cannot overtake the accepted blocked write")
        let pending = held; held = nil; pending?.resume()
        try await wait { secondWaiting && record.received == [97, 98] }
        XCTAssertEqual(firstCompletions, 1, "The late old runner completion is ignored")
        XCTAssertEqual(secondCompletions, 0)
        XCTAssertTrue(session.isSendingCustomSequence, "Old cleanup must not clear the newer reservation")
        try await wait { secondCompletions == 1 && record.received == [97, 98, 99] }
        XCTAssertTrue(session.trySend([100])); try await wait { record.received == [97, 98, 99, 100] }
    }

    func testLateCanceledWriteFailureCannotStopNewShortcut() async throws {
        let record = SSHTestRecord(echoInput: false), key = NIOSSHPrivateKey(ed25519Key: .init())
        let peer = try await server(record: record, key: key); defer { _ = peer.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic late writer failure", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(peer.localAddress?.port))
        let session = DirectTerminalSession(mac: mac); defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { session.trust != nil }; session.answerTrust(true); try await wait { session.canSendUserInput }
        var held: CheckedContinuation<Void, Error>?
        session.beforeWriteForTesting = { bytes in if bytes == [97] { try await withCheckedThrowingContinuation { held = $0 } } }
        defer { held?.resume(); held = nil }
        let old: [TerminalSequenceOperation<[UInt8]>] = [.input([97]), .wait(100), .input([120])]
        var completed = 0, fresh = false
        let epoch = try XCTUnwrap(session.customInputEpoch)
        XCTAssertTrue(session.sendSequencePlan(old, epoch: epoch, resolve: { old[$0].input }, stillValid: { true }, progress: { _ in }, completion: { XCTAssertNotNil($0); completed += 1 }))
        try await wait { held != nil }; session.cancelSequence(epoch: epoch)
        XCTAssertEqual(completed, 1)
        let next: [TerminalSequenceOperation<[UInt8]>] = [.input([98]), .wait(100), .input([99])]
        XCTAssertTrue(session.sendSequencePlan(next, epoch: try XCTUnwrap(session.customInputEpoch), resolve: { next[$0].input }, stillValid: { true }, progress: { _ in }, completion: { XCTAssertNil($0); fresh = true }))
        let pending = held; held = nil; pending?.resume(throwing: CocoaError(.fileWriteUnknown))
        try await wait { fresh && record.received == [98, 99] }
        XCTAssertTrue(session.connected, "The retired writer failure must not stop the newer run")
        XCTAssertEqual(completed, 1)
    }

    func testCancelBehindBlockedPriorWriteIsPromptAndRetainsQueueBudget() async throws {
        let record = SSHTestRecord(echoInput: false), key = NIOSSHPrivateKey(ed25519Key: .init())
        let peer = try await server(record: record, key: key); defer { _ = peer.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic blocked predecessor", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(peer.localAddress?.port))
        let session = DirectTerminalSession(mac: mac); defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { session.trust != nil }; session.answerTrust(true); try await wait { session.canSendUserInput }
        var held: CheckedContinuation<Void, Error>?
        session.beforeWriteForTesting = { bytes in if bytes == [112] { try await withCheckedThrowingContinuation { held = $0 } } }
        defer { held?.resume(); held = nil }
        XCTAssertTrue(session.trySend([112])); try await wait { held != nil }
        let plan: [TerminalSequenceOperation<[UInt8]>] = [.input([120]), .wait(100), .input([121])]
        var completed = 0
        for _ in 0..<3 {
            let epoch = try XCTUnwrap(session.customInputEpoch)
            XCTAssertTrue(session.sendSequencePlan(plan, epoch: epoch, resolve: { plan[$0].input }, stillValid: { true }, progress: { _ in }, completion: { XCTAssertNotNil($0); completed += 1 }))
            session.cancelSequence(epoch: epoch)
        }
        XCTAssertEqual(completed, 3, "Cancel also completes runners still awaiting their predecessor")
        XCTAssertFalse(session.sendSequencePlan(plan, epoch: try XCTUnwrap(session.customInputEpoch), resolve: { plan[$0].input }, stillValid: { true }, progress: { _ in }, completion: { XCTAssertNotNil($0) }), "Canceled but undrained tasks stay within the queue budget")
        XCTAssertTrue(session.trySend([113]))
        let pending = held; held = nil; pending?.resume()
        try await wait { record.received == [112, 113] }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(completed, 3)
        var fresh = false
        XCTAssertTrue(session.sendSequencePlan(plan, epoch: try XCTUnwrap(session.customInputEpoch), resolve: { plan[$0].input }, stillValid: { true }, progress: { _ in }, completion: { XCTAssertNil($0); fresh = true }))
        try await wait { fresh && record.received == [112, 113, 120, 121] }
    }

    func testCustomInputAdmissionFollowsWriterPauseResumeAndQueueLimit() async throws {
        let record = SSHTestRecord(), key = NIOSSHPrivateKey(ed25519Key: .init())
        let peer = try await server(record: record, key: key)
        defer { _ = peer.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic input admission", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(peer.localAddress?.port))
        let defaults = UserDefaults(suiteName: "terminal-admission-" + UUID().uuidString)!
        let session = DirectTerminalSession(mac: mac, activityDefaults: defaults, activityBackend: TerminalActivityTestBackend())
        defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        XCTAssertNil(session.customInputEpoch)
        XCTAssertFalse(session.trySend([0x61]))
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { session.trust != nil }
        XCTAssertFalse(session.trySend([0x61]))
        session.answerTrust(true)
        try await wait { session.canSendUserInput }
        let firstEpoch = try XCTUnwrap(session.customInputEpoch)
        XCTAssertFalse(session.trySend([]))
        XCTAssertTrue(session.trySend(Array("accepted".utf8)))
        try await wait { String(decoding: record.received, as: UTF8.self) == "accepted" }
        session.background(); await session.waitForLifecycleUpdates()
        XCTAssertTrue(session.connected); XCTAssertTrue(session.suspended)
        XCTAssertNil(session.customInputEpoch); XCTAssertFalse(session.trySend(Array("dropped".utf8)))
        session.foreground()
        XCTAssertTrue(session.suspended, "Resume is asynchronous even while connected remains true")
        XCTAssertNil(session.customInputEpoch); XCTAssertFalse(session.trySend(Array("dropped".utf8)))
        await session.waitForLifecycleUpdates()
        XCTAssertTrue(session.canSendUserInput); XCTAssertNotEqual(session.customInputEpoch, firstEpoch)
        let resumedEpoch = try XCTUnwrap(session.customInputEpoch)
        session.becameInactive()
        XCTAssertNil(session.customInputEpoch); XCTAssertFalse(session.trySend(Array("dropped".utf8)))
        session.foreground()
        XCTAssertTrue(session.canSendUserInput); XCTAssertNotEqual(session.customInputEpoch, resumedEpoch)
        session.inputAvailable = { false }
        XCTAssertNil(session.customInputEpoch); XCTAssertFalse(session.trySend(Array("dropped".utf8)))
        session.inputAvailable = { true }
        XCTAssertTrue(session.trySend(Array("-resumed".utf8)))
        try await wait { String(decoding: record.received, as: UTF8.self) == "accepted-resumed" }
        XCTAssertEqual(record.passwordRequests, 1); XCTAssertEqual(record.shellRequests, 1)
        XCTAssertFalse(session.trySend(Array(repeating: 0x61, count: DirectTerminalSession.maximumQueuedInputBytes + 1)))
        XCTAssertFalse(session.connected); XCTAssertNil(session.customInputEpoch)
        XCTAssertEqual(session.recovery?.reason, .inputPaused)
        XCTAssertEqual(String(decoding: record.received, as: UTF8.self), "accepted-resumed", "Rejected input is never replayed")
    }
    func testRealSSHTrustBeforeLoginInteractivePTYOrderedInputResizeAndPreservedShell() async throws {
        let record=SSHTestRecord(),key=NIOSSHPrivateKey(ed25519Key:.init())
        let server=try await server(record:record,key:key)
        let mac=DirectMacRecordV1(id:UUID(),name:"Synthetic SSH",addresses:["127.0.0.1"],sshPort:try XCTUnwrap(server.localAddress?.port))
        let session=DirectTerminalSession(mac:mac)
        var output=[UInt8](); session.received={ output += $0 }
        defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username:"synthetic",password:"synthetic-only",remember:true)
        try await wait { session.trust != nil || !session.connecting }
        XCTAssertNotNil(session.trust); XCTAssertEqual(record.passwordRequests,0)
        session.answerTrust(true); try await wait { session.connected || !session.connecting }
        XCTAssertTrue(session.connected,session.status); XCTAssertEqual(record.passwordRequests,1)
        try await wait { String(decoding:output,as:UTF8.self).contains("synthetic-ready") }
        session.send(Array("A".utf8)); session.send(Array("B".utf8)); session.resize(columns:100,rows:30)
        try await wait { String(decoding:output,as:UTF8.self).hasSuffix("AB") && record.size == [100,30] }
        XCTAssertEqual(record.size,[100,30]); XCTAssertEqual(try TerminalSecretStore.login(mac.id)?.username,"synthetic")
        let controller = TerminalController(session: session, customize: {}); controller.loadViewIfNeeded()
        let render = session.received
        session.received = { render?($0); output += $0 }
        controller.terminal.insertText("a")
        controller.terminal.keyboardState.toggle(.alt); controller.terminal.deleteBackward()
        XCTAssertFalse(controller.terminal.hasText); XCTAssertTrue(controller.terminal.keyboardState.active.isEmpty)
        controller.terminal.insertText("c")
        controller.terminal.keyboardState.toggle(.shift); controller.terminal.insertText("1")
        try await wait { record.received.suffix(5) == [0x61, 0x1b, 0x7f, 0x63, 0x21] }
        controller.terminal.insertText("xy")
        try await wait { record.received.suffix(2) == [0x78, 0x79] }
        let beforeDeletion = record.received.count
        controller.terminal.selectedTextRange = controller.terminal.textRange(from: controller.terminal.beginningOfDocument, to: controller.terminal.endOfDocument)
        controller.terminal.keyboardState.toggle(.alt); controller.terminal.deleteBackward()
        XCTAssertFalse(controller.terminal.hasText)
        try await wait { record.received.count >= beforeDeletion + 2 }
        XCTAssertEqual(Array(record.received.dropFirst(beforeDeletion)), [0x1b, 0x7f])
        for attempt in 0..<4 {
            controller.terminal.keyboardState.toggle(.ctrl)
            let inputCount = record.received.count
            session.background(); await session.waitForLifecycleUpdates()
            XCTAssertTrue(session.connected); XCTAssertTrue(session.suspended)
            XCTAssertTrue(controller.terminal.keyboardState.active.isEmpty)
            session.send(Array("MUST-NOT-REPLAY".utf8))
            session.resize(columns: 110 + attempt, rows: 35 + attempt)
            let marker = "background-output-\(attempt)"
            let renderedCount = output.count
            try await record.emit(marker)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(output.count, renderedCount, "Paused output must not reach the terminal view")
            XCTAssertEqual(session.pausedOutputByteCount, 0, "Pausing transport reads should apply backpressure")
            XCTAssertEqual(record.received.count, inputCount)
            session.foreground(); await session.waitForLifecycleUpdates()
            XCTAssertTrue(session.connected); XCTAssertFalse(session.suspended)
            try await wait("same shell output and latest size resume") {
                String(decoding: output, as: UTF8.self).contains(marker) && record.size == [110 + attempt, 35 + attempt]
            }
            session.send(Array("resume-\(attempt)".utf8))
            try await wait { String(decoding: record.received, as: UTF8.self).hasSuffix("resume-\(attempt)") }
            XCTAssertEqual(record.passwordRequests, 1, "Foreground must retain the same authenticated shell")
        }
        session.background(); session.foreground(); session.background()
        await session.waitForLifecycleUpdates()
        XCTAssertTrue(session.connected); XCTAssertTrue(session.suspended)
        session.foreground(); await session.waitForLifecycleUpdates()
        XCTAssertFalse(session.suspended); XCTAssertEqual(record.passwordRequests, 1)
        session.background(); await session.waitForLifecycleUpdates()
        session.foreground(); session.stop(); await session.waitForLifecycleUpdates()
        XCTAssertFalse(session.connected); XCTAssertFalse(session.suspended)
        session.send(Array("MUST-NOT-REPLAY".utf8)); XCTAssertFalse(session.connected)
        try await server.close()
    }
    func testPausedOutputIsBoundedOrderedAndNotRenderedUntilForeground() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let ssh = try XCTUnwrap((fixture["clientAdditions"] as? [String: Any])?["ssh"] as? [String: Any])
        let lifecycle = try XCTUnwrap(ssh["lifecycle"] as? [String: Any])
        XCTAssertEqual(lifecycle["pendingOutputLimitBytes"] as? Int, DirectTerminalSession.maximumPausedOutputBytes)
        let record = SSHTestRecord(), serverKey = NIOSSHPrivateKey(ed25519Key: .init())
        let server = try await server(record: record, key: serverKey)
        defer { _ = server.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Buffer", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let backend = TerminalActivityTestBackend(), defaults = UserDefaults(suiteName: "terminal-lifecycle-" + UUID().uuidString)!
        let session = DirectTerminalSession(mac: mac, activityDefaults: defaults, activityBackend: backend)
        defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        var output = [UInt8](); session.received = { output += $0 }
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { session.trust != nil || !session.connecting }
        session.answerTrust(true); try await wait { session.connected || !session.connecting }
        try await wait { !output.isEmpty }; output.removeAll()
        await session.waitForLifecycleUpdates()
        XCTAssertEqual(backend.attributes?.kind, .terminal); XCTAssertEqual(backend.phase, .connected)
        session.background(); await session.waitForLifecycleUpdates()
        XCTAssertEqual(backend.phase, .paused)
        try session.receiveOutput([1, 2]); try session.receiveOutput([3, 4])
        XCTAssertTrue(output.isEmpty); XCTAssertEqual(session.pausedOutputByteCount, 4)
        XCTAssertThrowsError(try session.receiveOutput(Array(repeating: 0, count: DirectTerminalSession.maximumPausedOutputBytes))) {
            XCTAssertEqual($0 as? TerminalConnectionFailure, .pausedOutputLimit)
        }
        XCTAssertEqual(session.pausedOutputByteCount, 4)
        session.foreground(); await session.waitForLifecycleUpdates()
        XCTAssertEqual(output, [1, 2, 3, 4]); XCTAssertEqual(session.pausedOutputByteCount, 0)
        XCTAssertEqual(backend.phase, .connected); XCTAssertEqual(record.passwordRequests, 1)
        defaults.set(false, forKey: VNCSessionActivityController.preferenceKey)
        session.activity?.preferenceChanged(); await session.waitForLifecycleUpdates()
        XCTAssertTrue(backend.ids.isEmpty); XCTAssertTrue(session.connected, "Status opt-out must retain SSH")
        session.background(); await session.waitForLifecycleUpdates()
        session.foreground(); await session.waitForLifecycleUpdates()
        XCTAssertTrue(session.connected); XCTAssertEqual(record.passwordRequests, 1)
        defaults.set(true, forKey: VNCSessionActivityController.preferenceKey)
        session.activity?.preferenceChanged(); await session.waitForLifecycleUpdates()
        XCTAssertFalse(session.endActivity("unrelated")); XCTAssertTrue(session.connected)
        XCTAssertTrue(session.endActivity("terminal-synthetic"))
        await session.waitForLifecycleUpdates()
        XCTAssertFalse(session.connected); XCTAssertFalse(session.endActivity("terminal-synthetic"))
        XCTAssertEqual(session.pausedOutputByteCount, 0)
    }
    func testBriefInactivityPublishesLatestDeferredPTYSizeWithoutReplacingShellOrReplayingInput() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let policy = try XCTUnwrap(fixture["recoveryPolicy"] as? [String: Any])
        XCTAssertEqual(policy["inactiveReturnRestoresLatestTerminalGrid"] as? Bool, true)
        let vectors = try XCTUnwrap(fixture["interruptionCases"] as? [[String: Any]])
        let vector = try XCTUnwrap(vectors.first { $0["name"] as? String == "brief-inactive-terminal-grid-change" })
        let expectations = try XCTUnwrap(vector["expect"] as? [String])
        XCTAssertTrue(expectations.contains("no-inactive-composed-input"))
        XCTAssertTrue(expectations.contains("fresh-composed-input-on-foreground"))
        let record = SSHTestRecord(), server = try await server(record: record, key: NIOSSHPrivateKey(ed25519Key: .init()))
        defer { _ = server.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Grid Return", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectTerminalSession(mac: mac, activityDefaults: UserDefaults(suiteName: UUID().uuidString)!, activityBackend: TerminalActivityTestBackend())
        defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.resize(columns: 80, rows: 24)
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { session.trust != nil || !session.connecting }; session.answerTrust(true)
        try await wait { session.connected && record.size == [80, 24] }
        session.becameInactive(); XCTAssertFalse(session.suspended)
        session.resize(columns: 100, rows: 30); session.resize(columns: 120, rows: 40)
        session.send(Array("MUST-NOT-REPLAY".utf8))
        XCTAssertFalse(session.canComposeText, "Composer entry waits for the session foreground handoff")
        var inactiveComposeReply = false
        var inactiveComposeIssue: String?
        session.sendComposedText(Array("INACTIVE-COMPOSER-MUST-NOT-REPLAY".utf8), generation: session.composeGeneration) {
            inactiveComposeReply = true; inactiveComposeIssue = $0
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(inactiveComposeReply)
        XCTAssertNotNil(inactiveComposeIssue, "Composed input must be rejected even while UIKit is globally active")
        XCTAssertEqual(record.sizes, [[80, 24]], "Inactive layout changes cannot write to the PTY")
        XCTAssertTrue(record.received.isEmpty)
        session.foreground()
        session.send(Array("active-only".utf8))
        try await wait("latest deferred grid and fresh input on retained shell") {
            record.size == [120, 40] && String(decoding: record.received, as: UTF8.self) == "active-only"
        }
        XCTAssertEqual(record.sizes, [[80, 24], [120, 40]], "Only the latest inactive grid is published")
        XCTAssertTrue(session.canComposeText)
        var freshComposeReply = false
        var freshComposeIssue: String?
        session.sendComposedText(Array("fresh-compose-only".utf8), generation: session.composeGeneration) {
            freshComposeReply = true; freshComposeIssue = $0
        }
        try await wait("fresh composed input on the same foreground PTY") {
            freshComposeReply && String(decoding: record.received, as: UTF8.self) == "active-onlyfresh-compose-only"
        }
        XCTAssertNil(freshComposeIssue)
        XCTAssertEqual(record.passwordRequests, 1); XCTAssertEqual(record.shellRequests, 1)
        session.foreground(); try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(String(decoding: record.received, as: UTF8.self), "active-onlyfresh-compose-only", "Rejected input is never replayed")
        XCTAssertEqual(record.sizes, [[80, 24], [120, 40]], "Duplicate active notifications do not resend an unchanged grid")
    }
    func testBriefInactivityAndSlowStatusUpdateRetainTheSameShellWithoutInputReplay() async throws {
        let record = SSHTestRecord(), key = NIOSSHPrivateKey(ed25519Key: .init())
        let server = try await server(record: record, key: key)
        defer { _ = server.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Interrupt", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let backend = TerminalActivityTestBackend()
        let session = DirectTerminalSession(mac: mac, activityDefaults: UserDefaults(suiteName: UUID().uuidString)!, activityBackend: backend)
        defer { backend.release(); session.stop(); try? TerminalSecretStore.remove(mac.id) }
        var output = [UInt8](); session.received = { output += $0 }
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { session.trust != nil || !session.connecting }; session.answerTrust(true)
        try await wait { session.connected && !output.isEmpty }; await session.waitForLifecycleUpdates()
        output.removeAll(); session.becameInactive()
        XCTAssertFalse(session.suspended); session.send(Array("MUST-NOT-REPLAY".utf8))
        try await record.emit("inactive-output")
        try await wait { session.pausedOutputByteCount > 0 }
        XCTAssertTrue(output.isEmpty); XCTAssertTrue(record.received.isEmpty)
        session.foreground()
        XCTAssertEqual(String(decoding: output, as: UTF8.self), "inactive-output")
        backend.blocked = true; session.background()
        try await Task.sleep(for: .milliseconds(1150)); XCTAssertTrue(session.connected)
        session.foreground()
        try await wait { !session.suspended }
        session.send(Array("active-only".utf8))
        try await wait { String(decoding: record.received, as: UTF8.self) == "active-only" }
        XCTAssertEqual(record.passwordRequests, 1)
        backend.release(); await session.waitForLifecycleUpdates()
    }
    func testBackgroundCancelsIncompleteTrustWithoutSendingLogin() async throws {
        let record = SSHTestRecord(), server = try await server(record: record, key: NIOSSHPrivateKey(ed25519Key: .init()))
        defer { _ = server.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Trust", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let session = DirectTerminalSession(mac: mac)
        defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { session.trust != nil || !session.connecting }
        XCTAssertNotNil(session.trust)
        session.background(); session.answerTrust(true); session.foreground()
        await session.waitForLifecycleUpdates()
        XCTAssertFalse(session.connected); XCTAssertFalse(session.connecting)
        XCTAssertNil(session.activity); XCTAssertEqual(record.passwordRequests, 0)
        XCTAssertEqual(session.recovery?.reason, .connectionCancelled)
    }
    func testTerminalEndIntentExitsOnlyItsPausedShell() async throws {
        guard ActivityKitSessionBackend().enabled else { throw XCTSkip("Live Activities disabled in Simulator settings") }
        let record = SSHTestRecord(), server = try await server(record: record, key: NIOSSHPrivateKey(ed25519Key: .init()))
        defer { _ = server.close() }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Terminal End", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        let defaults = UserDefaults(suiteName: "terminal-end-" + UUID().uuidString)!
        let session = DirectTerminalSession(mac: mac, activityDefaults: defaults)
        var exits = 0
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: DirectTerminalView(mac: mac, session: session, autoConnect: false, exit: { exits += 1 }).directAppearance())
        window.makeKeyAndVisible()
        defer { session.stop(); window.isHidden = true; window.rootViewController = nil; try? TerminalSecretStore.remove(mac.id) }
        try await Task.sleep(for: .milliseconds(200))
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        try await wait { session.trust != nil || !session.connecting }
        session.answerTrust(true); try await wait { session.connected || !session.connecting }
        await session.waitForLifecycleUpdates()
        let id = try XCTUnwrap(Activity<RemoteSessionActivityAttributes>.activities.first { $0.attributes.macID == mac.id }?.id)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        await session.waitForLifecycleUpdates(); XCTAssertTrue(session.connected); XCTAssertFalse(session.suspended)
        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        await session.waitForLifecycleUpdates(); XCTAssertTrue(session.connected); XCTAssertFalse(session.suspended)
        XCTAssertEqual(record.passwordRequests, 1)
        session.background(); await session.waitForLifecycleUpdates()
        _ = try await EndRemoteSessionIntent(activityID: "unrelated").perform()
        XCTAssertTrue(session.connected); XCTAssertEqual(exits, 0)
        _ = try await EndRemoteSessionIntent(activityID: id).perform()
        XCTAssertFalse(session.connected); XCTAssertEqual(exits, 1)
        _ = try await EndRemoteSessionIntent(activityID: id).perform()
        XCTAssertEqual(exits, 1); XCTAssertFalse(ActivityKitSessionBackend().existingIDs().contains(id))
    }
    func testChangedHostKeyRejectsBeforeAnyPasswordAuthentication() async throws {
        let record=SSHTestRecord(), key=NIOSSHPrivateKey(ed25519Key:.init())
        let server=try await server(record:record,key:key)
        let mac=DirectMacRecordV1(id:UUID(),name:"Synthetic Changed SSH",addresses:["127.0.0.1"],sshPort:try XCTUnwrap(server.localAddress?.port))
        let other=NIOSSHPrivateKey(ed25519Key:.init())
        try TerminalSecretStore.write(Data(String(openSSHPublicKey:other.publicKey).utf8),id:mac.id,kind:"host-key")
        let session=DirectTerminalSession(mac:mac); defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username:"synthetic",password:"synthetic-only",remember:false)
        try await wait { !session.connecting }
        XCTAssertFalse(session.connected); XCTAssertEqual(record.passwordRequests,0); XCTAssertNil(session.trust)
        XCTAssertEqual(session.recovery?.reason, .serverChanged)
        try await server.close()
    }
    func testRejectedFirstHostKeyCancelsWithoutSavingOrSendingLogin() async throws {
        let record=SSHTestRecord(),key=NIOSSHPrivateKey(ed25519Key:.init()),server=try await server(record:record,key:key)
        let mac=DirectMacRecordV1(id:UUID(),name:"Synthetic Reject SSH",addresses:["127.0.0.1"],sshPort:try XCTUnwrap(server.localAddress?.port))
        let session=DirectTerminalSession(mac:mac); defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username:"synthetic",password:"synthetic-only",remember:false)
        try await wait { session.trust != nil || !session.connecting }; XCTAssertNotNil(session.trust,session.status); session.answerTrust(false)
        try await wait { !session.connecting }; XCTAssertEqual(record.passwordRequests,0); XCTAssertNil(try TerminalSecretStore.hostKey(mac.id))
        try await server.close()
    }
}
