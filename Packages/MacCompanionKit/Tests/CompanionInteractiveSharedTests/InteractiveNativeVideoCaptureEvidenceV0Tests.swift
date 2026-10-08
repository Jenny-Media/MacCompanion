import Foundation
import Testing
@testable import CompanionInteractiveShared

private func captureEvidenceFixtureV0() throws -> [String: Any] {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
        let parent = root.deletingLastPathComponent()
        guard parent != root else { throw CocoaError(.fileNoSuchFile) }
        root = parent
    }
    let index = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/manifest.json"))) as? [String: Any])
    let entries = try #require(index["fixtures"] as? [[String: Any]])
    let path = "valid/native-backend-capture-evidence.json"
    #expect(entries.filter { $0["path"] as? String == path }.count == 1)
    return try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/" + path))) as? [String: Any])
}

@Test func nativeCaptureEvidenceJoinsActualSampleToCurrentOperationAndGeometry() throws {
    let fixture = try captureEvidenceFixtureV0()
    let record = try #require(fixture["record"] as? [String: Any])
    let bytes = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes])
    let value = try InteractiveNativeVideoCaptureEvidenceV0.decode(bytes)
    let geometry = try InteractiveNativeVideoContentGeometryV0(encodedWidth: 1920, encodedHeight: 800,
        capturePixelWidth: 5120, capturePixelHeight: 2134, logicalWidthPoints: 2560, logicalHeightPoints: 1067)
    try value.validate(operationID: value.operationID, geometry: geometry, nowMonotonicNanoseconds: 10_500_000_000)
    #expect(throws: InteractiveNativeVideoCaptureEvidenceErrorV0.bindingMismatch) {
        try value.validate(operationID: UUID(), geometry: geometry, nowMonotonicNanoseconds: 10_500_000_000)
    }
    let changed = try InteractiveNativeVideoContentGeometryV0(encodedWidth: 1920, encodedHeight: 800,
        capturePixelWidth: 5122, capturePixelHeight: 2134, logicalWidthPoints: 2560, logicalHeightPoints: 1067)
    #expect(throws: InteractiveNativeVideoCaptureEvidenceErrorV0.bindingMismatch) {
        try value.validate(operationID: value.operationID, geometry: changed, nowMonotonicNanoseconds: 10_500_000_000)
    }
    for now: UInt64 in [9_999_999_999, 12_000_000_001] {
        #expect(throws: InteractiveNativeVideoCaptureEvidenceErrorV0.notCurrent) {
            try value.validate(operationID: value.operationID, geometry: geometry, nowMonotonicNanoseconds: now)
        }
    }
}

@Test func nativeCaptureEvidenceRejectsMalformedPartialAndNoncanonicalReports() throws {
    let fixture = try captureEvidenceFixtureV0()
    let original = try #require(fixture["record"] as? [String: Any])
    let changes: [(String, Any)] = [("profile", "unknown"), ("aspectFitConfigured", false), ("sampleSequence", 0),
        ("encodedWidth", 0), ("formatHeight", 799), ("capturePixelWidth", 32769), ("cleanX", 1),
        ("cleanHeight", 799), ("unexpected", true)]
    for (field, changed) in changes {
        var record = original; record[field] = changed
        let bytes = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes])
        #expect(throws: InteractiveNativeVideoCaptureEvidenceErrorV0.invalidPayload) {
            try InteractiveNativeVideoCaptureEvidenceV0.decode(bytes)
        }
    }
    for field in original.keys {
        var record = original; record.removeValue(forKey: field)
        let bytes = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes])
        #expect(throws: InteractiveNativeVideoCaptureEvidenceErrorV0.invalidPayload) {
            try InteractiveNativeVideoCaptureEvidenceV0.decode(bytes)
        }
    }
    let canonical = try JSONSerialization.data(withJSONObject: original, options: [.sortedKeys, .withoutEscapingSlashes])
    for bytes in [Data(" ".utf8) + canonical, Data(repeating: 32, count: 2049)] {
        #expect(throws: InteractiveNativeVideoCaptureEvidenceErrorV0.invalidPayload) {
            try InteractiveNativeVideoCaptureEvidenceV0.decode(bytes)
        }
    }
}
