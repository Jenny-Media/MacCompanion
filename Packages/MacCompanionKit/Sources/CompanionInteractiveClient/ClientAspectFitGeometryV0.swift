import Foundation

public enum ClientAspectFitGeometryV0 {
    public static func contentRect(
        viewport: ClientInputRectV0,
        encodedWidth: UInt16,
        encodedHeight: UInt16
    ) throws -> ClientInputRectV0 {
        guard encodedWidth > 0, encodedHeight > 0 else {
            throw ClientViewportInputMapperErrorV0.invalidGeometry
        }
        let scale = min(
            viewport.width / Double(encodedWidth),
            viewport.height / Double(encodedHeight)
        )
        guard scale.isFinite, scale > 0 else {
            throw ClientViewportInputMapperErrorV0.invalidGeometry
        }
        // Multiplication can round a fitted edge a fraction of a point past
        // the viewport (for example 852.0000000000001). Canonicalize the
        // result before handing it to the strict input-authority mapper: this
        // is presentation arithmetic, not permission to accept genuinely
        // out-of-bounds input geometry.
        let width = min(
            viewport.width,
            Double(encodedWidth) * scale
        )
        let height = min(
            viewport.height,
            Double(encodedHeight) * scale
        )
        let maximumX = viewport.x + viewport.width - width
        let maximumY = viewport.y + viewport.height - height
        let x = min(
            maximumX,
            max(viewport.x, viewport.x + (viewport.width - width) / 2)
        )
        let y = min(
            maximumY,
            max(viewport.y, viewport.y + (viewport.height - height) / 2)
        )
        return try ClientInputRectV0(
            x: x,
            y: y,
            width: width,
            height: height
        )
    }
}
