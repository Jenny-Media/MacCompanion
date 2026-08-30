import CompanionDomain
import CompanionInteractiveRuntime
import CompanionInteractiveWire
import Foundation
import Testing

private func queueHeader(
    sessionID: UUID = UUID(
        uuidString: "018f6000-0000-7000-8000-000000000001"
    )!,
    sequence: UInt64,
    payloadLength: UInt32
) throws -> MediaRecordHeader {
    try MediaRecordHeader(
        type: .videoAccessUnit,
        payloadLength: payloadLength,
        interactiveSessionID: sessionID,
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

private actor RenderBlankProbe: InteractiveRuntimeRenderedFrameBlankingV0 {
    private(set) var calls = 0
    private let fails: Bool

    init(fails: Bool = false) { self.fails = fails }

    func blankRenderedInteractiveFrame() async throws {
        calls += 1
        if fails { throw BoundedInteractiveMediaQueueErrorV0.invalidBounds }
    }
}

private final class QueueWakeupProbeV0: @unchecked Sendable {
    private let lock = NSLock()
    private var callsStorage = 0

    func call() { lock.withLock { callsStorage += 1 } }
    func calls() -> Int { lock.withLock { callsStorage } }
}

@Test func boundedMediaQueueRejectsWithoutEvictingOrPartialAcceptance() throws {
    let queue = try BoundedInteractiveMediaQueueV0(
        maximumRecords: 1,
        maximumBytes: 3
    )
    let firstHeader = try queueHeader(sequence: 1, payloadLength: 3)
    #expect(queue.enqueueInteractiveMedia(
        header: firstHeader,
        payload: Data([1, 2, 3])
    ))
    #expect(!queue.enqueueInteractiveMedia(
        header: try queueHeader(sequence: 2, payloadLength: 1),
        payload: Data([4])
    ))
    #expect(queue.status().recordCount == 1)
    #expect(queue.status().byteCount == 3)
    #expect(queue.dequeue()?.header == firstHeader)
    #expect(queue.status().recordCount == 0)
}

@Test func queueRejectsMixedSessionsUntilPurged() throws {
    let queue = try BoundedInteractiveMediaQueueV0()
    let firstSession = UUID()
    let secondSession = UUID()
    #expect(queue.enqueueInteractiveMedia(
        header: try queueHeader(
            sessionID: firstSession,
            sequence: 1,
            payloadLength: 1
        ),
        payload: Data([1])
    ))
    #expect(!queue.enqueueInteractiveMedia(
        header: try queueHeader(
            sessionID: secondSession,
            sequence: 1,
            payloadLength: 1
        ),
        payload: Data([2])
    ))
    #expect(queue.purge() == 1)
    #expect(queue.enqueueInteractiveMedia(
        header: try queueHeader(
            sessionID: secondSession,
            sequence: 1,
            payloadLength: 1
        ),
        payload: Data([2])
    ))
}

@Test func queueWakeupHasSoleExactOwnerAndCannotMissRetainedRecords()
    throws
{
    let queue = try BoundedInteractiveMediaQueueV0()
    #expect(queue.enqueueInteractiveMedia(
        header: try queueHeader(sequence: 1, payloadLength: 1),
        payload: Data([1])
    ))
    let probe = QueueWakeupProbeV0()
    let firstToken = UUID()
    #expect(queue.installEnqueuedHandler(token: firstToken) {
        probe.call()
    })
    #expect(probe.calls() == 1)
    #expect(!queue.installEnqueuedHandler(token: UUID()) {})

    queue.removeEnqueuedHandler(token: UUID())
    #expect(queue.enqueueInteractiveMedia(
        header: try queueHeader(sequence: 2, payloadLength: 1),
        payload: Data([2])
    ))
    #expect(probe.calls() == 2)

    queue.removeEnqueuedHandler(token: firstToken)
    #expect(queue.enqueueInteractiveMedia(
        header: try queueHeader(sequence: 3, payloadLength: 1),
        payload: Data([3])
    ))
    #expect(probe.calls() == 2)
}

@Test func productionSizedQueueRetainsDelayedMediaRoleStartupBurst() throws {
    let queue = try BoundedInteractiveMediaQueueV0(
        maximumRecords: 64,
        maximumBytes: 16 * 1_024 * 1_024
    )
    let sessionID = UUID()

    // Decoder configuration plus two seconds of 30 fps access units may be
    // produced before the separately authenticated media role finishes its
    // network handshake. None may be silently dropped or rejected.
    for sequence in 1...61 {
        #expect(queue.enqueueInteractiveMedia(
            header: try queueHeader(
                sessionID: sessionID,
                sequence: UInt64(sequence),
                payloadLength: 1
            ),
            payload: Data([UInt8(sequence)])
        ))
    }
    #expect(queue.status().recordCount == 61)

    let probe = QueueWakeupProbeV0()
    #expect(queue.installEnqueuedHandler(token: UUID()) {
        probe.call()
    })
    #expect(probe.calls() == 1)

    for sequence in 1...61 {
        #expect(queue.dequeue()?.header.mediaSequence == UInt64(sequence))
    }
    #expect(queue.dequeue() == nil)
}

@Test func compositeBlankPurgesQueueEvenWhenRendererFails() async throws {
    let queue = try BoundedInteractiveMediaQueueV0()
    #expect(queue.enqueueInteractiveMedia(
        header: try queueHeader(sequence: 1, payloadLength: 1),
        payload: Data([1])
    ))
    let renderer = RenderBlankProbe(fails: true)
    let controller = QueuePurgingInteractiveFrameControllerV0(
        queue: queue,
        renderer: renderer
    )
    await #expect(throws: BoundedInteractiveMediaQueueErrorV0.invalidBounds) {
        try await controller.blankLastInteractiveFrame()
    }
    #expect(queue.status().recordCount == 0)
    #expect(await renderer.calls == 1)
}
