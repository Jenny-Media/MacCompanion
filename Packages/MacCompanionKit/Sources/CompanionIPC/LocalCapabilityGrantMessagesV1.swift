import CompanionDomain
import CompanionWire
import Foundation

public enum LocalCapabilityGrantMessageErrorV1: Error, Equatable, Sendable {
    case invalidMessage
    case bindingMismatch
}

private enum CapabilityGrantValidation {
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    static let maximumTime: Int64 = 9_007_199_254_740_991
    static let lifetime: Int64 = 300_000

    static func require(_ condition: Bool) throws {
        guard condition else { throw LocalCapabilityGrantMessageErrorV1.invalidMessage }
    }

    static func keys(_ decoder: Decoder, _ expected: [String]) throws {
        let container = try decoder.container(keyedBy: Key.self)
        try require(Set(container.allKeys.map(\.stringValue)) == Set(expected))
    }

    private struct Key: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

public struct LocalCapabilityGrantReviewRequestV1: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, commandID, deviceID, capabilityID, requestedAtUnixMilliseconds
    }
    public let protocolVersion: LocalIPCProtocolVersion
    public let commandID: UUID
    public let deviceID: UUID
    public let capabilityID: String
    public let requestedAtUnixMilliseconds: Int64

    public init(protocolVersion: LocalIPCProtocolVersion = .init(), commandID: UUID,
                deviceID: UUID, capabilityID: String, requestedAtUnixMilliseconds: Int64) throws {
        try CapabilityGrantValidation.require(protocolVersion == .init()
            && commandID != CapabilityGrantValidation.zero && deviceID != CapabilityGrantValidation.zero
            && commandID != deviceID && capabilityID != InteractiveControlDurableGrantV0.identifier
            && requestedAtUnixMilliseconds >= 0
            && requestedAtUnixMilliseconds <= CapabilityGrantValidation.maximumTime - CapabilityGrantValidation.lifetime)
        _ = try CapabilityGrantSet([capabilityID])
        self.protocolVersion = protocolVersion
        self.commandID = commandID
        self.deviceID = deviceID
        self.capabilityID = capabilityID
        self.requestedAtUnixMilliseconds = requestedAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        try CapabilityGrantValidation.keys(decoder, CodingKeys.allCases.map(\.stringValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(protocolVersion: c.decode(LocalIPCProtocolVersion.self, forKey: .protocolVersion),
            commandID: c.decode(UUID.self, forKey: .commandID), deviceID: c.decode(UUID.self, forKey: .deviceID),
            capabilityID: c.decode(String.self, forKey: .capabilityID),
            requestedAtUnixMilliseconds: c.decode(Int64.self, forKey: .requestedAtUnixMilliseconds))
    }
}

/// Retains all provider and effect facts, without inventing a second schema codec.
public struct LocalCapabilityGrantDescriptorV1: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case capability, providerID, providerVersion, providerGeneration, executionRevision
    }
    public let capability: CapabilityDiscoveryDescriptorV1
    public let providerID: String
    public let providerVersion: String
    public let providerGeneration: UUID
    public let executionRevision: UUID

    public init(_ descriptor: CapabilityDescriptorV1) throws {
        capability = try CapabilityDiscoveryDescriptorV1(descriptor)
        providerID = descriptor.providerID
        providerVersion = descriptor.providerVersion
        providerGeneration = descriptor.providerGeneration
        executionRevision = descriptor.executionRevision
    }

    public init(from decoder: Decoder) throws {
        try CapabilityGrantValidation.keys(decoder, CodingKeys.allCases.map(\.stringValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let capability = try c.decode(CapabilityDiscoveryDescriptorV1.self, forKey: .capability)
        // CanonicalJSONValue stores object members in an array; JSONDecoder
        // does not promise an allKeys order. Rebuild through the domain schema
        // so identical signed review retries have identical value semantics.
        try self.init(CapabilityDescriptorV1(capabilityID: capability.capabilityID, schemaVersion: capability.schemaVersion,
            providerID: c.decode(String.self, forKey: .providerID), providerVersion: c.decode(String.self, forKey: .providerVersion),
            providerGeneration: c.decode(UUID.self, forKey: .providerGeneration), executionRevision: c.decode(UUID.self, forKey: .executionRevision),
            englishTitle: capability.englishTitle, englishSummary: capability.englishSummary,
            parameterSchema: CapabilitySchemaV1(wireValue: capability.parameterSchema),
            resultSchema: CapabilitySchemaV1(wireValue: capability.resultSchema), effects: capability.effects.domainValue()))
    }

    public func domainValue() throws -> CapabilityDescriptorV1 {
        try CapabilityDescriptorV1(capabilityID: capability.capabilityID, schemaVersion: capability.schemaVersion,
            providerID: providerID, providerVersion: providerVersion, providerGeneration: providerGeneration,
            executionRevision: executionRevision, englishTitle: capability.englishTitle,
            englishSummary: capability.englishSummary,
            parameterSchema: CapabilitySchemaV1(wireValue: capability.parameterSchema),
            resultSchema: CapabilitySchemaV1(wireValue: capability.resultSchema), effects: capability.effects.domainValue())
    }
}

public struct LocalCapabilityGrantReviewV1: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, correlationID, reviewID, deviceID, deviceDisplayName
        case authorizationEpoch, grantRevision, policyRevision, currentGrantIDs
        case registryGeneration, descriptor, createdAtUnixMilliseconds, expiresAtUnixMilliseconds
    }
    public static let lifetimeMilliseconds: Int64 = 300_000
    public let protocolVersion: LocalIPCProtocolVersion
    public let correlationID: UUID
    public let reviewID: UUID
    public let deviceID: UUID
    public let deviceDisplayName: DeviceDisplayName
    public let authorizationEpoch: AuthorizationEpoch
    public let grantRevision: GrantRevision
    public let policyRevision: PolicyRevision
    public let currentGrantIDs: [String]
    public let registryGeneration: UUID
    public let descriptor: LocalCapabilityGrantDescriptorV1
    public let createdAtUnixMilliseconds: Int64
    public let expiresAtUnixMilliseconds: Int64

    public init(protocolVersion: LocalIPCProtocolVersion = .init(), correlationID: UUID, reviewID: UUID,
                deviceID: UUID, deviceDisplayName: DeviceDisplayName, authorizationEpoch: AuthorizationEpoch,
                grantRevision: GrantRevision, policyRevision: PolicyRevision, currentGrantIDs: [String],
                registryGeneration: UUID, descriptor: LocalCapabilityGrantDescriptorV1,
                createdAtUnixMilliseconds: Int64, expiresAtUnixMilliseconds: Int64) throws {
        let grants = try CapabilityGrantSet(currentGrantIDs)
        let capability = try descriptor.domainValue()
        _ = try CapabilityGrantSet(currentGrantIDs + [capability.capabilityID])
        try CapabilityGrantValidation.require(protocolVersion == .init()
            && ![correlationID, reviewID, deviceID, registryGeneration].contains(CapabilityGrantValidation.zero)
            && Set([correlationID, reviewID, deviceID]).count == 3
            && authorizationEpoch.rawValue >= 1 && grantRevision.rawValue >= 1 && policyRevision.rawValue >= 1
            && grants.capabilityIDs == currentGrantIDs && !currentGrantIDs.contains(capability.capabilityID)
            && capability.capabilityID != InteractiveControlDurableGrantV0.identifier
            && createdAtUnixMilliseconds >= 0
            && createdAtUnixMilliseconds <= CapabilityGrantValidation.maximumTime - Self.lifetimeMilliseconds)
        try CapabilityGrantValidation.require(expiresAtUnixMilliseconds == createdAtUnixMilliseconds + Self.lifetimeMilliseconds)
        self.protocolVersion = protocolVersion
        self.correlationID = correlationID
        self.reviewID = reviewID
        self.deviceID = deviceID
        self.deviceDisplayName = deviceDisplayName
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.policyRevision = policyRevision
        self.currentGrantIDs = currentGrantIDs
        self.registryGeneration = registryGeneration
        self.descriptor = descriptor
        self.createdAtUnixMilliseconds = createdAtUnixMilliseconds
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        try CapabilityGrantValidation.keys(decoder, CodingKeys.allCases.map(\.stringValue))
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(protocolVersion: c.decode(LocalIPCProtocolVersion.self, forKey: .protocolVersion),
            correlationID: c.decode(UUID.self, forKey: .correlationID), reviewID: c.decode(UUID.self, forKey: .reviewID),
            deviceID: c.decode(UUID.self, forKey: .deviceID), deviceDisplayName: c.decode(DeviceDisplayName.self, forKey: .deviceDisplayName),
            authorizationEpoch: c.decode(AuthorizationEpoch.self, forKey: .authorizationEpoch),
            grantRevision: c.decode(GrantRevision.self, forKey: .grantRevision), policyRevision: c.decode(PolicyRevision.self, forKey: .policyRevision),
            currentGrantIDs: c.decode([String].self, forKey: .currentGrantIDs), registryGeneration: c.decode(UUID.self, forKey: .registryGeneration),
            descriptor: c.decode(LocalCapabilityGrantDescriptorV1.self, forKey: .descriptor),
            createdAtUnixMilliseconds: c.decode(Int64.self, forKey: .createdAtUnixMilliseconds),
            expiresAtUnixMilliseconds: c.decode(Int64.self, forKey: .expiresAtUnixMilliseconds))
    }

    public func validate(against request: LocalCapabilityGrantReviewRequestV1) throws {
        guard correlationID == request.commandID, deviceID == request.deviceID,
              descriptor.capability.capabilityID == request.capabilityID,
              createdAtUnixMilliseconds >= request.requestedAtUnixMilliseconds else {
            throw LocalCapabilityGrantMessageErrorV1.bindingMismatch
        }
    }

    public func command(commandID: UUID, decision: LocalGrantDecisionV0, decidedAtUnixMilliseconds: Int64) throws -> LocalGrantDecisionCommandV0 {
        try LocalGrantDecisionCommandV0(commandID: commandID, reviewID: reviewID, deviceID: deviceID,
            deviceDisplayName: deviceDisplayName, decision: decision, expectedAuthorizationEpoch: authorizationEpoch,
            expectedGrantRevision: grantRevision, expectedPolicyRevision: policyRevision,
            expectedCurrentGrants: CapabilityGrantSet(currentGrantIDs),
            proposedGrants: CapabilityGrantSet(currentGrantIDs + [descriptor.capability.capabilityID]),
            decidedAtUnixMilliseconds: decidedAtUnixMilliseconds)
    }
}

public struct LocalCapabilityGrantDecisionCommandV1: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey { case kind, decision }
    public let kind: String
    public let decision: LocalGrantDecisionCommandV0
    public init(decision: LocalGrantDecisionCommandV0) {
        kind = "capabilityGrantDecision"
        self.decision = decision
    }
    public init(from decoder: Decoder) throws {
        try CapabilityGrantValidation.keys(decoder, ["kind", "decision"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try CapabilityGrantValidation.require(c.decode(String.self, forKey: .kind) == "capabilityGrantDecision")
        self.init(decision: try c.decode(LocalGrantDecisionCommandV0.self, forKey: .decision))
    }
}
