#if os(macOS)
import CompanionAgent
import CompanionAgentNetworkPlatform
import CompanionAgentPlatform
import CompanionHostPlatform
import CompanionSecurity
import Foundation

public struct MacAgentPreparedProductSnapshotV1:
    Equatable, Sendable
{
    public let hostID: UUID
    public let storagePaths: MacAgentReleaseStoragePathsV1
    public let finished: Bool

    public init(
        hostID: UUID,
        storagePaths: MacAgentReleaseStoragePathsV1,
        finished: Bool
    ) {
        self.hostID = hostID
        self.storagePaths = storagePaths
        self.finished = finished
    }
}

/// Inert, release-shaped Agent root after durable identity and primary-service
/// preparation. It retains the exact storage, prepared TLS/primary root, and
/// lifecycle/status XPC product as one authority graph. It exposes no raw
/// store, TLS configuration, primary services, pairing surface, or listener.
///
/// This checkpoint intentionally has no start method. A later authenticated
/// menu-generation router must be composed before local XPC and the network
/// listener can be activated with rollback as one runtime product.
@available(macOS 26.0, *)
public actor MacAgentPreparedProductV1 {
    public nonisolated let hostID: UUID
    public nonisolated let storagePaths: MacAgentReleaseStoragePathsV1

    private let storage: MacAgentReleaseStorageV1
    private let preparedPrimary: AgentPreparedPrimaryStartupV1
    private let finishLocalXPC: @Sendable () async -> Void
    private var finishTask: Task<Void, Never>?
    private var finished = false

    package init(
        storage: MacAgentReleaseStorageV1,
        preparedPrimary: AgentPreparedPrimaryStartupV1,
        localXPC: MacLocalXPCAgentProductV1
    ) {
        self.storage = storage
        self.preparedPrimary = preparedPrimary
        finishLocalXPC = { await localXPC.finish() }
        hostID = preparedPrimary.primaryServices.hostID
        storagePaths = storage.paths
    }

    package init(
        storage: MacAgentReleaseStorageV1,
        preparedPrimary: AgentPreparedPrimaryStartupV1,
        finishLocalXPC: @escaping @Sendable () async -> Void
    ) {
        self.storage = storage
        self.preparedPrimary = preparedPrimary
        self.finishLocalXPC = finishLocalXPC
        hostID = preparedPrimary.primaryServices.hostID
        storagePaths = storage.paths
    }

    /// Retires the unstarted XPC product and permanently consumes the prepared
    /// TLS/primary root. Repeated calls await the same effective terminal state
    /// and cannot make a discarded preparation reusable.
    public func finish() async {
        if let finishTask {
            await finishTask.value
            finished = true
            return
        }
        let finishLocalXPC = self.finishLocalXPC
        let preparedPrimary = self.preparedPrimary
        let task = Task {
            await finishLocalXPC()
            await preparedPrimary.discard()
        }
        finishTask = task
        await task.value
        finished = true
    }

    public func snapshot() -> MacAgentPreparedProductSnapshotV1 {
        MacAgentPreparedProductSnapshotV1(
            hostID: hostID,
            storagePaths: storagePaths,
            finished: finished
        )
    }

    package func preparedPrimarySnapshot()
        async -> AgentPreparedPrimaryStartupSnapshotV1
    {
        await preparedPrimary.snapshot()
    }
}

@available(macOS 26.0, *)
public enum MacAgentProductBootstrapResultV1: Sendable {
    case ready(MacAgentPreparedProductV1)
    case waitForFirstUnlock
    case requireLocalRecovery(HostIdentityRecoveryReason)
    case recoveryFenced(UUID)
}

/// Top-layer construction owner kept in a separate product target so neither
/// the menu platform module nor the network platform module gains the other's
/// authority closure. The permanent Agent does not link or invoke this owner
/// until the authenticated menu-surface and runtime activation gates close.
@available(macOS 26.0, *)
public enum MacAgentProductBootstrapV1 {
    package typealias LocalXPCFactory = @Sendable (
        AgentPrimaryServicesV1
    ) async throws -> MacLocalXPCAgentProductV1

    public static func prepare(
        hostIdentityConfiguration:
            SecurityHostIdentityKeyCustodyConfigurationV0,
        inputs: AgentNetworkPrimaryStartupInputsV1,
        processStarter: any MacDashboardLifecycleProcessStartingV1
    ) async throws -> MacAgentProductBootstrapResultV1 {
        let storage = try MacAgentReleaseStorageV1.systemDefault()
        let result = try await AgentNetworkPrimaryStartupFactoryV1.prepare(
            requiredAudit: storage.requiredAudit,
            hostIdentityConfiguration: hostIdentityConfiguration,
            inputs: inputs
        )
        return try await compose(
            storage: storage,
            preparation: result,
            makeLocalXPC: { services in
                try await MacLocalXPCAgentProductV1.afterAgentBootstrap(
                    services: services,
                    processStarter: processStarter
                )
            }
        )
    }

    package static func prepare(
        storage: MacAgentReleaseStorageV1,
        hostIdentityStartup: @escaping @Sendable () async throws ->
            SecurityHostIdentityStartupResultV0,
        inputs: AgentNetworkPrimaryStartupInputsV1,
        makeLocalXPC: @escaping LocalXPCFactory
    ) async throws -> MacAgentProductBootstrapResultV1 {
        let result = try await AgentNetworkPrimaryStartupFactoryV1.prepare(
            hostIdentityStartup: hostIdentityStartup,
            requiredAudit: storage.requiredAudit,
            inputs: inputs
        )
        return try await compose(
            storage: storage,
            preparation: result,
            makeLocalXPC: makeLocalXPC
        )
    }

    package static func compose(
        storage: MacAgentReleaseStorageV1,
        preparation: AgentNetworkPrimaryStartupResultV1,
        makeLocalXPC: @escaping LocalXPCFactory
    ) async throws -> MacAgentProductBootstrapResultV1 {
        switch preparation {
        case .waitForFirstUnlock:
            return .waitForFirstUnlock
        case let .requireLocalRecovery(reason):
            return .requireLocalRecovery(reason)
        case let .recoveryFenced(recoveryID):
            return .recoveryFenced(recoveryID)
        case let .ready(preparedPrimary):
            do {
                let localXPC = try await makeLocalXPC(
                    preparedPrimary.primaryServices
                )
                return .ready(MacAgentPreparedProductV1(
                    storage: storage,
                    preparedPrimary: preparedPrimary,
                    localXPC: localXPC
                ))
            } catch {
                await preparedPrimary.discard()
                throw error
            }
        }
    }
}
#endif
