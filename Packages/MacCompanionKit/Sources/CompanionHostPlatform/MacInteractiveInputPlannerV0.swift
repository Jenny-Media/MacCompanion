import CompanionInteractiveWire
import Foundation

public enum MacInteractiveInputPlanErrorV0: Error, Equatable, Sendable {
    case unsupportedHIDUsage(UInt16)
    case repeatedButtonDown(InteractivePointerButton)
    case unmatchedButtonUp(InteractivePointerButton)
    case repeatedKeyDown(UInt16)
    case unmatchedKeyUp(UInt16)
    case modifierMaskMismatch(UInt16)
}

public enum MacInteractiveInputEventV0: Equatable, Sendable {
    case pointerMove(x: UInt16, y: UInt16)
    case button(
        button: InteractivePointerButton,
        transition: InteractiveInputTransition
    )
    case scroll(unit: InteractiveScrollUnit, deltaX: Int32, deltaY: Int32)
    case key(
        virtualKeyCode: UInt16,
        transition: InteractiveInputTransition,
        modifiers: InteractiveModifierMask
    )
    case unicodeText(String)
}

/// Converts the closed wire input union into descriptions consumed by a later
/// Core Graphics adapter. This value never posts events and is safe for
/// unsigned package tests.
public struct MacInteractiveInputPlannerV0: Equatable, Sendable {
    public private(set) var pressedButtons: Set<InteractivePointerButton> = []
    public private(set) var pressedHIDUsages: Set<UInt16> = []
    public private(set) var modifiers: InteractiveModifierMask = []

    public init() {}

    public mutating func plan(
        _ payload: InteractiveInputPayload
    ) throws -> [MacInteractiveInputEventV0] {
        try payload.validate()
        switch payload {
        case let .pointerMove(x, y):
            return [.pointerMove(x: x, y: y)]
        case let .button(button, transition):
            switch transition {
            case .down:
                guard pressedButtons.insert(button).inserted else {
                    throw MacInteractiveInputPlanErrorV0.repeatedButtonDown(
                        button
                    )
                }
            case .up:
                guard pressedButtons.remove(button) != nil else {
                    throw MacInteractiveInputPlanErrorV0.unmatchedButtonUp(
                        button
                    )
                }
            }
            return [.button(button: button, transition: transition)]
        case let .scroll(unit, deltaX, deltaY):
            return [.scroll(unit: unit, deltaX: deltaX, deltaY: deltaY)]
        case let .physicalKey(usage, transition, nextModifiers):
            let virtualKeyCode = try Self.virtualKeyCode(for: usage)
            switch transition {
            case .down where pressedHIDUsages.contains(usage):
                throw MacInteractiveInputPlanErrorV0.repeatedKeyDown(usage)
            case .up where !pressedHIDUsages.contains(usage):
                throw MacInteractiveInputPlanErrorV0.unmatchedKeyUp(usage)
            default:
                break
            }
            var result: [MacInteractiveInputEventV0] = []
            if let modifier = Self.modifier(for: usage) {
                guard nextModifiers.contains(modifier)
                        == (transition == .down) else {
                    throw MacInteractiveInputPlanErrorV0.modifierMaskMismatch(
                        usage
                    )
                }
                result += synchronizeModifiers(
                    to: nextModifiers,
                    excludingUsage: usage
                )
            } else {
                result += synchronizeModifiers(to: nextModifiers)
            }
            switch transition {
            case .down:
                pressedHIDUsages.insert(usage)
            case .up:
                pressedHIDUsages.remove(usage)
            }
            modifiers = nextModifiers
            result.append(.key(
                virtualKeyCode: virtualKeyCode,
                transition: transition,
                modifiers: nextModifiers
            ))
            return result
        case let .modifiers(nextModifiers):
            return synchronizeModifiers(to: nextModifiers)
        case let .text(value):
            return [.unicodeText(value)]
        case .reset:
            return releaseAll()
        }
    }

    public mutating func releaseAll() -> [MacInteractiveInputEventV0] {
        var result: [MacInteractiveInputEventV0] = []
        var releaseModifiers = modifiers
        for usage in pressedHIDUsages.sorted() {
            if let virtualKeyCode = try? Self.virtualKeyCode(for: usage) {
                if let modifier = Self.modifier(for: usage) {
                    releaseModifiers.remove(modifier)
                }
                result.append(.key(
                    virtualKeyCode: virtualKeyCode,
                    transition: .up,
                    modifiers: releaseModifiers
                ))
            }
        }
        for button in pressedButtons.sorted(by: { $0.rawValue < $1.rawValue }) {
            result.append(.button(button: button, transition: .up))
        }
        pressedHIDUsages.removeAll(keepingCapacity: true)
        pressedButtons.removeAll(keepingCapacity: true)
        modifiers = []
        return result
    }

    private mutating func synchronizeModifiers(
        to target: InteractiveModifierMask,
        excludingUsage: UInt16? = nil
    ) -> [MacInteractiveInputEventV0] {
        var result: [MacInteractiveInputEventV0] = []
        var working = modifiers
        for (usage, modifier) in Self.modifierMappings {
            guard usage != excludingUsage,
                  working.contains(modifier),
                  !target.contains(modifier) else { continue }
            working.remove(modifier)
            pressedHIDUsages.remove(usage)
            result.append(.key(
                virtualKeyCode: Self.modifierVirtualKeyCode(for: usage),
                transition: .up,
                modifiers: working
            ))
        }
        for (usage, modifier) in Self.modifierMappings {
            guard usage != excludingUsage,
                  !working.contains(modifier),
                  target.contains(modifier) else { continue }
            working.insert(modifier)
            pressedHIDUsages.insert(usage)
            result.append(.key(
                virtualKeyCode: Self.modifierVirtualKeyCode(for: usage),
                transition: .down,
                modifiers: working
            ))
        }
        modifiers = target
        return result
    }

    private static let modifierMappings: [
        (usage: UInt16, modifier: InteractiveModifierMask)
    ] = [
        (0xe0, .leftControl), (0xe1, .leftShift),
        (0xe2, .leftOption), (0xe3, .leftCommand),
        (0xe4, .rightControl), (0xe5, .rightShift),
        (0xe6, .rightOption), (0xe7, .rightCommand),
    ]

    private static func modifier(
        for usage: UInt16
    ) -> InteractiveModifierMask? {
        modifierMappings.first(where: { $0.usage == usage })?.modifier
    }

    private static func modifierVirtualKeyCode(for usage: UInt16) -> UInt16 {
        switch usage {
        case 0xe0: 59
        case 0xe1: 56
        case 0xe2: 58
        case 0xe3: 55
        case 0xe4: 62
        case 0xe5: 60
        case 0xe6: 61
        case 0xe7: 54
        default:
            preconditionFailure("modifier mapping is internally inconsistent")
        }
    }

    /// USB HID Keyboard/Keypad usage to stable macOS virtual key code. The
    /// first profile intentionally rejects consumer, international, and
    /// unsupported function usages rather than treating HID numbers as key
    /// codes.
    public static func virtualKeyCode(for usage: UInt16) throws -> UInt16 {
        if (0x04...0x1d).contains(usage) {
            let letters: [UInt16] = [
                0, 11, 8, 2, 14, 3, 5, 4, 34, 38, 40, 37, 46,
                45, 31, 35, 12, 15, 1, 17, 32, 9, 13, 7, 16, 6,
            ]
            return letters[Int(usage - 0x04)]
        }
        if (0x1e...0x27).contains(usage) {
            let digits: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
            return digits[Int(usage - 0x1e)]
        }
        let explicit: [UInt16: UInt16] = [
            0x28: 36, 0x29: 53, 0x2a: 51, 0x2b: 48, 0x2c: 49,
            0x2d: 27, 0x2e: 24, 0x2f: 33, 0x30: 30, 0x31: 42,
            0x33: 41, 0x34: 39, 0x35: 50, 0x36: 43, 0x37: 47,
            0x38: 44, 0x39: 57,
            0x3a: 122, 0x3b: 120, 0x3c: 99, 0x3d: 118,
            0x3e: 96, 0x3f: 97, 0x40: 98, 0x41: 100,
            0x42: 101, 0x43: 109, 0x44: 103, 0x45: 111,
            0x4a: 115, 0x4b: 116, 0x4c: 117, 0x4d: 119,
            0x4e: 121, 0x4f: 124, 0x50: 123, 0x51: 125, 0x52: 126,
            0x53: 71, 0x54: 75, 0x55: 67, 0x56: 78, 0x57: 69,
            0x58: 76, 0x59: 83, 0x5a: 84, 0x5b: 85, 0x5c: 86,
            0x5d: 87, 0x5e: 88, 0x5f: 89, 0x60: 91, 0x61: 92,
            0x62: 82, 0x63: 65, 0x67: 81,
            0x68: 105, 0x69: 107, 0x6a: 113, 0x6b: 106,
            0x6c: 64, 0x6d: 79, 0x6e: 80, 0x6f: 90,
            0xe0: 59, 0xe1: 56, 0xe2: 58, 0xe3: 55,
            0xe4: 62, 0xe5: 60, 0xe6: 61, 0xe7: 54,
        ]
        guard let value = explicit[usage] else {
            throw MacInteractiveInputPlanErrorV0.unsupportedHIDUsage(usage)
        }
        return value
    }
}
