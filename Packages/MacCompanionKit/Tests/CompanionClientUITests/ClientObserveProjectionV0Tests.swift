import CompanionClient
import CompanionClientUI
import CompanionDomain
import CompanionObservation
import CompanionWire
import Foundation
import Testing

private let observeUIHostID = UUID(
    uuidString: "018fa800-0000-7000-8000-000000000001"
)!

private func observeUIStatus(
    hostState: HostState = .userSessionActive
) throws -> ClientObservedStatusV0 {
    ClientObservedStatusV0(
        snapshot: try StatusSnapshotBody(
            hostID: WireUUID(observeUIHostID),
            generation: WireUUID(UUID()),
            revision: 3,
            observedAtUnixMilliseconds: 10_000,
            validForMilliseconds: 1_000,
            hostState: hostState,
            system: SystemOverview(
                osName: "macOS",
                osVersion: "26.0",
                osBuild: "25A100",
                uptimeSeconds: 500,
                cpuUtilizationBasisPoints: 1_250,
                memoryTotalBytes: 16_000,
                memoryUsedBytes: 8_000,
                storageTotalBytes: 100_000,
                storageAvailableBytes: 40_000,
                powerSource: .ac,
                batteryLevelPercent: 80
            )
        ),
        freshness: try ObservationFreshness(
            observedAtUnixMilliseconds: 10_000,
            responseSentAtUnixMilliseconds: 10_100,
            requestStartedAtMonotonicMilliseconds: 1_000,
            receivedAtMonotonicMilliseconds: 1_200,
            validForMilliseconds: 1_000
        )
    )
}

@Test func observeProjectionDistinguishesWaitingFromNoReachableStatus()
    throws
{
    let waiting = try ClientObserveStatusProjectionV0(
        status: nil,
        reachability: .reachable,
        monotonicNowMilliseconds: 1_000
    )
    #expect(waiting.state == .waitingForStatus)
    #expect(waiting.canRefresh)

    let unavailable = try ClientObserveStatusProjectionV0(
        status: nil,
        reachability: .unreachable,
        monotonicNowMilliseconds: 1_000
    )
    #expect(unavailable.state == .unavailable)
    #expect(!unavailable.canRefresh)
}

@Test func observeProjectionUsesExclusiveLiveDeadlineAndValidatedMetrics()
    throws
{
    let status = try observeUIStatus()
    let live = try ClientObserveStatusProjectionV0(
        status: status,
        reachability: .reachable,
        monotonicNowMilliseconds: 1_899
    )
    #expect(live.state == .live)
    #expect(live.system?.hostState == "User session active")
    #expect(live.system?.cpuUtilizationBasisPoints == 1_250)
    #expect(live.system?.power == "Power adapter, 80%")

    let stale = try ClientObserveStatusProjectionV0(
        status: status,
        reachability: .reachable,
        monotonicNowMilliseconds: 1_900
    )
    #expect(stale.state == .stale)
    #expect(stale.estimatedAgeMilliseconds == 1_000)
}

@Test func observeProjectionNeverPresentsRetainedStatusAsLiveWhenDisconnected()
    throws
{
    let status = try observeUIStatus(hostState: .userSessionLocked)
    let projection = try ClientObserveStatusProjectionV0(
        status: status,
        reachability: .unreachable,
        monotonicNowMilliseconds: 1_201
    )
    #expect(projection.state == .unreachable)
    #expect(projection.title == "Mac unreachable")
    #expect(projection.system?.hostState == "Mac locked")
    #expect(!projection.canRefresh)
}

@Test func observeIssueCopyUsesOnlyStableCodeAndRetryClass() throws {
    let issue = ClientObserveIssueProjectionV0(
        request: .audit,
        error: ClientObserveRemoteErrorV0(try ProtocolErrorResponseBody(
            code: "policy.denied",
            retry: .afterUserAction
        ))
    )
    #expect(issue.title == "Activity could not be loaded")
    #expect(issue.diagnosticCode == "policy.denied")
    #expect(issue.detail == "Review the Mac or device settings, then try again.")
}

@Test func observeWorkspaceKeepsLatestBoundedPageAndGapEvidence() throws {
    let event = try AuditSelfEventWireV1(
        sequence: 2,
        eventID: WireUUID(UUID()),
        observedAtUnixMilliseconds: 10_000,
        scope: .selfDevice,
        actor: .agent,
        code: .connectionOpened,
        outcome: .succeeded
    )
    let page = try AuditListResponseBodyV1(
        events: [event],
        nextBeforeSequence: nil,
        oldestVisibleSequence: 1,
        newestVisibleSequence: 2,
        gaps: AuditGapWireV1(
            prunedThroughSequence: 1,
            droppedEventCount: 3
        )
    )
    let workspace = try ClientObserveWorkspaceProjectionV0(
        macName: "Studio Mac",
        observedStatus: try observeUIStatus(),
        reachability: .reachable,
        monotonicNowMilliseconds: 1_201,
        latestActivityPage: page
    )
    #expect(workspace.macName == "Studio Mac")
    #expect(workspace.activity?.rows.count == 1)
    #expect(workspace.activity?.gaps.historyIsIncomplete == true)
    #expect(workspace.activity?.gaps.messages.last
        == "3 scoped events were not retained.")
}
