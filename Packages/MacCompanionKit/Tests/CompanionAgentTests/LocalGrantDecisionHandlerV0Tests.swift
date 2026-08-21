import CompanionAgent
import CompanionDomain
import CompanionIPC
import CompanionOperations
import CompanionPersistence
import CompanionWire
import CryptoKit
import Foundation
import Testing

private let agentDeviceID = UUID(
    uuidString: "018f2100-0000-7000-8000-0000000000a1"
)!
private let agentClientID = UUID(
    uuidString: "018f2000-0000-7000-8000-0000000000a1"
)!
private let agentPairingID = UUID(
    uuidString: "018f4000-0000-7000-8000-0000000000a1"
)!
private let agentReviewID = UUID(
    uuidString: "018f4100-0000-7000-8000-0000000000a1"
)!
private let agentCommandID = UUID(
    uuidString: "018f4200-0000-7000-8000-0000000000a1"
)!
private let agentDisplayName = try! DeviceDisplayName("Jenny’s iPhone")
private let agentAudioGrant = "maccompanion.system.setAudioMuted"
private let agentRegistryGeneration = UUID(
    uuidString: "018f4300-0000-7000-8000-0000000000a1"
)!

private struct FixedAgentCapabilityClockV1:
    CapabilityRegistryPublicationWallClockV1
{
    let value: Int64

    func nowUnixMilliseconds() -> Int64 { value }
}

private func agentDescriptor(
    destructive: Bool = false
) throws -> CapabilityDescriptorV1 {
    try CapabilityDescriptorV1(
        capabilityID: agentAudioGrant,
        schemaVersion: 1,
        providerID: "maccompanion.native",
        providerVersion: "1.0.0",
        providerGeneration: UUID(
            uuidString: "018f4300-0000-7000-8000-0000000000a2"
        )!,
        executionRevision: UUID(
            uuidString: "018f4300-0000-7000-8000-0000000000a3"
        )!,
        englishTitle: "Set audio mute",
        englishSummary: "Sets the Mac audio mute state.",
        parameterSchema: .object(properties: []),
        resultSchema: .object(properties: []),
        effects: CapabilityEffectFacts(
            dataAccess: .none,
            changesLocalState: .reversible,
            mayDisruptUser: true,
            invokesExternalService: false,
            usesCredentials: false,
            destructive: destructive,
            requiresForegroundSession: false,
            allowedWhileLocked: true,
            cancellation: .notApplicable
        )
    )
}

private func agentRegistry(
    generation: UUID = agentRegistryGeneration,
    destructive: Bool = false
) throws -> CapabilityRegistrySnapshotV1 {
    try CapabilityRegistrySnapshotV1(
        generation: generation,
        capabilities: [agentDescriptor(destructive: destructive)]
    )
}

private actor AgentCapabilityProviderV1: CapabilityProviderV1 {
    nonisolated let identity: CapabilityProviderIdentityV1

    init(descriptor: CapabilityDescriptorV1) {
        identity = CapabilityProviderIdentityV1(
            providerID: descriptor.providerID,
            providerVersion: descriptor.providerVersion,
            providerGeneration: descriptor.providerGeneration,
            executionRevision: descriptor.executionRevision
        )
    }

    func execute(
        _ request: CapabilityProviderRequestV1
    ) async -> CapabilityProviderOutcomeV1 {
        .failed(.unavailable)
    }
}

private func agentPublication(
    generation: UUID = agentRegistryGeneration,
    destructive: Bool = false
) throws -> CapabilityRegistryPublicationV1 {
    let descriptor = try agentDescriptor(destructive: destructive)
    return try CapabilityRegistryPublicationV1(
        registry: CapabilityRegistrySnapshotV1(
            generation: generation,
            capabilities: [descriptor]
        ),
        providers: [AgentCapabilityProviderV1(descriptor: descriptor)]
    )
}

private struct AgentTemporaryDatabase {
    let directory: URL
    let database: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "maccompanion-agent-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        database = directory.appendingPathComponent("security.sqlite3")
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private func makeAgentStore(
    at database: URL,
    faults: Set<PersistenceFaultPoint> = []
) async throws -> SQLiteSecurityStore {
    let store = try SQLiteSecurityStore(
        path: database.path,
        injectedFaults: faults
    )
    if faults.isEmpty {
        let sessionKey = P256.Signing.PrivateKey().publicKey.x963Representation
        let approvalKey = P256.Signing.PrivateKey().publicKey.x963Representation
        let record = try StoredDeviceRecord(
            deviceID: agentDeviceID,
            clientID: agentClientID,
            sessionPublicKeyX963: sessionKey,
            approvalPublicKeyX963: approvalKey,
            authorization: DeviceAuthorization(
                state: .activeMonitorOnly,
                authorizationEpoch: .init(rawValue: 1),
                grantRevision: .init(rawValue: 1)
            ),
            policyRevision: .init(rawValue: 1),
            createdAtUnixMilliseconds: 1_000,
            updatedAtUnixMilliseconds: 1_000
        )
        try await store.commitPairing(
            pairingID: agentPairingID,
            record: record
        )
        try await store.setDeviceDisplayName(
            agentDeviceID,
            displayName: agentDisplayName,
            occurredAtUnixMilliseconds: 1_100
        )
    }
    return store
}

private func agentReview(
    generation: UUID = agentRegistryGeneration,
    destructive: Bool = false
) throws -> PendingLocalGrantExpansionReviewV0 {
    try PendingLocalGrantExpansionReviewV0(
        reviewID: agentReviewID,
        deviceID: agentDeviceID,
        deviceDisplayName: agentDisplayName,
        authorizationEpoch: .init(rawValue: 1),
        grantRevision: .init(rawValue: 1),
        policyRevision: .init(rawValue: 1),
        currentGrants: CapabilityGrantSet([]),
        proposedGrants: CapabilityGrantSet([agentAudioGrant]),
        registryGeneration: generation,
        requestedDescriptors: [agentDescriptor(destructive: destructive)]
    )
}

private actor SuspendingGrantPersistence: LocalGrantDecisionPersistingV0 {
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    func resolve(
        _ command: LocalGrantDecisionCommandV0
    ) async throws -> LocalGrantDecisionDurableStateV0 {
        started = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return try LocalGrantDecisionDurableStateV0(
            grants: command.proposedGrantSet(),
            authorizationEpoch: command.expectedAuthorizationEpoch.advanced(),
            grantRevision: command.expectedGrantRevision.advanced(),
            policyRevision: command.expectedPolicyRevision,
            completedAtUnixMilliseconds: command.decidedAtUnixMilliseconds
        )
    }

    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private func agentCommand(
    decision: LocalGrantDecisionV0 = .approve,
    displayName: DeviceDisplayName = agentDisplayName
) throws -> LocalGrantDecisionCommandV0 {
    try LocalGrantDecisionCommandV0(
        commandID: agentCommandID,
        reviewID: agentReviewID,
        deviceID: agentDeviceID,
        deviceDisplayName: displayName,
        decision: decision,
        expectedAuthorizationEpoch: .init(rawValue: 1),
        expectedGrantRevision: .init(rawValue: 1),
        expectedPolicyRevision: .init(rawValue: 1),
        expectedCurrentGrants: CapabilityGrantSet([]),
        proposedGrants: CapabilityGrantSet([agentAudioGrant]),
        decidedAtUnixMilliseconds: 2_000
    )
}

@Test func approvedLocalReviewAtomicallyExpandsAndReplaysReceipt() async throws {
    let temporary = try AgentTemporaryDatabase()
    defer { temporary.remove() }
    let store = try await makeAgentStore(at: temporary.database)
    let handler = LocalGrantDecisionHandlerV0(
        persistence: SQLiteLocalGrantDecisionPersistenceV0(store: store),
        registry: try agentRegistry()
    )
    try await handler.register(agentReview())
    let command = try agentCommand()
    let first = try await handler.handle(command)
    let replay = try await handler.handle(command)

    #expect(first == replay)
    #expect(first.authorizationEpoch.rawValue == 2)
    #expect(first.grantRevision.rawValue == 2)
    let expectedGrants = try CapabilityGrantSet([agentAudioGrant])
    #expect(try first.storedGrantSet() == expectedGrants)
    let stored = try await store.deviceGrantIdentitySnapshot(agentDeviceID)
    #expect(stored.grants == expectedGrants)
    #expect(stored.device.authorization.authorizationEpoch.rawValue == 2)
    #expect(try await store.securityEventCount() == 3)
}

@Test func declinedLocalReviewRevalidatesButMutatesNothing() async throws {
    let temporary = try AgentTemporaryDatabase()
    defer { temporary.remove() }
    let store = try await makeAgentStore(at: temporary.database)
    let handler = LocalGrantDecisionHandlerV0(
        persistence: SQLiteLocalGrantDecisionPersistenceV0(store: store),
        registry: try agentRegistry()
    )
    try await handler.register(agentReview())
    let receipt = try await handler.handle(
        agentCommand(decision: .decline)
    )

    #expect(receipt.authorizationEpoch.rawValue == 1)
    #expect(receipt.grantRevision.rawValue == 1)
    #expect(try receipt.storedGrantSet().isEmpty)
    #expect(try await store.deviceGrants(agentDeviceID).isEmpty)
    #expect(try await store.securityEventCount() == 2)
}

@Test func menuCommandCannotAlterAnAgentIssuedReviewAndConsumesMismatch() async throws {
    let temporary = try AgentTemporaryDatabase()
    defer { temporary.remove() }
    let store = try await makeAgentStore(at: temporary.database)
    let handler = LocalGrantDecisionHandlerV0(
        persistence: SQLiteLocalGrantDecisionPersistenceV0(store: store),
        registry: try agentRegistry()
    )
    try await handler.register(agentReview())
    let forgedName = try DeviceDisplayName("Forged device")
    await #expect(throws: LocalGrantDecisionHandlerErrorV0.commandMismatch) {
        _ = try await handler.handle(agentCommand(displayName: forgedName))
    }
    await #expect(
        throws: LocalGrantDecisionHandlerErrorV0.reviewUnavailable(agentReviewID)
    ) {
        _ = try await handler.handle(agentCommand())
    }
    #expect(try await store.deviceGrants(agentDeviceID).isEmpty)
}

@Test func durableStateChangeAfterReviewFailsClosedWithoutGrantWrite() async throws {
    let temporary = try AgentTemporaryDatabase()
    defer { temporary.remove() }
    let store = try await makeAgentStore(at: temporary.database)
    let handler = LocalGrantDecisionHandlerV0(
        persistence: SQLiteLocalGrantDecisionPersistenceV0(store: store),
        registry: try agentRegistry()
    )
    try await handler.register(agentReview())
    try await store.setDeviceDisplayName(
        agentDeviceID,
        displayName: try DeviceDisplayName("Renamed iPhone"),
        occurredAtUnixMilliseconds: 1_500
    )
    await #expect(
        throws: SecurityStoreError.grantExpansionStale(agentDeviceID)
    ) {
        _ = try await handler.handle(agentCommand())
    }
    #expect(try await store.deviceGrants(agentDeviceID).isEmpty)
    #expect(try await store.device(agentDeviceID)?
        .authorization.authorizationEpoch.rawValue == 1)
}

@Test func approvedExpansionFaultRollsBackGrantFencesAndEvent() async throws {
    let temporary = try AgentTemporaryDatabase()
    defer { temporary.remove() }
    _ = try await makeAgentStore(at: temporary.database)
    let faulting = try SQLiteSecurityStore(
        path: temporary.database.path,
        injectedFaults: [.beforeSecurityEvent]
    )
    let handler = LocalGrantDecisionHandlerV0(
        persistence: SQLiteLocalGrantDecisionPersistenceV0(store: faulting),
        registry: try agentRegistry()
    )
    try await handler.register(agentReview())
    await #expect(
        throws: SecurityStoreError.injectedFault(.beforeSecurityEvent)
    ) {
        _ = try await handler.handle(agentCommand())
    }
    let snapshot = try await faulting.deviceGrantSnapshot(agentDeviceID)
    #expect(snapshot.grants.isEmpty)
    #expect(snapshot.device.authorization.authorizationEpoch.rawValue == 1)
    #expect(snapshot.device.authorization.grantRevision.rawValue == 1)
    #expect(try await faulting.securityEventCount() == 2)
}

@Test func registryReplacementInvalidatesEveryPendingVisibleReview() async throws {
    let temporary = try AgentTemporaryDatabase()
    defer { temporary.remove() }
    let store = try await makeAgentStore(at: temporary.database)
    let handler = LocalGrantDecisionHandlerV0(
        persistence: SQLiteLocalGrantDecisionPersistenceV0(store: store),
        registry: try agentRegistry()
    )
    let review = try agentReview()
    try await handler.register(review)
    let replacementGeneration = UUID()
    try await handler.replaceRegistry(
        agentRegistry(generation: replacementGeneration)
    )
    await #expect(
        throws: LocalGrantDecisionHandlerErrorV0.reviewUnavailable(agentReviewID)
    ) {
        _ = try await handler.handle(agentCommand())
    }
    await #expect(throws: LocalGrantDecisionHandlerErrorV0.registryMismatch) {
        try await handler.register(review)
    }
    #expect(try await store.deviceGrants(agentDeviceID).isEmpty)
}

@Test func sharedCapabilityReplacementInvalidatesGrantReviewAndAuditsSwap() async throws {
    let temporary = try AgentTemporaryDatabase()
    defer { temporary.remove() }
    let store = try await makeAgentStore(at: temporary.database)
    let auditStore = try SQLiteBoundedAuditStoreV0(
        path: temporary.directory.appendingPathComponent("audit.sqlite3").path
    )
    let authority = AgentCapabilityAuthorityV1(
        initial: try agentPublication(),
        grantPersistence: SQLiteLocalGrantDecisionPersistenceV0(store: store),
        registryAuditWriter:
            BoundedCapabilityRegistryPublicationAuditWriterV1(store: auditStore),
        wallClock: FixedAgentCapabilityClockV1(value: 3_000)
    )
    try await authority.registerGrantReview(agentReview())
    let replacementGeneration = UUID()

    _ = try await authority.replace(
        with: agentPublication(generation: replacementGeneration)
    )

    await #expect(
        throws: LocalGrantDecisionHandlerErrorV0.reviewUnavailable(agentReviewID)
    ) {
        _ = try await authority.handleGrantDecision(agentCommand())
    }
    #expect(await authority.registrySnapshot().generation
        == replacementGeneration)
    let page = try await auditStore.page(
        scope: .localAdministration,
        limit: 10
    )
    #expect(page.events.map(\.draft.eventID) == [replacementGeneration])
}

@Test func exactProviderFailureRemovesOnlyThatProviderAndIsIdempotent() async throws {
    let temporary = try AgentTemporaryDatabase()
    defer { temporary.remove() }
    let store = try await makeAgentStore(at: temporary.database)
    let auditStore = try SQLiteBoundedAuditStoreV0(
        path: temporary.directory.appendingPathComponent("audit.sqlite3").path
    )
    let initial = try agentPublication()
    let identity = try #require(initial.providerIdentities.first)
    let authority = AgentCapabilityAuthorityV1(
        initial: initial,
        grantPersistence: SQLiteLocalGrantDecisionPersistenceV0(store: store),
        registryAuditWriter:
            BoundedCapabilityRegistryPublicationAuditWriterV1(store: auditStore),
        wallClock: FixedAgentCapabilityClockV1(value: 3_000)
    )
    try await authority.registerGrantReview(agentReview())

    let mismatched = CapabilityProviderIdentityV1(
        providerID: identity.providerID,
        providerVersion: identity.providerVersion,
        providerGeneration: UUID(),
        executionRevision: identity.executionRevision
    )
    await #expect(
        throws: CapabilityRegistryPublicationErrorV1.providerIdentityMismatch(
            identity.providerID
        )
    ) {
        _ = try await authority.markProviderUnavailable(
            mismatched,
            replacementGeneration: UUID()
        )
    }
    #expect(await authority.registrySnapshot() == initial.registry)

    let replacementGeneration = UUID()
    #expect(try await authority.markProviderUnavailable(
        identity,
        replacementGeneration: replacementGeneration
    ) == .replaced(
        previousGeneration: initial.registry.generation,
        currentGeneration: replacementGeneration
    ))
    let current = await authority.publicationSnapshot()
    #expect(current.registry.generation == replacementGeneration)
    #expect(current.registry.capabilities.isEmpty)
    #expect(current.providerIdentities.isEmpty)
    await #expect(
        throws: LocalGrantDecisionHandlerErrorV0.reviewUnavailable(agentReviewID)
    ) {
        _ = try await authority.handleGrantDecision(agentCommand())
    }
    #expect(try await authority.markProviderUnavailable(
        identity,
        replacementGeneration: replacementGeneration
    ) == .idempotentReplay(generation: replacementGeneration))
    await #expect(
        throws: CapabilityRegistryPublicationErrorV1.providerNotPublished(
            identity.providerID
        )
    ) {
        _ = try await authority.markProviderUnavailable(
            identity,
            replacementGeneration: UUID()
        )
    }
    let page = try await auditStore.page(
        scope: .localAdministration,
        limit: 10
    )
    #expect(page.events.map(\.draft.eventID) == [replacementGeneration])
}

@Test func sharedCapabilityAuditFailureCannotRollbackSwapOrReviewInvalidation() async throws {
    let temporary = try AgentTemporaryDatabase()
    defer { temporary.remove() }
    let store = try await makeAgentStore(at: temporary.database)
    let auditStore = try SQLiteBoundedAuditStoreV0(
        path: temporary.directory.appendingPathComponent("audit.sqlite3").path,
        injectedFaults: [.beforeInsert]
    )
    let writer = BoundedCapabilityRegistryPublicationAuditWriterV1(
        store: auditStore
    )
    let authority = AgentCapabilityAuthorityV1(
        initial: try agentPublication(),
        grantPersistence: SQLiteLocalGrantDecisionPersistenceV0(store: store),
        registryAuditWriter: writer,
        wallClock: FixedAgentCapabilityClockV1(value: 3_000)
    )
    try await authority.registerGrantReview(agentReview())
    let replacementGeneration = UUID()

    _ = try await authority.replace(
        with: agentPublication(generation: replacementGeneration)
    )

    #expect(await authority.registrySnapshot().generation
        == replacementGeneration)
    await #expect(
        throws: LocalGrantDecisionHandlerErrorV0.reviewUnavailable(agentReviewID)
    ) {
        _ = try await authority.handleGrantDecision(agentCommand())
    }
    #expect(await writer.health() == .degraded)
    #expect(try await auditStore.page(
        scope: .localAdministration,
        limit: 10
    ).events.isEmpty)
}

@Test func sharedCapabilityAuditDropCannotRollbackSwapOrReviewInvalidation() async throws {
    let temporary = try AgentTemporaryDatabase()
    defer { temporary.remove() }
    let store = try await makeAgentStore(at: temporary.database)
    let auditStore = try SQLiteBoundedAuditStoreV0(
        path: temporary.directory.appendingPathComponent("audit.sqlite3").path,
        configuration: AuditStoreConfigurationV0(
            logicalByteLimit: 4 * AuditEventDraftV0.maximumLogicalSize,
            retainedRowLimit: 10,
            retentionMilliseconds: 60_000,
            rateLimitAttempts: 1,
            rateLimitWindowMilliseconds: 60_000
        )
    )
    _ = try await auditStore.append(try AuditEventDraftV0(
        eventID: UUID(),
        observedAtUnixMilliseconds: 2_999,
        actor: .agent,
        visibility: .localOnly,
        code: .capabilityRegistryChanged,
        outcome: .succeeded,
        importance: .bestEffort
    ))
    let writer = BoundedCapabilityRegistryPublicationAuditWriterV1(
        store: auditStore
    )
    let authority = AgentCapabilityAuthorityV1(
        initial: try agentPublication(),
        grantPersistence: SQLiteLocalGrantDecisionPersistenceV0(store: store),
        registryAuditWriter: writer,
        wallClock: FixedAgentCapabilityClockV1(value: 3_000)
    )
    try await authority.registerGrantReview(agentReview())
    let replacementGeneration = UUID()

    _ = try await authority.replace(
        with: agentPublication(generation: replacementGeneration)
    )

    #expect(await authority.registrySnapshot().generation
        == replacementGeneration)
    await #expect(
        throws: LocalGrantDecisionHandlerErrorV0.reviewUnavailable(agentReviewID)
    ) {
        _ = try await authority.handleGrantDecision(agentCommand())
    }
    #expect(await writer.health() == .degraded)
    let page = try await auditStore.page(
        scope: .localAdministration,
        limit: 10
    )
    #expect(page.events.count == 1)
    #expect(page.gaps.droppedEventCount == 1)
}

@Test func changedEffectFactsCannotReuseAReviewEvenWithSameGeneration() async throws {
    let temporary = try AgentTemporaryDatabase()
    defer { temporary.remove() }
    let store = try await makeAgentStore(at: temporary.database)
    let handler = LocalGrantDecisionHandlerV0(
        persistence: SQLiteLocalGrantDecisionPersistenceV0(store: store),
        registry: try agentRegistry(destructive: true)
    )
    await #expect(throws: LocalGrantDecisionHandlerErrorV0.registryMismatch) {
        try await handler.register(agentReview(destructive: false))
    }
    #expect(try await store.deviceGrants(agentDeviceID).isEmpty)
}

@Test func registryReplacementCannotInterleaveWithDurableGrantCommit() async throws {
    let persistence = SuspendingGrantPersistence()
    let temporary = try AgentTemporaryDatabase()
    defer { temporary.remove() }
    let auditStore = try SQLiteBoundedAuditStoreV0(
        path: temporary.directory.appendingPathComponent("audit.sqlite3").path
    )
    let authority = AgentCapabilityAuthorityV1(
        initial: try agentPublication(),
        grantPersistence: persistence,
        registryAuditWriter:
            BoundedCapabilityRegistryPublicationAuditWriterV1(store: auditStore),
        wallClock: FixedAgentCapabilityClockV1(value: 3_000)
    )
    try await authority.registerGrantReview(agentReview())
    let command = try agentCommand()
    let deciding = Task { try await authority.handleGrantDecision(command) }
    await persistence.waitUntilStarted()
    await #expect(
        throws: AgentCapabilityAuthorityErrorV1.grantMutationInProgress
    ) {
        _ = try await authority.replace(
            with: agentPublication(generation: UUID())
        )
    }
    await persistence.resume()
    let receipt = try await deciding.value
    #expect(receipt.decision == .approve)
    _ = try await authority.replace(with: agentPublication(generation: UUID()))
    #expect(try await authority.handleGrantDecision(command) == receipt)
}
