#if os(visionOS) && MACCOMPANION_VNC_DEVELOPMENT
import UIKit

/// Retains HID identities and modifiers, never text or a composed string.
@MainActor final class VisionPhysicalKeyboard {
    var send: @MainActor (UInt32, Bool) -> Void = { _, _ in }
    private var pressed: [UIKeyboardHIDUsage: UInt32] = [:]
    private var modifiers: Set<UInt32> = []
    private var modifierPressed: [UIKeyboardHIDUsage: UInt32] = [:]
    private static let flags: [(UIKeyModifierFlags, UInt32)] = [(.shift, 0xffe1), (.control, 0xffe3), (.alternate, 0xffe9), (.command, 0xffeb)]
    func captured(_ key: UIKey) -> Bool { pressed[key.keyCode] != nil || modifierPressed[key.keyCode] != nil }
    static func capturesForTextInput(_ key: UIKey) -> Bool {
        if !key.modifierFlags.intersection([.control, .alternate, .command]).isEmpty { return true }
        guard let symbol = VisionHardwareKeys.symbol(key) else { return false }
        return (0xff00...0xffff).contains(symbol)
    }
    func handle(_ key: UIKey, down: Bool) {
        guard let symbol = VisionHardwareKeys.symbol(key) else { return }
        handle(usage: key.keyCode, symbol: symbol, flags: key.modifierFlags, down: down)
    }
    func handle(usage: UIKeyboardHIDUsage, symbol: UInt32, flags: UIKeyModifierFlags, down: Bool) {
        // A release from a retired owner must not reconstruct its modifiers.
        guard down || pressed[usage] != nil || modifierPressed[usage] != nil else { return }
        var target = Set(Self.flags.filter { flags.contains($0.0) }.map(\.1))
        let normalized: [UInt32: UInt32] = [0xffe1: 0xffe1, 0xffe2: 0xffe1, 0xffe3: 0xffe3, 0xffe4: 0xffe3,
            0xffe9: 0xffe9, 0xffea: 0xffe9, 0xffeb: 0xffeb, 0xffec: 0xffeb]
        if let modifier = normalized[symbol] {
            if down { modifierPressed[usage] = modifier; target.insert(modifier) }
            else { modifierPressed.removeValue(forKey: usage); if !modifierPressed.values.contains(modifier) { target.remove(modifier) } }
            sync(target); return
        }
        if down { sync(target) }
        if !(0xffe1...0xffec).contains(symbol) {
            if down { pressed[usage] = symbol; send(symbol, true) }
            else if let original = pressed.removeValue(forKey: usage) { send(original, false) }
        }
        if !down { sync(target) }
    }
    private func sync(_ target: Set<UInt32>) {
        for key in modifiers.subtracting(target).sorted() { send(key, false) }
        for key in target.subtracting(modifiers).sorted() { send(key, true) }
        modifiers = target
    }
    func clear() { pressed = [:]; modifiers = []; modifierPressed = [:] }
}
#endif
