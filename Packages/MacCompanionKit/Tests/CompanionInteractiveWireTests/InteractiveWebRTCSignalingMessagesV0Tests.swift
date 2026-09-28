import CompanionInteractiveWire
import CompanionWire
import Foundation
import XCTest

final class InteractiveWebRTCSignalingMessagesV0Tests: XCTestCase {
    func testAuthoritativeOfferAnswerFixtures() throws {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(
            atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path
        ) {
            let parent = root.deletingLastPathComponent()
            guard parent != root else { throw FixtureError.missingRoot }
            root = parent
        }
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf:
            root.appendingPathComponent("spec/fixtures/manifest.json")
        )) as? [String: Any]
        let entries = manifest?["fixtures"] as? [[String: Any]] ?? []
        let cases: [(String, WireMessageKind, Bool)] = [
            ("valid/interactive-media-offer-request.json", .interactiveMediaOfferRequest, true),
            ("valid/interactive-media-offer.json", .interactiveMediaOffer, true),
            ("valid/interactive-media-answer.json", .interactiveMediaAnswer, true),
            ("valid/interactive-media-ready.json", .interactiveMediaReady, true),
            ("invalid/interactive-media-offer-fingerprint-mismatch.json", .interactiveMediaOffer, false),
            ("invalid/interactive-media-offer-no-candidate.json", .interactiveMediaOffer, false),
            ("invalid/interactive-media-answer-unsafe-generation.json", .interactiveMediaAnswer, false),
        ]
        for (path, kind, expectedValid) in cases {
            XCTAssertEqual(entries.filter { $0["path"] as? String == path }.count, 1)
            let data = try Data(contentsOf:
                root.appendingPathComponent("spec/fixtures/\(path)"))
            if expectedValid {
                XCTAssertEqual(try WireCodec.messageKind(from: data), kind)
            } else if let decodedKind = try? WireCodec.messageKind(from: data) {
                XCTAssertEqual(decodedKind, kind)
            }
            let valid = (try? decode(kind, data: data)) != nil
            XCTAssertEqual(valid, expectedValid, path)
        }
    }

    private func decode(_ kind: WireMessageKind, data: Data) throws -> Bool {
        switch kind {
        case .interactiveMediaOfferRequest:
            _ = try WireCodec.decode(WireEnvelope<InteractiveWebRTCOfferRequestBodyV0>.self, from: data)
        case .interactiveMediaOffer:
            _ = try WireCodec.decode(WireEnvelope<InteractiveWebRTCOfferBodyV0>.self, from: data)
        case .interactiveMediaAnswer:
            _ = try WireCodec.decode(WireEnvelope<InteractiveWebRTCAnswerBodyV0>.self, from: data)
        case .interactiveMediaReady:
            _ = try WireCodec.decode(WireEnvelope<InteractiveWebRTCReadyBodyV0>.self, from: data)
        default: throw FixtureError.unexpectedKind
        }
        return true
    }

    private enum FixtureError: Error {
        case missingRoot, unexpectedKind
    }
}
