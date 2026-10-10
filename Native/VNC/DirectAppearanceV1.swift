#if (os(iOS) || os(macOS)) && MACCOMPANION_VNC_DEVELOPMENT
import Observation
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

enum DirectAppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? { self == .system ? nil : self == .dark ? .dark : .light }
    #if os(iOS)
    var interfaceStyle: UIUserInterfaceStyle { self == .system ? .unspecified : self == .dark ? .dark : .light }
    #endif
}

enum DirectTerminalAppearance: String, CaseIterable, Identifiable {
    case app, light, dark
    var id: String { rawValue }
    var title: String { self == .app ? "Follow App" : rawValue.capitalized }
    #if os(iOS)
    func style(app: DirectAppAppearance) -> UIUserInterfaceStyle { self == .app ? app.interfaceStyle : self == .dark ? .dark : .light }
    #endif
}

/// One preference source for SwiftUI, native controls and the separate privacy window.
@MainActor @Observable final class DirectAppearanceV1 {
    static let shared = DirectAppearanceV1()
    static let appKey = "direct-client-appearance-v1"
    static let terminalKey = "direct-terminal-appearance-v1"
    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?
    var app: DirectAppAppearance {
        didSet { defaults.set(app.rawValue, forKey: Self.appKey); applyWindows() }
    }
    var terminal: DirectTerminalAppearance {
        didSet { defaults.set(terminal.rawValue, forKey: Self.terminalKey) }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        app = DirectAppAppearance(rawValue: defaults.string(forKey: Self.appKey) ?? "") ?? .system
        terminal = DirectTerminalAppearance(rawValue: defaults.string(forKey: Self.terminalKey) ?? "") ?? .app
    }
    func install() {
        if observer == nil {
            #if os(iOS)
            let name = UIScene.didActivateNotification
            #else
            let name = NSApplication.didBecomeActiveNotification
            #endif
            observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyWindows() }
            }
        }
        applyWindows()
    }
    func applyWindows() {
        #if os(iOS)
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows { window.overrideUserInterfaceStyle = app.interfaceStyle }
        }
        #else
        NSApplication.shared.appearance = app == .system ? nil : NSAppearance(named: app == .dark ? .darkAqua : .aqua)
        #endif
    }
}

private struct DirectAppearanceModifier: ViewModifier {
    @State private var appearance = DirectAppearanceV1.shared
    func body(content: Content) -> some View {
        content.environment(appearance).preferredColorScheme(appearance.app.colorScheme)
            .onAppear { appearance.install() }
    }
}
extension View {
    func directAppearance() -> some View { modifier(DirectAppearanceModifier()) }
}
#endif
