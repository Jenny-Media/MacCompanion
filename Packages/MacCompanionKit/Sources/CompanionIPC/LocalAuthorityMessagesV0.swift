import CompanionDomain
import Foundation

public enum LocalAuthorityMessageErrorV0: Error, Equatable, Sendable {
    case invalidVersion
    case invalidTime
    case invalidGrantSet
    case invalidDecision
    case bindingMismatch
    case revisionMismatch
    case teardownIncomplete
    case unknownOrMissingField
}

private struct LocalAuthorityAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func requireLocalAuthorityKeys(
    _ decoder: Decoder,
    _ expected: Set<String>
) throws {
    let container = try decoder.container(
        keyedBy: LocalAuthorityAnyCodingKey.self
    )
    guard Set(container.allKeys.map(\.stringValue)) == expected else {
        throw LocalAuthorityMessageErrorV0.unknownOrMissingField
    }
}

private let localAuthorityMaximumTime = Int64(
    MonotonicRevision<AuthorizationEpochTag>.maximumWireValue
)

private func canonicalGrantIDs(
    _ value: CapabilityGrantSet
) -> [String] {
    value.capabilityIDs
}

private func decodeCanonicalGrantSet(_ ids: [String]) throws -> CapabilityGrantSet {
    let value: CapabilityGrantSet
    do {
        value = try CapabilityGrantSet(ids)
    } catch {
        throw LocalAuthorityMessageErrorV0.invalidGrantSet
    }
    guard value.capabilityIDs == ids else {
        throw LocalAuthorityMessageErrorV0.invalidGrantSet
    }
    return value
}

public enum LocalGrantDecisionV0: String, Codable, CaseIterable, Sendable {
    case approve
    case decline
}

public struct LocalGrantDecisionCommandV0: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, commandID, reviewID, deviceID, deviceDisplayName
        case decision, expectedAuthorizationEpoch, expectedGrantRevision
        case expectedPolicyRevision, expectedCurrentGrantIDs, proposedGrantIDs
        case decidedAtUnixMilliseconds
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let commandID: UUID
    public let reviewID: UUID
    public let deviceID: UUID
    public let deviceDisplayName: DeviceDisplayName
    public let decision: LocalGrantDecisionV0
    public let expectedAuthorizationEpoch: AuthorizationEpoch
    public let expectedGrantRevision: GrantRevision
    public let expectedPolicyRevision: PolicyRevision
    public let expectedCurrentGrantIDs: [String]
    public let proposedGrantIDs: [String]
    public let decidedAtUnixMilliseconds: Int64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        commandID: UUID,
        reviewID: UUID,
        deviceID: UUID,
        deviceDisplayName: DeviceDisplayName,
        decision: LocalGrantDecisionV0,
        expectedAuthorizationEpoch: AuthorizationEpoch,
        expectedGrantRevision: GrantRevision,
        expectedPolicyRevision: PolicyRevision,
        expectedCurrentGrants: CapabilityGrantSet,
        proposedGrants: CapabilityGrantSet,
        decidedAtUnixMilliseconds: Int64
    ) throws {
        guard protocolVersion == .init() else {
            throw LocalAuthorityMessageErrorV0.invalidVersion
        }
        guard expectedAuthorizationEpoch.rawValue >= 1,
              expectedGrantRevision.rawValue >= 1,
              expectedPolicyRevision.rawValue >= 1 else {
            throw LocalAuthorityMessageErrorV0.revisionMismatch
        }
        let current = Set(expectedCurrentGrants.capabilityIDs)
        let proposed = Set(proposedGrants.capabilityIDs)
        guard proposed.isStrictSuperset(of: current) else {
            throw LocalAuthorityMessageErrorV0.invalidGrantSet
        }
        guard decidedAtUnixMilliseconds >= 0,
              decidedAtUnixMilliseconds <= localAuthorityMaximumTime else {
            throw LocalAuthorityMessageErrorV0.invalidTime
        }
        self.protocolVersion = protocolVersion
        self.commandID = commandID
        self.reviewID = reviewID
        self.deviceID = deviceID
        self.deviceDisplayName = deviceDisplayName
        self.decision = decision
        self.expectedAuthorizationEpoch = expectedAuthorizationEpoch
        self.expectedGrantRevision = expectedGrantRevision
        self.expectedPolicyRevision = expectedPolicyRevision
        expectedCurrentGrantIDs = canonicalGrantIDs(expectedCurrentGrants)
        proposedGrantIDs = canonicalGrantIDs(proposedGrants)
        self.decidedAtUnixMilliseconds = decidedAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        try requireLocalAuthorityKeys(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue))
        )
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            protocolVersion: c.decode(LocalIPCProtocolVersion.self, forKey: .protocolVersion),
            commandID: c.decode(UUID.self, forKey: .commandID),
            reviewID: c.decode(UUID.self, forKey: .reviewID),
            deviceID: c.decode(UUID.self, forKey: .deviceID),
            deviceDisplayName: c.decode(DeviceDisplayName.self, forKey: .deviceDisplayName),
            decision: c.decode(LocalGrantDecisionV0.self, forKey: .decision),
            expectedAuthorizationEpoch: c.decode(AuthorizationEpoch.self, forKey: .expectedAuthorizationEpoch),
            expectedGrantRevision: c.decode(GrantRevision.self, forKey: .expectedGrantRevision),
            expectedPolicyRevision: c.decode(PolicyRevision.self, forKey: .expectedPolicyRevision),
            expectedCurrentGrants: decodeCanonicalGrantSet(
                c.decode([String].self, forKey: .expectedCurrentGrantIDs)
            ),
            proposedGrants: decodeCanonicalGrantSet(
                c.decode([String].self, forKey: .proposedGrantIDs)
            ),
            decidedAtUnixMilliseconds: c.decode(Int64.self, forKey: .decidedAtUnixMilliseconds)
        )
    }

    public func expectedCurrentGrantSet() throws -> CapabilityGrantSet {
        try decodeCanonicalGrantSet(expectedCurrentGrantIDs)
    }

    public func proposedGrantSet() throws -> CapabilityGrantSet {
        try decodeCanonicalGrantSet(proposedGrantIDs)
    }
}

public struct LocalGrantDecisionReceiptV0: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, correlationID, reviewID, deviceID, decision
        case storedGrantIDs, authorizationEpoch, grantRevision, policyRevision
        case completedAtUnixMilliseconds
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let correlationID: UUID
    public let reviewID: UUID
    public let deviceID: UUID
    public let decision: LocalGrantDecisionV0
    public let storedGrantIDs: [String]
    public let authorizationEpoch: AuthorizationEpoch
    public let grantRevision: GrantRevision
    public let policyRevision: PolicyRevision
    public let completedAtUnixMilliseconds: Int64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        correlationID: UUID,
        reviewID: UUID,
        deviceID: UUID,
        decision: LocalGrantDecisionV0,
        storedGrants: CapabilityGrantSet,
        authorizationEpoch: AuthorizationEpoch,
        grantRevision: GrantRevision,
        policyRevision: PolicyRevision,
        completedAtUnixMilliseconds: Int64
    ) throws {
        guard protocolVersion == .init() else {
            throw LocalAuthorityMessageErrorV0.invalidVersion
        }
        guard authorizationEpoch.rawValue >= 1,
              grantRevision.rawValue >= 1,
              policyRevision.rawValue >= 1 else {
            throw LocalAuthorityMessageErrorV0.revisionMismatch
        }
        guard completedAtUnixMilliseconds >= 0,
              completedAtUnixMilliseconds <= localAuthorityMaximumTime else {
            throw LocalAuthorityMessageErrorV0.invalidTime
        }
        self.protocolVersion = protocolVersion
        self.correlationID = correlationID
        self.reviewID = reviewID
        self.deviceID = deviceID
        self.decision = decision
        storedGrantIDs = canonicalGrantIDs(storedGrants)
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.policyRevision = policyRevision
        self.completedAtUnixMilliseconds = completedAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        try requireLocalAuthorityKeys(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue))
        )
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            protocolVersion: c.decode(LocalIPCProtocolVersion.self, forKey: .protocolVersion),
            correlationID: c.decode(UUID.self, forKey: .correlationID),
            reviewID: c.decode(UUID.self, forKey: .reviewID),
            deviceID: c.decode(UUID.self, forKey: .deviceID),
            decision: c.decode(LocalGrantDecisionV0.self, forKey: .decision),
            storedGrants: decodeCanonicalGrantSet(
                c.decode([String].self, forKey: .storedGrantIDs)
            ),
            authorizationEpoch: c.decode(AuthorizationEpoch.self, forKey: .authorizationEpoch),
            grantRevision: c.decode(GrantRevision.self, forKey: .grantRevision),
            policyRevision: c.decode(PolicyRevision.self, forKey: .policyRevision),
            completedAtUnixMilliseconds: c.decode(Int64.self, forKey: .completedAtUnixMilliseconds)
        )
    }

    public func storedGrantSet() throws -> CapabilityGrantSet {
        try decodeCanonicalGrantSet(storedGrantIDs)
    }

    public func validate(against command: LocalGrantDecisionCommandV0) throws {
        guard correlationID == command.commandID,
              reviewID == command.reviewID,
              deviceID == command.deviceID,
              decision == command.decision,
              policyRevision == command.expectedPolicyRevision,
              completedAtUnixMilliseconds >= command.decidedAtUnixMilliseconds else {
            throw LocalAuthorityMessageErrorV0.bindingMismatch
        }
        switch decision {
        case .approve:
            guard let nextEpoch = try? command.expectedAuthorizationEpoch.advanced(),
                  let nextGrant = try? command.expectedGrantRevision.advanced(),
                  authorizationEpoch == nextEpoch,
                  grantRevision == nextGrant,
                  storedGrantIDs == command.proposedGrantIDs else {
                throw LocalAuthorityMessageErrorV0.revisionMismatch
            }
        case .decline:
            guard authorizationEpoch == command.expectedAuthorizationEpoch,
                  grantRevision == command.expectedGrantRevision,
                  storedGrantIDs == command.expectedCurrentGrantIDs else {
                throw LocalAuthorityMessageErrorV0.revisionMismatch
            }
        }
    }
}

public enum LocalInteractiveStopReasonV0: String, Codable, CaseIterable, Sendable {
    case userRequested
    case deviceSuspended
    case deviceRevoked
    case controlDisabled
}

public struct LocalInteractiveStopCommandV0: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, commandID, deviceID, deviceDisplayName, requestID
        case approvalID, interactiveSessionID, reason, occurredAtUnixMilliseconds
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let commandID: UUID
    public let deviceID: UUID
    public let deviceDisplayName: DeviceDisplayName
    public let requestID: UUID
    public let approvalID: UUID
    public let interactiveSessionID: UUID?
    public let reason: LocalInteractiveStopReasonV0
    public let occurredAtUnixMilliseconds: Int64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        commandID: UUID,
        deviceID: UUID,
        deviceDisplayName: DeviceDisplayName,
        requestID: UUID,
        approvalID: UUID,
        interactiveSessionID: UUID?,
        reason: LocalInteractiveStopReasonV0,
        occurredAtUnixMilliseconds: Int64
    ) throws {
        guard protocolVersion == .init() else {
            throw LocalAuthorityMessageErrorV0.invalidVersion
        }
        guard occurredAtUnixMilliseconds >= 0,
              occurredAtUnixMilliseconds <= localAuthorityMaximumTime else {
            throw LocalAuthorityMessageErrorV0.invalidTime
        }
        self.protocolVersion = protocolVersion
        self.commandID = commandID
        self.deviceID = deviceID
        self.deviceDisplayName = deviceDisplayName
        self.requestID = requestID
        self.approvalID = approvalID
        self.interactiveSessionID = interactiveSessionID
        self.reason = reason
        self.occurredAtUnixMilliseconds = occurredAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        try requireLocalAuthorityKeys(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue))
        )
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            protocolVersion: c.decode(LocalIPCProtocolVersion.self, forKey: .protocolVersion),
            commandID: c.decode(UUID.self, forKey: .commandID),
            deviceID: c.decode(UUID.self, forKey: .deviceID),
            deviceDisplayName: c.decode(DeviceDisplayName.self, forKey: .deviceDisplayName),
            requestID: c.decode(UUID.self, forKey: .requestID),
            approvalID: c.decode(UUID.self, forKey: .approvalID),
            interactiveSessionID: c.decodeIfPresent(UUID.self, forKey: .interactiveSessionID),
            reason: c.decode(LocalInteractiveStopReasonV0.self, forKey: .reason),
            occurredAtUnixMilliseconds: c.decode(Int64.self, forKey: .occurredAtUnixMilliseconds)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(protocolVersion, forKey: .protocolVersion)
        try c.encode(commandID, forKey: .commandID)
        try c.encode(deviceID, forKey: .deviceID)
        try c.encode(deviceDisplayName, forKey: .deviceDisplayName)
        try c.encode(requestID, forKey: .requestID)
        try c.encode(approvalID, forKey: .approvalID)
        if let interactiveSessionID {
            try c.encode(interactiveSessionID, forKey: .interactiveSessionID)
        } else {
            try c.encodeNil(forKey: .interactiveSessionID)
        }
        try c.encode(reason, forKey: .reason)
        try c.encode(occurredAtUnixMilliseconds, forKey: .occurredAtUnixMilliseconds)
    }
}

public struct LocalInteractiveStoppedReceiptV0: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, correlationID, deviceID, requestID, approvalID
        case interactiveSessionID, reason, remoteAuthorityEnded
        case runtimeTeardownComplete, completedAtUnixMilliseconds
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let correlationID: UUID
    public let deviceID: UUID
    public let requestID: UUID
    public let approvalID: UUID
    public let interactiveSessionID: UUID?
    public let reason: LocalInteractiveStopReasonV0
    public let remoteAuthorityEnded: Bool
    public let runtimeTeardownComplete: Bool
    public let completedAtUnixMilliseconds: Int64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        correlationID: UUID,
        deviceID: UUID,
        requestID: UUID,
        approvalID: UUID,
        interactiveSessionID: UUID?,
        reason: LocalInteractiveStopReasonV0,
        remoteAuthorityEnded: Bool,
        runtimeTeardownComplete: Bool,
        completedAtUnixMilliseconds: Int64
    ) throws {
        guard protocolVersion == .init() else {
            throw LocalAuthorityMessageErrorV0.invalidVersion
        }
        guard remoteAuthorityEnded, runtimeTeardownComplete else {
            throw LocalAuthorityMessageErrorV0.teardownIncomplete
        }
        guard completedAtUnixMilliseconds >= 0,
              completedAtUnixMilliseconds <= localAuthorityMaximumTime else {
            throw LocalAuthorityMessageErrorV0.invalidTime
        }
        self.protocolVersion = protocolVersion
        self.correlationID = correlationID
        self.deviceID = deviceID
        self.requestID = requestID
        self.approvalID = approvalID
        self.interactiveSessionID = interactiveSessionID
        self.reason = reason
        self.remoteAuthorityEnded = remoteAuthorityEnded
        self.runtimeTeardownComplete = runtimeTeardownComplete
        self.completedAtUnixMilliseconds = completedAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        try requireLocalAuthorityKeys(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue))
        )
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            protocolVersion: c.decode(LocalIPCProtocolVersion.self, forKey: .protocolVersion),
            correlationID: c.decode(UUID.self, forKey: .correlationID),
            deviceID: c.decode(UUID.self, forKey: .deviceID),
            requestID: c.decode(UUID.self, forKey: .requestID),
            approvalID: c.decode(UUID.self, forKey: .approvalID),
            interactiveSessionID: c.decodeIfPresent(UUID.self, forKey: .interactiveSessionID),
            reason: c.decode(LocalInteractiveStopReasonV0.self, forKey: .reason),
            remoteAuthorityEnded: c.decode(Bool.self, forKey: .remoteAuthorityEnded),
            runtimeTeardownComplete: c.decode(Bool.self, forKey: .runtimeTeardownComplete),
            completedAtUnixMilliseconds: c.decode(Int64.self, forKey: .completedAtUnixMilliseconds)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(protocolVersion, forKey: .protocolVersion)
        try c.encode(correlationID, forKey: .correlationID)
        try c.encode(deviceID, forKey: .deviceID)
        try c.encode(requestID, forKey: .requestID)
        try c.encode(approvalID, forKey: .approvalID)
        if let interactiveSessionID {
            try c.encode(interactiveSessionID, forKey: .interactiveSessionID)
        } else {
            try c.encodeNil(forKey: .interactiveSessionID)
        }
        try c.encode(reason, forKey: .reason)
        try c.encode(remoteAuthorityEnded, forKey: .remoteAuthorityEnded)
        try c.encode(runtimeTeardownComplete, forKey: .runtimeTeardownComplete)
        try c.encode(completedAtUnixMilliseconds, forKey: .completedAtUnixMilliseconds)
    }

    public func validate(against command: LocalInteractiveStopCommandV0) throws {
        guard correlationID == command.commandID,
              deviceID == command.deviceID,
              requestID == command.requestID,
              approvalID == command.approvalID,
              interactiveSessionID == command.interactiveSessionID,
              reason == command.reason,
              completedAtUnixMilliseconds >= command.occurredAtUnixMilliseconds else {
            throw LocalAuthorityMessageErrorV0.bindingMismatch
        }
    }
}
