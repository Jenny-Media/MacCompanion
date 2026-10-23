#if os(iOS)
import SwiftUI
import XCTest
import StoreKit
import StoreKitTest
@testable import Mac_Companion

@MainActor private final class RemoteControlsFeedback: CompanionVNCInterfaceFeedback {
    var events: [String] = []
    override var foreground: Bool { true }
    override func emitFeedback(_ kind: String) { events.append(kind) }
}

private final class RemoteAnchorSession: CompanionVNCSession {
    override var connected: Bool { true }
    override var running: Bool { false }
    override func stop() {}
}

@MainActor private final class RemoteControlsTestViewer: CompanionVNCViewer {
    var available = true, accepts = true
    var epoch: UInt = 1
    var events: [[AnyHashable: Any]] = []
    var shown: UIViewController?
    var keyboardToggles = 0
    lazy var feedback = CompanionVNCInterfaceFeedback(view: view)
    override func loadView() { view = UIView() }
    override func viewDidLoad() {}
    override var controlsFeedback: CompanionVNCInterfaceFeedback { feedback }
    override var controlsEpoch: UInt { epoch }
    override func controlsInputAvailable() -> Bool { available }
    override func toggleControlsKeyboard() { keyboardToggles += 1 }
    override func sendControlEvents(_ events: [[AnyHashable: Any]], completion: @escaping (Bool) -> Void) -> Bool {
        guard available, accepts else { return false }; self.events += events; completion(true); return true
    }
    override func sendOrdinaryControlEvents(_ events: [[AnyHashable: Any]]) { if available { self.events += events } }
    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) { shown = nil; completion?() }
    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) { shown = viewControllerToPresent; completion?() }
}

@MainActor final class RemoteMacControlsTests: XCTestCase {
    private func controls(_ viewer: RemoteControlsTestViewer, data initialData: Data? = nil) -> RemoteMacControls {
        var data = initialData
        return .init(viewer: viewer, store: .init(read: { data }, write: { data = $0 }, legacyIDs: { [] }, legacyActions: { [] }, family: .remoteMac))
    }
    private func pro() async throws -> SKTestSession {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LifetimePro", withExtension: "storekit"))
        let store = try SKTestSession(contentsOf: url); store.disableDialogs = true; store.clearTransactions()
        DirectProAccess.shared.start(); _ = try await store.buyProduct(identifier: DirectProAccess.productID)
        for _ in 0..<250 {
            await DirectProAccess.shared.refresh()
            if DirectProAccess.shared.hasPro { return store }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("StoreKit test entitlement unavailable")
        throw NSError(domain: "RemoteMacControlsTests.StoreKit", code: 1)
    }
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    private func savedButton(_ id: UUID, in host: RemoteMacControls) throws -> UIButton {
        try XCTUnwrap(descendants(host.bar).compactMap { $0 as? UIButton }.first {
            $0.accessibilityIdentifier == "terminal-row-action-" + id.uuidString
        })
    }
    func testFloatingButtonTracksReorderedMainRowInBothRemoteModesAndHiddenBarFallback() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        defer { window.endEditing(true); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        for inputOnly in [false, true] {
            let viewer = CompanionVNCViewer(); viewer.preventsAutomaticConnection = true; viewer.inputOnly = inputOnly
            viewer.loadViewIfNeeded(); viewer.session = RemoteAnchorSession()
            (viewer.value(forKey: "login") as? UIView)?.isHidden = true
            _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
            let host = try XCTUnwrap(viewer.value(forKey: "remoteControls") as? RemoteMacControls)
            let overlay = try XCTUnwrap(viewer.value(forKey: "controls") as? CompanionVNCControls)
            let input = try XCTUnwrap(viewer.value(forKey: "input") as? UITextView)
            var profile = TerminalControlsProfile.remoteDefaults
            let numbersID = try XCTUnwrap(profile.addPreset(.numbers, before: nil))
            host.keyboardBar.configure(profile) { _ in XCTFail("Layout must not send input") }
            window.rootViewController = viewer; window.makeKeyAndVisible()
            func settleLayout() {
                window.layoutIfNeeded(); viewer.view.setNeedsLayout(); viewer.view.layoutIfNeeded()
            }
            func assertAnchor(file: StaticString = #filePath, line: UInt = #line) {
                settleLayout()
                XCTAssertTrue(overlay.buttonAnchorView === host.menuAnchor, file: file, line: line)
                let slot = host.menuAnchor.convert(host.menuAnchor.bounds, to: viewer.view)
                let button = overlay.button.convert(overlay.button.bounds, to: viewer.view)
                XCTAssertEqual(button.midX, slot.midX, accuracy: 0.5, file: file, line: line)
                XCTAssertEqual(button.midY, slot.midY, accuracy: 0.5, file: file, line: line)
                XCTAssertGreaterThanOrEqual(button.height, 44, file: file, line: line)
                XCTAssertLessThanOrEqual(button.height, slot.height, file: file, line: line)
            }
            func capture(_ name: String) {
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            }
            assertAnchor()
            let numbers = try XCTUnwrap(descendants(host.bar).first { $0.accessibilityIdentifier == "terminal-extra-row-" + numbersID.uuidString })
            let lowerRow = numbers.convert(numbers.bounds, to: viewer.view)
            let button = overlay.button.convert(overlay.button.bounds, to: viewer.view)
            XCTAssertFalse(button.intersects(lowerRow), "The bottom row must retain all of its keys")
            capture(inputOnly ? "trackpad-menu-above-numbers" : "screen-sharing-menu-above-numbers")
            _ = viewer.perform(NSSelectorFromString("keyboard"))
            try await Task.sleep(for: .milliseconds(500))
            XCTAssertTrue(input.isFirstResponder); assertAnchor()
            capture(inputOnly ? "trackpad-menu-native-keyboard" : "screen-sharing-menu-native-keyboard")
            viewer.fullscreen = true; settleLayout()
            XCTAssertTrue(host.bar.isHidden); XCTAssertNil(overlay.buttonAnchorView)
            let fallback = overlay.button.convert(overlay.button.bounds, to: viewer.view)
            let safe = viewer.view.bounds.inset(by: viewer.view.safeAreaInsets)
            XCTAssertEqual(fallback.maxY, safe.maxY - overlay.bottomInset, accuracy: 0.5)
            viewer.fullscreen = false; assertAnchor()
            _ = viewer.perform(NSSelectorFromString("keyboard"))
            try await Task.sleep(for: .milliseconds(500))
            XCTAssertFalse(input.isFirstResponder); assertAnchor()
            profile.moveRow(TerminalKeyboardRow.mainID, before: nil)
            host.keyboardBar.configure(profile) { _ in XCTFail("Layout must not send input") }
            assertAnchor()
            viewer.stop()
        }
    }
    func testSavedLocalControlsStayUsableWhileRemoteInputIsPaused() async throws {
        let store = try await pro(); defer { store.clearTransactions() }
        let keyboard = TerminalAppAction.keyboard.definition, expand = TerminalAppAction.expandRows.definition
        var chord = TerminalControlAction(title: "Interrupt", kind: .shortcut); chord.character = 0x63; chord.modifiers = [0xffe3]
        let remoteActions = [TerminalControlAction(title: "F1", kind: .key, key: .f1), chord,
            .init(title: "Text", kind: .text, text: "synthetic"), TerminalAppAction.paste.definition,
            TerminalAppAction.controlAlone.definition]
        var profile = TerminalControlsProfile.remoteDefaults
        profile.actions = [keyboard, expand] + remoteActions
        profile.keyboardRows = [
            .init(id: TerminalKeyboardRow.mainID, kind: .main, title: "Main", items: []),
            .init(kind: .custom, title: "Extra", items: [.key("key-left")], expandedOnly: true)]
        for action in profile.actions { profile.place(action.id, in: TerminalKeyboardRow.mainID) }
        profile.freezeKeyboardLayout()
        XCTAssertTrue(profile.valid)
        let viewer = RemoteControlsTestViewer(), host = controls(viewer, data: try JSONEncoder().encode(profile))
        XCTAssertTrue(try savedButton(remoteActions[0].id, in: host).isEnabled)
        viewer.available = false; host.refresh()
        let toggle = try savedButton(keyboard.id, in: host)
        XCTAssertTrue(toggle.isEnabled); XCTAssertEqual(toggle.alpha, 1)
        host.keyboardFocused(true); XCTAssertEqual(toggle.accessibilityLabel, "Hide Keyboard")
        toggle.sendActions(for: .touchUpInside)
        XCTAssertEqual(viewer.keyboardToggles, 1, "The saved local action must reach the viewer despite paused remote input")
        let expandButton = try savedButton(expand.id, in: host)
        XCTAssertTrue(expandButton.isEnabled); XCTAssertFalse(expandButton.isHidden)
        XCTAssertFalse(host.keyboardBar.showsExtraRows)
        expandButton.sendActions(for: .touchUpInside)
        XCTAssertTrue(host.keyboardBar.showsExtraRows)
        let collapse = try savedButton(expand.id, in: host)
        XCTAssertEqual(collapse.accessibilityLabel, "Collapse Rows")
        collapse.sendActions(for: .touchUpInside)
        XCTAssertFalse(host.keyboardBar.showsExtraRows)
        for action in remoteActions {
            let button = try savedButton(action.id, in: host)
            XCTAssertFalse(button.isEnabled, action.title)
            button.sendActions(for: .touchUpInside)
        }
        XCTAssertTrue(viewer.events.isEmpty); XCTAssertNil(viewer.shown, "Paused text and paste actions cannot open an input review")
        viewer.available = true; host.refresh()
        XCTAssertTrue(try savedButton(remoteActions[0].id, in: host).isEnabled)
        try savedButton(remoteActions[0].id, in: host).sendActions(for: .touchUpInside)
        XCTAssertEqual(viewer.events.count, 2)
    }
    func testPinnedAccessoryKeyEmitsOneFeedbackOnlyAfterAcceptedAdmission() async throws {
        let store = try await pro(); defer { store.clearTransactions() }
        let suite = "synthetic-remote-feedback-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let feedback = RemoteControlsFeedback(defaults: defaults)
        var profile = TerminalControlsProfile.remoteDefaults
        let id = profile.pin(try XCTUnwrap(TerminalKeyCatalog.key("key-f1")), in: .keyboard)
        profile.freezeKeyboardLayout()
        let viewer = RemoteControlsTestViewer(), host = controls(viewer, data: try JSONEncoder().encode(profile))
        host.setInterfaceFeedback(feedback)
        let key = try savedButton(id, in: host)
        key.sendActions(for: .touchUpInside)
        XCTAssertEqual(viewer.events.count, 2); XCTAssertEqual(feedback.events, ["key"])
        host.keyboardBar.toggle(.ctrl); feedback.events = []; viewer.events = []
        viewer.accepts = false; key.sendActions(for: .touchUpInside)
        XCTAssertTrue(viewer.events.isEmpty); XCTAssertTrue(feedback.events.isEmpty)
        let ctrl = try XCTUnwrap(host.modifierButtons.first { $0.accessibilityLabel == "Ctrl" })
        XCTAssertEqual(ctrl.accessibilityValue, "Next key", "Rejected saved keys must preserve the armed modifier")
        viewer.accepts = true; key.sendActions(for: .touchUpInside)
        XCTAssertEqual(viewer.events.count, 4); XCTAssertEqual(feedback.events, ["key"])
        XCTAssertEqual(ctrl.accessibilityValue, "Off")
        viewer.events = []; feedback.events = []
        host.showKeypad()
        let keypad = try XCTUnwrap((viewer.shown as? UIHostingController<TerminalKeypad>)?.rootView.state)
        keypad.send("paletteKey-key-f1")
        XCTAssertEqual(viewer.events.count, 2); XCTAssertEqual(feedback.events, ["key"], "Pinned and direct keys should each emit once")
        viewer.events = []; feedback.events = []
        defaults.set(false, forKey: CompanionVNCControlsHapticsPreference)
        key.sendActions(for: .touchUpInside)
        XCTAssertEqual(viewer.events.count, 2); XCTAssertTrue(feedback.events.isEmpty, "The shared haptic preference still applies")
    }
    func testOneShotLockedAndModifierAloneHaveSeparateBalancedBehavior() throws {
        let viewer = RemoteControlsTestViewer(), host = controls(viewer)
        host.keyboardBar.toggle(.ctrl)
        XCTAssertTrue(host.sendModifierAlone(0xffe1))
        XCTAssertTrue(host.sendKey(0x63))
        XCTAssertTrue(host.sendKey(0x64))
        XCTAssertEqual(viewer.events.compactMap { ($0["key"] as? NSNumber)?.uint32Value }, [0xffe1, 0xffe1, 0xffe3, 0x63, 0x63, 0xffe3, 0x64, 0x64])
        viewer.events = []
        host.keyboardBar.toggle(.command, lock: true)
        XCTAssertTrue(host.sendKey(0x63)); XCTAssertTrue(host.sendKey(0x76))
        XCTAssertEqual(viewer.events.filter { ($0["key"] as? NSNumber)?.uint32Value == 0xffeb }.count, 4)
        let command = try XCTUnwrap(host.modifierButtons.first { $0.accessibilityLabel == "Command" })
        XCTAssertEqual(command.accessibilityValue, "On")
        host.keyboardBar.toggle(.command)
        XCTAssertEqual(command.accessibilityValue, "Off")
        XCTAssertFalse(host.sendModifierAlone(0x61), "An ordinary key cannot be disguised as a modifier-alone action")
    }
    func testRejectedAdmissionPreservesArmedStateAndResetClearsIt() throws {
        let viewer = RemoteControlsTestViewer(), host = controls(viewer)
        host.keyboardBar.toggle(.ctrl); viewer.accepts = false
        XCTAssertFalse(host.sendKey(0x63)); XCTAssertTrue(viewer.events.isEmpty)
        let ctrl = try XCTUnwrap(host.modifierButtons.first { $0.accessibilityLabel == "Ctrl" })
        XCTAssertEqual(ctrl.accessibilityValue, "Next key")
        host.reset(); XCTAssertEqual(ctrl.accessibilityValue, "Off")
    }
    func testHeldModifiersApplyToEveryCommittedCharacter() {
        let viewer = RemoteControlsTestViewer(), host = controls(viewer)
        host.keyboardBar.toggle(.alt, lock: true); host.typeText("ab")
        XCTAssertEqual(viewer.events.filter { ($0["key"] as? NSNumber)?.uint32Value == 0xffe9 }.count, 4)
    }
    func testRetainedKeypadCallbackCannotReviveAfterEpochChangesOrReset() throws {
        let viewer = RemoteControlsTestViewer(), host = controls(viewer)
        host.showKeypad()
        let state = try XCTUnwrap((viewer.shown as? UIHostingController<TerminalKeypad>)?.rootView.state)
        viewer.available = false; viewer.epoch += 1; viewer.available = true
        state.send("paletteKey-key-f1"); state.alone(.controlAlone)
        XCTAssertTrue(viewer.events.isEmpty)
        state.ready = false; host.refresh(); XCTAssertFalse(state.ready, "A dismissed keypad must not revive on a bar refresh")
        host.reset(); XCTAssertFalse(state.ready)
        state.send("paletteKey-key-f1"); XCTAssertTrue(viewer.events.isEmpty)
    }
    func testRetainedTextReviewCannotSendAfterBriefInterruptionWithSameTransportEpoch() throws {
        let viewer = RemoteControlsTestViewer(), host = controls(viewer)
        let oldClipboard = UIPasteboard.general.string
        defer { UIPasteboard.general.string = oldClipboard }
        UIPasteboard.general.string = "synthetic"
        host.showKeypad()
        let keypad = try XCTUnwrap((viewer.shown as? UIHostingController<TerminalKeypad>)?.rootView.state)
        keypad.send("paste")
        let review = try XCTUnwrap((viewer.shown as? UIHostingController<TerminalSequenceReview>)?.rootView)
        XCTAssertTrue(viewer.events.isEmpty, "Reviewing text cannot send any prefix")
        host.reset()
        review.send()
        XCTAssertTrue(viewer.events.isEmpty, "A brief inactive transition retires the local callback even if the VNC transport epoch stays unchanged")
    }
    func testLiveAndEditingBarsShareKeycapsAndMinimumTargetSize() throws {
        let viewer = RemoteControlsTestViewer(), host = controls(viewer)
        let preview = TerminalKeyboardBar(terminal: nil, preferences: .init())
        preview.editingPreview = true; preview.configure(.remoteDefaults) { _ in XCTFail("Preview must be passive") }
        for bar in [host.keyboardBar, preview] {
            bar.frame = .init(x: 0, y: 0, width: 430, height: bar.height); bar.layoutIfNeeded()
            let command = try XCTUnwrap(bar.renderedModifiers.first { $0.accessibilityLabel == "Command" })
            XCTAssertGreaterThanOrEqual(command.bounds.height, 44)
            XCTAssertGreaterThanOrEqual(command.bounds.width, 44)
            XCTAssertEqual(command.configuration?.baseForegroundColor, .systemBlue)
        }
    }
}
#endif
