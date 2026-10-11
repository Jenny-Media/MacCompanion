import SwiftUI
import StoreKitTest
import XCTest
#if os(iOS)
import UIKit
@testable import Mac_Companion
#else
import AppKit
@testable import MacCompanion
#endif

private struct SettingsSnapshotCloud: DirectCloudTransport {
    func read() throws -> [Data] { [] }
    func write(_ data: Data, account: String) throws { throw DirectCloudError.storage }
    func removeAll() throws { throw DirectCloudError.storage }
}

@MainActor final class SettingsFeedbackLayoutTests: XCTestCase {
    func testMacDetailsRemainCompactAndCaptureSharedFormsAtNormalAndLargeTextSizes() async throws {
        for size in [DynamicTypeSize.large, .accessibility3] {
            let details = DirectMacDetailsContent(name: "Synthetic Mac", model: "MacBookPro18,3", scanning: false, unavailable: false, refresh: {})
                .environment(\.dynamicTypeSize, size)
            #if os(iOS)
            let host = UIHostingController(rootView: details)
            let fitting = host.sizeThatFits(in: .init(width: 340, height: 1200))
            XCTAssertLessThan(fitting.height, size == .large ? 240 : 440, "Mac Details must not create an empty flexible-height row")
            #else
            let host = NSHostingView(rootView: details)
            host.frame = .init(x: 0, y: 0, width: 420, height: 240)
            host.layoutSubtreeIfNeeded()
            XCTAssertLessThan(host.fittingSize.height, 240)
            #endif
            let form = NavigationStack {
                Form {
                    Section {
                        DisclosureGroup("Mac Details", isExpanded: .constant(true)) { details }
                    }
                    Section {
                        DisclosureGroup("Service Ports", isExpanded: .constant(true)) {
                            DirectServicePortField(title: "Screen Sharing", defaultPort: "5900", value: .constant(""), identifier: "qa-vnc-port")
                            DirectServicePortField(title: "Remote Login (SSH)", defaultPort: "22", value: .constant(""), identifier: "qa-ssh-port")
                        }
                    }
                }.directGroupedForm().navigationTitle("Mac Details").directInlineNavigationTitle()
            }.environment(\.dynamicTypeSize, size)
            try await capture(form, name: "mac-details-and-ports-" + (size == .large ? "normal" : "large"))
        }
    }
    func testCaptureSyncInformationAndProOnBothPlatforms() async throws {
        let config = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "LifetimePro", withExtension: "storekit"))
        let store = try SKTestSession(contentsOf: config); store.disableDialogs = true; store.clearTransactions()
        defer { store.clearTransactions() }
        let pro = DirectProAccess(); await pro.loadProduct()
        let suite = "settings-feedback-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let cloud = DirectCloudSyncV1(defaults: defaults, url: FileManager.default.temporaryDirectory.appending(path: suite),
            transport: SettingsSnapshotCloud(), writerID: UUID())
        let previous = DirectAppearanceV1.shared.app
        defer { DirectAppearanceV1.shared.app = previous }
        for appearance in [DirectAppAppearance.light, .dark] {
            DirectAppearanceV1.shared.app = appearance
            try await capture(NavigationStack { DirectSyncSecurityForm(cloud: cloud)
                .navigationTitle("Sync & Security").directInlineNavigationTitle() }.directAppearance(),
                name: "sync-security-" + appearance.rawValue)
            try await capture(DirectCloudInformationSheet(kind: .deleteData, cloud: cloud).directAppearance(), name: "delete-review-" + appearance.rawValue)
            try await capture(DirectProView(access: pro).directAppearance(), name: "pro-" + appearance.rawValue)
            #if os(iOS)
            if appearance == .light {
                try await capture(DirectProView(access: pro).directAppearance().environment(\.dynamicTypeSize, .accessibility3), name: "pro-large-text")
            }
            #endif
        }
    }
    private func capture<V: View>(_ view: V, name: String) async throws {
        #if os(iOS)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let original = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: view); window.makeKeyAndVisible()
        defer { window.endEditing(true); window.isHidden = true; window.rootViewController = nil; original?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(350))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        #else
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: 600, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(350)); host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds)); host.cacheDisplay(in: host.bounds, to: bitmap)
        let image = NSImage(size: host.bounds.size); image.addRepresentation(bitmap)
        #endif
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
