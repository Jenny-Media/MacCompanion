#if os(iOS)
import SwiftUI
import XCTest
@testable import Mac_Companion

@MainActor final class DesktopSizePreferenceTests: XCTestCase {
    func testDefaultMigrationExplicitMirrorAndPerMacIsolation() {
        let first = UUID(), second = UUID()
        defer { VNCSessionPreferences.clear(first); VNCSessionPreferences.clear(second) }
        XCTAssertEqual(VNCSessionPreferences.desktopSize(first), 2)
        for choice in [0, 1, 2, 3] {
            VNCSessionPreferences.setDesktopSize(choice, mac: first)
            XCTAssertEqual(VNCSessionPreferences.desktopSize(first), choice)
            XCTAssertEqual(VNCSessionPreferences.desktopSize(second), 2)
        }
        for invalid in [-1, 4, Int.max] {
            VNCSessionPreferences.setDesktopSize(invalid, mac: first)
            XCTAssertEqual(VNCSessionPreferences.desktopSize(first), 3)
        }
        VNCSessionPreferences.clear(first)
        XCTAssertEqual(VNCSessionPreferences.desktopSize(first), 2)
        let key = "direct-session-" + first.uuidString.lowercased() + "-desktop-size"
        UserDefaults.standard.set(99, forKey: key)
        XCTAssertEqual(VNCSessionPreferences.desktopSize(first), 2)
        UserDefaults.standard.set("invalid", forKey: key)
        XCTAssertEqual(VNCSessionPreferences.desktopSize(first), 2)
    }

    func testNativeDisplaySettingsRenderAtPhoneAndAccessibilitySizesWithoutSavingDraft() throws {
        let id = UUID()
        defer { VNCSessionPreferences.clear(id) }
        VNCSessionPreferences.setDesktopSize(0, mac: id)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        for category in [DynamicTypeSize.large, .accessibility3] {
            let host = UIHostingController(rootView: Form { DirectDesktopDisplaySection(selection: .constant(2)) }.environment(\.dynamicTypeSize, category))
            window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = host; window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            XCTAssertGreaterThan(host.view.bounds.width, 0)
            XCTAssertEqual(VNCSessionPreferences.desktopSize(id), 0, "Rendering/editing a draft must not change saved preferences")
        }
    }
}
#endif
