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
        let add = app.buttons["macs-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10)); add.tap()
        let host = app.textFields["quick-connect-host"]
        XCTAssertTrue(host.waitForExistence(timeout: 5)); host.tap(); host.typeText("synthetic.invalid")
        app.buttons["quick-connect-options"].tap()
        XCTAssertTrue(app.navigationBars["Connection Options"].waitForExistence(timeout: 5))
        for title in ["Screen Sharing", "Trackpad & Keyboard", "Terminal"] {
            let row = app.buttons[title].firstMatch
            for _ in 0..<4 where !row.isHittable { app.swipeUp() }
            XCTAssertTrue(row.isHittable); row.tap()
        }
        let port = app.textFields["quick-connect-ssh-port"]
        for _ in 0..<4 where !port.isHittable { app.swipeUp() }
        XCTAssertTrue(port.isHittable); capture("ios-connection-options", app: app)
        app.navigationBars["Connection Options"].buttons.firstMatch.tap()
        app.buttons["quick-connect-cancel"].tap()
    }
    func testSyncConsentRowsAndActionsRemainReachableWithoutEnablingSync() {
        continueAfterFailure = false
        for large in [false, true] {
            let app = app()
            if large { app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"] }
            app.launch(); defer { app.terminate() }
            XCTAssertTrue(app.buttons["open-app-settings"].waitForExistence(timeout: 10))
            app.buttons["open-app-settings"].tap()
            app.buttons["settings-sync"].tap()
            let toggle = app.switches["icloud-library-toggle"]
            XCTAssertEqual(toggle.value as? String, "0", "This QA journey requires sync to remain off")
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            XCTAssertTrue(app.staticTexts["Enable iCloud Sync?"].waitForExistence(timeout: 5))
            for identifier in ["icloud-enable-synced", "icloud-enable-local"] {
                let row = app.descendants(matching: .any)[identifier].firstMatch
                XCTAssertTrue(row.exists)
                for _ in 0..<4 where !row.isHittable { app.swipeUp() }
                XCTAssertTrue(row.isHittable)
            }
            let footer = app.staticTexts["Encrypted iCloud sync"]
            for _ in 0..<4 where !footer.isHittable { app.swipeUp() }
            XCTAssertTrue(footer.isHittable)
            let confirm = app.buttons["icloud-enable-confirm"]
            let cancel = app.buttons["icloud-enable-cancel"]
            XCTAssertTrue(confirm.isHittable)
            XCTAssertTrue(cancel.isHittable)
            capture(large ? "icloud-consent-large-text" : "icloud-consent", app: app)
            if !large {
                XCUIDevice.shared.orientation = .landscapeLeft
                XCTAssertEqual(XCUIDevice.shared.orientation, .landscapeLeft)
                XCTAssertTrue(cancel.isHittable)
                let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                screenshot.name = "icloud-consent-rotated"; screenshot.lifetime = .keepAlways
                add(screenshot)
            }
            cancel.tap()
            XCUIDevice.shared.orientation = .portrait
            XCTAssertTrue(app.navigationBars["Sync & Security"].waitForExistence(timeout: 5))
            XCTAssertEqual(toggle.value as? String, "0", "Reviewing and cancelling must not enable sync")
            app.terminate()
        }
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
    func testGestureGuideLivesInSettingsAndRemainsReachableWithLargeText() {
        continueAfterFailure = false
        for large in [false, true] {
            let app = app()
            if large { app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"] }
            app.launch()
            XCTAssertTrue(app.buttons["open-app-settings"].waitForExistence(timeout: 10))
            app.buttons["open-app-settings"].tap()
            let guide = app.buttons["settings-gesture-guide"]
            for _ in 0..<4 where !guide.isHittable { app.swipeUp() }
            XCTAssertTrue(guide.isHittable); guide.tap()
            XCTAssertTrue(app.navigationBars["Gesture Guide"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Screen Sharing"].exists)
            capture(large ? "gesture-guide-large-text" : "gesture-guide", app: app)
            app.navigationBars.buttons["App Settings"].tap()
            XCTAssertTrue(app.navigationBars["App Settings"].exists)
            app.terminate()
        }
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
