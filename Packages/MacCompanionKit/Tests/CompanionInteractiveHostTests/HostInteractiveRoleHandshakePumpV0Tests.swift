import CompanionDomain
@testable import CompanionInteractiveHost
import CompanionInteractiveWire
import CompanionWire
import Foundation
import Testing

private enum HostRolePumpTestErrorV0: Error {
    case noInput
    case oversizedRead
}

private final class HostRolePumpIOV0:
    HostInteractiveRoleHandshakeIOV0,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var incoming: [Data]
    private var sentStorage: [Data] = []
    private var requestedStorage: [Int] = []
    private var cancelCountStorage = 0

    init(incoming: [Data]) { self.incoming = incoming }

    func receive(maximumLength: Int) async throws
        -> HostInteractiveRoleReadChunkV0
    {
        try lock.withLock {
            requestedStorage.append(maximumLength)
            guard !incoming.isEmpty else {
                throw HostRolePumpTestErrorV0.noInput
            }
            let value = incoming.removeFirst()
            guard value.count <= maximumLength else {
                throw HostRolePumpTestErrorV0.oversizedRead
            }
            return HostInteractiveRoleReadChunkV0(data: value)
        }
    }

    func send(_ data: Data) async throws {
        lock.withLock { sentStorage.append(data) }
    }

    func cancel() {
        lock.withLock { cancelCountStorage += 1 }
    }

    var sent: [Data] { lock.withLock { sentStorage } }
    var requested: [Int] { lock.withLock { requestedStorage } }
    var cancelCount: Int { lock.withLock { cancelCountStorage } }
}

private final class HostRolePumpIDSourceV0: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [WireUUID]

    init(_ values: [WireUUID]) { self.values = values }

    func next() -> WireUUID {
        lock.withLock { values.removeFirst() }
    }
}

private actor HostRolePumpAuthenticatorV0:
    HostInteractiveChannelAuthenticatingV0
{
    private(set) var began: [InteractiveChannelHelloBody] = []
    private(set) var consumed: [InteractiveChannelProofBody] = []
    private(set) var invalidated: [(UUID, InteractiveChannelRoleName)] = []

    func beginInteractiveChannel(
        hello: InteractiveChannelHelloBody,
        hostNonce: WireBytes32,
        monotonicNowMilliseconds: UInt64
    ) async throws -> InteractiveChannelChallengeBody {
        began.append(hello)
        return InteractiveChannelChallengeBody(
            channelID: hello.channelID,
            role: hello.role,
            hostID: WireUUID(UUID(
                uuidString: "018f1000-0000-7000-8000-000000000001"
            )!),
            hostFingerprint: try WireFingerprint(
                Data(repeating: 0x44, count: 32)
            ),
            hostNonce: hostNonce
        )
    }

    func consumeInteractiveChannel(
        hello: InteractiveChannelHelloBody,
        proof: InteractiveChannelProofBody,
        monotonicNowMilliseconds: UInt64
    ) async throws -> InteractiveChannelAcceptedBody {
        consumed.append(proof)
        return InteractiveChannelAcceptedBody(
            channelID: hello.channelID,
            role: hello.role,
            serverProof: try WireBytes32(
                Data(repeating: 0x55, count: 32)
            )
        )
    }

    func invalidateInteractiveChannel(
        channelID: UUID,
        role: InteractiveChannelRoleName
    ) async {
        invalidated.append((channelID, role))
    }
}

private let hostRoleChannelID = WireUUID(UUID(
    uuidString: "018f8100-0000-7000-8000-000000000001"
)!)
private let hostRoleHelloID = WireUUID(UUID(
    uuidString: "018f8100-0000-7000-8000-000000000002"
)!)
private let hostRoleChallengeID = WireUUID(UUID(
    uuidString: "018f8100-0000-7000-8000-000000000003"
)!)
private let hostRoleProofID = WireUUID(UUID(
    uuidString: "018f8100-0000-7000-8000-000000000004"
)!)
private let hostRoleAcceptedID = WireUUID(UUID(
    uuidString: "018f8100-0000-7000-8000-000000000005"
)!)

private func hostRoleHello() throws
    -> InteractiveChannelEnvelope<InteractiveChannelHelloBody>
{
    try InteractiveChannelEnvelope(
        messageID: hostRoleHelloID,
        correlationID: nil,
        body: InteractiveChannelHelloBody(
            channelID: hostRoleChannelID,
            role: .media,
            clientID: WireUUID(UUID(
                uuidString: "018f8200-0000-7000-8000-000000000001"
            )!),
            primaryConnectionID: try WireBytes16(
                Data(repeating: 0x11, count: 16)
            ),
            interactiveSessionID: WireUUID(UUID(
                uuidString: "018f8300-0000-7000-8000-000000000001"
            )!),
            authorizationEpoch: .init(rawValue: 7),
            clientNonce: try WireBytes32(
                Data(repeating: 0x22, count: 32)
            )
        )
    )
}

private func hostRoleFrame(_ body: Data) -> Data {
    let length = UInt32(body.count)
    return Data([
        UInt8(length >> 24),
        UInt8((length >> 16) & 0xff),
        UInt8((length >> 8) & 0xff),
        UInt8(length & 0xff),
    ]) + body
}

private func hostRolePayload(_ frame: Data) -> Data {
    Data(frame.dropFirst(4))
}

@Test func hostRolePumpSendsAcceptedBeforeReadyHandoff() async throws {
    let hello = try hostRoleHello()
    let proof = try InteractiveChannelEnvelope(
        messageID: hostRoleProofID,
        correlationID: hostRoleChallengeID,
        body: InteractiveChannelProofBody(
            channelID: hostRoleChannelID,
            clientProof: try WireBytes32(
                Data(repeating: 0x33, count: 32)
            )
        )
    )
    let proofPayload = try InteractiveChannelCodec.encode(proof)
    let proofFrame = hostRoleFrame(proofPayload)
    let io = HostRolePumpIOV0(incoming: [
        Data(proofFrame.prefix(4)),
        Data(proofFrame.dropFirst(4)),
    ])
    let authenticator = HostRolePumpAuthenticatorV0()
    let IDs = HostRolePumpIDSourceV0([
        hostRoleChallengeID, hostRoleAcceptedID,
    ])
    let pump = HostInteractiveRoleHandshakePumpV0(
        io: io,
        initialHelloFrame: try InteractiveChannelCodec.encode(hello),
        authenticator: authenticator,
        monotonicNowMilliseconds: { 1_000 },
        hostNonce: {
            try WireBytes32(Data(repeating: 0x66, count: 32))
        },
        messageID: { IDs.next() }
    )

    let ready = try await pump.beginOnClassifiedConnection()

    #expect(ready.channelID == hostRoleChannelID)
    #expect(ready.role == .media)
    #expect(await pump.phase == .ready)
    #expect(io.requested == [4, proofPayload.count])
    #expect(io.sent.count == 2)
    let challenge = try InteractiveChannelCodec.decode(
        InteractiveChannelEnvelope<
            InteractiveChannelChallengeBody
        >.self,
        from: hostRolePayload(io.sent[0])
    )
    #expect(challenge.messageID == hostRoleChallengeID)
    #expect(challenge.correlationID == hostRoleHelloID)
    let accepted = try InteractiveChannelCodec.decode(
        InteractiveChannelEnvelope<
            InteractiveChannelAcceptedBody
        >.self,
        from: hostRolePayload(io.sent[1])
    )
    #expect(accepted.messageID == hostRoleAcceptedID)
    #expect(accepted.correlationID == hostRoleProofID)
    #expect(await authenticator.began.count == 1)
    #expect(await authenticator.consumed.count == 1)
    #expect(await authenticator.invalidated.isEmpty)
    try await pump.admitRoleTraffic()
}

@Test func hostRolePumpCorrelationFailureInvalidatesAndCloses()
    async throws
{
    let hello = try hostRoleHello()
    let proof = try InteractiveChannelEnvelope(
        messageID: hostRoleProofID,
        correlationID: WireUUID(UUID()),
        body: InteractiveChannelProofBody(
            channelID: hostRoleChannelID,
            clientProof: try WireBytes32(
                Data(repeating: 0x33, count: 32)
            )
        )
    )
    let frame = hostRoleFrame(try InteractiveChannelCodec.encode(proof))
    let io = HostRolePumpIOV0(incoming: [
        Data(frame.prefix(4)), Data(frame.dropFirst(4)),
    ])
    let authenticator = HostRolePumpAuthenticatorV0()
    let IDs = HostRolePumpIDSourceV0([
        hostRoleChallengeID, hostRoleAcceptedID,
    ])
    let pump = HostInteractiveRoleHandshakePumpV0(
        io: io,
        initialHelloFrame: try InteractiveChannelCodec.encode(hello),
        authenticator: authenticator,
        monotonicNowMilliseconds: { 1_000 },
        hostNonce: {
            try WireBytes32(Data(repeating: 0x66, count: 32))
        },
        messageID: { IDs.next() }
    )

    await #expect(throws: (any Error).self) {
        try await pump.beginOnClassifiedConnection()
    }
    #expect(await pump.phase == .closed)
    #expect(io.cancelCount == 1)
    #expect(await authenticator.consumed.isEmpty)
    #expect(await authenticator.invalidated.count == 1)
}
