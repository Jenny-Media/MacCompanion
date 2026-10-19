#if os(iOS)
import XCTest
import UIKit
import SwiftUI
import LocalAuthentication
@testable import Mac_Companion

@MainActor final class QuickConnectTests: XCTestCase {
    func testUnlockLabelsFollowAvailableAuthenticationAndPasscodeFallback() {
        let context = AvailableAuthenticationContext()
        context.kind = .faceID
        XCTAssertEqual(DirectUnlockMethod.current(context: context).buttonTitle, "Unlock with Face ID")
        context.kind = .touchID
        XCTAssertEqual(DirectUnlockMethod.current(context: context).buttonTitle, "Unlock with Touch ID")
        context.biometrics = false
        XCTAssertEqual(DirectUnlockMethod.current(context: context), .passcode)
        context.deviceAuthentication = false
        XCTAssertEqual(DirectUnlockMethod.current(context: context), .unavailable)
        context.biometrics = true; context.deviceAuthentication = true; context.kind = .faceID
        XCTAssertEqual(DirectUnlockMethod.current(context: context), .faceID, "Availability can recover after Settings or biometric lockout")
    }
    func testTrackpadRecoveryOnlyAppliesToDisplayFailures() {
        for stage in [7, 8, 10, 11, 110, 111, 112, 113, 114, 115] {
            XCTAssertFalse(DirectRecoveryBridgeV1.canOfferInputOnlyRecovery(stage: stage), "stage \(stage)")
        }
        for stage in [9, 103, 116, 117, 118] {
            XCTAssertTrue(DirectRecoveryBridgeV1.canOfferInputOnlyRecovery(stage: stage), "stage \(stage)")
        }
    }
    func testDraftValidatesWithoutSavingAndKeepsAStableIdentity() throws {
        var draft = DirectQuickConnectDraft(); draft.host = " EXAMPLE.local "
        let id = draft.id
        XCTAssertEqual(draft.record?.address, "example.local")
        XCTAssertEqual(draft.record?.id, id)
        draft.port = "0"; XCTAssertNil(draft.record)
        draft.port = "5900"; draft.sshPort = "65536"; XCTAssertNil(draft.record)
        draft.sshPort = "22"; draft.host = "https://example.local"; XCTAssertNil(draft.record)
        draft.host = "example.local"; draft.additionalAddresses = "backup.local\n192.0.2.1"
        XCTAssertEqual(draft.record?.addresses, ["example.local", "backup.local", "192.0.2.1"])
    }
    func testSavedEndpointReusesUUIDAndItsPreferences() throws {
        var saved = try DirectMacRecordV1.normalized(name: "My Mac", addresses: ["example.local"], port: 5901, sshPort: 2222)
        saved.preferredConnection = .trackpad; saved.swipeLeft = .disabled
        var draft = DirectQuickConnectDraft(); draft.host = "EXAMPLE.LOCAL."; draft.port = "5901"; draft.sshPort = "2222"
        let request = try XCTUnwrap(draft.request(in: [saved]))
        XCTAssertEqual(request.mac, saved); XCTAssertEqual(request.mac.id, saved.id)
        XCTAssertEqual(request.connection, .trackpad)
        draft.connection = .terminal; draft.choseConnection = true
        XCTAssertEqual(draft.request(in: [saved])?.connection, .terminal)
        draft.connection = .desktop
        draft.port = "5900"; XCTAssertNil(draft.savedMac(in: [saved]))
    }
    func testDuplicateEndpointNeverChoosesAnArbitrarySavedLogin() throws {
        let one = try DirectMacRecordV1.normalized(name: "One", addresses: ["example.local"])
        let two = try DirectMacRecordV1.normalized(name: "Two", addresses: ["example.local"])
        var draft = DirectQuickConnectDraft(); draft.host = "example.local"
        XCTAssertNil(draft.savedMac(in: [one, two]))
        XCTAssertEqual(draft.request(in: [one, two])?.mac.id, draft.id)
    }
    func testNearbyServicesShareOneMacAndPreserveServicePorts() throws {
        let services = [DirectMacDetectedIdentity(name: "Synthetic Mac", host: "Example.local.", addresses: [], port: 5901, connection: .desktop),
                        DirectMacDetectedIdentity(name: "Synthetic Mac", host: "example.local", addresses: [], port: 2222, connection: .terminal)]
        let items = DirectMacDiscoveryItem.group(services)
        XCTAssertEqual(items.count, 1)
        let draft = DirectQuickConnectDraft(item: try XCTUnwrap(items.first))
        XCTAssertEqual(draft.port, "5901"); XCTAssertEqual(draft.sshPort, "2222"); XCTAssertEqual(draft.connection, .desktop)
        let sshOnly = DirectQuickConnectDraft(item: try XCTUnwrap(DirectMacDiscoveryItem.group([services[1]]).first))
        XCTAssertEqual(sshOnly.connection, .terminal)
    }
    func testDiscoveryShowsNewResultsImmediatelyWithoutCommittingPartialMetadata() {
        let old = DirectMacDetectedIdentity(name: "Previous Mac", host: "previous.local", addresses: [], port: 5900, connection: .desktop)
        let new = DirectMacDetectedIdentity(name: "New Mac", host: "new.local", addresses: [], port: 22, connection: .terminal)
        var results = DirectMacDiscoveryResults()
        results.finish([old]); results.preview([new])
        XCTAssertEqual(Set(results.visible.map(\.host)), [old.host, new.host])
        XCTAssertEqual(results.completed.map(\.host), [old.host], "Only a completed scan may update saved Mac metadata")
        results.cancel()
        XCTAssertEqual(results.visible.map(\.host), [old.host])
        results.preview([new]); results.finish([new])
        XCTAssertEqual(results.visible.map(\.host), [new.host])
        XCTAssertEqual(results.completed.map(\.host), [new.host])
    }
    func testVisibleConnectionModeAlwaysMatchesTheSubmittedMode() throws {
        var saved = try DirectMacRecordV1.normalized(name: "My Mac", addresses: ["example.local"])
        saved.preferredConnection = .trackpad
        var draft = DirectQuickConnectDraft(); draft.host = "example.local"
        XCTAssertEqual(draft.effectiveConnection(in: [saved]), draft.request(in: [saved])?.connection)
        draft.connection = .terminal; draft.choseConnection = true
        XCTAssertEqual(draft.effectiveConnection(in: [saved]), draft.request(in: [saved])?.connection)
    }
    func testFieldsKeepTheirFillAcrossSheetElevationAndAvoidAppAccountAutoFill() {
        let base = UITraitCollection(userInterfaceStyle: .light)
        let elevated = UITraitCollection(traitsFrom: [base, UITraitCollection(userInterfaceLevel: .elevated)])
        XCTAssertEqual(DirectConnectionStyle.field.resolvedColor(with: base), DirectConnectionStyle.field.resolvedColor(with: elevated))
        XCTAssertEqual(DirectConnectionStyle.remoteCredentialContentType.rawValue, "")
    }
    func testNativeFormSizingIgnoresStaleMeasurementsAndKeepsItsIdentityAcrossKeyboard() async throws {
        let mount = try PanelMount(); defer { mount.close() }
        let owner = NSObject(), retired = NSObject()
        mount.host.show(UIViewController(), owner: owner, cancel: {})
        try await eventually { mount.anchor.presentedViewController != nil }
        let controller = try XCTUnwrap(mount.anchor.presentedViewController)
        let sheet = try XCTUnwrap(controller.sheetPresentationController)
        XCTAssertEqual(controller.modalPresentationStyle, .formSheet)
        XCTAssertFalse(sheet.prefersPageSizing)
        XCTAssertEqual(controller.preferredContentSize.width, 560)
        if #available(iOS 27.0, *) { XCTAssertEqual(sheet.preferredPlacement, .center) }
        mount.host.setContentHeight(300, owner: owner)
        XCTAssertEqual(controller.preferredContentSize.height, 300)
        mount.host.setContentHeight(800, owner: retired)
        XCTAssertEqual(controller.preferredContentSize.height, 300)
        let nativeDetents = sheet.detents.map(\.identifier)
        NotificationCenter.default.post(name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.post(name: UIResponder.keyboardWillHideNotification, object: nil)
        XCTAssertEqual(sheet.detents.map(\.identifier), nativeDetents)
        XCTAssertTrue(mount.anchor.presentedViewController === controller)
        XCTAssertEqual(controller.preferredContentSize.height, 300)
    }
    func testOptionsExpansionKeepsABoundedFormThroughKeyboardDismissal() async throws {
        let mount = try PanelMount(); defer { mount.close() }
        let owner = NSObject()
        mount.host.show(UIViewController(), owner: owner, cancel: {})
        try await eventually { mount.anchor.presentedViewController != nil }
        let sheet = try XCTUnwrap(mount.anchor.presentedViewController?.sheetPresentationController)
        NotificationCenter.default.post(name: UIResponder.keyboardWillShowNotification, object: nil)
        mount.host.expand()
        mount.host.setContentHeight(300, owner: owner)
        NotificationCenter.default.post(name: UIResponder.keyboardWillHideNotification, object: nil)
        XCTAssertEqual(mount.anchor.presentedViewController?.preferredContentSize.height, 620)
        XCTAssertEqual(sheet.detents.count, 1)
        mount.host.compact()
        XCTAssertEqual(mount.anchor.presentedViewController?.preferredContentSize.height, 300)
    }
    func testTrustSizingReturnsToTheUnderlyingFormWithoutReplacingIt() async throws {
        let mount = try PanelMount(); defer { mount.close() }
        let owner = NSObject(), content = UIViewController(), trust = UIViewController()
        mount.host.show(content, owner: owner, cancel: {})
        try await eventually { mount.anchor.presentedViewController != nil }
        let panel = try XCTUnwrap(mount.anchor.presentedViewController)
        mount.host.setContentHeight(360, owner: owner)
        mount.host.showTrust(trust)
        XCTAssertEqual(panel.preferredContentSize.height, 620)
        mount.host.setContentHeight(400, owner: owner)
        XCTAssertEqual(panel.preferredContentSize.height, 620)
        mount.host.finishTrust(trust)
        XCTAssertEqual(panel.preferredContentSize.height, 400)
        XCTAssertTrue(panel.children.first === content)
    }
    func testSavingMacAndLoginAreIndependentChoices() throws {
        var draft = DirectQuickConnectDraft(); draft.host = "example.local"; draft.saveMac = false
        let request = try XCTUnwrap(draft.request(in: []))
        XCTAssertFalse(request.saveMac)
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = DirectMacLibraryV1(url: directory.appending(path: "macs.json"), removeLogin: { _ in })
        XCTAssertTrue(library.macs.isEmpty, "Constructing and cancelling a request must not save a Mac")
        draft.saveMac = true
        let connected = try XCTUnwrap(draft.request(in: []))
        XCTAssertTrue(library.save(id: connected.mac.id, name: connected.mac.name, addresses: connected.mac.addresses))
        XCTAssertNil(DesktopCredentialStoreV1.read(connected.mac.id), "Saving a Mac must not manufacture a login")
        XCTAssertEqual(library.macs.map(\.id), [draft.id])
    }
    func testNativeSheetReplacesContentWithoutAnotherPresentationAndRejectsOldHide() async throws {
        let mount = try PanelMount(); defer { mount.close() }
        let first = UIViewController(), second = UIViewController(), firstOwner = NSObject(), secondOwner = NSObject()
        mount.host.show(first, owner: firstOwner, cancel: {})
        try await eventually { mount.anchor.presentedViewController != nil }
        let sheet = try XCTUnwrap(mount.anchor.presentedViewController)
        mount.host.hide(firstOwner)
        mount.host.show(second, owner: secondOwner, cancel: {})
        await Task.yield(); await Task.yield()
        XCTAssertTrue(mount.anchor.presentedViewController === sheet)
        XCTAssertTrue(second.parent === sheet); XCTAssertNil(first.parent)
        mount.host.close(); try await eventually { mount.anchor.presentedViewController == nil }
    }
    func testInteractiveDismissalRejectsCancelledOwnerUpdatesAndStaleCallbacks() async throws {
        let mount = try PanelMount(); defer { mount.close() }
        let owner = NSObject(), content = UIViewController()
        var cancellations = 0
        mount.host.show(content, owner: owner, cancel: {
            cancellations += 1
            // Cancelling native/SwiftUI content can synchronously redraw it.
            mount.host.show(content, owner: owner, cancel: {})
        })
        try await eventually { content.parent != nil }
        let sheet = try XCTUnwrap(content.parent)
        let presentation = try XCTUnwrap(sheet.presentationController)
        let count = mount.anchor.presentations
        sheet.dismiss(animated: false)
        try await eventually { mount.anchor.presentedViewController == nil }
        mount.host.presentationControllerDidDismiss(presentation)
        await Task.yield(); await Task.yield()
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(mount.anchor.presentations, count, "Cancel must not flash another sheet")
        XCTAssertFalse(mount.host.isVisible)
        mount.host.show(content, owner: owner, cancel: {})
        XCTAssertEqual(mount.anchor.presentations, count, "A late update from the dismissed login remains retired")
        let nextOwner = NSObject(), next = UIViewController()
        mount.host.show(next, owner: nextOwner, cancel: { cancellations += 1 })
        try await eventually { next.parent != nil }
        mount.host.presentationControllerDidDismiss(presentation)
        XCTAssertTrue(mount.host.isVisible, "The old sheet cannot dismiss a new login")
        XCTAssertEqual(cancellations, 1)
    }

    func testSheetDismissalLockFollowsTheCurrentOwnerAndPreservesTrustProtection() async throws {
        let mount = try PanelMount(); defer { mount.close() }
        let content = UIViewController(), owner = NSObject(), retired = NSObject(), trust = UIViewController()
        mount.host.show(content, owner: owner, cancel: {})
        try await eventually { content.parent != nil }
        let sheet = try XCTUnwrap(content.parent)
        XCTAssertFalse(sheet.isModalInPresentation)
        mount.host.setDismissalLocked(true, owner: owner)
        XCTAssertTrue(sheet.isModalInPresentation)
        mount.host.show(content, owner: owner, cancel: {})
        XCTAssertTrue(sheet.isModalInPresentation)
        mount.host.setDismissalLocked(false, owner: retired)
        XCTAssertTrue(sheet.isModalInPresentation)
        mount.host.showTrust(trust)
        mount.host.setDismissalLocked(false, owner: owner)
        XCTAssertTrue(sheet.isModalInPresentation)
        mount.host.finishTrust(trust)
        XCTAssertFalse(sheet.isModalInPresentation, "Returning to an idle form restores dismissal")
        mount.host.setDismissalLocked(true, owner: owner)
        mount.host.show(UIViewController(), owner: retired, cancel: {})
        XCTAssertFalse(sheet.isModalInPresentation, "An old connection cannot lock its replacement")
        mount.host.setDismissalLocked(true, owner: owner)
        XCTAssertFalse(sheet.isModalInPresentation)
        mount.host.close()
        try await eventually { mount.anchor.presentedViewController == nil }
    }
    func testTrustTemporarilyReplacesContentAndProgrammaticCloseDoesNotCancel() async throws {
        let mount = try PanelMount(); defer { mount.close() }
        let content = UIViewController(), owner = NSObject(), trust = UIViewController()
        var cancelled = false
        mount.host.show(content, owner: owner, cancel: { cancelled = true })
        try await eventually { content.parent != nil }
        let sheet = try XCTUnwrap(content.parent)
        mount.host.showTrust(trust)
        XCTAssertTrue(trust.parent === sheet); XCTAssertTrue(sheet.isModalInPresentation)
        // Progress updates cannot override the active fingerprint prompt.
        mount.host.show(content, owner: owner, cancel: { cancelled = true })
        XCTAssertTrue(trust.parent === sheet)
        mount.host.finishTrust(trust)
        XCTAssertTrue(content.parent === sheet); XCTAssertFalse(sheet.isModalInPresentation)
        mount.host.close(); try await eventually { mount.anchor.presentedViewController == nil }
        XCTAssertFalse(cancelled)
    }
    func testNativeDesktopSheetKeepsItsFieldsAndResignsKeyboardBeforeConnecting() throws {
        let mount = try PanelMount(); defer { mount.close() }
        let viewer = CompanionVNCViewer(); viewer.connectionPanelHost = mount.host; viewer.preventsLoginRetention = true
        viewer.loadViewIfNeeded(); viewer.view.frame = mount.window.bounds
        mount.anchor.addChild(viewer); mount.anchor.view.addSubview(viewer.view); viewer.didMove(toParent: mount.anchor)
        defer { viewer.stop(); viewer.willMove(toParent: nil); viewer.view.removeFromSuperview(); viewer.removeFromParent() }
        viewer.foregrounded()
        let username = try XCTUnwrap(viewer.value(forKey: "username") as? UITextField)
        let password = try XCTUnwrap(viewer.value(forKey: "password") as? UITextField)
        XCTAssertEqual(username.textContentType?.rawValue, "")
        XCTAssertEqual(password.textContentType?.rawValue, "")
        XCTAssertEqual(username.placeholder, "Username"); XCTAssertEqual(password.placeholder, "Password")
        let connect = try XCTUnwrap(viewer.value(forKey: "connect") as? UIButton)
        let fields = try XCTUnwrap(viewer.value(forKey: "loginFields") as? UIView)
        let footer = try XCTUnwrap(viewer.value(forKey: "loginActions") as? UIView)
        let scroll = try XCTUnwrap(viewer.value(forKey: "loginScroll") as? UIView)
        let attached = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in password.window != nil }, object: nil)
        wait(for: [attached], timeout: 3)
        XCTAssertFalse(footer.isDescendant(of: scroll), "Login actions stay outside the scrolling fields")
        XCTAssertTrue((viewer.value(forKey: "saveLoginRow") as? UIView)?.isHidden == true)
        username.text = "synthetic"; password.text = "synthetic-only"
        XCTAssertTrue(password.becomeFirstResponder()); XCTAssertTrue(password.isFirstResponder)
        var attempts = 0
        viewer.connectHandler = { _, _, remember in
            attempts += 1; XCTAssertFalse(password.isFirstResponder); XCTAssertFalse(remember)
        }
        connect.sendActions(for: .touchUpInside)
        XCTAssertEqual(attempts, 1); XCTAssertTrue(fields.isHidden)
        viewer.showInvalidLogin()
        XCTAssertTrue(viewer.value(forKey: "password") as? UITextField === password)
        XCTAssertEqual(password.text, "synthetic-only"); XCTAssertFalse(fields.isHidden)
    }
    func testGroupedRowKeepsItsEditorAndDraftAcrossNarrowWidthsAndLargeText() async throws {
        let mount = try PanelMount(); defer { mount.close() }
        let content = UIHostingController(rootView: DirectCredentialRow {
            DirectConnectionPasswordField(text: .constant("synthetic-password"), secure: false, identifier: "grouped-test-password") {}
        })
        mount.anchor.addChild(content); mount.anchor.view.addSubview(content.view); content.didMove(toParent: mount.anchor)
        func fields(_ view: UIView) -> [UITextField] {
            (view as? UITextField).map { [$0] } ?? view.subviews.flatMap(fields)
        }
        content.view.frame = CGRect(x: 0, y: 80, width: 520, height: 130)
        try await eventually { fields(content.view).count == 1 }
        let editor = try XCTUnwrap(fields(content.view).first)
        XCTAssertTrue(editor.becomeFirstResponder())
        for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
            content.traitOverrides.preferredContentSizeCategory = category
            for width in [CGFloat(520), 280, 210, 520] {
                content.view.frame.size.width = width
                content.view.setNeedsLayout(); content.view.layoutIfNeeded()
                await Task.yield()
                XCTAssertTrue(fields(content.view).first === editor)
                XCTAssertEqual(editor.text, "synthetic-password")
                XCTAssertTrue(editor.isFirstResponder)
                let frame = editor.convert(editor.bounds, to: content.view)
                XCTAssertGreaterThan(frame.width, 100)
                XCTAssertGreaterThanOrEqual(frame.minX, 0)
                XCTAssertLessThanOrEqual(frame.maxX, width + 1)
            }
        }
    }
    private func eventually(_ predicate: () -> Bool) async throws {
        for _ in 0..<150 { if predicate() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("Native panel did not settle")
    }
}

private final class AvailableAuthenticationContext: LAContext, @unchecked Sendable {
    var kind: LABiometryType = .none
    var biometrics = true
    var deviceAuthentication = true
    override var biometryType: LABiometryType { kind }
    override func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        policy == .deviceOwnerAuthenticationWithBiometrics ? biometrics : deviceAuthentication
    }
}

@MainActor private final class PanelPresentationAnchor: UIViewController {
    var presentations = 0
    override func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
        presentations += 1
        super.present(viewControllerToPresent, animated: flag, completion: completion)
    }
}

@MainActor private final class PanelMount {
    let window: UIWindow
    let anchor = PanelPresentationAnchor()
    let host = DirectConnectionPanelHost()
    private weak var previous: UIWindow?
    init() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previous = scene.windows.first(where: \.isKeyWindow)
        window = UIWindow(windowScene: scene); window.rootViewController = anchor
        window.makeKeyAndVisible(); anchor.loadViewIfNeeded(); host.attach(anchor)
    }
    func close() { host.close(); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
}
#endif
