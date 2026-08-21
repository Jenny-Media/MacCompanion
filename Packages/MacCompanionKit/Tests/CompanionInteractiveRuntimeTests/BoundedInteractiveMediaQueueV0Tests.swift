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
