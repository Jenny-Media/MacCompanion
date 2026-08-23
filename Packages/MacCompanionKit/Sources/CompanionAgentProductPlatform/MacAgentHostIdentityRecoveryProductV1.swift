#if os(macOS)
import CompanionAgentNetworkPlatform
import CompanionAgentPlatform
import CompanionHostPlatform
import CompanionIPC
import CompanionLocalXPCPlatform
import CompanionSecurity
import Foundation

package enum MacAgentHostIdentityRecoveryModeV1: Equatable, Sendable {
    case fresh(HostIdentityRecoveryReason)
    case resume(UUID)
}

package enum MacAgentHostIdentityRecoveryProductErrorV1:
    Error,
    Equatable,
    Sendable
{
    case unavailable
    case duplicateGeneration(UInt64)
    case recoveryMismatch
}

/// Stable server-side method route. It owns no store or raw recovery
/// coordinator and accepts commands only through the exact currently bound
/// connection-scoped delivery authority.
@available(macOS 26.0, *)
package actor MacAgentHostIdentityRecoveryCommandAuthorityV1:
    MacLocalXPCHostIdentityRecoveryHandlingV1
{
    private struct Current: Sendable {
        let generation: UInt64
        let delivery: AgentLocalHostIdentityRecoveryDeliveryV0
    }

    private var current: Current?
    private var terminal = false

    package func bind(
        _ delivery: AgentLocalHostIdentityRecoveryDeliveryV0,
        generation: UInt64
    ) throws {
        guard !terminal, generation > 0 else {
            throw MacAgentHostIdentityRecoveryProductErrorV1.unavailable
        }
        guard current == nil else {
            throw MacAgentHostIdentityRecoveryProductErrorV1
                .duplicateGeneration(generation)
        }
        current = Current(generation: generation, delivery: delivery)
    }

    public func recoverHostIdentity(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) async throws -> LocalHostIdentityRecoveredReceiptV0 {
        guard !terminal, let current else {
            throw MacAgentHostIdentityRecoveryProductErrorV1.unavailable
        }
        return try await current.delivery.recoverHostIdentity(command)
    }

    @discardableResult
    package func invalidate(generation: UInt64) async -> Bool {
        guard let current, current.generation == generation else {
            return false
        }
        self.current = nil
        await current.delivery.invalidate()
        return true
    }

    package func finish() async {
        guard !terminal else { return }
        terminal = true
        let current = self.current
        self.current = nil
        await current?.delivery.invalidate()
    }

    package func currentGeneration() -> UInt64? { current?.generation }
}

/// Inertly constructed recovery-only Agent product. Startup opens only the
/// exact local-XPC profile; the Keychain/store mutation remains behind an
/// authenticated ready generation, an Agent-issued visible review or durable
/// resume, and the menu's exact confirmed command.
@available(macOS 26.0, *)
public actor MacAgentHostIdentityRecoveryProductV1 {
    private let localXPC: MacLocalXPCAgentProductV1
    private let commandAuthority:
        MacAgentHostIdentityRecoveryCommandAuthorityV1
    private var finishTask: Task<Void, Never>?

    package init(
        storage: MacAgentReleaseStorageV1,
        hostIdentityConfiguration:
            SecurityHostIdentityKeyCustodyConfigurationV0,
        mode: MacAgentHostIdentityRecoveryModeV1,
        reviewIDSource: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        let commandAuthority =
            MacAgentHostIdentityRecoveryCommandAuthorityV1()
        self.commandAuthority = commandAuthority
        localXPC = MacLocalXPCAgentProductV1.composeHostIdentityRecovery(
            recoveryHandler: commandAuthority,
            onSurfaces: { surfaces in
                let delivery = AgentHostIdentityRecoveryProductFactoryV0.make(
                    requiredAudit: storage.requiredAudit,
                    hostIdentityConfiguration: hostIdentityConfiguration,
                    alreadyAuthorizedSurface: surfaces.hostIdentityRecovery
                )
                do {
                    try await commandAuthority.bind(
                        delivery,
                        generation: surfaces.generation
                    )
                    switch mode {
                    case .fresh:
                        _ = try await delivery.publishReview(
                            reviewID: reviewIDSource(),
                            cause: .keyUnavailable
                        )
                    case let .resume(expectedRecoveryID):
                        let command = try await delivery.publishResumable()
                        guard command.recoveryID == expectedRecoveryID else {
                            throw MacAgentHostIdentityRecoveryProductErrorV1
                                .recoveryMismatch
                        }
                    }
                } catch {
                    _ = await commandAuthority.invalidate(
                        generation: surfaces.generation
                    )
                    throw error
                }
            },
            onSurfaceInvalidated: { generation in
                _ = await commandAuthority.invalidate(
                    generation: generation
                )
            }
        )
    }

    public func start() async throws {
        guard finishTask == nil else {
            throw MacAgentHostIdentityRecoveryProductErrorV1.unavailable
        }
        try await localXPC.start()
    }

    public func finish() async {
        if let finishTask {
            await finishTask.value
            return
        }
        let localXPC = self.localXPC
        let commandAuthority = self.commandAuthority
        let task = Task {
            await localXPC.finish()
            await commandAuthority.finish()
        }
        finishTask = task
        await task.value
    }

    package func authenticatedMenuGeneration() async -> UInt64? {
        await commandAuthority.currentGeneration()
    }
}
#endif
