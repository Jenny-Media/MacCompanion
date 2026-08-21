import CompanionDomain
import Foundation

public enum DeviceAdministrationMessageErrorV0: Error, Equatable, Sendable {
    case invalidVersion
    case invalidTime
    case invalidIdentifier
    case invalidState
    case bindingMismatch
    case unknownOrMissingField
}

private struct DeviceAdministrationCodingKeyV0: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func requireDeviceAdministrationKeysV0(
    _ decoder: Decoder,
    expected: Set<String>
) throws {
    let container = try decoder.container(
        keyedBy: DeviceAdministrationCodingKeyV0.self
    )
    guard Set(container.allKeys.map(\.stringValue)) == expected else {
        throw DeviceAdministrationMessageErrorV0.unknownOrMissingField
    }
}

private let deviceAdministrationMaximumTimeV0: Int64 =
    9_007_199_254_740_991
private let deviceRevocationReviewLifetimeV0: Int64 = 5 * 60 * 1_000
private let deviceAdministrationZeroUUIDV0 = UUID(
    uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
)

public struct SetDeviceDisplayNameCommandV0: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, commandID, deviceID, displayName
        case occurredAtUnixMilliseconds
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let commandID: UUID
    public let deviceID: UUID
    public let displayName: DeviceDisplayName
    public let occurredAtUnixMilliseconds: Int64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        commandID: UUID,
        deviceID: UUID,
        displayName: DeviceDisplayName,
        occurredAtUnixMilliseconds: Int64
    ) throws {
        guard protocolVersion == .init() else {
            throw DeviceAdministrationMessageErrorV0.invalidVersion
        }
        guard occurredAtUnixMilliseconds >= 0,
              occurredAtUnixMilliseconds
                <= Int64(MonotonicRevision<AuthorizationEpochTag>.maximumWireValue) else {
            throw DeviceAdministrationMessageErrorV0.invalidTime
        }
        self.protocolVersion = protocolVersion
        self.commandID = commandID
        self.deviceID = deviceID
        self.displayName = displayName
        self.occurredAtUnixMilliseconds = occurredAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        try requireDeviceAdministrationKeysV0(
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
            deviceID: container.decode(UUID.self, forKey: .deviceID),
            displayName: container.decode(
                DeviceDisplayName.self,
                forKey: .displayName
            ),
            occurredAtUnixMilliseconds: container.decode(
                Int64.self,
                forKey: .occurredAtUnixMilliseconds
            )
        )
    }
}

public struct SetDeviceDisplayNameReceiptV0: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, correlationID, deviceID, displayName
        case storedAtUnixMilliseconds
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let correlationID: UUID
    public let deviceID: UUID
    public let displayName: DeviceDisplayName
    public let storedAtUnixMilliseconds: Int64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        correlationID: UUID,
        deviceID: UUID,
        displayName: DeviceDisplayName,
        storedAtUnixMilliseconds: Int64
    ) throws {
        guard protocolVersion == .init() else {
            throw DeviceAdministrationMessageErrorV0.invalidVersion
        }
        guard storedAtUnixMilliseconds >= 0,
              storedAtUnixMilliseconds
                <= Int64(MonotonicRevision<AuthorizationEpochTag>.maximumWireValue) else {
            throw DeviceAdministrationMessageErrorV0.invalidTime
        }
        self.protocolVersion = protocolVersion
        self.correlationID = correlationID
        self.deviceID = deviceID
        self.displayName = displayName
        self.storedAtUnixMilliseconds = storedAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        try requireDeviceAdministrationKeysV0(
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
            deviceID: container.decode(UUID.self, forKey: .deviceID),
            displayName: container.decode(
                DeviceDisplayName.self,
                forKey: .displayName
            ),
            storedAtUnixMilliseconds: container.decode(
                Int64.self,
                forKey: .storedAtUnixMilliseconds
            )
        )
    }

    public func validate(
        against command: SetDeviceDisplayNameCommandV0
    ) throws {
        guard correlationID == command.commandID,
              deviceID == command.deviceID,
              displayName == command.displayName,
              storedAtUnixMilliseconds
                >= command.occurredAtUnixMilliseconds else {
            throw DeviceAdministrationMessageErrorV0.bindingMismatch
        }
    }
}

/// Immutable public facts the authenticated menu app must present before a
/// destructive single-device revoke. No remote-provided name or key material
/// is present.
public struct LocalDeviceRevocationReviewV0:
    Codable,
    Equatable,
    Sendable
{
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, reviewID, deviceID, deviceDisplayName
        case state, authorizationEpoch, grantRevision
        case createdAtUnixMilliseconds, expiresAtUnixMilliseconds
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let reviewID: UUID
    public let deviceID: UUID
    public let deviceDisplayName: DeviceDisplayName
    public let state: DeviceAuthorizationState
    public let authorizationEpoch: AuthorizationEpoch
    public let grantRevision: GrantRevision
    public let createdAtUnixMilliseconds: Int64
    public let expiresAtUnixMilliseconds: Int64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        reviewID: UUID,
        deviceID: UUID,
        deviceDisplayName: DeviceDisplayName,
        state: DeviceAuthorizationState,
        authorizationEpoch: AuthorizationEpoch,
        grantRevision: GrantRevision,
        createdAtUnixMilliseconds: Int64,
        expiresAtUnixMilliseconds: Int64
    ) throws {
        guard protocolVersion == .init() else {
            throw DeviceAdministrationMessageErrorV0.invalidVersion
        }
        guard reviewID != deviceAdministrationZeroUUIDV0,
              deviceID != deviceAdministrationZeroUUIDV0,
              reviewID != deviceID else {
            throw DeviceAdministrationMessageErrorV0.invalidIdentifier
        }
        guard state == .activeMonitorOnly
                || state == .activeGranted
                || state == .suspended,
              authorizationEpoch.rawValue >= 1,
              grantRevision.rawValue >= 1 else {
            throw DeviceAdministrationMessageErrorV0.invalidState
        }
        guard createdAtUnixMilliseconds >= 0,
              createdAtUnixMilliseconds
                <= deviceAdministrationMaximumTimeV0
                    - deviceRevocationReviewLifetimeV0,
              expiresAtUnixMilliseconds
                == createdAtUnixMilliseconds
                    + deviceRevocationReviewLifetimeV0 else {
            throw DeviceAdministrationMessageErrorV0.invalidTime
        }
        self.protocolVersion = protocolVersion
        self.reviewID = reviewID
        self.deviceID = deviceID
        self.deviceDisplayName = deviceDisplayName
        self.state = state
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.createdAtUnixMilliseconds = createdAtUnixMilliseconds
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        try requireDeviceAdministrationKeysV0(
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
            deviceID: container.decode(UUID.self, forKey: .deviceID),
            deviceDisplayName: container.decode(
                DeviceDisplayName.self,
                forKey: .deviceDisplayName
            ),
            state: container.decode(
                DeviceAuthorizationState.self,
                forKey: .state
            ),
            authorizationEpoch: container.decode(
                AuthorizationEpoch.self,
                forKey: .authorizationEpoch
            ),
            grantRevision: container.decode(
                GrantRevision.self,
                forKey: .grantRevision
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

public struct LocalDeviceRevocationCommandV0:
    Codable,
    Equatable,
    Sendable
{
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, commandID, review, confirmedAtUnixMilliseconds
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let commandID: UUID
    public let review: LocalDeviceRevocationReviewV0
    public let confirmedAtUnixMilliseconds: Int64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        commandID: UUID,
        review: LocalDeviceRevocationReviewV0,
        confirmedAtUnixMilliseconds: Int64
    ) throws {
        guard protocolVersion == .init(), review.protocolVersion == .init()
        else {
            throw DeviceAdministrationMessageErrorV0.invalidVersion
        }
        guard commandID != deviceAdministrationZeroUUIDV0,
              commandID != review.reviewID,
              commandID != review.deviceID else {
            throw DeviceAdministrationMessageErrorV0.invalidIdentifier
        }
        guard confirmedAtUnixMilliseconds
                >= review.createdAtUnixMilliseconds,
              confirmedAtUnixMilliseconds
                < review.expiresAtUnixMilliseconds else {
            throw DeviceAdministrationMessageErrorV0.invalidTime
        }
        self.protocolVersion = protocolVersion
        self.commandID = commandID
        self.review = review
        self.confirmedAtUnixMilliseconds = confirmedAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        try requireDeviceAdministrationKeysV0(
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
            review: container.decode(
                LocalDeviceRevocationReviewV0.self,
                forKey: .review
            ),
            confirmedAtUnixMilliseconds: container.decode(
                Int64.self,
                forKey: .confirmedAtUnixMilliseconds
            )
        )
    }
}

public struct LocalDeviceRevokedReceiptV0:
    Codable,
    Equatable,
    Sendable
{
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, correlationID, reviewID, deviceID, state
        case authorizationEpoch, grantRevision, completedAtUnixMilliseconds
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let correlationID: UUID
    public let reviewID: UUID
    public let deviceID: UUID
    public let state: DeviceAuthorizationState
    public let authorizationEpoch: AuthorizationEpoch
    public let grantRevision: GrantRevision
    public let completedAtUnixMilliseconds: Int64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        correlationID: UUID,
        reviewID: UUID,
        deviceID: UUID,
        state: DeviceAuthorizationState = .revoked,
        authorizationEpoch: AuthorizationEpoch,
        grantRevision: GrantRevision,
        completedAtUnixMilliseconds: Int64
    ) throws {
        guard protocolVersion == .init() else {
            throw DeviceAdministrationMessageErrorV0.invalidVersion
        }
        guard correlationID != deviceAdministrationZeroUUIDV0,
              reviewID != deviceAdministrationZeroUUIDV0,
              deviceID != deviceAdministrationZeroUUIDV0 else {
            throw DeviceAdministrationMessageErrorV0.invalidIdentifier
        }
        guard state == .revoked,
              authorizationEpoch.rawValue >= 2,
              grantRevision.rawValue >= 2 else {
            throw DeviceAdministrationMessageErrorV0.invalidState
        }
        guard completedAtUnixMilliseconds >= 0,
              completedAtUnixMilliseconds
                <= deviceAdministrationMaximumTimeV0 else {
            throw DeviceAdministrationMessageErrorV0.invalidTime
        }
        self.protocolVersion = protocolVersion
        self.correlationID = correlationID
        self.reviewID = reviewID
        self.deviceID = deviceID
        self.state = state
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.completedAtUnixMilliseconds = completedAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        try requireDeviceAdministrationKeysV0(
            decoder,
            expected: Set(CodingKeys.allCases.map(\.stringValue))
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
            reviewID: container.decode(UUID.self, forKey: .reviewID),
            deviceID: container.decode(UUID.self, forKey: .deviceID),
            state: container.decode(
                DeviceAuthorizationState.self,
                forKey: .state
            ),
            authorizationEpoch: container.decode(
                AuthorizationEpoch.self,
                forKey: .authorizationEpoch
            ),
            grantRevision: container.decode(
                GrantRevision.self,
                forKey: .grantRevision
            ),
            completedAtUnixMilliseconds: container.decode(
                Int64.self,
                forKey: .completedAtUnixMilliseconds
            )
        )
    }

    public func validate(
        against command: LocalDeviceRevocationCommandV0
    ) throws {
        guard correlationID == command.commandID,
              reviewID == command.review.reviewID,
              deviceID == command.review.deviceID,
              state == .revoked,
              authorizationEpoch
                == (try command.review.authorizationEpoch.advanced()),
              grantRevision
                == (try command.review.grantRevision.advanced()),
              completedAtUnixMilliseconds
                >= command.confirmedAtUnixMilliseconds else {
            throw DeviceAdministrationMessageErrorV0.bindingMismatch
        }
    }
}
