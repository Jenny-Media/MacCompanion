import Foundation

public enum LocalInteractiveAdmissionMessageErrorV1:
    Error,
    Equatable,
    Sendable
{
    case invalidVersion
    case invalidRevision
    case unknownOrMissingField
    case bindingMismatch
}

private struct LocalInteractiveAdmissionAnyCodingKeyV1: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func requireLocalInteractiveAdmissionKeysV1(
    _ decoder: Decoder,
    _ expected: Set<String>
) throws {
    let container = try decoder.container(
        keyedBy: LocalInteractiveAdmissionAnyCodingKeyV1.self
    )
    guard Set(container.allKeys.map(\.stringValue)) == expected else {
        throw LocalInteractiveAdmissionMessageErrorV1
            .unknownOrMissingField
    }
}

public struct LocalInteractiveAdmissionPublicationV1:
    Codable,
    Equatable,
    Sendable
{
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, commandID, menuAppGeneration, revision
        case selectedDisplayID
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let commandID: UUID
    public let menuAppGeneration: UUID
    public let revision: UInt64
    public let selectedDisplayID: UUID?

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        commandID: UUID,
        menuAppGeneration: UUID,
        revision: UInt64,
        selectedDisplayID: UUID?
    ) throws {
        guard protocolVersion == .init() else {
            throw LocalInteractiveAdmissionMessageErrorV1.invalidVersion
        }
        guard revision > 0,
              revision <= 9_007_199_254_740_991 else {
            throw LocalInteractiveAdmissionMessageErrorV1.invalidRevision
        }
        self.protocolVersion = protocolVersion
        self.commandID = commandID
        self.menuAppGeneration = menuAppGeneration
        self.revision = revision
        self.selectedDisplayID = selectedDisplayID
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encode(commandID, forKey: .commandID)
        try container.encode(menuAppGeneration, forKey: .menuAppGeneration)
        try container.encode(revision, forKey: .revision)
        // The closed wire shape requires this key even when Control has no
        // selected display. Synthesized Optional encoding omits nil keys.
        try container.encode(selectedDisplayID, forKey: .selectedDisplayID)
    }

    public init(from decoder: Decoder) throws {
        try requireLocalInteractiveAdmissionKeysV1(
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
            menuAppGeneration: container.decode(
                UUID.self,
                forKey: .menuAppGeneration
            ),
            revision: container.decode(UInt64.self, forKey: .revision),
            selectedDisplayID: container.decodeIfPresent(
                UUID.self,
                forKey: .selectedDisplayID
            )
        )
    }
}

public struct LocalInteractiveAdmissionPublishedReceiptV1:
    Codable,
    Equatable,
    Sendable
{
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, correlationID, menuAppGeneration, revision
        case selectedDisplayID
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let correlationID: UUID
    public let menuAppGeneration: UUID
    public let revision: UInt64
    public let selectedDisplayID: UUID?

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        correlationID: UUID,
        menuAppGeneration: UUID,
        revision: UInt64,
        selectedDisplayID: UUID?
    ) throws {
        guard protocolVersion == .init() else {
            throw LocalInteractiveAdmissionMessageErrorV1.invalidVersion
        }
        guard revision > 0,
              revision <= 9_007_199_254_740_991 else {
            throw LocalInteractiveAdmissionMessageErrorV1.invalidRevision
        }
        self.protocolVersion = protocolVersion
        self.correlationID = correlationID
        self.menuAppGeneration = menuAppGeneration
        self.revision = revision
        self.selectedDisplayID = selectedDisplayID
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encode(correlationID, forKey: .correlationID)
        try container.encode(menuAppGeneration, forKey: .menuAppGeneration)
        try container.encode(revision, forKey: .revision)
        try container.encode(selectedDisplayID, forKey: .selectedDisplayID)
    }

    public init(from decoder: Decoder) throws {
        try requireLocalInteractiveAdmissionKeysV1(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            protocolVersion: container.decode(
                LocalIPCProtocolVersion.self,
                forKey: .protocolVersion
            ),
            correlationID: container.decode(
                UUID.self,
                forKey: .correlationID
            ),
            menuAppGeneration: container.decode(
                UUID.self,
                forKey: .menuAppGeneration
            ),
            revision: container.decode(UInt64.self, forKey: .revision),
            selectedDisplayID: container.decodeIfPresent(
                UUID.self,
                forKey: .selectedDisplayID
            )
        )
    }

    public func validate(
        against command: LocalInteractiveAdmissionPublicationV1
    ) throws {
        guard correlationID == command.commandID,
              menuAppGeneration == command.menuAppGeneration,
              revision == command.revision,
              selectedDisplayID == command.selectedDisplayID else {
            throw LocalInteractiveAdmissionMessageErrorV1.bindingMismatch
        }
    }
}
