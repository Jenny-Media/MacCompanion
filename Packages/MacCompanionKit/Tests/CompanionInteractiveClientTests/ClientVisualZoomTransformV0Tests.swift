import CompanionInteractiveClient
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
