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

@MainActor final class TerminalDuoLayoutTests: XCTestCase {
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
