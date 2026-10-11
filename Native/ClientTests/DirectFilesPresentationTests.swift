import XCTest
import SwiftUI
import NIO
#if os(iOS)
import UIKit
@testable import Mac_Companion
#else
import AppKit
@testable import MacCompanion
#endif

@MainActor final class DirectFilesPresentationTests: XCTestCase {
    #if os(iOS)
    func testMountedFilesDefersFirstLoginUntilSignInBecomesAvailable() async throws {
        if !DirectProAccess.shared.ready { await DirectProAccess.shared.refresh() }
        // Keep the SSH handshake pending on an owned loopback socket, so the
        // new sheet's initial task runs while loading credentials is ineligible.
        let server = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .childChannelInitializer { $0.eventLoop.makeSucceededFuture(()) }.bind(host: "127.0.0.1", port: 0).get()
        defer { Task { try? await server.close() } }
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Deferred Login", addresses: ["127.0.0.1"], sshPort: try XCTUnwrap(server.localAddress?.port))
        try TerminalSecretStore.save(.init(username: "synthetic-saved-account", password: "synthetic-saved-password"), id: mac.id)
        let session = DirectFilesSession(mac: mac); defer { session.close(); try? TerminalSecretStore.remove(mac.id) }
        session.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: true)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = UIHostingController(rootView: DirectFilesView(mac: mac, session: session, retainWhenDismissed: true)); window.makeKeyAndVisible()
        defer { window.endEditing(true); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        func fields() -> [UITextField] { descendants(window).compactMap { $0 as? UITextField } }
        try await Task.sleep(for: .milliseconds(300)); window.layoutIfNeeded()
        XCTAssertTrue(session.busy); XCTAssertFalse(fields().contains { $0.text == "synthetic-saved-account" })
        session.disconnect()
        let deadline = Date().addingTimeInterval(5)
        while !fields().contains(where: { $0.text == "synthetic-saved-account" }) {
            guard Date() < deadline else { XCTFail("Deferred saved login was not initialized"); return }
            try await Task.sleep(for: .milliseconds(50)); window.layoutIfNeeded()
        }
        XCTAssertTrue(fields().contains { $0.text == "synthetic-saved-password" })
        XCTAssertEqual(session.phase, .interrupted, "Showing saved credentials must not reconnect automatically")
    }
    #endif
    #if os(macOS)
    func testMountedFilesRefreshesExternalDiskKeyChangesWithoutReloadingDrafts() async throws {
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Key Selection", addresses: ["127.0.0.1"], sshPort: 1)
        let session = DirectFilesSession(mac: mac)
        defer { session.close(); try? TerminalSecretStore.forgetLogin(mac.id) }
        try TerminalSecretStore.save(.init(username: "synthetic-password-account", password: "synthetic-saved-password"), id: mac.id)
        let first = MacSSHKeyFileReference(id: UUID(), name: "Synthetic A", bookmark: Data([1]), fingerprint: "SHA256:synthetic-a")
        let second = MacSSHKeyFileReference(id: UUID(), name: "Synthetic B", bookmark: Data([2]), fingerprint: "SHA256:synthetic-b")
        var selection: (file: MacSSHKeyFileReference, username: String)? = (first, "synthetic-key-a")
        var view = DirectFilesView(mac: mac, session: session)
        // Synthetic references avoid real file grants and shared-library writes.
        view.selectedKeyFile = { _ in selection }
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: 720, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.makeFirstResponder(nil); window.contentView = nil; window.close() }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        func fields() -> MacCredentialFields.Fields? { descendants(host).compactMap { $0 as? MacCredentialFields.Fields }.first }
        func phrase() -> NSTextField? {
            let pair = fields()
            // SwiftUI's secure control may use a separate prompt and a different
            // NSTextField subclass. Exclude the native account/password pair.
            return descendants(host).compactMap { $0 as? NSTextField }.first {
                $0.isEditable && $0 !== pair?.account && $0 !== pair?.secret
            }
        }
        func settle() async throws { try await Task.sleep(for: .milliseconds(150)); host.layoutSubtreeIfNeeded() }
        let deadline = Date().addingTimeInterval(10)
        while fields()?.account.stringValue != "synthetic-key-a" || phrase() == nil {
            guard Date() < deadline else {
                XCTFail("Mounted Files login did not become available")
                return
            }
            try await settle()
        }
        func edit(_ field: NSTextField, _ value: String) async throws {
            XCTAssertTrue(window.makeFirstResponder(field))
            let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
            editor.insertText(value, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            window.makeFirstResponder(nil); try await settle()
        }
        let pair = try XCTUnwrap(fields())
        pair.secret.stringValue = "synthetic-edited-password" // Real autofill/KVO binding path.
        pair.account.stringValue = "synthetic-edited-account"
        try await edit(try XCTUnwrap(phrase()), "synthetic-passphrase-a")
        selection = (first, "unrelated-account-update")
        NotificationCenter.default.post(name: MacSSHKeyFileStore.changed, object: nil); try await settle()
        XCTAssertEqual(phrase()?.stringValue, "synthetic-passphrase-a", "Same-reference notifications preserve the draft")
        XCTAssertEqual(pair.account.stringValue, "synthetic-edited-account")
        XCTAssertEqual(pair.secret.stringValue, "synthetic-edited-password")
        selection = (second, "synthetic-key-b")
        NotificationCenter.default.post(name: MacSSHKeyFileStore.changed, object: nil); try await settle()
        XCTAssertEqual(pair.account.stringValue, "synthetic-key-b")
        XCTAssertEqual(phrase()?.stringValue, "", "A new file cannot inherit the previous file's passphrase")
        XCTAssertEqual(pair.secret.stringValue, "synthetic-edited-password")
        try await edit(try XCTUnwrap(phrase()), "synthetic-passphrase-b")
        selection = nil
        NotificationCenter.default.post(name: MacSSHKeyFileStore.changed, object: nil); try await settle()
        XCTAssertNil(phrase())
        XCTAssertEqual(pair.secret.stringValue, "synthetic-edited-password", "Removing a key must not reload the saved password")
        XCTAssertEqual(pair.account.stringValue, "synthetic-password-account")
        XCTAssertEqual(session.phase, .signIn, "Key-selection notifications never connect automatically")
        selection = (first, "synthetic-key-a")
        NotificationCenter.default.post(name: MacSSHKeyFileStore.changed, object: nil); try await settle()
        try await edit(try XCTUnwrap(phrase()), "synthetic-deferred-passphrase")
        // The owner is busy immediately; retire it before yielding, so this
        // cancellation test never authenticates or contacts a real Mac.
        session.connect(username: "synthetic", password: "synthetic-only", key: nil, remember: true)
        XCTAssertTrue(session.busy)
        selection = (second, "synthetic-deferred-key-b")
        NotificationCenter.default.post(name: MacSSHKeyFileStore.changed, object: nil)
        session.disconnect(); try await settle()
        XCTAssertEqual(fields()?.account.stringValue, "synthetic-deferred-key-b", "Returning to sign-in reconciles a key change missed while busy")
        XCTAssertEqual(phrase()?.stringValue, "")
        XCTAssertEqual(fields()?.secret.stringValue, "synthetic-edited-password")
        XCTAssertEqual(session.phase, .interrupted)
    }
    #endif
    func testFilesSignInAtNarrowWidthAndAccessibilitySize() async throws {
        let mac = DirectMacRecordV1(id: UUID(), name: "Synthetic Mac", addresses: ["fixture.local"])
        for large in [false, true] {
            let session = DirectFilesSession(mac: mac); defer { session.close() }
            let view = DirectFilesView(mac: mac, session: session).environment(\.dynamicTypeSize, large ? .accessibility3 : .large)
            #if os(iOS)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let previous = scene.windows.first { $0.isKeyWindow }
            let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            window.rootViewController = UIHostingController(rootView: view); window.makeKeyAndVisible()
            defer { window.endEditing(true); window.isHidden = true; window.rootViewController = nil; previous?.makeKeyAndVisible() }
            try await Task.sleep(for: .milliseconds(200))
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            #else
            let host = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(200)); host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
            let image = NSImage(size: host.bounds.size); image.addRepresentation(bitmap)
            #endif
            let attachment = XCTAttachment(image: image); attachment.name = "files-sign-in-" + (large ? "accessibility" : "default"); attachment.lifetime = .keepAlways; add(attachment)
            XCTAssertEqual(session.phase, .signIn, "Presentation must never authenticate automatically")
            XCTAssertFalse(session.busy)
        }
    }
}
