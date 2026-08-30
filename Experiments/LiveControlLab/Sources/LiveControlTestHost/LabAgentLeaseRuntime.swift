#if !DEBUG
#error("Disposable Agent scheduler adapter is test-only")
#endif
@testable import CompanionAgent
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionIPC
import Foundation
import LiveControlLabSupport

/// Uses the shipping scheduler over the lab's own serialized lease/runtime.
/// This is deliberately NOT proof of Agent admission, XPC, or lease issuance.
struct LabAgentLeaseRuntime: AgentInteractiveLeaseRenewingRuntimeV1 {
    weak var session: HostSession?

    func install(_ bootstrap: InteractiveSessionBootstrap,
                 requirement: InteractiveSessionRuntimeRequirementV0) async throws {
        // The test-only scheduler entry is used only after actual menu install.
        throw LabError.unsupported
    }

    func activeLeaseForScheduling() async -> InteractiveExecutionLease? {
        await session?.leaseForAgentScheduling()
    }

    func renewActiveLease(nowMonotonicNanoseconds: UInt64) async throws -> AgentInteractiveLeaseRenewalResultV1 {
        guard let session else { throw LabError.closed }
        do {
            return try await session.renewForAgentScheduler()
        } catch {
            // Match the production runtime contract: an ambiguous renewal is
            // already fail-closed before the scheduler receives its error.
            await session.closeFromAgentScheduler()
            throw error
        }
    }

    func terminate(interactiveSessionID: UUID, primaryConnectionID: Data,
                   reason: InteractiveSessionEndReason) async {
        guard let session,
              await session.matchesAgentSession(interactiveSessionID, primaryConnectionID) else { return }
        await session.closeFromAgentScheduler()
    }
}
