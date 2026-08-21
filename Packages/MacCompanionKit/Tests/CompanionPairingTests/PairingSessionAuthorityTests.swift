import CompanionDomain
import CompanionPairing
import CompanionPersistence
import CryptoKit
import Foundation
import Testing

private let pairingID = UUID(uuidString: "018f4000-0000-7000-8000-000000000001")!
private let clientID = UUID(uuidString: "018f2000-0000-7000-8000-000000000001")!
private let deviceID = UUID(uuidString: "018f2100-0000-7000-8000-000000000001")!
private let hostFingerprint = Data(hex: "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f")
private let oneTimeSecret = Data(hex: "c0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedf")
private let clientNonce = Data(base64URL: "EBESExQVFhcYGRobHB0eHyAhIiMkJSYnKCkqKywtLi8")
private let hostNonce = Data(base64URL: "MDEyMzQ1Njc4OTo7PD0-P0BBQkNERUZHSElKS0xNTk8")
private let sessionPublicKey = Data(base64URL: "BGsX0fLhLEJH-Lzm5WOkQPJ3A32BLeszoPShOUXYmMKWT-NC4v4af5uO5-tKfA-eFivOM1drMV7Oy7ZAaDe_UfU")
private let approvalPublicKey = Data(base64URL: "BHzyexiNA09-ilI4AwS1GsPAiWnid_IbNaYLSPxHZpl4B3dVENuO0EApPZrGn3Qw27p9reY86YIpngS3nSJ4c9E")
private let secretProof = Data(hex: "60bf3cbe77c02faca2fc3d20b6940c1b60b152d1f377aa88b158c6bed7ca660c")
private let signature = Data(base64URL: "7wfFfyYk85I2xCTmDLs2dJ5aESa0746q-r_-n_xizx3EA3gIN0kTsajrXJMdMASuX65QXfnElf90LdQzZ-JoRQ")
private let transcriptDigest = Data(hex: "035a5302e8ab1aebadb5ad063f14505f65d36ff9a4773a6d96f38fd34c7571c1")
private let pairingDisplayName = try! DeviceDisplayName("Jenny's iPhone")

private actor RecordingCommitter: PairingCommitter {
    private(set) var commits: [(
        UUID, StoredDeviceRecord, DeviceDisplayName
    )] = []

    func commitPairing(
        pairingID: UUID,
        record: StoredDeviceRecord,
        displayName: DeviceDisplayName
    ) async throws {
        commits.append((pairingID, record, displayName))
    }
}

private enum TestCommitError: Error {
    case unavailable
}

private actor FailOnceCommitter: PairingCommitter {
    private var shouldFail = true
    private(set) var successfulCommits = 0

    func commitPairing(
        pairingID: UUID,
        record: StoredDeviceRecord,
        displayName: DeviceDisplayName
    ) async throws {
        if shouldFail {
            shouldFail = false
            throw TestCommitError.unavailable
        }
        successfulCommits += 1
    }
}

private actor SuspendingPairingCommitter: PairingCommitter {
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    func commitPairing(
        pairingID: UUID,
        record: StoredDeviceRecord,
        displayName: DeviceDisplayName
    ) async throws {
        started = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private func authorityThroughProof(
    committer: any PairingCommitter,
    auditWriter: (any PairingAuditWritingV0)? = nil
) async throws -> (PairingSessionAuthority, PairingApprovalContext) {
    let authority = PairingSessionAuthority(
        committer: committer,
        auditWriter: auditWriter
    )
    let advertisement = try await authority.createSession(
        pairingID: pairingID,
        hostFingerprint: hostFingerprint,
        wallNowUnixMilliseconds: 1_787_198_400_000,
        monotonicNowMilliseconds: 1_000,
        oneTimeSecret: oneTimeSecret
    )
    #expect(advertisement.expiresAtUnixMilliseconds == 1_787_198_700_000)
    let challenge = try await authority.begin(
        pairingID: pairingID,
        clientID: clientID,
        sessionPublicKeyX963: sessionPublicKey,
        approvalPublicKeyX963: approvalPublicKey,
        clientNonce: clientNonce,
        monotonicNowMilliseconds: 1_010,
        hostNonce: hostNonce
    )
    #expect(challenge.hostNonce == hostNonce)
    let context = try await authority.prove(
        pairingID: pairingID,
        secretProof: secretProof,
        signature: signature,
        monotonicNowMilliseconds: 1_020
    )
    return (authority, context)
}

@Test func goldenPairingFlowCommitsExactlyOnceAsMonitorOnly() async throws {
    let committer = RecordingCommitter()
    let (authority, context) = try await authorityThroughProof(committer: committer)
    #expect(context.transcriptDigest == transcriptDigest)
    #expect(context.authenticationString == "23F-6F5")
    #expect(context.clientID == clientID)

    let completed = try await authority.decideApproval(
        pairingID: pairingID,
        approvedTranscriptDigest: transcriptDigest,
        approved: true,
        deviceID: deviceID,
        displayName: pairingDisplayName,
        policyRevision: .init(rawValue: 7),
        wallNowUnixMilliseconds: 1_787_198_401_030,
        monotonicNowMilliseconds: 1_030
    )
    #expect(completed.deviceID == deviceID)
    #expect(completed.displayName == pairingDisplayName)
    #expect(completed.policyRevision.rawValue == 7)

    let commits = await committer.commits
    #expect(commits.count == 1)
    #expect(commits.first?.0 == pairingID)
    #expect(commits.first?.1.clientID == clientID)
    #expect(commits.first?.1.authorization.state == .activeMonitorOnly)
    #expect(commits.first?.1.authorization.authorizationEpoch.rawValue == 1)
    #expect(commits.first?.1.authorization.grantRevision.rawValue == 1)
    #expect(commits.first?.1.policyRevision.rawValue == 7)
    #expect(commits.first?.2 == pairingDisplayName)

    await #expect(throws: PairingSessionError.alreadyConsumed) {
        _ = try await authority.decideApproval(
            pairingID: pairingID,
            approvedTranscriptDigest: transcriptDigest,
            approved: true,
            deviceID: UUID(),
            displayName: pairingDisplayName,
            policyRevision: .init(rawValue: 7),
            wallNowUnixMilliseconds: 1_787_198_401_040,
            monotonicNowMilliseconds: 1_040
        )
    }
}

@Test func pairingApprovalContextRejectsMismatchedKeyFingerprint() throws {
    #expect(throws: PairingSessionError.invalidInput) {
        try PairingApprovalContext(
            pairingID: pairingID,
            clientID: clientID,
            sessionPublicKeyX963: sessionPublicKey,
            approvalPublicKeyX963: approvalPublicKey,
            sessionPublicKeyFingerprint: Data(repeating: 0, count: 32),
            approvalPublicKeyFingerprint: Data(
                SHA256.hash(data: approvalPublicKey)
            ),
            transcriptDigest: transcriptDigest,
            authenticationString: "23F-6F5",
            expiresAtUnixMilliseconds: 1_787_198_700_000,
            deadlineMonotonicMilliseconds: 301_000
        )
    }
}

@Test func pairingDeclineRequiresNoNameAndPersistsNothing() async throws {
    let committer = RecordingCommitter()
    let (authority, _) = try await authorityThroughProof(
        committer: committer
    )

    await #expect(throws: PairingSessionError.invalidInput) {
        _ = try await authority.decideApproval(
            pairingID: pairingID,
            approvedTranscriptDigest: transcriptDigest,
            approved: true,
            deviceID: deviceID,
            displayName: nil,
            policyRevision: .init(rawValue: 7),
            wallNowUnixMilliseconds: 1_787_198_401_030,
            monotonicNowMilliseconds: 1_030
        )
    }
    await #expect(throws: PairingSessionError.approvalRejected) {
        _ = try await authority.decideApproval(
            pairingID: pairingID,
            approvedTranscriptDigest: transcriptDigest,
            approved: false,
            deviceID: deviceID,
            displayName: nil,
            policyRevision: .init(rawValue: 7),
            wallNowUnixMilliseconds: 1_787_198_401_031,
            monotonicNowMilliseconds: 1_031
        )
    }
    #expect(await committer.commits.isEmpty)
}

@Test func authorityAndSQLiteAtomicallyPersistConsumptionIdentityAndEvent() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("maccompanion-pairing-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SQLiteSecurityStore(
        path: directory.appendingPathComponent("security.sqlite3").path
    )
    let (authority, _) = try await authorityThroughProof(committer: store)

    _ = try await authority.decideApproval(
        pairingID: pairingID,
        approvedTranscriptDigest: transcriptDigest,
        approved: true,
        deviceID: deviceID,
        displayName: pairingDisplayName,
        policyRevision: .init(rawValue: 3),
        wallNowUnixMilliseconds: 1_787_198_401_030,
        monotonicNowMilliseconds: 1_030
    )

    #expect(try await store.pairingConsumptionDeviceID(pairingID) == deviceID)
    #expect(try await store.device(deviceID)?.policyRevision.rawValue == 3)
    #expect(try await store.deviceDisplayName(deviceID) == pairingDisplayName)
    #expect(try await store.securityEventCount() == 1)
}

@Test func pairingNameAndIdentityRollbackAsOneTransaction() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "maccompanion-pairing-name-rollback-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SQLiteSecurityStore(
        path: directory.appendingPathComponent("security.sqlite3").path,
        injectedFaults: [.afterDeviceMutation]
    )
    let (authority, _) = try await authorityThroughProof(committer: store)

    await #expect(throws: SecurityStoreError.injectedFault(
        .afterDeviceMutation
    )) {
        _ = try await authority.decideApproval(
            pairingID: pairingID,
            approvedTranscriptDigest: transcriptDigest,
            approved: true,
            deviceID: deviceID,
            displayName: pairingDisplayName,
            policyRevision: .init(rawValue: 3),
            wallNowUnixMilliseconds: 1_787_198_401_030,
            monotonicNowMilliseconds: 1_030
        )
    }

    #expect(try await store.pairingConsumptionDeviceID(pairingID) == nil)
    #expect(try await store.device(deviceID) == nil)
    #expect(try await store.deviceDisplayName(deviceID) == nil)
    #expect(try await store.securityEventCount() == 0)
}

@Test func fiveFailedProofsConsumeTheBootScopedSession() async throws {
    let committer = RecordingCommitter()
    let authority = PairingSessionAuthority(committer: committer)
    _ = try await authority.createSession(
        pairingID: pairingID,
        hostFingerprint: hostFingerprint,
        wallNowUnixMilliseconds: 10_000,
        monotonicNowMilliseconds: 100,
        oneTimeSecret: oneTimeSecret
    )
    _ = try await authority.begin(
        pairingID: pairingID,
        clientID: clientID,
        sessionPublicKeyX963: sessionPublicKey,
        approvalPublicKeyX963: approvalPublicKey,
        clientNonce: clientNonce,
        monotonicNowMilliseconds: 110,
        hostNonce: hostNonce
    )
    let invalid = Data(repeating: 0, count: 32)
    for attempt in 1...PairingSessionAuthority.maximumFailedProofs {
        await #expect(throws: PairingSessionError.invalidProof(
            remainingAttempts: PairingSessionAuthority.maximumFailedProofs - attempt
        )) {
            _ = try await authority.prove(
                pairingID: pairingID,
                secretProof: invalid,
                signature: signature,
                monotonicNowMilliseconds: 110 + Int64(attempt)
            )
        }
    }
    await #expect(throws: PairingSessionError.alreadyConsumed) {
        _ = try await authority.prove(
            pairingID: pairingID,
            secretProof: secretProof,
            signature: signature,
            monotonicNowMilliseconds: 120
        )
    }
}

@Test func monotonicDeadlineExpiresSessionEvenIfWallClockChanges() async throws {
    let authority = PairingSessionAuthority(committer: RecordingCommitter())
    _ = try await authority.createSession(
        pairingID: pairingID,
        hostFingerprint: hostFingerprint,
        wallNowUnixMilliseconds: 10_000,
        monotonicNowMilliseconds: 100,
        oneTimeSecret: oneTimeSecret
    )
    await #expect(throws: PairingSessionError.expired) {
        _ = try await authority.begin(
            pairingID: pairingID,
            clientID: clientID,
            sessionPublicKeyX963: sessionPublicKey,
            approvalPublicKeyX963: approvalPublicKey,
            clientNonce: clientNonce,
            monotonicNowMilliseconds: 100 + PairingSessionAuthority.lifetimeMilliseconds,
            hostNonce: hostNonce
        )
    }
}

@Test func localCancellationConsumesAdvertisedSessionAndIsFailClosed() async throws {
    let authority = PairingSessionAuthority(committer: RecordingCommitter())
    _ = try await authority.createSession(
        pairingID: pairingID,
        hostFingerprint: hostFingerprint,
        wallNowUnixMilliseconds: 10_000,
        monotonicNowMilliseconds: 100,
        oneTimeSecret: oneTimeSecret
    )
    try await authority.cancel(
        pairingID: pairingID,
        monotonicNowMilliseconds: 110
    )

    await #expect(throws: PairingSessionError.alreadyConsumed) {
        _ = try await authority.begin(
            pairingID: pairingID,
            clientID: clientID,
            sessionPublicKeyX963: sessionPublicKey,
            approvalPublicKeyX963: approvalPublicKey,
            clientNonce: clientNonce,
            monotonicNowMilliseconds: 111,
            hostNonce: hostNonce
        )
    }
    await #expect(throws: PairingSessionError.alreadyConsumed) {
        try await authority.cancel(
            pairingID: pairingID,
            monotonicNowMilliseconds: 112
        )
    }
}

@Test func localCancellationCannotRaceDurablePairingCommit() async throws {
    let committer = SuspendingPairingCommitter()
    let (authority, _) = try await authorityThroughProof(committer: committer)
    let decision = Task {
        try await authority.decideApproval(
            pairingID: pairingID,
            approvedTranscriptDigest: transcriptDigest,
            approved: true,
            deviceID: deviceID,
            displayName: pairingDisplayName,
            policyRevision: .init(rawValue: 1),
            wallNowUnixMilliseconds: 1_787_198_401_030,
            monotonicNowMilliseconds: 1_030
        )
    }
    await committer.waitUntilStarted()
    await #expect(throws: PairingSessionError.invalidState) {
        try await authority.cancel(
            pairingID: pairingID,
            monotonicNowMilliseconds: 1_031
        )
    }
    await committer.resume()
    #expect(try await decision.value.deviceID == deviceID)
}

@Test func commitFailureRestoresProvedStateForFreshLocalRetry() async throws {
    let committer = FailOnceCommitter()
    let (authority, _) = try await authorityThroughProof(committer: committer)
    await #expect(throws: TestCommitError.unavailable) {
        _ = try await authority.decideApproval(
            pairingID: pairingID,
            approvedTranscriptDigest: transcriptDigest,
            approved: true,
            deviceID: deviceID,
            displayName: pairingDisplayName,
            policyRevision: .init(rawValue: 1),
            wallNowUnixMilliseconds: 1_787_198_401_030,
            monotonicNowMilliseconds: 1_030
        )
    }
    _ = try await authority.decideApproval(
        pairingID: pairingID,
        approvedTranscriptDigest: transcriptDigest,
        approved: true,
        deviceID: deviceID,
        displayName: pairingDisplayName,
        policyRevision: .init(rawValue: 1),
        wallNowUnixMilliseconds: 1_787_198_401_040,
        monotonicNowMilliseconds: 1_040
    )
    #expect(await committer.successfulCommits == 1)
}

@Test func approvedPairingPublishesIdempotentBestEffortDetailAfterCommit() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-pairing-audit-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let auditStore = try SQLiteBoundedAuditStoreV0(
        path: directory.appendingPathComponent("audit.sqlite3").path
    )
    let auditWriter = BoundedPairingAuditWriterV0(store: auditStore)
    let committer = RecordingCommitter()
    let (authority, _) = try await authorityThroughProof(
        committer: committer,
        auditWriter: auditWriter
    )

    _ = try await authority.decideApproval(
        pairingID: pairingID,
        approvedTranscriptDigest: transcriptDigest,
        approved: true,
        deviceID: deviceID,
        displayName: pairingDisplayName,
        policyRevision: .init(rawValue: 7),
        wallNowUnixMilliseconds: 1_787_198_401_030,
        monotonicNowMilliseconds: 1_030
    )
    let page = try await auditStore.page(
        scope: .localAdministration,
        limit: 10
    )
    #expect(await committer.commits.count == 1)
    #expect(page.events.count == 1)
    #expect(page.events.first?.draft.eventID == pairingID)
    #expect(page.events.first?.draft.code == .pairingApproved)
    #expect(page.events.first?.draft.subjectDeviceID == deviceID)
    #expect(page.events.first?.draft.policyRevision?.rawValue == 7)
    #expect(page.events.first?.draft.importance == .bestEffort)
    #expect(await auditWriter.health() == .healthy)
}

@Test func detailedAuditFailureNeverRollsBackCompletedPairing() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-pairing-audit-fault-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let auditStore = try SQLiteBoundedAuditStoreV0(
        path: directory.appendingPathComponent("audit.sqlite3").path,
        injectedFaults: [.afterCompaction]
    )
    let auditWriter = BoundedPairingAuditWriterV0(store: auditStore)
    let committer = RecordingCommitter()
    let (authority, _) = try await authorityThroughProof(
        committer: committer,
        auditWriter: auditWriter
    )

    let completed = try await authority.decideApproval(
        pairingID: pairingID,
        approvedTranscriptDigest: transcriptDigest,
        approved: true,
        deviceID: deviceID,
        displayName: pairingDisplayName,
        policyRevision: .init(rawValue: 7),
        wallNowUnixMilliseconds: 1_787_198_401_030,
        monotonicNowMilliseconds: 1_030
    )

    #expect(completed.deviceID == deviceID)
    #expect(await committer.commits.count == 1)
    #expect(await auditWriter.health() == .degraded)
    #expect(try await auditStore.page(
        scope: .localAdministration,
        limit: 10
    ).events.isEmpty)
}

@Test func durablePairingAuditDropDegradesHealthWithoutRollingBackCommit() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-pairing-audit-drop-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let auditStore = try SQLiteBoundedAuditStoreV0(
        path: directory.appendingPathComponent("audit.sqlite3").path,
        configuration: try AuditStoreConfigurationV0(
            logicalByteLimit: 16 * 1_024 * 1_024,
            retainedRowLimit: 50_000,
            retentionMilliseconds: 30 * 24 * 60 * 60 * 1_000,
            rateLimitAttempts: 1,
            rateLimitWindowMilliseconds: 60_000
        )
    )
    _ = try await auditStore.append(try AuditEventDraftV0(
        eventID: UUID(),
        observedAtUnixMilliseconds: 1_787_198_401_020,
        actor: .localUser,
        visibility: .subjectDevice,
        subjectDeviceID: deviceID,
        code: .deviceNameConfirmed,
        importance: .bestEffort
    ))
    let auditWriter = BoundedPairingAuditWriterV0(store: auditStore)
    let committer = RecordingCommitter()
    let (authority, _) = try await authorityThroughProof(
        committer: committer,
        auditWriter: auditWriter
    )

    let completed = try await authority.decideApproval(
        pairingID: pairingID,
        approvedTranscriptDigest: transcriptDigest,
        approved: true,
        deviceID: deviceID,
        displayName: pairingDisplayName,
        policyRevision: .init(rawValue: 7),
        wallNowUnixMilliseconds: 1_787_198_401_030,
        monotonicNowMilliseconds: 1_030
    )

    #expect(completed.deviceID == deviceID)
    #expect(await committer.commits.count == 1)
    #expect(await auditWriter.health() == .degraded)
    #expect(try await auditStore.page(
        scope: .localAdministration,
        limit: 10
    ).gaps.droppedEventCount == 1)
}

private extension Data {
    init(hex: String) {
        self.init()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
    }

    init(base64URL: String) {
        var text = base64URL
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        text.append(String(repeating: "=", count: (4 - text.count % 4) % 4))
        self = Data(base64Encoded: text)!
    }
}
