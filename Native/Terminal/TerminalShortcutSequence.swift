#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation

enum TerminalControlsFamily: String, Codable { case terminal, remoteMac }

/// A step owns its chord. It never borrows the live keyboard's modifier state.
struct TerminalShortcutStep: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case key, text }
    var id = UUID()
    var kind: Kind = .key
    var character: UInt32 = 0
    var modifiers: [UInt32] = []
    var text = ""
    var chord: VNCQuickAction { .init(title: "Step", kind: .shortcut, key: character, modifiers: modifiers) }
    var valid: Bool {
        switch kind {
        case .key: return text.isEmpty && chord.terminalShortcutValid
        case .text: return character == 0 && modifiers.isEmpty && text.utf8.count <= 4096 && (try? DirectComposedText(text, mode: .terminal)) != nil
        }
    }
    var label: String {
        if kind == .text { return "Text · " + String(text.replacingOccurrences(of: "\n", with: "↵").prefix(24)) }
        guard character != 0 else { return "Choose Key" }
        let names: [(UInt32, String)] = [(0xffe3, "⌃"), (0xffe9, "⌥"), (0xffe1, "⇧"), (0xffeb, "⌘")]
        let key = TerminalAccessoryKey.allCases.first { $0.shortcutCode == character }?.title
            ?? (character == 0xff08 ? "⌫" : character == 0xff0d ? "↵" : character == 0x20 ? "Space" : UnicodeScalar(character).map(String.init) ?? "Choose Key")
        return names.filter { modifiers.contains($0.0) }.map(\.1).joined() + key
    }
    var remoteEvents: [[String: Any]] {
        var events: [[String: Any]] = []
        let keyboard = CompanionVNCKeyboard { events.append(contentsOf: $0 as? [[String: Any]] ?? []) }
        if kind == .text { return (try? DirectComposedText(text, mode: .desktop))?.desktopEvents ?? [] }
        else {
            for code in modifiers { keyboard.toggleModifier(code) }
            keyboard.pressKey(character)
        }
        return events
    }
}

@MainActor enum TerminalSequencePump {
    static func write(_ packets: [[UInt8]], current: () -> Bool, send: ([UInt8]) async throws -> Void) async throws {
        for packet in packets {
            guard current(), !Task.isCancelled else { throw CancellationError() }
            try await send(packet)
        }
        guard current(), !Task.isCancelled else { throw CancellationError() }
    }
}

enum TerminalSequenceFailure: Error { case invalid, unsupported, tooLarge }

extension TerminalControlAction {
    var resolvedSteps: [TerminalShortcutStep] {
        steps ?? [.init(character: character, modifiers: modifiers)]
    }
    var hasSequenceText: Bool { kind == .shortcut && resolvedSteps.contains { $0.kind == .text } }
    var sequencePreview: String { resolvedSteps.map(\.label).joined(separator: " → ") }
    func terminalSequence(encoding: TerminalKeyEncoding, bracketedPaste: Bool) throws -> [[UInt8]] {
        guard kind == .shortcut, valid else { throw TerminalSequenceFailure.invalid }
        var packets: [[UInt8]] = []
        for step in resolvedSteps {
            let bytes: [UInt8]
            if step.kind == .text {
                bytes = try DirectComposedText(step.text, mode: .terminal).terminalBytes(bracketedPaste: bracketedPaste)
            } else {
                guard !step.modifiers.contains(0xffeb) || encoding.supportsCommand else { throw TerminalSequenceFailure.unsupported }
                bytes = step.chord.terminalBytes(encoding: encoding)
            }
            guard !bytes.isEmpty else { throw TerminalSequenceFailure.unsupported }
            packets.append(bytes)
        }
        guard packets.reduce(0, { $0 + $1.count }) <= 16384 else { throw TerminalSequenceFailure.tooLarge }
        return packets
    }
    func remoteSequence() throws -> [[String: Any]] {
        guard kind == .shortcut, valid else { throw TerminalSequenceFailure.invalid }
        var events: [[String: Any]] = []
        for step in resolvedSteps {
            let group = step.remoteEvents
            guard !group.isEmpty else { throw TerminalSequenceFailure.unsupported }
            events.append(contentsOf: group)
        }
        guard !events.isEmpty, events.count <= 512 else { throw TerminalSequenceFailure.tooLarge }
        return events
    }
}
#endif
