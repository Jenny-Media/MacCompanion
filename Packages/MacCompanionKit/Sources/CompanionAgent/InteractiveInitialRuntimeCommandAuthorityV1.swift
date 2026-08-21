import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionIPC
import Foundation

public enum InteractiveInitialRuntimeCommandStateV1:
    Equatable,
    Sendable
{
    case ready
    case prepared
    case installed
    case transferred
    case teardownRequired
}

public enum InteractiveInitialRuntimeCommandErrorV1:
    Error,
    Equatable,
    Sendable
{
    case invalidBinding
    case invalidTime
    case invalidState(InteractiveInitialRuntimeCommandStateV1)
    case receiptRejected
}

public struct InteractiveInitialRuntimePreparationV1: Equatable, Sendable {
    public let command: InteractiveRuntimeInstallCommandV0
    public let descriptor: AdaptiveSurfaceDescriptor

    public init(
        command: InteractiveRuntimeInstallCommandV0,
        descriptor: AdaptiveSurfaceDescriptor
    ) {
        self.command = command
        self.descriptor = descriptor
    }
}

/// One-use bridge from a signature-bound Interactive bootstrap to the first
/// bounded local runtime command. It performs no IPC and claims no atomic
/// final-store revalidation; the signed runtime bridge must provide both.
public struct InteractiveInitialRuntimeCommandAuthorityV1: Sendable {
    private struct PreparationRequest: Equatable, Sendable {
        let commandID: UUID
        let leaseID: UUID
        let nowMonotonicNanoseconds: UInt64
    }

    public private(set) var state: InteractiveInitialRuntimeCommandStateV1
        = .ready

    private var bootstrap: InteractiveSessionBootstrap?
    private let requirement: InteractiveSessionRuntimeRequirementV0
    private let desktop: AdaptiveSurfaceDescriptor
    private let sessionDeadlineMonotonicMilliseconds: Int64
    private var preparationRequest: PreparationRequest?
    private var preparation: InteractiveInitialRuntimePreparationV1?
    private var installedReceipt: InteractiveRuntimeInstallReceiptV0?

    public init(
        bootstrap: InteractiveSessionBootstrap,
        requirement: InteractiveSessionRuntimeRequirementV0,
        desktop: AdaptiveSurfaceDescriptor
    ) throws {
        guard requirement.isEligibleForInteractiveControl,
              bootstrap.session.state == .starting,
              let sessionID = bootstrap.session.sessionID,
              let sessionEpoch = bootstrap.session.authorizationEpoch,
              let sessionDeadline = bootstrap.session
                .sessionDeadlineMonotonicMilliseconds,
              sessionDeadline >= 0,
              sessionID == bootstrap.acceptedBody
                .interactiveSessionID.rawValue,
              sessionID == desktop.interactiveSessionID,
              sessionEpoch == bootstrap.acceptedBody.authorizationEpoch,
              sessionEpoch == requirement.command.authorizationEpoch,
              sessionEpoch == desktop.authorizationEpoch,
              desktop.kind == .desktop,
              desktop.surfaceRevision.rawValue == 1,
              desktop.coordinateSpaceRevision.rawValue == 1,
              Set(desktop.interactionClasses)
                == bootstrap.approvedInteractionClasses else {
            throw InteractiveInitialRuntimeCommandErrorV1.invalidBinding
        }
        self.bootstrap = bootstrap
        self.requirement = requirement
        self.desktop = desktop
        sessionDeadlineMonotonicMilliseconds = sessionDeadline
    }

    public mutating func prepare(
        commandID: UUID,
        leaseID: UUID,
        nowMonotonicNanoseconds: UInt64
    ) throws -> InteractiveInitialRuntimePreparationV1 {
        let request = PreparationRequest(
            commandID: commandID,
            leaseID: leaseID,
            nowMonotonicNanoseconds: nowMonotonicNanoseconds
        )
        if state == .prepared, request == preparationRequest,
           let preparation {
            return preparation
        }
        guard state == .ready else {
            throw InteractiveInitialRuntimeCommandErrorV1.invalidState(state)
        }
        guard let bootstrap,
              let selectedDisplayID = requirement.admission.selectedDisplayID else {
            throw InteractiveInitialRuntimeCommandErrorV1.invalidBinding
        }
        let nowMilliseconds = Int64(nowMonotonicNanoseconds / 1_000_000)
        guard desktop.createdAtMonotonicMilliseconds <= nowMilliseconds,
              desktop.expiresAtMonotonicMilliseconds > nowMilliseconds,
              sessionDeadlineMonotonicMilliseconds > nowMilliseconds else {
            throw InteractiveInitialRuntimeCommandErrorV1.invalidTime
        }

        let sessionDeadlineNanoseconds = try nanoseconds(
            sessionDeadlineMonotonicMilliseconds
        )
        let descriptorDeadlineNanoseconds = try nanoseconds(
            desktop.expiresAtMonotonicMilliseconds
        )
        let (maximumLeaseDeadline, overflow) = nowMonotonicNanoseconds
            .addingReportingOverflow(
                InteractiveExecutionLease.maximumLifetimeNanoseconds
            )
        guard !overflow else {
            throw InteractiveInitialRuntimeCommandErrorV1.invalidTime
        }
        let leaseDeadline = min(
            min(maximumLeaseDeadline, sessionDeadlineNanoseconds),
            descriptorDeadlineNanoseconds
        )
        guard leaseDeadline > nowMonotonicNanoseconds else {
            throw InteractiveInitialRuntimeCommandErrorV1.invalidTime
        }

        let lease = try InteractiveExecutionLease(
            leaseID: leaseID,
            hostID: requirement.command.hostID,
            deviceID: requirement.command.deviceID,
            interactiveSessionID: desktop.interactiveSessionID,
            authorizationEpoch: requirement.command.authorizationEpoch,
            selectedDisplayID: selectedDisplayID,
            surfaceID: desktop.surfaceID,
            surfaceRevision: .init(rawValue: desktop.surfaceRevision.rawValue),
            coordinateRevision: .init(
                rawValue: desktop.coordinateSpaceRevision.rawValue
            ),
            allowedInteractionClasses:
                bootstrap.approvedInteractionClasses,
            renewalCounter: 0,
            issuedAtMonotonicNanoseconds: nowMonotonicNanoseconds,
            expiresAtMonotonicNanoseconds: leaseDeadline
        )
        let result = InteractiveInitialRuntimePreparationV1(
            command: try InteractiveRuntimeInstallCommandV0(
                commandID: commandID,
                lease: lease,
                deviceDisplayName: requirement.admission.deviceDisplayName,
                sessionDeadlineMonotonicNanoseconds:
                    sessionDeadlineNanoseconds
            ),
            descriptor: desktop
        )
        preparationRequest = request
        preparation = result
        state = .prepared
        return result
    }

    /// Consumes the exact visible-runtime receipt. Any ambiguous or stale
    /// result invalidates unused channel credentials and requires the caller
    /// to converge menu-runtime teardown before admitting another session.
    public mutating func accept(
        _ receipt: InteractiveRuntimeInstallReceiptV0,
        nowMonotonicNanoseconds: UInt64
    ) throws {
        if state == .installed || state == .transferred,
           receipt == installedReceipt {
            return
        }
        guard state == .prepared, let preparation,
              var bootstrap else {
            throw InteractiveInitialRuntimeCommandErrorV1.invalidState(state)
        }
        do {
            guard nowMonotonicNanoseconds
                    >= preparation.command.lease
                        .issuedAtMonotonicNanoseconds,
                  nowMonotonicNanoseconds
                    < preparation.command.lease
                        .expiresAtMonotonicNanoseconds,
                  receipt.menuAppGeneration
                    == requirement.admission.visibleMenuAppGeneration,
                  receipt.menuAppRevision
                    >= requirement.admission.visibleMenuAppRevision else {
                throw InteractiveInitialRuntimeCommandErrorV1.receiptRejected
            }
            try receipt.validate(against: preparation.command)
            let nowMilliseconds = Int64(
                nowMonotonicNanoseconds / 1_000_000
            )
            _ = try bootstrap.session.apply(
                .executorReadyUnlocked(
                    monotonicNowMilliseconds: nowMilliseconds
                )
            )
        } catch {
            self.bootstrap = bootstrap
            requireTeardown()
            throw InteractiveInitialRuntimeCommandErrorV1.receiptRejected
        }
        self.bootstrap = bootstrap
        installedReceipt = receipt
        state = .installed
    }

    /// Transfers role credentials and active session state exactly once to the
    /// Agent runtime owner after receipt acceptance.
    public mutating func takeInstalledBootstrap()
        throws -> InteractiveSessionBootstrap {
        guard state == .installed, let bootstrap else {
            throw InteractiveInitialRuntimeCommandErrorV1.invalidState(state)
        }
        self.bootstrap = nil
        state = .transferred
        return bootstrap
    }

    private mutating func requireTeardown() {
        if var bootstrap {
            bootstrap.inputChannelAuthority.invalidate()
            bootstrap.mediaChannelAuthority.invalidate()
            if bootstrap.session.state == .starting {
                _ = try? bootstrap.session.apply(.end(.protocolViolation))
            }
            self.bootstrap = bootstrap
        }
        state = .teardownRequired
    }

    private func nanoseconds(_ milliseconds: Int64) throws -> UInt64 {
        guard milliseconds >= 0 else {
            throw InteractiveInitialRuntimeCommandErrorV1.invalidTime
        }
        let (result, overflow) = UInt64(milliseconds)
            .multipliedReportingOverflow(by: 1_000_000)
        guard !overflow else {
            throw InteractiveInitialRuntimeCommandErrorV1.invalidTime
        }
        return result
    }
}
