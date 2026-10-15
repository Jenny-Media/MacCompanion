#if os(iOS)
import XCTest
import SwiftUI
import UIKit
@testable import Mac_Companion

@MainActor final class SettingsRefreshBoundaryTests: XCTestCase {
    func testMacListKeepsItsWorkingRefreshAction() async throws {
        let state = RefreshAuditState()
        let mount = try RefreshAuditMount(RefreshAuditHarness(state: state, modal: AnyView(Text("Unused"))))
        defer { mount.close() }
        try await wait { !mount.refreshControls(in: mount.root.view).isEmpty }
        let control = try XCTUnwrap(mount.refreshControls(in: mount.root.view).first)
        control.beginRefreshing(); control.sendActions(for: .valueChanged)
        try await wait { state.calls == 1 }
        control.endRefreshing()
    }

    func testFormerOuterRefreshScopeReproducesTheUnrelatedSheetRefresh() async throws {
        let state = RefreshAuditState()
        let mount = try RefreshAuditMount(RefreshAuditHarness(state: state, modal: AnyView(Form { Text("Synthetic Settings") }), legacyScope: true))
        defer { mount.close() }
        try await wait { !mount.refreshControls(in: mount.root.view).isEmpty }
        state.showModal = true
        try await wait { state.modalRefreshAvailable != nil && mount.root.presentedViewController != nil }
        XCTAssertEqual(state.modalRefreshAvailable, true, "The old outer modifier leaks its action into the presented form")
        XCTAssertFalse(mount.refreshControls(in: try XCTUnwrap(mount.root.presentedViewController).view).isEmpty)
    }

    func testNetworkDiscoveryRefreshDoesNotLeakIntoPresentedFormsOrNestedScreens() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = DirectMacLibraryV1(url: directory.appending(path: "macs.json"), removeLogin: { _ in })
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic UI Audit", addresses: ["ui-audit.invalid"])
        let files = DirectFilesSession(mac: mac)
        defer { files.close(); try? TerminalSecretStore.remove(mac.id) }
        var filesView = DirectFilesView(mac: mac, session: files)
        filesView.sessionAvailable = { false }
        let screens: [(String, AnyView)] = [
            ("Login & Access", AnyView(DirectMacAccessView(mac: mac))),
            ("Mac Settings", AnyView(DirectMacEditorV1(mac: mac, library: library))),
            ("App Settings", AnyView(DirectSessionSettingsV1().directAppearance())),
            ("SSH Keys", AnyView(TerminalKeySettings())),
            ("Setup Guide", AnyView(DirectMacSetupGuide())),
            ("Pro", AnyView(DirectProView())),
            ("Files", AnyView(filesView))
        ]
        for (name, screen) in screens {
            let state = RefreshAuditState()
            let mount = try RefreshAuditMount(RefreshAuditHarness(state: state, modal: screen))
            defer { mount.close() }
            try await wait { !mount.refreshControls(in: mount.root.view).isEmpty }
            state.showModal = true
            try await wait { state.modalRefreshAvailable != nil && mount.root.presentedViewController != nil }
            XCTAssertEqual(state.modalRefreshAvailable, false, name + " must not inherit the Mac list’s scan")
            let presented = try XCTUnwrap(mount.root.presentedViewController)
            XCTAssertTrue(mount.refreshControls(in: presented.view).isEmpty, name + " must not offer an unrelated pull-to-refresh")
            XCTAssertEqual(state.calls, 0)
            mount.close()
        }
    }

    func testAccountEditorRendersSavedFieldsAndMethodChoicesAtNarrowAndLargeTextSizes() async throws {
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Saved Account", addresses: ["ui-audit.invalid"])
        let profile = DirectMacAccessProfile(login: .init(username: "synthetic-account", password: "synthetic-only"),
            sshMethod: .password, sshPassword: .init(username: "synthetic-terminal", password: "synthetic-terminal-only"))
        try DirectMacAccessStore.write(profile, id: mac.id)
        defer { try? TerminalSecretStore.remove(mac.id) }
        for size in [DynamicTypeSize.large, .accessibility3] {
            let mount = try RefreshAuditMount(DirectMacAccessView(mac: mac).dynamicTypeSize(size))
            defer { mount.close() }
            try await wait { mount.fields.contains { $0.text == "synthetic-account" } }
            XCTAssertTrue(mount.fields.contains { $0.text == "synthetic-only" && $0.isSecureTextEntry })
            XCTAssertTrue(mount.refreshControls(in: mount.root.view).isEmpty)
            XCTAssertEqual(try DirectMacAccessStore.load(mac.id), profile, "Opening the editor must not change the saved login")
            let image = UIGraphicsImageRenderer(bounds: mount.window.bounds).image { _ in mount.window.drawHierarchy(in: mount.window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = "login-access-" + (size == .large ? "normal" : "large-text")
            attachment.lifetime = .keepAlways; add(attachment)
            mount.close()
        }
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            if Date() >= deadline { XCTFail("The audit screen did not settle"); throw NSError(domain: "UIAudit", code: 1) }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}

@MainActor @Observable private final class RefreshAuditState {
    var calls = 0
    var showModal = false
    var modalRefreshAvailable: Bool?
}
private struct RefreshAuditProbe: View {
    @Environment(\.refresh) private var refresh
    var record: (RefreshAction?) -> Void
    var body: some View { Color.clear.frame(width: 1, height: 1).onAppear { record(refresh) } }
}
private struct RefreshAuditHarness: View {
    @Bindable var state: RefreshAuditState
    let modal: AnyView
    var legacyScope = false
    var body: some View {
        NavigationStack {
            if legacyScope {
                List { rows }
                    .sheet(isPresented: $state.showModal) { modalContent }
                    .refreshable { await MainActor.run { state.calls += 1 } }
            } else {
                DirectMacDiscoveryList(refresh: { await MainActor.run { state.calls += 1 } }) { rows }
                    .sheet(isPresented: $state.showModal) { modalContent }
            }
        }
    }
    private var rows: some View {
        Text("Synthetic Mac")
    }
    private var modalContent: some View {
        modal.overlay(alignment: .topLeading) { RefreshAuditProbe { state.modalRefreshAvailable = $0 != nil } }
    }
}
@MainActor private final class RefreshAuditMount {
    let window: UIWindow
    let root: UIViewController
    private let previous: UIWindow?
    init(_ view: some View) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previous = scene.windows.first { $0.isKeyWindow }
        window = UIWindow(windowScene: scene); window.frame = .init(x: 0, y: 0, width: 390, height: 844)
        root = UIHostingController(rootView: view); window.rootViewController = root; window.makeKeyAndVisible()
    }
    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    var fields: [UITextField] { descendants(root.view).compactMap { $0 as? UITextField } }
    func refreshControls(in view: UIView) -> [UIRefreshControl] {
        descendants(view).compactMap { ($0 as? UIScrollView)?.refreshControl }
    }
    func close() { root.dismiss(animated: false); window.endEditing(true); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
}
#endif
