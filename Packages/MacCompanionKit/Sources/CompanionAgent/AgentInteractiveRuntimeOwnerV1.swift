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
                    active.preparation.command.lease.interactiveSessionID,
                leaseID: active.preparation.command.lease.leaseID
            )
        case let .terminating(active):
            .terminating(
                interactiveSessionID:
                    active.preparation.command.lease.interactiveSessionID,
                leaseID: active.preparation.command.lease.leaseID
            )
        case let .safetyRecoveryRequired(sessionID):
            .safetyRecoveryRequired(interactiveSessionID: sessionID)
        }
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
                invalidateCredentials(&bootstrap)
                storage = .safetyRecoveryRequired(sessionID)
                throw AgentInteractiveRuntimeOwnerErrorV1
                    .safetyRecoveryRequired
            }

            do {
                try authority.accept(
                    receipt,
                    nowMonotonicNanoseconds: monotonicNowNanoseconds()
                )
                bootstrap = try authority.takeInstalledBootstrap()
            } catch {
                invalidateCredentials(&bootstrap)
                storage = .safetyRecoveryRequired(sessionID)
                throw AgentInteractiveRuntimeOwnerErrorV1
                    .runtimeReceiptRejected
            }
            storage = .active(Active(
                bootstrap: bootstrap,
                preparation: preparation,
                primaryConnectionID: requirement.command.primaryConnectionID
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

    private func performTerminate(
        interactiveSessionID: UUID,
        primaryConnectionID: Data,
        reason: InteractiveSessionEndReason
    ) async {
        guard case var .active(active) = storage,
              active.preparation.command.lease.interactiveSessionID
                == interactiveSessionID,
              active.bootstrap.acceptedBody.interactiveSessionID.rawValue
                == interactiveSessionID,
              active.primaryConnectionID == primaryConnectionID else {
            return
        }
        storage = .terminating(active)
        let command: InteractiveRuntimeRevokeCommandV0
        do {
            command = try InteractiveRuntimeRevokeCommandV0(
                commandID: identifier(),
                leaseID: active.preparation.command.lease.leaseID,
                interactiveSessionID: interactiveSessionID,
                reason: reason
            )
            let receipt = try await runtime.revokeInteractiveLease(command)
            try receipt.validate(against: command)
            invalidateCredentials(&active.bootstrap)
            storage = .idle
        } catch {
            invalidateCredentials(&active.bootstrap)
            storage = .safetyRecoveryRequired(interactiveSessionID)
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
