import Foundation

public enum InteractiveInputStreamError: Error, Equatable, Sendable {
    case sequenceMismatch(expected: UInt64, actual: UInt64)
    case clientTimeWentBackward
    case totalRateExceeded
    case pointerRateExceeded
    case repeatedButtonDown
    case unmatchedButtonUp
    case repeatedKeyDown
    case unmatchedKeyUp
    case textDeniedWhileLocked
}

public struct InteractiveInputStreamState: Equatable, Sendable {
    public static let maximumTotalMessagesPerSecond = 240
    public static let maximumPointerMovesPerSecond = 120

    public private(set) var lastSequence: UInt64 = 0
    public private(set) var lastClientMonotonicMilliseconds: UInt64 = 0
    public private(set) var pressedButtons: Set<InteractivePointerButton> = []
    public private(set) var pressedKeyboardUsages: Set<UInt16> = []
    public private(set) var modifierMask: InteractiveModifierMask = []
    private var totalAdmissionTimes: [UInt64] = []
    private var pointerAdmissionTimes: [UInt64] = []

    public init() {}

    public mutating func admit(
        _ envelope: InteractiveInputEnvelope,
        hostUnlocked: Bool,
        hostMonotonicMilliseconds: UInt64
    ) throws {
        try envelope.validate()
        let expected = lastSequence + 1
        guard envelope.sequence == expected else {
            throw InteractiveInputStreamError.sequenceMismatch(
                expected: expected,
                actual: envelope.sequence
            )
        }
        guard lastSequence == 0 ||
                envelope.clientMonotonicMilliseconds >= lastClientMonotonicMilliseconds else {
            throw InteractiveInputStreamError.clientTimeWentBackward
        }

        let cutoff = hostMonotonicMilliseconds >= 1_000
            ? hostMonotonicMilliseconds - 1_000
            : 0
        let retainedTotal = totalAdmissionTimes.filter { $0 > cutoff }
        let retainedPointer = pointerAdmissionTimes.filter { $0 > cutoff }
        guard retainedTotal.count < Self.maximumTotalMessagesPerSecond else {
            throw InteractiveInputStreamError.totalRateExceeded
        }
        if envelope.input.kind == .pointerMove,
           retainedPointer.count >= Self.maximumPointerMovesPerSecond {
            throw InteractiveInputStreamError.pointerRateExceeded
        }

        var nextButtons = pressedButtons
        var nextKeys = pressedKeyboardUsages
        var nextModifiers = modifierMask
        switch envelope.input {
        case let .button(button, transition):
            switch transition {
            case .down:
                guard nextButtons.insert(button).inserted else {
                    throw InteractiveInputStreamError.repeatedButtonDown
                }
            case .up:
                guard nextButtons.remove(button) != nil else {
                    throw InteractiveInputStreamError.unmatchedButtonUp
                }
            }
        case let .physicalKey(usage, transition, modifiers):
            switch transition {
            case .down:
                guard nextKeys.insert(usage).inserted else {
                    throw InteractiveInputStreamError.repeatedKeyDown
                }
            case .up:
                guard nextKeys.remove(usage) != nil else {
                    throw InteractiveInputStreamError.unmatchedKeyUp
                }
            }
            nextModifiers = modifiers
        case let .modifiers(modifiers):
            nextModifiers = modifiers
        case .text:
            guard hostUnlocked else {
                throw InteractiveInputStreamError.textDeniedWhileLocked
            }
        case .reset:
            nextButtons.removeAll(keepingCapacity: true)
            nextKeys.removeAll(keepingCapacity: true)
            nextModifiers = []
        case .pointerMove, .scroll:
            break
        }

        lastSequence = envelope.sequence
        lastClientMonotonicMilliseconds = envelope.clientMonotonicMilliseconds
        pressedButtons = nextButtons
        pressedKeyboardUsages = nextKeys
        modifierMask = nextModifiers
        totalAdmissionTimes = retainedTotal + [hostMonotonicMilliseconds]
        pointerAdmissionTimes = envelope.input.kind == .pointerMove
            ? retainedPointer + [hostMonotonicMilliseconds]
            : retainedPointer
    }

    public mutating func releaseAll() {
        pressedButtons.removeAll(keepingCapacity: true)
        pressedKeyboardUsages.removeAll(keepingCapacity: true)
        modifierMask = []
    }
}
