import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionTestSupport
import CompanionWire
import Foundation
import Testing

private let inputMessageID = WireUUID(UUID(uuidString: "018f6400-0000-7000-8000-000000000001")!)
private let inputSessionID = WireUUID(UUID(uuidString: "018f6000-0000-7000-8000-000000000001")!)
private let inputSurfaceID = WireUUID(UUID(uuidString: "018f6100-0000-7000-8000-000000000001")!)
private let inputFocusToken = WireUUID(UUID(uuidString: "018f6300-0000-7000-8000-000000000001")!)

private func inputEnvelope(
    sequence: UInt64,
    time: UInt64? = nil,
    focus: Bool = false,
    input: InteractiveInputPayload
) throws -> InteractiveInputEnvelope {
    try InteractiveInputEnvelope(
        messageID: inputMessageID,
        interactiveSessionID: inputSessionID,
        authorizationEpoch: .init(rawValue: 4),
        sequence: sequence,
        clientMonotonicMilliseconds: time ?? sequence,
        surfaceID: inputSurfaceID,
        surfaceRevision: .init(rawValue: 2),
        coordinateSpaceRevision: .init(rawValue: 3),
        focusToken: focus ? inputFocusToken : nil,
        focusRevision: focus ? .init(rawValue: 7) : nil,
        input: input
    )
}

@Test func authoritativeInputFixtureDecodesCanonicalPhysicalKey() throws {
    let url = FixturePaths.authoritativeFixtures()
        .appendingPathComponent("valid/interactive-input-physical-key.json")
    let source = try Data(contentsOf: url)
    let envelope = try InteractiveInputCodec.decode(source)
    #expect(envelope.input == .physicalKey(usage: 4, transition: .down, modifiers: [.leftShift]))
    let canonicalSource = source.last == 0x0a ? Data(source.dropLast()) : source
    #expect(try InteractiveInputCodec.encode(envelope) == canonicalSource)
}

@Test func everyMVPInputVariantRoundTripsThroughClosedUnion() throws {
    let values: [InteractiveInputPayload] = [
        .pointerMove(x: 0, y: 65_535),
        .button(button: .primary, transition: .down),
        .scroll(unit: .pixel, deltaX: -20, deltaY: 40),
        .physicalKey(usage: 0x04, transition: .down, modifiers: [.leftShift]),
        .modifiers([.leftCommand, .rightOption]),
        .text("Hello, 世界"),
        .reset,
    ]
    for (index, value) in values.enumerated() {
        let envelope = try inputEnvelope(
            sequence: UInt64(index + 1),
            focus: false,
            input: value
        )
        #expect(try InteractiveInputCodec.decode(
            InteractiveInputCodec.encode(envelope)
        ) == envelope)
    }
}

@Test func textFixtureWithoutAccessibilityFocusIsValid() throws {
    let url = FixturePaths.authoritativeFixtures()
        .appendingPathComponent("valid/interactive-input-text-without-focus.json")
    let envelope = try InteractiveInputCodec.decode(Data(contentsOf: url))
    #expect(envelope.input == .text("secret"))
    #expect(envelope.focusToken == nil)
    #expect(envelope.focusRevision == nil)
}

@Test func balancedButtonKeyAndResetStateIsExplicit() throws {
    var state = InteractiveInputStreamState()
    try state.admit(
        inputEnvelope(sequence: 1, input: .button(button: .primary, transition: .down)),
        hostUnlocked: true,
        hostMonotonicMilliseconds: 10
    )
    try state.admit(
        inputEnvelope(sequence: 2, input: .physicalKey(usage: 4, transition: .down, modifiers: [.leftShift])),
        hostUnlocked: true,
        hostMonotonicMilliseconds: 11
    )
    #expect(state.pressedButtons == [.primary])
    #expect(state.pressedKeyboardUsages == [4])
    try state.admit(
        inputEnvelope(sequence: 3, input: .reset),
        hostUnlocked: true,
        hostMonotonicMilliseconds: 12
    )
    #expect(state.pressedButtons.isEmpty)
    #expect(state.pressedKeyboardUsages.isEmpty)
    #expect(state.modifierMask.isEmpty)
}

@Test func streamRejectsSequenceTimeTransitionAndLockViolationsWithoutMutation() throws {
    var state = InteractiveInputStreamState()
    try state.admit(
        inputEnvelope(sequence: 1, time: 10, input: .button(button: .primary, transition: .down)),
        hostUnlocked: true,
        hostMonotonicMilliseconds: 10
    )
    #expect(throws: InteractiveInputStreamError.sequenceMismatch(expected: 2, actual: 3)) {
        try state.admit(
            inputEnvelope(sequence: 3, input: .reset),
            hostUnlocked: true,
            hostMonotonicMilliseconds: 11
        )
    }
    #expect(throws: InteractiveInputStreamError.repeatedButtonDown) {
        try state.admit(
            inputEnvelope(sequence: 2, time: 11, input: .button(button: .primary, transition: .down)),
            hostUnlocked: true,
            hostMonotonicMilliseconds: 11
        )
    }
    #expect(state.lastSequence == 1)
    #expect(throws: InteractiveInputStreamError.textDeniedWhileLocked) {
        try state.admit(
            inputEnvelope(sequence: 2, time: 11, input: .text("secret")),
            hostUnlocked: false,
            hostMonotonicMilliseconds: 11
        )
    }
    #expect(state.lastSequence == 1)
}

@Test func slidingWindowEnforcesIndependentPointerAndTotalLimits() throws {
    var pointerState = InteractiveInputStreamState()
    for sequence in 1...120 {
        try pointerState.admit(
            inputEnvelope(sequence: UInt64(sequence), input: .pointerMove(x: 1, y: 1)),
            hostUnlocked: true,
            hostMonotonicMilliseconds: 1_000
        )
    }
    #expect(throws: InteractiveInputStreamError.pointerRateExceeded) {
        try pointerState.admit(
            inputEnvelope(sequence: 121, input: .pointerMove(x: 1, y: 1)),
            hostUnlocked: true,
            hostMonotonicMilliseconds: 1_999
        )
    }
    try pointerState.admit(
        inputEnvelope(sequence: 121, input: .pointerMove(x: 1, y: 1)),
        hostUnlocked: true,
        hostMonotonicMilliseconds: 2_000
    )

    var totalState = InteractiveInputStreamState()
    for sequence in 1...240 {
        try totalState.admit(
            inputEnvelope(sequence: UInt64(sequence), input: .modifiers([])),
            hostUnlocked: true,
            hostMonotonicMilliseconds: 1_000
        )
    }
    #expect(throws: InteractiveInputStreamError.totalRateExceeded) {
        try totalState.admit(
            inputEnvelope(sequence: 241, input: .reset),
            hostUnlocked: true,
            hostMonotonicMilliseconds: 1_999
        )
    }
}
