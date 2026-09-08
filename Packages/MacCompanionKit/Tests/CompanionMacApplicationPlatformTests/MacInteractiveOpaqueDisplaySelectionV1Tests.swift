#if os(macOS)
@testable import CompanionMacApplicationPlatform
import CoreGraphics
import Foundation
import Testing

@Test
@available(macOS 14.0, *)
func opaqueDisplaySelectionNeverRedirectsAfterDisplayLoss() throws {
    let opaqueID = UUID()
    let physicalID: CGDirectDisplayID = 77
    let online = DisplayOnlineProbeV1(online: true)
    let selection = try MacInteractiveOpaqueDisplaySelectionV1(
        physicalDisplayID: physicalID,
        opaqueID: opaqueID,
        isDisplayOnline: { _ in online.value() }
    )

    #expect(selection.opaqueSelectedDisplayID() == opaqueID)
    #expect(
        try selection.resolvePhysicalDisplayID(
            selectedDisplayID: opaqueID
        ) == physicalID
    )
    #expect(throws: MacInteractiveOpaqueDisplaySelectionErrorV1.self) {
        _ = try selection.resolvePhysicalDisplayID(
            selectedDisplayID: UUID()
        )
    }

    online.set(false)
    #expect(selection.opaqueSelectedDisplayID() == nil)
    online.set(true)
    #expect(selection.opaqueSelectedDisplayID() == nil)
    #expect(throws: MacInteractiveOpaqueDisplaySelectionErrorV1.self) {
        _ = try selection.resolvePhysicalDisplayID(
            selectedDisplayID: opaqueID
        )
    }
}

@Test
@available(macOS 14.0, *)
func opaqueDisplaySelectionRejectsUnavailableConstructionAndInvalidation()
    throws
{
    #expect(throws: MacInteractiveOpaqueDisplaySelectionErrorV1.self) {
        _ = try MacInteractiveOpaqueDisplaySelectionV1(
            physicalDisplayID: 0,
            opaqueID: UUID(),
            isDisplayOnline: { _ in true }
        )
    }
    let selection = try MacInteractiveOpaqueDisplaySelectionV1(
        physicalDisplayID: 5,
        opaqueID: UUID(),
        isDisplayOnline: { _ in true }
    )
    selection.invalidate()
    #expect(selection.opaqueSelectedDisplayID() == nil)
}

@Test
@available(macOS 14.0, *)
func opaqueDisplaySelectionEnumeratesSwitchesAndNeverRedirectsOnLoss()
    throws
{
    let mainOpaqueID = UUID()
    let secondaryOpaqueID = UUID()
    let displays = DisplayListProbeV1([
        .init(
            id: 22,
            pixelWidth: 2_560,
            pixelHeight: 1_440,
            layoutX: 1_512,
            layoutY: -229,
            layoutWidth: 2_560,
            layoutHeight: 1_440,
            isMain: false
        ),
        .init(
            id: 11,
            pixelWidth: 3_024,
            pixelHeight: 1_964,
            layoutX: 0,
            layoutY: 0,
            layoutWidth: 1_512,
            layoutHeight: 982,
            isMain: true
        ),
    ])
    let selection = try MacInteractiveOpaqueDisplaySelectionV1(
        initialOpaqueIDs: [
            11: mainOpaqueID,
            22: secondaryOpaqueID,
        ],
        onlineDisplays: { displays.value() }
    )

    #expect(selection.opaqueSelectedDisplayID() == mainOpaqueID)
    #expect(selection.availableDisplays() == [
        .init(
            id: mainOpaqueID,
            name: "Main Display",
            pixelWidth: 3_024,
            pixelHeight: 1_964,
            layoutX: 0,
            layoutY: 0,
            layoutWidth: 1_512,
            layoutHeight: 982,
            isMain: true
        ),
        .init(
            id: secondaryOpaqueID,
            name: "Display 2",
            pixelWidth: 2_560,
            pixelHeight: 1_440,
            layoutX: 1_512,
            layoutY: -229,
            layoutWidth: 2_560,
            layoutHeight: 1_440,
            isMain: false
        ),
    ])

    try selection.selectDisplay(id: secondaryOpaqueID)
    #expect(
        try selection.resolvePhysicalDisplayID(
            selectedDisplayID: secondaryOpaqueID
        ) == 22
    )

    displays.set([
        .init(
            id: 11,
            pixelWidth: 3_024,
            pixelHeight: 1_964,
            layoutX: 0,
            layoutY: 0,
            layoutWidth: 1_512,
            layoutHeight: 982,
            isMain: true
        ),
    ])
    #expect(selection.opaqueSelectedDisplayID() == nil)
    #expect(selection.availableDisplays().map(\.id) == [mainOpaqueID])
    #expect(throws: MacInteractiveOpaqueDisplaySelectionErrorV1.self) {
        _ = try selection.resolvePhysicalDisplayID(
            selectedDisplayID: secondaryOpaqueID
        )
    }
}

private final class DisplayOnlineProbeV1: @unchecked Sendable {
    private let lock = NSLock()
    private var online: Bool

    init(online: Bool) { self.online = online }

    func value() -> Bool { lock.withLock { online } }
    func set(_ value: Bool) { lock.withLock { online = value } }
}

private final class DisplayListProbeV1: @unchecked Sendable {
    private let lock = NSLock()
    private var displays:
        [MacInteractiveOpaqueDisplaySelectionV1.PhysicalDisplay]

    init(
        _ displays:
            [MacInteractiveOpaqueDisplaySelectionV1.PhysicalDisplay]
    ) {
        self.displays = displays
    }

    func value()
        -> [MacInteractiveOpaqueDisplaySelectionV1.PhysicalDisplay]
    {
        lock.withLock { displays }
    }

    func set(
        _ value:
            [MacInteractiveOpaqueDisplaySelectionV1.PhysicalDisplay]
    ) {
        lock.withLock { displays = value }
    }
}
#endif
