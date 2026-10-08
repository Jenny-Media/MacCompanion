import XCTest
@testable import Mac_Companion

@MainActor final class ScrollSettingsTests: XCTestCase {
    func testScrollSpeedDefaultsBoundsInvalidValuesAndPointerIndependence() {
        let defaults = UserDefaults.standard, key = VNCSessionPreferences.scrollSpeedKey
        let old = defaults.object(forKey: key), mac = UUID()
        defer { defaults.set(old, forKey: key); VNCSessionPreferences.clear(mac) }
        defaults.removeObject(forKey: key)
        XCTAssertEqual(VNCSessionPreferences.scrollSpeed, 1)
        VNCSessionPreferences.setSpeed(2.2, mac: mac)
        VNCSessionPreferences.setScrollSpeed(99)
        XCTAssertEqual(VNCSessionPreferences.scrollSpeed, 4)
        VNCSessionPreferences.setScrollSpeed(-1)
        XCTAssertEqual(VNCSessionPreferences.scrollSpeed, 0.25)
        VNCSessionPreferences.setScrollSpeed(2)
        VNCSessionPreferences.setScrollSpeed(.nan)
        VNCSessionPreferences.setScrollSpeed(.infinity)
        XCTAssertEqual(VNCSessionPreferences.scrollSpeed, 2)
        XCTAssertEqual(VNCSessionPreferences.speed(mac), 2.2)
        defaults.set(Double.nan, forKey: key)
        XCTAssertEqual(VNCSessionPreferences.scrollSpeed, 1)
    }
    func testSavingGlobalScrollSpeedUpdatesConnectedViewerWithoutReconnectAndStopsObserving() throws {
        let defaults = UserDefaults.standard, key = VNCSessionPreferences.scrollSpeedKey
        let old = defaults.object(forKey: key)
        defer { defaults.set(old, forKey: key) }
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", addresses: ["studio.local"])
        let coordinator = VNCRemoteDesktopView.Coordinator(mac: mac)
        let viewer = CompanionVNCViewer(); viewer.pointerSpeed = 2.2
        coordinator.viewer = viewer; coordinator.observeActivity()
        defer { coordinator.stopObserving(); coordinator.activity.finish() }
        VNCSessionPreferences.setScrollSpeed(3)
        XCTAssertEqual(viewer.scrollSpeed, 3)
        XCTAssertEqual(viewer.pointerSpeed, 2.2, accuracy: 0.001)
        coordinator.stopObserving()
        VNCSessionPreferences.setScrollSpeed(1)
        XCTAssertEqual(viewer.scrollSpeed, 3)
    }
}
