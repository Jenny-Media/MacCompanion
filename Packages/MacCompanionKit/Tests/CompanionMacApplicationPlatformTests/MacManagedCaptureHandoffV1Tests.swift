#if os(macOS)
import Foundation
import Testing
import CompanionInteractiveShared
@testable import CompanionMacApplicationPlatform

private func handoffFixture() throws -> [String: Any] {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
        let parent = root.deletingLastPathComponent(); guard root != parent else { throw CocoaError(.fileNoSuchFile) }; root = parent
    }
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/manifest.json"))) as! [String: Any]
    #expect((manifest["fixtures"] as! [[String: Any]]).filter { $0["path"] as? String == "native-stream-continuity-v0.1.json" }.count == 1)
    return try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("spec/fixtures/native-stream-continuity-v0.1.json"))) as! [String: Any]
}

@MainActor
@Test func managedCaptureParentRequiresExactReceiptAndRetainsKnownPredecessor() async throws {
    let f = try handoffFixture(), records = f["childHandoff"] as! [String: Any]
    let old = UUID(uuidString: (records["pause"] as! [String: Any])["operationID"] as! String)!
    let next = UUID(uuidString: (records["select"] as! [String: Any])["operationID"] as! String)!
    let expiry = DispatchTime.now().uptimeNanoseconds + 30_000_000_000
    for kind in ["success", "wrong-operation", "wrong-sequence", "unsafe", "stop"] {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("maccompanion-parent-handoff-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let owner = try MacManagedCaptureHandoffV1(directory: root, transport: old, expiryNanoseconds: expiry, current: { true })
        let receipt = root.appendingPathComponent("capture-handoff-receipt.json")
        let command = root.appendingPathComponent("capture-handoff-command.json")
        let child = Task { @MainActor in
            let until = ContinuousClock.now.advanced(by: .seconds(2))
            while !FileManager.default.fileExists(atPath: command.path), ContinuousClock.now < until { try await Task.sleep(for: .milliseconds(10)) }
            let request = try JSONSerialization.jsonObject(with: Data(contentsOf: command)) as! [String: Any]
            #expect(request["transportOperationID"] as? String == old.uuidString)
            #expect((request["expiresAtMonotonicNanoseconds"] as? NSNumber)?.uint64Value == expiry)
            if kind == "stop" { owner.close(); return }
            var reply: [String: Any] = ["profile": "maccompanion.capture-handoff-receipt.v1",
                "transportOperationID": old.uuidString, "operationID": old.uuidString, "sequence": 1,
                "action": "pause", "result": "paused"]
            if kind == "wrong-operation" { reply["operationID"] = next.uuidString }
            if kind == "wrong-sequence" { reply["sequence"] = 2 }
            try JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys, .withoutEscapingSlashes]).write(to: receipt, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: kind == "unsafe" ? 0o644 : 0o600], ofItemAtPath: receipt.path)
        }
        do { try await owner.pause(operationID: old); #expect(kind == "success") }
        catch { #expect(kind != "success") }
        try await child.value
        if kind == "success" {
            var record = (records["select"] as! [String: Any])["context"] as! [String: Any]
            record["expiresAtMonotonicNanoseconds"] = expiry
            let context = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes])
            let nextChild = Task { @MainActor in
                let until = ContinuousClock.now.advanced(by: .seconds(2))
                while ContinuousClock.now < until {
                    let request = try JSONSerialization.jsonObject(with: Data(contentsOf: command)) as! [String: Any]
                    if (request["sequence"] as? NSNumber)?.intValue == 2 {
                        #expect(request["previousOperationID"] as? String == old.uuidString)
                        try await Task.sleep(for: .milliseconds(80)) // Known old receipt cannot complete select.
                        let reply: [String: Any] = ["profile": "maccompanion.capture-handoff-receipt.v1",
                            "transportOperationID": old.uuidString, "operationID": next.uuidString, "sequence": 2,
                            "action": "select", "result": "selected"]
                        try JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys, .withoutEscapingSlashes]).write(to: receipt, options: .atomic)
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: receipt.path)
                        return
                    }
                    try await Task.sleep(for: .milliseconds(10))
                }
                Issue.record("Missing selection command")
            }
            try await owner.select(operationID: next, previousOperationID: old, context: context)
            try await nextChild.value
        }
        owner.close()
    }
}

@MainActor
@Test func managedCaptureParentRejectsDirectoryAliasAndExpiredLease() throws {
    let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("maccompanion-parent-scope-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: root) }
    let alias = root.appendingPathComponent("alias")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
    let now = DispatchTime.now().uptimeNanoseconds
    #expect(throws: (any Error).self) { try MacManagedCaptureHandoffV1(directory: alias, transport: UUID(), expiryNanoseconds: now+1_000_000_000, current: { true }) }
    #expect(throws: (any Error).self) { try MacManagedCaptureHandoffV1(directory: root, transport: UUID(), expiryNanoseconds: now, current: { true }) }
}

@MainActor
@Test func managedCaptureParentDiscardsAtomicallyReplacedReceipt() async throws {
    let fixture = try handoffFixture()
    #expect((fixture["childHandoffCases"] as! [String]).contains("atomic-receipt-replacement-discards-old-snapshot"))
    let records = fixture["childHandoff"] as! [String: Any]
    let old = UUID(uuidString: (records["pause"] as! [String: Any])["operationID"] as! String)!
    for scenario in ["atomic", "same-inode", "unsafe-mode", "hardlink", "symlink", "missing"] {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true).appendingPathComponent("maccompanion-parent-receipt-race-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let receipt = root.appendingPathComponent("capture-handoff-receipt.json")
        let command = root.appendingPathComponent("capture-handoff-command.json")
        let reply: [String: Any] = ["profile": "maccompanion.capture-handoff-receipt.v1",
            "transportOperationID": old.uuidString, "operationID": old.uuidString,
            "sequence": 1, "action": "pause", "result": "paused"]
        let exact = try JSONSerialization.data(withJSONObject: reply, options: [.sortedKeys, .withoutEscapingSlashes])
        func publish(_ data: Data) throws {
            let temporary = root.appendingPathComponent(UUID().uuidString)
            try data.write(to: temporary)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            guard rename(temporary.path, receipt.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        }
        // The opened snapshot is deliberately malformed. Only the newly opened,
        // independently checked exact replacement may finish the pause.
        try publish(scenario == "atomic" ? Data("{}".utf8) : exact)
        var replaced = false
        let owner = try MacManagedCaptureHandoffV1(directory: root, transport: old,
            expiryNanoseconds: DispatchTime.now().uptimeNanoseconds + 5_000_000_000,
            current: { true }, receiptReadCheckpoint: {
                guard !replaced else { return }
                replaced = true
                switch scenario {
                case "same-inode":
                    let fd = open(receipt.path, O_WRONLY | O_TRUNC | O_CLOEXEC)
                    guard fd >= 0 else { throw CocoaError(.fileWriteUnknown) }
                    defer { close(fd) }
                    let count = exact.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
                    guard count == exact.count else { throw CocoaError(.fileWriteUnknown) }
                case "missing": try FileManager.default.removeItem(at: receipt)
                case "symlink":
                    let target = root.appendingPathComponent("symlink-target")
                    try exact.write(to: target)
                    try FileManager.default.removeItem(at: receipt)
                    try FileManager.default.createSymbolicLink(at: receipt, withDestinationURL: target)
                default:
                    try publish(exact)
                    if scenario == "unsafe-mode" {
                        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: receipt.path)
                    } else if scenario == "hardlink" {
                        try FileManager.default.linkItem(at: receipt, to: root.appendingPathComponent("hardlink"))
                    }
                }
            })
        defer { owner.close() }
        do { try await owner.pause(operationID: old); #expect(scenario == "atomic") }
        catch { #expect(scenario != "atomic") }
        #expect(replaced)
        #expect(FileManager.default.fileExists(atPath: command.path))
    }
}

@Test func nativeSurfaceEpochSwiftMatchesIndexedCaptureCodec() throws {
    let f = try handoffFixture(), epoch = f["epoch"] as! [String: Any]
    let surface = try InteractiveNativeVideoSurfaceV0(surfaceID: UUID(uuidString: epoch["surfaceID"] as! String)!,
        surfaceRevision: (epoch["surfaceRevision"] as! NSNumber).int64Value,
        coordinateSpaceRevision: (epoch["coordinateSpaceRevision"] as! NSNumber).int64Value, encodedWidth: 640, encodedHeight: 360)
    let bytes = try surface.frameEpochData()
    #expect(bytes.count == 48)
    #expect(bytes.map { String(format: "%02x", $0) }.joined() == epoch["bytesHex"] as? String)
}
#endif
