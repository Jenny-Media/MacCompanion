#if os(macOS)
import CompanionAgent
import CompanionAgentNetworkPlatform
import CompanionAgentPlatform
import CompanionHostPlatform
import CompanionLifecycle
import CompanionSecurity
import Foundation

public enum MacAgentApplicationPreparationErrorV1:
    Error,
    Equatable,
    Sendable
{
    case unsafeInitialLifecycleState
}

public struct MacAgentApplicationPreparationInputsV1: Sendable {
    package let hostIdentityConfiguration:
        SecurityHostIdentityKeyCustodyConfigurationV0
    package let nativeMVPProviders: AgentNativeMVPProviderCompositionV1
    package let wallNowUnixMilliseconds: Int64
    package let statusPlatform: AgentHostStatusPlatformServicesV1
    package let interactivePlatform: AgentInteractivePlatformServicesV1
    package let processStarter: any MacDashboardLifecycleProcessStartingV1

    public init(
        hostIdentityConfiguration:
            SecurityHostIdentityKeyCustodyConfigurationV0,
        nativeMVPProviders: AgentNativeMVPProviderCompositionV1,
        wallNowUnixMilliseconds: Int64,
        statusPlatform: AgentHostStatusPlatformServicesV1,
        interactivePlatform: AgentInteractivePlatformServicesV1,
        processStarter: any MacDashboardLifecycleProcessStartingV1
    ) {
        self.hostIdentityConfiguration = hostIdentityConfiguration
        self.nativeMVPProviders = nativeMVPProviders
        self.wallNowUnixMilliseconds = wallNowUnixMilliseconds
        self.statusPlatform = statusPlatform
        self.interactivePlatform = interactivePlatform
        self.processStarter = processStarter
    }
}

public struct MacAgentInertApplicationSnapshotV1: Equatable, Sendable {
    public let hostID: UUID
    public let storagePaths: MacAgentReleaseStoragePathsV1
    public let lifecycle: AgentRemoteLifecycleSnapshotV1
    public let requestContexts:
        MacAgentConservativeRequestContextSnapshotV1
    public let finished: Bool

    public init(
        hostID: UUID,
        storagePaths: MacAgentReleaseStoragePathsV1,
        lifecycle: AgentRemoteLifecycleSnapshotV1,
        requestContexts: MacAgentConservativeRequestContextSnapshotV1,
        finished: Bool
    ) {
        self.hostID = hostID
        self.storagePaths = storagePaths
        self.lifecycle = lifecycle
        self.requestContexts = requestContexts
        self.finished = finished
    }
}

@available(macOS 26.0, *)
package struct MacAgentPreparedProductHandleV1: Sendable {
    package let hostID: UUID
    package let storagePaths: MacAgentReleaseStoragePathsV1
    private let currentLifecycle:
        @Sendable () async -> AgentRemoteLifecycleSnapshotV1
    private let startPreparedLocalService: @Sendable () async throws -> Void
    private let finishPrepared: @Sendable () async -> Void

    package init(product: MacAgentPreparedProductV1) {
        hostID = product.hostID
        storagePaths = product.storagePaths
        currentLifecycle = { await product.lifecycleSnapshot() }
        startPreparedLocalService = {
            try await product.startLocalAuthorization()
        }
        finishPrepared = { await product.finish() }
    }

    package init(
        hostID: UUID,
        storagePaths: MacAgentReleaseStoragePathsV1,
        currentLifecycle: @escaping @Sendable () async ->
            AgentRemoteLifecycleSnapshotV1,
        startLocalService: @escaping @Sendable () async throws -> Void = {},
        finish: @escaping @Sendable () async -> Void
    ) {
        self.hostID = hostID
        self.storagePaths = storagePaths
        self.currentLifecycle = currentLifecycle
        startPreparedLocalService = startLocalService
        self.finishPrepared = finish
    }

    package func lifecycleSnapshot() async
        -> AgentRemoteLifecycleSnapshotV1
    {
        await currentLifecycle()
    }

    package func startLocalService() async throws {
        try await startPreparedLocalService()
    }

    package func finish() async {
        await finishPrepared()
    }
}

@available(macOS 26.0, *)
package enum MacAgentPreparedApplicationRootResultV1: Sendable {
    case prepared(MacAgentPreparedProductHandleV1)
    case waitForFirstUnlock
    case requireLocalRecovery(HostIdentityRecoveryReason)
    case recoveryFenced(UUID)
}

/// Owns a durable, prepared Agent root without exposing any activation method.
/// Storage and host identity may already have been created or reconciled, but
/// readiness-producing local XPC construction is deferred and no listener,
/// login role, or process is activated by this owner.
@available(macOS 26.0, *)
public actor MacAgentInertApplicationLifecycleV1 {
    public nonisolated let hostID: UUID
    public nonisolated let storagePaths: MacAgentReleaseStoragePathsV1
    private let requestContexts:
        MacAgentConservativeRequestContextProductV1
    private let prepared: MacAgentPreparedProductHandleV1
    private var finishTask: Task<Void, Never>?
    private var finished = false

    package init(
        requestContexts: MacAgentConservativeRequestContextProductV1,
        prepared: MacAgentPreparedProductHandleV1
    ) {
        self.requestContexts = requestContexts
        self.prepared = prepared
        hostID = prepared.hostID
        storagePaths = prepared.storagePaths
    }

    deinit {
        requestContexts.finish()
        guard finishTask == nil else { return }
        let prepared = self.prepared
        Task { await prepared.finish() }
    }

    public func snapshot() async -> MacAgentInertApplicationSnapshotV1 {
        let lifecycle = await prepared.lifecycleSnapshot()
        return MacAgentInertApplicationSnapshotV1(
            hostID: hostID,
            storagePaths: storagePaths,
            lifecycle: lifecycle,
            requestContexts: requestContexts.snapshot(),
            finished: finished
        )
    }

    package func canonicalInitialLifecycleSnapshot() async throws
        -> AgentRemoteLifecycleSnapshotV1
    {
        let snapshot = await prepared.lifecycleSnapshot()
        guard snapshot.revision == 0,
              snapshot.agentObservationEpoch == 0,
              snapshot.menuAppObservationEpoch == 0 else {
            throw MacAgentApplicationPreparationErrorV1
                .unsafeInitialLifecycleState
        }
        try MacAgentApplicationPreparationFacadeV1
            .validateInitialLifecycleState(snapshot.state)
        return snapshot
    }

    package func startPreparedLocalService() async throws {
        guard finishTask == nil, !finished else {
            throw MacAgentApplicationPreparationErrorV1
                .unsafeInitialLifecycleState
        }
        do {
            try await prepared.startLocalService()
            try Task.checkCancellation()
            guard finishTask == nil, !finished else {
                throw MacAgentApplicationPreparationErrorV1
                    .unsafeInitialLifecycleState
            }
        } catch {
            await finish()
            throw error
        }
    }

    public func finish() async {
        if let finishTask {
            await finishTask.value
            finished = true
            return
        }
        requestContexts.finish()
        let prepared = self.prepared
        let task = Task { await prepared.finish() }
        finishTask = task
        await task.value
        finished = true
    }
}

@available(macOS 26.0, *)
public enum MacAgentApplicationPreparationResultV1: Sendable {
    case prepared(MacAgentInertApplicationLifecycleV1)
    case waitForFirstUnlock
    case requireLocalRecovery(HostIdentityRecoveryReason)
    case recoveryFenced(UUID)
}

/// Loads durable desired intent before creating the Agent startup inputs, then
/// retains any ready preparation behind an activation-inert lifecycle owner.
@available(macOS 26.0, *)
public enum MacAgentApplicationPreparationFacadeV1 {
    public static func prepare(
        inputs: MacAgentApplicationPreparationInputsV1
    ) async throws -> MacAgentApplicationPreparationResultV1 {
        try await prepare(
            makeStorage: { try MacAgentReleaseStorageV1.systemDefault() },
            makeIntentStore: {
                try AtomicFileMacRemoteAccessIntentStoreV1(directory: $0)
            },
            makePrimaryInputs: { lifecycleState in
                AgentNetworkPrimaryStartupInputsV1(
                    nativeMVPProviders: inputs.nativeMVPProviders,
                    wallNowUnixMilliseconds:
                        inputs.wallNowUnixMilliseconds,
                    lifecycleState: lifecycleState,
                    statusPlatform: inputs.statusPlatform,
                    interactivePlatform: inputs.interactivePlatform
                )
            },
            prepareRoot: { storage, primaryInputs in
                let result = try await MacAgentProductBootstrapV1
                    .prepareStatusOnlyInert(
                    storage: storage,
                    hostIdentityConfiguration:
                        inputs.hostIdentityConfiguration,
                    inputs: primaryInputs,
                    processStarter: inputs.processStarter
                )
                switch result {
                case let .ready(product):
                    return .prepared(
                        MacAgentPreparedProductHandleV1(product: product)
                    )
                case .waitForFirstUnlock:
                    return .waitForFirstUnlock
                case let .requireLocalRecovery(reason):
                    return .requireLocalRecovery(reason)
                case let .recoveryFenced(recoveryID):
                    return .recoveryFenced(recoveryID)
                }
            }
        )
    }

    package static func prepare(
        makeStorage: @escaping @Sendable () throws ->
            MacAgentReleaseStorageV1,
        makeIntentStore: @escaping @Sendable (URL) throws ->
            any MacRemoteAccessIntentPersistenceV1,
        makePrimaryInputs: @escaping @Sendable (ProductLifecycleState) throws
            -> AgentNetworkPrimaryStartupInputsV1,
        prepareRoot: @escaping @Sendable (
            MacAgentReleaseStorageV1,
            AgentNetworkPrimaryStartupInputsV1
        ) async throws -> MacAgentPreparedApplicationRootResultV1
    ) async throws -> MacAgentApplicationPreparationResultV1 {
        try Task.checkCancellation()
        let storage = try makeStorage()
        try Task.checkCancellation()
        let intentStore = try makeIntentStore(
            storage.paths.remoteAccessIntentDirectory
        )
        try Task.checkCancellation()
        let initialState = try await MacDashboardLifecycleStartupStateLoaderV1(
            intentStore: intentStore
        ).loadInitialState(consoleSession: .otherConsoleUserActive)
        try Task.checkCancellation()
        try validateInitialLifecycleState(initialState)
        let requestContexts = MacAgentConservativeRequestContextProductV1()
        try Task.checkCancellation()
        let primaryInputs = try makePrimaryInputs(initialState)
        guard primaryInputs.lifecycleState == initialState else {
            throw MacAgentApplicationPreparationErrorV1
                .unsafeInitialLifecycleState
        }
        try Task.checkCancellation()
        let result = try await prepareRoot(storage, primaryInputs)

        switch result {
        case let .prepared(prepared):
            let preparedLifecycle = await prepared.lifecycleSnapshot()
            guard preparedLifecycle == AgentRemoteLifecycleSnapshotV1(
                revision: 0,
                state: initialState
            ) else {
                await prepared.finish()
                throw MacAgentApplicationPreparationErrorV1
                    .unsafeInitialLifecycleState
            }
            let owner = MacAgentInertApplicationLifecycleV1(
                requestContexts: requestContexts,
                prepared: prepared
            )
            do {
                try Task.checkCancellation()
                return .prepared(owner)
            } catch {
                await owner.finish()
                throw error
            }
        case .waitForFirstUnlock:
            try Task.checkCancellation()
            return .waitForFirstUnlock
        case let .requireLocalRecovery(reason):
            try Task.checkCancellation()
            return .requireLocalRecovery(reason)
        case let .recoveryFenced(recoveryID):
            try Task.checkCancellation()
            return .recoveryFenced(recoveryID)
        }
    }

    package static func validateInitialLifecycleState(
        _ state: ProductLifecycleState
    ) throws {
        let expected: ManagedProcessState = state.desiredEnabled
            ? .starting
            : .stopped
        guard state.consoleSession == .otherConsoleUserActive,
              state.agent == expected,
              state.menuApp == expected,
              !state.observeAvailable,
              !state.newInteractiveControlAvailable,
              !state.localAdministrationVisible else {
            throw MacAgentApplicationPreparationErrorV1
                .unsafeInitialLifecycleState
        }
    }
}
#endif
