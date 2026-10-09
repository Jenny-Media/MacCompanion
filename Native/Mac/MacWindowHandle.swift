#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import AppKit
import Observation
import SwiftUI

@MainActor @Observable final class MacWindowHandle {
    weak var window: NSWindow?
    var fullScreen = false
    func toggleFullScreen() { window?.toggleFullScreen(nil) }
    func raise() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil); NSApplication.shared.activate()
    }
    var acceptsActions: Bool { window?.isKeyWindow == true && DirectAppLockV1.shared.canAccess }
}

struct MacWindowReader: NSViewRepresentable {
    let handle: MacWindowHandle
    var initiallyFullScreen = false
    var fullScreenChanged: @MainActor (Bool) -> Void = { _ in }
    func makeNSView(context: Context) -> Reader { Reader(handle: handle, initiallyFullScreen: initiallyFullScreen, changed: fullScreenChanged) }
    func updateNSView(_ view: Reader, context: Context) { view.changed = fullScreenChanged }
    static func dismantleNSView(_ view: Reader, coordinator: ()) { view.detach() }
    @MainActor final class Reader: NSView {
        let handle: MacWindowHandle
        private let initiallyFullScreen: Bool
        var changed: @MainActor (Bool) -> Void
        private var observations: [NSObjectProtocol] = []
        private var initialized = false
        init(handle: MacWindowHandle, initiallyFullScreen: Bool, changed: @escaping @MainActor (Bool) -> Void) {
            self.handle = handle; self.initiallyFullScreen = initiallyFullScreen; self.changed = changed
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); detach()
            guard let window else { return }
            handle.window = window; handle.fullScreen = window.styleMask.contains(.fullScreen)
            for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                observations.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, let window = self.handle.window else { return }
                        self.handle.fullScreen = window.styleMask.contains(.fullScreen); self.changed(self.handle.fullScreen)
                    }
                })
            }
            if !initialized {
                initialized = true
                if initiallyFullScreen {
                    Task { @MainActor [weak self, weak window] in
                        await Task.yield()
                        guard let self, let window, self.handle.window === window, !window.styleMask.contains(.fullScreen) else { return }
                        window.toggleFullScreen(nil)
                    }
                }
            }
        }
        func detach() {
            observations.forEach(NotificationCenter.default.removeObserver); observations = []
            handle.window = nil
        }
    }
}
#endif
