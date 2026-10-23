#if os(iOS)
import SwiftUI
import StoreKitTest
import XCTest
@testable import Mac_Companion

private final class SavedTextSession: CompanionVNCSession {
    var sent: [[AnyHashable: Any]] = []
    override var connected: Bool { true }
    override var running: Bool { false }
    override var composedTextReady: Bool { true }
    override func stop() {}
    override func tryComposedTextEvents(_ events: [[AnyHashable: Any]], completion: @escaping (Bool) -> Void) -> Bool {
        sent += events; completion(true); return true
    }
}

@MainActor final class SavedTextReviewTests: XCTestCase {
    @MainActor private struct Fixture {
        let window: UIWindow
        let previous: UIWindow?
        let viewer: CompanionVNCViewer
        let session: SavedTextSession
        let controls: RemoteMacControls
        let store: TerminalControlsStore
        let saved: TerminalControlAction
        var composer: DirectTextComposer? { viewer.value(forKey: "textComposer") as? DirectTextComposer }
        func close() {
            composer?.invalidate(); viewer.dismiss(animated: false); viewer.stop()
            window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible()
        }
    }
    private func pro() async throws -> SKTestSession {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LifetimePro", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url); session.disableDialogs = true; session.clearTransactions()
        DirectProAccess.shared.start(); _ = try await session.buyProduct(identifier: DirectProAccess.productID)
        for _ in 0..<250 {
            await DirectProAccess.shared.refresh()
            if DirectProAccess.shared.hasPro { return session }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw NSError(domain: "SavedTextReviewTests.ProUnavailable", code: 1)
    }
    private func fixture(_ inputOnly: Bool) throws -> Fixture {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        let viewer = CompanionVNCViewer(), session = SavedTextSession()
        viewer.preventsAutomaticConnection = true; viewer.inputOnly = inputOnly; viewer.macName = "Synthetic Saved Text"
        viewer.loadViewIfNeeded(); viewer.session = session
        (viewer.value(forKey: "login") as? UIView)?.isHidden = true
        _ = viewer.perform(NSSelectorFromString("updateConnectionChrome"))
        window.rootViewController = viewer; window.makeKeyAndVisible(); window.layoutIfNeeded()
        let saved = TerminalControlAction(title: "Greeting", kind: .text, text: "hello", inMenu: false)
        var profile = TerminalControlsProfile.remoteDefaults; profile.actions.append(saved)
        var data: Data? = try JSONEncoder().encode(profile)
        let store = TerminalControlsStore(read: { data }, write: { data = $0 }, legacyIDs: { [] }, legacyActions: { [] }, family: .remoteMac)
        let controls = RemoteMacControls(viewer: viewer, store: store)
        return Fixture(window: window, previous: previous, viewer: viewer, session: session, controls: controls, store: store, saved: saved)
    }
    private func waitFor(_ predicate: () -> Bool) async throws {
        for _ in 0..<150 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Saved Text presentation did not settle")
    }
    private func selectSaved(_ f: Fixture) async throws {
        f.controls.showText()
        try await waitFor { f.viewer.presentedViewController is UIHostingController<TerminalSavedItems> && f.viewer.presentedViewController?.isBeingPresented == false }
        let library = try XCTUnwrap(f.viewer.presentedViewController as? UIHostingController<TerminalSavedItems>)
        library.rootView.select(f.saved.id)
    }
    private func panel(_ f: Fixture) async throws -> DirectTextComposerPanel {
        try await waitFor { f.viewer.presentedViewController is DirectTextComposerPanel && f.viewer.presentedViewController?.isBeingPresented == false }
        return try XCTUnwrap(f.viewer.presentedViewController as? DirectTextComposerPanel)
    }
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    private func activate(_ title: String, in alert: UIAlertController) throws {
        let action = try XCTUnwrap(alert.actions.first { $0.title == title })
        // UIKit exposes the stored action as an Objective-C block; exercise the
        // production handler without adding a testing entry point to the app.
        let object = try XCTUnwrap(action.value(forKey: "handler")) as AnyObject
        let handler = unsafeBitCast(object, to: (@convention(block) (UIAlertAction) -> Void).self)
        handler(action)
    }
    private func capture(_ f: Fixture, name: String) {
        f.window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: f.window.bounds).image { _ in f.window.drawHierarchy(in: f.window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image)
        attachment.name = (f.viewer.inputOnly ? "trackpad-" : "screen-sharing-") + name
        attachment.lifetime = .keepAlways; add(attachment)
    }
    func testSavedTextOpensEditableDraftAndSendsOnlyEditsWithoutChangingDefinitionInBothModes() async throws {
        let entitlement = try await pro(); defer { entitlement.clearTransactions() }
        for inputOnly in [false, true] {
            let f = try fixture(inputOnly); defer { f.close() }
            try await selectSaved(f)
            let panel = try await panel(f), composer = try XCTUnwrap(f.composer)
            try await waitFor { self.descendants(panel.view).contains { $0 is UITextView } }
            let editor = try XCTUnwrap(descendants(panel.view).compactMap { $0 as? UITextView }.first)
            XCTAssertEqual(editor.text, f.saved.text); XCTAssertTrue(f.session.sent.isEmpty)
            editor.selectedRange = NSRange(location: 0, length: editor.text.utf16.count); editor.insertText("edited greeting")
            try await waitFor { composer.draft.text == "edited greeting" }
            XCTAssertEqual(try f.store.load().actions.first { $0.id == f.saved.id }?.text, f.saved.text)
            capture(f, name: "saved-text-editable-draft")
            composer.draft.requestSend()
            let keys = f.session.sent.compactMap { ($0["key"] as? NSNumber)?.uint32Value }
            XCTAssertEqual(keys, "edited greeting".unicodeScalars.flatMap { [$0.value, $0.value] })
            XCTAssertFalse(keys.contains(0xff0d), "Send Text must not append Return")
            XCTAssertEqual(try f.store.load().actions.first { $0.id == f.saved.id }?.text, f.saved.text)
            try await waitFor { f.viewer.presentedViewController == nil }
        }
    }
    func testExistingUnsentDraftCanBeKeptOrExplicitlyReplacedInBothModes() async throws {
        let entitlement = try await pro(); defer { entitlement.clearTransactions() }
        for inputOnly in [false, true] {
            let f = try fixture(inputOnly); defer { f.close() }
            f.viewer.showControlsComposer(); _ = try await panel(f)
            let composer = try XCTUnwrap(f.composer); composer.draft.edit("unsent draft"); composer.draft.close?()
            try await waitFor { f.viewer.presentedViewController == nil }
            try await selectSaved(f)
            try await waitFor { f.viewer.presentedViewController is UIAlertController && f.viewer.presentedViewController?.isBeingPresented == false }
            let keep = try XCTUnwrap(f.viewer.presentedViewController as? UIAlertController)
            XCTAssertEqual(keep.title, "Replace unsent draft?"); XCTAssertEqual(composer.draft.text, "unsent draft")
            capture(f, name: "saved-text-replace-draft")
            try activate("Keep Draft", in: keep); keep.dismiss(animated: false)
            try await waitFor { f.viewer.presentedViewController == nil }
            XCTAssertEqual(composer.draft.text, "unsent draft"); XCTAssertTrue(f.session.sent.isEmpty)
            try await selectSaved(f)
            try await waitFor { f.viewer.presentedViewController is UIAlertController && f.viewer.presentedViewController?.isBeingPresented == false }
            let replace = try XCTUnwrap(f.viewer.presentedViewController as? UIAlertController)
            try activate("Replace Draft", in: replace); _ = try await panel(f)
            XCTAssertEqual(composer.draft.text, f.saved.text); XCTAssertTrue(f.session.sent.isEmpty)
            composer.draft.close?(); try await waitFor { f.viewer.presentedViewController == nil }
            try await selectSaved(f); _ = try await panel(f)
            XCTAssertEqual(composer.draft.text, f.saved.text, "Reopening identical saved text must not ask to replace itself")
        }
    }
    func testMultilineSavedTextReviewRequiresConfirmationAndClosingSendsNothing() async throws {
        let entitlement = try await pro(); defer { entitlement.clearTransactions() }
        for inputOnly in [false, true] {
            let f = try fixture(inputOnly); defer { f.close() }
            try await selectSaved(f); _ = try await panel(f)
            let composer = try XCTUnwrap(f.composer)
            composer.draft.edit("first\nsecond\tvalue"); composer.draft.requestSend()
            XCTAssertNotNil(composer.draft.confirmation); XCTAssertTrue(f.session.sent.isEmpty)
            composer.draft.close?(); try await waitFor { f.viewer.presentedViewController == nil }
            XCTAssertTrue(f.session.sent.isEmpty); XCTAssertEqual(composer.draft.text, "first\nsecond\tvalue")
            XCTAssertEqual(try f.store.load().actions.first { $0.id == f.saved.id }?.text, f.saved.text)
        }
    }
    func testPendingReplacementCannotOutliveControlsResetOrComposerInvalidation() async throws {
        let entitlement = try await pro(); defer { entitlement.clearTransactions() }
        for inputOnly in [false, true] { for invalidate in [false, true] {
            let f = try fixture(inputOnly); defer { f.close() }
            f.viewer.showControlsComposer(); _ = try await panel(f)
            let composer = try XCTUnwrap(f.composer); composer.draft.edit("original draft"); composer.draft.close?()
            try await waitFor { f.viewer.presentedViewController == nil }
            try await selectSaved(f)
            try await waitFor { f.viewer.presentedViewController is UIAlertController && f.viewer.presentedViewController?.isBeingPresented == false }
            let alert = try XCTUnwrap(f.viewer.presentedViewController as? UIAlertController)
            if invalidate { composer.invalidate() } else { f.controls.reset() }
            try activate("Replace Draft", in: alert)
            try await waitFor { f.viewer.presentedViewController == nil }
            XCTAssertEqual(composer.draft.text, invalidate ? "" : "original draft")
            XCTAssertTrue(f.session.sent.isEmpty)
        } }
    }
    func testSavedDraftCannotSendAfterItsDefinitionChanges() async throws {
        let entitlement = try await pro(); defer { entitlement.clearTransactions() }
        for inputOnly in [false, true] {
            let f = try fixture(inputOnly); defer { f.close() }
            try await selectSaved(f); _ = try await panel(f)
            let composer = try XCTUnwrap(f.composer)
            var changed = try f.store.load(); changed.actions.removeAll { $0.id == f.saved.id }; _ = try f.store.save(changed)
            composer.draft.requestSend()
            XCTAssertTrue(f.session.sent.isEmpty); XCTAssertFalse(composer.draft.active)
            try await waitFor { f.viewer.presentedViewController == nil }
        }
    }
}
#endif
