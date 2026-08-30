@testable import CompanionClientPlatform
import Testing
import VideoToolbox

@Test func realtimeDecoderTreatsOnlyTemporarySubmissionPressureAsDrop() {
    #expect(
        VideoToolboxClientDecoderV0.submissionDisposition(status: noErr)
            == .accepted
    )
    #expect(
        VideoToolboxClientDecoderV0.submissionDisposition(
            status: kVTVideoDecoderNotAvailableNowErr
        ) == .dropped
    )
}

@Test func realtimeDecoderKeepsInvalidOrMalformedSessionsTerminal() {
    #expect(
        VideoToolboxClientDecoderV0.submissionDisposition(
            status: kVTInvalidSessionErr
        ) == .failed(kVTInvalidSessionErr)
    )
    #expect(
        VideoToolboxClientDecoderV0.submissionDisposition(
            status: kVTVideoDecoderBadDataErr
        ) == .failed(kVTVideoDecoderBadDataErr)
    )
}
