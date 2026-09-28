import Foundation
import XCTest
@testable import CompanionInteractiveShared

final class InteractiveNativeVideoLifecycleV0Tests: XCTestCase {
    private struct Fixture: Decodable {
        struct Scenario: Decodable {
            let id: String
            let steps: [String]
            let expect: [String]
        }
        let cases: [Scenario]
    }

    private func binding(grantRevision: Int64 = 1) throws -> InteractiveNativeVideoBindingV0 {
        try .init(hostID: UUID(uuidString: "018f6000-0000-7000-8000-000000000001")!,
                  hostFingerprint: Data(repeating: 0x11, count: 32),
                  clientID: UUID(uuidString: "018f6000-0000-7000-8000-000000000002")!,
                  primaryConnectionID: Data(repeating: 0x22, count: 16),
                  interactiveSessionID: UUID(uuidString: "018f6000-0000-7000-8000-000000000003")!,
                  authorizationEpoch: 1, grantRevision: grantRevision, policyRevision: 1,
                  controlGeneration: UUID(uuidString: "018f6000-0000-7000-8000-000000000004")!,
                  expiresAtMonotonicMilliseconds: 100)
    }

    private func surface(revision: Int64 = 1, width: Int = 1920) throws -> InteractiveNativeVideoSurfaceV0 {
        try .init(surfaceID: UUID(uuidString: "018f6000-0000-7000-8000-000000000005")!,
                  surfaceRevision: revision, coordinateSpaceRevision: 1,
                  encodedWidth: width, encodedHeight: 1080)
    }

    func testAuthoritativeLifecycleCases() throws {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
            let parent = root.deletingLastPathComponent()
            guard root != parent else { throw CocoaError(.fileNoSuchFile) }
            root = parent
        }
        let relative = "valid/native-video-lifecycle.json"
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf:
            root.appendingPathComponent("spec/fixtures/manifest.json"))) as? [String: Any]
        let entries = manifest?["fixtures"] as? [[String: Any]] ?? []
        XCTAssertEqual(entries.filter { $0["path"] as? String == relative }.count, 1)
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf:
            root.appendingPathComponent("spec/fixtures/\(relative)")))
        for scenario in fixture.cases {
            let original = try binding()
            var current = original
            let expectedSurface = try surface()
            var lease = InteractiveNativeVideoLifecycleV0(binding: original, surface: expectedSurface)
            var now: UInt64 = 10
            var generation: UInt64 = 0
            var old: UInt64 = 0
            XCTAssertEqual(scenario.steps.count, scenario.expect.count)
            for (step, expected) in zip(scenario.steps, scenario.expect) {
                let result: String
                switch step {
                case "begin":
                    if let next = lease.begin(current: current, nowMonotonicMilliseconds: now) {
                        old = generation; generation = next; result = lease.phase.rawValue
                    } else { result = "reject" }
                case "connected":
                    result = lease.connected(generation: generation, current: current,
                        nowMonotonicMilliseconds: now) ? lease.phase.rawValue : "reject"
                case "frame", "oldFrame":
                    result = lease.frame(generation: step == "oldFrame" ? old : generation,
                        surface: expectedSurface, current: current,
                        nowMonotonicMilliseconds: now) ? lease.phase.rawValue : "reject"
                case "wrongSurface", "wrongDimensions":
                    _ = lease.frame(generation: generation,
                        surface: try surface(revision: step == "wrongSurface" ? 2 : 1,
                                             width: step == "wrongDimensions" ? 1280 : 1920),
                        current: current, nowMonotonicMilliseconds: now)
                    result = lease.phase.rawValue
                    XCTAssertEqual(lease.failure, .incompatibleFrame)
                case "fail", "oldFailure":
                    result = lease.connectionFailed(generation: step == "oldFailure" ? old : generation,
                        current: current, nowMonotonicMilliseconds: now) ? lease.phase.rawValue : "reject"
                case "stop": lease.stop(); result = lease.phase.rawValue
                case "drain":
                    result = lease.drained(generation: generation) ? lease.phase.rawValue : "reject"
                case "expire":
                    now = 100
                    XCTAssertFalse(lease.revalidate(current: current, nowMonotonicMilliseconds: now))
                    XCTAssertEqual(lease.failure, .expired)
                    result = lease.phase.rawValue
                case "background":
                    lease.authorizationLost()
                    result = lease.phase.rawValue
                case "revoke":
                    current = try binding(grantRevision: 2)
                    XCTAssertFalse(lease.revalidate(current: current, nowMonotonicMilliseconds: now))
                    XCTAssertEqual(lease.failure, .authorizationLost)
                    result = lease.phase.rawValue
                case "admitInput", "oldInputAdmission":
                    result = lease.admitInput(generation: step == "oldInputAdmission" ? old : generation,
                        surface: expectedSurface, current: current, nowMonotonicMilliseconds: now) ? "admit" : "reject"
                case "input": result = lease.allowsInput ? "enabled" : "disabled"
                default: XCTFail("Unknown authoritative step: \(step)"); continue
                }
                XCTAssertEqual(result, expected, "\(scenario.id): \(step)")
            }
        }
    }

    func testInvalidGeometryCannotCreateAFrameFence() throws {
        XCTAssertThrowsError(try surface(width: 0))
        XCTAssertThrowsError(try surface(revision: 0))
        XCTAssertThrowsError(try surface(width: 8193))
    }

    func testAuthorityLossAtBeginDoesNotReserveNativeOwner() throws {
        let original = try binding()
        var lease = InteractiveNativeVideoLifecycleV0(binding: original, surface: try surface())
        XCTAssertNil(lease.begin(current: try binding(grantRevision: 2), nowMonotonicMilliseconds: 10))
        XCTAssertFalse(lease.requiresDrain)
        XCTAssertTrue(lease.isTerminal)
    }

    func testStaleDrainCannotReleaseCurrentGeneration() throws {
        let current = try binding()
        var lease = InteractiveNativeVideoLifecycleV0(binding: current, surface: try surface())
        let first = try XCTUnwrap(lease.begin(current: current, nowMonotonicMilliseconds: 10))
        XCTAssertTrue(lease.connectionFailed(generation: first, current: current, nowMonotonicMilliseconds: 10))
        XCTAssertTrue(lease.drained(generation: first))
        let second = try XCTUnwrap(lease.begin(current: current, nowMonotonicMilliseconds: 11))
        lease.stop()
        XCTAssertFalse(lease.drained(generation: first))
        XCTAssertTrue(lease.requiresDrain)
        XCTAssertTrue(lease.drained(generation: second))
    }
}
