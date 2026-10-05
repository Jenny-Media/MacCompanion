import XCTest
import SwiftUI
@testable import Mac_Companion

@MainActor final class AppearanceTests: XCTestCase {
    func testAppChoicePersistsAndUpdatesNativeWindowsWithoutReplacingViewerOrOwner() throws {
        let suite = "appearance-qa-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let appearance = DirectAppearanceV1(defaults: defaults)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let viewer = CompanionVNCViewer(); viewer.loadViewIfNeeded()
        let owner = viewer.session
        window.rootViewController = viewer; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil; viewer.stop(); defaults.removePersistentDomain(forName: suite); DirectAppearanceV1.shared.applyWindows() }
        appearance.app = .light; window.layoutIfNeeded()
        XCTAssertEqual(viewer.traitCollection.userInterfaceStyle, .light)
        appearance.app = .dark; window.layoutIfNeeded()
        XCTAssertEqual(viewer.traitCollection.userInterfaceStyle, .dark)
        XCTAssertTrue(viewer.session === owner)
        XCTAssertTrue(window.rootViewController === viewer)
        XCTAssertEqual(DirectAppearanceV1(defaults: defaults).app, .dark)
        appearance.app = .system; XCTAssertEqual(window.overrideUserInterfaceStyle, .unspecified)
        defaults.set("unknown", forKey: DirectAppearanceV1.appKey)
        XCTAssertEqual(DirectAppearanceV1(defaults: defaults).app, .system)
    }

    func testTerminalPaletteIsIndependentAndFollowsAppWhenSelectedWithoutNewSession() throws {
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", addresses: ["127.0.0.1"])
        let session = DirectTerminalSession(mac: mac)
        let controller = TerminalController(session: session)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.overrideUserInterfaceStyle = .light
        window.rootViewController = controller; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil; session.stop() }
        controller.applyAppearance(.dark); window.layoutIfNeeded()
        XCTAssertEqual(controller.terminal.traitCollection.userInterfaceStyle, .dark)
        XCTAssertEqual(controller.terminal.nativeForegroundColor, .white)
        XCTAssertEqual(controller.terminal.nativeBackgroundColor, .black)
        controller.applyAppearance(.light); window.layoutIfNeeded()
        XCTAssertEqual(controller.terminal.nativeForegroundColor, .black)
        XCTAssertEqual(controller.terminal.nativeBackgroundColor, .white)
        controller.applyAppearance(.unspecified); window.overrideUserInterfaceStyle = .dark; window.layoutIfNeeded()
        XCTAssertEqual(controller.terminal.nativeBackgroundColor, .black)
        XCTAssertTrue(controller.session === session); XCTAssertFalse(session.connecting)
        XCTAssertEqual(DirectTerminalAppearance.app.style(app: .light), .light)
        XCTAssertEqual(DirectTerminalAppearance.dark.style(app: .light), .dark)
    }
}
