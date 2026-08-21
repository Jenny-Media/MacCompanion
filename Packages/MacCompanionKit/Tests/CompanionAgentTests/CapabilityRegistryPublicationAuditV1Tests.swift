import CompanionAgent
import CompanionPersistence
import Foundation
import Testing

private func registryPublicationAuditStoreV1(
    suffix: String,
    faults: Set<AuditStoreFaultPointV0> = [],
    configuration: AuditStoreConfigurationV0 = .production
) throws -> SQLiteBoundedAuditStoreV0 {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-registry-publication-audit-\(suffix)-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return try SQLiteBoundedAuditStoreV0(
        path: directory.appendingPathComponent("audit.sqlite3").path,
        configuration: configuration,
        injectedFaults: faults
    )
}

@Test func registryAuditWriterIsClosedLocalAndIdempotent() async throws {
    let store = try registryPublicationAuditStoreV1(suffix: "success")
    let writer = BoundedCapabilityRegistryPublicationAuditWriterV1(store: store)
    let generation = UUID()
    await writer.recordCompletedReplacement(
        currentGeneration: generation,
        observedAtUnixMilliseconds: 1_787_300_000_000
    )
    await writer.recordCompletedReplacement(
        currentGeneration: generation,
        observedAtUnixMilliseconds: 1_787_300_000_000
    )

    let pageAfterSwap = try await store.page(
        scope: .localAdministration,
        limit: 10
    )
    #expect(pageAfterSwap.events.count == 1)
    let event = try #require(pageAfterSwap.events.first?.draft)
    #expect(event.eventID == generation)
    #expect(event.observedAtUnixMilliseconds == 1_787_300_000_000)
    #expect(event.actor == .agent)
    #expect(event.visibility == .localOnly)
    #expect(event.code == .capabilityRegistryChanged)
    #expect(event.outcome == .succeeded)
    #expect(event.importance == .bestEffort)
    #expect(event.subjectDeviceID == nil)
    #expect(event.correlationID == nil)
    #expect(event.capabilityID == nil)

    #expect(await writer.health() == .healthy)
}

@Test func registryAuditFailureDegradesHealth() async throws {
    let store = try registryPublicationAuditStoreV1(
        suffix: "fault",
        faults: [.beforeInsert]
    )
    let writer = BoundedCapabilityRegistryPublicationAuditWriterV1(store: store)
    await writer.recordCompletedReplacement(
        currentGeneration: UUID(),
        observedAtUnixMilliseconds: 1
    )

    #expect(await writer.health() == .degraded)
    #expect(try await store.page(
        scope: .localAdministration,
        limit: 10
    ).events.isEmpty)
}

@Test func registryAuditDurableDropDegradesHealth() async throws {
    let store = try registryPublicationAuditStoreV1(
        suffix: "drop",
        configuration: AuditStoreConfigurationV0(
            logicalByteLimit: 4 * AuditEventDraftV0.maximumLogicalSize,
            retainedRowLimit: 10,
            retentionMilliseconds: 60_000,
            rateLimitAttempts: 1,
            rateLimitWindowMilliseconds: 60_000
        )
    )
    _ = try await store.append(try AuditEventDraftV0(
        eventID: UUID(),
        observedAtUnixMilliseconds: 100,
        actor: .agent,
        visibility: .localOnly,
        code: .capabilityRegistryChanged,
        outcome: .succeeded,
        importance: .bestEffort
    ))
    let writer = BoundedCapabilityRegistryPublicationAuditWriterV1(store: store)
    await writer.recordCompletedReplacement(
        currentGeneration: UUID(),
        observedAtUnixMilliseconds: 101
    )

    #expect(await writer.health() == .degraded)
    let page = try await store.page(scope: .localAdministration, limit: 10)
    #expect(page.events.count == 1)
    #expect(page.gaps.droppedEventCount == 1)
}
