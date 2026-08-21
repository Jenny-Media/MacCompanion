import CompanionSecurity
import CompanionTestSupport
import CompanionTransport
import CompanionWire
import CryptoKit
import Foundation
@testable import CompanionNetworkPlatform
import Testing

private enum NetworkHostPairingPumpTestErrorV0: Error {
    case cancelled
    case receiveAlreadyPending
    case sendFailed
    case exhaustedPlan
}

private final class NetworkHostPairingPumpFakeIOV0:
    NetworkHostIngressFrameIOV0,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var receiveContinuation: CheckedContinuation<
        NetworkHostIngressFrameChunkV0,
        Error
    >?
    private var maximumLengthStorage: Int?
    private var sentStorage: [Data] = []
    private var cancelCountStorage = 0
    private var failSendStorage = false

    var sent: [Data] { lock.withLock { sentStorage } }
    var hasPendingReceive: Bool {
        lock.withLock { receiveContinuation != nil }
    }
    var cancelCount: Int { lock.withLock { cancelCountStorage } }

    func failSends() {
        lock.withLock { failSendStorage = true }
    }

    func receive(maximumLength: Int) async throws
        -> NetworkHostIngressFrameChunkV0
    {
        try await withCheckedThrowingContinuation { continuation in
            let installed = lock.withLock { () -> Bool in
                guard receiveContinuation == nil else { return false }
                receiveContinuation = continuation
                maximumLengthStorage = maximumLength
                return true
            }
            if !installed {
                continuation.resume(
                    throwing:
                        NetworkHostPairingPumpTestErrorV0
                            .receiveAlreadyPending
                )
            }
        }
    }

    func send(_ data: Data) async throws {
        try lock.withLock {
            if failSendStorage {
                throw NetworkHostPairingPumpTestErrorV0.sendFailed
            }
            sentStorage.append(data)
        }
    }

    func cancel() {
        let continuation = lock.withLock { () -> CheckedContinuation<
            NetworkHostIngressFrameChunkV0,
            Error
        >? in
            cancelCountStorage += 1
            let continuation = receiveContinuation
            receiveContinuation = nil
            maximumLengthStorage = nil
            return continuation
        }
        continuation?.resume(
            throwing: NetworkHostPairingPumpTestErrorV0.cancelled
        )
    }

    func push(_ data: Data, isComplete: Bool = false) throws {
        let pair = lock.withLock { () -> (
            CheckedContinuation<NetworkHostIngressFrameChunkV0, Error>?,
            Int?
        ) in
            let continuation = receiveContinuation
            let maximumLength = maximumLengthStorage
            receiveContinuation = nil
            maximumLengthStorage = nil
            return (continuation, maximumLength)
        }
        guard let continuation = pair.0,
              let maximumLength = pair.1,
              data.count <= maximumLength else {
            throw NetworkHostPairingPumpTestErrorV0.exhaustedPlan
        }
        continuation.resume(returning: .init(
            data: data,
            isComplete: isComplete
        ))
    }
}

private actor NetworkHostPairingPumpFakeSessionV0:
    NetworkHostPairingSessionHandlingV0
{
    struct Plan: Sendable {
        let expectedRequest: Data
        let response: NetworkHostPairingSessionResponseV0
        let nextDeadline: UInt64?
    }

    private var plans: [Plan]
    private var completions: [Data?]
    private var deadline: UInt64?
    private var receivedStorage: [Data] = []
    private var completionCheckCountStorage = 0
    private var cancelCountStorage = 0

    init(
        plans: [Plan],
        completions: [Data?] = [],
        initialDeadline: UInt64? = 1_000
    ) {
        self.plans = plans
        self.completions = completions
        deadline = initialDeadline
    }

    func receivePairingRequest(
        requestJSON: Data,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64,
        responseMessageID: WireUUID
    ) throws -> NetworkHostPairingSessionResponseV0 {
        receivedStorage.append(requestJSON)
        guard !plans.isEmpty else {
            throw NetworkHostPairingPumpTestErrorV0.exhaustedPlan
        }
        let plan = plans.removeFirst()
        guard plan.expectedRequest == requestJSON else {
            throw NetworkHostPairingPumpTestErrorV0.exhaustedPlan
        }
        deadline = plan.nextDeadline
        return plan.response
    }

    func takePairingCompletionIfAvailable(
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64,
        responseMessageID: WireUUID
    ) throws -> Data? {
        completionCheckCountStorage += 1
        guard !completions.isEmpty else { return nil }
        return completions.removeFirst()
    }

    func nextPairingDeadlineMonotonicMilliseconds() -> UInt64? {
        deadline
    }

    func cancelPairing(at monotonicNowMilliseconds: UInt64) {
        cancelCountStorage += 1
    }

    func received() -> [Data] { receivedStorage }
    func completionChecks() -> Int { completionCheckCountStorage }
    func cancelCount() -> Int { cancelCountStorage }
}

private final class NetworkHostPairingPumpContextV0:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var monotonicStorage: UInt64

    init(monotonic: UInt64) {
        monotonicStorage = monotonic
    }

    var monotonic: UInt64 {
        get { lock.withLock { monotonicStorage } }
        set { lock.withLock { monotonicStorage = newValue } }
    }

    func snapshot() -> NetworkHostPairingRequestContextV0 {
        NetworkHostPairingRequestContextV0(
            wallNowUnixMilliseconds: 1,
            monotonicNowMilliseconds: monotonic,
            responseMessageID: WireUUID(UUID())
        )
    }
}

private final class NetworkHostPairingPumpTerminalRecorderV0:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var values: [NetworkHostPairingTerminationReasonV0] = []

    var reasons: [NetworkHostPairingTerminationReasonV0] {
        lock.withLock { values }
    }

    func record(_ reason: NetworkHostPairingTerminationReasonV0) {
        lock.withLock { values.append(reason) }
    }
}

private func networkHostPairingPumpClassifiedV0(
    io: any NetworkHostIngressFrameIOV0,
    initialFrame: Data
) throws -> NetworkHostClassifiedConnectionV0 {
    NetworkHostClassifiedConnectionV0(
        role: .pairing,
        tlsBinding: try networkHostIngressClassifierBindingForPumpV0(),
        io: io,
        initialFrame: initialFrame
    )
}

private func networkHostIngressClassifierBindingForPumpV0() throws
    -> HostApplicationTLSBinding
{
    let key = P256.Signing.PrivateKey()
    let spki = try CompanionSecurityV0.p256SubjectPublicKeyInfoDER(
        publicKeyX963: key.publicKey.x963Representation
    )
    let fingerprint = try CompanionSecurityV0.hostFingerprint(
        subjectPublicKeyInfoDER: spki
    )
    return try HostApplicationTLSBinding(
        evidence: HostTLSListenerEvidence(
            negotiatedTLSMajor: 1,
            negotiatedTLSMinor: 3,
            earlyDataAccepted: false,
            servedSubjectPublicKeyInfoDER: spki
        ),
        requiredHostFingerprint: fingerprint
    )
}

private func networkHostPairingPumpFixtureV0(_ name: String) throws -> Data {
    try Data(
        contentsOf: FixturePaths.authoritativeFixtures()
            .appendingPathComponent("valid/\(name).json")
    )
}

private func networkHostPairingPumpPayloadV0(_ framed: Data) throws -> Data {
    var decoder = LengthPrefixedFrameDecoder()
    let frames = try decoder.append(framed)
    guard frames.count == 1 else {
        throw NetworkHostPairingPumpTestErrorV0.exhaustedPlan
    }
    return frames[0]
}

private func networkHostPairingPumpEventuallyV0(
    _ condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    for _ in 0..<2_000 {
        if await condition() { return true }
        await Task.yield()
    }
    return false
}

@Test func hostPairingPumpReplaysFirstFrameBeforeReadingProve() async throws {
    let begin = try networkHostPairingPumpFixtureV0("pairing-begin")
    let prove = try networkHostPairingPumpFixtureV0("pairing-prove")
    let challenge = try networkHostPairingPumpFixtureV0("pairing-challenge")
    let pending = try networkHostPairingPumpFixtureV0(
        "pairing-pending-approval"
    )
    let io = NetworkHostPairingPumpFakeIOV0()
    let session = NetworkHostPairingPumpFakeSessionV0(plans: [
        .init(
            expectedRequest: begin,
            response: .init(frame: challenge, disposition: .awaitPeer),
            nextDeadline: 1_000
        ),
        .init(
            expectedRequest: prove,
            response: .init(
                frame: pending,
                disposition: .awaitLocalDecision
            ),
            nextDeadline: 1_000
        ),
    ])
    let context = NetworkHostPairingPumpContextV0(monotonic: 100)
    let pump = try NetworkHostPairingFramePumpV0(
        classifiedConnection: try networkHostPairingPumpClassifiedV0(
            io: io,
            initialFrame: begin
        ),
        session: session,
        context: context.snapshot,
        pollMilliseconds: 10
    )

    try await pump.beginOnClassifiedConnection()
    #expect(await session.received() == [begin])
    #expect(try networkHostPairingPumpPayloadV0(io.sent[0]) == challenge)
    #expect(await networkHostPairingPumpEventuallyV0 {
        io.hasPendingReceive
    })

    try io.push(try LengthPrefixedFrameDecoder.encode(prove))
    #expect(await networkHostPairingPumpEventuallyV0 {
        await session.received().count == 2 && io.sent.count == 2
    })
    #expect(await session.received() == [begin, prove])
    #expect(try networkHostPairingPumpPayloadV0(io.sent[1]) == pending)
    await pump.cancel()
}

@Test func hostPairingPumpSendsSilentDurableCompletionAndCloses()
    async throws
{
    let begin = try networkHostPairingPumpFixtureV0("pairing-begin")
    let prove = try networkHostPairingPumpFixtureV0("pairing-prove")
    let challenge = try networkHostPairingPumpFixtureV0("pairing-challenge")
    let pending = try networkHostPairingPumpFixtureV0(
        "pairing-pending-approval"
    )
    let complete = try networkHostPairingPumpFixtureV0("pairing-complete")
    let io = NetworkHostPairingPumpFakeIOV0()
    let session = NetworkHostPairingPumpFakeSessionV0(
        plans: [
            .init(
                expectedRequest: begin,
                response: .init(frame: challenge, disposition: .awaitPeer),
                nextDeadline: 1_000
            ),
            .init(
                expectedRequest: prove,
                response: .init(
                    frame: pending,
                    disposition: .awaitLocalDecision
                ),
                nextDeadline: 100
            ),
        ],
        completions: [complete]
    )
    let context = NetworkHostPairingPumpContextV0(monotonic: 100)
    let terminals = NetworkHostPairingPumpTerminalRecorderV0()
    let pump = try NetworkHostPairingFramePumpV0(
        classifiedConnection: try networkHostPairingPumpClassifiedV0(
            io: io,
            initialFrame: begin
        ),
        session: session,
        context: context.snapshot,
        pollMilliseconds: 1,
        terminal: terminals.record
    )

    try await pump.beginOnClassifiedConnection()
    #expect(await networkHostPairingPumpEventuallyV0 { io.hasPendingReceive })
    try io.push(try LengthPrefixedFrameDecoder.encode(prove))
    #expect(await networkHostPairingPumpEventuallyV0 {
        io.sent.count == 3 && terminals.reasons == [.terminalResponseSent]
    })
    #expect(try networkHostPairingPumpPayloadV0(io.sent[2]) == complete)
    #expect(await session.completionChecks() == 1)
    #expect(await session.cancelCount() == 1)
    #expect(io.cancelCount == 1)
}

@Test func hostPairingPumpExpiresSilentPeerWithoutPollingLocalOutcome()
    async throws
{
    let begin = try networkHostPairingPumpFixtureV0("pairing-begin")
    let challenge = try networkHostPairingPumpFixtureV0("pairing-challenge")
    let io = NetworkHostPairingPumpFakeIOV0()
    let session = NetworkHostPairingPumpFakeSessionV0(
        plans: [
            .init(
                expectedRequest: begin,
                response: .init(frame: challenge, disposition: .awaitPeer),
                nextDeadline: 100
            ),
        ],
        initialDeadline: 100
    )
    let context = NetworkHostPairingPumpContextV0(monotonic: 100)
    let terminals = NetworkHostPairingPumpTerminalRecorderV0()
    let pump = try NetworkHostPairingFramePumpV0(
        classifiedConnection: try networkHostPairingPumpClassifiedV0(
            io: io,
            initialFrame: begin
        ),
        session: session,
        context: context.snapshot,
        pollMilliseconds: 1,
        terminal: terminals.record
    )

    try await pump.beginOnClassifiedConnection()
    #expect(await networkHostPairingPumpEventuallyV0 {
        terminals.reasons == [.sessionDeadline]
    })
    #expect(await session.completionChecks() == 0)
    #expect(await session.cancelCount() == 1)
}

@Test func hostPairingPumpFailsClosedOnMalformedSecondFrame() async throws {
    let begin = try networkHostPairingPumpFixtureV0("pairing-begin")
    let challenge = try networkHostPairingPumpFixtureV0("pairing-challenge")
    let io = NetworkHostPairingPumpFakeIOV0()
    let session = NetworkHostPairingPumpFakeSessionV0(plans: [
        .init(
            expectedRequest: begin,
            response: .init(frame: challenge, disposition: .awaitPeer),
            nextDeadline: 1_000
        ),
    ])
    let context = NetworkHostPairingPumpContextV0(monotonic: 100)
    let terminals = NetworkHostPairingPumpTerminalRecorderV0()
    let pump = try NetworkHostPairingFramePumpV0(
        classifiedConnection: try networkHostPairingPumpClassifiedV0(
            io: io,
            initialFrame: begin
        ),
        session: session,
        context: context.snapshot,
        pollMilliseconds: 1,
        terminal: terminals.record
    )

    try await pump.beginOnClassifiedConnection()
    #expect(await networkHostPairingPumpEventuallyV0 { io.hasPendingReceive })
    try io.push(Data([0, 0, 0, 0]))
    #expect(await networkHostPairingPumpEventuallyV0 {
        terminals.reasons == [.protocolOrSessionFailure]
    })
    #expect(await session.cancelCount() == 1)
}

@Test func hostPairingPumpClosesWhenInitialResponseCannotBeSent() async throws {
    let begin = try networkHostPairingPumpFixtureV0("pairing-begin")
    let challenge = try networkHostPairingPumpFixtureV0("pairing-challenge")
    let io = NetworkHostPairingPumpFakeIOV0()
    io.failSends()
    let session = NetworkHostPairingPumpFakeSessionV0(plans: [
        .init(
            expectedRequest: begin,
            response: .init(frame: challenge, disposition: .awaitPeer),
            nextDeadline: 1_000
        ),
    ])
    let context = NetworkHostPairingPumpContextV0(monotonic: 100)
    let terminals = NetworkHostPairingPumpTerminalRecorderV0()
    let pump = try NetworkHostPairingFramePumpV0(
        classifiedConnection: try networkHostPairingPumpClassifiedV0(
            io: io,
            initialFrame: begin
        ),
        session: session,
        context: context.snapshot,
        pollMilliseconds: 1,
        terminal: terminals.record
    )

    await #expect(throws: NetworkHostPairingFramePumpErrorV0.sendFailed) {
        try await pump.beginOnClassifiedConnection()
    }
    #expect(terminals.reasons == [.sendFailed])
    #expect(await session.cancelCount() == 1)
    #expect(io.cancelCount == 1)
}
