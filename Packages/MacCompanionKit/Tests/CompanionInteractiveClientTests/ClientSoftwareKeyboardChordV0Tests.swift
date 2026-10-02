import CompanionInteractiveClient
import CompanionInteractiveWire
import Foundation
import Testing

@Test func softwareKeyboardChordsUseIndexedVectorsAndPreserveUnicode() throws {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
        let parent = root.deletingLastPathComponent()
        try #require(parent != root)
        root = parent
    }
    let index = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/manifest.json"))) as! [String: Any]
    let path = "valid/native-input-posting.json"
    try #require((index["fixtures"] as! [[String: Any]]).filter { $0["path"] as? String == path }.count == 1)
    let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/" + path))) as! [String: Any]
    for row in fixture["softwareKeyboardCases"] as! [[String: Any]] {
        let text = row["text"] as! String
        let modifiers = InteractiveModifierMask(rawValue: (row["modifierMask"] as! NSNumber).uint8Value)
        let payloads = try ClientKeyboardActionV0.text(text).softwareKeyboardPayloads(modifiers: modifiers)
        if let usage = row["usage"] as? NSNumber {
            let effective = InteractiveModifierMask(rawValue: (row["effectiveModifierMask"] as! NSNumber).uint8Value)
            #expect(payloads == [
                .physicalKey(usage: usage.uint16Value, transition: .down, modifiers: effective),
                .physicalKey(usage: usage.uint16Value, transition: .up, modifiers: effective),
                .modifiers([]),
            ])
        } else if let unicode = row["unicodeText"] as? String {
            #expect(payloads == [.text(unicode)])
        } else {
            #expect(row["omitted"] as? Bool == true)
            #expect(payloads.isEmpty)
        }
    }
}
