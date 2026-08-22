import Foundation

public enum LocalRemoteAccessBootstrapMessageErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidVersion
    case invalidRevision
    case invalidTime
    case invalidConsentProfile
    case bindingMismatch
    case unknownOrMissingField
}

public enum LocalRemoteAccessConsentProfileV0:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    /// Enables the Agent only. Observe, Act, and Control remain separately
    /// granted and this value carries no capability authorization.
    case agentRemoteAccessV1
}

private struct LocalRemoteAccessBootstrapAnyCodingKeyV0: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func requireLocalRemoteAccessBootstrapKeysV0(
    _ decoder: Decoder,
    _ expected: Set<String>
) throws {
    let container = try decoder.container(
        keyedBy: LocalRemoteAccessBootstrapAnyCodingKeyV0.self
    )
    guard Set(container.allKeys.map(\.stringValue)) == expected else {
        throw LocalRemoteAccessBootstrapMessageErrorV0
            .unknownOrMissingField
    }
}

private let localRemoteAccessBootstrapMaximumSafeIntegerV0: Int64 =
    9_007_199_254_740_991
private let localRemoteAccessBootstrapOfferLifetimeMillisecondsV0: Int64 =
    5 * 60 * 1_000

/// Agent-issued, content-free proof that the authentication-only service read
/// one canonical disabled durable-intent revision. Revision zero means the
/// record is absent; stored revisions are positive.
public struct LocalRemoteAccessBootstrapOfferV0:
    Codable,
    Equatable,
    Sendable
{
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, offerID, expectedIntentRevision
        case createdAtUnixMilliseconds, expiresAtUnixMilliseconds
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let offerID: UUID
    public let expectedIntentRevision: Int64
    public let createdAtUnixMilliseconds: Int64
    public let expiresAtUnixMilliseconds: Int64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        offerID: UUID,
        expectedIntentRevision: Int64,
        createdAtUnixMilliseconds: Int64,
        expiresAtUnixMilliseconds: Int64
    ) throws {
        guard protocolVersion == .init() else {
            throw LocalRemoteAccessBootstrapMessageErrorV0.invalidVersion
        }
        guard expectedIntentRevision >= 0,
              expectedIntentRevision <
                localRemoteAccessBootstrapMaximumSafeIntegerV0 else {
            throw LocalRemoteAccessBootstrapMessageErrorV0.invalidRevision
        }
        guard createdAtUnixMilliseconds >= 0,
              createdAtUnixMilliseconds <=
                localRemoteAccessBootstrapMaximumSafeIntegerV0,
              createdAtUnixMilliseconds <= Int64.max
                - localRemoteAccessBootstrapOfferLifetimeMillisecondsV0,
              expiresAtUnixMilliseconds == createdAtUnixMilliseconds
                + localRemoteAccessBootstrapOfferLifetimeMillisecondsV0,
              expiresAtUnixMilliseconds <=
                localRemoteAccessBootstrapMaximumSafeIntegerV0 else {
            throw LocalRemoteAccessBootstrapMessageErrorV0.invalidTime
        }
        self.protocolVersion = protocolVersion
        self.offerID = offerID
        self.expectedIntentRevision = expectedIntentRevision
        self.createdAtUnixMilliseconds = createdAtUnixMilliseconds
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        try requireLocalRemoteAccessBootstrapKeysV0(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            protocolVersion: container.decode(
                LocalIPCProtocolVersion.self,
                forKey: .protocolVersion
            ),
            offerID: container.decode(UUID.self, forKey: .offerID),
            expectedIntentRevision: container.decode(
                Int64.self,
                forKey: .expectedIntentRevision
            ),
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

/// Exact explicit-local-consent command. The complete Agent offer is embedded
/// so a stale, substituted, recovery-mode, or concurrent durable revision
/// cannot be repaired by the receiving transport.
public struct LocalRemoteAccessEnableCommandV0:
    Codable,
    Equatable,
    Sendable
{
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, commandID, offer, consentProfile
        case confirmedAtUnixMilliseconds
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let commandID: UUID
    public let offer: LocalRemoteAccessBootstrapOfferV0
    public let consentProfile: LocalRemoteAccessConsentProfileV0
    public let confirmedAtUnixMilliseconds: Int64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        commandID: UUID,
        offer: LocalRemoteAccessBootstrapOfferV0,
        consentProfile: LocalRemoteAccessConsentProfileV0 =
            .agentRemoteAccessV1,
        confirmedAtUnixMilliseconds: Int64
    ) throws {
        guard protocolVersion == .init(),
              offer.protocolVersion == protocolVersion else {
            throw LocalRemoteAccessBootstrapMessageErrorV0.invalidVersion
        }
        guard consentProfile == .agentRemoteAccessV1 else {
            throw LocalRemoteAccessBootstrapMessageErrorV0
                .invalidConsentProfile
        }
        guard confirmedAtUnixMilliseconds >=
                offer.createdAtUnixMilliseconds,
              confirmedAtUnixMilliseconds <
                offer.expiresAtUnixMilliseconds else {
            throw LocalRemoteAccessBootstrapMessageErrorV0.invalidTime
        }
        self.protocolVersion = protocolVersion
        self.commandID = commandID
        self.offer = offer
        self.consentProfile = consentProfile
        self.confirmedAtUnixMilliseconds = confirmedAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        try requireLocalRemoteAccessBootstrapKeysV0(
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
            offer: container.decode(
                LocalRemoteAccessBootstrapOfferV0.self,
                forKey: .offer
            ),
            consentProfile: container.decode(
                LocalRemoteAccessConsentProfileV0.self,
                forKey: .consentProfile
            ),
            confirmedAtUnixMilliseconds: container.decode(
                Int64.self,
                forKey: .confirmedAtUnixMilliseconds
            )
        )
    }
}

public struct LocalRemoteAccessEnabledReceiptV0:
    Codable,
    Equatable,
    Sendable
{
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, correlationID, offerID, intentRevision
        case completedAtUnixMilliseconds
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let correlationID: UUID
    public let offerID: UUID
    public let intentRevision: Int64
    public let completedAtUnixMilliseconds: Int64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        correlationID: UUID,
        offerID: UUID,
        intentRevision: Int64,
        completedAtUnixMilliseconds: Int64
    ) throws {
        guard protocolVersion == .init() else {
            throw LocalRemoteAccessBootstrapMessageErrorV0.invalidVersion
        }
        guard intentRevision > 0,
              intentRevision <=
                localRemoteAccessBootstrapMaximumSafeIntegerV0 else {
            throw LocalRemoteAccessBootstrapMessageErrorV0.invalidRevision
        }
        guard completedAtUnixMilliseconds >= 0,
              completedAtUnixMilliseconds <=
                localRemoteAccessBootstrapMaximumSafeIntegerV0 else {
            throw LocalRemoteAccessBootstrapMessageErrorV0.invalidTime
        }
        self.protocolVersion = protocolVersion
        self.correlationID = correlationID
        self.offerID = offerID
        self.intentRevision = intentRevision
        self.completedAtUnixMilliseconds = completedAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        try requireLocalRemoteAccessBootstrapKeysV0(
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
            offerID: container.decode(UUID.self, forKey: .offerID),
            intentRevision: container.decode(
                Int64.self,
                forKey: .intentRevision
            ),
            completedAtUnixMilliseconds: container.decode(
                Int64.self,
                forKey: .completedAtUnixMilliseconds
            )
        )
    }

    public func validate(
        against command: LocalRemoteAccessEnableCommandV0
    ) throws {
        guard protocolVersion == command.protocolVersion,
              correlationID == command.commandID,
              offerID == command.offer.offerID,
              command.offer.expectedIntentRevision < Int64.max,
              intentRevision == command.offer.expectedIntentRevision + 1,
              completedAtUnixMilliseconds >=
                command.confirmedAtUnixMilliseconds else {
            throw LocalRemoteAccessBootstrapMessageErrorV0.bindingMismatch
        }
    }
}
