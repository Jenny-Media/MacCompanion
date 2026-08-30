#if os(macOS)
import CompanionHostPlatform
import CoreGraphics
import Testing

@Test func applicationCropUsesPaddedVisibleWindowUnion() throws {
    let crop = try ScreenCaptureKitApplicationCropV0(
        windowGlobalBounds: [
            CGRect(x: 1_200, y: 200, width: 500, height: 400),
            CGRect(x: 1_650, y: 500, width: 300, height: 250),
        ],
        sourceGlobalBounds: CGRect(x: 1_000, y: 100, width: 1_440, height: 900)
    )
    #expect(crop.globalBounds == CGRect(
        x: 1_176, y: 176, width: 798, height: 598
    ))
    #expect(crop.sourceRect == CGRect(x: 176, y: 76, width: 798, height: 598))
}

@Test func applicationCropClipsWindowsAndPaddingToDisplay() throws {
    let crop = try ScreenCaptureKitApplicationCropV0(
        windowGlobalBounds: [
            CGRect(x: -50, y: -30, width: 300, height: 200),
            CGRect(x: 900, y: 650, width: 300, height: 200),
        ],
        sourceGlobalBounds: CGRect(x: 0, y: 0, width: 1_000, height: 700)
    )
    #expect(crop.globalBounds == CGRect(x: 0, y: 0, width: 1_000, height: 700))
    #expect(crop.sourceRect == crop.globalBounds)
}

@Test func applicationCropRejectsNoVisibleContentAndInvalidSource() {
    #expect(throws: ScreenCaptureKitApplicationCropErrorV0.noVisibleContent) {
        _ = try ScreenCaptureKitApplicationCropV0(
            windowGlobalBounds: [CGRect(x: 2_000, y: 2_000, width: 100, height: 100)],
            sourceGlobalBounds: CGRect(x: 0, y: 0, width: 1_000, height: 700)
        )
    }
    #expect(throws: ScreenCaptureKitApplicationCropErrorV0.invalidGeometry) {
        _ = try ScreenCaptureKitApplicationCropV0(
            windowGlobalBounds: [],
            sourceGlobalBounds: .zero
        )
    }
}
#endif
