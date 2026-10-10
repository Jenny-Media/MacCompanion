#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import AppKit
import SwiftUI

/// Observe only the containing window; never replace SwiftUI's window delegate.
struct MacWindowLifetime: NSViewRepresentable {
    let close: @MainActor () -> Void
    func makeNSView(context: Context) -> Observer { Observer(close: close) }
    func updateNSView(_ view: Observer, context: Context) { view.close = close }
    static func dismantleNSView(_ view: Observer, coordinator: ()) { view.finish() }
    @MainActor final class Observer: NSView {
        var close: @MainActor () -> Void
        private var observation: NSObjectProtocol?
        private var finished = false
        init(close: @escaping @MainActor () -> Void) { self.close = close; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observation { NotificationCenter.default.removeObserver(observation); self.observation = nil }
            guard let window else { return }
            observation = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish() }
            }
        }
        func finish() {
            guard !finished else { return }; finished = true
            if let observation { NotificationCenter.default.removeObserver(observation); self.observation = nil }
            close()
        }
    }
}
#endif
