@testable import CompanionClient
import CompanionDiscovery
import CompanionDomain
import CryptoKit
import Foundation
import Testing

private func storageIdentity(
    pairingID: UUID,
    clientID: UUID,
    scalar: UInt8
) throws -> ClientPreparedIdentityV0 {
    func key(_ value: UInt8) throws -> P256.Signing.PrivateKey {
        var bytes = Data(repeating: 0, count: 32)
        bytes[31] = value
        return try P256.Signing.PrivateKey(rawRepresentation: bytes)
    }
    let session = try key(scalar)
    let approval = try key(scalar + 1)
    return try ClientPreparedIdentityV0(
        pairingID: pairingID,
        clientID: clientID,
        sessionKey: ClientCustodiedPublicKeyV0(
            role: .session,
            reference: ClientSigningKeyReferenceV0(UUID()),
            publicKeyX963: session.publicKey.x963Representation,
            protection: .afterFirstUnlockThisDeviceOnly
        ),
        approvalKey: ClientCustodiedPublicKeyV0(
            role: .approval,
            reference: ClientSigningKeyReferenceV0(UUID()),
            publicKeyX963: approval.publicKey.x963Representation,
            protection: .whenUnlockedThisDeviceOnlyUserPresence
        )
    )
}

private func storageRecord(
    identity: ClientPreparedIdentityV0,
    hostID: UUID = UUID()
) throws -> ClientDurablePairedHostV0 {
    try ClientDurablePairedHostV0(
        host: ClientPairedHostV0(
            pairingID: identity.pairingID,
            clientID: identity.clientID,
            hostID: hostID,
            deviceID: UUID(),
            hostFingerprint: Data(repeating: 0x77, count: 32),
            endpoints: [
                try EndpointCandidate(
                    kind: .dns,
                    value: "studio.example.test",
                    port: 47_474
                ),
            ],
            deviceState: .activeMonitorOnly,
            authorizationEpoch: .init(rawValue: 1),
            grantRevision: .init(rawValue: 1),
            policyRevision: .init(rawValue: 2)
        ),
        identity: identity
    )
}

private actor StorageRecoveryCustody: ClientIdentityRecoveryCustodyV0 {
    var pending: [ClientPreparedIdentityV0]
    var valid = true
    var adopted: [ClientPreparedIdentityV0] = []
    var discarded: [ClientPreparedIdentityV0] = []

    init(_ pending: [ClientPreparedIdentityV0]) {
        self.pending = pending
    }

    func prepareIdentity(
        pairingID: UUID,
        clientID: UUID
    ) async throws -> ClientPreparedIdentityV0 {
        throw ClientIdentityPublicationErrorV0.invalidPhase
    }

    func validatePreparedIdentity(
        _ identity: ClientPreparedIdentityV0
    ) async throws -> Bool {
        valid && pending.contains(identity)
    }

    func signSessionInput(
        _ input: Data,
        using reference: ClientSigningKeyReferenceV0
    ) async throws -> Data {
        throw ClientIdentityPublicationErrorV0.invalidPhase
    }

    func signApprovalInput(
        _ input: Data,
        using reference: ClientSigningKeyReferenceV0,
        reason: ClientApprovalPresenceReasonV0
    ) async throws -> Data {
        throw ClientIdentityPublicationErrorV0.invalidPhase
    }

    func discardPreparedIdentity(
        _ identity: ClientPreparedIdentityV0
    ) async throws {
        discarded.append(identity)
        pending.removeAll { $0 == identity }
    }

    func preparedIdentities() async throws -> [ClientPreparedIdentityV0] {
        pending
    }

    func markPreparedIdentityPublished(
        _ identity: ClientPreparedIdentityV0
    ) async throws {
        adopted.append(identity)
        pending.removeAll { $0 == identity }
    }

    func mutationCounts() -> (Int, Int) {
        (adopted.count, discarded.count)
    }

    func setValid(_ value: Bool) {
        valid = value
    }
}

private actor StorageRecoveryPersistence: ClientPairedHostRecoveryPersistenceV0 {
    var records: [UUID: ClientDurablePairedHostV0]

    init(_ records: [ClientDurablePairedHostV0]) {
        self.records = Dictionary(uniqueKeysWithValues: records.map {
            ($0.pairingID, $0)
        })
    }

    func storedRecord(
        pairingID: UUID,
        clientID: UUID
    ) async throws -> ClientDurablePairedHostV0? {
        guard let value = records[pairingID], value.clientID == clientID else {
            return nil
        }
        return value
    }
}

private struct ClientStorageTemporaryDirectory {
    let root: URL
    let store: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "maccompanion-client-store-\(UUID().uuidString)",
            isDirectory: true
        )
        store = root.appendingPathComponent("PairedHosts", isDirectory: true)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

@Test func pairedHostStorageHasCanonicalValidatedRoundTripWithoutPrivateKeys() throws {
    let identity = try storageIdentity(
        pairingID: UUID(),
        clientID: UUID(),
        scalar: 10
    )
    let record = try storageRecord(identity: identity)
    let encoded = try ClientPairedHostStorageCodecV0.encode(record)
    #expect(try ClientPairedHostStorageCodecV0.decode(encoded) == record)
    let text = try #require(String(data: encoded, encoding: .utf8))
    #expect(text.contains("\"schemaVersion\":1"))
    #expect(text.contains("\"sessionKey\""))
    #expect(text.contains("\"approvalKey\""))
    #expect(!text.contains("privateKey"))
}

@Test func pairedHostStorageRejectsUnknownWhitespaceAndNonInitialState() throws {
    let identity = try storageIdentity(
        pairingID: UUID(),
        clientID: UUID(),
        scalar: 12
    )
    let encoded = try ClientPairedHostStorageCodecV0.encode(
        storageRecord(identity: identity)
    )
    let text = try #require(String(data: encoded, encoding: .utf8))

    #expect(throws: ClientPairedHostStorageErrorV0.invalidRecord) {
        _ = try ClientPairedHostStorageCodecV0.decode(
            Data(text.replacingOccurrences(
                of: "{",
                with: "{\"unknown\":1,",
                options: [],
                range: text.startIndex..<text.index(after: text.startIndex)
            ).utf8)
        )
    }
    #expect(throws: ClientPairedHostStorageErrorV0.nonCanonicalEncoding) {
        _ = try ClientPairedHostStorageCodecV0.decode(Data((" " + text).utf8))
    }
    #expect(throws: ClientPairedHostStorageErrorV0.invalidRecord) {
        _ = try ClientPairedHostStorageCodecV0.decode(Data(text
            .replacingOccurrences(of: "activeMonitorOnly", with: "suspended")
            .utf8))
    }
}

@Test func restartReconciliationAdoptsCommittedAndDeletesOnlyOrphan() async throws {
    let clientID = UUID()
    let committed = try storageIdentity(
        pairingID: UUID(),
        clientID: clientID,
        scalar: 14
    )
    let orphan = try storageIdentity(
        pairingID: UUID(),
        clientID: clientID,
        scalar: 16
    )
    let custody = StorageRecoveryCustody([committed, orphan])
    let persistence = StorageRecoveryPersistence([
        try storageRecord(identity: committed),
    ])

    let result = try await ClientIdentityRestartReconcilerV0.reconcile(
        custody: custody,
        persistence: persistence
    )
    #expect(result.adoptedPublishedCount == 1)
    #expect(result.discardedOrphanCount == 1)
    let counts = await custody.mutationCounts()
    #expect(counts.0 == 1)
    #expect(counts.1 == 1)
}

@Test func restartConflictAndMissingKeyPreflightMutateNothing() async throws {
    let clientID = UUID()
    let pending = try storageIdentity(
        pairingID: UUID(),
        clientID: clientID,
        scalar: 18
    )
    let differentKeys = try storageIdentity(
        pairingID: pending.pairingID,
        clientID: clientID,
        scalar: 20
    )
    let conflictCustody = StorageRecoveryCustody([pending])
    let conflictStore = StorageRecoveryPersistence([
        try storageRecord(identity: differentKeys),
    ])
    await #expect(throws: ClientPairedHostStorageErrorV0.recoveryConflict) {
        _ = try await ClientIdentityRestartReconcilerV0.reconcile(
            custody: conflictCustody,
            persistence: conflictStore
        )
    }
    let conflictCounts = await conflictCustody.mutationCounts()
    #expect(conflictCounts.0 == 0)
    #expect(conflictCounts.1 == 0)

    let missingCustody = StorageRecoveryCustody([pending])
    await missingCustody.setValid(false)
    let matchingStore = StorageRecoveryPersistence([
        try storageRecord(identity: pending),
    ])
    await #expect(throws: ClientPairedHostStorageErrorV0.keyUnavailable) {
        _ = try await ClientIdentityRestartReconcilerV0.reconcile(
            custody: missingCustody,
            persistence: matchingStore
        )
    }
    let missingCounts = await missingCustody.mutationCounts()
    #expect(missingCounts.0 == 0)
    #expect(missingCounts.1 == 0)
}

@Test func atomicFileStorePersistsCanonicalRecordAndExactReplayAcrossRestart() async throws {
    let temporary = try ClientStorageTemporaryDirectory()
    defer { temporary.remove() }
    let identity = try storageIdentity(
        pairingID: UUID(),
        clientID: UUID(),
        scalar: 22
    )
    let record = try storageRecord(identity: identity)
    let store = try AtomicFileClientPairedHostStoreV0(
        directory: temporary.store
    )
    #expect(try await store.commitAtomically(record) == .inserted)

    let restarted = try AtomicFileClientPairedHostStoreV0(
        directory: temporary.store
    )
    #expect(try await restarted.storedRecord(
        pairingID: record.pairingID,
        clientID: record.clientID
    ) == record)
    #expect(try await restarted.commitAtomically(record)
        == .alreadyPresentExactRecord)
    let entries = try FileManager.default.contentsOfDirectory(
        at: temporary.store,
        includingPropertiesForKeys: nil
    )
    let file = try #require(entries.first)
    let attributes = try FileManager.default.attributesOfItem(
        atPath: file.path
    )
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    let encoded = try Data(contentsOf: file)
    #expect(try ClientPairedHostStorageCodecV0.decode(encoded) == record)
    #expect(!String(decoding: encoded, as: UTF8.self).contains("privateKey"))
}

@Test func atomicFileStoreSupportsBoundedMultipleHostsAndRealRecoveryLookup() async throws {
    let temporary = try ClientStorageTemporaryDirectory()
    defer { temporary.remove() }
    let clientID = UUID()
    let firstIdentity = try storageIdentity(
        pairingID: UUID(),
        clientID: clientID,
        scalar: 24
    )
    let secondIdentity = try storageIdentity(
        pairingID: UUID(),
        clientID: clientID,
        scalar: 26
    )
    let first = try storageRecord(identity: firstIdentity)
    let second = try storageRecord(identity: secondIdentity)
    let store = try AtomicFileClientPairedHostStoreV0(
        directory: temporary.store,
        maximumRecordCount: 2
    )
    #expect(try await store.commitAtomically(first) == .inserted)
    #expect(try await store.commitAtomically(second) == .inserted)
    #expect(try await store.allRecords().count == 2)
    #expect(try await store.pairedHost(hostID: first.hostID) == first)
    #expect(try await store.pairedHost(hostID: UUID()) == nil)

    let custody = StorageRecoveryCustody([firstIdentity, secondIdentity])
    let result = try await ClientIdentityRestartReconcilerV0.reconcile(
        custody: custody,
        persistence: store
    )
    #expect(result.adoptedPublishedCount == 2)
    #expect(result.discardedOrphanCount == 0)

    let thirdIdentity = try storageIdentity(
        pairingID: UUID(),
        clientID: clientID,
        scalar: 28
    )
    await #expect(throws: ClientPairedHostFileStoreErrorV0.quotaExceeded) {
        _ = try await store.commitAtomically(
            storageRecord(identity: thirdIdentity)
        )
    }
}

@Test func atomicFileStoreRejectsPairingHostAndKeyReferenceConflicts() async throws {
    let temporary = try ClientStorageTemporaryDirectory()
    defer { temporary.remove() }
    let firstIdentity = try storageIdentity(
        pairingID: UUID(),
        clientID: UUID(),
        scalar: 30
    )
    let hostID = UUID()
    let first = try storageRecord(identity: firstIdentity, hostID: hostID)
    let store = try AtomicFileClientPairedHostStoreV0(
        directory: temporary.store
    )
    _ = try await store.commitAtomically(first)

    let differentIdentity = try storageIdentity(
        pairingID: firstIdentity.pairingID,
        clientID: firstIdentity.clientID,
        scalar: 32
    )
    await #expect(
        throws: ClientIdentityPublicationErrorV0.persistenceConflict
    ) {
        _ = try await store.commitAtomically(
            storageRecord(identity: differentIdentity)
        )
    }

    let anotherIdentity = try storageIdentity(
        pairingID: UUID(),
        clientID: UUID(),
        scalar: 34
    )
    await #expect(
        throws: ClientIdentityPublicationErrorV0.persistenceConflict
    ) {
        _ = try await store.commitAtomically(
            storageRecord(identity: anotherIdentity, hostID: hostID)
        )
    }
    #expect(try await store.allRecords() == [first])
}

@Test func preRenameFaultsPublishNothingWhilePostRenameRetryConverges() async throws {
    for point in [
        ClientPairedHostFileFaultPointV0.afterTemporaryWrite,
        .afterTemporarySync,
        .beforeRename,
    ] {
        let temporary = try ClientStorageTemporaryDirectory()
        defer { temporary.remove() }
        let identity = try storageIdentity(
            pairingID: UUID(),
            clientID: UUID(),
            scalar: 36
        )
        let record = try storageRecord(identity: identity)
        let faulting = try AtomicFileClientPairedHostStoreV0(
            directory: temporary.store,
            injectedFaults: [point]
        )
        await #expect(
            throws: ClientPairedHostFileStoreErrorV0.injectedFault(point)
        ) {
            _ = try await faulting.commitAtomically(record)
        }
        let restarted = try AtomicFileClientPairedHostStoreV0(
            directory: temporary.store
        )
        #expect(try await restarted.allRecords().isEmpty)
    }

    let temporary = try ClientStorageTemporaryDirectory()
    defer { temporary.remove() }
    let identity = try storageIdentity(
        pairingID: UUID(),
        clientID: UUID(),
        scalar: 38
    )
    let record = try storageRecord(identity: identity)
    let point = ClientPairedHostFileFaultPointV0
        .afterRenameBeforeDirectorySync
    let faulting = try AtomicFileClientPairedHostStoreV0(
        directory: temporary.store,
        injectedFaults: [point]
    )
    await #expect(
        throws: ClientPairedHostFileStoreErrorV0.injectedFault(point)
    ) {
        _ = try await faulting.commitAtomically(record)
    }
    let restarted = try AtomicFileClientPairedHostStoreV0(
        directory: temporary.store
    )
    #expect(try await restarted.commitAtomically(record)
        == .alreadyPresentExactRecord)
}

@Test func restartFailsClosedOnNoncanonicalOrUnexpectedVisibleFiles() async throws {
    let temporary = try ClientStorageTemporaryDirectory()
    defer { temporary.remove() }
    let identity = try storageIdentity(
        pairingID: UUID(),
        clientID: UUID(),
        scalar: 40
    )
    let record = try storageRecord(identity: identity)
    let store = try AtomicFileClientPairedHostStoreV0(
        directory: temporary.store
    )
    _ = try await store.commitAtomically(record)
    let files = try FileManager.default.contentsOfDirectory(
        at: temporary.store,
        includingPropertiesForKeys: nil
    )
    let recordFile = try #require(files.first)
    var tampered = try Data(contentsOf: recordFile)
    tampered.append(0x0a)
    try tampered.write(to: recordFile)
    let restarted = try AtomicFileClientPairedHostStoreV0(
        directory: temporary.store
    )
    await #expect(
        throws: ClientPairedHostStorageErrorV0.nonCanonicalEncoding
    ) {
        _ = try await restarted.allRecords()
    }

    try FileManager.default.removeItem(at: recordFile)
    try Data("unexpected".utf8).write(
        to: temporary.store.appendingPathComponent("README.txt")
    )
    let unexpected = try AtomicFileClientPairedHostStoreV0(
        directory: temporary.store
    )
    await #expect(throws: ClientPairedHostFileStoreErrorV0.unsafeStorage) {
        _ = try await unexpected.allRecords()
    }
}

@Test func macLibraryKeepsIndependentHostsAndFencesInterruptedForget() async throws {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
        let parent = root.deletingLastPathComponent()
        try #require(parent != root); root = parent
    }
    let path = "client-mac-library-v0.1.json"
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/manifest.json"))) as! [String: Any]
    try #require((manifest["fixtures"] as! [[String: Any]]).filter { $0["path"] as? String == path }.count == 1)
    let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/" + path))) as! [String: Any]
    let clientID = UUID()
    let records = try (0..<2).map { index in
        try storageRecord(identity: storageIdentity(pairingID: UUID(), clientID: clientID, scalar: UInt8(50 + index * 2)))
    }
    for item in fixture["cases"] as! [[String: Any]] {
        let paired = Array(records.prefix(item["pairedCount"] as! Int))
        var preferences = ClientMacLibraryPreferencesV1()
        for record in paired.prefix(item["pendingRemovalCount"] as! Int) { preferences.beginRemoval(hostID: record.hostID) }
        #expect(try preferences.visibleRecords(paired, clientID: clientID).count == item["visibleCount"] as! Int)
    }

    let temporary = try ClientStorageTemporaryDirectory()
    defer { temporary.remove() }
    let paired = try AtomicFileClientPairedHostStoreV0(directory: temporary.store)
    for record in records { _ = try await paired.commitAtomically(record) }
    let namesDirectory = temporary.root.appendingPathComponent("Library", isDirectory: true)
    try FileManager.default.createDirectory(at: namesDirectory, withIntermediateDirectories: true)
    let library = try AtomicFileClientMacLibraryStoreV1(directory: namesDirectory)
    var preferences = try await library.snapshot()
    try preferences.rename(hostID: records[0].hostID, name: "Studio Mac")
    try preferences.rename(hostID: records[1].hostID, name: "Travel Mac")
    preferences.beginRemoval(hostID: records[0].hostID)
    try await library.replace(preferences)
    let restarted = try AtomicFileClientMacLibraryStoreV1(directory: namesDirectory)
    let stored = try await restarted.snapshot()
    #expect(stored == preferences)
    let visible = try stored.library(records: await paired.allRecords(), clientID: clientID,
        configuredHostIDs: [records[1].hostID])
    #expect(visible.map(\.name) == ["Travel Mac"])
    #expect(visible.first?.needsRouteSetup == false)
    #expect(try await paired.pairedHost(hostID: records[1].hostID) == records[1])

    try await paired.remove(records[0])
    try await paired.remove(records[0]) // Interrupted cleanup is idempotent.
    #expect(try await paired.allRecords() == [records[1]])
    preferences.finishRemoval(hostID: records[0].hostID)
    try await library.replace(preferences)
    #expect(try await restarted.snapshot().names == [records[1].hostID: "Travel Mac"])
}

@Test func macLibraryRejectsConflictsUnsafeMetadataAndWrongHostRemoval() async throws {
    let clientID = UUID()
    let record = try storageRecord(identity: storageIdentity(pairingID: UUID(), clientID: clientID, scalar: 60))
    var preferences = ClientMacLibraryPreferencesV1()
    #expect(throws: ClientMacLibraryErrorV1.invalidName) { try preferences.rename(hostID: record.hostID, name: "  ") }
    #expect(throws: ClientMacLibraryErrorV1.invalidName) { try preferences.rename(hostID: record.hostID, name: "a\nb") }
    #expect(throws: ClientMacLibraryErrorV1.conflictingInventory) { _ = try preferences.visibleRecords([record, record], clientID: clientID) }
    #expect(throws: ClientMacLibraryErrorV1.conflictingInventory) { _ = try preferences.visibleRecords([record], clientID: UUID()) }

    let temporary = try ClientStorageTemporaryDirectory()
    defer { temporary.remove() }
    let paired = try AtomicFileClientPairedHostStoreV0(directory: temporary.store)
    _ = try await paired.commitAtomically(record)
    let replacement = try storageRecord(identity: storageIdentity(pairingID: UUID(), clientID: clientID, scalar: 62), hostID: record.hostID)
    await #expect(throws: ClientIdentityPublicationErrorV0.persistenceConflict) { try await paired.remove(replacement) }
    #expect(try await paired.allRecords() == [record])
    let library = try AtomicFileClientMacLibraryStoreV1(directory: temporary.store)
    try Data("{}".utf8).write(to: temporary.store.appendingPathComponent("library.json"))
    await #expect(throws: (any Error).self) { _ = try await library.snapshot() }
    await #expect(throws: (any Error).self) { try await library.replace(.init()) }
}
