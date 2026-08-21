import CompanionAuthentication
import CompanionDomain
import CompanionPersistence
import CompanionSecurity
import CompanionWire
import CryptoKit
import Foundation

public enum OperationAdmissionError: Error, Equatable, Sendable {
    case invalidInput
    case capabilityUnavailable
    case schemaRejected
    case deviceAuthorizationChanged
    case capabilityNotGranted
    case hostIdentityUnavailable
    case hostStateDenied
    case approvalRequired
    case approvalNotFound
    case approvalCapacityExceeded
}

public enum OperationAdmissionPreparationV0: Equatable, Sendable {
    case admitted(DurableOperationAdmissionResult)
    case approvalRequired(OperationApprovalChallengeV0)
}

public struct CompletedOperationApprovalV0: Equatable, Sendable {
    public let admission: DurableOperationAdmissionResult
    public let canonicalParametersJSON: Data

    public init(
        admission: DurableOperationAdmissionResult,
        canonicalParametersJSON: Data
    ) {
        self.admission = admission
        self.canonicalParametersJSON = canonicalParametersJSON
    }
}

public actor OperationAdmissionAuthorityV0 {
    public static let operationLifetimeMilliseconds: Int64 = 30_000

    private let store: SQLiteSecurityStore
    private let registryReader: any CapabilityRegistrySnapshotReadingV1
    private var pendingApprovals: [UUID: PendingApproval] = [:]

    private struct PreparedCandidate: Sendable {
        let record: StoredDurableOperationRecord
        let capability: CapabilityDescriptorV1
        let device: StoredDeviceRecord
        let hostFingerprint: Data
        let canonicalParametersJSON: Data
    }

    private struct PendingApproval: Sendable {
        var authority: OperationApprovalAuthorityV0
        let record: StoredDurableOperationRecord
        let primaryConnectionID: Data
        let deadlineMonotonicMilliseconds: UInt64
        let canonicalParametersJSON: Data
    }

    public init(
        store: SQLiteSecurityStore,
        registry: CapabilityRegistrySnapshotV1
    ) {
        self.store = store
        registryReader = FixedCapabilityRegistrySnapshotReaderV1(registry)
    }

    public init(
        store: SQLiteSecurityStore,
        registryReader: any CapabilityRegistrySnapshotReadingV1
    ) {
        self.store = store
        self.registryReader = registryReader
    }

    public func admitWithoutFreshApproval(
        operationID: UUID,
        parametersJSON: Data,
        capabilityID: String,
        principal: AuthenticatedDevicePrincipal,
        hostState: HostState,
        wallNowUnixMilliseconds: Int64,
        selectedVersion: WireVersion = .init()
    ) async throws -> DurableOperationAdmissionResult {
        let registry = await registryReader.registrySnapshot()
        if let existing = try await existingAdmissionIfMatching(
            operationID: operationID,
            parametersJSON: parametersJSON,
            capabilityID: capabilityID,
            principal: principal,
            selectedVersion: selectedVersion,
            registry: registry
        ) {
            return existing
        }
        let candidate = try await prepareCandidate(
            operationID: operationID,
            parametersJSON: parametersJSON,
            capabilityID: capabilityID,
            principal: principal,
            hostState: hostState,
            wallNowUnixMilliseconds: wallNowUnixMilliseconds,
            selectedVersion: selectedVersion,
            registry: registry
        )
        guard Self.allowsWithoutFreshApproval(candidate.capability.effects) else {
            throw OperationAdmissionError.approvalRequired
        }
        return try await admit(candidate.record)
    }

    public func prepareAdmission(
        operationID: UUID,
        parametersJSON: Data,
        capabilityID: String,
        principal: AuthenticatedDevicePrincipal,
        primaryConnectionID: Data,
        hostState: HostState,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64,
        selectedVersion: WireVersion = .init(),
        approvalID: UUID? = nil,
        serverChallenge: Data? = nil,
        registrySnapshot: CapabilityRegistrySnapshotV1? = nil
    ) async throws -> OperationAdmissionPreparationV0 {
        guard primaryConnectionID.count == 16,
              monotonicNowMilliseconds <= UInt64(Int64.max - Self.operationLifetimeMilliseconds) else {
            throw OperationAdmissionError.invalidInput
        }
        expireApprovals(monotonicNowMilliseconds: monotonicNowMilliseconds)
        let registry: CapabilityRegistrySnapshotV1
        if let registrySnapshot {
            registry = registrySnapshot
        } else {
            registry = await registryReader.registrySnapshot()
        }
        let existing = pendingApprovals.values.first {
            $0.record.operationID == operationID
        }
        if existing == nil,
           let durable = try await existingAdmissionIfMatching(
               operationID: operationID,
               parametersJSON: parametersJSON,
               capabilityID: capabilityID,
               principal: principal,
               selectedVersion: selectedVersion,
               registry: registry
           ) {
            return .admitted(durable)
        }
        let candidate = try await prepareCandidate(
            operationID: operationID,
            parametersJSON: parametersJSON,
            capabilityID: capabilityID,
            principal: principal,
            hostState: hostState,
            wallNowUnixMilliseconds: existing?.record.createdAtUnixMilliseconds
                ?? wallNowUnixMilliseconds,
            selectedVersion: selectedVersion,
            registry: registry
        )
        if let existing {
            guard existing.record.requestDigest == candidate.record.requestDigest,
                  existing.primaryConnectionID == primaryConnectionID else {
                throw SecurityStoreError.operationIDConflict(operationID)
            }
            return .approvalRequired(existing.authority.challenge)
        }
        if Self.allowsWithoutFreshApproval(candidate.capability.effects) {
            return .admitted(try await admit(candidate.record))
        }
        guard pendingApprovals.count < 128 else {
            throw OperationAdmissionError.approvalCapacityExceeded
        }
        let approvalID = approvalID ?? UUID()
        guard pendingApprovals[approvalID] == nil else {
            throw OperationAdmissionError.invalidInput
        }
        let challengeBytes = serverChallenge ?? Self.randomBytes(count: 32)
        let expiresAt = UInt64(candidate.record.expiresAtUnixMilliseconds)
        let monotonicExpiry = monotonicNowMilliseconds
            + UInt64(Self.operationLifetimeMilliseconds)
        let authority = try OperationApprovalAuthorityV0(
            hostFingerprint: candidate.hostFingerprint,
            clientID: candidate.record.clientID,
            primaryConnectionID: primaryConnectionID,
            approvalID: approvalID,
            operationDigest: candidate.record.requestDigest,
            serverChallenge: challengeBytes,
            authorizationEpoch: candidate.record.authorizationEpoch,
            grantRevision: candidate.record.grantRevision,
            policyRevision: candidate.record.policyRevision,
            providerGeneration: candidate.record.providerGeneration,
            executionRevision: candidate.record.executionRevision,
            issuedAtUnixMilliseconds: UInt64(wallNowUnixMilliseconds),
            expiresAtUnixMilliseconds: expiresAt,
            selectedMajor: selectedVersion.major,
            selectedMinor: selectedVersion.minor,
            approvalPublicKeyX963: candidate.device.approvalPublicKeyX963,
            issuedAtMonotonicMilliseconds: monotonicNowMilliseconds,
            expiresAtMonotonicMilliseconds: monotonicExpiry
        )
        pendingApprovals[approvalID] = PendingApproval(
            authority: authority,
            record: candidate.record,
            primaryConnectionID: primaryConnectionID,
            deadlineMonotonicMilliseconds: monotonicExpiry,
            canonicalParametersJSON: candidate.canonicalParametersJSON
        )
        return .approvalRequired(authority.challenge)
    }

    public func completeApproval(
        approvalID: UUID,
        rawSignature: Data,
        primaryConnectionID: Data,
        monotonicNowMilliseconds: UInt64,
        registrySnapshot: CapabilityRegistrySnapshotV1? = nil
    ) async throws -> DurableOperationAdmissionResult {
        try await completeApprovalForExecution(
            approvalID: approvalID,
            rawSignature: rawSignature,
            primaryConnectionID: primaryConnectionID,
            monotonicNowMilliseconds: monotonicNowMilliseconds,
            registrySnapshot: registrySnapshot
        ).admission
    }

    public func completeApprovalForExecution(
        approvalID: UUID,
        rawSignature: Data,
        primaryConnectionID: Data,
        monotonicNowMilliseconds: UInt64,
        registrySnapshot: CapabilityRegistrySnapshotV1? = nil
    ) async throws -> CompletedOperationApprovalV0 {
        guard var pending = pendingApprovals.removeValue(forKey: approvalID) else {
            throw OperationAdmissionError.approvalNotFound
        }
        let registry: CapabilityRegistrySnapshotV1
        if let registrySnapshot {
            registry = registrySnapshot
        } else {
            registry = await registryReader.registrySnapshot()
        }
        guard let capability = registry.capability(pending.record.capabilityID),
              capability.providerGeneration == pending.record.providerGeneration,
              capability.executionRevision == pending.record.executionRevision,
              capability.schemaVersion == pending.record.schemaVersion else {
            throw OperationAdmissionError.capabilityUnavailable
        }
        guard let current = try await store.device(pending.record.deviceID),
              current.clientID == pending.record.clientID,
              current.authorization.state == .activeGranted else {
            throw OperationAdmissionError.deviceAuthorizationChanged
        }
        let grants = try await store.deviceGrants(pending.record.deviceID)
        guard grants.capabilityIDs.contains(pending.record.capabilityID) else {
            throw OperationAdmissionError.capabilityNotGranted
        }
        _ = try pending.authority.verifyAndConsume(
            rawSignature: rawSignature,
            current: OperationApprovalCurrentStateV0(
                clientID: current.clientID,
                primaryConnectionID: primaryConnectionID,
                authorizationEpoch: current.authorization.authorizationEpoch.rawValue,
                grantRevision: current.authorization.grantRevision.rawValue,
                policyRevision: current.policyRevision.rawValue,
                providerGeneration: capability.providerGeneration,
                executionRevision: capability.executionRevision,
                approvalPublicKeyX963: current.approvalPublicKeyX963
            ),
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
        return CompletedOperationApprovalV0(
            admission: try await admit(pending.record),
            canonicalParametersJSON: pending.canonicalParametersJSON
        )
    }

    private func prepareCandidate(
        operationID: UUID,
        parametersJSON: Data,
        capabilityID: String,
        principal: AuthenticatedDevicePrincipal,
        hostState: HostState,
        wallNowUnixMilliseconds: Int64,
        selectedVersion: WireVersion,
        registry: CapabilityRegistrySnapshotV1
    ) async throws -> PreparedCandidate {
        guard wallNowUnixMilliseconds >= 0,
              wallNowUnixMilliseconds <= WireLimits.maximumSafeInteger
                - Self.operationLifetimeMilliseconds,
              selectedVersion.major == 0,
              selectedVersion.minor == 1 else {
            throw OperationAdmissionError.invalidInput
        }
        guard let capability = registry.capability(capabilityID) else {
            throw OperationAdmissionError.capabilityUnavailable
        }
        let value: CanonicalJSONValue
        let canonicalParameters: Data
        do {
            value = try CanonicalJSON.parse(parametersJSON)
            try capability.parameterSchema.validate(value)
            canonicalParameters = CanonicalJSON.canonicalData(for: value)
        } catch {
            throw OperationAdmissionError.schemaRejected
        }
        guard Self.isEligible(hostState, for: capability.effects) else {
            throw OperationAdmissionError.hostStateDenied
        }
        guard let hostIdentity = try await store.hostIdentity(),
              hostIdentity.state == .ready else {
            throw OperationAdmissionError.hostIdentityUnavailable
        }
        guard let current = try await store.device(principal.deviceID),
              current.clientID == principal.clientID,
              current.authorization.state == .activeGranted,
              current.authorization.state == principal.deviceState,
              current.authorization.authorizationEpoch == principal.authorizationEpoch,
              current.authorization.grantRevision == principal.grantRevision,
              current.policyRevision == principal.policyRevision else {
            throw OperationAdmissionError.deviceAuthorizationChanged
        }
        let grants = try await store.deviceGrants(principal.deviceID)
        guard grants.capabilityIDs.contains(capabilityID) else {
            throw OperationAdmissionError.capabilityNotGranted
        }
        let expiresAt = wallNowUnixMilliseconds
            + Self.operationLifetimeMilliseconds
        let parametersDigest = Data(SHA256.hash(data: canonicalParameters))
        let binding: Data
        do {
            binding = try CompanionSecurityV0.operationDigestInput(
                hostID: hostIdentity.hostID,
                deviceID: principal.deviceID,
                clientID: principal.clientID,
                operationID: operationID,
                capabilityID: capability.capabilityID,
                schemaVersion: capability.schemaVersion,
                providerID: capability.providerID,
                providerVersion: capability.providerVersion,
                providerGeneration: capability.providerGeneration,
                executionRevision: capability.executionRevision,
                canonicalParametersSHA256: parametersDigest,
                effects: capability.effects,
                requiredHostState: hostState,
                authorizationEpoch: principal.authorizationEpoch.rawValue,
                grantRevision: principal.grantRevision.rawValue,
                policyRevision: principal.policyRevision.rawValue,
                expiresAtUnixMilliseconds: UInt64(expiresAt),
                selectedMajor: selectedVersion.major,
                selectedMinor: selectedVersion.minor
            )
        } catch {
            throw OperationAdmissionError.invalidInput
        }
        let record = try StoredDurableOperationRecord(
            operationID: operationID,
            deviceID: principal.deviceID,
            clientID: principal.clientID,
            requestDigest: CompanionSecurityV0.operationDigest(binding),
            state: .queued,
            capabilityID: capability.capabilityID,
            schemaVersion: capability.schemaVersion,
            providerID: capability.providerID,
            providerVersion: capability.providerVersion,
            providerGeneration: capability.providerGeneration,
            executionRevision: capability.executionRevision,
            authorizationEpoch: principal.authorizationEpoch.rawValue,
            grantRevision: principal.grantRevision.rawValue,
            policyRevision: principal.policyRevision.rawValue,
            requiredHostState: hostState,
            expiresAtUnixMilliseconds: expiresAt,
            createdAtUnixMilliseconds: wallNowUnixMilliseconds,
            updatedAtUnixMilliseconds: wallNowUnixMilliseconds
        )
        return PreparedCandidate(
            record: record,
            capability: capability,
            device: current,
            hostFingerprint: hostIdentity.hostFingerprint,
            canonicalParametersJSON: canonicalParameters
        )
    }

    private func existingAdmissionIfMatching(
        operationID: UUID,
        parametersJSON: Data,
        capabilityID: String,
        principal: AuthenticatedDevicePrincipal,
        selectedVersion: WireVersion,
        registry: CapabilityRegistrySnapshotV1
    ) async throws -> DurableOperationAdmissionResult? {
        guard let existing = try await store.durableOperation(operationID) else {
            return nil
        }
        guard selectedVersion.major == 0, selectedVersion.minor == 1,
              existing.deviceID == principal.deviceID,
              existing.clientID == principal.clientID,
              existing.capabilityID == capabilityID,
              let capability = registry.capability(capabilityID),
              capability.schemaVersion == existing.schemaVersion,
              capability.providerID == existing.providerID,
              capability.providerVersion == existing.providerVersion,
              capability.providerGeneration == existing.providerGeneration,
              capability.executionRevision == existing.executionRevision,
              let hostIdentity = try await store.hostIdentity(),
              hostIdentity.state == .ready else {
            throw SecurityStoreError.operationIDConflict(operationID)
        }
        let canonicalParameters: Data
        do {
            let value = try CanonicalJSON.parse(parametersJSON)
            try capability.parameterSchema.validate(value)
            canonicalParameters = CanonicalJSON.canonicalData(for: value)
        } catch {
            throw SecurityStoreError.operationIDConflict(operationID)
        }
        let parametersDigest = Data(SHA256.hash(data: canonicalParameters))
        let binding: Data
        do {
            binding = try CompanionSecurityV0.operationDigestInput(
                hostID: hostIdentity.hostID,
                deviceID: existing.deviceID,
                clientID: existing.clientID,
                operationID: existing.operationID,
                capabilityID: existing.capabilityID,
                schemaVersion: existing.schemaVersion,
                providerID: existing.providerID,
                providerVersion: existing.providerVersion,
                providerGeneration: existing.providerGeneration,
                executionRevision: existing.executionRevision,
                canonicalParametersSHA256: parametersDigest,
                effects: capability.effects,
                requiredHostState: existing.requiredHostState,
                authorizationEpoch: existing.authorizationEpoch,
                grantRevision: existing.grantRevision,
                policyRevision: existing.policyRevision,
                expiresAtUnixMilliseconds: UInt64(
                    existing.expiresAtUnixMilliseconds
                ),
                selectedMajor: selectedVersion.major,
                selectedMinor: selectedVersion.minor
            )
        } catch {
            throw SecurityStoreError.operationIDConflict(operationID)
        }
        guard CompanionSecurityV0.operationDigest(binding)
                == existing.requestDigest else {
            throw SecurityStoreError.operationIDConflict(operationID)
        }
        return .existing(existing)
    }

    private func admit(
        _ record: StoredDurableOperationRecord
    ) async throws -> DurableOperationAdmissionResult {
        do {
            return try await store.admitDurableOperation(record)
        } catch SecurityStoreError.operationAuthorizationStale(_) {
            throw OperationAdmissionError.deviceAuthorizationChanged
        } catch SecurityStoreError.operationCapabilityNotGranted(_, _) {
            throw OperationAdmissionError.capabilityNotGranted
        }
    }

    private func expireApprovals(monotonicNowMilliseconds: UInt64) {
        pendingApprovals = pendingApprovals.filter {
            monotonicNowMilliseconds < $0.value.deadlineMonotonicMilliseconds
        }
    }

    private static func randomBytes(count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in
            UInt8.random(in: .min ... .max, using: &generator)
        })
    }

    private static func allowsWithoutFreshApproval(
        _ effects: CapabilityEffectFacts
    ) -> Bool {
        guard effects.dataAccess == .none
                || effects.dataAccess == .publicData else {
            return false
        }
        return effects.changesLocalState != .irreversible
            && !effects.mayDisruptUser
            && !effects.invokesExternalService
            && !effects.usesCredentials
            && !effects.destructive
            && !effects.requiresForegroundSession
    }

    private static func isEligible(
        _ hostState: HostState,
        for effects: CapabilityEffectFacts
    ) -> Bool {
        switch hostState {
        case .userSessionActive:
            true
        case .userSessionLocked:
            effects.allowedWhileLocked
        case .otherConsoleUserActive,
             .serviceStoppingForLogout,
             .hostPreparingForSleep:
            false
        }
    }
}
