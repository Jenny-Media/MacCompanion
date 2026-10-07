import XCTest
import SwiftUI
import StoreKitTest
@testable import Mac_Companion

/// Opt-in, hosted Simulator captures. Synthetic records never enter a release target.
@MainActor final class ScreenshotReviewTests: XCTestCase {
    func testCaptureImmersiveDesktop() async throws {
        guard ProcessInfo.processInfo.environment["MACCOMPANION_SCREENSHOT_REVIEW"] == "1" else { throw XCTSkip("Opt-in synthetic screenshots only") }
        let folder = URL.documentsDirectory.appending(path: "ImmersiveDesktop")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ready = folder.appending(path: "ready")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.windowLevel = .normal + 1
        let appearance = DirectAppearanceV1.shared, previous = appearance.app
        defer {
            window.endEditing(true); window.isHidden = true; window.rootViewController = nil
            appearance.app = previous; try? FileManager.default.removeItem(at: ready)
        }
        appearance.app = .light
        let mac = try DirectMacRecordV1.normalized(name: "Studio Mac", addresses: ["studio.local"])
        let host = UIHostingController(rootView: DirectDesktopSessionView(mac: mac, showMacs: {}))
        window.rootViewController = host; window.makeKeyAndVisible()
        func controllers(_ root: UIViewController) -> [UIViewController] { [root] + root.children.flatMap(controllers) }
        func capture(_ name: String) async throws {
            save(window, name: name, folder: folder)
            try Data(name.utf8).write(to: ready, options: .atomic)
            try await Task.sleep(for: .seconds(2)); try? FileManager.default.removeItem(at: ready)
        }
        try await Task.sleep(for: .milliseconds(400)); try await capture("login")
        let viewer = try XCTUnwrap(controllers(host).compactMap { $0 as? CompanionVNCViewer }.first)
        defer { viewer.stop() }
        let canvas = try XCTUnwrap(viewer.value(forKey: "canvas") as? UIScrollView)
        let login = try XCTUnwrap(viewer.value(forKey: "login") as? UIView)
        for dark in [false, true] {
            let frame = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 1800)).image { context in
                (dark ? UIColor.black : UIColor.white).setFill(); context.fill(CGRect(x: 0, y: 0, width: 1200, height: 1800))
                let ink = dark ? UIColor.white : UIColor.black
                for row in 0..<36 {
                    ("Desktop row \(row + 1) · Studio Mac" as NSString).draw(at: CGPoint(x: 24, y: row * 50 + 8), withAttributes: [.font: UIFont.systemFont(ofSize: 30), .foregroundColor: ink])
                }
            }
            _ = viewer.perform(NSSelectorFromString("frame:"), with: frame)
            login.isHidden = true; _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
            try await Task.sleep(for: .milliseconds(400)); window.layoutIfNeeded()
            _ = viewer.perform(NSSelectorFromString("fitDesktop"))
            let name = dark ? "dark" : "light"
            try await capture("fit-" + name)
            canvas.setZoomScale(canvas.minimumZoomScale * 2, animated: false)
            canvas.setContentOffset(CGPoint(x: 0, y: 120), animated: false)
            try await Task.sleep(for: .milliseconds(300)); try await capture("pan-" + name)
        }
        _ = viewer.perform(NSSelectorFromString("keyboard"))
        try await Task.sleep(for: .milliseconds(600)); try await capture("keyboard")
        _ = viewer.perform(NSSelectorFromString("showSessionMenu"))
        try await Task.sleep(for: .milliseconds(500)); try await capture("menu")
        viewer.dismiss(animated: false); window.endEditing(true)
        viewer.fullscreen = true; window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(400)); try await capture("controls-hidden")
    }

    func testCaptureImmersiveTerminalEntryAndScrollback() async throws {
        guard ProcessInfo.processInfo.environment["MACCOMPANION_SCREENSHOT_REVIEW"] == "1" else { throw XCTSkip("Opt-in synthetic screenshots only") }
        let folder = URL.documentsDirectory.appending(path: "ImmersiveTerminal")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ready = folder.appending(path: "ready")
        try? FileManager.default.removeItem(at: ready)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.windowLevel = .normal + 1
        let appearance = DirectAppearanceV1.shared, previousApp = appearance.app, previousTerminal = appearance.terminal
        defer {
            window.endEditing(true); window.isHidden = true; window.rootViewController = nil
            appearance.app = previousApp; appearance.terminal = previousTerminal
            try? FileManager.default.removeItem(at: ready)
        }
        func controllers(_ root: UIViewController) -> [UIViewController] { [root] + root.children.flatMap(controllers) }
        func capture(_ name: String) async throws {
            save(window, name: name, folder: folder)
            try Data(name.utf8).write(to: ready, options: .atomic)
            try await Task.sleep(for: .seconds(2))
            try? FileManager.default.removeItem(at: ready)
        }
        let mac = try DirectMacRecordV1.normalized(name: "Studio Mac", addresses: ["studio.local"])
        for (name, palette) in [("light", DirectTerminalAppearance.light), ("dark", .dark)] {
            appearance.app = palette == .dark ? .dark : .light; appearance.terminal = palette
            let session = DirectTerminalSession(mac: mac)
            let host = UIHostingController(rootView: DirectTerminalView(mac: mac, session: session, autoConnect: false, exit: {}).environment(appearance))
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(500)); try await capture("login-" + name)
            session.connected = true
            try await Task.sleep(for: .milliseconds(500))
            let controller = try XCTUnwrap(controllers(host).compactMap { $0 as? TerminalController }.first)
            controller.terminal.feed(text: "Welcome to Studio Mac\r\nLast login: synthetic session\r\ndemo@studio ~ % ")
            try await Task.sleep(for: .milliseconds(500)); try await capture("initial-" + name)
            controller.terminal.feed(text: "\r\n" + (1...100).map { "Scrollback row \($0) · Studio Mac\r\n" }.joined() + "demo@studio ~ % ")
            try await Task.sleep(for: .milliseconds(500))
            controller.terminal.setContentOffset(CGPoint(x: 0, y: controller.terminal.caretFrame.height * 28.5), animated: false)
            try await Task.sleep(for: .milliseconds(300)); try await capture("scroll-" + name)
            _ = controller.terminal.becomeFirstResponder()
            try await Task.sleep(for: .milliseconds(600))
            controller.terminal.setContentOffset(CGPoint(x: 0, y: controller.terminal.caretFrame.height * 42.5), animated: false)
            try await Task.sleep(for: .milliseconds(300)); try await capture("keyboard-scroll-" + name)
            _ = controller.terminal.resignFirstResponder(); session.stop()
        }
    }
    func testCapturePersistentTerminalBar() async throws {
        guard ProcessInfo.processInfo.environment["MACCOMPANION_SCREENSHOT_REVIEW"] == "1" else { throw XCTSkip("Opt-in synthetic screenshots only") }
        let folder = URL.documentsDirectory.appending(path: "PersistentTerminalBar")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ready = folder.appending(path: "ready")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.windowLevel = .normal + 1
        let appearance = DirectAppearanceV1.shared, previousApp = appearance.app, previousTerminal = appearance.terminal
        defer {
            window.endEditing(true); window.isHidden = true; window.rootViewController = nil
            appearance.app = previousApp; appearance.terminal = previousTerminal
            try? FileManager.default.removeItem(at: ready)
        }
        func controllers(_ root: UIViewController) -> [UIViewController] { [root] + root.children.flatMap(controllers) }
        func capture(_ name: String) async throws {
            save(window, name: name, folder: folder)
            try Data(name.utf8).write(to: ready, options: .atomic)
            try await Task.sleep(for: .seconds(2)); try? FileManager.default.removeItem(at: ready)
        }
        let mac = try DirectMacRecordV1.normalized(name: "Studio Mac", addresses: ["studio.local"])
        for (name, palette) in [("light", DirectTerminalAppearance.light), ("dark", .dark)] {
            appearance.app = palette == .dark ? .dark : .light; appearance.terminal = palette
            let session = DirectTerminalSession(mac: mac); session.connected = true
            let host = UIHostingController(rootView: DirectTerminalView(mac: mac, session: session, autoConnect: false, exit: {}).environment(appearance))
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(400))
            let controller = try XCTUnwrap(controllers(host).compactMap { $0 as? TerminalController }.first)
            controller.terminal.feed(text: "Welcome to Studio Mac\r\n" + (1...50).map { "Synthetic output row \($0)\r\n" }.joined() + "demo@studio ~ % ")
            try await Task.sleep(for: .milliseconds(300)); try await capture("terminal-bar-closed-" + name)
            controller.keyboardBar.keyboardButton.sendActions(for: .touchUpInside)
            try await Task.sleep(for: .milliseconds(650)); window.layoutIfNeeded()
            XCTAssertEqual(controller.keyboardBar.bounds.height, 108, accuracy: 1)
            let toolbar = controller.keyboardBar.convert(controller.keyboardBar.bounds, to: window)
            let button = controller.controls.button.convert(controller.controls.button.bounds, to: window)
            XCTAssertTrue(toolbar.contains(button))
            try await capture("terminal-bar-keyboard-" + name)
            controller.controls.button.sendActions(for: .touchUpInside)
            try await Task.sleep(for: .milliseconds(350)); try await capture("terminal-bar-quick-menu-" + name)
            controller.controls.close()
            controller.controls.actionHandler?(["kind": "session"])
            try await Task.sleep(for: .milliseconds(650)); try await capture("terminal-bar-session-menu-" + name)
            controller.dismiss(animated: false); _ = controller.terminal.resignFirstResponder(); session.stop()
        }
    }

    func testCaptureSessionChromeAndKeyboardMenus() async throws {
        guard ProcessInfo.processInfo.environment["MACCOMPANION_SCREENSHOT_REVIEW"] == "1" else { throw XCTSkip("Opt-in Simulator screenshots only") }
        let folder = URL.documentsDirectory.appending(path: "SessionLayoutFix")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ready = folder.appending(path: "ready")
        try? FileManager.default.removeItem(at: ready)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.windowLevel = .normal + 1
        let previousApp = DirectAppearanceV1.shared.app, previousTerminal = DirectAppearanceV1.shared.terminal
        defer {
            window.endEditing(true); window.isHidden = true; window.rootViewController = nil
            DirectAppearanceV1.shared.app = previousApp; DirectAppearanceV1.shared.terminal = previousTerminal
            try? FileManager.default.removeItem(at: ready)
        }
        let mac = try DirectMacRecordV1.normalized(name: "Studio Mac", addresses: ["studio.local"])
        func controllers(_ root: UIViewController) -> [UIViewController] { [root] + root.children.flatMap(controllers) }
        func systemCapture(_ name: String) async throws {
            save(window, name: name, folder: folder)
            try Data(name.utf8).write(to: ready, options: .atomic)
            try await Task.sleep(for: .seconds(2))
            try? FileManager.default.removeItem(at: ready)
        }
        for (name, palette, large) in [("light", DirectTerminalAppearance.light, false), ("dark", .dark, false), ("large", .light, true)] {
            DirectAppearanceV1.shared.app = .light; DirectAppearanceV1.shared.terminal = palette
            let session = DirectTerminalSession(mac: mac); session.connected = true
            let host = UIHostingController(rootView: DirectTerminalView(mac: mac, session: session, autoConnect: false, exit: {})
                .environment(DirectAppearanceV1.shared)
                .environment(\.dynamicTypeSize, large ? .accessibility3 : .large))
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(400))
            let controller = try XCTUnwrap(controllers(host).compactMap { $0 as? TerminalController }.first)
            controller.terminal.feed(text: (1...40).map { "Synthetic output row \($0)\r\n" }.joined() + "demo@studio ~ % ")
            _ = controller.terminal.becomeFirstResponder()
            try await Task.sleep(for: .milliseconds(600))
            try await systemCapture("terminal-dock-" + name)
            controller.controls.actionHandler?(["kind": "session"])
            try await Task.sleep(for: .milliseconds(600))
            try await systemCapture("terminal-keyboard-menu-" + name)
            controller.dismiss(animated: false); _ = controller.terminal.resignFirstResponder(); session.stop()
        }
        DirectAppearanceV1.shared.app = .light
        let host = UIHostingController(rootView: DirectDesktopSessionView(mac: mac, showMacs: {}))
        window.rootViewController = host; window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(400))
        let viewer = try XCTUnwrap(controllers(host).compactMap { $0 as? CompanionVNCViewer }.first)
        let desktop = UIGraphicsImageRenderer(size: CGSize(width: 1280, height: 800)).image { context in
            UIColor.systemIndigo.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1280, height: 800))
            UIColor.white.setFill(); context.fill(CGRect(x: 150, y: 110, width: 980, height: 580))
            ("Synthetic desktop · Studio Mac" as NSString).draw(at: CGPoint(x: 190, y: 150), withAttributes: [.font: UIFont.systemFont(ofSize: 30), .foregroundColor: UIColor.black])
        }
        _ = viewer.perform(NSSelectorFromString("frame:"), with: desktop)
        (viewer.value(forKey: "login") as? UIView)?.isHidden = true
        _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
        try await Task.sleep(for: .milliseconds(500)); try await systemCapture("desktop-canvas-chrome")
        _ = viewer.perform(NSSelectorFromString("showSessionMenu"))
        try await Task.sleep(for: .milliseconds(600)); try await systemCapture("desktop-session-menu")
        viewer.dismiss(animated: false)
        (viewer.value(forKey: "login") as? UIView)?.isHidden = false
        _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
        try await Task.sleep(for: .milliseconds(400)); save(window, name: "desktop-login-theme-restored", folder: folder)
        viewer.stop()
    }

    func testCaptureTrialScreens() async throws {
        guard ProcessInfo.processInfo.environment["MACCOMPANION_SCREENSHOT_REVIEW"] == "1" else {
            throw XCTSkip("Enable only for a dedicated Simulator screenshot review.")
        }
        let folder = URL.documentsDirectory.appending(path: "TrialScreens")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.windowLevel = .normal + 1
        defer { window.isHidden = true; window.rootViewController = nil }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LifetimePro", withExtension: "storekit"))
        let store = try SKTestSession(contentsOf: url); store.disableDialogs = true; store.clearTransactions()
        defer { store.clearTransactions() }
        await DirectProAccess.shared.loadProduct()
        await capture(DirectProView(), name: "01-pro-free-trial", window: window, folder: folder)
        await capture(DirectProView(), name: "02-pro-free-trial-dark", window: window, folder: folder, style: .dark)
        await capture(DirectProView(), name: "03-pro-trial-large-text", window: window, folder: folder, largeText: true)
        await DirectProAccess.shared.startTrial(); XCTAssertTrue(DirectProAccess.shared.trialIsActive)
        await capture(DirectProView(), name: "04-pro-active-trial", window: window, folder: folder)
        await DirectProAccess.shared.purchase(); XCTAssertTrue(DirectProAccess.shared.hasLifetimePro)
        await capture(DirectProView(), name: "05-pro-lifetime", window: window, folder: folder)
    }
    func testCaptureFeatureScreens() async throws {
        guard ProcessInfo.processInfo.environment["MACCOMPANION_SCREENSHOT_REVIEW"] == "1" else {
            throw XCTSkip("Enable only for a dedicated Simulator screenshot review.")
        }
        let folder = URL.documentsDirectory.appending(path: "ScreenshotReview")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .normal + 1
        defer { window.isHidden = true; window.rootViewController = nil }
        let mac = try DirectMacRecordV1.normalized(name: "Living Room Mac", addresses: ["127.0.0.1"])
        let first = try TerminalKeyLibraryStore.add(.create(), name: "Personal Key")
        let second = try TerminalKeyLibraryStore.add(.create(), name: "Work Key")
        defer {
            try? TerminalSecretStore.remove(mac.id)
            try? TerminalKeyLibraryStore.delete(first)
            try? TerminalKeyLibraryStore.delete(second)
        }
        try TerminalKeyLibraryStore.associate(first, macID: mac.id, username: "demo")
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LifetimePro", withExtension: "storekit"))
        let store = try SKTestSession(contentsOf: url)
        store.disableDialogs = true; store.clearTransactions()
        defer { store.clearTransactions() }
        await DirectProAccess.shared.refresh()
        await DirectProAccess.shared.loadProduct()
        await capture(DirectProView(), name: "01-lifetime-pro-free", window: window, folder: folder)
        await DirectProAccess.shared.purchase()
        XCTAssertTrue(DirectProAccess.shared.hasPro)
        await capture(TerminalKeySettings(), name: "02-ssh-key-library", window: window, folder: folder)
        await capture(TerminalKeySettings(mac: mac), name: "03-mac-key-selection", window: window, folder: folder)
        let library = TerminalKeyLibrary(); library.reload()
        let entry = try XCTUnwrap(library.keys.first)
        await capture(NavigationStack { TerminalKeyDetail(entry: entry, library: library, changed: {}) }, name: "09-key-detail-export", window: window, folder: folder)
        await capture(TerminalKeyComposer(importing: false, save: { _, _ in false }), name: "10-create-key", window: window, folder: folder)
        await capture(TerminalKeyComposer(importing: true, save: { _, _ in false }), name: "11-import-key", window: window, folder: folder)
        await capture(TerminalKeyInstallView(mac: mac), name: "04-install-key", window: window, folder: folder)
        try TerminalKeyboardPreferences(keys: [.home, .end, .pageUp, .pageDown, .f1, .f2],
            snippets: [.init(name: "Status", text: "pwd")]).save(mac.id)
        await capture(TerminalKeyboardSettings(macID: mac.id), name: "05-terminal-keyboard-settings", window: window, folder: folder)
        await capture(TerminalKeySettings(), name: "06-key-library-dark", window: window, folder: folder, style: .dark)
        await capture(TerminalKeyInstallView(mac: mac), name: "07-install-key-large-text", window: window, folder: folder, largeText: true)
        let session = DirectTerminalSession(mac: mac)
        let controller = TerminalController(session: session, customize: {})
        window.overrideUserInterfaceStyle = .dark; window.rootViewController = controller; window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        controller.terminal.feed(text: "Synthetic Simulator terminal preview\r\n\r\ndemo@living-room ~ % ")
        _ = controller.terminal.becomeFirstResponder()
        try await Task.sleep(for: .seconds(1))
        save(window, name: "08-terminal-number-modifier-custom-rows", folder: folder)
        try Data().write(to: folder.appending(path: "terminal-ready"))
        try await Task.sleep(for: .seconds(8))
        _ = controller.terminal.resignFirstResponder(); session.stop()
    }

    func testCaptureRecoveryScreens() async throws {
        guard ProcessInfo.processInfo.environment["MACCOMPANION_SCREENSHOT_REVIEW"] == "1" else { throw XCTSkip("Opt-in Simulator screenshots only") }
        let folder = URL.documentsDirectory.appending(path: "RecoveryScreens")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.windowLevel = .normal + 1
        defer { window.isHidden = true; window.rootViewController = nil }
        let mac = DirectMacRecordV1(id: UUID(), name: "Living Room Mac", addresses: ["living-room.local", "100.64.0.8"])
        let session = DirectTerminalSession(mac: mac)
        let file = folder.appending(path: "synthetic-unavailable.json")
        try Data("Synthetic unreadable Macs".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file); session.stop(); try? TerminalSecretStore.remove(mac.id) }
        let macs = DirectMacLibraryV1(url: file, removeLogin: { _ in })
        for (suffix, style, largeText) in [("light", UIUserInterfaceStyle.light, false), ("dark", .dark, false), ("large", .light, true)] {
            await capture(DirectTerminalView(mac: mac, session: session, exit: {}).task {
                try? await Task.sleep(for: .milliseconds(100)); session.recovery = .make(.keyRejected)
            }, name: "terminal-key-rejected-" + suffix, window: window, folder: folder, style: style, largeText: largeText)
            await capture(DirectMacLibraryRootV1(library: macs), name: "saved-macs-unavailable-" + suffix, window: window, folder: folder, style: style, largeText: largeText)
            await capture(DirectMacEditorV1(mac: mac, library: DirectMacLibraryV1(url: folder.appending(path: "synthetic-macs.json"), removeLogin: { _ in })), name: "mac-terminal-access-" + suffix, window: window, folder: folder, style: style, largeText: largeText)
            await capture(TerminalKeyInstallView(mac: mac, initialUsername: "demo"), name: "key-setup-" + suffix, window: window, folder: folder, style: style, largeText: largeText)
            await capture(DirectSavedLoginEditor(mac: mac, service: .desktop), name: "saved-desktop-login-" + suffix, window: window, folder: folder, style: style, largeText: largeText)
            await capture(DirectSavedLoginEditor(mac: mac, service: .terminal), name: "saved-terminal-login-" + suffix, window: window, folder: folder, style: style, largeText: largeText)
            await capture(TerminalServerTrustView(macName: mac.name, fingerprint: "SHA256:exampleFingerprintForSyntheticReviewOnly", answer: { _ in }), name: "verify-server-" + suffix, window: window, folder: folder, style: style, largeText: largeText)
            await capture(ScrollView { DirectRecoveryCard(notice: .make(.setupUncertain), primary: .init(title: "Test Key Login", perform: {}), secondary: .init(title: "Manual Steps", perform: {})).padding(20) }, name: "uncertain-setup-" + suffix, window: window, folder: folder, style: style, largeText: largeText)
        }
        let previousAppearance = DirectAppearanceV1.shared.app; DirectAppearanceV1.shared.app = .dark
        defer { DirectAppearanceV1.shared.app = previousAppearance }
        let viewer = CompanionVNCViewer(); viewer.macName = mac.name
        window.overrideUserInterfaceStyle = .dark; window.rootViewController = viewer; window.makeKeyAndVisible(); viewer.loadViewIfNeeded()
        viewer.showConnectionFailure(); try await Task.sleep(for: .milliseconds(700))
        save(window, name: "desktop-recovery-dark", folder: folder)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1280, height: 800)).image { context in
            UIColor.systemIndigo.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1280, height: 800))
            ("Synthetic inactive desktop" as NSString).draw(at: CGPoint(x: 80, y: 100), withAttributes: [.font: UIFont.systemFont(ofSize: 44), .foregroundColor: UIColor.white])
        }
        _ = viewer.perform(NSSelectorFromString("frame:"), with: image)
        viewer.showConnectionFailure(); try await Task.sleep(for: .milliseconds(700))
        save(window, name: "desktop-last-frame-recovery-dark", folder: folder)
        viewer.stop()
    }

    func testCaptureDesktopLoginAndProgress() async throws {
        guard ProcessInfo.processInfo.environment["MACCOMPANION_SCREENSHOT_REVIEW"] == "1" else { throw XCTSkip("Opt-in Simulator screenshots only") }
        let folder = URL.documentsDirectory.appending(path: "LoginScreens")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.windowLevel = .normal + 1
        let previous = DirectAppearanceV1.shared.app
        defer { window.isHidden = true; window.rootViewController = nil; DirectAppearanceV1.shared.app = previous }
        for (name, style, appearance) in [("light", UIUserInterfaceStyle.light, DirectAppAppearance.light), ("dark", .dark, .dark), ("large", .light, .light)] {
            for inputOnly in [false, true] {
                DirectAppearanceV1.shared.app = appearance
                let viewer = CompanionVNCViewer(); viewer.macName = "Living Room Mac"
                viewer.inputOnly = inputOnly
                let prefix = inputOnly ? "trackpad-" : ""
                viewer.connectionMacNames = ["Living Room Mac", "Studio Mac"]
                if name == "large" { viewer.traitOverrides.preferredContentSizeCategory = .accessibilityExtraLarge }
                window.overrideUserInterfaceStyle = style; window.rootViewController = viewer; window.makeKeyAndVisible(); viewer.loadViewIfNeeded()
                (viewer.value(forKey: "username") as? UITextField)?.text = "alex"
                (viewer.value(forKey: "password") as? UITextField)?.text = "synthetic-only"
                _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
                try await Task.sleep(for: .milliseconds(300)); save(window,name:prefix + "login-" + name,folder:folder)
                viewer.setValue(true,forKey:"starting"); (viewer.value(forKey:"progressLabel") as? UILabel)?.text = "Connecting to Screen Sharing…"
                _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
                try await Task.sleep(for: .milliseconds(300)); save(window,name:prefix + "connecting-" + name,folder:folder)
                viewer.setValue(false, forKey: "starting"); viewer.showRecoveryStage(7)
                try await Task.sleep(for: .milliseconds(300)); save(window, name: prefix + "login-error-" + name, folder: folder)
                (viewer.value(forKey: "loginScroll") as? UIView)?.isHidden = true
                (viewer.value(forKey: "loginBackdrop") as? UIViewController)?.view.isHidden = true
                (viewer.value(forKey: "controls") as? UIView)?.isHidden = false
                (viewer.value(forKey: "toolbar") as? UIView)?.isHidden = false
                _ = viewer.perform(NSSelectorFromString("showSessionMenu"))
                try await Task.sleep(for: .milliseconds(600)); save(window, name: prefix + "desktop-session-menu-" + name, folder: folder)
                viewer.dismiss(animated: false)
                viewer.stop()
            }
        }
    }

    func testCaptureCompactTerminalLoginProgressAndFloatingControls() async throws {
        guard ProcessInfo.processInfo.environment["MACCOMPANION_SCREENSHOT_REVIEW"] == "1" else { throw XCTSkip("Opt-in Simulator screenshots only") }
        let folder = URL.documentsDirectory.appending(path: "SessionUIScreens")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let keyboardReady = folder.appending(path: "keyboard-visible-ready")
        try? FileManager.default.removeItem(at: keyboardReady)
        defer { try? FileManager.default.removeItem(at: keyboardReady) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.windowLevel = .normal + 1
        let previousApp = DirectAppearanceV1.shared.app, previousTerminal = DirectAppearanceV1.shared.terminal
        defer { window.isHidden = true; window.rootViewController = nil; DirectAppearanceV1.shared.app = previousApp; DirectAppearanceV1.shared.terminal = previousTerminal }
        let mac = try DirectMacRecordV1.normalized(name: "Living Room Mac", addresses: ["studio.local"])
        for (name, style, largeText) in [("light", UIUserInterfaceStyle.light, false), ("dark", .dark, false), ("large", .light, true)] {
            DirectAppearanceV1.shared.app = style == .dark ? .dark : .light
            DirectAppearanceV1.shared.terminal = .app
            let session = DirectTerminalSession(mac: mac)
            let view = DirectTerminalView(mac: mac, session: session, autoConnect: false, exit: {})
            await capture(view, name: "terminal-login-" + name, window: window, folder: folder, style: style, largeText: largeText)
            session.connecting = true
            try await Task.sleep(for: .milliseconds(300)); save(window, name: "terminal-progress-" + name, folder: folder)
            session.connecting = false; session.connected = true
            session.connected = false; session.recovery = .make(.loginRejected)
            try await Task.sleep(for: .milliseconds(300)); save(window, name: "terminal-error-" + name, folder: folder)
            session.recovery = .make(.keyRejected)
            try await Task.sleep(for: .milliseconds(300)); save(window, name: "terminal-key-error-" + name, folder: folder)
            if name == "dark" {
                // Cover the reported mismatch: a dark terminal in a light app.
                DirectAppearanceV1.shared.app = .light; DirectAppearanceV1.shared.terminal = .dark
            }
            session.recovery = nil; session.connected = true
            try await Task.sleep(for: .milliseconds(300)); save(window, name: "terminal-connected-" + name, folder: folder)
            func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
            let terminal = try XCTUnwrap(descendants(window).compactMap { $0 as? SessionTerminalView }.first)
            terminal.feed(text: "demo@studio ~ % pwd\r\n/Users/demo\r\ndemo@studio ~ % ")
            let controls = try XCTUnwrap(descendants(window).compactMap { $0 as? CompanionVNCControls }.first)
            controls.button.sendActions(for: .touchUpInside)
            try await Task.sleep(for: .milliseconds(300)); save(window, name: "terminal-controls-" + name, folder: folder)
            controls.close()
            func controllers(_ root: UIViewController) -> [UIViewController] { [root] + root.children.flatMap(controllers) }
            let controller = try XCTUnwrap(window.rootViewController.flatMap { controllers($0).compactMap { $0 as? TerminalController }.first })
            controls.actionHandler?(["kind": "session"])
            try await Task.sleep(for: .milliseconds(600)); save(window, name: "terminal-session-menu-" + name, folder: folder)
            controller.dismiss(animated: false)
            try await Task.sleep(for: .milliseconds(100))
            controls.actionHandler?(["kind": "inputMenu"])
            try await Task.sleep(for: .milliseconds(600)); save(window, name: "terminal-input-menu-" + name, folder: folder)
            controller.dismiss(animated: false)
            try await Task.sleep(for: .milliseconds(100))
            controls.actionHandler?(["kind": "connectionInfo"])
            try await Task.sleep(for: .milliseconds(500)); save(window, name: "terminal-connection-details-" + name, folder: folder)
            controller.dismiss(animated: false)
            controls.close(); _ = terminal.becomeFirstResponder()
            try await Task.sleep(for: .milliseconds(500)); save(window, name: "terminal-keyboard-" + name, folder: folder)
            if name == "dark" {
                // A separate Simulator screenshot includes the system keyboard;
                // drawHierarchy captures only this app window.
                try Data().write(to: keyboardReady)
                try await Task.sleep(for: .seconds(8))
            }
            _ = terminal.resignFirstResponder(); session.stop()
        }
    }

    func testCaptureMenusAboveFloatingControls() async throws {
        guard ProcessInfo.processInfo.environment["MACCOMPANION_SCREENSHOT_REVIEW"] == "1" else { throw XCTSkip("Opt-in synthetic screenshots only") }
        let folder = URL.documentsDirectory.appending(path: "AboveControlsMenus")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.windowLevel = .normal + 1
        let appearance = DirectAppearanceV1.shared, previousApp = appearance.app, previousTerminal = appearance.terminal
        defer {
            window.endEditing(true); window.isHidden = true; window.rootViewController = nil
            appearance.app = previousApp; appearance.terminal = previousTerminal
        }
        func verify(_ presenter: UIViewController, controls: CompanionVNCControls, name: String) async throws {
            try await Task.sleep(for: .milliseconds(650)); window.layoutIfNeeded()
            let navigation = try XCTUnwrap(presenter.presentedViewController as? UINavigationController, name)
            let deadline = Date().addingTimeInterval(3)
            while navigation.transitionCoordinator != nil && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            let popover = try XCTUnwrap(navigation.popoverPresentationController)
            XCTAssertEqual(popover.arrowDirection, .down, name)
            let popup = navigation.view.convert(navigation.view.bounds, to: window)
            let button = controls.button.convert(controls.button.bounds, to: window)
            XCTAssertLessThanOrEqual(popup.maxY, button.minY + 1, name)
            XCTAssertGreaterThanOrEqual(popup.minY, window.safeAreaInsets.top - 1, name)
            save(window, name: name, folder: folder)
            if let menu = navigation.topViewController as? CompanionVNCMenu {
                let section = menu.tableView.numberOfSections - 1
                let last = IndexPath(row: menu.tableView.numberOfRows(inSection: section) - 1, section: section)
                menu.tableView.scrollToRow(at: last, at: .bottom, animated: false)
                menu.tableView.layoutIfNeeded()
                XCTAssertTrue(menu.tableView.bounds.contains(menu.tableView.rectForRow(at: last)), name + " last action reachable")
            }
        }
        func dismiss(_ presenter: UIViewController) async throws {
            await withCheckedContinuation { continuation in
                presenter.dismiss(animated: false) { continuation.resume() }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        for inputOnly in [false, true] {
            appearance.app = .dark
            let viewer = CompanionVNCViewer(); viewer.macName = "Studio Mac"; viewer.inputOnly = inputOnly
            window.rootViewController = viewer; window.overrideUserInterfaceStyle = .dark; window.makeKeyAndVisible(); viewer.loadViewIfNeeded()
            viewer.displayLayout = ["aspectRatio": 1.6, "views": [
                ["id": 1, "title": "Built-in Display", "x": 0, "y": 0, "width": 0.5, "height": 1, "pixelWidth": 640, "pixelHeight": 800],
                ["id": 2, "title": "Studio Display", "x": 0.5, "y": 0, "width": 0.5, "height": 1, "pixelWidth": 640, "pixelHeight": 800]]]
            let frame = UIGraphicsImageRenderer(size: CGSize(width: 1280, height: 800)).image { context in
                UIColor.systemIndigo.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1280, height: 800))
                ("Synthetic desktop · Studio Mac" as NSString).draw(at: CGPoint(x: 100, y: 100), withAttributes: [.font: UIFont.systemFont(ofSize: 30), .foregroundColor: UIColor.white])
            }
            _ = viewer.perform(NSSelectorFromString("frame:"), with: frame)
            (viewer.value(forKey: "login") as? UIView)?.isHidden = true
            _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
            let controls = try XCTUnwrap(viewer.value(forKey: "controls") as? CompanionVNCControls)
            let input = try XCTUnwrap(viewer.value(forKey: "input") as? UITextView)
            let mode = inputOnly ? "trackpad" : "desktop"
            let actions = inputOnly ? ["session", "viewMenu", "inputMenu"] : ["session", "viewMenu", "inputMenu", "keys", "functionKeys", "displays"]
            for keyboard in [false, true] {
                if keyboard { _ = input.becomeFirstResponder() }
                else { _ = input.resignFirstResponder() }
                try await Task.sleep(for: .milliseconds(500)); window.layoutIfNeeded()
                let suffix = keyboard ? "-keyboard" : "-closed"
                controls.button.sendActions(for: .touchUpInside)
                try await Task.sleep(for: .milliseconds(250))
                let panel = try XCTUnwrap(controls.value(forKey: "panel") as? UIView)
                XCTAssertLessThanOrEqual(panel.frame.maxY, controls.button.frame.minY)
                save(window, name: mode + "-quick-actions" + suffix, folder: folder); controls.close()
                for action in actions {
                    controls.actionHandler?(["kind": action])
                    try await verify(viewer, controls: controls, name: mode + "-" + action + suffix)
                    try await dismiss(viewer)
                }
            }
            window.endEditing(true); viewer.stop()
        }
        appearance.app = .light; appearance.terminal = .light
        let mac = try DirectMacRecordV1.normalized(name: "Studio Mac", addresses: ["studio.local"])
        let session = DirectTerminalSession(mac: mac); session.connected = true
        let host = UIHostingController(rootView: DirectTerminalView(mac: mac, session: session, autoConnect: false, exit: {}).environment(appearance))
        window.overrideUserInterfaceStyle = .light; window.rootViewController = host; window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(400))
        func controllers(_ root: UIViewController) -> [UIViewController] { [root] + root.children.flatMap(controllers) }
        let terminal = try XCTUnwrap(controllers(host).compactMap { $0 as? TerminalController }.first)
        terminal.terminal.feed(text: "demo@studio ~ % pwd\r\n/Users/demo\r\ndemo@studio ~ % ")
        for keyboard in [false, true] {
            if keyboard { _ = terminal.terminal.becomeFirstResponder() }
            else { _ = terminal.terminal.resignFirstResponder() }
            try await Task.sleep(for: .milliseconds(500)); window.layoutIfNeeded()
            let suffix = keyboard ? "-keyboard" : "-closed"
            terminal.controls.button.sendActions(for: .touchUpInside)
            try await Task.sleep(for: .milliseconds(250))
            let panel = try XCTUnwrap(terminal.controls.value(forKey: "panel") as? UIView)
            XCTAssertLessThanOrEqual(panel.frame.maxY, terminal.controls.button.frame.minY)
            save(window, name: "terminal-quick-actions" + suffix, folder: folder); terminal.controls.close()
            for action in ["session", "inputMenu", "appearance"] {
                terminal.controls.actionHandler?(["kind": action])
                try await verify(terminal, controls: terminal.controls, name: "terminal-" + action + suffix)
                try await dismiss(terminal)
            }
        }
        window.endEditing(true); session.stop()
    }

    func testCaptureSharedConnectionCardSeparation() async throws {
        guard ProcessInfo.processInfo.environment["MACCOMPANION_SCREENSHOT_REVIEW"] == "1" else { throw XCTSkip("Opt-in Simulator screenshots only") }
        let reduced = ProcessInfo.processInfo.environment["MACCOMPANION_REDUCED_TRANSPARENCY_REVIEW"] == "1"
        if reduced { XCTAssertTrue(UIAccessibility.isReduceTransparencyEnabled, "Capture must use the real system setting") }
        let folder = URL.documentsDirectory.appending(path: reduced ? "ConnectionCardReducedScreens" : "ConnectionCardScreens")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.windowLevel = .normal + 1
        let previous = DirectAppearanceV1.shared.app
        defer { window.isHidden = true; window.rootViewController = nil; DirectAppearanceV1.shared.app = previous }
        let mac = try DirectMacRecordV1.normalized(name: "Studio Mac", addresses: ["studio.local"])
        for (name, style, large, highContrast) in [
            ("light", UIUserInterfaceStyle.light, false, false),
            ("dark", .dark, false, false),
            ("large", .light, true, false),
            ("contrast-dark", .dark, false, true)
        ] {
            if reduced && (large || highContrast) { continue }
            DirectAppearanceV1.shared.app = style == .dark ? .dark : .light
            window.traitOverrides.accessibilityContrast = highContrast ? .high : .normal
            window.traitOverrides.preferredContentSizeCategory = large ? .accessibilityExtraLarge : .large
            for inputOnly in [false, true] {
                let viewer = CompanionVNCViewer(); viewer.macName = mac.name; viewer.inputOnly = inputOnly
                viewer.connectionMacNames = ["Studio Mac", "Living Room Mac"]
                window.overrideUserInterfaceStyle = style; window.rootViewController = viewer; window.makeKeyAndVisible(); viewer.loadViewIfNeeded()
                let mode = inputOnly ? "trackpad" : "desktop"
                for state in ["login", "progress", "error"] {
                    viewer.setValue(state == "progress", forKey: "starting")
                    if state == "error" { viewer.showRecoveryStage(7) }
                    else { (viewer.value(forKey: "progressLabel") as? UILabel)?.text = "Connecting to Screen Sharing…" }
                    _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
                    try await Task.sleep(for: .milliseconds(400)); save(window, name: mode + "-" + state + "-" + name, folder: folder)
                }
                viewer.stop()
            }
            let session = DirectTerminalSession(mac: mac)
            let view = DirectTerminalView(mac: mac, session: session, autoConnect: false, exit: {})
            await capture(view, name: "terminal-login-" + name, window: window, folder: folder,
                          style: style, largeText: large)
            session.connecting = true
            try await Task.sleep(for: .milliseconds(400)); save(window, name: "terminal-progress-" + name, folder: folder)
            session.connecting = false; session.recovery = .make(.loginRejected)
            try await Task.sleep(for: .milliseconds(400)); save(window, name: "terminal-error-" + name, folder: folder)
            session.stop()
        }
    }

    private func capture<V: View>(_ view: V, name: String, window: UIWindow, folder: URL,
                                 style: UIUserInterfaceStyle = .light, largeText: Bool = false) async {
        let host = UIHostingController(rootView: view.environment(DirectAppearanceV1.shared)
            .environment(\.dynamicTypeSize, largeText ? .accessibility3 : .large))
        window.overrideUserInterfaceStyle = style; window.rootViewController = host; window.makeKeyAndVisible()
        try? await Task.sleep(for: .milliseconds(700))
        save(window, name: name, folder: folder)
    }
    private func save(_ window: UIWindow, name: String, folder: URL) {
        window.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        do { try XCTUnwrap(image.pngData()).write(to: folder.appending(path: name + ".png")) }
        catch { XCTFail("Screenshot could not be saved: \(error)") }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}
