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
            XCTAssertGreaterThan(keyboard.height, 100, "The real software keyboard must be visible")
            XCTAssertEqual(button.maxY, keyboard.minY - 8, accuracy: 2, "SwiftUI and UIKit must avoid the keyboard once")
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
            XCTAssertLessThanOrEqual(controller.terminal.frame.maxY + 4, button.minY, "The control must never cover a terminal row")
            XCTAssertLessThanOrEqual(button.maxY, controller.keyboardCeiling(), "The dock must stay above the keyboard")
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
            menu.tableView.scrollToRow(at: IndexPath(row: 0, section: 2), at: .bottom, animated: false)
            menu.tableView.layoutIfNeeded()
            let exit = menu.tableView.convert(menu.tableView.rectForRow(at: IndexPath(row: 0, section: 2)), to: nav.view)
            XCTAssertLessThanOrEqual(exit.maxY, nav.view.bounds.maxY + 1)
            controller.dismiss(animated: false)
        }
        XCTAssertTrue(String(decoding: controller.terminal.getTerminal().getBufferAsData(), as: UTF8.self).contains("rightmost columns"))
    }

    func testSharedSessionMenuFitsContentAndKeySubmenuPreservesTerminal() async throws {
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
        XCTAssertTrue(items.contains { $0["title"] as? String == "Exit to My Macs" && $0["destructive"] as? Bool == true })
        menu.tableView(menu.tableView, didSelectRowAt: IndexPath(row: 1, section: 1))
        try await Task.sleep(for: .milliseconds(500))
        for _ in 0..<100 where navigation.transitionCoordinator != nil { try await Task.sleep(for: .milliseconds(20)) }
        try await Task.sleep(for: .milliseconds(100))
        let keys = try XCTUnwrap(navigation.topViewController as? CompanionVNCMenu)
        XCTAssertEqual(navigation.viewControllers.count, 2)
        XCTAssertLessThan(navigation.preferredContentSize.height, 350, "Three key actions should not reserve a full-size sheet")
        let last = keys.tableView.rectForRow(at: IndexPath(row: 2, section: 0))
        let visible = keys.tableView.convert(last, to: navigation.view)
        let bottomPadding = navigation.view.bounds.maxY - visible.maxY
        XCTAssertGreaterThanOrEqual(bottomPadding, 0, "The final action must be fully visible")
        XCTAssertLessThanOrEqual(bottomPadding, 32, "A short menu must end near its final action")
        navigation.popViewController(animated: false)
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
        XCTAssertFalse(terminal.isUserInteractionEnabled)
        session.recovery = nil; session.connected = true
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(controls.isHidden); XCTAssertTrue(terminal.isUserInteractionEnabled)
        XCTAssertTrue(descendants(host.view).contains { $0 === terminal })
    }
}
