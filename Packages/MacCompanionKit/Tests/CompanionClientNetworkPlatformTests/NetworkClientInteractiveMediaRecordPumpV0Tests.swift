import CompanionDiscovery
import CompanionInteractiveClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionWire
@testable import CompanionClientNetworkPlatform
import Foundation
import Testing

private actor MediaPumpTestIOV0 {
    private var bytes: Data
    private let terminalAtEnd: Bool
    private(set) var requests: [Int] = []
    private(set) var cancelled = false

    init(bytes: Data, terminalAtEnd: Bool = false) {
        self.bytes = bytes
        self.terminalAtEnd = terminalAtEnd
    }

    func receive(maximumLength: Int) -> ClientInteractiveRoleReadChunkV0 {
        requests.append(maximumLength)
        let count = min(maximumLength, 1, bytes.count)
        guard count > 0 else {
            return ClientInteractiveRoleReadChunkV0(
                data: Data(),
                isComplete: terminalAtEnd
            )
        }
        let value = Data(bytes.prefix(count))
        bytes.removeFirst(count)
        return ClientInteractiveRoleReadChunkV0(
            data: value,
            isComplete: terminalAtEnd && bytes.isEmpty
        )
    }

    func cancel() { cancelled = true }
    func remaining() -> Data { bytes }
}

private actor MediaPumpTestConsumerV0:
    ClientInteractiveMediaRecordConsumingV0
{
    private(set) var values: [(MediaRecordHeader, Data)] = []

    func consume(header: MediaRecordHeader, payload: Data) {
        values.append((header, payload))
    }

    func count() -> Int { values.count }
    func payload(at index: Int) -> Data { values[index].1 }
}

private actor InitialDesktopTestPrimaryV0:
    NetworkClientInteractiveInitialPrimaryControllingV0
{
    let descriptor: AdaptiveSurfaceDescriptor
    private(set) var began = false
    private(set) var acknowledgementCount = 0
    private var surfacePhase: ClientInitialSurfacePhaseV0 = .awaitingRequest

    init(descriptor: AdaptiveSurfaceDescriptor) {
        self.descriptor = descriptor
    }

    func beginInitialSurface() { began = true; surfacePhase = .awaitingDescriptor }

    func waitForInitialDescriptor(
        timeoutMilliseconds: UInt64
    ) -> AdaptiveSurfaceDescriptor {
        surfacePhase = .awaitingMedia
        return descriptor
    }

    func admitInitialMedia(
        header: MediaRecordHeader,
        payloadByteCount: Int
    ) -> ClientMediaAdmissionV0 {
        switch header.type {
        case .decoderConfiguration: return .decoderConfiguration
        case .videoAccessUnit:
            return .videoAccessUnit(
                cleanKeyframe: header.flags.contains(.cleanKeyframe)
            )
        case .discontinuity: return .discontinuity
        case .end: return .end
        }
    }

    func confirmInitialRenderedFrame(
        _ receipt: ClientDecodedFrameReceiptV0
    ) -> Bool { receipt.mediaSequence == 2 }

    func acknowledgeInitialSurface() {
        acknowledgementCount += 1
        surfacePhase = .awaitingAcknowledgement
    }

    func initialSurfacePhase() -> ClientInitialSurfacePhaseV0? {
        surfacePhase
    }

    func acknowledgeFromHost() { surfacePhase = .active }

    func makeInitialInputFrame(
        _ payload: InteractiveInputPayload
    ) throws -> Data {
        try JSONEncoder().encode(["kind": payload.kind.rawValue])
    }

    func closeInitialInputFrame() throws -> Data? {
        try JSONEncoder().encode(["kind": "reset"])
    }
}

private actor InitialDesktopTestRendererV0:
    ClientInteractiveInitialMediaRenderingV0
{
    private(set) var headers: [MediaRecordHeader] = []
    private(set) var closed = false

    func process(
        header: MediaRecordHeader,
        payload: Data,
        admission: ClientMediaAdmissionV0
    ) { headers.append(header) }

    func close() { closed = true }
    func count() -> Int { headers.count }
}

private actor InitialDesktopSuspendingIOV0 {
    private var bytes: Data
    private var continuation:
        CheckedContinuation<ClientInteractiveRoleReadChunkV0, Never>?

    init(bytes: Data) { self.bytes = bytes }

    func receive(maximumLength: Int) async
        -> ClientInteractiveRoleReadChunkV0
    {
        if !bytes.isEmpty {
            let count = min(maximumLength, bytes.count)
            let value = Data(bytes.prefix(count))
            bytes.removeFirst(count)
            return ClientInteractiveRoleReadChunkV0(data: value)
        }
        return await withCheckedContinuation { continuation = $0 }
    }

    func cancel() {
        continuation?.resume(returning: ClientInteractiveRoleReadChunkV0(
            data: Data(),
            isComplete: true
        ))
        continuation = nil
    }
}

private actor InitialDesktopInputIOV0 {
    private(set) var sends: [Data] = []
    private(set) var cancelled = false

    func send(_ value: Data) { sends.append(value) }
    func cancel() { cancelled = true }
    func count() -> Int { sends.count }
    func value(at index: Int) -> Data { sends[index] }
}

private func mediaPumpHeader(
    type: MediaRecordType,
    payloadLength: UInt32,
    sequence: UInt64
) throws -> MediaRecordHeader {
    try MediaRecordHeader(
        type: type,
        flags: type == .videoAccessUnit ? [.cleanKeyframe] : [],
        payloadLength: payloadLength,
        interactiveSessionID: UUID(),
        authorizationEpoch: .init(rawValue: 1),
        surfaceID: UUID(),
        surfaceRevision: .init(rawValue: 1),
        coordinateSpaceRevision: .init(rawValue: 1),
        mediaSequence: sequence,
        presentationTimeNanoseconds: sequence,
        encodedWidth: type == .decoderConfiguration
            || type == .videoAccessUnit ? 640 : 0,
        encodedHeight: type == .decoderConfiguration
            || type == .videoAccessUnit ? 480 : 0
    )
}

private func mediaPumpConnection(
    io: MediaPumpTestIOV0
) throws -> NetworkClientInteractiveReadyRoleConnectionV0 {
    NetworkClientInteractiveReadyRoleConnectionV0(
        endpoint: try EndpointCandidate(
            kind: .ipv4,
            value: "192.0.2.44",
            port: 48_321
        ),
        role: .media,
        channelID: WireUUID(UUID()),
        receive: { maximumLength in
            await io.receive(maximumLength: maximumLength)
        },
        cancel: { await io.cancel() }
    )
}

@Test func mediaRecordPumpReadsExactHeaderAndPayloadWithoutSentinel() async throws {
    let payload = Data([0xaa, 0xbb, 0xcc])
    let record = try mediaPumpHeader(
        type: .decoderConfiguration,
        payloadLength: UInt32(payload.count),
        sequence: 1
    ).encode() + payload
    let end = try mediaPumpHeader(
        type: .end,
        payloadLength: 0,
        sequence: 2
    ).encode()
    let sentinel = Data([0xde, 0xad])
    let io = MediaPumpTestIOV0(bytes: record + end + sentinel)
    let consumer = MediaPumpTestConsumerV0()
    let pump = try NetworkClientInteractiveMediaRecordPumpV0(
        connection: try mediaPumpConnection(io: io),
        consumer: consumer
    )

    try await pump.run()

    #expect(await pump.phase == .ended)
    #expect(await consumer.count() == 2)
    #expect(await consumer.payload(at: 0) == payload)
    #expect(await io.remaining() == sentinel)
    #expect(await io.cancelled)
}

@Test func mediaRecordPumpRejectsHeaderBeforePayloadAllocation() async throws {
    var invalid = try mediaPumpHeader(
        type: .decoderConfiguration,
        payloadLength: 1,
        sequence: 1
    ).encode()
    invalid[12] = 0xff
    let io = MediaPumpTestIOV0(bytes: invalid + Data(repeating: 1, count: 32))
    let consumer = MediaPumpTestConsumerV0()
    let pump = try NetworkClientInteractiveMediaRecordPumpV0(
        connection: try mediaPumpConnection(io: io),
        consumer: consumer
    )

    await #expect(throws:
        NetworkClientInteractiveMediaRecordPumpErrorV0.invalidHeader
    ) {
        try await pump.run()
    }
    #expect(await pump.phase == .closed)
    #expect(await consumer.count() == 0)
    #expect(await io.remaining().count == 32)
}

@Test func mediaRecordPumpFailsClosedOnTruncatedPayload() async throws {
    let header = try mediaPumpHeader(
        type: .decoderConfiguration,
        payloadLength: 3,
        sequence: 1
    )
    let io = MediaPumpTestIOV0(
        bytes: header.encode() + Data([0xaa]),
        terminalAtEnd: true
    )
    let pump = try NetworkClientInteractiveMediaRecordPumpV0(
        connection: try mediaPumpConnection(io: io),
        consumer: MediaPumpTestConsumerV0()
    )

    await #expect(throws:
        NetworkClientInteractiveMediaRecordPumpErrorV0.remoteClosed
    ) {
        try await pump.run()
    }
    #expect(await pump.phase == .closed)
    #expect(await io.cancelled)
}

@Test func initialDesktopOwnerAcknowledgesOnlyRendererProof() async throws {
    let sessionID = UUID()
    let surfaceID = UUID()
    let descriptor = try AdaptiveSurfaceDescriptor(
        interactiveSessionID: sessionID,
        authorizationEpoch: .init(rawValue: 1),
        surfaceID: surfaceID,
        kind: .desktop,
        surfaceRevision: .init(rawValue: 1),
        coordinateSpaceRevision: .init(rawValue: 1),
        encodedWidth: 640,
        encodedHeight: 480,
        logicalWidthPoints: 640,
        logicalHeightPoints: 480,
        interactionClasses: [.view],
        privacyProfile: .visualOnly,
        metadataFields: [],
        createdAtMonotonicMilliseconds: 1,
        expiresAtMonotonicMilliseconds: 30_001
    )
    let configuration = try MediaRecordHeader(
        type: .decoderConfiguration,
        payloadLength: 1,
        interactiveSessionID: sessionID,
        authorizationEpoch: descriptor.authorizationEpoch,
        surfaceID: surfaceID,
        surfaceRevision: descriptor.surfaceRevision,
        coordinateSpaceRevision: descriptor.coordinateSpaceRevision,
        mediaSequence: 1,
        presentationTimeNanoseconds: 1,
        encodedWidth: 640,
        encodedHeight: 480
    )
    let clean = try MediaRecordHeader(
        type: .videoAccessUnit,
        flags: [.cleanKeyframe],
        payloadLength: 1,
        interactiveSessionID: sessionID,
        authorizationEpoch: descriptor.authorizationEpoch,
        surfaceID: surfaceID,
        surfaceRevision: descriptor.surfaceRevision,
        coordinateSpaceRevision: descriptor.coordinateSpaceRevision,
        mediaSequence: 2,
        presentationTimeNanoseconds: 2,
        encodedWidth: 640,
        encodedHeight: 480
    )
    let io = InitialDesktopSuspendingIOV0(
        bytes: configuration.encode() + Data([0x01])
            + clean.encode() + Data([0x02])
    )
    let endpoint = try EndpointCandidate(
        kind: .ipv4,
        value: "192.0.2.45",
        port: 48_322
    )
    let connection = NetworkClientInteractiveReadyRoleConnectionV0(
        endpoint: endpoint,
        role: .media,
        channelID: WireUUID(UUID()),
        receive: { await io.receive(maximumLength: $0) },
        cancel: { await io.cancel() }
    )
    let inputIO = InitialDesktopInputIOV0()
    let inputConnection = NetworkClientInteractiveReadyRoleConnectionV0(
        endpoint: endpoint,
        role: .input,
        channelID: WireUUID(UUID()),
        send: { await inputIO.send($0) },
        cancel: { await inputIO.cancel() }
    )
    let primary = InitialDesktopTestPrimaryV0(descriptor: descriptor)
    let renderer = InitialDesktopTestRendererV0()
    let activation = try
        NetworkClientInteractiveInitialDesktopActivationV0(
            channel: primary,
            inputConnection: inputConnection,
            mediaConnection: connection,
            renderer: renderer
        )

    #expect(try await activation.start() == descriptor)
    for _ in 0..<1_000 {
        if await renderer.count() == 2 { break }
        await Task.yield()
    }
    #expect(await renderer.count() == 2)
    #expect(await primary.acknowledgementCount == 0)
    try await activation.reportRendered(ClientDecodedFrameReceiptV0(
        generation: 1,
        fence: ClientDecoderFenceV0(header: clean),
        mediaSequence: 2,
        presentationTimeNanoseconds: 2,
        frameReference: UUID()
    ))
    #expect(await primary.acknowledgementCount == 1)
    #expect(await activation.phase == .awaitingAcknowledgement)

    await primary.acknowledgeFromHost()
    #expect(await activation.refreshPrimaryState())
    #expect(await activation.phase == .active)
    try await activation.sendInput([.pointerMove(x: 1, y: 2)])
    #expect(await inputIO.count() == 1)
    let framedInput = await inputIO.value(at: 0)
    #expect(framedInput.prefix(4) == Data([0, 0, 0, 22]))
    #expect(framedInput.dropFirst(4)
        == Data(#"{"kind":"pointerMove"}"#.utf8))
    await activation.close()
    #expect(await inputIO.count() == 2)
    let framedReset = await inputIO.value(at: 1)
    #expect(framedReset.prefix(4) == Data([0, 0, 0, 16]))
    #expect(framedReset.dropFirst(4) == Data(#"{"kind":"reset"}"#.utf8))
    #expect(await inputIO.cancelled)
    #expect(await renderer.closed)
}
