import Foundation
import XCTest
@testable import CompanionInteractiveShared

final class InteractiveWebRTCMediaLeaseV0Tests: XCTestCase {
    private struct Fixture: Decodable {
        let binding: Binding
        let cases: [Case]

        struct Binding: Decodable {
            let hostID: UUID
            let hostFingerprintHex: String
            let clientID: UUID
            let primaryConnectionIDHex: String
            let interactiveSessionID: UUID
            let authorizationEpoch: Int64
            let grantRevision: Int64
            let policyRevision: Int64
            let controlGeneration: UUID
            let expiresAtMonotonicMilliseconds: UInt64
        }

        struct Case: Decodable {
            let id: String
            let steps: [String]
            let expect: [String]
        }
    }

    func testAuthoritativeTransitionCases() throws {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("spec/fixtures/manifest.json").path
        ) {
            let parent = directory.deletingLastPathComponent()
            guard parent != directory else { throw FixtureError.missingRoot }
            directory = parent
        }
        let relative = "valid/interactive-webrtc-media-lease.json"
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf:
            directory.appendingPathComponent("spec/fixtures/manifest.json")
        )) as? [String: Any]
        let entries = manifest?["fixtures"] as? [[String: Any]] ?? []
        XCTAssertEqual(entries.filter { $0["path"] as? String == relative }.count, 1)
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf:
            directory.appendingPathComponent("spec/fixtures/\(relative)")
        ))
        let source = fixture.binding
        let binding = try makeBinding(source)
        for scenario in fixture.cases {
            XCTAssertEqual(scenario.steps.count, scenario.expect.count, scenario.id)
            var lease = InteractiveWebRTCMediaLeaseV0(binding: binding)
            var current = binding
            var now: UInt64 = 10
            var peer: UInt64 = 0
            var oldPeer: UInt64 = 0
            let firstSurface = try InteractiveWebRTCMediaSurfaceFenceV0(
                surfaceID: UUID(uuidString: "018f6000-0000-7000-8000-000000000030")!,
                surfaceRevision: 1, coordinateSpaceRevision: 1
            )
            let secondSurface = try InteractiveWebRTCMediaSurfaceFenceV0(
                surfaceID: UUID(uuidString: "018f6000-0000-7000-8000-000000000031")!,
                surfaceRevision: 2, coordinateSpaceRevision: 2
            )
            var surface = firstSurface
            XCTAssertTrue(lease.setCurrentSurface(surface, current: current,
                                                  nowMonotonicMilliseconds: now))
            let offer = UUID(uuidString: "018f6000-0000-7000-8000-000000000020")!
            let answer = UUID(uuidString: "018f6000-0000-7000-8000-000000000021")!
            let ice = UUID(uuidString: "018f6000-0000-7000-8000-000000000022")!
            for (step, expected) in zip(scenario.steps, scenario.expect) {
                let result: String
                switch step {
                case "beginPeer":
                    oldPeer = peer
                    if let next = lease.beginPeer(current: current, nowMonotonicMilliseconds: now) {
                        peer = next
                        result = "peer:\(next)"
                    } else { result = "reject" }
                case "offer":
                    result = lease.admitOffer(offer, peer: peer, current: current,
                                              nowMonotonicMilliseconds: now) ? "admit" : "reject"
                case "answer", "answerDuplicate":
                    result = lease.admitAnswer(answer, respondingTo: offer, peer: peer,
                                               current: current,
                                               nowMonotonicMilliseconds: now) ? "admit" : "reject"
                case "ice", "iceDuplicate":
                    result = lease.admitICE(ice, peer: peer, current: current,
                                            nowMonotonicMilliseconds: now) ? "admit" : "reject"
                case "frame":
                    result = lease.admitFrame(peer: peer, surface: surface,
                                              current: current,
                                              nowMonotonicMilliseconds: now) ? "admit" : "reject"
                case "oldFrame":
                    let stale = oldPeer == 0 ? peer : oldPeer
                    result = lease.admitFrame(peer: stale, surface: surface,
                                              current: current,
                                              nowMonotonicMilliseconds: now) ? "admit" : "reject"
                case "surfaceChange":
                    surface = secondSurface
                    _ = lease.setCurrentSurface(surface, current: current,
                                                nowMonotonicMilliseconds: now)
                    result = lease.isPresenting ? "presenting" : "blank"
                case "staleSurfaceFrame":
                    result = lease.admitFrame(peer: peer, surface: firstSurface,
                                              current: current,
                                              nowMonotonicMilliseconds: now) ? "admit" : "reject"
                case "background":
                    lease.background()
                    result = lease.isPresenting ? "presenting" : "blank"
                case "stop":
                    lease.close()
                    result = lease.isPresenting ? "presenting" : "blank"
                case "expire":
                    now = binding.expiresAtMonotonicMilliseconds
                    _ = lease.admitFrame(peer: peer, surface: surface,
                                         current: current,
                                         nowMonotonicMilliseconds: now)
                    result = lease.isPresenting ? "presenting" : "blank"
                case "revoke", "mismatchIdentity":
                    current = try makeBinding(source,
                        grantRevision: step == "revoke" ? source.grantRevision + 1 : nil,
                        fingerprint: step == "mismatchIdentity" ? Data(repeating: 0x44, count: 32) : nil)
                    _ = lease.admitFrame(peer: peer, surface: surface,
                                         current: current,
                                         nowMonotonicMilliseconds: now)
                    result = lease.isPresenting ? "presenting" : "blank"
                default: throw FixtureError.unknownStep(step)
                }
                XCTAssertEqual(result, expected, "\(scenario.id): \(step)")
            }
        }
    }

    private func makeBinding(
        _ value: Fixture.Binding, grantRevision: Int64? = nil,
        fingerprint: Data? = nil
    ) throws -> InteractiveWebRTCMediaBindingV0 {
        guard let host = Data(hex: value.hostFingerprintHex),
              let connection = Data(hex: value.primaryConnectionIDHex) else {
            throw FixtureError.invalidHex
        }
        return try InteractiveWebRTCMediaBindingV0(
            hostID: value.hostID, hostFingerprint: fingerprint ?? host,
            clientID: value.clientID, primaryConnectionID: connection,
            interactiveSessionID: value.interactiveSessionID,
            authorizationEpoch: value.authorizationEpoch,
            grantRevision: grantRevision ?? value.grantRevision,
            policyRevision: value.policyRevision,
            controlGeneration: value.controlGeneration,
            expiresAtMonotonicMilliseconds: value.expiresAtMonotonicMilliseconds
        )
    }

    private enum FixtureError: Error {
        case missingRoot, invalidHex, unknownStep(String)
    }
}

private extension Data {
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        var position = hex.startIndex
        while position < hex.endIndex {
            let next = hex.index(position, offsetBy: 2)
            guard let byte = UInt8(hex[position..<next], radix: 16) else { return nil }
            bytes.append(byte)
            position = next
        }
        self.init(bytes)
    }
}
