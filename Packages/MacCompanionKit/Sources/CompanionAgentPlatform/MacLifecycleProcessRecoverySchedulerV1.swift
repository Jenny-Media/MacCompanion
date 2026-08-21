import CompanionAgent
import Foundation

/// Owns the one bounded retry loop for each login role after the observation
/// owner has retained an exact lifecycle/epoch recovery fence. These retries
/// are safe only for idempotent requests to start an already-registered login
/// role; semantic remote operations never use this policy.
package actor MacLifecycleProcessRecoverySchedulerV1 {
    package typealias Sleep = @Sendable (UInt64) async throws -> Void

    /// Three retries keep recovery responsive without allowing an unbounded
    /// crash loop. Physical Stage 0 evidence may tighten these constants, but
    /// final targets cannot silently expand the attempt count.
    package static let standardDelaysNanoseconds: [UInt64] = [
        250_000_000,
        1_000_000_000,
        4_000_000_000,
    ]

    private let observations: MacLifecycleProcessObservationOwnerV1
    private let delaysNanoseconds: [UInt64]
    private let sleep: Sleep
    private var agentTask: Task<Void, Never>?
    private var menuTask: Task<Void, Never>?

    package init(
        observations: MacLifecycleProcessObservationOwnerV1,
        delaysNanoseconds: [UInt64] = standardDelaysNanoseconds,
        sleep: @escaping Sleep = { try await Task.sleep(nanoseconds: $0) }
    ) {
        precondition(
            !delaysNanoseconds.isEmpty
                && delaysNanoseconds.count <= 3
                && delaysNanoseconds.allSatisfy { $0 > 0 && $0 <= 30_000_000_000 }
        )
        self.observations = observations
        self.delaysNanoseconds = delaysNanoseconds
        self.sleep = sleep
    }

    package func schedule(role: AgentLoginRoleV1) {
        task(for: role)?.cancel()
        let observations = self.observations
        let delays = delaysNanoseconds
        let sleep = self.sleep
        let task = Task {
            for delay in delays {
                do {
                    try await sleep(delay)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                let disposition = await observations.retryPendingRecovery(
                    role: role
                )
                switch disposition {
                case .recoveryNotCompleted, .recoveryOutcomeUnknown:
                    continue
                case .accepted, .duplicate, .ignoredStale, .notEligible:
                    return
                }
            }
        }
        setTask(task, for: role)
    }

    package func waitUntilIdle(role: AgentLoginRoleV1) async {
        await task(for: role)?.value
    }

    private func task(for role: AgentLoginRoleV1) -> Task<Void, Never>? {
        switch role {
        case .agent: agentTask
        case .menuApp: menuTask
        }
    }

    private func setTask(
        _ task: Task<Void, Never>?,
        for role: AgentLoginRoleV1
    ) {
        switch role {
        case .agent: agentTask = task
        case .menuApp: menuTask = task
        }
    }
}
