#if os(macOS)
@testable import CompanionAgentPlatform
import CompanionInteractiveRuntime
import CompanionInteractiveWire
import CompanionIPC
import CompanionWire
import Foundation
import Testing

@available(macOS 26.0, *)
private actor MediaPublicationGateV1 {
    private var headersStorage: [MediaRecordHeader] = []
    private var permits = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func publish(_ header: MediaRecordHeader) async {
        headersStorage.append(header)
        if permits > 0 {
            permits -= 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func releaseOne() {
        guard !waiters.isEmpty else {
            permits += 1
            return
        }
        waiters.removeFirst().resume()
    }

    func releaseAll() {
        let values = waiters
        waiters.removeAll()
        values.forEach { $0.resume() }
    }

    func headers() -> [MediaRecordHeader] { headersStorage }
}

@available(macOS 26.0, *)
private final class MediaDrainClientProbeV1:
    MacLocalXPCDashboardClientV1,
    @unchecked Sendable
{
    enum Failure: Error { case injected }

    let gate = MediaPublicationGateV1()
    private let failsPublication: Bool
    private let lock = NSLock()
    private var startsStorage = 0
    private var cancelsStorage = 0

    init(failsPublication: Bool = false) {
        self.failsPublication = failsPublication
    }

    func start() throws { lock.withLock { startsStorage += 1 } }
    func publishMenuReady() {}
    func readAgentStatus() {}

    func publishInteractiveMedia(
        header: MediaRecordHeader,
        payload _: Data
    ) async throws {
        if failsPublication { throw Failure.injected }
        await gate.publish(header)
    }

    func cancel() {
        lock.withLock { cancelsStorage += 1 }
        Task { await gate.releaseAll() }
    }

    func finishMenuPresentationReceiver() async {
        await gate.releaseAll()
    }

    func snapshot() -> (starts: Int, cancels: Int) {
        lock.withLock { (startsStorage, cancelsStorage) }
    }
}

private func mediaDrainHeaderV1(
    sequence: UInt64,
    payloadLength: UInt32 = 1
) throws -> MediaRecordHeader {
    try MediaRecordHeader(
        type: .videoAccessUnit,
        payloadLength: payloadLength,
        interactiveSessionID: UUID(
            uuidString: "018f6000-0000-7000-8000-000000000001"
        )!,
        authorizationEpoch: .init(rawValue: 1),
        surfaceID: UUID(
            uuidString: "018f6100-0000-7000-8000-000000000001"
        )!,
        surfaceRevision: .init(rawValue: 1),
        coordinateSpaceRevision: .init(rawValue: 1),
        mediaSequence: sequence,
        presentationTimeNanoseconds: sequence,
        encodedWidth: 100,
        encodedHeight: 100
    )
}

@available(macOS 26.0, *)
private func eventuallyMediaDrainV1(
    _ predicate: @escaping @Sendable () async -> Bool
) async -> Bool {
    for _ in 0..<500 {
        if await predicate() { return true }
        await Task.yield()
    }
    return false
}

@available(macOS 26.0, *)
@Test func mediaDrainAwaitsExactXPCReceiptBeforeNextDequeue()
    async throws
{
    let queue = try BoundedInteractiveMediaQueueV0()
    #expect(queue.enqueueInteractiveMedia(
        header: try mediaDrainHeaderV1(sequence: 1),
        payload: Data([1])
    ))
    #expect(queue.enqueueInteractiveMedia(
        header: try mediaDrainHeaderV1(sequence: 2),
        payload: Data([2])
    ))
    let client = MediaDrainClientProbeV1()
    let drain = MacLocalXPCInteractiveMediaDrainClientV1(
        client: client,
        mediaQueue: queue
    )

    try drain.start()
    #expect(await eventuallyMediaDrainV1 {
        await client.gate.headers().count == 1
    })
    #expect(queue.status().recordCount == 1)
    #expect(client.snapshot().starts == 1)

    await client.gate.releaseOne()
    #expect(await eventuallyMediaDrainV1 {
        await client.gate.headers().count == 2
    })
    #expect(queue.status().recordCount == 0)
    #expect(await client.gate.headers().map(\.mediaSequence) == [1, 2])

    await client.gate.releaseOne()
    drain.cancel()
    #expect(client.snapshot().cancels == 1)
}

@available(macOS 26.0, *)
@Test func mediaDrainFailureCancelsClientAndWithdrawsQueueHandler()
    async throws
{
    let queue = try BoundedInteractiveMediaQueueV0()
    #expect(queue.enqueueInteractiveMedia(
        header: try mediaDrainHeaderV1(sequence: 1),
        payload: Data([1])
    ))
    #expect(queue.enqueueInteractiveMedia(
        header: try mediaDrainHeaderV1(sequence: 2),
        payload: Data([2])
    ))
    let client = MediaDrainClientProbeV1(failsPublication: true)
    let drain = MacLocalXPCInteractiveMediaDrainClientV1(
        client: client,
        mediaQueue: queue
    )

    try drain.start()
    #expect(await eventuallyMediaDrainV1 {
        client.snapshot().cancels == 1
    })
    #expect(queue.status().recordCount == 1)
    let replacementToken = UUID()
    #expect(queue.installEnqueuedHandler(token: replacementToken) {})
    queue.removeEnqueuedHandler(token: replacementToken)
}
#endif
