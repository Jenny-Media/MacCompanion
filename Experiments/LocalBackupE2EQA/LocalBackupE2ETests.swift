import XCTest

@MainActor final class LocalBackupE2ETests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    override func tearDown() { XCUIDevice.shared.orientation = .portrait; super.tearDown() }
    private func launch(_ role: String, _ phase: String, edit: Bool = false) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.backupe2e.ios")
        app.launchEnvironment = ["MC_BACKUP_E2E_ROLE": role, "MC_BACKUP_E2E_OBSERVATION": phase]
        if edit { app.launchEnvironment["MC_BACKUP_E2E_EDIT"] = "return-from-B" }
        app.launch()
        XCTAssertTrue(app.navigationBars["Backup & Restore"].waitForExistence(timeout: 10))
        return app
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func scroll(_ app: XCUIApplication, down: Bool = false) {
        let form = app.collectionViews.allElementsBoundByIndex.last(where: { $0.isHittable }) ?? app
        if down { form.swipeDown() } else { form.swipeUp() }
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication, down: Bool = false) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { break }
            scroll(app, down: down)
        }
        XCTAssertTrue(element.exists); XCTAssertTrue(element.isHittable)
    }
    private func folder(_ app: XCUIApplication) {
        let destination = app.cells.matching(NSPredicate(format: "label CONTAINS %@", "Mac Companion Backup QA")).firstMatch
        for _ in 0..<6 where !destination.exists {
            let local = app.cells.matching(NSPredicate(format: "label == %@ OR label == %@", "On My iPhone", "On My iPad")).firstMatch
            if local.exists { local.tap() }
            else if app.buttons["Browse"].firstMatch.exists { app.buttons["Browse"].firstMatch.tap() }
            else if app.buttons["BackButton"].exists { app.buttons["BackButton"].tap() }
            else if app.buttons["DOC.navBarButton.backInHistory"].exists { app.buttons["DOC.navBarButton.backInHistory"].tap() }
        }
        XCTAssertTrue(destination.waitForExistence(timeout: 8))
        destination.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
    }
    private func export(_ app: XCUIApplication, name: String) {
        let create = app.buttons["backup-create"]; reveal(create, app, down: true); create.tap()
        let picker = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8)); folder(app)
        let field = app.textFields["DOCPicker.filenameTextField"]
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 5) { field.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String)?.count ?? 0) + name)
        field.typeText("\n") // Commit the native filename editor before its Save action.
        if !picker.waitForNonExistence(timeout: 2) { app.buttons["DOCPicker.actionButton"].tap() }
        XCTAssertTrue(picker.waitForNonExistence(timeout: 10)); capture(name + "-exported")
    }
    private func select(_ app: XCUIApplication, file: String) {
        let restore = app.buttons["backup-import"]; reveal(restore, app, down: true); restore.tap()
        let picker = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8)); folder(app)
        let item = app.cells.matching(NSPredicate(format: "label CONTAINS %@", file)).firstMatch
        reveal(item, app); item.tap()
        // Files may scroll an icon tile into its final position during the
        // first event. Only retry within the still-present picker.
        if !picker.waitForNonExistence(timeout: 2) {
            XCTAssertTrue(item.exists)
            item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        }
        XCTAssertTrue(picker.waitForNonExistence(timeout: 8))
    }
    private func confirm(_ app: XCUIApplication, previous: Bool = false) {
        let title = previous ? "Previous Data" : "Restore Backup"
        XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 8))
        let button = app.buttons["backup-confirm-restore"]; reveal(button, app); capture(title + "-preview"); button.tap()
        XCTAssertTrue(app.navigationBars[title].waitForNonExistence(timeout: 8))
        reveal(app.buttons["backup-previous"], app); XCTAssertFalse(app.staticTexts["backup-error"].exists)
        capture(title + "-complete")
    }
    func test01ExportSourceA() {
        let app = launch("A", "baseline-a"); export(app, name: "MC-E2E-A"); app.terminate()
        _ = launch("A", "source-a-relaunch"); app.terminate()
    }
    func test02PrepareTargetB() {
        let app = launch("B", "baseline-b"); capture("target-b-before-import"); app.terminate()
    }
    func test03ImportAOnB() {
        let app = launch("B", "import-a-on-b"); select(app, file: "incoming-a.json")
        confirm(app); app.terminate(); _ = launch("B", "import-a-on-b-relaunch"); app.terminate()
    }
    func test04RecoverPreviousB() {
        let app = launch("B", "recover-b")
        let previous = app.buttons["backup-previous"]; reveal(previous, app); previous.tap(); confirm(app, previous: true)
        app.terminate(); _ = launch("B", "recover-b-relaunch"); app.terminate()
    }
    func test05CancelThenRestoreAOnB() {
        let app = launch("B", "cancel-on-b"); select(app, file: "incoming-a.json")
        let cancel = app.buttons["backup-cancel"]; reveal(cancel, app, down: true); cancel.tap()
        XCTAssertTrue(app.navigationBars["Restore Backup"].waitForNonExistence(timeout: 5))
        app.terminate(); _ = launch("B", "cancel-on-b-relaunch"); app.terminate()
        _ = launch("B", "restore-a-again"); select(app, file: "incoming-a.json"); confirm(app); app.terminate()
    }
    func test06EditAndExportReturnB() {
        let app = launch("B", "edited-b", edit: true); export(app, name: "MC-E2E-B-return"); app.terminate()
        _ = launch("B", "edited-b-relaunch"); app.terminate()
    }
    func test07ImportReturnOnA() {
        let app = launch("A", "return-on-a"); select(app, file: "incoming-b-return.json"); confirm(app)
        app.terminate(); _ = launch("A", "return-on-a-relaunch"); app.terminate()
    }
    func test08RecoverPreviousA() {
        let app = launch("A", "recover-a")
        let previous = app.buttons["backup-previous"]; reveal(previous, app); previous.tap(); confirm(app, previous: true)
        app.terminate(); _ = launch("A", "recover-a-relaunch"); app.terminate()
    }
    func test09RejectInvalidFileOnA() {
        let app = launch("A", "invalid-on-a"); select(app, file: "invalid-backup.json")
        let error = app.staticTexts["backup-error"]; reveal(error, app); capture("invalid-backup-rejected")
        app.terminate(); _ = launch("A", "invalid-on-a-relaunch"); app.terminate()
    }
}
