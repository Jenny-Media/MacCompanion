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
    var softwareKeyboard = false, keyboardCurrent = true
    var keyboardHides = 0, keyboardRestores = 0
    var composerReview: (text: String, title: String, available: () -> Bool)?
    var sequenceOwner: String?
    var holdSequenceReplies = false
    var pendingSequenceReplies: [(Bool) -> Void] = []
    var connectionID = UUID().uuidString
    lazy var feedback = CompanionVNCInterfaceFeedback(view: view)
    override func loadView() { view = UIView() }
    override func viewDidLoad() {}
    override func viewWillLayoutSubviews() {}
    override func viewDidLayoutSubviews() {}
    override var controlsFeedback: CompanionVNCInterfaceFeedback { feedback }
    override var controlsEpoch: UInt { epoch }
    override var controlsConnectionID: String { connectionID }
    override func controlsInputAvailable() -> Bool { available }
    override func toggleControlsKeyboard() { keyboardToggles += 1 }
    override func controlsSoftwareKeyboardVisible() -> Bool { softwareKeyboard }
    override func controlsExecutionKeyboardCurrent() -> Bool { keyboardCurrent }
    override func hideControlsExecutionKeyboard() -> Bool { keyboardHides += 1; softwareKeyboard = false; return true }
    override func restoreControlsExecutionKeyboard() { keyboardRestores += 1; softwareKeyboard = true }
    override func showControlsComposer(text: String, title: String, available: @escaping () -> Bool) {
        composerReview = (text, title, available)
    }
    override func sendControlEvents(_ events: [[AnyHashable: Any]], completion: @escaping (Bool) -> Void) -> Bool {
        guard available, accepts else { return false }; self.events += events; completion(true); return true
    }
    override func sendOrdinaryControlEvents(_ events: [[AnyHashable: Any]]) { if available { self.events += events } }
    override func beginControlSequence() -> String? {
        guard available, sequenceOwner == nil else { return nil }
        let id = UUID().uuidString; sequenceOwner = id; return id
    }
    override func sendControlSequenceEvents(_ events: [[AnyHashable: Any]], identifier: String, completion: @escaping (Bool) -> Void) -> Bool {
        guard available, accepts, sequenceOwner == identifier else { return false }
        self.events += events
        if holdSequenceReplies { pendingSequenceReplies.append(completion) } else { completion(true) }
        return true
    }
    override func endControlSequence(_ identifier: String) { if sequenceOwner == identifier { sequenceOwner = nil } }
    override func cancelControlSequence(_ identifier: String) { endControlSequence(identifier) }
    override func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) { shown = nil; completion?() }
    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) { shown = viewControllerToPresent; completion?() }
}

@MainActor final class RemoteMacControlsTests: XCTestCase {
    func testKeyboardRestoresDuringNativeDismissalAnimationAndDoesNotStealFocus() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let owner = UIViewController(); window.rootViewController = owner
        let input = UITextField(frame: .init(x: 12, y: 100, width: 200, height: 44))
        let other = UITextField(frame: .init(x: 12, y: 160, width: 200, height: 44))
        owner.view.addSubview(input); owner.view.addSubview(other); window.makeKeyAndVisible()
        defer { owner.view.endEditing(true); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        XCTAssertTrue(input.becomeFirstResponder())
        for _ in 0..<100 where !TerminalSequenceKeyboard.softwareVisible(in: owner.view, responder: input) { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(TerminalSequenceKeyboard.softwareVisible(in: owner.view, responder: input))
        let embedded = UIViewController(); owner.addChild(embedded); owner.view.addSubview(embedded.view); embedded.didMove(toParent: owner)
        embedded.view.frame = .init(x: 0, y: 0, width: owner.view.bounds.width, height: owner.view.bounds.height / 2)
        input.removeFromSuperview(); embedded.view.addSubview(input); XCTAssertTrue(input.becomeFirstResponder())
        embedded.view.layoutIfNeeded()
        XCTAssertTrue(TerminalSequenceKeyboard.softwareVisible(in: embedded.view, responder: input), "A SwiftUI-sized owner can end above the keyboard; compare in window coordinates")
        input.removeFromSuperview(); owner.view.addSubview(input); XCTAssertTrue(input.becomeFirstResponder())
        embedded.willMove(toParent: nil); embedded.view.removeFromSuperview(); embedded.removeFromParent()
        let keyboard = TerminalSequenceKeyboard(visible: { input.isFirstResponder }, current: { TerminalSequenceKeyboard.presentationCurrent(in: owner, responder: input) },
            hide: { input.resignFirstResponder() }, restore: { _ = input.becomeFirstResponder() })
        keyboard.start(delay: .milliseconds(20))
        // Wait for the hide event, then reverse its animation immediately.
        for _ in 0..<100 where !keyboard.didHide { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(keyboard.didHide); XCTAssertFalse(input.isFirstResponder); keyboard.finish()
        XCTAssertTrue(input.isFirstResponder, "Cancel during native dismissal must reverse the keyboard transition")
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(TerminalSequenceKeyboard.softwareVisible(in: owner.view, responder: input))
        XCTAssertTrue(other.becomeFirstResponder())
        XCTAssertFalse(TerminalSequenceKeyboard.presentationCurrent(in: owner, responder: input))
    }
    func testKeyboardPresentationDelayCancellationAndRetirement() async throws {
        var visible = true, current = true, hides = 0, restores = 0
        func make() -> TerminalSequenceKeyboard {
            .init(visible: { visible }, current: { current }, hide: { hides += 1; visible = false; return true }, restore: { restores += 1; visible = true })
        }
        let quick = make(); quick.start(delay: .milliseconds(40)); quick.finish()
        try await Task.sleep(for: .milliseconds(80)); XCTAssertEqual(hides, 0); XCTAssertEqual(restores, 0)
        let sustained = make(); sustained.start(delay: .milliseconds(30))
        try await Task.sleep(for: .milliseconds(60)); XCTAssertFalse(visible); XCTAssertEqual(hides, 1)
        sustained.finish(); sustained.finish(); XCTAssertTrue(visible); XCTAssertEqual(restores, 1)
        let obsolete = make(); obsolete.start(delay: .milliseconds(30))
        try await Task.sleep(for: .milliseconds(60)); current = false
        obsolete.finish(); XCTAssertFalse(visible); XCTAssertEqual(restores, 1)
        // An old completion must never reopen a keyboard during a newer run.
        current = true; obsolete.finish(); XCTAssertFalse(visible); XCTAssertEqual(restores, 1)
        let initiallyHidden = make(); initiallyHidden.start(delay: .milliseconds(20))
        try await Task.sleep(for: .milliseconds(40)); initiallyHidden.finish(); XCTAssertEqual(hides, 2); XCTAssertEqual(restores, 1)
        visible = true
        let retired = make(); retired.start(delay: .milliseconds(20))
        try await Task.sleep(for: .milliseconds(40)); retired.finish(restoring: false)
        XCTAssertFalse(visible); XCTAssertEqual(restores, 1)
        visible = true
        let changedBeforeHide = make(); changedBeforeHide.start(delay: .milliseconds(30)); current = false
        try await Task.sleep(for: .milliseconds(60)); changedBeforeHide.finish(); XCTAssertEqual(hides, 3)
        current = true; visible = false
        let arrivingKeyboard = make(); arrivingKeyboard.start(delay: .milliseconds(20)); visible = true
        try await Task.sleep(for: .milliseconds(40)); XCTAssertFalse(visible); XCTAssertEqual(hides, 4)
        arrivingKeyboard.finish(); XCTAssertTrue(visible); XCTAssertEqual(restores, 2)
    }
    func testKeyboardPresentationDoesNotRestoreWhenDismissalFailsOrFocusChanges() async throws {
        var visible = true, focused = true, restores = 0
        let failed = TerminalSequenceKeyboard(visible: { visible }, current: { focused }, hide: { false }, restore: { restores += 1 })
        failed.start(delay: .milliseconds(20)); try await Task.sleep(for: .milliseconds(40)); failed.finish(); XCTAssertEqual(restores, 0)
        let focusChanged = TerminalSequenceKeyboard(visible: { visible }, current: { focused }, hide: { visible = false; return true }, restore: { restores += 1 })
        focusChanged.start(delay: .milliseconds(20)); try await Task.sleep(for: .milliseconds(40)); focused = false
        focusChanged.finish(); XCTAssertEqual(restores, 0)
    }
    func testSustainedRemoteRunHidesKeyboardAndCancelRestoresWithoutWaitingInBothModes() async throws {
        let entitlement = try await pro(); defer { entitlement.clearTransactions() }
        for inputOnly in [false, true] {
            var action = TerminalControlAction(title: "Held send", kind: .shortcut)
            action.steps = [.init(character: 97)]
            var profile = TerminalControlsProfile.remoteDefaults
            profile.actions.append(action); profile.pin(action.id, in: .menu, enabled: true); profile.captureRemoteMenu()
            profile.remoteMenus = ["desktop": profile.resolvedMenuPlacements, "trackpad": profile.resolvedMenuPlacements]; profile.remoteMenuMode = "desktop"
            let viewer = RemoteControlsTestViewer(); viewer.inputOnly = inputOnly; viewer.softwareKeyboard = true; viewer.holdSequenceReplies = true
            let host = controls(viewer, data: try JSONEncoder().encode(profile)); defer { host.reset() }
            func run() throws { host.performMenuAction(try XCTUnwrap(host.menuActions().first { $0["title"] as? String == action.title })) }
            try run(); XCTAssertTrue(viewer.softwareKeyboard)
            try await Task.sleep(for: .milliseconds(650)); XCTAssertFalse(viewer.softwareKeyboard); XCTAssertEqual(viewer.keyboardHides, 1)
            let panel = try XCTUnwrap(viewer.children.compactMap { $0 as? TerminalSequenceBannerController }.first)
            panel.rootView.cancel(); XCTAssertTrue(viewer.softwareKeyboard); XCTAssertEqual(viewer.keyboardRestores, 1)
            XCTAssertTrue(host.bar.isUserInteractionEnabled); XCTAssertNil(viewer.sequenceOwner)
            viewer.pendingSequenceReplies[0](true); XCTAssertEqual(viewer.keyboardRestores, 1)
            try run(); try await Task.sleep(for: .milliseconds(650)); XCTAssertFalse(viewer.softwareKeyboard)
            host.reset(); XCTAssertFalse(viewer.softwareKeyboard); XCTAssertEqual(viewer.keyboardRestores, 1)
            viewer.pendingSequenceReplies[1](true); XCTAssertEqual(viewer.keyboardRestores, 1)
        }
    }
    func testExplicitConfirmationAndConnectionSkipApplyInBothRemoteModes() async throws {
        let entitlement = try await pro(); defer { entitlement.clearTransactions() }
        for inputOnly in [false, true] {
            var action = TerminalControlAction(title: "Confirmable", kind: .shortcut)
            action.steps = [.init(kind: .typeText, text: "x")]
            var profile = TerminalControlsProfile.remoteDefaults
            profile.actions.append(action); profile.pin(action.id, in: .menu, enabled: true); profile.captureRemoteMenu()
            profile.remoteMenus = ["desktop": profile.resolvedMenuPlacements, "trackpad": profile.resolvedMenuPlacements]
            profile.remoteMenuMode = "desktop"
            var data = try JSONEncoder().encode(profile)
            let viewer = RemoteControlsTestViewer(); viewer.inputOnly = inputOnly
            let host = RemoteMacControls(viewer: viewer, store: .init(read: { data }, write: { data = $0 }, legacyIDs: { [] }, family: .remoteMac))
            mount(host, in: viewer)
            func run() throws { host.performMenuAction(try XCTUnwrap(host.menuActions().first { $0["title"] as? String == action.title })) }
            try run(); XCTAssertNil(viewer.shown); XCTAssertEqual(viewer.events.count, 2)
            profile.actions[profile.actions.firstIndex { $0.id == action.id }!].confirmBeforeRunning = true
            data = try JSONEncoder().encode(profile); host.reload(); viewer.events = []
            try run()
            let canceled = try XCTUnwrap((viewer.shown as? UIHostingController<TerminalSequenceReview>)?.rootView)
            canceled.cancel(); XCTAssertTrue(viewer.events.isEmpty)
            try run()
            try XCTUnwrap((viewer.shown as? UIHostingController<TerminalSequenceReview>)?.rootView).send(true)
            XCTAssertEqual(viewer.events.count, 2); XCTAssertNil(viewer.shown)
            viewer.epoch += 1; host.reset() // Same transport, brief inactivity or mode retirement.
            try run(); XCTAssertNil(viewer.shown); XCTAssertEqual(viewer.events.count, 4)
            viewer.connectionID = UUID().uuidString; try run()
            let review = try XCTUnwrap((viewer.shown as? UIHostingController<TerminalSequenceReview>)?.rootView)
            review.send(true)
            let index = profile.actions.firstIndex { $0.id == action.id }!
            profile.actions[index].steps![0].text = "changed"
            data = try JSONEncoder().encode(profile); host.reload(); try run()
            XCTAssertNotNil(viewer.shown as? UIHostingController<TerminalSequenceReview>)
            host.reset()
        }
    }
    func testTimedRemoteSequenceCompletesAndResetCancelsSuffixInBothModes() async throws {
        let entitlement = try await pro(); defer { entitlement.clearTransactions() }
        for inputOnly in [false, true] {
            var action = TerminalControlAction(title: "Timed Remote", kind: .shortcut)
            action.steps = [.init(character: 97), .init(kind: .wait, waitMilliseconds: 500), .init(character: 98)]
            var profile = TerminalControlsProfile.remoteDefaults
            profile.actions.append(action); profile.pin(action.id, in: .menu, enabled: true); profile.captureRemoteMenu()
            profile.remoteMenus = ["desktop": profile.resolvedMenuPlacements, "trackpad": profile.resolvedMenuPlacements]
            profile.remoteMenuMode = "desktop"
            XCTAssertTrue(profile.valid)
            let viewer = RemoteControlsTestViewer(); viewer.inputOnly = inputOnly
            let host = controls(viewer, data: try JSONEncoder().encode(profile))
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
            window.rootViewController = viewer; viewer.view.backgroundColor = .systemBackground; window.makeKeyAndVisible()
            defer { host.reset(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
            func run() throws { host.performMenuAction(try XCTUnwrap(host.menuActions().first { $0["title"] as? String == action.title })) }
            try run()
            for _ in 0..<100 where viewer.events.count < 4 || viewer.sequenceOwner != nil { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertEqual(viewer.events.compactMap { ($0["key"] as? NSNumber)?.uint32Value }, [97, 97, 98, 98])
            XCTAssertNil(viewer.sequenceOwner)
            viewer.events = []; try run()
            for _ in 0..<100 where viewer.events.isEmpty { try await Task.sleep(for: .milliseconds(1)) }
            XCTAssertEqual(viewer.events.count, 2)
            XCTAssertNil(viewer.shown, "Progress must not present a modal sheet")
            try await Task.sleep(for: .milliseconds(210)) // The progress surface appears only after the quick-run threshold.
            viewer.view.frame = window.bounds; window.layoutIfNeeded(); viewer.view.layoutIfNeeded()
            XCTAssertGreaterThan(host.bar.bounds.height, 0)
            let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: screenshot); attachment.name = inputOnly ? "trackpad-nonmodal-shortcut-progress" : "desktop-nonmodal-shortcut-progress"; attachment.lifetime = .keepAlways; add(attachment)
            host.reset()
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertEqual(viewer.events.count, 2, "Reset during the wait must retire its suffix in either remote mode")
            XCTAssertNil(viewer.sequenceOwner)
            viewer.events = []; try run()
            for _ in 0..<100 where viewer.events.isEmpty { try await Task.sleep(for: .milliseconds(1)) }
            let banner = try XCTUnwrap(viewer.children.compactMap { $0 as? TerminalSequenceBannerController }.first)
            banner.rootView.cancel()
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertEqual(viewer.events.count, 2, "Explicit Cancel must stop a key-only suffix in either mode")
            XCTAssertNil(viewer.sequenceOwner)
            XCTAssertTrue(viewer.children.compactMap { $0 as? TerminalSequenceBannerController }.isEmpty)
        }
    }
    func testImmediateRemoteShortcutIsExclusiveAndOldCallbacksCannotFinishNewRunInBothModes() async throws {
        let entitlement = try await pro(); defer { entitlement.clearTransactions() }
        for inputOnly in [false, true] {
            var first = TerminalControlAction(title: "First", kind: .shortcut)
            first.steps = [.init(character: 97), .init(character: 98)]
            var second = TerminalControlAction(title: "Second", kind: .shortcut)
            second.steps = [.init(character: 99)]
            var profile = TerminalControlsProfile.remoteDefaults
            profile.actions += [first, second]
            profile.pin(first.id, in: .menu, enabled: true); profile.pin(second.id, in: .menu, enabled: true); profile.captureRemoteMenu()
            profile.remoteMenus = ["desktop": profile.resolvedMenuPlacements, "trackpad": profile.resolvedMenuPlacements]
            profile.remoteMenuMode = "desktop"
            let viewer = RemoteControlsTestViewer(); viewer.inputOnly = inputOnly; viewer.holdSequenceReplies = true
            let host = controls(viewer, data: try JSONEncoder().encode(profile)); defer { host.reset() }
            func run(_ action: TerminalControlAction) throws { host.performMenuAction(try XCTUnwrap(host.menuActions().first { $0["title"] as? String == action.title })) }
            try run(first)
            let originalOwner = try XCTUnwrap(viewer.sequenceOwner)
            let original = try XCTUnwrap(viewer.children.compactMap { $0 as? TerminalSequenceBannerController }.first)
            XCTAssertFalse(original.progressVisible, "Block input immediately without flashing progress")
            XCTAssertFalse(host.bar.isUserInteractionEnabled); XCTAssertTrue(host.bar.accessibilityElementsHidden)
            try run(second)
            XCTAssertEqual(viewer.sequenceOwner, originalOwner); XCTAssertEqual(viewer.pendingSequenceReplies.count, 1)
            original.rootView.cancel()
            XCTAssertNil(viewer.sequenceOwner); XCTAssertTrue(host.bar.isUserInteractionEnabled)
            try run(second)
            let current = try XCTUnwrap(viewer.sequenceOwner)
            XCTAssertNotEqual(current, originalOwner)
            original.rootView.cancel()
            viewer.pendingSequenceReplies[0](true)
            XCTAssertEqual(viewer.sequenceOwner, current, "An old Cancel or reply must not release the newer owner")
            XCTAssertFalse(host.bar.isUserInteractionEnabled)
            viewer.pendingSequenceReplies[1](true)
            XCTAssertNil(viewer.sequenceOwner); XCTAssertTrue(host.bar.isUserInteractionEnabled)
            XCTAssertFalse(host.bar.accessibilityElementsHidden)
            XCTAssertTrue(viewer.children.compactMap { $0 as? TerminalSequenceBannerController }.isEmpty)
        }
    }

    func testRemoteLayoutChangesDoNotCancelExecutionButDefinitionChangesDoInBothModes() async throws {
        let entitlement = try await pro(); defer { entitlement.clearTransactions() }
        for inputOnly in [false, true] {
            var action = TerminalControlAction(title: "Keep running", kind: .shortcut)
            action.steps = [.init(character: 97), .init(kind: .wait, waitMilliseconds: 600), .init(character: 98)]
            var profile = TerminalControlsProfile.remoteDefaults
            profile.actions.append(action); profile.pin(action.id, in: .menu, enabled: true); profile.captureRemoteMenu()
            profile.remoteMenus = ["desktop": profile.resolvedMenuPlacements, "trackpad": profile.resolvedMenuPlacements]; profile.remoteMenuMode = "desktop"
            var data = try JSONEncoder().encode(profile)
            let viewer = RemoteControlsTestViewer(); viewer.inputOnly = inputOnly
            let host = RemoteMacControls(viewer: viewer, store: .init(read: { data }, write: { data = $0 }, legacyIDs: { [] }, family: .remoteMac))
            mount(host, in: viewer)
            defer { host.reset() }
            func run() throws { host.performMenuAction(try XCTUnwrap(host.menuActions().first { $0["title"] as? String == action.title })) }
            try run()
            for _ in 0..<100 where viewer.events.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
            profile.rowsExpanded = true; profile.revision = UUID(); data = try JSONEncoder().encode(profile); host.reload()
            for _ in 0..<200 where viewer.sequenceOwner != nil { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertEqual(viewer.events.compactMap { ($0["key"] as? NSNumber)?.uint32Value }, [97, 97, 98, 98])
            viewer.events = []; try run()
            for _ in 0..<100 where viewer.events.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
            let index = try XCTUnwrap(profile.actions.firstIndex { $0.id == action.id })
            profile.actions[index].steps![2].character = 99; profile.revision = UUID(); data = try JSONEncoder().encode(profile); host.reload()
            for _ in 0..<100 where viewer.sequenceOwner != nil { try await Task.sleep(for: .milliseconds(10)) }
            XCTAssertNil(viewer.sequenceOwner)
            XCTAssertEqual(viewer.events.compactMap { ($0["key"] as? NSNumber)?.uint32Value }, [97, 97], "Changed definitions must still retire the suffix")
        }
    }

    func testDockedProgressRestoresRowsAndInteractionForBothTextSizes() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
            let viewer = RemoteControlsTestViewer()
            viewer.traitOverrides.preferredContentSizeCategory = category
            let host = controls(viewer), bar = try XCTUnwrap(host.bar as? TerminalKeyboardBar)
            let window = UIWindow(windowScene: scene); window.rootViewController = viewer; window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
            viewer.view.backgroundColor = .systemBackground; window.layoutIfNeeded(); viewer.view.layoutIfNeeded()
            var action = TerminalControlAction(title: "Open workspace", kind: .shortcut)
            action.steps = [.init(character: 97), .init(kind: .wait, waitMilliseconds: 10_000), .init(character: 98)]
            let progress = TerminalSequenceProgress(action: action)
            progress.move(to: 1)
            let panel = TerminalSequenceBannerController(progress: progress, cancel: {})
            let floating = UIButton(); floating.alpha = 0.7; viewer.view.addSubview(floating)
            let original = bar.frame
            panel.attach(to: viewer, covering: bar, blocking: [floating])
            viewer.view.layoutIfNeeded()
            XCTAssertTrue(bar.executionActive); XCTAssertFalse(bar.isUserInteractionEnabled); XCTAssertTrue(bar.accessibilityElementsHidden)
            XCTAssertFalse(panel.progressVisible); XCTAssertTrue(panel.children.isEmpty, "Quick shortcuts must not build a hidden SwiftUI graph")
            XCTAssertEqual(bar.frame, original); XCTAssertEqual(floating.alpha, 0.7, accuracy: 0.0001)
            let point = bar.convert(CGPoint(x: bar.bounds.midX, y: bar.bounds.midY), to: viewer.view)
            let hit = try XCTUnwrap(viewer.view.hitTest(point, with: nil))
            XCTAssertTrue(hit === panel.view || hit.isDescendant(of: panel.view), "Even before progress appears, touches cannot reach the rows")
            try await Task.sleep(for: .milliseconds(230)); window.layoutIfNeeded(); viewer.view.layoutIfNeeded()
            XCTAssertTrue(panel.progressVisible)
            floating.isHidden = false // Model a keyboard-driven visibility update.
            XCTAssertEqual(floating.alpha, 0, "Floating controls remain concealed outside the collapsed dock")
            XCTAssertEqual(bar.bounds.height, bar.executionToolbarHeight)
            XCTAssertEqual(panel.view.convert(panel.view.bounds, to: viewer.view), bar.frame, "Progress must occupy the rows, not terminal content above them")
            if category == .large { XCTAssertEqual(bar.bounds.height, 64) }
            let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: screenshot); attachment.name = category == .large ? "docked-progress-toolbar" : "accessible-docked-progress-toolbar"; attachment.lifetime = .keepAlways; add(attachment)
            if category.isAccessibilityCategory {
                // Model limited space above a landscape or floating keyboard.
                viewer.additionalSafeAreaInsets.top = max(0, window.bounds.height - 220)
                viewer.view.layoutIfNeeded(); panel.view.setNeedsLayout(); panel.view.layoutIfNeeded(); viewer.view.layoutIfNeeded()
                XCTAssertGreaterThanOrEqual(bar.frame.minY, viewer.view.safeAreaLayoutGuide.layoutFrame.minY)
                XCTAssertLessThan(bar.executionToolbarHeight, 200)
                viewer.additionalSafeAreaInsets.top = 0
            }
            panel.close(); viewer.view.layoutIfNeeded()
            XCTAssertFalse(bar.executionActive); XCTAssertTrue(bar.isUserInteractionEnabled); XCTAssertFalse(bar.accessibilityElementsHidden)
            XCTAssertEqual(bar.executionToolbarHeight, 0); XCTAssertNil(panel.parent); XCTAssertEqual(bar.frame, original)
            XCTAssertEqual(floating.alpha, 0.7, accuracy: 0.0001); XCTAssertTrue(floating.isUserInteractionEnabled)
            let quick = TerminalSequenceBannerController(progress: progress, cancel: {})
            quick.attach(to: viewer, covering: bar); quick.close()
            try await Task.sleep(for: .milliseconds(200))
            XCTAssertFalse(quick.progressVisible, "A completed fast shortcut must not show late progress")
            XCTAssertTrue(quick.children.isEmpty)
            XCTAssertTrue(bar.isUserInteractionEnabled)
        }
    }

    func testDockedToolbarCollapsesOneTwoAndFourRowsAcrossWidthsAndAppearance() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        func scrolls(in view: UIView) -> [UIScrollView] {
            (view as? UIScrollView).map { [$0] } ?? view.subviews.flatMap { scrolls(in: $0) }
        }
        for count in [1, 2, 4] {
            var profile = TerminalControlsProfile.remoteDefaults; profile.freezeKeyboardLayout()
            profile.keyboardRows = (0..<(count - 1)).map { _ in
                TerminalKeyboardRow(kind: .custom, title: "Synthetic row", items: TerminalRowPreset.numbers.items, expandedOnly: false)
            } + [.init(id: TerminalKeyboardRow.mainID, kind: .main, title: "Main", items: [.control(.keyboard), .control(.ctrl), .control(.keypad)])]
            profile.rowsExpanded = true; XCTAssertTrue(profile.valid)
            let owner = UIViewController(), viewer = RemoteControlsTestViewer()
            let window = UIWindow(windowScene: scene); window.rootViewController = owner; window.makeKeyAndVisible()
            owner.addChild(viewer); owner.view.addSubview(viewer.view); viewer.didMove(toParent: owner)
            viewer.view.frame = .init(x: 0, y: 80, width: min(430, window.bounds.width), height: window.bounds.height - 160)
            let host = controls(viewer, data: try JSONEncoder().encode(profile)), bar = try XCTUnwrap(host.bar as? TerminalKeyboardBar)
            window.layoutIfNeeded(); viewer.view.layoutIfNeeded()
            let restingHeight = bar.bounds.height
            let scrollers = scrolls(in: bar)
            XCTAssertFalse(scrollers.isEmpty)
            for scroll in scrollers { scroll.contentOffset.x = max(0, scroll.contentSize.width - scroll.bounds.width) / 2 }
            let initialOffsets = scrollers.map(\.contentOffset)
            var action = TerminalControlAction(title: "Synthetic row geometry", kind: .shortcut)
            action.steps = [.init(kind: .wait, waitMilliseconds: 1000), .init(character: 97)]
            let panel = TerminalSequenceBannerController(progress: .init(action: action), cancel: {})
            panel.attach(to: viewer, covering: bar, delay: .zero)
            try await Task.sleep(for: .milliseconds(80))
            viewer.view.layoutIfNeeded()
            XCTAssertEqual(scrollers.map(\.contentOffset), initialOffsets, "Presenting the dock must preserve existing manual scrolling")
            for width in [CGFloat(320), min(430, window.bounds.width)] {
                for appearance in [UIUserInterfaceStyle.light, .dark] {
                    owner.overrideUserInterfaceStyle = appearance
                    viewer.view.frame.size.width = width
                    viewer.view.setNeedsLayout(); viewer.view.layoutIfNeeded(); panel.view.setNeedsLayout(); panel.view.layoutIfNeeded(); viewer.view.layoutIfNeeded()
                    XCTAssertEqual(panel.view.convert(panel.view.bounds, to: viewer.view), bar.frame)
                    XCTAssertEqual(bar.bounds.width, width)
                    XCTAssertEqual(bar.bounds.height, 64, "The dock height must be independent of the configured row count")
                    XCTAssertEqual(panel.view.backgroundColor, .systemBackground)
                    XCTAssertFalse(panel.view.subviews.contains { $0 is UIVisualEffectView }, "The dock must have no glass backdrop")
                    XCTAssertTrue(bar.subviews.compactMap { $0 as? UIStackView }.allSatisfy(\.isHidden), "Actual key rows must be visually hidden")
                    let hit = viewer.view.hitTest(bar.center, with: nil)
                    XCTAssertTrue(hit === panel.view || hit?.isDescendant(of: panel.view) == true)
                }
            }
            for scroll in scrollers { scroll.contentOffset.x = max(0, scroll.contentSize.width - scroll.bounds.width) / 2 }
            let offsets = scrollers.map(\.contentOffset)
            panel.close(); viewer.view.layoutIfNeeded()
            XCTAssertTrue(bar.isUserInteractionEnabled); XCTAssertFalse(bar.accessibilityElementsHidden)
            XCTAssertEqual(bar.bounds.height, restingHeight)
            XCTAssertEqual(scrollers.map(\.contentOffset), offsets, "Restoring rows must not reset manual scrolling")
            XCTAssertTrue(bar.subviews.compactMap { $0 as? UIStackView }.allSatisfy { !$0.isHidden })
            window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible()
        }
    }

    private func controls(_ viewer: RemoteControlsTestViewer, data initialData: Data? = nil) -> RemoteMacControls {
        var data = initialData
        let host = RemoteMacControls(viewer: viewer, store: .init(read: { data }, write: { data = $0 }, legacyIDs: { [] }, legacyActions: { [] }, family: .remoteMac))
        mount(host, in: viewer)
        return host
    }
    private func mount(_ host: RemoteMacControls, in viewer: UIViewController) {
        viewer.view.addSubview(host.bar)
        NSLayoutConstraint.activate([host.bar.leadingAnchor.constraint(equalTo: viewer.view.leadingAnchor), host.bar.trailingAnchor.constraint(equalTo: viewer.view.trailingAnchor), host.bar.bottomAnchor.constraint(equalTo: viewer.view.safeAreaLayoutGuide.bottomAnchor)])
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
    func testSavedMenuUsesSharedDefinitionsAndRetiresCapturedSelections() async throws {
        let entitlement = try await pro(); defer { entitlement.clearTransactions() }
        var profile = TerminalControlsProfile.remoteDefaults
        profile.importRemoteMenus(["desktop": [], "trackpad": []])
        var chord = TerminalControlAction(title: "Interrupt", kind: .shortcut, inMenu: false)
        chord.character = 0x63; chord.modifiers = [0xffe3]
        profile.actions.append(chord); profile.pin(chord.id, in: .menu, enabled: true)
        profile.pin(chord.id, in: .menu, enabled: true); profile.captureRemoteMenu()
        let viewer = RemoteControlsTestViewer(), host = controls(viewer, data: try JSONEncoder().encode(profile))
        let items = host.menuActions()
        XCTAssertEqual(items.count, 2)
        XCTAssertNotEqual(items[0]["id"] as? String, items[1]["id"] as? String)
        host.performMenuAction(items[0]); XCTAssertEqual(viewer.events.count, 4)
        viewer.epoch += 1; host.performMenuAction(items[1]); XCTAssertEqual(viewer.events.count, 4)
        host.reset(); host.performMenuAction(items[0]); XCTAssertEqual(viewer.events.count, 4)
        host.performMenuAction(try XCTUnwrap(host.menuActions().first)); XCTAssertEqual(viewer.events.count, 8)
        viewer.available = false
        XCTAssertTrue(host.menuActions().allSatisfy { $0["disabled"] as? Bool == true })
        host.performMenuAction(try XCTUnwrap(host.menuActions().first)); XCTAssertEqual(viewer.events.count, 8)
    }
    func testSharedPanelRoutesAndCapturesInBothRemoteModes() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        for inputOnly in [false, true] {
            let viewer = CompanionVNCViewer(); viewer.preventsAutomaticConnection = true; viewer.inputOnly = inputOnly
            viewer.macName = "Review Mac"; viewer.loadViewIfNeeded(); viewer.session = RemoteAnchorSession()
            if !inputOnly {
                let frame = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800)).image { context in
                    UIColor.systemGray5.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
                    ("Synthetic shared desktop" as NSString).draw(at: CGPoint(x: 60, y: 80), withAttributes: [.font: UIFont.systemFont(ofSize: 32), .foregroundColor: UIColor.label])
                }
                viewer.perform(NSSelectorFromString("frame:"), with: frame)
            }
            (viewer.value(forKey: "login") as? UIView)?.isHidden = true
            _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
            window.rootViewController = viewer; window.makeKeyAndVisible(); window.layoutIfNeeded()
            let overlay = try XCTUnwrap(viewer.value(forKey: "controls") as? CompanionVNCControls)
            func capture(_ suffix: String) {
                window.layoutIfNeeded()
                let snapshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
                let attachment = XCTAttachment(image: snapshot)
                attachment.name = (inputOnly ? "trackpad-" : "screen-sharing-") + suffix; attachment.lifetime = .keepAlways; add(attachment)
            }
            overlay.button.sendActions(for: .touchUpInside); overlay.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(250))
            XCTAssertNil(descendants(overlay).first { $0.accessibilityIdentifier == "customize-quick-actions" })
            let items = try XCTUnwrap(overlay.value(forKey: "items") as? [[String: Any]])
            XCTAssertEqual(items.suffix(6).compactMap { $0["title"] as? String }, ["Keypad", "Shortcuts", "Text", "Customize Controls", "Display", "Session"])
            capture("unified-floating-menu")
            let settings = try XCTUnwrap(descendants(overlay).compactMap { $0 as? UIButton }.first { $0.accessibilityIdentifier == "session-action-customize" })
            settings.sendActions(for: .touchUpInside)
            try await Task.sleep(for: .milliseconds(700))
            let controller = try XCTUnwrap(viewer.presentedViewController as? UIHostingController<TerminalControlsSettings>)
            XCTAssertEqual(controller.sheetPresentationController?.detents.count, 1, "Customization opens at full height")
            XCTAssertEqual(controller.rootView.store.remoteMode, inputOnly ? .trackpad : .desktop)
            capture("shared-customization-hub")
            controller.rootView.close()
            for _ in 0..<60 {
                if viewer.presentedViewController == nil { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            XCTAssertNil(viewer.presentedViewController)
            for (kind, section) in [("savedShortcuts", TerminalSavedItemsSection.shortcuts), ("savedText", .text)] {
                viewer.perform(NSSelectorFromString("performControlAction:"), with: ["kind": kind])
                try await Task.sleep(for: .milliseconds(500))
                let library = try XCTUnwrap(viewer.presentedViewController as? UIHostingController<TerminalSavedItems>)
                XCTAssertEqual(library.rootView.section, section)
                capture(section == .shortcuts ? "shared-shortcuts" : "shared-text")
                viewer.dismiss(animated: false)
            }
            viewer.stop()
        }
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
    func testKeyPreviewIsPassiveCancelsAndKeepsExistingInputAdmission() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let viewer = RemoteControlsTestViewer()
        var profile = TerminalControlsProfile.remoteDefaults
        profile.freezeKeyboardLayout()
        let main = try XCTUnwrap(profile.keyboardRows?.firstIndex { $0.kind == .main })
        profile.keyboardRows![main].placements.insert(.init(item: .key("key-f1")), at: 0)
        let host = controls(viewer, data: try JSONEncoder().encode(profile))
        let window = UIWindow(windowScene: scene); window.rootViewController = viewer; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        viewer.view.backgroundColor = .systemBackground
        let explanation = UILabel()
        explanation.text = "Key preview\nLift to send. Slide away to cancel."
        explanation.numberOfLines = 0; explanation.font = .preferredFont(forTextStyle: .title2)
        explanation.frame = CGRect(x: 28, y: 100, width: window.bounds.width - 56, height: 100)
        viewer.view.addSubview(explanation)
        window.layoutIfNeeded(); viewer.view.layoutIfNeeded()
        let key = try XCTUnwrap(descendants(host.bar).compactMap { $0 as? TerminalKeyPreviewButton }.first { $0.configuration?.title == "F1" })
        key.sendActions(for: .touchDown)
        XCTAssertTrue(key.keyPreviewVisible); XCTAssertTrue(viewer.events.isEmpty)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "keyboard-key-preview"; attachment.lifetime = .keepAlways; add(attachment)
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try image.pngData()?.write(to: folder.appending(path: "keyboard-key-preview.png"))
        key.sendActions(for: .touchDragExit)
        XCTAssertFalse(key.keyPreviewVisible); XCTAssertTrue(viewer.events.isEmpty)
        key.sendActions(for: .touchDragEnter); XCTAssertTrue(key.keyPreviewVisible)
        key.sendActions(for: .touchCancel); XCTAssertFalse(key.keyPreviewVisible); XCTAssertTrue(viewer.events.isEmpty)
        key.sendActions(for: .touchDown); key.sendActions(for: .touchUpInside)
        XCTAssertFalse(key.keyPreviewVisible); XCTAssertEqual(viewer.events.count, 2, "One balanced remote key only")
        viewer.events = []
        key.sendActions(for: .touchDown); host.keyboardBar.showsExtraRows.toggle()
        XCTAssertFalse(key.keyPreviewVisible); XCTAssertTrue(viewer.events.isEmpty)
        viewer.view.layoutIfNeeded()
        key.sendActions(for: .touchDown); XCTAssertTrue(key.keyPreviewVisible)
        let originalFrame = key.frame; key.frame.origin.x += 2
        key.dismissMovedKeyPreview(); XCTAssertFalse(key.keyPreviewVisible); key.frame = originalFrame
        key.sendActions(for: .touchDown); key.isEnabled = false
        XCTAssertFalse(key.keyPreviewVisible); XCTAssertTrue(viewer.events.isEmpty)
        host.refresh(); key.sendActions(for: .touchDown)
        host.keyboardBar.executionActive = true
        XCTAssertFalse(key.keyPreviewVisible); XCTAssertTrue(viewer.events.isEmpty)
        host.keyboardBar.executionActive = false; host.refresh(); key.sendActions(for: .touchDown)
        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        XCTAssertFalse(key.keyPreviewVisible)
        key.sendActions(for: .touchDown); key.removeFromSuperview()
        XCTAssertFalse(key.keyPreviewVisible); XCTAssertTrue(viewer.events.isEmpty)
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
        review.send(false)
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
    func testSavedTextRoutesToEditableComposerAndRetiresCapturedAdmissionInBothModes() async throws {
        let entitlement = try await pro(); defer { entitlement.clearTransactions() }
        for inputOnly in [false, true] {
            var profile = TerminalControlsProfile.remoteDefaults
            let saved = TerminalControlAction(title: "Greeting", kind: .text, text: "synthetic", inMenu: false)
            profile.actions.append(saved); profile.pin(saved.id, in: .menu, enabled: true)
            profile.place(saved.id, in: TerminalKeyboardRow.mainID); profile.captureRemoteMenu()
            let viewer = RemoteControlsTestViewer(); viewer.inputOnly = inputOnly
            let host = controls(viewer, data: try JSONEncoder().encode(profile))
            try savedButton(saved.id, in: host).sendActions(for: .touchUpInside)
            let first = try XCTUnwrap(viewer.composerReview)
            XCTAssertEqual(first.text, saved.text); XCTAssertEqual(first.title, saved.title); XCTAssertTrue(first.available())
            XCTAssertNil(viewer.shown, "Standalone saved text must not open a shortcut review")
            host.reset(); XCTAssertFalse(first.available())
            host.showText()
            let library = try XCTUnwrap((viewer.shown as? UIHostingController<TerminalSavedItems>)?.rootView)
            library.select(saved.id)
            let second = try XCTUnwrap(viewer.composerReview); XCTAssertTrue(second.available())
            viewer.epoch += 1; XCTAssertFalse(second.available())
            host.showKeypad()
            let keypad = try XCTUnwrap((viewer.shown as? UIHostingController<TerminalKeypad>)?.rootView.state)
            keypad.useSaved(saved.id)
            XCTAssertTrue(try XCTUnwrap(viewer.composerReview).available())
            viewer.available = false; XCTAssertFalse(try XCTUnwrap(viewer.composerReview).available())
            XCTAssertTrue(viewer.events.isEmpty)
        }
    }
    func testEveryRemoteModifierAccessibilityActionMatchesItsEffectInBothModes() throws {
        for inputOnly in [false, true] {
            let viewer = RemoteControlsTestViewer(); viewer.inputOnly = inputOnly
            let host = controls(viewer)
            for key in host.modifierButtons {
                let title = try XCTUnwrap(key.accessibilityLabel)
                func action() throws -> UIAccessibilityCustomAction { try XCTUnwrap(key.accessibilityCustomActions?.first) }
                XCTAssertEqual(try action().name, "Keep " + title + " On")
                key.sendActions(for: .touchUpInside)
                XCTAssertEqual(key.accessibilityValue, "Next key")
                let keep = try action(); XCTAssertTrue(try XCTUnwrap(keep.actionHandler)(keep))
                XCTAssertEqual(key.accessibilityValue, "On")
                let turnOff = try action(); XCTAssertEqual(turnOff.name, "Turn " + title + " Off")
                XCTAssertTrue(try XCTUnwrap(turnOff.actionHandler)(turnOff))
                XCTAssertEqual(key.accessibilityValue, "Off")
                XCTAssertEqual(try action().name, "Keep " + title + " On")
            }
            XCTAssertTrue(viewer.events.isEmpty)
        }
    }
}
#endif
