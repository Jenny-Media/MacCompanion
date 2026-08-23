#if os(macOS)
import CompanionAgent
import CompanionLifecycle
import CompanionLocalXPCPlatform

public enum MacUpdateAgentBuildReadinessErrorV0:
    Error, Equatable, Sendable
{
    case invalidPolicy
    case unavailable
}

/// Bounded launch-readiness retry for the startup-only authenticated build
/// probe. A protocol-order violation is terminal; ordinary launch races may
/// retry without ever widening the signed-peer or exact-message checks.
@available(macOS 26.0, *)
public struct MacUpdateAgentBuildReadinessV0: Sendable {
    public static let defaultMaximumAttempts = 4
    public static let defaultRetryDelayNanoseconds: UInt64 = 250_000_000

    private let maximumAttempts: Int
    private let retryDelayNanoseconds: UInt64
    private let probe: @Sendable () async throws -> UInt64
    private let pause: @Sendable (UInt64) async throws -> Void

    public init(
        maximumAttempts: Int = Self.defaultMaximumAttempts,
        retryDelayNanoseconds: UInt64 =
            Self.defaultRetryDelayNanoseconds
    ) throws {
        try self.init(
            maximumAttempts: maximumAttempts,
            retryDelayNanoseconds: retryDelayNanoseconds,
            probe: {
                try await MacLocalXPCAgentBuildProbeV0().readBuild()
            },
            pause: { try await Task.sleep(nanoseconds: $0) }
        )
    }

    package init(
        maximumAttempts: Int,
        retryDelayNanoseconds: UInt64,
        probe: @escaping @Sendable () async throws -> UInt64,
        pause: @escaping @Sendable (UInt64) async throws -> Void
    ) throws {
        guard maximumAttempts > 0,
              retryDelayNanoseconds > 0 else {
            throw MacUpdateAgentBuildReadinessErrorV0.invalidPolicy
        }
        self.maximumAttempts = maximumAttempts
        self.retryDelayNanoseconds = retryDelayNanoseconds
        self.probe = probe
        self.pause = pause
    }

    public func readBuild() async throws -> UInt64 {
        for attempt in 1...maximumAttempts {
            try Task.checkCancellation()
            do {
                return try await probe()
            } catch let error as MacLocalXPCAgentBuildProbeErrorV0 {
                try Task.checkCancellation()
                switch error {
                case .invalidTimeout, .unexpectedEvent:
                    throw MacUpdateAgentBuildReadinessErrorV0.unavailable
                case .startFailed, .timedOut, .invalidated:
                    break
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw MacUpdateAgentBuildReadinessErrorV0.unavailable
            }
            guard attempt < maximumAttempts else {
                throw MacUpdateAgentBuildReadinessErrorV0.unavailable
            }
            try await pause(retryDelayNanoseconds)
        }
        throw MacUpdateAgentBuildReadinessErrorV0.unavailable
    }
}

/// Concrete closure binding for the bundle-independent Agent reactivation
/// saga. Registration status remains only a state input; running-build evidence
/// comes exclusively from the authenticated local-XPC readiness reader.
@available(macOS 26.0, *)
public struct MacUpdateAgentReactivationPlatformV0: Sendable {
    private let registration: any AgentLoginRoleRawServiceV1
    private let service: any AgentLoginRoleServiceV1
    private let persistence: any MacUpdateAgentReactivationPersistenceV0
    private let currentAgentBuild: @Sendable () async throws -> UInt64?

    package init(
        registration: any AgentLoginRoleRawServiceV1,
        service: any AgentLoginRoleServiceV1,
        persistence: any MacUpdateAgentReactivationPersistenceV0,
        currentAgentBuild:
            @escaping @Sendable () async throws -> UInt64?
    ) {
        self.registration = registration
        self.service = service
        self.persistence = persistence
        self.currentAgentBuild = currentAgentBuild
    }

    public init(
        registration: any AgentLoginRoleRawServiceV1,
        service: any AgentLoginRoleServiceV1,
        persistence: any MacUpdateAgentReactivationPersistenceV0,
        readiness: MacUpdateAgentBuildReadinessV0
    ) {
        self.init(
            registration: registration,
            service: service,
            persistence: persistence,
            currentAgentBuild: { try await readiness.readBuild() }
        )
    }

    /// Runtime shutdown must use the build already authenticated by the
    /// dashboard lifetime. Unlike startup repair, it must not open a competing
    /// one-shot local-XPC probe.
    public init(
        registration: any AgentLoginRoleRawServiceV1,
        service: any AgentLoginRoleServiceV1,
        persistence: any MacUpdateAgentReactivationPersistenceV0,
        activeAgentBuild:
            MacAuthenticatedAgentBuildLifetimeV0
    ) {
        self.init(
            registration: registration,
            service: service,
            persistence: persistence,
            currentAgentBuild: { activeAgentBuild.currentBuild() }
        )
    }

    public func dependencies()
        -> MacUpdateAgentReactivationDependenciesV0
    {
        let registration = self.registration
        let service = self.service
        let persistence = self.persistence
        let currentAgentBuild = self.currentAgentBuild
        return MacUpdateAgentReactivationDependenciesV0(
            registrationState: {
                Self.map(await registration.status())
            },
            currentReceipt: { try await persistence.current() },
            replaceReceipt: { expected, replacement in
                try await persistence.replace(
                    expected: expected,
                    with: replacement
                )
            },
            clearReceipt: { expected in
                try await persistence.clear(expected: expected)
            },
            currentAgentBuild: currentAgentBuild,
            unregisterAndWait: { try await service.unregister() },
            registerAndWait: { try await service.register() }
        )
    }

    package static func map(
        _ state: AgentLoginRoleRegistrationStateV1
    ) -> MacUpdateAgentRegistrationStateV0 {
        switch state {
        case .notRegistered:
            .notRegistered
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound, .unknown:
            .unavailable
        }
    }
}
#endif
