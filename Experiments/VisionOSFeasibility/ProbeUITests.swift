import XCTest

final class VisionInputFeasibilityUITests: XCTestCase {
    @MainActor func testNativeSelectionAndDrag() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Native visionOS dependency and input probe"].waitForExistence(timeout: 30))
        let location = app.staticTexts["vision-input-probe"]
        XCTAssertTrue(location.exists)
        let before = location.label
        location.tap()
        XCTAssertNotEqual(location.label, before, "System selection must deliver a local coordinate")
        let selected = location.label
        print("Probe bounds: \(location.frame); selection: \(selected)")
        location.swipeRight(velocity: .slow)
        print("Probe after drag: \(location.label)")
        XCTAssertNotEqual(location.label.components(separatedBy: ";").first,
                          selected.components(separatedBy: ";").first,
                          "System drag must update the local coordinate")
    }
    @MainActor func testUIKitPan() {
        let app = XCUIApplication(); app.launch()
        let probe = app.staticTexts["vision-pan-probe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 30))
        let before = probe.label
        probe.swipeRight(velocity: .slow)
        XCTAssertNotEqual(probe.label, before, "UIKit must receive the system pan gesture")
    }
}
