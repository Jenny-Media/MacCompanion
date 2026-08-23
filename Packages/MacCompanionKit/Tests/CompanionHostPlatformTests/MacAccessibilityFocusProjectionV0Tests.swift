#if os(macOS)
import CompanionHostPlatform
import CompanionInteractiveShared
import CoreGraphics
import Foundation
import Testing

@Test func accessibilityFocusProjectionKeepsOnlyClosedShape() throws {
    let projector = MacAccessibilityFocusProjectorV0()
    let token = UUID()
    let candidate = try projector.project(
        .verified(MacAccessibilityFocusObservationV0(
            category: .text,
            globalBounds: CGRect(x: 300, y: 250, width: 400, height: 100),
            editable: true,
            secure: false
        )),
        currentSurfaceGlobalBounds: CGRect(
            x: 100,
            y: 50,
            width: 1_000,
            height: 500
        ),
        focusToken: token,
        focusRevision: .init(rawValue: 3),
        inputPaused: false
    )
    #expect(candidate.recommendedTargetKind == .focusedRegion)
    #expect(candidate.reason == .verifiedFocus)
    #expect(candidate.focus?.token == token)
    #expect(candidate.focus?.revision.rawValue == 3)
    #expect(candidate.focus?.category == .text)
    #expect(candidate.focus?.editable == true)
    #expect(candidate.focus?.secure == false)
    let expectedBounds = try NormalizedSurfaceRect(
        x: 13_107,
        y: 26_214,
        width: 26_214,
        height: 13_107
    )
    #expect(candidate.focus?.bounds == expectedBounds)
}

@Test func accessibilityFocusProjectionFallsBackForUnsafeGeometry()
    throws
{
    let projector = MacAccessibilityFocusProjectorV0()
    let surface = CGRect(x: 0, y: 0, width: 1_000, height: 500)
    let clipped = try projector.project(
        .verified(MacAccessibilityFocusObservationV0(
            category: .button,
            globalBounds: CGRect(x: 900, y: 100, width: 200, height: 50),
            editable: false,
            secure: false
        )),
        currentSurfaceGlobalBounds: surface,
        focusToken: UUID(),
        focusRevision: .init(rawValue: 1),
        inputPaused: true
    )
    #expect(clipped.recommendedTargetKind == .desktop)
    #expect(clipped.focus == nil)
    #expect(clipped.reason == .ambiguousGeometry)
    #expect(clipped.inputPaused)

    let unavailable = try projector.project(
        .unavailable(.accessibilityUnavailable),
        currentSurfaceGlobalBounds: surface,
        focusToken: UUID(),
        focusRevision: .init(rawValue: 2),
        inputPaused: false
    )
    #expect(unavailable.recommendedTargetKind == .desktop)
    #expect(unavailable.reason == .accessibilityUnavailable)
}

@Test func accessibilityFocusProjectionRejectsInvalidSurfaceGeometry() {
    #expect(throws: MacAccessibilityFocusProjectionErrorV0.invalidGeometry) {
        try MacAccessibilityFocusProjectorV0().project(
            .unavailable(.noVerifiedFocus),
            currentSurfaceGlobalBounds: .zero,
            focusToken: UUID(),
            focusRevision: .init(rawValue: 1),
            inputPaused: false
        )
    }
}
#endif
