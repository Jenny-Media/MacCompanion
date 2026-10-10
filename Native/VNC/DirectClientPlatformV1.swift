#if (os(iOS) || os(macOS)) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Platform lifecycle admission for shared models. Mac sessions can continue in
/// background windows; their AppKit surfaces separately admit focused input.
@MainActor enum DirectClientPlatformV1 {
    static var sessionAvailable: Bool {
        #if os(iOS)
        UIApplication.shared.applicationState == .active
        #else
        true
        #endif
    }
    static var didBecomeActive: Notification.Name {
        #if os(iOS)
        UIApplication.didBecomeActiveNotification
        #else
        NSApplication.didBecomeActiveNotification
        #endif
    }
    static var willResignActive: Notification.Name {
        #if os(iOS)
        UIApplication.willResignActiveNotification
        #else
        NSApplication.didResignActiveNotification
        #endif
    }
    static var didEnterBackground: Notification.Name {
        #if os(iOS)
        UIApplication.didEnterBackgroundNotification
        #else
        Notification.Name("DirectMacSessionDidSuspend")
        #endif
    }
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
    static func open(_ url: URL) {
        #if os(iOS)
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
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
    @ViewBuilder func directNoAutocapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }
}
#endif
