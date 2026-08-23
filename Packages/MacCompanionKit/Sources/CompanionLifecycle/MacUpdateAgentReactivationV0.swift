public enum MacUpdateAgentRegistrationStateV0:
    String, Equatable, Sendable
{
    case notRegistered
    case enabled
    case requiresApproval
    case unavailable
}

public enum MacUpdateAgentReactivationReceiptPhaseV0:
    String, Equatable, Sendable
{
    case prepared
    case agentStopped
}

/// Durable, non-secret recovery intent written before the containing app
/// unregisters a KeepAlive Agent for replacement. Either the old or new app
/// can safely repair the registration, but no unrelated build can consume it.
public struct MacUpdateAgentReactivationReceiptV0:
    Equatable, Sendable
{
    public static let profile =
        "maccompanion.update-agent-reactivation.v0.1"

    public let profile: String
    public let sourceBuild: UInt64
    public let candidateBuild: UInt64
    public let phase: MacUpdateAgentReactivationReceiptPhaseV0

    public init(
        profile: String = Self.profile,
        sourceBuild: UInt64,
        candidateBuild: UInt64,
        phase: MacUpdateAgentReactivationReceiptPhaseV0
    ) throws {
        guard profile == Self.profile,
              candidateBuild > sourceBuild else {
            throw MacUpdateAgentReactivationErrorV0.invalidReceipt
        }
        self.profile = profile
        self.sourceBuild = sourceBuild
        self.candidateBuild = candidateBuild
        self.phase = phase
    }

    func advancing(
        to phase: MacUpdateAgentReactivationReceiptPhaseV0
    ) throws -> Self {
        try Self(
            sourceBuild: sourceBuild,
            candidateBuild: candidateBuild,
            phase: phase
        )
    }
}

public struct MacUpdateAgentReactivationDependenciesV0: Sendable {
    public let registrationState:
        @Sendable () async -> MacUpdateAgentRegistrationStateV0
    public let currentReceipt:
        @Sendable () async throws -> MacUpdateAgentReactivationReceiptV0?
    public let replaceReceipt: @Sendable (
        _ expected: MacUpdateAgentReactivationReceiptV0?,
        _ replacement: MacUpdateAgentReactivationReceiptV0
    ) async throws -> Bool
    public let clearReceipt: @Sendable (
        _ expected: MacUpdateAgentReactivationReceiptV0
    ) async throws -> Bool
    public let currentAgentBuild: @Sendable () async throws -> UInt64?
    public let unregisterAndWait: @Sendable () async throws -> Void
    public let registerAndWait: @Sendable () async throws -> Void

    public init(
        registrationState: @escaping @Sendable () async
            -> MacUpdateAgentRegistrationStateV0,
        currentReceipt: @escaping @Sendable () async throws
            -> MacUpdateAgentReactivationReceiptV0?,
        replaceReceipt: @escaping @Sendable (
            _ expected: MacUpdateAgentReactivationReceiptV0?,
            _ replacement: MacUpdateAgentReactivationReceiptV0
        ) async throws -> Bool,
        clearReceipt: @escaping @Sendable (
            _ expected: MacUpdateAgentReactivationReceiptV0
        ) async throws -> Bool,
        currentAgentBuild: @escaping @Sendable () async throws -> UInt64?,
        unregisterAndWait:
            @escaping @Sendable () async throws -> Void,
        registerAndWait:
            @escaping @Sendable () async throws -> Void
    ) {
        self.registrationState = registrationState
        self.currentReceipt = currentReceipt
        self.replaceReceipt = replaceReceipt
        self.clearReceipt = clearReceipt
        self.currentAgentBuild = currentAgentBuild
        self.unregisterAndWait = unregisterAndWait
        self.registerAndWait = registerAndWait
    }
}

public enum MacUpdateAgentReactivationErrorV0:
    Error, Equatable, Sendable
{
    case invalidBuilds
    case invalidReceipt
    case invalidPhase
    case registrationUnavailable
    case agentVersionMismatch
    case receiptAlreadyExists
    case persistenceConflict
    case effectFailed
}

public enum MacUpdateAgentStopPhaseV0: String, Equatable, Sendable {
    case awaitingStop
    case stopping
    case stopped
    case recoveryRequired
    case finished
}

/// Single-use stop/recovery owner for an Agent registered with KeepAlive. It
/// persists recovery intent before unregistering, because ServiceManagement's
/// completed unregister is the point at which the running process is gone and
/// re-registration becomes safe.
public actor MacUpdateAgentStopOwnerV0 {
    private let sourceBuild: UInt64
    private let candidateBuild: UInt64
    private let dependencies: MacUpdateAgentReactivationDependenciesV0
    private var phase = MacUpdateAgentStopPhaseV0.awaitingStop

    public init(
        sourceBuild: UInt64,
        candidateBuild: UInt64,
        dependencies: MacUpdateAgentReactivationDependenciesV0
    ) throws {
        guard candidateBuild > sourceBuild else {
            throw MacUpdateAgentReactivationErrorV0.invalidBuilds
        }
        self.sourceBuild = sourceBuild
        self.candidateBuild = candidateBuild
        self.dependencies = dependencies
    }

    public func currentPhase() -> MacUpdateAgentStopPhaseV0 {
        phase
    }

    /// Returns the exact-version fact expected by the outer update authority.
    /// A disabled/unregistered Agent is already safely stopped.
    public func stopForUpdate() async throws -> Bool {
        guard phase == .awaitingStop else {
            throw MacUpdateAgentReactivationErrorV0.invalidPhase
        }
        phase = .stopping

        switch await dependencies.registrationState() {
        case .notRegistered:
            phase = .stopped
            return true
        case .requiresApproval, .unavailable:
            phase = .finished
            throw MacUpdateAgentReactivationErrorV0
                .registrationUnavailable
        case .enabled:
            break
        }

        let observedBuild: UInt64?
        do {
            observedBuild = try await dependencies.currentAgentBuild()
        } catch {
            phase = .finished
            throw MacUpdateAgentReactivationErrorV0.effectFailed
        }
        guard observedBuild == sourceBuild else {
            phase = .finished
            return false
        }

        let prepared = try MacUpdateAgentReactivationReceiptV0(
            sourceBuild: sourceBuild,
            candidateBuild: candidateBuild,
            phase: .prepared
        )
        do {
            guard try await dependencies.currentReceipt() == nil else {
                phase = .finished
                throw MacUpdateAgentReactivationErrorV0
                    .receiptAlreadyExists
            }
            guard try await dependencies.replaceReceipt(nil, prepared) else {
                phase = .finished
                throw MacUpdateAgentReactivationErrorV0
                    .persistenceConflict
            }
            try await dependencies.unregisterAndWait()
            let stopped = try prepared.advancing(to: .agentStopped)
            guard try await dependencies.replaceReceipt(
                prepared,
                stopped
            ) else {
                phase = .recoveryRequired
                throw MacUpdateAgentReactivationErrorV0
                    .persistenceConflict
            }
            phase = .stopped
            return true
        } catch let error as MacUpdateAgentReactivationErrorV0 {
            if phase == .stopping { phase = .recoveryRequired }
            throw error
        } catch {
            phase = .recoveryRequired
            throw MacUpdateAgentReactivationErrorV0.effectFailed
        }
    }

    /// Re-registers the source-build Agent after a failed updater handoff or
    /// any earlier stop failure. The receipt is retained until exact readiness
    /// proves recovery.
    public func recoverSourceBuild() async throws {
        guard phase == .stopped || phase == .recoveryRequired
                || phase == .finished else {
            throw MacUpdateAgentReactivationErrorV0.invalidPhase
        }
        do {
            guard let receipt = try await dependencies.currentReceipt() else {
                phase = .finished
                return
            }
            try Self.requireReceipt(
                receipt,
                sourceBuild: sourceBuild,
                candidateBuild: candidateBuild
            )
            try await dependencies.registerAndWait()
            guard try await dependencies.currentAgentBuild()
                    == sourceBuild else {
                throw MacUpdateAgentReactivationErrorV0
                    .agentVersionMismatch
            }
            guard try await dependencies.clearReceipt(receipt) else {
                throw MacUpdateAgentReactivationErrorV0
                    .persistenceConflict
            }
            phase = .finished
        } catch let error as MacUpdateAgentReactivationErrorV0 {
            phase = .recoveryRequired
            throw error
        } catch {
            phase = .recoveryRequired
            throw MacUpdateAgentReactivationErrorV0.effectFailed
        }
    }

    fileprivate static func requireReceipt(
        _ receipt: MacUpdateAgentReactivationReceiptV0,
        sourceBuild: UInt64,
        candidateBuild: UInt64
    ) throws {
        guard receipt.profile
                == MacUpdateAgentReactivationReceiptV0.profile,
              receipt.sourceBuild == sourceBuild,
              receipt.candidateBuild == candidateBuild else {
            throw MacUpdateAgentReactivationErrorV0.invalidReceipt
        }
    }
}

/// Startup repair consumed by either the unchanged source app after a failed
/// update or the installed candidate app after a successful replacement.
public actor MacUpdateAgentStartupReactivatorV0 {
    private let runningBuild: UInt64
    private let dependencies: MacUpdateAgentReactivationDependenciesV0
    private var consumed = false

    public init(
        runningBuild: UInt64,
        dependencies: MacUpdateAgentReactivationDependenciesV0
    ) {
        self.runningBuild = runningBuild
        self.dependencies = dependencies
    }

    /// Returns true only when a retained receipt was repaired and cleared.
    public func reactivateIfNeeded() async throws -> Bool {
        guard !consumed else {
            throw MacUpdateAgentReactivationErrorV0.invalidPhase
        }
        consumed = true

        do {
            guard let receipt = try await dependencies.currentReceipt() else {
                return false
            }
            guard runningBuild == receipt.sourceBuild
                    || runningBuild == receipt.candidateBuild else {
                throw MacUpdateAgentReactivationErrorV0.invalidReceipt
            }
            try await dependencies.registerAndWait()
            guard try await dependencies.currentAgentBuild()
                    == runningBuild else {
                throw MacUpdateAgentReactivationErrorV0
                    .agentVersionMismatch
            }
            guard try await dependencies.clearReceipt(receipt) else {
                throw MacUpdateAgentReactivationErrorV0
                    .persistenceConflict
            }
            return true
        } catch let error as MacUpdateAgentReactivationErrorV0 {
            throw error
        } catch {
            throw MacUpdateAgentReactivationErrorV0.effectFailed
        }
    }
}
