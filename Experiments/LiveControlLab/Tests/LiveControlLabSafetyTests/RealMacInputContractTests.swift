import CompanionInteractiveWire
import Testing
@testable import LiveControlTestHost

@Test func realMacInputAllowsOnlyTheBoundedScenario() throws {
    for payload: InteractiveInputPayload in [
        .pointerMove(x: 0, y: .max), .reset,
        .button(button: .primary, transition: .down), .button(button: .primary, transition: .up),
        .physicalKey(usage: 0x28, transition: .down, modifiers: []),
        .physicalKey(usage: 0x28, transition: .up, modifiers: []),
        .text("hello world"), .text("abc ")
    ] { try RealMacInputContract.validate(payload) }
}

@Test func realMacInputRejectsUnscopedActions() {
    for payload: InteractiveInputPayload in [
        .button(button: .secondary, transition: .down),
        .physicalKey(usage: 0x14, transition: .down, modifiers: .leftCommand),
        .physicalKey(usage: 0x28, transition: .down, modifiers: .leftCommand),
        .modifiers(.leftControl), .scroll(unit: .pixel, deltaX: 0, deltaY: 1),
        .text(""), .text(String(repeating: "a", count: 65)), .text("\n"), .text("\u{1b}"), .text("🔒")
    ] { #expect(throws: RealMacLabError.self) { try RealMacInputContract.validate(payload) } }
}

@Test func receivingTextNotSendingTextDeterminesTheResult() {
    let feedback = RealMacFeedback()
    #expect(!feedback.snapshot().1)
    feedback.received(button: false, returnKey: false)
    #expect(!feedback.snapshot().1)
    feedback.changed("hello world")
    #expect(feedback.snapshot().1)
    #expect(!feedback.snapshot().2)
    feedback.changed("hello worldabc ")
    #expect(feedback.snapshot().2)
    feedback.received(button: true, returnKey: true)
    #expect(!feedback.snapshot().3)
    feedback.received(button: true, returnKey: true)
    feedback.changed("hello worldabc \n")
    #expect(feedback.snapshot().3 && feedback.snapshot().4)
    feedback.reset()
    #expect(feedback.snapshot().0 == 0 && !feedback.snapshot().1 && !feedback.snapshot().3)
}
