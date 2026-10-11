import XCTest
import UIKit
import SwiftUI
import SwiftTerm
@testable import MacCompanionVision

@MainActor final class VisionReviewRegressionTests: XCTestCase {
    private func wait(_ label: String, _ predicate: () -> Bool) async throws {
        for _ in 0..<400 { if predicate() { return }; try await Task.sleep(for: .milliseconds(25)) }
        XCTFail(label); throw POSIXError(.ETIMEDOUT)
    }
    private func window() throws -> (UIWindow, UIWindow?) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let previous = scene.keyWindow, window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController(); window.makeKeyAndVisible()
        return (window, previous)
    }
    private func descendants<T: UIView>(_ view: UIView, _: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? view.subviews.flatMap { descendants($0, T.self) }
    }
    func testViewportRetirementCannotRepressModifierFromOldRelease() async throws {
        let server = DesktopSSHServer(.rfb); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic keyboard retirement", addresses: ["127.0.0.1"], sshPort: server.port)
        try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
        let session = VisionDesktopSession(mac: mac), interaction = VisionDesktopInteraction()
        let (window, previous) = try window()
        defer { session.close(); window.isHidden = true; previous?.makeKey(); try? TerminalSecretStore.remove(mac.id) }
        do {
            let canvas = VisionDesktopCanvas(session: session, interaction: interaction)
            canvas.frame = CGRect(x: 0, y: 0, width: 600, height: 300)
            window.rootViewController!.view.addSubview(canvas); canvas.layoutIfNeeded()
            session.connect(username: "synthetic", password: "synthetic-only", remember: false)
            try await wait("Desktop admits keys", { session.canInput })
            XCTAssertTrue(canvas.becomeFirstResponder())
            let keys = interaction.physicalKeyboard
            keys.handle(usage: .keyboardLeftControl, symbol: 0xffe3, flags: .control, down: true)
            keys.handle(usage: .keyboardA, symbol: 97, flags: .control, down: true)
            try await wait("Chord reaches peer", { server.record.count("keyDown-97") == 1 })
            canvas.frame.size.width = 650; canvas.setNeedsLayout(); canvas.layoutIfNeeded()
            try await wait("Resize balances keys", { server.record.count("keyUp-65507") == 1 && server.record.count("keyUp-97") == 1 })
            keys.handle(usage: .keyboardA, symbol: 97, flags: .control, down: false)
            keys.handle(usage: .keyboardLeftControl, symbol: 0xffe3, flags: [], down: false)
            keys.handle(usage: .keyboardB, symbol: 98, flags: [], down: true)
            keys.handle(usage: .keyboardB, symbol: 98, flags: [], down: false)
            try await wait("Fresh key still works", { server.record.count("keyUp-98") == 1 })
            XCTAssertEqual(server.record.count("keyDown-65507"), 1)
            XCTAssertEqual(server.record.count("keyUp-65507"), 1)
            try await server.close()
        } catch { try? await server.close(); throw error }
    }
    func testDelayedNativeTerminalAttachmentPreservesInitialPTYBanner() async throws {
        let server = SSHTestServer(); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic startup", addresses: ["127.0.0.1"], sshPort: server.port)
        try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
        let session = DirectTerminalSession(mac: mac), output = VisionTerminalOutput(session: session)
        let (window, previous) = try window()
        defer { session.stop(); window.isHidden = true; previous?.makeKey(); try? TerminalSecretStore.remove(mac.id) }
        do {
            session.connect(username: "synthetic", password: "synthetic-only", remember: false)
            try await wait("PTY output waits for presentation", { session.connected && output.pendingByteCount > 0 })
            try session.receiveOutput(Array("synthetic-before-render\r\n".utf8))
            let host = UIHostingController(rootView: VisionTerminalSurface(session: session, interaction: .init(), output: output).directAppearance())
            window.rootViewController = host; host.view.layoutIfNeeded()
            try await wait("Terminal attaches", { !self.descendants(host.view, VisionTerminalView.self).isEmpty })
            let view = try XCTUnwrap(descendants(host.view, VisionTerminalView.self).first)
            try await wait("Terminal completes native layout", { view.window != nil && view.getTerminal().cols >= 40 && view.getTerminal().rows >= 4 })
            let text = String(decoding: view.getTerminal().getBufferAsData(), as: UTF8.self)
            XCTAssertTrue(text.contains("synthetic-ready")); XCTAssertTrue(text.contains("synthetic-before-render"))
            XCTAssertEqual(output.pendingByteCount, 0)
            // The pinned SwiftTerm schedules its display cache refresh on a
            // 16.67 ms timer after feed. Capture the painted frame, not the
            // previous cache while the emulator already contains the new text.
            try await Task.sleep(for: .milliseconds(100))
            view.layoutIfNeeded(); view.setNeedsDisplay(); view.layer.displayIfNeeded()
            let rendered = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
                XCTAssertTrue(view.drawHierarchy(in: view.bounds, afterScreenUpdates: true))
            }
            let capture = XCTAttachment(image: rendered); capture.name = "Native Terminal startup rendering"; capture.lifetime = .keepAlways; add(capture)
            try await server.close()
        } catch { try? await server.close(); throw error }
    }
    func testTerminalBufferRetiresOldShellAndIgnoresStaleDetach() throws {
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic buffer owner", address: "127.0.0.1")
        let session = DirectTerminalSession(mac: mac), output = VisionTerminalOutput(session: session)
        try session.receiveOutput(Array("old-shell".utf8)); XCTAssertGreaterThan(output.pendingByteCount, 0)
        session.stop()
        var first: [UInt8] = [], second: [UInt8] = []
        let old = output.attach { first += $0 }
        XCTAssertTrue(first.isEmpty, "The retired shell's pending bytes cannot enter the new emulator")
        let current = output.attach { second += $0 }
        output.detach(old)
        try session.receiveOutput(Array("current-shell".utf8))
        XCTAssertTrue(first.isEmpty); XCTAssertEqual(second, Array("current-shell".utf8))
        XCTAssertTrue(output.owns(current)); XCTAssertFalse(output.owns(old))
        output.detach(current)
        var delayed: [UInt8] = []
        let preparing = output.attach({ delayed += $0 }, ready: false)
        try session.receiveOutput(Array("before-layout".utf8)); XCTAssertTrue(delayed.isEmpty)
        XCTAssertGreaterThan(output.pendingByteCount, 0)
        output.activate(old); XCTAssertTrue(delayed.isEmpty, "A stale layout cannot activate the new receiver")
        output.activate(preparing); XCTAssertEqual(delayed, Array("before-layout".utf8))
        output.activate(preparing); XCTAssertEqual(delayed, Array("before-layout".utf8), "Layout repeats cannot replay output")
        output.detach(preparing)
    }
    func testTerminalStartupOverflowEndsExplicitly() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "native-visionos-client-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let row = try XCTUnwrap(fixture["terminalOutput"] as? [String: Any])
        let maximum = try XCTUnwrap(row["maximumPendingBytes"] as? Int)
        XCTAssertEqual(maximum, DirectTerminalSession.maximumPausedOutputBytes)
        let server = SSHTestServer(); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic buffer bound", addresses: ["127.0.0.1"], sshPort: server.port)
        try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
        let session = DirectTerminalSession(mac: mac), output = VisionTerminalOutput(session: session)
        defer { session.stop(); try? TerminalSecretStore.remove(mac.id) }
        do {
            session.connect(username: "synthetic", password: "synthetic-only", remember: false)
            try await wait("Shell is live before overflow", { session.connected && output.pendingByteCount > 0 })
            try session.receiveOutput([UInt8](repeating: 120, count: maximum - output.pendingByteCount))
            XCTAssertEqual(output.pendingByteCount, maximum)
            try session.receiveOutput([120])
            XCTAssertEqual(output.pendingByteCount, 0); XCTAssertEqual(session.recovery?.reason, .inputPaused)
            XCTAssertFalse(session.connected)
            try await server.close()
        } catch { try? await server.close(); throw error }
    }
    func testSensitiveSceneLifecycleUsesIndexedCases() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "native-visionos-client-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for row in try XCTUnwrap(fixture["sensitiveSceneLifecycle"] as? [[String: Any]]) {
            let name = try XCTUnwrap(row["phase"] as? String)
            let phase: ScenePhase = name == "background" ? .background : name == "inactive" ? .inactive : .active
            XCTAssertEqual(VisionSensitiveLifecycle.interrupts(phase: phase, locked: try XCTUnwrap(row["locked"] as? Bool)), row["interrupt"] as? Bool)
        }
    }
    func testNativeImportPassphraseClearsOnlyOnOwningSceneBackground() async throws {
        let (window, previous) = try window()
        let form = TerminalKeyComposer(importing: true, save: { _, _ in XCTFail("Background cannot save a key"); return false })
        let host = UIHostingController(rootView: form.environment(\.scenePhase, .active))
        window.rootViewController = host; host.view.layoutIfNeeded()
        defer { window.isHidden = true; previous?.makeKey() }
        try await wait("Secure import field mounted", { self.descendants(host.view, UITextField.self).contains { $0.isSecureTextEntry } })
        let field = try XCTUnwrap(descendants(host.view, UITextField.self).first { $0.isSecureTextEntry })
        XCTAssertTrue(field.becomeFirstResponder()); field.insertText("synthetic-draft-only")
        try await wait("Native binding holds draft", { field.text == "synthetic-draft-only" })
        host.rootView = form.environment(\.scenePhase, .inactive)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(field.text, "synthetic-draft-only", "Temporary authentication inactivity must not cancel the operation")
        host.rootView = form.environment(\.scenePhase, .background)
        try await wait("Owning scene background purges draft", { self.descendants(host.view, UITextField.self).filter { $0.isSecureTextEntry }.allSatisfy { $0.text?.isEmpty != false } })
        host.rootView = form.environment(\.scenePhase, .active)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(descendants(host.view, UITextField.self).filter { $0.isSecureTextEntry }.allSatisfy { $0.text?.isEmpty != false })
        XCTAssertTrue(DirectAppLockV1.shared.canAccess, "The simulated scene transition does not lock another active window")
    }
    func testUnreadableLibraryPreservesDataAndRetryRestoresSaving() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "macs.json"), bad = Data("synthetic-unreadable".utf8)
        try bad.write(to: url)
        let library = DirectMacLibraryV1(url: url, removeLogin: { _ in })
        XCTAssertFalse(library.readable); XCTAssertNotNil(library.recovery)
        XCTAssertFalse(VisionMacSaving.save(library: library, mac: nil, name: "Synthetic", addresses: "127.0.0.1", desktopPort: "5900", sshPort: "22"))
        XCTAssertEqual(try Data(contentsOf: url), bad)
        let goodURL = directory.appending(path: "recovered.json")
        let recovered = DirectMacLibraryV1(url: goodURL, removeLogin: { _ in })
        XCTAssertTrue(recovered.save(id: nil, name: "Synthetic recovered", addresses: ["127.0.0.1"]))
        try Data(contentsOf: goodURL).write(to: url)
        library.reload()
        XCTAssertTrue(library.readable); XCTAssertNil(library.recovery)
        let mac = try XCTUnwrap(library.macs.first)
        XCTAssertTrue(VisionMacSaving.save(library: library, mac: mac, name: "Edited after retry", addresses: "127.0.0.1", desktopPort: "5900", sshPort: "22"))
        XCTAssertEqual(DirectMacLibraryV1(url: url, removeLogin: { _ in }).macs.first?.name, "Edited after retry")
    }
    func testRemovedEditorSnapshotCannotBypassFreeCreationLimit() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "vision-save-" + UUID().uuidString))
        let access = DirectProAccess(defaults: defaults)
        let library = DirectMacLibraryV1(url: directory.appending(path: "macs.json"), removeLogin: { _ in })
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertTrue(library.save(id: nil, name: "Removed while editing", addresses: ["127.0.0.1"]))
        let snapshot = try XCTUnwrap(library.macs.first)
        XCTAssertTrue(library.save(id: nil, name: "Kept free Mac", addresses: ["127.0.0.2"]))
        let kept = try XCTUnwrap(library.macs.last)
        try library.applyCloud([kept])
        let before = try Data(contentsOf: directory.appending(path: "macs.json"))
        XCTAssertFalse(VisionMacSaving.save(library: library, mac: snapshot, name: "Recreated", addresses: "127.0.0.1", desktopPort: "5900", sshPort: "22", access: access))
        XCTAssertEqual(library.macs, [kept]); XCTAssertEqual(try Data(contentsOf: directory.appending(path: "macs.json")), before)
        XCTAssertTrue(VisionMacSaving.save(library: library, mac: kept, name: "Edited current", addresses: "127.0.0.2", desktopPort: "5900", sshPort: "22", access: access))
        library.remove(library.macs[0])
        XCTAssertTrue(VisionMacSaving.save(library: library, mac: snapshot, name: "New permitted Mac", addresses: "127.0.0.1", desktopPort: "5900", sshPort: "22", access: access))
        XCTAssertEqual(library.macs.count, 1)
    }
}
