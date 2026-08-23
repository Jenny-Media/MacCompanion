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

private final class DisplayOnlineProbeV1: @unchecked Sendable {
    private let lock = NSLock()
    private var online: Bool

    init(online: Bool) { self.online = online }

    func value() -> Bool { lock.withLock { online } }
    func set(_ value: Bool) { lock.withLock { online = value } }
}
#endif
