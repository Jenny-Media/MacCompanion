#if os(macOS)
import CoreGraphics
import Foundation

public enum ScreenCaptureKitApplicationCropErrorV0:
    Error, Equatable, Sendable
{
    case invalidGeometry
    case noVisibleContent
}

/// Plans the smallest padded display-local crop that contains every visible
/// window for one application on the selected display. The application filter
/// remains authoritative; this value only removes unused display canvas.
public struct ScreenCaptureKitApplicationCropV0: Equatable, Sendable {
    public let globalBounds: CGRect
    public let sourceRect: CGRect

    public init(
        windowGlobalBounds: [CGRect],
        sourceGlobalBounds: CGRect,
        paddingPoints: Double = 24
    ) throws {
        guard Self.valid(sourceGlobalBounds),
              paddingPoints.isFinite,
              paddingPoints >= 0 else {
            throw ScreenCaptureKitApplicationCropErrorV0.invalidGeometry
        }

        let visible = windowGlobalBounds.compactMap { bounds -> CGRect? in
            guard Self.valid(bounds) else { return nil }
            let clipped = bounds.intersection(sourceGlobalBounds)
            return Self.valid(clipped) ? clipped : nil
        }
        guard let first = visible.first else {
            throw ScreenCaptureKitApplicationCropErrorV0.noVisibleContent
        }
        let union = visible.dropFirst().reduce(first) { partial, bounds in
            partial.union(bounds)
        }
        let padded = union
            .insetBy(dx: -paddingPoints, dy: -paddingPoints)
            .intersection(sourceGlobalBounds)
        guard Self.valid(padded) else {
            throw ScreenCaptureKitApplicationCropErrorV0.invalidGeometry
        }

        globalBounds = padded
        sourceRect = CGRect(
            x: padded.minX - sourceGlobalBounds.minX,
            y: padded.minY - sourceGlobalBounds.minY,
            width: padded.width,
            height: padded.height
        )
    }

    private static func valid(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite
            && rect.width > 0 && rect.height > 0
    }
}
#endif
