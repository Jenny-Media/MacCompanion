import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionIPC
import Foundation
import OSLog

private let agentInteractiveLeaseRenewalLoggerV1 = Logger(
    subsystem: "media.jenny.maccompanion.agent",
    category: "interactive-lease-renewal"
)

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
    ) async throws -> AgentInteractiveLeaseRenewalResultV1
}

/// Both facts are captured in the runtime's serialized renewal operation,
/// after any preceding surface transition, never by a separate snapshot read.
public struct AgentInteractiveLeaseRenewalResultV1: Sendable {
    public let previous: InteractiveExecutionLease
    public let renewal: InteractiveRuntimeLeaseRenewalV0

    public init(previous: InteractiveExecutionLease, renewal: InteractiveRuntimeLeaseRenewalV0) {
        self.previous = previous
        self.renewal = renewal
    }

    func validate(scheduled: InteractiveExecutionLease, initial: InteractiveExecutionLease,
                  now: UInt64) throws {
        try renewal.validate(current: previous)
        let replacement = renewal.replacement
        let advancedSurface = previous.renewalCounter > scheduled.renewalCounter
            && previous.surfaceRevision.rawValue > scheduled.surfaceRevision.rawValue
            && previous.coordinateRevision.rawValue > scheduled.coordinateRevision.rawValue
        guard previous == scheduled || advancedSurface,
              previous.hostID == initial.hostID,
              previous.deviceID == initial.deviceID,
              previous.interactiveSessionID == initial.interactiveSessionID,
              previous.authorizationEpoch == initial.authorizationEpoch,
              previous.selectedDisplayID == initial.selectedDisplayID,
              Set(initial.allowedInteractionClasses).isSuperset(of: previous.allowedInteractionClasses),
              previous.issuedAtMonotonicNanoseconds >= scheduled.issuedAtMonotonicNanoseconds,
              replacement.issuedAtMonotonicNanoseconds >= now,
              replacement.expiresAtMonotonicNanoseconds > now else {
            throw AgentInteractiveLeaseRenewalOwnerErrorV1.invalidLease
        }
    }
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
    private struct PendingInstall {
        let token: UUID
        let sessionID: UUID
        let primaryConnectionID: Data
        var fenced = false
    }
    private var pendingInstall: PendingInstall?

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
        let sessionID = bootstrap.acceptedBody.interactiveSessionID.rawValue
        let token = try reserveInstall(sessionID: sessionID,
            primaryConnectionID: requirement.command.primaryConnectionID)
        defer { if pendingInstall?.token == token { pendingInstall = nil } }
        try await runtime.install(bootstrap, requirement: requirement)
        try await startInstalledRuntime(
            interactiveSessionID: sessionID,
            primaryConnectionID: requirement.command.primaryConnectionID,
            token: token
        )
    }

#if DEBUG
    /// Internal test entry after a disposable runtime has installed its lease.
    /// It grants nothing and is absent from Release; shipping always uses install.
    func startForInstalledTestRuntime(
        interactiveSessionID: UUID, primaryConnectionID: Data
    ) async throws {
        guard primaryConnectionID.count == 16 else {
            throw AgentInteractiveLeaseRenewalOwnerErrorV1.unavailable
        }
        let token = try reserveInstall(sessionID: interactiveSessionID,
            primaryConnectionID: primaryConnectionID)
        defer { if pendingInstall?.token == token { pendingInstall = nil } }
        try await startInstalledRuntime(interactiveSessionID: interactiveSessionID,
                                        primaryConnectionID: primaryConnectionID, token: token)
    }
#endif

    private func startInstalledRuntime(
        interactiveSessionID: UUID, primaryConnectionID: Data, token: UUID
    ) async throws {
        try requireUnfencedInstall(token)
        let snapshot = await runtime.activeLeaseForScheduling()
        try requireUnfencedInstall(token)
        guard let lease = snapshot,
              lease.interactiveSessionID == interactiveSessionID else {
            await runtime.terminate(
                interactiveSessionID: interactiveSessionID,
                primaryConnectionID: primaryConnectionID,
                reason: .protocolViolation
            )
            throw AgentInteractiveLeaseRenewalOwnerErrorV1.invalidLease
        }
        startRenewalLoop(
            initialLease: lease,
            primaryConnectionID: primaryConnectionID
        )
    }

    public func terminate(
        interactiveSessionID: UUID,
        primaryConnectionID: Data,
        reason: InteractiveSessionEndReason
    ) async {
        if pendingInstall?.sessionID == interactiveSessionID,
           pendingInstall?.primaryConnectionID == primaryConnectionID {
            pendingInstall?.fenced = true
        }
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

    private func reserveInstall(sessionID: UUID, primaryConnectionID: Data) throws -> UUID {
        guard renewalTask == nil, pendingInstall == nil else {
            throw AgentInteractiveLeaseRenewalOwnerErrorV1.unavailable
        }
        let token = UUID()
        pendingInstall = PendingInstall(token: token, sessionID: sessionID,
            primaryConnectionID: primaryConnectionID)
        return token
    }

    private func requireUnfencedInstall(_ token: UUID) throws {
        guard pendingInstall?.token == token, pendingInstall?.fenced == false else {
            throw AgentInteractiveLeaseRenewalOwnerErrorV1.unavailable
        }
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
                agentInteractiveLeaseRenewalLoggerV1.notice(
                    "lease renewal started scheduledCounter=\(lease.renewalCounter, privacy: .public)"
                )
                do {
                    let result = try await runtime.renewActiveLease(
                        nowMonotonicNanoseconds: renewalSample
                    )
                    do {
                        try result.validate(scheduled: lease, initial: initialLease, now: renewalSample)
                    } catch {
                        agentInteractiveLeaseRenewalLoggerV1.error("lease renewal result rejected")
                        await runtime.terminate(
                            interactiveSessionID:
                                lease.interactiveSessionID,
                            primaryConnectionID: primaryConnectionID,
                            reason: .protocolViolation
                        )
                        break
                    }
                    let replacement = result.renewal.replacement
                    agentInteractiveLeaseRenewalLoggerV1.notice(
                        "lease renewed counter=\(replacement.renewalCounter, privacy: .public)"
                    )
                    lease = replacement
                } catch {
                    agentInteractiveLeaseRenewalLoggerV1.error(
                        "lease renewal failed error=\(String(describing: error), privacy: .public)"
                    )
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
