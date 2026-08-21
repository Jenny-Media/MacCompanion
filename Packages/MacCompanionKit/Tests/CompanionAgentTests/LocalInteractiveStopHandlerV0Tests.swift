import CompanionAgent
import CompanionDomain
import CompanionIPC
import CompanionPersistence
import Foundation
import Testing

private let stopCommandID = UUID(
    uuidString: "018f5200-0000-7000-8000-000000000001"
)!
private let stopDeviceID = UUID(
    uuidString: "018f2100-0000-7000-8000-000000000001"
)!
private let stopRequestID = UUID(
    uuidString: "018f5300-0000-7000-8000-000000000001"
)!
private let stopApprovalID = UUID(
    uuidString: "018f5400-0000-7000-8000-000000000001"
)!
private let stopSessionID = UUID(
    uuidString: "018f5500-0000-7000-8000-000000000001"
)!

private func stopCommand(
    sessionID: UUID? = stopSessionID
) throws -> LocalInteractiveStopCommandV0 {
    try LocalInteractiveStopCommandV0(
        commandID: stopCommandID,
        deviceID: stopDeviceID,
        deviceDisplayName: DeviceDisplayName("Jenny’s iPhone"),
        requestID: stopRequestID,
        approvalID: stopApprovalID,
        interactiveSessionID: sessionID,
        reason: .userRequested,
        occurredAtUnixMilliseconds: 10_000
    )
}

private actor StopTrace {
    private var values: [String] = []
    func append(_ value: String) { values.append(value) }
    func snapshot() -> [String] { values }
}

private struct TestRemoteEnder: LocalInteractiveRemoteAuthorityEndingV0 {
    let trace: StopTrace
    let mismatched: Bool
    let ended: Bool

    init(trace: StopTrace, mismatched: Bool = false, ended: Bool = true) {
        self.trace = trace
        self.mismatched = mismatched
        self.ended = ended
    }

    func endRemoteAuthority(
        for command: LocalInteractiveStopCommandV0
    ) async throws -> LocalInteractiveRemoteEndProofV0 {
        await trace.append("remote")
        return LocalInteractiveRemoteEndProofV0(
            deviceID: command.deviceID,
            requestID: mismatched ? UUID() : command.requestID,
            approvalID: command.approvalID,
            interactiveSessionID: command.interactiveSessionID,
            remoteAuthorityEnded: ended
        )
    }
}

private struct TestRuntimeTeardown: LocalInteractiveRuntimeTearingDownV0 {
    let trace: StopTrace
    let complete: Bool
    let mismatched: Bool

    init(trace: StopTrace, complete: Bool = true, mismatched: Bool = false) {
        self.trace = trace
        self.complete = complete
        self.mismatched = mismatched
    }

    func teardownRuntime(
        for command: LocalInteractiveStopCommandV0,
        after remoteEnd: LocalInteractiveRemoteEndProofV0
    ) async throws -> LocalInteractiveRuntimeTeardownProofV0 {
        await trace.append("runtime")
        return LocalInteractiveRuntimeTeardownProofV0(
            deviceID: command.deviceID,
            requestID: command.requestID,
            approvalID: command.approvalID,
            interactiveSessionID: mismatched
                ? UUID() : command.interactiveSessionID,
            runtimeTeardownComplete: complete,
            completedAtUnixMilliseconds: 10_001
        )
    }
}

private struct TestRuntimeRouter: LocalInteractiveRuntimeRevocationRoutingV0 {
    let route: LocalInteractiveRuntimeRevocationRouteV0

    func revokeRuntime(
        for command: LocalInteractiveStopCommandV0
    ) async throws -> LocalInteractiveRuntimeRevocationRouteV0 {
        route
    }
}

@Test func localStopClosesRemoteBeforeRuntimeAndReplaysReceipt() async throws {
    let trace = StopTrace()
    let handler = LocalInteractiveStopHandlerV0(
        remote: TestRemoteEnder(trace: trace),
        runtime: TestRuntimeTeardown(trace: trace)
    )
    let command = try stopCommand()
    let first = try await handler.handle(command)
    let replay = try await handler.handle(command)

    #expect(first == replay)
    #expect(first.remoteAuthorityEnded)
    #expect(first.runtimeTeardownComplete)
    #expect(await trace.snapshot() == ["remote", "runtime"])
}

@Test func pendingApprovalStopUsesExplicitNilAndStillProvesSafety() async throws {
    let trace = StopTrace()
    let handler = LocalInteractiveStopHandlerV0(
        remote: TestRemoteEnder(trace: trace),
        runtime: TestRuntimeTeardown(trace: trace)
    )
    let receipt = try await handler.handle(stopCommand(sessionID: nil))
    #expect(receipt.interactiveSessionID == nil)
    #expect(await trace.snapshot() == ["remote", "runtime"])
}

@Test func remoteMismatchOrFailureNeverStartsRuntimeTeardown() async throws {
    for remote in [
        TestRemoteEnder(trace: StopTrace(), mismatched: true),
        TestRemoteEnder(trace: StopTrace(), ended: false),
    ] {
        let trace = remote.trace
        let handler = LocalInteractiveStopHandlerV0(
            remote: remote,
            runtime: TestRuntimeTeardown(trace: trace)
        )
        await #expect(throws: (any Error).self) {
            _ = try await handler.handle(stopCommand())
        }
        #expect(await trace.snapshot() == ["remote"])
    }
}

@Test func incompleteOrMismatchedRuntimeProofNeverProducesStopReceipt() async throws {
    for runtime in [
        TestRuntimeTeardown(trace: StopTrace(), complete: false),
        TestRuntimeTeardown(trace: StopTrace(), mismatched: true),
    ] {
        let trace = runtime.trace
        let handler = LocalInteractiveStopHandlerV0(
            remote: TestRemoteEnder(trace: trace),
            runtime: runtime
        )
        await #expect(throws: (any Error).self) {
            _ = try await handler.handle(stopCommand())
        }
        #expect(await trace.snapshot() == ["remote", "runtime"])
    }
}

@Test func runtimeReceiptAdapterRequiresAllFourSafetyEffectsForActiveSession() async throws {
    let command = try stopCommand()
    let revoke = try InteractiveRuntimeRevokeCommandV0(
        commandID: UUID(),
        leaseID: UUID(),
        interactiveSessionID: stopSessionID,
        reason: .localSuspension
    )
    let receipt = try InteractiveRuntimeRevokedReceiptV0(
        correlationID: revoke.commandID,
        leaseID: revoke.leaseID,
        interactiveSessionID: revoke.interactiveSessionID,
        inputReleased: true,
        captureStopped: true,
        lastFrameBlanked: true,
        indicatorCleared: true
    )
    let route = LocalInteractiveRuntimeRevocationRouteV0(
        deviceID: command.deviceID,
        requestID: command.requestID,
        approvalID: command.approvalID,
        noRuntimeInstalled: false,
        revokeCommand: revoke,
        revokedReceipt: receipt,
        completedAtUnixMilliseconds: 10_001
    )
    let adapter = InteractiveRuntimeReceiptTeardownV0(
        router: TestRuntimeRouter(route: route)
    )
    let proof = try await adapter.teardownRuntime(
        for: command,
        after: LocalInteractiveRemoteEndProofV0(
            deviceID: command.deviceID,
            requestID: command.requestID,
            approvalID: command.approvalID,
            interactiveSessionID: command.interactiveSessionID,
            remoteAuthorityEnded: true
        )
    )
    #expect(proof.runtimeTeardownComplete)

    let mismatchedRoute = LocalInteractiveRuntimeRevocationRouteV0(
        deviceID: command.deviceID,
        requestID: command.requestID,
        approvalID: command.approvalID,
        noRuntimeInstalled: true,
        revokeCommand: nil,
        revokedReceipt: nil,
        completedAtUnixMilliseconds: 10_001
    )
    let mismatched = InteractiveRuntimeReceiptTeardownV0(
        router: TestRuntimeRouter(route: mismatchedRoute)
    )
    await #expect(
        throws: LocalInteractiveStopHandlerErrorV0.runtimeTeardownIncomplete
    ) {
        _ = try await mismatched.teardownRuntime(
            for: command,
            after: LocalInteractiveRemoteEndProofV0(
                deviceID: command.deviceID,
                requestID: command.requestID,
                approvalID: command.approvalID,
                interactiveSessionID: command.interactiveSessionID,
                remoteAuthorityEnded: true
            )
        )
    }
}

@Test func pendingRuntimeReceiptAdapterRequiresExplicitNoRuntimeProof() async throws {
    let command = try stopCommand(sessionID: nil)
    let route = LocalInteractiveRuntimeRevocationRouteV0(
        deviceID: command.deviceID,
        requestID: command.requestID,
        approvalID: command.approvalID,
        noRuntimeInstalled: true,
        revokeCommand: nil,
        revokedReceipt: nil,
        completedAtUnixMilliseconds: 10_001
    )
    let adapter = InteractiveRuntimeReceiptTeardownV0(
        router: TestRuntimeRouter(route: route)
    )
    let proof = try await adapter.teardownRuntime(
        for: command,
        after: LocalInteractiveRemoteEndProofV0(
            deviceID: command.deviceID,
            requestID: command.requestID,
            approvalID: command.approvalID,
            interactiveSessionID: nil,
            remoteAuthorityEnded: true
        )
    )
    #expect(proof.interactiveSessionID == nil)
    #expect(proof.runtimeTeardownComplete)
}

@Test func completedLocalStopPublishesOneIdempotentBestEffortEvent() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-local-stop-audit-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SQLiteBoundedAuditStoreV0(
        path: directory.appendingPathComponent("audit.sqlite3").path
    )
    let writer = BoundedLocalInteractiveStopAuditWriterV0(store: store)
    let trace = StopTrace()
    let handler = LocalInteractiveStopHandlerV0(
        remote: TestRemoteEnder(trace: trace),
        runtime: TestRuntimeTeardown(trace: trace),
        auditWriter: writer
    )
    let command = try stopCommand()

    let first = try await handler.handle(command)
    let replay = try await handler.handle(command)
    let page = try await store.page(scope: .localAdministration, limit: 10)

    #expect(first == replay)
    #expect(page.events.count == 1)
    #expect(page.events.first?.draft.eventID == command.commandID)
    #expect(page.events.first?.draft.code == .interactiveStopped)
    #expect(page.events.first?.draft.interactiveSessionID == stopSessionID)
    #expect(page.events.first?.draft.importance == .bestEffort)
    #expect(await writer.health() == .healthy)
}

@Test func stopAuditFailureCannotDelayCompletedSafetyTeardown() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-local-stop-audit-fault-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SQLiteBoundedAuditStoreV0(
        path: directory.appendingPathComponent("audit.sqlite3").path,
        injectedFaults: [.afterCompaction]
    )
    let writer = BoundedLocalInteractiveStopAuditWriterV0(store: store)
    let trace = StopTrace()
    let handler = LocalInteractiveStopHandlerV0(
        remote: TestRemoteEnder(trace: trace),
        runtime: TestRuntimeTeardown(trace: trace),
        auditWriter: writer
    )

    let receipt = try await handler.handle(stopCommand())

    #expect(receipt.remoteAuthorityEnded)
    #expect(receipt.runtimeTeardownComplete)
    #expect(await trace.snapshot() == ["remote", "runtime"])
    #expect(await writer.health() == .degraded)
}

@Test func droppedStopAuditDegradesHealthAfterCompletedSafetyTeardown() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-local-stop-audit-drop-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SQLiteBoundedAuditStoreV0(
        path: directory.appendingPathComponent("audit.sqlite3").path,
        configuration: try AuditStoreConfigurationV0(
            logicalByteLimit: 16 * 1_024 * 1_024,
            retainedRowLimit: 50_000,
            retentionMilliseconds: 30 * 24 * 60 * 60 * 1_000,
            rateLimitAttempts: 1,
            rateLimitWindowMilliseconds: 60_000
        )
    )
    _ = try await store.append(try AuditEventDraftV0(
        eventID: UUID(),
        observedAtUnixMilliseconds: 9_999,
        actor: .localUser,
        visibility: .subjectDevice,
        subjectDeviceID: stopDeviceID,
        code: .interactiveRequested,
        importance: .bestEffort
    ))
    let writer = BoundedLocalInteractiveStopAuditWriterV0(store: store)
    let trace = StopTrace()
    let handler = LocalInteractiveStopHandlerV0(
        remote: TestRemoteEnder(trace: trace),
        runtime: TestRuntimeTeardown(trace: trace),
        auditWriter: writer
    )

    let receipt = try await handler.handle(stopCommand())

    #expect(receipt.runtimeTeardownComplete)
    #expect(await trace.snapshot() == ["remote", "runtime"])
    #expect(await writer.health() == .degraded)
    #expect(try await store.page(
        scope: .localAdministration,
        limit: 10
    ).gaps.droppedEventCount == 1)
}
