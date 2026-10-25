import XCTest
import SwiftUI
@testable import Mac_Companion

/// Opt-in Simulator-only capture driver. It hosts shipping views with local
/// synthetic content; it never connects a Mac or enters a release target.
@MainActor final class AppStoreCaptureTests: XCTestCase {
    private struct Request: Decodable { let id: String; let screen: String; let stop: Bool? }

    func testCaptureReleaseMaterials() async throws {
        guard ProcessInfo.processInfo.environment["MACCOMPANION_STORE_CAPTURE"] == "1" else {
            throw XCTSkip("Opt-in local App Store materials only")
        }
        let folder = URL.documentsDirectory.appending(path: "AppStoreCapture")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .normal + 1
        window.overrideUserInterfaceStyle = .light
        window.traitOverrides.preferredContentSizeCategory = .large
        let oldApp = DirectAppearanceV1.shared.app
        let oldTerminal = DirectAppearanceV1.shared.terminal
        DirectAppearanceV1.shared.app = .light
        DirectAppearanceV1.shared.terminal = .light
        var viewer: CompanionVNCViewer?
        var session: DirectTerminalSession?
        defer {
            viewer?.stop(); session?.stop(); window.endEditing(true)
            window.isHidden = true; window.rootViewController = nil
            DirectAppearanceV1.shared.app = oldApp
            DirectAppearanceV1.shared.terminal = oldTerminal
        }
        let store = folder.appending(path: "synthetic-macs-" + UUID().uuidString + ".json")
        let library = DirectMacLibraryV1(url: store, removeLogin: { _ in })
        XCTAssertTrue(library.save(id: nil, name: "Studio Mac", addresses: ["studio.local"]))
        let mac = try XCTUnwrap(library.macs.first)
        // Choose the shipping mirror mode for this synthetic record.
        UserDefaults.standard.set(0, forKey: VNCSessionPreferences.desktopSizeKey(mac.id))
        let pro = DirectProAccess(readEntitlements: { DirectProSnapshot() })
        await pro.refresh()
        try Data("ready".utf8).write(to: folder.appending(path: "ready"), options: .atomic)
        let deadline = Date().addingTimeInterval(1800)
        var last = ""
        while Date() < deadline {
            guard let bytes = try? Data(contentsOf: folder.appending(path: "request.json")),
                  let request = try? JSONDecoder().decode(Request.self, from: bytes), request.id != last else {
                try await Task.sleep(for: .milliseconds(200)); continue
            }
            last = request.id
            if request.stop == true { return }
            viewer?.stop(); session?.stop(); viewer = nil; session = nil
            window.endEditing(true)
            switch request.screen {
            case "library":
                window.rootViewController = UIHostingController(rootView: DirectMacLibraryRootV1(library: library, pro: pro).directAppearance())
            case "terminal":
                let terminal = DirectTerminalSession(mac: mac)
                terminal.connected = true; session = terminal
                window.rootViewController = UIHostingController(rootView: DirectTerminalView(mac: mac, session: terminal, autoConnect: false, exit: {}).directAppearance())
            case "desktop", "desktop-keyboard", "trackpad", "controls", "composer":
                let desktop = try XCTUnwrap(CompanionVNCDuoSampleWorkspace() as? CompanionVNCViewer)
                desktop.inputOnly = request.screen == "trackpad"
                viewer = desktop; window.rootViewController = desktop
            default:
                XCTFail("Unknown capture screen"); return
            }
            window.makeKeyAndVisible()
            try await Task.sleep(for: .seconds(2))
            if let session {
                session.received?(Array("Studio Mac - synthetic preview\r\n\r\ndemo@studio ~ % pwd\r\n/Users/demo\r\n\r\ndemo@studio ~ % ".utf8))
            }
            if request.screen == "desktop-keyboard" { viewer?.toggleControlsKeyboard() }
            if request.screen == "controls" { _ = viewer?.perform(NSSelectorFromString("showSessionMenu")) }
            if request.screen == "composer" { viewer?.showControlsComposer() }
            try await Task.sleep(for: .seconds(2))
            window.layoutIfNeeded()
            var geometry: [String: Any] = ["screen": request.screen,
                "width": window.bounds.width, "height": window.bounds.height,
                "locale": Locale.current.identifier, "languages": Locale.preferredLanguages,
                "contentSizeCategory": window.traitCollection.preferredContentSizeCategory.rawValue,
                "synthetic": true, "remoteTransport": false]
            if let viewer {
                let division = CompanionVNCActiveDivision(viewer.view)
                geometry["division"] = division.isNull ? NSNull() : ["x": division.minX, "y": division.minY, "width": division.width, "height": division.height] as Any
            }
            try JSONSerialization.data(withJSONObject: geometry, options: .sortedKeys).write(to: folder.appending(path: request.id + "-geometry.json"), options: .atomic)
            try Data(request.id.utf8).write(to: folder.appending(path: "capture-ready"), options: .atomic)
            let ackDeadline = Date().addingTimeInterval(120)
            while (try? String(contentsOf: folder.appending(path: "capture-ack"), encoding: .utf8)) != request.id {
                guard Date() < ackDeadline else { XCTFail("Capture not acknowledged"); return }
                try await Task.sleep(for: .milliseconds(150))
            }
        }
        XCTFail("Capture driver was not stopped")
    }
}
