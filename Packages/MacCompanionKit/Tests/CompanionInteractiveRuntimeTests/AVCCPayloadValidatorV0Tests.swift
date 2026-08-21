import CompanionInteractiveRuntime
import CompanionInteractiveShared
import Foundation
import Testing

private let validBaselineAVCC = Data([
    1, 66, 0, 30, 0xff, 0xe1,
    0, 4, 0x67, 66, 0, 30,
    1, 0, 2, 0x68, 0,
])

@Test func baselineAVCCConfigurationAndLengthPrefixedSlicesValidate() throws {
    try AVCCPayloadValidatorV0.validateDecoderConfiguration(validBaselineAVCC)
    let parameterSets = try AVCCPayloadValidatorV0.decoderParameterSets(
        validBaselineAVCC
    )
    #expect(parameterSets.sequence == [Data([0x67, 66, 0, 30])])
    #expect(parameterSets.picture == [Data([0x68, 0])])
    try AVCCPayloadValidatorV0.validateAccessUnit(
        Data([0, 0, 0, 2, 0x41, 0]),
        cleanKeyframe: false
    )
    try AVCCPayloadValidatorV0.validateAccessUnit(
        Data([0, 0, 0, 2, 0x65, 0]),
        cleanKeyframe: true
    )
}

@Test func AVCCConfigurationRejectsReservedLengthAndParameterSetFaults() {
    var wrongLengthSize = validBaselineAVCC
    wrongLengthSize[4] = 0xfe
    #expect(throws: AVCCPayloadErrorV0.unsupportedNALLengthSize) {
        try AVCCPayloadValidatorV0.validateDecoderConfiguration(wrongLengthSize)
    }

    var wrongSPS = validBaselineAVCC
    wrongSPS[8] = 0x68
    #expect(throws: AVCCPayloadErrorV0.invalidParameterSet) {
        try AVCCPayloadValidatorV0.validateDecoderConfiguration(wrongSPS)
    }

    var trailing = validBaselineAVCC
    trailing.append(0)
    #expect(throws: AVCCPayloadErrorV0.invalidConfiguration) {
        try AVCCPayloadValidatorV0.validateDecoderConfiguration(trailing)
    }
}

@Test func AVCCAccessUnitsRejectAnnexBTruncationAndFalseKeyframeClaims() {
    #expect(throws: AVCCPayloadErrorV0.truncatedNALUnit) {
        try AVCCPayloadValidatorV0.validateAccessUnit(
            Data([0, 0, 0, 1, 0x65, 0]),
            cleanKeyframe: true
        )
    }
    #expect(throws: AVCCPayloadErrorV0.keyframeFlagMismatch) {
        try AVCCPayloadValidatorV0.validateAccessUnit(
            Data([0, 0, 0, 1, 0x65]),
            cleanKeyframe: false
        )
    }
    #expect(throws: AVCCPayloadErrorV0.missingVideoSlice) {
        try AVCCPayloadValidatorV0.validateAccessUnit(
            Data([0, 0, 0, 1, 0x67]),
            cleanKeyframe: false
        )
    }
}
