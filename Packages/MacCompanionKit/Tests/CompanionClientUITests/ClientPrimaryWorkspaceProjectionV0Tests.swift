@testable import CompanionClient
@testable import CompanionClientNetworkPlatform
@testable import CompanionClientUI
import CompanionDomain
import CompanionInteractiveClient
import CompanionObservation
import CompanionStudy
import CompanionWire
import Foundation
import Testing

private let primaryWorkspaceHostID = UUID()

private func primaryWorkspaceStatus() throws -> ClientObservedStatusV0 {
    ClientObservedStatusV0(
        snapshot: try StatusSnapshotBody(
            hostID: WireUUID(primaryWorkspaceHostID),
            generation: WireUUID(UUID()),
            revision: 1,
            observedAtUnixMilliseconds: 10_000,
            validForMilliseconds: 1_000,
            hostState: .userSessionActive,
            system: SystemOverview(
                osName: "macOS",
                osVersion: "26.0",
                osBuild: "25A100",
                uptimeSeconds: 10,
                cpuUtilizationBasisPoints: 100,
                memoryTotalBytes: 1_000,
                memoryUsedBytes: 500,
                storageTotalBytes: 2_000,
                storageAvailableBytes: 1_000,
                powerSource: .ac,
                batteryLevelPercent: nil
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

private func primaryWorkspaceSnapshot(
    revision: UInt64,
    availability: NetworkClientPrimaryAvailabilityV0,
    status: ClientObservedStatusV0? = nil,
    statusError: ClientObserveRemoteErrorV0? = nil,
    auditError: ClientObserveRemoteErrorV0? = nil,
    latestObserveErrorRequest: ClientObserveRequestKindV0? = nil,
    catalog: GrantedCapabilityCatalogV1? = nil,
    catalogError: ClientOperationRemoteErrorV1? = nil,
    operationError: ClientOperationRemoteErrorV1? = nil,
    latestActErrorRequest: ClientActRequestKindV1? = nil,
    authenticatedRouteClass:
        NetworkClientAuthenticatedRouteClassV1? = nil,
    deviceState: DeviceAuthorizationState = .activeGranted,
    controlState: NetworkClientPrimaryControlStateV0 = .inactive
) -> NetworkClientPrimaryApplicationSnapshotV0 {
    let authenticatedSession = availability == .connected
        ? ClientAuthenticatedSessionV0(
            clientID: UUID(),
            hostID: primaryWorkspaceHostID,
            deviceID: UUID(),
            connectionID: Data(repeating: 0x44, count: 16),
            deviceState: deviceState,
            authorizationEpoch: .init(rawValue: 1),
            grantRevision: .init(rawValue: 1),
            policyRevision: .init(rawValue: 1),
            hostState: .userSessionActive,
            features: [],
            serverTimeUnixMilliseconds: 10_000
        ) : nil
    return NetworkClientPrimaryApplicationSnapshotV0(
        revision: revision,
        hostID: primaryWorkspaceHostID,
        availability: availability,
        authenticatedRouteClass: authenticatedRouteClass,
        authenticatedSession: authenticatedSession,
        observeChannel: nil,
        actChannel: nil,
        controlChannel: nil,
        observedStatus: status,
        latestAuditPage: nil,
        statusError: statusError,
        auditError: auditError,
        latestObserveErrorRequest: latestObserveErrorRequest,
        catalog: catalog,
        operationState: nil,
        approvalPrompt: nil,
        catalogRemoteError: catalogError,
        operationRemoteError: operationError,
        latestActErrorRequest: latestActErrorRequest,
        controlState: controlState,
        interactiveDisplayCatalog: nil
    )
}

@Test func primaryWorkspaceRequiresMacGrantForMonitorOnlyDevice() throws {
    let projection = try ClientPrimaryWorkspaceProjectionV0(
        macName: "Studio Mac",
        snapshot: primaryWorkspaceSnapshot(
            revision: 1,
            availability: .connected,
            deviceState: .activeMonitorOnly
        ),
        monotonicNowMilliseconds: 1_201
    )

    #expect(projection.control.mode == .grantRequired)
    #expect(projection.control.entry(hasLocalLiveProduct: false)
        == .grantRequired)
    #expect(projection.control.detail.contains("Allow Remote Control once"))
    #expect(projection.control.diagnosticCode == "interactive.grantRequired")
}

@Test func primaryWorkspaceStartsWaitingWithoutReusingPriorStatus() throws {
    let catalog = GrantedCapabilityCatalogV1(
        registryGeneration: WireUUID(UUID()),
        grantRevision: 1,
        policyRevision: 1,
        capabilities: []
    )
    let projection = try ClientPrimaryWorkspaceProjectionV0(
        macName: "Studio Mac",
        snapshot: primaryWorkspaceSnapshot(
            revision: 7,
            availability: .connected,
            catalog: catalog
        ),
        monotonicNowMilliseconds: 1_201
    )

    #expect(projection.revision == 7)
    #expect(projection.connected)
    #expect(projection.observe.status.state == .waitingForStatus)
    #expect(projection.approvedActions == catalog)
}

@Test func primaryWorkspaceRetainsStatusOnlyAsUnreachableAndHidesAct()
    throws
{
    let catalog = GrantedCapabilityCatalogV1(
        registryGeneration: WireUUID(UUID()),
        grantRevision: 1,
        policyRevision: 1,
        capabilities: []
    )
    let projection = try ClientPrimaryWorkspaceProjectionV0(
        macName: "Studio Mac",
        snapshot: primaryWorkspaceSnapshot(
            revision: 8,
            availability: .disconnected,
            status: try primaryWorkspaceStatus(),
            catalog: catalog
        ),
        monotonicNowMilliseconds: 1_201
    )

    #expect(!projection.connected)
    #expect(projection.observe.status.state == .unreachable)
    #expect(projection.approvedActions == nil)
    #expect(projection.operationState == nil)
}

@Test func primaryWorkspaceRendersOnlyLatestClosedIssueAndStableCodes()
    throws
{
    let statusError = ClientObserveRemoteErrorV0(
        try ProtocolErrorResponseBody(
            code: "provider.unavailable",
            retry: .afterReconnect
        )
    )
    let auditError = ClientObserveRemoteErrorV0(
        try ProtocolErrorResponseBody(
            code: "capability.registryChanged",
            retry: .afterUserAction
        )
    )
    let actError = ClientOperationRemoteErrorV1(
        try ProtocolErrorResponseBody(
            code: "operation.approvalNotFound",
            retry: .afterApproval
        )
    )
    let projection = try ClientPrimaryWorkspaceProjectionV0(
        macName: "Studio Mac",
        snapshot: primaryWorkspaceSnapshot(
            revision: 9,
            availability: .connected,
            statusError: statusError,
            auditError: auditError,
            latestObserveErrorRequest: .audit,
            operationError: actError,
            latestActErrorRequest: .operation
        ),
        monotonicNowMilliseconds: 1_201
    )

    #expect(projection.observe.issue?.diagnosticCode
        == "capability.registryChanged")
    #expect(projection.observe.issue?.title == "Activity could not be loaded")
    #expect(projection.actIssue?.diagnosticCode
        == "operation.approvalNotFound")
    #expect(projection.actIssue?.detail
        == "Approve the required access, then try again.")
}

@Test func primaryWorkspaceControlProjectionNeverClaimsAcceptedSessionIsActive()
    throws
{
    let interactiveSessionID = UUID()
    let accepted = try ClientPrimaryWorkspaceProjectionV0(
        macName: "Studio Mac",
        snapshot: primaryWorkspaceSnapshot(
            revision: 10,
            availability: .connected,
            controlState: .accepted(
                interactiveSessionID: interactiveSessionID,
                expiresAtUnixMilliseconds: 100_000,
                effects: [.view, .pointer]
            )
        ),
        monotonicNowMilliseconds: 1_201
    )
    #expect(accepted.control.mode == .acceptedPreparingChannels)
    #expect(accepted.control.detail.contains("still starting"))

    let channelsReady = try ClientPrimaryWorkspaceProjectionV0(
        macName: "Studio Mac",
        snapshot: primaryWorkspaceSnapshot(
            revision: 11,
            availability: .connected,
            controlState: .preparing(
                interactiveSessionID: interactiveSessionID,
                expiresAtUnixMilliseconds: 100_000,
                effects: [.view, .pointer],
                phase: .roleChannelsReady
            )
        ),
        monotonicNowMilliseconds: 1_201
    )
    #expect(channelsReady.control.mode == .channelsReady)
    #expect(channelsReady.control.detail.contains("opening Remote Control"))

    let preparingSurface = try ClientPrimaryWorkspaceProjectionV0(
        macName: "Studio Mac",
        snapshot: primaryWorkspaceSnapshot(
            revision: 12,
            availability: .connected,
            controlState: .preparing(
                interactiveSessionID: interactiveSessionID,
                expiresAtUnixMilliseconds: 100_000,
                effects: [.view, .pointer],
                phase: .initialSurface
            )
        ),
        monotonicNowMilliseconds: 1_201
    )
    #expect(preparingSurface.control.mode == .preparingInitialSurface)
    #expect(preparingSurface.control.detail.contains("first verified frame"))

    let active = try ClientPrimaryWorkspaceProjectionV0(
        macName: "Studio Mac",
        snapshot: primaryWorkspaceSnapshot(
            revision: 13,
            availability: .connected,
            controlState: .active(
                interactiveSessionID: interactiveSessionID,
                expiresAtUnixMilliseconds: 100_000,
                effects: [.view, .pointer]
            )
        ),
        monotonicNowMilliseconds: 1_201
    )
    #expect(active.control.mode == .active)
    #expect(active.control.detail.contains("is live"))

    let ending = try ClientPrimaryWorkspaceProjectionV0(
        macName: "Studio Mac",
        snapshot: primaryWorkspaceSnapshot(
            revision: 14,
            availability: .connected,
            controlState: .ending(
                interactiveSessionID: interactiveSessionID,
                effects: [.view, .pointer]
            )
        ),
        monotonicNowMilliseconds: 1_201
    )
    #expect(ending.control.mode == .ending)
    #expect(ending.control.detail.contains("safety cleanup"))

    let endFailed = try ClientPrimaryWorkspaceProjectionV0(
        macName: "Studio Mac",
        snapshot: primaryWorkspaceSnapshot(
            revision: 15,
            availability: .connected,
            controlState: .endFailed(
                interactiveSessionID: interactiveSessionID,
                effects: [.view, .pointer],
                error: ClientInteractiveRemoteErrorV0(
                    code: "interactive.hostUnavailable",
                    retry: .afterReconnect
                )
            )
        ),
        monotonicNowMilliseconds: 1_201
    )
    #expect(endFailed.control.mode == .endFailed)
    #expect(endFailed.control.diagnosticCode
        == "interactive.hostUnavailable")

    let failed = try ClientPrimaryWorkspaceProjectionV0(
        macName: "Studio Mac",
        snapshot: primaryWorkspaceSnapshot(
            revision: 16,
            availability: .connected,
            controlState: .preparationFailed(
                interactiveSessionID: interactiveSessionID,
                effects: [.view, .pointer],
                phase: .initialSurface
            )
        ),
        monotonicNowMilliseconds: 1_201
    )
    #expect(failed.control.mode == .preparationFailed)
    #expect(failed.control.diagnosticCode
        == "interactive.preparationFailed")

    let rejected = try ClientPrimaryWorkspaceProjectionV0(
        macName: "Studio Mac",
        snapshot: primaryWorkspaceSnapshot(
            revision: 17,
            availability: .connected,
            controlState: .remoteRejected(
                ClientInteractiveRemoteErrorV0(
                    code: "policy.denied",
                    retry: .afterUserAction
                )
            )
        ),
        monotonicNowMilliseconds: 1_201
    )
    #expect(rejected.control.mode == .rejected)
    #expect(rejected.control.diagnosticCode == "policy.denied")

    let activeElsewhere = try ClientPrimaryWorkspaceProjectionV0(
        macName: "Studio Mac",
        snapshot: primaryWorkspaceSnapshot(
            revision: 18,
            availability: .connected,
            controlState: .remoteRejected(
                ClientInteractiveRemoteErrorV0(
                    code: "interactive.sessionActive",
                    retry: .afterUserAction
                )
            )
        ),
        monotonicNowMilliseconds: 1_201
    )
    #expect(activeElsewhere.control.mode == .rejected)
    #expect(activeElsewhere.control.detail.contains(
        "already has an active Remote Control session"
    ))
    #expect(activeElsewhere.control.diagnosticCode
        == "interactive.sessionActive")

    let disconnected = try ClientPrimaryWorkspaceProjectionV0(
        macName: "Studio Mac",
        snapshot: primaryWorkspaceSnapshot(
            revision: 18,
            availability: .disconnected,
            controlState: .accepted(
                interactiveSessionID: UUID(),
                expiresAtUnixMilliseconds: 100_000,
                effects: [.view]
            )
        ),
        monotonicNowMilliseconds: 1_201
    )
    #expect(disconnected.control.mode == .unavailable)
}

@Test func primaryWorkspaceControlEntrySeparatesAuthorityFromPresentation()
    throws
{
    func control(
        _ state: NetworkClientPrimaryControlStateV0
    ) throws -> ClientControlWorkspaceProjectionV0 {
        try ClientPrimaryWorkspaceProjectionV0(
            macName: "Studio Mac",
            snapshot: primaryWorkspaceSnapshot(
                revision: 1,
                availability: .connected,
                controlState: state
            ),
            monotonicNowMilliseconds: 1_201
        ).control
    }

    let interactiveSessionID = UUID()
    #expect(try control(.inactive).entry(hasLocalLiveProduct: false)
        == .requestFullControl)
    #expect(try control(.requestSubmitted(effects: [.view]))
        .entry(hasLocalLiveProduct: false) == .wait)
    #expect(try control(.preparing(
        interactiveSessionID: interactiveSessionID,
        expiresAtUnixMilliseconds: 100_000,
        effects: [.view],
        phase: .roleChannelsReady
    )).entry(hasLocalLiveProduct: false) == .openLiveControl)
    #expect(try control(.preparing(
        interactiveSessionID: interactiveSessionID,
        expiresAtUnixMilliseconds: 100_000,
        effects: [.view],
        phase: .initialSurface
    )).entry(hasLocalLiveProduct: false) == .wait)
    #expect(try control(.preparing(
        interactiveSessionID: interactiveSessionID,
        expiresAtUnixMilliseconds: 100_000,
        effects: [.view],
        phase: .initialSurface
    )).entry(hasLocalLiveProduct: true) == .openLiveControl)
    #expect(try control(.ending(
        interactiveSessionID: interactiveSessionID,
        effects: [.view]
    )).entry(hasLocalLiveProduct: true) == .wait)
    #expect(try control(.preparationFailed(
        interactiveSessionID: interactiveSessionID,
        effects: [.view],
        phase: .initialSurface
    )).entry(hasLocalLiveProduct: false) == .stopFailedSession)
}

@Test func stage3MuteJobProjectionRequiresExactCapabilityAndTerminalOutcome() {
    let capabilityID = ClientStage3StudyActJobProjectionV1
        .setAudioMutedCapabilityID
    #expect(ClientStage3StudyActJobProjectionV1.result(
        capabilityID: capabilityID,
        state: .terminal(.succeeded(verifiedResult: nil))
    ) == .completed)
    #expect(ClientStage3StudyActJobProjectionV1.result(
        capabilityID: capabilityID,
        state: .terminal(.denied)
    ) == .denied)
    #expect(ClientStage3StudyActJobProjectionV1.result(
        capabilityID: capabilityID,
        state: .terminal(.cancelled)
    ) == .notCompleted)
    #expect(ClientStage3StudyActJobProjectionV1.result(
        capabilityID: capabilityID,
        state: .terminal(.failed(.providerUnavailable))
    ) == .failed)
    #expect(ClientStage3StudyActJobProjectionV1.result(
        capabilityID: capabilityID,
        state: .terminal(.outcomeUnknown)
    ) == .outcomeUnknown)
    #expect(ClientStage3StudyActJobProjectionV1.result(
        capabilityID: capabilityID,
        state: .awaitingInvokeReply
    ) == nil)
    #expect(ClientStage3StudyActJobProjectionV1.result(
        capabilityID: "maccompanion.system.keepAwake",
        state: .terminal(.succeeded(verifiedResult: nil))
    ) == nil)
}

@Test func stage3ControlJobProjectionAcceptsOnlyClosedControlCategories() {
    for category in Stage3StudyJobCategoryV1.allCases {
        let expected = switch category {
        case .controlUnexpectedDialog, .controlDevelopmentApp,
             .controlOtherOwnedApp:
            true
        case .observeLongRunningTask, .observeSystemHealth,
             .observeAvailability, .actSetAudioMuted:
            false
        }
        #expect(
            ClientStage3StudyControlJobProjectionV1.accepts(category)
                == expected
        )
    }
}

@Test func stage3ObserveJobProjectionAcceptsOnlyObserveCategories() {
    for category in Stage3StudyJobCategoryV1.allCases {
        let expected = switch category {
        case .observeLongRunningTask, .observeSystemHealth,
             .observeAvailability:
            true
        case .actSetAudioMuted, .controlUnexpectedDialog,
             .controlDevelopmentApp, .controlOtherOwnedApp:
            false
        }
        #expect(
            ClientStage3StudyObserveJobProjectionV1.accepts(category)
                == expected
        )
    }
}

@Test func stage3RouteProjectionMapsOnlyClosedAuthenticatedProvenance() {
    #expect(ClientStage3StudyRouteProjectionV1.routeClass(.lan) == .lan)
    #expect(ClientStage3StudyRouteProjectionV1.routeClass(.privateDNS)
        == .privateDNS)
    #expect(ClientStage3StudyRouteProjectionV1.routeClass(.privateNetwork)
        == .privateNetwork)
}

@MainActor
@Test func primaryWorkspaceModelRejectsOutOfOrderProjectionUpdates()
    async throws
{
    let primaryState = NetworkClientPrimaryApplicationStateV0(
        hostID: primaryWorkspaceHostID
    )
    let pair = AsyncStream<NetworkClientPrimaryApplicationSnapshotV0>
        .makeStream(bufferingPolicy: .unbounded)
    let model = try ClientPrimaryWorkspaceModelV0(
        macName: "Studio Mac",
        primaryState: primaryState,
        initialSnapshot: primaryWorkspaceSnapshot(
            revision: 0,
            availability: .disconnected
        ),
        updates: pair.stream,
        monotonicNowMilliseconds: { 1_201 }
    )
    model.start()
    pair.continuation.yield(primaryWorkspaceSnapshot(
        revision: 2,
        availability: .connected
    ))
    pair.continuation.yield(primaryWorkspaceSnapshot(
        revision: 1,
        availability: .disconnected,
        status: try primaryWorkspaceStatus()
    ))
    for _ in 0..<1_000 where model.projection.revision != 2 {
        await Task.yield()
    }

    #expect(model.projection.revision == 2)
    #expect(model.projection.connected)
    #expect(model.projection.observe.status.state == .waitingForStatus)
    model.stop()
    pair.continuation.finish()
}

@MainActor
@Test func primaryWorkspaceModelCapturesStudyTransitionsAndExplicitControlJob()
    async throws
{
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "maccompanion-workspace-study-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try AtomicFileStage3StudyReportStoreV1(
        directory: directory
    )
    let owner = Stage3StudyLocalReportOwnerV1(persistence: store)
    let capture = Stage3StudyLocalCaptureV1(
        reportOwner: owner,
        monotonicNowMilliseconds: { 2_000 }
    )
    _ = try await capture.enroll(Stage3StudyLocalEnrollmentV1(
        cohortPhase: .dogfood,
        studyCode: String(repeating: "A", count: 15) + "2",
        build: try Stage3StudyBuildV1(
            appVersion: "0.1.0",
            buildNumber: "1",
            iOSMajorVersion: 27,
            macOSMajorVersion: 27
        ),
        workaround: .returnOrDefer,
        adaptiveJobApplicable: true
    ))
    try await capture.beginSession(dayIndex: 0)
    _ = try await capture.recordSetupAttempted()
    _ = try await capture.recordPairingResult(
        .completed,
        developerIntervention: false,
        durationMilliseconds: 10
    )

    let primaryState = NetworkClientPrimaryApplicationStateV0(
        hostID: primaryWorkspaceHostID
    )
    let pair = AsyncStream<NetworkClientPrimaryApplicationSnapshotV0>
        .makeStream(bufferingPolicy: .unbounded)
    var captureFailureCount = 0
    let model = try ClientPrimaryWorkspaceModelV0(
        macName: "Studio Mac",
        primaryState: primaryState,
        initialSnapshot: primaryWorkspaceSnapshot(
            revision: 0,
            availability: .disconnected
        ),
        updates: pair.stream,
        monotonicNowMilliseconds: { 1_201 },
        studyCapture: capture,
        studyCaptureFailure: { captureFailureCount += 1 }
    )
    model.start()
    pair.continuation.yield(primaryWorkspaceSnapshot(
        revision: 1,
        availability: .connected,
        authenticatedRouteClass: .privateNetwork
    ))
    pair.continuation.yield(primaryWorkspaceSnapshot(
        revision: 2,
        availability: .connected,
        status: try primaryWorkspaceStatus()
    ))

    var report: Stage3StudyReportV1?
    for _ in 0..<1_000 {
        report = try await owner.currentReport()
        if report?.operationalEvents.count == 1,
           report?.firstFreshObserve == .completed,
           report?.routeClassesUsed == [.privateNetwork] { break }
        await Task.yield()
    }
    #expect(report?.operationalEvents == [
        try Stage3StudyOperationalEventV1(
            dayIndex: 0,
            kind: .connection,
            initiator: .system,
            result: .completed
        ),
    ])
    #expect(report?.firstFreshObserve == .completed)
    #expect(report?.routeClassesUsed == [.privateNetwork])
    #expect(report?.timings.timeToFirstFreshObserveMilliseconds == 0)
    #expect(report?.jobs.isEmpty == true)
    #expect(captureFailureCount == 0)

    _ = try await model.recordObserveStudyJob(
        category: .observeSystemHealth
    )
    let controlSnapshot = ClientStage3StudyControlSnapshotV1(
        modesUsed: [.desktop, .application],
        durationDelta: try Stage3StudyControlDurationDeltaV1(
            desktopMilliseconds: 100,
            applicationMilliseconds: 200
        )
    )
    _ = try await model.recordControlStudyJob(
        category: .controlDevelopmentApp,
        snapshot: controlSnapshot
    )
    report = try await owner.currentReport()
    #expect(report?.jobs == [
        try Stage3StudyJobV1(
            dayIndex: 0,
            path: .observe,
            category: .observeSystemHealth,
            result: .completed,
            controlWasActive: false
        ),
        try Stage3StudyJobV1(
            dayIndex: 0,
            path: .control,
            category: .controlDevelopmentApp,
            result: .completed,
            controlWasActive: true,
            controlModesUsed: [.desktop, .application]
        ),
    ])
    #expect(report?.controlDurations.desktopMilliseconds == 100)
    #expect(report?.controlDurations.applicationMilliseconds == 200)

    model.stop()
    pair.continuation.finish()
}
