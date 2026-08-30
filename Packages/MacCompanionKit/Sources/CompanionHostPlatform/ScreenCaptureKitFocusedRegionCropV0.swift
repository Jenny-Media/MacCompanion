#if os(macOS)
import CoreGraphics
import Foundation

public enum ScreenCaptureKitFocusedRegionCropErrorV0:
    Error, Equatable, Sendable
{
    case invalidGeometry
    case focusOutsideSource
}

/// Pure display-logical crop planning for Smart Zoom. The global rectangle is
/// retained for input mapping; `sourceRect` is translated to the display-style
/// filter's local logical coordinate system.
public struct ScreenCaptureKitFocusedRegionCropV0: Equatable, Sendable {
    public let globalBounds: CGRect
    public let sourceRect: CGRect
    public let profile: ScreenCaptureKitCaptureProfileV0

    public init(
        focusGlobalBounds: CGRect,
        sourceGlobalBounds: CGRect,
        pointPixelScale: Double,
        minimumWidthPoints: Double = 640,
        minimumHeightPoints: Double = 480,
        minimumSourceFraction: Double = 0.5,
        minimumAspectRatio: Double = 4.0 / 3.0
    ) throws {
        guard Self.valid(focusGlobalBounds),
              Self.valid(sourceGlobalBounds),
              sourceGlobalBounds.contains(focusGlobalBounds),
              pointPixelScale.isFinite, pointPixelScale > 0,
              minimumWidthPoints.isFinite, minimumWidthPoints > 0,
              minimumHeightPoints.isFinite, minimumHeightPoints > 0,
              minimumSourceFraction.isFinite,
              minimumSourceFraction > 0,
              minimumSourceFraction <= 1,
              minimumAspectRatio.isFinite,
              minimumAspectRatio > 0 else {
            if Self.valid(focusGlobalBounds),
               Self.valid(sourceGlobalBounds),
               !sourceGlobalBounds.contains(focusGlobalBounds) {
                throw ScreenCaptureKitFocusedRegionCropErrorV0
                    .focusOutsideSource
            }
            throw ScreenCaptureKitFocusedRegionCropErrorV0.invalidGeometry
        }

        var desiredWidth = min(
            sourceGlobalBounds.width,
            max(
                minimumWidthPoints,
                sourceGlobalBounds.width * minimumSourceFraction,
                focusGlobalBounds.width * 2.5
            )
        )
        var desiredHeight = min(
            sourceGlobalBounds.height,
            max(
                minimumHeightPoints,
                sourceGlobalBounds.height * minimumSourceFraction,
                focusGlobalBounds.height * 12
            )
        )
        // Keep recognizable surrounding UI instead of turning a text field
        // into a shallow strip. Expand only; never crop away context merely to
        // force the target aspect ratio.
        if desiredWidth / desiredHeight < minimumAspectRatio {
            desiredWidth = min(
                sourceGlobalBounds.width,
                desiredHeight * minimumAspectRatio
            )
        }
        desiredWidth = min(sourceGlobalBounds.width, ceil(desiredWidth))
        desiredHeight = min(sourceGlobalBounds.height, ceil(desiredHeight))
        let centeredX = focusGlobalBounds.midX - desiredWidth / 2
        let centeredY = focusGlobalBounds.midY - desiredHeight / 2
        let minimumX = sourceGlobalBounds.minX
        let minimumY = sourceGlobalBounds.minY
        let maximumX = sourceGlobalBounds.maxX - desiredWidth
        let maximumY = sourceGlobalBounds.maxY - desiredHeight
        let originX = min(max(centeredX, minimumX), maximumX)
        let originY = min(max(centeredY, minimumY), maximumY)
        let proposed = CGRect(
            x: floor(originX),
            y: floor(originY),
            width: ceil(desiredWidth),
            height: ceil(desiredHeight)
        ).intersection(sourceGlobalBounds)
        guard Self.valid(proposed), proposed.contains(focusGlobalBounds)
        else {
            throw ScreenCaptureKitFocusedRegionCropErrorV0.invalidGeometry
        }
        let local = CGRect(
            x: proposed.minX - sourceGlobalBounds.minX,
            y: proposed.minY - sourceGlobalBounds.minY,
            width: proposed.width,
            height: proposed.height
        )
        let captureWidth = Int(
            (proposed.width * pointPixelScale).rounded(.up)
        )
        let captureHeight = Int(
            (proposed.height * pointPixelScale).rounded(.up)
        )
        globalBounds = proposed
        sourceRect = local
        profile = try ScreenCaptureKitOpaqueTargetCatalogV0.captureProfile(
            logicalWidth: captureWidth,
            logicalHeight: captureHeight
        )
    }

    private static func valid(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite
            && rect.width > 0 && rect.height > 0
    }
}
#endif
