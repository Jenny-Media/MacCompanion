import AppKit
import SwiftUI
import XCTest
@testable import MacCompanion

private final class PrivateEditorMarker: NSView {}
private struct PrivateEditorProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> PrivateEditorMarker { PrivateEditorMarker() }
    func updateNSView(_ view: PrivateEditorMarker, context: Context) {}
}

private final class StatusTransport: CompanionVNCSession {
    private var active = false
    private(set) var stopCount = 0
    override var running: Bool { active }
    override var connected: Bool { active }
    override func connectAddresses(_ addresses: [String]!, port: Int, username: String!, password: String!) { active = true }
    override func stop() { active = false; stopCount += 1 }
    func reportConnected() { stateHandler?("Connected", ["framebufferWidth": 100, "framebufferHeight": 100]) }
}

@MainActor final class PrivacyAndVNCRegressionTests: XCTestCase {
    func testLockRemovesRenderedPrivateEditorSubtree() async throws {
        let host = NSHostingView(rootView: MacSheetPrivacyContent(canAccess: true, content: PrivateEditorProbe()))
        host.frame = CGRect(x: 0, y: 0, width: 500, height: 400)
        func containsEditor(_ view: NSView) -> Bool {
            view is PrivateEditorMarker || view.subviews.contains(where: containsEditor)
        }
        for _ in 0..<100 {
            host.layoutSubtreeIfNeeded()
            if containsEditor(host) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(containsEditor(host))
        host.rootView = MacSheetPrivacyContent(canAccess: false, content: PrivateEditorProbe())
        for _ in 0..<100 {
            host.layoutSubtreeIfNeeded()
            if !containsEditor(host) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(containsEditor(host), "Lock must remove cached editor content, including its nested presentation owners")
    }

    func testPeriodicVNCStatusWhileLockedRetainsEstablishedDesktop() {
        var allowed = true
        let transport = StatusTransport()
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic", addresses: ["fixture.local"])
        let session = MacVNCSession(mac: mac, removeSavedLogin: { _ in },
                                    makeTransport: { transport }, canAccess: { allowed })
        defer { session.close() }
        session.connect(username: "synthetic", password: "synthetic-only", remember: false)
        XCTAssertFalse(transport.inputOnly, "Native Desktop must request a visible framebuffer")
        transport.reportConnected()
        XCTAssertTrue(session.connected); XCTAssertTrue(session.canInput)
        allowed = false; session.pauseInput()
        XCTAssertTrue(session.connected); XCTAssertFalse(session.canInput)
        for _ in 0..<3 { transport.reportConnected() }
        XCTAssertTrue(session.connected); XCTAssertEqual(transport.stopCount, 0)
        let frame = NSImage(size: NSSize(width: 1, height: 1))
        transport.frameHandler?(frame)
        XCTAssertTrue(session.image === frame, "A locked established window may keep receiving output")
        allowed = true
        XCTAssertTrue(session.canInput)
    }

    func testInitialVNCStatusAfterLockCannotSaveLoginOrReviveRetiredOwner() throws {
        var allowed = true
        let transport = StatusTransport()
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic", addresses: ["fixture.local"])
        defer { try? DesktopCredentialStoreV1.remove(mac.id) }
        let session = MacVNCSession(mac: mac, makeTransport: { transport }, canAccess: { allowed })
        defer { session.close() }
        session.connect(username: "synthetic", password: "synthetic-only", remember: true)
        let lateCallback = try XCTUnwrap(transport.stateHandler)
        allowed = false
        transport.reportConnected()
        XCTAssertFalse(session.connected); XCTAssertFalse(session.connecting)
        XCTAssertEqual(transport.stopCount, 1)
        XCTAssertNil(try DesktopCredentialStoreV1.readChecked(mac.id))
        allowed = true
        lateCallback("Connected", ["framebufferWidth": 100, "framebufferHeight": 100])
        XCTAssertFalse(session.connected)
        XCTAssertNil(try DesktopCredentialStoreV1.readChecked(mac.id))
    }
}
