import CompanionAgent
import CompanionDomain
import CompanionIPC
import CompanionNativeProviders
import CompanionOperations
import CompanionPersistence
import CompanionWire
import CryptoKit
import Foundation
import Testing

private actor ActGrantFence: AgentDeviceRevocationPrimaryFencingV0 {
    var events: [String] = []
    func fenceForSecurityAdministration() { events.append("fence") }
    func releaseSecurityAdministrationFence() { events.append("release") }
    func refresh() { events.append("refresh") }
}

private struct ActGrantNoAudio: DefaultOutputMuteControllingV1 {
    func setDefaultOutputMuted(_ desired: Bool) throws -> Bool { desired }
}

private final class ActGrantClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int64 = 2_000
    func read() -> Int64 { lock.withLock { value } }
    func advance(_ delta: Int64) { lock.withLock { value += delta } }
}

private struct ActGrantFixture {
    let root: URL
    let deviceID: UUID
    let store: SQLiteSecurityStore
    let authority: AgentCapabilityAuthorityV1
    let handler: LocalCapabilityGrantHandlerV1
    let fence: ActGrantFence
    let clock: ActGrantClock

    static func make() async throws -> Self {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("act-grant-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        do {
            let store = try SQLiteSecurityStore(path: root.appendingPathComponent("security.sqlite3").path)
            let deviceID = UUID()
            let record = try StoredDeviceRecord(deviceID: deviceID, clientID: UUID(),
                sessionPublicKeyX963: P256.Signing.PrivateKey().publicKey.x963Representation,
                approvalPublicKeyX963: P256.Signing.PrivateKey().publicKey.x963Representation,
                authorization: DeviceAuthorization(state: .activeMonitorOnly,
                    authorizationEpoch: .init(rawValue: 1), grantRevision: .init(rawValue: 1)),
                policyRevision: .init(rawValue: 1), createdAtUnixMilliseconds: 1_000, updatedAtUnixMilliseconds: 1_000)
            try await store.commitPairing(pairingID: UUID(), record: record)
            try await store.setDeviceDisplayName(deviceID, displayName: DeviceDisplayName("Test phone"), occurredAtUnixMilliseconds: 1_100)
            let audit = try SQLiteBoundedAuditStoreV0(path: root.appendingPathComponent("audit.sqlite3").path)
            let authority = AgentCapabilityAuthorityV1(initial: try publication(),
                grantPersistence: SQLiteLocalGrantDecisionPersistenceV0(store: store),
                registryAuditWriter: BoundedCapabilityRegistryPublicationAuditWriterV1(store: audit))
            let fence = ActGrantFence()
            let clock = ActGrantClock()
            let handler = LocalCapabilityGrantHandlerV1(store: store, capabilities: authority, primary: fence,
                refreshInventory: { await fence.refresh() }, wallNowUnixMilliseconds: { clock.read() })
            return Self(root: root, deviceID: deviceID, store: store, authority: authority, handler: handler, fence: fence, clock: clock)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }
    static func publication() throws -> CapabilityRegistryPublicationV1 {
        try CapabilityRegistryPublicationV1(registry: CapabilityRegistrySnapshotV1(generation: UUID(),
            capabilities: [NativeAudioMuteCapabilityV1.descriptor()]),
            providers: [NativeAudioMuteProviderV1(controller: ActGrantNoAudio())])
    }
    func request(commandID: UUID = UUID(), capabilityID: String = NativeAudioMuteCapabilityV1.capabilityID) throws -> LocalCapabilityGrantReviewRequestV1 {
        try .init(commandID: commandID, deviceID: deviceID, capabilityID: capabilityID, requestedAtUnixMilliseconds: clock.read())
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

@Test func publishedActGrantDeclineReplayThenApprovePreservesIndependentControl() async throws {
    let f = try await ActGrantFixture.make()
    defer { f.remove() }
    let control = try LocalInteractiveControlGrantHandlerV0(store: f.store, primary: f.fence, wallNowUnixMilliseconds: { 2_000 })
    let controlReview = try await control.makeReview(.init(commandID: UUID(), requestedAtUnixMilliseconds: 2_000))
    _ = try await control.decide(controlReview.makeDecisionCommand(commandID: UUID(), decision: .approve, decidedAtUnixMilliseconds: 2_000))
    let request = try f.request()
    let review = try await f.handler.makeReview(request)
    #expect(try await f.handler.makeReview(request) == review)
    #expect(review.currentGrantIDs == [InteractiveControlDurableGrantV0.identifier])
    #expect(try review.descriptor.domainValue() == NativeAudioMuteCapabilityV1.descriptor())
    let decline = try review.command(commandID: UUID(), decision: .decline, decidedAtUnixMilliseconds: 2_000)
    let receipt = try await f.handler.decide(decline)
    #expect(try await f.handler.decide(decline) == receipt)
    #expect(await f.fence.events == ["fence", "release"])
    #expect(try await f.store.deviceGrants(f.deviceID).capabilityIDs == review.currentGrantIDs)
    let changed = try review.command(commandID: decline.commandID, decision: .approve, decidedAtUnixMilliseconds: 2_000)
    await #expect(throws: LocalCapabilityGrantHandlerErrorV1.requestMismatch) { try await f.handler.decide(changed) }
    let fresh = try await f.handler.makeReview(f.request())
    let approval = try fresh.command(commandID: UUID(), decision: .approve, decidedAtUnixMilliseconds: 2_000)
    let approved = try await f.handler.decide(approval)
    #expect(try await f.handler.decide(approval) == approved)
    #expect(approved.authorizationEpoch.rawValue == 3)
    #expect(approved.grantRevision.rawValue == 3)
    #expect(try await f.store.deviceGrants(f.deviceID).capabilityIDs == [InteractiveControlDurableGrantV0.identifier, NativeAudioMuteCapabilityV1.capabilityID])
    #expect(await f.fence.events == ["fence", "release", "fence", "refresh", "release"])
    await #expect(throws: LocalCapabilityGrantHandlerErrorV1.alreadyGranted) { try await f.handler.makeReview(f.request()) }
}

@Test func publishedActGrantRejectsUnavailableAndChangedRequest() async throws {
    let f = try await ActGrantFixture.make()
    defer { f.remove() }
    await #expect(throws: LocalCapabilityGrantHandlerErrorV1.capabilityUnavailable) {
        try await f.handler.makeReview(f.request(capabilityID: "missing.capability"))
    }
    let request = try f.request()
    _ = try await f.handler.makeReview(request)
    await #expect(throws: LocalCapabilityGrantHandlerErrorV1.requestMismatch) {
        try await f.handler.makeReview(f.request(commandID: request.commandID, capabilityID: "other.capability"))
    }
    #expect(try await f.store.deviceGrants(f.deviceID).isEmpty)
    #expect(await f.fence.events.isEmpty)
}

@Test(arguments: ["registry", "name", "expiry", "generation"])
func publishedActGrantStaleAuthorityCannotCommit(change: String) async throws {
    let f = try await ActGrantFixture.make()
    defer { f.remove() }
    let request = try f.request()
    let review = try await f.handler.makeReview(request)
    let command = try review.command(commandID: UUID(), decision: .approve, decidedAtUnixMilliseconds: 2_000)
    switch change {
    case "registry": _ = try await f.authority.replace(with: ActGrantFixture.publication())
    case "name": try await f.store.setDeviceDisplayName(f.deviceID, displayName: DeviceDisplayName("Changed phone"), occurredAtUnixMilliseconds: 2_000)
    case "expiry": f.clock.advance(300_000)
    default: await f.handler.invalidateReview()
    }
    await #expect(throws: (any Error).self) { try await f.handler.makeReview(request) }
    await #expect(throws: (any Error).self) { try await f.handler.decide(command) }
    #expect(try await f.store.deviceGrants(f.deviceID).isEmpty)
    #expect(try await f.store.device(f.deviceID)?.authorization.authorizationEpoch.rawValue == 1)
}
