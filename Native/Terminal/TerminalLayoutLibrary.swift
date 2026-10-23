#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

@MainActor enum TerminalControlNavigation {
    static var items: [[String: Any]] { items(for: .terminal) }
    static func items(for family: TerminalControlsFamily) -> [[String: Any]] { [
        ["kind": "moreKeys", "title": "Keypad", "symbol": "rectangle.grid.3x2"],
        ["kind": "savedShortcuts", "title": "Shortcuts", "symbol": "list.bullet.rectangle"],
        ["kind": "savedText", "title": "Text", "symbol": "text.quote"],
        ["kind": "customize", "title": "Customize Controls", "symbol": "slider.horizontal.3"],
        family == .terminal
            ? ["kind": "appearance", "title": "Appearance", "symbol": "circle.lefthalf.filled"]
            : ["kind": "viewMenu", "title": "Display", "symbol": "display.2"],
        ["kind": "session", "title": "Session", "symbol": "link"]] }
}
#endif
