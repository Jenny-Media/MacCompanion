import CompanionDomain
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionIPC
import Foundation

public enum AgentInteractiveRuntimeOwnerErrorV1:
    Error,
    Equatable,
    Sendable
{
    case unavailable
    case finalAdmissionChanged
    case invalidDesktop
    case runtimeReceiptRejected
    case safetyRecoveryRequired
}

public enum AgentInteractiveRuntimeOwnerStateV1:
    Equatable,
    Sendable
{
    case idle
    case installing(interactiveSessionID: UUID)
    case active(interactiveSessionID: UUID, leaseID: UUID)
    case terminating(interactiveSessionID: UUID, leaseID: UUID)
    case safetyRecoveryRequired(interactiveSessionID: UUID)
}

public struct AgentInteractiveInitialDesktopRequestV1:
    Equatable,
    Sendable
{
    public let interactiveSessionID: UUID
    public let authorizationEpoch: AuthorizationEpoch
    public let selectedDisplayID: UUID
    public let interactionClasses: Set<SurfaceInteractionClass>
    public let nowMonotonicNanoseconds: UInt64

    public init(
        interactiveSessionID: UUID,
        authorizationEpoch: AuthorizationEpoch,
        selectedDisplayID: UUID,
        interactionClasses: Set<SurfaceInteractionClass>,
        nowMonotonicNanoseconds: UInt64
    ) {
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.selectedDisplayID = selectedDisplayID
        self.interactionClasses = interactionClasses
        self.nowMonotonicNanoseconds = nowMonotonicNanoseconds
    }
}

/// Menu-backed preparation of the first Desktop descriptor. The later macOS
/// adapter owns the opaque UUID-to-CGDisplay mapping and may not return titles,
/// process identifiers, or platform capture objects through this seam.
public protocol AgentInteractiveInitialDesktopPreparingV1: Sendable {
    func prepareInitialDesktop(
        _ request: AgentInteractiveInitialDesktopRequestV1
    ) async throws -> AdaptiveSurfaceDescriptor
}

/// Narrow authenticated menu-runtime route. The production adapter is the
/// current-ready local-XPC generation; tests may provide a deterministic
/// in-memory implementation.
public protocol AgentInteractiveMenuRuntimeRoutingV1: Sendable {
    func installInteractiveLease(
        _ command: InteractiveRuntimeInstallCommandV0
    ) async throws -> InteractiveRuntimeInstallReceiptV0

    func renewInteractiveLease(
        _ renewal: InteractiveRuntimeLeaseRenewalV0
    ) async throws

    func revokeInteractiveLease(
        _ command: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0
}

/// Agent-owned final installation boundary for one Interactive session. It
/// re-reads the durable-plus-visible admission on both sides of menu-backed
/// Desktop preparation, then transfers credentials only after the exact menu
/// runtime receipt is accepted. Operations are explicitly sequenced so a
/// concurrent termination cannot interleave with a suspended install.
public actor AgentInteractiveRuntimeOwnerV1:
    InteractiveSessionRuntimeOwningV0
{
    private struct Active: Sendable {
        var bootstrap: InteractiveSessionBootstrap
        let preparation: InteractiveInitialRuntimePreparationV1
        let primaryConnectionID: Data
        let requirement: InteractiveSessionRuntimeRequirementV0
        var currentLease: InteractiveExecutionLease
    }

    private enum Storage: Sendable {
        case idle
        case installing(UUID)
        case active(Active)
        case terminating(Active)
        case safetyRecoveryRequired(UUID)
    }

    private let admission: any InteractiveSessionAdmissionReadingV0
    private let desktop: any AgentInteractiveInitialDesktopPreparingV1
    private let runtime: any AgentInteractiveMenuRuntimeRoutingV1
    private let monotonicNowNanoseconds: @Sendable () -> UInt64
    private let identifier: @Sendable () -> UUID
    private var storage: Storage = .idle
    private var sequencingTail = Task<Void, Never> {}

    public init(
        admission: any InteractiveSessionAdmissionReadingV0,
        desktop: any AgentInteractiveInitialDesktopPreparingV1,
        runtime: any AgentInteractiveMenuRuntimeRoutingV1,
        monotonicNowNanoseconds: @escaping @Sendable () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds
        },
        identifier: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.admission = admission
        self.desktop = desktop
        self.runtime = runtime
        self.monotonicNowNanoseconds = monotonicNowNanoseconds
        self.identifier = identifier
    }

    public func state() -> AgentInteractiveRuntimeOwnerStateV1 {
        switch storage {
        case .idle:
            .idle
        case let .installing(sessionID):
            .installing(interactiveSessionID: sessionID)
        case let .active(active):
            .active(
                interactiveSessionID:
                    active.currentLease.interactiveSessionID,
                leaseID: active.currentLease.leaseID
            )
        case let .terminating(active):
            .terminating(
                interactiveSessionID:
                    active.currentLease.interactiveSessionID,
                leaseID: active.currentLease.leaseID
            )
        case let .safetyRecoveryRequired(sessionID):
            .safetyRecoveryRequired(interactiveSessionID: sessionID)
        }
    }

    public func activeLeaseForScheduling() -> InteractiveExecutionLease? {
        guard case .active(let active) = storage else { return nil }
        return active.currentLease
    }

    public func install(
        _ bootstrap: InteractiveSessionBootstrap,
        requirement: InteractiveSessionRuntimeRequirementV0
    ) async throws {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            try await performInstall(
                bootstrap,
                requirement: requirement
            )
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func terminate(
        interactiveSessionID: UUID,
        primaryConnectionID: Data,
        reason: InteractiveSessionEndReason
    ) async {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            await performTerminate(
                interactiveSessionID: interactiveSessionID,
                primaryConnectionID: primaryConnectionID,
                reason: reason
            )
        }
        sequencingTail = operation
        await operation.value
    }

    /// Renews only the exact active lease after another final admission read.
    /// A higher-level product scheduler calls this before the current deadline;
    /// this owner never infers success from a send or silently retries an
    /// ambiguous acknowledgement.
    public func renewActiveLease(
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveExecutionLease {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            return try await performRenewal(
                nowMonotonicNanoseconds: nowMonotonicNanoseconds
            )
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    private func performInstall(
        _ suppliedBootstrap: InteractiveSessionBootstrap,
        requirement: InteractiveSessionRuntimeRequirementV0
    ) async throws {
        guard case .idle = storage,
              requirement.isEligibleForInteractiveControl,
              let sessionID = suppliedBootstrap.session.sessionID,
              sessionID
                == suppliedBootstrap.acceptedBody.interactiveSessionID.rawValue,
              let selectedDisplayID = requirement.admission.selectedDisplayID
        else {
            throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
        }
        storage = .installing(sessionID)
        var bootstrap = suppliedBootstrap

        do {
            try await requireExactFinalAdmission(requirement)
            let now = monotonicNowNanoseconds()
            let descriptor = try await desktop.prepareInitialDesktop(
                AgentInteractiveInitialDesktopRequestV1(
                    interactiveSessionID: sessionID,
                    authorizationEpoch: requirement.command.authorizationEpoch,
                    selectedDisplayID: selectedDisplayID,
                    interactionClasses: bootstrap.approvedInteractionClasses,
                    nowMonotonicNanoseconds: now
                )
            )
            try await requireExactFinalAdmission(requirement)
            guard descriptor.interactiveSessionID == sessionID,
                  descriptor.authorizationEpoch
                    == requirement.command.authorizationEpoch,
                  descriptor.kind == .desktop,
                  Set(descriptor.interactionClasses)
                    == bootstrap.approvedInteractionClasses else {
                throw AgentInteractiveRuntimeOwnerErrorV1.invalidDesktop
            }

            var authority = try InteractiveInitialRuntimeCommandAuthorityV1(
                bootstrap: bootstrap,
                requirement: requirement,
                desktop: descriptor
            )
            let preparation = try authority.prepare(
                commandID: identifier(),
                leaseID: identifier(),
                nowMonotonicNanoseconds: now
            )

            let receipt: InteractiveRuntimeInstallReceiptV0
            do {
                receipt = try await runtime.installInteractiveLease(
                    preparation.command
                )
            } catch {
                let revoked = await attemptRevoke(
                    lease: preparation.command.lease,
                    bootstrap: &bootstrap,
                    reason: .protocolViolation
                )
                storage = revoked
                    ? .idle : .safetyRecoveryRequired(sessionID)
                throw revoked
                    ? AgentInteractiveRuntimeOwnerErrorV1.unavailable
                    : AgentInteractiveRuntimeOwnerErrorV1
                        .safetyRecoveryRequired
            }

            do {
                try authority.accept(
                    receipt,
                    nowMonotonicNanoseconds: monotonicNowNanoseconds()
                )
                bootstrap = try authority.takeInstalledBootstrap()
            } catch {
                let revoked = await attemptRevoke(
                    lease: preparation.command.lease,
                    bootstrap: &bootstrap,
                    reason: .protocolViolation
                )
                storage = revoked
                    ? .idle : .safetyRecoveryRequired(sessionID)
                throw AgentInteractiveRuntimeOwnerErrorV1
                    .runtimeReceiptRejected
            }
            storage = .active(Active(
                bootstrap: bootstrap,
                preparation: preparation,
                primaryConnectionID: requirement.command.primaryConnectionID,
                requirement: requirement,
                currentLease: preparation.command.lease
            ))
        } catch let error as AgentInteractiveRuntimeOwnerErrorV1 {
            if case .installing = storage {
                invalidateCredentials(&bootstrap)
                storage = .idle
            }
            throw error
        } catch {
            if case .installing = storage {
                invalidateCredentials(&bootstrap)
                storage = .idle
            }
            throw error
        }
    }

    private func performRenewal(
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveExecutionLease {
        guard case var .active(active) = storage else {
            if case .safetyRecoveryRequired = storage {
                throw AgentInteractiveRuntimeOwnerErrorV1
                    .safetyRecoveryRequired
            }
            throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
        }
        do {
            try await requireExactFinalAdmission(active.requirement)
            let current = active.currentLease
            guard nowMonotonicNanoseconds
                    >= current.issuedAtMonotonicNanoseconds,
                  nowMonotonicNanoseconds
                    < current.expiresAtMonotonicNanoseconds,
                  nowMonotonicNanoseconds
                    < active.preparation.command
                        .sessionDeadlineMonotonicNanoseconds,
                  current.renewalCounter
                    < MonotonicRevision<AuthorizationEpochTag>
                        .maximumWireValue else {
                throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
            }
            let (maximumExpiry, overflow) = nowMonotonicNanoseconds
                .addingReportingOverflow(
                    InteractiveExecutionLease.maximumLifetimeNanoseconds
                )
            guard !overflow else {
                throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
            }
            let expiry = min(
                maximumExpiry,
                active.preparation.command
                    .sessionDeadlineMonotonicNanoseconds
            )
            guard expiry > nowMonotonicNanoseconds else {
                throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
            }
            let replacement = try InteractiveExecutionLease(
                leaseID: identifier(),
                hostID: current.hostID,
                deviceID: current.deviceID,
                interactiveSessionID: current.interactiveSessionID,
                authorizationEpoch: current.authorizationEpoch,
                selectedDisplayID: current.selectedDisplayID,
                surfaceID: current.surfaceID,
                surfaceRevision: current.surfaceRevision,
                coordinateRevision: current.coordinateRevision,
                allowedInteractionClasses:
                    Set(current.allowedInteractionClasses),
                renewalCounter: current.renewalCounter + 1,
                issuedAtMonotonicNanoseconds: nowMonotonicNanoseconds,
                expiresAtMonotonicNanoseconds: expiry
            )
            let renewal = try InteractiveRuntimeLeaseRenewalV0(
                commandID: identifier(),
                previousLeaseID: current.leaseID,
                replacement: replacement
            )
            try renewal.validate(current: current)
            try await runtime.renewInteractiveLease(renewal)
            active.currentLease = replacement
            storage = .active(active)
            return replacement
        } catch let error as AgentInteractiveRuntimeOwnerErrorV1 {
            let revoked = await attemptRevoke(
                lease: active.currentLease,
                bootstrap: &active.bootstrap,
                reason: .authorizationChanged
            )
            storage = revoked ? .idle : .safetyRecoveryRequired(
                active.currentLease.interactiveSessionID
            )
            throw error
        } catch {
            let revoked = await attemptRevoke(
                lease: active.currentLease,
                bootstrap: &active.bootstrap,
                reason: .protocolViolation
            )
            storage = revoked ? .idle : .safetyRecoveryRequired(
                active.currentLease.interactiveSessionID
            )
            if revoked { throw error }
            throw AgentInteractiveRuntimeOwnerErrorV1.safetyRecoveryRequired
        }
    }

    private func performTerminate(
        interactiveSessionID: UUID,
        primaryConnectionID: Data,
        reason: InteractiveSessionEndReason
    ) async {
        guard case var .active(active) = storage,
              active.currentLease.interactiveSessionID == interactiveSessionID,
              active.bootstrap.acceptedBody.interactiveSessionID.rawValue
                == interactiveSessionID,
              active.primaryConnectionID == primaryConnectionID else {
            return
        }
        storage = .terminating(active)
        if await attemptRevoke(
            lease: active.currentLease,
            bootstrap: &active.bootstrap,
            reason: reason
        ) {
            storage = .idle
        } else {
            storage = .safetyRecoveryRequired(interactiveSessionID)
        }
    }

    private func attemptRevoke(
        lease: InteractiveExecutionLease,
        bootstrap: inout InteractiveSessionBootstrap,
        reason: InteractiveSessionEndReason
    ) async -> Bool {
        defer { invalidateCredentials(&bootstrap) }
        do {
            let command = try InteractiveRuntimeRevokeCommandV0(
                commandID: identifier(),
                leaseID: lease.leaseID,
                interactiveSessionID: lease.interactiveSessionID,
                reason: reason
            )
            let receipt = try await runtime.revokeInteractiveLease(command)
            try receipt.validate(against: command)
            return true
        } catch {
            return false
        }
    }

    private func requireExactFinalAdmission(
        _ requirement: InteractiveSessionRuntimeRequirementV0
    ) async throws {
        guard let current = try await admission.snapshot(
            deviceID: requirement.command.deviceID
        ), current == requirement.admission,
        InteractiveSessionRuntimeRequirementV0(
            command: requirement.command,
            admission: current
        ).isEligibleForInteractiveControl else {
            throw AgentInteractiveRuntimeOwnerErrorV1
                .finalAdmissionChanged
        }
    }

    private func invalidateCredentials(
        _ bootstrap: inout InteractiveSessionBootstrap
    ) {
        bootstrap.inputChannelAuthority.invalidate()
        bootstrap.mediaChannelAuthority.invalidate()
    }
}
