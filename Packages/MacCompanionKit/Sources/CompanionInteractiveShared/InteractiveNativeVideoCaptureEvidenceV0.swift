import Foundation

public enum InteractiveNativeVideoCaptureEvidenceErrorV0: Error, Equatable, Sendable {
    case invalidPayload, bindingMismatch, notCurrent
}

/// Observation from the owned Mac capture process, not client presentation or
/// input authority. Only the exact current backend may project this into XPC.
public struct InteractiveNativeVideoCaptureEvidenceV0: Codable, Equatable, Sendable {
    public let profile: String
    public let operationID: UUID
    public let monotonicNanoseconds: UInt64
    public let sampleSequence: UInt64
    public let capturePixelWidth: Int
    public let capturePixelHeight: Int
    public let encodedWidth: Int
    public let encodedHeight: Int
    public let formatWidth: Int
    public let formatHeight: Int
    public let cleanX: Double
    public let cleanY: Double
    public let cleanWidth: Double
    public let cleanHeight: Double
    public let aspectFitConfigured: Bool

    public static func decode(_ data: Data) throws -> Self {
        guard (1...2048).contains(data.count),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              Set(object.keys) == Set(["profile", "operationID", "monotonicNanoseconds", "sampleSequence",
                "capturePixelWidth", "capturePixelHeight", "encodedWidth", "encodedHeight", "formatWidth",
                "formatHeight", "cleanX", "cleanY", "cleanWidth", "cleanHeight", "aspectFitConfigured"]),
              let canonical = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]),
              canonical == data,
              let value = try? JSONDecoder().decode(Self.self, from: data) else {
            throw InteractiveNativeVideoCaptureEvidenceErrorV0.invalidPayload
        }
        try value.validateShape()
        return value
    }

    public func validateShape() throws {
        guard profile == "maccompanion.native-capture-evidence.v0.1", sampleSequence > 0,
              monotonicNanoseconds > 0, (1...32768).contains(capturePixelWidth),
              (1...32768).contains(capturePixelHeight), (320...8192).contains(encodedWidth),
              (240...8192).contains(encodedHeight), formatWidth == encodedWidth, formatHeight == encodedHeight,
              aspectFitConfigured, cleanX == 0, cleanY == 0,
              cleanWidth == Double(encodedWidth), cleanHeight == Double(encodedHeight) else {
            throw InteractiveNativeVideoCaptureEvidenceErrorV0.invalidPayload
        }
    }

    public func validate(operationID: UUID, encodedWidth: Int, encodedHeight: Int,
                         nowMonotonicNanoseconds: UInt64) throws {
        try validateShape()
        guard self.operationID == operationID, self.encodedWidth == encodedWidth,
              self.encodedHeight == encodedHeight else {
            throw InteractiveNativeVideoCaptureEvidenceErrorV0.bindingMismatch
        }
        guard monotonicNanoseconds <= nowMonotonicNanoseconds,
              nowMonotonicNanoseconds - monotonicNanoseconds <= 2_000_000_000 else {
            throw InteractiveNativeVideoCaptureEvidenceErrorV0.notCurrent
        }
    }

    public func validate(operationID: UUID, geometry: InteractiveNativeVideoContentGeometryV0,
                         nowMonotonicNanoseconds: UInt64) throws {
        try validate(operationID: operationID, encodedWidth: geometry.encodedWidth,
            encodedHeight: geometry.encodedHeight, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
        guard capturePixelWidth == geometry.capturePixelWidth, capturePixelHeight == geometry.capturePixelHeight else {
            throw InteractiveNativeVideoCaptureEvidenceErrorV0.bindingMismatch
        }
    }
}
