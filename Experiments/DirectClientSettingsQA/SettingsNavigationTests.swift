import XCTest
import UIKit

@MainActor final class SettingsNavigationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCUIDevice.shared.orientation = .portrait
    }
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }
    private func app() -> XCUIApplication {
        XCUIApplication(bundleIdentifier: ProcessInfo.processInfo.environment["MACCOMPANION_SETTINGS_QA_BUNDLE"] ?? "dev.maccompanion.proqa.ios")
    }
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
    func testAddMacShowsFullPortLabelsAndConsistentModeRows() {
        continueAfterFailure = false
        let app = app(); app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["Add Mac"].firstMatch.waitForExistence(timeout: 10)); app.buttons["Add Mac"].firstMatch.tap()
        let row = app.buttons["mac-open-on-tap"]
        for _ in 0..<4 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.isHittable)
        var heights: [CGFloat] = []
        for title in ["Desktop", "Trackpad & Keyboard", "Terminal"] {
            row.tap()
            XCTAssertTrue(app.buttons[title].firstMatch.waitForExistence(timeout: 5))
            app.buttons[title].firstMatch.tap()
            XCTAssertEqual(row.value as? String, title)
            heights.append(row.frame.height)
            capture("ios-open-on-tap-" + title.lowercased().replacingOccurrences(of: " ", with: "-"), app: app)
        }
        XCTAssertLessThan((heights.max() ?? 0) - (heights.min() ?? 0), 2, "Changing modes must keep the same row layout")
        let ports = app.buttons["Service Ports"]
        let form = app.descendants(matching: .any)["mac-editor-form"].firstMatch
        for _ in 0..<4 where !ports.isHittable { form.swipeUp() }
        XCTAssertTrue(ports.isHittable); ports.tap()
        XCTAssertTrue(app.textFields["mac-ssh-port"].waitForExistence(timeout: 5))
        capture("ios-add-mac-ports", app: app)
        app.buttons["Cancel"].firstMatch.tap()
    }
    func testSyncDeletionCanBeCancelledAtBothConfirmationSteps() {
        continueAfterFailure = false
        let app = app(); app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["open-app-settings"].waitForExistence(timeout: 10)); app.buttons["open-app-settings"].tap()
        app.buttons["settings-sync"].tap()
        XCTAssertTrue(app.navigationBars["Sync & Security"].waitForExistence(timeout: 5))
        let toggle = app.switches["icloud-library-toggle"]
        let original = toggle.value as? String
        capture("ios-sync-security", app: app)
        app.buttons["icloud-credentials-info"].tap()
        XCTAssertTrue(app.navigationBars["Credentials & iCloud"].waitForExistence(timeout: 5))
        capture("ios-credentials-info", app: app); app.buttons["Done"].firstMatch.tap()
        app.buttons["What Syncs"].tap()
        capture("ios-what-syncs", app: app)
        app.buttons["What Syncs"].tap()
        app.buttons["Manage Sync"].tap()
        let delete = app.buttons["icloud-delete-data"]
        if !delete.isHittable { app.swipeUp() }
        delete.tap()
        XCTAssertTrue(app.navigationBars["Delete iCloud Data"].waitForExistence(timeout: 5))
        capture("ios-delete-review", app: app)
        app.buttons["icloud-review-continue"].tap()
        XCTAssertTrue(app.alerts["Delete Mac Data from iCloud?"].waitForExistence(timeout: 5))
        app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Delete iCloud Data"].exists)
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Sync & Security"].waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, original, "Cancelling must not disable sync or execute deletion")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Deletion requested.")).firstMatch.exists)
    }
    func testProHasInformationalBenefitsAndAStablePurchaseArea() {
        continueAfterFailure = false
        let app = app(); app.launch(); defer { app.terminate() }
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.buttons["open-app-settings"].waitForExistence(timeout: 10)); app.buttons["open-app-settings"].tap()
        app.buttons["settings-pro"].tap()
        XCTAssertTrue(app.navigationBars["Mac Companion Pro"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["pro-restore"].exists)
        XCTAssertFalse(app.buttons["More Macs and SSH keys"].exists, "A benefit is content, not an inactive button")
        capture("ios-pro", app: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        let restore = app.buttons["pro-restore"]
        let content = app.scrollViews["pro-scroll-content"]
        for _ in 0..<6 where !restore.isHittable { content.swipeUp() }
        XCTAssertTrue(restore.isHittable, "Purchase controls must remain reachable in landscape")
        capture("ios-pro-landscape-purchase-controls", app: app)
    }
    func testGearOpensSettingsAndAppearanceChangesTheExistingSheet() throws {
        continueAfterFailure = false
        let app = XCUIApplication(bundleIdentifier: ProcessInfo.processInfo.environment["MACCOMPANION_SETTINGS_QA_BUNDLE"] ?? "dev.maccompanion.proqa.ios")
        app.launch(); defer { app.terminate() }
        let gear = app.buttons["open-app-settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10)); gear.tap()
        XCTAssertTrue(app.navigationBars["App Settings"].waitForExistence(timeout: 5), "The gear opens Settings directly")
        app.descendants(matching: .any)["settings-appearance"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 5))
        func choose(_ title: String) {
            app.descendants(matching: .any)["app-appearance"].firstMatch.tap()
            app.buttons[title].firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Appearance"].exists, "Keep the existing navigation destination")
        }
        func sample() throws -> Int {
            let image = app.screenshot().image
            let corner = try XCTUnwrap(image.cgImage?.cropping(to: CGRect(x: 3 * image.scale, y: image.size.height * image.scale * 0.8, width: 1, height: 1)))
            var rgba = [UInt8](repeating: 0, count: 4)
            let context = try XCTUnwrap(CGContext(data: &rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(corner, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return Int(rgba[0]) + Int(rgba[1]) + Int(rgba[2])
        }
        choose("Light")
        let light = try sample()
        choose("Dark")
        XCTAssertLessThan(try sample(), light / 2, "The open sheet must immediately render dark")
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "appearance-dark-without-reopening"
        attachment.lifetime = .keepAlways; add(attachment)
        choose("System")
    }
}
