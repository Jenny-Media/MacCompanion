#if os(macOS)
import CompanionHostPlatform
import CoreGraphics
import Testing

@Test func focusedRegionCropAddsContextAndTranslatesDisplayOrigin()
    throws
{
    let crop = try ScreenCaptureKitFocusedRegionCropV0(
        focusGlobalBounds: CGRect(x: 1_200, y: 260, width: 200, height: 40),
        sourceGlobalBounds: CGRect(x: 1_000, y: 100, width: 1_440, height: 900),
        pointPixelScale: 2
    )
    #expect(crop.globalBounds == CGRect(
        x: 1_130, y: 190, width: 340, height: 180
    ))
    #expect(crop.sourceRect == CGRect(x: 130, y: 90, width: 340, height: 180))
    #expect(crop.profile.width == 680)
    #expect(crop.profile.height == 360)
}

@Test func focusedRegionCropClampsAtSourceEdgeWithoutClippingFocus()
    throws
{
    let focus = CGRect(x: 5, y: 8, width: 80, height: 30)
    let crop = try ScreenCaptureKitFocusedRegionCropV0(
        focusGlobalBounds: focus,
        sourceGlobalBounds: CGRect(x: 0, y: 0, width: 1_000, height: 700),
        pointPixelScale: 1
    )
    #expect(crop.globalBounds == CGRect(x: 0, y: 0, width: 320, height: 180))
    #expect(crop.globalBounds.contains(focus))
    #expect(crop.sourceRect == crop.globalBounds)
}

@Test func focusedRegionCropBoundsLargeFocusAndCaptureProfile() throws {
    let crop = try ScreenCaptureKitFocusedRegionCropV0(
        focusGlobalBounds: CGRect(x: 100, y: 100, width: 1_500, height: 800),
        sourceGlobalBounds: CGRect(x: 0, y: 0, width: 2_560, height: 1_440),
        pointPixelScale: 2
    )
    #expect(crop.globalBounds.contains(
        CGRect(x: 100, y: 100, width: 1_500, height: 800)
    ))
    #expect(crop.profile.width <= 1_920)
    #expect(crop.profile.height <= 1_200)
    #expect(crop.profile.width * crop.profile.height <= 2_304_000)
}

@Test func focusedRegionCropRejectsOutsideAndUnsafeGeometry() {
    #expect(throws: ScreenCaptureKitFocusedRegionCropErrorV0.focusOutsideSource) {
        _ = try ScreenCaptureKitFocusedRegionCropV0(
            focusGlobalBounds: CGRect(x: 900, y: 600, width: 200, height: 200),
            sourceGlobalBounds: CGRect(x: 0, y: 0, width: 1_000, height: 700),
            pointPixelScale: 1
        )
    }
    #expect(throws: ScreenCaptureKitFocusedRegionCropErrorV0.invalidGeometry) {
        _ = try ScreenCaptureKitFocusedRegionCropV0(
            focusGlobalBounds: CGRect(x: 1, y: 1, width: 10, height: 10),
            sourceGlobalBounds: CGRect(x: 0, y: 0, width: 100, height: 100),
            pointPixelScale: .nan
        )
    }
}

@available(macOS 13.0, *)
@Test func focusedRegionSourceRectReachesStreamConfiguration() throws {
    let profile = try ScreenCaptureKitCaptureProfileV0(
        width: 640,
        height: 360,
        framesPerSecond: 30,
        queueDepth: 3
    )
    let sourceRect = CGRect(x: 100, y: 50, width: 320, height: 180)
    let configuration = ScreenCaptureKitCaptureConfigurationV0
        .makeStreamConfiguration(
            profile: profile,
            sourceRect: sourceRect
        )
    #expect(configuration.sourceRect == sourceRect)
}
#endif
