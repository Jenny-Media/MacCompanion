import XCTest
@testable import Mac_Companion

@MainActor final class TrackpadFeedbackSettingsTests: XCTestCase {
    func testFeedbackDefaultsAndIndependentChoices() {
        let defaults = UserDefaults.standard
        let keys = [VNCSessionPreferences.touchPointsKey, VNCSessionPreferences.trackpadHapticsKey]
        let old = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, old) { defaults.set(value, forKey: key) } }
        for key in keys { defaults.removeObject(forKey: key) }
        XCTAssertTrue(VNCSessionPreferences.showsTouchPoints); XCTAssertTrue(VNCSessionPreferences.trackpadHaptics)
        VNCSessionPreferences.setTrackpadFeedback(showsTouchPoints: false, haptics: true)
        XCTAssertFalse(VNCSessionPreferences.showsTouchPoints); XCTAssertTrue(VNCSessionPreferences.trackpadHaptics)
        VNCSessionPreferences.setTrackpadFeedback(showsTouchPoints: true, haptics: false)
        XCTAssertTrue(VNCSessionPreferences.showsTouchPoints); XCTAssertFalse(VNCSessionPreferences.trackpadHaptics)
    }
    func testSavedFeedbackUpdatesConnectedViewerAndObserverRetires() throws {
        let defaults = UserDefaults.standard
        let keys = [VNCSessionPreferences.touchPointsKey, VNCSessionPreferences.trackpadHapticsKey]
        let old = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, old) { defaults.set(value, forKey: key) } }
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic Mac", addresses: ["studio.local"])
        let coordinator = VNCRemoteDesktopView.Coordinator(mac: mac), viewer = CompanionVNCViewer()
        coordinator.viewer = viewer; coordinator.observeActivity()
        defer { coordinator.stopObserving(); coordinator.activity.finish() }
        VNCSessionPreferences.setTrackpadFeedback(showsTouchPoints: false, haptics: true)
        XCTAssertFalse(viewer.showsTouchPoints); XCTAssertTrue(viewer.trackpadHapticsEnabled)
        VNCSessionPreferences.setTrackpadFeedback(showsTouchPoints: true, haptics: false)
        XCTAssertTrue(viewer.showsTouchPoints); XCTAssertFalse(viewer.trackpadHapticsEnabled)
        coordinator.stopObserving()
        VNCSessionPreferences.setTrackpadFeedback(showsTouchPoints: false, haptics: true)
        XCTAssertTrue(viewer.showsTouchPoints); XCTAssertFalse(viewer.trackpadHapticsEnabled)
    }
}
