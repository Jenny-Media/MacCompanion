import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionIPC
import Foundation

public enum AgentInteractiveLeaseRenewalOwnerErrorV1:
    Error,
    Equatable,
    Sendable
{
    case unavailable
    case invalidLease
}

public protocol AgentInteractiveLeaseRenewingRuntimeV1:
    InteractiveSessionRuntimeOwningV0
{
    func activeLeaseForScheduling() async -> InteractiveExecutionLease?

    func renewActiveLease(
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveExecutionLease
}

extension AgentInteractiveRuntimeOwnerV1:
    AgentInteractiveLeaseRenewingRuntimeV1
{}

/// Product-level owner that starts renewal only after the exact initial lease
/// install returns. Each successful renewal supplies the next authoritative
/// deadline. A failed or ambiguous renewal is never retried: the underlying
/// runtime owner performs fail-closed revocation and this loop terminates.
public actor AgentInteractiveLeaseRenewalOwnerV1:
    InteractiveSessionRuntimeOwningV0
{
    public static let renewalLeadNanoseconds: UInt64 = 2_000_000_000

    public typealias Sleep = @Sendable (UInt64) async throws -> Void

    private let runtime: any AgentInteractiveLeaseRenewingRuntimeV1
    private let monotonicNowNanoseconds: @Sendable () -> UInt64
    private let sleep: Sleep
    private var renewalTask: (token: UUID, task: Task<Void, Never>)?

    public init(
        runtime: any AgentInteractiveLeaseRenewingRuntimeV1,
        monotonicNowNanoseconds: @escaping @Sendable () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds
        },
        sleep: @escaping Sleep = { nanoseconds in
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    ) {
        self.runtime = runtime
        self.monotonicNowNanoseconds = monotonicNowNanoseconds
        self.sleep = sleep
    }

    public func install(
        _ bootstrap: InteractiveSessionBootstrap,
        requirement: InteractiveSessionRuntimeRequirementV0
    ) async throws {
        guard renewalTask == nil else {
            throw AgentInteractiveLeaseRenewalOwnerErrorV1.unavailable
        }
        try await runtime.install(bootstrap, requirement: requirement)
        guard let lease = await runtime.activeLeaseForScheduling(),
              lease.interactiveSessionID
                == bootstrap.acceptedBody.interactiveSessionID.rawValue else {
            await runtime.terminate(
                interactiveSessionID:
                    bootstrap.acceptedBody.interactiveSessionID.rawValue,
                primaryConnectionID: requirement.command.primaryConnectionID,
                reason: .protocolViolation
            )
            throw AgentInteractiveLeaseRenewalOwnerErrorV1.invalidLease
        }
        startRenewalLoop(
            initialLease: lease,
            primaryConnectionID: requirement.command.primaryConnectionID
        )
    }

    public func terminate(
        interactiveSessionID: UUID,
        primaryConnectionID: Data,
        reason: InteractiveSessionEndReason
    ) async {
        let task = renewalTask?.task
        renewalTask = nil
        task?.cancel()
        await task?.value
        await runtime.terminate(
            interactiveSessionID: interactiveSessionID,
            primaryConnectionID: primaryConnectionID,
            reason: reason
        )
    }

    private func startRenewalLoop(
        initialLease: InteractiveExecutionLease,
        primaryConnectionID: Data
    ) {
        let token = UUID()
        let runtime = self.runtime
        let now = monotonicNowNanoseconds
        let sleep = self.sleep
        let task = Task { [weak self] in
            var lease = initialLease
            while !Task.isCancelled {
                let sample = now()
                let renewalAt = lease.expiresAtMonotonicNanoseconds
                    > Self.renewalLeadNanoseconds
                    ? lease.expiresAtMonotonicNanoseconds
                        - Self.renewalLeadNanoseconds
                    : 0
                if renewalAt > sample {
                    do {
                        try await sleep(renewalAt - sample)
                    } catch {
                        break
                    }
                }
                guard !Task.isCancelled else { break }
                let renewalSample = now()
                do {
                    let replacement = try await runtime.renewActiveLease(
                        nowMonotonicNanoseconds: renewalSample
                    )
                    guard replacement.leaseID != lease.leaseID,
                          replacement.hostID == lease.hostID,
                          replacement.deviceID == lease.deviceID,
                          replacement.interactiveSessionID
                            == lease.interactiveSessionID,
                          replacement.authorizationEpoch
                            == lease.authorizationEpoch,
                          replacement.selectedDisplayID
                            == lease.selectedDisplayID,
                          replacement.surfaceID == lease.surfaceID,
                          replacement.surfaceRevision
                            == lease.surfaceRevision,
                          replacement.coordinateRevision
                            == lease.coordinateRevision,
                          replacement.allowedInteractionClasses
                            == lease.allowedInteractionClasses,
                          replacement.renewalCounter
                            == lease.renewalCounter + 1,
                          replacement.issuedAtMonotonicNanoseconds
                            == renewalSample,
                          replacement.expiresAtMonotonicNanoseconds
                            > renewalSample else {
                        await runtime.terminate(
                            interactiveSessionID:
                                lease.interactiveSessionID,
                            primaryConnectionID: primaryConnectionID,
                            reason: .protocolViolation
                        )
                        break
                    }
                    lease = replacement
                } catch {
                    break
                }
            }
            await self?.renewalLoopFinished(token: token)
        }
        renewalTask = (token, task)
    }

    private func renewalLoopFinished(token: UUID) {
        guard renewalTask?.token == token else { return }
        renewalTask = nil
    }
}
