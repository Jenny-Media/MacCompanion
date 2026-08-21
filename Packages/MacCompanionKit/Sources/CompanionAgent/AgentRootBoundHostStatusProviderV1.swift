import CompanionDomain
import CompanionHost
import CompanionHostPersistence
import CompanionHostSession
import CompanionPersistence
import Foundation

/// Platform measurement seams accepted by the release Agent. Host identity
/// and durable revision sequence ownership are intentionally absent.
public struct AgentHostStatusPlatformServicesV1: Sendable {
    package let sampler: any HostSystemSampling
    package let clock: any HostStatusClock
    package let initialGeneration: UUID
    package let validForMilliseconds: UInt32

    public init(
        sampler: any HostSystemSampling,
        clock: any HostStatusClock,
        initialGeneration: UUID,
        validForMilliseconds: UInt32 = 5_000
    ) {
        self.sampler = sampler
        self.clock = clock
        self.initialGeneration = initialGeneration
        self.validForMilliseconds = validForMilliseconds
    }
}

/// Lazily binds Observe status to the release root's exact host identity and
/// private security store. Lazy initialization avoids mutating durable status
/// state when some earlier Agent bootstrap gate fails.
package actor AgentRootBoundHostStatusProviderV1:
    HostStatusSnapshotProvidingV0
{
    private let hostID: UUID
    private let store: SQLiteSecurityStore
    private let platform: AgentHostStatusPlatformServicesV1
    private var authority: HostStatusAuthority?

    package init(
        hostID: UUID,
        store: SQLiteSecurityStore,
        platform: AgentHostStatusPlatformServicesV1
    ) {
        self.hostID = hostID
        self.store = store
        self.platform = platform
    }

    package func snapshot(
        hostState: HostState
    ) async throws -> HostStatusSnapshot {
        let authority: HostStatusAuthority
        if let existing = self.authority {
            authority = existing
        } else {
            let bootstrap = try await SQLiteStatusSequenceCommitter.bootstrap(
                store: store,
                initialGeneration: platform.initialGeneration
            )
            let created = try HostStatusAuthority(
                hostID: hostID,
                sequence: bootstrap.state,
                sampler: platform.sampler,
                clock: platform.clock,
                sequenceCommitter: bootstrap.committer,
                validForMilliseconds: platform.validForMilliseconds
            )
            self.authority = created
            authority = created
        }
        return try await authority.snapshot(hostState: hostState)
    }
}
