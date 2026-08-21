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
        let width = Double(encodedWidth) * scale
        let height = Double(encodedHeight) * scale
        return try ClientInputRectV0(
            x: viewport.x + (viewport.width - width) / 2,
            y: viewport.y + (viewport.height - height) / 2,
            width: width,
            height: height
        )
    }
}
