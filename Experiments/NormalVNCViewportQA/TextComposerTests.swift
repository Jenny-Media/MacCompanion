import XCTest
import UIKit
@testable import Mac_Companion

@MainActor private final class ComposerAdmissionProbe: NSObject {
    @objc var interruptionHandler: (() -> Void)?
    @objc var sending: Bool { false }
    var available: (() -> Bool)?
    var send: ((String, @escaping (String?) -> Void) -> Void)?
    @objc func invalidate() { available = nil; send = nil }
    @objc func present(from controller: UIViewController, available: @escaping () -> Bool,
                       send: @escaping (String, @escaping (String?) -> Void) -> Void) {
        self.available = available; self.send = send
    }
}

@MainActor private final class ComposerPanProbe: UIPanGestureRecognizer {
    var simulatedState: UIGestureRecognizer.State = .possible
    override var state: UIGestureRecognizer.State {
        get { simulatedState }
        set { simulatedState = newValue }
    }
}

@MainActor final class TextComposerTests: XCTestCase {

    func testInlineFooterNativeEditorGrowsAndUsesFullWidthWithSafeActions() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let root = UIViewController(); window.rootViewController = root; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let draft = DirectTextComposerDraft(macName: "Synthetic", mode: .desktop)
        draft.configure(available: { true }, send: { _, _ in XCTFail("Layout must not send") })
        let panel = DirectTextComposerPanel(draft: draft)
        root.addChild(panel); root.view.addSubview(panel.view); panel.didMove(toParent: root)
        panel.view.frame = root.view.bounds; panel.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        panel.simulatedKeyboardFrame = .zero
        try await Task.sleep(for: .milliseconds(300)); panel.view.endEditing(true)
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        let editor = try XCTUnwrap(descendants(panel.view).compactMap { $0 as? UITextView }.first)
        let grabber = try XCTUnwrap(descendants(panel.view).first { $0.accessibilityIdentifier == "compose-grabber" })
        draft.edit("alpha"); try await Task.sleep(for: .milliseconds(80)); panel.view.layoutIfNeeded()
        let shortHeight = panel.panelFrame.height
        draft.edit("one\ntwo\nthree\nfour\nfive\nsix\nseven\neight")
        try await Task.sleep(for: .milliseconds(100)); panel.view.layoutIfNeeded()
        XCTAssertGreaterThan(panel.panelFrame.height, shortHeight)
        XCTAssertLessThan(panel.panelFrame.height, 200)
        editor.selectedRange = NSRange(location: 2, length: 3)
        for hasIssue in [false, true, false] {
            draft.issue = hasIssue ? "Synthetic delivery error" : nil
            try await Task.sleep(for: .milliseconds(80)); panel.view.layoutIfNeeded()
            let card = panel.panelFrame, close = panel.closeActionFrame, send = panel.deliveryActionFrame
            let text = editor.convert(editor.bounds, to: panel.view), grip = grabber.convert(grabber.bounds, to: panel.view)
            XCTAssertGreaterThanOrEqual(text.width, card.width - 24)
            XCTAssertEqual(close.midY, send.midY, accuracy: 1); XCTAssertEqual(grip.midY, send.midY, accuracy: 1)
            XCTAssertLessThan(close.minX, grip.minX); XCTAssertLessThan(grip.maxX, send.minX + 1)
            XCTAssertFalse(text.intersects(close)); XCTAssertFalse(text.intersects(send)); XCTAssertFalse(text.intersects(grip))
            XCTAssertFalse(close.intersects(grip)); XCTAssertFalse(grip.intersects(send))
            XCTAssertGreaterThanOrEqual(grip.height, 44); XCTAssertGreaterThanOrEqual(grip.width, 44)
            XCTAssertEqual(editor.selectedRange, NSRange(location: 2, length: 3))
            XCTAssertTrue(descendants(panel.view).contains { $0 === editor })
        }
    }

    func testSimulatedTabletKeyboardLayoutsRenderReadableEditorAndActions() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene), root = UIViewController()
        window.rootViewController = root; window.makeKeyAndVisible()
        defer { root.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let draft = DirectTextComposerDraft(macName: "Synthetic", mode: .desktop)
        draft.configure(available: { true }, send: { _, _ in })
        let panel = DirectTextComposerPanel(draft: draft)
        root.addChild(panel); root.view.addSubview(panel.view); panel.didMove(toParent: root)
        panel.view.translatesAutoresizingMaskIntoConstraints = false
        let width = panel.view.widthAnchor.constraint(equalToConstant: 1024)
        let height = panel.view.heightAnchor.constraint(equalToConstant: 1280)
        NSLayoutConstraint.activate([width, height, panel.view.topAnchor.constraint(equalTo: root.view.safeAreaLayoutGuide.topAnchor),
            panel.view.leadingAnchor.constraint(equalTo: root.view.leadingAnchor)])
        try await Task.sleep(for: .milliseconds(400)); panel.view.endEditing(true)
        func descendants(_ v: UIView) -> [UIView] { [v] + v.subviews.flatMap(descendants) }
        let editor = try XCTUnwrap(descendants(panel.view).compactMap { $0 as? UITextView }.first)
        draft.edit("synthetic tablet draft"); try await Task.sleep(for: .milliseconds(100))
        editor.selectedRange = NSRange(location: 3, length: 4); let selection = editor.selectedRange
        for size in [CGSize(width: 1024, height: 1280), CGSize(width: 1366, height: 988)] {
            width.constant = size.width; height.constant = size.height; root.view.layoutIfNeeded()
            for keyboard in [CGRect(x: 0, y: size.height - 314, width: size.width, height: 314),
                             CGRect(x: size.width / 2 - 160, y: 60, width: 320, height: 260),
                             CGRect(x: 0, y: 60, width: size.width, height: 280),
                             CGRect(x: size.width / 2 - 160, y: 400, width: 320, height: 260)] {
                panel.simulatedKeyboardFrame = keyboard
                for action in 0..<4 {
                    if action == 1 || action == 3 { panel.toggleDock() }
                    if action == 2 { panel.toggleExpansion() }
                    try await Task.sleep(for: .milliseconds(300)); panel.view.setNeedsLayout(); panel.view.layoutIfNeeded()
                    let card = panel.panelFrame, send = panel.deliveryActionFrame
                    XCTAssertFalse(card.intersects(keyboard), "Rendered native card must avoid the controlled keyboard viewport")
                    XCTAssertGreaterThan(editor.bounds.height, 35)
                    XCTAssertTrue(card.contains(send)); XCTAssertGreaterThan(send.width, 35)
                    XCTAssertTrue(panel.view.bounds.contains(card))
                    XCTAssertTrue(descendants(panel.view).contains(where: { $0 === editor }))
                    XCTAssertEqual(editor.selectedRange, selection); XCTAssertEqual(draft.text, "synthetic tablet draft")
                }
                draft.expanded = false
            }
        }
    }
    func testNativeGlassBubblePreservesReadableEditorAndActionsAcrossAppearance() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene), root = UIViewController()
        root.view.backgroundColor = .systemOrange
        window.rootViewController = root; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let draft = DirectTextComposerDraft(macName: "Synthetic", mode: .desktop)
        draft.configure(available: { true }, send: { _, _ in XCTFail("Appearance must not send") })
        let panel = DirectTextComposerPanel(draft: draft)
        root.addChild(panel); root.view.addSubview(panel.view); panel.didMove(toParent: root)
        panel.view.frame = root.view.bounds; panel.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !descendants(panel.view).contains(where: { ($0 as? UITextView)?.isFirstResponder == true }), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let editor = try XCTUnwrap(descendants(panel.view).compactMap { $0 as? UITextView }.first)
        XCTAssertTrue(editor.isFirstResponder)
        draft.edit("synthetic glass draft"); try await Task.sleep(for: .milliseconds(80))
        editor.selectedRange = NSRange(location: 3, length: 4); let selection = editor.selectedRange
        let material = try XCTUnwrap(descendants(panel.view).first(where: { $0.accessibilityIdentifier == "compose-bubble" }) as? UIVisualEffectView)
        if #available(iOS 26.0, *) {
            let glass = try XCTUnwrap(material.effect as? UIGlassEffect)
            XCTAssertFalse(glass.isInteractive, "Typing must not energize a second interactive glass layer")
        } else { XCTAssertTrue(material.effect is UIBlurEffect) }
        for style in [UIUserInterfaceStyle.light, .dark] {
            panel.overrideUserInterfaceStyle = style
            for contrast in [UIAccessibilityContrast.normal, .high] {
                panel.traitOverrides.accessibilityContrast = contrast
                root.view.backgroundColor = contrast == .high ? .systemTeal : .systemOrange
                try await Task.sleep(for: .milliseconds(100)); panel.view.setNeedsLayout(); panel.view.layoutIfNeeded()
                XCTAssertEqual(editor.traitCollection.userInterfaceStyle, style)
                XCTAssertTrue(descendants(panel.view).contains(where: { $0 === editor }))
                XCTAssertEqual(draft.text, "synthetic glass draft"); XCTAssertEqual(editor.selectedRange, selection)
                XCTAssertTrue(editor.isFirstResponder); XCTAssertGreaterThan(editor.bounds.height, 35)
                XCTAssertTrue(panel.panelFrame.contains(panel.closeActionFrame)); XCTAssertTrue(panel.panelFrame.contains(panel.deliveryActionFrame))
                XCTAssertGreaterThanOrEqual(panel.closeActionFrame.width, 44); XCTAssertGreaterThanOrEqual(panel.deliveryActionFrame.width, 44)
                XCTAssertFalse(panel.closeActionFrame.intersects(panel.deliveryActionFrame))
                let capture = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) })
                capture.name = "synthetic-native-glass-" + (style == .dark ? "dark" : "light") + (contrast == .high ? "-high-contrast" : "")
                capture.lifetime = .keepAlways; add(capture)
            }
        }
    }
    func testTextBubbleHasOnlyDirectCloseAndSendWithSafeAccessibleBounds() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene), root = UIViewController()
        window.rootViewController = root; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let draft = DirectTextComposerDraft(macName: "Synthetic", mode: .desktop)
        draft.configure(available: { true }, send: { _, _ in XCTFail("Layout must not send") })
        let panel = DirectTextComposerPanel(draft: draft)
        root.addChild(panel); root.view.addSubview(panel.view); panel.didMove(toParent: root)
        panel.view.translatesAutoresizingMaskIntoConstraints = false
        let width = panel.view.widthAnchor.constraint(equalToConstant: 390), height = panel.view.heightAnchor.constraint(equalToConstant: 800)
        NSLayoutConstraint.activate([width, height, panel.view.topAnchor.constraint(equalTo: root.view.topAnchor), panel.view.leadingAnchor.constraint(equalTo: root.view.leadingAnchor)])
        try await Task.sleep(for: .milliseconds(400)); panel.view.endEditing(true)
        func descendants(_ v: UIView) -> [UIView] { [v] + v.subviews.flatMap(descendants) }
        let editor = try XCTUnwrap(descendants(panel.view).compactMap { $0 as? UITextView }.first)
        draft.edit("synthetic bubble draft"); try await Task.sleep(for: .milliseconds(80))
        editor.selectedRange = NSRange(location: 2, length: 3); let selection = editor.selectedRange
        for large in [false, true] {
            panel.traitOverrides.preferredContentSizeCategory = large ? .accessibilityExtraExtraExtraLarge : .large
            for size in [CGSize(width: 390, height: 800), CGSize(width: 320, height: 180), CGSize(width: 844, height: 200)] {
                width.constant = size.width; height.constant = size.height; root.view.layoutIfNeeded()
                panel.simulatedKeyboardFrame = .zero
                for issue in [false, true] {
                    draft.issue = issue ? "Synthetic delivery error" : nil
                    try await Task.sleep(for: .milliseconds(120)); panel.view.setNeedsLayout(); panel.view.layoutIfNeeded()
                    let card = panel.panelFrame, close = panel.closeActionFrame, send = panel.deliveryActionFrame
                    XCTAssertTrue(card.contains(close)); XCTAssertTrue(card.contains(send))
                    XCTAssertGreaterThanOrEqual(close.width, 44); XCTAssertGreaterThanOrEqual(close.height, 44)
                    XCTAssertGreaterThanOrEqual(send.width, 44); XCTAssertGreaterThanOrEqual(send.height, 44)
                    XCTAssertFalse(close.intersects(send)); XCTAssertFalse(editor.convert(editor.bounds, to: panel.view).intersects(send))
                    XCTAssertGreaterThan(editor.bounds.width, 80); XCTAssertGreaterThan(editor.bounds.height, 35)
                    XCTAssertTrue(descendants(panel.view).contains(where: { $0 === editor })); XCTAssertEqual(editor.selectedRange, selection)
                    XCTAssertFalse(descendants(panel.view).contains { ["compose-expand", "compose-dock", "compose-more", "compose-discard", "compose-destination"].contains($0.accessibilityIdentifier ?? "") })
                    if !large { XCTAssertLessThanOrEqual(card.width, 284); XCTAssertLessThanOrEqual(card.height, 156) }
                }
            }
        }
    }
    func testUndockedGuideUsesReadableFreeAreasAndTracksAllKeyboardModes() {
        let draft = DirectTextComposerDraft(macName: "Synthetic", mode: .desktop)
        draft.configure(available: { true }, send: { _, _ in })
        let panel = DirectTextComposerPanel(draft: draft); panel.loadViewIfNeeded()
        let guide = panel.view.keyboardLayoutGuide
        XCTAssertTrue(guide.followsUndockedKeyboard)
        let safe = CGRect(x: 0, y: 24, width: 1024, height: 1250)
        for keyboard in [CGRect(x: 0, y: 960, width: 1024, height: 314),
                         CGRect(x: 350, y: 60, width: 320, height: 260),
                         CGRect(x: 0, y: 100, width: 1024, height: 280),
                         CGRect(x: 350, y: 440, width: 320, height: 260)] {
            let area = DirectComposerPlacement.area(safe: safe, keyboard: keyboard)
            let card = DirectComposerPlacement.frame(area: area, size: CGSize(width: 420, height: 324), anchor: CGPoint(x: 0.5, y: 1))
            XCTAssertFalse(card.intersects(keyboard))
            XCTAssertGreaterThanOrEqual(card.height, 180)
            XCTAssertGreaterThanOrEqual(card.minY, safe.minY); XCTAssertLessThanOrEqual(card.maxY, safe.maxY)
            let docked = DirectComposerPlacement.frame(area: area, size: card.size, anchor: DirectComposerPlacement.dockedAnchor(area: area, keyboard: keyboard))
            XCTAssertFalse(docked.intersects(keyboard))
        }
    }
    func testNarrowCompactComposerKeepsInvalidAndErrorActionsInsideCard() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene), root = UIViewController()
        window.rootViewController = root; window.makeKeyAndVisible()
        defer { root.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let draft = DirectTextComposerDraft(macName: "Synthetic", mode: .desktop)
        draft.configure(available: { true }, send: { _, _ in })
        let panel = DirectTextComposerPanel(draft: draft)
        root.addChild(panel); root.view.addSubview(panel.view); panel.didMove(toParent: root)
        panel.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([panel.view.widthAnchor.constraint(equalToConstant: 320),
            panel.view.heightAnchor.constraint(equalToConstant: 220),
            panel.view.topAnchor.constraint(equalTo: root.view.safeAreaLayoutGuide.topAnchor, constant: 8),
            panel.view.centerXAnchor.constraint(equalTo: root.view.centerXAnchor)])
        try await Task.sleep(for: .milliseconds(400))
        for invalid in [true, false] {
            draft.edit(invalid ? String(repeating: "x", count: 257) : "synthetic draft")
            if !invalid { draft.issue = "Synthetic delivery failure" }
            try await Task.sleep(for: .milliseconds(200)); panel.view.setNeedsLayout(); panel.view.layoutIfNeeded()
            XCTAssertTrue(draft.compactLayout)
            let bounds = panel.panelFrame, send = panel.deliveryActionFrame
            XCTAssertGreaterThan(send.width, 35)
            XCTAssertGreaterThanOrEqual(send.minX, bounds.minX)
            XCTAssertLessThanOrEqual(send.maxX, bounds.maxX, "Send must remain in the actual narrow card, including invalid/error states")
            XCTAssertLessThanOrEqual(send.maxY, bounds.maxY)
        }
    }
    func testFloatingPlacementSnapsAndReclampsForKeyboardAndTablet() {
        let phone = DirectComposerPlacement.area(safe: CGRect(x: 0, y: 59, width: 440, height: 860), keyboardTop: 600)
        let size = CGSize(width: 350, height: 324)
        let anchor = DirectComposerPlacement.anchor(origin: CGPoint(x: -50, y: 400), area: phone, size: size, snap: true)
        XCTAssertEqual(anchor, CGPoint(x: 0, y: 1))
        let frame = DirectComposerPlacement.frame(area: phone, size: size, anchor: anchor)
        XCTAssertEqual(frame.minX, phone.minX); XCTAssertEqual(frame.maxY, 592)
        let near = DirectComposerPlacement.anchor(origin: CGPoint(x: phone.minX + 15, y: phone.minY + 19), area: phone, size: size, snap: true)
        XCTAssertEqual(near, .zero)
        let interior = DirectComposerPlacement.anchor(origin: CGPoint(x: phone.minX + 34, y: phone.minY + 40), area: phone, size: size, snap: true)
        XCTAssertGreaterThan(interior.x, 0); XCTAssertLessThan(interior.x, 1)
        let tight = DirectComposerPlacement.anchor(origin: CGPoint(x: phone.midX - 390 / 2, y: phone.minY + 40), area: phone, size: CGSize(width: 390, height: 324), snap: true)
        XCTAssertEqual(tight.x, 0.5, accuracy: 0.01, "Vertical dragging must not force a horizontal edge snap in narrow layouts")
        for safe in [CGRect(x: 59, y: 0, width: 780, height: 400), CGRect(x: 0, y: 24, width: 1024, height: 1300)] {
            let area = DirectComposerPlacement.area(safe: safe, keyboardTop: safe.height * 0.6)
            let resized = DirectComposerPlacement.frame(area: area, size: size, anchor: anchor)
            XCTAssertGreaterThanOrEqual(resized.minX, area.minX); XCTAssertLessThanOrEqual(resized.maxX, area.maxX)
            XCTAssertGreaterThanOrEqual(resized.minY, area.minY); XCTAssertEqual(resized.maxY, area.maxY)
        }
    }
    func testDockAndFloatRetainSelectionAndKeyboardWithCanceledDrag() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene), root = UIViewController()
        window.rootViewController = root; window.makeKeyAndVisible()
        defer { root.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let draft = DirectTextComposerDraft(macName: "Synthetic", mode: .terminal)
        draft.configure(available: { true }, send: { _, _ in })
        let panel = DirectTextComposerPanel(draft: draft); panel.modalPresentationStyle = .overFullScreen
        root.present(panel, animated: false); try await Task.sleep(for: .milliseconds(600))
        func descendants(_ v: UIView) -> [UIView] { [v] + v.subviews.flatMap(descendants) }
        let editor = try XCTUnwrap(descendants(panel.view).compactMap { $0 as? UITextView }.first); editor.becomeFirstResponder()
        draft.edit("synthetic selection"); try await Task.sleep(for: .milliseconds(200)); editor.selectedRange = NSRange(location: 3, length: 4)
        let selected = editor.selectedRange
        let anchor = CGPoint(x: 0, y: 0); draft.floatingAnchor = anchor
        panel.toggleDock(); try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(draft.docked); XCTAssertTrue(editor.isFirstResponder); XCTAssertEqual(editor.selectedRange, selected)
        panel.toggleExpansion(); try await Task.sleep(for: .milliseconds(300))
        panel.toggleDock(); try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(draft.docked); XCTAssertFalse(draft.expanded); XCTAssertEqual(draft.floatingAnchor, anchor)
        XCTAssertTrue(editor.isFirstResponder); XCTAssertEqual(editor.selectedRange, selected); XCTAssertEqual(draft.text, "synthetic selection")
        let pan = ComposerPanProbe(); pan.simulatedState = .began; panel.perform(NSSelectorFromString("resize:"), with: pan)
        pan.setTranslation(CGPoint(x: 100, y: 50), in: panel.view); pan.simulatedState = .changed
        panel.perform(NSSelectorFromString("resize:"), with: pan)
        pan.simulatedState = .cancelled; panel.perform(NSSelectorFromString("resize:"), with: pan)
        XCTAssertEqual(draft.floatingAnchor, anchor); XCTAssertEqual(draft.text, "synthetic selection")
        draft.requestSend(); XCTAssertTrue(draft.sending)
        panel.toggleDock(); panel.toggleExpansion()
        XCTAssertFalse(draft.docked); XCTAssertFalse(draft.expanded)
    }
    func testRetiredFloatingGestureCannotRestorePlacement() {
        let draft = DirectTextComposerDraft(macName: "Synthetic", mode: .desktop)
        draft.configure(available: { true }, send: { _, _ in })
        let panel = DirectTextComposerPanel(draft: draft); panel.loadViewIfNeeded()
        draft.floatingAnchor = .zero
        let pan = ComposerPanProbe(); pan.simulatedState = .began; panel.perform(NSSelectorFromString("resize:"), with: pan)
        draft.invalidate(); draft.configure(available: { true }, send: { _, _ in }); pan.simulatedState = .cancelled; panel.perform(NSSelectorFromString("resize:"), with: pan)
        XCTAssertEqual(draft.floatingAnchor, CGPoint(x: 0.5, y: 1)); XCTAssertFalse(draft.docked); XCTAssertTrue(draft.active)
        panel.toggleDock(); panel.toggleExpansion(); XCTAssertFalse(draft.docked); XCTAssertFalse(draft.expanded)
    }
    func testTrackpadNativeControlsExposeComposeBeforeAndAfterModeChanges() throws {
        let viewer = CompanionVNCViewer(); viewer.loadViewIfNeeded()
        let controls = try XCTUnwrap(viewer.value(forKey: "controls") as? CompanionVNCControls)
        for onlyInput in [false, true, false, true] {
            controls.close(); viewer.inputOnly = onlyInput
            controls.perform(NSSelectorFromString("open"))
            let choices = try XCTUnwrap(controls.value(forKey: "choices") as? [UIButton])
            let compose = try XCTUnwrap(choices.first { $0.accessibilityIdentifier == "session-action-composeText" })
            XCTAssertTrue(compose.isEnabled)
            XCTAssertEqual(choices.first?.accessibilityIdentifier, "session-action-composeText")
            let expected = (onlyInput ? DirectControlMode.trackpad : .desktop).defaults.map { $0.kind.rawValue }
            XCTAssertEqual(controls.quickActions.compactMap { $0["kind"] as? String }, expected)
            XCTAssertEqual(expected.contains("mode"), !onlyInput)
        }
        controls.close()
    }
    func testTrackpadComposerQuickActionPresentsWithoutDesktopPixelsAndSendsOnlyOnRequest() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let viewer = CompanionVNCViewer(); viewer.inputOnly = true; viewer.macName = "Synthetic Mac"
        window.rootViewController = viewer; window.makeKeyAndVisible(); viewer.loadViewIfNeeded()
        let owner = viewer.session
        owner.inputOnly = true
        for key in ["running", "inputReady", "established"] { owner.setValue(true, forKey: key) }
        defer {
            (viewer.value(forKey: "textComposer") as? DirectTextComposer)?.invalidate()
            owner.setValue(false, forKey: "running")
            window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible()
        }
        XCTAssertNil(viewer.value(forKey: "lastFramebuffer")); XCTAssertTrue(owner.composedTextReady)
        let controls = try XCTUnwrap(viewer.value(forKey: "controls") as? CompanionVNCControls)
        controls.perform(NSSelectorFromString("open"))
        let choices = try XCTUnwrap(controls.value(forKey: "choices") as? [UIButton])
        let compose = try XCTUnwrap(choices.first { $0.accessibilityIdentifier == "session-action-composeText" })
        compose.sendActions(for: .touchUpInside)
        try await Task.sleep(for: .milliseconds(350))
        let composer = try XCTUnwrap(viewer.value(forKey: "textComposer") as? DirectTextComposer)
        XCTAssertTrue(composer.draft.active); XCTAssertEqual(composer.draft.mode, .trackpad)
        XCTAssertNotNil(viewer.presentedViewController)
        XCTAssertEqual((owner.value(forKey: "events") as? [NSDictionary])?.count, 0)
        composer.draft.edit("a"); composer.draft.requestSend()
        XCTAssertEqual((owner.value(forKey: "events") as? [NSDictionary])?.count, 2)
    }
    func testCustomizedTrackpadProfileCanAddFreeComposeWithoutReplacingOtherChoices() throws {
        let right = VNCQuickAction(title: "My Right Click", kind: .rightClick)
        var profile = [right]
        XCTAssertEqual(DirectControlMode.trackpad.upgradingUntouchedDefaults(profile), [right])
        let compose = try XCTUnwrap(DirectQuickActionEditing.standards(.trackpad).first { $0.kind == .composeText })
        XCTAssertNotNil(DirectQuickActionEditing.add(compose, to: &profile, mode: .trackpad))
        XCTAssertEqual(profile.first, right); XCTAssertEqual(profile.last?.kind, .composeText)
        XCTAssertTrue(DirectQuickActionEditing.canSave(profile, mode: .trackpad, hasPro: false))
    }
    func testComposeQuickActionUpgradesOnlyUntouchedDefaultsInEveryIOSMode() {
        for mode in DirectControlMode.allCases {
            XCTAssertEqual(mode.defaults.first?.kind, .composeText)
            XCTAssertEqual(mode.defaults.first?.native["kind"] as? String, "composeText")
            XCTAssertEqual(mode.defaults.first?.isCustom, false)
            XCTAssertTrue(mode.defaults.allSatisfy { $0.compatible(with: mode) })
            let old = mode.legacyDefaults
            let upgraded = mode.upgradingUntouchedDefaults(old)
            XCTAssertEqual(upgraded.first?.kind, .composeText)
            XCTAssertEqual(Array(upgraded.dropFirst()), old, "Existing IDs and choices must remain intact")
            var customized = old; customized[0].enabled = false
            XCTAssertEqual(mode.upgradingUntouchedDefaults(customized), customized)
            customized = old; customized[0].title = "My Action"
            XCTAssertEqual(mode.upgradingUntouchedDefaults(customized), customized)
            XCTAssertEqual(mode.upgradingUntouchedDefaults([]), [])
            XCTAssertEqual(mode.upgradingUntouchedDefaults(Array(old.reversed())), Array(old.reversed()))
        }
    }
    func testCompactComposerUsesActualKeyboardGuideAndLeavesDesktopVisible() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene), root = UIViewController()
        root.view.backgroundColor = .systemBlue; window.rootViewController = root; window.makeKeyAndVisible()
        defer { root.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let composer = DirectTextComposer(macName: "Synthetic Mac", mode: "desktop")
        composer.present(from: root, available: { true }, send: { _, _ in XCTFail("Presentation must never send text") })
        try await Task.sleep(for: .milliseconds(600))
        let panel = try XCTUnwrap(root.presentedViewController as? DirectTextComposerPanel)
        func descendants(_ v: UIView) -> [UIView] { [v] + v.subviews.flatMap(descendants) }
        let editor = try XCTUnwrap(descendants(panel.view).compactMap { $0 as? UITextView }.first)
        XCTAssertTrue(editor.becomeFirstResponder())
        for _ in 0..<100 {
            if panel.view.keyboardLayoutGuide.layoutFrame.height > 150 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        panel.view.layoutIfNeeded()
        XCTAssertGreaterThan(panel.view.keyboardLayoutGuide.layoutFrame.height, 150, "Coverage requires the actual software keyboard")
        let content = try XCTUnwrap(descendants(panel.view).first { $0.accessibilityIdentifier == "compose-panel" })
        let contentRect = content.convert(content.bounds, to: panel.view)
        XCTAssertGreaterThanOrEqual(content.convert(content.bounds, to: window).minY, window.safeAreaInsets.top + 40, "Compact panel leaves remote desktop visible")
        XCTAssertLessThanOrEqual(contentRect.maxY, panel.view.keyboardLayoutGuide.layoutFrame.minY)
        let sendRect = panel.deliveryActionFrame
        XCTAssertGreaterThan(sendRect.width, 20); XCTAssertGreaterThan(sendRect.height, 20)
        XCTAssertGreaterThanOrEqual(sendRect.minY, contentRect.minY)
        XCTAssertLessThanOrEqual(sendRect.maxY, panel.view.keyboardLayoutGuide.layoutFrame.minY)
        let editorRect = editor.convert(editor.bounds, to: panel.view)
        XCTAssertGreaterThan(editorRect.height, 35)
        XCTAssertLessThanOrEqual(editorRect.maxY, sendRect.minY, "The inline footer reserves Send below editable text")
        editor.insertText("synthetic draft")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(composer.draft.text, "synthetic draft")
        editor.selectedRange = NSRange(location: 3, length: 0)
        let selection = editor.selectedRange
        panel.toggleExpansion(); try await Task.sleep(for: .milliseconds(450)); panel.view.layoutIfNeeded()
        XCTAssertTrue(editor.isFirstResponder); XCTAssertEqual(editor.selectedRange, selection)
        XCTAssertGreaterThanOrEqual(content.bounds.height, contentRect.height)
        XCTAssertEqual(composer.draft.text, "synthetic draft")
        panel.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        panel.view.setNeedsLayout(); panel.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let largeRect = panel.deliveryActionFrame
        XCTAssertGreaterThan(largeRect.width, 20)
        XCTAssertLessThanOrEqual(largeRect.maxY, panel.view.keyboardLayoutGuide.layoutFrame.minY)
        XCTAssertLessThanOrEqual(largeRect.maxX, panel.view.bounds.maxX)
        composer.draft.expanded = true
        let latePan = ComposerPanProbe(); latePan.simulatedState = .began
        panel.perform(NSSelectorFromString("resize:"), with: latePan)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        latePan.simulatedState = .cancelled
        panel.perform(NSSelectorFromString("resize:"), with: latePan)
        XCTAssertFalse(composer.draft.expanded, "Late canceled drag cannot restore retired presentation state")
        XCTAssertFalse(composer.draft.active); XCTAssertEqual(composer.draft.text, "")
    }
    func testLandscapeComposerKeepsActualSendAndEditorAboveKeyboard() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene), root = UIViewController()
        root.view.backgroundColor = .systemBlue; window.rootViewController = root; window.makeKeyAndVisible()
        defer {
            root.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil
            previous?.makeKeyAndVisible(); if !scene.interfaceOrientation.isPortrait { scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) }
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        for _ in 0..<200 {
            if scene.interfaceOrientation.isLandscape && window.bounds.width > window.bounds.height { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(scene.interfaceOrientation.isLandscape, "Coverage requires actual landscape geometry")
        let composer = DirectTextComposer(macName: "Synthetic Mac", mode: "desktop")
        composer.present(from: root, available: { true }, send: { _, _ in XCTFail("Layout must not send") })
        try await Task.sleep(for: .milliseconds(600))
        let panel = try XCTUnwrap(root.presentedViewController as? DirectTextComposerPanel)
        func descendants(_ v: UIView) -> [UIView] { [v] + v.subviews.flatMap(descendants) }
        let editor = try XCTUnwrap(descendants(panel.view).compactMap { $0 as? UITextView }.first)
        XCTAssertTrue(editor.becomeFirstResponder())
        for _ in 0..<100 {
            if panel.view.keyboardLayoutGuide.layoutFrame.height > 120 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        panel.view.layoutIfNeeded()
        let content = try XCTUnwrap(descendants(panel.view).first { $0.accessibilityIdentifier == "compose-panel" })
        let contentRect = content.convert(content.bounds, to: panel.view)
        let editorRect = editor.convert(editor.bounds, to: panel.view)
        XCTAssertGreaterThanOrEqual(content.convert(content.bounds, to: window).minY, window.safeAreaInsets.top + 8)
        XCTAssertGreaterThan(panel.view.keyboardLayoutGuide.layoutFrame.height, 120)
        XCTAssertGreaterThan(panel.deliveryActionFrame.height, 20)
        XCTAssertGreaterThanOrEqual(panel.deliveryActionFrame.minY, contentRect.minY)
        XCTAssertLessThanOrEqual(panel.deliveryActionFrame.maxY, contentRect.maxY)
        XCTAssertLessThanOrEqual(panel.deliveryActionFrame.maxY, panel.view.keyboardLayoutGuide.layoutFrame.minY)
        XCTAssertGreaterThan(editorRect.height, 35)
        XCTAssertGreaterThanOrEqual(editorRect.minY, contentRect.minY)
        XCTAssertLessThanOrEqual(editorRect.maxY, panel.deliveryActionFrame.minY, "The inline footer reserves Send below the editor")
        editor.insertText(String(repeating: "x", count: 257))
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(composer.draft.canSend, "Invalid input keeps Send disabled in compact layout")
        panel.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        panel.view.setNeedsLayout(); panel.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThan(panel.deliveryActionFrame.height, 40)
        XCTAssertLessThanOrEqual(panel.deliveryActionFrame.maxY, panel.view.keyboardLayoutGuide.layoutFrame.minY)
        let capture = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) })
        capture.name = "compose-landscape-accessibility"; capture.lifetime = .keepAlways; add(capture)
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        for _ in 0..<100 {
            if root.presentedViewController == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(root.presentedViewController)
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        for _ in 0..<200 {
            if scene.interfaceOrientation.isPortrait && window.bounds.height > window.bounds.width { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(scene.interfaceOrientation.isPortrait)
        // Keep the owned window alive until rotation and dismissal settle, so
        // its transition cannot compete with the next test's presentation.
        try await Task.sleep(for: .milliseconds(400))
    }
    func testBackgroundDuringPresentationRetiresPopupAndAllowsNextComposer() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene), root = UIViewController()
        window.rootViewController = root; window.makeKeyAndVisible()
        defer { root.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        let first = DirectTextComposer(macName: "Synthetic Mac", mode: "desktop")
        first.present(from: root, available: { true }, send: { _, _ in XCTFail("Retired draft cannot send") })
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        for _ in 0..<100 {
            if root.presentedViewController == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(root.presentedViewController); XCTAssertFalse(first.draft.active)
        let next = DirectTextComposer(macName: "Synthetic Mac", mode: "terminal")
        next.present(from: root, available: { true }, send: { _, _ in XCTFail("Reopening must not send") })
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNotNil(root.presentedViewController); XCTAssertTrue(next.draft.active)
    }
    func testCapturedComposerAvailabilityAndFinalDeliveryRejectLaterRestoration() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let vectors = try XCTUnwrap(fixture["interruptionCases"] as? [[String: Any]])
        XCTAssertNotNil(vectors.first { $0["name"] as? String == "replacement-composer-delivery-before-layout" })
        let viewer = CompanionVNCViewer(); viewer.loadViewIfNeeded()
        let owner = viewer.session
        for key in ["running", "inputReady", "established", "baselinePresented"] { owner.setValue(true, forKey: key) }
        let probe = ComposerAdmissionProbe(); viewer.setValue(probe, forKey: "textComposer")
        defer { viewer.perform(NSSelectorFromString("stopViewer")); owner.setValue(false, forKey: "running") }
        viewer.perform(NSSelectorFromString("showTextComposer"))
        let availability = try XCTUnwrap(probe.available), delivery = try XCTUnwrap(probe.send)
        XCTAssertTrue(availability())
        viewer.setValue(true, forKey: "restoreViewportPending")
        XCTAssertFalse(availability(), "A captured availability callback must observe later restoration")
        var rejected: String?
        // Exercise the production final-send closure independently of the draft's
        // earlier availability check, as a late delivery callback can do.
        delivery("synthetic-only") { rejected = $0 }
        XCTAssertNotNil(rejected)
        XCTAssertEqual((owner.value(forKey: "events") as? [NSDictionary])?.count, 0)
        viewer.setValue(false, forKey: "restoreViewportPending")
        XCTAssertTrue(availability())
        delivery("a") { _ in }
        XCTAssertEqual((owner.value(forKey: "events") as? [NSDictionary])?.count, 2, "Current readiness still admits balanced Unicode events")
    }
    func testInterruptedSendWarningSurvivesAutomaticReplacementUntilAcknowledged() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ios-text-composer-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let lifecycle = try XCTUnwrap(fixture["lifecycle"] as? [String: Any])
        let policy = try XCTUnwrap(lifecycle["automaticReplacement"] as? [String: Any])
        let modes = try XCTUnwrap(policy["modes"] as? [String])
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        for mode in modes {
            let viewer = CompanionVNCViewer()
            viewer.inputOnly = mode == "trackpad"; viewer.macName = "Synthetic Mac"
            window.rootViewController = viewer; window.makeKeyAndVisible(); viewer.loadViewIfNeeded()
            viewer.session.inputOnly = mode == "trackpad"
            viewer.session.setValue(true, forKey: "running"); viewer.session.setValue(true, forKey: "inputReady")
            viewer.session.setValue(true, forKey: "established"); viewer.session.setValue(true, forKey: "baselinePresented")
            viewer.perform(NSSelectorFromString("showTextComposer"))
            try await Task.sleep(for: .milliseconds(350))
            let composer = try XCTUnwrap(viewer.value(forKey: "textComposer") as? DirectTextComposer)
            var completion: ((String?) -> Void)?
            composer.draft.configure(available: { true }, send: { _, done in completion = done })
            composer.draft.edit("hello"); composer.draft.requestSend()
            XCTAssertTrue(composer.sending)
            viewer.perform(NSSelectorFromString("background"))
            XCTAssertEqual(viewer.value(forKey: "textSendInterrupted") as? Bool, true)
            XCTAssertFalse(composer.draft.active); XCTAssertEqual(composer.draft.text, "")
            viewer.session.setValue(false, forKey: "running")
            var replacements = 0
            viewer.connectHandler = { _, _, _ in replacements += 1 }
            viewer.foregrounded()
            XCTAssertEqual(replacements, 1)
            XCTAssertEqual(viewer.value(forKey: "textSendInterrupted") as? Bool, policy["warningBeforeAcknowledge"] as? Bool)
            // Establish the replacement's real viewer callbacks and report a
            // synthetic connected framebuffer, without opening a network socket.
            viewer.prepareConnection()
            let owner = viewer.session
            owner.setValue(true, forKey: "running"); owner.setValue(true, forKey: "inputReady")
            let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
                UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            }
            owner.frameHandler?(image); owner.stateHandler?("Connected", [:])
            XCTAssertEqual(viewer.value(forKey: "textSendInterrupted") as? Bool, policy["warningBeforeAcknowledge"] as? Bool)
            XCTAssertNotNil(viewer.value(forKey: "recoveryController"))
            completion?(nil) // A retired callback must not acknowledge the warning.
            XCTAssertEqual(viewer.value(forKey: "textSendInterrupted") as? Bool, true)
            let acknowledge = NSSelectorFromString("acknowledgeTextSendWarning")
            XCTAssertTrue(viewer.responds(to: acknowledge))
            if viewer.responds(to: acknowledge) { viewer.perform(acknowledge) }
            XCTAssertEqual(viewer.value(forKey: "textSendInterrupted") as? Bool, policy["warningAfterAcknowledge"] as? Bool)
            XCTAssertNil(viewer.value(forKey: "recoveryController"))
            viewer.perform(NSSelectorFromString("stopViewer")); try await Task.sleep(for: .milliseconds(350))
        }
    }
    func testAuthoritativeTextVectorsPreserveUnicodeWhitespaceAndFrameOnlyTerminalPaste() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ios-text-composer-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        for item in cases {
            let input = try XCTUnwrap(item["text"] as? String)
            for mode in DirectControlMode.allCases {
                if item["invalid"] as? Bool == true { XCTAssertThrowsError(try DirectComposedText(input, mode: mode)); continue }
                let prepared = try DirectComposedText(input, mode: mode)
                XCTAssertEqual(prepared.text, item["normalized"] as? String)
                XCTAssertEqual(prepared.needsConfirmation, item["confirmation"] as? Bool)
                let keys = prepared.desktopEvents.compactMap { $0["down"] as? Bool == true ? $0["key"] as? UInt32 : nil }
                XCTAssertEqual(keys.map(Int.init), item["desktopKeys"] as? [Int])
                XCTAssertEqual(prepared.desktopEvents.count, keys.count * 2)
                XCTAssertEqual(hex(prepared.terminalBytes(bracketedPaste: false)), item["terminalHex"] as? String)
                XCTAssertEqual(hex(prepared.terminalBytes(bracketedPaste: true)), item["bracketedHex"] as? String)
            }
        }
        XCTAssertNoThrow(try DirectComposedText(String(repeating: "😀", count: 256), mode: .desktop))
        XCTAssertThrowsError(try DirectComposedText(String(repeating: "😀", count: 257), mode: .trackpad))
        XCTAssertNoThrow(try DirectComposedText(String(repeating: "😀", count: 1024), mode: .terminal))
        XCTAssertThrowsError(try DirectComposedText(String(repeating: "😀", count: 1025), mode: .terminal))
    }
    func testEditingAndCancelledConfirmationSendNothingAndBusyAdmissionRetainsDraft() {
        for mode in DirectControlMode.allCases {
            let draft = DirectTextComposerDraft(macName: "Synthetic Mac", mode: mode)
            var sent: [String] = []
            var completion: ((String?) -> Void)?
            draft.configure(available: { true }, send: { sent.append($0); completion = $1 })
            draft.edit("one\n  two\n")
            XCTAssertTrue(sent.isEmpty)
            draft.requestSend(); XCTAssertTrue(sent.isEmpty); XCTAssertNotNil(draft.confirmation)
            draft.confirmation = nil; XCTAssertTrue(sent.isEmpty)
            draft.requestSend(); draft.confirmSend()
            XCTAssertEqual(sent, ["one\n  two\n"]); XCTAssertTrue(draft.sending)
            draft.requestSend(); draft.confirmSend(try? DirectComposedText("one\n  two\n", mode: mode)); draft.edit("replacement")
            XCTAssertEqual(sent.count, 1); XCTAssertEqual(draft.text, "one\n  two\n")
            completion?("Input is busy. Nothing was queued.")
            XCTAssertFalse(draft.sending); XCTAssertEqual(draft.text, "one\n  two\n")
            draft.requestSend(); draft.confirmSend(); completion?(nil)
            XCTAssertEqual(sent.count, 2); XCTAssertEqual(draft.text, "")
        }
    }
    func testStaleOwnerAndLateCompletionCannotSendOrEraseAnotherDraft() {
        let draft = DirectTextComposerDraft(macName: "Synthetic Mac", mode: .terminal)
        var admitted = true, sent: [String] = [], completion: ((String?) -> Void)?
        var interruptions = 0
        draft.interrupted = { interruptions += 1 }
        draft.configure(available: { admitted }, send: { sent.append($0); completion = $1 })
        draft.edit("hello"); draft.requestSend()
        let oldCompletion = completion
        draft.invalidate(); XCTAssertEqual(draft.text, ""); XCTAssertFalse(draft.active)
        XCTAssertEqual(interruptions, 1)
        draft.configure(available: { admitted }, send: { sent.append($0); completion = $1 })
        draft.edit("new draft"); oldCompletion?(nil)
        XCTAssertEqual(draft.text, "new draft"); XCTAssertEqual(sent.count, 1)
        admitted = false; draft.requestSend()
        XCTAssertEqual(sent.count, 1); XCTAssertEqual(draft.text, ""); XCTAssertFalse(draft.active)
    }
    func testExactConfirmationAndOversizePasteDoNotSilentlyChangeText() {
        let draft = DirectTextComposerDraft(macName: "Synthetic Mac", mode: .desktop)
        var sent: [String] = []
        draft.configure(available: { true }, send: { text, complete in sent.append(text); complete(nil) })
        draft.edit("reviewed\n"); draft.requestSend()
        let confirmation = draft.confirmation
        draft.edit("changed\n"); draft.confirmation = confirmation; draft.confirmSend()
        XCTAssertTrue(sent.isEmpty); XCTAssertNotNil(draft.issue)
        draft.edit(String(repeating: "x", count: 16385))
        XCTAssertEqual(draft.text, "changed\n"); XCTAssertNotNil(draft.issue)
    }
    func testDesktopQueueRejectsWholeGroupAndCancelsOnePendingWriteWithoutReplay() async throws {
        let owner = CompanionVNCSession()
        owner.setValue(true, forKey: "running"); owner.setValue(true, forKey: "inputReady")
        owner.setValue(true, forKey: "established"); owner.setValue(true, forKey: "baselinePresented")
        let events = try DirectComposedText(String(repeating: "x", count: 256), mode: .desktop).desktopEvents
        var replies: [Bool] = []
        XCTAssertTrue(owner.tryComposedTextEvents(events) { replies.append($0) })
        let queued = try XCTUnwrap(owner.value(forKey: "events") as? [NSDictionary])
        XCTAssertEqual(queued.count, 512)
        XCTAssertFalse(owner.tryComposedTextEvents(events) { replies.append($0) })
        XCTAssertEqual((owner.value(forKey: "events") as? [NSDictionary])?.count, 512)
        XCTAssertTrue(replies.isEmpty)
        owner.stop()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(replies, [false]); XCTAssertTrue((owner.value(forKey: "events") as? [NSDictionary])?.isEmpty == true)
        XCTAssertFalse(owner.tryComposedTextEvents(events) { replies.append($0) })
        owner.stop(); try await Task.sleep(for: .milliseconds(30)); XCTAssertEqual(replies, [false])
    }
    func testAppLockRetiresAHiddenDraftWithoutWaitingForItToReopen() async throws {
        let defaults = UserDefaults.standard, key = DirectAppLockV1.preferenceKey
        let original = defaults.object(forKey: key)
        guard !defaults.bool(forKey: key) else { throw XCTSkip("Leave an already enabled QA app lock unchanged") }
        defer {
            DirectAppLockV1.shared.setEnabled(false)
            if let original { defaults.set(original, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        let composer = DirectTextComposer(macName: "Synthetic Mac", mode: "desktop")
        defaults.set(true, forKey: key)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(DirectAppLockV1.shared.canAccess)
        composer.draft.configure(available: { true }, send: { _, _ in XCTFail("Lock must not send input") })
        composer.draft.edit("hidden unsent draft")
        DirectAppLockV1.shared.background()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(composer.draft.text, ""); XCTAssertFalse(composer.draft.active)
    }
    func testNativeEditorAndBackgroundPrivacyWithSyntheticCaptures() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene), root = UIViewController()
        window.rootViewController = root; window.makeKeyAndVisible()
        defer { root.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        for mode in DirectControlMode.allCases {
            let composer = DirectTextComposer(macName: "Synthetic Mac", mode: mode.rawValue)
            composer.present(from: root, available: { true }, send: { _, _ in XCTFail("Editing must not send input") })
            try await Task.sleep(for: .milliseconds(400))
            let host = try XCTUnwrap(root.presentedViewController)
            func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
            let editor = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UITextView }.first)
            XCTAssertTrue(editor.becomeFirstResponder())
            editor.insertText("中文😀\n  second line\n")
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(composer.draft.text, "中文😀\n  second line\n")
            let capture = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) })
            capture.name = "compose-" + mode.rawValue; capture.lifetime = .keepAlways; add(capture)
            editor.setMarkedText("拼音", selectedRange: NSRange(location: 2, length: 0))
            editor.unmarkText()
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(composer.draft.text.contains("拼音"))
            let retained = composer.draft.text
            editor.insertText(String(repeating: "x", count: 16385))
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(composer.draft.text, retained)
            XCTAssertEqual(editor.text, retained, "The editor must not display a rejected paste as though it can be sent")
            root.dismiss(animated: false); try await Task.sleep(for: .milliseconds(50))
            composer.present(from: root, available: { true }, send: { _, _ in XCTFail("Returning to session must not send input") })
            XCTAssertEqual(composer.draft.text, retained)
            try await Task.sleep(for: .milliseconds(350))
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            XCTAssertEqual(composer.draft.text, ""); XCTAssertFalse(composer.draft.active)
            try await Task.sleep(for: .milliseconds(350))
        }
    }
    func testDesktopAndTrackpadEntryUseOnlyTheirCurrentViewerAndClearAtEnd() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        for inputOnly in [false, true] {
            let viewer = CompanionVNCViewer()
            viewer.macName = "Synthetic Mac"; viewer.inputOnly = inputOnly
            window.rootViewController = viewer; window.makeKeyAndVisible(); viewer.loadViewIfNeeded()
            let ownerType = try XCTUnwrap(NSClassFromString("ControlsSession") as? CompanionVNCSession.Type)
            let owner = ownerType.init(), groups = NSMutableArray()
            owner.setValue(groups, forKey: "groups"); owner.setValue(NSMutableArray(), forKey: "pointers")
            viewer.setValue(owner, forKey: "session")
            viewer.perform(NSSelectorFromString("showTextComposer"))
            try await Task.sleep(for: .milliseconds(400))
            let composer = try XCTUnwrap(viewer.value(forKey: "textComposer") as? DirectTextComposer)
            XCTAssertEqual(composer.draft.mode, inputOnly ? .trackpad : .desktop)
            composer.draft.edit("中文😀\n")
            XCTAssertEqual(groups.count, 0)
            composer.draft.close?()
            try await Task.sleep(for: .milliseconds(350))
            viewer.perform(NSSelectorFromString("showTextComposer"))
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertEqual(composer.draft.text, "中文😀\n")
            composer.draft.requestSend(); composer.draft.confirmSend()
            XCTAssertEqual(groups.count, 1)
            let events = try XCTUnwrap(groups.firstObject as? [[String: Any]])
            XCTAssertEqual(events.count, 8)
            XCTAssertEqual(events.last?["key"] as? UInt32, 0xff0d)
            XCTAssertEqual(events.last?["down"] as? Bool, false)
            XCTAssertEqual(composer.draft.text, "")
            try await Task.sleep(for: .milliseconds(350))
            viewer.perform(NSSelectorFromString("showTextComposer")); composer.draft.edit("unsent")
            viewer.perform(NSSelectorFromString("stopViewer"))
            XCTAssertEqual(composer.draft.text, ""); XCTAssertFalse(composer.draft.active)
            try await Task.sleep(for: .milliseconds(350))
        }
    }
    private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
}
