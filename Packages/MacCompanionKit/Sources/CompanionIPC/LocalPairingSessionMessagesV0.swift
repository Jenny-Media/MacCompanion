import CompanionWire
import Foundation

public enum LocalPairingSessionMessageErrorV0: Error, Equatable, Sendable {
    case invalidVersion
    case invalidTime
    case invalidQRCode
    case bindingMismatch
    case unknownOrMissingField
}

private struct LocalPairingAnyCodingKeyV0: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func requireLocalPairingKeysV0(
    _ decoder: Decoder,
    _ expected: Set<String>
) throws {
    let container = try decoder.container(keyedBy: LocalPairingAnyCodingKeyV0.self)
    guard Set(container.allKeys.map(\.stringValue)) == expected else {
        throw LocalPairingSessionMessageErrorV0.unknownOrMissingField
    }
}

private let localPairingMaximumTimeV0: Int64 = 9_007_199_254_740_991
private let localPairingLifetimeMillisecondsV0: Int64 = 5 * 60 * 1_000

public struct LocalPairingSessionCreateCommandV0:
    Codable, Equatable, Sendable
{
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, commandID
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let commandID: UUID

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        commandID: UUID
    ) throws {
        guard protocolVersion == .init() else {
            throw LocalPairingSessionMessageErrorV0.invalidVersion
        }
        self.protocolVersion = protocolVersion
        self.commandID = commandID
    }

    public init(from decoder: Decoder) throws {
        try requireLocalPairingKeysV0(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            protocolVersion: container.decode(
                LocalIPCProtocolVersion.self,
                forKey: .protocolVersion
            ),
            commandID: container.decode(UUID.self, forKey: .commandID)
        )
    }
}

public struct LocalPairingSessionCreatedReceiptV0:
    Codable, Equatable, Sendable
{
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, correlationID, pairingID, encodedQRCode
        case createdAtUnixMilliseconds, expiresAtUnixMilliseconds
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let correlationID: UUID
    public let pairingID: UUID
    public let encodedQRCode: String
    public let createdAtUnixMilliseconds: Int64
    public let expiresAtUnixMilliseconds: Int64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        correlationID: UUID,
        pairingID: UUID,
        encodedQRCode: String,
        createdAtUnixMilliseconds: Int64,
        expiresAtUnixMilliseconds: Int64
    ) throws {
        guard protocolVersion == .init() else {
            throw LocalPairingSessionMessageErrorV0.invalidVersion
        }
        guard createdAtUnixMilliseconds >= 0,
              createdAtUnixMilliseconds <= localPairingMaximumTimeV0,
              expiresAtUnixMilliseconds >= 0,
              expiresAtUnixMilliseconds <= localPairingMaximumTimeV0,
              createdAtUnixMilliseconds <= Int64.max
                - localPairingLifetimeMillisecondsV0,
              expiresAtUnixMilliseconds
                == createdAtUnixMilliseconds
                    + localPairingLifetimeMillisecondsV0 else {
            throw LocalPairingSessionMessageErrorV0.invalidTime
        }
        let payload: PairingQRCodePayload
        do {
            payload = try PairingQRCodeCodec.decode(
                encodedQRCode,
                nowUnixMilliseconds: createdAtUnixMilliseconds
            )
        } catch {
            throw LocalPairingSessionMessageErrorV0.invalidQRCode
        }
        guard payload.pairingID.rawValue == pairingID,
              payload.expiresAtUnixMilliseconds
                == expiresAtUnixMilliseconds else {
            throw LocalPairingSessionMessageErrorV0.bindingMismatch
        }
        self.protocolVersion = protocolVersion
        self.correlationID = correlationID
        self.pairingID = pairingID
        self.encodedQRCode = encodedQRCode
        self.createdAtUnixMilliseconds = createdAtUnixMilliseconds
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        try requireLocalPairingKeysV0(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            protocolVersion: container.decode(
                LocalIPCProtocolVersion.self,
                forKey: .protocolVersion
            ),
            correlationID: container.decode(UUID.self, forKey: .correlationID),
            pairingID: container.decode(UUID.self, forKey: .pairingID),
            encodedQRCode: container.decode(String.self, forKey: .encodedQRCode),
            createdAtUnixMilliseconds: container.decode(
                Int64.self,
                forKey: .createdAtUnixMilliseconds
            ),
            expiresAtUnixMilliseconds: container.decode(
                Int64.self,
                forKey: .expiresAtUnixMilliseconds
            )
        )
    }
}

public struct LocalPairingSessionDismissCommandV0:
    Codable, Equatable, Sendable
{
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, commandID, pairingID
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let commandID: UUID
    public let pairingID: UUID

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        commandID: UUID,
        pairingID: UUID
    ) throws {
        guard protocolVersion == .init() else {
            throw LocalPairingSessionMessageErrorV0.invalidVersion
        }
        self.protocolVersion = protocolVersion
        self.commandID = commandID
        self.pairingID = pairingID
    }

    public init(from decoder: Decoder) throws {
        try requireLocalPairingKeysV0(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            protocolVersion: container.decode(
                LocalIPCProtocolVersion.self,
                forKey: .protocolVersion
            ),
            commandID: container.decode(UUID.self, forKey: .commandID),
            pairingID: container.decode(UUID.self, forKey: .pairingID)
        )
    }
}

public struct LocalPairingSessionDismissedReceiptV0:
    Codable, Equatable, Sendable
{
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, correlationID, pairingID
        case completedAtUnixMilliseconds
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let correlationID: UUID
    public let pairingID: UUID
    public let completedAtUnixMilliseconds: Int64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        correlationID: UUID,
        pairingID: UUID,
        completedAtUnixMilliseconds: Int64
    ) throws {
        guard protocolVersion == .init() else {
            throw LocalPairingSessionMessageErrorV0.invalidVersion
        }
        guard completedAtUnixMilliseconds >= 0,
              completedAtUnixMilliseconds <= localPairingMaximumTimeV0 else {
            throw LocalPairingSessionMessageErrorV0.invalidTime
        }
        self.protocolVersion = protocolVersion
        self.correlationID = correlationID
        self.pairingID = pairingID
        self.completedAtUnixMilliseconds = completedAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        try requireLocalPairingKeysV0(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            protocolVersion: container.decode(
                LocalIPCProtocolVersion.self,
                forKey: .protocolVersion
            ),
            correlationID: container.decode(UUID.self, forKey: .correlationID),
            pairingID: container.decode(UUID.self, forKey: .pairingID),
            completedAtUnixMilliseconds: container.decode(
                Int64.self,
                forKey: .completedAtUnixMilliseconds
            )
        )
    }
}
