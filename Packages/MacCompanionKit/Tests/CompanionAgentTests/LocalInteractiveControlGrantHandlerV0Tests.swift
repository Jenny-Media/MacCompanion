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

private func makeInteractiveGrantStore(
    at database: URL
) async throws -> SQLiteSecurityStore {
    let store = try SQLiteSecurityStore(path: database.path)
    let record = try StoredDeviceRecord(
        deviceID: interactiveGrantDeviceID,
        clientID: UUID(
            uuidString: "018f9900-0000-7000-8000-000000000022"
        )!,
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
        createdAtUnixMilliseconds: 1_000,
        updatedAtUnixMilliseconds: 1_000
    )
    try await store.commitPairing(
        pairingID: UUID(
            uuidString: "018f9900-0000-7000-8000-000000000023"
        )!,
        record: record
    )
    try await store.setDeviceDisplayName(
        interactiveGrantDeviceID,
        displayName: DeviceDisplayName("iPhone"),
        occurredAtUnixMilliseconds: 1_100
    )
    return store
}

@Test func interactiveControlGrantRequiresReviewThenFencesAndPersists()
    async throws
{
    let temporary = try InteractiveGrantTemporaryDatabase()
    defer { temporary.remove() }
    let store = try await makeInteractiveGrantStore(at: temporary.database)
    let primary = InteractiveGrantPrimaryFence()
    let handler = try LocalInteractiveControlGrantHandlerV0(
        store: store,
        primary: primary,
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
    #expect(receipt.authorizationEpoch.rawValue == 2)
    #expect(receipt.grantRevision.rawValue == 2)
    #expect(try await store.deviceGrants(interactiveGrantDeviceID)
        .capabilityIDs == [InteractiveControlDurableGrantV0.identifier])
    #expect(try await store.device(interactiveGrantDeviceID)?
        .authorization.state == .activeGranted)
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
