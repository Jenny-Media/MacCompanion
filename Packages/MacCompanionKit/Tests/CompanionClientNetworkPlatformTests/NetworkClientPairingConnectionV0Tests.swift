import CompanionClientApp
@testable import CompanionClientNetworkPlatform
import CompanionDiscovery
import CompanionTransport
import CompanionWire
import Dispatch
import Foundation
import Testing

private final class PairingFrameIOProbeV0:
    NetworkClientPairingFrameIOV0,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var receiveChunks: [NetworkClientPairingFrameChunkV0]
    private var sentStorage: [Data] = []
    private var cancelCountStorage = 0

    init(receiveChunks: [NetworkClientPairingFrameChunkV0] = []) {
        self.receiveChunks = receiveChunks
    }

    var sent: [Data] { lock.withLock { sentStorage } }
    var cancelCount: Int { lock.withLock { cancelCountStorage } }

    func send(_ data: Data) async throws {
        lock.withLock { sentStorage.append(data) }
    }

    func receive(maximumLength: Int) async throws
        -> NetworkClientPairingFrameChunkV0
    {
        #expect(
            maximumLength
                == NetworkClientPairingFrameChannelV0
                    .maximumReceiveChunkBytes
        )
        return lock.withLock {
            if receiveChunks.isEmpty {
                return .init(data: Data(), isComplete: true)
            }
            return receiveChunks.removeFirst()
        }
    }

    func cancel() {
        lock.withLock { cancelCountStorage += 1 }
    }
}

private actor PairingRouteAttemptProbeV0:
    NetworkClientPairingRouteAttemptingV0
{
    struct Attempt: Equatable, Sendable {
        let endpoint: EndpointCandidate
        let fingerprint: Data
        let timeoutMilliseconds: Int64
    }

    private let winningEndpoint: EndpointCandidate?
    private let candidate: NetworkClientPairingRouteCandidateV0?
    private var attemptsStorage: [Attempt] = []

    init(
        winningEndpoint: EndpointCandidate?,
        candidate: NetworkClientPairingRouteCandidateV0?
    ) {
        self.winningEndpoint = winningEndpoint
        self.candidate = candidate
    }

    func attempts() -> [Attempt] { attemptsStorage }

    func attempt(
        endpoint: EndpointCandidate,
        requiredHostFingerprint: Data,
        connectTimeoutMilliseconds: Int64
    ) async -> NetworkClientPairingRouteCandidateV0? {
        attemptsStorage.append(.init(
            endpoint: endpoint,
            fingerprint: requiredHostFingerprint,
            timeoutMilliseconds: connectTimeoutMilliseconds
        ))
        guard endpoint == winningEndpoint else { return nil }
        return candidate
    }
}

private actor PairingStaggerBarrierV0 {
    private let expectedCount: Int
    private var delaysStorage: [Int64] = []
    private var continuations: [CheckedContinuation<Void, Never>] = []

    init(expectedCount: Int) {
        self.expectedCount = expectedCount
    }

    func delays() -> [Int64] { delaysStorage }

    func wait(_ delay: Int64) async {
        delaysStorage.append(delay)
        guard delaysStorage.count < expectedCount else {
            let pending = continuations
            continuations.removeAll()
            pending.forEach { $0.resume() }
            return
        }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }
}

private actor PairingSuspendedAttemptProbeV0:
    NetworkClientPairingRouteAttemptingV0
{
    private var started = false
    private var cancelled = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var attemptContinuation:
        CheckedContinuation<NetworkClientPairingRouteCandidateV0?, Never>?

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func wasCancelled() -> Bool { cancelled }

    func attempt(
        endpoint: EndpointCandidate,
        requiredHostFingerprint: Data,
        connectTimeoutMilliseconds: Int64
    ) async -> NetworkClientPairingRouteCandidateV0? {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                attemptContinuation = continuation
            }
        } onCancel: {
            Task { await self.cancelAttempt() }
        }
    }

    private func cancelAttempt() {
        guard !cancelled else { return }
        cancelled = true
        let continuation = attemptContinuation
        attemptContinuation = nil
        continuation?.resume(returning: nil)
    }
}

private let pairingClockV0 = NetworkClientClockSnapshotV0(
    wallNowUnixMilliseconds: 1_000_000,
    monotonicNowMilliseconds: 1_000
)

private func pairingEndpointV0(
    _ kind: EndpointKind = .ipv4,
    value: String = "192.0.2.1"
) throws -> EndpointCandidate {
    try EndpointCandidate(kind: kind, value: value, port: 49_001)
}

private func pairingRequestV0(
    endpoints: [EndpointCandidate],
    expiresAt: Int64 = 1_010_000
) throws -> ClientPairingConnectionRequestV0 {
    try ClientPairingConnectionRequestV0(
        pairingID: UUID(uuidString: "00000000-0000-4000-8000-000000000101")!,
        requiredHostFingerprint: Data(repeating: 0xa5, count: 32),
        endpoints: endpoints,
        expiresAtUnixMilliseconds: expiresAt
    )
}

private func pairingCandidateV0(
    endpoint: EndpointCandidate,
    io: PairingFrameIOProbeV0
) -> NetworkClientPairingRouteCandidateV0 {
    NetworkClientPairingRouteCandidateV0(
        endpoint: endpoint,
        evidence: TLSPeerEvidence(
            negotiatedTLSMajor: 1,
            negotiatedTLSMinor: 3,
            earlyDataAccepted: false,
            pinnedLeafPolicyAccepted: true,
            subjectPublicKeyInfoDER: Data(repeating: 0x30, count: 91)
        ),
        channel: NetworkClientPairingFrameChannelV0(
            io: io,
            clock: { pairingClockV0 }
        )
    )
}

@Test func pairingConnectionRacesEveryRouteWithOneImmutablePin() async throws {
    let endpoints = [
        try pairingEndpointV0(),
        try pairingEndpointV0(.dns, value: "mac.example"),
        try pairingEndpointV0(.bonjour, value: "home._maccompanion._tcp.local."),
    ]
    let io = PairingFrameIOProbeV0()
    let probe = PairingRouteAttemptProbeV0(
        winningEndpoint: endpoints[1],
        candidate: pairingCandidateV0(endpoint: endpoints[1], io: io)
    )
    let barrier = PairingStaggerBarrierV0(expectedCount: endpoints.count)
    let request = try pairingRequestV0(endpoints: endpoints)
    let connection = NetworkClientPairingConnectionV0(
        request: request,
        attempter: probe,
        clock: { pairingClockV0 },
        wait: { delay in await barrier.wait(delay) }
    )

    try await connection.connectTCP()
    let evidence = try await connection.acceptPinnedTLS()

    #expect(evidence.negotiatedTLSMajor == 1)
    #expect(await barrier.delays().sorted() == [0, 250, 500])
    let attempts = await probe.attempts()
    #expect(Set(attempts.map(\.endpoint)) == Set(endpoints))
    #expect(
        attempts.allSatisfy {
            $0.fingerprint == request.requiredHostFingerprint
        }
    )
    #expect(
        attempts.map(\.timeoutMilliseconds).sorted()
            == [4_500, 4_750, 5_000]
    )

    await connection.close()
    #expect(io.cancelCount == 1)
}

@Test func pairingConnectionFramesTrafficAndFreezesOneDeadline() async throws {
    let endpoint = try pairingEndpointV0()
    let response = Data("pairing-response".utf8)
    let encodedResponse = try LengthPrefixedFrameDecoder.encode(response)
    let io = PairingFrameIOProbeV0(receiveChunks: [
        .init(data: encodedResponse.prefix(3), isComplete: false),
        .init(data: encodedResponse.dropFirst(3), isComplete: false),
    ])
    let probe = PairingRouteAttemptProbeV0(
        winningEndpoint: endpoint,
        candidate: pairingCandidateV0(endpoint: endpoint, io: io)
    )
    let connection = NetworkClientPairingConnectionV0(
        request: try pairingRequestV0(endpoints: [endpoint]),
        attempter: probe,
        clock: { pairingClockV0 },
        wait: { _ in }
    )

    try await connection.connectTCP()
    _ = try await connection.acceptPinnedTLS()
    let request = Data("pairing-request".utf8)
    try await connection.send(
        request,
        deadlineMonotonicMilliseconds: 10_000
    )
    #expect(
        try await connection.receive(
            deadlineMonotonicMilliseconds: 10_000
        ) == response
    )
    #expect(io.sent == [try LengthPrefixedFrameDecoder.encode(request)])

    await #expect(
        throws: NetworkClientPairingConnectionErrorV0.deadlineMismatch
    ) {
        try await connection.send(
            Data(),
            deadlineMonotonicMilliseconds: 10_001
        )
    }
    #expect(io.cancelCount == 1)
}

@Test func pairingConnectionMalformedFrameFailsClosed() async throws {
    let endpoint = try pairingEndpointV0()
    let io = PairingFrameIOProbeV0(receiveChunks: [
        .init(data: Data([0, 0, 0, 0]), isComplete: false),
    ])
    let probe = PairingRouteAttemptProbeV0(
        winningEndpoint: endpoint,
        candidate: pairingCandidateV0(endpoint: endpoint, io: io)
    )
    let connection = NetworkClientPairingConnectionV0(
        request: try pairingRequestV0(endpoints: [endpoint]),
        attempter: probe,
        clock: { pairingClockV0 },
        wait: { _ in }
    )

    try await connection.connectTCP()
    _ = try await connection.acceptPinnedTLS()
    await #expect(
        throws: NetworkClientPairingConnectionErrorV0.protocolFailure
    ) {
        try await connection.receive(
            deadlineMonotonicMilliseconds: 10_000
        )
    }
    #expect(io.cancelCount == 1)
    await #expect(
        throws: NetworkClientPairingConnectionErrorV0.invalidPhase
    ) {
        try await connection.receive(
            deadlineMonotonicMilliseconds: 10_000
        )
    }
}

@Test func pairingConnectionExpiredQRStartsNoRouteAttempt() async throws {
    let endpoint = try pairingEndpointV0()
    let probe = PairingRouteAttemptProbeV0(
        winningEndpoint: nil,
        candidate: nil
    )
    let connection = NetworkClientPairingConnectionV0(
        request: try pairingRequestV0(
            endpoints: [endpoint],
            expiresAt: pairingClockV0.wallNowUnixMilliseconds
        ),
        attempter: probe,
        clock: { pairingClockV0 },
        wait: { _ in }
    )

    await #expect(throws: NetworkClientPairingConnectionErrorV0.expired) {
        try await connection.connectTCP()
    }
    #expect(await probe.attempts().isEmpty)
}

@Test func pairingConnectionExpiredDeadlinePerformsNoWrite() async throws {
    let endpoint = try pairingEndpointV0()
    let io = PairingFrameIOProbeV0()
    let probe = PairingRouteAttemptProbeV0(
        winningEndpoint: endpoint,
        candidate: pairingCandidateV0(endpoint: endpoint, io: io)
    )
    let connection = NetworkClientPairingConnectionV0(
        request: try pairingRequestV0(endpoints: [endpoint]),
        attempter: probe,
        clock: { pairingClockV0 },
        wait: { _ in }
    )

    try await connection.connectTCP()
    _ = try await connection.acceptPinnedTLS()
    await #expect(
        throws: NetworkClientPairingConnectionErrorV0.deadlineExpired
    ) {
        try await connection.send(
            Data("must-not-send".utf8),
            deadlineMonotonicMilliseconds:
                pairingClockV0.monotonicNowMilliseconds
        )
    }
    #expect(io.sent.isEmpty)
    #expect(io.cancelCount == 1)
}

@Test func pairingFactoryConstructionStartsNoNetworkActivity() async throws {
    let endpoint = try pairingEndpointV0()
    let request = try pairingRequestV0(endpoints: [endpoint])
    let factory = NetworkClientPairingConnectionFactoryV0(
        pinnedLeafEvaluator: { _ in
            Issue.record("Trust evaluation must not run during construction")
            return Data()
        },
        verificationQueue: DispatchQueue(
            label: "MacCompanionTests.PairingVerification"
        ),
        connectionQueue: DispatchQueue(
            label: "MacCompanionTests.PairingConnection"
        ),
        clock: { pairingClockV0 }
    )

    let connection = try await factory.makeConnection(request)
    await connection.close()
}

@Test func pairingConnectionCloseCancelsSuspendedRouteRace() async throws {
    let endpoint = try pairingEndpointV0()
    let probe = PairingSuspendedAttemptProbeV0()
    let connection = NetworkClientPairingConnectionV0(
        request: try pairingRequestV0(endpoints: [endpoint]),
        attempter: probe,
        clock: { pairingClockV0 },
        wait: { _ in }
    )
    let connect = Task { try await connection.connectTCP() }
    await probe.waitUntilStarted()

    await connection.close()

    await #expect(
        throws: NetworkClientPairingConnectionErrorV0.invalidPhase
    ) {
        try await connect.value
    }
    #expect(await probe.wasCancelled())
}
