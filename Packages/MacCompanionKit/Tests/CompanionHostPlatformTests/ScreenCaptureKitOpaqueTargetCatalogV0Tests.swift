import CompanionDomain
import CompanionHostPlatform
import CompanionInteractiveShared
import Foundation
import Testing

@Test(arguments: [1, 3, 641, 855, 1_919, 3_841], [1, 3, 361, 1_199, 2_161])
func opaqueCatalogUsesEvenEncodedDimensionsBeforeDescriptor(width: Int, height: Int) throws {
    let profile = try ScreenCaptureKitOpaqueTargetCatalogV0.captureProfile(
        logicalWidth: width, logicalHeight: height)
    #expect(profile.width >= 2 && profile.width <= 1_920 && profile.width.isMultiple(of: 2))
    #expect(profile.height >= 2 && profile.height <= 1_200 && profile.height.isMultiple(of: 2))
}

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

@Test func opaquePickerUsesIndexedCaptureEligibilityAndBoundedTitles() throws {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
        let parent = root.deletingLastPathComponent()
        try #require(parent != root)
        root = parent
    }
    let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
        root.appendingPathComponent("spec/fixtures/native-selected-capture-context-v0.1.json"))) as? [String: Any])
    for row in try #require(fixture["pickerWindowCases"] as? [[String: Any]]) {
        #expect(ScreenCaptureKitOpaqueTargetCatalogV0.isSelectableWindow(
            onScreen: try #require(row["onScreen"] as? Bool), layer: try #require(row["layer"] as? Int),
            width: try #require(row["width"] as? Double), height: try #require(row["height"] as? Double),
            scale: try #require(row["scale"] as? Double)) == (try #require(row["selectable"] as? Bool)))
    }
    for row in try #require(fixture["pickerTitleCases"] as? [[String: Any]]) {
        let title = AdaptiveSurfaceTargetObservationV0.sanitizedWindowTitle(try #require(row["input"] as? String))
        #expect(title == (row["title"] as? String))
        try AdaptiveSurfaceTargetObservationV0.validateWindowTitle(title)
    }
}
