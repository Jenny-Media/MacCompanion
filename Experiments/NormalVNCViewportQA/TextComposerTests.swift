import XCTest
import UIKit
@testable import Mac_Companion

@MainActor private final class ComposerAdmissionProbe: NSObject {
    @objc var interruptionHandler: (() -> Void)?
    @objc var sending: Bool { false }
    var available: (() -> Bool)?
    var send: ((String, @escaping (String?) -> Void) -> Void)?
    @objc func invalidate() { available = nil; send = nil }
    @objc func present(from controller: UIViewController, available: @escaping () -> Bool,
                       send: @escaping (String, @escaping (String?) -> Void) -> Void) {
        self.available = available; self.send = send
    }
}

@MainActor final class TextComposerTests: XCTestCase {
    func testCapturedComposerAvailabilityAndFinalDeliveryRejectLaterRestoration() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-screen-sharing-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let vectors = try XCTUnwrap(fixture["interruptionCases"] as? [[String: Any]])
        XCTAssertNotNil(vectors.first { $0["name"] as? String == "replacement-composer-delivery-before-layout" })
        let viewer = CompanionVNCViewer(); viewer.loadViewIfNeeded()
        let owner = viewer.session
        for key in ["running", "inputReady", "established", "baselinePresented"] { owner.setValue(true, forKey: key) }
        let probe = ComposerAdmissionProbe(); viewer.setValue(probe, forKey: "textComposer")
        defer { viewer.perform(NSSelectorFromString("stopViewer")); owner.setValue(false, forKey: "running") }
        viewer.perform(NSSelectorFromString("showTextComposer"))
        let availability = try XCTUnwrap(probe.available), delivery = try XCTUnwrap(probe.send)
        XCTAssertTrue(availability())
        viewer.setValue(true, forKey: "restoreViewportPending")
        XCTAssertFalse(availability(), "A captured availability callback must observe later restoration")
        var rejected: String?
        // Exercise the production final-send closure independently of the draft's
        // earlier availability check, as a late delivery callback can do.
        delivery("synthetic-only") { rejected = $0 }
        XCTAssertNotNil(rejected)
        XCTAssertEqual((owner.value(forKey: "events") as? [NSDictionary])?.count, 0)
        viewer.setValue(false, forKey: "restoreViewportPending")
        XCTAssertTrue(availability())
        delivery("a") { _ in }
        XCTAssertEqual((owner.value(forKey: "events") as? [NSDictionary])?.count, 2, "Current readiness still admits balanced Unicode events")
    }
    func testInterruptedSendWarningSurvivesAutomaticReplacementUntilAcknowledged() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ios-text-composer-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let lifecycle = try XCTUnwrap(fixture["lifecycle"] as? [String: Any])
        let policy = try XCTUnwrap(lifecycle["automaticReplacement"] as? [String: Any])
        let modes = try XCTUnwrap(policy["modes"] as? [String])
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        for mode in modes {
            let viewer = CompanionVNCViewer()
            viewer.inputOnly = mode == "trackpad"; viewer.macName = "Synthetic Mac"
            window.rootViewController = viewer; window.makeKeyAndVisible(); viewer.loadViewIfNeeded()
            viewer.session.inputOnly = mode == "trackpad"
            viewer.session.setValue(true, forKey: "running"); viewer.session.setValue(true, forKey: "inputReady")
            viewer.session.setValue(true, forKey: "established"); viewer.session.setValue(true, forKey: "baselinePresented")
            viewer.perform(NSSelectorFromString("showTextComposer"))
            try await Task.sleep(for: .milliseconds(350))
            let composer = try XCTUnwrap(viewer.value(forKey: "textComposer") as? DirectTextComposer)
            var completion: ((String?) -> Void)?
            composer.draft.configure(available: { true }, send: { _, done in completion = done })
            composer.draft.edit("hello"); composer.draft.requestSend()
            XCTAssertTrue(composer.sending)
            viewer.perform(NSSelectorFromString("background"))
            XCTAssertEqual(viewer.value(forKey: "textSendInterrupted") as? Bool, true)
            XCTAssertFalse(composer.draft.active); XCTAssertEqual(composer.draft.text, "")
            viewer.session.setValue(false, forKey: "running")
            var replacements = 0
            viewer.connectHandler = { _, _, _ in replacements += 1 }
            viewer.foregrounded()
            XCTAssertEqual(replacements, 1)
            XCTAssertEqual(viewer.value(forKey: "textSendInterrupted") as? Bool, policy["warningBeforeAcknowledge"] as? Bool)
            // Establish the replacement's real viewer callbacks and report a
            // synthetic connected framebuffer, without opening a network socket.
            viewer.prepareConnection()
            let owner = viewer.session
            owner.setValue(true, forKey: "running"); owner.setValue(true, forKey: "inputReady")
            let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
                UIColor.black.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
            }
            owner.frameHandler?(image); owner.stateHandler?("Connected", [:])
            XCTAssertEqual(viewer.value(forKey: "textSendInterrupted") as? Bool, policy["warningBeforeAcknowledge"] as? Bool)
            XCTAssertNotNil(viewer.value(forKey: "recoveryController"))
            completion?(nil) // A retired callback must not acknowledge the warning.
            XCTAssertEqual(viewer.value(forKey: "textSendInterrupted") as? Bool, true)
            let acknowledge = NSSelectorFromString("acknowledgeTextSendWarning")
            XCTAssertTrue(viewer.responds(to: acknowledge))
            if viewer.responds(to: acknowledge) { viewer.perform(acknowledge) }
            XCTAssertEqual(viewer.value(forKey: "textSendInterrupted") as? Bool, policy["warningAfterAcknowledge"] as? Bool)
            XCTAssertNil(viewer.value(forKey: "recoveryController"))
            viewer.perform(NSSelectorFromString("stopViewer")); try await Task.sleep(for: .milliseconds(350))
        }
    }
    func testAuthoritativeTextVectorsPreserveUnicodeWhitespaceAndFrameOnlyTerminalPaste() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "ios-text-composer-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        for item in cases {
            let input = try XCTUnwrap(item["text"] as? String)
            for mode in DirectControlMode.allCases {
                if item["invalid"] as? Bool == true { XCTAssertThrowsError(try DirectComposedText(input, mode: mode)); continue }
                let prepared = try DirectComposedText(input, mode: mode)
                XCTAssertEqual(prepared.text, item["normalized"] as? String)
                XCTAssertEqual(prepared.needsConfirmation, item["confirmation"] as? Bool)
                let keys = prepared.desktopEvents.compactMap { $0["down"] as? Bool == true ? $0["key"] as? UInt32 : nil }
                XCTAssertEqual(keys.map(Int.init), item["desktopKeys"] as? [Int])
                XCTAssertEqual(prepared.desktopEvents.count, keys.count * 2)
                XCTAssertEqual(hex(prepared.terminalBytes(bracketedPaste: false)), item["terminalHex"] as? String)
                XCTAssertEqual(hex(prepared.terminalBytes(bracketedPaste: true)), item["bracketedHex"] as? String)
            }
        }
        XCTAssertNoThrow(try DirectComposedText(String(repeating: "😀", count: 256), mode: .desktop))
        XCTAssertThrowsError(try DirectComposedText(String(repeating: "😀", count: 257), mode: .trackpad))
        XCTAssertNoThrow(try DirectComposedText(String(repeating: "😀", count: 1024), mode: .terminal))
        XCTAssertThrowsError(try DirectComposedText(String(repeating: "😀", count: 1025), mode: .terminal))
    }
    func testEditingAndCancelledConfirmationSendNothingAndBusyAdmissionRetainsDraft() {
        for mode in DirectControlMode.allCases {
            let draft = DirectTextComposerDraft(macName: "Synthetic Mac", mode: mode)
            var sent: [String] = []
            var completion: ((String?) -> Void)?
            draft.configure(available: { true }, send: { sent.append($0); completion = $1 })
            draft.edit("one\n  two\n")
            XCTAssertTrue(sent.isEmpty)
            draft.requestSend(); XCTAssertTrue(sent.isEmpty); XCTAssertNotNil(draft.confirmation)
            draft.confirmation = nil; XCTAssertTrue(sent.isEmpty)
            draft.requestSend(); draft.confirmSend()
            XCTAssertEqual(sent, ["one\n  two\n"]); XCTAssertTrue(draft.sending)
            draft.requestSend(); draft.confirmSend(try? DirectComposedText("one\n  two\n", mode: mode)); draft.edit("replacement")
            XCTAssertEqual(sent.count, 1); XCTAssertEqual(draft.text, "one\n  two\n")
            completion?("Input is busy. Nothing was queued.")
            XCTAssertFalse(draft.sending); XCTAssertEqual(draft.text, "one\n  two\n")
            draft.requestSend(); draft.confirmSend(); completion?(nil)
            XCTAssertEqual(sent.count, 2); XCTAssertEqual(draft.text, "")
        }
    }
    func testStaleOwnerAndLateCompletionCannotSendOrEraseAnotherDraft() {
        let draft = DirectTextComposerDraft(macName: "Synthetic Mac", mode: .terminal)
        var admitted = true, sent: [String] = [], completion: ((String?) -> Void)?
        var interruptions = 0
        draft.interrupted = { interruptions += 1 }
        draft.configure(available: { admitted }, send: { sent.append($0); completion = $1 })
        draft.edit("hello"); draft.requestSend()
        let oldCompletion = completion
        draft.invalidate(); XCTAssertEqual(draft.text, ""); XCTAssertFalse(draft.active)
        XCTAssertEqual(interruptions, 1)
        draft.configure(available: { admitted }, send: { sent.append($0); completion = $1 })
        draft.edit("new draft"); oldCompletion?(nil)
        XCTAssertEqual(draft.text, "new draft"); XCTAssertEqual(sent.count, 1)
        admitted = false; draft.requestSend()
        XCTAssertEqual(sent.count, 1); XCTAssertEqual(draft.text, ""); XCTAssertFalse(draft.active)
    }
    func testExactConfirmationAndOversizePasteDoNotSilentlyChangeText() {
        let draft = DirectTextComposerDraft(macName: "Synthetic Mac", mode: .desktop)
        var sent: [String] = []
        draft.configure(available: { true }, send: { text, complete in sent.append(text); complete(nil) })
        draft.edit("reviewed\n"); draft.requestSend()
        let confirmation = draft.confirmation
        draft.edit("changed\n"); draft.confirmation = confirmation; draft.confirmSend()
        XCTAssertTrue(sent.isEmpty); XCTAssertNotNil(draft.issue)
        draft.edit(String(repeating: "x", count: 16385))
        XCTAssertEqual(draft.text, "changed\n"); XCTAssertNotNil(draft.issue)
    }
    func testDesktopQueueRejectsWholeGroupAndCancelsOnePendingWriteWithoutReplay() async throws {
        let owner = CompanionVNCSession()
        owner.setValue(true, forKey: "running"); owner.setValue(true, forKey: "inputReady")
        owner.setValue(true, forKey: "established"); owner.setValue(true, forKey: "baselinePresented")
        let events = try DirectComposedText(String(repeating: "x", count: 256), mode: .desktop).desktopEvents
        var replies: [Bool] = []
        XCTAssertTrue(owner.tryComposedTextEvents(events) { replies.append($0) })
        let queued = try XCTUnwrap(owner.value(forKey: "events") as? [NSDictionary])
        XCTAssertEqual(queued.count, 512)
        XCTAssertFalse(owner.tryComposedTextEvents(events) { replies.append($0) })
        XCTAssertEqual((owner.value(forKey: "events") as? [NSDictionary])?.count, 512)
        XCTAssertTrue(replies.isEmpty)
        owner.stop()
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(replies, [false]); XCTAssertTrue((owner.value(forKey: "events") as? [NSDictionary])?.isEmpty == true)
        XCTAssertFalse(owner.tryComposedTextEvents(events) { replies.append($0) })
        owner.stop(); try await Task.sleep(for: .milliseconds(30)); XCTAssertEqual(replies, [false])
    }
    func testAppLockRetiresAHiddenDraftWithoutWaitingForItToReopen() async throws {
        let defaults = UserDefaults.standard, key = DirectAppLockV1.preferenceKey
        let original = defaults.object(forKey: key)
        guard !defaults.bool(forKey: key) else { throw XCTSkip("Leave an already enabled QA app lock unchanged") }
        defer {
            DirectAppLockV1.shared.setEnabled(false)
            if let original { defaults.set(original, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
        let composer = DirectTextComposer(macName: "Synthetic Mac", mode: "desktop")
        defaults.set(true, forKey: key)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(DirectAppLockV1.shared.canAccess)
        composer.draft.configure(available: { true }, send: { _, _ in XCTFail("Lock must not send input") })
        composer.draft.edit("hidden unsent draft")
        DirectAppLockV1.shared.background()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(composer.draft.text, ""); XCTAssertFalse(composer.draft.active)
    }
    func testNativeEditorAndBackgroundPrivacyWithSyntheticCaptures() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene), root = UIViewController()
        window.rootViewController = root; window.makeKeyAndVisible()
        defer { root.dismiss(animated: false); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        for mode in DirectControlMode.allCases {
            let composer = DirectTextComposer(macName: "Synthetic Mac", mode: mode.rawValue)
            composer.present(from: root, available: { true }, send: { _, _ in XCTFail("Editing must not send input") })
            try await Task.sleep(for: .milliseconds(400))
            let host = try XCTUnwrap(root.presentedViewController)
            func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
            let editor = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UITextView }.first)
            XCTAssertTrue(editor.becomeFirstResponder())
            editor.insertText("中文😀\n  second line\n")
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(composer.draft.text, "中文😀\n  second line\n")
            let capture = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) })
            capture.name = "compose-" + mode.rawValue; capture.lifetime = .keepAlways; add(capture)
            editor.setMarkedText("拼音", selectedRange: NSRange(location: 2, length: 0))
            editor.unmarkText()
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(composer.draft.text.contains("拼音"))
            let retained = composer.draft.text
            editor.insertText(String(repeating: "x", count: 16385))
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertEqual(composer.draft.text, retained)
            XCTAssertEqual(editor.text, retained, "The editor must not display a rejected paste as though it can be sent")
            root.dismiss(animated: false); try await Task.sleep(for: .milliseconds(50))
            composer.present(from: root, available: { true }, send: { _, _ in XCTFail("Returning to session must not send input") })
            XCTAssertEqual(composer.draft.text, retained)
            NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
            XCTAssertEqual(composer.draft.text, ""); XCTAssertFalse(composer.draft.active)
            try await Task.sleep(for: .milliseconds(350))
        }
    }
    func testDesktopAndTrackpadEntryUseOnlyTheirCurrentViewerAndClearAtEnd() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        for inputOnly in [false, true] {
            let viewer = CompanionVNCViewer()
            viewer.macName = "Synthetic Mac"; viewer.inputOnly = inputOnly
            window.rootViewController = viewer; window.makeKeyAndVisible(); viewer.loadViewIfNeeded()
            let ownerType = try XCTUnwrap(NSClassFromString("ControlsSession") as? CompanionVNCSession.Type)
            let owner = ownerType.init(), groups = NSMutableArray()
            owner.setValue(groups, forKey: "groups"); owner.setValue(NSMutableArray(), forKey: "pointers")
            viewer.setValue(owner, forKey: "session")
            viewer.perform(NSSelectorFromString("showTextComposer"))
            try await Task.sleep(for: .milliseconds(400))
            let composer = try XCTUnwrap(viewer.value(forKey: "textComposer") as? DirectTextComposer)
            XCTAssertEqual(composer.draft.mode, inputOnly ? .trackpad : .desktop)
            composer.draft.edit("中文😀\n")
            XCTAssertEqual(groups.count, 0)
            composer.draft.close?()
            try await Task.sleep(for: .milliseconds(350))
            viewer.perform(NSSelectorFromString("showTextComposer"))
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertEqual(composer.draft.text, "中文😀\n")
            composer.draft.requestSend(); composer.draft.confirmSend()
            XCTAssertEqual(groups.count, 1)
            let events = try XCTUnwrap(groups.firstObject as? [[String: Any]])
            XCTAssertEqual(events.count, 8)
            XCTAssertEqual(events.last?["key"] as? UInt32, 0xff0d)
            XCTAssertEqual(events.last?["down"] as? Bool, false)
            XCTAssertEqual(composer.draft.text, "")
            try await Task.sleep(for: .milliseconds(350))
            viewer.perform(NSSelectorFromString("showTextComposer")); composer.draft.edit("unsent")
            viewer.perform(NSSelectorFromString("stopViewer"))
            XCTAssertEqual(composer.draft.text, ""); XCTAssertFalse(composer.draft.active)
            try await Task.sleep(for: .milliseconds(350))
        }
    }
    private func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined() }
}
