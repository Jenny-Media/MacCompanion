import Foundation
import XCTest
@testable import CompanionInteractiveShared

final class InteractiveNativeVideoForegroundRecoveryV0Tests: XCTestCase {
    func testIndexedRecoveryInterleavings() throws {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
            let parent = root.deletingLastPathComponent()
            guard parent != root else { throw CocoaError(.fileNoSuchFile) }; root = parent
        }
        let name = "native-foreground-recovery-v0.1.json"
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf:
            root.appendingPathComponent("spec/fixtures/manifest.json"))) as? [String: Any])
        let entries = try XCTUnwrap(manifest["fixtures"] as? [[String: Any]])
        XCTAssertEqual(entries.filter { $0["path"] as? String == name }.count, 1)
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf:
            root.appendingPathComponent("spec/fixtures/" + name))) as? [String: Any])
        let cases = try XCTUnwrap(fixture["cases"] as? [[String: Any]])
        func binding(grant: Int64 = 1, primary: UInt8 = 0x22) throws -> InteractiveNativeVideoBindingV0 {
            try .init(hostID: UUID(uuidString: "018f6000-0000-7000-8000-000000000001")!,
                hostFingerprint: Data(repeating: 0x11, count: 32),
                clientID: UUID(uuidString: "018f6000-0000-7000-8000-000000000002")!,
                primaryConnectionID: Data(repeating: primary, count: 16),
                interactiveSessionID: UUID(uuidString: "018f6000-0000-7000-8000-000000000003")!,
                authorizationEpoch: 1, grantRevision: grant, policyRevision: 1,
                controlGeneration: UUID(uuidString: "018f6000-0000-7000-8000-000000000004")!,
                expiresAtMonotonicMilliseconds: 100)
        }
        for scenario in cases {
            let original = try binding()
            var current: InteractiveNativeVideoBindingV0? = original, now: UInt64 = 1
            var recovery = InteractiveNativeVideoForegroundRecoveryV0()
            var oldTicket: InteractiveNativeVideoForegroundRecoveryV0.Ticket?
            var results: [String] = []
            for step in try XCTUnwrap(scenario["steps"] as? [String]) {
                switch step {
                case "background": recovery.background(binding: original); results.append("waiting")
                case "cancel": recovery.cancel(); results.append("cancelled")
                case "expire": now = 100; results.append("expired")
                case "revoke": current = nil; results.append("revoked")
                case "changePrimary": current = try binding(primary: 0x33); results.append("changed")
                case "changeGrant": current = try binding(grant: 2); results.append("changed")
                case "resume", "inactiveResume":
                    let ticket = recovery.resume(current: current, foreground: step == "resume", nowMonotonicMilliseconds: now)
                    if let ticket { oldTicket = ticket }
                    results.append(ticket == nil ? "deny" : "resume")
                case "oldTicket": results.append(oldTicket.map { recovery.isCurrent($0) } == true ? "resume" : "deny")
                default: XCTFail("Unknown authoritative recovery step")
                }
            }
            XCTAssertEqual(results, scenario["expect"] as? [String], scenario["id"] as? String ?? "")
        }
    }
}
