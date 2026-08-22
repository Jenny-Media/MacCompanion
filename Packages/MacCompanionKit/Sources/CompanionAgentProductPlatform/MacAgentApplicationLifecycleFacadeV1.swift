#if os(macOS)
import CompanionLifecycle
import CompanionNetworkPlatform
import Foundation

/// A construction-inert owner for the Agent's conservative public-session
/// evidence. This facade deliberately begins safe-disabled and ambiguous.
/// Starting it observes public workspace lifecycle notifications only; it does
/// not create storage, touch Keychain, start XPC, start a listener, or launch a
/// process.
public final class MacAgentApplicationLifecycleFacadeV1:
    @unchecked Sendable
{
    public let initialLifecycleState: ProductLifecycleState

    private let requestContexts: MacAgentConservativeRequestContextProductV1

    public convenience init() {
        self.init(
            requestContexts: MacAgentConservativeRequestContextProductV1()
        )
    }

    package init(
        requestContexts: MacAgentConservativeRequestContextProductV1
    ) {
        self.requestContexts = requestContexts
        self.initialLifecycleState = ProductLifecycleState(
            desiredEnabled: false,
            consoleSession: .otherConsoleUserActive,
            agent: .stopped,
            menuApp: .stopped
        )
    }

    deinit {
        // Context closures deliberately retain the inner context owner rather
        // than this facade. If they escape, dropping the facade must still
        // terminalize every primary context before its lifecycle owner is gone.
        requestContexts.finish()
    }

    /// Starts only the conservative request-context observer.
    public func start() throws {
        try requestContexts.start()
    }

    /// Retires the observer and permanently fails future primary contexts
    /// closed. Repeated calls are harmless.
    public func finish() {
        requestContexts.finish()
    }

    public func snapshot() -> MacAgentApplicationLifecycleFacadeSnapshotV1 {
        MacAgentApplicationLifecycleFacadeSnapshotV1(
            initialLifecycleState: initialLifecycleState,
            requestContexts: requestContexts.snapshot()
        )
    }

    package var primaryContext:
        @Sendable () -> NetworkHostRequestContextV0
    {
        requestContexts.primaryContext
    }

    package var pairingContext:
        @Sendable () -> NetworkHostPairingRequestContextV0
    {
        requestContexts.pairingContext
    }
}

public struct MacAgentApplicationLifecycleFacadeSnapshotV1:
    Equatable,
    Sendable
{
    public let initialLifecycleState: ProductLifecycleState
    public let requestContexts: MacAgentConservativeRequestContextSnapshotV1

    public init(
        initialLifecycleState: ProductLifecycleState,
        requestContexts: MacAgentConservativeRequestContextSnapshotV1
    ) {
        self.initialLifecycleState = initialLifecycleState
        self.requestContexts = requestContexts
    }
}
#endif
