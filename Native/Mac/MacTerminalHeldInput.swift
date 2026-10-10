#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation

// Only this ledger can manufacture cleanup. It retains report identities, never
// terminal text, and cannot admit input to a replacement connection.
struct MacTerminalInputReleases {
    let packets: [[UInt8]]
    fileprivate init(_ packets: [[UInt8]]) { self.packets = packets }
}

struct MacTerminalHeldInput {
    private var keys: [String: [UInt8]] = [:]
    private var buttons: [Int: [UInt8]] = [:]

    mutating func observe(_ bytes: ArraySlice<UInt8>, keyboardEvents: Bool,
                          releasedButton: Int? = nil) -> Bool {
        guard let (prefix, body) = Self.report(bytes, keyboardEvents: keyboardEvents) else { return true }
        if MacTerminalMouseReport.contains(bytes) {
            if body.first == 77 {
                let payload = body.dropFirst()
                guard let encoded = payload.first, encoded >= 32 else { return true }
                let flags = Int(encoded) - 32
                let release = prefix + [77, UInt8((flags & ~32 & ~3) + 3 + 32)] + payload.dropFirst()
                mouse(flags: flags, released: flags & 3 == 3 && flags & 32 == 0,
                      release: release, releasedButton: releasedButton)
            } else {
                let sgr = body.first == 60
                let numbers = (sgr ? body.dropFirst() : body[...]).dropLast().split(separator: 59)
                guard numbers.count == 3, let encoded = Self.number(numbers[0]) else { return true }
                let flags = encoded - (sgr ? 0 : 32)
                guard flags >= 0 else { return true }
                let released = sgr ? body.last == 109 : flags & 3 == 3 && flags & 32 == 0
                let flag = sgr ? flags & ~32 : (flags & ~32 & ~3) + 3 + 32
                let fields = String(flag) + ";" + String(decoding: numbers[1], as: UTF8.self)
                    + ";" + String(decoding: numbers[2], as: UTF8.self)
                let release = prefix + (sgr ? [60] : []) + Array(fields.utf8) + [sgr ? 109 : 77]
                mouse(flags: flags, released: released, release: release, releasedButton: releasedButton)
            }
            return true
        }
        guard keyboardEvents, let final = body.last,
              [UInt8(117), 126, 65, 66, 67, 68, 72, 70, 80, 81, 82, 83].contains(final) else { return true }
        let fields = body.dropLast().split(separator: 59, omittingEmptySubsequences: false)
        guard (1...3).contains(fields.count) else { return true }
        let primary = fields.first?.split(separator: 58).first
        let implicit = fields.count == 1 && fields[0].isEmpty && final != 117 && final != 126
        guard let key = implicit ? 1 : primary.flatMap(Self.number), key > 0 else { return true }
        let modifiers = fields.count > 1 ? fields[1].split(separator: 58, omittingEmptySubsequences: false) : []
        guard modifiers.isEmpty || (modifiers.count <= 2 && Self.number(modifiers[0]) != nil) else { return true }
        let event = modifiers.count == 2 ? Self.number(modifiers[1]) : 1
        guard let event, (1...3).contains(event) else { return true }
        let identity = String(final) + ":" + String(key)
        if event == 3 { keys.removeValue(forKey: identity); return true }
        guard keys[identity] != nil || keys.count < 256 else { return false }
        keys[identity] = prefix + Array((String(key) + ";1:3").utf8) + [final]
        return true
    }

    mutating func releaseAll() -> MacTerminalInputReleases {
        let packets = keys.keys.sorted().compactMap { keys[$0] } + buttons.keys.sorted().compactMap { buttons[$0] }
        keys.removeAll(keepingCapacity: false); buttons.removeAll(keepingCapacity: false)
        return MacTerminalInputReleases(packets)
    }

    private mutating func mouse(flags: Int, released: Bool, release: [UInt8], releasedButton: Int?) {
        guard flags & 64 == 0 else { return } // Wheel reports never hold a button.
        if released {
            if let releasedButton { buttons.removeValue(forKey: releasedButton) }
            else { buttons.removeAll(keepingCapacity: false) }
        } else if flags & 3 != 3 {
            let button = flags & 3
            if flags & 32 == 0 || buttons[button] != nil { buttons[button] = release }
        }
    }
    private static func report(_ bytes: ArraySlice<UInt8>, keyboardEvents: Bool) -> ([UInt8], ArraySlice<UInt8>)? {
        if bytes.starts(with: [27, 91]) { return ([27, 91], bytes.dropFirst(2)) }
        if bytes.first == 155 { return ([155], bytes.dropFirst()) }
        // With report-events alone, SwiftTerm emits legacy SS3 presses for
        // application cursor keys/F1-F4, followed by CSI releases.
        if keyboardEvents, bytes.count == 3, bytes.starts(with: [27, 79]) { return ([27, 91], bytes.dropFirst(2)) }
        if keyboardEvents, bytes.count == 2, bytes.first == 143 { return ([27, 91], bytes.dropFirst()) }
        return nil
    }
    private static func number(_ bytes: ArraySlice<UInt8>) -> Int? {
        guard !bytes.isEmpty, bytes.count <= 10, bytes.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return Int(String(decoding: bytes, as: UTF8.self))
    }
}
#endif
