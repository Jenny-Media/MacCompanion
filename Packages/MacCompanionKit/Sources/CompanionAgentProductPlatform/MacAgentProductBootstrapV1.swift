#if os(macOS)
import CompanionAgent
import CompanionAgentNetworkPlatform
import CompanionAgentPlatform
import CompanionDiscovery
import CompanionHostPlatform
import CompanionIPC
import CompanionInteractiveHost
import CompanionLocalXPCPlatform
import CompanionNetworkPlatform
import CompanionSecurity
import Dispatch
import Foundation

@available(macOS 26.0, *)
package protocol MacAgentNetworkListenerRuntimeV1: AnyObject, Sendable {
    func start() async throws
    func closeNetworkAdmission() async throws
    func drainNetworkConnections() async throws
    func reopenNetworkAdmission() async throws
    func cancel() async
    func snapshot() async -> AgentNetworkListenerServiceSnapshotV1
    func hasAuthenticatedEventSink(
        primaryConnectionID: Data
    ) async -> Bool
    func sendAuthenticatedEvent(
        _ eventJSON: Data,
        primaryConnectionID: Data
    ) async throws
}

@available(macOS 26.0, *)
package extension MacAgentNetworkListenerRuntimeV1 {
    func closeNetworkAdmission() async throws {
        throw MacAgentPreparedProductCompositionErrorV1
            .networkProductUnavailable
    }

    func drainNetworkConnections() async throws {
        throw MacAgentPreparedProductCompositionErrorV1
            .networkProductUnavailable
    }

    func reopenNetworkAdmission() async throws {
        throw MacAgentPreparedProductCompositionErrorV1
            .networkProductUnavailable
    }

    func hasAuthenticatedEventSink(
        primaryConnectionID: Data
    ) async -> Bool { false }

    func sendAuthenticatedEvent(
        _ eventJSON: Data,
        primaryConnectionID: Data
    ) async throws {
        throw AgentNetworkAuthenticatedEventSinkErrorV2.unavailable
    }
}

@available(macOS 26.0, *)
extension AgentNetworkListenerServiceV1: MacAgentNetworkListenerRuntimeV1 {}

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

@available(macOS 26.0, *)
private actor MacAgentUpdateQuiescenceCoordinatorV0:
    MacLocalXPCUpdateQuiescenceHandlingV0
{
    private weak var product: MacAgentPreparedProductV1?

    func install(_ product: MacAgentPreparedProductV1) {
        precondition(self.product == nil)
        self.product = product
    }

    func closeNetworkAdmissionForUpdate() async throws {
        guard let product else {
            throw MacAgentPreparedProductCompositionErrorV1
                .networkProductUnavailable
        }
        try await product.closeNetworkAdmissionForUpdate()
    }

    func drainNetworkConnectionsForUpdate() async throws {
        guard let product else {
            throw MacAgentPreparedProductCompositionErrorV1
                .networkProductUnavailable
        }
        try await product.drainNetworkConnectionsForUpdate()
    }

    func reopenNetworkAdmissionAfterUpdateFailure() async throws {
        guard let product else {
            throw MacAgentPreparedProductCompositionErrorV1
                .networkProductUnavailable
        }
        try await product.reopenNetworkAdmissionAfterUpdateFailure()
    }
}

package enum MacAgentPreparedProductCompositionErrorV1:
    Error,
    Equatable,
    Sendable
{
    case authenticatedMenuUnavailable
    case networkProductAlreadyComposed
    case networkProductUnavailable
    case networkListenerAlreadyStarted
    case terminal
}

@available(macOS 26.0, *)
package actor MacAgentNetworkListenerRuntimeOwnerV1 {
    private let runtime: any MacAgentNetworkListenerRuntimeV1
    private var startTask: Task<Void, Error>?
    private var finishTask: Task<Void, Never>?

    package init(runtime: any MacAgentNetworkListenerRuntimeV1) {
        self.runtime = runtime
    }

    package func start() async throws {
        guard finishTask == nil else {
            throw MacAgentPreparedProductCompositionErrorV1.terminal
        }
        guard startTask == nil else {
            throw MacAgentPreparedProductCompositionErrorV1
                .networkListenerAlreadyStarted
        }
        let runtime = self.runtime
        let task = Task {
            try Task.checkCancellation()
            try await runtime.start()
            try Task.checkCancellation()
        }
        startTask = task
        do {
            try await withTaskCancellationHandler {
                try await task.value
                try Task.checkCancellation()
            } onCancel: {
                Task { await self.finish() }
            }
            guard finishTask == nil else {
                throw MacAgentPreparedProductCompositionErrorV1.terminal
            }
        } catch {
            await finish()
            throw error
        }
    }

    package func finish() async {
        if let finishTask {
            await finishTask.value
            return
        }
        let startTask = self.startTask
        let runtime = self.runtime
        startTask?.cancel()
        let task = Task {
            await runtime.cancel()
            if let startTask { _ = await startTask.result }
        }
        finishTask = task
        await task.value
    }

    package func closeNetworkAdmission() async throws {
        guard finishTask == nil else {
            throw MacAgentPreparedProductCompositionErrorV1.terminal
        }
        try await runtime.closeNetworkAdmission()
        guard finishTask == nil else {
            throw MacAgentPreparedProductCompositionErrorV1.terminal
        }
    }

    package func drainNetworkConnections() async throws {
        guard finishTask == nil else {
            throw MacAgentPreparedProductCompositionErrorV1.terminal
        }
        try await runtime.drainNetworkConnections()
        guard finishTask == nil else {
            throw MacAgentPreparedProductCompositionErrorV1.terminal
        }
    }

    package func reopenNetworkAdmission() async throws {
        guard finishTask == nil else {
            throw MacAgentPreparedProductCompositionErrorV1.terminal
        }
        try await runtime.reopenNetworkAdmission()
        guard finishTask == nil else {
            throw MacAgentPreparedProductCompositionErrorV1.terminal
        }
    }

    package func sendAuthenticatedEvent(
        _ eventJSON: Data,
        primaryConnectionID: Data
    ) async throws {
        guard finishTask == nil else {
            throw MacAgentPreparedProductCompositionErrorV1.terminal
        }
        try await runtime.sendAuthenticatedEvent(
            eventJSON,
            primaryConnectionID: primaryConnectionID
        )
    }

    package func hasAuthenticatedPrimaryEventSink(
        primaryConnectionID: Data
    ) async -> Bool {
        guard finishTask == nil else { return false }
        return await runtime.hasAuthenticatedEventSink(
            primaryConnectionID: primaryConnectionID
        )
    }

    package func snapshot() async -> AgentNetworkListenerServiceSnapshotV1 {
        await runtime.snapshot()
    }
}

/// Defers readiness-producing local-XPC composition until explicit activation.
/// Finishing an unactivated owner never invokes the factory.
@available(macOS 26.0, *)
package actor MacAgentDeferredLocalXPCOwnerV1 {
    package typealias Factory = @Sendable () async throws ->
        MacLocalXPCAgentProductV1

    private let factory: Factory
    private var product: MacLocalXPCAgentProductV1?
    private var startTask: Task<MacLocalXPCAgentProductV1, Error>?
    private var finishTask: Task<Void, Never>?

    package init(factory: @escaping Factory) {
        self.factory = factory
    }

    package func start() async throws {
        guard finishTask == nil else {
            throw MacAgentPreparedProductCompositionErrorV1.terminal
        }
        if let startTask {
            do {
                _ = try await awaitStart(startTask)
                guard finishTask == nil else {
                    throw MacAgentPreparedProductCompositionErrorV1.terminal
                }
                return
            } catch {
                await finish()
                throw error
            }
        }
        let factory = self.factory
        let task = Task {
            let product = try await factory()
            do {
                try Task.checkCancellation()
                try await product.start()
                try Task.checkCancellation()
                return product
            } catch {
                await product.finish()
                throw error
            }
        }
        startTask = task
        do {
            let product = try await awaitStart(task)
            guard finishTask == nil else {
                throw MacAgentPreparedProductCompositionErrorV1.terminal
            }
            self.product = product
        } catch {
            await finish()
            throw error
        }
    }

    private func awaitStart(
        _ task: Task<MacLocalXPCAgentProductV1, Error>
    ) async throws -> MacLocalXPCAgentProductV1 {
        try await withTaskCancellationHandler {
            let product = try await task.value
            try Task.checkCancellation()
            return product
        } onCancel: {
            task.cancel()
        }
    }

    package func finish() async {
        if let finishTask {
            await finishTask.value
            return
        }
        let product = self.product
        let startTask = self.startTask
        startTask?.cancel()
        let task = Task {
            if let product { await product.finish() }
            if let startTask {
                switch await startTask.result {
                case let .success(started) where started !== product:
                    await started.finish()
                case .success, .failure:
                    break
                }
            }
        }
        finishTask = task
        await task.value
    }
}

/// Inert, release-shaped Agent root after durable identity and primary-service
/// preparation. It retains the exact storage, prepared TLS/primary root, and
/// lifecycle/status XPC construction as one authority graph. It exposes no raw
/// store, TLS configuration, primary services, pairing surface, or listener.
///
/// Public construction remains inert. The inert preparation path defers local
/// XPC construction until package-owned activation first starts local
/// authorization, waits for an authenticated menu generation, and may then
/// compose an unstarted network product. The package seam now coordinates
/// listener activation and rollback; live request-context composition and
/// permanent-target activation remain later runtime checkpoints.
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
    private let localPairingCommandAuthority:
        MacAgentLocalPairingCommandAuthorityV1?
    private let interactiveRuntimeAuthority:
        AgentInteractiveRuntimeBindingAuthorityV1?
    private let interactiveRoleDataAuthority:
        AgentInteractiveRoleDataBindingAuthorityV0?
    private let focusCandidateSourceAuthority:
        MacAgentFocusCandidateSourceAuthorityV1?
    private let focusEventObserver: MacAgentFocusEventObserverV1?
    private let currentMenuGeneration: @Sendable () async -> UInt64?
    private var networkCompositionTask:
        Task<AgentNetworkPairingProductCompositionV0, Error>?
    private var networkProduct:
        AgentNetworkPairingProductCompositionV0?
    private var networkCompositionReserved = false
    private var networkListenerOwner:
        MacAgentNetworkListenerRuntimeOwnerV1?
    private var networkListenerConstructionTask:
        Task<AgentNetworkListenerServiceV1, Error>?
    private var networkListenerConstructionReserved = false
    private var localStartTask: Task<Void, Error>?
    private var finishTask: Task<Void, Never>?
    private var finished = false

    package init(
        storage: MacAgentReleaseStorageV1,
        preparedPrimary: AgentPreparedPrimaryStartupV1,
        localXPC: MacLocalXPCAgentProductV1,
        menuSurfaceAuthority:
            MacAgentAuthenticatedMenuSurfaceAuthorityV1 =
                MacAgentAuthenticatedMenuSurfaceAuthorityV1(),
        localPairingCommandAuthority:
            MacAgentLocalPairingCommandAuthorityV1? = nil,
        interactiveRuntimeAuthority:
            AgentInteractiveRuntimeBindingAuthorityV1? = nil,
        interactiveRoleDataAuthority:
            AgentInteractiveRoleDataBindingAuthorityV0? = nil,
        focusCandidateSourceAuthority:
            MacAgentFocusCandidateSourceAuthorityV1? = nil,
        focusEventObserver: MacAgentFocusEventObserverV1? = nil
    ) {
        self.storage = storage
        self.preparedPrimary = preparedPrimary
        self.menuSurfaceAuthority = menuSurfaceAuthority
        self.localPairingCommandAuthority = localPairingCommandAuthority
        self.interactiveRuntimeAuthority = interactiveRuntimeAuthority
        self.interactiveRoleDataAuthority = interactiveRoleDataAuthority
        self.focusCandidateSourceAuthority = focusCandidateSourceAuthority
        self.focusEventObserver = focusEventObserver
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
        makeLocalXPC: @escaping @Sendable (AgentPrimaryServicesV1)
            async throws -> MacLocalXPCAgentProductV1,
        menuSurfaceAuthority:
            MacAgentAuthenticatedMenuSurfaceAuthorityV1 =
                MacAgentAuthenticatedMenuSurfaceAuthorityV1(),
        localPairingCommandAuthority:
            MacAgentLocalPairingCommandAuthorityV1? = nil,
        interactiveRuntimeAuthority:
            AgentInteractiveRuntimeBindingAuthorityV1? = nil,
        interactiveRoleDataAuthority:
            AgentInteractiveRoleDataBindingAuthorityV0? = nil,
        focusCandidateSourceAuthority:
            MacAgentFocusCandidateSourceAuthorityV1? = nil,
        focusEventObserver: MacAgentFocusEventObserverV1? = nil
    ) {
        self.storage = storage
        self.preparedPrimary = preparedPrimary
        self.menuSurfaceAuthority = menuSurfaceAuthority
        self.localPairingCommandAuthority = localPairingCommandAuthority
        self.interactiveRuntimeAuthority = interactiveRuntimeAuthority
        self.interactiveRoleDataAuthority = interactiveRoleDataAuthority
        self.focusCandidateSourceAuthority = focusCandidateSourceAuthority
        self.focusEventObserver = focusEventObserver
        currentMenuGeneration = {
            await menuSurfaceAuthority.currentGeneration()
        }
        let deferred = MacAgentDeferredLocalXPCOwnerV1 {
            try await makeLocalXPC(preparedPrimary.primaryServices)
        }
        startLocalXPC = { try await deferred.start() }
        finishLocalXPC = { await deferred.finish() }
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
        localPairingCommandAuthority:
            MacAgentLocalPairingCommandAuthorityV1? = nil,
        interactiveRuntimeAuthority:
            AgentInteractiveRuntimeBindingAuthorityV1? = nil,
        interactiveRoleDataAuthority:
            AgentInteractiveRoleDataBindingAuthorityV0? = nil,
        focusCandidateSourceAuthority:
            MacAgentFocusCandidateSourceAuthorityV1? = nil,
        focusEventObserver: MacAgentFocusEventObserverV1? = nil,
        currentMenuGeneration:
            (@Sendable () async -> UInt64?)? = nil
    ) {
        self.storage = storage
        self.preparedPrimary = preparedPrimary
        self.menuSurfaceAuthority = menuSurfaceAuthority
        self.localPairingCommandAuthority = localPairingCommandAuthority
        self.interactiveRuntimeAuthority = interactiveRuntimeAuthority
        self.interactiveRoleDataAuthority = interactiveRoleDataAuthority
        self.focusCandidateSourceAuthority = focusCandidateSourceAuthority
        self.focusEventObserver = focusEventObserver
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
        let localPairingCommandAuthority = self.localPairingCommandAuthority
        let interactiveRuntimeAuthority = self.interactiveRuntimeAuthority
        let interactiveRoleDataAuthority = self.interactiveRoleDataAuthority
        let focusCandidateSourceAuthority =
            self.focusCandidateSourceAuthority
        let focusEventObserver = self.focusEventObserver
        let localStartTask = self.localStartTask
        let networkCompositionTask = self.networkCompositionTask
        let networkProduct = self.networkProduct
        let networkListenerOwner = self.networkListenerOwner
        let networkListenerConstructionTask =
            self.networkListenerConstructionTask
        localStartTask?.cancel()
        networkListenerConstructionTask?.cancel()
        let task = Task {
            await focusEventObserver?.finish()
            await focusCandidateSourceAuthority?.finish()
            await localPairingCommandAuthority?.finish()
            await interactiveRoleDataAuthority?.finish()
            await interactiveRuntimeAuthority?.finish()
            if let networkListenerOwner {
                await networkListenerOwner.finish()
            } else if let networkListenerConstructionTask,
                      let listener = try?
                        await networkListenerConstructionTask.value {
                await listener.cancel()
            }
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

    package func lifecycleSnapshot()
        async -> AgentRemoteLifecycleSnapshotV1
    {
        await preparedPrimary.primaryServices.lifecycle.currentSnapshot()
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
            do {
                try await awaitLocalStart(localStartTask)
                guard finishTask == nil, !finished else {
                    throw MacAgentPreparedProductCompositionErrorV1.terminal
                }
                return
            } catch {
                await finish()
                throw error
            }
        }
        let startLocalXPC = self.startLocalXPC
        let task = Task { try await startLocalXPC() }
        localStartTask = task
        do {
            try await awaitLocalStart(task)
            guard finishTask == nil, !finished else {
                throw MacAgentPreparedProductCompositionErrorV1.terminal
            }
        } catch {
            await finish()
            throw error
        }
    }

    private func awaitLocalStart(
        _ task: Task<Void, Error>
    ) async throws {
        try await withTaskCancellationHandler {
            try await task.value
            try Task.checkCancellation()
        } onCancel: {
            task.cancel()
        }
    }

    package func startAndComposeNetworkPairingProduct(
        port: UInt16,
        additionalEndpoints: [EndpointCandidate] = [],
        timeSource: any AgentLocalPairingTimeSamplingV0,
        policySource: any AgentLocalPairingPolicyReadingV0,
        pairingIDGenerator: @escaping @Sendable () -> UUID = { UUID() },
        deviceIDGenerator: @escaping @Sendable () -> UUID = { UUID() },
        binding: AgentNetworkListenerBindingV1 = .bonjour
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
            deviceIDGenerator: deviceIDGenerator,
            binding: binding
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
        deviceIDGenerator: @escaping @Sendable () -> UUID = { UUID() },
        binding: AgentNetworkListenerBindingV1 = .bonjour
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
                deviceIDGenerator: deviceIDGenerator,
                binding: binding
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
            if let localPairingCommandAuthority {
                do {
                    try await localPairingCommandAuthority.install(product)
                } catch {
                    await product.authorizedSurfaceLost()
                    throw error
                }
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

    #if DEBUG
    package func confirmIsolatedLoopbackEndpoint() async throws -> Bool {
        guard finishTask == nil, !finished, let networkProduct else {
            throw MacAgentPreparedProductCompositionErrorV1.terminal
        }
        return try await networkProduct.confirmIsolatedLoopbackEndpoint()
    }
    #endif

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

    /// Constructs the exact shared listener through the sealed network
    /// aggregate and retains it without starting network traffic. This split
    /// makes construction binding independently testable without a live port.
    package func prepareNetworkListener(
        queue: DispatchQueue,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64,
        primaryContext: @escaping @Sendable () -> NetworkHostRequestContextV0,
        pairingRequestContext: @escaping @Sendable () ->
            NetworkHostPairingRequestContextV0,
        acceptedTerminal: @escaping @Sendable (
            NetworkHostAcceptedConnectionTerminationReasonV0
        ) -> Void = { _ in },
        primaryTerminal: @escaping @Sendable (
            NetworkHostPrimaryTerminationReasonV0
        ) -> Void = { _ in },
        pairingTerminal: @escaping @Sendable (
            NetworkHostPairingTerminationReasonV0
        ) -> Void = { _ in },
        listenerTerminal: @escaping @Sendable (
            NetworkHostListenerTerminationReasonV0
        ) -> Void = { _ in },
        admissionFailure: @escaping @Sendable (
            AgentNetworkListenerAdmissionFailureV1
        ) -> Void = { _ in },
        makeReviewID: @escaping @Sendable () -> UUID = { UUID() }
    ) async throws {
        guard finishTask == nil, !finished else {
            throw MacAgentPreparedProductCompositionErrorV1.terminal
        }
        guard let networkProduct else {
            throw MacAgentPreparedProductCompositionErrorV1
                .networkProductUnavailable
        }
        guard !networkListenerConstructionReserved,
              networkListenerConstructionTask == nil,
              networkListenerOwner == nil else {
            throw MacAgentPreparedProductCompositionErrorV1
                .networkListenerAlreadyStarted
        }
        networkListenerConstructionReserved = true
        let terminalHandler = networkListenerTerminalHandler(
            forwarding: listenerTerminal
        )
        let interactivePairReady: (@Sendable (
            AgentInteractiveReadyRolePairV0
        ) async throws -> Void)?
        if let interactiveRoleDataAuthority {
            interactivePairReady = { pair in
                try await interactiveRoleDataAuthority.accept(pair)
            }
        } else {
            interactivePairReady = nil
        }
        let task = Task {
            let listener = try await networkProduct.makeListenerService(
                queue: queue,
                monotonicNowMilliseconds: monotonicNowMilliseconds,
                primaryContext: primaryContext,
                pairingRequestContext: pairingRequestContext,
                interactiveAuthenticator: interactiveRuntimeAuthority,
                interactivePairReady: interactivePairReady,
                acceptedTerminal: acceptedTerminal,
                primaryTerminal: primaryTerminal,
                pairingTerminal: pairingTerminal,
                listenerTerminal: terminalHandler,
                admissionFailure: admissionFailure,
                makeReviewID: makeReviewID
            )
            do {
                try Task.checkCancellation()
                return listener
            } catch {
                await listener.cancel()
                throw error
            }
        }
        networkListenerConstructionTask = task
        networkListenerConstructionReserved = false
        do {
            let listener = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            do {
                try Task.checkCancellation()
                guard finishTask == nil, !finished else {
                    throw MacAgentPreparedProductCompositionErrorV1.terminal
                }
                let owner = MacAgentNetworkListenerRuntimeOwnerV1(
                    runtime: listener
                )
                try await focusEventObserver?.install(
                    listener: owner,
                    context: primaryContext
                )
                networkListenerOwner = owner
            } catch {
                await listener.cancel()
                throw error
            }
        } catch {
            networkListenerConstructionReserved = false
            await finish()
            throw error
        }
    }

    /// Starts only the exact service constructed by prepareNetworkListener.
    /// Caller cancellation and any start failure join whole-product rollback.
    package func startNetworkListener(
        queue: DispatchQueue,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64,
        primaryContext: @escaping @Sendable () -> NetworkHostRequestContextV0,
        pairingRequestContext: @escaping @Sendable () ->
            NetworkHostPairingRequestContextV0,
        acceptedTerminal: @escaping @Sendable (
            NetworkHostAcceptedConnectionTerminationReasonV0
        ) -> Void = { _ in },
        primaryTerminal: @escaping @Sendable (
            NetworkHostPrimaryTerminationReasonV0
        ) -> Void = { _ in },
        pairingTerminal: @escaping @Sendable (
            NetworkHostPairingTerminationReasonV0
        ) -> Void = { _ in },
        listenerTerminal: @escaping @Sendable (
            NetworkHostListenerTerminationReasonV0
        ) -> Void = { _ in },
        admissionFailure: @escaping @Sendable (
            AgentNetworkListenerAdmissionFailureV1
        ) -> Void = { _ in },
        makeReviewID: @escaping @Sendable () -> UUID = { UUID() }
    ) async throws {
        do {
            if networkListenerOwner == nil {
                try await prepareNetworkListener(
                    queue: queue,
                    monotonicNowMilliseconds: monotonicNowMilliseconds,
                    primaryContext: primaryContext,
                    pairingRequestContext: pairingRequestContext,
                    acceptedTerminal: acceptedTerminal,
                    primaryTerminal: primaryTerminal,
                    pairingTerminal: pairingTerminal,
                    listenerTerminal: listenerTerminal,
                    admissionFailure: admissionFailure,
                    makeReviewID: makeReviewID
                )
            }
            guard let networkListenerOwner else {
                throw MacAgentPreparedProductCompositionErrorV1.terminal
            }
            try await networkListenerOwner.start()
            // Text preparation consumes the same privacy-filtered focus events
            // as optional Smart Zoom. The observer itself additionally
            // requires an authenticated primary sink and an active descriptor
            // carrying Keyboard + Text authority before it samples AX.
            try await focusEventObserver?.start()
            try Task.checkCancellation()
        } catch let error as MacAgentPreparedProductCompositionErrorV1 {
            throw error
        } catch {
            await finish()
            throw error
        }
    }

    package func networkListenerSnapshot()
        async -> AgentNetworkListenerServiceSnapshotV1?
    {
        await networkListenerOwner?.snapshot()
    }

    package func closeNetworkAdmissionForUpdate() async throws {
        guard finishTask == nil, !finished else {
            throw MacAgentPreparedProductCompositionErrorV1.terminal
        }
        guard let networkListenerOwner else {
            throw MacAgentPreparedProductCompositionErrorV1
                .networkProductUnavailable
        }
        try await networkListenerOwner.closeNetworkAdmission()
    }

    package func drainNetworkConnectionsForUpdate() async throws {
        guard finishTask == nil, !finished else {
            throw MacAgentPreparedProductCompositionErrorV1.terminal
        }
        guard let networkListenerOwner else {
            throw MacAgentPreparedProductCompositionErrorV1
                .networkProductUnavailable
        }
        try await networkListenerOwner.drainNetworkConnections()
    }

    package func reopenNetworkAdmissionAfterUpdateFailure() async throws {
        guard finishTask == nil, !finished else {
            throw MacAgentPreparedProductCompositionErrorV1.terminal
        }
        guard let networkListenerOwner else {
            throw MacAgentPreparedProductCompositionErrorV1
                .networkProductUnavailable
        }
        try await networkListenerOwner.reopenNetworkAdmission()
    }

    /// Returns the exact non-authorizing terminal callback installed on the
    /// listener. Tests can exercise the callback-to-product fence without
    /// opening a live port or receiving the listener/network authority.
    package func networkListenerTerminalHandler(
        forwarding listenerTerminal: @escaping @Sendable (
            NetworkHostListenerTerminationReasonV0
        ) -> Void = { _ in }
    ) -> @Sendable (NetworkHostListenerTerminationReasonV0) -> Void {
        { [weak self] reason in
            listenerTerminal(reason)
            Task { await self?.networkListenerTerminated() }
        }
    }

    /// Exact callback target for the listener service's terminal event. The
    /// installed handler holds this product weakly, so runtime ownership has
    /// no cycle while every terminal reason joins the same rollback.
    package func networkListenerTerminated() async {
        await finish()
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
    private enum LocalXPCPreparationModeV1 {
        case immediate
        case deferredUntilActivation
    }

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
        return try await prepare(
            storage: storage,
            hostIdentityConfiguration: hostIdentityConfiguration,
            inputs: inputs,
            processStarter: processStarter
        )
    }

    package static func prepare(
        storage: MacAgentReleaseStorageV1,
        hostIdentityConfiguration:
            SecurityHostIdentityKeyCustodyConfigurationV0,
        inputs: AgentNetworkPrimaryStartupInputsV1,
        processStarter: any MacDashboardLifecycleProcessStartingV1
    ) async throws -> MacAgentProductBootstrapResultV1 {
        let interactiveAdmission =
            AgentVisibleInteractiveAdmissionAuthorityV1()
        let interactiveRuntime =
            AgentInteractiveRuntimeBindingAuthorityV1()
        let boundInputs = inputs.replacingInteractiveAuthorities(
            admission: interactiveAdmission,
            runtime: interactiveRuntime
        )
        let result = try await AgentNetworkPrimaryStartupFactoryV1.prepare(
            requiredAudit: storage.requiredAudit,
            hostIdentityConfiguration: hostIdentityConfiguration,
            inputs: boundInputs
        )
        return try await composeProduction(
            storage: storage,
            preparation: result,
            processStarter: processStarter,
            mode: .immediate,
            interactiveAdmission: interactiveAdmission,
            interactiveRuntime: interactiveRuntime
        )
    }

    package static func prepareInert(
        storage: MacAgentReleaseStorageV1,
        hostIdentityConfiguration:
            SecurityHostIdentityKeyCustodyConfigurationV0,
        inputs: AgentNetworkPrimaryStartupInputsV1,
        processStarter: any MacDashboardLifecycleProcessStartingV1
    ) async throws -> MacAgentProductBootstrapResultV1 {
        let interactiveAdmission =
            AgentVisibleInteractiveAdmissionAuthorityV1()
        let interactiveRuntime =
            AgentInteractiveRuntimeBindingAuthorityV1()
        let boundInputs = inputs.replacingInteractiveAuthorities(
            admission: interactiveAdmission,
            runtime: interactiveRuntime
        )
        let result = try await AgentNetworkPrimaryStartupFactoryV1.prepare(
            requiredAudit: storage.requiredAudit,
            hostIdentityConfiguration: hostIdentityConfiguration,
            inputs: boundInputs
        )
        return try await composeProduction(
            storage: storage,
            preparation: result,
            processStarter: processStarter,
            mode: .deferredUntilActivation,
            interactiveAdmission: interactiveAdmission,
            interactiveRuntime: interactiveRuntime
        )
    }

    /// Prepares the permanent Agent's first live local-service slice. The
    /// deferred factory is fixed here, below the application boundary, so the
    /// executable cannot substitute a presentation-capable profile or raw
    /// status reader. Construction remains inert until the returned product's
    /// package-owned local-authorization start is invoked.
    package static func prepareStatusOnlyInert(
        storage: MacAgentReleaseStorageV1,
        hostIdentityConfiguration:
            SecurityHostIdentityKeyCustodyConfigurationV0,
        inputs: AgentNetworkPrimaryStartupInputsV1,
        processStarter: any MacDashboardLifecycleProcessStartingV1
    ) async throws -> MacAgentProductBootstrapResultV1 {
        let result = try await AgentNetworkPrimaryStartupFactoryV1.prepare(
            requiredAudit: storage.requiredAudit,
            hostIdentityConfiguration: hostIdentityConfiguration,
            inputs: inputs
        )
        return try await composeInert(
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
            makeLocalXPC: makeLocalXPC,
            menuSurfaceAuthority:
                MacAgentAuthenticatedMenuSurfaceAuthorityV1()
        )
    }

    package static func prepareInert(
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
        return try await composeInert(
            storage: storage,
            preparation: result,
            makeLocalXPC: makeLocalXPC
        )
    }

    #if DEBUG
    /// Uses the shipping graph with test custody and a UUID-only XPC address.
    /// This prepares no listener and grants no remote capability.
    package static func prepareIsolatedPresentation(
        storage: MacAgentReleaseStorageV1,
        hostIdentityStartup: @escaping @Sendable () async throws -> SecurityHostIdentityStartupResultV0,
        inputs: AgentNetworkPrimaryStartupInputsV1,
        testID: UUID,
        onEvent: @escaping MacLocalXPCServerV1.EventHandler
    ) async throws -> MacAgentProductBootstrapResultV1 {
        let admission = AgentVisibleInteractiveAdmissionAuthorityV1()
        let runtime = AgentInteractiveRuntimeBindingAuthorityV1()
        let result = try await AgentNetworkPrimaryStartupFactoryV1.prepare(
            hostIdentityStartup: hostIdentityStartup, requiredAudit: storage.requiredAudit,
            inputs: inputs.replacingInteractiveAuthorities(admission: admission, runtime: runtime))
        return try await composeProduction(storage: storage, preparation: result,
            processStarter: InertMacDashboardLifecycleProcessStarterV1(),
            mode: .deferredUntilActivation, interactiveAdmission: admission, interactiveRuntime: runtime,
            serverFactory: { profile, reader, commands, update, admission, media, consume in
                MacLocalXPCServerV1(isolatedTestID: testID, profile: profile, statusReader: reader,
                    menuPairingCommandHandler: commands, updateQuiescenceHandler: update,
                    interactiveAdmissionHandler: admission, interactiveMediaHandler: media,
                    onEvent: { event in consume(event); onEvent(event) })
            })
    }
    #endif

    private static func composeProduction(
        storage: MacAgentReleaseStorageV1,
        preparation: AgentNetworkPrimaryStartupResultV1,
        processStarter: any MacDashboardLifecycleProcessStartingV1,
        mode: LocalXPCPreparationModeV1,
        interactiveAdmission: AgentVisibleInteractiveAdmissionAuthorityV1,
        interactiveRuntime: AgentInteractiveRuntimeBindingAuthorityV1,
        serverFactory: @escaping MacLocalXPCAgentProductV1.PresentationServerFactory =
            MacLocalXPCAgentProductV1.productionPresentationServerFactory
    ) async throws -> MacAgentProductBootstrapResultV1 {
        let menuSurfaceAuthority =
            MacAgentAuthenticatedMenuSurfaceAuthorityV1()
        let localPairingCommandAuthority =
            MacAgentLocalPairingCommandAuthorityV1()
        let menuLossCoordinator = MacAgentMenuSurfaceLossCoordinatorV1()
        let updateQuiescenceCoordinator =
            MacAgentUpdateQuiescenceCoordinatorV0()
        let interactiveRoleData =
            AgentInteractiveRoleDataBindingAuthorityV0(
                runtime: interactiveRuntime
            )
        let localInteractiveRoleData =
            MacLocalXPCInteractiveRoleDataRouteV1()
        let focusCandidateSource =
            MacAgentFocusCandidateSourceAuthorityV1()
        let focusEventObserver = MacAgentFocusEventObserverV1(
            source: focusCandidateSource,
            control: interactiveRuntime
        )
        let makeLocalXPC: LocalXPCFactory = { services in
            try await localPairingCommandAuthority.installDeviceAdministrationFactory({
                services.makeLocalDeviceRevocationHandler()
            }, capabilityGrants: { services.makeLocalCapabilityGrantHandler() })
            try await localPairingCommandAuthority
                .installInteractiveControlGrantHandler(
                    try services.makeLocalInteractiveControlGrantHandler()
                )
            return try await MacLocalXPCAgentProductV1
                .afterAgentBootstrapWithMenuPresentation(
                services: services,
                processStarter: processStarter,
                menuPairingCommandHandler: localPairingCommandAuthority,
                updateQuiescenceHandler: updateQuiescenceCoordinator,
                interactiveAdmissionHandler: interactiveAdmission,
                interactiveMediaHandler: localInteractiveRoleData,
                onSurfaces: {
                    let surfaces = $0
                    do {
                        try await menuSurfaceAuthority.install(surfaces)
                        try await localPairingCommandAuthority.bindDeviceAdministration(generation: surfaces.generation)
                        let route =
                            MacLocalXPCInteractiveMenuRuntimeRouteV1(
                                sender: surfaces.interactiveRuntime
                            )
                        try await focusCandidateSource.bind(
                            route,
                            generation: surfaces.generation
                        )
                        let owner = AgentInteractiveRuntimeOwnerV1(
                            admission:
                                SQLiteInteractiveSessionAdmissionReaderV0(
                                    store: storage.requiredAudit.securityStore,
                                    visible: interactiveAdmission
                            ),
                            desktop: route,
                            runtime: route,
                            surfaceRuntime: route,
                            displayRuntime: route
                        )
                        try await interactiveRuntime.bind(
                            runtime:
                                AgentInteractiveLeaseRenewalOwnerV1(
                                    runtime: owner
                                ),
                            channelAuthenticator: owner,
                            surfaceControl: owner,
                            displayControl: owner,
                            mediaNegotiation: route,
                            nativeRuntime: route,
                            generation: surfaces.generation
                        )
                        try await localInteractiveRoleData.bind(
                            generation: surfaces.generation,
                            input: surfaces.interactiveInput
                        )
                        try await interactiveRoleData.bind(
                            route: localInteractiveRoleData,
                            generation: surfaces.generation
                        )
                    } catch {
                        await localPairingCommandAuthority.invalidateDeviceAdministration(generation: surfaces.generation)
                        await localInteractiveRoleData.invalidate(
                            generation: surfaces.generation
                        )
                        _ = await interactiveRoleData.invalidate(
                            generation: surfaces.generation
                        )
                        _ = await interactiveRuntime.invalidate(
                            generation: surfaces.generation
                        )
                        _ = await focusCandidateSource.invalidate(
                            generation: surfaces.generation
                        )
                        _ = await menuSurfaceAuthority.invalidate(
                            generation: surfaces.generation
                        )
                        throw error
                    }
                },
                onSurfaceInvalidated: {
                    await localPairingCommandAuthority.invalidateDeviceAdministration(generation: $0)
                    _ = await interactiveRoleData.invalidate(generation: $0)
                    await localInteractiveRoleData.invalidate(generation: $0)
                    _ = await focusCandidateSource.invalidate(generation: $0)
                    _ = await interactiveRuntime.invalidate(generation: $0)
                    await menuLossCoordinator
                        .authenticatedMenuSurfaceUnavailable(generation: $0)
                },
                serverFactory: serverFactory
            )
        }
        let composed: MacAgentProductBootstrapResultV1
        switch mode {
        case .immediate:
            composed = try await compose(
                storage: storage,
                preparation: preparation,
                makeLocalXPC: makeLocalXPC,
                menuSurfaceAuthority: menuSurfaceAuthority,
                localPairingCommandAuthority: localPairingCommandAuthority,
                interactiveRuntimeAuthority: interactiveRuntime,
                interactiveRoleDataAuthority: interactiveRoleData,
                focusCandidateSourceAuthority: focusCandidateSource,
                focusEventObserver: focusEventObserver
            )
        case .deferredUntilActivation:
            composed = try await composeInert(
                storage: storage,
                preparation: preparation,
                makeLocalXPC: makeLocalXPC,
                menuSurfaceAuthority: menuSurfaceAuthority,
                localPairingCommandAuthority: localPairingCommandAuthority,
                interactiveRuntimeAuthority: interactiveRuntime,
                interactiveRoleDataAuthority: interactiveRoleData,
                focusCandidateSourceAuthority: focusCandidateSource,
                focusEventObserver: focusEventObserver
            )
        }
        if case let .ready(product) = composed {
            await menuLossCoordinator.install(product)
            await updateQuiescenceCoordinator.install(product)
        }
        return composed
    }

    package static func composeInert(
        storage: MacAgentReleaseStorageV1,
        preparation: AgentNetworkPrimaryStartupResultV1,
        makeLocalXPC: @escaping LocalXPCFactory,
        menuSurfaceAuthority:
            MacAgentAuthenticatedMenuSurfaceAuthorityV1 =
                MacAgentAuthenticatedMenuSurfaceAuthorityV1(),
        localPairingCommandAuthority:
            MacAgentLocalPairingCommandAuthorityV1? = nil,
        interactiveRuntimeAuthority:
            AgentInteractiveRuntimeBindingAuthorityV1? = nil,
        interactiveRoleDataAuthority:
            AgentInteractiveRoleDataBindingAuthorityV0? = nil,
        focusCandidateSourceAuthority:
            MacAgentFocusCandidateSourceAuthorityV1? = nil,
        focusEventObserver: MacAgentFocusEventObserverV1? = nil
    ) async throws -> MacAgentProductBootstrapResultV1 {
        switch preparation {
        case .waitForFirstUnlock:
            return .waitForFirstUnlock
        case let .requireLocalRecovery(reason):
            return .requireLocalRecovery(reason)
        case let .recoveryFenced(recoveryID):
            return .recoveryFenced(recoveryID)
        case let .ready(preparedPrimary):
            return .ready(MacAgentPreparedProductV1(
                storage: storage,
                preparedPrimary: preparedPrimary,
                makeLocalXPC: makeLocalXPC,
                menuSurfaceAuthority: menuSurfaceAuthority,
                localPairingCommandAuthority: localPairingCommandAuthority,
                interactiveRuntimeAuthority: interactiveRuntimeAuthority,
                interactiveRoleDataAuthority: interactiveRoleDataAuthority,
                focusCandidateSourceAuthority:
                    focusCandidateSourceAuthority,
                focusEventObserver: focusEventObserver
            ))
        }
    }

    package static func compose(
        storage: MacAgentReleaseStorageV1,
        preparation: AgentNetworkPrimaryStartupResultV1,
        makeLocalXPC: @escaping LocalXPCFactory,
        menuSurfaceAuthority:
            MacAgentAuthenticatedMenuSurfaceAuthorityV1 =
                MacAgentAuthenticatedMenuSurfaceAuthorityV1(),
        localPairingCommandAuthority:
            MacAgentLocalPairingCommandAuthorityV1? = nil,
        interactiveRuntimeAuthority:
            AgentInteractiveRuntimeBindingAuthorityV1? = nil,
        interactiveRoleDataAuthority:
            AgentInteractiveRoleDataBindingAuthorityV0? = nil,
        focusCandidateSourceAuthority:
            MacAgentFocusCandidateSourceAuthorityV1? = nil,
        focusEventObserver: MacAgentFocusEventObserverV1? = nil
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
                    menuSurfaceAuthority: menuSurfaceAuthority,
                    localPairingCommandAuthority: localPairingCommandAuthority,
                    interactiveRuntimeAuthority:
                        interactiveRuntimeAuthority,
                    interactiveRoleDataAuthority:
                        interactiveRoleDataAuthority,
                    focusCandidateSourceAuthority:
                        focusCandidateSourceAuthority,
                    focusEventObserver: focusEventObserver
                ))
            } catch {
                await preparedPrimary.discard()
                throw error
            }
        }
    }
}

private extension AgentNetworkPrimaryStartupInputsV1 {
    func replacingInteractiveAuthorities(
        admission: AgentVisibleInteractiveAdmissionAuthorityV1,
        runtime: AgentInteractiveRuntimeBindingAuthorityV1
    ) -> Self {
#if MACCOMPANION_WEBRTC_DEVELOPMENT
        let mediaNegotiation: (any InteractiveWebRTCNegotiatingV0)? = runtime
#else
        let mediaNegotiation = interactivePlatform.mediaNegotiation
#endif
        return Self(
            registry: registry,
            providerLoader: providerLoader,
            wallNowUnixMilliseconds: wallNowUnixMilliseconds,
            lifecycleState: lifecycleState,
            statusPlatform: statusPlatform,
            interactivePlatform: AgentInteractivePlatformServicesV1(
                visibleAdmission: admission,
                materials: interactivePlatform.materials,
                runtime: runtime,
                mediaNegotiation: mediaNegotiation,
                nativeRuntime: interactivePlatform.nativeRuntime ?? runtime,
                surfaceControl: runtime,
                displaySelection: runtime
            )
        )
    }
}
#endif
