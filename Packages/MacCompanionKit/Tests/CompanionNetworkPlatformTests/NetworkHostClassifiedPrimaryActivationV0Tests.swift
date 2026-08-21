import CompanionAuthentication
import CompanionDomain
import CompanionHost
import CompanionHostSession
@testable import CompanionNetworkPlatform
import CompanionOperations
import CompanionPersistence
import CompanionSecurity
import CompanionTransport
import CompanionWire
import CryptoKit
import Foundation
import Testing

private enum NetworkHostClassifiedPrimaryTestErrorV0: Error {
    case unused
    case cancelled
    case noPendingReceive
}

private struct NetworkHostClassifiedPrimaryUnusedStatusV0:
    HostStatusSnapshotProvidingV0
{
    func snapshot(hostState: HostState) async throws -> HostStatusSnapshot {
        throw NetworkHostClassifiedPrimaryTestErrorV0.unused
    }
}

private struct NetworkHostClassifiedPrimaryUnusedOperationsV0:
    AuthenticatedOperationWireDispatchingV0
{
    func dispatch(
        requestJSON: Data,
        context: AuthenticatedOperationCommandContextV0,
        responseMessageID: WireUUID
    ) async throws -> Data {
        throw NetworkHostClassifiedPrimaryTestErrorV0.unused
    }
}

private struct NetworkHostClassifiedPrimaryUnusedCapabilitiesV0:
    AuthenticatedCapabilityRegistryDispatchingV1
{
    func dispatch(
        requestJSON: Data,
        principal: AuthenticatedDevicePrincipal,
        responseMessageID: WireUUID,
        sentAtUnixMilliseconds: Int64
    ) async throws -> Data {
        throw NetworkHostClassifiedPrimaryTestErrorV0.unused
    }
}

private actor NetworkHostClassifiedPrimaryUnusedInteractiveV0:
    AuthenticatedInteractiveWireDispatchingV0
{
    func dispatch(
        requestJSON: Data,
        context: AuthenticatedInteractiveCommandContextV0,
        responseMessageID: WireUUID
    ) async throws -> Data {
        throw NetworkHostClassifiedPrimaryTestErrorV0.unused
    }

    func primarySessionClosed() async {}
}

private final class NetworkHostClassifiedPrimaryIOV0:
    NetworkHostIngressFrameIOV0,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var continuation: CheckedContinuation<
        NetworkHostIngressFrameChunkV0,
        Error
    >?
    private var maximumLength: Int?
    private var sentStorage: [Data] = []
    private var cancelCountStorage = 0

    var sent: [Data] { lock.withLock { sentStorage } }
    var hasPendingReceive: Bool { lock.withLock { continuation != nil } }
    var cancelCount: Int { lock.withLock { cancelCountStorage } }

    func receive(maximumLength: Int) async throws
        -> NetworkHostIngressFrameChunkV0
    {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                self.continuation = continuation
                self.maximumLength = maximumLength
            }
        }
    }

    func send(_ data: Data) async throws {
        lock.withLock { sentStorage.append(data) }
    }

    func cancel() {
        let continuation = lock.withLock { () -> CheckedContinuation<
            NetworkHostIngressFrameChunkV0,
            Error
        >? in
            cancelCountStorage += 1
            let value = self.continuation
            self.continuation = nil
            maximumLength = nil
            return value
        }
        continuation?.resume(
            throwing: NetworkHostClassifiedPrimaryTestErrorV0.cancelled
        )
    }

    func push(_ data: Data) throws {
        let pair = lock.withLock { () -> (
            CheckedContinuation<NetworkHostIngressFrameChunkV0, Error>?,
            Int?
        ) in
            let continuation = self.continuation
            let maximumLength = self.maximumLength
            self.continuation = nil
            self.maximumLength = nil
            return (continuation, maximumLength)
        }
        guard let continuation = pair.0,
              let maximumLength = pair.1,
              data.count <= maximumLength else {
            throw NetworkHostClassifiedPrimaryTestErrorV0.noPendingReceive
        }
        continuation.resume(returning: .init(
            data: data,
            isComplete: false
        ))
    }
}

private final class NetworkHostClassifiedPrimaryContextV0:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var callCount = 0

    func snapshot() -> NetworkHostRequestContextV0 {
        lock.withLock {
            defer { callCount += 1 }
            return NetworkHostRequestContextV0(
                hostState: .userSessionActive,
                wallNowUnixMilliseconds: Int64(4_001 + callCount),
                monotonicNowMilliseconds: UInt64(100 + callCount),
                responseMessageID: WireUUID(UUID())
            )
        }
    }
}

private actor NetworkHostClassifiedPrimaryActivationRecorderV0 {
    private(set) var activated = false

    func mark() { activated = true }
}

private func networkHostClassifiedPrimaryEventuallyV0(
    _ condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    for _ in 0..<2_000 {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return false
}

private func networkHostClassifiedPrimaryPayloadV0(_ data: Data) throws
    -> Data
{
    var decoder = LengthPrefixedFrameDecoder()
    let frames = try decoder.append(data)
    guard frames.count == 1 else {
        throw NetworkHostClassifiedPrimaryTestErrorV0.unused
    }
    return frames[0]
}

@Test func classifiedPrimaryPublishesActivationOnlyAfterValidProof()
    async throws
{
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "maccompanion-classified-primary-\(UUID())",
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try SQLiteSecurityStore(
        path: directory.appendingPathComponent("security.sqlite3").path
    )
    let hostID = UUID()
    let pairingID = UUID()
    let deviceID = UUID()
    let clientID = UUID()
    let clientKey = P256.Signing.PrivateKey()
    let approvalKey = P256.Signing.PrivateKey()
    try await store.commitPairing(
        pairingID: pairingID,
        record: try StoredDeviceRecord(
            deviceID: deviceID,
            clientID: clientID,
            sessionPublicKeyX963: clientKey.publicKey.x963Representation,
            approvalPublicKeyX963:
                approvalKey.publicKey.x963Representation,
            authorization: DeviceAuthorization(
                state: .activeMonitorOnly,
                authorizationEpoch: .init(rawValue: 1),
                grantRevision: .init(rawValue: 1)
            ),
            policyRevision: .init(rawValue: 1),
            createdAtUnixMilliseconds: 1,
            updatedAtUnixMilliseconds: 1
        )
    )
    let hostKey = P256.Signing.PrivateKey()
    let spki = try CompanionSecurityV0.p256SubjectPublicKeyInfoDER(
        publicKeyX963: hostKey.publicKey.x963Representation
    )
    let fingerprint = try CompanionSecurityV0.hostFingerprint(
        subjectPublicKeyInfoDER: spki
    )
    let binding = try HostApplicationTLSBinding(
        evidence: HostTLSListenerEvidence(
            negotiatedTLSMajor: 1,
            negotiatedTLSMinor: 3,
            earlyDataAccepted: false,
            servedSubjectPublicKeyInfoDER: spki
        ),
        requiredHostFingerprint: fingerprint
    )
    let session = try AuthenticatedPrimarySessionV0(
        hostID: hostID,
        tlsBinding: binding,
        acceptedAtMonotonicMilliseconds: 0,
        authentication: ApplicationAuthenticationAuthority(
            deviceReader: store
        ),
        status: NetworkHostClassifiedPrimaryUnusedStatusV0(),
        operations: NetworkHostClassifiedPrimaryUnusedOperationsV0(),
        capabilities: NetworkHostClassifiedPrimaryUnusedCapabilitiesV0(),
        interactive: NetworkHostClassifiedPrimaryUnusedInteractiveV0()
    )
    let clientNonce = Data((0x10...0x2f).map(UInt8.init))
    let hello = try WireCodec.encode(WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 4_000,
        body: try AuthHelloBody(
            clientID: WireUUID(clientID),
            clientNonce: WireBytes32(clientNonce)
        )
    ))
    let io = NetworkHostClassifiedPrimaryIOV0()
    let classified = NetworkHostClassifiedConnectionV0(
        role: .applicationPrimary,
        tlsBinding: binding,
        io: io,
        initialFrame: hello
    )
    let context = NetworkHostClassifiedPrimaryContextV0()
    let pump = try NetworkHostPrimaryFramePumpV0(
        classifiedConnection: classified,
        session: session,
        context: context.snapshot
    )
    let activation = NetworkHostClassifiedPrimaryActivationRecorderV0()
    let task = Task {
        try await pump.beginOnClassifiedConnection()
        await activation.mark()
    }

    let challengeReady = await networkHostClassifiedPrimaryEventuallyV0 {
        io.sent.count == 1 && io.hasPendingReceive
    }
    #expect(challengeReady)
    #expect(!(await activation.activated))
    let challengeFrame = try #require(io.sent.first)
    let challengeData = try networkHostClassifiedPrimaryPayloadV0(
        challengeFrame
    )
    let challenge = try WireCodec.decode(
        WireEnvelope<AuthChallengeBody>.self,
        from: challengeData
    )
    let signingInput = try CompanionSecurityV0.authenticationSigningInput(
        clientID: clientID,
        connectionID: challenge.body.connectionID.rawValue,
        clientNonce: clientNonce,
        serverNonce: challenge.body.serverNonce.rawValue,
        hostFingerprint: fingerprint,
        selectedMajor: challenge.body.selectedVersion.major,
        selectedMinor: challenge.body.selectedVersion.minor
    )
    let proof = try WireCodec.encode(WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: challenge.messageID,
        sentAtUnixMilliseconds: 4_002,
        body: AuthProofBody(
            signature: try WireBytes64(
                clientKey.signature(for: signingInput).rawRepresentation
            )
        )
    ))
    try io.push(try LengthPrefixedFrameDecoder.encode(proof))
    try await task.value

    #expect(await activation.activated)
    #expect(await session.phase == .ready)
    let completedFrames = io.sent
    #expect(completedFrames.count == 2)
    let descriptionFrame = try #require(completedFrames.last)
    _ = try WireCodec.decode(
        WireEnvelope<SessionDescriptionBody>.self,
        from: networkHostClassifiedPrimaryPayloadV0(descriptionFrame)
    )
    await pump.cancel()
    #expect(io.cancelCount == 1)
}
