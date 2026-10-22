#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

@MainActor enum TerminalControlNavigation {
    static let items: [[String: Any]] = [
        ["kind": "moreKeys", "title": "Keypad", "symbol": "rectangle.grid.3x2"],
        ["kind": "savedShortcuts", "title": "Shortcuts", "symbol": "list.bullet.rectangle"],
        ["kind": "savedText", "title": "Text", "symbol": "text.quote"],
        ["kind": "customize", "title": "Customize Controls", "symbol": "slider.horizontal.3"],
        ["kind": "appearance", "title": "Appearance", "symbol": "circle.lefthalf.filled"],
        ["kind": "session", "title": "Session", "symbol": "link"]]
}
#endif
