public enum MacUpdateChannelV0: String, CaseIterable, Sendable {
    case beta
    case stable
}

public enum MacUpdateCandidateValidationErrorV0:
    Error, Equatable, Sendable
{
    case channelMismatch
    case nonIncreasingBuild
    case trustRequirementMissing
}

/// An update candidate that has already passed the complete frozen update
/// trust profile. Construction does not fetch, extract, or install anything.
public struct MacUpdateValidatedCandidateV0: Equatable, Sendable {
    public let channel: MacUpdateChannelV0
    public let currentBuild: UInt64
    public let candidateBuild: UInt64

    /// Internal constructor used only after the public exact-candidate binding
    /// has correlated independent feed and post-validation observations.
    init(
        installedChannel: MacUpdateChannelV0,
        candidateChannel: MacUpdateChannelV0,
        currentBuild: UInt64,
        candidateBuild: UInt64,
        signedFeedVerified: Bool,
        archiveSignatureVerified: Bool,
        verifiedBeforeExtraction: Bool,
        releaseEvidence: MacUpdateReleaseEvidenceV0
    ) throws {
        guard installedChannel == candidateChannel else {
            throw MacUpdateCandidateValidationErrorV0.channelMismatch
        }
        guard candidateBuild > currentBuild else {
            throw MacUpdateCandidateValidationErrorV0.nonIncreasingBuild
        }
        guard signedFeedVerified,
              archiveSignatureVerified,
              verifiedBeforeExtraction,
              releaseEvidence.channel == candidateChannel,
              releaseEvidence.candidateBuild == candidateBuild else {
            throw MacUpdateCandidateValidationErrorV0
                .trustRequirementMissing
        }
        channel = candidateChannel
        self.currentBuild = currentBuild
        self.candidateBuild = candidateBuild
    }
}

public enum MacUpdateControlStateV0: String, CaseIterable, Sendable {
    case inactive
    case active
    case cleanupUncertain
}

public enum MacUpdateInstallPhaseV0: String, CaseIterable, Sendable {
    case pendingConfirmation
    case confirmationAccepted
    case closingNetworkAdmission
    case drainingBoundedWork
    case stoppingAgent
    case ready
    case handingOff
    case closed
}

public enum MacUpdateInstallEffectV0: String, Equatable, Sendable {
    case closeNetworkAdmission
    case drainBoundedWork
    case stopAgent
}

public enum MacUpdateInstallRecoveryRequirementV0:
    String, Equatable, Sendable
{
    case none
    case reconcileNetworkAdmission
    case reconcileAgentAndNetworkAdmission
}

public enum MacUpdateInstallAuthorityErrorV0:
    Error, Equatable, Sendable
{
    case invalidPhase
    case invalidClock
    case foregroundRequired
    case confirmationExpired
    case controlActive
    case controlCleanupUncertain
    case agentVersionMismatch
    case updaterRejected
    case closed
}

public struct MacUpdateInstallSnapshotV0: Equatable, Sendable {
    public let phase: MacUpdateInstallPhaseV0
    public let candidate: MacUpdateValidatedCandidateV0
    public let confirmationDeadlineMilliseconds: Int64?
    public let recoveryRequirement:
        MacUpdateInstallRecoveryRequirementV0
}

/// Single-use, application-owned installation gate. It serializes local
/// confirmation and runtime shutdown before the updater callback can run.
/// There is deliberately no lock-state parameter: a fresh foreground grant
/// that is cancelled on foreground loss is the public-API-safe boundary.
public actor MacUpdateInstallAuthorityV0 {
    public static let confirmationLifetimeMilliseconds: Int64 = 300_000

    private let candidate: MacUpdateValidatedCandidateV0
    private var phase = MacUpdateInstallPhaseV0.pendingConfirmation
    private var confirmationDeadlineMilliseconds: Int64?
    private var recoveryRequirement =
        MacUpdateInstallRecoveryRequirementV0.none

    /// Internal so production consumers obtain this authority only from the
    /// single-use exact-candidate admission owner.
    init(candidate: MacUpdateValidatedCandidateV0) {
        self.candidate = candidate
    }

    public func snapshot() -> MacUpdateInstallSnapshotV0 {
        MacUpdateInstallSnapshotV0(
            phase: phase,
            candidate: candidate,
            confirmationDeadlineMilliseconds:
                confirmationDeadlineMilliseconds,
            recoveryRequirement: recoveryRequirement
        )
    }

    public func confirm(
        monotonicNowMilliseconds: Int64,
        menuForeground: Bool
    ) throws {
        try requirePhase(.pendingConfirmation)
        guard monotonicNowMilliseconds >= 0,
              monotonicNowMilliseconds <= Int64.max
                - Self.confirmationLifetimeMilliseconds else {
            close(recoveryRequirement: .none)
            throw MacUpdateInstallAuthorityErrorV0.invalidClock
        }
        guard menuForeground else {
            close(recoveryRequirement: .none)
            throw MacUpdateInstallAuthorityErrorV0.foregroundRequired
        }
        confirmationDeadlineMilliseconds = monotonicNowMilliseconds
            + Self.confirmationLifetimeMilliseconds
        phase = .confirmationAccepted
    }

    public func beginRuntimeShutdown(
        monotonicNowMilliseconds: Int64,
        menuForeground: Bool,
        controlState: MacUpdateControlStateV0
    ) throws -> MacUpdateInstallEffectV0 {
        try requirePhase(.confirmationAccepted)
        try requireFreshConfirmation(
            monotonicNowMilliseconds: monotonicNowMilliseconds,
            menuForeground: menuForeground
        )
        switch controlState {
        case .inactive:
            phase = .closingNetworkAdmission
            return .closeNetworkAdmission
        case .active:
            throw MacUpdateInstallAuthorityErrorV0.controlActive
        case .cleanupUncertain:
            throw MacUpdateInstallAuthorityErrorV0
                .controlCleanupUncertain
        }
    }

    public func networkAdmissionDidClose(
        monotonicNowMilliseconds: Int64,
        menuForeground: Bool
    ) throws -> MacUpdateInstallEffectV0 {
        try requirePhase(.closingNetworkAdmission)
        try requireFreshConfirmation(
            monotonicNowMilliseconds: monotonicNowMilliseconds,
            menuForeground: menuForeground
        )
        phase = .drainingBoundedWork
        return .drainBoundedWork
    }

    public func boundedWorkDidDrain(
        monotonicNowMilliseconds: Int64,
        menuForeground: Bool
    ) throws -> MacUpdateInstallEffectV0 {
        try requirePhase(.drainingBoundedWork)
        try requireFreshConfirmation(
            monotonicNowMilliseconds: monotonicNowMilliseconds,
            menuForeground: menuForeground
        )
        phase = .stoppingAgent
        return .stopAgent
    }

    public func agentDidStop(
        exactVersionMatch: Bool,
        monotonicNowMilliseconds: Int64,
        menuForeground: Bool
    ) throws {
        try requirePhase(.stoppingAgent)
        try requireFreshConfirmation(
            monotonicNowMilliseconds: monotonicNowMilliseconds,
            menuForeground: menuForeground
        )
        guard exactVersionMatch else {
            close(
                recoveryRequirement:
                    .reconcileAgentAndNetworkAdmission
            )
            throw MacUpdateInstallAuthorityErrorV0.agentVersionMismatch
        }
        phase = .ready
    }

    public func handOffToUpdater(
        monotonicNowMilliseconds: Int64,
        menuForeground: Bool,
        start: @escaping @Sendable () async throws -> Void
    ) async throws {
        try requirePhase(.ready)
        try requireFreshConfirmation(
            monotonicNowMilliseconds: monotonicNowMilliseconds,
            menuForeground: menuForeground
        )
        phase = .handingOff
        do {
            try await start()
            close(recoveryRequirement: .none)
        } catch {
            close(
                recoveryRequirement:
                    .reconcileAgentAndNetworkAdmission
            )
            throw MacUpdateInstallAuthorityErrorV0.updaterRejected
        }
    }

    /// Foreground loss revokes any unconsumed authority, including a fully
    /// drained but not-yet-handed-off candidate.
    public func menuForegroundDidChange(_ foreground: Bool) {
        guard !foreground, phase != .closed, phase != .handingOff else {
            return
        }
        close(recoveryRequirement: inferredRecoveryRequirement())
    }

    public func runtimeShutdownFailed() {
        guard phase != .closed, phase != .handingOff else { return }
        close(recoveryRequirement: inferredRecoveryRequirement())
    }

    public func finish() {
        guard phase != .closed, phase != .handingOff else { return }
        close(recoveryRequirement: inferredRecoveryRequirement())
    }

    private func requirePhase(
        _ expected: MacUpdateInstallPhaseV0
    ) throws {
        guard phase != .closed else {
            throw MacUpdateInstallAuthorityErrorV0.closed
        }
        guard phase == expected else {
            throw MacUpdateInstallAuthorityErrorV0.invalidPhase
        }
    }

    private func requireFreshConfirmation(
        monotonicNowMilliseconds: Int64,
        menuForeground: Bool
    ) throws {
        guard monotonicNowMilliseconds >= 0 else {
            close(recoveryRequirement: inferredRecoveryRequirement())
            throw MacUpdateInstallAuthorityErrorV0.invalidClock
        }
        guard menuForeground else {
            close(recoveryRequirement: inferredRecoveryRequirement())
            throw MacUpdateInstallAuthorityErrorV0.foregroundRequired
        }
        guard let deadline = confirmationDeadlineMilliseconds,
              monotonicNowMilliseconds <= deadline else {
            close(recoveryRequirement: inferredRecoveryRequirement())
            throw MacUpdateInstallAuthorityErrorV0.confirmationExpired
        }
    }

    private func inferredRecoveryRequirement()
        -> MacUpdateInstallRecoveryRequirementV0
    {
        switch phase {
        case .pendingConfirmation, .confirmationAccepted, .closed:
            .none
        case .closingNetworkAdmission, .drainingBoundedWork:
            .reconcileNetworkAdmission
        case .stoppingAgent, .ready, .handingOff:
            .reconcileAgentAndNetworkAdmission
        }
    }

    private func close(
        recoveryRequirement:
            MacUpdateInstallRecoveryRequirementV0
    ) {
        phase = .closed
        confirmationDeadlineMilliseconds = nil
        self.recoveryRequirement = recoveryRequirement
    }
}
