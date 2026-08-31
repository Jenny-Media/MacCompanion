import CompanionInteractiveClient
import CompanionInteractiveShared
import Foundation
import Testing

private func zoomRect(
    x: Double,
    y: Double,
    width: Double,
    height: Double
) throws -> ClientInputRectV0 {
    try ClientInputRectV0(x: x, y: y, width: width, height: height)
}

@Test func visualZoomKeepsItsAnchorStableThroughInverseMapping() throws {
    let viewport = try zoomRect(x: 0, y: 0, width: 400, height: 800)
    let content = try zoomRect(
        x: 0,
        y: 287.5,
        width: 400,
        height: 225
    )
    let initial = try ClientVisualZoomTransformV0(
        viewport: viewport,
        content: content
    )
    let anchor = try ClientInputPointV0(x: 100, y: 400)
    let zoomed = try initial.zoomed(to: 2, around: anchor)

    #expect(zoomed.scale == 2)
    #expect(zoomed.translation.x == 100)
    #expect(zoomed.translation.y == 0)
    #expect(try zoomed.mappingToUnzoomed(anchor) == anchor)
    #expect(try zoomed.mappingDeltaToUnzoomed(
        ClientInputPointV0(x: 20, y: -10)
    ) == ClientInputPointV0(x: 10, y: -5))
}

@Test func visualZoomClampsPanToVisibleContentAndResetsAtFit() throws {
    let viewport = try zoomRect(x: 0, y: 0, width: 400, height: 800)
    let content = try zoomRect(
        x: 0,
        y: 287.5,
        width: 400,
        height: 225
    )
    let center = try ClientInputPointV0(x: 200, y: 400)
    let initial = try ClientVisualZoomTransformV0(
        viewport: viewport,
        content: content
    )
    let zoomed = try initial.zoomed(to: 4, around: center)
    let panned = try zoomed.panned(by:
        ClientInputPointV0(x: 10_000, y: 10_000)
    )

    #expect(panned.translation.x == 600)
    #expect(panned.translation.y == 50)
    let fit = try panned.zoomed(to: 1, around: center)
    #expect(fit.scale == 1)
    #expect(fit.translation.x == 0)
    #expect(fit.translation.y == 0)
    let mapped = try fit.mappingToUnzoomed(
        ClientInputPointV0(x: 25, y: 325)
    )
    #expect(mapped.x == 25)
    #expect(mapped.y == 325)
}

@Test func visualZoomFocusCentersTargetAndPreservesSurroundingContext()
    throws
{
    let viewport = try zoomRect(x: 0, y: 0, width: 400, height: 800)
    let initial = try ClientVisualZoomTransformV0(
        viewport: viewport,
        content: viewport
    )
    let focused = try initial.focused(
        on: zoomRect(x: 230, y: 300, width: 40, height: 40)
    )

    #expect(focused.scale == 2.25)
    let expectedTranslation = try ClientInputPointV0(
        x: -112.5,
        y: 180
    )
    #expect(focused.translation == expectedTranslation)
    #expect(try focused.mappingToUnzoomed(
        ClientInputPointV0(x: 200, y: 400)
    ) == ClientInputPointV0(x: 250, y: 320))
}

@Test func normalizedFocusAtEveryContentEdgeDoesNotOvershoot() throws {
    let viewport = try zoomRect(x: 0, y: 0, width: 1_024, height: 1_366)
    let content = try zoomRect(
        x: 0,
        y: 395,
        width: 1_024,
        height: 576
    )
    let initial = try ClientVisualZoomTransformV0(
        viewport: viewport,
        content: content
    )
    let edgeTargets = [
        try NormalizedSurfaceRect(
            x: 0, y: 0, width: 1_535, height: 1_535
        ),
        try NormalizedSurfaceRect(
            x: 64_000, y: 0, width: 1_535, height: 1_535
        ),
        try NormalizedSurfaceRect(
            x: 0, y: 64_000, width: 1_535, height: 1_535
        ),
        try NormalizedSurfaceRect(
            x: 64_000, y: 64_000, width: 1_535, height: 1_535
        ),
    ]

    for target in edgeTargets {
        let focused = try initial.focused(onNormalized: target)
        #expect((1...ClientVisualZoomTransformV0.maximumScale)
            .contains(focused.scale))
        #expect(focused.content == content)
    }
}

@Test func normalizedFocusChurnAcrossDynamicViewportsRemainsValid() throws {
    let viewports = [
        try zoomRect(x: 0, y: 0, width: 393, height: 852),
        try zoomRect(x: 0, y: 0, width: 852, height: 393),
        try zoomRect(x: 0, y: 0, width: 1_024, height: 1_366),
    ]
    let targets = [
        try NormalizedSurfaceRect(
            x: 1, y: 1, width: 8_191, height: 2_047
        ),
        try NormalizedSurfaceRect(
            x: 28_000, y: 31_000, width: 9_000, height: 3_000
        ),
        try NormalizedSurfaceRect(
            x: 60_000, y: 62_000, width: 5_535, height: 3_535
        ),
    ]

    for viewport in viewports {
        let transform = try ClientVisualZoomTransformV0(
            viewport: viewport,
            content: viewport
        )
        for _ in 0..<100 {
            for target in targets {
                _ = try transform.focused(onNormalized: target)
            }
        }
    }
}

@Test func visualZoomEdgePanTracksEveryViewportEdgeWithBoundedSteps() throws {
    let viewport = try zoomRect(x: 0, y: 0, width: 400, height: 800)

    #expect(try ClientVisualZoomEdgePanV0.delta(
        for: ClientInputPointV0(x: 200, y: 400),
        in: viewport
    ) == ClientInputPointV0(x: 0, y: 0))
    #expect(try ClientVisualZoomEdgePanV0.delta(
        for: ClientInputPointV0(x: 20, y: 24),
        in: viewport
    ) == ClientInputPointV0(x: 28, y: 24))
    #expect(try ClientVisualZoomEdgePanV0.delta(
        for: ClientInputPointV0(x: 380, y: 776),
        in: viewport
    ) == ClientInputPointV0(x: -28, y: -24))
    #expect(try ClientVisualZoomEdgePanV0.delta(
        for: ClientInputPointV0(x: -100, y: 900),
        in: viewport
    ) == ClientInputPointV0(x: 32, y: -32))
}

@Test func visualZoomEdgePanRevealsOnlyAxesWithHiddenContent() throws {
    let viewport = try zoomRect(x: 0, y: 0, width: 400, height: 800)
    let content = try zoomRect(
        x: 0,
        y: 287.5,
        width: 400,
        height: 225
    )
    let zoomed = try ClientVisualZoomTransformV0(
        viewport: viewport,
        content: content,
        scale: 2
    )
    let edgeDelta = try ClientVisualZoomEdgePanV0.delta(
        for: ClientInputPointV0(x: 399, y: 799),
        in: viewport
    )
    let panned = try zoomed.panned(by: edgeDelta)

    #expect(panned.translation.x == -32)
    // At 2x the letterboxed desktop is still fully visible vertically, so the
    // transform clamps vertical edge tracking instead of moving into blanking.
    #expect(panned.translation.y == 0)
}

@Test func visualZoomEdgePanRejectsInvalidTuning() throws {
    let viewport = try zoomRect(x: 0, y: 0, width: 400, height: 800)
    let point = try ClientInputPointV0(x: 0, y: 0)

    #expect(throws: ClientVisualZoomTransformErrorV0.invalidGeometry) {
        _ = try ClientVisualZoomEdgePanV0.delta(
            for: point,
            in: viewport,
            activationInset: .infinity
        )
    }
    #expect(throws: ClientVisualZoomTransformErrorV0.invalidGeometry) {
        _ = try ClientVisualZoomEdgePanV0.delta(
            for: point,
            in: viewport,
            maximumStep: 0
        )
    }
}

@Test func visualZoomRejectsInvalidScaleAndNoncontainedContent() throws {
    let viewport = try zoomRect(x: 0, y: 0, width: 400, height: 800)
    let content = try zoomRect(x: 0, y: 0, width: 400, height: 800)

    #expect(throws: ClientVisualZoomTransformErrorV0.invalidScale) {
        _ = try ClientVisualZoomTransformV0(
            viewport: viewport,
            content: content,
            scale: .infinity
        )
    }
    #expect(throws: ClientVisualZoomTransformErrorV0.invalidGeometry) {
        _ = try ClientVisualZoomTransformV0(
            viewport: viewport,
            content: zoomRect(
                x: -1,
                y: 0,
                width: 400,
                height: 800
            )
        )
    }
}
