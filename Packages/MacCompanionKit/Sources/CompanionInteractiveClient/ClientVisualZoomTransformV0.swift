import Foundation

public enum ClientVisualZoomTransformErrorV0:
    Error, Equatable, Sendable
{
    case invalidScale
    case invalidGeometry
}

/// A local-only visual transform. It changes neither the host surface nor its
/// authority fence; direct-touch input is mapped through the inverse transform
/// before the ordinary viewport mapper produces normalized host coordinates.
public struct ClientVisualZoomTransformV0: Equatable, Sendable {
    public static let maximumScale = 4.0

    public let viewport: ClientInputRectV0
    public let content: ClientInputRectV0
    public let scale: Double
    public let translation: ClientInputPointV0

    public init(
        viewport: ClientInputRectV0,
        content: ClientInputRectV0,
        scale: Double = 1,
        translation: ClientInputPointV0? = nil
    ) throws {
        guard scale.isFinite,
              (1...Self.maximumScale).contains(scale) else {
            throw ClientVisualZoomTransformErrorV0.invalidScale
        }
        guard content.x >= viewport.x,
              content.y >= viewport.y,
              content.x + content.width <= viewport.x + viewport.width,
              content.y + content.height
                <= viewport.y + viewport.height else {
            throw ClientVisualZoomTransformErrorV0.invalidGeometry
        }
        self.viewport = viewport
        self.content = content
        self.scale = scale
        self.translation = try Self.clampedTranslation(
            translation ?? ClientInputPointV0(x: 0, y: 0),
            viewport: viewport,
            content: content,
            scale: scale
        )
    }

    public func zoomed(
        to requestedScale: Double,
        around anchor: ClientInputPointV0
    ) throws -> Self {
        guard requestedScale.isFinite else {
            throw ClientVisualZoomTransformErrorV0.invalidScale
        }
        let nextScale = min(
            Self.maximumScale,
            max(1, requestedScale)
        )
        let center = viewportCenter
        let ratio = nextScale / scale
        let translation = try ClientInputPointV0(
            x: anchor.x - center.x
                - ratio * (anchor.x - center.x - self.translation.x),
            y: anchor.y - center.y
                - ratio * (anchor.y - center.y - self.translation.y)
        )
        return try Self(
            viewport: viewport,
            content: content,
            scale: nextScale,
            translation: translation
        )
    }

    public func panned(by delta: ClientInputPointV0) throws -> Self {
        try Self(
            viewport: viewport,
            content: content,
            scale: scale,
            translation: ClientInputPointV0(
                x: translation.x + delta.x,
                y: translation.y + delta.y
            )
        )
    }

    public func mappingToUnzoomed(
        _ point: ClientInputPointV0
    ) throws -> ClientInputPointV0 {
        let center = viewportCenter
        return try ClientInputPointV0(
            x: center.x + (point.x - center.x - translation.x) / scale,
            y: center.y + (point.y - center.y - translation.y) / scale
        )
    }

    public func mappingDeltaToUnzoomed(
        _ delta: ClientInputPointV0
    ) throws -> ClientInputPointV0 {
        try ClientInputPointV0(
            x: delta.x / scale,
            y: delta.y / scale
        )
    }

    private var viewportCenter: (x: Double, y: Double) {
        (
            x: viewport.x + viewport.width / 2,
            y: viewport.y + viewport.height / 2
        )
    }

    private static func clampedTranslation(
        _ requested: ClientInputPointV0,
        viewport: ClientInputRectV0,
        content: ClientInputRectV0,
        scale: Double
    ) throws -> ClientInputPointV0 {
        let centerX = viewport.x + viewport.width / 2
        let centerY = viewport.y + viewport.height / 2
        let x = clampAxis(
            requested.x,
            viewportMinimum: viewport.x,
            viewportMaximum: viewport.x + viewport.width,
            contentMinimum: centerX + (content.x - centerX) * scale,
            contentMaximum: centerX
                + (content.x + content.width - centerX) * scale
        )
        let y = clampAxis(
            requested.y,
            viewportMinimum: viewport.y,
            viewportMaximum: viewport.y + viewport.height,
            contentMinimum: centerY + (content.y - centerY) * scale,
            contentMaximum: centerY
                + (content.y + content.height - centerY) * scale
        )
        return try ClientInputPointV0(x: x, y: y)
    }

    private static func clampAxis(
        _ requested: Double,
        viewportMinimum: Double,
        viewportMaximum: Double,
        contentMinimum: Double,
        contentMaximum: Double
    ) -> Double {
        let lower = viewportMaximum - contentMaximum
        let upper = viewportMinimum - contentMinimum
        if lower <= upper {
            return min(upper, max(lower, requested))
        }
        let viewportCenter = (viewportMinimum + viewportMaximum) / 2
        let contentCenter = (contentMinimum + contentMaximum) / 2
        return viewportCenter - contentCenter
    }
}
