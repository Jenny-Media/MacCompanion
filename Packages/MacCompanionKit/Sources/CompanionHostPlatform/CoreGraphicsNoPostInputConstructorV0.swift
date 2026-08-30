import CompanionIPC
import CompanionInteractiveShared
import CompanionInteractiveWire
import CoreGraphics
import Foundation

public enum CoreGraphicsInputConstructionErrorV0: Error, Equatable, Sendable {
    case invalidDisplayBounds
    case invalidCursorPosition
    case cursorOutsideSelectedDisplay
    case geometryFenceMismatch
    case eventCreationFailed
}

public struct MacDisplayGeometrySnapshotV0: Equatable, Sendable {
    public let selectedDisplayID: UUID
    public let coordinateRevision: CoordinateRevision
    public let logicalBounds: CGRect
    public let backingScaleFactor: CGFloat
    public let rotation: SurfaceRotation

    public init(
        selectedDisplayID: UUID,
        coordinateRevision: CoordinateRevision,
        logicalBounds: CGRect,
        backingScaleFactor: CGFloat,
        rotation: SurfaceRotation
    ) throws {
        guard coordinateRevision.rawValue > 0,
              coordinateRevision.rawValue
                <= CoordinateRevision.maximumWireValue,
              logicalBounds.origin.x.isFinite,
              logicalBounds.origin.y.isFinite,
              abs(logicalBounds.origin.x) <= 131_072,
              abs(logicalBounds.origin.y) <= 131_072,
              logicalBounds.width.isFinite,
              logicalBounds.height.isFinite,
              logicalBounds.width > 0,
              logicalBounds.height > 0,
              logicalBounds.width <= 32_768,
              logicalBounds.height <= 32_768,
              backingScaleFactor.isFinite,
              (1...8).contains(backingScaleFactor) else {
            throw CoreGraphicsInputConstructionErrorV0.invalidDisplayBounds
        }
        self.selectedDisplayID = selectedDisplayID
        self.coordinateRevision = coordinateRevision
        self.logicalBounds = logicalBounds
        self.backingScaleFactor = backingScaleFactor
        self.rotation = rotation
    }
}

/// This sink is construction-only. Implementations may inspect, transform, or
/// test events but must never call `CGEventPost`; real posting is a separate
/// signed-target adapter and evidence gate.
public protocol CoreGraphicsConstructedEventSinkV0: AnyObject {
    func receiveConstructedEvent(_ event: CGEvent) throws
}

public struct CoreGraphicsNoPostInputConstructorV0 {
    public init() {}

    @discardableResult
    public func construct(
        _ descriptions: [MacInteractiveInputEventV0],
        fence: InteractiveCommandFence,
        geometry: MacDisplayGeometrySnapshotV0,
        currentCursorPosition: CGPoint,
        buttonClickState: UInt8? = nil,
        sink: any CoreGraphicsConstructedEventSinkV0
    ) throws -> Int {
        guard fence.selectedDisplayID == geometry.selectedDisplayID,
              fence.coordinateRevision == geometry.coordinateRevision else {
            throw CoreGraphicsInputConstructionErrorV0.geometryFenceMismatch
        }
        try Self.validateCursor(currentCursorPosition)
        var constructed: [CGEvent] = []
        var plannedCursor = currentCursorPosition
        for description in descriptions {
            let result = try Self.events(
                for: description,
                selectedDisplayBounds: geometry.logicalBounds,
                currentCursorPosition: plannedCursor,
                buttonClickState: buttonClickState
            )
            constructed += result.events
            plannedCursor = result.cursorPosition
        }
        for event in constructed {
            try sink.receiveConstructedEvent(event)
        }
        return constructed.count
    }

    public static func normalizedPoint(
        x: UInt16,
        y: UInt16,
        in bounds: CGRect
    ) throws -> CGPoint {
        guard bounds.origin.x.isFinite, bounds.origin.y.isFinite,
              bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0 else {
            throw CoreGraphicsInputConstructionErrorV0.invalidDisplayBounds
        }
        let xFraction = CGFloat(x) / CGFloat(UInt16.max)
        let yFraction = CGFloat(y) / CGFloat(UInt16.max)
        return CGPoint(
            x: min(bounds.maxX.nextDown, bounds.minX + bounds.width * xFraction),
            y: min(bounds.maxY.nextDown, bounds.minY + bounds.height * yFraction)
        )
    }

    public static func eventFlags(
        for modifiers: InteractiveModifierMask
    ) -> CGEventFlags {
        var result: CGEventFlags = []
        if !modifiers.intersection([.leftControl, .rightControl]).isEmpty {
            result.insert(.maskControl)
        }
        if !modifiers.intersection([.leftShift, .rightShift]).isEmpty {
            result.insert(.maskShift)
        }
        if !modifiers.intersection([.leftOption, .rightOption]).isEmpty {
            result.insert(.maskAlternate)
        }
        if !modifiers.intersection([.leftCommand, .rightCommand]).isEmpty {
            result.insert(.maskCommand)
        }
        return result
    }

    private static func events(
        for description: MacInteractiveInputEventV0,
        selectedDisplayBounds: CGRect,
        currentCursorPosition: CGPoint,
        buttonClickState: UInt8?
    ) throws -> (events: [CGEvent], cursorPosition: CGPoint) {
        switch description {
        case let .pointerMove(x, y):
            let position = try normalizedPoint(
                x: x,
                y: y,
                in: selectedDisplayBounds
            )
            guard let event = CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: position,
                mouseButton: .left
            ) else { throw CoreGraphicsInputConstructionErrorV0.eventCreationFailed }
            return ([event], position)
        case let .button(button, transition):
            guard selectedDisplayBounds.contains(currentCursorPosition) else {
                throw CoreGraphicsInputConstructionErrorV0
                    .cursorOutsideSelectedDisplay
            }
            let type: CGEventType
            let cgButton: CGMouseButton
            switch (button, transition) {
            case (.primary, .down):
                type = .leftMouseDown
                cgButton = .left
            case (.primary, .up):
                type = .leftMouseUp
                cgButton = .left
            case (.secondary, .down):
                type = .rightMouseDown
                cgButton = .right
            case (.secondary, .up):
                type = .rightMouseUp
                cgButton = .right
            }
            guard let event = CGEvent(
                mouseEventSource: nil,
                mouseType: type,
                mouseCursorPosition: currentCursorPosition,
                mouseButton: cgButton
            ) else { throw CoreGraphicsInputConstructionErrorV0.eventCreationFailed }
            if let buttonClickState {
                event.setIntegerValueField(
                    .mouseEventClickState,
                    value: Int64(buttonClickState)
                )
            }
            return ([event], currentCursorPosition)
        case let .scroll(unit, deltaX, deltaY):
            let cgUnit: CGScrollEventUnit = unit == .pixel ? .pixel : .line
            guard let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: cgUnit,
                wheelCount: 2,
                wheel1: deltaY,
                wheel2: deltaX,
                wheel3: 0
            ) else { throw CoreGraphicsInputConstructionErrorV0.eventCreationFailed }
            return ([event], currentCursorPosition)
        case let .key(virtualKeyCode, transition, modifiers):
            guard let event = CGEvent(
                keyboardEventSource: nil,
                virtualKey: CGKeyCode(virtualKeyCode),
                keyDown: transition == .down
            ) else { throw CoreGraphicsInputConstructionErrorV0.eventCreationFailed }
            event.flags = eventFlags(for: modifiers)
            if modifierVirtualKeyCodes.contains(virtualKeyCode) {
                event.type = .flagsChanged
            }
            return ([event], currentCursorPosition)
        case let .unicodeText(value):
            let units = Array(value.utf16)
            guard let down = CGEvent(
                keyboardEventSource: nil,
                virtualKey: 0,
                keyDown: true
            ), let up = CGEvent(
                keyboardEventSource: nil,
                virtualKey: 0,
                keyDown: false
            ) else { throw CoreGraphicsInputConstructionErrorV0.eventCreationFailed }
            units.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                down.keyboardSetUnicodeString(
                    stringLength: buffer.count,
                    unicodeString: baseAddress
                )
                up.keyboardSetUnicodeString(
                    stringLength: buffer.count,
                    unicodeString: baseAddress
                )
            }
            return ([down, up], currentCursorPosition)
        }
    }

    private static func validateCursor(_ currentCursorPosition: CGPoint) throws {
        guard currentCursorPosition.x.isFinite,
              currentCursorPosition.y.isFinite else {
            throw CoreGraphicsInputConstructionErrorV0.invalidCursorPosition
        }
    }

    private static let modifierVirtualKeyCodes: Set<UInt16> = [
        54, 55, 56, 58, 59, 60, 61, 62,
    ]
}
