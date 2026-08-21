import CompanionInteractiveWire
import Foundation

public enum ClientInputInteractionModeV0: String, Equatable, Sendable {
    case trackpad
    case directTouch
}

public enum ClientViewportInputMapperErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidGeometry
    case invalidSensitivity
    case nonFiniteInput
    case modeMismatch
    case pointOutsideContent
    case dragAlreadyActive
    case dragNotActive
    case zeroScroll
}

public struct ClientInputPointV0: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) throws {
        guard x.isFinite, y.isFinite else {
            throw ClientViewportInputMapperErrorV0.nonFiniteInput
        }
        self.x = x
        self.y = y
    }
}

public struct ClientInputRectV0: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) throws {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite,
              width > 0, height > 0,
              x <= Double.greatestFiniteMagnitude - width,
              y <= Double.greatestFiniteMagnitude - height else {
            throw ClientViewportInputMapperErrorV0.invalidGeometry
        }
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public func contains(_ point: ClientInputPointV0) -> Bool {
        point.x >= x && point.y >= y
            && point.x < x + width && point.y < y + height
    }
}

public enum ClientKeyboardActionV0: Equatable, Sendable {
    case text(String)
    case deleteBackward
    case returnKey
    case tab
    case escape
    case arrowRight
    case arrowLeft
    case arrowDown
    case arrowUp
    case modifiers(InteractiveModifierMask)

    public func payloads(
        modifiers: InteractiveModifierMask = []
    ) throws -> [InteractiveInputPayload] {
        switch self {
        case let .text(value):
            let payload = InteractiveInputPayload.text(value)
            try payload.validate()
            return [payload]
        case let .modifiers(mask):
            return [.modifiers(mask)]
        case .deleteBackward:
            return Self.stroke(usage: 0x2a, modifiers: modifiers)
        case .returnKey:
            return Self.stroke(usage: 0x28, modifiers: modifiers)
        case .tab:
            return Self.stroke(usage: 0x2b, modifiers: modifiers)
        case .escape:
            return Self.stroke(usage: 0x29, modifiers: modifiers)
        case .arrowRight:
            return Self.stroke(usage: 0x4f, modifiers: modifiers)
        case .arrowLeft:
            return Self.stroke(usage: 0x50, modifiers: modifiers)
        case .arrowDown:
            return Self.stroke(usage: 0x51, modifiers: modifiers)
        case .arrowUp:
            return Self.stroke(usage: 0x52, modifiers: modifiers)
        }
    }

    private static func stroke(
        usage: UInt16,
        modifiers: InteractiveModifierMask
    ) -> [InteractiveInputPayload] {
        [
            .physicalKey(
                usage: usage,
                transition: .down,
                modifiers: modifiers
            ),
            .physicalKey(
                usage: usage,
                transition: .up,
                modifiers: modifiers
            ),
        ]
    }
}

/// Pure pre-sequence mapper. The caller must pass every returned payload in
/// order to `ClientInputProducerV0`; it may not drop a button/key transition.
public struct ClientViewportInputMapperV0: Sendable {
    public let viewport: ClientInputRectV0
    public let content: ClientInputRectV0
    public let trackpadSensitivity: Double
    public private(set) var mode: ClientInputInteractionModeV0
    public private(set) var normalizedPointerX: UInt16 = 32_768
    public private(set) var normalizedPointerY: UInt16 = 32_768
    public private(set) var heldDragButton: InteractivePointerButton?

    public init(
        viewport: ClientInputRectV0,
        content: ClientInputRectV0,
        mode: ClientInputInteractionModeV0,
        trackpadSensitivity: Double = 1
    ) throws {
        guard content.x >= viewport.x,
              content.y >= viewport.y,
              content.x + content.width <= viewport.x + viewport.width,
              content.y + content.height <= viewport.y + viewport.height else {
            throw ClientViewportInputMapperErrorV0.invalidGeometry
        }
        guard trackpadSensitivity.isFinite,
              (0.25...4).contains(trackpadSensitivity) else {
            throw ClientViewportInputMapperErrorV0.invalidSensitivity
        }
        self.viewport = viewport
        self.content = content
        self.mode = mode
        self.trackpadSensitivity = trackpadSensitivity
    }

    public mutating func setMode(
        _ newMode: ClientInputInteractionModeV0
    ) -> [InteractiveInputPayload] {
        guard newMode != mode else { return [] }
        let requiresReset = heldDragButton != nil
        heldDragButton = nil
        mode = newMode
        return requiresReset ? [.reset] : []
    }

    public mutating func directMove(
        to point: ClientInputPointV0
    ) throws -> InteractiveInputPayload {
        guard mode == .directTouch else {
            throw ClientViewportInputMapperErrorV0.modeMismatch
        }
        let normalized = try normalize(point)
        normalizedPointerX = normalized.x
        normalizedPointerY = normalized.y
        return .pointerMove(x: normalized.x, y: normalized.y)
    }

    public mutating func trackpadMove(
        delta: ClientInputPointV0
    ) throws -> InteractiveInputPayload {
        guard mode == .trackpad else {
            throw ClientViewportInputMapperErrorV0.modeMismatch
        }
        let xDelta = Self.scaledTrackpadDelta(
            delta.x / content.width * 65_535 * trackpadSensitivity
        )
        let yDelta = Self.scaledTrackpadDelta(
            delta.y / content.height * 65_535 * trackpadSensitivity
        )
        normalizedPointerX = Self.saturatingCoordinate(
            Int64(normalizedPointerX) + xDelta
        )
        normalizedPointerY = Self.saturatingCoordinate(
            Int64(normalizedPointerY) + yDelta
        )
        return .pointerMove(
            x: normalizedPointerX,
            y: normalizedPointerY
        )
    }

    public mutating func tap(
        at point: ClientInputPointV0? = nil,
        button: InteractivePointerButton = .primary
    ) throws -> [InteractiveInputPayload] {
        guard heldDragButton == nil else {
            throw ClientViewportInputMapperErrorV0.dragAlreadyActive
        }
        var payloads: [InteractiveInputPayload] = []
        switch mode {
        case .directTouch:
            guard let point else {
                throw ClientViewportInputMapperErrorV0.pointOutsideContent
            }
            payloads.append(try directMove(to: point))
        case .trackpad:
            guard point == nil else {
                throw ClientViewportInputMapperErrorV0.modeMismatch
            }
        }
        payloads.append(.button(button: button, transition: .down))
        payloads.append(.button(button: button, transition: .up))
        return payloads
    }

    public mutating func beginDirectDrag(
        at point: ClientInputPointV0,
        button: InteractivePointerButton = .primary
    ) throws -> [InteractiveInputPayload] {
        guard mode == .directTouch else {
            throw ClientViewportInputMapperErrorV0.modeMismatch
        }
        try beginDrag(button: button)
        do {
            let move = try directMove(to: point)
            return [move, .button(button: button, transition: .down)]
        } catch {
            heldDragButton = nil
            throw error
        }
    }

    public mutating func beginTrackpadDrag(
        button: InteractivePointerButton = .primary
    ) throws -> [InteractiveInputPayload] {
        guard mode == .trackpad else {
            throw ClientViewportInputMapperErrorV0.modeMismatch
        }
        try beginDrag(button: button)
        return [.button(button: button, transition: .down)]
    }

    public mutating func updateDirectDrag(
        to point: ClientInputPointV0
    ) throws -> InteractiveInputPayload {
        guard mode == .directTouch, heldDragButton != nil else {
            throw ClientViewportInputMapperErrorV0.dragNotActive
        }
        return try directMove(to: point)
    }

    public mutating func updateTrackpadDrag(
        delta: ClientInputPointV0
    ) throws -> InteractiveInputPayload {
        guard mode == .trackpad, heldDragButton != nil else {
            throw ClientViewportInputMapperErrorV0.dragNotActive
        }
        return try trackpadMove(delta: delta)
    }

    public mutating func endDrag() throws -> InteractiveInputPayload {
        guard let heldDragButton else {
            throw ClientViewportInputMapperErrorV0.dragNotActive
        }
        self.heldDragButton = nil
        return .button(button: heldDragButton, transition: .up)
    }

    public mutating func reset() -> InteractiveInputPayload {
        heldDragButton = nil
        return .reset
    }

    public func scroll(
        delta: ClientInputPointV0,
        unit: InteractiveScrollUnit = .pixel
    ) throws -> InteractiveInputPayload {
        let x = Self.clampedScroll(delta.x)
        let y = Self.clampedScroll(delta.y)
        guard x != 0 || y != 0 else {
            throw ClientViewportInputMapperErrorV0.zeroScroll
        }
        return .scroll(unit: unit, deltaX: x, deltaY: y)
    }

    private mutating func beginDrag(
        button: InteractivePointerButton
    ) throws {
        guard heldDragButton == nil else {
            throw ClientViewportInputMapperErrorV0.dragAlreadyActive
        }
        heldDragButton = button
    }

    private func normalize(
        _ point: ClientInputPointV0
    ) throws -> (x: UInt16, y: UInt16) {
        guard content.contains(point) else {
            throw ClientViewportInputMapperErrorV0.pointOutsideContent
        }
        let x = ((point.x - content.x) / content.width * 65_535).rounded()
        let y = ((point.y - content.y) / content.height * 65_535).rounded()
        return (
            Self.saturatingCoordinate(Int64(x)),
            Self.saturatingCoordinate(Int64(y))
        )
    }

    private static func saturatingCoordinate(_ value: Int64) -> UInt16 {
        UInt16(clamping: max(0, min(65_535, value)))
    }

    private static func clampedScroll(_ value: Double) -> Int32 {
        let rounded = value.rounded()
        if rounded <= -4_096 { return -4_096 }
        if rounded >= 4_096 { return 4_096 }
        return Int32(rounded)
    }

    private static func scaledTrackpadDelta(_ value: Double) -> Int64 {
        if value <= -65_535 { return -65_535 }
        if value >= 65_535 { return 65_535 }
        return Int64(value.rounded())
    }
}
