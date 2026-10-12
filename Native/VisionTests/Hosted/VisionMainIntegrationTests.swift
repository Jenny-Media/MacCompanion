import XCTest
import UIKit
@preconcurrency import NIOSSH
@preconcurrency import Citadel
@testable import MacCompanionVision

@MainActor final class VisionMainIntegrationTests: XCTestCase {
    private func wait(_ label: String, _ ready: () -> Bool) async throws {
        for _ in 0..<400 { if ready() { return }; try await Task.sleep(for: .milliseconds(25)) }
        XCTFail(label); throw POSIXError(.ETIMEDOUT)
    }
    private func fixture() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "native-visionos-client-v1", withExtension: "json"))
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return try XCTUnwrap(document["mainIntegration"] as? [String: Any])
    }
    private func library(_ root: URL, _ name: String, macs: [DirectMacRecordV1]) throws -> DirectMacLibraryV1 {
        let library = DirectMacLibraryV1(url: root.appendingPathComponent(name))
        for mac in macs {
            XCTAssertTrue(library.save(id: mac.id, name: mac.name, addresses: mac.addresses, port: mac.port, sshPort: mac.sshPort))
        }
        return library
    }
    private func pendingApproval(_ id: String) async throws {
        let rows = try XCTUnwrap(try fixture()["hostApprovalCases"] as? [[String: Any]])
        let row = try XCTUnwrap(rows.first { $0["id"] as? String == id })
        let compatible = try XCTUnwrap(row["storedMatchesPeer"] as? Bool)
        let accepted = try XCTUnwrap(row["accepted"] as? Bool)
        let server = DesktopSSHServer(.rfb); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic pending approval", addresses: ["127.0.0.1"], sshPort: server.port)
        let session = VisionDesktopSession(mac: mac)
        defer { session.close(); try? TerminalSecretStore.remove(mac.id); try? DesktopCredentialStoreV1.remove(mac.id) }
        do {
            session.connect(username: "synthetic", password: "synthetic-only", remember: true)
            try await wait("Desktop awaits first-use approval", { session.trust != nil })
            XCTAssertEqual(server.record.count("auth"), 0); XCTAssertEqual(server.record.count("forward"), 0)
            let winner = compatible ? server.hostKey : String(openSSHPublicKey: NIOSSHPrivateKey(ed25519Key: .init()).publicKey)
            // Another legitimate owner wins while this actual SSH handshake waits.
            try TerminalSecretStore.approveHostKey(winner, id: mac.id)
            session.answerTrust(true)
            try await wait("Pending approval completes", { !session.connecting })
            XCTAssertEqual(try TerminalSecretStore.hostKey(mac.id), winner)
            XCTAssertEqual(session.connected, accepted)
            if accepted {
                try await wait("Compatible owner renders", { session.image != nil })
                XCTAssertGreaterThan(server.record.count("auth"), 0)
                XCTAssertEqual(try DesktopCredentialStoreV1.readChecked(mac.id)?.username, "synthetic")
            } else {
                XCTAssertEqual(session.recovery?.reason, .serverChanged)
                XCTAssertEqual(server.record.count("auth"), 0); XCTAssertEqual(server.record.count("forward"), 0)
                XCTAssertNil(try DesktopCredentialStoreV1.readChecked(mac.id))
            }
            try await server.close()
        } catch { try? await server.close(); throw error }
    }
    func testPendingDesktopApprovalPreservesDifferentWinningPin() async throws {
        try await pendingApproval("concurrent-different-key")
    }
    func testPendingDesktopApprovalAcceptsSameWinningPin() async throws {
        try await pendingApproval("concurrent-same-key")
    }
    func testMacRemovalRetiresPendingOwnersBeforeReturningAndScopesLibrary() async throws {
        let cases = try XCTUnwrap(try fixture()["macRemovalCases"] as? [String])
        XCTAssertTrue(cases.contains("pending-trust")); XCTAssertTrue(cases.contains("terminal-owning-library"))
        XCTAssertTrue(cases.contains("same-uuid-different-library"))
        let server = DesktopSSHServer(.rfb); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic removed pending Mac", addresses: ["127.0.0.1"], sshPort: server.port)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let owned = try library(root, "owned.json", macs: [mac]), other = try library(root, "other.json", macs: [mac])
        let first = VisionDesktopSession(mac: mac, libraryURL: owned.storageURL)
        let second = VisionDesktopSession(mac: mac, libraryURL: owned.storageURL)
        let foreign = VisionDesktopSession(mac: mac, libraryURL: other.storageURL)
        let terminal = DirectTerminalSession(mac: mac, libraryURL: owned.storageURL)
        defer {
            first.close(); second.close(); foreign.close(); terminal.stop()
            try? TerminalSecretStore.remove(mac.id); try? DesktopCredentialStoreV1.remove(mac.id)
            try? FileManager.default.removeItem(at: root)
        }
        do {
            for session in [first, second, foreign] { session.connect(username: "synthetic", password: "synthetic-only", remember: true) }
            try await wait("All actual handshakes await approval", { first.trust != nil && second.trust != nil && foreign.trust != nil })
            owned.remove(mac)
            // No await and no SwiftUI watcher can supply this retirement.
            XCTAssertTrue(first.closed); XCTAssertTrue(second.closed); XCTAssertTrue(terminal.macRemoved)
            XCTAssertTrue(owned.macs.isEmpty)
            XCTAssertFalse(first.connecting); XCTAssertFalse(second.connecting)
            XCTAssertNil(first.trust); XCTAssertNil(second.trust)
            XCTAssertFalse(foreign.closed); XCTAssertTrue(foreign.connecting); XCTAssertNotNil(foreign.trust)
            XCTAssertEqual(other.macs.map(\.id), [mac.id])
            let connections = server.record.count("tcp")
            first.answerTrust(true); second.answerTrust(true)
            first.connect(username: "synthetic", password: "synthetic-only", remember: true)
            terminal.connect(username: "synthetic", password: "synthetic-only", remember: true)
            try await Task.sleep(for: .milliseconds(150))
            XCTAssertEqual(server.record.count("tcp"), connections)
            XCTAssertEqual(server.record.count("auth"), 0); XCTAssertEqual(server.record.count("forward"), 0)
            XCTAssertNil(try TerminalSecretStore.hostKey(mac.id)); XCTAssertNil(try DesktopCredentialStoreV1.readChecked(mac.id))
            try await server.close()
        } catch { try? await server.close(); throw error }
    }
    func testMacRemovalRevokesConnectedDesktopInputAndPreservesOtherMac() async throws {
        XCTAssertTrue(try XCTUnwrap(try fixture()["macRemovalCases"] as? [String]).contains("connected-owners"))
        let server = DesktopSSHServer(.rfb); try await server.start()
        let mac = try DirectMacRecordV1.normalized(name: "Synthetic removed connected Mac", addresses: ["127.0.0.1"], sshPort: server.port)
        let siblingMac = try DirectMacRecordV1.normalized(name: "Synthetic retained Mac", addresses: ["127.0.0.1"], sshPort: server.port)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let owned = try library(root, "owned.json", macs: [mac, siblingMac])
        let first = VisionDesktopSession(mac: mac, libraryURL: owned.storageURL)
        let second = VisionDesktopSession(mac: mac, libraryURL: owned.storageURL)
        let sibling = VisionDesktopSession(mac: siblingMac, libraryURL: owned.storageURL)
        defer {
            first.close(); second.close(); sibling.close()
            for id in [mac.id, siblingMac.id] { try? TerminalSecretStore.remove(id); try? DesktopCredentialStoreV1.remove(id) }
            try? FileManager.default.removeItem(at: root)
        }
        do {
            for id in [mac.id, siblingMac.id] { try TerminalSecretStore.approveHostKey(server.hostKey, id: id) }
            for session in [first, second, sibling] {
                session.inputAvailable = { true }; session.connect(username: "synthetic", password: "synthetic-only", remember: true)
            }
            try await wait("All Desktop owners render", { first.image != nil && second.image != nil && sibling.image != nil })
            XCTAssertNotNil(try DesktopCredentialStoreV1.readChecked(mac.id))
            first.key(0xffe3, down: true); second.pointer(CGPoint(x: 128, y: 64), mask: 1)
            try await wait("Removed owners hold input", { server.record.count("keyDown-65507") == 1 && server.record.count("pointerDown") > 0 })
            owned.remove(mac)
            XCTAssertTrue(first.closed); XCTAssertTrue(second.closed)
            XCTAssertFalse(first.canInput); XCTAssertFalse(second.pointerHeld)
            XCTAssertNil(first.image); XCTAssertNil(second.image)
            XCTAssertTrue(sibling.canInput); XCTAssertEqual(owned.macs.map(\.id), [siblingMac.id])
            first.key(97, down: true); second.key(97, down: true)
            sibling.key(97, down: true); sibling.key(97, down: false)
            try await wait("Retained owner still sends balanced input", { server.record.count("keyUp-97") == 1 })
            XCTAssertEqual(server.record.count("keyDown-97"), 1)
            XCTAssertNil(try DesktopCredentialStoreV1.readChecked(mac.id)); XCTAssertNil(try TerminalSecretStore.hostKey(mac.id))
            XCTAssertNotNil(try DesktopCredentialStoreV1.readChecked(siblingMac.id))
            try await server.close()
        } catch { try? await server.close(); throw error }
    }
}
