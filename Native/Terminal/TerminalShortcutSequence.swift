#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation

enum TerminalControlsFamily: String, Codable { case terminal, remoteMac }

/// A step owns its chord. It never borrows the live keyboard's modifier state.
struct TerminalShortcutStep: Codable, Equatable, Identifiable {
    // Keep the old `text` spelling for saved paste steps.
    enum Kind: String, Codable, CaseIterable {
        case key, typeText, text, wait
        var title: String {
            switch self { case .key: "Press Key"; case .typeText: "Type Text"; case .text: "Paste Text"; case .wait: "Wait" }
        }
        var symbol: String {
            switch self { case .key: "keyboard"; case .typeText: "character.cursor.ibeam"; case .text: "doc.on.clipboard"; case .wait: "hourglass" }
        }
    }
    var id = UUID()
    var kind: Kind = .key
    var character: UInt32 = 0
    var modifiers: [UInt32] = []
    var text = ""
    var waitMilliseconds: Int?
    var isText: Bool { kind == .text || kind == .typeText }
    var hasTypingSeparators: Bool { text.unicodeScalars.contains { [9, 10, 13, 0x2028, 0x2029].contains($0.value) } }
    var chord: VNCQuickAction { .init(title: "Step", kind: .shortcut, key: character, modifiers: modifiers) }
    var valid: Bool {
        switch kind {
        case .key: return waitMilliseconds == nil && text.isEmpty && chord.terminalShortcutValid
        case .text, .typeText:
            return waitMilliseconds == nil && character == 0 && modifiers.isEmpty && text.utf8.count <= 4096
                && (try? DirectComposedText(text, mode: .terminal)) != nil
                && (kind != .typeText || !hasTypingSeparators)
        case .wait: return character == 0 && modifiers.isEmpty && text.isEmpty && waitMilliseconds.map { (100...30_000).contains($0) } == true
        }
    }
    var label: String { kind == .key && character == 0xff0d ? compactLabel + " Return" : compactLabel }
    var compactLabel: String {
        if isText { return (kind == .typeText ? "Type · " : "Paste · ") + String(text.replacingOccurrences(of: "\n", with: "↵").prefix(24)) }
        if kind == .wait { return "Wait " + (Double(waitMilliseconds ?? 1000) / 1000).formatted(.number.precision(.fractionLength(0...1))) + " s" }
        guard character != 0 else { return "Choose Key" }
        let names: [(UInt32, String)] = [(0xffe3, "⌃"), (0xffe9, "⌥"), (0xffe1, "⇧"), (0xffeb, "⌘")]
        let key = TerminalAccessoryKey.allCases.first { $0.shortcutCode == character }?.title
            ?? (character == 0xff08 ? "⌫" : character == 0xff0d ? "↵" : character == 0x20 ? "Space" : UnicodeScalar(character).map(String.init) ?? "Choose Key")
        return names.filter { modifiers.contains($0.0) }.map(\.1).joined() + key
    }
    var remoteEvents: [[String: Any]] {
        var events: [[String: Any]] = []
        let keyboard = CompanionVNCKeyboard { events.append(contentsOf: $0 as? [[String: Any]] ?? []) }
        if isText { return (try? DirectComposedText(text, mode: .desktop))?.desktopEvents ?? [] }
        else if kind == .wait { return [] }
        else {
            for code in modifiers { keyboard.toggleModifier(code) }
            keyboard.pressKey(character)
        }
        return events
    }
    func terminalBytes(encoding: TerminalKeyEncoding, bracketedPaste: Bool) throws -> [UInt8] {
        guard valid, kind != .wait else { throw TerminalSequenceFailure.invalid }
        let bytes: [UInt8]
        switch kind {
        case .text: bytes = try DirectComposedText(text, mode: .terminal).terminalBytes(bracketedPaste: bracketedPaste)
        case .typeText: bytes = text.unicodeScalars.flatMap { encoding.bytes(.text(String($0))) }
        case .key:
            guard !modifiers.contains(0xffeb) || encoding.supportsCommand else { throw TerminalSequenceFailure.unsupported }
            bytes = chord.terminalBytes(encoding: encoding)
        case .wait: throw TerminalSequenceFailure.invalid
        }
        guard !bytes.isEmpty else { throw TerminalSequenceFailure.unsupported }
        return bytes
    }
}

/// Connection-local consent, separate from the saved shortcut and input epochs.
@MainActor struct TerminalShortcutConfirmations {
    private var connection: String?
    private var skipped: [UUID: TerminalControlAction] = [:]
    private mutating func use(_ connectionID: String) {
        if connection != connectionID { connection = connectionID; skipped.removeAll() }
    }
    mutating func requiresReview(_ action: TerminalControlAction, connectionID: String) -> Bool {
        use(connectionID)
        if let previous = skipped[action.id], !action.sameDefinition(as: previous) { skipped.removeValue(forKey: action.id) }
        return action.confirmBeforeRunning == true && skipped[action.id] == nil
    }
    mutating func skip(_ action: TerminalControlAction, connectionID: String) {
        use(connectionID); skipped[action.id] = action
    }
    mutating func definitionsChanged(_ actions: [TerminalControlAction]) {
        skipped = skipped.filter { id, previous in actions.contains { $0.id == id && $0.sameDefinition(as: previous) } }
    }
}

enum TerminalSequenceOperation<Payload> {
    case input(Payload)
    case wait(Int)
    var input: Payload? { if case .input(let payload) = self { return payload }; return nil }
}

@MainActor enum TerminalSequencePump {
    /// Wait in short cancellable slices, without blocking the UI or socket reader.
    static func run<Payload>(_ operations: [TerminalSequenceOperation<Payload>], current: @MainActor () -> Bool,
                            pause: @MainActor (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
                            progress: @MainActor (Int) -> Void = { _ in },
                            send: @MainActor (Int, Payload) async throws -> Void) async throws {
        for (index, operation) in operations.enumerated() {
            guard current(), !Task.isCancelled else { throw CancellationError() }
            progress(index)
            switch operation {
            case .input(let payload): try await send(index, payload)
            case .wait(let milliseconds):
                guard (100...30_000).contains(milliseconds) else { throw TerminalSequenceFailure.invalid }
                var remaining = milliseconds
                while remaining > 0 {
                    guard current(), !Task.isCancelled else { throw CancellationError() }
                    let slice = min(50, remaining)
                    try await pause(UInt64(slice) * 1_000_000)
                    remaining -= slice
                }
            }
        }
        guard current(), !Task.isCancelled else { throw CancellationError() }
    }
    static func write(_ packets: [[UInt8]], current: @MainActor () -> Bool, send: @MainActor ([UInt8]) async throws -> Void) async throws {
        try await run(packets.map { .input($0) }, current: current) { _, packet in try await send(packet) }
    }
}

enum TerminalSequenceFailure: Error { case invalid, unsupported, tooLarge }

extension TerminalControlAction {
    /// Adding a step only edits the draft; repeated Return keys remain explicit.
    @discardableResult mutating func appendShortcutStep(_ step: TerminalShortcutStep) -> Bool {
        let current = steps ?? (character == 0 ? [] : resolvedSteps)
        guard kind == .shortcut, step.valid, current.count < 32, !current.contains(where: { $0.id == step.id }) else { return false }
        steps = current + [step]; return true
    }
    var resolvedSteps: [TerminalShortcutStep] {
        steps ?? [.init(character: character, modifiers: modifiers)]
    }
    var hasSequenceText: Bool { kind == .shortcut && resolvedSteps.contains( where: \.isText) }
    var hasSequenceWait: Bool { kind == .shortcut && resolvedSteps.contains { $0.kind == .wait } }
    var sequencePreview: String { resolvedSteps.map(\.label).joined(separator: " → ") }
    /// Timed plans retain step indices, never a forecast of future mode-dependent bytes.
    func terminalSchedule() throws -> [TerminalSequenceOperation<Int>] {
        guard kind == .shortcut, valid else { throw TerminalSequenceFailure.invalid }
        return resolvedSteps.enumerated().map { index, step in
            step.kind == .wait ? .wait(step.waitMilliseconds!) : .input(index)
        }
    }
    func terminalPlan(encoding: TerminalKeyEncoding, bracketedPaste: Bool) throws -> [TerminalSequenceOperation<[UInt8]>] {
        guard kind == .shortcut, valid else { throw TerminalSequenceFailure.invalid }
        var operations: [TerminalSequenceOperation<[UInt8]>] = []
        for step in resolvedSteps {
            if step.kind == .wait { operations.append(.wait(step.waitMilliseconds!)); continue }
            let bytes = try step.terminalBytes(encoding: encoding, bracketedPaste: bracketedPaste)
            operations.append(.input(bytes))
        }
        guard operations.compactMap(\.input).reduce(0, { $0 + $1.count }) <= 16384 else { throw TerminalSequenceFailure.tooLarge }
        return operations
    }
    func remotePlan() throws -> [TerminalSequenceOperation<[[String: Any]]>] {
        guard kind == .shortcut, valid else { throw TerminalSequenceFailure.invalid }
        var operations: [TerminalSequenceOperation<[[String: Any]]>] = []
        var eventCount = 0
        for step in resolvedSteps {
            if step.kind == .wait { operations.append(.wait(step.waitMilliseconds!)); continue }
            let group = step.remoteEvents
            guard !group.isEmpty else { throw TerminalSequenceFailure.unsupported }
            operations.append(.input(group)); eventCount += group.count
        }
        guard eventCount > 0, eventCount <= 512 else { throw TerminalSequenceFailure.tooLarge }
        return operations
    }
    // Legacy callers cannot silently discard waits.
    func terminalSequence(encoding: TerminalKeyEncoding, bracketedPaste: Bool) throws -> [[UInt8]] {
        guard !hasSequenceWait else { throw TerminalSequenceFailure.unsupported }
        return try terminalPlan(encoding: encoding, bracketedPaste: bracketedPaste).compactMap(\.input)
    }
    func remoteSequence() throws -> [[String: Any]] {
        guard !hasSequenceWait else { throw TerminalSequenceFailure.unsupported }
        return try remotePlan().compactMap(\.input).flatMap { $0 }
    }
}
#endif
