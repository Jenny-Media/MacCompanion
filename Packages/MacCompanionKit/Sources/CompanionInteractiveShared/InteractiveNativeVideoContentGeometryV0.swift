import Foundation

public enum InteractiveNativeVideoContentGeometryErrorV0: Error, Equatable, Sendable {
    case invalidDimensions
}

/// Unrotated aspect-fit geometry only. Construction neither verifies backend
/// clean aperture nor grants native presentation/input authority.
public struct InteractiveNativeVideoContentGeometryV0: Equatable, Sendable {
    public let encodedWidth: Int
    public let encodedHeight: Int
    public let capturePixelWidth: Int
    public let capturePixelHeight: Int
    public let logicalWidthPoints: Int
    public let logicalHeightPoints: Int
    public let contentX: Double
    public let contentY: Double
    public let contentWidth: Double
    public let contentHeight: Double

    public init(encodedWidth: Int, encodedHeight: Int,
                capturePixelWidth: Int, capturePixelHeight: Int,
                logicalWidthPoints: Int, logicalHeightPoints: Int) throws {
        guard (320...8192).contains(encodedWidth), (240...8192).contains(encodedHeight),
              (1...32768).contains(capturePixelWidth), (1...32768).contains(capturePixelHeight),
              logicalWidthPoints > 0, logicalHeightPoints > 0,
              UInt32(exactly: logicalWidthPoints) != nil,
              UInt32(exactly: logicalHeightPoints) != nil else {
            throw InteractiveNativeVideoContentGeometryErrorV0.invalidDimensions
        }
        self.encodedWidth = encodedWidth; self.encodedHeight = encodedHeight
        self.capturePixelWidth = capturePixelWidth; self.capturePixelHeight = capturePixelHeight
        self.logicalWidthPoints = logicalWidthPoints; self.logicalHeightPoints = logicalHeightPoints
        let scale = min(Double(encodedWidth) / Double(capturePixelWidth),
                        Double(encodedHeight) / Double(capturePixelHeight))
        contentWidth = min(Double(encodedWidth), Double(capturePixelWidth) * scale)
        contentHeight = min(Double(encodedHeight), Double(capturePixelHeight) * scale)
        contentX = (Double(encodedWidth) - contentWidth) / 2
        contentY = (Double(encodedHeight) - contentHeight) / 2
    }
}
