import CompanionAuthentication
import CompanionDomain
import CompanionPersistence
import CompanionWire
import Foundation

public struct AuthenticatedOperationCommandContextV0: Equatable, Sendable {
    public let principal: AuthenticatedDevicePrincipal
    public let primaryConnectionID: Data
    public let hostState: HostState
    public let wallNowUnixMilliseconds: Int64
    public let monotonicNowMilliseconds: UInt64
    public let selectedVersion: WireVersion

    public init(
        principal: AuthenticatedDevicePrincipal,
        primaryConnectionID: Data,
        hostState: HostState,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64,
        selectedVersion: WireVersion = .init()
    ) throws {
        guard primaryConnectionID.count == 16,
              wallNowUnixMilliseconds >= 0,
              wallNowUnixMilliseconds <= WireLimits.maximumSafeInteger,
              monotonicNowMilliseconds <= UInt64(Int64.max),
              selectedVersion.major == 0,
              selectedVersion.minor == 1 else {
            throw OperationCommandError.invalidContext
        }
        self.principal = principal
        self.primaryConnectionID = primaryConnectionID
        self.hostState = hostState
        self.wallNowUnixMilliseconds = wallNowUnixMilliseconds
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
        self.selectedVersion = selectedVersion
    }
}

public enum OperationCommandReplyV0: Equatable, Sendable {
    case approvalRequired(OperationApprovalRequiredBody)
    case status(OperationStatusResponseBody)
}

public enum OperationCommandError: Error, Equatable, Sendable {
    case invalidContext
    case operationNotFound
    case providerUnavailable
    case duplicateProviderIdentity
}

public protocol CapabilityProviderResolvingV1: Sendable {
    func provider(
        matching identity: CapabilityProviderIdentityV1
    ) async -> (any CapabilityProviderV1)?
}

public actor CapabilityProviderCatalogV1: CapabilityProviderResolvingV1 {
    private var providers: [String: any CapabilityProviderV1] = [:]

    public init(providers: [any CapabilityProviderV1] = []) throws {
        for provider in providers {
            guard self.providers[provider.identity.providerID] == nil else {
                throw OperationCommandError.duplicateProviderIdentity
            }
            self.providers[provider.identity.providerID] = provider
        }
    }

    public func replace(_ providers: [any CapabilityProviderV1]) throws {
        var replacement: [String: any CapabilityProviderV1] = [:]
        for provider in providers {
            guard replacement[provider.identity.providerID] == nil else {
                throw OperationCommandError.duplicateProviderIdentity
            }
            replacement[provider.identity.providerID] = provider
        }
        self.providers = replacement
    }

    public func provider(
        matching identity: CapabilityProviderIdentityV1
    ) -> (any CapabilityProviderV1)? {
        guard let provider = providers[identity.providerID],
              provider.identity == identity else {
            return nil
        }
        return provider
    }
}

public actor OperationCommandCoordinatorV0 {
    private let store: SQLiteSecurityStore
    private let startup: OperationStartupReconcilerV0
    private let admission: OperationAdmissionAuthorityV0
    private let execution: OperationExecutionAuthorityV0
    private let providers: (any CapabilityProviderResolvingV1)?
    private let publicationReader:
        (any CapabilityRegistryPublicationReadingV1)?

    public init(
        store: SQLiteSecurityStore,
        startup: OperationStartupReconcilerV0,
        admission: OperationAdmissionAuthorityV0,
        execution: OperationExecutionAuthorityV0,
        providers: any CapabilityProviderResolvingV1
    ) {
        self.store = store
        self.startup = startup
        self.admission = admission
        self.execution = execution
        self.providers = providers
        publicationReader = nil
    }

    /// Release-composition initializer. Provider resolution remains inside the
    /// immutable publication authority instead of a separately replaceable
    /// catalog.
    public init(
        store: SQLiteSecurityStore,
        startup: OperationStartupReconcilerV0,
        publicationReader: any CapabilityRegistryPublicationReadingV1,
        deadlineRunner: any CapabilityProviderDeadlineRunningV1 =
            SystemCapabilityProviderDeadlineRunnerV1(),
        auditWriter: any OperationAuditWritingV0
    ) {
        self.store = store
        self.startup = startup
        admission = OperationAdmissionAuthorityV0(
            store: store,
            registryReader: publicationReader
        )
        execution = OperationExecutionAuthorityV0(
            store: store,
            publicationReader: publicationReader,
            deadlineRunner: deadlineRunner,
            auditWriter: auditWriter
        )
        providers = nil
        self.publicationReader = publicationReader
    }

    public func reconcileBeforeOpeningIngress(
        wallNowUnixMilliseconds: Int64
    ) async throws -> DurableOperationStartupReconciliation {
        try await startup.reconcileBeforeOpeningIngress(
            wallNowUnixMilliseconds: wallNowUnixMilliseconds
        )
    }

    public func invoke(
        _ body: OperationInvokeRequestBody,
        context: AuthenticatedOperationCommandContextV0
    ) async throws -> OperationCommandReplyV0 {
        _ = try await startup.requireReconciled()
        let publication = await publicationReader?.publicationSnapshot()
        try body.validate()
        let parameters = CanonicalJSON.canonicalData(for: body.parameters)
        let preparation = try await admission.prepareAdmission(
            operationID: body.operationID.rawValue,
            parametersJSON: parameters,
            capabilityID: body.capabilityID,
            principal: context.principal,
            primaryConnectionID: context.primaryConnectionID,
            hostState: context.hostState,
            wallNowUnixMilliseconds: context.wallNowUnixMilliseconds,
            monotonicNowMilliseconds: context.monotonicNowMilliseconds,
            selectedVersion: context.selectedVersion,
            registrySnapshot: publication?.registry
        )
        switch preparation {
        case let .approvalRequired(challenge):
            return .approvalRequired(try approvalBody(
                operationID: body.operationID,
                challenge: challenge
            ))
        case let .admitted(admissionResult):
            return try await executeOrObserve(
                record: record(from: admissionResult),
                parametersJSON: parameters,
                context: context,
                publication: publication
            )
        }
    }

    public func approve(
        _ body: OperationApproveRequestBody,
        context: AuthenticatedOperationCommandContextV0
    ) async throws -> OperationCommandReplyV0 {
        _ = try await startup.requireReconciled()
        let publication = await publicationReader?.publicationSnapshot()
        try body.validate()
        let completed = try await admission.completeApprovalForExecution(
            approvalID: body.approvalID.rawValue,
            rawSignature: body.signature.rawValue,
            primaryConnectionID: context.primaryConnectionID,
            monotonicNowMilliseconds: context.monotonicNowMilliseconds,
            registrySnapshot: publication?.registry
        )
        let admitted = record(from: completed.admission)
        try requireOwnership(admitted, principal: context.principal)
        return try await executeOrObserve(
            record: admitted,
            parametersJSON: completed.canonicalParametersJSON,
            context: context,
            publication: publication
        )
    }

    public func status(
        _ body: OperationStatusRequestBody,
        context: AuthenticatedOperationCommandContextV0
    ) async throws -> OperationCommandReplyV0 {
        _ = try await startup.requireReconciled()
        try body.validate()
        let record = try await ownedRecord(
            body.operationID.rawValue,
            principal: context.principal
        )
        return .status(try statusBody(record: record, result: nil))
    }

    public func cancel(
        _ body: OperationCancelRequestBody,
        context: AuthenticatedOperationCommandContextV0
    ) async throws -> OperationCommandReplyV0 {
        _ = try await startup.requireReconciled()
        try body.validate()
        let record = try await ownedRecord(
            body.operationID.rawValue,
            principal: context.principal
        )
        let provider: (any CapabilityProviderV1)?
        if record.state == .running {
            if let providers {
                provider = await providers.provider(matching: identity(for: record))
                guard provider != nil else {
                    throw OperationCommandError.providerUnavailable
                }
            } else {
                provider = nil
            }
        } else {
            provider = nil
        }
        let result: OperationCancellationResultV0
        if let publication = await publicationReader?.publicationSnapshot() {
            result = try await execution.requestCancellation(
                operationID: record.operationID,
                wallNowUnixMilliseconds: context.wallNowUnixMilliseconds,
                publication: publication
            )
        } else {
            result = try await execution.requestCancellation(
                operationID: record.operationID,
                wallNowUnixMilliseconds: context.wallNowUnixMilliseconds,
                provider: provider
            )
        }
        let updated: StoredDurableOperationRecord
        switch result {
        case let .cancelled(value), let .alreadyRequested(value),
             let .alreadyTerminal(value):
            updated = value
        case let .requested(value, _):
            updated = value
        }
        return .status(try statusBody(record: updated, result: nil))
    }

    private func executeOrObserve(
        record: StoredDurableOperationRecord,
        parametersJSON: Data,
        context: AuthenticatedOperationCommandContextV0,
        publication: CapabilityRegistryPublicationV1?
    ) async throws -> OperationCommandReplyV0 {
        try requireOwnership(record, principal: context.principal)
        guard record.state == .queued else {
            return .status(try statusBody(record: record, result: nil))
        }
        do {
            let result: OperationExecutionResultV0
            if let publication {
                result = try await execution.execute(
                    operationID: record.operationID,
                    parametersJSON: parametersJSON,
                    hostState: context.hostState,
                    wallNowUnixMilliseconds: context.wallNowUnixMilliseconds,
                    publication: publication
                )
            } else {
                guard let providers,
                      let provider = await providers.provider(
                        matching: identity(for: record)
                      ) else {
                    let failed = try await store
                        .failQueuedOperationForUnavailableProvider(
                            record.operationID,
                            occurredAtUnixMilliseconds:
                                context.wallNowUnixMilliseconds
                        )
                    return .status(try statusBody(record: failed, result: nil))
                }
                result = try await execution.execute(
                    operationID: record.operationID,
                    parametersJSON: parametersJSON,
                    hostState: context.hostState,
                    wallNowUnixMilliseconds: context.wallNowUnixMilliseconds,
                    provider: provider
                )
            }
            switch result {
            case let .succeeded(updated, canonicalResultJSON):
                return .status(try statusBody(
                    record: updated,
                    result: CanonicalJSON.parse(canonicalResultJSON)
                ))
            case let .failed(updated, _), let .cancelled(updated),
                 let .outcomeUnknown(updated), let .alreadyTerminal(updated):
                return .status(try statusBody(record: updated, result: nil))
            }
        } catch let error as OperationExecutionError {
            switch error {
            case .operationNotQueued(.running),
                 .operationNotQueued(.cancelRequested):
                let current = try await ownedRecord(
                    record.operationID,
                    principal: context.principal
                )
                return .status(try statusBody(record: current, result: nil))
            default:
                throw error
            }
        }
    }

    private func ownedRecord(
        _ operationID: UUID,
        principal: AuthenticatedDevicePrincipal
    ) async throws -> StoredDurableOperationRecord {
        guard let record = try await store.durableOperation(operationID) else {
            throw OperationCommandError.operationNotFound
        }
        try requireOwnership(record, principal: principal)
        return record
    }

    private func requireOwnership(
        _ record: StoredDurableOperationRecord,
        principal: AuthenticatedDevicePrincipal
    ) throws {
        guard record.deviceID == principal.deviceID,
              record.clientID == principal.clientID else {
            throw OperationCommandError.operationNotFound
        }
    }

    private func statusBody(
        record: StoredDurableOperationRecord,
        result: CanonicalJSONValue?
    ) throws -> OperationStatusResponseBody {
        try OperationStatusResponseBody(
            operationID: WireUUID(record.operationID),
            state: record.state,
            terminalCode: record.terminalCode,
            result: result
        )
    }

    private func approvalBody(
        operationID: WireUUID,
        challenge: OperationApprovalChallengeV0
    ) throws -> OperationApprovalRequiredBody {
        guard challenge.issuedAtUnixMilliseconds <= UInt64(Int64.max),
              challenge.expiresAtUnixMilliseconds <= UInt64(Int64.max) else {
            throw OperationCommandError.invalidContext
        }
        return try OperationApprovalRequiredBody(
            operationID: operationID,
            approvalID: WireUUID(challenge.approvalID),
            operationDigest: WireBytes32(challenge.operationDigest),
            serverChallenge: WireBytes32(challenge.serverChallenge),
            issuedAtUnixMilliseconds: Int64(challenge.issuedAtUnixMilliseconds),
            expiresAtUnixMilliseconds: Int64(challenge.expiresAtUnixMilliseconds)
        )
    }

    private func identity(
        for record: StoredDurableOperationRecord
    ) -> CapabilityProviderIdentityV1 {
        CapabilityProviderIdentityV1(
            providerID: record.providerID,
            providerVersion: record.providerVersion,
            providerGeneration: record.providerGeneration,
            executionRevision: record.executionRevision
        )
    }

    private func record(
        from result: DurableOperationAdmissionResult
    ) -> StoredDurableOperationRecord {
        switch result {
        case let .created(record), let .existing(record): record
        }
    }
}
