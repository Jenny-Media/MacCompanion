import CompanionDomain
import CompanionInteractiveClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import Foundation
import Testing

private let decoderSessionID = UUID()
private let decoderSurfaceID = UUID()
private let decoderConfiguration = Data([
    1, 100, 0, 31, 0xff, 0xe1,
    0, 2, 0x67, 0x64,
    1,
    0, 2, 0x68, 0xee,
])
private let decoderCleanAccessUnit = Data([0, 0, 0, 2, 0x65, 0x88])
private let decoderDeltaAccessUnit = Data([0, 0, 0, 2, 0x41, 0x88])

private func decoderHeader(
    type: MediaRecordType,
    sequence: UInt64,
    surfaceID: UUID = decoderSurfaceID,
    revision: UInt64 = 1,
    coordinateRevision: UInt64 = 1,
    clean: Bool = false,
    presentationTimeNanoseconds: UInt64? = nil,
    payloadLength: Int
) throws -> MediaRecordHeader {
    let hasDimensions = type == .decoderConfiguration
        || type == .videoAccessUnit
    return try MediaRecordHeader(
        type: type,
        flags: clean ? [.cleanKeyframe] : [],
        payloadLength: UInt32(payloadLength),
        interactiveSessionID: decoderSessionID,
        authorizationEpoch: .init(rawValue: 4),
        surfaceID: surfaceID,
        surfaceRevision: .init(rawValue: revision),
        coordinateSpaceRevision: .init(rawValue: coordinateRevision),
        mediaSequence: sequence,
        presentationTimeNanoseconds:
            presentationTimeNanoseconds ?? sequence * 1_000,
        encodedWidth: hasDimensions ? 1_280 : 0,
        encodedHeight: hasDimensions ? 720 : 0
    )
}

@Test func decoderAuthorityConfiguresDecodesAndKeepsOnlyNewestFrame() throws {
    var authority = ClientDecoderRenderAuthorityV0()
    let configurationHeader = try decoderHeader(
        type: .decoderConfiguration,
        sequence: 1,
        payloadLength: decoderConfiguration.count
    )
    let configurationAction = try authority.process(
        header: configurationHeader,
        payload: decoderConfiguration,
        admission: .decoderConfiguration
    )
    guard case let .configure(configuration) = configurationAction else {
        Issue.record("expected configuration")
        return
    }
    #expect(configuration.generation == 1)
    #expect(authority.phase == .awaitingCleanKeyframe)

    let keyframeHeader = try decoderHeader(
        type: .videoAccessUnit,
        sequence: 2,
        clean: true,
        payloadLength: decoderCleanAccessUnit.count
    )
    let decodeAction = try authority.process(
        header: keyframeHeader,
        payload: decoderCleanAccessUnit,
        admission: .videoAccessUnit(cleanKeyframe: true)
    )
    guard case let .decode(decode) = decodeAction else {
        Issue.record("expected decode")
        return
    }
    let firstReference = UUID()
    #expect(authority.admitDecodedFrame(ClientDecodedFrameReceiptV0(
        generation: decode.generation,
        fence: decode.fence,
        mediaSequence: 2,
        presentationTimeNanoseconds: 2_000,
        frameReference: firstReference
    )) == .accepted)

    let secondReference = UUID()
    let deltaHeader = try decoderHeader(
        type: .videoAccessUnit,
        sequence: 3,
        payloadLength: decoderDeltaAccessUnit.count
    )
    _ = try authority.process(
        header: deltaHeader,
        payload: decoderDeltaAccessUnit,
        admission: .videoAccessUnit(cleanKeyframe: false)
    )
    #expect(authority.admitDecodedFrame(ClientDecodedFrameReceiptV0(
        generation: 1,
        fence: decode.fence,
        mediaSequence: 3,
        presentationTimeNanoseconds: 3_000,
        frameReference: secondReference
    )) == .replaced(previousFrameReference: firstReference))
    #expect(authority.blank() == secondReference)
    #expect(authority.latestFrame == nil)
}

@Test func discontinuityInvalidatesOldCallbacksBeforeNewConfiguration() throws {
    var authority = ClientDecoderRenderAuthorityV0()
    let configurationHeader = try decoderHeader(
        type: .decoderConfiguration,
        sequence: 1,
        payloadLength: decoderConfiguration.count
    )
    guard case let .configure(initial) = try authority.process(
        header: configurationHeader,
        payload: decoderConfiguration,
        admission: .decoderConfiguration
    ) else { return }
    let oldKeyframe = try decoderHeader(
        type: .videoAccessUnit,
        sequence: 2,
        clean: true,
        payloadLength: decoderCleanAccessUnit.count
    )
    _ = try authority.process(
        header: oldKeyframe,
        payload: decoderCleanAccessUnit,
        admission: .videoAccessUnit(cleanKeyframe: true)
    )

    let replacementSurface = UUID()
    let discontinuity = try decoderHeader(
        type: .discontinuity,
        sequence: 3,
        surfaceID: replacementSurface,
        revision: 2,
        coordinateRevision: 2,
        payloadLength: 0
    )
    #expect(try authority.process(
        header: discontinuity,
        payload: Data(),
        admission: .discontinuity
    ) == .reset(
        generation: 2,
        fence: ClientDecoderFenceV0(header: discontinuity)
    ))
    #expect(authority.admitDecodedFrame(ClientDecodedFrameReceiptV0(
        generation: 1,
        fence: initial.fence,
        mediaSequence: 2,
        presentationTimeNanoseconds: 2_000,
        frameReference: UUID()
    )) == .discardedStale)

    let replacementConfiguration = try decoderHeader(
        type: .decoderConfiguration,
        sequence: 4,
        surfaceID: replacementSurface,
        revision: 2,
        coordinateRevision: 2,
        payloadLength: decoderConfiguration.count
    )
    guard case let .configure(next) = try authority.process(
        header: replacementConfiguration,
        payload: decoderConfiguration,
        admission: .decoderConfiguration
    ) else { return }
    #expect(next.generation == 2)
    #expect(next.fence.encodedWidth == 1_280)
}

@Test func reconfigurationAdvancesGenerationAndRequiresAnotherCleanFrame() throws {
    var authority = ClientDecoderRenderAuthorityV0()
    let configurationHeader = try decoderHeader(
        type: .decoderConfiguration,
        sequence: 1,
        payloadLength: decoderConfiguration.count
    )
    _ = try authority.process(
        header: configurationHeader,
        payload: decoderConfiguration,
        admission: .decoderConfiguration
    )
    let keyframe = try decoderHeader(
        type: .videoAccessUnit,
        sequence: 2,
        clean: true,
        payloadLength: decoderCleanAccessUnit.count
    )
    _ = try authority.process(
        header: keyframe,
        payload: decoderCleanAccessUnit,
        admission: .videoAccessUnit(cleanKeyframe: true)
    )
    let reconfiguration = try decoderHeader(
        type: .decoderConfiguration,
        sequence: 3,
        payloadLength: decoderConfiguration.count
    )
    guard case let .configure(command) = try authority.process(
        header: reconfiguration,
        payload: decoderConfiguration,
        admission: .decoderConfiguration
    ) else { return }
    #expect(command.generation == 2)
    #expect(authority.phase == .awaitingCleanKeyframe)

    #expect(throws: ClientDecoderRenderErrorV0.admissionMismatch) {
        _ = try authority.process(
            header: try decoderHeader(
                type: .videoAccessUnit,
                sequence: 4,
                payloadLength: decoderDeltaAccessUnit.count
            ),
            payload: decoderDeltaAccessUnit,
            admission: .videoAccessUnit(cleanKeyframe: false)
        )
    }
    #expect(authority.phase == .closed)
}

@Test func malformedDecoderPayloadClosesBeforeACommandIsProduced() throws {
    var authority = ClientDecoderRenderAuthorityV0()
    let header = try decoderHeader(
        type: .decoderConfiguration,
        sequence: 1,
        payloadLength: 7
    )
    #expect(throws: AVCCPayloadErrorV0.invalidConfiguration) {
        _ = try authority.process(
            header: header,
            payload: Data(repeating: 0, count: 7),
            admission: .decoderConfiguration
        )
    }
    #expect(authority.phase == .closed)
}

@Test func decoderAuthorityRejectsAnEndForAnotherSurface() throws {
    var authority = ClientDecoderRenderAuthorityV0()
    _ = try authority.process(
        header: try decoderHeader(
            type: .decoderConfiguration,
            sequence: 1,
            payloadLength: decoderConfiguration.count
        ),
        payload: decoderConfiguration,
        admission: .decoderConfiguration
    )
    #expect(throws: ClientDecoderRenderErrorV0.fenceMismatch) {
        _ = try authority.process(
            header: try decoderHeader(
                type: .end,
                sequence: 2,
                surfaceID: UUID(),
                payloadLength: 0
            ),
            payload: Data(),
            admission: .end
        )
    }
    #expect(authority.phase == .closed)
}

@Test func decoderAuthorityRejectsTimestampOutsideCoreMediaRange() throws {
    var authority = ClientDecoderRenderAuthorityV0()
    _ = try authority.process(
        header: try decoderHeader(
            type: .decoderConfiguration,
            sequence: 1,
            payloadLength: decoderConfiguration.count
        ),
        payload: decoderConfiguration,
        admission: .decoderConfiguration
    )
    #expect(
        throws: ClientDecoderRenderErrorV0.presentationTimeOutOfRange
    ) {
        _ = try authority.process(
            header: try decoderHeader(
                type: .videoAccessUnit,
                sequence: 2,
                clean: true,
                presentationTimeNanoseconds: UInt64.max,
                payloadLength: decoderCleanAccessUnit.count
            ),
            payload: decoderCleanAccessUnit,
            admission: .videoAccessUnit(cleanKeyframe: true)
        )
    }
    #expect(authority.phase == .closed)
}
