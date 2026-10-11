#if (os(iOS) || os(macOS) || os(visionOS)) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import SwiftUI
#if os(iOS) || os(visionOS)
import UIKit
#else
import AppKit
#endif

/// Platform lifecycle admission for shared models. Mac sessions can continue in
/// background windows; their AppKit surfaces separately admit focused input.
@MainActor enum DirectClientPlatformV1 {
    static var sessionAvailable: Bool {
        #if os(iOS) || os(visionOS)
        UIApplication.shared.applicationState == .active
        #else
        true
        #endif
    }
    static var didBecomeActive: Notification.Name {
        #if os(iOS) || os(visionOS)
        UIApplication.didBecomeActiveNotification
        #else
        NSApplication.didBecomeActiveNotification
        #endif
    }
    static var willResignActive: Notification.Name {
        #if os(iOS) || os(visionOS)
        UIApplication.willResignActiveNotification
        #else
        NSApplication.didResignActiveNotification
        #endif
    }
    static var didEnterBackground: Notification.Name {
        #if os(iOS) || os(visionOS)
        UIApplication.didEnterBackgroundNotification
        #else
        Notification.Name("DirectMacSessionDidSuspend")
        #endif
    }
    static func copy(_ text: String) {
        #if os(iOS) || os(visionOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
    static func open(_ url: URL) {
        #if os(iOS) || os(visionOS)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }
    static func dataURL(_ name: String) -> URL {
        #if os(macOS)
        if let directory = ProcessInfo.processInfo.environment["MACCOMPANION_DIRECT_DATA_DIRECTORY"], directory.hasPrefix("/") {
            return URL(fileURLWithPath: directory, isDirectory: true).appending(path: name)
        }
        return URL.applicationSupportDirectory.appending(path: "MacCompanion", directoryHint: .isDirectory).appending(path: name)
        #else
        return URL.applicationSupportDirectory.appending(path: name)
        #endif
    }
    static func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #if os(macOS)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #else
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #endif
    }
}

extension View {
    @ViewBuilder func directInlineNavigationTitle() -> some View {
        #if os(iOS) || os(visionOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
    @ViewBuilder func directNoAutocapitalization() -> some View {
        #if os(iOS) || os(visionOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
#endif
