import XCTest
import UIKit
import SwiftUI
@testable import MacCompanionVision

@MainActor final class VisionInteractionTests: XCTestCase {
    private func wait(_ label: String, _ predicate: () -> Bool) async throws {
        for _ in 0..<400 { if predicate() { return }; try await Task.sleep(for: .milliseconds(25)) }
        XCTFail(label); throw POSIXError(.ETIMEDOUT)
    }
    private func ownedWindow() throws -> (UIWindow, UIWindow?) {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first { $0.isKeyWindow }, window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController(); window.makeKeyAndVisible()
        return (window, previous)
    }
    func testNativeCanvasSamplingRenderedResponseAndLocalAdjustment() async throws {
        let server = DesktopSSHServer(.rfb); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic interaction Mac", addresses: ["127.0.0.1"], sshPort: server.port)
        let session = VisionDesktopSession(mac: mac)
        let (window, previous) = try ownedWindow()
        defer { session.close(); window.isHidden = true; previous?.makeKey(); try? TerminalSecretStore.remove(mac.id) }
        do {
            try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
            let canvas = VisionDesktopCanvas(session: session)
            canvas.frame = CGRect(x: 0, y: 0, width: 600, height: 300)
            window.rootViewController!.view.addSubview(canvas); canvas.layoutIfNeeded()
            session.connect(username: "synthetic", password: "synthetic-only", remember: false)
            try await wait("Owned desktop ready", { session.canInput && session.image != nil })
            let start = CGPoint(x: 300, y: 150)
            @MainActor func pixels() -> Data { session.image?.cgImage?.dataProvider?.data as Data? ?? Data() }
            let initial = pixels()
            canvas.selectionChanged(start: start, translation: .zero); canvas.selectionFinished(cancelled: false)
            try await wait("Input changes decoded pixels", { pixels() != initial })
            let primary = server.record.count("pointer-mask-1")
            var totals: [Int] = []
            for samples in [1, 20, 120] {
                let before = server.record.count("pointer-mask-8")
                canvas.selectionChanged(start: start, translation: .zero)
                for sample in 1...samples { canvas.selectionChanged(start: start, translation: CGPoint(x: 0, y: CGFloat(sample) * 60 / CGFloat(samples))) }
                canvas.selectionFinished(cancelled: false)
                try await wait("Five distance-based pulses", { server.record.count("pointer-mask-8") == before + 5 })
                totals.append(server.record.count("pointer-mask-8") - before)
            }
            XCTAssertEqual(totals, [5, 5, 5]); XCTAssertEqual(server.record.count("pointer-mask-1"), primary)
            canvas.selectionChanged(start: start, translation: .zero)
            try await wait("Hold opens actions", { canvas.interaction.contextTarget != nil })
            canvas.selectionFinished(cancelled: false); canvas.targetAction(.doubleClick)
            try await wait("Two explicit clicks", { server.record.count("pointer-mask-1") == primary + 2 })
            let clicks = server.record.pointerEvents().filter { $0.mask == 1 }
            XCTAssertEqual(clicks.suffix(2).map(\.x), [128, 128]); XCTAssertEqual(clicks.suffix(2).map(\.y), [64, 64])
            canvas.showActions(); canvas.frame.size.width = 500; canvas.layoutIfNeeded()
            canvas.targetAction(.right)
            XCTAssertNil(canvas.interaction.contextTarget); XCTAssertEqual(server.record.count("pointer-mask-4"), 0)
            canvas.setAdjusting(true)
            let beforeAdjustment = server.record.pointerEvents().count, frameSize = session.framebuffer
            canvas.adjustZoom(2, anchor: CGPoint(x: 250, y: 150))
            let anchor = canvas.remote(CGPoint(x: 250, y: 150))
            XCTAssertEqual(anchor, CGPoint(x: 128, y: 64))
            canvas.adjustPan(CGPoint(x: 10000, y: 0)); let boundary = session.pan.x
            canvas.adjustPan(CGPoint(x: -10, y: 0)); XCTAssertEqual(session.pan.x, boundary - 10)
            canvas.selectionChanged(start: CGPoint(x: 250, y: 150), translation: .zero)
            canvas.selectionChanged(start: CGPoint(x: 250, y: 150), translation: CGPoint(x: 0, y: 60))
            canvas.selectionFinished(cancelled: false)
            session.fit(); canvas.setAdjusting(false)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(server.record.pointerEvents().count, beforeAdjustment); XCTAssertEqual(session.framebuffer, frameSize)
            let beforePhysical = server.record.pointerEvents().count
            canvas.physicalSelection(start: CGPoint(x: 250, y: 150), translation: .zero)
            XCTAssertTrue(session.pointerHeld)
            canvas.spatialEnded()
            XCTAssertTrue(session.pointerHeld, "The hand observer cannot finish the physical recognizer's drag")
            canvas.physicalSelection(start: CGPoint(x: 250, y: 150), translation: CGPoint(x: 30, y: 0))
            canvas.selectionFinished(cancelled: true)
            XCTAssertFalse(session.pointerHeld)
            try await wait("Physical drag balanced", { server.record.pointerEvents().count >= beforePhysical + 3 && server.record.pointerEvents().last?.mask == 0 })
            let physicalEvents = Array(server.record.pointerEvents().dropFirst(beforePhysical))
            XCTAssertEqual(physicalEvents.first?.mask, 1); XCTAssertEqual(physicalEvents.first?.x, 128)
            XCTAssertEqual(physicalEvents.first?.y, 64); XCTAssertEqual(physicalEvents.last?.mask, 0)
            let ornament = UIWindow(windowScene: try XCTUnwrap(window.windowScene))
            ornament.rootViewController = UIViewController(); ornament.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertTrue(session.canInput, "A native ornament in the owned scene retains admission")
            XCTAssertTrue(canvas.becomeFirstResponder()); XCTAssertTrue(window.isKeyWindow)
            ornament.isHidden = true
            canvas.selectionChanged(start: CGPoint(x: 250, y: 150), translation: .zero)
            session.pause(); canvas.selectionFinished(cancelled: false)
            try await Task.sleep(for: .milliseconds(650))
            XCTAssertNil(canvas.interaction.contextTarget); XCTAssertFalse(session.pointerHeld)
            session.resume(); try await wait("Resume after pending hold", { session.image != nil })
            try await server.close()
        } catch { try? await server.close(); throw error }
    }
    func testToolbarActionsResolveVisibleTargetAfterDisplayAndViewChanges() async throws {
        let server = DesktopSSHServer(.rfb, nativeGestures: true); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic display Mac", addresses: ["127.0.0.1"], sshPort: server.port)
        let session = VisionDesktopSession(mac: mac), (window, previous) = try ownedWindow()
        defer { session.close(); window.isHidden = true; previous?.makeKey(); try? TerminalSecretStore.remove(mac.id) }
        do {
            try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
            let canvas = VisionDesktopCanvas(session: session); canvas.frame = CGRect(x: 0, y: 0, width: 600, height: 300)
            canvas.interaction.canvas = canvas
            window.rootViewController!.view.addSubview(canvas); canvas.layoutIfNeeded()
            session.connect(username: "synthetic", password: "synthetic-only", remember: false)
            try await wait("Two decoded displays ready", { session.canInput && session.image != nil && session.displays.count == 2 })
            session.pointer(CGPoint(x: 100, y: 100), mask: 0)
            session.selectDisplay(2)
            XCTAssertEqual(session.crop, CGRect(x: 128, y: 0, width: 128, height: 128))
            canvas.showActions()
            XCTAssertEqual(canvas.interaction.contextTarget?.local, CGPoint(x: 300, y: 150))
            canvas.targetAction(.right)
            try await wait("Click belongs to visible second display center", { server.record.pointerEvents().contains { $0.mask == 4 && $0.x == 192 && $0.y == 64 } })
            XCTAssertFalse(server.record.pointerEvents().contains { $0.mask == 4 && $0.x == 128 && $0.y == 100 })
            // Exercise the same dispatcher used by the configurable More menu.
            let rightClick = try XCTUnwrap(VNCQuickAction.defaults.first { $0.kind == .rightClick })
            session.selectDisplay(nil); session.pointer(CGPoint(x: 100, y: 100), mask: 0); session.selectDisplay(2)
            let beforeShortcut = server.record.count("pointer-mask-4")
            canvas.interaction.performQuickAction(rightClick)
            try await wait("More shortcut resolves current display target", { server.record.count("pointer-mask-4") == beforeShortcut + 1 })
            XCTAssertEqual(server.record.pointerEvents().last?.x, 192); XCTAssertEqual(server.record.pointerEvents().last?.y, 64)
            XCTAssertNil(canvas.interaction.contextTarget)
            // A cursor hidden by local zoom/pan also resolves to the visible center.
            session.selectDisplay(nil); session.pointer(CGPoint(x: 10, y: 10), mask: 0)
            canvas.setAdjusting(true); canvas.adjustZoom(2); canvas.adjustPan(CGPoint(x: 100, y: 0)); canvas.setAdjusting(false)
            let center = try XCTUnwrap(canvas.remote(CGPoint(x: 300, y: 150)))
            canvas.showActions(); XCTAssertEqual(canvas.interaction.contextTarget?.local, CGPoint(x: 300, y: 150))
            canvas.targetAction(.doubleClick)
            try await wait("Both clicks use visible adjusted target", { server.record.pointerEvents().filter { $0.mask == 1 }.count == 2 })
            let clicks = server.record.pointerEvents().filter { $0.mask == 1 }
            XCTAssertEqual(clicks.map(\.x), [Int(center.x), Int(center.x)]); XCTAssertEqual(clicks.map(\.y), [Int(center.y), Int(center.y)])
            session.pointer(CGPoint(x: 10, y: 10), mask: 0)
            let beforeAdjustedShortcut = server.record.count("pointer-mask-4")
            canvas.interaction.performQuickAction(rightClick)
            try await wait("More shortcut uses current visible adjusted target", { server.record.count("pointer-mask-4") == beforeAdjustedShortcut + 1 })
            XCTAssertEqual(server.record.pointerEvents().last?.x, Int(center.x)); XCTAssertEqual(server.record.pointerEvents().last?.y, Int(center.y))
            let beforeBypass = server.record.count("pointer-mask-4")
            session.quickAction(rightClick)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(server.record.count("pointer-mask-4"), beforeBypass, "Target-specific actions cannot bypass the canvas binding")
            try await server.close()
        } catch { try? await server.close(); throw error }
    }
    func testNativeScrollCoalescingPreservesDistanceAndRetiresOwner() async throws {
        let server = DesktopSSHServer(.rfb, nativeGestures: true); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic native scroll Mac", addresses: ["127.0.0.1"], sshPort: server.port)
        let session = VisionDesktopSession(mac: mac), (window, previous) = try ownedWindow()
        defer { session.close(); window.isHidden = true; previous?.makeKey(); try? TerminalSecretStore.remove(mac.id) }
        do {
            try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
            let canvas = VisionDesktopCanvas(session: session); canvas.frame = CGRect(x: 0, y: 0, width: 600, height: 300)
            window.rootViewController!.view.addSubview(canvas); canvas.layoutIfNeeded()
            session.connect(username: "synthetic", password: "synthetic-only", remember: false)
            try await wait("Native extension layout ready", { session.canInput && session.image != nil && session.displays.count == 2 })
            let point = CGPoint(x: 100, y: 64)
            for deltas in [[CGPoint(x: 3000, y: -1500)], [CGPoint](repeating: CGPoint(x: 1000, y: -500), count: 3),
                           [CGPoint(x: -3000, y: 0.125)], [CGPoint(x: 16384, y: 8192)]] {
                let before = server.record.scrollEvents().count
                for delta in deltas { session.scroll(point, dx: delta.x, dy: delta.y) }
                session.finishGesture()
                try await wait("Native gesture ends without disconnect", { server.record.scrollEvents().dropFirst(before).last?.phase == 4 })
                let events = Array(server.record.scrollEvents().dropFirst(before)), changes = events.filter { $0.phase == 2 }
                XCTAssertEqual(events.first?.phase, 1); XCTAssertEqual(events.filter { $0.phase == 1 }.count, 1)
                XCTAssertEqual(events.filter { $0.phase == 4 }.count, 1)
                XCTAssertTrue(events.allSatisfy { $0.x == 100 && $0.y == 64 })
                XCTAssertTrue(changes.allSatisfy { abs($0.dx) <= 2048 && abs($0.dy) <= 2048 })
                XCTAssertEqual(changes.reduce(0) { $0 + $1.dx }, deltas.reduce(0) { $0 + Double($1.x) })
                XCTAssertEqual(changes.reduce(0) { $0 + $1.dy }, deltas.reduce(0) { $0 + Double($1.y) })
                XCTAssertTrue(session.canInput)
            }
            XCTAssertTrue(server.record.pointerEvents().isEmpty, "Negotiated native updates must not fall back to wheel clicks")
            session.scroll(point, dx: 3000, dy: 0); session.pause()
            try await wait("Pause releases admitted native gesture", { server.record.scrollEvents().last?.phase == 4 })
            let retired = server.record.scrollEvents().count
            session.scroll(point, dx: 1000, dy: 0); session.finishGesture()
            try await Task.sleep(for: .milliseconds(100)); XCTAssertEqual(server.record.scrollEvents().count, retired)
            session.resume(); try await wait("Fresh frame on resume", { session.image != nil && session.canInput })
            session.scroll(point, dx: 0, dy: 0); session.finishGesture()
            try await Task.sleep(for: .milliseconds(100)); XCTAssertEqual(server.record.scrollEvents().count, retired)
            session.scroll(point, dx: 1, dy: 0); session.finishGesture()
            try await wait("Only new movement follows resume", { server.record.scrollEvents().count == retired + 3 })
            XCTAssertEqual(server.record.scrollEvents().last?.phase, 4)
            try await server.close()
        } catch { try? await server.close(); throw error }
    }
    func testPhysicalWheelRetiresOutsideContentBeforeTheNextGesture() async throws {
        struct Corpus: Decodable { let physicalWheelBoundaries: [Boundary] }
        struct Boundary: Decodable {
            let name: String; let state: String; let viewport: [Double]
            let begin: [Double]; let finish: [Double]; let next: [Double]
            let initialDelta: [Double]; let nextDelta: [Double]
            let nativeBeginTargets: [[Double]]; let fallbackPulses: Int
            let preservesHeldPointer: Bool
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "native-visionos-client-v1", withExtension: "json"))
        let rows = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url)).physicalWheelBoundaries
        XCTAssertEqual(rows.count, 3)
        for native in [false, true] {
            let server = DesktopSSHServer(.rfb, nativeGestures: native); try await server.start()
            let mac = try DirectMacRecordV1.normalized(name: "Synthetic wheel Mac", addresses: ["127.0.0.1"], sshPort: server.port)
            let session = VisionDesktopSession(mac: mac), (window, previous) = try ownedWindow()
            do {
                try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
                let canvas = VisionDesktopCanvas(session: session)
                window.rootViewController!.view.addSubview(canvas)
                session.connect(username: "synthetic", password: "synthetic-only", remember: false)
                try await wait("Wheel peer ready", { session.canInput && session.image != nil })
                let recognizer = WheelSampleRecognizer()
                let selector = NSSelectorFromString("wheel:")
                XCTAssertTrue(canvas.responds(to: selector), "Invoke the actual UIKit wheel target, not a separate test controller")
                for row in rows {
                    canvas.frame.size = CGSize(width: row.viewport[0], height: row.viewport[1]); canvas.layoutIfNeeded()
                    @MainActor func dispatch(_ state: UIGestureRecognizer.State, _ point: [Double], _ delta: [Double]) {
                        recognizer.sampledState = state
                        recognizer.sampledLocation = CGPoint(x: point[0], y: point[1])
                        recognizer.sampledTranslation = CGPoint(x: delta[0], y: delta[1])
                        canvas.perform(selector, with: recognizer)
                        XCTAssertEqual(recognizer.sampledTranslation, .zero, "Every sample is consumed, including an unmapped endpoint")
                    }
                    let beforeNative = server.record.scrollEvents().count
                    let beforeFallback = server.record.count("pointer-mask-8")
                    dispatch(.began, row.begin, row.initialDelta)
                    let terminal: UIGestureRecognizer.State = row.state == "ended" ? .ended : row.state == "cancelled" ? .cancelled : .failed
                    dispatch(terminal, row.finish, [0, 50])
                    dispatch(.began, row.next, row.nextDelta); dispatch(.ended, row.next, [0, 0])
                    if native {
                        try await wait(row.name + " closes both native gestures", { server.record.scrollEvents().count == beforeNative + 6 })
                        let events = Array(server.record.scrollEvents().dropFirst(beforeNative))
                        XCTAssertEqual(events.map(\.phase), [1, 2, 4, 1, 2, 4])
                        let begins = events.filter { $0.phase == 1 }
                        XCTAssertEqual(begins.map { [$0.x, $0.y] }, row.nativeBeginTargets.map { $0.map(Int.init) })
                        XCTAssertEqual(events.filter { $0.phase == 2 }.map(\.dy), [row.initialDelta[1], row.nextDelta[1]])
                    } else {
                        try await Task.sleep(for: .milliseconds(100))
                        XCTAssertEqual(server.record.count("pointer-mask-8") - beforeFallback, row.fallbackPulses,
                            "Five points from the retired gesture cannot combine with seven new points")
                        XCTAssertTrue(server.record.scrollEvents().isEmpty)
                    }
                    XCTAssertTrue(session.canInput)
                    let beforeDrag = server.record.pointerEvents().count
                    canvas.physicalSelection(start: CGPoint(x: row.begin[0], y: row.begin[1]), translation: .zero)
                    XCTAssertTrue(session.pointerHeld)
                    dispatch(terminal, row.finish, [0, 0])
                    XCTAssertEqual(session.pointerHeld, row.preservesHeldPointer, "A late wheel completion cannot finish another recognizer's drag")
                    canvas.selectionFinished(cancelled: true)
                    XCTAssertFalse(session.pointerHeld)
                    try await wait("Physical owner finishes its own drag", { server.record.pointerEvents().count >= beforeDrag + 2 && server.record.pointerEvents().last?.mask == 0 })
                }
                session.close(); window.isHidden = true; previous?.makeKey(); try? TerminalSecretStore.remove(mac.id)
                try await server.close()
            } catch {
                session.close(); window.isHidden = true; previous?.makeKey(); try? TerminalSecretStore.remove(mac.id)
                try? await server.close(); throw error
            }
        }
    }

    func testPhysicalWheelRejectsRetiredSequenceUntilANewBegin() async throws {
        struct Corpus: Decodable { let physicalWheelLifecycle: [Row] }
        struct Row: Decodable {
            let name: String; let transition: String; let viewport: [Double]
            let begin: [Double]; let initialDelta: [Double]; let staleDelta: [Double]
            let next: [Double]; let nextDelta: [Double]; let nextContinuation: [Double]
            let nextTarget: [Int]; let freshFallbackPulses: Int
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "native-visionos-client-v1", withExtension: "json"))
        let rows = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url)).physicalWheelLifecycle
        XCTAssertEqual(rows.count, 7)
        for native in [false, true] {
            let server = DesktopSSHServer(.rfb, nativeGestures: native); try await server.start()
            let mac = try DirectMacRecordV1.normalized(name: "Synthetic wheel lifecycle", addresses: ["127.0.0.1"], sshPort: server.port)
            let session = VisionDesktopSession(mac: mac), (window, previous) = try ownedWindow()
            do {
                try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
                let canvas = VisionDesktopCanvas(session: session)
                window.rootViewController!.view.addSubview(canvas)
                session.connect(username: "synthetic", password: "synthetic-only", remember: false)
                try await wait("Lifecycle peer ready", { session.canInput && session.image != nil && (!native || session.displays.count == 2) })
                let recognizer = WheelSampleRecognizer(), selector = NSSelectorFromString("wheel:")
                XCTAssertTrue(canvas.responds(to: selector))
                @MainActor func dispatch(_ state: UIGestureRecognizer.State, _ point: [Double], _ delta: [Double]) {
                    recognizer.sampledState = state
                    recognizer.sampledLocation = CGPoint(x: point[0], y: point[1])
                    recognizer.sampledTranslation = CGPoint(x: delta[0], y: delta[1])
                    canvas.perform(selector, with: recognizer)
                    XCTAssertEqual(recognizer.sampledTranslation, .zero)
                }
                for row in rows {
                    canvas.setAdjusting(false); session.selectDisplay(nil)
                    canvas.frame.size = CGSize(width: row.viewport[0], height: row.viewport[1]); canvas.layoutIfNeeded()
                    let before = server.record.scrollEvents().count
                    dispatch(.began, row.begin, row.initialDelta)
                    if native { try await wait("Initial wheel admitted", { server.record.scrollEvents().count == before + 2 }) }
                    switch row.transition {
                    case "owner-release": session.releaseInput()
                    case "display": session.selectDisplay(native ? 2 : nil)
                    case "resize": canvas.frame.size.width = 640; canvas.layoutIfNeeded()
                    case "pause-resume":
                        session.pause(); session.resume()
                        try await wait("Wheel owner resumes", { session.canInput && session.image != nil })
                    case "adjustment": canvas.setAdjusting(true); canvas.setAdjusting(false)
                    case "view-change": canvas.adjustZoom(2)
                    case "hand-handoff":
                        let start = CGPoint(x: row.begin[0], y: row.begin[1])
                        canvas.selectionChanged(start: start, translation: .zero)
                        canvas.selectionChanged(start: start, translation: CGPoint(x: 0, y: 24))
                        if native { try await wait("Hand owns new scroll", { server.record.scrollEvents().count >= before + 5 }) }
                    default: XCTFail("Unknown indexed wheel transition")
                    }
                    try await Task.sleep(for: .milliseconds(100))
                    let updates = server.record.scrollEvents().filter { $0.phase != 4 }.count
                    let ends = server.record.scrollEvents().filter { $0.phase == 4 }.count
                    let pulses = server.record.count("pointer-mask-8")
                    dispatch(.changed, row.begin, row.staleDelta)
                    dispatch(.ended, row.begin, row.staleDelta)
                    try await Task.sleep(for: .milliseconds(100))
                    XCTAssertEqual(server.record.scrollEvents().filter { $0.phase != 4 }.count, updates, row.name)
                    XCTAssertEqual(server.record.count("pointer-mask-8"), pulses, row.name)
                    if row.transition == "hand-handoff" {
                        XCTAssertEqual(server.record.scrollEvents().filter { $0.phase == 4 }.count, ends, "Late wheel completion cannot end the hand scroll")
                        canvas.selectionFinished(cancelled: true)
                    }
                    try await Task.sleep(for: .milliseconds(100))
                    let freshNative = server.record.scrollEvents().count, freshFallback = server.record.count("pointer-mask-8")
                    dispatch(.began, row.next, row.nextDelta)
                    dispatch(.changed, row.next, row.nextContinuation); dispatch(.ended, row.next, [0, 0])
                    if native {
                        try await wait("Fresh wheel complete", { server.record.scrollEvents().count == freshNative + 4 })
                        let events = Array(server.record.scrollEvents().dropFirst(freshNative))
                        XCTAssertEqual(events.map(\.phase), [1, 2, 2, 4])
                        XCTAssertEqual([events[0].x, events[0].y], row.nextTarget)
                    } else {
                        try await wait("Fresh fallback begins without carried remainder", { server.record.count("pointer-mask-8") == freshFallback + row.freshFallbackPulses })
                    }
                    XCTAssertTrue(session.canInput)
                }
                session.close(); window.isHidden = true; previous?.makeKey(); try? TerminalSecretStore.remove(mac.id)
                try await server.close()
            } catch {
                session.close(); window.isHidden = true; previous?.makeKey(); try? TerminalSecretStore.remove(mac.id)
                try? await server.close(); throw error
            }
        }
    }
    func testRetiredPhysicalDragCannotCompleteANewerHandDrag() async throws {
        struct Corpus: Decodable { let physicalSelectionRetirement: [Row] }
        struct Row: Decodable {
            let state: String; let transition: String; let viewport: [Double]; let pointerStart: [Double]
            let handStart: [Double]; let handTranslation: [Double]
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "native-visionos-client-v1", withExtension: "json"))
        let rows = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url)).physicalSelectionRetirement
        XCTAssertEqual(rows.count, 9)
        let server = DesktopSSHServer(.rfb); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic pointer retirement", addresses: ["127.0.0.1"], sshPort: server.port)
        let session = VisionDesktopSession(mac: mac), (window, previous) = try ownedWindow()
        defer { session.close(); window.isHidden = true; previous?.makeKey(); try? TerminalSecretStore.remove(mac.id) }
        do {
            try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
            let canvas = VisionDesktopCanvas(session: session)
            canvas.interaction.canvas = canvas
            window.rootViewController!.view.addSubview(canvas)
            session.connect(username: "synthetic", password: "synthetic-only", remember: false)
            try await wait("Pointer peer ready", { session.canInput && session.image != nil })
            let recognizer = WheelSampleRecognizer(), selector = NSSelectorFromString("physicalDrag:")
            XCTAssertTrue(canvas.responds(to: selector))
            for row in rows {
                canvas.setAdjusting(false); session.releaseInput()
                canvas.frame.size = CGSize(width: row.viewport[0], height: row.viewport[1]); canvas.layoutIfNeeded()
                let before = server.record.count("pointer-mask-1")
                recognizer.sampledState = .began
                recognizer.sampledLocation = CGPoint(x: row.pointerStart[0], y: row.pointerStart[1])
                recognizer.sampledTranslation = .zero
                recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
                let touch = PointerSampleTouch(); touch.sampledLocation = recognizer.sampledLocation
                XCTAssertTrue(canvas.gestureRecognizer(recognizer, shouldReceive: touch))
                canvas.perform(selector, with: recognizer)
                XCTAssertTrue(session.pointerHeld)
                try await wait("Physical drag admitted", { server.record.count("pointer-mask-1") >= before + 1 })
                switch row.transition {
                case "owner-release": session.releaseInput()
                case "adjustment": canvas.setAdjusting(true); canvas.setAdjusting(false)
                case "keyboard": canvas.interaction.requestKeyboard()
                default: XCTFail("Unknown indexed physical selection retirement")
                }
                XCTAssertFalse(session.pointerHeld)
                try await wait("Retired pointer released", { server.record.pointerEvents().last?.mask == 0 })
                let beforeHand = server.record.count("pointer-mask-1")
                canvas.showActions(); canvas.targetAction(.armDrag)
                let start = CGPoint(x: row.handStart[0], y: row.handStart[1])
                canvas.selectionChanged(start: start, translation: .zero)
                canvas.selectionChanged(start: start, translation: CGPoint(x: row.handTranslation[0], y: row.handTranslation[1]))
                XCTAssertTrue(session.pointerHeld)
                try await wait("New hand drag admitted", { server.record.count("pointer-mask-1") > beforeHand && server.record.pointerEvents().last?.mask == 1 })
                try await Task.sleep(for: .milliseconds(100))
                let events = server.record.pointerEvents().count
                recognizer.sampledState = row.state == "ended" ? .ended : row.state == "cancelled" ? .cancelled : .failed
                canvas.perform(selector, with: recognizer)
                XCTAssertTrue(session.pointerHeld, "Retired " + row.state + " cannot release the new hand drag")
                try await Task.sleep(for: .milliseconds(50))
                XCTAssertEqual(server.record.pointerEvents().count, events, row.state)
                canvas.selectionFinished(cancelled: true)
                XCTAssertFalse(session.pointerHeld)
                try await wait("Hand recognizer completes its own drag", { server.record.pointerEvents().last?.mask == 0 })
            }
            try await server.close()
        } catch { try? await server.close(); throw error }
    }
    func testPhysicalPressRetirementRejectsStaleEndpointsThenAcceptsFreshTouch() async throws {
        struct Corpus: Decodable { let physicalPressRetirement: [Row] }
        struct Row: Decodable {
            let name: String; let source: String; let buttonMask: Int; let transition: String
            let viewport: [Double]; let start: [Double]; let staleEndpoint: [Double]
            let staleState: String; let freshTarget: [Int]; let staleEvents: Int; let freshMasks: [Int]
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "native-visionos-client-v1", withExtension: "json"))
        let rows = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url)).physicalPressRetirement
        XCTAssertEqual(rows.count, 42)
        let server = DesktopSSHServer(.rfb, nativeGestures: true); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic physical press retirement", addresses: ["127.0.0.1"], sshPort: server.port)
        let session = VisionDesktopSession(mac: mac), (window, previous) = try ownedWindow()
        defer { session.close(); window.isHidden = true; previous?.makeKey(); try? TerminalSecretStore.remove(mac.id) }
        do {
            try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
            let canvas = VisionDesktopCanvas(session: session); canvas.interaction.canvas = canvas
            window.rootViewController!.view.addSubview(canvas)
            session.connect(username: "synthetic", password: "synthetic-only", remember: false)
            try await wait("Press peer ready", { session.canInput && session.image != nil && session.displays.count == 2 })
            for row in rows {
                canvas.setAdjusting(false); session.selectDisplay(nil); canvas.interaction.dismissKeyboard()
                canvas.frame.size = CGSize(width: row.viewport[0], height: row.viewport[1]); canvas.layoutIfNeeded()
                let recognizer: UIGestureRecognizer = row.source == "drag" ? WheelSampleRecognizer() : TapSampleRecognizer()
                recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
                if let tap = recognizer as? UITapGestureRecognizer { tap.buttonMaskRequired = row.buttonMask == 4 ? .secondary : .primary }
                let selector = NSSelectorFromString(row.source == "drag" ? "physicalDrag:" : row.source == "primary" ? "primary:" : "secondary:")
                XCTAssertTrue(canvas.responds(to: selector))
                @MainActor func sample(_ state: UIGestureRecognizer.State, _ point: CGPoint) {
                    if let tap = recognizer as? TapSampleRecognizer { tap.sampledState = state; tap.sampledLocation = point }
                    if let drag = recognizer as? WheelSampleRecognizer {
                        drag.sampledState = state; drag.sampledLocation = point; drag.sampledTranslation = .zero
                    }
                }
                @MainActor func admit(_ point: CGPoint) {
                    sample(.possible, point)
                    let event = PointerSampleEvent(); event.sampledMask = row.buttonMask == 4 ? .secondary : .primary
                    XCTAssertTrue(canvas.gestureRecognizer(recognizer, shouldReceive: event), row.name)
                    let touch = PointerSampleTouch(); touch.sampledLocation = point
                    let delegate: any UIGestureRecognizerDelegate = canvas
                    XCTAssertTrue(delegate.gestureRecognizer?(recognizer, shouldReceive: touch) ?? true, row.name)
                }
                let start = CGPoint(x: row.start[0], y: row.start[1])
                if row.transition != "no-admission" { admit(start) }
                switch row.transition {
                case "owner-release": session.releaseInput()
                case "resize": canvas.frame.size.width = 640; canvas.layoutIfNeeded()
                case "display": session.selectDisplay(2)
                case "adjustment-active": canvas.setAdjusting(true)
                case "adjustment-exit": canvas.setAdjusting(true); canvas.setAdjusting(false)
                case "view-change": canvas.adjustZoom(2)
                case "view-roundtrip": canvas.adjustZoom(2); canvas.adjustZoom(0.5)
                case "fit": session.fit()
                case "keyboard": canvas.interaction.requestKeyboard()
                case "cancel-selection": canvas.cancelSelection()
                case "hand-handoff":
                    canvas.showActions(); canvas.targetAction(.armDrag)
                    canvas.selectionChanged(start: start, translation: .zero)
                    canvas.selectionChanged(start: start, translation: CGPoint(x: 24, y: 0))
                    XCTAssertTrue(session.pointerHeld)
                    try await wait("Hand owns held input", { server.record.pointerEvents().last?.mask == 1 })
                case "pause-resume":
                    session.pause(); session.resume()
                    try await wait("Press owner resumes", { session.canInput && session.image != nil })
                case "cancelled", "failed", "no-admission": break
                default: XCTFail("Unknown indexed press transition")
                }
                try await Task.sleep(for: .milliseconds(100))
                let before = server.record.pointerEvents().count
                let terminal: UIGestureRecognizer.State = row.staleState == "began" ? .began : row.staleState == "cancelled" ? .cancelled : row.staleState == "failed" ? .failed : .ended
                sample(terminal, CGPoint(x: row.staleEndpoint[0], y: row.staleEndpoint[1])); canvas.perform(selector, with: recognizer)
                // A consumed cancellation/failure cannot later become a click.
                if row.transition == "cancelled" || row.transition == "failed" { sample(.ended, start); canvas.perform(selector, with: recognizer) }
                try await Task.sleep(for: .milliseconds(50))
                XCTAssertEqual(server.record.pointerEvents().count - before, row.staleEvents, row.name)
                if row.transition == "hand-handoff" {
                    XCTAssertTrue(session.pointerHeld, row.name); canvas.selectionFinished(cancelled: true)
                }
                canvas.cancelSelection(); canvas.setAdjusting(false); canvas.interaction.dismissKeyboard()
                try await Task.sleep(for: .milliseconds(100))
                let freshBefore = server.record.pointerEvents().count
                let fresh = CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY)
                admit(fresh); sample(row.source == "drag" ? .began : .ended, fresh); canvas.perform(selector, with: recognizer)
                if row.source == "drag" {
                    XCTAssertTrue(session.pointerHeld, row.name)
                    sample(.ended, fresh); canvas.perform(selector, with: recognizer); XCTAssertFalse(session.pointerHeld)
                }
                try await wait("Fresh press completes", { server.record.pointerEvents().count >= freshBefore + 2 && server.record.pointerEvents().last?.mask == 0 })
                let events = Array(server.record.pointerEvents().dropFirst(freshBefore))
                var transitions: [Int] = []
                for event in events where transitions.last != event.mask { transitions.append(event.mask) }
                XCTAssertEqual(transitions, row.freshMasks, row.name)
                XCTAssertEqual([events[0].x, events[0].y], row.freshTarget, row.name)
            }
            try await server.close()
        } catch { try? await server.close(); throw error }
    }
    func testHandPanReversesImmediatelyAfterEdgeOvershoot() async throws {
        struct Corpus: Decodable { let handPanBoundaries: [Row] }
        struct Row: Decodable {
            let name: String; let crop: [Double]; let viewport: [Double]; let zoom: Double; let pan: [Double]
            let translations: [[Double]]; let expectedPan: [[Double]]; let cancelled: Bool
            let restartTranslation: [Double]; let restartPan: [Double]
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "native-visionos-client-v1", withExtension: "json"))
        let rows = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url)).handPanBoundaries
        XCTAssertEqual(rows.count, 7)
        let server = DesktopSSHServer(.rfb, nativeGestures: true); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic hand pan boundaries", addresses: ["127.0.0.1"], sshPort: server.port)
        let session = VisionDesktopSession(mac: mac), (window, previous) = try ownedWindow()
        defer { session.close(); window.isHidden = true; previous?.makeKey(); try? TerminalSecretStore.remove(mac.id) }
        do {
            try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
            let canvas = VisionDesktopCanvas(session: session)
            window.rootViewController!.view.addSubview(canvas)
            session.connect(username: "synthetic", password: "synthetic-only", remember: false)
            try await wait("Hand pan peer ready", { session.canInput && session.image != nil && session.displays.count == 2 })
            for row in rows {
                canvas.setAdjusting(false); session.selectDisplay(nil)
                canvas.frame.size = CGSize(width: row.viewport[0], height: row.viewport[1]); canvas.layoutIfNeeded()
                XCTAssertEqual(session.crop, CGRect(x: row.crop[0], y: row.crop[1], width: row.crop[2], height: row.crop[3]))
                session.zoom = row.zoom; session.pan = CGPoint(x: row.pan[0], y: row.pan[1])
                canvas.setAdjusting(true)
                let start = CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY)
                canvas.selectionChanged(start: start, translation: .zero)
                for (travel, expected) in zip(row.translations, row.expectedPan) {
                    canvas.selectionChanged(start: start, translation: CGPoint(x: travel[0], y: travel[1]))
                    XCTAssertEqual(session.pan, CGPoint(x: expected[0], y: expected[1]), row.name)
                }
                canvas.selectionFinished(cancelled: row.cancelled)
                // Completion/cancellation keeps the bounded local position;
                // the next hand selection starts its own displacement baseline.
                canvas.selectionChanged(start: start, translation: .zero)
                canvas.selectionChanged(start: start, translation: CGPoint(x: row.restartTranslation[0], y: row.restartTranslation[1]))
                XCTAssertEqual(session.pan, CGPoint(x: row.restartPan[0], y: row.restartPan[1]), row.name)
                canvas.selectionFinished(cancelled: false); canvas.setAdjusting(false)
            }
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(server.record.pointerEvents().isEmpty, "Hand view adjustment must send no remote pointer or wheel input")
            XCTAssertTrue(server.record.scrollEvents().isEmpty, "Hand view adjustment must send no native scrolling")
            XCTAssertEqual(server.record.count("keyDown"), 0); XCTAssertEqual(server.record.count("keyUp"), 0)
            try await server.close()
        } catch { try? await server.close(); throw error }
    }
    func testMagnificationKeepsInitialAnchorAndRejectsRetiredCallbacks() async throws {
        struct Corpus: Decodable { let magnificationLifecycle: [Row] }
        struct Row: Decodable {
            let name: String; let transition: String; let viewport: [Double]
            let anchor: [Double]; let movedCentroids: [[Double]]; let factors: [Double]
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "native-visionos-client-v1", withExtension: "json"))
        let rows = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url)).magnificationLifecycle
        XCTAssertEqual(rows.count, 9)
        let server = DesktopSSHServer(.rfb, nativeGestures: true); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic magnification lifecycle", addresses: ["127.0.0.1"], sshPort: server.port)
        let session = VisionDesktopSession(mac: mac), (window, previous) = try ownedWindow()
        defer { session.close(); window.isHidden = true; previous?.makeKey(); try? TerminalSecretStore.remove(mac.id) }
        do {
            try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
            let canvas = VisionDesktopCanvas(session: session)
            window.rootViewController!.view.addSubview(canvas)
            session.connect(username: "synthetic", password: "synthetic-only", remember: false)
            try await wait("Magnification peer ready", { session.canInput && session.image != nil && session.displays.count == 2 })
            let recognizer = PinchSampleRecognizer(), selector = NSSelectorFromString("zoom:")
            XCTAssertTrue(canvas.responds(to: selector))
            @MainActor func dispatch(_ state: UIGestureRecognizer.State, _ location: CGPoint, _ scale: CGFloat) {
                recognizer.sampledState = state; recognizer.sampledLocation = location; recognizer.scale = scale
                canvas.perform(selector, with: recognizer)
                XCTAssertEqual(recognizer.scale, 1)
            }
            for row in rows {
                canvas.setAdjusting(false); session.selectDisplay(nil)
                canvas.frame.size = CGSize(width: row.viewport[0], height: row.viewport[1]); canvas.layoutIfNeeded()
                canvas.setAdjusting(true)
                try await Task.sleep(for: .milliseconds(100))
                let beforeGesture = server.record.pointerEvents().count
                let anchor = CGPoint(x: row.anchor[0], y: row.anchor[1]), target = try XCTUnwrap(canvas.remote(anchor))
                dispatch(.began, anchor, 1)
                for (centroid, factor) in zip(row.movedCentroids, row.factors) {
                    dispatch(.changed, CGPoint(x: centroid[0], y: centroid[1]), factor)
                    let rect = VisionDesktopGeometry.destination(crop: session.crop, viewport: canvas.bounds.size, zoom: session.zoom, pan: session.pan)
                    XCTAssertEqual(rect.minX + (target.x - session.crop.minX) / session.crop.width * rect.width, anchor.x, accuracy: 0.001, row.name)
                    XCTAssertEqual(rect.minY + (target.y - session.crop.minY) / session.crop.height * rect.height, anchor.y, accuracy: 0.001, row.name)
                }
                try await Task.sleep(for: .milliseconds(50))
                XCTAssertEqual(server.record.pointerEvents().count, beforeGesture, "Magnification itself sends no remote input")
                switch row.transition {
                case "ended": dispatch(.ended, anchor, 1)
                case "cancelled", "failed":
                    let zoom = session.zoom, pan = session.pan
                    dispatch(row.transition == "cancelled" ? .cancelled : .failed, anchor, 2)
                    XCTAssertEqual(session.zoom, zoom); XCTAssertEqual(session.pan, pan)
                case "owner-release": session.releaseInput()
                case "resize": canvas.frame.size.width = 640; canvas.layoutIfNeeded()
                case "display": session.selectDisplay(2)
                case "pause-resume":
                    session.pause(); session.resume()
                    try await wait("Magnification owner resumes", { session.canInput && session.image != nil })
                case "adjustment-exit": canvas.setAdjusting(false); canvas.setAdjusting(true)
                case "view-change": canvas.adjustPan(CGPoint(x: 10, y: 0))
                default: XCTFail("Unknown indexed magnification transition")
                }
                // Owner pause may send a balanced zero-mask cleanup. Settle that
                // transition separately from late and newly begun local zoom.
                try await Task.sleep(for: .milliseconds(100))
                let afterRetirement = server.record.pointerEvents().count
                let zoom = session.zoom, pan = session.pan
                dispatch(.changed, anchor, 2); dispatch(.ended, anchor, 2)
                XCTAssertEqual(session.zoom, zoom, row.name); XCTAssertEqual(session.pan, pan, row.name)
                session.fit()
                let freshAnchor = CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY)
                let freshTarget = try XCTUnwrap(canvas.remote(freshAnchor))
                dispatch(.began, freshAnchor, 1)
                dispatch(.changed, CGPoint(x: freshAnchor.x + 30, y: freshAnchor.y + 10), 1.25)
                XCTAssertEqual(session.zoom, 1.25, row.name)
                let rect = VisionDesktopGeometry.destination(crop: session.crop, viewport: canvas.bounds.size, zoom: session.zoom, pan: session.pan)
                XCTAssertEqual(rect.minX + (freshTarget.x - session.crop.minX) / session.crop.width * rect.width, freshAnchor.x, accuracy: 0.001)
                dispatch(.ended, freshAnchor, 1)
                try await Task.sleep(for: .milliseconds(50))
                XCTAssertEqual(server.record.pointerEvents().count, afterRetirement, "Retired and fresh zoom callbacks send no remote input")
            }
            XCTAssertTrue(server.record.pointerEvents().allSatisfy { $0.mask == 0 }, "Only owner-retirement cleanup is allowed between local gestures")
            try await server.close()
        } catch { try? await server.close(); throw error }
    }
    func testQuickActionSettingsPreserveStoredEntriesAndFilterEveryPresentation() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "native-visionos-client-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(fixture["quickActionPresentation"] as? [[String: Any]])
        for row in cases {
            let mode = try XCTUnwrap(DirectControlMode(rawValue: row["mode"] as! String))
            let stored = (row["storedKinds"] as! [String]).map { kind in
                VNCQuickAction(title: "Stored " + kind, kind: VNCQuickAction.Kind(rawValue: kind)!,
                    enabled: !(row["disabledKinds"] as? [String] ?? []).contains(kind), key: kind == "shortcut" ? 0x63 : 0)
            }
            let id = UUID(); defer { VNCSessionPreferences.clear(id) }
            try VNCSessionPreferences.saveActions(stored, mac: id)
            let loaded = try VNCSessionPreferences.readActions(id)
            let presented = VisionQuickActionPresentation.presented(loaded, mode: mode)
            XCTAssertEqual(presented.map { $0.kind.rawValue }, row["presentedKinds"] as? [String])
            XCTAssertEqual(VisionQuickActionPresentation.standards(mode).map { $0.kind.rawValue }, row["standardKinds"] as? [String])
            let restored = VisionQuickActionPresentation.restored(loaded, mode: mode)
            XCTAssertEqual(restored.map { $0.kind.rawValue }, row["restoredKinds"] as? [String])
            XCTAssertTrue(DirectQuickActionEditing.valid(restored, mode: mode))
            XCTAssertEqual(restored.filter { !VisionQuickActionPresentation.supported($0, mode: mode) },
                loaded.filter { !VisionQuickActionPresentation.supported($0, mode: mode) })
            XCTAssertEqual(try VNCSessionPreferences.readActions(id), stored, "Presentation cannot mutate stored profiles")
            if let first = presented.first, let index = loaded.firstIndex(where: { $0.id == first.id }) {
                var edited = loaded; edited[index].enabled = false
                try VNCSessionPreferences.saveActions(edited, mac: id)
                XCTAssertEqual(try VNCSessionPreferences.readActions(id).filter { !VisionQuickActionPresentation.supported($0, mode: mode) },
                    stored.filter { !VisionQuickActionPresentation.supported($0, mode: mode) })
                XCTAssertFalse(VisionQuickActionPresentation.presented(edited, mode: mode).filter(\.enabled).contains { $0.id == first.id })
            }
        }
        XCTAssertFalse(VisionQuickActionPresentation.presented(DirectControlMode.desktop.defaults, mode: .desktop).contains { $0.kind == .mode })
        XCTAssertEqual(DirectQuickActionEditing.standards(.desktop).filter { $0.kind == .mode }.count, 1, "Shared platform catalogue remains unchanged")
        XCTAssertTrue(VNCQuickAction(title: "Copy Text", kind: .copyText).compatible(with: .desktop), "Shared profile compatibility remains unchanged")
    }
    func testRegistryReusesDiscoveryAndRetainsIndependentOwners() throws {
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic registry Mac", address: "127.0.0.1")
        let registry = VisionSessionRegistry(), first = VisionSessionRequest(mac: mac, connection: .desktop)
        let second = VisionSessionRequest(mac: mac, connection: .desktop), terminal = VisionSessionRequest(mac: mac, connection: .terminal)
        registry.add(first); registry.add(first); registry.add(second); registry.add(terminal)
        XCTAssertEqual(registry.requests.count, 3); XCTAssertEqual(registry.existing(mac: mac.id, connection: .desktop), first)
        registry.remove(first.id); XCTAssertEqual(registry.existing(mac: mac.id, connection: .desktop), second)
        XCTAssertEqual(registry.existing(mac: mac.id, connection: .terminal), terminal)
    }
    func testNativeTerminalControlsApplicationCursorPasteAndFocusAdmission() async throws {
        let server = SSHTestServer(); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Terminal Mac", addresses: ["127.0.0.1"], sshPort: server.port)
        let session = DirectTerminalSession(mac: mac), interaction = VisionTerminalInteraction()
        let (window, previous) = try ownedWindow()
        defer { session.stop(); window.isHidden = true; previous?.makeKey(); try? TerminalSecretStore.remove(mac.id) }
        do {
            try TerminalSecretStore.write(Data(server.hostKey.utf8), id: mac.id, kind: "host-key")
            let host = UIHostingController(rootView: VisionTerminalSurface(session: session, interaction: interaction).directAppearance())
            window.rootViewController = host; host.view.layoutIfNeeded()
            session.connect(username: "synthetic", password: "synthetic-only", remember: false)
            try await wait("Native terminal controls attached", { session.connected && interaction.specialKey != nil })
            interaction.keyboard?(); interaction.specialKey?(0xff09); interaction.specialKey?(0xff1b)
            try await wait("Tab and Escape delivered", { server.record.received == [9, 27] })
            try await server.record.emit("\u{1b}[?1h\u{1b}[?2004h")
            try await Task.sleep(for: .milliseconds(100))
            interaction.specialKey?(0xff52)
            // Exercise the normal clipboard path and restore the Simulator clipboard.
            let previousPaste = UIPasteboard.general.string
            UIPasteboard.general.string = "paste"
            interaction.quickAction?(.init(title: "Paste", kind: .paste))
            UIPasteboard.general.string = previousPaste
            let expected = [UInt8]([9, 27]) + Array("\u{1b}OA\u{1b}[200~paste\u{1b}[201~".utf8)
            try await wait("Application cursor and bracketed paste", { server.record.received == expected })
            interaction.toggleModifier?(true); XCTAssertTrue(interaction.control)
            interaction.specialKey?(0xff51); XCTAssertFalse(interaction.control)
            interaction.sendControl?(4)
            try await wait("Control left and EOF", { server.record.received == expected + Array("\u{1b}[1;5D".utf8) + [4] })
            interaction.dismissKeyboard?(); XCTAssertFalse(interaction.control); XCTAssertFalse(interaction.option)
            @MainActor func terminalView(_ view: UIView) -> VisionTerminalView? {
                if let view = view as? VisionTerminalView { return view }
                return view.subviews.lazy.compactMap { terminalView($0) }.first
            }
            let native = try XCTUnwrap(terminalView(host.view))
            try await server.record.emit((0..<100).map { "synthetic-line-\($0)\r\n" }.joined())
            try await wait("Native scrollback grows", { native.contentSize.height > native.bounds.height })
            let beforeSelection = server.record.received
            native.selection.selectAll()
            XCTAssertTrue(native.selection.getSelectedText().contains("synthetic-line-0"))
            native.setContentOffset(.zero, animated: false)
            XCTAssertEqual(native.contentOffset.y, 0); XCTAssertEqual(server.record.received, beforeSelection, "Local scrollback and selection send no input")
            native.terminalDelegate?.requestOpenLink(source: native, link: "https://example.com", params: [:])
            XCTAssertEqual(interaction.link?.host, "example.com")
            session.background()
            let before = server.record.received
            interaction.specialKey?(0xff09); interaction.sendControl?(4)
            try await Task.sleep(for: .milliseconds(100)); XCTAssertEqual(server.record.received, before)
            try await server.close()
        } catch { try? await server.close(); throw error }
    }
}

@MainActor private final class WheelSampleRecognizer: UIPanGestureRecognizer {
    var sampledState: UIGestureRecognizer.State = .possible
    var sampledLocation = CGPoint.zero
    var sampledTranslation = CGPoint.zero
    override var state: UIGestureRecognizer.State {
        get { sampledState }
        set { sampledState = newValue }
    }
    override func location(in view: UIView?) -> CGPoint { sampledLocation }
    override func translation(in view: UIView?) -> CGPoint { sampledTranslation }
    override func setTranslation(_ translation: CGPoint, in view: UIView?) { sampledTranslation = translation }
}

@MainActor private final class PinchSampleRecognizer: UIPinchGestureRecognizer {
    var sampledState: UIGestureRecognizer.State = .possible
    var sampledLocation = CGPoint.zero
    override var state: UIGestureRecognizer.State {
        get { sampledState }
        set { sampledState = newValue }
    }
    override func location(in view: UIView?) -> CGPoint { sampledLocation }
}

@MainActor private final class TapSampleRecognizer: UITapGestureRecognizer {
    var sampledState: UIGestureRecognizer.State = .possible
    var sampledLocation = CGPoint.zero
    override var state: UIGestureRecognizer.State {
        get { sampledState }
        set { sampledState = newValue }
    }
    override func location(in view: UIView?) -> CGPoint { sampledLocation }
}
@MainActor private final class PointerSampleTouch: UITouch {
    var sampledLocation = CGPoint.zero
    override var type: UITouch.TouchType { .indirectPointer }
    override var phase: UITouch.Phase { .began }
    override func location(in view: UIView?) -> CGPoint { sampledLocation }
}
@MainActor private final class PointerSampleEvent: UIEvent {
    var sampledMask: UIEvent.ButtonMask = .primary
    override var type: UIEvent.EventType { .touches }
    override var buttonMask: UIEvent.ButtonMask { sampledMask }
}
