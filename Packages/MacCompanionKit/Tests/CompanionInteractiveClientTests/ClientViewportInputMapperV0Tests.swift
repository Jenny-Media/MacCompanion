import CompanionInteractiveClient
import CompanionInteractiveWire
import Testing

private func viewportMapper(
    mode: ClientInputInteractionModeV0
) throws -> ClientViewportInputMapperV0 {
    try ClientViewportInputMapperV0(
        viewport: ClientInputRectV0(x: 0, y: 0, width: 400, height: 300),
        content: ClientInputRectV0(
            x: 0,
            y: 37.5,
            width: 400,
            height: 225
        ),
        mode: mode
    )
}

@Test func directTouchMapsOnlyTheHalfOpenRenderedContent() throws {
    var mapper = try viewportMapper(mode: .directTouch)
    let payloads = try mapper.tap(
        at: ClientInputPointV0(x: 200, y: 150)
    )
    #expect(payloads == [
        .pointerMove(x: 32_768, y: 32_768),
        .button(button: .primary, transition: .down),
        .button(button: .primary, transition: .up),
    ])
    #expect(
        throws: ClientViewportInputMapperErrorV0.pointOutsideContent
    ) {
        _ = try mapper.directMove(
            to: ClientInputPointV0(x: 200, y: 20)
        )
    }
    #expect(
        throws: ClientViewportInputMapperErrorV0.pointOutsideContent
    ) {
        _ = try mapper.directMove(
            to: ClientInputPointV0(x: 400, y: 150)
        )
    }
}

@Test func trackpadMotionAccumulatesAndSaturatesWithoutAHostCursor() throws {
    var mapper = try viewportMapper(mode: .trackpad)
    #expect(try mapper.trackpadMove(
        delta: ClientInputPointV0(x: 100, y: -56.25)
    ) == .pointerMove(x: 49_152, y: 16_384))
    #expect(try mapper.trackpadMove(
        delta: ClientInputPointV0(x: 10_000, y: -10_000)
    ) == .pointerMove(x: 65_535, y: 0))
    #expect(try mapper.tap() == [
        .button(button: .primary, transition: .down),
        .button(button: .primary, transition: .up),
    ])
}

@Test func dragIsBalancedAndModeSwitchResetsHeldState() throws {
    var mapper = try viewportMapper(mode: .directTouch)
    #expect(try mapper.beginDirectDrag(
        at: ClientInputPointV0(x: 0, y: 37.5)
    ) == [
        .pointerMove(x: 0, y: 0),
        .button(button: .primary, transition: .down),
    ])
    #expect(throws: ClientViewportInputMapperErrorV0.dragAlreadyActive) {
        _ = try mapper.beginDirectDrag(
            at: ClientInputPointV0(x: 20, y: 50)
        )
    }
    #expect(mapper.setMode(.trackpad) == [.reset])
    #expect(mapper.heldDragButton == nil)
    #expect(throws: ClientViewportInputMapperErrorV0.dragNotActive) {
        _ = try mapper.endDrag()
    }

    #expect(try mapper.beginTrackpadDrag(button: .secondary) == [
        .button(button: .secondary, transition: .down),
    ])
    #expect(try mapper.endDrag()
        == .button(button: .secondary, transition: .up))
}

@Test func scrollAndKeyboardMappingsAreClosedAndBounded() throws {
    let mapper = try viewportMapper(mode: .trackpad)
    #expect(try mapper.scroll(
        delta: ClientInputPointV0(x: 9_000, y: -9_000)
    ) == .scroll(unit: .pixel, deltaX: 4_096, deltaY: -4_096))
    #expect(throws: ClientViewportInputMapperErrorV0.zeroScroll) {
        _ = try mapper.scroll(
            delta: ClientInputPointV0(x: 0.1, y: -0.1)
        )
    }
    #expect(try ClientKeyboardActionV0.deleteBackward.payloads(
        modifiers: [.leftCommand]
    ) == [
        .physicalKey(
            usage: 0x2a,
            transition: .down,
            modifiers: [.leftCommand]
        ),
        .physicalKey(
            usage: 0x2a,
            transition: .up,
            modifiers: [.leftCommand]
        ),
    ])
    #expect(try ClientKeyboardActionV0.text("hello").payloads()
        == [.text("hello")])
}

@Test func viewportGeometryAndNonfiniteInputFailBeforeMutation() throws {
    #expect(throws: ClientViewportInputMapperErrorV0.invalidGeometry) {
        _ = try ClientInputRectV0(x: 0, y: 0, width: 0, height: 10)
    }
    #expect(throws: ClientViewportInputMapperErrorV0.invalidGeometry) {
        _ = try ClientViewportInputMapperV0(
            viewport: ClientInputRectV0(
                x: 0, y: 0, width: 100, height: 100
            ),
            content: ClientInputRectV0(
                x: 90, y: 0, width: 20, height: 100
            ),
            mode: .directTouch
        )
    }
    #expect(throws: ClientViewportInputMapperErrorV0.nonFiniteInput) {
        _ = try ClientInputPointV0(x: .infinity, y: 0)
    }
    #expect(throws: ClientViewportInputMapperErrorV0.invalidSensitivity) {
        _ = try ClientViewportInputMapperV0(
            viewport: ClientInputRectV0(
                x: 0, y: 0, width: 100, height: 100
            ),
            content: ClientInputRectV0(
                x: 0, y: 0, width: 100, height: 100
            ),
            mode: .trackpad,
            trackpadSensitivity: 4.1
        )
    }
}
