import XCTest
import SwiftUI
@testable import Mac_Companion

/// Opt-in hosted screenshots of production views with synthetic content only.
/// Device Hub controls the actual pose. No pose, region or safe area is fabricated.
@MainActor final class DuoComparisonTests: XCTestCase {
    struct Request: Decodable {
        var id: String; var dark: Bool?; var largeText: Bool?; var stop: Bool?
        var screens: [String]?; var externalCapture: Bool?
    }
    private var request: Request?
    private var directory: URL?
    func testInteractiveCapture() async throws {
        guard ProcessInfo.processInfo.environment["MACCOMPANION_DUO_REVIEW"] == "1" else { throw XCTSkip("Dedicated Duo screenshot review only") }
        let directory = URL.documentsDirectory.appending(path: "DuoReview")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for name in ["request.json", "completed", "capture-ready.json", "capture-ack"] { try? FileManager.default.removeItem(at: directory.appending(path: name)) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene); window.windowLevel = .normal + 1
        let previousAppAppearance = DirectAppearanceV1.shared.app
        let previousTerminalAppearance = DirectAppearanceV1.shared.terminal
        let store = directory.appending(path: "synthetic-macs.json")
        try? FileManager.default.removeItem(at: store)
        let library = DirectMacLibraryV1(url: store, removeLogin: { _ in })
        let mac = try DirectMacRecordV1.normalized(name: "Studio Mac", addresses: ["studio.local", "100.64.0.8"])
        for (name, address) in [("Studio Mac", "studio.local"), ("Living Room", "living-room.local"), ("Travel Mac", "travel.local")] {
            _ = library.save(id: nil, name: name, addresses: [address])
        }
        defer {
            window.isHidden = true; window.rootViewController = nil
            DirectAppearanceV1.shared.app = previousAppAppearance
            DirectAppearanceV1.shared.terminal = previousTerminalAppearance
        }
        try Data("ready".utf8).write(to: directory.appending(path: "ready"))
        var last = ""
        let deadline = Date().addingTimeInterval(1800)
        while Date() < deadline {
            if let data = try? Data(contentsOf: directory.appending(path: "request.json")),
               let request = try? JSONDecoder().decode(Request.self, from: data), request.id != last {
                last = request.id; self.request = request; self.directory = directory
                if request.stop == true { return }
                let folder = directory.appending(path: request.id)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                DirectAppearanceV1.shared.app = request.dark == true ? .dark : .light
                DirectAppearanceV1.shared.terminal = .app
                window.overrideUserInterfaceStyle = request.dark == true ? .dark : .light
                window.traitOverrides.preferredContentSizeCategory = request.largeText == true ? .accessibilityExtraLarge : .large
                func wants(_ name: String) -> Bool { request.screens?.contains(name) ?? ["macs", "login", "desktop", "controls", "settings", "ssh-setup", "terminal"].contains(name) }
                if wants("macs") { await capture(UIHostingController(rootView: DirectMacLibraryRootV1(library: library).directAppearance()), window: window, folder: folder, name: "macs") }
                let login = CompanionVNCViewer(); login.macName = mac.name
                if wants("login") { await capture(login, window: window, folder: folder, name: "login") }
                if wants("login-keyboard") {
                    window.rootViewController = login; window.makeKeyAndVisible(); await settle()
                    (login.value(forKey: "username") as? UITextField)?.becomeFirstResponder()
                    await captureState(window, folder: folder, name: "login-keyboard")
                    window.endEditing(true)
                }
                if wants("login-validation") {
                    window.rootViewController = login; window.makeKeyAndVisible(); await settle()
                    login.showInvalidLogin()
                    await captureState(window, folder: folder, name: "login-validation")
                }
                let desktop = CompanionVNCViewer(); desktop.macName = mac.name
                window.rootViewController = desktop; window.makeKeyAndVisible(); desktop.loadViewIfNeeded()
                desktop.perform(NSSelectorFromString("frame:"), with: syntheticDesktop())
                (desktop.value(forKey: "login") as? UIView)?.isHidden = true
                desktop.perform(NSSelectorFromString("updateConnectionChrome"))
                desktop.setValue(true, forKey: "trackpadMode")
                if wants("desktop") { await captureState(window, folder: folder, name: "desktop") }
                let controls = try XCTUnwrap(desktop.value(forKey: "controls") as? CompanionVNCControls)
                controls.quickActions = [
                    ["kind": "setPointer", "title": "Pointer", "symbol": "cursorarrow", "enabled": true],
                    ["kind": "keyboard", "title": "Keyboard", "symbol": "keyboard", "enabled": true],
                    ["kind": "fit", "title": "Fit Display", "enabled": true]]
                if wants("controls") { controls.perform(NSSelectorFromString("open")); await captureState(window, folder: folder, name: "controls"); controls.close() }
                if wants("desktop-keyboard") || wants("controls-keyboard") {
                    desktop.perform(NSSelectorFromString("keyboard")); await settle()
                    if wants("desktop-keyboard") { await captureState(window, folder: folder, name: "desktop-keyboard") }
                    if wants("controls-keyboard") { controls.perform(NSSelectorFromString("open")); await captureState(window, folder: folder, name: "controls-keyboard"); controls.close() }
                    window.endEditing(true)
                }
                if wants("desktop-recovery") { desktop.showConnectionFailure(); await captureState(window, folder: folder, name: "desktop-recovery") }
                desktop.stop()
                if wants("settings") { await capture(UIHostingController(rootView: DirectSessionSettingsV1().directAppearance()), window: window, folder: folder, name: "settings") }
                if wants("ssh-setup") { await capture(UIHostingController(rootView: TerminalKeyInstallView(mac: mac, initialUsername: "demo").directAppearance()), window: window, folder: folder, name: "ssh-setup") }
                if wants("terminal-login") || wants("terminal-login-keyboard") {
                    let session = DirectTerminalSession(mac: mac)
                    let login = UIHostingController(rootView: DirectTerminalView(mac: mac, session: session, exit: {}).directAppearance())
                    window.rootViewController = login; window.makeKeyAndVisible(); await settle()
                    if wants("terminal-login") { await captureState(window, folder: folder, name: "terminal-login") }
                    if wants("terminal-login-keyboard") {
                        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
                        descendants(login.view).compactMap { $0 as? UITextField }.first?.becomeFirstResponder()
                        await captureState(window, folder: folder, name: "terminal-login-keyboard")
                        window.endEditing(true)
                    }
                    session.stop()
                }
                for screen in ["terminal", "terminal-keyboard", "terminal-fullscreen", "terminal-fullscreen-keyboard", "terminal-recovery"] where wants(screen) {
                    let session = DirectTerminalSession(mac: mac); session.connected = true
                    let terminal = UIHostingController(rootView: DirectTerminalView(mac: mac, session: session, fullscreen: screen.contains("fullscreen"), exit: {}).directAppearance())
                    window.rootViewController = terminal; window.makeKeyAndVisible(); await settle()
                    session.received?(Array("Mac Companion — synthetic preview\r\n\r\ndemo@studio ~ % git status\r\nOn branch main\r\nYour branch is up to date.\r\n\r\nnothing to commit, working tree clean\r\n\r\ndemo@studio ~ % ".utf8))
                    if screen.contains("keyboard") { session.toggleKeyboard?() }
                    if screen == "terminal-recovery" { session.connected = false; session.recovery = .make(.macUnreachable) }
                    await captureState(window, folder: folder, name: screen)
                    window.endEditing(true); session.stop()
                }
                window.rootViewController = desktop; window.makeKeyAndVisible(); await settle()
                let division = CompanionVNCActiveDivision(desktop.view)
                var geometry: [String: Any] = ["width": window.bounds.width, "height": window.bounds.height,
                    "safeTop": window.safeAreaInsets.top, "safeLeft": window.safeAreaInsets.left,
                    "safeBottom": window.safeAreaInsets.bottom, "safeRight": window.safeAreaInsets.right]
                geometry["division"] = division.isNull ? NSNull() : ["x": division.minX, "y": division.minY, "width": division.width, "height": division.height] as Any
                geometry["dark"] = request.dark == true; geometry["largeText"] = request.largeText == true
                try JSONSerialization.data(withJSONObject: geometry, options: .sortedKeys).write(to: folder.appending(path: "geometry.json"))
                try Data(request.id.utf8).write(to: directory.appending(path: "completed"))
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        XCTFail("Duo capture was not ended by the review driver")
    }
    private func capture(_ controller: UIViewController, window: UIWindow, folder: URL, name: String) async {
        window.rootViewController = controller; window.makeKeyAndVisible(); await captureState(window, folder: folder, name: name)
    }
    private func captureState(_ window: UIWindow, folder: URL, name: String) async {
        // The RC system keyboard can finish its light/dark glyph transition
        // after the accessory is already laid out. Capture its settled state.
        if name.hasPrefix("terminal") && name.contains("keyboard") { try? await Task.sleep(for: .milliseconds(5200)) }
        else if name.contains("keyboard") { try? await Task.sleep(for: .milliseconds(1200)) }
        await settle(); save(window, folder: folder, name: name)
        guard let request, request.externalCapture == true, let directory else { return }
        let token = request.id + "/" + name
        try? JSONSerialization.data(withJSONObject: ["token": token, "id": request.id, "screen": name]).write(to: directory.appending(path: "capture-ready.json"), options: .atomic)
        let deadline = Date().addingTimeInterval(120)
        while Date() < deadline {
            if (try? String(contentsOf: directory.appending(path: "capture-ack"), encoding: .utf8)) == token { return }
            try? await Task.sleep(for: .milliseconds(150))
        }
        XCTFail("External screenshot was not acknowledged: " + token)
    }
    private func settle() async { try? await Task.sleep(for: .milliseconds(600)) }
    private func save(_ window: UIWindow, folder: URL, name: String) {
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try? image.pngData()?.write(to: folder.appending(path: name + ".png"))
    }
    private func syntheticDesktop() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1440, height: 900)).image { ctx in
            UIColor(red: 0.06, green: 0.13, blue: 0.27, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 1440, height: 900))
            UIColor(white: 0.97, alpha: 1).setFill(); UIBezierPath(roundedRect: CGRect(x: 160, y: 100, width: 1120, height: 700), cornerRadius: 20).fill()
            UIColor(white: 0.91, alpha: 1).setFill(); ctx.fill(CGRect(x: 160, y: 154, width: 235, height: 646))
            for (i, color) in [UIColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                color.setFill(); UIBezierPath(ovalIn: CGRect(x: 184 + i * 24, y: 122, width: 14, height: 14)).fill()
            }
            let ink: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 24, weight: .semibold), .foregroundColor: UIColor(white: 0.13, alpha: 1)]
            ("Studio workspace" as NSString).draw(at: CGPoint(x: 610, y: 114), withAttributes: ink)
            for (i, title) in ["Overview", "Projects", "Documents", "Shared", "Archive"].enumerated() {
                (title as NSString).draw(at: CGPoint(x: 190, y: 194 + i * 64), withAttributes: ink)
            }
            ("Your Mac, within reach." as NSString).draw(at: CGPoint(x: 445, y: 214), withAttributes: [.font: UIFont.systemFont(ofSize: 42, weight: .bold), .foregroundColor: UIColor.black])
            ("A synthetic desktop for layout comparison" as NSString).draw(at: CGPoint(x: 445, y: 278), withAttributes: ink)
            for i in 0..<3 {
                UIColor(red: 0.9, green: 0.94, blue: 1, alpha: 1).setFill(); UIBezierPath(roundedRect: CGRect(x: 445 + i * 244, y: 365, width: 218, height: 204), cornerRadius: 16).fill()
                ("Project \(i + 1)" as NSString).draw(at: CGPoint(x: 465 + i * 244, y: 396), withAttributes: ink)
            }
        }
    }
}
