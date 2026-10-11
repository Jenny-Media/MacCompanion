import XCTest
import UIKit
import SwiftTerm
import SwiftUI
@preconcurrency import NIOSSH
@testable import MacCompanionVision

@MainActor final class VisionClientTests: XCTestCase {
    private func wait(_ label: String, _ predicate: () -> Bool) async throws {
        for _ in 0..<400 { if predicate() { return }; try await Task.sleep(for: .milliseconds(25)) }
        XCTFail(label); throw POSIXError(.ETIMEDOUT)
    }
    private func withServer(_ mode: DesktopSSHServer.Mode = .rfb, width: Int = 256, height: Int = 128, body: (DesktopSSHServer) async throws -> Void) async throws {
        let server = DesktopSSHServer(mode, width: width, height: height); try await server.start()
        do { try await body(server); try await server.close() }
        catch { try? await server.close(); throw error }
    }
    func testWindowRequestsHaveIndependentIdentitiesForTheSameMac() throws {
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", address: "127.0.0.1")
        let first = VisionSessionRequest(mac: mac, connection: .desktop), next = VisionSessionRequest(mac: mac, connection: .desktop)
        XCTAssertNotEqual(first.id, next.id); XCTAssertNotEqual(first, next)
        let restored = try JSONDecoder().decode(VisionSessionRequest.self, from: JSONEncoder().encode(first))
        XCTAssertEqual(restored, first); XCTAssertEqual(restored.mac, mac)
        XCTAssertNotEqual(VisionSessionRequest(mac: mac, connection: .terminal), first)
    }
    func testGeometryUsesTheManifestIndexedWideUltrawideCorpus() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "native-visionos-client-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for row in try XCTUnwrap(fixture["geometry"] as? [[String: Any]]) {
            let crop = try XCTUnwrap(row["crop"] as? [CGFloat]), size = try XCTUnwrap(row["viewport"] as? [CGFloat])
            let point = try XCTUnwrap(row["point"] as? [CGFloat])
            let rect = CGRect(x: crop[0], y: crop[1], width: crop[2], height: crop[3])
            let destination = VisionDesktopGeometry.destination(crop: rect, viewport: CGSize(width: size[0], height: size[1]))
            let mapped = VisionDesktopGeometry.map(CGPoint(x: point[0], y: point[1]), crop: rect, destination: destination, dragging: row["dragging"] as? Bool ?? false)
            if let expected = row["mapped"] as? [CGFloat] { XCTAssertEqual(mapped, CGPoint(x: expected[0], y: expected[1])) }
            else { XCTAssertNil(mapped) }
        }
    }
    func testNativeDesktopIMECommitsOnceAndCancellationSendsNothing() {
        let view = VisionCommittedTextView(); var committed: [String] = []
        view.admission = { true }; view.committed = { committed.append($0) }
        view.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0))
        XCTAssertTrue(committed.isEmpty)
        view.unmarkText(); XCTAssertEqual(committed, ["中文"])
        view.textViewDidChange(view); XCTAssertEqual(committed, ["中文"])
        view.setMarkedText("未提交", selectedRange: NSRange(location: 3, length: 0)); view.discard()
        XCTAssertEqual(committed, ["中文"]); XCTAssertTrue(view.text.isEmpty); XCTAssertNil(view.markedTextRange)
        view.admission = { false }; view.insertText("discarded")
        XCTAssertEqual(committed, ["中文"])
    }
    func testDesktopSelectionAndKeyboardFocusUseTheOwningNativeWindow() async throws {
        try await withServer { server in
            let mac = try DirectMacRecordV1.normalized(name: "Synthetic input Mac", addresses: ["127.0.0.1"], sshPort: server.port)
            try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
            let session = VisionDesktopSession(mac: mac)
            defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
            session.connect(username: "synthetic", password: "synthetic-only", remember: false)
            try await wait("Connected desktop", { session.connected && session.image != nil })
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
            let previous = scene.windows.first { $0.isKeyWindow }
            let window = UIWindow(windowScene: scene), controller = UIViewController()
            window.rootViewController = controller; window.makeKeyAndVisible()
            defer { window.isHidden = true; previous?.makeKey() }
            let interaction = VisionDesktopInteraction()
            let canvas = VisionDesktopCanvas(session: session, interaction: interaction)
            interaction.canvas = canvas
            canvas.frame = CGRect(x: 0, y: 0, width: 600, height: 300)
            controller.view.addSubview(canvas); canvas.layoutIfNeeded()
            try await wait("Owning window admits input", { session.canInput })
            XCTAssertTrue(canvas.becomeFirstResponder())
            let start = CGPoint(x: 300, y: 150)
            canvas.selectionChanged(start: start, translation: .zero)
            canvas.selectionChanged(start: start, translation: CGPoint(x: 3, y: 4))
            canvas.selectionFinished(cancelled: false)
            try await wait("Short selection clicks", { server.record.count("pointerDown") == 1 && server.record.count("pointerUp") >= 1 })
            canvas.selectionChanged(start: start, translation: .zero)
            canvas.selectionFinished(cancelled: true)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(server.record.count("pointerDown"), 1, "Cancellation must not click")
            canvas.selectionChanged(start: start, translation: .zero)
            canvas.selectionChanged(start: start, translation: CGPoint(x: 25, y: 0))
            canvas.selectionFinished(cancelled: false)
            try await wait("Movement scrolls without a hold", { server.record.count("pointer-mask-32") + server.record.count("pointer-mask-64") > 0 })
            XCTAssertFalse(session.pointerHeld); XCTAssertEqual(server.record.count("pointerDown"), 1)
            canvas.showActions(); canvas.targetAction(.armDrag)
            canvas.selectionChanged(start: start, translation: .zero)
            canvas.selectionChanged(start: start, translation: CGPoint(x: 25, y: 0))
            try await wait("Explicit Drag Item holds", { session.pointerHeld && server.record.count("pointerDown") > 1 })
            session.releaseInput()
            canvas.selectionChanged(start: start, translation: CGPoint(x: 30, y: 0))
            canvas.selectionFinished(cancelled: false)
            XCTAssertFalse(session.pointerHeld, "Interrupted selection must not restart its hold")
            interaction.requestKeyboard()
            let host = UIHostingController(rootView: VisionDesktopKeyboard(session: session, interaction: interaction))
            controller.addChild(host); host.view.frame = CGRect(x: 0, y: 310, width: 600, height: 44)
            controller.view.addSubview(host.view); host.didMove(toParent: controller)
            @MainActor func textView(_ view: UIView) -> VisionCommittedTextView? {
                if let view = view as? VisionCommittedTextView { return view }
                return view.subviews.lazy.compactMap { textView($0) }.first
            }
            try await wait("Native text view mounted", { textView(host.view) != nil })
            let keyboard = try XCTUnwrap(textView(host.view))
            try await wait("Attachment focuses native text input", { keyboard.isFirstResponder })
            XCTAssertFalse(canvas.isFirstResponder)
            keyboard.setMarkedText("未提交", selectedRange: NSRange(location: 3, length: 0))
            let beforeComposition = server.record.count("keyDown")
            keyboard.physical.handle(usage: .keyboardLeftControl, symbol: 0xffe3, flags: .control, down: true)
            try await wait("Text input modifier held", { server.record.count("keyDown-65507") == 1 })
            XCTAssertTrue(canvas.becomeFirstResponder())
            let beforeModifiedClick = server.record.count("pointer-mask-1")
            canvas.selectionChanged(start: start, translation: .zero); canvas.selectionFinished(cancelled: false)
            try await wait("Modified click sent", { server.record.count("pointer-mask-1") == beforeModifiedClick + 1 })
            XCTAssertEqual(server.record.pointerEvents().last(where: { $0.mask == 1 })?.modifiers, [0xffe3], "The peer must observe Control during the click")
            XCTAssertEqual(server.record.count("keyUp-65507"), 0, "A click preserves a held modifier during same-owner focus transfer")
            XCTAssertEqual(server.record.count("keyDown"), beforeComposition + 1, "Returning to the desktop discards composition")
            XCTAssertNil(keyboard.markedTextRange); XCTAssertTrue(keyboard.text.isEmpty)
            keyboard.discard() // Dismantling an already unfocused bar retains the canvas's physical key identities.
            interaction.physicalKeyboard.handle(usage: .keyboardLeftControl, symbol: 0xffe3, flags: [], down: false)
            try await wait("Modifier release survives unfocused bar removal", { server.record.count("keyUp-65507") == 1 })
            interaction.requestKeyboard(); host.rootView = VisionDesktopKeyboard(session: session, interaction: interaction)
            try await wait("One request reopens an already visible keyboard", { keyboard.isFirstResponder })
            keyboard.insertText("x")
            try await wait("Committed text reaches the real peer", { server.record.count("keyDown-120") == 1 })
            session.releaseInput()
            XCTAssertEqual(server.record.count("keyUp-65507"), 1)
        }
    }
    func testPhysicalKeyboardUsesOriginalKeyIdentityAndBalancesModifiers() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "native-visionos-client-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for row in try XCTUnwrap(fixture["physicalKeyboard"] as? [[String: Any]]) {
            let keyboard = VisionPhysicalKeyboard(); var output: [[Any]] = []
            keyboard.send = { output.append([$0, $1]) }
            for event in try XCTUnwrap(row["events"] as? [[String: Any]]) {
                let usage = try XCTUnwrap(UIKeyboardHIDUsage(rawValue: try XCTUnwrap(event["usage"] as? Int)))
                let names = try XCTUnwrap(event["flags"] as? [String]); var flags: UIKeyModifierFlags = []
                if names.contains("control") { flags.insert(.control) }; if names.contains("shift") { flags.insert(.shift) }
                keyboard.handle(usage: usage, symbol: UInt32(try XCTUnwrap(event["symbol"] as? Int)), flags: flags, down: try XCTUnwrap(event["down"] as? Bool))
            }
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: output), try JSONSerialization.data(withJSONObject: row["output"]!))
        }
    }
    func testWideAndUltrawideFramesRenderInNativeCanvasWithoutChangingRemoteSize() async throws {
        for width in [3440, 5120] {
            try await withServer(width: width, height: 1440) { server in
                let mac = try DirectMacRecordV1.normalized(name: "Synthetic wide desktop", addresses: ["127.0.0.1"], sshPort: server.port)
                try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
                let session = VisionDesktopSession(mac: mac); defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
                session.connect(username: "synthetic", password: "synthetic-only", remember: false)
                try await wait("Wide frame received", { session.image != nil })
                XCTAssertEqual(session.framebuffer, CGSize(width: width, height: 1440))
                let canvas = VisionDesktopCanvas(session: session)
                canvas.frame = CGRect(x: 0, y: 0, width: 1200, height: 700); canvas.layoutIfNeeded()
                let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true; format.preferredRange = .standard
                let snapshot = UIGraphicsImageRenderer(size: canvas.bounds.size, format: format).image { context in
                    UIColor.black.setFill(); context.fill(canvas.bounds); canvas.draw(canvas.bounds)
                }
                let image = try XCTUnwrap(snapshot.cgImage), data = try XCTUnwrap(image.dataProvider?.data)
                let bytes = try XCTUnwrap(CFDataGetBytePtr(data)); XCTAssertEqual(image.bitsPerPixel, 32)
                let center = 350 * image.bytesPerRow + 600 * 4
                XCTAssertNotEqual(Array(UnsafeBufferPointer(start: bytes + center, count: 4)), Array(UnsafeBufferPointer(start: bytes, count: 4)), "Native renderer must draw remote content and retain letterboxing")
                XCTAssertEqual(canvas.remote(CGPoint(x: 600, y: 350)), CGPoint(x: width / 2, y: 720))
                XCTAssertNil(canvas.remote(.zero))
                session.zoom = 2; session.pan = CGPoint(x: 100, y: 0); canvas.frame.size.width = 800; canvas.layoutIfNeeded()
                XCTAssertEqual(session.framebuffer.width, CGFloat(width), "Local resize/zoom must not change the Mac resolution")
            }
        }
    }
    func testNativeSwiftTermCompositionCanBeDiscardedWithoutCommitting() {
        let view = VisionTerminalView(frame: CGRect(x: 0, y: 0, width: 1200, height: 600))
        view.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0))
        XCTAssertNotNil(view.markedTextRange)
        view.controlModifier = true; view.metaModifier = true; view.discardComposition()
        XCTAssertNil(view.markedTextRange); XCTAssertFalse(view.controlModifier); XCTAssertFalse(view.metaModifier)
        XCTAssertEqual(view.text(in: view.textRange(from: view.beginningOfDocument, to: view.endOfDocument)!), "")
    }
    func testSSHTrustPrecedesAuthenticationAndNativeDesktopRenders() async throws {
        try await withServer { server in
            let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", addresses: ["127.0.0.1"], sshPort: server.port)
            let session = VisionDesktopSession(mac: mac); defer { session.close(); try? TerminalSecretStore.remove(mac.id); try? DesktopCredentialStoreV1.remove(mac.id) }
            session.inputAvailable = { true }
            session.connect(username: "synthetic", password: "synthetic-only", remember: true)
            try await wait("First-use server trust", { session.trust != nil })
            XCTAssertEqual(server.record.count("auth"), 0); XCTAssertEqual(server.record.count("forward"), 0)
            session.answerTrust(true)
            try await wait("Native encrypted desktop frame", { session.connected && session.image != nil })
            XCTAssertEqual(session.framebuffer, CGSize(width: 256, height: 128))
            XCTAssertEqual(try TerminalSecretStore.hostKey(mac.id), server.hostKey)
            XCTAssertEqual(try DesktopCredentialStoreV1.readChecked(mac.id)?.username, "synthetic")
            session.key(0xffe3, down: true); session.key(0xffe3, down: false)
            session.click(CGPoint(x: 128, y: 64))
            try await wait("Remote input", { server.record.count("keyUp") == 1 && server.record.count("pointerDown") > 0 })
        }
    }
    func testRejectedChangedAndCancelledTrustCannotSendCredentialsOrForward() async throws {
        for scenario in ["reject", "changed", "cancel"] {
            try await withServer { server in
                let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", addresses: ["127.0.0.1"], sshPort: server.port)
                if scenario == "changed" {
                    let unrelated = NIOSSHPrivateKey(ed25519Key: .init())
                    try TerminalSecretStore.write(Data(String(openSSHPublicKey: unrelated.publicKey).utf8), id: mac.id, kind: "host-key")
                }
                let session = VisionDesktopSession(mac: mac); defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
                session.connect(username: "synthetic", password: "synthetic-only", remember: false)
                if scenario == "changed" { try await wait("Changed key rejected", { !session.connecting && session.recovery != nil }); XCTAssertEqual(session.recovery?.reason, .serverChanged) }
                else {
                    try await wait("Trust request", { session.trust != nil })
                    if scenario == "reject" { session.answerTrust(false) } else { session.disconnect() }
                }
                try await wait("SSH closed", { !session.connecting })
                XCTAssertFalse(session.connected); XCTAssertEqual(server.record.count("auth"), 0); XCTAssertEqual(server.record.count("forward"), 0)
                if scenario != "changed" { XCTAssertNil(try TerminalSecretStore.hostKey(mac.id)) }
            }
        }
    }
    func testTwoDesktopsForSameMacReleaseOnlyTheirOwnInput() async throws {
        try await withServer { server in
            let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", addresses: ["127.0.0.1"], sshPort: server.port)
            try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
            let first = VisionDesktopSession(mac: mac), second = VisionDesktopSession(mac: mac)
            defer { first.close(); second.close(); try? TerminalSecretStore.remove(mac.id) }
            var firstFocused = true; first.inputAvailable = { firstFocused }; second.inputAvailable = { true }
            first.connect(username: "synthetic", password: "synthetic-only", remember: false)
            second.connect(username: "synthetic", password: "synthetic-only", remember: false)
            try await wait("Both windows connected", { first.connected && second.connected && first.image != nil && second.image != nil })
            first.key(0xff1b, down: true); second.key(0xffe3, down: true)
            try await wait("Both holds", { server.record.count("keyDown") == 2 })
            firstFocused = false; first.releaseInput(); first.releaseInput()
            try await wait("First owner release", { server.record.count("keyUp-65307") == 1 })
            XCTAssertEqual(server.record.count("keyUp-65507"), 0); XCTAssertTrue(second.canInput)
            first.key(0xff09, down: true)
            first.close(); XCTAssertTrue(second.connected); second.key(0xffe3, down: false)
            try await wait("Second owner still sends", { server.record.count("keyUp-65507") == 1 })
            XCTAssertEqual(server.record.count("keyDown"), 2); XCTAssertEqual(server.record.count("keyUp-65307"), 1)
        }
    }
    func testDesktopInterruptionClearsFrameAndReleasesBeforeResume() async throws {
        try await withServer { server in
            let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", addresses: ["127.0.0.1"], sshPort: server.port)
            try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
            let session = VisionDesktopSession(mac: mac); defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
            session.inputAvailable = { true }; session.connect(username: "synthetic", password: "synthetic-only", remember: false)
            try await wait("Initial frame", { session.connected && session.image != nil })
            session.key(0xffe3, down: true); session.pointer(CGPoint(x: 128, y: 64), mask: 1)
            try await wait("Held input", { server.record.count("keyDown") == 1 && server.record.count("pointerDown") > 0 })
            session.pause(); XCTAssertNil(session.image); XCTAssertFalse(session.canInput)
            try await wait("Held key released", { server.record.count("keyUp") == 1 })
            session.resume(); try await wait("Fresh frame after resume", { session.image != nil && session.canInput })
        }
    }
    func testPerWindowTerminalAdmissionIsCheckedBeforeQueuedWriteExecutes() async throws {
        let server = SSHTestServer(); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", addresses: ["127.0.0.1"], sshPort: server.port)
        let session = DirectTerminalSession(mac: mac); var focused = true; session.inputAvailable = { focused }
        do {
            try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
            session.connect(username: "synthetic", password: "synthetic-only", remember: false)
            try await wait("Terminal connected", { session.connected })
            for _ in 0..<8 {
                session.send([UInt8](repeating: 32, count: 16_384)); focused = false
                try await Task.sleep(for: .milliseconds(15)); XCTAssertTrue(session.connected)
                focused = true
            }
            XCTAssertTrue(server.record.received.isEmpty)
            focused = true; session.send(Array("accepted".utf8))
            try await wait("Focused terminal input", { server.record.received == Array("accepted".utf8) })
            session.stop(); try TerminalSecretStore.remove(mac.id); try await server.close()
        } catch { session.stop(); try? TerminalSecretStore.remove(mac.id); try? await server.close(); throw error }
    }
    func testUnfocusedTerminalAnswersEmulatorQueryButRejectsUserInput() async throws {
        let server = SSHTestServer(); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", addresses: ["127.0.0.1"], sshPort: server.port)
        let session = DirectTerminalSession(mac: mac), interaction = VisionTerminalInteraction()
        let coordinator = VisionTerminalSurface.Coordinator(session: session, interaction: interaction)
        let view = VisionTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 500)); coordinator.view = view; view.terminalDelegate = coordinator
        session.inputAvailable = { false }; session.received = { [weak coordinator] in coordinator?.feed($0) }
        do {
            try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
            session.connect(username: "synthetic", password: "synthetic-only", remember: false)
            try await wait("Terminal connected", { session.connected })
            session.send(Array("unfocused-user-input".utf8))
            try await server.record.emit("\u{1b}[5n")
            try await wait("Emulator reply", { server.record.received == Array("\u{1b}[0n".utf8) })
            session.background(); session.send([3], source: .emulatorReply)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(server.record.received, Array("\u{1b}[0n".utf8))
            session.stop(); try TerminalSecretStore.remove(mac.id); try await server.close()
        } catch { session.stop(); try? TerminalSecretStore.remove(mac.id); try? await server.close(); throw error }
    }
}
