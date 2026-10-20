#if os(iOS)
import UIKit
import XCTest
@testable import Mac_Companion

@MainActor private final class InteractionFeedbackRecorder: CompanionVNCInterfaceFeedback {
    var active = true
    var events: [String] = []
    override var foreground: Bool { active }
    override func emitFeedback(_ kind: String) { events.append(kind) }
}

@MainActor private final class InteractionPan: UIPanGestureRecognizer {
    var phase: UIGestureRecognizer.State = .possible
    override var state: UIGestureRecognizer.State { get { phase } set { phase = newValue } }
}

@MainActor final class InteractionHapticsTests: XCTestCase {
    private func withFeedback(_ body: (UserDefaults, InteractionFeedbackRecorder) throws -> Void) rethrows {
        let suite = "synthetic-interaction-feedback-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults, InteractionFeedbackRecorder(defaults: defaults))
    }
    private func withWindow(_ controller: UIViewController, _ body: () throws -> Void) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        window.rootViewController = controller; window.makeKeyAndVisible(); controller.loadViewIfNeeded()
        defer { controller.view.endEditing(true); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        try body()
    }
    func testTerminalKeyboardTogglesTickOnceAndAutomaticFocusAndNoopStaySilent() throws {
        try withFeedback { defaults, feedback in
            let session = DirectTerminalSession(mac: .init(id: UUID(), name: "Synthetic", addresses: ["synthetic.invalid"]))
            session.connected = true
            let controller = TerminalController(session: session, customize: {})
            defer { session.stop() }
            try withWindow(controller) {
                controller.keyboardBar.keyFeedback = feedback
                _ = controller.terminal.resignFirstResponder()
                controller.keyboardBar.keyboardButton.sendActions(for: .touchUpInside)
                XCTAssertTrue(controller.terminal.isFirstResponder)
                controller.keyboardBar.keyboardButton.sendActions(for: .touchUpInside)
                XCTAssertFalse(controller.terminal.isFirstResponder)
                XCTAssertEqual(feedback.events, ["selection", "selection"])
                _ = controller.terminal.becomeFirstResponder(); _ = controller.terminal.resignFirstResponder()
                XCTAssertEqual(feedback.events.count, 2)
                controller.keyboardBar.toggleKeyboard = {}
                controller.keyboardBar.keyboardButton.sendActions(for: .touchUpInside)
                XCTAssertEqual(feedback.events.count, 2)
                defaults.set(false, forKey: CompanionVNCControlsHapticsPreference)
                controller.controls.actionHandler?(["kind": "numberRow"])
                XCTAssertEqual(feedback.events.count, 2)
            }
        }
    }
    func testDesktopAndInputOnlyKeyboardTogglesHonorPreferenceAndIgnoreAutomaticFocus() throws {
        for inputOnly in [false, true] {
            try withFeedback { defaults, feedback in
                let viewer = CompanionVNCViewer(); viewer.session = CompanionVNCSession(); viewer.inputOnly = inputOnly
                defer { viewer.stop() }
                try withWindow(viewer) {
                    viewer.setValue(feedback, forKey: "keyFeedback")
                    let input = try XCTUnwrap(viewer.value(forKey: "input") as? UITextView)
                    input.resignFirstResponder()
                    _ = viewer.perform(NSSelectorFromString("keyboard"))
                    XCTAssertTrue(input.isFirstResponder)
                    _ = viewer.perform(NSSelectorFromString("keyboard"))
                    XCTAssertFalse(input.isFirstResponder)
                    XCTAssertEqual(feedback.events, ["selection", "selection"])
                    input.becomeFirstResponder(); input.resignFirstResponder()
                    XCTAssertEqual(feedback.events.count, 2)
                    defaults.set(false, forKey: CompanionVNCControlsHapticsPreference)
                    _ = viewer.perform(NSSelectorFromString("keyboard"))
                    XCTAssertEqual(feedback.events.count, 2)
                }
            }
        }
    }
    func testSessionOptionsTickOnlyForChangesAndNotRestorationOrRejectedInputOnly() throws {
        withFeedback { defaults, feedback in
            let viewer = CompanionVNCViewer(); viewer.session = CompanionVNCSession(); viewer.loadViewIfNeeded()
            viewer.setValue(feedback, forKey: "keyFeedback"); defer { viewer.stop() }
            func action(_ kind: String) { _ = viewer.perform(NSSelectorFromString("performControlAction:"), with: ["kind": kind]) }
            viewer.fullscreen = true; viewer.fullscreen = false
            XCTAssertTrue(feedback.events.isEmpty, "Restoring presentation stays silent")
            action("setTrackpad"); action("setTrackpad"); action("setPointer"); action("setPointer")
            XCTAssertEqual(feedback.events, ["selection", "selection"])
            action("fullscreen"); XCTAssertEqual(feedback.events.count, 3)
            viewer.setValue(false, forKey: "foreground")
            action("inputOnly"); XCTAssertEqual(feedback.events.count, 3, "Background input-only changes are rejected")
            defaults.set(false, forKey: CompanionVNCControlsHapticsPreference)
            action("fullscreen"); action("setTrackpad"); XCTAssertEqual(feedback.events.count, 3)
        }
    }
    func testTerminalNumberRowAndPaletteMenusAvoidReselectionAndDuplicateFeedback() {
        withFeedback { _, feedback in
            let appearance = DirectAppearanceV1.shared, previous = appearance.terminal
            defer { appearance.terminal = previous }
            appearance.terminal = .app
            let session = DirectTerminalSession(mac: .init(id: UUID(), name: "Synthetic", addresses: ["synthetic.invalid"]))
            let controller = TerminalController(session: session, customize: {}); session.connected = true; controller.loadViewIfNeeded()
            defer { session.stop() }
            controller.keyboardBar.keyFeedback = feedback
            controller.controls.actionHandler?(["kind": "numberRow"])
            controller.controls.actionHandler?(["kind": "colors-dark"])
            controller.controls.actionHandler?(["kind": "colors-dark"])
            XCTAssertEqual(feedback.events, ["selection", "selection"])
            controller.controls.actionHandler?(["kind": "numberRow", "interfaceFeedbackHandled": true])
            XCTAssertEqual(feedback.events.count, 2)
        }
    }
    func testComposerCompletionIsOwnedAndEmitsOnceForSuccessOrFailure() {
        for error in [nil, "Synthetic send failure"] as [String?] {
            let draft = DirectTextComposerDraft(macName: "Synthetic", mode: .terminal)
            var completion: ((String?) -> Void)?, events: [String] = [], closed = 0
            draft.feedback = { events.append($0) }; draft.close = { closed += 1 }
            draft.configure(available: { true }, send: { _, done in completion = done })
            draft.edit("synthetic"); draft.requestSend(); XCTAssertTrue(draft.sending)
            completion?(error); completion?(error)
            XCTAssertEqual(events, [error == nil ? "success" : "error"])
            XCTAssertEqual(closed, error == nil ? 1 : 0)
        }
    }
    func testComposerRetiredUnavailableAndCancelledWorkStaySilent() {
        for retired in [false, true] {
            let draft = DirectTextComposerDraft(macName: "Synthetic", mode: .terminal)
            var completion: ((String?) -> Void)?, events: [String] = [], available = true
            draft.feedback = { events.append($0) }
            draft.configure(available: { available }, send: { _, done in completion = done })
            draft.edit("synthetic"); draft.requestSend()
            if retired { draft.invalidate(); draft.configure(available: { true }, send: { _, _ in }) }
            else { available = false }
            completion?(nil); completion?("Synthetic failure")
            XCTAssertTrue(events.isEmpty)
        }
    }
    func testSavedLoginSuccessFollowsCommitAndFailureNeverEmitsSuccess() throws {
        let mac = UUID(); defer { try? DirectMacAccessStore.forget(mac) }
        let draft = DirectMacAccessDraft(macID: mac); var events: [String] = []
        draft.feedback = { events.append($0) }
        XCTAssertFalse(draft.save()); XCTAssertTrue(events.isEmpty)
        draft.load(); XCTAssertTrue(draft.save()); XCTAssertTrue(events.isEmpty, "Unchanged Save is silent")
        draft.value.login = .init(username: "synthetic", password: "synthetic-only")
        XCTAssertTrue(draft.save(onSaved: { XCTAssertNotNil(try? DirectMacAccessStore.load(mac).login) }))
        XCTAssertEqual(events, ["success"])
        let owner = DirectMacConnections.shared.begin(macID: mac, kind: "synthetic", disconnect: {})
        XCTAssertFalse(draft.forget()); XCTAssertEqual(events, ["success", "error"])
        DirectMacConnections.shared.end(owner)
        XCTAssertTrue(draft.forget()); XCTAssertEqual(events, ["success", "error", "success"])
        XCTAssertNil(try DirectMacAccessStore.load(mac).login)
        XCTAssertTrue(draft.forget()); XCTAssertEqual(events.count, 3, "Already forgotten stays silent")
    }
    func testQuickControlOptionsDeferFeedbackToAcceptanceAndGenericActionsMarkItHandled() {
        withFeedback { _, feedback in
            let controls = CompanionVNCControls(); controls.setValue(feedback, forKey: "interfaceFeedback")
            var received: [AnyHashable: Any]?
            controls.actionHandler = { received = $0 }
            for kind in ["keyboard", "fullscreen", "setTrackpad", "numberRow", "virtualDisplay", "colors-dark", "composeText"] {
                controls.setValue(UIVisualEffectView(), forKey: "panel")
                controls.setValue([["kind": kind]], forKey: "items")
                let button = UIButton(); button.tag = 0
                _ = controls.perform(NSSelectorFromString("chosen:"), with: button)
                XCTAssertEqual(received?["kind"] as? String, kind)
                XCTAssertEqual(received?["interfaceFeedbackHandled"] as? Bool == true, kind == "composeText")
            }
            XCTAssertEqual(feedback.events, ["commit"], "State options have one downstream feedback owner")
        }
    }
    func testOldComposerCompletionCannotAcknowledgeANewerRetry() {
        let draft = DirectTextComposerDraft(macName: "Synthetic", mode: .terminal)
        var completions: [(String?) -> Void] = [], events: [String] = []
        draft.feedback = { events.append($0) }
        draft.configure(available: { true }, send: { _, done in completions.append(done) })
        draft.edit("synthetic"); draft.requestSend(); completions[0]("Synthetic failure")
        draft.requestSend(); completions[0](nil)
        XCTAssertTrue(draft.sending); XCTAssertEqual(events, ["error"])
        completions[1](nil); XCTAssertEqual(events, ["error", "success"])
    }
    func testComposerExpandDockAndAccessibilityMovesTickOnlyOnCommittedChanges() {
        let draft = DirectTextComposerDraft(macName: "Synthetic", mode: .terminal)
        var events: [String] = []
        draft.feedback = { events.append($0) }
        draft.configure(available: { true }, send: { _, _ in })
        let panel = DirectTextComposerPanel(draft: draft); panel.loadViewIfNeeded()
        panel.toggleExpansion(); panel.toggleExpansion(); panel.toggleDock()
        XCTAssertEqual(events, ["selection", "selection", "selection"])
        draft.invalidate(); panel.toggleExpansion(); panel.toggleDock()
        XCTAssertEqual(events.count, 3, "Retired panels cannot acknowledge changes")
    }
    func testComposerDragOnlyTicksOnCommittedEdgeSnap() throws {
        let draft = DirectTextComposerDraft(macName: "Synthetic", mode: .terminal)
        var events: [String] = []
        draft.feedback = { events.append($0) }
        draft.configure(available: { true }, send: { _, _ in })
        let panel = DirectTextComposerPanel(draft: draft)
        try withWindow(panel) {
            panel.view.layoutIfNeeded()
            draft.floatingAnchor = CGPoint(x: 0.5, y: 0.5)
            panel.view.setNeedsLayout(); panel.view.layoutIfNeeded()
            let pan = InteractionPan()
            @MainActor func move(_ phase: UIGestureRecognizer.State, _ x: CGFloat) {
                pan.phase = phase; pan.setTranslation(CGPoint(x: x, y: x), in: panel.view)
                _ = panel.perform(NSSelectorFromString("resize:"), with: pan)
            }
            move(.began, 0); move(.changed, -2000)
            XCTAssertTrue(events.isEmpty, "Dragging remains silent")
            move(.cancelled, -2000); XCTAssertTrue(events.isEmpty)
            XCTAssertEqual(draft.floatingAnchor, CGPoint(x: 0.5, y: 0.5))
            move(.began, 0); move(.changed, -2000); move(.ended, -2000)
            XCTAssertEqual(events, ["selection"])
            XCTAssertEqual(draft.floatingAnchor.y, 0, "The diagonal drag commits at the top edge on both narrow and wide layouts")
        }
    }
    func testTerminalCopyAcknowledgesActualSelectionAndEmptyCopyDoesNotTouchClipboard() throws {
        try withFeedback { defaults, feedback in
            let session = DirectTerminalSession(mac: .init(id: UUID(), name: "Synthetic", addresses: ["synthetic.invalid"]))
            let controller = TerminalController(session: session, customize: {}); defer { session.stop() }
            try withWindow(controller) {
                controller.keyboardBar.keyFeedback = feedback
                let previous = UIPasteboard.general.changeCount
                controller.terminal.copy(nil)
                XCTAssertEqual(UIPasteboard.general.changeCount, previous); XCTAssertTrue(feedback.events.isEmpty)
                controller.terminal.feed(text: "synthetic clipboard fixture\r\n")
                controller.terminal.selectAll(nil); controller.terminal.copy(nil)
                XCTAssertGreaterThan(UIPasteboard.general.changeCount, previous)
                XCTAssertEqual(feedback.events, ["success"])
                controller.terminal.copy(nil); XCTAssertEqual(feedback.events, ["success"])
                defaults.set(false, forKey: CompanionVNCControlsHapticsPreference)
                controller.terminal.selectAll(nil); controller.terminal.copy(nil)
                XCTAssertEqual(feedback.events, ["success"])
            }
        }
    }
    func testTrackpadNativeGeneratorsReuseTheirSurfaceAndRetireWhenDisabled() throws {
        let viewer = CompanionVNCViewer(); viewer.session = CompanionVNCSession(); viewer.loadViewIfNeeded()
        defer { viewer.stop() }
        let overlay = try XCTUnwrap(viewer.value(forKey: "trackpadFeedback") as? UIView)
        overlay.setValue(true, forKey: "active")
        _ = overlay.perform(NSSelectorFromString("prepareHaptics"))
        XCTAssertEqual(overlay.interactions.filter { $0 is UIImpactFeedbackGenerator }.count, 2)
        _ = overlay.perform(NSSelectorFromString("prepareHaptics"))
        XCTAssertEqual(overlay.interactions.filter { $0 is UIImpactFeedbackGenerator }.count, 2)
        overlay.setValue(false, forKey: "hapticsEnabled")
        XCTAssertTrue(overlay.interactions.isEmpty)
        overlay.setValue(true, forKey: "hapticsEnabled")
        _ = overlay.perform(NSSelectorFromString("prepareHaptics"))
        XCTAssertEqual(overlay.interactions.filter { $0 is UIImpactFeedbackGenerator }.count, 2)
    }
    func testNotificationAndDisconnectGeneratorsBindToViewsAndRespectPreference() {
        withFeedback { defaults, _ in
            let view = UIView(), feedback = CompanionVNCInterfaceFeedback(defaults: defaults, view: view)
            defaults.set(false, forKey: CompanionVNCControlsHapticsPreference)
            feedback.feedback("success"); feedback.feedback("error"); feedback.feedback("end")
            XCTAssertTrue(view.interactions.isEmpty)
            defaults.set(true, forKey: CompanionVNCControlsHapticsPreference)
            feedback.feedback("success"); feedback.feedback("error"); feedback.feedback("end"); feedback.feedback("end")
            XCTAssertEqual(view.interactions.filter { $0 is UINotificationFeedbackGenerator }.count, 1)
            XCTAssertEqual(view.interactions.filter { $0 is UIImpactFeedbackGenerator }.count, 1)
        }
    }
}
#endif
