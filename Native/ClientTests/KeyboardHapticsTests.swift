#if os(iOS)
import SwiftTerm
import UIKit
import XCTest
@testable import Mac_Companion

@MainActor private final class KeyboardFeedbackRecorder: CompanionVNCInterfaceFeedback {
    var active = true
    var events: [String] = []
    override var foreground: Bool { active }
    override func emitFeedback(_ kind: String) { events.append(kind) }
}

@MainActor private final class KeyboardHold: UILongPressGestureRecognizer {
    var simulatedState: UIGestureRecognizer.State = .possible
    override var state: UIGestureRecognizer.State {
        get { simulatedState }
        set { simulatedState = newValue }
    }
}

@MainActor private final class HapticTerminalController: TerminalController {
    var output: [UInt8] = []
    override func send(source: TerminalView, data: ArraySlice<UInt8>) { output += terminal.encodeOutput(data) }
}

@MainActor private final class KeyboardMenuViewer: CompanionVNCViewer {
    var capturedMenu: UINavigationController?
    override func present(_ controller: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
        capturedMenu = controller as? UINavigationController
        completion?()
    }
}

@MainActor final class KeyboardHapticsTests: XCTestCase {
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    private func button(_ title: String, in view: UIView) throws -> UIButton {
        try XCTUnwrap(descendants(view).compactMap { $0 as? UIButton }.first {
            $0.configuration?.title == title || $0.title(for: .normal) == title
        })
    }
    private func withFeedback(_ body: (UserDefaults, KeyboardFeedbackRecorder) throws -> Void) rethrows {
        let suite = "synthetic-key-feedback-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults, KeyboardFeedbackRecorder(defaults: defaults))
    }
    private func terminal(_ feedback: KeyboardFeedbackRecorder) -> HapticTerminalController {
        let session = DirectTerminalSession(mac: .init(id: UUID(), name: "Synthetic keyboard", addresses: ["127.0.0.1"]))
        let controller = HapticTerminalController(session: session, customize: {})
        session.connected = true
        controller.loadViewIfNeeded(); controller.keyboardBar.keyFeedback = feedback
        return controller
    }
    private func viewer(_ feedback: KeyboardFeedbackRecorder, inputOnly: Bool, preset: Int = 0) -> CompanionVNCViewer {
        let viewer = CompanionVNCViewer()
        viewer.session = CompanionVNCSession(); viewer.macName = "Synthetic keyboard"
        viewer.inputOnly = inputOnly; viewer.restoredDesktopSizePreset = preset
        viewer.loadViewIfNeeded(); viewer.setValue(feedback, forKey: "keyFeedback")
        return viewer
    }
    private func hold(_ target: NSObject, button: UIButton, selector: String) {
        let gesture = KeyboardHold(); button.addGestureRecognizer(gesture)
        for state in [UIGestureRecognizer.State.began, .changed, .ended] {
            gesture.simulatedState = state
            _ = target.perform(NSSelectorFromString(selector), with: gesture)
        }
    }
    func testTerminalDigitsAndNavigationEmitOneQuietTickEachWithoutChangingOutput() throws {
        try withFeedback { _, feedback in
            let controller = terminal(feedback)
            for digit in "1234567890" { try button(String(digit), in: controller.keyboardBar).sendActions(for: .touchUpInside) }
            for key in [TerminalAccessoryKey.escape, .tab, .left, .down, .up, .right] {
                try button(key.title, in: controller.keyboardBar).sendActions(for: .touchUpInside)
            }
            let expected = Array("1234567890".utf8) + [TerminalAccessoryKey.escape, .tab, .left, .down, .up, .right].flatMap { $0.bytes() }
            XCTAssertEqual(controller.output, expected)
            XCTAssertEqual(feedback.events, Array(repeating: "key", count: 16))
        }
    }
    func testTerminalModifierTapsAndHoldsEmitOnlyOnExplicitStateChanges() throws {
        try withFeedback { _, feedback in
            let controller = terminal(feedback), bar = controller.keyboardBar
            let alt = try button("Alt", in: bar)
            alt.sendActions(for: .touchUpInside); alt.sendActions(for: .touchUpInside)
            XCTAssertTrue(controller.terminal.keyboardState.active.isEmpty)
            hold(bar, button: alt, selector: "lockModifier:")
            XCTAssertEqual(controller.terminal.keyboardState.locked, .alt)
            XCTAssertEqual(feedback.events, ["selection", "selection", "selection"])
            try button("1", in: bar).sendActions(for: .touchUpInside)
            XCTAssertEqual(controller.output, Array("\u{1b}1".utf8))
            XCTAssertEqual(controller.terminal.keyboardState.locked, .alt)
            hold(bar, button: alt, selector: "lockModifier:")
            XCTAssertTrue(controller.terminal.keyboardState.active.isEmpty)
            XCTAssertEqual(feedback.events, ["selection", "selection", "selection", "key", "selection"])
        }
    }
    func testTerminalReadsInterfacePreferenceLiveAndIgnoresTrackpadPreference() throws {
        try withFeedback { defaults, feedback in
            let controller = terminal(feedback), bar = controller.keyboardBar
            defaults.set(false, forKey: VNCSessionPreferences.trackpadHapticsKey)
            try button("Ctrl", in: bar).sendActions(for: .touchUpInside)
            try button("1", in: bar).sendActions(for: .touchUpInside)
            XCTAssertEqual(feedback.events, ["selection", "key"])
            defaults.set(false, forKey: CompanionVNCControlsHapticsPreference)
            try button("Alt", in: bar).sendActions(for: .touchUpInside)
            try button("2", in: bar).sendActions(for: .touchUpInside)
            XCTAssertEqual(feedback.events, ["selection", "key"])
            XCTAssertTrue(controller.output.suffix(2).elementsEqual(Array("\u{1b}2".utf8)), "Disabling haptics must not disable input")
            defaults.set(true, forKey: CompanionVNCControlsHapticsPreference)
            try button("3", in: bar).sendActions(for: .touchUpInside)
            XCTAssertEqual(feedback.events, ["selection", "key", "key"])
            XCTAssertFalse(defaults.bool(forKey: VNCSessionPreferences.trackpadHapticsKey))
        }
    }
    func testTerminalSystemTypingOutputAndAutomaticModifierResetAddNoFeedback() throws {
        try withFeedback { _, feedback in
            let controller = terminal(feedback)
            controller.terminal.insertText("synthetic"); controller.terminal.deleteBackward()
            controller.terminal.feed(text: "synthetic output\r\n")
            controller.terminal.resetModifiers(); controller.keyboardBar.refresh()
            XCTAssertTrue(feedback.events.isEmpty, "Only our on-screen controls should add haptics")
            feedback.active = false
            try button("1", in: controller.keyboardBar).sendActions(for: .touchUpInside)
            XCTAssertTrue(feedback.events.isEmpty)
        }
    }
    func testMirrorVirtualDisplayAndInputOnlyToolbarKeysHonorLivePreference() throws {
        for (inputOnly, preset) in [(false, 0), (false, 1), (true, 0)] {
            try withFeedback { defaults, feedback in
                let viewer = viewer(feedback, inputOnly: inputOnly, preset: preset)
                defer { viewer.stop() }
                let modifiers = try XCTUnwrap(viewer.value(forKey: "modifiers") as? [UIButton])
                XCTAssertEqual(modifiers.count, 4)
                for modifier in modifiers { modifier.sendActions(for: .touchUpInside) }
                try button("esc", in: viewer.view).sendActions(for: .touchUpInside)
                try button("⇥", in: viewer.view).sendActions(for: .touchUpInside)
                XCTAssertEqual(feedback.events, Array(repeating: "selection", count: 4) + ["key", "key"])
                defaults.set(false, forKey: CompanionVNCControlsHapticsPreference)
                modifiers[0].sendActions(for: .touchUpInside)
                try button("esc", in: viewer.view).sendActions(for: .touchUpInside)
                XCTAssertEqual(feedback.events.count, 6)
                defaults.set(true, forKey: CompanionVNCControlsHapticsPreference)
                defaults.set(false, forKey: VNCSessionPreferences.trackpadHapticsKey)
                try button("esc", in: viewer.view).sendActions(for: .touchUpInside)
                XCTAssertEqual(feedback.events.last, "key"); XCTAssertEqual(feedback.events.count, 7)
            }
        }
    }
    func testDesktopAndInputOnlyModifierHoldsEmitOnceAndSystemTypingAddsNothing() throws {
        for inputOnly in [false, true] {
            try withFeedback { _, feedback in
                let viewer = viewer(feedback, inputOnly: inputOnly)
                defer { viewer.stop() }
                let modifiers = try XCTUnwrap(viewer.value(forKey: "modifiers") as? [UIButton])
                for modifier in modifiers { hold(viewer, button: modifier, selector: "singleModifier:") }
                XCTAssertEqual(feedback.events, Array(repeating: "selection", count: 4))
                let input = try XCTUnwrap(viewer.value(forKey: "input") as? UITextView)
                input.text = "synthetic"
                _ = viewer.perform(NSSelectorFromString("textViewDidChange:"), with: input)
                _ = viewer.perform(NSSelectorFromString("resetModifiers"))
                XCTAssertEqual(feedback.events.count, 4)
            }
        }
    }
    func testDesktopAndInputOnlyMenuKeysHonorPreferenceWithoutDuplicatingQuickActions() throws {
        for inputOnly in [false, true] {
            try withFeedback { defaults, feedback in
                let viewer = KeyboardMenuViewer()
                viewer.session = CompanionVNCSession(); viewer.inputOnly = inputOnly
                viewer.loadViewIfNeeded(); viewer.setValue(feedback, forKey: "keyFeedback")
                defer { viewer.stop() }
                _ = viewer.perform(NSSelectorFromString("moreKeys:"), with: nil)
                let menu = try XCTUnwrap(viewer.capturedMenu?.topViewController as? CompanionVNCMenu)
                menu.selectionHandler?(["kind": "key", "key": 0xffbe])
                menu.selectionHandler?(["kind": "modifier", "key": 0xffe1])
                XCTAssertEqual(feedback.events, ["key", "selection"])
                defaults.set(false, forKey: CompanionVNCControlsHapticsPreference)
                menu.selectionHandler?(["kind": "key", "key": 0xffbe])
                XCTAssertEqual(feedback.events.count, 2)
                defaults.set(true, forKey: CompanionVNCControlsHapticsPreference)
                _ = viewer.perform(NSSelectorFromString("performControlAction:"), with: ["kind": "escape"])
                XCTAssertEqual(feedback.events.count, 2, "Quick-action UI already provides its own commit feedback")
            }
        }
    }
    func testRealUIKitGeneratorsAttachToTheTerminalAndDesktopKeySurfaces() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: CompanionVNCControlsHapticsPreference)
        defaults.set(true, forKey: CompanionVNCControlsHapticsPreference)
        defer { defaults.set(previous, forKey: CompanionVNCControlsHapticsPreference) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKeyAndVisible() }
        let session = DirectTerminalSession(mac: .init(id: UUID(), name: "Synthetic keyboard", addresses: ["127.0.0.1"]))
        session.connected = true
        let terminal = HapticTerminalController(session: session, customize: {})
        window.rootViewController = terminal; window.makeKeyAndVisible(); terminal.loadViewIfNeeded()
        let number = try button("1", in: terminal.keyboardBar)
        number.sendActions(for: .touchDown)
        XCTAssertTrue(terminal.output.isEmpty, "Preparing haptics must not send a key")
        number.sendActions(for: .touchUpInside)
        try button("Alt", in: terminal.keyboardBar).sendActions(for: .touchUpInside)
        XCTAssertEqual(terminal.keyboardBar.interactions.filter { $0 is UIImpactFeedbackGenerator }.count, 1,
                       "The real key generator must be attached to its visible keyboard surface")
        XCTAssertEqual(terminal.keyboardBar.interactions.filter { $0 is UISelectionFeedbackGenerator }.count, 1)
        for inputOnly in [false, true] {
            let viewer = CompanionVNCViewer(); viewer.session = CompanionVNCSession(); viewer.inputOnly = inputOnly
            window.rootViewController = viewer; viewer.loadViewIfNeeded()
            defer { viewer.stop() }
            try button("esc", in: viewer.view).sendActions(for: .touchUpInside)
            let modifiers = try XCTUnwrap(viewer.value(forKey: "modifiers") as? [UIButton])
            modifiers[0].sendActions(for: .touchUpInside)
            XCTAssertEqual(viewer.view.interactions.filter { $0 is UIImpactFeedbackGenerator }.count, 1)
            XCTAssertEqual(viewer.view.interactions.filter { $0 is UISelectionFeedbackGenerator }.count, 1)
        }
    }
    func testPreparingRealKeyFeedbackHonorsPreferenceAndReusesViewInteractions() throws {
        let suite = "synthetic-native-feedback-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let view = UIView()
        let feedback = CompanionVNCInterfaceFeedback(defaults: defaults, view: view)
        defaults.set(false, forKey: CompanionVNCControlsHapticsPreference)
        feedback.prepareKeyFeedback(); feedback.feedback("key"); feedback.feedback("selection")
        XCTAssertTrue(view.interactions.isEmpty, "Disabled haptics must not prepare or emit native feedback")
        defaults.set(true, forKey: CompanionVNCControlsHapticsPreference)
        feedback.prepareKeyFeedback()
        let impact = try XCTUnwrap(view.interactions.first { $0 is UIImpactFeedbackGenerator })
        let selection = try XCTUnwrap(view.interactions.first { $0 is UISelectionFeedbackGenerator })
        for _ in 0..<3 { feedback.prepareKeyFeedback(); feedback.feedback("key"); feedback.feedback("selection") }
        XCTAssertEqual(view.interactions.count, 2)
        XCTAssertTrue(view.interactions.contains { $0 === impact })
        XCTAssertTrue(view.interactions.contains { $0 === selection })
        XCTAssertTrue(feedback.sourceView === view)
    }
    func testCaptureOnScreenKeyboardsForSimulatorVisualReview() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        defer { window.rootViewController?.view.endEditing(true); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let terminal = HapticTerminalController(session: DirectTerminalSession(mac: .init(id: UUID(), name: "Synthetic keyboard", addresses: ["127.0.0.1"])), customize: {})
        terminal.session.connected = true
        window.rootViewController = terminal; window.makeKeyAndVisible(); terminal.loadViewIfNeeded()
        terminal.terminal.feed(text: "Synthetic Simulator keyboard preview\r\n")
        _ = terminal.terminal.becomeFirstResponder()
        try await Task.sleep(for: .milliseconds(450)); window.layoutIfNeeded()
        var image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        var attachment = XCTAttachment(image: image); attachment.name = "Terminal keyboard"; attachment.lifetime = .keepAlways; add(attachment)
        terminal.view.endEditing(true)
        for inputOnly in [false, true] {
            let viewer = CompanionVNCViewer(); viewer.session = CompanionVNCSession(); viewer.inputOnly = inputOnly
            viewer.macName = "Synthetic keyboard"; window.rootViewController = viewer; viewer.loadViewIfNeeded()
            let frame = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 650)).image { context in
                UIColor.systemBackground.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 650))
            }
            _ = viewer.perform(NSSelectorFromString("frame:"), with: frame)
            (viewer.value(forKey: "login") as? UIView)?.isHidden = true
            _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
            _ = viewer.perform(NSSelectorFromString("keyboard"))
            try await Task.sleep(for: .milliseconds(450)); window.layoutIfNeeded()
            image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            attachment = XCTAttachment(image: image); attachment.name = inputOnly ? "Trackpad and Keyboard" : "Screen Sharing keyboard"
            attachment.lifetime = .keepAlways; add(attachment); viewer.stop()
        }
    }
}
#endif
