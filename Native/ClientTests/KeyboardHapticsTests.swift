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

@MainActor private final class KeyboardDragSession: NSObject, UIDragSession, UIDropSession {
    var items: [UIDragItem] = []
    var localContext: Any?
    var allowsMoveOperation = true
    var isRestrictedToDraggingApplication = true
    var localDragSession: (any UIDragSession)? { self }
    var progressIndicatorStyle = UIDropSessionProgressIndicatorStyle.none
    nonisolated let progress = Progress(totalUnitCount: 1)
    let source: UIView
    var point = CGPoint.zero
    init(source: UIView) { self.source = source }
    func location(in view: UIView) -> CGPoint { source.convert(point, to: view) }
    func hasItemsConforming(toTypeIdentifiers typeIdentifiers: [String]) -> Bool { true }
    func canLoadObjects(ofClass aClass: any NSItemProviderReading.Type) -> Bool { false }
    func loadObjects(ofClass aClass: any NSItemProviderReading.Type, completion: @escaping ([any NSItemProviderReading]) -> Void) -> Progress {
        completion([]); return progress
    }
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
    var inputReady = true, acceptsInput = true
    var inputEpoch = UUID()
    override func viewDidLoad() {
        super.viewDidLoad()
        terminal.customInputEpoch = { [weak self] in self?.inputReady == true ? self?.inputEpoch : nil }
        terminal.admitCustomInput = { [weak self] bytes in
            guard let self, self.acceptsInput else { return false }; self.output += bytes; return true
        }
        terminal.admitCustomSequence = { [weak self] packets, valid, _, complete in
            guard let self, inputReady && acceptsInput, valid() else { complete("Synthetic input admission rejected"); return false }
            output += packets.flatMap { $0 }; complete(nil); return true
        }
        keyboardBar.refresh()
    }
    override func send(source: TerminalView, data: ArraySlice<UInt8>) { output += terminal.encodeOutput(data) }
}

private final class KeyboardMenuSession: CompanionVNCSession {
    var ready = true
    var live = true
    var sizeAllowed = true
    var acceptsSize = true
    var acceptsKeys = true
    var livePreset = 1
    var sizes: [Int] = []
    var keyGroups = 0
    var clicks = 0
    override func tryClickX(_ x: Int, y: Int, mask: Int) -> Bool { clicks += 1; return true }
    var sentKeys: [UInt32] = []
    override var running: Bool { live }
    override var connected: Bool { ready }
    override var desktopFrameReady: Bool { ready }
    override var desktopSizeAvailable: Bool { ready && sizeAllowed }
    override var diagnosticCounters: [AnyHashable: Any] {
        let size = livePreset == 1 ? (2048, 1280) : livePreset == 2 ? (2560, 1600) : (2880, 1800)
        return ["layoutVirtual": true, "layoutCount": 1, "framebufferWidth": size.0,
                "framebufferHeight": size.1, "layoutWidth": size.0, "layoutHeight": size.1]
    }
    override func requestDesktopSizePreset(_ preset: Int) -> Bool {
        guard acceptsSize else { return false }; sizes.append(preset); return true
    }
    override func keyEvents(_ events: [[AnyHashable: Any]]?) {
        if let events, !events.isEmpty {
            keyGroups += 1
            sentKeys += events.compactMap { ($0["key"] as? NSNumber)?.uint32Value }
        }
    }
    override func tryComposedTextEvents(_ events: [[AnyHashable: Any]], completion: @escaping (Bool) -> Void) -> Bool {
        guard tryKeyEvents(events) else { return false }; completion(true); return true
    }
    override func tryKeyEvents(_ events: [[AnyHashable: Any]]?) -> Bool {
        guard acceptsKeys else { return false }; keyEvents(events); return true
    }
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
        let title = title == "esc" ? "Escape" : title == "⇥" ? "Tab" : title
        return try XCTUnwrap(descendants(view).compactMap { $0 as? UIButton }.first {
            $0.accessibilityLabel == title || $0.configuration?.title == title || $0.title(for: .normal) == title
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
        viewer.macName = "Synthetic keyboard"
        viewer.inputOnly = inputOnly; viewer.restoredDesktopSizePreset = preset
        viewer.loadViewIfNeeded(); viewer.session = KeyboardMenuSession()
        viewer.setValue(feedback, forKey: "keyFeedback")
        (viewer.value(forKey: "login") as? UIView)?.isHidden = true
        _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
        return viewer
    }
    private func hold(_ target: NSObject, button: UIButton, selector: String) {
        let gesture = KeyboardHold(); button.addGestureRecognizer(gesture)
        for state in [UIGestureRecognizer.State.began, .changed, .ended] {
            gesture.simulatedState = state
            _ = target.perform(NSSelectorFromString(selector), with: gesture)
        }
    }
    func testIndividualKeyDragFeedbackTracksLiftInsertionAndCommitWithoutRepeating() throws {
        try withFeedback { defaults, feedback in
            let bar = TerminalKeyboardBar(terminal: nil, preferences: .init())
            bar.editingPreview = true; bar.previewShowsAllRows = true
            bar.configure(.defaults) { _ in XCTFail("Editing must not send input") }
            bar.keyFeedback = feedback
            bar.frame = CGRect(x: 0, y: 0, width: 430, height: bar.height); bar.layoutIfNeeded()
            let source = try button("Tab", in: bar), target = try button("Home", in: bar)
            let drag = try XCTUnwrap(source.interactions.compactMap { $0 as? UIDragInteraction }.first)
            let drop = try XCTUnwrap(target.interactions.compactMap { $0 as? UIDropInteraction }.first)
            let session = KeyboardDragSession(source: target)
            var moved = 0
            bar.previewPlacementMove = { _, _, _, _ in moved += 1 }
            session.items = bar.dragInteraction(drag, itemsForBeginning: session)
            XCTAssertEqual(session.items.count, 1)
            bar.dragInteraction(drag, sessionWillBegin: session)
            session.point = CGPoint(x: 1, y: target.bounds.midY)
            for _ in 0..<5 { _ = bar.dropInteraction(drop, sessionDidUpdate: session) }
            XCTAssertEqual(feedback.events, ["selection", "selection"])
            session.point.x = target.bounds.maxX - 1
            _ = bar.dropInteraction(drop, sessionDidUpdate: session)
            XCTAssertEqual(feedback.events, ["selection", "selection", "selection"])
            bar.dropInteraction(drop, performDrop: session)
            XCTAssertEqual(moved, 1); XCTAssertEqual(feedback.events.last, "commit")
            bar.dropInteraction(drop, sessionDidEnd: session)
            // Cancellation has no successful-drop feedback.
            feedback.events = []
            bar.dragInteraction(drag, sessionWillBegin: session)
            bar.dragInteraction(drag, sessionDidEnd: session, with: .cancel)
            XCTAssertEqual(feedback.events, ["selection"])
            // Dropping a key back on itself is also not a committed edit.
            let ownDrop = try XCTUnwrap(source.interactions.compactMap { $0 as? UIDropInteraction }.first)
            let ownSession = KeyboardDragSession(source: source); ownSession.items = session.items
            ownSession.point = CGPoint(x: 1, y: source.bounds.midY)
            bar.dropInteraction(ownDrop, performDrop: ownSession)
            XCTAssertEqual(moved, 1); XCTAssertEqual(feedback.events, ["selection"])
            for enabled in [false, true] {
                feedback.events = []; defaults.set(enabled, forKey: CompanionVNCControlsHapticsPreference)
                feedback.active = !enabled
                bar.dragInteraction(drag, sessionWillBegin: session)
                _ = bar.dropInteraction(drop, sessionDidUpdate: session)
                bar.dropInteraction(drop, performDrop: session)
                bar.dropInteraction(drop, sessionDidEnd: session)
                XCTAssertTrue(feedback.events.isEmpty, "Disabled haptics and background drags stay silent")
            }
        }
    }
    func testTerminalDigitsAndNavigationEmitOneQuietTickEachWithoutChangingOutput() throws {
        try withFeedback { _, feedback in
            let controller = terminal(feedback)
            for digit in "1234567890" { try button(String(digit), in: controller.keyboardBar).sendActions(for: .touchUpInside) }
            for key in [TerminalAccessoryKey.escape, .tab, .left, .down, .up, .right] {
                if key == .escape || key == .tab {
                    try button(key == .escape ? "Escape" : key.title, in: controller.keyboardBar).sendActions(for: .touchUpInside)
                } else { controller.makeMoreKeysMenu().selectionHandler?(["kind": "terminalKey-" + key.rawValue]) }
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
    func testTerminalModifierAccessibilityActionsNameTheirCurrentEffect() throws {
        try withFeedback { _, feedback in
            let controller = terminal(feedback), bar = controller.keyboardBar
            for key in bar.renderedModifiers where key.isEnabled {
                let title = try XCTUnwrap(key.accessibilityLabel)
                let keep = try XCTUnwrap(key.accessibilityCustomActions?.first)
                XCTAssertEqual(keep.name, "Keep " + title + " On")
                XCTAssertTrue(try XCTUnwrap(keep.actionHandler)(keep))
                XCTAssertEqual(key.accessibilityValue, "On")
                let turnOff = try XCTUnwrap(key.accessibilityCustomActions?.first)
                XCTAssertEqual(turnOff.name, "Turn " + title + " Off")
                XCTAssertTrue(try XCTUnwrap(turnOff.actionHandler)(turnOff))
                XCTAssertEqual(key.accessibilityValue, "Off")
            }
            XCTAssertTrue(controller.output.isEmpty)
        }
    }
    func testEveryRepeatedKeyboardAndExpandPlacementEmitsSelectionFeedback() throws {
        try withFeedback { defaults, feedback in
            let controller = terminal(feedback), bar = controller.keyboardBar
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
            window.rootViewController = controller; window.makeKeyAndVisible()
            defer { window.endEditing(true); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
            var profile = TerminalControlsProfile.defaults
            _ = profile.addPreset(.essentials, before: TerminalKeyboardRow.mainID)
            profile.placeBarItem(.control(.keyboard), in: TerminalKeyboardRow.mainID)
            profile.placeBarItem(.control(.expand), in: TerminalKeyboardRow.mainID)
            // Exercise this synthetic layout without the controller replacing
            // it with its separately persisted profile after an expansion.
            bar.layoutChanged = {}
            bar.configure(profile) { _ in XCTFail("Utilities never send input") }
            let keyboards = descendants(bar).compactMap { $0 as? UIButton }.filter { ["Show Keyboard", "Hide Keyboard"].contains($0.accessibilityLabel ?? "") }
            let expands = descendants(bar).compactMap { $0 as? UIButton }.filter { ["Expand Rows", "Collapse Rows"].contains($0.accessibilityLabel ?? "") }
            XCTAssertEqual(keyboards.count, 3); XCTAssertEqual(expands.count, 3)
            for key in keyboards {
                let before = controller.terminal.isFirstResponder, count = feedback.events.count
                key.sendActions(for: .touchUpInside)
                XCTAssertNotEqual(controller.terminal.isFirstResponder, before)
                XCTAssertEqual(feedback.events.count, count + 1); XCTAssertEqual(feedback.events.last, "selection")
            }
            for key in expands {
                let before = bar.showsExtraRows, count = feedback.events.count
                key.sendActions(for: .touchUpInside)
                XCTAssertNotEqual(bar.showsExtraRows, before); XCTAssertEqual(feedback.events.count, count + 1)
            }
            defaults.set(false, forKey: CompanionVNCControlsHapticsPreference)
            let count = feedback.events.count
            (keyboards + expands).forEach { $0.sendActions(for: .touchUpInside) }
            XCTAssertEqual(feedback.events.count, count); XCTAssertTrue(controller.output.isEmpty)
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
    func testKeyboardCustomizationOwnsInputUntilCloseAndCannotResumeAcrossInactivity() throws {
        try withFeedback { _, feedback in
            let viewer = viewer(feedback, inputOnly: true)
            let owner = try XCTUnwrap(viewer.session as? KeyboardMenuSession)
            defer { viewer.stop() }
            viewer.beginKeyboardCustomization()
            XCTAssertFalse(viewer.controlsInputAvailable())
            let input = try XCTUnwrap(viewer.value(forKey: "input") as? UITextView)
            input.text = "synthetic"; _ = viewer.perform(NSSelectorFromString("textViewDidChange:"), with: input)
            XCTAssertEqual(owner.keyGroups, 0, "Native typing cannot escape into the Mac while editing controls")
            viewer.endKeyboardCustomization(); XCTAssertTrue(viewer.controlsInputAvailable())
            let controls = try XCTUnwrap(viewer.value(forKey: "remoteControls") as? RemoteMacControls)
            controls.showSettings()
            for _ in 0..<3 { _ = viewer.perform(NSSelectorFromString("updateStatusPresentation")) }
            XCTAssertFalse(viewer.controlsInputAvailable(), "Status refreshes cannot close the editor or resume its input owner")
            input.text = "synthetic"; _ = viewer.perform(NSSelectorFromString("textViewDidChange:"), with: input)
            XCTAssertEqual(owner.keyGroups, 0)
            controls.reset(); XCTAssertTrue(viewer.controlsInputAvailable())
            viewer.beginKeyboardCustomization(); viewer.becameInactive(); viewer.endKeyboardCustomization()
            XCTAssertFalse(viewer.controlsInputAvailable(), "Closing a retained editor cannot release a lifecycle pause")
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
                viewer.inputOnly = inputOnly
                viewer.loadViewIfNeeded(); viewer.setValue(feedback, forKey: "keyFeedback")
                let owner = KeyboardMenuSession(); viewer.session = owner
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
    func testUnavailableConnectionCannotOpenKeyMenus() {
        let viewer = KeyboardMenuViewer(); viewer.loadViewIfNeeded()
        let owner = KeyboardMenuSession(); owner.ready = false; viewer.session = owner
        defer { viewer.stop() }
        _ = viewer.perform(NSSelectorFromString("moreKeys:"), with: nil)
        _ = viewer.perform(NSSelectorFromString("showFunctionKeys"))
        XCTAssertNil(viewer.capturedMenu)
        owner.ready = true; viewer.setValue(true, forKey: "restoreViewportPending")
        _ = viewer.perform(NSSelectorFromString("moreKeys:"), with: nil)
        _ = viewer.perform(NSSelectorFromString("showFunctionKeys"))
        XCTAssertNil(viewer.capturedMenu)
    }
    func testKeyMenuCallbacksRejectDisconnectRestoreAndReplacementWithoutInputOrFeedback() throws {
        for inputOnly in [false, true] {
            for transition in ["disconnected", "restoring", "replacement", "paused-and-resumed"] {
                try withFeedback { _, feedback in
                    let viewer = KeyboardMenuViewer(); viewer.inputOnly = inputOnly; viewer.loadViewIfNeeded()
                    viewer.setValue(feedback, forKey: "keyFeedback")
                    let owner = KeyboardMenuSession(); viewer.session = owner
                    defer { viewer.stop() }
                    _ = viewer.perform(NSSelectorFromString("moreKeys:"), with: nil)
                    let menu = try XCTUnwrap(viewer.capturedMenu?.topViewController as? CompanionVNCMenu)
                    let delayed = try XCTUnwrap(menu.selectionHandler)
                    let replacement = KeyboardMenuSession()
                    switch transition {
                    case "disconnected": owner.ready = false
                    case "restoring": viewer.setValue(true, forKey: "restoreViewportPending")
                    case "replacement": viewer.session = replacement
                    default:
                        _ = viewer.perform(NSSelectorFromString("becameInactive"))
                        viewer.setValue(false, forKey: "inputInactive")
                    }
                    delayed(["kind": "key", "key": 0xffbe]); delayed(["kind": "modifier", "key": 0xffe1])
                    XCTAssertTrue(feedback.events.isEmpty, transition)
                    XCTAssertEqual(owner.keyGroups, 0, transition); XCTAssertEqual(replacement.keyGroups, 0, transition)
                }
            }
        }
    }
    func testRejectedOrRemovedMenuShortcutsStaySilent() throws {
        try withFeedback { _, feedback in
            let viewer = KeyboardMenuViewer(); viewer.loadViewIfNeeded(); viewer.setValue(feedback, forKey: "keyFeedback")
            let owner = KeyboardMenuSession(); viewer.session = owner; defer { viewer.stop() }
            _ = viewer.perform(NSSelectorFromString("moreKeys:"), with: nil)
            let menu = try XCTUnwrap(viewer.capturedMenu?.topViewController as? CompanionVNCMenu)
            viewer.quickActionsProvider = { _ in [] }
            menu.selectionHandler?(["kind": "text", "id": "removed", "text": "synthetic"])
            XCTAssertTrue(feedback.events.isEmpty); XCTAssertEqual(owner.keyGroups, 0)
            viewer.quickActionsProvider = nil; owner.acceptsKeys = false
            menu.selectionHandler?(["kind": "text", "text": "synthetic"])
            XCTAssertTrue(feedback.events.isEmpty); XCTAssertEqual(owner.keyGroups, 0)
            owner.acceptsKeys = true
            menu.selectionHandler?(["kind": "text", "text": "synthetic"])
            XCTAssertEqual(feedback.events, ["key"]); XCTAssertEqual(owner.keyGroups, 1)
        }
    }
    func testNativeKeyMenuDismissesOnDisconnectAndCopiedCallbackCannotRevive() async throws {
        try await verifyMenuDismissal(inputOnly: false)
        try await verifyMenuDismissal(inputOnly: true)
    }
    private func verifyMenuDismissal(inputOnly: Bool) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let viewer = CompanionVNCViewer(); viewer.inputOnly = inputOnly
        window.rootViewController = viewer; window.makeKeyAndVisible(); viewer.loadViewIfNeeded()
        let owner = KeyboardMenuSession(); viewer.session = owner
        defer { viewer.stop(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        viewer.view.layoutIfNeeded()
        _ = viewer.perform(NSSelectorFromString("moreKeys:"), with: nil)
        let navigation = try XCTUnwrap(viewer.presentedViewController as? UINavigationController)
        let menu = try XCTUnwrap(navigation.topViewController as? CompanionVNCMenu)
        let copied = try XCTUnwrap(menu.selectionHandler)
        for _ in 0..<100 {
            if !navigation.isBeingPresented { break }; try await Task.sleep(for: .milliseconds(20))
        }
        owner.ready = false
        _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
        for _ in 0..<100 {
            if viewer.presentedViewController == nil { break }; try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNil(viewer.presentedViewController)
        XCTAssertFalse(navigation.view.isUserInteractionEnabled); XCTAssertNil(menu.selectionHandler)
        owner.ready = true; copied(["kind": "key", "key": 0xffbe])
        XCTAssertEqual(owner.keyGroups, 0, "An old callback cannot revive when the same connection becomes ready again")
    }
    func testRemoteToolbarWaitsSilentlyAndReenablesWithoutQueuedModifiers() throws {
        for (inputOnly, preset) in [(false, 0), (false, 1), (true, 0)] {
            for pause in ["resizing", "checkingResume", "restoreViewportPending", "inputInactive", "foreground", "exited"] {
                try withFeedback { _, feedback in
                    let viewer = viewer(feedback, inputOnly: inputOnly, preset: preset)
                    let owner = try XCTUnwrap(viewer.session as? KeyboardMenuSession)
                    defer { viewer.stop() }
                    let modifiers = try XCTUnwrap(viewer.value(forKey: "modifiers") as? [UIButton])
                    modifiers[0].sendActions(for: .touchUpInside)
                    XCTAssertTrue(modifiers[0].isSelected)
                    feedback.events.removeAll()
                    if pause == "resizing" { owner.ready = false }
                    else { viewer.setValue(pause != "foreground", forKey: pause) }
                    _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
                    for key in [try button("esc", in: viewer.view), try button("⇥", in: viewer.view)] + modifiers {
                        XCTAssertFalse(key.isEnabled, pause); XCTAssertLessThan(key.alpha, 1, pause)
                        // Exercise the handler as well as UIKit's disabled appearance.
                        _ = viewer.perform(NSSelectorFromString("remoteKey:"), with: key)
                    }
                    for modifier in modifiers { hold(viewer, button: modifier, selector: "singleModifier:") }
                    XCTAssertTrue(feedback.events.isEmpty, pause); XCTAssertEqual(owner.keyGroups, 0, pause)
                    XCTAssertTrue(modifiers.allSatisfy { !$0.isSelected }, "A pause clears one-shot modifiers")
                    let keyboard = try XCTUnwrap(viewer.value(forKey: "keyboardButton") as? UIButton)
                    XCTAssertTrue(keyboard.isEnabled, "Keyboard visibility remains a local control")
                    owner.ready = true
                    if pause != "resizing" { viewer.setValue(pause == "foreground", forKey: pause) }
                    _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
                    let escape = try button("esc", in: viewer.view)
                    XCTAssertTrue(escape.isEnabled); XCTAssertEqual(escape.alpha, 1)
                    escape.sendActions(for: .touchUpInside)
                    XCTAssertEqual(feedback.events, ["key"]); XCTAssertEqual(owner.keyGroups, 1)
                    XCTAssertEqual(owner.sentKeys, [0xff1b, 0xff1b], "No queued modifier is sent after recovery")
                    XCTAssertTrue(modifiers.allSatisfy { !$0.isSelected })
                }
            }
        }
    }
    func testGeneralMenusKeepLocalActionsDuringTemporaryInputPauses() throws {
        for pause in ["resizing", "checkingResume", "restoreViewportPending"] {
            try withFeedback { _, feedback in
                let viewer = KeyboardMenuViewer(); viewer.loadViewIfNeeded(); viewer.setValue(feedback, forKey: "keyFeedback")
                let owner = KeyboardMenuSession(); viewer.session = owner
                defer { viewer.stop() }
                _ = viewer.perform(NSSelectorFromString("showViewMenu"))
                let menu = try XCTUnwrap(viewer.capturedMenu?.topViewController as? CompanionVNCMenu)
                let selection = try XCTUnwrap(menu.selectionHandler)
                if pause == "resizing" { owner.ready = false }
                else { viewer.setValue(true, forKey: pause) }
                _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
                XCTAssertNotNil(menu.selectionHandler, pause)
                selection(["kind": "fullscreen"])
                XCTAssertTrue(viewer.fullscreen, pause); XCTAssertEqual(feedback.events, ["selection"], pause)
                var settingsOpened = 0; viewer.appSettingsHandler = { settingsOpened += 1 }
                _ = viewer.perform(NSSelectorFromString("showSessionMenu"))
                let sessionMenu = try XCTUnwrap(viewer.capturedMenu?.topViewController as? CompanionVNCMenu)
                sessionMenu.selectionHandler?(["kind": "appSettings"])
                XCTAssertEqual(settingsOpened, 1, pause); XCTAssertEqual(owner.keyGroups, 0)
                let inputSections = try XCTUnwrap(viewer.perform(NSSelectorFromString("inputMenuSections"))?.takeUnretainedValue() as? [[String: Any]])
                let rows = inputSections.flatMap { $0["items"] as? [[String: Any]] ?? [] }
                XCTAssertEqual(rows.first { $0["kind"] as? String == "keys" }?["disabled"] as? Bool, true)
            }
        }
    }
    func testDisplayMenuCanStartStandaloneInputOnlyRecoveryDuringResize() throws {
        let viewer = KeyboardMenuViewer(); viewer.loadViewIfNeeded()
        let owner = KeyboardMenuSession(); owner.ready = false; viewer.session = owner
        defer { viewer.stop() }
        let credentials = try XCTUnwrap(viewer.value(forKey: "credentialState") as? DirectDesktopLoginState)
        credentials.edit(username: "synthetic", password: "synthetic-only", remember: false)
        _ = credentials.beginLogin(); credentials.authenticated()
        var attempts = 0; viewer.connectHandler = { _, _, _ in attempts += 1 }
        viewer.setValue(2, forKey: "pendingDesktopSizePreset")
        _ = viewer.perform(NSSelectorFromString("showViewMenu"))
        let menu = try XCTUnwrap(viewer.capturedMenu?.topViewController as? CompanionVNCMenu)
        _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
        menu.selectionHandler?(["kind": "inputOnly"])
        XCTAssertTrue(viewer.inputOnly); XCTAssertEqual(attempts, 1)
        XCTAssertEqual(viewer.value(forKey: "pendingDesktopSizePreset") as? Int, 0)
        XCTAssertEqual(owner.keyGroups, 0)
    }
    func testGeneralMenuCallbacksCannotReviveAfterLifecycleRetirement() throws {
        for transition in ["inactive", "stop", "replacement"] {
            let viewer = KeyboardMenuViewer(); viewer.loadViewIfNeeded()
            let owner = KeyboardMenuSession(); viewer.session = owner
            defer { viewer.stop() }
            _ = viewer.perform(NSSelectorFromString("showSessionMenu"))
            let menu = try XCTUnwrap(viewer.capturedMenu?.topViewController as? CompanionVNCMenu)
            let delayed = try XCTUnwrap(menu.selectionHandler)
            var settingsOpened = 0; viewer.appSettingsHandler = { settingsOpened += 1 }
            switch transition {
            case "inactive": viewer.becameInactive(); viewer.foregrounded()
            case "stop": viewer.stop()
            default: viewer.session = KeyboardMenuSession()
            }
            delayed(["kind": "appSettings"])
            XCTAssertEqual(settingsOpened, 0, transition)
        }
    }
    func testNativeQueueRejectionKeepsToolbarAndMenuKeyFeedbackSilent() throws {
        for inputOnly in [false, true] {
            try withFeedback { _, feedback in
                let viewer = KeyboardMenuViewer(); viewer.inputOnly = inputOnly; viewer.loadViewIfNeeded()
                viewer.setValue(feedback, forKey: "keyFeedback")
                let owner = KeyboardMenuSession(); owner.acceptsKeys = false; viewer.session = owner
                defer { viewer.stop() }
                let escape = try button("esc", in: viewer.view)
                let modifiers = try XCTUnwrap(viewer.value(forKey: "modifiers") as? [UIButton])
                _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
                XCTAssertTrue(escape.isEnabled, "Ready appearance does not guarantee native queue admission")
                escape.sendActions(for: .touchUpInside)
                for modifier in modifiers { hold(viewer, button: modifier, selector: "singleModifier:") }
                _ = viewer.perform(NSSelectorFromString("moreKeys:"), with: nil)
                let menu = try XCTUnwrap(viewer.capturedMenu?.topViewController as? CompanionVNCMenu)
                menu.selectionHandler?(["kind": "key", "key": 0xffbe])
                menu.selectionHandler?(["kind": "modifier", "key": 0xffe1])
                XCTAssertTrue(feedback.events.isEmpty); XCTAssertEqual(owner.keyGroups, 0)
                owner.acceptsKeys = true
                escape.sendActions(for: .touchUpInside)
                menu.selectionHandler?(["kind": "modifier", "key": 0xffe1])
                XCTAssertEqual(feedback.events, ["key", "selection"]); XCTAssertEqual(owner.keyGroups, 2)
            }
        }
    }
    func testTerminalPasteFeedbackRequiresContentAndPreservesNativeBracketedPaste() throws {
        // This QA fixture owns only synthetic clipboard content; never read
        // the Simulator's previous (potentially shared) clipboard.
        UIPasteboard.general.items = []
        defer { UIPasteboard.general.items = [] }
        for bracketed in [false, true] {
            try withFeedback { defaults, feedback in
                let controller = terminal(feedback), terminal = controller.terminal
                if bracketed { terminal.feed(text: "\u{1b}[?2004h") }
                XCTAssertEqual(terminal.getTerminal().bracketedPasteMode, bracketed)
                terminal.keyboardState.toggle(.alt)
                UIPasteboard.general.items = []
                terminal.pasteWithFeedback()
                XCTAssertTrue(feedback.events.isEmpty); XCTAssertTrue(controller.output.isEmpty)
                XCTAssertEqual(terminal.keyboardState.active, .alt)
                UIPasteboard.general.string = ""
                terminal.pasteWithFeedback()
                XCTAssertTrue(feedback.events.isEmpty); XCTAssertEqual(terminal.keyboardState.active, .alt)
                XCTAssertTrue(controller.output.isEmpty, "Empty custom paste does not enqueue framing alone")
                controller.output.removeAll()
                UIPasteboard.general.string = "synthetic\ntext"
                terminal.pasteWithFeedback()
                let expected = Array((bracketed ? "\u{1b}[200~synthetic\ntext\u{1b}[201~" : "synthetic\ntext").utf8)
                XCTAssertEqual(controller.output, expected); XCTAssertEqual(feedback.events, ["key"])
                XCTAssertTrue(terminal.keyboardState.active.isEmpty)
                defaults.set(false, forKey: CompanionVNCControlsHapticsPreference)
                terminal.pasteWithFeedback()
                XCTAssertEqual(controller.output, expected + expected); XCTAssertEqual(feedback.events, ["key"])
            }
        }
    }
    func testTerminalPausedRejectedAndRetiredMenuActionsStaySilent() throws {
        try withFeedback { _, feedback in
            let controller = terminal(feedback), terminal = controller.terminal, bar = controller.keyboardBar
            let oldMenu = controller.makeMoreKeysMenu()
            func trigger(_ menu: CompanionVNCMenu, _ kind: String) {
                menu.selectionHandler?(["kind": kind])
            }
            controller.inputReady = false; bar.refresh()
            try button("1", in: bar).sendActions(for: .touchUpInside)
            try button("Ctrl", in: bar).sendActions(for: .touchUpInside)
            trigger(oldMenu, "terminalKey-f1"); trigger(oldMenu, "shiftNext"); terminal.pasteWithFeedback()
            XCTAssertTrue(controller.output.isEmpty); XCTAssertTrue(feedback.events.isEmpty)
            XCTAssertTrue(terminal.keyboardState.active.isEmpty)
            XCTAssertFalse(try button("1", in: bar).isEnabled); XCTAssertTrue(bar.keyboardButton.isEnabled)
            controller.inputReady = true; controller.inputEpoch = UUID(); bar.refresh()
            trigger(oldMenu, "terminalKey-f1"); trigger(oldMenu, "shiftNext")
            XCTAssertTrue(controller.output.isEmpty); XCTAssertTrue(feedback.events.isEmpty)
            controller.acceptsInput = false
            let currentMenu = controller.makeMoreKeysMenu()
            trigger(currentMenu, "terminalKey-f1"); try button("1", in: bar).sendActions(for: .touchUpInside)
            XCTAssertTrue(controller.output.isEmpty); XCTAssertTrue(feedback.events.isEmpty)
            controller.acceptsInput = true
            trigger(currentMenu, "terminalKey-f1")
            XCTAssertEqual(controller.output, TerminalAccessoryKey.f1.bytes()); XCTAssertEqual(feedback.events, ["key"])
        }
    }
    func testOrdinaryVNCCommitsKeepOverflowFailureWhileAccessoryRejectionStaysRetryable() throws {
        for systemInput in ["text", "delete"] {
            try withFeedback { _, feedback in
                let viewer = CompanionVNCViewer(); viewer.loadViewIfNeeded(); viewer.setValue(feedback, forKey: "keyFeedback")
                let owner = CompanionVNCSession(); owner.setValue(true, forKey: "running"); owner.setValue(true, forKey: "inputReady")
                viewer.session = owner
                defer { owner.setValue(false, forKey: "running"); viewer.stop() }
                let full: [[AnyHashable: Any]] = (0..<512).map { ["key": 0x61, "down": $0 % 2 == 0] }
                XCTAssertTrue(owner.tryKeyEvents(full))
                try button("esc", in: viewer.view).sendActions(for: .touchUpInside)
                XCTAssertTrue(feedback.events.isEmpty); XCTAssertEqual(owner.value(forKey: "overflow") as? Bool, false)
                XCTAssertEqual((owner.value(forKey: "events") as? [NSDictionary])?.count, 512)
                let input = try XCTUnwrap(viewer.value(forKey: "input") as? UITextView)
                if systemInput == "text" {
                    input.text = "synthetic"
                    _ = viewer.perform(NSSelectorFromString("textViewDidChange:"), with: input)
                } else { input.deleteBackward() }
                XCTAssertEqual(owner.value(forKey: "overflow") as? Bool, true, systemInput)
                XCTAssertTrue(feedback.events.isEmpty)
            }
        }
    }
    private func chooseQuickAction(_ item: [AnyHashable: Any], in controls: CompanionVNCControls) {
        controls.setValue(UIVisualEffectView(), forKey: "panel")
        controls.setValue([item], forKey: "items")
        let choice = UIButton(); choice.tag = 0
        _ = controls.perform(NSSelectorFromString("chosen:"), with: choice)
    }
    func testTerminalQuickActionProducerWaitsForAdmissionAndEmptyPasteStaysSilent() throws {
        try withFeedback { defaults, feedback in
            let controller = terminal(feedback), terminal = controller.terminal, controls = controller.controls
            controls.setValue(feedback, forKey: "interfaceFeedback")
            defer { UIPasteboard.general.items = [] }
            controller.inputReady = false
            for kind in ["escape", "tab", "returnKey", "interrupt", "paste"] { chooseQuickAction(["kind": kind], in: controls) }
            XCTAssertTrue(feedback.events.isEmpty); XCTAssertTrue(controller.output.isEmpty)
            controller.inputReady = true; controller.acceptsInput = false
            chooseQuickAction(["kind": "escape"], in: controls)
            XCTAssertTrue(feedback.events.isEmpty); XCTAssertTrue(controller.output.isEmpty)
            controller.acceptsInput = true
            for kind in ["escape", "tab", "returnKey", "interrupt"] { chooseQuickAction(["kind": kind], in: controls) }
            XCTAssertEqual(controller.output, [0x1b, 0x09, 0x0d, 0x03])
            XCTAssertEqual(feedback.events, Array(repeating: "commit", count: 4), "One owner pulse per accepted quick action")
            terminal.keyboardState.toggle(.alt)
            UIPasteboard.general.items = []
            chooseQuickAction(["kind": "paste"], in: controls)
            XCTAssertEqual(feedback.events.count, 4); XCTAssertEqual(terminal.keyboardState.active, .alt)
            terminal.feed(text: "\u{1b}[?2004h")
            UIPasteboard.general.string = "synthetic"
            controller.acceptsInput = false
            chooseQuickAction(["kind": "paste"], in: controls)
            XCTAssertEqual(feedback.events.count, 4); XCTAssertEqual(terminal.keyboardState.active, .alt)
            controller.acceptsInput = true
            chooseQuickAction(["kind": "paste"], in: controls)
            XCTAssertEqual(controller.output, [0x1b, 0x09, 0x0d, 0x03] + Array("\u{1b}[200~synthetic\u{1b}[201~".utf8))
            XCTAssertEqual(feedback.events.count, 5); XCTAssertTrue(terminal.keyboardState.active.isEmpty)
            chooseQuickAction(["kind": "text", "id": UUID().uuidString, "text": "removed"], in: controls)
            XCTAssertEqual(feedback.events.count, 5, "Removed or unavailable Pro actions stay silent")
            defaults.set(false, forKey: CompanionVNCControlsHapticsPreference)
            chooseQuickAction(["kind": "escape"], in: controls)
            XCTAssertEqual(controller.output.last, 0x1b); XCTAssertEqual(feedback.events.count, 5)
        }
    }
    func testVNCQuickActionProducerRejectsFullQueueAndPulsesOnceAfterAcceptanceInBothModes() throws {
        for inputOnly in [false, true] {
            try withFeedback { defaults, feedback in
                let viewer = CompanionVNCViewer(); viewer.inputOnly = inputOnly; viewer.loadViewIfNeeded()
                viewer.setValue(feedback, forKey: "keyFeedback")
                let controls = try XCTUnwrap(viewer.value(forKey: "controls") as? CompanionVNCControls)
                controls.setValue(feedback, forKey: "interfaceFeedback")
                let full = CompanionVNCSession(); full.setValue(true, forKey: "running"); full.setValue(true, forKey: "inputReady")
                viewer.session = full
                defer { full.setValue(false, forKey: "running"); viewer.stop() }
                XCTAssertTrue(full.tryKeyEvents((0..<512).map { ["key": 0x61, "down": $0 % 2 == 0] }))
                let actions: [[AnyHashable: Any]] = [["kind": "escape"], ["kind": "tab"], ["kind": "returnKey"],
                    ["kind": "text", "text": "synthetic"], ["kind": "shortcut", "key": 0xff1b, "modifiers": [0xffe9]], ["kind": "rightClick"]]
                for item in actions { chooseQuickAction(item, in: controls) }
                XCTAssertTrue(feedback.events.isEmpty); XCTAssertEqual(full.value(forKey: "overflow") as? Bool, false)
                let accepted = KeyboardMenuSession(); viewer.session = accepted; full.setValue(false, forKey: "running")
                for item in actions { chooseQuickAction(item, in: controls) }
                XCTAssertEqual(feedback.events, Array(repeating: "commit", count: actions.count))
                XCTAssertEqual(accepted.keyGroups, 5); XCTAssertEqual(accepted.clicks, 1)
                chooseQuickAction(["kind": "text", "text": ""], in: controls)
                XCTAssertEqual(feedback.events.count, actions.count, "Empty text is not an accepted key action")
                viewer.quickActionsProvider = { _ in [] }
                chooseQuickAction(["kind": "text", "id": "removed", "text": "synthetic"], in: controls)
                XCTAssertEqual(feedback.events.count, actions.count)
                defaults.set(false, forKey: CompanionVNCControlsHapticsPreference)
                chooseQuickAction(["kind": "escape"], in: controls)
                XCTAssertEqual(feedback.events.count, actions.count); XCTAssertEqual(accepted.keyGroups, 6)
            }
        }
    }
    func testDesktopSizeFeedbackUsesLiveGeometryAndPreservesVerifiedSaving() {
        withFeedback { defaults, feedback in
            let viewer = CompanionVNCViewer(); viewer.loadViewIfNeeded(); viewer.setValue(feedback, forKey: "keyFeedback")
            let owner = KeyboardMenuSession(); viewer.session = owner; viewer.restoredDesktopSizePreset = 2
            var saved: [Int] = []; viewer.desktopSizeSelectionHandler = { saved.append($0) }
            defer { viewer.stop() }
            _ = viewer.perform(NSSelectorFromString("performControlAction:"), with: ["kind": "desktopSize", "preset": 1])
            XCTAssertTrue(feedback.events.isEmpty, "Reselecting the live size stays silent even if the saved preference differs")
            XCTAssertTrue(owner.sizes.isEmpty); XCTAssertEqual(saved, [1])
            // Recreate the independent mismatch before choosing the saved size.
            viewer.restoredDesktopSizePreset = 2; saved = []
            _ = viewer.perform(NSSelectorFromString("performControlAction:"), with: ["kind": "desktopSize", "preset": 2])
            XCTAssertEqual(feedback.events, ["selection"]); XCTAssertEqual(owner.sizes, [2])
            XCTAssertTrue(saved.isEmpty, "A queued resize must not overwrite the saved size before verified pixels")
            viewer.setValue(0, forKey: "pendingDesktopSizePreset"); owner.acceptsSize = false
            _ = viewer.perform(NSSelectorFromString("performControlAction:"), with: ["kind": "desktopSize", "preset": 3])
            XCTAssertEqual(feedback.events.count, 1); XCTAssertEqual(owner.sizes, [2])
            owner.acceptsSize = true; defaults.set(false, forKey: CompanionVNCControlsHapticsPreference)
            _ = viewer.perform(NSSelectorFromString("performControlAction:"), with: ["kind": "desktopSize", "preset": 3])
            XCTAssertEqual(feedback.events.count, 1); XCTAssertEqual(owner.sizes, [2, 3]); XCTAssertTrue(saved.isEmpty)
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
            viewer.session = KeyboardMenuSession()
            _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
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
            viewer.session = KeyboardMenuSession()
            _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
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
