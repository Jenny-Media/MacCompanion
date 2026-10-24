import XCTest
import SwiftUI
@testable import Mac_Companion

@MainActor final class AppearanceTests: XCTestCase {
    func testAnAlreadyPresentedSettingsSheetTracksAppearanceWithoutReopening() async throws {
        let previous = DirectAppearanceV1.shared.app
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        DirectAppearanceV1.shared.app = .light
        let host = UIHostingController(rootView: AnyView(Color.clear.sheet(isPresented: .constant(true)) {
            DirectSessionSettingsV1()
        }.directAppearance()))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer {
            host.rootView = AnyView(Color.clear)
            host.dismiss(animated: false)
            window.isHidden = true; window.rootViewController = nil
            DirectAppearanceV1.shared.app = previous; previousWindow?.makeKeyAndVisible()
        }
        try await Task.sleep(for: .milliseconds(500))
        let sheet = try XCTUnwrap(host.presentedViewController)
        for choice in [DirectAppAppearance.dark, .light, .dark] {
            DirectAppearanceV1.shared.app = choice
            try await Task.sleep(for: .milliseconds(250)); window.layoutIfNeeded()
            XCTAssertTrue(host.presentedViewController === sheet, "Do not recreate the sheet or reset its navigation")
            XCTAssertEqual(sheet.view.traitCollection.userInterfaceStyle, choice.interfaceStyle)
            let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            })
            attachment.name = "settings-appearance-" + choice.rawValue; attachment.lifetime = .keepAlways; add(attachment)
        }
        host.rootView = AnyView(Color.clear)
        host.dismiss(animated: false)
        try await Task.sleep(for: .milliseconds(300))
    }
    func testConnectionBackdropReachesStatusAreaInProductionHost() async throws {
        let previous = DirectAppearanceV1.shared.app
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", addresses: ["studio.local"])
        defer { window.isHidden = true; window.rootViewController = nil; DirectAppearanceV1.shared.app = previous }
        func controllers(_ root: UIViewController) -> [UIViewController] { [root] + root.children.flatMap(controllers) }
        for style in [UIUserInterfaceStyle.light, .dark] {
            DirectAppearanceV1.shared.app = style == .dark ? .dark : .light
            for inputOnly in [false, true] {
                let host = UIHostingController(rootView: DirectDesktopSessionView(mac: mac, inputOnly: inputOnly, showMacs: {})
                    .ignoresSafeArea(.container, edges: .bottom))
                window.rootViewController = host; window.makeKeyAndVisible()
                try await Task.sleep(for: .milliseconds(300))
                let viewer = try XCTUnwrap(controllers(host).compactMap { $0 as? CompanionVNCViewer }.first)
                let backdrop = try XCTUnwrap(viewer.value(forKey: "loginBackdrop") as? UIViewController)
                let card = try XCTUnwrap(viewer.value(forKey: "login") as? UIView)
                for progress in [false, true] {
                    viewer.setValue(progress, forKey: "starting")
                    _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
                    try await Task.sleep(for: .milliseconds(200)); window.layoutIfNeeded()
                    XCTAssertEqual(backdrop.view.convert(backdrop.view.bounds, to: window).minY, 0, accuracy: 0.5,
                                   "The login backdrop must cover the status area in the SwiftUI host")
                    XCTAssertGreaterThanOrEqual(card.convert(card.bounds, to: window).minY, window.safeAreaInsets.top)
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    func pixel(_ point: CGPoint) throws -> [UInt8] {
                        let crop = try XCTUnwrap(image.cgImage?.cropping(to: CGRect(x: point.x * image.scale, y: point.y * image.scale, width: 1, height: 1)))
                        var rgba = [UInt8](repeating: 0, count: 4)
                        let context = try XCTUnwrap(CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                        context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1)); return rgba
                    }
                    let top = try pixel(CGPoint(x: 1, y: 1))
                    let below = try pixel(CGPoint(x: 1, y: window.safeAreaInsets.top + 1))
                    for channel in 0..<3 { XCTAssertEqual(Int(top[channel]), Int(below[channel]), accuracy: 2, "No color seam below the status bar") }
                }
                viewer.stop()
            }
        }
    }

    func testDesktopReachesStatusAreaButFitAndRestoredViewportUseUnobscuredCanvas() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Desktop", addresses: ["studio.local"])
        let host = UIHostingController(rootView: DirectDesktopSessionView(mac: mac, showMacs: {}))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.endEditing(true); window.isHidden = true; window.rootViewController = nil }
        func controllers(_ root: UIViewController) -> [UIViewController] { [root] + root.children.flatMap(controllers) }
        try await Task.sleep(for: .milliseconds(300))
        let viewer = try XCTUnwrap(controllers(host).compactMap { $0 as? CompanionVNCViewer }.first)
        defer { viewer.stop() }
        let login = try XCTUnwrap(viewer.value(forKey: "login") as? UIView)
        let image = try XCTUnwrap(viewer.value(forKey: "image") as? UIImageView)
        let canvas = try XCTUnwrap(viewer.value(forKey: "canvas") as? UIScrollView)
        let frame = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 1800)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 800, height: 1800))
        }
        _ = viewer.perform(NSSelectorFromString("frame:"), with: frame)
        login.isHidden = true; _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
        try await Task.sleep(for: .milliseconds(400)); window.layoutIfNeeded()
        XCTAssertEqual(canvas.convert(canvas.bounds, to: window).minY, 0, accuracy: 0.5)
        XCTAssertEqual(canvas.contentInset.top, window.safeAreaInsets.top + 8, accuracy: 0.5)
        if #available(iOS 26, *) { XCTAssertEqual(canvas.topEdgeEffect.style, .automatic) }
        _ = viewer.perform(NSSelectorFromString("fitDesktop"))
        let fitted = image.convert(image.bounds, to: window)
        XCTAssertGreaterThanOrEqual(fitted.minY, window.safeAreaInsets.top + 8 - 0.5)
        XCTAssertLessThanOrEqual(fitted.maxY, canvas.convert(canvas.bounds, to: window).maxY + 0.5)
        let owner = viewer.session
        canvas.setZoomScale(canvas.minimumZoomScale * 2, animated: false)
        canvas.setContentOffset(CGPoint(x: 100, y: 120), animated: false)
        window.layoutIfNeeded()
        XCTAssertLessThan(image.convert(image.bounds, to: window).minY, 0, "A zoomed desktop must pan behind status icons")
        _ = viewer.perform(NSSelectorFromString("rememberViewport"))
        let center = try XCTUnwrap(viewer.value(forKey: "resumeCenter") as? NSValue).cgPointValue
        let ratio = try XCTUnwrap(viewer.value(forKey: "resumeZoomRatio") as? NSNumber).doubleValue
        viewer.fullscreen = true; window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        _ = viewer.perform(NSSelectorFromString("rememberViewport"))
        let restored = try XCTUnwrap(viewer.value(forKey: "resumeCenter") as? NSValue).cgPointValue
        XCTAssertEqual(restored.x, center.x, accuracy: 0.01)
        XCTAssertEqual(restored.y, center.y, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(viewer.value(forKey: "resumeZoomRatio") as? NSNumber).doubleValue, ratio, accuracy: 0.01)
        XCTAssertTrue(viewer.session === owner)
        _ = viewer.perform(NSSelectorFromString("keyboard"))
        try await Task.sleep(for: .milliseconds(600)); window.layoutIfNeeded()
        _ = viewer.perform(NSSelectorFromString("rememberViewport"))
        let keyboardCenter = try XCTUnwrap(viewer.value(forKey: "resumeCenter") as? NSValue).cgPointValue
        XCTAssertEqual(keyboardCenter.x, center.x, accuracy: 0.01)
        XCTAssertEqual(keyboardCenter.y, center.y, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(viewer.value(forKey: "resumeZoomRatio") as? NSNumber).doubleValue, ratio, accuracy: 0.01)
        _ = viewer.perform(NSSelectorFromString("keyboard"))
        try await Task.sleep(for: .milliseconds(400)); window.layoutIfNeeded()
        _ = viewer.perform(NSSelectorFromString("rememberViewport"))
        let closedCenter = try XCTUnwrap(viewer.value(forKey: "resumeCenter") as? NSValue).cgPointValue
        XCTAssertEqual(closedCenter.x, center.x, accuracy: 0.01)
        XCTAssertEqual(closedCenter.y, center.y, accuracy: 0.01)
        viewer.inputOnly = true; window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(200)); window.layoutIfNeeded()
        XCTAssertEqual(canvas.contentInset.top, 0)
        XCTAssertTrue(image.isHidden)
        XCTAssertGreaterThanOrEqual(canvas.convert(canvas.bounds, to: window).minY, window.safeAreaInsets.top + 8 - 0.5)
        viewer.inputOnly = false; login.isHidden = false
        _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
        try await Task.sleep(for: .milliseconds(200)); window.layoutIfNeeded()
        XCTAssertEqual(canvas.contentInset.top, 0)
        XCTAssertGreaterThanOrEqual(login.convert(login.bounds, to: window).minY, window.safeAreaInsets.top - 0.5)
    }

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

    func testAppChoicePersistsAndUpdatesNativeWindowsWithoutReplacingViewerOrOwner() async throws {
        let suite = "appearance-qa-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let appearance = DirectAppearanceV1(defaults: defaults)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let viewer = CompanionVNCViewer(); viewer.loadViewIfNeeded()
        let owner = viewer.session
        window.rootViewController = viewer; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil; viewer.stop(); defaults.removePersistentDomain(forName: suite); DirectAppearanceV1.shared.applyWindows() }
        appearance.app = .light
        try await Task.sleep(for: .milliseconds(200)); window.layoutIfNeeded()
        XCTAssertEqual(viewer.traitCollection.userInterfaceStyle, .light)
        appearance.app = .dark
        try await Task.sleep(for: .milliseconds(200)); window.layoutIfNeeded()
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
        XCTAssertEqual(controller.keyboardBar.overrideUserInterfaceStyle, .dark)
        controller.applyAppearance(.light); window.layoutIfNeeded()
        XCTAssertEqual(controller.terminal.nativeForegroundColor, .black)
        XCTAssertEqual(controller.terminal.nativeBackgroundColor, .white)
        XCTAssertEqual(controller.view.backgroundColor, .white)
        XCTAssertEqual(controller.preferredStatusBarStyle, .darkContent)
        XCTAssertEqual(controller.keyboardBar.overrideUserInterfaceStyle, .light)
        controller.applyAppearance(.unspecified); window.overrideUserInterfaceStyle = .dark; window.layoutIfNeeded()
        XCTAssertEqual(controller.terminal.nativeBackgroundColor, .black)
        XCTAssertTrue(controller.session === session); XCTAssertFalse(session.connecting)
        XCTAssertEqual(DirectTerminalAppearance.app.style(app: .light), .light)
        XCTAssertEqual(DirectTerminalAppearance.dark.style(app: .light), .dark)
    }
}

@MainActor private final class VNCSoftwareKeyboardFrame: NSObject {
    var frame = CGRect.null
    @objc func changed(_ notification: Notification) {
        if let value = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue { frame = value.cgRectValue }
    }
}

/// Exercises the SwiftUI-to-UIKit boundary, rather than mounting the viewer
/// directly. The controller owns keyboard avoidance for its canvas and bar.
@MainActor final class VNCKeyboardHostingTests: XCTestCase {
    func testSampleHostKeepsUIKitKeyboardGeometryAndFit() async throws {
        try await verifyHost(AnyView(DuoWorkspaceSample().directDesktopSafeArea()))
    }

    func testProductionHostKeepsUIKitKeyboardGeometryAndFit() async throws {
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic viewport", addresses: ["unused.invalid"])
        try await verifyHost(AnyView(DirectDesktopSessionView(mac: mac, autoConnect: false,
            libraryURL: folder.appending(path: "macs.json"), showMacs: {})))
    }

    private func verifyHost(_ root: AnyView) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: root)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer {
            window.endEditing(true); window.isHidden = true; window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        func controllers(_ root: UIViewController) -> [UIViewController] { [root] + root.children.flatMap(controllers) }
        try await Task.sleep(for: .milliseconds(400)); window.layoutIfNeeded()
        let viewer = try XCTUnwrap(controllers(host).compactMap { $0 as? CompanionVNCViewer }.first)
        defer { viewer.stop() }
        XCTAssertTrue(viewer.preventsAutomaticConnection)
        let image = try XCTUnwrap(viewer.value(forKey: "image") as? UIImageView)
        let canvas = try XCTUnwrap(viewer.value(forKey: "canvas") as? UIScrollView)
        let input = try XCTUnwrap(viewer.value(forKey: "input") as? UITextView)
        if image.image == nil {
            let frame = UIGraphicsImageRenderer(size: CGSize(width: 1440, height: 900)).image { context in
                UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1440, height: 900))
            }
            viewer.perform(NSSelectorFromString("frame:"), with: frame)
            (viewer.value(forKey: "login") as? UIView)?.isHidden = true
            viewer.perform(NSSelectorFromString("updateConnectionChrome"))
        }
        try await Task.sleep(for: .milliseconds(400)); window.layoutIfNeeded()
        viewer.perform(NSSelectorFromString("fitDesktop"))
        let initialHeight = viewer.view.bounds.height
        let owner = viewer.session
        XCTAssertEqual(canvas.zoomScale / canvas.minimumZoomScale, 1, accuracy: 0.01)
        let keyboard = VNCSoftwareKeyboardFrame()
        NotificationCenter.default.addObserver(keyboard, selector: #selector(VNCSoftwareKeyboardFrame.changed),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        defer { NotificationCenter.default.removeObserver(keyboard) }
        XCTAssertTrue(input.becomeFirstResponder())
        for _ in 0..<100 {
            window.layoutIfNeeded()
            if !keyboard.frame.isNull && window.convert(keyboard.frame, from: nil).intersection(window.bounds).height > 100 { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        try await Task.sleep(for: .milliseconds(500)); window.layoutIfNeeded()
        let keyboardRect = window.convert(keyboard.frame, from: nil)
        let keyboardTop = keyboardRect.minY
        XCTAssertFalse(keyboard.frame.isNull)
        XCTAssertGreaterThan(keyboardRect.intersection(window.bounds).height, 100, "A real software keyboard must be visible")
        XCTAssertTrue(input.isFirstResponder)
        XCTAssertEqual(viewer.view.bounds.height, initialHeight, accuracy: 1,
                       "SwiftUI must not shrink a controller that already owns keyboard avoidance")
        let overlap = try XCTUnwrap(viewer.value(forKey: "keyboardOverlap") as? NSNumber).doubleValue
        XCTAssertGreaterThan(overlap, 100, "UIKit must observe the visible keyboard inside its stable view")
        XCTAssertEqual(canvas.zoomScale / canvas.minimumZoomScale, 1, accuracy: 0.01)
        let visible = canvas.convert(canvas.bounds.inset(by: canvas.contentInset), to: window)
            .intersection(CGRect(x: 0, y: 0, width: window.bounds.width, height: keyboardTop))
        let displayed = image.convert(image.bounds, to: window)
        XCTAssertTrue(visible.insetBy(dx: -1, dy: -1).contains(displayed),
                      "The entire fitted synthetic image remains above the actual software keyboard: \(displayed) in \(visible), keyboard \(keyboardRect)")
        XCTAssertTrue(viewer.session === owner)
        NSLog("DuoHostedKeyboard view=%@ window=%@ keyboard=%@ guide=%@ overlap=%.3f ratio=%.6f",
              String(describing: viewer.view.bounds), String(describing: window.bounds), String(describing: keyboardRect),
              String(describing: window.keyboardLayoutGuide.layoutFrame), overlap, canvas.zoomScale / canvas.minimumZoomScale)
        XCTAssertTrue(input.resignFirstResponder())
        try await Task.sleep(for: .milliseconds(500)); window.layoutIfNeeded()
        XCTAssertEqual(viewer.view.bounds.height, initialHeight, accuracy: 1)
        XCTAssertEqual(canvas.zoomScale / canvas.minimumZoomScale, 1, accuracy: 0.01)
        XCTAssertTrue(viewer.session === owner)
    }
}
