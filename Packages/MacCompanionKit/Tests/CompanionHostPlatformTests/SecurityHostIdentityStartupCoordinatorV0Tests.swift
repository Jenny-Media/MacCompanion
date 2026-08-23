@testable import CompanionHostPlatform
import CompanionPersistence
import CompanionSecurity
import CryptoKit
import Foundation
import Security
import Testing

private actor StartupTestCustodyV0:
    SecurityHostIdentityStartupCustodyV0,
    SecurityHostIdentityRecoveryCustodyV0
{
    private var privateKeys: [Data: SecKey] = [:]
    private var issued: [Data: SecurityHostIssuedIdentityV0] = [:]
    private var availabilityOverride: HostIdentityKeyAvailability?
    private var issueCount = 0
    private var prepareTags: [Data] = []
    private var deletedTags: [Data] = []
    private var deletionStates: [StoredHostIdentityState] = []
    private var recoveryStore: SQLiteSecurityStore?
    private var failDeletion = false

    func setAvailability(_ value: HostIdentityKeyAvailability?) {
        availabilityOverride = value
    }

    func configureRecovery(
        store: SQLiteSecurityStore,
        failDeletion: Bool = false
    ) {
        recoveryStore = store
        self.failDeletion = failDeletion
    }

    func snapshot() -> (
        issueCount: Int,
        prepareTags: [Data],
        deletedTags: [Data],
        deletionStates: [StoredHostIdentityState]
    ) {
        (issueCount, prepareTags, deletedTags, deletionStates)
    }

    func prepareKey(
        applicationTag: Data
    ) throws -> SecurityHostPreparedIdentityKeyV0 {
        prepareTags.append(applicationTag)
        if case .unavailableBeforeFirstUnlock = availabilityOverride {
            throw SecurityHostIdentityKeyCustodyErrorV0
                .keyUnavailableBeforeFirstUnlock
        }
        let key = try privateKey(applicationTag: applicationTag)
        return try assemble(
            key: key,
            applicationTag: applicationTag,
            issuanceTimeUnixMilliseconds: 1_724_000_000_000,
            serialByte: 0x11
        ).key
    }

    func availability(
        applicationTag: Data
    ) throws -> HostIdentityKeyAvailability {
        if let availabilityOverride { return availabilityOverride }
        guard let key = privateKeys[applicationTag] else { return .missing }
        return .available(
            publicKeyX963: try publicKeyX963(key)
        )
    }

    func issueListenerIdentity(
        applicationTag: Data,
        issuanceTimeUnixMilliseconds: Int64
    ) throws -> SecurityHostIssuedIdentityV0 {
        let key = try privateKey(applicationTag: applicationTag)
        issueCount += 1
        let value = try assemble(
            key: key,
            applicationTag: applicationTag,
            issuanceTimeUnixMilliseconds: issuanceTimeUnixMilliseconds,
            serialByte: UInt8(0x20 + issueCount)
        )
        issued[applicationTag] = value
        return value
    }

    func loadListenerIdentity(
        applicationTag: Data,
        certificateDER: Data,
        wallNowUnixMilliseconds _: Int64
    ) throws -> SecurityHostIssuedIdentityV0 {
        guard let value = issued[applicationTag],
              value.certificateDER == certificateDER else {
            throw SecurityHostIdentityKeyCustodyErrorV0.certificateInvalid
        }
        return value
    }

    func deleteRetiredKeyForConfirmedRecovery(
        applicationTag: Data
    ) async throws {
        if let recoveryStore,
           let record = try await recoveryStore.hostIdentity() {
            deletionStates.append(record.state)
        }
        guard !failDeletion else {
            throw SecurityHostIdentityKeyCustodyErrorV0.deletionFailed(-1)
        }
        deletedTags.append(applicationTag)
        privateKeys.removeValue(forKey: applicationTag)
        issued.removeValue(forKey: applicationTag)
    }

    private func privateKey(applicationTag: Data) throws -> SecKey {
        if let existing = privateKeys[applicationTag] { return existing }
        let software = P256.Signing.PrivateKey()
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(
            software.x963Representation as CFData,
            [
                kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
                kSecAttrKeyClass: kSecAttrKeyClassPrivate,
                kSecAttrKeySizeInBits: 256,
            ] as CFDictionary,
            &error
        ) else {
            _ = error?.takeRetainedValue()
            throw SecurityHostIdentityKeyCustodyErrorV0.keyCreationFailed
        }
        privateKeys[applicationTag] = key
        return key
    }

    private func assemble(
        key: SecKey,
        applicationTag: Data,
        issuanceTimeUnixMilliseconds: Int64,
        serialByte: UInt8
    ) throws -> SecurityHostIssuedIdentityV0 {
        try SecurityHostIdentityKeyCustodyV0.assembleIssuedIdentity(
            privateKey: key,
            applicationTag: applicationTag,
            serialNumber: Data(repeating: serialByte, count: 16),
            issuanceTimeUnixMilliseconds: issuanceTimeUnixMilliseconds
        )
    }

    private func publicKeyX963(_ privateKey: SecKey) throws -> Data {
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let bytes = SecKeyCopyExternalRepresentation(
                  publicKey,
                  nil
              ) as Data? else {
            throw SecurityHostIdentityKeyCustodyErrorV0.keyMismatch
        }
        return bytes
    }
}

private struct StartupTemporaryDatabaseV0 {
    let directory: URL
    let database: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "maccompanion-host-startup-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        database = directory.appendingPathComponent("security.sqlite3")
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private let startupNowV0: Int64 = 1_724_000_000_000
private let startupUUIDV0 = UUID(
    uuidString: "018f9000-0000-7000-8000-000000000001"
)!
private let startupTagV0 = Data(
    "example.maccompanion.agent.host.018f9000-0000-7000-8000-000000000001".utf8
)

private func startupCoordinatorV0(
    store: SQLiteSecurityStore,
    custody: StartupTestCustodyV0
) -> SecurityHostIdentityStartupCoordinatorV0 {
    SecurityHostIdentityStartupCoordinatorV0(
        store: store,
        custody: custody,
        wallNowUnixMilliseconds: { startupNowV0 },
        makeUUID: { startupUUIDV0 },
        applicationTag: { _ in startupTagV0 }
    )
}

@Test func hostIdentityStartupPersistsCandidateBeforePublishingReadyIdentity()
    async throws
{
    let temporary = try StartupTemporaryDatabaseV0()
    defer { temporary.remove() }
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    let custody = StartupTestCustodyV0()
    let coordinator = startupCoordinatorV0(store: store, custody: custody)

    guard case let .ready(record, issued, renewal) =
        try await coordinator.start() else {
        Issue.record("expected ready bootstrap")
        return
    }
    #expect(record.hostID == startupUUIDV0)
    #expect(record.keyApplicationTag == startupTagV0)
    #expect(record.hostFingerprint == issued.key.hostFingerprint)
    #expect(!renewal)
    #expect(try await store.hostIdentityBootstrap() == nil)
    #expect(try await store.hostIdentity() == record)
    #expect(try await store.securityEventCount() == 1)
    let snapshot = await custody.snapshot()
    #expect(snapshot.issueCount == 1)
    #expect(snapshot.prepareTags == [startupTagV0])
}

@Test func hostIdentityStartupCrashResumesExactPendingTagAndKey() async throws {
    let temporary = try StartupTemporaryDatabaseV0()
    defer { temporary.remove() }
    let custody = StartupTestCustodyV0()
    let faulting = try SQLiteSecurityStore(
        path: temporary.database.path,
        injectedFaults: [.beforeSecurityEvent]
    )
    let first = startupCoordinatorV0(store: faulting, custody: custody)

    await #expect(
        throws: SecurityStoreError.injectedFault(.beforeSecurityEvent)
    ) {
        _ = try await first.start()
    }
    let pending = try #require(
        try await faulting.hostIdentityBootstrap()
    )
    #expect(pending.keyApplicationTag == startupTagV0)
    #expect(try await faulting.hostIdentity() == nil)

    let resumedStore = try SQLiteSecurityStore(path: temporary.database.path)
    let resumed = startupCoordinatorV0(
        store: resumedStore,
        custody: custody
    )
    guard case let .ready(record, _, _) = try await resumed.start() else {
        Issue.record("expected resumed ready identity")
        return
    }
    #expect(record.hostID == pending.hostID)
    #expect(record.keyApplicationTag == pending.keyApplicationTag)
    #expect(try await resumedStore.hostIdentityBootstrap() == nil)
    let snapshot = await custody.snapshot()
    #expect(snapshot.issueCount == 2)
    #expect(snapshot.prepareTags == [startupTagV0, startupTagV0])
}

@Test func hostIdentityStartupLoadsReadyIdentityWithoutKeyOrCertificateRotation()
    async throws
{
    let temporary = try StartupTemporaryDatabaseV0()
    defer { temporary.remove() }
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    let custody = StartupTestCustodyV0()
    _ = try await startupCoordinatorV0(
        store: store,
        custody: custody
    ).start()
    let before = try #require(try await store.hostIdentity())

    guard case let .ready(after, _, _) = try await startupCoordinatorV0(
        store: store,
        custody: custody
    ).start() else {
        Issue.record("expected existing ready identity")
        return
    }
    #expect(after == before)
    #expect(try await store.securityEventCount() == 1)
    #expect(await custody.snapshot().issueCount == 1)
}

@Test func hostIdentityStartupWaitsOrRequiresRecoveryWithoutRotatingKey()
    async throws
{
    let temporary = try StartupTemporaryDatabaseV0()
    defer { temporary.remove() }
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    let custody = StartupTestCustodyV0()
    _ = try await startupCoordinatorV0(
        store: store,
        custody: custody
    ).start()

    await custody.setAvailability(.unavailableBeforeFirstUnlock)
    guard case .waitForFirstUnlock = try await startupCoordinatorV0(
        store: store,
        custody: custody
    ).start() else {
        Issue.record("expected first-unlock wait")
        return
    }

    await custody.setAvailability(.missing)
    guard case .requireLocalRecovery(.missingEstablishedKey) =
        try await startupCoordinatorV0(
            store: store,
            custody: custody
        ).start() else {
        Issue.record("expected explicit local recovery")
        return
    }
    #expect(await custody.snapshot().issueCount == 1)
}

@Test func pendingHostIdentityWaitsBeforeFirstUnlockAndKeepsDurableCandidate()
    async throws
{
    let temporary = try StartupTemporaryDatabaseV0()
    defer { temporary.remove() }
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    let custody = StartupTestCustodyV0()
    await custody.setAvailability(.unavailableBeforeFirstUnlock)

    guard case .waitForFirstUnlock = try await startupCoordinatorV0(
        store: store,
        custody: custody
    ).start() else {
        Issue.record("expected pending first-unlock wait")
        return
    }
    let pending = try #require(try await store.hostIdentityBootstrap())
    #expect(pending.hostID == startupUUIDV0)
    #expect(pending.keyApplicationTag == startupTagV0)
    #expect(try await store.hostIdentity() == nil)
    #expect(await custody.snapshot().issueCount == 0)
}

@Test func invalidStoredCertificateRenewsAroundTheSameEstablishedKey()
    async throws
{
    let temporary = try StartupTemporaryDatabaseV0()
    defer { temporary.remove() }
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    let custody = StartupTestCustodyV0()
    _ = try await startupCoordinatorV0(
        store: store,
        custody: custody
    ).start()
    let original = try #require(try await store.hostIdentity())
    let invalid = try StoredHostIdentityRecord(
        hostID: original.hostID,
        keyApplicationTag: original.keyApplicationTag,
        hostFingerprint: original.hostFingerprint,
        certificateDER: Data([0x30]),
        certificateNotBeforeUnixMilliseconds:
            original.certificateNotBeforeUnixMilliseconds,
        certificateNotAfterUnixMilliseconds:
            original.certificateNotAfterUnixMilliseconds,
        establishedAtUnixMilliseconds:
            original.establishedAtUnixMilliseconds,
        updatedAtUnixMilliseconds: original.updatedAtUnixMilliseconds
    )
    try await store.replaceHostIdentityCertificate(
        expected: original,
        replacement: invalid
    )

    guard case let .ready(repaired, issued, _) =
        try await startupCoordinatorV0(
            store: store,
            custody: custody
        ).start() else {
        Issue.record("expected same-key certificate repair")
        return
    }
    #expect(repaired.hostID == original.hostID)
    #expect(repaired.keyApplicationTag == original.keyApplicationTag)
    #expect(repaired.hostFingerprint == original.hostFingerprint)
    #expect(repaired.certificateDER == issued.certificateDER)
    #expect(repaired.certificateDER != invalid.certificateDER)
    #expect(await custody.snapshot().issueCount == 2)
    #expect(try await store.securityEventCount() == 3)
}

@Test func recoveryFencedHostIdentityCannotPublishListenerIdentity()
    async throws
{
    let temporary = try StartupTemporaryDatabaseV0()
    defer { temporary.remove() }
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    let custody = StartupTestCustodyV0()
    _ = try await startupCoordinatorV0(
        store: store,
        custody: custody
    ).start()
    let original = try #require(try await store.hostIdentity())
    let recoveryID = UUID(
        uuidString: "018f9000-0000-7000-8000-000000000099"
    )!
    _ = try await store.beginHostIdentityRecovery(
        intent: recoveryIntentV0(
            original: original,
            recoveryID: recoveryID
        ),
        occurredAtUnixMilliseconds: startupNowV0
    )

    guard case .recoveryFenced(recoveryID) =
        try await startupCoordinatorV0(
            store: store,
            custody: custody
        ).start() else {
        Issue.record("expected durable recovery fence")
        return
    }
    #expect(await custody.snapshot().issueCount == 1)
}

private let recoveryIDV0 = UUID(
    uuidString: "018f9000-0000-7000-8000-000000000099"
)!
private let recoveryHostIDV0 = UUID(
    uuidString: "018f9000-0000-7000-8000-000000000100"
)!
private let recoveryTagV0 = Data(
    "example.maccompanion.agent.host.018f9000-0000-7000-8000-000000000099".utf8
)

private func recoveryIntentV0(
    original: StoredHostIdentityRecord,
    recoveryID: UUID = recoveryIDV0
) throws -> StoredHostIdentityRecoveryIntent {
    try StoredHostIdentityRecoveryIntent(
        commandID: UUID(
            uuidString: "018f9000-0000-7000-8000-000000000101"
        )!,
        recoveryID: recoveryID,
        reviewID: UUID(
            uuidString: "018f9000-0000-7000-8000-000000000102"
        )!,
        expectedHostID: original.hostID,
        expectedHostFingerprint: original.hostFingerprint,
        cause: .suspectedCompromise,
        reviewCreatedAtUnixMilliseconds: startupNowV0 - 2,
        reviewExpiresAtUnixMilliseconds: startupNowV0 + 299_998,
        confirmedAtUnixMilliseconds: startupNowV0 - 1
    )
}

private func recoveryCoordinatorV0(
    store: SQLiteSecurityStore,
    custody: StartupTestCustodyV0,
    recoveryID: UUID = recoveryIDV0
) -> SecurityHostIdentityRecoveryCoordinatorV0 {
    SecurityHostIdentityRecoveryCoordinatorV0(
        store: store,
        custody: custody,
        wallNowUnixMilliseconds: { startupNowV0 + 1_000 },
        makeHostID: { recoveryHostIDV0 },
        applicationTag: { identifier in
            #expect(identifier == recoveryID)
            return recoveryTagV0
        }
    )
}

@Test func confirmedRecoveryFencesBeforeDeletingAndPublishesRotatedIdentity()
    async throws
{
    let temporary = try StartupTemporaryDatabaseV0()
    defer { temporary.remove() }
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    let custody = StartupTestCustodyV0()
    _ = try await startupCoordinatorV0(
        store: store,
        custody: custody
    ).start()
    let original = try #require(try await store.hostIdentity())
    await custody.configureRecovery(store: store)

    let recovered = try await recoveryCoordinatorV0(
        store: store,
        custody: custody
    ).recover(
        intent: recoveryIntentV0(original: original)
    )

    #expect(recovered.record.hostID == recoveryHostIDV0)
    #expect(recovered.record.hostID != original.hostID)
    #expect(recovered.record.keyApplicationTag == recoveryTagV0)
    #expect(recovered.record.hostFingerprint != original.hostFingerprint)
    #expect(try await store.hostIdentity() == recovered.record)
    #expect(try await store.securityEventCount() == 3)
    let snapshot = await custody.snapshot()
    #expect(snapshot.deletedTags == [original.keyApplicationTag])
    #expect(snapshot.deletionStates == [.fencedForReplacement])

    let replayed = try await recoveryCoordinatorV0(
        store: store,
        custody: custody
    ).recover(
        intent: recoveryIntentV0(original: original)
    )
    #expect(replayed.record == recovered.record)
    #expect(replayed.issuedIdentity.certificateDER
        == recovered.issuedIdentity.certificateDER)
    let replaySnapshot = await custody.snapshot()
    #expect(replaySnapshot.issueCount == snapshot.issueCount)
    #expect(replaySnapshot.deletedTags == snapshot.deletedTags)
    #expect(try await store.securityEventCount() == 3)

    guard case .recoveryFenced(recoveryIDV0) =
        try await startupCoordinatorV0(
            store: store,
            custody: custody
        ).start() else {
        Issue.record("completed recovery must remain replay-only before ack")
        return
    }
    let completion = try #require(
        try await store.hostIdentityRecoveryReceipt()
    )
    try await store.acknowledgeHostIdentityRecoveryCompletion(
        commandID: recoveryIntentV0(original: original).commandID,
        receipt: completion,
        occurredAtUnixMilliseconds: startupNowV0 + 1_001
    )
    guard case let .ready(ready, _, _) = try await startupCoordinatorV0(
        store: store,
        custody: custody
    ).start() else {
        Issue.record("acknowledged recovery should permit ordinary startup")
        return
    }
    #expect(ready == recovered.record)
    #expect(try await store.securityEventCount() == 4)
}

@Test func recoveryCompletionFailureResumesAfterOldKeyDeletion() async throws {
    let temporary = try StartupTemporaryDatabaseV0()
    defer { temporary.remove() }
    let setupStore = try SQLiteSecurityStore(path: temporary.database.path)
    let custody = StartupTestCustodyV0()
    _ = try await startupCoordinatorV0(
        store: setupStore,
        custody: custody
    ).start()
    let original = try #require(try await setupStore.hostIdentity())
    _ = try await setupStore.beginHostIdentityRecovery(
        intent: recoveryIntentV0(original: original),
        occurredAtUnixMilliseconds: startupNowV0 + 1_000
    )

    let faulting = try SQLiteSecurityStore(
        path: temporary.database.path,
        injectedFaults: [.beforeSecurityEvent]
    )
    await custody.configureRecovery(store: faulting)
    await #expect(
        throws: SecurityStoreError.injectedFault(.beforeSecurityEvent)
    ) {
        _ = try await recoveryCoordinatorV0(
            store: faulting,
            custody: custody
        ).recover(
            intent: recoveryIntentV0(original: original)
        )
    }
    let fenced = try #require(try await faulting.hostIdentity())
    #expect(fenced.state == .fencedForReplacement)
    #expect(fenced.keyApplicationTag == original.keyApplicationTag)

    let resumedStore = try SQLiteSecurityStore(
        path: temporary.database.path
    )
    await custody.configureRecovery(store: resumedStore)
    let recovered = try await recoveryCoordinatorV0(
        store: resumedStore,
        custody: custody
    ).recover(
        intent: recoveryIntentV0(original: original)
    )
    #expect(recovered.record.keyApplicationTag == recoveryTagV0)
    #expect(try await resumedStore.securityEventCount() == 3)
    let snapshot = await custody.snapshot()
    #expect(snapshot.deletedTags == [
        original.keyApplicationTag,
        original.keyApplicationTag,
    ])
    #expect(snapshot.deletionStates == [
        .fencedForReplacement,
        .fencedForReplacement,
    ])
}

@Test func recoveryDeletionFailureLeavesDurableFenceAndOldReference() async throws {
    let temporary = try StartupTemporaryDatabaseV0()
    defer { temporary.remove() }
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    let custody = StartupTestCustodyV0()
    _ = try await startupCoordinatorV0(
        store: store,
        custody: custody
    ).start()
    let original = try #require(try await store.hostIdentity())
    await custody.configureRecovery(store: store, failDeletion: true)

    await #expect(
        throws: SecurityHostIdentityKeyCustodyErrorV0.deletionFailed(-1)
    ) {
        _ = try await recoveryCoordinatorV0(
            store: store,
            custody: custody
        ).recover(
            intent: recoveryIntentV0(original: original)
        )
    }
    let fenced = try #require(try await store.hostIdentity())
    #expect(fenced.state == .fencedForReplacement)
    #expect(fenced.recoveryID == recoveryIDV0)
    #expect(fenced.keyApplicationTag == original.keyApplicationTag)
    #expect(try await store.securityEventCount() == 2)
    #expect(await custody.snapshot().deletedTags.isEmpty)
}

@Test func recoveryIDConflictMutatesNoSecondKeyOrIdentity() async throws {
    let temporary = try StartupTemporaryDatabaseV0()
    defer { temporary.remove() }
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    let custody = StartupTestCustodyV0()
    _ = try await startupCoordinatorV0(
        store: store,
        custody: custody
    ).start()
    let original = try #require(try await store.hostIdentity())
    _ = try await store.beginHostIdentityRecovery(
        intent: recoveryIntentV0(original: original),
        occurredAtUnixMilliseconds: startupNowV0 + 1_000
    )
    let otherID = UUID(
        uuidString: "018f9000-0000-7000-8000-000000000098"
    )!

    await #expect(
        throws: SecurityStoreError.hostIdentityRecoveryConflict
    ) {
        _ = try await recoveryCoordinatorV0(
            store: store,
            custody: custody,
            recoveryID: otherID
        ).recover(
            intent: recoveryIntentV0(
                original: original,
                recoveryID: otherID
            )
        )
    }
    let snapshot = await custody.snapshot()
    #expect(snapshot.issueCount == 1)
    #expect(snapshot.prepareTags == [startupTagV0])
    #expect(snapshot.deletedTags.isEmpty)
    #expect(try await store.hostIdentity()?.recoveryID == recoveryIDV0)
}
