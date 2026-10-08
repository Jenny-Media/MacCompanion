import CompanionInteractiveShared
import Foundation
import Testing
@testable import CompanionInteractiveClient

private struct NativeContentFixtureV0: Decodable {
    struct Dimensions: Decodable { let encoded: [Int]; let capture: [Int]; let logical: [Int] }
    struct Case: Decodable {
        let id: String
        let encoded: [Int]; let capture: [Int]; let logical: [Int]
        let viewport: [Double]; let content: [Double]
    }
    let cases: [Case]
    let rejectedDimensions: [Dimensions]
}

@Test func nativeContentGeometryUsesAuthoritativeCasesAndRejectsPadding() throws {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
        let parent = root.deletingLastPathComponent()
        guard parent != root else { throw CocoaError(.fileNoSuchFile) }
        root = parent
    }
    let relative = "valid/native-video-content-geometry.json"
    let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
        root.appendingPathComponent("spec/fixtures/manifest.json"))) as? [String: Any])
    let entries = try #require(manifest["fixtures"] as? [[String: Any]])
    #expect(entries.filter { $0["path"] as? String == relative }.count == 1)
    let fixture = try JSONDecoder().decode(NativeContentFixtureV0.self, from: Data(contentsOf:
        root.appendingPathComponent("spec/fixtures/" + relative)))
    for value in fixture.cases {
        let geometry = try InteractiveNativeVideoContentGeometryV0(encodedWidth: value.encoded[0], encodedHeight: value.encoded[1],
            capturePixelWidth: value.capture[0], capturePixelHeight: value.capture[1],
            logicalWidthPoints: value.logical[0], logicalHeightPoints: value.logical[1])
        let viewport = try ClientInputRectV0(x: value.viewport[0], y: value.viewport[1], width: value.viewport[2], height: value.viewport[3])
        let rect = try ClientAspectFitGeometryV0.nativeContentRect(viewport: viewport, geometry: geometry)
        for (actual, expected) in zip([rect.x, rect.y, rect.width, rect.height], value.content) {
            #expect(abs(actual - expected) < 0.000001, Comment(rawValue: value.id))
        }
        var mapper = try ClientViewportInputMapperV0(viewport: viewport, content: rect, mode: .directTouch)
        #expect(try mapper.directMove(to: .init(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2))
            == .pointerMove(x: 32768, y: 32768))
        var trackpad = try ClientViewportInputMapperV0(viewport: viewport, content: rect, mode: .trackpad)
        #expect(try trackpad.trackpadMove(delta: .init(x: rect.width / 4, y: -rect.height / 4))
            == .pointerMove(x: 49152, y: 16384))
        for point in [try ClientInputPointV0(x: rect.x - 0.001, y: rect.y + rect.height / 2),
                      try .init(x: rect.x + rect.width, y: rect.y + rect.height / 2),
                      try .init(x: rect.x + rect.width / 2, y: rect.y - 0.001),
                      try .init(x: rect.x + rect.width / 2, y: rect.y + rect.height)] {
            #expect(throws: ClientViewportInputMapperErrorV0.pointOutsideContent) {
                try mapper.directMove(to: point)
            }
        }
    }
    for value in fixture.rejectedDimensions {
        #expect(throws: InteractiveNativeVideoContentGeometryErrorV0.invalidDimensions) {
            try InteractiveNativeVideoContentGeometryV0(encodedWidth: value.encoded[0], encodedHeight: value.encoded[1],
                capturePixelWidth: value.capture[0], capturePixelHeight: value.capture[1],
                logicalWidthPoints: value.logical[0], logicalHeightPoints: value.logical[1])
        }
    }
}
