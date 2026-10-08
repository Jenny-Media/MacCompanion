import Foundation
import CompanionInteractiveShared

public enum ClientAspectFitGeometryV0 {
    /// Projects source pixels inside an encoded frame and then inside the
    /// viewport. Both sets of padding remain outside the input mapper.
    public static func nativeContentRect(
        viewport: ClientInputRectV0,
        geometry: InteractiveNativeVideoContentGeometryV0
    ) throws -> ClientInputRectV0 {
        let frame = try contentRect(viewport: viewport,
            encodedWidth: UInt16(geometry.encodedWidth), encodedHeight: UInt16(geometry.encodedHeight))
        let width = min(frame.width, frame.width * (geometry.contentWidth / Double(geometry.encodedWidth)))
        let height = min(frame.height, frame.height * (geometry.contentHeight / Double(geometry.encodedHeight)))
        let x = min(frame.x + frame.width - width,
            max(frame.x, frame.x + frame.width * (geometry.contentX / Double(geometry.encodedWidth))))
        let y = min(frame.y + frame.height - height,
            max(frame.y, frame.y + frame.height * (geometry.contentY / Double(geometry.encodedHeight))))
        return try .init(x: x, y: y, width: width, height: height)
    }

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
