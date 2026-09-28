#if os(macOS)
@testable import CompanionMacApplicationPlatform
import CompanionInteractiveShared
import Foundation
import Testing

private struct FocusOwnershipFixtureV1: Decodable {
    let profile: String
    let cases: [Case]

    struct Case: Decodable {
        let name: String
        let currentKind: InteractiveSurfaceKind
        let selectedProcessID: Int32?
        let observedProcessID: Int32?
        let accept: Bool
    }
}

@Test func focusOwnerRejectsCrossAppModalAndMissingPID() throws {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(
        atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path
    ) {
        let parent = root.deletingLastPathComponent()
        #expect(parent != root)
        guard parent != root else { return }
        root = parent
    }
    let path = "valid/interactive-focus-owner-policy.json"
    let manifestData = try Data(contentsOf:
        root.appendingPathComponent("spec/fixtures/manifest.json"))
    let manifest = try JSONSerialization.jsonObject(with: manifestData)
        as? [String: Any]
    let entries = manifest?["fixtures"] as? [[String: Any]] ?? []
    #expect(entries.filter { $0["path"] as? String == path }.count == 1)

    let fixture = try JSONDecoder().decode(
        FocusOwnershipFixtureV1.self,
        from: Data(contentsOf:
            root.appendingPathComponent("spec/fixtures/\(path)"))
    )
    #expect(fixture.profile == "interactive.focus.owner-policy.v0.1")
    for item in fixture.cases {
        #expect(
            MacInteractiveFocusOwnershipV1.accepts(
                currentKind: item.currentKind,
                selectedProcessID: item.selectedProcessID,
                observedProcessID: item.observedProcessID
            ) == item.accept,
            "\(item.name)"
        )
    }
}
#endif
