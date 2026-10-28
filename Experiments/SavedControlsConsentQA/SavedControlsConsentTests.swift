import XCTest

@MainActor final class SavedControlsConsentTests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }
    override func tearDown() { XCUIDevice.shared.orientation = .portrait; super.tearDown() }
    private func launch(large: Bool) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "dev.maccompanion.savedcontrolsqa.ios")
        if large { app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"] }
        app.launch(); return app
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func scrollForm(_ app: XCUIApplication, down: Bool = false) {
        // iPad presents a smaller form sheet. A whole-app swipe can land on
        // the obscured page; target the frontmost hittable vertical form.
        let form = app.collectionViews.allElementsBoundByIndex.last(where: { $0.isHittable }) ?? app
        if down { form.swipeDown() } else { form.swipeUp() }
    }
    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { break }
            scrollForm(app)
        }
        XCTAssertTrue(element.exists)
        XCTAssertTrue(element.isHittable)
    }
    private func tapSwitch(_ element: XCUIElement, app: XCUIApplication) {
        reveal(element, app: app)
        let thumb = element.switches.firstMatch; XCTAssertTrue(thumb.exists); thumb.tap()
    }
    private func revealConsentFooter(_ footer: XCUIElement, app: XCUIApplication) {
        let confirm = app.buttons["icloud-enable-confirm"]
        for _ in 0..<6 {
            if footer.frame.maxY <= confirm.frame.minY - 8 { break }
            // isHittable also accepts partially visible text. Drag inside the
            // modal content rather than the underlying iPad form or action bar.
            let startY = confirm.frame.minY - 30
            let top = app.staticTexts["Enable iCloud Sync?"].frame.minY
            let endY = max(app.frame.minY + 100, min(top + 40, startY - 100))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: confirm.frame.midX - app.frame.minX, dy: startY - app.frame.minY))
            let end = origin.withOffset(CGVector(dx: confirm.frame.midX - app.frame.minX, dy: endY - app.frame.minY))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertLessThanOrEqual(footer.frame.maxY, confirm.frame.minY - 8, "The complete encryption note must scroll clear of the pinned actions")
    }
    func testManualBackupPreviewCancelRestoreAndRecovery() {
        for large in [false, true] {
            let app = launch(large: large); defer { app.terminate() }
            let route = app.buttons["fixture-backupPreview"]
            reveal(route, app: app); route.tap()
            let restore = app.buttons["backup-confirm-restore"]
            XCTAssertTrue(app.navigationBars["Restore Backup"].waitForExistence(timeout: 8))
            capture("manual-backup-preview" + (large ? "-large-text" : ""))
            reveal(restore, app: app)
            capture("manual-backup-preview-action" + (large ? "-large-text" : ""))
            dismissBackupPreview(app)
            XCTAssertTrue(app.buttons["backup-create"].waitForExistence(timeout: 5))
            capture("manual-backup-home" + (large ? "-large-text" : ""))
            dismissBackupHome(app)
            XCTAssertEqual(app.staticTexts["fixture-backup-macs"].label, "Saved Macs: Current Mac")
            reveal(route, app: app); route.tap()
            XCTAssertTrue(app.navigationBars["Restore Backup"].waitForExistence(timeout: 8)); reveal(restore, app: app); restore.tap()
            let previous = app.buttons["backup-previous"]
            XCTAssertTrue(app.navigationBars["Backup & Restore"].waitForExistence(timeout: 8)); reveal(previous, app: app)
            capture("manual-backup-restored" + (large ? "-large-text" : ""))
            dismissBackupHome(app)
            XCTAssertEqual(app.staticTexts["fixture-backup-macs"].label, "Saved Macs: Restored Mac")
            let manual = app.buttons["fixture-backup"]
            reveal(manual, app: app); manual.tap()
            reveal(previous, app: app); previous.tap()
            XCTAssertTrue(app.navigationBars["Previous Data"].waitForExistence(timeout: 5)); reveal(restore, app: app)
            capture("manual-backup-recovery" + (large ? "-large-text" : ""))
            restore.tap()
            XCTAssertTrue(app.navigationBars["Previous Data"].waitForNonExistence(timeout: 8))
            reveal(app.staticTexts["backup-status"], app: app)
            dismissBackupHome(app)
            XCTAssertEqual(app.staticTexts["fixture-backup-macs"].label, "Saved Macs: Current Mac")
            app.terminate()
        }
    }
    private func dismissBackupPreview(_ app: XCUIApplication) {
        let cancel = app.buttons["backup-cancel"]
        // Duo hides navigation chrome while scrolling. Reverse the scroll
        // before using its native toolbar, then verify the dialog closed.
        for _ in 0..<8 {
            if cancel.exists && cancel.isHittable { break }
            scrollForm(app, down: true)
        }
        XCTAssertTrue(cancel.exists); XCTAssertTrue(cancel.isHittable); cancel.tap()
        XCTAssertTrue(app.navigationBars["Restore Backup"].waitForNonExistence(timeout: 5))
    }
    private func dismissBackupHome(_ app: XCUIApplication) {
        let done = app.buttons["Done"].firstMatch
        for _ in 0..<8 {
            if done.exists && done.isHittable { break }
            scrollForm(app, down: true)
        }
        XCTAssertTrue(done.isHittable); done.tap()
        XCTAssertTrue(app.navigationBars["Backup & Restore"].waitForNonExistence(timeout: 5))
    }
    private func dismissBackupFilePicker(_ app: XCUIApplication) {
        let picker = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        let cancel = app.buttons["Cancel"].firstMatch
        if cancel.exists { cancel.tap() }
        else {
            // Newer Files pickers use the native sheet-dismiss gesture.
            let start = picker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
            let end = start.withOffset(CGVector(dx: 0, dy: app.frame.height * 0.7))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
    }
    func testManualBackupSystemPickersCancelWithoutChanges() {
        let app = launch(large: false); defer { app.terminate() }
        let manual = app.buttons["fixture-backup"]
        reveal(manual, app: app); manual.tap()
        app.buttons["backup-create"].tap()
        dismissBackupFilePicker(app)
        XCTAssertTrue(app.buttons["backup-import"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["backup-error"].exists)
        app.buttons["backup-import"].tap()
        dismissBackupFilePicker(app)
        XCTAssertTrue(app.buttons["backup-create"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["backup-error"].exists)
        XCTAssertFalse(app.buttons["backup-previous"].exists)
        dismissBackupHome(app)
        XCTAssertEqual(app.staticTexts["fixture-backup-macs"].label, "Saved Macs: Current Mac")
    }
    func testManualBackupFilesRoundTrip() {
        let app = launch(large: false); defer { app.terminate() }
        let manual = app.buttons["fixture-backup"]
        reveal(manual, app: app); manual.tap()
        app.buttons["backup-create"].tap()
        let picker = app.navigationBars["FullDocumentManagerViewControllerNavigationBar"]
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        let name = "Mac Companion QA " + UUID().uuidString.prefix(8)
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.exists); field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let keyboard = app.keyboards.firstMatch
        if !keyboard.waitForExistence(timeout: 5) { field.tap() }
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8))
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (field.value as? String)?.count ?? 0) + name)
        // Commit the iPad filename edit before using the Files toolbar.
        let hideKeyboard = app.buttons["Hide keyboard"].firstMatch
        if hideKeyboard.exists { hideKeyboard.tap() }
        app.buttons["DOCPicker.actionButton"].tap()
        XCTAssertTrue(picker.waitForNonExistence(timeout: 8))
        app.buttons["backup-import"].tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 8))
        let file = app.cells.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 8))
        file.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)).tap()
        XCTAssertTrue(app.navigationBars["Restore Backup"].waitForExistence(timeout: 8))
        capture("manual-backup-files-roundtrip")
        dismissBackupPreview(app)
        XCTAssertFalse(app.buttons["backup-previous"].exists)
        dismissBackupHome(app)
        XCTAssertEqual(app.staticTexts["fixture-backup-macs"].label, "Saved Macs: Current Mac")
    }
    func testOneSyncConfirmationIncludesSavedContentAndHasNoSeparateOption() {
        for large in [false, true] {
            let app = launch(large: large); defer { app.terminate() }
            app.buttons["fixture-sync"].tap()
            let toggle = app.switches["icloud-library-toggle"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 10)); XCTAssertEqual(toggle.value as? String, "0")
            XCTAssertFalse(app.switches["icloud-saved-content-toggle"].exists)
            tapSwitch(toggle, app: app)
            XCTAssertTrue(app.staticTexts["Enable iCloud Sync?"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Saved Macs, keyboard layouts, shortcuts and saved text."].exists)
            let footer = app.staticTexts["Encrypted iCloud sync"]
            revealConsentFooter(footer, app: app)
            XCTAssertTrue(app.buttons["icloud-enable-confirm"].isHittable)
            XCTAssertTrue(app.buttons["icloud-enable-cancel"].isHittable)
            capture(large ? "unified-sync-large-text" : "unified-sync")
            if !large {
                XCUIDevice.shared.orientation = .landscapeLeft
                XCTAssertTrue(app.buttons["icloud-enable-cancel"].isHittable); capture("unified-sync-rotated")
            }
            app.buttons["icloud-enable-cancel"].tap(); XCUIDevice.shared.orientation = .portrait
            XCTAssertEqual(toggle.value as? String, "0")
            tapSwitch(toggle, app: app)
            app.buttons["icloud-enable-confirm"].tap()
            XCTAssertEqual(toggle.value as? String, "1")
            XCTAssertTrue(app.staticTexts["icloud-summary"].exists)
            capture(large ? "sync-enabled-large-text" : "sync-enabled")
            XCTAssertFalse(app.switches["icloud-saved-content-toggle"].exists)
            tapSwitch(toggle, app: app); XCTAssertEqual(toggle.value as? String, "0")
            app.terminate()
        }
    }
    func testSyncDetailsAndManagementUseSeparateScreensAndScopedDeletion() {
        for large in [false, true] {
            for page in ["what-syncs", "manage-sync"] {
                let app = launch(large: large)
                app.buttons["fixture-sync"].tap()
                capture("sync-home-" + page + (large ? "-large" : ""))
                app.buttons["icloud-" + page].tap()
                if page == "what-syncs" {
                    XCTAssertTrue(app.navigationBars["What Syncs"].waitForExistence(timeout: 5))
                    XCTAssertTrue(app.staticTexts["Across devices"].exists)
                    capture("sync-scope-top" + (large ? "-large" : ""))
                    reveal(app.buttons["icloud-credentials-info"], app: app)
                    capture("sync-scope-local" + (large ? "-large" : ""))
                } else {
                    XCTAssertTrue(app.navigationBars["Manage Sync"].waitForExistence(timeout: 5))
                    let delete = app.buttons["icloud-delete-data"]
                    reveal(delete, app: app)
                    XCTAssertTrue(delete.label.contains("Delete Synced Data from iCloud"))
                    capture("sync-manage" + (large ? "-large" : ""))
                    delete.tap()
                    XCTAssertTrue(app.navigationBars["Delete iCloud Data"].waitForExistence(timeout: 5))
                    reveal(app.staticTexts["Saved Macs, preferences, keyboard layouts, shortcuts and saved text."], app: app)
                    capture("sync-deletion-scope" + (large ? "-large" : ""))
                    XCTAssertTrue(app.buttons["icloud-review-continue"].isHittable)
                    app.buttons["Cancel"].firstMatch.tap()
                    XCTAssertTrue(app.navigationBars["Manage Sync"].waitForExistence(timeout: 5))
                }
                app.terminate()
            }
        }
    }

    func testEnablingSyncNeedsNoAdditionalSetup() {
        let app = launch(large: false); defer { app.terminate() }
        app.buttons["fixture-sync"].tap()
        tapSwitch(app.switches["icloud-library-toggle"], app: app)
        app.buttons["icloud-enable-confirm"].tap()
        XCTAssertEqual(app.switches["icloud-library-toggle"].value as? String, "1")
        XCTAssertFalse(app.buttons["icloud-controls-setup"].exists)
        XCTAssertFalse(app.staticTexts["Finish setting up saved controls."].exists)
        XCTAssertFalse(app.navigationBars["Set Up Controls"].exists)
        capture("sync-automatic")
        app.buttons["icloud-manage-sync"].tap()
        XCTAssertTrue(app.buttons["Refresh iCloud"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Finish Controls Setup"].exists)
        capture("sync-automatic-management")
    }
    func testGuidanceRowsAndSecurityDetailsStayReachable() {
        let routes: [(String, String, String)] = [
            ("gestures", "Gesture Guide", "Customize"),
            ("setup", "Set Up Your Mac", "Your Mac account"),
            ("trust", "Verify This Mac", "2. Match the key type"),
            ("identity", "Verify Server Identity", "3. Verify again"),
            ("manual", "Manual Key Setup", "5. Test the key"),
            ("keyImport", "Import SSH Key", "Ed25519 OpenSSH keys only, up to 32 KiB. Import passphrases are used once and never saved.")
        ]
        for large in [false, true] {
            for (route,title,last) in routes {
                // Passive guidance capture does not assume where system chrome
                // puts modal/navigation buttons in the current Duo fold shape.
                let app = launch(large: large)
                let button = app.buttons["fixture-" + route]; reveal(button, app: app); button.tap()
                XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
                reveal(app.staticTexts[last], app: app)
                if route == "trust" {
                    XCTAssertTrue(app.staticTexts["ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub"].exists)
                    XCTAssertTrue(app.buttons["server-trust-cancel"].isHittable)
                }
                capture("copy-" + route + (large ? "-large-text" : ""))
                if route == "trust" {
                    app.buttons["server-trust-cancel"].tap()
                    XCTAssertTrue(app.navigationBars["Copy QA"].waitForExistence(timeout: 5))
                }
                app.terminate()
            }
        }
    }
    func testRecoveryNoticeIsVisibleAndLeadsToLayoutWithUndo() {
        for large in [false, true] {
            let app = launch(large: large); defer { app.terminate() }
            reveal(app.buttons["fixture-recoveryNotice"], app: app); app.buttons["fixture-recoveryNotice"].tap()
            let notice = app.buttons["icloud-recovery-notice"]
            reveal(notice, app: app); capture(large ? "recovery-notice-large" : "recovery-notice")
            notice.tap()
            XCTAssertTrue(app.navigationBars["Recovered Changes"].waitForExistence(timeout: 5))
            app.buttons["icloud-recovered-fixture-text"].tap()
            reveal(app.buttons["icloud-recovered-restore"], app: app); app.buttons["icloud-recovered-restore"].tap()
            // Duo places the system back button in its side rail toolbar.
            let back = app.buttons["BackButton"]
            XCTAssertTrue(back.waitForExistence(timeout: 5)); back.tap()
            XCTAssertTrue(notice.waitForExistence(timeout: 5)); reveal(notice, app: app)
            XCTAssertTrue(notice.label.contains("Review Layout"))
            capture(large ? "recovery-layout-notice-large" : "recovery-layout-notice")
            notice.tap()
            let explanation = app.staticTexts["This is a saved alternative. Your current layout is still in use."]
            reveal(explanation, app: app)
            XCTAssertTrue(app.otherElements["icloud-recovery-preview-current"].waitForExistence(timeout: 5))
            let preview = app.otherElements["icloud-recovery-preview-recovered"]
            reveal(preview, app: app)
            capture(large ? "keyboard-comparison-large" : "keyboard-comparison")
            let details = app.buttons["icloud-recovery-details-recovered"]
            reveal(details, app: app); details.tap()
            reveal(app.staticTexts["Synthetic alternate layout"], app: app)
            reveal(app.staticTexts["Starts at: Right"], app: app)
            let allRows = app.switches["icloud-recovery-all-rows"]
            for _ in 0..<8 where !allRows.isHittable { scrollForm(app, down: true) }
            tapSwitch(allRows, app: app)
            reveal(preview, app: app); capture(large ? "keyboard-comparison-expanded-large" : "keyboard-comparison-expanded")
            let restore = app.buttons["icloud-recovered-restore"]
            reveal(restore, app: app); capture(large ? "recovery-layout-detail-large" : "recovery-layout-detail")
            restore.tap(); app.buttons["Use Layout"].tap()
            XCTAssertTrue(notice.waitForExistence(timeout: 5)); reveal(notice, app: app); notice.tap()
            let undo = app.buttons["icloud-recovered-restore"]; reveal(undo, app: app)
            XCTAssertTrue(undo.exists, "Switching layouts keeps the previous one available to undo")
            capture(large ? "recovery-layout-undo-large" : "recovery-layout-undo")
            app.terminate()
        }
    }

    func testRecoveredChangesHaveClearRestoreUndoAndDiscardActions() {
        for large in [false, true] {
            let app = launch(large: large); defer { app.terminate() }
            reveal(app.buttons["fixture-recovered"], app: app); app.buttons["fixture-recovered"].tap()
            XCTAssertTrue(app.navigationBars["Recovered Changes"].waitForExistence(timeout: 5))
            capture(large ? "recovered-list-large" : "recovered-list")
            app.buttons["icloud-recovered-fixture-text"].tap()
            XCTAssertTrue(app.staticTexts["Synthetic recovered notes. No personal data."].waitForExistence(timeout: 5))
            capture(large ? "recovered-text-large" : "recovered-text")
            let restore = app.buttons["icloud-recovered-restore"]; reveal(restore, app: app); restore.tap()
            XCTAssertTrue(app.navigationBars["Recovered Changes"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["icloud-recovered-fixture-text"].exists)
            app.buttons["icloud-recovered-fixture-layout"].tap()
            XCTAssertTrue(app.otherElements["icloud-recovery-preview-current"].waitForExistence(timeout: 5))
            let preview = app.otherElements["icloud-recovery-preview-recovered"]
            reveal(preview, app: app)
            capture(large ? "keyboard-comparison-large" : "keyboard-comparison")
            let details = app.buttons["icloud-recovery-details-recovered"]
            reveal(details, app: app); details.tap()
            reveal(app.staticTexts["Synthetic alternate layout"], app: app)
            reveal(app.staticTexts["Starts at: Right"], app: app)
            let allRows = app.switches["icloud-recovery-all-rows"]
            for _ in 0..<8 where !allRows.isHittable { scrollForm(app, down: true) }
            tapSwitch(allRows, app: app)
            reveal(preview, app: app); capture(large ? "keyboard-comparison-expanded-large" : "keyboard-comparison-expanded")
            reveal(app.buttons["icloud-recovered-restore"], app: app)
            capture(large ? "recovered-layout-large" : "recovered-layout")
            app.buttons["icloud-recovered-restore"].tap()
            XCTAssertTrue(app.buttons["Use Layout"].waitForExistence(timeout: 5)); app.buttons["Use Layout"].tap()
            XCTAssertTrue(app.navigationBars["Recovered Changes"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["icloud-recovered-fixture-layout"].exists)
            let discard = app.buttons["icloud-recovered-discard-all"]; reveal(discard, app: app); discard.tap()
            XCTAssertTrue(app.staticTexts["Only recovery copies are removed. Your current data and iCloud data are kept."].waitForExistence(timeout: 5))
            capture(large ? "recovered-discard-large" : "recovered-discard")
            app.buttons["Cancel"].tap(); XCTAssertTrue(discard.exists)
            discard.tap(); app.buttons["Discard Recovery Copies"].tap()
            XCTAssertTrue(app.staticTexts["No recovered changes"].waitForExistence(timeout: 5))
            capture(large ? "recovered-empty-large" : "recovered-empty")
            app.terminate()
        }
    }

}
