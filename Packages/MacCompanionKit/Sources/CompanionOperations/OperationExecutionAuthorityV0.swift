import CompanionDomain
import CompanionPersistence
import CompanionSecurity
import CompanionWire
import CryptoKit
import Foundation

public struct CapabilityProviderIdentityV1: Equatable, Sendable {
    public let providerID: String
    public let providerVersion: String
    public let providerGeneration: UUID
    public let executionRevision: UUID

    public init(
        providerID: String,
        providerVersion: String,
        providerGeneration: UUID,
        executionRevision: UUID
    ) {
        self.providerID = providerID
        self.providerVersion = providerVersion
        self.providerGeneration = providerGeneration
        self.executionRevision = executionRevision
    }
}

public struct CapabilityProviderRequestV1: Equatable, Sendable {
    public let operationID: UUID
    public let capabilityID: String
    public let parameters: CanonicalJSONValue
    public let expiresAtUnixMilliseconds: Int64

    public init(
        operationID: UUID,
        capabilityID: String,
        parameters: CanonicalJSONValue,
        expiresAtUnixMilliseconds: Int64
    ) {
        self.operationID = operationID
        self.capabilityID = capabilityID
        self.parameters = parameters
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
    }
}

public enum CapabilityProviderFailureCodeV1: String, CaseIterable, Sendable {
    case unavailable = "provider.unavailable"
    case permissionDenied = "provider.permissionDenied"
    case rejected = "provider.rejected"
    case timedOut = "provider.timedOut"
    case executionFailed = "provider.executionFailed"
}

public enum CapabilityProviderOutcomeV1: Equatable, Sendable {
    case succeeded(resultJSON: Data)
    case failed(CapabilityProviderFailureCodeV1)
    case cancelled
    case outcomeUnknown
}

public enum CapabilityProviderDeadlineResultV1: Equatable, Sendable {
    case completed(CapabilityProviderOutcomeV1)
    case deadlineExceeded
}

public protocol CapabilityProviderDeadlineRunningV1: Sendable {
    func run(
        timeoutMilliseconds: UInt64,
        operation: @escaping @Sendable () async -> CapabilityProviderOutcomeV1
    ) async -> CapabilityProviderDeadlineResultV1
}

public struct SystemCapabilityProviderDeadlineRunnerV1:
    CapabilityProviderDeadlineRunningV1 {
    public init() {}

    public func run(
        timeoutMilliseconds: UInt64,
        operation: @escaping @Sendable () async -> CapabilityProviderOutcomeV1
    ) async -> CapabilityProviderDeadlineResultV1 {
        let latch = ProviderDeadlineLatchV1()
        let providerTask = Task {
            let outcome = await operation()
            await latch.resolve(.completed(outcome))
        }
        let timeoutTask = Task {
            do {
                let (nanoseconds, overflow) = timeoutMilliseconds.multipliedReportingOverflow(
                    by: 1_000_000
                )
                guard !overflow else {
                    await latch.resolve(.deadlineExceeded)
                    return
                }
                try await Task.sleep(nanoseconds: nanoseconds)
                await latch.resolve(.deadlineExceeded)
            } catch {
                return
            }
        }
        let result = await latch.wait()
        switch result {
        case .completed:
            timeoutTask.cancel()
        case .deadlineExceeded:
            providerTask.cancel()
        }
        return result
    }
}

private actor ProviderDeadlineLatchV1 {
    private var result: CapabilityProviderDeadlineResultV1?
    private var waiters: [
        CheckedContinuation<CapabilityProviderDeadlineResultV1, Never>
    ] = []

    func resolve(_ candidate: CapabilityProviderDeadlineResultV1) {
        guard result == nil else { return }
        result = candidate
        let pending = waiters
        waiters.removeAll(keepingCapacity: false)
        for waiter in pending { waiter.resume(returning: candidate) }
    }

    func wait() async -> CapabilityProviderDeadlineResultV1 {
        if let result { return result }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

public protocol CapabilityProviderV1: Sendable {
    var identity: CapabilityProviderIdentityV1 { get }
    func execute(
        _ request: CapabilityProviderRequestV1
    ) async -> CapabilityProviderOutcomeV1
    func requestCancellation(operationID: UUID) async -> Bool
}

public extension CapabilityProviderV1 {
    func requestCancellation(operationID: UUID) async -> Bool { false }
}

public enum OperationExecutionError: Error, Equatable, Sendable {
    case operationNotFound
    case operationNotQueued(OperationState)
    case capabilityUnavailable
    case providerIdentityMismatch
    case requestBindingMismatch
    case hostIdentityUnavailable
}

public enum OperationExecutionResultV0: Equatable, Sendable {
    case succeeded(
        record: StoredDurableOperationRecord,
        canonicalResultJSON: Data
    )
    case failed(
        record: StoredDurableOperationRecord,
        code: String
    )
    case cancelled(StoredDurableOperationRecord)
    case outcomeUnknown(StoredDurableOperationRecord)
    case alreadyTerminal(StoredDurableOperationRecord)
}

public enum OperationCancellationResultV0: Equatable, Sendable {
    case cancelled(StoredDurableOperationRecord)
    case requested(
        record: StoredDurableOperationRecord,
        providerAccepted: Bool
    )
    case alreadyRequested(StoredDurableOperationRecord)
    case alreadyTerminal(StoredDurableOperationRecord)
}

public actor OperationExecutionAuthorityV0 {
    private let store: SQLiteSecurityStore
    private let deadlineRunner: any CapabilityProviderDeadlineRunningV1
    private let auditWriter: (any OperationAuditWritingV0)?
    private let registryReader: any CapabilityRegistrySnapshotReadingV1
    private let publicationReader:
        (any CapabilityRegistryPublicationReadingV1)?
    private var inFlightProviders: [UUID: any CapabilityProviderV1] = [:]

    public init(
        store: SQLiteSecurityStore,
        registry: CapabilityRegistrySnapshotV1,
        deadlineRunner: any CapabilityProviderDeadlineRunningV1 =
            SystemCapabilityProviderDeadlineRunnerV1(),
        auditWriter: (any OperationAuditWritingV0)? = nil
    ) {
        self.store = store
        registryReader = FixedCapabilityRegistrySnapshotReaderV1(registry)
        publicationReader = nil
        self.deadlineRunner = deadlineRunner
        self.auditWriter = auditWriter
    }

    public init(
        store: SQLiteSecurityStore,
        registryReader: any CapabilityRegistrySnapshotReadingV1,
        deadlineRunner: any CapabilityProviderDeadlineRunningV1 =
            SystemCapabilityProviderDeadlineRunnerV1(),
        auditWriter: (any OperationAuditWritingV0)? = nil
    ) {
        self.store = store
        self.registryReader = registryReader
        publicationReader = registryReader
            as? any CapabilityRegistryPublicationReadingV1
        self.deadlineRunner = deadlineRunner
        self.auditWriter = auditWriter
    }

    public init(
        store: SQLiteSecurityStore,
        publicationReader: any CapabilityRegistryPublicationReadingV1,
        deadlineRunner: any CapabilityProviderDeadlineRunningV1 =
            SystemCapabilityProviderDeadlineRunnerV1(),
        auditWriter: (any OperationAuditWritingV0)? = nil
    ) {
        self.store = store
        registryReader = publicationReader
        self.publicationReader = publicationReader
        self.deadlineRunner = deadlineRunner
        self.auditWriter = auditWriter
    }

    public func execute(
        operationID: UUID,
        parametersJSON: Data,
        hostState: HostState,
        wallNowUnixMilliseconds: Int64,
        provider: any CapabilityProviderV1
    ) async throws -> OperationExecutionResultV0 {
        let registry = await registryReader.registrySnapshot()
        return try await execute(
            operationID: operationID,
            parametersJSON: parametersJSON,
            hostState: hostState,
            wallNowUnixMilliseconds: wallNowUnixMilliseconds,
            registry: registry,
            provider: provider
        )
    }

    /// Release-composition entry point. The provider and descriptor come from
    /// one retained publication snapshot, so replacement cannot retarget the
    /// command between registry validation and provider invocation.
    public func execute(
        operationID: UUID,
        parametersJSON: Data,
        hostState: HostState,
        wallNowUnixMilliseconds: Int64
    ) async throws -> OperationExecutionResultV0 {
        guard let publicationReader else {
            throw OperationExecutionError.capabilityUnavailable
        }
        let publication = await publicationReader.publicationSnapshot()
        return try await execute(
            operationID: operationID,
            parametersJSON: parametersJSON,
            hostState: hostState,
            wallNowUnixMilliseconds: wallNowUnixMilliseconds,
            publication: publication
        )
    }

    public func execute(
        operationID: UUID,
        parametersJSON: Data,
        hostState: HostState,
        wallNowUnixMilliseconds: Int64,
        publication: CapabilityRegistryPublicationV1
    ) async throws -> OperationExecutionResultV0 {
        guard let operation = try await store.durableOperation(operationID),
              let provider = publication.provider(
                forCapabilityID: operation.capabilityID
              ) else {
            throw OperationExecutionError.capabilityUnavailable
        }
        return try await execute(
            operationID: operationID,
            parametersJSON: parametersJSON,
            hostState: hostState,
            wallNowUnixMilliseconds: wallNowUnixMilliseconds,
            registry: publication.registry,
            provider: provider
        )
    }

    private func execute(
        operationID: UUID,
        parametersJSON: Data,
        hostState: HostState,
        wallNowUnixMilliseconds: Int64,
        registry: CapabilityRegistrySnapshotV1,
        provider: any CapabilityProviderV1
    ) async throws -> OperationExecutionResultV0 {
        guard let operation = try await store.durableOperation(operationID) else {
            throw OperationExecutionError.operationNotFound
        }
        if operation.state.isTerminal {
            await auditWriter?.recordTerminal(operation)
            return .alreadyTerminal(operation)
        }
        guard operation.state == .queued else {
            throw OperationExecutionError.operationNotQueued(operation.state)
        }
        guard let capability = registry.capability(operation.capabilityID),
              Self.matches(operation, capability: capability) else {
            throw OperationExecutionError.capabilityUnavailable
        }
        let expectedProvider = CapabilityProviderIdentityV1(
            providerID: capability.providerID,
            providerVersion: capability.providerVersion,
            providerGeneration: capability.providerGeneration,
            executionRevision: capability.executionRevision
        )
        guard provider.identity == expectedProvider else {
            throw OperationExecutionError.providerIdentityMismatch
        }
        guard let hostIdentity = try await store.hostIdentity(),
              hostIdentity.state == .ready else {
            throw OperationExecutionError.hostIdentityUnavailable
        }

        let parameters: CanonicalJSONValue
        let canonicalParameters: Data
        do {
            parameters = try CanonicalJSON.parse(parametersJSON)
            try capability.parameterSchema.validate(parameters)
            canonicalParameters = CanonicalJSON.canonicalData(for: parameters)
        } catch {
            throw OperationExecutionError.requestBindingMismatch
        }
        let parametersDigest = Data(SHA256.hash(data: canonicalParameters))
        let binding = try CompanionSecurityV0.operationDigestInput(
            hostID: hostIdentity.hostID,
            deviceID: operation.deviceID,
            clientID: operation.clientID,
            operationID: operation.operationID,
            capabilityID: operation.capabilityID,
            schemaVersion: operation.schemaVersion,
            providerID: operation.providerID,
            providerVersion: operation.providerVersion,
            providerGeneration: operation.providerGeneration,
            executionRevision: operation.executionRevision,
            canonicalParametersSHA256: parametersDigest,
            effects: capability.effects,
            requiredHostState: operation.requiredHostState,
            authorizationEpoch: operation.authorizationEpoch,
            grantRevision: operation.grantRevision,
            policyRevision: operation.policyRevision,
            expiresAtUnixMilliseconds: UInt64(operation.expiresAtUnixMilliseconds),
            selectedMajor: 0,
            selectedMinor: 1
        )
        guard CompanionSecurityV0.operationDigest(binding)
                == operation.requestDigest else {
            throw OperationExecutionError.requestBindingMismatch
        }

        let claim = try await store.claimDurableOperationExecution(
            operationID,
            snapshot: DurableOperationExecutionSnapshot(
                providerGeneration: capability.providerGeneration,
                executionRevision: capability.executionRevision,
                hostState: hostState,
                nowUnixMilliseconds: wallNowUnixMilliseconds
            )
        )
        switch claim {
        case let .failed(record):
            await auditWriter?.recordTerminal(record)
            return .failed(
                record: record,
                code: record.terminalCode ?? "operation.authorizationRevoked"
            )
        case let .claimed(record):
            do {
                try await auditWriter?.recordRequiredExecutionStart(record)
            } catch {
                let failed = try await store.transitionDurableOperation(
                    operationID,
                    to: .failed,
                    occurredAtUnixMilliseconds: max(
                        wallNowUnixMilliseconds,
                        record.updatedAtUnixMilliseconds
                    ),
                    terminalCode: "audit.requiredUnavailable"
                )
                await auditWriter?.recordTerminal(failed)
                return .failed(
                    record: failed,
                    code: "audit.requiredUnavailable"
                )
            }
        }

        let request = CapabilityProviderRequestV1(
            operationID: operationID,
            capabilityID: capability.capabilityID,
            parameters: parameters,
            expiresAtUnixMilliseconds: operation.expiresAtUnixMilliseconds
        )
        let remainingMilliseconds = UInt64(
            operation.expiresAtUnixMilliseconds - wallNowUnixMilliseconds
        )
        inFlightProviders[operationID] = provider
        defer { inFlightProviders.removeValue(forKey: operationID) }
        let deadlineResult = await deadlineRunner.run(
            timeoutMilliseconds: remainingMilliseconds
        ) {
            await provider.execute(request)
        }
        switch deadlineResult {
        case .deadlineExceeded:
            let current = try await store.durableOperation(operationID)
            let unknown = try await store.transitionDurableOperation(
                operationID,
                to: .outcomeUnknown,
                occurredAtUnixMilliseconds: max(
                    operation.expiresAtUnixMilliseconds,
                    current?.updatedAtUnixMilliseconds ?? 0
                ),
                terminalCode: "operation.outcomeUnknown"
            )
            await auditWriter?.recordTerminal(unknown)
            return .outcomeUnknown(unknown)

        case .completed(.outcomeUnknown):
            let current = try await store.durableOperation(operationID)
            let unknown = try await store.transitionDurableOperation(
                operationID,
                to: .outcomeUnknown,
                occurredAtUnixMilliseconds: max(
                    wallNowUnixMilliseconds,
                    current?.updatedAtUnixMilliseconds ?? 0
                ),
                terminalCode: "operation.outcomeUnknown"
            )
            await auditWriter?.recordTerminal(unknown)
            return .outcomeUnknown(unknown)

        case .completed(.cancelled):
            let current = try await store.durableOperation(operationID)
            var transitionTime = max(
                wallNowUnixMilliseconds,
                current?.updatedAtUnixMilliseconds ?? 0
            )
            if current?.state == .running {
                let requested = try await store.transitionDurableOperation(
                    operationID,
                    to: .cancelRequested,
                    occurredAtUnixMilliseconds: transitionTime
                )
                transitionTime = requested.updatedAtUnixMilliseconds
            }
            let cancelled = try await store.transitionDurableOperation(
                operationID,
                to: .cancelled,
                occurredAtUnixMilliseconds: transitionTime,
                terminalCode: "operation.cancelled"
            )
            await auditWriter?.recordTerminal(cancelled)
            return .cancelled(cancelled)

        case let .completed(.failed(code)):
            let transitionTime = try await currentTransitionTime(
                operationID: operationID,
                proposed: wallNowUnixMilliseconds
            )
            let failed = try await store.transitionDurableOperation(
                operationID,
                to: .failed,
                occurredAtUnixMilliseconds: transitionTime,
                terminalCode: code.rawValue
            )
            await auditWriter?.recordTerminal(failed)
            return .failed(record: failed, code: code.rawValue)

        case let .completed(.succeeded(resultJSON)):
            let canonicalResult: Data
            do {
                let result = try CanonicalJSON.parse(resultJSON)
                try capability.resultSchema.validate(result)
                canonicalResult = CanonicalJSON.canonicalData(for: result)
            } catch {
                let code = "provider.invalidResult"
                let transitionTime = try await currentTransitionTime(
                    operationID: operationID,
                    proposed: wallNowUnixMilliseconds
                )
                let failed = try await store.transitionDurableOperation(
                    operationID,
                    to: .failed,
                    occurredAtUnixMilliseconds: transitionTime,
                    terminalCode: code
                )
                await auditWriter?.recordTerminal(failed)
                return .failed(record: failed, code: code)
            }
            let transitionTime = try await currentTransitionTime(
                operationID: operationID,
                proposed: wallNowUnixMilliseconds
            )
            let succeeded = try await store.transitionDurableOperation(
                operationID,
                to: .succeeded,
                occurredAtUnixMilliseconds: transitionTime
            )
            await auditWriter?.recordTerminal(succeeded)
            return .succeeded(
                record: succeeded,
                canonicalResultJSON: canonicalResult
            )
        }
    }

    public func requestCancellation(
        operationID: UUID,
        wallNowUnixMilliseconds: Int64,
        provider: (any CapabilityProviderV1)?
    ) async throws -> OperationCancellationResultV0 {
        let registry = await registryReader.registrySnapshot()
        return try await requestCancellation(
            operationID: operationID,
            wallNowUnixMilliseconds: wallNowUnixMilliseconds,
            registry: registry,
            provider: provider
        )
    }

    /// Release-composition cancellation resolves a running provider from the
    /// same publication snapshot used to validate its descriptor identity.
    public func requestCancellation(
        operationID: UUID,
        wallNowUnixMilliseconds: Int64
    ) async throws -> OperationCancellationResultV0 {
        guard let publicationReader else {
            throw OperationExecutionError.capabilityUnavailable
        }
        let publication = await publicationReader.publicationSnapshot()
        return try await requestCancellation(
            operationID: operationID,
            wallNowUnixMilliseconds: wallNowUnixMilliseconds,
            publication: publication
        )
    }

    public func requestCancellation(
        operationID: UUID,
        wallNowUnixMilliseconds: Int64,
        publication: CapabilityRegistryPublicationV1
    ) async throws -> OperationCancellationResultV0 {
        let operation = try await store.durableOperation(operationID)
        let provider = operation.flatMap {
            publication.provider(forCapabilityID: $0.capabilityID)
        }
        return try await requestCancellation(
            operationID: operationID,
            wallNowUnixMilliseconds: wallNowUnixMilliseconds,
            registry: publication.registry,
            provider: provider
        )
    }

    private func requestCancellation(
        operationID: UUID,
        wallNowUnixMilliseconds: Int64,
        registry: CapabilityRegistrySnapshotV1,
        provider: (any CapabilityProviderV1)?
    ) async throws -> OperationCancellationResultV0 {
        guard let operation = try await store.durableOperation(operationID) else {
            throw OperationExecutionError.operationNotFound
        }
        if operation.state.isTerminal {
            await auditWriter?.recordTerminal(operation)
            return .alreadyTerminal(operation)
        }
        if operation.state == .cancelRequested {
            return .alreadyRequested(operation)
        }
        if operation.state == .queued {
            let cancelled = try await store.transitionDurableOperation(
                operationID,
                to: .cancelled,
                occurredAtUnixMilliseconds: max(
                    wallNowUnixMilliseconds,
                    operation.updatedAtUnixMilliseconds
                ),
                terminalCode: "operation.cancelled"
            )
            await auditWriter?.recordTerminal(cancelled)
            return .cancelled(cancelled)
        }
        guard operation.state == .running else {
            throw OperationExecutionError.operationNotQueued(operation.state)
        }
        let effectiveProvider: any CapabilityProviderV1
        if let retained = inFlightProviders[operationID] {
            effectiveProvider = retained
        } else {
            guard let capability = registry.capability(operation.capabilityID),
                  Self.matches(operation, capability: capability),
                  let supplied = provider else {
                throw OperationExecutionError.capabilityUnavailable
            }
            effectiveProvider = supplied
        }
        let expectedProvider = CapabilityProviderIdentityV1(
            providerID: operation.providerID,
            providerVersion: operation.providerVersion,
            providerGeneration: operation.providerGeneration,
            executionRevision: operation.executionRevision
        )
        guard effectiveProvider.identity == expectedProvider else {
            throw OperationExecutionError.providerIdentityMismatch
        }
        let requested = try await store.transitionDurableOperation(
            operationID,
            to: .cancelRequested,
            occurredAtUnixMilliseconds: max(
                wallNowUnixMilliseconds,
                operation.updatedAtUnixMilliseconds
            )
        )
        let accepted = await effectiveProvider.requestCancellation(
            operationID: operationID
        )
        return .requested(record: requested, providerAccepted: accepted)
    }

    private static func matches(
        _ operation: StoredDurableOperationRecord,
        capability: CapabilityDescriptorV1
    ) -> Bool {
        operation.schemaVersion == capability.schemaVersion
            && operation.providerID == capability.providerID
            && operation.providerVersion == capability.providerVersion
            && operation.providerGeneration == capability.providerGeneration
            && operation.executionRevision == capability.executionRevision
    }

    private func currentTransitionTime(
        operationID: UUID,
        proposed: Int64
    ) async throws -> Int64 {
        guard let operation = try await store.durableOperation(operationID) else {
            throw OperationExecutionError.operationNotFound
        }
        return max(proposed, operation.updatedAtUnixMilliseconds)
    }
}
