import CompanionClient
import CompanionClientApp
import CompanionDiscovery
import CompanionDomain
import CompanionPresentation
import CompanionSecurity
import CompanionTransport
import CompanionWire
import CryptoKit
import Foundation
import Testing

private let clientAppPairingID = UUID(
    uuidString: "018fa100-0000-7000-8000-000000000001"
)!
private let clientAppClientID = UUID(
    uuidString: "018fa100-0000-7000-8000-000000000002"
)!
private let clientAppHostID = UUID(
    uuidString: "018fa100-0000-7000-8000-000000000003"
)!
private let clientAppDeviceID = UUID(
    uuidString: "018fa100-0000-7000-8000-000000000004"
)!
private let clientAppSecret = Data(repeating: 0xa1, count: 32)
private let clientAppHostNonce = Data(repeating: 0xb2, count: 32)
private let clientAppHostSPKI = Data((0x00...0x5a).map(UInt8.init))
private let clientAppWall: Int64 = 1_000_000
private let clientAppExpiry: Int64 = 1_300_000

private enum ClientAppProbeError: Error {
    case injected
    case invalidFlow
}

private func clientAppPrivateKey(_ scalar: UInt8) throws
    -> P256.Signing.PrivateKey
{
    var bytes = Data(repeating: 0, count: 32)
    bytes[31] = scalar
    return try P256.Signing.PrivateKey(rawRepresentation: bytes)
}

private func clientAppFingerprint() throws -> Data {
    try CompanionSecurityV0.hostFingerprint(
        subjectPublicKeyInfoDER: clientAppHostSPKI
    )
}

private func clientAppQR() throws -> PairingQRCodePayload {
    try PairingQRCodePayload(
        pairingID: WireUUID(clientAppPairingID),
        oneTimeSecret: WireBytes32(clientAppSecret),
        expiresAtUnixMilliseconds: clientAppExpiry,
        hostFingerprint: WireFingerprint(clientAppFingerprint()),
        endpoints: [
            try EndpointCandidate(
                kind: .bonjour,
                value: "studio._maccompanion._tcp.local.",
                port: 47_474
            ),
        ]
    )
}

private actor ClientAppCustodyProbe: ClientIdentityKeyCustodyV0 {
    private let sessionKey: P256.Signing.PrivateKey
    private let approvalKey: P256.Signing.PrivateKey
    private var prepared: ClientPreparedIdentityV0?
    private var discardCount = 0

    init() throws {
        sessionKey = try clientAppPrivateKey(1)
        approvalKey = try clientAppPrivateKey(2)
    }

    func discardedCount() -> Int { discardCount }

    func prepareIdentity(
        pairingID: UUID,
        clientID: UUID
    ) async throws -> ClientPreparedIdentityV0 {
        let value = try ClientPreparedIdentityV0(
            pairingID: pairingID,
            clientID: clientID,
            sessionKey: ClientCustodiedPublicKeyV0(
                role: .session,
                reference: ClientSigningKeyReferenceV0(UUID()),
                publicKeyX963: sessionKey.publicKey.x963Representation,
                protection: .afterFirstUnlockThisDeviceOnly
            ),
            approvalKey: ClientCustodiedPublicKeyV0(
                role: .approval,
                reference: ClientSigningKeyReferenceV0(UUID()),
                publicKeyX963: approvalKey.publicKey.x963Representation,
                protection: .whenUnlockedThisDeviceOnlyUserPresence
            )
        )
        prepared = value
        return value
    }

    func validatePreparedIdentity(
        _ identity: ClientPreparedIdentityV0
    ) async throws -> Bool {
        prepared == identity
    }

    func signSessionInput(
        _ input: Data,
        using reference: ClientSigningKeyReferenceV0
    ) async throws -> Data {
        guard prepared?.sessionKey.reference == reference else {
            throw ClientAppProbeError.invalidFlow
        }
        return try sessionKey.signature(for: input).rawRepresentation
    }

    func signApprovalInput(
        _ input: Data,
        using reference: ClientSigningKeyReferenceV0,
        reason: ClientApprovalPresenceReasonV0
    ) async throws -> Data {
        guard prepared?.approvalKey.reference == reference else {
            throw ClientAppProbeError.invalidFlow
        }
        return try approvalKey.signature(for: input).rawRepresentation
    }

    func discardPreparedIdentity(
        _ identity: ClientPreparedIdentityV0
    ) async throws {
        guard prepared == identity else {
            throw ClientAppProbeError.invalidFlow
        }
        prepared = nil
        discardCount += 1
    }
}

private actor ClientAppPersistenceProbe: ClientPairedHostPersistenceV0 {
    private var stored: ClientDurablePairedHostV0?
    private var shouldFail = false
    private var suspendCommit = false
    private var commitWaiters: [CheckedContinuation<Void, Never>] = []
    private var commitContinuation: CheckedContinuation<Void, Never>?

    func setShouldFail(_ value: Bool) { shouldFail = value }
    func suspendNextCommit() { suspendCommit = true }
    func record() -> ClientDurablePairedHostV0? { stored }

    func waitForCommit() async {
        if commitContinuation != nil { return }
        await withCheckedContinuation { continuation in
            commitWaiters.append(continuation)
        }
    }

    func resumeCommit() {
        commitContinuation?.resume()
        commitContinuation = nil
    }

    func commitAtomically(
        _ record: ClientDurablePairedHostV0
    ) async throws -> ClientPairedHostCommitResultV0 {
        if shouldFail { throw ClientAppProbeError.injected }
        if suspendCommit {
            suspendCommit = false
            let waiters = commitWaiters
            commitWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
            await withCheckedContinuation { continuation in
                commitContinuation = continuation
            }
        }
        if stored == record { return .alreadyPresentExactRecord }
        guard stored == nil else { throw ClientAppProbeError.invalidFlow }
        stored = record
        return .inserted
    }
}

private final class ClientAppClockProbe:
    ClientPairingClockV0,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var monotonic: UInt64 = 1_000

    func sample() throws -> ClientPairingTimeSampleV0 {
        try lock.withLock {
            defer { monotonic += 1 }
            return try ClientPairingTimeSampleV0(
                wallUnixMilliseconds: clientAppWall,
                monotonicMilliseconds: monotonic
            )
        }
    }
}

private final class ClientAppRandomnessProbe:
    ClientPairingRandomnessV0,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var nextIdentifier: UInt64 = 1

    func randomBytes(count: Int) throws -> Data {
        Data(repeating: 0xc3, count: count)
    }

    func randomUUID() -> UUID {
        lock.withLock {
            defer { nextIdentifier += 1 }
            let suffix = String(format: "%012llx", nextIdentifier)
            return UUID(
                uuidString: "018fa200-0000-7000-8000-\(suffix)"
            )!
        }
    }
}

private actor ClientAppPresentationProbe {
    private var snapshots: [PairingClientPresentation] = []
    func append(_ value: PairingClientPresentation) { snapshots.append(value) }
    func values() -> [PairingClientPresentation] { snapshots }
}

private actor ClientAppConnectionProbe: ClientPairingConnectionV0 {
    private let mismatchedPin: Bool
    private let failConnect: Bool
    private let suspendCompletion: Bool
    private var closed = false
    private var responses: [Data] = []
    private var begin: WireEnvelope<PairingBeginBody>?
    private var receiveCount = 0
    private var completionWaiter: CheckedContinuation<Data, any Error>?
    private var completionStarted = false
    private var completionStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var observedDeadlines: [UInt64] = []

    init(
        mismatchedPin: Bool = false,
        failConnect: Bool = false,
        suspendCompletion: Bool = false
    ) {
        self.mismatchedPin = mismatchedPin
        self.failConnect = failConnect
        self.suspendCompletion = suspendCompletion
    }

    func isClosed() -> Bool { closed }
    func deadlines() -> [UInt64] { observedDeadlines }

    func waitForCompletionReceive() async {
        if completionStarted { return }
        await withCheckedContinuation { continuation in
            completionStartWaiters.append(continuation)
        }
    }

    func connectTCP() async throws {
        if failConnect { throw ClientAppProbeError.injected }
    }

    func acceptPinnedTLS() async throws -> TLSPeerEvidence {
        TLSPeerEvidence(
            negotiatedTLSMajor: 1,
            negotiatedTLSMinor: 3,
            earlyDataAccepted: false,
            pinnedLeafPolicyAccepted: true,
            subjectPublicKeyInfoDER: mismatchedPin
                ? Data(repeating: 0x7f, count: 91)
                : clientAppHostSPKI
        )
    }

    func send(
        _ frame: Data,
        deadlineMonotonicMilliseconds: UInt64
    ) async throws {
        guard !closed else { throw ClientAppProbeError.invalidFlow }
        observedDeadlines.append(deadlineMonotonicMilliseconds)
        let kind = try WireCodec.messageKind(from: frame)
        switch kind {
        case .pairingBegin:
            let request = try WireCodec.decode(
                WireEnvelope<PairingBeginBody>.self,
                from: frame
            )
            begin = request
            responses.append(
                try WireCodec.encode(WireEnvelope(
                    messageID: WireUUID(UUID()),
                    correlationID: request.messageID,
                    sentAtUnixMilliseconds: clientAppWall,
                    body: try PairingChallengeBody(
                        hostNonce: WireBytes32(clientAppHostNonce),
                        hostFingerprint: WireFingerprint(clientAppFingerprint())
                    )
                ))
            )
        case .pairingProve:
            guard let begin else { throw ClientAppProbeError.invalidFlow }
            let proof = try WireCodec.decode(
                WireEnvelope<PairingProveBody>.self,
                from: frame
            )
            let transcript = try CompanionSecurityV0.pairingTranscriptInput(
                pairingID: clientAppPairingID,
                hostFingerprint: clientAppFingerprint(),
                clientID: clientAppClientID,
                sessionPublicKeyX963: begin.body.sessionPublicKey.rawValue,
                approvalPublicKeyX963: begin.body.approvalPublicKey.rawValue,
                clientNonce: begin.body.clientNonce.rawValue,
                hostNonce: clientAppHostNonce,
                selectedMajor: 0,
                selectedMinor: 1
            )
            let digest = CompanionSecurityV0.pairingTranscriptDigest(transcript)
            guard try CompanionSecurityV0.verifyPairingSecretProof(
                proof.body.secretProof.rawValue,
                oneTimeSecret: clientAppSecret,
                transcriptDigest: digest
            ) else {
                throw ClientAppProbeError.invalidFlow
            }
            responses.append(
                try WireCodec.encode(WireEnvelope(
                    messageID: WireUUID(UUID()),
                    correlationID: proof.messageID,
                    sentAtUnixMilliseconds: clientAppWall,
                    body: try PairingPendingApprovalBody(
                        transcriptDigest: WireBytes32(digest),
                        authenticationString: PairingAuthenticationString(
                            try CompanionSecurityV0.authenticationString(
                                oneTimeSecret: clientAppSecret,
                                transcriptDigest: digest
                            )
                        ),
                        expiresAtUnixMilliseconds: clientAppExpiry
                    )
                ))
            )
            responses.append(
                try WireCodec.encode(WireEnvelope(
                    messageID: WireUUID(UUID()),
                    correlationID: proof.messageID,
                    sentAtUnixMilliseconds: clientAppWall,
                    body: try PairingCompleteBody(
                        hostID: WireUUID(clientAppHostID),
                        deviceID: WireUUID(clientAppDeviceID),
                        policyRevision: .init(rawValue: 1),
                        hostFingerprint: WireFingerprint(clientAppFingerprint())
                    )
                ))
            )
        default:
            throw ClientAppProbeError.invalidFlow
        }
    }

    func receive(
        deadlineMonotonicMilliseconds: UInt64
    ) async throws -> Data {
        guard !closed, !responses.isEmpty else {
            throw ClientAppProbeError.invalidFlow
        }
        observedDeadlines.append(deadlineMonotonicMilliseconds)
        receiveCount += 1
        if suspendCompletion, receiveCount == 3 {
            completionStarted = true
            let waiters = completionStartWaiters
            completionStartWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
            return try await withCheckedThrowingContinuation { continuation in
                completionWaiter = continuation
            }
        }
        return responses.removeFirst()
    }

    func close() async {
        guard !closed else { return }
        closed = true
        completionWaiter?.resume(throwing: ClientAppProbeError.injected)
        completionWaiter = nil
    }
}

private actor ClientAppConnectionFactoryProbe:
    ClientPairingConnectionCreatingV0
{
    let connection: ClientAppConnectionProbe
    private var requests: [ClientPairingConnectionRequestV0] = []

    init(connection: ClientAppConnectionProbe) {
        self.connection = connection
    }

    func values() -> [ClientPairingConnectionRequestV0] { requests }

    func makeConnection(
        _ request: ClientPairingConnectionRequestV0
    ) async throws -> any ClientPairingConnectionV0 {
        requests.append(request)
        return connection
    }
}

private struct ClientAppFixture {
    let owner: ClientPairingApplicationOwnerV0
    let custody: ClientAppCustodyProbe
    let persistence: ClientAppPersistenceProbe
    let connection: ClientAppConnectionProbe
    let factory: ClientAppConnectionFactoryProbe
    let states: ClientAppPresentationProbe
}

private func clientAppFixture(
    mismatchedPin: Bool = false,
    failConnect: Bool = false,
    suspendCompletion: Bool = false
) throws -> ClientAppFixture {
    let custody = try ClientAppCustodyProbe()
    let persistence = ClientAppPersistenceProbe()
    let connection = ClientAppConnectionProbe(
        mismatchedPin: mismatchedPin,
        failConnect: failConnect,
        suspendCompletion: suspendCompletion
    )
    let factory = ClientAppConnectionFactoryProbe(connection: connection)
    let states = ClientAppPresentationProbe()
    return ClientAppFixture(
        owner: try ClientPairingApplicationOwnerV0(
            clientID: clientAppClientID,
            custody: custody,
            persistence: persistence,
            connections: factory,
            clock: ClientAppClockProbe(),
            randomness: ClientAppRandomnessProbe(),
            stateChanged: { value in await states.append(value) }
        ),
        custody: custody,
        persistence: persistence,
        connection: connection,
        factory: factory,
        states: states
    )
}

private func clientAppScan(_ owner: ClientPairingApplicationOwnerV0) async throws {
    try await owner.receiveScan(
        PairingQRCodeCodec.encode(clientAppQR())
    )
}

@Test func clientPairingApplicationOwnerPublishesOnlyAfterDurableCompletion() async throws {
    let fixture = try clientAppFixture()
    try await clientAppScan(fixture.owner)
    try await fixture.owner.acceptPreview()

    let snapshot = await fixture.owner.snapshot()
    #expect(snapshot.phase == .paired)
    #expect(snapshot.pairedHost?.hostID == clientAppHostID)
    #expect(await fixture.persistence.record()?.deviceID == clientAppDeviceID)
    #expect(await fixture.connection.isClosed())
    let requests = await fixture.factory.values()
    #expect(requests.count == 1)
    #expect(requests[0].pairingID == clientAppPairingID)
    #expect(requests[0].requiredHostFingerprint == (try clientAppFingerprint()))
    #expect(requests[0].endpoints == (try clientAppQR()).endpoints)
    #expect(requests[0].expiresAtUnixMilliseconds == clientAppExpiry)
    let deadlines = await fixture.connection.deadlines()
    #expect(deadlines.count == 5)
    #expect(Set(deadlines).count == 1)

    let values = await fixture.states.values()
    #expect(values.first?.phase == .preview)
    #expect(values.contains { $0.phase == .compareOnMac })
    #expect(values.contains { $0.phase == .saving })
    #expect(values.last?.phase == .paired)
}

@Test func clientPairingApplicationOwnerCancellationFencesPendingCompletion() async throws {
    let fixture = try clientAppFixture(suspendCompletion: true)
    try await clientAppScan(fixture.owner)
    let pairing = Task { try await fixture.owner.acceptPreview() }
    await fixture.connection.waitForCompletionReceive()

    await fixture.owner.cancel()
    try await pairing.value

    #expect(await fixture.owner.snapshot().phase == .scanning)
    #expect(await fixture.persistence.record() == nil)
    #expect(await fixture.custody.discardedCount() == 1)
    #expect(await fixture.connection.isClosed())
}

@Test func clientPairingApplicationOwnerMapsPinMismatchWithoutPublication() async throws {
    let fixture = try clientAppFixture(mismatchedPin: true)
    try await clientAppScan(fixture.owner)
    try await fixture.owner.acceptPreview()

    let snapshot = await fixture.owner.snapshot()
    #expect(snapshot.phase == .failed)
    #expect(snapshot.failure == .identityVerificationFailed)
    #expect(await fixture.persistence.record() == nil)
    #expect(await fixture.custody.discardedCount() == 1)
}

@Test func clientPairingApplicationOwnerMapsTransportFailureWithoutProviderText() async throws {
    let fixture = try clientAppFixture(failConnect: true)
    try await clientAppScan(fixture.owner)
    try await fixture.owner.acceptPreview()

    let snapshot = await fixture.owner.snapshot()
    #expect(snapshot.phase == .failed)
    #expect(snapshot.failure == .connectionFailed)
    #expect(await fixture.persistence.record() == nil)
    #expect(await fixture.custody.discardedCount() == 1)
}

@Test func clientPairingApplicationOwnerFailsClosedOnDurableStorageError() async throws {
    let fixture = try clientAppFixture()
    await fixture.persistence.setShouldFail(true)
    try await clientAppScan(fixture.owner)
    try await fixture.owner.acceptPreview()

    let snapshot = await fixture.owner.snapshot()
    #expect(snapshot.phase == .failed)
    #expect(snapshot.failure == .clientStorageUnavailable)
    #expect(snapshot.pairedHost == nil)
    #expect(await fixture.persistence.record() == nil)
    #expect(await fixture.custody.discardedCount() == 1)
}

@Test func clientPairingApplicationOwnerDoesNotCancelAnInFlightAtomicCommit() async throws {
    let fixture = try clientAppFixture()
    await fixture.persistence.suspendNextCommit()
    try await clientAppScan(fixture.owner)
    let pairing = Task { try await fixture.owner.acceptPreview() }
    await fixture.persistence.waitForCommit()

    await fixture.owner.cancel()
    #expect(await fixture.owner.snapshot().phase == .saving)
    await fixture.persistence.resumeCommit()
    try await pairing.value

    #expect(await fixture.owner.snapshot().phase == .paired)
    #expect(await fixture.persistence.record()?.hostID == clientAppHostID)
    #expect(await fixture.custody.discardedCount() == 0)
}
