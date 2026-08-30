#if os(macOS)
import CompanionInteractiveShared
@testable import CompanionMacApplicationPlatform
import Foundation
import Testing

private func reuseGuardFocusV1(token: UUID) throws -> SurfaceFocus {
    try SurfaceFocus(
        token: token,
        revision: .init(rawValue: 1),
        category: .text,
        bounds: NormalizedSurfaceRect(
            x: 10_000,
            y: 10_000,
            width: 20_000,
            height: 8_000
        ),
        editable: true,
        secure: false
    )
}

@Test func repeatedPendingFocusSampleDoesNotRestoreActiveFocus() throws {
    let activeFocus = try reuseGuardFocusV1(token: UUID())
    let pendingFocus = try reuseGuardFocusV1(token: UUID())

    #expect(!MacInteractiveFocusReuseGuardV1.shouldReuseActiveFocus(
        activeKind: .focusedRegion,
        activeFocus: activeFocus,
        lastFocus: pendingFocus,
        fingerprintMatches: true
    ))
}

@Test func stableCommittedFocusSampleReusesActiveFocus() throws {
    let activeFocus = try reuseGuardFocusV1(token: UUID())

    #expect(MacInteractiveFocusReuseGuardV1.shouldReuseActiveFocus(
        activeKind: .focusedRegion,
        activeFocus: activeFocus,
        lastFocus: activeFocus,
        fingerprintMatches: true
    ))
}
#endif
