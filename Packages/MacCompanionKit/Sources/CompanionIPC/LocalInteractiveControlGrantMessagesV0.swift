import CompanionDomain
import CompanionWire
import Foundation

public enum LocalInteractiveControlGrantErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidRequest
    case invalidReview
    case bindingMismatch
}

/// Fixed product authority used only to explain and persist the durable
/// Interactive Control grant. It is deliberately not a published Act provider.
public enum InteractiveControlDurableGrantV0 {
    public static let identifier = "maccompanion.interactive.control"
    public static let reviewLifetimeMilliseconds: Int64 = 300_000

    public static func descriptor() throws -> CapabilityDescriptorV1 {
        try CapabilityDescriptorV1(
            capabilityID: identifier,
            schemaVersion: 1,
            providerID: "maccompanion.interactive.authorization",
            providerVersion: "0.1.0",
            providerGeneration: UUID(
                uuidString: "018f9900-0000-7000-8000-000000000010"
            )!,
            executionRevision: UUID(
                uuidString: "018f9900-0000-7000-8000-000000000011"
            )!,
            englishTitle: "Remote Control",
            englishSummary:
                "Allow this iPhone to request live screen, pointer, keyboard, and eligible text control sessions.",
            parameterSchema: .object(properties: []),
            resultSchema: .object(properties: []),
            effects: try CapabilityEffectFacts(
                dataAccess: .privateData,
                changesLocalState: .irreversible,
                mayDisruptUser: true,
                invokesExternalService: false,
                usesCredentials: false,
                destructive: false,
                requiresForegroundSession: true,
                allowedWhileLocked: false,
                cancellation: .bestEffort
            )
        )
    }

    public static func registry() throws -> CapabilityRegistrySnapshotV1 {
        try CapabilityRegistrySnapshotV1(
            generation: UUID(
                uuidString: "018f9900-0000-7000-8000-000000000012"
            )!,
            capabilities: [descriptor()]
        )
    }
}

public struct LocalInteractiveControlGrantReviewRequestV0:
    Codable,
    Equatable,
    Sendable
{
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, commandID, requestedAtUnixMilliseconds
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let commandID: UUID
    public let requestedAtUnixMilliseconds: Int64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        commandID: UUID,
        requestedAtUnixMilliseconds: Int64
    ) throws {
        guard protocolVersion == .init(),
              commandID != Self.zeroUUID,
              requestedAtUnixMilliseconds >= 0,
              requestedAtUnixMilliseconds <= Self.maximumTime else {
            throw LocalInteractiveControlGrantErrorV0.invalidRequest
        }
        self.protocolVersion = protocolVersion
        self.commandID = commandID
        self.requestedAtUnixMilliseconds = requestedAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        let all = try decoder.container(
            keyedBy: LocalInteractiveControlGrantAnyCodingKeyV0.self
        )
        guard Set(all.allKeys.map(\.stringValue))
                == Set(CodingKeys.allCases.map(\.stringValue)) else {
            throw LocalInteractiveControlGrantErrorV0.invalidRequest
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            protocolVersion: container.decode(
                LocalIPCProtocolVersion.self,
                forKey: .protocolVersion
            ),
            commandID: container.decode(UUID.self, forKey: .commandID),
            requestedAtUnixMilliseconds: container.decode(
                Int64.self,
                forKey: .requestedAtUnixMilliseconds
            )
        )
    }

    fileprivate static let maximumTime: Int64 = 9_007_199_254_740_991
    fileprivate static let zeroUUID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    )
}

private struct LocalInteractiveControlGrantAnyCodingKeyV0: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

public struct LocalInteractiveControlGrantReviewV0:
    Codable,
    Equatable,
    Sendable
{
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, correlationID, reviewID, deviceID
        case deviceDisplayName, authorizationEpoch, grantRevision
        case policyRevision, currentGrantIDs, capabilityID
        case createdAtUnixMilliseconds, expiresAtUnixMilliseconds
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let correlationID: UUID
    public let reviewID: UUID
    public let deviceID: UUID
    public let deviceDisplayName: DeviceDisplayName
    public let authorizationEpoch: AuthorizationEpoch
    public let grantRevision: GrantRevision
    public let policyRevision: PolicyRevision
    public let currentGrantIDs: [String]
    public let capabilityID: String
    public let createdAtUnixMilliseconds: Int64
    public let expiresAtUnixMilliseconds: Int64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        correlationID: UUID,
        reviewID: UUID,
        deviceID: UUID,
        deviceDisplayName: DeviceDisplayName,
        authorizationEpoch: AuthorizationEpoch,
        grantRevision: GrantRevision,
        policyRevision: PolicyRevision,
        currentGrants: CapabilityGrantSet,
        capabilityID: String = InteractiveControlDurableGrantV0.identifier,
        createdAtUnixMilliseconds: Int64,
        expiresAtUnixMilliseconds: Int64
    ) throws {
        guard protocolVersion == .init(),
              correlationID != LocalInteractiveControlGrantReviewRequestV0.zeroUUID,
              reviewID != LocalInteractiveControlGrantReviewRequestV0.zeroUUID,
              deviceID != LocalInteractiveControlGrantReviewRequestV0.zeroUUID,
              correlationID != reviewID,
              reviewID != deviceID,
              capabilityID == InteractiveControlDurableGrantV0.identifier,
              !currentGrants.capabilityIDs.contains(capabilityID),
              authorizationEpoch.rawValue >= 1,
              grantRevision.rawValue >= 1,
              policyRevision.rawValue >= 1,
              createdAtUnixMilliseconds >= 0,
              createdAtUnixMilliseconds
                <= LocalInteractiveControlGrantReviewRequestV0.maximumTime
                    - InteractiveControlDurableGrantV0.reviewLifetimeMilliseconds,
              expiresAtUnixMilliseconds
                == createdAtUnixMilliseconds
                    + InteractiveControlDurableGrantV0.reviewLifetimeMilliseconds else {
            throw LocalInteractiveControlGrantErrorV0.invalidReview
        }
        self.protocolVersion = protocolVersion
        self.correlationID = correlationID
        self.reviewID = reviewID
        self.deviceID = deviceID
        self.deviceDisplayName = deviceDisplayName
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.policyRevision = policyRevision
        currentGrantIDs = currentGrants.capabilityIDs.sorted()
        self.capabilityID = capabilityID
        self.createdAtUnixMilliseconds = createdAtUnixMilliseconds
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        let all = try decoder.container(
            keyedBy: LocalInteractiveControlGrantAnyCodingKeyV0.self
        )
        guard Set(all.allKeys.map(\.stringValue))
                == Set(CodingKeys.allCases.map(\.stringValue)) else {
            throw LocalInteractiveControlGrantErrorV0.invalidReview
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let current: CapabilityGrantSet
        do {
            current = try CapabilityGrantSet(
                container.decode([String].self, forKey: .currentGrantIDs)
            )
        } catch {
            throw LocalInteractiveControlGrantErrorV0.invalidReview
        }
        try self.init(
            protocolVersion: container.decode(
                LocalIPCProtocolVersion.self,
                forKey: .protocolVersion
            ),
            correlationID: container.decode(UUID.self, forKey: .correlationID),
            reviewID: container.decode(UUID.self, forKey: .reviewID),
            deviceID: container.decode(UUID.self, forKey: .deviceID),
            deviceDisplayName: container.decode(
                DeviceDisplayName.self,
                forKey: .deviceDisplayName
            ),
            authorizationEpoch: container.decode(
                AuthorizationEpoch.self,
                forKey: .authorizationEpoch
            ),
            grantRevision: container.decode(
                GrantRevision.self,
                forKey: .grantRevision
            ),
            policyRevision: container.decode(
                PolicyRevision.self,
                forKey: .policyRevision
            ),
            currentGrants: current,
            capabilityID: container.decode(String.self, forKey: .capabilityID),
            createdAtUnixMilliseconds: container.decode(
                Int64.self,
                forKey: .createdAtUnixMilliseconds
            ),
            expiresAtUnixMilliseconds: container.decode(
                Int64.self,
                forKey: .expiresAtUnixMilliseconds
            )
        )
        guard currentGrantIDs == current.capabilityIDs else {
            throw LocalInteractiveControlGrantErrorV0.invalidReview
        }
    }

    public func currentGrantSet() throws -> CapabilityGrantSet {
        try CapabilityGrantSet(currentGrantIDs)
    }

    public func proposedGrantSet() throws -> CapabilityGrantSet {
        try CapabilityGrantSet(currentGrantIDs + [capabilityID])
    }

    public func validate(
        against request: LocalInteractiveControlGrantReviewRequestV0
    ) throws {
        guard correlationID == request.commandID,
              createdAtUnixMilliseconds >= request.requestedAtUnixMilliseconds
        else {
            throw LocalInteractiveControlGrantErrorV0.bindingMismatch
        }
    }

    public func makeDecisionCommand(
        commandID: UUID,
        decision: LocalGrantDecisionV0,
        decidedAtUnixMilliseconds: Int64
    ) throws -> LocalGrantDecisionCommandV0 {
        try LocalGrantDecisionCommandV0(
            commandID: commandID,
            reviewID: reviewID,
            deviceID: deviceID,
            deviceDisplayName: deviceDisplayName,
            decision: decision,
            expectedAuthorizationEpoch: authorizationEpoch,
            expectedGrantRevision: grantRevision,
            expectedPolicyRevision: policyRevision,
            expectedCurrentGrants: currentGrantSet(),
            proposedGrants: proposedGrantSet(),
            decidedAtUnixMilliseconds: decidedAtUnixMilliseconds
        )
    }
}
