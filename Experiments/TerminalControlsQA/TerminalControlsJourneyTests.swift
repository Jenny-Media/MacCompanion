import XCTest
import StoreKitTest

@MainActor final class TerminalControlsJourneyTests: XCTestCase {
    private let itemID = "00000000-0000-0000-0000-00000000C001"
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication, up: Bool = true) {
        for _ in 0..<8 where !element.isHittable {
            if up { app.swipeUp() } else { app.swipeDown() }
        }
        if !element.isHittable {
            capture("terminal-controls-unreachable-control", app: app)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "terminal-controls-accessibility-tree"; tree.lifetime = .keepAlways; add(tree)
        }
        XCTAssertTrue(element.isHittable)
    }
    private func open(_ app: XCUIApplication) {
        app.buttons["controls-qa-open"].tap()
        XCTAssertTrue(app.buttons["terminal-controls-cancel"].waitForExistence(timeout: 5))
        let item = app.buttons["terminal-row-preview-" + itemID]
        XCTAssertTrue(item.waitForExistence(timeout: 5)); item.tap()
    }
    private func rename(_ name: String, app: XCUIApplication, up: Bool = true) {
        let field = app.textFields["terminal-control-name"]
        reveal(field, app: app, up: up)
        let count = (field.value as? String)?.count ?? 0
        field.tap(); field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + name)
    }
    func testCancelAndSingleSavePreserveOneActionAcrossBothPlacements() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.controlsqa.ios")
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["controls-qa-pro"].waitForExistence(timeout: 10))
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LifetimePro", withExtension: "storekit"))
        let store = try SKTestSession(contentsOf: url); store.disableDialogs = true; store.clearTransactions()
        defer { store.clearTransactions() }
        _ = try await store.buyProduct(identifier: "media.jenny.maccompanion.pro.lifetime")
        for _ in 0..<5 where !app.staticTexts["Pro ready"].exists {
            app.buttons["controls-qa-refresh-pro"].tap()
            if app.staticTexts["Pro ready"].waitForExistence(timeout: 2) { break }
        }
        XCTAssertTrue(app.staticTexts["Pro ready"].waitForExistence(timeout: 15), "The app must verify the StoreKit test entitlement")
        open(app); rename("Cancelled", app: app)
        app.buttons["terminal-controls-cancel"].tap()
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 0")
        XCTAssertEqual(app.staticTexts["controls-qa-title"].label, "Project")
        open(app)
        XCTAssertEqual(app.textFields["terminal-control-name"].value as? String, "Project")
        let menu = app.switches["terminal-placement-menu"]
        reveal(menu, app: app); menu.tap()
        rename("Saved Project", app: app, up: false)
        capture("terminal-controls-settings-save", app: app)
        app.buttons["terminal-controls-save"].tap()
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 1")
        XCTAssertEqual(app.staticTexts["controls-qa-title"].label, "Saved Project")
        XCTAssertEqual(app.staticTexts["controls-qa-placements"].label, "Row: on; Menu: off")
        open(app)
        let row = app.switches["terminal-placement-row"]
        reveal(row, app: app)
        XCTAssertEqual(row.value as? String, "1"); XCTAssertEqual(menu.value as? String, "0")
        XCTAssertEqual(app.textFields["terminal-control-name"].value as? String, "Saved Project")
        capture("terminal-controls-settings-persisted", app: app)
        app.buttons["terminal-controls-cancel"].tap()
        XCTAssertEqual(app.staticTexts["controls-qa-writes"].label, "Writes: 1")
    }
}
