import XCTest

@MainActor final class MacShortcutsUITests: XCTestCase {
    private let first = "00000000-0000-0000-0000-000000000011"
    private let second = "00000000-0000-0000-0000-000000000022"
    private func launch(large: Bool = false, dark: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.shortcutsqa.ios")
        app.launchArguments = ["--reset-library"] + (large ? ["--large-text"] : []) + (dark ? ["--dark"] : [])
        app.launch()
        XCTAssertTrue(app.buttons["mac-connect-" + first].waitForExistence(timeout: 10))
        return app
    }
    private func edit(_ app: XCUIApplication, _ id: String) {
        app.buttons["mac-manage-" + id].tap(); app.buttons["Mac Settings"].tap()
        XCTAssertTrue(app.navigationBars["Edit Mac"].waitForExistence(timeout: 5))
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, editor: Bool = false) {
        let list = editor ? app.descendants(matching: .any)["mac-editor-form"].firstMatch : app.collectionViews.element(boundBy: app.collectionViews.count - 1)
        for _ in 0..<12 where !element.isHittable {
            let above = element.exists && !element.frame.isEmpty && element.frame.midY < list.frame.minY
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: above ? 0.25 : 0.85))
            start.press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: above ? 0.85 : 0.25)))
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func openSheet(_ app: XCUIApplication) {
        let shortcuts = app.buttons["mac-shortcuts-open"]; reveal(shortcuts, in: app, editor: true); shortcuts.tap()
        XCTAssertTrue(app.navigationBars["My Macs Shortcuts"].waitForExistence(timeout: 5))
    }
    private func choose(_ gesture: String, _ action: String, app: XCUIApplication) {
        let row = app.buttons[gesture]; reveal(row, in: app); row.tap()
        let option = app.buttons["mac-shortcut-option-" + action]
        XCTAssertTrue(option.waitForExistence(timeout: 4), app.debugDescription)
        if gesture == "mac-open-on-tap" { XCTAssertFalse(app.buttons["mac-shortcut-option-none"].exists) }
        option.tap()
        XCTAssertTrue(app.navigationBars["My Macs Shortcuts"].exists)
    }
    private func capture(_ name: String, app: XCUIApplication) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func previewRow(_ app: XCUIApplication) -> XCUIElement { app.buttons["mac-swipe-preview"] }
    private func fullSwipe(_ row: XCUIElement, left: Bool, app: XCUIApplication) {
        reveal(row, in: app)
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.94 : 0.06, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: left ? 0.002 : 0.998, dy: row.frame.midY / app.frame.height))
        start.press(forDuration: 0.1, thenDragTo: end)
    }
    private func status(_ app: XCUIApplication, contains text: String) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        XCTAssertTrue(app.staticTexts.matching(identifier: "mac-preview-status").matching(predicate).firstMatch.waitForExistence(timeout: 5), app.debugDescription)
    }
    private func done(_ app: XCUIApplication) { app.buttons["mac-shortcut-done"].tap(); XCTAssertTrue(app.navigationBars["Edit Mac"].waitForExistence(timeout: 5)) }
    func testDisplayChoicesCancelSaveAndPerMacIsolation() {
        let app = launch(); defer { app.terminate() }
        edit(app, first)
        let virtual = app.buttons["mac-display-virtual"], mirror = app.buttons["mac-display-mirror"]
        reveal(mirror, in: app, editor: true)
        XCTAssertTrue(virtual.isSelected); mirror.tap(); XCTAssertTrue(mirror.isSelected)
        app.buttons["Cancel"].tap(); edit(app, first); reveal(mirror, in: app, editor: true)
        XCTAssertTrue(virtual.isSelected, "Cancel must discard the draft")
        mirror.tap(); app.buttons["Save"].tap(); edit(app, first); reveal(mirror, in: app, editor: true)
        XCTAssertTrue(mirror.isSelected); capture("mirror-display-choice", app: app)
        app.buttons["Cancel"].tap(); edit(app, second); reveal(mirror, in: app, editor: true)
        XCTAssertTrue(virtual.isSelected, "Display choices must be isolated per Mac")
    }
    func testLargeTextDisplayChoicesAndAdvancedSizesAreReachable() {
        let app = launch(large: true, dark: true); defer { app.terminate() }
        edit(app, first)
        let virtual = app.buttons["mac-display-virtual"], mirror = app.buttons["mac-display-mirror"]
        reveal(virtual, in: app, editor: true); XCTAssertTrue(virtual.isSelected)
        capture("virtual-display-choice-large-text", app: app)
        reveal(mirror, in: app, editor: true); mirror.tap(); XCTAssertTrue(mirror.isSelected)
        reveal(virtual, in: app, editor: true); virtual.tap()
        let advanced = app.buttons["Advanced"]; reveal(advanced, in: app, editor: true); advanced.tap()
        let size = app.buttons["mac-desktop-size"]; reveal(size, in: app, editor: true); size.tap()
        let more = app.buttons["More Space"]; XCTAssertTrue(more.waitForExistence(timeout: 3)); more.tap()
        app.buttons["Save"].tap(); edit(app, first); reveal(virtual, in: app, editor: true)
        XCTAssertTrue(virtual.isSelected)
    }
    func testSharedSheetHasThreeAlignedTwoLineRows() {
        let app = launch(); defer { app.terminate() }
        edit(app, first); openSheet(app)
        let rows = ["mac-open-on-tap", "mac-swipe-left", "mac-swipe-right"].map { app.buttons[$0] }
        for row in rows { reveal(row, in: app) }
        for row in rows {
            XCTAssertEqual(row.frame.minX, rows[0].frame.minX, accuracy: 1)
            XCTAssertEqual(row.frame.width, rows[0].frame.width, accuracy: 1)
            XCTAssertEqual(row.frame.height, rows[0].frame.height, accuracy: 2)
            XCTAssertGreaterThan(row.frame.height, 52)
        }
        capture("shared-shortcuts-sheet", app: app)
    }
    func testOnePreviewSupportsRepeatedTapAndBothNativeFullSwipesWithoutConnecting() {
        let app = launch(); defer { app.terminate() }
        edit(app, first); openSheet(app)
        previewRow(app).tap(); status(app, contains: "Open on Tap → Screen Sharing")
        fullSwipe(previewRow(app), left: true, app: app); status(app, contains: "Swipe Left → Terminal")
        fullSwipe(previewRow(app), left: false, app: app); status(app, contains: "Swipe Right → Trackpad & Keyboard")
        previewRow(app).tap(); previewRow(app).tap(); status(app, contains: "Open on Tap → Screen Sharing")
        capture("shared-preview-tap", app: app)
        done(app); app.buttons["Save"].tap()
        XCTAssertEqual(app.staticTexts["qa-shortcut-route"].label, "No connection opened")
    }
    func testChangingMappingsUpdatesBothDirectionsAndTapInTheSamePreview() {
        let app = launch(); defer { app.terminate() }
        edit(app, first); openSheet(app)
        choose("mac-open-on-tap", "terminal", app: app)
        choose("mac-swipe-left", "desktop", app: app)
        choose("mac-swipe-right", "terminal", app: app)
        let row = previewRow(app); reveal(row, in: app); row.tap(); status(app, contains: "Open on Tap → Terminal")
        row.swipeLeft(); let left = app.buttons["mac-preview-left"]
        XCTAssertTrue(left.waitForExistence(timeout: 3)); XCTAssertEqual(left.label, "Screen Sharing"); left.tap()
        status(app, contains: "Swipe Left → Screen Sharing")
        row.swipeRight(); let right = app.buttons["mac-preview-right"]
        XCTAssertTrue(right.waitForExistence(timeout: 3)); XCTAssertEqual(right.label, "Terminal"); right.tap()
        status(app, contains: "Swipe Right → Terminal")
        capture("shared-preview-right-terminal", app: app)
        done(app); app.buttons["Save"].tap()
        XCTAssertEqual(app.staticTexts["qa-shortcut-route"].label, "No connection opened")
    }
    func testNoneDisablesOnlyItsDirectionAndCancelDiscardsAllDraftChanges() {
        let app = launch(); defer { app.terminate() }
        edit(app, first); openSheet(app)
        choose("mac-swipe-left", "none", app: app)
        XCTAssertEqual(app.buttons["mac-swipe-left"].value as? String, "None")
        let row = previewRow(app); reveal(row, in: app); row.swipeLeft()
        XCTAssertFalse(app.buttons["mac-preview-left"].exists)
        fullSwipe(row, left: false, app: app); status(app, contains: "Swipe Right → Trackpad & Keyboard")
        choose("mac-open-on-tap", "terminal", app: app)
        done(app); app.buttons["Cancel"].tap()
        edit(app, first); openSheet(app)
        XCTAssertEqual(app.buttons["mac-open-on-tap"].value as? String, "Screen Sharing")
        XCTAssertEqual(app.buttons["mac-swipe-left"].value as? String, "Terminal")
    }
    func testSaveRelaunchAndPerMacIndependence() {
        let app = launch(); defer { app.terminate() }
        edit(app, first); openSheet(app)
        choose("mac-open-on-tap", "terminal", app: app); choose("mac-swipe-left", "trackpad", app: app); choose("mac-swipe-right", "none", app: app)
        done(app); app.buttons["Save"].tap()
        app.buttons["mac-connect-" + first].tap()
        XCTAssertEqual(app.staticTexts["qa-shortcut-route"].label, "First Mac · Terminal")
        app.terminate(); app.launchArguments = []; app.launch()
        edit(app, first); openSheet(app)
        XCTAssertEqual(app.buttons["mac-swipe-left"].value as? String, "Trackpad & Keyboard")
        XCTAssertEqual(app.buttons["mac-swipe-right"].value as? String, "None")
        done(app); app.buttons["Cancel"].tap()
        edit(app, second); openSheet(app)
        XCTAssertEqual(app.buttons["mac-swipe-left"].value as? String, "Terminal")
        XCTAssertEqual(app.buttons["mac-swipe-right"].value as? String, "Trackpad & Keyboard")
    }
    func testRealListSwipesStillUseChoicesAndReorderSuppressesThem() {
        let app = launch(); defer { app.terminate() }
        let row = app.buttons["mac-connect-" + first]
        row.swipeLeft(); let left = app.buttons["mac-swipe-left-" + first]
        XCTAssertTrue(left.waitForExistence(timeout: 3)); left.tap()
        XCTAssertEqual(app.staticTexts["qa-shortcut-route"].label, "First Mac · Terminal")
        fullSwipe(row, left: false, app: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "First Mac · Trackpad & Keyboard")).firstMatch.waitForExistence(timeout: 3))
        app.buttons["macs-edit-order"].tap(); row.swipeLeft()
        XCTAssertFalse(app.buttons["mac-swipe-left-" + first].exists)
        XCTAssertFalse(app.buttons["mac-manage-" + first].exists)
    }
    func testLargeTextDarkSheetKeepsPreviewAndAllChoicesReachable() {
        let app = launch(large: true, dark: true); defer { app.terminate() }
        edit(app, first); openSheet(app)
        XCTAssertGreaterThan(app.buttons["mac-open-on-tap"].frame.height, 70)
        let row = previewRow(app); row.swipeRight()
        let right = app.buttons["mac-preview-right"]; XCTAssertTrue(right.waitForExistence(timeout: 3)); right.tap()
        status(app, contains: "Swipe Right → Trackpad & Keyboard")
        capture("shared-shortcuts-large-dark", app: app)
        for gesture in ["mac-open-on-tap", "mac-swipe-left", "mac-swipe-right"] { choose(gesture, "trackpad", app: app) }
        choose("mac-swipe-right", "none", app: app)
        done(app); app.buttons["Cancel"].tap()
    }
    func testLandscapeSheetKeepsChoicesAndDoneReachable() {
        let app = launch(large: true); defer { XCUIDevice.shared.orientation = .portrait; app.terminate() }
        app.terminate(); XCUIDevice.shared.orientation = .landscapeLeft
        app.launchArguments = ["--large-text"]; app.launch()
        XCTAssertTrue(app.buttons["mac-connect-" + first].waitForExistence(timeout: 10))
        edit(app, first); openSheet(app)
        choose("mac-open-on-tap", "trackpad", app: app); choose("mac-swipe-left", "none", app: app); choose("mac-swipe-right", "terminal", app: app)
        done(app); app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["mac-connect-" + first].waitForExistence(timeout: 5))
    }
}
