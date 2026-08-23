#if os(macOS)
import CompanionAgent
import CompanionAgentNetworkPlatform
import CompanionAgentPlatform
import CompanionAgentProductPlatform
import CompanionHost
import CompanionHostPlatform
import CompanionLocalXPCPlatform
import Foundation

public enum MacCompanionAgentInertPreparationDeferralV1:
    Equatable,
    Sendable
{
    case firstUnlockRequired
    case localRecoveryRequired
    case recoveryFenced
}

package enum MacCompanionAgentPreparedServiceModeV1: Sendable {
    case disabledRemoteAccessBootstrap
    case enabledProduct
}

/// Narrow permanent-target preparation owner. Profile selection and activation
/// remain package-owned; the executable can retain or finish this authority but
/// cannot select a server profile, inject a reader, or start a second service.
@available(macOS 26.0, *)
public actor MacCompanionAgentInertSystemOwnerV1 {
    private let prepared: MacAgentInertApplicationLifecycleV1

    package init(prepared: MacAgentInertApplicationLifecycleV1) {
        self.prepared = prepared
    }

    package func selectedServiceMode() async throws
        -> MacCompanionAgentPreparedServiceModeV1
    {
        let snapshot = try await prepared
            .canonicalInitialLifecycleSnapshot()
        return snapshot.state.desiredEnabled
            ? .enabledProduct
            : .disabledRemoteAccessBootstrap
    }

    package func disabledRemoteAccessBootstrapIntentStore() async throws
        -> any MacRemoteAccessIntentPersistenceV1
    {
        try await prepared.disabledRemoteAccessBootstrapIntentStore()
    }

    package func startEnabledProduct() async throws {
        let snapshot = try await prepared
            .canonicalInitialLifecycleSnapshot()
        guard snapshot.state.desiredEnabled else {
            throw MacAgentApplicationPreparationErrorV1
                .unsafeInitialLifecycleState
        }
        try await prepared.startPreparedLocalService()
    }

    public func finish() async {
        await prepared.finish()
    }
}

@available(macOS 26.0, *)
public enum MacCompanionAgentInertSystemPreparationResultV1: Sendable {
    case ready(MacCompanionAgentInertSystemOwnerV1)
    case recovery(MacAgentHostIdentityRecoveryProductV1)
    case deferred(MacCompanionAgentInertPreparationDeferralV1)
}

/// The only public lifetime retained by the permanent Agent executable. The
/// selected mode is intentionally private so the executable cannot use it as
/// an authorization fact or construct a competing Mach-service owner.
@available(macOS 26.0, *)
public actor MacCompanionAgentLocalServiceOwnerV1 {
    private let finishSelected: @Sendable () async -> Void
    private let restartRequest: MacCompanionAgentRestartRequestV1
    private var finishTask: Task<Void, Never>?

    package init(
        restartRequest: MacCompanionAgentRestartRequestV1,
        finish: @escaping @Sendable () async -> Void
    ) {
        self.restartRequest = restartRequest
        finishSelected = finish
    }

    deinit {
        guard finishTask == nil else { return }
        let finishSelected = self.finishSelected
        Task { await finishSelected() }
    }

    public func finish() async {
        if let finishTask {
            await finishTask.value
            return
        }
        let finishSelected = self.finishSelected
        let task = Task { await finishSelected() }
        finishTask = task
        await task.value
    }

    public func waitForRestartRequest() async {
        await restartRequest.wait()
    }
}

package actor MacCompanionAgentRestartRequestV1 {
    private var requested = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    package func request() {
        guard !requested else { return }
        requested = true
        let waiters = self.waiters
        self.waiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    package func wait() async {
        guard !requested else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

@available(macOS 26.0, *)
public enum MacCompanionAgentLocalServiceStartupOutcomeV1: Sendable {
    case retryAfterFirstUnlock
    case running(MacCompanionAgentLocalServiceOwnerV1)
}

/// Release-shaped, construction-only entry point for the permanent per-user
/// Agent. The broader product module remains hidden from the executable. This
/// seam may reconcile private release storage and host Keychain identity, but
/// it supplies explicit fail-closed Interactive and process-start platforms.
@available(macOS 26.0, *)
public enum MacCompanionAgentInertSystemPreparationV1 {
    public static let hostIdentityApplicationTagPrefix =
        "media.jenny.maccompanion.agent.identity.v1"

    public static func prepare() async throws
        -> MacCompanionAgentInertSystemPreparationResultV1
    {
        let clock = SystemMacDashboardLifecycleWallClockV1()
        let inputs = try makeInputs(
            registryGeneration: UUID(),
            wallNowUnixMilliseconds: clock.nowUnixMilliseconds()
        )
        return map(
            try await MacAgentApplicationPreparationFacadeV1.prepare(
                inputs: inputs
            )
        )
    }

    package static func makeInputs(
        registryGeneration: UUID,
        wallNowUnixMilliseconds: Int64
    ) throws -> MacAgentApplicationPreparationInputsV1 {
        MacAgentApplicationPreparationInputsV1(
            hostIdentityConfiguration:
                try SecurityHostIdentityKeyCustodyConfigurationV0(
                    applicationTagPrefix: hostIdentityApplicationTagPrefix
                ),
            nativeMVPProviders:
                try AgentNativeMVPProviderCompositionV1.systemDefault(
                    registryGeneration: registryGeneration
                ),
            wallNowUnixMilliseconds: wallNowUnixMilliseconds,
            statusPlatform: AgentHostStatusPlatformServicesV1(
                sampler: MacSystemStatusSampler(),
                clock: SystemHostStatusClock(),
                initialGeneration: UUID()
            ),
            interactivePlatform: .deferredMenuBinding(
                materials: SecurityInteractiveSessionMaterialGeneratorV0()
            ),
            processStarter: InertMacDashboardLifecycleProcessStarterV1()
        )
    }

    package static func map(
        _ result: MacAgentApplicationPreparationResultV1
    ) -> MacCompanionAgentInertSystemPreparationResultV1 {
        switch result {
        case let .prepared(prepared):
            return .ready(
                MacCompanionAgentInertSystemOwnerV1(prepared: prepared)
            )
        case let .hostIdentityRecovery(product):
            return .recovery(product)
        case .waitForFirstUnlock:
            return .deferred(.firstUnlockRequired)
        case .requireLocalRecovery:
            return .deferred(.localRecoveryRequired)
        case .recoveryFenced:
            return .deferred(.recoveryFenced)
        }
    }
}

@available(macOS 26.0, *)
package protocol MacCompanionAgentSelectedServiceRuntimeV1:
    AnyObject,
    Sendable
{
    func start() async throws
    func finish() async
}

@available(macOS 26.0, *)
package actor MacCompanionAgentAuthenticationOnlyRuntimeV1:
    MacCompanionAgentSelectedServiceRuntimeV1
{
    private let server: MacLocalXPCServerV1
    private var startTask: Task<Void, Error>?
    private var finishTask: Task<Void, Never>?

    package init() {
        server = MacLocalXPCServerV1(profile: .authenticationOnly) { _ in }
    }

    package func start() async throws {
        guard startTask == nil, finishTask == nil else {
            throw MacLocalXPCConstructionErrorV1.alreadyStarted
        }
        let server = self.server
        let task = Task {
            try Task.checkCancellation()
            try server.start()
            try Task.checkCancellation()
        }
        startTask = task
        do {
            try await withTaskCancellationHandler {
                try await task.value
                try Task.checkCancellation()
            } onCancel: {
                task.cancel()
                Task { await self.finish() }
            }
            guard finishTask == nil else {
                throw MacLocalXPCConstructionErrorV1.alreadyStarted
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
        let server = self.server
        let startTask = self.startTask
        startTask?.cancel()
        let task = Task {
            server.cancel()
            if let startTask { _ = await startTask.result }
        }
        finishTask = task
        await task.value
    }

    deinit {
        startTask?.cancel()
        server.cancel()
    }
}

/// Disabled startup runtime with exactly one injected durable bootstrap
/// authority. It cannot receive the distinct host-recovery authority.
@available(macOS 26.0, *)
package actor MacCompanionAgentDisabledBootstrapRuntimeV1:
    MacCompanionAgentSelectedServiceRuntimeV1
{
    private let server: MacLocalXPCServerV1
    private var startTask: Task<Void, Error>?
    private var finishTask: Task<Void, Never>?

    package init(
        intentStore: any MacRemoteAccessIntentPersistenceV1,
        restartRequest: MacCompanionAgentRestartRequestV1
    ) {
        let onRestartRequired: @Sendable () -> Void = {
            Task { await restartRequest.request() }
        }
        let authority = MacRemoteAccessBootstrapAuthorityV1(
            intentStore: intentStore,
            onUnacknowledgedDurableChange: onRestartRequired
        )
        server = MacLocalXPCServerV1(
            profile: .disabledRemoteAccessBootstrap,
            bootstrapHandler: authority
        ) { event in
            guard case .remoteAccessEnabled = event else { return }
            onRestartRequired()
        }
    }

    package func start() async throws {
        guard startTask == nil, finishTask == nil else {
            throw MacLocalXPCConstructionErrorV1.alreadyStarted
        }
        let server = self.server
        let task = Task {
            try Task.checkCancellation()
            try server.start()
            try Task.checkCancellation()
        }
        startTask = task
        do {
            try await withTaskCancellationHandler {
                try await task.value
                try Task.checkCancellation()
            } onCancel: {
                task.cancel()
                Task { await self.finish() }
            }
            guard finishTask == nil else {
                throw MacLocalXPCConstructionErrorV1.alreadyStarted
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
        let server = self.server
        let startTask = self.startTask
        startTask?.cancel()
        let task = Task {
            server.cancel()
            if let startTask { _ = await startTask.result }
        }
        finishTask = task
        await task.value
    }

    deinit {
        startTask?.cancel()
        server.cancel()
    }
}

@available(macOS 26.0, *)
extension MacCompanionAgentInertSystemOwnerV1:
    MacCompanionAgentSelectedServiceRuntimeV1
{
    package func start() async throws {
        try await startEnabledProduct()
    }
}

@available(macOS 26.0, *)
extension MacAgentHostIdentityRecoveryProductV1:
    MacCompanionAgentSelectedServiceRuntimeV1
{}

/// Prepares first, validates the exact revision-zero canonical lifecycle, and
/// then constructs and starts exactly one local Mach-service owner:
/// readiness/status for enabled startup, disabled bootstrap for canonical
/// disabled startup, the recovery-only presentation/command product for
/// durable recovery, and no service before first unlock. A selected-service
/// failure or cancellation retires all retained preparation and never falls
/// back to the other profile.
@available(macOS 26.0, *)
public enum MacCompanionAgentLocalServiceStartupV1 {
    public static func start() async throws
        -> MacCompanionAgentLocalServiceStartupOutcomeV1
    {
        try await start(
            prepare: {
                try await MacCompanionAgentInertSystemPreparationV1.prepare()
            },
            makeAuthenticationOnly: {
                MacCompanionAgentAuthenticationOnlyRuntimeV1()
            },
            makeDisabledBootstrap: { intentStore, onRestartRequired in
                MacCompanionAgentDisabledBootstrapRuntimeV1(
                    intentStore: intentStore,
                    restartRequest: onRestartRequired
                )
            }
        )
    }

    package static func start(
        prepare: @escaping @Sendable () async throws ->
            MacCompanionAgentInertSystemPreparationResultV1,
        makeAuthenticationOnly: @escaping @Sendable () ->
            any MacCompanionAgentSelectedServiceRuntimeV1,
        makeDisabledBootstrap: @escaping @Sendable (
            any MacRemoteAccessIntentPersistenceV1,
            MacCompanionAgentRestartRequestV1
        ) -> any MacCompanionAgentSelectedServiceRuntimeV1 = {
            intentStore, restartRequest in
            MacCompanionAgentDisabledBootstrapRuntimeV1(
                intentStore: intentStore,
                restartRequest: restartRequest
            )
        }
    ) async throws -> MacCompanionAgentLocalServiceStartupOutcomeV1 {
        let result = try await prepare()
        let restartRequest = MacCompanionAgentRestartRequestV1()
        switch result {
        case let .ready(owner):
            do {
                try Task.checkCancellation()
                switch try await owner.selectedServiceMode() {
                case .enabledProduct:
                    return try await startAndRetain(
                        owner,
                        restartRequest: restartRequest
                    )
                case .disabledRemoteAccessBootstrap:
                    let intentStore = try await owner
                        .disabledRemoteAccessBootstrapIntentStore()
                    return try await startAndRetain(
                        makeDisabledBootstrap(intentStore, restartRequest),
                        restartRequest: restartRequest,
                        additionallyFinish: { await owner.finish() }
                    )
                }
            } catch {
                await owner.finish()
                throw error
            }
        case let .recovery(product):
            return try await startAndRetain(
                product,
                restartRequest: restartRequest
            )
        case .deferred(.firstUnlockRequired):
            try Task.checkCancellation()
            return .retryAfterFirstUnlock
        case .deferred(.localRecoveryRequired), .deferred(.recoveryFenced):
            // Retained only for package-injected legacy preparation seams.
            // The production facade maps both cases to `.recovery`.
            return try await startAndRetain(
                makeAuthenticationOnly(),
                restartRequest: restartRequest
            )
        }
    }

    private static func startAndRetain(
        _ selected: any MacCompanionAgentSelectedServiceRuntimeV1,
        restartRequest: MacCompanionAgentRestartRequestV1,
        additionallyFinish: @escaping @Sendable () async -> Void = {}
    ) async throws -> MacCompanionAgentLocalServiceStartupOutcomeV1 {
        do {
            try await selected.start()
            try Task.checkCancellation()
            let owner = MacCompanionAgentLocalServiceOwnerV1(
                restartRequest: restartRequest
            ) {
                await selected.finish()
                await additionallyFinish()
            }
            do {
                try Task.checkCancellation()
                return .running(owner)
            } catch {
                await owner.finish()
                throw error
            }
        } catch {
            await selected.finish()
            await additionallyFinish()
            throw error
        }
    }
}
#endif
