import CompanionAgent
import CompanionLifecycle
import CompanionPersistence
import Foundation
import Testing

private func lifecycleAuditStore(
    suffix: String,
    faults: Set<AuditStoreFaultPointV0> = []
) throws -> SQLiteBoundedAuditStoreV0 {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-lifecycle-audit-\(suffix)-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return try SQLiteBoundedAuditStoreV0(
        path: directory.appendingPathComponent("audit.sqlite3").path,
        injectedFaults: faults
    )
}

private func completedLifecycleTransition(
    from before: ProductLifecycleState,
    event: ProductLifecycleEvent,
    transitionID: UUID = UUID(),
    observedAt: Int64 = 1_787_200_000_000
) throws -> CompletedLifecycleTransitionV0 {
    var after = before
    let effects = try after.apply(event)
    return try CompletedLifecycleTransitionV0(
        transitionID: transitionID,
        observedAtUnixMilliseconds: observedAt,
        before: before,
        event: event,
        after: after,
        effects: effects
    )
}

@Test func lifecycleAuditPublishesOnlyCoarseGlobalSecurityAndAvailability() async throws {
    let store = try lifecycleAuditStore(suffix: "coarse")
    let writer = BoundedLifecycleAuditWriterV0(store: store)
    let initial = ProductLifecycleState(consoleSession: .active)

    let enabled = try completedLifecycleTransition(
        from: initial,
        event: .enableRequested,
        transitionID: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    )
    await writer.recordCompletedTransition(enabled)

    let agentReady = try completedLifecycleTransition(
        from: enabled.after,
        event: .agentReady,
        transitionID: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
    )
    await writer.recordCompletedTransition(agentReady)

    let page = try await store.page(scope: .localAdministration, limit: 10)
    #expect(page.events.map(\.draft.code) == [
        .hostAvailabilityChanged,
        .hostSecurityStateChanged,
    ])
    #expect(page.events.map(\.draft.outcome) == [.succeeded, .succeeded])
    for event in page.events {
        #expect(event.draft.actor == .system)
        #expect(event.draft.visibility == .allPairedDevices)
        #expect(event.draft.subjectDeviceID == nil)
        #expect(event.draft.correlationID == nil)
        #expect(event.draft.capabilityID == nil)
        #expect(event.draft.importance == .bestEffort)
    }
    #expect(await writer.health() == .healthy)
}

@Test func lifecycleAuditIsIdempotentAndIgnoresNonGlobalTransitions() async throws {
    let store = try lifecycleAuditStore(suffix: "idempotent")
    let writer = BoundedLifecycleAuditWriterV0(store: store)
    var ready = ProductLifecycleState(consoleSession: .active)
    _ = try ready.apply(.enableRequested)
    _ = try ready.apply(.agentReady)
    _ = try ready.apply(.menuAppReady)

    let transition = try completedLifecycleTransition(
        from: ready,
        event: .menuAppExited,
        transitionID: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
    )
    await writer.recordCompletedTransition(transition)
    await writer.recordCompletedTransition(transition)

    let page = try await store.page(scope: .localAdministration, limit: 10)
    #expect(page.events.isEmpty)
    #expect(await writer.health() == .healthy)
}

@Test func lifecycleAuditFailureCannotChangeCompletedRecoveryTransition() async throws {
    let store = try lifecycleAuditStore(
        suffix: "fault",
        faults: [.beforeInsert]
    )
    let writer = BoundedLifecycleAuditWriterV0(store: store)
    var ready = ProductLifecycleState(consoleSession: .active)
    _ = try ready.apply(.enableRequested)
    _ = try ready.apply(.agentReady)
    _ = try ready.apply(.menuAppReady)

    let transition = try completedLifecycleTransition(
        from: ready,
        event: .agentExited
    )
    #expect(transition.effects == [
        .endInteractiveControl,
        .closeAllRemoteSessions,
        .requestAgentRecovery,
    ])
    #expect(transition.after.agent == .starting)
    #expect(!transition.after.observeAvailable)

    await writer.recordCompletedTransition(transition)

    #expect(transition.after.agent == .starting)
    #expect(transition.effects.contains(.requestAgentRecovery))
    #expect(await writer.health() == .degraded)
    #expect(try await store.page(
        scope: .localAdministration,
        limit: 10
    ).events.isEmpty)
}

@Test func lifecycleAuditRejectsACompletionThatDoesNotMatchTheReducer() throws {
    let before = ProductLifecycleState(consoleSession: .active)
    var forgedAfter = before
    let effects = try forgedAfter.apply(.enableRequested)

    #expect(throws: LifecycleAuditTransitionErrorV0.mismatchedTransition) {
        try CompletedLifecycleTransitionV0(
            transitionID: UUID(),
            observedAtUnixMilliseconds: 1,
            before: before,
            event: .enableRequested,
            after: before,
            effects: effects
        )
    }
}
