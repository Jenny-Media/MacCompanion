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

    func requestReplacementSurfaceTargets() {}

    func replacementSurfaceTargets()
        -> [InteractiveSurfaceTargetCandidateV0]?
    { [] }

    func prepareReplacementSurfaceSelection(
        targetKind: InteractiveSurfaceKind,
        targetToken: UUID?
    ) throws -> ClientSurfaceSelectionRequestV0 {
        throw NetworkClientInteractiveInitialDesktopErrorV0.unavailable
    }

    func sendReplacementSurfaceSelection(_ frame: Data) {}

    func replacementSurfacePhase() -> ClientSurfaceControlPhaseV0? {
        .active
    }

    func replacementSurfaceDescriptor()
        -> AdaptiveSurfaceDescriptor?
    { descriptor }

    func confirmReplacementRenderedFrame(
        _ receipt: ClientDecodedFrameReceiptV0
    ) -> Bool { false }

    func acknowledgeReplacementSurface() {}
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

private actor ReplacementOrderingLogV0 {
    private var values: [String] = []
    func append(_ value: String) { values.append(value) }
    func snapshot() -> [String] { values }
}

private actor ReplacementTestPrimaryV0:
    NetworkClientInteractiveInitialPrimaryControllingV0
{
    let initial: AdaptiveSurfaceDescriptor
    let replacement: AdaptiveSurfaceDescriptor
    let candidate: InteractiveSurfaceTargetCandidateV0
    let log: ReplacementOrderingLogV0
    private var initialPhase: ClientInitialSurfacePhaseV0 = .awaitingRequest
    private var replacementPhase: ClientSurfaceControlPhaseV0 = .active

    init(
        initial: AdaptiveSurfaceDescriptor,
        replacement: AdaptiveSurfaceDescriptor,
        candidate: InteractiveSurfaceTargetCandidateV0,
        log: ReplacementOrderingLogV0
    ) {
        self.initial = initial
        self.replacement = replacement
        self.candidate = candidate
        self.log = log
    }

    func beginInitialSurface() { initialPhase = .awaitingDescriptor }
    func waitForInitialDescriptor(
        timeoutMilliseconds: UInt64
    ) -> AdaptiveSurfaceDescriptor {
        initialPhase = .awaitingMedia
        return initial
    }
    func admitInitialMedia(
        header: MediaRecordHeader,
        payloadByteCount: Int
    ) -> ClientMediaAdmissionV0 { .videoAccessUnit(cleanKeyframe: true) }
    func confirmInitialRenderedFrame(
        _ receipt: ClientDecodedFrameReceiptV0
    ) -> Bool { true }
    func acknowledgeInitialSurface() { initialPhase = .awaitingAcknowledgement }
    func initialSurfacePhase() -> ClientInitialSurfacePhaseV0? { initialPhase }
    func acknowledgeInitialFromHost() { initialPhase = .active }
    func makeInitialInputFrame(
        _ payload: InteractiveInputPayload
    ) throws -> Data {
        try JSONEncoder().encode(["kind": payload.kind.rawValue])
    }
    func closeInitialInputFrame() throws -> Data? { nil }

    func requestReplacementSurfaceTargets() {}
    func replacementSurfaceTargets()
        -> [InteractiveSurfaceTargetCandidateV0]?
    { [candidate] }
    func prepareReplacementSurfaceSelection(
        targetKind: InteractiveSurfaceKind,
        targetToken: UUID?
    ) throws -> ClientSurfaceSelectionRequestV0 {
        let reset = try InteractiveInputEnvelope(
            messageID: WireUUID(UUID()),
            interactiveSessionID: WireUUID(initial.interactiveSessionID),
            authorizationEpoch: initial.authorizationEpoch,
            sequence: 1,
            clientMonotonicMilliseconds: 10,
            surfaceID: WireUUID(initial.surfaceID),
            surfaceRevision: initial.surfaceRevision,
            coordinateSpaceRevision: initial.coordinateSpaceRevision,
            input: .reset
        )
        replacementPhase = .awaitingSelection
        return ClientSurfaceSelectionRequestV0(
            reset: reset,
            requestJSON: Data([0xaa])
        )
    }
    func sendReplacementSurfaceSelection(_ frame: Data) async {
        await log.append("select")
        replacementPhase = .awaitingMedia
    }
    func replacementSurfacePhase() -> ClientSurfaceControlPhaseV0? {
        replacementPhase
    }
    func replacementSurfaceDescriptor()
        -> AdaptiveSurfaceDescriptor?
    { replacement }
    func confirmReplacementRenderedFrame(
        _ receipt: ClientDecodedFrameReceiptV0
    ) -> Bool {
        replacementPhase == .awaitingMedia
            && receipt.fence.surfaceID == replacement.surfaceID
    }
    func acknowledgeReplacementSurface() async {
        await log.append("acknowledge")
        replacementPhase = .active
    }
}

private actor AutomaticFocusTestPrimaryV0:
    NetworkClientInteractiveInitialPrimaryControllingV0
{
    let initial: AdaptiveSurfaceDescriptor
    let replacement: AdaptiveSurfaceDescriptor
    private var initialPhase: ClientInitialSurfacePhaseV0 = .awaitingRequest
    private var replacementPhase: ClientSurfaceControlPhaseV0 = .active
    private var selectedKind: InteractiveSurfaceKind?
    private var selectedToken: UUID?

    init(
        initial: AdaptiveSurfaceDescriptor,
        replacement: AdaptiveSurfaceDescriptor
    ) {
        self.initial = initial
        self.replacement = replacement
    }

    func beginInitialSurface() { initialPhase = .awaitingDescriptor }
    func waitForInitialDescriptor(
        timeoutMilliseconds: UInt64
    ) -> AdaptiveSurfaceDescriptor {
        initialPhase = .awaitingMedia
        return initial
    }
    func admitInitialMedia(
        header: MediaRecordHeader,
        payloadByteCount: Int
    ) -> ClientMediaAdmissionV0 { .videoAccessUnit(cleanKeyframe: true) }
    func confirmInitialRenderedFrame(
        _ receipt: ClientDecodedFrameReceiptV0
    ) -> Bool { true }
    func acknowledgeInitialSurface() { initialPhase = .awaitingAcknowledgement }
    func initialSurfacePhase() -> ClientInitialSurfacePhaseV0? { initialPhase }
    func acknowledgeInitialFromHost() { initialPhase = .active }
    func makeInitialInputFrame(
        _ payload: InteractiveInputPayload
    ) throws -> Data { Data([0x01]) }
    func closeInitialInputFrame() throws -> Data? { nil }
    func requestReplacementSurfaceTargets() {}
    func replacementSurfaceTargets()
        -> [InteractiveSurfaceTargetCandidateV0]?
    { [] }
    func prepareReplacementSurfaceSelection(
        targetKind: InteractiveSurfaceKind,
        targetToken: UUID?
    ) throws -> ClientSurfaceSelectionRequestV0 {
        selectedKind = targetKind
        selectedToken = targetToken
        replacementPhase = .awaitingSelection
        return ClientSurfaceSelectionRequestV0(
            reset: nil,
            requestJSON: Data([0xaa])
        )
    }
    func sendReplacementSurfaceSelection(_ frame: Data) {
        replacementPhase = .active
    }
    func replacementSurfacePhase() -> ClientSurfaceControlPhaseV0? {
        replacementPhase
    }
    func replacementSurfaceDescriptor()
        -> AdaptiveSurfaceDescriptor?
    { selectedKind == nil ? initial : replacement }
    func confirmReplacementRenderedFrame(
        _ receipt: ClientDecodedFrameReceiptV0
    ) -> Bool { false }
    func acknowledgeReplacementSurface() {}
    func selection() -> (InteractiveSurfaceKind?, UUID?) {
        (selectedKind, selectedToken)
    }
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

@Test func replacementSurfaceOrdersResetBeforeSelectAndAckBeforeInput()
    async throws
{
    let sessionID = UUID()
    let applicationToken = UUID()
    let initial = try AdaptiveSurfaceDescriptor(
        interactiveSessionID: sessionID,
        authorizationEpoch: .init(rawValue: 1),
        surfaceID: UUID(),
        kind: .desktop,
        surfaceRevision: .init(rawValue: 1),
        coordinateSpaceRevision: .init(rawValue: 1),
        encodedWidth: 640,
        encodedHeight: 480,
        logicalWidthPoints: 640,
        logicalHeightPoints: 480,
        interactionClasses: [.view, .pointer, .keyboard],
        privacyProfile: .visualOnly,
        metadataFields: [],
        createdAtMonotonicMilliseconds: 1,
        expiresAtMonotonicMilliseconds: 30_001
    )
    let replacement = try AdaptiveSurfaceDescriptor(
        interactiveSessionID: sessionID,
        authorizationEpoch: initial.authorizationEpoch,
        surfaceID: UUID(),
        kind: .application,
        surfaceRevision: .init(rawValue: 2),
        coordinateSpaceRevision: .init(rawValue: 2),
        applicationToken: applicationToken,
        fallbackSurfaceID: initial.surfaceID,
        encodedWidth: 800,
        encodedHeight: 600,
        logicalWidthPoints: 800,
        logicalHeightPoints: 600,
        interactionClasses: [.view, .pointer, .keyboard],
        privacyProfile: .visualOnly,
        metadataFields: [.applicationName],
        createdAtMonotonicMilliseconds: 2,
        expiresAtMonotonicMilliseconds: 30_002
    )
    let candidate = try InteractiveSurfaceTargetCandidateV0(
        targetToken: WireUUID(applicationToken),
        kind: .application,
        applicationToken: WireUUID(applicationToken),
        applicationName: "Notes",
        windowOrdinal: nil,
        currentWindowAvailable: true
    )
    let log = ReplacementOrderingLogV0()
    let primary = ReplacementTestPrimaryV0(
        initial: initial,
        replacement: replacement,
        candidate: candidate,
        log: log
    )
    let endpoint = try EndpointCandidate(
        kind: .ipv4,
        value: "192.0.2.46",
        port: 48_323
    )
    let mediaIO = InitialDesktopSuspendingIOV0(bytes: Data())
    let inputConnection = NetworkClientInteractiveReadyRoleConnectionV0(
        endpoint: endpoint,
        role: .input,
        channelID: WireUUID(UUID()),
        send: { value in
            guard value.count > 4 else { return }
            if let envelope = try? InteractiveInputCodec.decode(
                Data(value.dropFirst(4))
            ), envelope.input == .reset {
                await log.append("reset")
            } else {
                await log.append("input")
            }
        },
        cancel: {}
    )
    let mediaConnection = NetworkClientInteractiveReadyRoleConnectionV0(
        endpoint: endpoint,
        role: .media,
        channelID: WireUUID(UUID()),
        receive: { await mediaIO.receive(maximumLength: $0) },
        cancel: { await mediaIO.cancel() }
    )
    let activation = try NetworkClientInteractiveInitialDesktopActivationV0(
        channel: primary,
        inputConnection: inputConnection,
        mediaConnection: mediaConnection,
        renderer: InitialDesktopTestRendererV0()
    )

    #expect(try await activation.start() == initial)
    try await activation.reportRendered(ClientDecodedFrameReceiptV0(
        generation: 1,
        fence: ClientDecoderFenceV0(header: try MediaRecordHeader(
            type: .videoAccessUnit,
            flags: [.cleanKeyframe],
            payloadLength: 1,
            interactiveSessionID: initial.interactiveSessionID,
            authorizationEpoch: initial.authorizationEpoch,
            surfaceID: initial.surfaceID,
            surfaceRevision: initial.surfaceRevision,
            coordinateSpaceRevision: initial.coordinateSpaceRevision,
            mediaSequence: 1,
            presentationTimeNanoseconds: 1,
            encodedWidth: initial.encodedWidth,
            encodedHeight: initial.encodedHeight
        )),
        mediaSequence: 1,
        presentationTimeNanoseconds: 1,
        frameReference: UUID()
    ))
    await primary.acknowledgeInitialFromHost()
    #expect(await activation.refreshPrimaryState())
    #expect(try await activation.requestSurfaceTargets() == [candidate])

    let selection = Task {
        try await activation.selectSurface(
            targetKind: .application,
            targetToken: applicationToken,
            timeoutMilliseconds: 1_000
        )
    }
    for _ in 0..<1_000 {
        if await primary.replacementSurfacePhase() == .awaitingMedia { break }
        try await Task.sleep(for: .milliseconds(1))
    }
    #expect(await primary.replacementSurfacePhase() == .awaitingMedia)
    #expect(await log.snapshot() == ["reset", "select"])
    let replacementHeader = try MediaRecordHeader(
        type: .videoAccessUnit,
        flags: [.cleanKeyframe],
        payloadLength: 1,
        interactiveSessionID: replacement.interactiveSessionID,
        authorizationEpoch: replacement.authorizationEpoch,
        surfaceID: replacement.surfaceID,
        surfaceRevision: replacement.surfaceRevision,
        coordinateSpaceRevision: replacement.coordinateSpaceRevision,
        mediaSequence: 2,
        presentationTimeNanoseconds: 2,
        encodedWidth: replacement.encodedWidth,
        encodedHeight: replacement.encodedHeight
    )
    try await activation.reportRendered(ClientDecodedFrameReceiptV0(
        generation: 2,
        fence: ClientDecoderFenceV0(header: replacementHeader),
        mediaSequence: 2,
        presentationTimeNanoseconds: 2,
        frameReference: UUID()
    ))
    #expect(try await selection.value == replacement)
    #expect(await log.snapshot() == ["reset", "select", "acknowledge"])
    try await activation.sendInput([
        InteractiveInputPayload.pointerMove(x: 1, y: 2),
    ])
    #expect(await log.snapshot()
        == ["reset", "select", "acknowledge", "input"])
    await activation.close()
}

@Test func admittedFocusEventAutomaticallyUsesReplacementPathAndHonorsOptOut()
    async throws
{
    let sessionID = UUID()
    let focusToken = UUID()
    let eventTargetToken = UUID()
    let initial = try AdaptiveSurfaceDescriptor(
        interactiveSessionID: sessionID,
        authorizationEpoch: .init(rawValue: 1),
        surfaceID: UUID(),
        kind: .desktop,
        surfaceRevision: .init(rawValue: 1),
        coordinateSpaceRevision: .init(rawValue: 1),
        encodedWidth: 640,
        encodedHeight: 480,
        logicalWidthPoints: 640,
        logicalHeightPoints: 480,
        interactionClasses: [.view, .pointer, .keyboard],
        privacyProfile: .visualOnly,
        metadataFields: [],
        createdAtMonotonicMilliseconds: 1,
        expiresAtMonotonicMilliseconds: 30_001
    )
    let focus = try SurfaceFocus(
        token: focusToken,
        revision: .init(rawValue: 1),
        category: .text,
        bounds: NormalizedSurfaceRect(
            x: 10_000,
            y: 20_000,
            width: 8_000,
            height: 3_000
        ),
        editable: true,
        secure: false
    )
    let replacement = try AdaptiveSurfaceDescriptor(
        interactiveSessionID: sessionID,
        authorizationEpoch: initial.authorizationEpoch,
        surfaceID: UUID(),
        kind: .focusedRegion,
        surfaceRevision: .init(rawValue: 2),
        coordinateSpaceRevision: .init(rawValue: 2),
        applicationToken: UUID(),
        parentSurfaceID: initial.surfaceID,
        fallbackSurfaceID: initial.surfaceID,
        encodedWidth: 800,
        encodedHeight: 600,
        logicalWidthPoints: 800,
        logicalHeightPoints: 600,
        interactionClasses: [.view, .pointer, .keyboard],
        privacyProfile: .assistedVisual,
        metadataFields: [
            .focusCategory, .focusBounds, .editable, .secure,
        ],
        focus: focus,
        createdAtMonotonicMilliseconds: 2,
        expiresAtMonotonicMilliseconds: 30_002
    )
    let primary = AutomaticFocusTestPrimaryV0(
        initial: initial,
        replacement: replacement
    )
    let endpoint = try EndpointCandidate(
        kind: .ipv4,
        value: "192.0.2.47",
        port: 48_324
    )
    let mediaIO = InitialDesktopSuspendingIOV0(bytes: Data())
    let activation = try NetworkClientInteractiveInitialDesktopActivationV0(
        channel: primary,
        inputConnection: NetworkClientInteractiveReadyRoleConnectionV0(
            endpoint: endpoint,
            role: .input,
            channelID: WireUUID(UUID()),
            send: { _ in },
            cancel: {}
        ),
        mediaConnection: NetworkClientInteractiveReadyRoleConnectionV0(
            endpoint: endpoint,
            role: .media,
            channelID: WireUUID(UUID()),
            receive: { await mediaIO.receive(maximumLength: $0) },
            cancel: { await mediaIO.cancel() }
        ),
        renderer: InitialDesktopTestRendererV0()
    )
    #expect(try await activation.start() == initial)
    let initialHeader = try MediaRecordHeader(
        type: .videoAccessUnit,
        flags: [.cleanKeyframe],
        payloadLength: 1,
        interactiveSessionID: initial.interactiveSessionID,
        authorizationEpoch: initial.authorizationEpoch,
        surfaceID: initial.surfaceID,
        surfaceRevision: initial.surfaceRevision,
        coordinateSpaceRevision: initial.coordinateSpaceRevision,
        mediaSequence: 1,
        presentationTimeNanoseconds: 1,
        encodedWidth: initial.encodedWidth,
        encodedHeight: initial.encodedHeight
    )
    try await activation.reportRendered(ClientDecodedFrameReceiptV0(
        generation: 1,
        fence: ClientDecoderFenceV0(header: initialHeader),
        mediaSequence: 1,
        presentationTimeNanoseconds: 1,
        frameReference: UUID()
    ))
    await primary.acknowledgeInitialFromHost()
    #expect(await activation.refreshPrimaryState())

    let event = ClientSurfaceFocusEventV0(
        messageID: WireUUID(UUID()),
        eventSequence: 1,
        recommendedTargetKind: .focusedRegion,
        targetToken: WireUUID(eventTargetToken),
        focus: focus,
        inputPaused: false,
        reason: .verifiedFocus,
        expiresAtMonotonicMilliseconds: 1_000
    )
    await activation.setAutomaticSmartZoomEnabled(false)
    let ignored = try await activation.applyFocusEvent(event)
    #expect(ignored == nil)
    let ignoredSelection = await primary.selection()
    #expect(ignoredSelection.0 == nil)

    await activation.setAutomaticSmartZoomEnabled(true)
    #expect(try await activation.applyFocusEvent(
        event,
        timeoutMilliseconds: 100
    ) == replacement)
    let automaticSelection = await primary.selection()
    #expect(automaticSelection.0 == .focusedRegion)
    #expect(automaticSelection.1 == eventTargetToken)

    _ = try await activation.selectSurface(
        targetKind: .desktop,
        targetToken: nil,
        timeoutMilliseconds: 100
    )
    let automaticEnabled = await activation.isAutomaticSmartZoomEnabled()
    #expect(!automaticEnabled)
    await activation.close()
}
