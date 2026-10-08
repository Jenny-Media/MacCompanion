#if !DEBUG || !targetEnvironment(simulator)
#error("Owned normal-app identity cleanup is Debug Simulator-only")
#endif
import CompanionClient
import CompanionClientPlatform
import Foundation
import XCTest

/// Runs only as a separate, explicitly selected hosted QA bundle. It deletes
/// the exact test pair's validated opaque key references, never a whole group.
final class PairedIdentityCleanup: XCTestCase {
    func testDiscardExactOwnedPairKeys() async throws {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "media.jenny.maccompanion.ios")
        let env = ProcessInfo.processInfo.environment
        let clientID = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(env["MACCOMPANION_TEST_CLIENT_ID"])))
        let hostID = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(env["MACCOMPANION_TEST_HOST_ID"])))
        let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                               in: .userDomainMask, appropriateFor: nil, create: false)
        let root = base.appendingPathComponent("dev.maccompanion.simulator/iOS/v1/paired-hosts-v1")
        let store = try AtomicFileClientPairedHostStoreV0(directory: root)
        let records = try await store.allRecords()
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.clientID, clientID)
        XCTAssertEqual(record.hostID, hostID)
        guard records.count == 1, record.clientID == clientID, record.hostID == hostID else { return }
        let prompts = try SecurityClientPresencePromptsV0(pairNewMac: "Test cleanup.",
            approveOperation: "Test cleanup.", startInteractiveControl: "Test cleanup.", expandGrant: "Test cleanup.")
        let custody = SecurityClientIdentityKeyCustodyV0(configuration: try .init(
            applicationTagPrefix: "dev.maccompanion.simulator.identity.v1",
            requireSecureEnclave: false, prompts: prompts))
        try await custody.registerPublishedIdentity(record)
        let identity = try ClientPreparedIdentityV0(pairingID: record.pairingID, clientID: clientID,
            sessionKey: record.sessionKey, approvalKey: record.approvalKey)
        try await custody.discardPreparedIdentity(identity)
        do {
            try await custody.registerPublishedIdentity(record)
            XCTFail("Deleted test keys must not remain usable")
        } catch SecurityClientKeyCustodyErrorV0.keyMismatch { }
    }
}
