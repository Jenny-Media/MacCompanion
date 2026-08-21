import CompanionDomain
import CompanionHostPlatform
import Foundation
import Testing

@available(macOS 13.0, *)
@Test func opaqueCatalogRequiresAnExplicitSelfExclusion() throws {
    #expect(
        throws:
            ScreenCaptureKitOpaqueTargetCatalogErrorV0.invalidConfiguration
    ) {
        _ = try ScreenCaptureKitOpaqueTargetCatalogV0(
            interactiveSessionID: UUID(),
            authorizationEpoch: .init(rawValue: 1),
            selectedDisplayID: 1,
            excludedBundleIdentifiers: [],
            excludedProcessIdentifiers: []
        )
    }
    _ = try ScreenCaptureKitOpaqueTargetCatalogV0(
        interactiveSessionID: UUID(),
        authorizationEpoch: .init(rawValue: 1),
        selectedDisplayID: 1,
        excludedBundleIdentifiers: ["invalid.fixture.menu"],
        excludedProcessIdentifiers: []
    )
}

@available(macOS 13.0, *)
@Test func opaqueCatalogCaptureProfilePreservesAspectWithinBounds() throws {
    let wide = try ScreenCaptureKitOpaqueTargetCatalogV0.captureProfile(
        logicalWidth: 3_840,
        logicalHeight: 2_160
    )
    #expect(wide.width == 1_920)
    #expect(wide.height == 1_080)
    #expect(wide.framesPerSecond == 30)
    #expect(wide.queueDepth == 3)

    let small = try ScreenCaptureKitOpaqueTargetCatalogV0.captureProfile(
        logicalWidth: 800,
        logicalHeight: 600
    )
    #expect(small.width == 800)
    #expect(small.height == 600)
}
