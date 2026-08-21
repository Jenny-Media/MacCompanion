import CompanionHostPlatform
import CompanionInteractiveWire
import Testing

@Test func HIDMappingUsesMacVirtualKeyCodesAndRejectsUnsupportedUsages() throws {
    #expect(try MacInteractiveInputPlannerV0.virtualKeyCode(for: 0x04) == 0)
    #expect(try MacInteractiveInputPlannerV0.virtualKeyCode(for: 0x1d) == 6)
    #expect(try MacInteractiveInputPlannerV0.virtualKeyCode(for: 0x1e) == 18)
    #expect(try MacInteractiveInputPlannerV0.virtualKeyCode(for: 0x3a) == 122)
    #expect(try MacInteractiveInputPlannerV0.virtualKeyCode(for: 0x4f) == 124)
    #expect(try MacInteractiveInputPlannerV0.virtualKeyCode(for: 0xe7) == 54)
    #expect(throws: MacInteractiveInputPlanErrorV0.unsupportedHIDUsage(0x46)) {
        try MacInteractiveInputPlannerV0.virtualKeyCode(for: 0x46)
    }
}

@Test func plannerMapsClosedInputUnionWithoutPosting() throws {
    var planner = MacInteractiveInputPlannerV0()
    #expect(try planner.plan(.pointerMove(x: 10, y: 20)) == [
        .pointerMove(x: 10, y: 20),
    ])
    #expect(try planner.plan(.scroll(
        unit: .pixel,
        deltaX: 1,
        deltaY: -2
    )) == [.scroll(unit: .pixel, deltaX: 1, deltaY: -2)])
    #expect(try planner.plan(.text("hello")) == [.unicodeText("hello")])
    #expect(try planner.plan(.modifiers([.leftShift])) == [
        .key(
            virtualKeyCode: 56,
            transition: .down,
            modifiers: [.leftShift]
        ),
    ])
}

@Test func resetExpandsEveryHeldInputIntoDeterministicReleases() throws {
    var planner = MacInteractiveInputPlannerV0()
    _ = try planner.plan(.button(button: .secondary, transition: .down))
    _ = try planner.plan(.button(button: .primary, transition: .down))
    _ = try planner.plan(.physicalKey(
        usage: 0x05,
        transition: .down,
        modifiers: [.leftShift]
    ))
    _ = try planner.plan(.physicalKey(
        usage: 0x04,
        transition: .down,
        modifiers: [.leftShift]
    ))

    #expect(try planner.plan(.reset) == [
        .key(
            virtualKeyCode: 0,
            transition: .up,
            modifiers: [.leftShift]
        ),
        .key(
            virtualKeyCode: 11,
            transition: .up,
            modifiers: [.leftShift]
        ),
        .key(virtualKeyCode: 56, transition: .up, modifiers: []),
        .button(button: .primary, transition: .up),
        .button(button: .secondary, transition: .up),
    ])
    #expect(planner.pressedButtons.isEmpty)
    #expect(planner.pressedHIDUsages.isEmpty)
    #expect(planner.modifiers.isEmpty)
    #expect(try planner.plan(.reset).isEmpty)
}

@Test func completeModifierMasksExpandToBalancedLeftAndRightKeys() throws {
    var planner = MacInteractiveInputPlannerV0()
    #expect(try planner.plan(.modifiers([
        .leftShift, .rightCommand,
    ])) == [
        .key(
            virtualKeyCode: 56,
            transition: .down,
            modifiers: [.leftShift]
        ),
        .key(
            virtualKeyCode: 54,
            transition: .down,
            modifiers: [.leftShift, .rightCommand]
        ),
    ])
    #expect(try planner.plan(.modifiers([.rightCommand])) == [
        .key(
            virtualKeyCode: 56,
            transition: .up,
            modifiers: [.rightCommand]
        ),
    ])
}

@Test func plannerDefensivelyRejectsUnbalancedTransitions() throws {
    var planner = MacInteractiveInputPlannerV0()
    #expect(throws: MacInteractiveInputPlanErrorV0.unmatchedButtonUp(.primary)) {
        try planner.plan(.button(button: .primary, transition: .up))
    }
    #expect(throws: MacInteractiveInputPlanErrorV0.unmatchedKeyUp(0x04)) {
        try planner.plan(.physicalKey(
            usage: 0x04,
            transition: .up,
            modifiers: []
        ))
    }
}
