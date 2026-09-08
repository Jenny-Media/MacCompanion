@testable import CompanionClientUI
import CompanionInteractiveWire
import CompanionWire
import CoreGraphics
import Foundation
import Testing

private func topologyDisplay(
    ordinal: UInt8,
    x: Int32,
    y: Int32,
    width: UInt16,
    height: UInt16
) throws -> InteractiveDisplayCandidateV1 {
    try .init(
        displayID: WireUUID(UUID()),
        ordinal: ordinal,
        pixelWidth: width,
        pixelHeight: height,
        layoutX: x,
        layoutY: y,
        layoutWidth: width,
        layoutHeight: height,
        isMain: ordinal == 1
    )
}

@Test func sharedDisplayTopologyPreservesHorizontalArrangementAndScale()
    throws
{
    let main = try topologyDisplay(
        ordinal: 1, x: 0, y: 0, width: 1_500, height: 1_000
    )
    let secondary = try topologyDisplay(
        ordinal: 2, x: 1_500, y: -250, width: 2_500, height: 1_500
    )
    let geometry = try #require(ClientSharedDisplayTopologyGeometryV0(
        displays: [main, secondary],
        canvasSize: CGSize(width: 440, height: 240),
        padding: 20
    ))
    let mainFrame = try #require(geometry.framesByDisplayID[main.id])
    let secondaryFrame = try #require(
        geometry.framesByDisplayID[secondary.id]
    )

    #expect(mainFrame.maxX == secondaryFrame.minX)
    #expect(secondaryFrame.minY < mainFrame.minY)
    #expect(abs(secondaryFrame.width / mainFrame.width - 5.0 / 3.0) < 0.000_001)
    #expect(abs(secondaryFrame.height / mainFrame.height - 1.5) < 0.000_001)
}

@Test func sharedDisplayTopologyPreservesVerticalAndNegativeOrigins() throws {
    let upper = try topologyDisplay(
        ordinal: 1, x: -320, y: -900, width: 1_200, height: 900
    )
    let lower = try topologyDisplay(
        ordinal: 2, x: 0, y: 0, width: 1_600, height: 1_000
    )
    let geometry = try #require(ClientSharedDisplayTopologyGeometryV0(
        displays: [upper, lower],
        canvasSize: CGSize(width: 360, height: 500)
    ))
    let upperFrame = try #require(geometry.framesByDisplayID[upper.id])
    let lowerFrame = try #require(geometry.framesByDisplayID[lower.id])

    #expect(upperFrame.maxY == lowerFrame.minY)
    #expect(upperFrame.minX < lowerFrame.minX)
    #expect(upperFrame.minX >= 20)
    #expect(lowerFrame.maxX <= 340)
}

@Test func sharedDisplayTopologyRejectsAnEmptyCatalogOrTinyCanvas() throws {
    #expect(ClientSharedDisplayTopologyGeometryV0(
        displays: [],
        canvasSize: CGSize(width: 300, height: 200)
    ) == nil)
    let display = try topologyDisplay(
        ordinal: 1, x: 0, y: 0, width: 1_200, height: 800
    )
    #expect(ClientSharedDisplayTopologyGeometryV0(
        displays: [display],
        canvasSize: CGSize(width: 30, height: 30)
    ) == nil)
}
