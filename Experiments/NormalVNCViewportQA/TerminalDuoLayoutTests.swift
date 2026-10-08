import XCTest
import SwiftUI
import UIKit
@testable import Mac_Companion

@MainActor private final class FoldTerminalController: TerminalController {
    var division = CGRect.null
    var simulatedKeyboardTop: CGFloat?
    override func activeDivision() -> CGRect { division }
    override func keyboardCeiling() -> CGFloat { simulatedKeyboardTop ?? super.keyboardCeiling() }
}

@MainActor private final class SoftwareKeyboardFrame: NSObject {
    var frame = CGRect.null
    @objc func changed(_ notification: Notification) {
        if let value = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue { frame = value.cgRectValue }
    }
}

@MainActor final class TerminalDuoLayoutTests: XCTestCase {
    func testImmersiveTerminalProtectsEntryAndLiveGridButAllowsHistoryBehindStatus() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Terminal", addresses: ["studio.local"])
        let session = DirectTerminalSession(mac: mac); session.connected = true
        let host = UIHostingController(rootView: DirectTerminalView(mac: mac, session: session, autoConnect: false, exit: {}).directAppearance())
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.endEditing(true); window.isHidden = true; window.rootViewController = nil; session.stop() }
        func controllers(_ root: UIViewController) -> [UIViewController] { [root] + root.children.flatMap(controllers) }
        try await Task.sleep(for: .milliseconds(400))
        let controller = try XCTUnwrap(controllers(host).compactMap { $0 as? TerminalController }.first)
        let terminal = controller.terminal
        terminal.feed(text: "Welcome to the synthetic Mac\r\ndemo@studio ~ % ")
        try await Task.sleep(for: .milliseconds(100)); window.layoutIfNeeded()
        XCTAssertEqual(terminal.convert(terminal.bounds, to: window).minY, 0, accuracy: 0.5, "The connected canvas must reach the screen edge")
        XCTAssertEqual(terminal.contentInset.top, window.safeAreaInsets.top + 8, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(terminal.convert(CGPoint.zero, to: window).y, window.safeAreaInsets.top + 8 - 0.5, "Initial login output must start below the system icons")
        XCTAssertGreaterThanOrEqual(terminal.convert(terminal.caretFrame, to: window).minY, window.safeAreaInsets.top)
        for keyboard in [false, true, false] {
            if keyboard { _ = terminal.becomeFirstResponder() }
            else { _ = terminal.resignFirstResponder() }
            try await Task.sleep(for: .milliseconds(500)); window.layoutIfNeeded()
            terminal.feed(text: "\r\n" + (1...120).map { "Synthetic scrollback row \($0)\r\n" }.joined() + "demo@studio ~ % ")
            try await Task.sleep(for: .milliseconds(100)); terminal.layoutIfNeeded()
            let cell = terminal.caretFrame.height
            XCTAssertGreaterThan(cell, 0)
            let grid = terminal.getTerminal()
            XCTAssertEqual(grid.rows, Int(floor((terminal.bounds.height - terminal.contentInset.top) / cell)))
            let liveGridStart = terminal.contentSize.height - CGFloat(grid.rows) * cell
            XCTAssertEqual(terminal.convert(CGPoint(x: 0, y: liveGridStart), to: window).y, window.safeAreaInsets.top + 8, accuracy: 0.5, "Interactive rows must stay below status icons while following output")
            let caret = terminal.convert(terminal.caretFrame, to: window)
            XCTAssertGreaterThanOrEqual(caret.minY, window.safeAreaInsets.top)
            XCTAssertLessThanOrEqual(caret.maxY, terminal.convert(terminal.bounds, to: window).maxY + 0.5)

            let historyOffset = cell * 28.5
            terminal.setContentOffset(CGPoint(x: 0, y: historyOffset), animated: false)
            window.layoutIfNeeded(); terminal.layoutIfNeeded()
            XCTAssertEqual(terminal.contentOffset.y, historyOffset, accuracy: 0.5, "Layout must not snap scrollback to the safe area")
            XCTAssertEqual(terminal.convert(CGPoint(x: 0, y: cell * 29), to: window).y, cell * 0.5, accuracy: 0.5, "History must pass behind the status icons")
            terminal.setContentOffset(CGPoint(x: 0, y: -terminal.contentInset.top), animated: false)
            terminal.layoutIfNeeded()
            XCTAssertEqual(terminal.convert(CGPoint.zero, to: window).y, window.safeAreaInsets.top + 8, accuracy: 0.5, "The first history row must remain reachable")
        }
        // Full-screen CLI tools use the same protected grid, without a second
        // rendering surface or a terminal reset when entering/leaving it.
        terminal.feed(text: "\u{1b}[?1049h\u{1b}[2J\u{1b}[HTop row in an alternate buffer")
        try await Task.sleep(for: .milliseconds(100)); window.layoutIfNeeded()
        XCTAssertGreaterThanOrEqual(terminal.convert(CGPoint.zero, to: window).y, window.safeAreaInsets.top + 8 - 0.5)
        terminal.feed(text: "\u{1b}[?1049l")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(String(decoding: terminal.getTerminal().getBufferAsData(), as: UTF8.self).contains("Synthetic scrollback row"))
    }

    func testHostedTerminalDockFollowsKeyboardAcrossPaletteChanges() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let appearance = DirectAppearanceV1.shared
        let previousApp = appearance.app, previousTerminal = appearance.terminal
        appearance.app = .light; appearance.terminal = .light
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Terminal", addresses: ["studio.local"])
        let session = DirectTerminalSession(mac: mac); session.connected = true
        let host = UIHostingController(rootView: DirectTerminalView(mac: mac, session: session, autoConnect: false, exit: {}).environment(appearance))
        let keyboardFrame = SoftwareKeyboardFrame()
        NotificationCenter.default.addObserver(keyboardFrame, selector: #selector(SoftwareKeyboardFrame.changed(_:)), name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer {
            NotificationCenter.default.removeObserver(keyboardFrame)
            window.endEditing(true); window.isHidden = true; window.rootViewController = nil; session.stop()
            appearance.app = previousApp; appearance.terminal = previousTerminal
        }
        func controllers(_ root: UIViewController) -> [UIViewController] { [root] + root.children.flatMap(controllers) }
        try await Task.sleep(for: .milliseconds(400))
        let controller = try XCTUnwrap(controllers(host).compactMap { $0 as? TerminalController }.first)
        controller.terminal.feed(text: "Preserved while changing terminal colors\r\n")
        XCTAssertTrue(controller.terminal.becomeFirstResponder())
        for palette in [DirectTerminalAppearance.light, .dark, .light] {
            appearance.terminal = palette
            try await Task.sleep(for: .milliseconds(700)); window.layoutIfNeeded()
            let button = controller.controls.button.convert(controller.controls.button.bounds, to: window)
            let terminal = controller.terminal.convert(controller.terminal.bounds, to: window)
            let keyboard = window.convert(keyboardFrame.frame, from: window.screen.coordinateSpace)
            XCTAssertEqual(controller.keyboardBar.bounds.height, 108, accuracy: 1, "The number row must remain visible in the SwiftUI host")
            XCTAssertGreaterThan(keyboard.height, 100, "The real software keyboard must be visible")
            XCTAssertEqual(button.maxY, keyboard.minY - 4, accuracy: 2, "SwiftUI and UIKit must avoid the keyboard once")
            XCTAssertLessThanOrEqual(terminal.maxY + 4, button.minY)
            XCTAssertTrue(controller.terminal.isFirstResponder)
            XCTAssertTrue(controllers(host).contains { $0 === controller }, "Changing colors must preserve the controller")
        }
        XCTAssertTrue(String(decoding: controller.terminal.getTerminal().getBufferAsData(), as: UTF8.self).contains("changing terminal colors"))
    }

    func testDockAndSessionMenuStayClearOfTerminalAndSoftwareKeyboard() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.overrideUserInterfaceStyle = .light
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Terminal", addresses: ["studio.local"])
        let session = DirectTerminalSession(mac: mac); session.connected = true
        let controller = TerminalController(session: session, customize: {})
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.endEditing(true); window.isHidden = true; window.rootViewController = nil; session.stop() }
        controller.terminal.feed(text: "The prompt and its rightmost columns remain readable\r\n")
        for keyboard in [false, true, false] {
            if keyboard { XCTAssertTrue(controller.terminal.becomeFirstResponder()) }
            else { _ = controller.terminal.resignFirstResponder() }
            try await Task.sleep(for: .milliseconds(500)); controller.view.layoutIfNeeded()
            let button = controller.controls.button.convert(controller.controls.button.bounds, to: controller.view)
            let toolbar = controller.keyboardBar.convert(controller.keyboardBar.bounds, to: controller.view)
            XCTAssertLessThanOrEqual(controller.terminal.frame.maxY + 4, button.minY, "The control must never cover a terminal row")
            XCTAssertLessThanOrEqual(button.maxY, controller.keyboardCeiling(), "The dock must stay above the keyboard")
            XCTAssertTrue(toolbar.contains(button), "The menu button must occupy the modifier bar")
            XCTAssertLessThan(toolbar.minY - controller.terminal.frame.maxY, controller.terminal.caretFrame.height + 1, "Only whole-row rounding may separate output from the toolbar")
            XCTAssertEqual(toolbar.height, keyboard ? 108 : 60, accuracy: 1, "Keyboard requested: \(keyboard); first responder: \(controller.terminal.isFirstResponder); ceiling: \(controller.keyboardCeiling())")
            XCTAssertNil(controller.terminal.inputAccessoryView, "A second accessory would duplicate the toolbar and keyboard avoidance")
            if !keyboard { continue }
            XCTAssertLessThan(controller.keyboardCeiling(), controller.view.bounds.height - 100)
            controller.controls.actionHandler?(["kind": "session"])
            try await Task.sleep(for: .milliseconds(600))
            let nav = try XCTUnwrap(controller.presentedViewController as? UINavigationController)
            let menu = try XCTUnwrap(nav.topViewController as? CompanionVNCMenu)
            let header = menu.tableView.convert(menu.tableView.rectForHeader(inSection: 0), to: nav.view)
            let bar = nav.navigationBar.convert(nav.navigationBar.bounds, to: nav.view)
            XCTAssertGreaterThanOrEqual(header.minY, bar.maxY - 1, "The first heading must not hide beneath the title bar")
            XCTAssertEqual(menu.navigationItem.rightBarButtonItem?.title, "Done")
            let panel = nav.view.convert(nav.view.bounds, to: controller.view)
            XCTAssertLessThanOrEqual(panel.maxY, controller.keyboardCeiling() + 1)
            menu.tableView.scrollToRow(at: IndexPath(row: 0, section: 1), at: .bottom, animated: false)
            menu.tableView.layoutIfNeeded()
            let exit = menu.tableView.convert(menu.tableView.rectForRow(at: IndexPath(row: 0, section: 1)), to: nav.view)
            XCTAssertLessThanOrEqual(exit.maxY, nav.view.bounds.maxY + 1)
            // UIKit restores keyboard focus while dismissing the popover. Finish
            // that transition before the next iteration hides the keyboard.
            await withCheckedContinuation { (completion: CheckedContinuation<Void, Never>) in
                controller.dismiss(animated: false) { completion.resume() }
            }
        }
        XCTAssertTrue(String(decoding: controller.terminal.getTerminal().getBufferAsData(), as: UTF8.self).contains("rightmost columns"))
    }

    func testPersistentBarTogglesKeyboardAndKeepsFixedControlsWithScrollableKeys() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Terminal", addresses: ["studio.local"])
        let session = DirectTerminalSession(mac: mac); session.connected = true
        let controller = TerminalController(session: session, customize: {})
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.endEditing(true); window.isHidden = true; window.rootViewController = nil; session.stop() }
        controller.terminal.feed(text: "Preserved while toggling the toolbar keyboard\r\n")
        try await Task.sleep(for: .milliseconds(350)); window.layoutIfNeeded()
        let toolbar = controller.keyboardBar
        XCTAssertFalse(toolbar.isHidden)
        XCTAssertEqual(toolbar.keyboardButton.accessibilityLabel, "Show Keyboard")
        XCTAssertFalse(controller.controls.quickActions.contains { $0["kind"] as? String == "keyboard" })
        let originalRows = controller.terminal.getTerminal().rows
        toolbar.keyboardButton.sendActions(for: .touchUpInside)
        try await Task.sleep(for: .milliseconds(550)); window.layoutIfNeeded()
        XCTAssertTrue(controller.terminal.isFirstResponder)
        XCTAssertEqual(toolbar.keyboardButton.accessibilityLabel, "Hide Keyboard")
        XCTAssertLessThan(controller.terminal.getTerminal().rows, originalRows)
        toolbar.keyboardButton.sendActions(for: .touchUpInside)
        try await Task.sleep(for: .milliseconds(550)); window.layoutIfNeeded()
        XCTAssertFalse(controller.terminal.isFirstResponder)
        XCTAssertEqual(toolbar.keyboardButton.accessibilityLabel, "Show Keyboard")
        XCTAssertFalse(toolbar.isHidden)
        XCTAssertEqual(controller.terminal.getTerminal().rows, originalRows)
        XCTAssertTrue(String(decoding: controller.terminal.getTerminal().getBufferAsData(), as: UTF8.self).contains("toggling the toolbar keyboard"))

        // A narrow toolbar keeps both end controls reachable without shrinking
        // the terminal keys; the existing Fn menu remains reachable by scrolling.
        let narrow = TerminalKeyboardBar(terminal: controller.terminal, preferences: .init())
        narrow.translatesAutoresizingMaskIntoConstraints = true
        narrow.frame = CGRect(x: 0, y: 0, width: 320, height: 60); controller.view.addSubview(narrow)
        narrow.layoutIfNeeded()
        let keyboardFrame = narrow.keyboardButton.convert(narrow.keyboardButton.bounds, to: narrow)
        let anchorFrame = narrow.menuAnchor.convert(narrow.menuAnchor.bounds, to: narrow)
        XCTAssertTrue(narrow.bounds.contains(keyboardFrame)); XCTAssertTrue(narrow.bounds.contains(anchorFrame))
        XCTAssertGreaterThan(narrow.keyScroll.contentSize.width, narrow.keyScroll.bounds.width)
        let keys = try XCTUnwrap(narrow.keyScroll.subviews.compactMap { $0 as? UIStackView }.first)
        for key in keys.arrangedSubviews { XCTAssertGreaterThanOrEqual(key.bounds.width, 44) }
        narrow.keyScroll.setContentOffset(CGPoint(x: narrow.keyScroll.contentSize.width - narrow.keyScroll.bounds.width, y: 0), animated: false)
        let fn = try XCTUnwrap(keys.arrangedSubviews.last as? UIButton)
        XCTAssertTrue(narrow.keyScroll.bounds.contains(fn.convert(fn.bounds, to: narrow.keyScroll)))
        func titles(_ menu: UIMenu) -> [String] { menu.children.flatMap { item in (item as? UIMenu).map(titles) ?? [item.title] } }
        XCTAssertFalse(titles(try XCTUnwrap(fn.menu)).contains("Hide Keyboard"))
        narrow.removeFromSuperview()
    }

    func testNumberRowMenuAppliesImmediatelyAndRestoresAcrossSessions() async throws {
        let suite = "TerminalNumberRowQA-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.windowLevel = .normal + 1
        let mac = try DirectMacRecordV1.normalized(name: "Studio Mac", addresses: ["studio.local"])
        let session = DirectTerminalSession(mac: mac); session.connected = true
        var customizationRequested = false
        let controller = TerminalController(session: session, customize: { customizationRequested = true }, defaults: defaults)
        window.rootViewController = controller; window.makeKeyAndVisible(); controller.applyAppearance(.light)
        let folder = URL.documentsDirectory.appending(path: "TerminalNumberRow")
        let ready = folder.appending(path: "ready")
        defer {
            window.endEditing(true); window.isHidden = true; window.rootViewController = nil; session.stop()
            defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: ready)
        }
        func capture(_ name: String) async throws {
            guard ProcessInfo.processInfo.environment["MACCOMPANION_SCREENSHOT_REVIEW"] == "1" else { return }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(name.utf8).write(to: ready, options: .atomic)
            try await Task.sleep(for: .seconds(2)); try? FileManager.default.removeItem(at: ready)
        }
        func inputMenu(_ owner: TerminalController) async throws -> CompanionVNCMenu {
            owner.controls.actionHandler?(["kind": "inputMenu"])
            try await Task.sleep(for: .milliseconds(550))
            let navigation = try XCTUnwrap(owner.presentedViewController as? UINavigationController)
            return try XCTUnwrap(navigation.topViewController as? CompanionVNCMenu)
        }
        func numberRow(_ bar: TerminalKeyboardBar) throws -> UIView {
            func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
            return try XCTUnwrap(descendants(bar).first { $0.accessibilityIdentifier == "terminal-number-row" })
        }
        try await Task.sleep(for: .milliseconds(350))
        controller.terminal.feed(text: "Welcome to Studio Mac\r\n" + (1...40).map { "Synthetic output row \($0)\r\n" }.joined() + "demo@studio ~ % ")
        XCTAssertTrue(controller.keyboardBar.showsNumberRow, "New installations retain the number row")
        XCTAssertTrue(controller.terminal.becomeFirstResponder())
        try await Task.sleep(for: .milliseconds(550)); window.layoutIfNeeded()
        XCTAssertEqual(controller.keyboardBar.bounds.height, 108, accuracy: 1)
        let rowsWithNumbers = controller.terminal.getTerminal().rows
        try await capture("number-row-on")
        let menu = try await inputMenu(controller)
        let path = IndexPath(row: 0, section: 0)
        let checked = menu.tableView(menu.tableView, cellForRowAt: path)
        XCTAssertEqual(checked.accessibilityIdentifier, "session-menu-numberRow")
        XCTAssertEqual(checked.accessoryType, .checkmark)
        XCTAssertTrue(checked.accessibilityTraits.contains(.selected))
        XCTAssertFalse(checked.accessibilityTraits.contains(.notEnabled))
        XCTAssertNotNil((checked.contentConfiguration as? UIListContentConfiguration)?.image)
        try await capture("number-row-menu-on")
        menu.tableView(menu.tableView, didSelectRowAt: path)
        try await Task.sleep(for: .milliseconds(650)); window.layoutIfNeeded()
        XCTAssertFalse(controller.keyboardBar.showsNumberRow)
        XCTAssertTrue(try numberRow(controller.keyboardBar).isHidden)
        XCTAssertEqual(controller.keyboardBar.bounds.height, 60, accuracy: 1)
        XCTAssertGreaterThan(controller.terminal.getTerminal().rows, rowsWithNumbers, "Hiding numbers must return space to the PTY")
        XCTAssertTrue(controller.terminal.isFirstResponder)
        XCTAssertTrue(session.connected); XCTAssertTrue(controller.session === session)
        XCTAssertFalse(controller.keyboardBar.isHidden); XCTAssertFalse(controller.controls.isHidden)
        XCTAssertEqual(defaults.object(forKey: TerminalController.numberRowPreference) as? Bool, false)
        XCTAssertFalse(customizationRequested, "This free layout choice must not open Pro customization")
        XCTAssertTrue(String(decoding: controller.terminal.getTerminal().getBufferAsData(), as: UTF8.self).contains("Synthetic output row"))
        try await capture("number-row-off")
        let uncheckedMenu = try await inputMenu(controller)
        let unchecked = uncheckedMenu.tableView(uncheckedMenu.tableView, cellForRowAt: path)
        XCTAssertEqual(unchecked.accessoryType, .none); XCTAssertFalse(unchecked.accessibilityTraits.contains(.selected))
        try await capture("number-row-menu-off")
        controller.dismiss(animated: false); _ = controller.terminal.resignFirstResponder()

        // A new session controller reads the persisted choice without changing
        // the protected per-Mac custom-key preferences or requiring Pro.
        let restored = TerminalController(session: session, customize: {}, defaults: defaults)
        window.rootViewController = restored
        try await Task.sleep(for: .milliseconds(350)); window.layoutIfNeeded()
        XCTAssertFalse(restored.keyboardBar.showsNumberRow)
        XCTAssertTrue(restored.terminal.becomeFirstResponder())
        try await Task.sleep(for: .milliseconds(550)); window.layoutIfNeeded()
        XCTAssertEqual(restored.keyboardBar.bounds.height, 60, accuracy: 1)
        let restoredMenu = try await inputMenu(restored)
        restoredMenu.tableView(restoredMenu.tableView, didSelectRowAt: path)
        try await Task.sleep(for: .milliseconds(650)); window.layoutIfNeeded()
        XCTAssertEqual(restored.keyboardBar.bounds.height, 108, accuracy: 1)
        XCTAssertFalse(try numberRow(restored.keyboardBar).isHidden)
        XCTAssertTrue(defaults.bool(forKey: TerminalController.numberRowPreference))
        _ = restored.terminal.resignFirstResponder()
        try await Task.sleep(for: .milliseconds(550)); window.layoutIfNeeded()
        restored.controls.actionHandler?(["kind": "numberRow"]); window.layoutIfNeeded()
        XCTAssertEqual(restored.keyboardBar.bounds.height, 60, accuracy: 1, "A closed keyboard keeps only the persistent modifier bar")
    }

    func testSessionMenuContainsOnlyActiveSessionActionsAndPreservesTerminal() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.overrideUserInterfaceStyle = .light
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Terminal", addresses: ["studio.local"])
        let session = DirectTerminalSession(mac: mac); session.connected = true
        let controller = TerminalController(session: session, customize: {})
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; session.stop() }
        controller.applyAppearance(.dark)
        controller.terminal.feed(text: "Preserved across menus\r\n")
        controller.controls.actionHandler?(["kind": "session"])
        try await Task.sleep(for: .milliseconds(500))
        let navigation = try XCTUnwrap(controller.presentedViewController as? UINavigationController)
        let menu = try XCTUnwrap(navigation.topViewController as? CompanionVNCMenu)
        for _ in 0..<100 where navigation.transitionCoordinator != nil { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(navigation.traitCollection.userInterfaceStyle, .dark, "Menus must follow the terminal palette even when the app is light")
        let items = menu.sections.flatMap { $0["items"] as? [[String: Any]] ?? [] }
        XCTAssertEqual(items.compactMap { $0["kind"] as? String }, ["connectionInfo", "appSettings", "exit"])
        XCTAssertTrue(items.contains { $0["title"] as? String == "Disconnect" && $0["destructive"] as? Bool == true })
        XCTAssertEqual(navigation.viewControllers.count, 1)
        XCTAssertLessThan(navigation.preferredContentSize.height, 350, "Three session actions should not reserve a full-size sheet")
        let last = menu.tableView.rectForRow(at: IndexPath(row: 0, section: 1))
        let visible = menu.tableView.convert(last, to: navigation.view)
        let bottomPadding = navigation.view.bounds.maxY - visible.maxY
        XCTAssertGreaterThanOrEqual(bottomPadding, 0, "The final action must be fully visible")
        XCTAssertLessThanOrEqual(bottomPadding, 32, "A short menu must end near its final action")
        XCTAssertTrue(navigation.topViewController === menu)
        XCTAssertTrue(controller.session === session)
        XCTAssertTrue(String(decoding: controller.terminal.getTerminal().getBufferAsData(), as: UTF8.self).contains("Preserved across menus"))
        controller.dismiss(animated: false)
    }
    func testLoginFieldsKeepIdentityAndFocusAcrossCompactLayoutAndLargeText() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Terminal", addresses: ["studio.local"])
        let session = DirectTerminalSession(mac: mac)
        let host = UIHostingController(rootView: DirectTerminalView(mac: mac, session: session, exit: {}).directAppearance())
        let holder = UIViewController(); holder.addChild(host); holder.view.addSubview(host.view); host.didMove(toParent: holder)
        window.rootViewController = holder; window.makeKeyAndVisible()
        defer { window.endEditing(true); window.isHidden = true; window.rootViewController = nil; session.stop() }
        func fields(_ view: UIView) -> [UITextField] { (view as? UITextField).map { [$0] } ?? view.subviews.flatMap(fields) }
        host.view.frame = CGRect(x: 0, y: 0, width: 900, height: 660)
        try await Task.sleep(for: .milliseconds(250))
        let original = fields(host.view); XCTAssertEqual(original.count, 2)
        XCTAssertLessThan(try XCTUnwrap(original.last).bounds.height, 64, "The password field must use its text height, not stretch the connection sheet")
        let account = try XCTUnwrap(original.first)
        XCTAssertTrue(account.becomeFirstResponder())
        host.view.frame.size.height = 400; host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))
        let compact = fields(host.view)
        XCTAssertEqual(compact.count, 2); XCTAssertTrue(compact.first === account); XCTAssertTrue(account.isFirstResponder)
        XCTAssertEqual(compact[0].convert(compact[0].bounds, to: host.view).midY, compact[1].convert(compact[1].bounds, to: host.view).midY, accuracy: 2)
        host.traitOverrides.preferredContentSizeCategory = .accessibilityExtraLarge
        try await Task.sleep(for: .milliseconds(250))
        let large = fields(host.view)
        XCTAssertTrue(large.first === account); XCTAssertTrue(account.isFirstResponder)
        XCTAssertGreaterThan(large[1].convert(large[1].bounds, to: host.view).minY, large[0].convert(large[0].bounds, to: host.view).maxY)
    }

    func testTerminalUsesLowerRegionWithClosedKeyboardAndPreservesSessionAndBuffer() throws {
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", addresses: ["studio.local"])
        let session = DirectTerminalSession(mac: mac)
        let controller = FoldTerminalController(session: session, customize: {})
        controller.loadViewIfNeeded(); controller.view.frame = CGRect(x: 0, y: 0, width: 669, height: 951)
        controller.view.layoutIfNeeded(); controller.terminal.feed(text: "Preserved terminal contents\r\n")
        let normalHeight = controller.terminal.frame.height
        controller.division = CGRect(x: 0, y: 465, width: 669, height: 20)
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        XCTAssertEqual(controller.terminal.frame.height, normalHeight, accuracy: 1)
        for ceiling in [CGFloat(680), 600, 390] {
            controller.simulatedKeyboardTop = ceiling
            controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
            XCTAssertLessThanOrEqual(controller.terminal.frame.maxY, min(465, ceiling))
            XCTAssertGreaterThan(controller.terminal.frame.height, 0)
            XCTAssertTrue(controller.session === session)
            XCTAssertTrue(String(decoding: controller.terminal.getTerminal().getBufferAsData(), as: UTF8.self).contains("Preserved terminal contents"))
        }
        controller.simulatedKeyboardTop = nil
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        XCTAssertEqual(controller.terminal.frame.height, normalHeight, accuracy: 1)
        controller.division = .null; controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        XCTAssertEqual(controller.terminal.frame.height, normalHeight, accuracy: 1)
        XCTAssertTrue(controller.session === session); XCTAssertNotNil(session.received)
        XCTAssertTrue(String(decoding: controller.terminal.getTerminal().getBufferAsData(), as: UTF8.self).contains("Preserved terminal contents"))
        session.stop()
    }

    func testHeaderlessTerminalPreservesBufferAndFloatingControlsAcrossRecovery() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Terminal", addresses: ["studio.local"])
        let session = DirectTerminalSession(mac: mac); session.connected = true
        let host = UIHostingController(rootView: DirectTerminalView(mac: mac, session: session, exit: {}).directAppearance())
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; session.stop() }
        try await Task.sleep(for: .milliseconds(300))
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        let terminal = try XCTUnwrap(descendants(host.view).compactMap { $0 as? SessionTerminalView }.first)
        let controls = try XCTUnwrap(descendants(host.view).compactMap { $0 as? CompanionVNCControls }.first)
        XCTAssertFalse(controls.isHidden)
        XCTAssertNil(controls.hitTest(CGPoint(x: 10, y: 10), with: nil), "The floating overlay must not intercept terminal selection or scrolling")
        session.received?(Array("Fullscreen buffer survives\r\n".utf8))
        let navigation = try XCTUnwrap(host.children.compactMap { $0 as? UINavigationController }.first)
        XCTAssertTrue(navigation.isNavigationBarHidden)
        session.connected = false; session.recovery = .make(.terminalEnded)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(descendants(host.view).contains { $0 === terminal })
        XCTAssertTrue(String(decoding: terminal.getTerminal().getBufferAsData(), as: UTF8.self).contains("Fullscreen buffer survives"))
        XCTAssertTrue(navigation.isNavigationBarHidden)
        XCTAssertTrue(controls.isHidden)
        XCTAssertTrue(terminal.keyboardBar?.isHidden == true)
        XCTAssertFalse(terminal.isUserInteractionEnabled)
        session.recovery = nil; session.connected = true
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(controls.isHidden); XCTAssertTrue(terminal.isUserInteractionEnabled)
        XCTAssertTrue(terminal.keyboardBar?.isHidden == false)
        XCTAssertTrue(descendants(host.view).contains { $0 === terminal })
    }
}
