import CompanionInteractiveClient
import Testing

@Test func aspectFitUsesWholeViewportForMatchingAspect() throws {
    let viewport = try ClientInputRectV0(
        x: 10,
        y: 20,
        width: 320,
        height: 180
    )
    #expect(try ClientAspectFitGeometryV0.contentRect(
        viewport: viewport,
        encodedWidth: 1_280,
        encodedHeight: 720
    ) == viewport)
}

@Test func aspectFitCentersLetterboxedContent() throws {
    let content = try ClientAspectFitGeometryV0.contentRect(
        viewport: try .init(x: 0, y: 0, width: 400, height: 400),
        encodedWidth: 1_600,
        encodedHeight: 900
    )
    #expect(content.x == 0)
    #expect(content.y == 87.5)
    #expect(content.width == 400)
    #expect(content.height == 225)
}

@Test func aspectFitCentersPillarboxedContent() throws {
    let content = try ClientAspectFitGeometryV0.contentRect(
        viewport: try .init(x: 5, y: 7, width: 600, height: 300),
        encodedWidth: 900,
        encodedHeight: 1_600
    )
    #expect(content.x == 220.625)
    #expect(content.y == 7)
    #expect(content.width == 168.75)
    #expect(content.height == 300)
}

@Test func aspectFitCanonicalizesFloatingPointEdgeOvershoot() throws {
    let viewport = try ClientInputRectV0(
        x: 0,
        y: 0,
        width: 393,
        height: 852
    )
    let content = try ClientAspectFitGeometryV0.contentRect(
        viewport: viewport,
        encodedWidth: 100,
        encodedHeight: 295
    )

    #expect(content.y == viewport.y)
    #expect(content.height == viewport.height)
    #expect(content.x >= viewport.x)
    #expect(content.x + content.width <= viewport.x + viewport.width)
    #expect(throws: Never.self) {
        _ = try ClientViewportInputMapperV0(
            viewport: viewport,
            content: content,
            mode: .directTouch
        )
    }
}

@Test func aspectFitRejectsMissingEncodedDimensions() throws {
    #expect(throws: ClientViewportInputMapperErrorV0.invalidGeometry) {
        _ = try ClientAspectFitGeometryV0.contentRect(
            viewport: try .init(x: 0, y: 0, width: 100, height: 100),
            encodedWidth: 0,
            encodedHeight: 100
        )
    }
}
