import CompanionWire
import Foundation

public enum LocalHostIdentityRecoveryMessageErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidVersion
    case invalidTime
    case invalidIdentifier
    case invalidReplacement
    case bindingMismatch
    case unknownOrMissingField
}

public enum LocalHostIdentityRecoveryCauseV0:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case keyUnavailable
    case suspectedCompromise
    case userRequestedReset
}

public enum LocalHostIdentityRecoveryScopeV0:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case invalidateAllPairingsGrantsAndWork
}

private struct LocalHostIdentityRecoveryCodingKeyV0: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func requireLocalHostIdentityRecoveryKeysV0(
    _ decoder: Decoder,
    expected: Set<String>
) throws {
    let container = try decoder.container(
        keyedBy: LocalHostIdentityRecoveryCodingKeyV0.self
    )
    guard Set(container.allKeys.map(\.stringValue)) == expected else {
        throw LocalHostIdentityRecoveryMessageErrorV0.unknownOrMissingField
    }
}

private let localHostIdentityRecoveryMaximumTimeV0: Int64 =
    9_007_199_254_740_991
private let localHostIdentityRecoveryReviewLifetimeV0: Int64 = 5 * 60 * 1_000
private let localHostIdentityRecoveryZeroUUIDV0 = UUID(
    uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
)

/// Immutable Agent-issued public facts for one local destructive confirmation.
/// It contains no Keychain reference or replacement-identity choice.
public struct LocalHostIdentityRecoveryReviewV0:
    Codable,
    Equatable,
    Sendable
{
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, reviewID, hostID, hostFingerprint, cause, scope
        case createdAtUnixMilliseconds, expiresAtUnixMilliseconds
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let reviewID: UUID
    public let hostID: UUID
    public let hostFingerprint: WireFingerprint
    public let cause: LocalHostIdentityRecoveryCauseV0
    public let scope: LocalHostIdentityRecoveryScopeV0
    public let createdAtUnixMilliseconds: Int64
    public let expiresAtUnixMilliseconds: Int64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        reviewID: UUID,
        hostID: UUID,
        hostFingerprint: WireFingerprint,
        cause: LocalHostIdentityRecoveryCauseV0,
        scope: LocalHostIdentityRecoveryScopeV0 =
            .invalidateAllPairingsGrantsAndWork,
        createdAtUnixMilliseconds: Int64,
        expiresAtUnixMilliseconds: Int64
    ) throws {
        guard protocolVersion == .init() else {
            throw LocalHostIdentityRecoveryMessageErrorV0.invalidVersion
        }
        guard reviewID != localHostIdentityRecoveryZeroUUIDV0,
              hostID != localHostIdentityRecoveryZeroUUIDV0 else {
            throw LocalHostIdentityRecoveryMessageErrorV0.invalidIdentifier
        }
        guard createdAtUnixMilliseconds >= 0,
              createdAtUnixMilliseconds
                <= localHostIdentityRecoveryMaximumTimeV0
                    - localHostIdentityRecoveryReviewLifetimeV0,
              expiresAtUnixMilliseconds
                == createdAtUnixMilliseconds
                    + localHostIdentityRecoveryReviewLifetimeV0 else {
            throw LocalHostIdentityRecoveryMessageErrorV0.invalidTime
        }
        self.protocolVersion = protocolVersion
        self.reviewID = reviewID
        self.hostID = hostID
        self.hostFingerprint = hostFingerprint
        self.cause = cause
        self.scope = scope
        self.createdAtUnixMilliseconds = createdAtUnixMilliseconds
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        try requireLocalHostIdentityRecoveryKeysV0(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.stringValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            protocolVersion: container.decode(
                LocalIPCProtocolVersion.self,
                forKey: .protocolVersion
            ),
            reviewID: container.decode(UUID.self, forKey: .reviewID),
            hostID: container.decode(UUID.self, forKey: .hostID),
            hostFingerprint: container.decode(
                WireFingerprint.self,
                forKey: .hostFingerprint
            ),
            cause: container.decode(
                LocalHostIdentityRecoveryCauseV0.self,
                forKey: .cause
            ),
            scope: container.decode(
                LocalHostIdentityRecoveryScopeV0.self,
                forKey: .scope
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

public struct LocalHostIdentityRecoveryCommandV0:
    Codable,
    Equatable,
    Sendable
{
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, commandID, recoveryID, review
        case confirmedAtUnixMilliseconds
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let commandID: UUID
    public let recoveryID: UUID
    public let review: LocalHostIdentityRecoveryReviewV0
    public let confirmedAtUnixMilliseconds: Int64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        commandID: UUID,
        recoveryID: UUID,
        review: LocalHostIdentityRecoveryReviewV0,
        confirmedAtUnixMilliseconds: Int64
    ) throws {
        guard protocolVersion == .init(), review.protocolVersion == .init()
        else {
            throw LocalHostIdentityRecoveryMessageErrorV0.invalidVersion
        }
        guard commandID != localHostIdentityRecoveryZeroUUIDV0,
              recoveryID != localHostIdentityRecoveryZeroUUIDV0,
              commandID != recoveryID else {
            throw LocalHostIdentityRecoveryMessageErrorV0.invalidIdentifier
        }
        guard confirmedAtUnixMilliseconds
                >= review.createdAtUnixMilliseconds,
              confirmedAtUnixMilliseconds
                < review.expiresAtUnixMilliseconds else {
            throw LocalHostIdentityRecoveryMessageErrorV0.invalidTime
        }
        self.protocolVersion = protocolVersion
        self.commandID = commandID
        self.recoveryID = recoveryID
        self.review = review
        self.confirmedAtUnixMilliseconds = confirmedAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        try requireLocalHostIdentityRecoveryKeysV0(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.stringValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            protocolVersion: container.decode(
                LocalIPCProtocolVersion.self,
                forKey: .protocolVersion
            ),
            commandID: container.decode(UUID.self, forKey: .commandID),
            recoveryID: container.decode(UUID.self, forKey: .recoveryID),
            review: container.decode(
                LocalHostIdentityRecoveryReviewV0.self,
                forKey: .review
            ),
            confirmedAtUnixMilliseconds: container.decode(
                Int64.self,
                forKey: .confirmedAtUnixMilliseconds
            )
        )
    }
}

public struct LocalHostIdentityRecoveredReceiptV0:
    Codable,
    Equatable,
    Sendable
{
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, correlationID, recoveryID, replacedHostID
        case newHostID, newHostFingerprint, completedAtUnixMilliseconds
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let correlationID: UUID
    public let recoveryID: UUID
    public let replacedHostID: UUID
    public let newHostID: UUID
    public let newHostFingerprint: WireFingerprint
    public let completedAtUnixMilliseconds: Int64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        correlationID: UUID,
        recoveryID: UUID,
        replacedHostID: UUID,
        newHostID: UUID,
        newHostFingerprint: WireFingerprint,
        completedAtUnixMilliseconds: Int64
    ) throws {
        guard protocolVersion == .init() else {
            throw LocalHostIdentityRecoveryMessageErrorV0.invalidVersion
        }
        guard correlationID != localHostIdentityRecoveryZeroUUIDV0,
              recoveryID != localHostIdentityRecoveryZeroUUIDV0,
              replacedHostID != localHostIdentityRecoveryZeroUUIDV0,
              newHostID != localHostIdentityRecoveryZeroUUIDV0 else {
            throw LocalHostIdentityRecoveryMessageErrorV0.invalidIdentifier
        }
        guard replacedHostID != newHostID else {
            throw LocalHostIdentityRecoveryMessageErrorV0.invalidReplacement
        }
        guard completedAtUnixMilliseconds >= 0,
              completedAtUnixMilliseconds
                <= localHostIdentityRecoveryMaximumTimeV0 else {
            throw LocalHostIdentityRecoveryMessageErrorV0.invalidTime
        }
        self.protocolVersion = protocolVersion
        self.correlationID = correlationID
        self.recoveryID = recoveryID
        self.replacedHostID = replacedHostID
        self.newHostID = newHostID
        self.newHostFingerprint = newHostFingerprint
        self.completedAtUnixMilliseconds = completedAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        try requireLocalHostIdentityRecoveryKeysV0(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.stringValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            protocolVersion: container.decode(
                LocalIPCProtocolVersion.self,
                forKey: .protocolVersion
            ),
            correlationID: container.decode(UUID.self, forKey: .correlationID),
            recoveryID: container.decode(UUID.self, forKey: .recoveryID),
            replacedHostID: container.decode(UUID.self, forKey: .replacedHostID),
            newHostID: container.decode(UUID.self, forKey: .newHostID),
            newHostFingerprint: container.decode(
                WireFingerprint.self,
                forKey: .newHostFingerprint
            ),
            completedAtUnixMilliseconds: container.decode(
                Int64.self,
                forKey: .completedAtUnixMilliseconds
            )
        )
    }

    public func validate(
        against command: LocalHostIdentityRecoveryCommandV0
    ) throws {
        guard correlationID == command.commandID,
              recoveryID == command.recoveryID,
              replacedHostID == command.review.hostID,
              newHostID != command.review.hostID,
              newHostFingerprint != command.review.hostFingerprint,
              completedAtUnixMilliseconds
                >= command.confirmedAtUnixMilliseconds else {
            throw LocalHostIdentityRecoveryMessageErrorV0.bindingMismatch
        }
    }
}
