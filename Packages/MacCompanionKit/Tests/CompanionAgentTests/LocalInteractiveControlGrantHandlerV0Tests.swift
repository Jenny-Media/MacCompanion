import CompanionAgent
import CompanionDomain
import CompanionIPC
import CompanionPersistence
import CryptoKit
import Foundation
import Testing

private actor InteractiveGrantPrimaryFence:
    AgentDeviceRevocationPrimaryFencingV0
{
    private var events: [String] = []

    func fenceForSecurityAdministration() async { events.append("fence") }
    func releaseSecurityAdministrationFence() async {
        events.append("release")
    }
    func snapshot() -> [String] { events }
}

private actor InteractiveGrantInventoryRefreshCounter {
    private var count = 0
    func refresh() { count += 1 }
    func snapshot() -> Int { count }
}

private struct InteractiveGrantTemporaryDatabase {
    let directory: URL
    let database: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "maccompanion-interactive-grant-\(UUID().uuidString)",
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

private let interactiveGrantDeviceID = UUID(
    uuidString: "018f9900-0000-7000-8000-000000000021"
)!

private func addInteractiveGrantDevice(
    to store: SQLiteSecurityStore,
    deviceID: UUID,
    clientID: UUID,
    displayName: String,
    createdAtUnixMilliseconds: Int64
) async throws {
    let record = try StoredDeviceRecord(
        deviceID: deviceID,
        clientID: clientID,
        sessionPublicKeyX963:
            P256.Signing.PrivateKey().publicKey.x963Representation,
        approvalPublicKeyX963:
            P256.Signing.PrivateKey().publicKey.x963Representation,
        authorization: DeviceAuthorization(
            state: .activeMonitorOnly,
            authorizationEpoch: .init(rawValue: 1),
            grantRevision: .init(rawValue: 1)
        ),
        policyRevision: .init(rawValue: 1),
        createdAtUnixMilliseconds: createdAtUnixMilliseconds,
        updatedAtUnixMilliseconds: createdAtUnixMilliseconds
    )
    try await store.commitPairing(
        pairingID: UUID(),
        record: record
    )
    try await store.setDeviceDisplayName(
        deviceID,
        displayName: DeviceDisplayName(displayName),
        occurredAtUnixMilliseconds: createdAtUnixMilliseconds
    )
}

private func makeInteractiveGrantStore(
    at database: URL
) async throws -> SQLiteSecurityStore {
    let store = try SQLiteSecurityStore(path: database.path)
    try await addInteractiveGrantDevice(
        to: store,
        deviceID: interactiveGrantDeviceID,
        clientID: UUID(
            uuidString: "018f9900-0000-7000-8000-000000000022"
        )!,
        displayName: "iPhone",
        createdAtUnixMilliseconds: 1_000
    )
    return store
}

@Test func interactiveControlReviewsNewestEligibleDeviceThenAdvancesToOlderDevice()
    async throws
{
    let temporary = try InteractiveGrantTemporaryDatabase()
    defer { temporary.remove() }
    let store = try await makeInteractiveGrantStore(at: temporary.database)
    let iPadID = UUID(
        uuidString: "018f9900-0000-7000-8000-000000000024"
    )!
    try await addInteractiveGrantDevice(
        to: store,
        deviceID: iPadID,
        clientID: UUID(
            uuidString: "018f9900-0000-7000-8000-000000000025"
        )!,
        displayName: "iPad Pro",
        createdAtUnixMilliseconds: 1_500
    )
    let handler = try LocalInteractiveControlGrantHandlerV0(
        store: store,
        primary: InteractiveGrantPrimaryFence(),
        wallNowUnixMilliseconds: { 2_000 }
    )

    let newest = try await handler.makeReview(
        LocalInteractiveControlGrantReviewRequestV0(
            commandID: UUID(),
            requestedAtUnixMilliseconds: 2_000
        )
    )
    #expect(newest.deviceID == iPadID)
    #expect(newest.deviceDisplayName.rawValue == "iPad Pro")
    _ = try await handler.decide(
        newest.makeDecisionCommand(
            commandID: UUID(),
            decision: .approve,
            decidedAtUnixMilliseconds: 2_000
        )
    )
    #expect(try await !store.interactiveControlGranted())

    let older = try await handler.makeReview(
        LocalInteractiveControlGrantReviewRequestV0(
            commandID: UUID(),
            requestedAtUnixMilliseconds: 2_000
        )
    )
    #expect(older.deviceID == interactiveGrantDeviceID)
    #expect(older.deviceDisplayName.rawValue == "iPhone")
    _ = try await handler.decide(
        older.makeDecisionCommand(
            commandID: UUID(),
            decision: .approve,
            decidedAtUnixMilliseconds: 2_000
        )
    )
    #expect(try await store.interactiveControlGranted())
}

@Test func interactiveControlGrantRequiresReviewThenFencesAndPersists()
    async throws
{
    let temporary = try InteractiveGrantTemporaryDatabase()
    defer { temporary.remove() }
    let store = try await makeInteractiveGrantStore(at: temporary.database)
    let primary = InteractiveGrantPrimaryFence()
    let refreshes = InteractiveGrantInventoryRefreshCounter()
    let handler = try LocalInteractiveControlGrantHandlerV0(
        store: store,
        primary: primary,
        refreshInventory: { await refreshes.refresh() },
        wallNowUnixMilliseconds: { 2_000 }
    )
    let request = try LocalInteractiveControlGrantReviewRequestV0(
        commandID: UUID(),
        requestedAtUnixMilliseconds: 2_000
    )
    let review = try await handler.makeReview(request)
    #expect(review.deviceID == interactiveGrantDeviceID)
    #expect(review.deviceDisplayName.rawValue == "iPhone")
    #expect(try await store.deviceGrants(interactiveGrantDeviceID).isEmpty)

    let command = try review.makeDecisionCommand(
        commandID: UUID(),
        decision: .approve,
        decidedAtUnixMilliseconds: 2_000
    )
    let receipt = try await handler.decide(command)

    #expect(await primary.snapshot() == ["fence", "release"])
    #expect(await refreshes.snapshot() == 1)
    #expect(receipt.authorizationEpoch.rawValue == 2)
    #expect(receipt.grantRevision.rawValue == 2)
    #expect(try await store.deviceGrants(interactiveGrantDeviceID)
        .capabilityIDs == [InteractiveControlDurableGrantV0.identifier])
    #expect(try await store.device(interactiveGrantDeviceID)?
        .authorization.state == .activeGranted)
    #expect(try await store.interactiveControlGranted())
}

@Test func requestingReviewNeverAddsControlGrant() async throws {
    let temporary = try InteractiveGrantTemporaryDatabase()
    defer { temporary.remove() }
    let store = try await makeInteractiveGrantStore(at: temporary.database)
    let primary = InteractiveGrantPrimaryFence()
    let handler = try LocalInteractiveControlGrantHandlerV0(
        store: store,
        primary: primary,
        wallNowUnixMilliseconds: { 2_000 }
    )
    _ = try await handler.makeReview(
        LocalInteractiveControlGrantReviewRequestV0(
            commandID: UUID(),
            requestedAtUnixMilliseconds: 2_000
        )
    )
    #expect(try await store.deviceGrants(interactiveGrantDeviceID).isEmpty)
    #expect(await primary.snapshot().isEmpty)
}

@Test func failedDecisionRequiresAndAcceptsAFreshReview() async throws {
    let temporary = try InteractiveGrantTemporaryDatabase()
    defer { temporary.remove() }
    let store = try await makeInteractiveGrantStore(at: temporary.database)
    let primary = InteractiveGrantPrimaryFence()
    let handler = try LocalInteractiveControlGrantHandlerV0(
        store: store,
        primary: primary,
        wallNowUnixMilliseconds: { 2_000 }
    )
    let firstReview = try await handler.makeReview(
        LocalInteractiveControlGrantReviewRequestV0(
            commandID: UUID(),
            requestedAtUnixMilliseconds: 2_000
        )
    )
    try await store.setDeviceDisplayName(
        interactiveGrantDeviceID,
        displayName: DeviceDisplayName("Renamed iPhone"),
        occurredAtUnixMilliseconds: 2_000
    )
    let staleCommand = try firstReview.makeDecisionCommand(
        commandID: UUID(),
        decision: .approve,
        decidedAtUnixMilliseconds: 2_000
    )

    await #expect(
        throws: SecurityStoreError.grantExpansionStale(
            interactiveGrantDeviceID
        )
    ) {
        try await handler.decide(staleCommand)
    }
    #expect(await primary.snapshot() == ["fence", "release"])
    #expect(try await store.deviceGrants(interactiveGrantDeviceID).isEmpty)

    let freshReview = try await handler.makeReview(
        LocalInteractiveControlGrantReviewRequestV0(
            commandID: UUID(),
            requestedAtUnixMilliseconds: 2_000
        )
    )
    #expect(freshReview.reviewID != firstReview.reviewID)
    #expect(freshReview.deviceDisplayName.rawValue == "Renamed iPhone")
    let receipt = try await handler.decide(
        freshReview.makeDecisionCommand(
            commandID: UUID(),
            decision: .approve,
            decidedAtUnixMilliseconds: 2_000
        )
    )

    #expect(receipt.grantRevision.rawValue == 2)
    #expect(try await store.deviceGrants(interactiveGrantDeviceID)
        .capabilityIDs == [InteractiveControlDurableGrantV0.identifier])
}
