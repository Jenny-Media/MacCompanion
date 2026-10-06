import XCTest
import SwiftUI
import StoreKitTest
@testable import Mac_Companion

/// Opt-in, hosted Simulator captures. Synthetic records never enter a release target.
@MainActor final class ScreenshotReviewTests: XCTestCase {
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
        for (name, style, appearance) in [("light", UIUserInterfaceStyle.light, DirectAppAppearance.light), ("dark", .dark, .dark)] {
            DirectAppearanceV1.shared.app = appearance
            let viewer = CompanionVNCViewer(); viewer.macName = "Living Room Mac"
            window.overrideUserInterfaceStyle = style; window.rootViewController = viewer; window.makeKeyAndVisible(); viewer.loadViewIfNeeded()
            try await Task.sleep(for: .milliseconds(300)); save(window,name:"login-" + name,folder:folder)
            viewer.setValue(true,forKey:"starting"); (viewer.value(forKey:"progressLabel") as? UILabel)?.text = "Opening desktop…"
            _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
            try await Task.sleep(for: .milliseconds(300)); save(window,name:"connecting-" + name,folder:folder)
            viewer.stop()
        }
    }

    private func capture<V: View>(_ view: V, name: String, window: UIWindow, folder: URL,
                                 style: UIUserInterfaceStyle = .light, largeText: Bool = false) async {
        let host = UIHostingController(rootView: view.environment(DirectAppearanceV1.shared).environment(\.dynamicTypeSize, largeText ? .accessibility3 : .large))
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
