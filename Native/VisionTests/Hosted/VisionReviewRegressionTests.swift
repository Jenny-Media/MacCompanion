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
    private func cancellation(_ surface: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "native-visionos-client-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let rows = try XCTUnwrap(fixture["hardwareCancellation"] as? [String: Any])
        if surface == "canvas" {
            var row = try XCTUnwrap(rows["desktop"] as? [String: Any])
            row["cases"] = rows["canvasCases"]
            return row
        }
        return try XCTUnwrap(rows[surface] as? [String: Any])
    }
    private func press(_ row: [String: Any], prefix: String = "", control: Bool = false) throws -> CancellationPress {
        let usage = try XCTUnwrap(UIKeyboardHIDUsage(rawValue: try XCTUnwrap(row[prefix + "Usage"] as? Int)))
        return CancellationPress(CancellationKey(usage: usage, text: row[prefix + "Characters"] as? String ?? "", flags: control ? .control : []))
    }
    private func desktopCancellation(retired: Bool) async throws {
        let row = try cancellation("desktop")
        XCTAssertEqual(Set(try XCTUnwrap(row["cases"] as? [String])), ["focused-cancel", "duplicate-endpoints", "modified-click", "retired-same-hid"])
        let server = DesktopSSHServer(.rfb); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic cancellation", addresses: ["127.0.0.1"], sshPort: server.port)
        try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
        let session = VisionDesktopSession(mac: mac), interaction = VisionDesktopInteraction()
        interaction.requestKeyboard()
        let (window, previous) = try window()
        defer { session.close(); window.isHidden = true; previous?.makeKey(); try? TerminalSecretStore.remove(mac.id) }
        do {
            let host = UIHostingController(rootView: VStack {
                VisionDesktopSurface(session: session, interaction: interaction)
                VisionDesktopKeyboard(session: session, interaction: interaction).frame(height: 56)
            }.directAppearance())
            window.rootViewController = host; host.view.layoutIfNeeded()
            session.connect(username: "synthetic", password: "synthetic-only", remember: false)
            try await wait("Native keyboard ready", { session.canInput && !self.descendants(host.view, VisionCommittedTextView.self).isEmpty })
            let view = try XCTUnwrap(descendants(host.view, VisionCommittedTextView.self).first)
            XCTAssertTrue(view.becomeFirstResponder())
            let original = CancellationPress(CancellationKey(usage: try XCTUnwrap(UIKeyboardHIDUsage(rawValue: try XCTUnwrap(row["usage"] as? Int))), text: try XCTUnwrap(row["characters"] as? String), flags: .control))
            let modifier = try press(row, prefix: "modifier", control: true)
            view.pressesBegan([modifier], with: nil); view.pressesBegan([original], with: nil)
            let key = try XCTUnwrap(row["key"] as? Int), modifierKey = try XCTUnwrap(row["modifierKey"] as? Int)
            try await wait("Captured chord reaches real RFB", { server.record.count("keyDown-\(key)") == 1 && server.record.count("keyDown-\(modifierKey)") == 1 })
            if retired {
                session.releaseInput(discardComposition: false)
                try await wait("Retirement balances first owner", { server.record.count("keyUp-\(key)") == 1 && server.record.count("keyUp-\(modifierKey)") == 1 })
                let fresh = CancellationPress(CancellationKey(usage: original.sample.keyCode, text: original.sample.charactersIgnoringModifiers, flags: .control))
                view.pressesBegan([fresh], with: nil)
                try await wait("Same HID starts fresh owner", { server.record.count("keyDown-\(key)") == 2 })
                original.sampledPhase = .cancelled; view.pressesCancelled([original, modifier], with: nil)
                view.pressesEnded([original, modifier], with: nil)
                try await Task.sleep(for: .milliseconds(100))
                XCTAssertEqual(server.record.count("keyUp-\(key)"), 1)
                XCTAssertEqual(server.record.count("keyUp-\(modifierKey)"), 1)
                fresh.sampledPhase = .cancelled; view.pressesCancelled([fresh], with: nil)
                try await wait("Fresh owner cancels once", { server.record.count("keyUp-\(key)") == 2 && server.record.count("keyUp-\(modifierKey)") == 2 })
            } else {
                let canvas = try XCTUnwrap(interaction.canvas)
                let point = CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY)
                canvas.selectionChanged(start: point, translation: .zero); canvas.selectionFinished(cancelled: false)
                try await wait("Modified click reaches peer", { server.record.count("pointer-mask-1") == 1 })
                XCTAssertEqual(server.record.pointerEvents().first { $0.mask == 1 }?.modifiers, [UInt32(modifierKey)])
                XCTAssertEqual(server.record.count("keyUp-\(modifierKey)"), 0)
                XCTAssertTrue(view.becomeFirstResponder())
                original.sampledPhase = .cancelled; view.pressesCancelled([original], with: nil)
                try await wait("Cancel balances full captured owner", { server.record.count("keyUp-\(key)") == 1 && server.record.count("keyUp-\(modifierKey)") == 1 })
                XCTAssertTrue(view.isFirstResponder, "Cancellation does not require focus loss")
                view.pressesCancelled([original, modifier], with: nil); view.pressesEnded([original, modifier], with: nil)
            }
            let fresh = try press(row, prefix: "fresh")
            view.pressesBegan([fresh], with: nil); fresh.sampledPhase = .ended; view.pressesEnded([fresh], with: nil)
            let freshKey = try XCTUnwrap(row["freshKey"] as? Int)
            try await wait("Fresh captured arrow balances", { server.record.count("keyUp-\(freshKey)") == 1 })
            XCTAssertEqual(server.record.count("keyDown-\(key)"), retired ? 2 : 1)
            XCTAssertEqual(server.record.count("keyUp-\(key)"), retired ? 2 : 1)
            XCTAssertEqual(server.record.count("keyDown-\(modifierKey)"), retired ? 2 : 1)
            XCTAssertEqual(server.record.count("keyUp-\(modifierKey)"), retired ? 2 : 1)
            try await server.close()
        } catch { try? await server.close(); throw error }
    }
    func testNativeDesktopCancellationBalancesChordWithoutLosingFocus() async throws { try await desktopCancellation(retired: false) }
    func testRetiredNativeKeyboardCancellationCannotReleaseFreshSameHID() async throws { try await desktopCancellation(retired: true) }
    func testNativeCanvasEndpointsCannotRetireFreshKeysOrPointer() async throws {
        let row = try cancellation("canvas")
        XCTAssertEqual(Set(try XCTUnwrap(row["cases"] as? [String])), ["current-cancel", "duplicate-endpoints", "retired-same-hid-and-control-flags", "late-cancel-during-fresh-drag"])
        let server = DesktopSSHServer(.rfb); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic canvas cancellation", addresses: ["127.0.0.1"], sshPort: server.port)
        try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
        let session = VisionDesktopSession(mac: mac), interaction = VisionDesktopInteraction()
        let (window, previous) = try window()
        defer { session.close(); window.isHidden = true; previous?.makeKey(); try? TerminalSecretStore.remove(mac.id) }
        do {
            let canvas = VisionDesktopCanvas(session: session, interaction: interaction)
            canvas.frame = CGRect(x: 0, y: 0, width: 600, height: 300)
            window.rootViewController!.view.addSubview(canvas); canvas.layoutIfNeeded()
            session.connect(username: "synthetic", password: "synthetic-only", remember: false)
            try await wait("Canvas ready", { session.canInput && session.image != nil })
            XCTAssertTrue(canvas.becomeFirstResponder())
            let usage = try XCTUnwrap(UIKeyboardHIDUsage(rawValue: try XCTUnwrap(row["usage"] as? Int)))
            let text = try XCTUnwrap(row["characters"] as? String)
            let original = CancellationPress(CancellationKey(usage: usage, text: text, flags: .control))
            let modifier = try press(row, prefix: "modifier", control: true)
            let key = try XCTUnwrap(row["key"] as? Int), control = try XCTUnwrap(row["modifierKey"] as? Int)
            canvas.pressesBegan([modifier, original], with: nil)
            try await wait("Canvas chord admitted", { server.record.count("keyDown-\(key)") == 1 && server.record.count("keyDown-\(control)") == 1 })
            original.sampledPhase = .cancelled; canvas.pressesCancelled([original], with: nil)
            try await wait("Current canvas cancellation balances", { server.record.count("keyUp-\(key)") == 1 && server.record.count("keyUp-\(control)") == 1 })
            XCTAssertTrue(canvas.isFirstResponder)
            let fresh = CancellationPress(CancellationKey(usage: usage, text: text, flags: []))
            canvas.pressesBegan([fresh], with: nil)
            try await wait("Fresh same HID admitted", { server.record.count("keyDown-\(key)") == 2 })
            canvas.physicalSelection(start: CGPoint(x: 300, y: 150), translation: .zero)
            try await wait("Fresh pointer hold admitted", { session.pointerHeld && server.record.pointerEvents().last?.mask == 1 })
            XCTAssertEqual(server.record.pointerEvents().last?.modifiers, [], "Fresh drag cannot inherit retired Control")
            let pointers = server.record.pointerEvents().count
            original.sampledPhase = .ended; canvas.pressesEnded([original, modifier], with: nil)
            original.sampledPhase = .cancelled; canvas.pressesCancelled([original, modifier], with: nil)
            canvas.pressesCancelled([original], with: nil)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(server.record.count("keyUp-\(key)"), 1)
            XCTAssertEqual(server.record.count("keyDown-\(control)"), 1, "Old flags cannot reconstruct retired Control")
            XCTAssertEqual(server.record.count("keyUp-\(control)"), 1)
            XCTAssertEqual(server.record.pointerEvents().count, pointers); XCTAssertTrue(session.pointerHeld)
            fresh.sampledPhase = .cancelled; canvas.pressesCancelled([fresh], with: nil)
            try await wait("Current cancellation releases fresh key and pointer", { server.record.count("keyUp-\(key)") == 2 && server.record.pointerEvents().last?.mask == 0 })
            XCTAssertFalse(session.pointerHeld)
            canvas.selectionFinished(cancelled: true)
            let arrow = try press(row, prefix: "fresh")
            canvas.pressesBegan([arrow], with: nil)
            canvas.pressesEnded([fresh], with: nil); canvas.pressesCancelled([fresh], with: nil)
            arrow.sampledPhase = .ended; canvas.pressesEnded([arrow], with: nil)
            let arrowKey = try XCTUnwrap(row["freshKey"] as? Int)
            try await wait("Fresh arrow balances after retired endpoints", { server.record.count("keyUp-\(arrowKey)") == 1 })
            XCTAssertEqual(server.record.count("keyUp-\(key)"), 2)
            XCTAssertEqual(server.record.count("keyDown-\(control)"), 1)
            try await server.close()
        } catch { try? await server.close(); throw error }
    }
    private func terminalCancellation(kitty: Bool) async throws {
        let row = try cancellation("terminal")
        XCTAssertEqual(Set(try XCTUnwrap(row["cases"] as? [String])), ["repeat-cancel", "duplicate-endpoints", "retired-same-hid", "kitty-cancel"])
        let server = SSHTestServer(); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic terminal cancellation", addresses: ["127.0.0.1"], sshPort: server.port)
        try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
        let session = DirectTerminalSession(mac: mac), interaction = VisionTerminalInteraction()
        let (window, previous) = try window()
        defer { session.stop(); window.isHidden = true; previous?.makeKey(); try? TerminalSecretStore.remove(mac.id) }
        do {
            let host = UIHostingController(rootView: VisionTerminalSurface(session: session, interaction: interaction).directAppearance())
            window.rootViewController = host; host.view.layoutIfNeeded()
            session.connect(username: "synthetic", password: "synthetic-only", remember: false)
            try await wait("Native Terminal ready", { session.connected && !self.descendants(host.view, VisionTerminalView.self).isEmpty })
            let view = try XCTUnwrap(descendants(host.view, VisionTerminalView.self).first)
            XCTAssertTrue(view.becomeFirstResponder())
            if kitty {
                let mode = try XCTUnwrap(row["kittyMode"] as? [UInt8])
                try await server.record.emit(String(decoding: mode, as: UTF8.self))
                try await wait("Kitty reporting negotiated", { view.getTerminal().keyboardEnhancementFlags.contains(.reportEvents) })
            }
            let usage = try XCTUnwrap(UIKeyboardHIDUsage(rawValue: try XCTUnwrap(row["usage"] as? Int)))
            let original = CancellationPress(CancellationKey(usage: usage, text: try XCTUnwrap(row["characters"] as? String), flags: []))
            view.pressesBegan([original], with: nil)
            let down = try XCTUnwrap(row[kitty ? "kittyPress" : "legacyPress"] as? [UInt8])
            try await wait("Native key reaches real SSH", { server.record.received.starts(with: down) })
            if !kitty { try await wait("Inherited timer repeats", { server.record.received.count >= down.count * 2 }) }
            original.sampledPhase = .cancelled; view.pressesCancelled([original], with: nil)
            let release = try XCTUnwrap(row["kittyRelease"] as? [UInt8])
            if kitty { try await wait("Cancellation reports one release", { server.record.received == down + release }) }
            try await Task.sleep(for: .milliseconds(100))
            let afterCancel = server.record.received
            XCTAssertTrue(view.isFirstResponder)
            view.pressesCancelled([original], with: nil); original.sampledPhase = .ended; view.pressesEnded([original], with: nil)
            try await Task.sleep(for: .milliseconds(550)); XCTAssertEqual(server.record.received, afterCancel, "No repeat or duplicate release after cancellation")
            let fresh = CancellationPress(CancellationKey(usage: usage, text: original.sample.characters, flags: []))
            view.pressesBegan([fresh], with: nil)
            try await wait("Same HID starts new native press", { server.record.received.count > afterCancel.count })
            view.pressesCancelled([original], with: nil); view.pressesEnded([original], with: nil)
            if !kitty { try await wait("Old endpoint cannot stop fresh repeat", { server.record.received.count >= afterCancel.count + down.count * 2 }) }
            fresh.sampledPhase = .ended; view.pressesEnded([fresh], with: nil)
            try await Task.sleep(for: .milliseconds(100))
            let afterEnd = server.record.received
            if kitty { XCTAssertEqual(afterEnd, down + release + down + release) }
            try await Task.sleep(for: .milliseconds(550)); XCTAssertEqual(server.record.received, afterEnd)
            try await server.close()
        } catch { try? await server.close(); throw error }
    }
    func testNativeTerminalCancellationStopsRepeatAndIgnoresOldEndpoints() async throws { try await terminalCancellation(kitty: false) }
    func testNativeTerminalCancellationBalancesNegotiatedKittyRelease() async throws { try await terminalCancellation(kitty: true) }
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
    func testImportCompletionRetainsPresentationOwnershipAcrossSceneChanges() throws {
        try checkFileRequestCompletions(importing: true)
    }
    func testExportCompletionCannotClearANewerPresentation() throws {
        try checkFileRequestCompletions(importing: false)
    }
    private func checkFileRequestCompletions(importing: Bool) throws {
        let fixtureURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "native-visionos-client-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any])
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let contents = "synthetic-file-request-only"
        try Data(contents.utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        for row in try XCTUnwrap(fixture["fileRequestCompletion"] as? [[String: Any]]) {
            let name = try XCTUnwrap(row["name"] as? String)
            let requests = VisionFileRequests(); requests.scenePhase = .active
            var generation = UUID(), unlocked = true, receipts = 0, reads = 0, errors = 0
            var exportDraft: Data? = Data(contents.utf8)
            let receive: (Result<URL, Error>) -> Void = { result in
                receipts += 1
                if importing, case .success(let url) = result {
                    reads += 1
                    XCTAssertEqual(try? TerminalSSHKey.readOpenSSHFile(url), contents)
                }
                if case .failure = result { errors += 1 }
                if !importing { exportDraft = nil }
            }
            let first = requests.begin(generation: generation)
            // These are the production callback factory's actual retained closures.
            let firstCompletion = requests.completion(for: first, generation: { generation }, available: { unlocked }, receive: receive)
            var current = first
            switch name {
            case "superseded-success", "superseded-cancellation", "superseded-error":
                requests.invalidate(); generation = UUID()
                current = requests.begin(generation: generation)
            case "inactive": requests.scenePhase = .inactive
            case "background": requests.scenePhase = .background; requests.invalidate(); generation = UUID()
            case "locked": unlocked = false
            case "generation-change": generation = UUID()
            case "duplicate": break
            default: XCTFail("Unknown indexed completion case: " + name)
            }
            let oldResult: Result<URL, Error> = name == "superseded-cancellation" ? .failure(CancellationError())
                : name == "superseded-error" ? .failure(POSIXError(.EIO)) : .success(file)
            firstCompletion(oldResult)
            let expected = try XCTUnwrap(row["firstReceipts"] as? Int)
            XCTAssertEqual(receipts, expected, name)
            XCTAssertEqual(reads, importing ? expected : 0, name)
            XCTAssertEqual(errors, 0, "An old failure cannot replace a newer issue: " + name)
            if !importing { XCTAssertEqual(exportDraft, expected == 0 ? Data(contents.utf8) : nil, name) }
            if name.hasPrefix("superseded") { XCTAssertEqual(requests.current, current, "A cannot consume B: " + name) }
            requests.scenePhase = .active; unlocked = true
            firstCompletion(.success(file)); firstCompletion(.failure(POSIXError(.EIO)))
            XCTAssertEqual(receipts, expected, "Retired or denied callbacks cannot replay: " + name)
            XCTAssertEqual(errors, 0, name)
            exportDraft = Data(contents.utf8)
            let fresh = name.hasPrefix("superseded") ? current : requests.begin(generation: generation)
            let freshCompletion = requests.completion(for: fresh, generation: { generation }, available: { unlocked }, receive: receive)
            freshCompletion(.success(file)); freshCompletion(.failure(CancellationError()))
            XCTAssertEqual(receipts, expected + 1, "Fresh B completes exactly once: " + name)
            XCTAssertEqual(reads, importing ? expected + 1 : 0, name)
            XCTAssertEqual(errors, 0, name); XCTAssertNil(requests.current, name)
            if !importing { XCTAssertNil(exportDraft, name) }
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
    func testServicePortDefaultsAndInvalidInputsUsePersistedRecords() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "native-visionos-client-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(fixture["servicePortDefaults"] as? [[String: Any]])
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        for row in cases {
            let id = try XCTUnwrap(row["id"] as? String)
            let storage = directory.appending(path: id + ".json")
            let library = DirectMacLibraryV1(url: storage, removeLogin: { _ in })
            XCTAssertTrue(library.save(id: nil, name: "Synthetic service ports", addresses: ["127.0.0.1"]))
            let current = try XCTUnwrap(library.macs.first), before = try Data(contentsOf: storage)
            let valid = try XCTUnwrap(row["valid"] as? Bool)
            XCTAssertEqual(VisionMacSaving.save(library: library, mac: current, name: "Synthetic service ports",
                addresses: "127.0.0.1", desktopPort: try XCTUnwrap(row["desktopInput"] as? String),
                sshPort: try XCTUnwrap(row["sshInput"] as? String)), valid, id)
            let persisted = try XCTUnwrap(DirectMacLibraryV1(url: storage, removeLogin: { _ in }).macs.first)
            if valid {
                XCTAssertEqual(persisted.port, try XCTUnwrap(row["desktopPort"] as? Int), id)
                XCTAssertEqual(persisted.sshPort, try XCTUnwrap(row["sshPort"] as? Int), id)
            } else {
                XCTAssertEqual(persisted, current, id)
                XCTAssertEqual(try Data(contentsOf: storage), before, id)
            }
        }
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

@MainActor private final class CancellationKey: UIKey {
    let usage: UIKeyboardHIDUsage
    let value: String
    let flags: UIKeyModifierFlags
    init(usage: UIKeyboardHIDUsage, text: String, flags: UIKeyModifierFlags) {
        self.usage = usage; value = text; self.flags = flags; super.init()
    }
    required init?(coder: NSCoder) { fatalError("Generated test keys are not decoded") }
    override var keyCode: UIKeyboardHIDUsage { usage }
    override var characters: String { value }
    override var charactersIgnoringModifiers: String { value }
    override var modifierFlags: UIKeyModifierFlags { flags }
}
private final class CancellationPress: UIPress {
    let sample: UIKey
    var sampledPhase: UIPress.Phase = .began
    init(_ key: UIKey) { sample = key; super.init() }
    override var key: UIKey? { sample }
    override var phase: UIPress.Phase { sampledPhase }
}
