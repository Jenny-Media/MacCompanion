#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import AppKit

struct MacVNCKeyEvent: Equatable {
    let key: UInt32
    let down: Bool
    var dictionary: [String: Any] { ["key": key, "down": down] }
}

/// The input method sees only this local, bounded preedit document. Remote
/// pixels and committed text never become a readable text-input document.
struct MacVNCComposition {
    private(set) var text = ""
    private(set) var selection = NSRange(location: NSNotFound, length: 0)
    var hasMarkedText: Bool { !text.isEmpty }
    var markedRange: NSRange { .init(location: hasMarkedText ? 0 : NSNotFound, length: text.utf16.count) }
    mutating func set(_ text: String, selectedRange: NSRange) {
        guard text.utf16.count <= 4096 else { discard(); return }
        self.text = text
        let length = text.utf16.count
        let start = selectedRange.location == NSNotFound ? length : min(selectedRange.location, length)
        selection = .init(location: start, length: min(selectedRange.length, length - start))
    }
    mutating func discard() { text = ""; selection = .init(location: NSNotFound, length: 0) }
    func substring(_ range: NSRange) -> (NSAttributedString, NSRange)? {
        guard hasMarkedText, range.location != NSNotFound, range.location < text.utf16.count else { return nil }
        let bounded = NSRange(location: range.location, length: min(range.length, text.utf16.count - range.location))
        let string = text as NSString
        let actual = bounded.length == 0 ? bounded : string.rangeOfComposedCharacterSequences(for: bounded)
        return (NSAttributedString(string: string.substring(with: actual)), actual)
    }
}

struct MacVNCKeyboardState {
    private(set) var held: [UInt16: UInt32] = [:]
    private(set) var modifiers: [UInt32] = []
    static func keysym(code: UInt16, characters: String) -> UInt32? {
        let special: [UInt16: UInt32] = [36: 0xff0d, 48: 0xff09, 51: 0xff08, 53: 0xff1b,
            76: 0xff8d, 115: 0xff50, 116: 0xff55, 117: 0xffff, 119: 0xff57, 121: 0xff56,
            123: 0xff51, 124: 0xff53, 125: 0xff54, 126: 0xff52,
            122: 0xffbe, 120: 0xffbf, 99: 0xffc0, 118: 0xffc1, 96: 0xffc2, 97: 0xffc3,
            98: 0xffc4, 100: 0xffc5, 101: 0xffc6, 109: 0xffc7, 103: 0xffc8, 111: 0xffc9]
        if let key = special[code] { return key }
        guard let scalar = characters.unicodeScalars.first, scalar.value >= 0x20,
              !(0xf700...0xf8ff).contains(scalar.value) else { return nil }
        return scalar.value < 256 ? scalar.value : 0x01000000 | scalar.value
    }
    mutating func updateModifiers(_ flags: NSEvent.ModifierFlags) -> [MacVNCKeyEvent] {
        let mapping: [(NSEvent.ModifierFlags, UInt32)] = [(.shift, 0xffe1), (.control, 0xffe3), (.option, 0xffe9), (.command, 0xffeb)]
        let next = mapping.compactMap { flags.contains($0.0) ? $0.1 : nil }
        let events = modifiers.reversed().filter { !next.contains($0) }.map { MacVNCKeyEvent(key: $0, down: false) }
            + next.filter { !modifiers.contains($0) }.map { MacVNCKeyEvent(key: $0, down: true) }
        modifiers = next
        return events
    }
    mutating func keyDown(code: UInt16, characters: String, repeatKey: Bool) -> [MacVNCKeyEvent] {
        if let key = held[code] { return repeatKey ? [.init(key: key, down: true)] : [] }
        guard let key = Self.keysym(code: code, characters: characters) else { return [] }
        held[code] = key
        return [.init(key: key, down: true)]
    }
    mutating func keyUp(code: UInt16) -> [MacVNCKeyEvent] {
        guard let key = held.removeValue(forKey: code) else { return [] }
        return [.init(key: key, down: false)]
    }
    mutating func releaseAll() -> [MacVNCKeyEvent] {
        let result = held.keys.sorted().compactMap { held[$0] }.map { MacVNCKeyEvent(key: $0, down: false) }
            + modifiers.reversed().map { MacVNCKeyEvent(key: $0, down: false) }
        held = [:]; modifiers = []
        return result
    }
}

enum MacVNCGeometry {
    static func following(cursor: CGPoint, crop: CGRect, viewport: CGSize, zoom: CGFloat, pan: CGPoint) -> CGPoint {
        let dest = destination(crop: crop, viewport: viewport, zoom: zoom, pan: pan)
        guard !dest.isEmpty, crop.contains(cursor), zoom > 1 else { return pan }
        let px = dest.minX + (cursor.x - crop.minX) / crop.width * dest.width
        let py = dest.minY + (cursor.y - crop.minY) / crop.height * dest.height
        let marginX = min(40, viewport.width / 4), marginY = min(40, viewport.height / 4)
        let effective = CGPoint(x: dest.midX - viewport.width / 2, y: dest.midY - viewport.height / 2)
        let proposed = CGPoint(x: effective.x + max(marginX, min(viewport.width - marginX, px)) - px,
                               y: effective.y + max(marginY, min(viewport.height - marginY, py)) - py)
        let result = destination(crop: crop, viewport: viewport, zoom: zoom, pan: proposed)
        return CGPoint(x: result.midX - viewport.width / 2, y: result.midY - viewport.height / 2)
    }
    static func destination(crop: CGRect, viewport: CGSize, zoom: CGFloat = 1, pan: CGPoint = .zero) -> CGRect {
        guard !crop.isEmpty, viewport.width > 0, viewport.height > 0, zoom.isFinite else { return .zero }
        let scale = min(viewport.width / crop.width, viewport.height / crop.height) * max(1, min(8, zoom))
        let size = CGSize(width: crop.width * scale, height: crop.height * scale)
        let maxX = max(0, (size.width - viewport.width) / 2), maxY = max(0, (size.height - viewport.height) / 2)
        return .init(x: (viewport.width - size.width) / 2 + max(-maxX, min(maxX, pan.x)),
                     y: (viewport.height - size.height) / 2 + max(-maxY, min(maxY, pan.y)), width: size.width, height: size.height)
    }
    static func map(point: CGPoint, crop: CGRect, destination: CGRect, clamp: Bool = false) -> CGPoint? {
        guard !crop.isEmpty, !destination.isEmpty, point.x.isFinite, point.y.isFinite,
              clamp || destination.contains(point) else { return nil }
        return .init(x: crop.minX + floor(max(0, min(crop.width - 1, (point.x - destination.minX) / destination.width * crop.width))),
                     y: crop.minY + floor(max(0, min(crop.height - 1, (point.y - destination.minY) / destination.height * crop.height))))
    }
}
#endif
