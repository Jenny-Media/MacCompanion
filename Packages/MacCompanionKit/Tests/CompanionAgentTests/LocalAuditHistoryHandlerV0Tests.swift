import CompanionAgent
import CompanionIPC
import CompanionPersistence
import Foundation
import Testing

private struct LocalAuditHandlerTemporaryStore {
    let directory: URL
    let store: SQLiteBoundedAuditStoreV0

    init(rateLimitAttempts: Int = 120) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "maccompanion-local-audit-handler-\(UUID())",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        store = try SQLiteBoundedAuditStoreV0(
            path: directory.appendingPathComponent("audit.sqlite3").path,
            configuration: try AuditStoreConfigurationV0(
                logicalByteLimit: 16 * 1_024 * 1_024,
                retainedRowLimit: 50_000,
                retentionMilliseconds: 30 * 24 * 60 * 60 * 1_000,
                rateLimitAttempts: rateLimitAttempts,
                rateLimitWindowMilliseconds: 60_000
            )
        )
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private func handlerAuditDraft(
    sequenceTime: Int64,
    deviceID: UUID,
    code: AuditEventCodeV0
) throws -> AuditEventDraftV0 {
    try AuditEventDraftV0(
        eventID: UUID(),
        observedAtUnixMilliseconds: sequenceTime,
        actor: .pairedDevice,
        visibility: .subjectDevice,
        subjectDeviceID: deviceID,
        code: code,
        capabilityID: "maccompanion.system.setAudioMuted",
        outcome: .succeeded,
        importance: .bestEffort
    )
}

@Test func localAuditHandlerMapsOnlyBoundedLocalAdministrationPages() async throws {
    let temporary = try LocalAuditHandlerTemporaryStore()
    defer { temporary.remove() }
    let deviceA = UUID()
    let deviceB = UUID()
    _ = try await temporary.store.append(try handlerAuditDraft(
        sequenceTime: 1,
        deviceID: deviceA,
        code: .operationRequested
    ))
    _ = try await temporary.store.append(try handlerAuditDraft(
        sequenceTime: 2,
        deviceID: deviceB,
        code: .operationCompleted
    ))
    _ = try await temporary.store.append(try handlerAuditDraft(
        sequenceTime: 3,
        deviceID: deviceA,
        code: .interactiveStarted
    ))
    let handler = LocalAuditHistoryHandlerV0(store: temporary.store)
    let firstRequest = try LocalAuditPageRequestV0(
        requestID: UUID(),
        limit: 2
    )
    let first = try await handler.handle(firstRequest)

    try first.validate(against: firstRequest)
    #expect(first.events.map(\.sequence) == [3, 2])
    #expect(first.events.map(\.subjectDeviceID) == [deviceA, deviceB])
    #expect(first.nextBeforeSequence == 2)

    let secondRequest = try LocalAuditPageRequestV0(
        requestID: UUID(),
        beforeSequence: first.nextBeforeSequence,
        limit: 2
    )
    let second = try await handler.handle(secondRequest)
    #expect(second.events.map(\.sequence) == [1])
    #expect(second.nextBeforeSequence == nil)
}

@Test func localAuditHandlerPreservesStoreBoundsAndGapMetadata() async throws {
    let temporary = try LocalAuditHandlerTemporaryStore(rateLimitAttempts: 1)
    defer { temporary.remove() }
    let deviceID = UUID()
    _ = try await temporary.store.append(try handlerAuditDraft(
        sequenceTime: 1,
        deviceID: deviceID,
        code: .operationRequested
    ))
    #expect(try await temporary.store.append(try handlerAuditDraft(
        sequenceTime: 2,
        deviceID: deviceID,
        code: .operationCompleted
    )) == .droppedRateLimited)
    let handler = LocalAuditHistoryHandlerV0(store: temporary.store)
    let request = try LocalAuditPageRequestV0(requestID: UUID(), limit: 10)
    let page = try await handler.handle(request)

    #expect(page.correlationID == request.requestID)
    #expect(page.gaps.droppedEventCount == 1)
    #expect(page.oldestVisibleSequence == 1)
    #expect(page.newestVisibleSequence == 1)
}
