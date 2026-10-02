#if os(macOS)
@testable import CompanionMacApplicationPlatform
import Foundation
import Testing

@Test func managedNativeDiagnosticsRetainOnlyIndexedClosedCodes() throws {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
        let parent = root.deletingLastPathComponent()
        try #require(parent != root)
        root = parent
    }
    let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
        root.appendingPathComponent("spec/fixtures/native-selected-capture-context-v0.1.json"))) as? [String: Any])
    for row in try #require(fixture["childDiagnosticCases"] as? [[String: Any]]) {
        let lines = try #require(row["lines"] as? [String])
        let codes = try #require(row["codes"] as? [String])
        #expect(MacManagedNativeCaptureDiagnosticsV1.codes(in: Data(lines.joined(separator: "\n").utf8)) == codes)
    }
}

@Test func managedNativeDiagnosticsBoundReadsAndRejectLinks() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let log = root.appendingPathComponent("startup.log")
    let old = Data("selected-capture-context-error=12\n".utf8)
    try (old + Data(repeating: 32, count: 65_536) + Data("\nselected-capture-sample-rejected=7\n".utf8)).write(to: log)
    #expect(MacManagedNativeCaptureDiagnosticsV1.codes(file: log) == ["selected-capture-sample-rejected=7"])
    let link = root.appendingPathComponent("link.log")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: log)
    #expect(MacManagedNativeCaptureDiagnosticsV1.codes(file: link).isEmpty)
    let hardLink = root.appendingPathComponent("hard-link.log")
    try FileManager.default.linkItem(at: log, to: hardLink)
    #expect(MacManagedNativeCaptureDiagnosticsV1.codes(file: log).isEmpty)
}
#endif
