import CompanionDomain
import CompanionInteractiveShared
import CompanionWire
import Foundation

public enum InteractiveInputKind: String, Codable, CaseIterable, Sendable {
    case pointerMove
    case button
    case scroll
    case physicalKey
    case modifiers
    case text
    case reset
}

public enum InteractivePointerButton: String, Codable, CaseIterable, Sendable {
    case primary
    case secondary
}

public enum InteractiveInputTransition: String, Codable, CaseIterable, Sendable {
    case down
    case up
}

public enum InteractiveScrollUnit: String, Codable, CaseIterable, Sendable {
    case pixel
    case line
}

public struct InteractiveModifierMask: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let leftControl = Self(rawValue: 1 << 0)
    public static let leftShift = Self(rawValue: 1 << 1)
    public static let leftOption = Self(rawValue: 1 << 2)
    public static let leftCommand = Self(rawValue: 1 << 3)
    public static let rightControl = Self(rawValue: 1 << 4)
    public static let rightShift = Self(rawValue: 1 << 5)
    public static let rightOption = Self(rawValue: 1 << 6)
    public static let rightCommand = Self(rawValue: 1 << 7)
}

extension InteractiveModifierMask: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(UInt8.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum InteractiveInputPayload: Equatable, Sendable {
    case pointerMove(x: UInt16, y: UInt16)
    case button(button: InteractivePointerButton, transition: InteractiveInputTransition)
    case scroll(unit: InteractiveScrollUnit, deltaX: Int32, deltaY: Int32)
    case physicalKey(usage: UInt16, transition: InteractiveInputTransition, modifiers: InteractiveModifierMask)
    case modifiers(InteractiveModifierMask)
    case text(String)
    case reset

    public var kind: InteractiveInputKind {
        switch self {
        case .pointerMove: .pointerMove
        case .button: .button
        case .scroll: .scroll
        case .physicalKey: .physicalKey
        case .modifiers: .modifiers
        case .text: .text
        case .reset: .reset
        }
    }

    public func validate() throws {
        switch self {
        case .pointerMove, .button, .modifiers, .reset:
            break
        case let .scroll(_, deltaX, deltaY):
            guard deltaX != 0 || deltaY != 0,
                  (-4_096...4_096).contains(deltaX),
                  (-4_096...4_096).contains(deltaY) else {
                throw WireError.boundsExceeded(field: "scrollDelta", limit: 4_096)
            }
        case let .physicalKey(usage, _, _):
            guard (0x04...0xe7).contains(usage) else {
                throw WireError.invalidFrame(reason: "unsupported USB HID keyboard usage")
            }
        case let .text(value):
            guard !value.isEmpty, value.utf8.count <= 4_096,
                  !value.unicodeScalars.contains(where: { $0.value == 0 }) else {
                throw WireError.boundsExceeded(field: "textUTF8Bytes", limit: 4_096)
            }
        }
    }
}

extension InteractiveInputPayload: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, x, y, button, transition, unit, deltaX, deltaY, usage, modifierMask, text
    }

    public init(from decoder: Decoder) throws {
        let probe = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try probe.decode(InteractiveInputKind.self, forKey: .kind)
        switch kind {
        case .pointerMove:
            try requireExactKeys(decoder, ["kind", "x", "y"])
            self = .pointerMove(
                x: try probe.decode(UInt16.self, forKey: .x),
                y: try probe.decode(UInt16.self, forKey: .y)
            )
        case .button:
            try requireExactKeys(decoder, ["kind", "button", "transition"])
            self = .button(
                button: try probe.decode(InteractivePointerButton.self, forKey: .button),
                transition: try probe.decode(InteractiveInputTransition.self, forKey: .transition)
            )
        case .scroll:
            try requireExactKeys(decoder, ["kind", "unit", "deltaX", "deltaY"])
            self = .scroll(
                unit: try probe.decode(InteractiveScrollUnit.self, forKey: .unit),
                deltaX: try probe.decode(Int32.self, forKey: .deltaX),
                deltaY: try probe.decode(Int32.self, forKey: .deltaY)
            )
        case .physicalKey:
            try requireExactKeys(decoder, ["kind", "usage", "transition", "modifierMask"])
            self = .physicalKey(
                usage: try probe.decode(UInt16.self, forKey: .usage),
                transition: try probe.decode(InteractiveInputTransition.self, forKey: .transition),
                modifiers: try probe.decode(InteractiveModifierMask.self, forKey: .modifierMask)
            )
        case .modifiers:
            try requireExactKeys(decoder, ["kind", "modifierMask"])
            self = .modifiers(try probe.decode(InteractiveModifierMask.self, forKey: .modifierMask))
        case .text:
            try requireExactKeys(decoder, ["kind", "text"])
            self = .text(try probe.decode(String.self, forKey: .text))
        case .reset:
            try requireExactKeys(decoder, ["kind"])
            self = .reset
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case let .pointerMove(x, y):
            try container.encode(x, forKey: .x)
            try container.encode(y, forKey: .y)
        case let .button(button, transition):
            try container.encode(button, forKey: .button)
            try container.encode(transition, forKey: .transition)
        case let .scroll(unit, deltaX, deltaY):
            try container.encode(unit, forKey: .unit)
            try container.encode(deltaX, forKey: .deltaX)
            try container.encode(deltaY, forKey: .deltaY)
        case let .physicalKey(usage, transition, modifiers):
            try container.encode(usage, forKey: .usage)
            try container.encode(transition, forKey: .transition)
            try container.encode(modifiers, forKey: .modifierMask)
        case let .modifiers(modifiers):
            try container.encode(modifiers, forKey: .modifierMask)
        case let .text(text):
            try container.encode(text, forKey: .text)
        case .reset:
            break
        }
    }
}

public struct InteractiveInputEnvelope: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case version, messageID, interactiveSessionID, authorizationEpoch
        case sequence, clientMonotonicMilliseconds
        case surfaceID, surfaceRevision, coordinateSpaceRevision
        case focusToken, focusRevision, input
    }

    public let version: WireVersion
    public let messageID: WireUUID
    public let interactiveSessionID: WireUUID
    public let authorizationEpoch: AuthorizationEpoch
    public let sequence: UInt64
    public let clientMonotonicMilliseconds: UInt64
    public let surfaceID: WireUUID
    public let surfaceRevision: SurfaceRevision
    public let coordinateSpaceRevision: CoordinateSpaceRevision
    public let focusToken: WireUUID?
    public let focusRevision: FocusRevision?
    public let input: InteractiveInputPayload

    public init(
        version: WireVersion = .init(),
        messageID: WireUUID,
        interactiveSessionID: WireUUID,
        authorizationEpoch: AuthorizationEpoch,
        sequence: UInt64,
        clientMonotonicMilliseconds: UInt64,
        surfaceID: WireUUID,
        surfaceRevision: SurfaceRevision,
        coordinateSpaceRevision: CoordinateSpaceRevision,
        focusToken: WireUUID? = nil,
        focusRevision: FocusRevision? = nil,
        input: InteractiveInputPayload
    ) throws {
        self.version = version
        self.messageID = messageID
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.sequence = sequence
        self.clientMonotonicMilliseconds = clientMonotonicMilliseconds
        self.surfaceID = surfaceID
        self.surfaceRevision = surfaceRevision
        self.coordinateSpaceRevision = coordinateSpaceRevision
        self.focusToken = focusToken
        self.focusRevision = focusRevision
        self.input = input
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, [
            "version", "messageID", "interactiveSessionID", "authorizationEpoch",
            "sequence", "clientMonotonicMilliseconds", "surfaceID", "surfaceRevision",
            "coordinateSpaceRevision", "focusToken", "focusRevision", "input",
        ])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(WireVersion.self, forKey: .version)
        messageID = try container.decode(WireUUID.self, forKey: .messageID)
        interactiveSessionID = try container.decode(WireUUID.self, forKey: .interactiveSessionID)
        authorizationEpoch = try container.decode(AuthorizationEpoch.self, forKey: .authorizationEpoch)
        sequence = try container.decode(UInt64.self, forKey: .sequence)
        clientMonotonicMilliseconds = try container.decode(UInt64.self, forKey: .clientMonotonicMilliseconds)
        surfaceID = try container.decode(WireUUID.self, forKey: .surfaceID)
        surfaceRevision = try container.decode(SurfaceRevision.self, forKey: .surfaceRevision)
        coordinateSpaceRevision = try container.decode(CoordinateSpaceRevision.self, forKey: .coordinateSpaceRevision)
        focusToken = try container.decodeIfPresent(WireUUID.self, forKey: .focusToken)
        focusRevision = try container.decodeIfPresent(FocusRevision.self, forKey: .focusRevision)
        input = try container.decode(InteractiveInputPayload.self, forKey: .input)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(messageID, forKey: .messageID)
        try container.encode(interactiveSessionID, forKey: .interactiveSessionID)
        try container.encode(authorizationEpoch, forKey: .authorizationEpoch)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(clientMonotonicMilliseconds, forKey: .clientMonotonicMilliseconds)
        try container.encode(surfaceID, forKey: .surfaceID)
        try container.encode(surfaceRevision, forKey: .surfaceRevision)
        try container.encode(coordinateSpaceRevision, forKey: .coordinateSpaceRevision)
        try container.encode(focusToken, forKey: .focusToken)
        try container.encode(focusRevision, forKey: .focusRevision)
        try container.encode(input, forKey: .input)
    }

    public func validate() throws {
        guard version == .init() else { throw WireError.unsupportedVersion(major: version.major, minor: version.minor) }
        guard authorizationEpoch.rawValue >= 1,
              surfaceRevision.rawValue >= 1,
              coordinateSpaceRevision.rawValue >= 1,
              sequence >= 1, sequence <= UInt64(WireLimits.maximumSafeInteger),
              clientMonotonicMilliseconds <= UInt64(WireLimits.maximumSafeInteger) else {
            throw WireError.boundsExceeded(field: "interactiveInputFence", limit: Int(WireLimits.maximumSafeInteger))
        }
        guard (focusToken == nil) == (focusRevision == nil),
              focusRevision.map({ $0.rawValue >= 1 }) ?? true else {
            throw WireError.invalidFrame(reason: "partial or zero focus fence")
        }
        if input.kind == .text, focusToken == nil {
            throw WireError.invalidFrame(reason: "text input requires exact focus fence")
        }
        try input.validate()
    }
}

public enum InteractiveInputCodec {
    public static func decode(_ data: Data) throws -> InteractiveInputEnvelope {
        try StrictJSON.validate(data)
        return try JSONDecoder().decode(InteractiveInputEnvelope.self, from: data)
    }

    public static func encode(_ envelope: InteractiveInputEnvelope) throws -> Data {
        try envelope.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(envelope)
    }
}
