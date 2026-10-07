import XCTest
import SwiftUI
@testable import Mac_Companion

@MainActor final class AppearanceTests: XCTestCase {
    func testDesktopCanvasThemeReachesHostingSafeAreasAndRestoresLoginTheme() async throws {
        let previous = DirectAppearanceV1.shared.app; DirectAppearanceV1.shared.app = .light
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.overrideUserInterfaceStyle = .light
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Desktop", addresses: ["studio.local"])
        let host = UIHostingController(rootView: DirectDesktopSessionView(mac: mac, showMacs: {}))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; DirectAppearanceV1.shared.app = previous }
        try await Task.sleep(for: .milliseconds(300))
        func controllers(_ root: UIViewController) -> [UIViewController] { [root] + root.children.flatMap(controllers) }
        let viewer = try XCTUnwrap(controllers(host).compactMap { $0 as? CompanionVNCViewer }.first)
        let owner = viewer.session
        let login = try XCTUnwrap(viewer.value(forKey: "login") as? UIView)
        login.isHidden = true; _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
        try await Task.sleep(for: .milliseconds(400)); window.layoutIfNeeded()
        XCTAssertEqual(viewer.view.backgroundColor, .black)
        XCTAssertEqual(viewer.preferredStatusBarStyle, .lightContent)
        XCTAssertEqual(host.traitCollection.userInterfaceStyle, .dark)
        XCTAssertEqual(DirectAppearanceV1.shared.app, .light, "Session chrome must not change the saved app theme")
        // Sample only this synthetic host's solid corner, outside the native
        // viewer's safe area. This checks the previous white status strip.
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let pixel = try XCTUnwrap(image.cgImage?.cropping(to: CGRect(x: 2, y: 2, width: 1, height: 1)))
        var rgba = [UInt8](repeating: 0, count: 4)
        let context = try XCTUnwrap(CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertLessThan(Int(rgba[0]) + Int(rgba[1]) + Int(rgba[2]), 20)
        login.isHidden = false; _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(host.traitCollection.userInterfaceStyle, .light)
        XCTAssertEqual(viewer.preferredStatusBarStyle, .darkContent)
        XCTAssertTrue(viewer.session === owner)
        viewer.stop()
    }

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
        let controller = TerminalController(session: session, customize: {})
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.overrideUserInterfaceStyle = .light
        window.rootViewController = controller; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil; session.stop() }
        controller.applyAppearance(.dark); window.layoutIfNeeded()
        XCTAssertEqual(controller.terminal.traitCollection.userInterfaceStyle, .dark)
        XCTAssertEqual(controller.terminal.nativeForegroundColor, .white)
        XCTAssertEqual(controller.terminal.nativeBackgroundColor, .black)
        XCTAssertEqual(controller.view.backgroundColor, .black)
        XCTAssertEqual(controller.preferredStatusBarStyle, .lightContent)
        XCTAssertEqual(controller.controls.traitCollection.userInterfaceStyle, .dark)
        XCTAssertEqual(controller.terminal.inputAccessoryView?.overrideUserInterfaceStyle, .dark)
        controller.applyAppearance(.light); window.layoutIfNeeded()
        XCTAssertEqual(controller.terminal.nativeForegroundColor, .black)
        XCTAssertEqual(controller.terminal.nativeBackgroundColor, .white)
        XCTAssertEqual(controller.view.backgroundColor, .white)
        XCTAssertEqual(controller.preferredStatusBarStyle, .darkContent)
        XCTAssertEqual(controller.terminal.inputAccessoryView?.overrideUserInterfaceStyle, .light)
        controller.applyAppearance(.unspecified); window.overrideUserInterfaceStyle = .dark; window.layoutIfNeeded()
        XCTAssertEqual(controller.terminal.nativeBackgroundColor, .black)
        XCTAssertTrue(controller.session === session); XCTAssertFalse(session.connecting)
        XCTAssertEqual(DirectTerminalAppearance.app.style(app: .light), .light)
        XCTAssertEqual(DirectTerminalAppearance.dark.style(app: .light), .dark)
    }
}
