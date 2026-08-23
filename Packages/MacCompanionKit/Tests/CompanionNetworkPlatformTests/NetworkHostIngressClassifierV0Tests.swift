import CompanionInteractiveWire
import CompanionSecurity
import CompanionTestSupport
import CompanionTransport
import CompanionWire
import CryptoKit
import Foundation
@testable import CompanionNetworkPlatform
import Testing

private enum NetworkHostIngressClassifierTestErrorV0: Error {
    case noChunk
    case oversizedRead
}

private final class NetworkHostIngressClassifierFakeIOV0:
    NetworkHostIngressFrameIOV0,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var chunks: [NetworkHostIngressFrameChunkV0]
    private var requestedStorage: [Int] = []
    private var cancelCountStorage = 0
    private var sentStorage: [Data] = []

    init(chunks: [NetworkHostIngressFrameChunkV0]) {
        self.chunks = chunks
    }

    var requested: [Int] { lock.withLock { requestedStorage } }
    var remainingChunks: Int { lock.withLock { chunks.count } }
    var cancelCount: Int { lock.withLock { cancelCountStorage } }

    func receive(maximumLength: Int) async throws
        -> NetworkHostIngressFrameChunkV0
    {
        try lock.withLock {
            requestedStorage.append(maximumLength)
            guard !chunks.isEmpty else {
                throw NetworkHostIngressClassifierTestErrorV0.noChunk
            }
            let chunk = chunks.removeFirst()
            guard chunk.data.count <= maximumLength else {
                throw NetworkHostIngressClassifierTestErrorV0.oversizedRead
            }
            return chunk
        }
    }

    func send(_ data: Data) async throws {
        lock.withLock { sentStorage.append(data) }
    }

    func cancel() {
        lock.withLock { cancelCountStorage += 1 }
    }
}

private final class NetworkHostIngressClassifierClockV0:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var values: [UInt64]
    private let fallback: UInt64

    init(_ values: [UInt64], fallback: UInt64? = nil) {
        self.values = values
        self.fallback = fallback ?? values.last ?? 0
    }

    func now() -> UInt64 {
        lock.withLock {
            guard !values.isEmpty else { return fallback }
            return values.removeFirst()
        }
    }
}

private func networkHostIngressClassifierBindingV0() throws
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

private func networkHostIngressFixtureV0(_ name: String) throws -> Data {
    try Data(
        contentsOf: FixturePaths.authoritativeFixtures()
            .appendingPathComponent("valid/\(name).json")
    )
}

private func networkHostIngressPrefixV0(_ count: Int) -> Data {
    let value = UInt32(count)
    return Data([
        UInt8((value >> 24) & 0xff),
        UInt8((value >> 16) & 0xff),
        UInt8((value >> 8) & 0xff),
        UInt8(value & 0xff),
    ])
}

@Test func hostIngressClassifiesAuthoritativePairingWithoutSecondFrameRead()
    async throws
{
    let pairing = try networkHostIngressFixtureV0("pairing-begin")
    let second = try networkHostIngressFixtureV0("auth-hello")
    let prefix = networkHostIngressPrefixV0(pairing.count)
    let io = NetworkHostIngressClassifierFakeIOV0(chunks: [
        .init(data: prefix.prefix(2), isComplete: false),
        .init(data: prefix.suffix(2), isComplete: false),
        .init(data: pairing, isComplete: false),
        .init(data: second, isComplete: false),
    ])
    let binding = try networkHostIngressClassifierBindingV0()
    let classifier = try NetworkHostIngressClassifierV0(
        io: io,
        tlsBinding: binding,
        acceptedAtMonotonicMilliseconds: 100,
        monotonicNowMilliseconds: { 100 }
    )

    let classified = try await classifier.classify()
    #expect(classified.role == .pairing)
    #expect(classified.tlsBinding == binding)
    #expect(io.requested == [4, 2, pairing.count])
    #expect(io.remainingChunks == 1)
    #expect(io.cancelCount == 0)

    let consumed = try classified.consume(expectedRole: .pairing)
    #expect(consumed.initialFrame == pairing)
    #expect(throws: NetworkHostIngressClassifierErrorV0
        .classifiedConnectionAlreadyConsumed) {
        try classified.consume(expectedRole: .pairing)
    }
    consumed.io.cancel()
    #expect(io.cancelCount == 1)
}

@Test func hostIngressClassifiesAuthoritativeAuthentication() async throws {
    let hello = try networkHostIngressFixtureV0("auth-hello")
    let io = NetworkHostIngressClassifierFakeIOV0(chunks: [
        .init(
            data: networkHostIngressPrefixV0(hello.count),
            isComplete: false
        ),
        .init(data: hello, isComplete: false),
    ])
    let classifier = try NetworkHostIngressClassifierV0(
        io: io,
        tlsBinding: try networkHostIngressClassifierBindingV0(),
        acceptedAtMonotonicMilliseconds: 1,
        monotonicNowMilliseconds: { 1 }
    )

    let classified = try await classifier.classify()
    #expect(classified.role == .applicationPrimary)
    #expect(throws: NetworkHostIngressClassifierErrorV0.roleMismatch) {
        try classified.consume(expectedRole: .pairing)
    }
    classified.cancel()
    #expect(io.cancelCount == 1)
}

@Test func hostIngressClassifiesStrictInteractiveHelloByBodyRole()
    async throws
{
    let hello = try networkHostIngressFixtureV0(
        "interactive-channel-hello"
    )
    let decoded = try InteractiveChannelCodec.decode(
        InteractiveChannelEnvelope<InteractiveChannelHelloBody>.self,
        from: hello
    )
    let io = NetworkHostIngressClassifierFakeIOV0(chunks: [
        .init(
            data: networkHostIngressPrefixV0(hello.count),
            isComplete: false
        ),
        .init(data: hello, isComplete: false),
    ])
    let classifier = try NetworkHostIngressClassifierV0(
        io: io,
        tlsBinding: try networkHostIngressClassifierBindingV0(),
        acceptedAtMonotonicMilliseconds: 1,
        monotonicNowMilliseconds: { 1 }
    )

    let classified = try await classifier.classify()
    let expected: NetworkHostIngressRoleV0 = switch decoded.body.role {
    case .input: .interactiveInput
    case .media: .interactiveMedia
    }
    #expect(classified.role == expected)
    #expect(io.requested == [4, hello.count])
    let consumed = try classified.consume(expectedRole: expected)
    #expect(consumed.initialFrame == hello)
    consumed.io.cancel()
}

@Test func hostIngressRejectsARegisteredNonIngressKindAndCloses() async throws {
    let request = try WireCodec.encode(WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 1,
        body: StatusSnapshotRequestBody()
    ))
    let io = NetworkHostIngressClassifierFakeIOV0(chunks: [
        .init(
            data: networkHostIngressPrefixV0(request.count),
            isComplete: false
        ),
        .init(data: request, isComplete: false),
    ])
    let classifier = try NetworkHostIngressClassifierV0(
        io: io,
        tlsBinding: try networkHostIngressClassifierBindingV0(),
        acceptedAtMonotonicMilliseconds: 10,
        monotonicNowMilliseconds: { 10 }
    )

    await #expect(throws: NetworkHostIngressClassifierErrorV0
        .unexpectedFirstMessage(.statusSnapshotRequest)) {
        try await classifier.classify()
    }
    #expect(io.cancelCount == 1)
}

@Test func hostIngressRejectsInvalidLengthAndRemoteTruncation() async throws {
    let binding = try networkHostIngressClassifierBindingV0()
    let zeroIO = NetworkHostIngressClassifierFakeIOV0(chunks: [
        .init(data: Data(repeating: 0, count: 4), isComplete: false),
    ])
    let zero = try NetworkHostIngressClassifierV0(
        io: zeroIO,
        tlsBinding: binding,
        acceptedAtMonotonicMilliseconds: 1,
        monotonicNowMilliseconds: { 1 }
    )
    await #expect(throws: NetworkHostIngressClassifierErrorV0
        .protocolFailure) {
        try await zero.classify()
    }
    #expect(zeroIO.cancelCount == 1)

    let truncatedIO = NetworkHostIngressClassifierFakeIOV0(chunks: [
        .init(data: networkHostIngressPrefixV0(10), isComplete: false),
        .init(data: Data(repeating: 1, count: 5), isComplete: true),
    ])
    let truncated = try NetworkHostIngressClassifierV0(
        io: truncatedIO,
        tlsBinding: binding,
        acceptedAtMonotonicMilliseconds: 1,
        monotonicNowMilliseconds: { 1 }
    )
    await #expect(throws: NetworkHostIngressClassifierErrorV0.remoteClosed) {
        try await truncated.classify()
    }
    #expect(truncatedIO.cancelCount == 1)
}

@Test func hostIngressClosesOnDeadlineAndClockRegressionBeforeReading()
    async throws
{
    let binding = try networkHostIngressClassifierBindingV0()
    let deadlineIO = NetworkHostIngressClassifierFakeIOV0(chunks: [])
    let deadline = try NetworkHostIngressClassifierV0(
        io: deadlineIO,
        tlsBinding: binding,
        acceptedAtMonotonicMilliseconds: 100,
        maximumClassificationMilliseconds: 10,
        monotonicNowMilliseconds: { 110 }
    )
    await #expect(throws: NetworkHostIngressClassifierErrorV0
        .deadlineExpired) {
        try await deadline.classify()
    }
    #expect(deadlineIO.requested.isEmpty)
    #expect(deadlineIO.cancelCount == 1)

    let regressedIO = NetworkHostIngressClassifierFakeIOV0(chunks: [])
    let clock = NetworkHostIngressClassifierClockV0([100, 99])
    let regressed = try NetworkHostIngressClassifierV0(
        io: regressedIO,
        tlsBinding: binding,
        acceptedAtMonotonicMilliseconds: 100,
        monotonicNowMilliseconds: clock.now
    )
    await #expect(throws: NetworkHostIngressClassifierErrorV0.invalidClock) {
        try await regressed.classify()
    }
    #expect(regressedIO.requested.isEmpty)
    #expect(regressedIO.cancelCount == 1)
}
