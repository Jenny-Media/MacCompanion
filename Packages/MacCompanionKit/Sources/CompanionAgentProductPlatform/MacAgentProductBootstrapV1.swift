#if os(macOS)
import CompanionAgent
import CompanionAgentNetworkPlatform
import CompanionAgentPlatform
import CompanionDiscovery
import CompanionHostPlatform
import CompanionIPC
import CompanionLocalXPCPlatform
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

@available(macOS 26.0, *)
private actor MacAgentMenuSurfaceLossCoordinatorV1 {
    private weak var product: MacAgentPreparedProductV1?

    func install(_ product: MacAgentPreparedProductV1) {
        precondition(self.product == nil)
        self.product = product
    }

    func authenticatedMenuSurfaceUnavailable(generation: UInt64) async {
        await product?.authenticatedMenuSurfaceUnavailable(
            generation: generation
        )
    }
}

package enum MacAgentPreparedProductCompositionErrorV1:
    Error,
    Equatable,
    Sendable
{
    case authenticatedMenuUnavailable
    case networkProductAlreadyComposed
    case terminal
}

/// Inert, release-shaped Agent root after durable identity and primary-service
/// preparation. It retains the exact storage, prepared TLS/primary root, and
/// lifecycle/status XPC product as one authority graph. It exposes no raw
/// store, TLS configuration, primary services, pairing surface, or listener.
///
/// Public construction remains inert. Package-owned activation first starts
/// local authorization, waits for an authenticated menu generation, and may
/// then compose an unstarted network product. Coordinated listener activation
/// and rollback remain a later runtime checkpoint.
@available(macOS 26.0, *)
public actor MacAgentPreparedProductV1 {
    public nonisolated let hostID: UUID
    public nonisolated let storagePaths: MacAgentReleaseStoragePathsV1

    private let storage: MacAgentReleaseStorageV1
    private let preparedPrimary: AgentPreparedPrimaryStartupV1
    private let startLocalXPC: @Sendable () async throws -> Void
    private let finishLocalXPC: @Sendable () async -> Void
    private let menuSurfaceAuthority:
        MacAgentAuthenticatedMenuSurfaceAuthorityV1
    private let currentMenuGeneration: @Sendable () async -> UInt64?
    private var networkCompositionTask:
        Task<AgentNetworkPairingProductCompositionV0, Error>?
    private var networkProduct:
        AgentNetworkPairingProductCompositionV0?
    private var networkCompositionReserved = false
    private var localStartTask: Task<Void, Error>?
    private var finishTask: Task<Void, Never>?
    private var finished = false

    package init(
        storage: MacAgentReleaseStorageV1,
        preparedPrimary: AgentPreparedPrimaryStartupV1,
        localXPC: MacLocalXPCAgentProductV1,
        menuSurfaceAuthority:
            MacAgentAuthenticatedMenuSurfaceAuthorityV1 =
                MacAgentAuthenticatedMenuSurfaceAuthorityV1()
    ) {
        self.storage = storage
        self.preparedPrimary = preparedPrimary
        self.menuSurfaceAuthority = menuSurfaceAuthority
        currentMenuGeneration = {
            await menuSurfaceAuthority.currentGeneration()
        }
        startLocalXPC = { try await localXPC.start() }
        finishLocalXPC = { await localXPC.finish() }
        hostID = preparedPrimary.primaryServices.hostID
        storagePaths = storage.paths
    }

    package init(
        storage: MacAgentReleaseStorageV1,
        preparedPrimary: AgentPreparedPrimaryStartupV1,
        startLocalXPC: @escaping @Sendable () async throws -> Void = {},
        finishLocalXPC: @escaping @Sendable () async -> Void,
        menuSurfaceAuthority:
            MacAgentAuthenticatedMenuSurfaceAuthorityV1 =
                MacAgentAuthenticatedMenuSurfaceAuthorityV1(),
        currentMenuGeneration:
            (@Sendable () async -> UInt64?)? = nil
    ) {
        self.storage = storage
        self.preparedPrimary = preparedPrimary
        self.menuSurfaceAuthority = menuSurfaceAuthority
        self.currentMenuGeneration = currentMenuGeneration ?? {
            await menuSurfaceAuthority.currentGeneration()
        }
        self.startLocalXPC = startLocalXPC
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
        let menuSurfaceAuthority = self.menuSurfaceAuthority
        let localStartTask = self.localStartTask
        let networkCompositionTask = self.networkCompositionTask
        let networkProduct = self.networkProduct
        localStartTask?.cancel()
        let task = Task {
            let composedNetwork: AgentNetworkPairingProductCompositionV0?
            if let networkProduct {
                composedNetwork = networkProduct
            } else if let networkCompositionTask {
                composedNetwork = try? await networkCompositionTask.value
            } else {
                composedNetwork = nil
            }
            await composedNetwork?.authorizedSurfaceLost()
            await finishLocalXPC()
            if let localStartTask {
                _ = await localStartTask.result
            }
            await menuSurfaceAuthority.finish()
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

    package func authenticatedMenuSurfaceGeneration() async -> UInt64? {
        await menuSurfaceAuthority.currentGeneration()
    }

    package func authorizedPairingReviewSurface()
        -> any LocalPairingReviewSurfaceV0
    {
        menuSurfaceAuthority
    }

    package func authorizedHostIdentityRecoverySurface()
        -> any LocalHostIdentityRecoverySurfaceV0
    {
        menuSurfaceAuthority
    }

    package func startLocalAuthorization() async throws {
        guard finishTask == nil, !finished else {
            throw MacAgentPreparedProductCompositionErrorV1.terminal
        }
        if let localStartTask {
            try await localStartTask.value
            guard finishTask == nil, !finished else {
                throw MacAgentPreparedProductCompositionErrorV1.terminal
            }
            return
        }
        let startLocalXPC = self.startLocalXPC
        let task = Task { try await startLocalXPC() }
        localStartTask = task
        do {
            try await task.value
            guard finishTask == nil, !finished else {
                throw MacAgentPreparedProductCompositionErrorV1.terminal
            }
        } catch {
            await finish()
            throw error
        }
    }

    package func startAndComposeNetworkPairingProduct(
        port: UInt16,
        additionalEndpoints: [EndpointCandidate] = [],
        timeSource: any AgentLocalPairingTimeSamplingV0,
        policySource: any AgentLocalPairingPolicyReadingV0,
        pairingIDGenerator: @escaping @Sendable () -> UUID = { UUID() },
        deviceIDGenerator: @escaping @Sendable () -> UUID = { UUID() }
    ) async throws {
        try await startLocalAuthorization()
        _ = try await menuSurfaceAuthority.waitForAvailableGeneration()
        guard finishTask == nil, !finished else {
            throw MacAgentPreparedProductCompositionErrorV1.terminal
        }
        try await composeNetworkPairingProduct(
            port: port,
            additionalEndpoints: additionalEndpoints,
            timeSource: timeSource,
            policySource: policySource,
            pairingIDGenerator: pairingIDGenerator,
            deviceIDGenerator: deviceIDGenerator
        )
    }

    /// Consumes the one-use TLS/primary preparation only after at least one
    /// exact authenticated menu generation has installed the stable narrow
    /// review authority. The network product remains unstarted and retained
    /// exclusively by this lifecycle owner; a later package checkpoint must
    /// construct and start its listener here with coordinated rollback.
    package func composeNetworkPairingProduct(
        port: UInt16,
        additionalEndpoints: [EndpointCandidate] = [],
        timeSource: any AgentLocalPairingTimeSamplingV0,
        policySource: any AgentLocalPairingPolicyReadingV0,
        pairingIDGenerator: @escaping @Sendable () -> UUID = { UUID() },
        deviceIDGenerator: @escaping @Sendable () -> UUID = { UUID() }
    ) async throws {
        guard finishTask == nil, !finished else {
            throw MacAgentPreparedProductCompositionErrorV1.terminal
        }
        guard !networkCompositionReserved,
              networkCompositionTask == nil,
              networkProduct == nil else {
            throw MacAgentPreparedProductCompositionErrorV1
                .networkProductAlreadyComposed
        }
        networkCompositionReserved = true
        guard await currentMenuGeneration() != nil else {
            networkCompositionReserved = false
            throw MacAgentPreparedProductCompositionErrorV1
                .authenticatedMenuUnavailable
        }
        guard finishTask == nil, !finished else {
            networkCompositionReserved = false
            throw MacAgentPreparedProductCompositionErrorV1.terminal
        }
        let preparedPrimary = self.preparedPrimary
        let menuSurfaceAuthority = self.menuSurfaceAuthority
        let task = Task {
            try await preparedPrimary.consumeForAuthorizedSurface(
                port: port,
                additionalEndpoints: additionalEndpoints,
                timeSource: timeSource,
                policySource: policySource,
                alreadyAuthorizedSurface: menuSurfaceAuthority,
                pairingIDGenerator: pairingIDGenerator,
                deviceIDGenerator: deviceIDGenerator
            )
        }
        networkCompositionTask = task
        networkCompositionReserved = false
        do {
            let product = try await task.value
            guard finishTask == nil, !finished else {
                await product.authorizedSurfaceLost()
                throw MacAgentPreparedProductCompositionErrorV1.terminal
            }
            networkProduct = product
        } catch {
            throw error
        }
    }

    package func networkPairingProductSnapshot()
        async -> AgentNetworkPairingProductCompositionSnapshotV0?
    {
        await networkProduct?.snapshot()
    }

    /// Exact nonterminal presentation loss. The authority is fenced before
    /// any in-flight composition is awaited, then pending local review state
    /// converges without terminating primary ingress or Observe ownership.
    package func authenticatedMenuSurfaceUnavailable(
        generation: UInt64
    ) async {
        guard await menuSurfaceAuthority.invalidate(
            generation: generation
        ) else { return }
        if let networkProduct {
            await networkProduct.authenticatedMenuSurfaceUnavailable()
        } else if let networkCompositionTask,
                  let composed = try? await networkCompositionTask.value {
            if self.networkProduct == nil {
                self.networkProduct = composed
            }
            await composed.authenticatedMenuSurfaceUnavailable()
        }
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
        let menuSurfaceAuthority =
            MacAgentAuthenticatedMenuSurfaceAuthorityV1()
        let menuLossCoordinator = MacAgentMenuSurfaceLossCoordinatorV1()
        let result = try await AgentNetworkPrimaryStartupFactoryV1.prepare(
            requiredAudit: storage.requiredAudit,
            hostIdentityConfiguration: hostIdentityConfiguration,
            inputs: inputs
        )
        let composed = try await compose(
            storage: storage,
            preparation: result,
            makeLocalXPC: { services in
                try await MacLocalXPCAgentProductV1
                    .afterAgentBootstrapWithMenuPresentation(
                    services: services,
                    processStarter: processStarter,
                    onSurfaces: {
                        try await menuSurfaceAuthority.install($0)
                    },
                    onSurfaceInvalidated: {
                        await menuLossCoordinator
                            .authenticatedMenuSurfaceUnavailable(
                            generation: $0
                        )
                    }
                )
            },
            menuSurfaceAuthority: menuSurfaceAuthority
        )
        if case let .ready(product) = composed {
            await menuLossCoordinator.install(product)
        }
        return composed
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
            makeLocalXPC: makeLocalXPC,
            menuSurfaceAuthority:
                MacAgentAuthenticatedMenuSurfaceAuthorityV1()
        )
    }

    package static func compose(
        storage: MacAgentReleaseStorageV1,
        preparation: AgentNetworkPrimaryStartupResultV1,
        makeLocalXPC: @escaping LocalXPCFactory,
        menuSurfaceAuthority:
            MacAgentAuthenticatedMenuSurfaceAuthorityV1 =
                MacAgentAuthenticatedMenuSurfaceAuthorityV1()
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
                    localXPC: localXPC,
                    menuSurfaceAuthority: menuSurfaceAuthority
                ))
            } catch {
                await preparedPrimary.discard()
                throw error
            }
        }
    }
}
#endif
