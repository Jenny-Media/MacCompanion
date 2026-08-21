#if canImport(UIKit)
import CompanionInteractiveClient
import CoreGraphics
import UIKit

public enum UIKitClientInputAdapterV0 {
    public static func point(_ value: CGPoint) throws -> ClientInputPointV0 {
        try ClientInputPointV0(x: Double(value.x), y: Double(value.y))
    }

    @MainActor public static func location(
        of recognizer: UIGestureRecognizer,
        in view: UIView
    ) throws -> ClientInputPointV0 {
        try point(recognizer.location(in: view))
    }

    /// Consumes the incremental pan translation exactly once so a caller does
    /// not accidentally resend a reliable pointer delta.
    @MainActor public static func consumeTranslation(
        of recognizer: UIPanGestureRecognizer,
        in view: UIView
    ) throws -> ClientInputPointV0 {
        let translation = recognizer.translation(in: view)
        let point = try self.point(translation)
        recognizer.setTranslation(.zero, in: view)
        return point
    }

    public static func keyboardAction(
        for input: String
    ) -> ClientKeyboardActionV0? {
        switch input {
        case UIKeyCommand.inputDelete:
            return .deleteBackward
        case "\r", "\n":
            return .returnKey
        case "\t":
            return .tab
        case "\u{1b}":
            return .escape
        case UIKeyCommand.inputRightArrow:
            return .arrowRight
        case UIKeyCommand.inputLeftArrow:
            return .arrowLeft
        case UIKeyCommand.inputDownArrow:
            return .arrowDown
        case UIKeyCommand.inputUpArrow:
            return .arrowUp
        case "":
            return nil
        default:
            return .text(input)
        }
    }
}
#endif
