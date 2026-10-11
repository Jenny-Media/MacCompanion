import XCTest
import SwiftUI
#if os(iOS)
import UIKit
@testable import Mac_Companion
#else
import AppKit
@testable import MacCompanion
#endif

@MainActor final class DirectFilesPresentationTests: XCTestCase {
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
