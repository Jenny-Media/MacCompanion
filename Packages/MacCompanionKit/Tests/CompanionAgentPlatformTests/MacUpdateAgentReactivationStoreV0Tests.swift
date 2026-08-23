#if os(macOS)
@testable import CompanionAgentPlatform
import CompanionLifecycle
import Foundation
import Testing

private func updateReceiptStoreDirectoryV0() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "maccompanion-update-receipt-\(UUID().uuidString)",
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    return directory
}

private func platformUpdateReceiptV0(
    phase: MacUpdateAgentReactivationReceiptPhaseV0 = .prepared,
    candidateBuild: UInt64 = 11
) throws -> MacUpdateAgentReactivationReceiptV0 {
    try MacUpdateAgentReactivationReceiptV0(
        sourceBuild: 10,
        candidateBuild: candidateBuild,
        phase: phase
    )
}

@Test func updateReceiptCodecIsCanonicalAndClosed() throws {
    let receipt = try platformUpdateReceiptV0(phase: .agentStopped)
    let data = try MacUpdateAgentReactivationStorageCodecV0.encode(receipt)
    #expect(
        String(decoding: data, as: UTF8.self)
            == "{\"candidateBuild\":11,\"phase\":\"agentStopped\",\"profile\":\"maccompanion.update-agent-reactivation.v0.1\",\"sourceBuild\":10}\n"
    )
    #expect(
        try MacUpdateAgentReactivationStorageCodecV0.decode(data)
            == receipt
    )

    let mutations = [
        Data(data.dropLast()),
        Data(" \(String(decoding: data, as: UTF8.self))".utf8),
        Data(String(decoding: data, as: UTF8.self).replacingOccurrences(
            of: "\"sourceBuild\":10",
            with: "\"sourceBuild\":10,\"unknown\":true"
        ).utf8),
        Data(String(decoding: data, as: UTF8.self).replacingOccurrences(
            of: "\"sourceBuild\":10",
            with: "\"sourceBuild\":10,\"sourceBuild\":10"
        ).utf8),
    ]
    for mutation in mutations {
        #expect(
            throws: MacUpdateAgentReactivationStoreErrorV0.invalidRecord
        ) {
            _ = try MacUpdateAgentReactivationStorageCodecV0
                .decode(mutation)
        }
    }
}

@Test func updateReceiptStoreInsertsAdvancesReopensAndClears()
async throws {
    let directory = try updateReceiptStoreDirectoryV0()
    defer { try? FileManager.default.removeItem(at: directory) }
    let prepared = try platformUpdateReceiptV0()
    let stopped = try platformUpdateReceiptV0(phase: .agentStopped)
    let store = try AtomicFileMacUpdateAgentReactivationStoreV0(
        directory: directory
    )

    #expect(try await store.current() == nil)
    #expect(try await store.replace(expected: nil, with: prepared))
    #expect(
        try await store.replace(expected: prepared, with: stopped)
    )
    #expect(try await store.current() == stopped)

    let reopened = try AtomicFileMacUpdateAgentReactivationStoreV0(
        directory: directory
    )
    #expect(try await reopened.current() == stopped)
    #expect(try await reopened.clear(expected: stopped))
    #expect(try await store.current() == nil)

    let attributes = try FileManager.default.attributesOfItem(
        atPath: directory.path
    )
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
}

@Test func updateReceiptStoreCompareAndSwapNeverOverwrites()
async throws {
    let directory = try updateReceiptStoreDirectoryV0()
    defer { try? FileManager.default.removeItem(at: directory) }
    let prepared = try platformUpdateReceiptV0()
    let other = try platformUpdateReceiptV0(candidateBuild: 12)
    let store = try AtomicFileMacUpdateAgentReactivationStoreV0(
        directory: directory
    )

    #expect(try await store.replace(expected: nil, with: prepared))
    #expect(
        try await store.replace(expected: nil, with: other) == false
    )
    #expect(try await store.clear(expected: other) == false)
    #expect(try await store.current() == prepared)
}

@Test func preRenameFailureLeavesNoVisibleReceipt() async throws {
    let directory = try updateReceiptStoreDirectoryV0()
    defer { try? FileManager.default.removeItem(at: directory) }
    let receipt = try platformUpdateReceiptV0()
    let store = try AtomicFileMacUpdateAgentReactivationStoreV0(
        directory: directory,
        injectedFaults: [.afterTemporarySync]
    )

    await #expect(
        throws: MacUpdateAgentReactivationStoreErrorV0.injectedFault(
            .afterTemporarySync
        )
    ) {
        _ = try await store.replace(expected: nil, with: receipt)
    }
    #expect(try await store.current() == nil)
}

@Test func postRenameFailureConvergesOnReadback() async throws {
    let directory = try updateReceiptStoreDirectoryV0()
    defer { try? FileManager.default.removeItem(at: directory) }
    let receipt = try platformUpdateReceiptV0()
    let store = try AtomicFileMacUpdateAgentReactivationStoreV0(
        directory: directory,
        injectedFaults: [.afterRenameBeforeDirectorySync]
    )

    await #expect(
        throws: MacUpdateAgentReactivationStoreErrorV0.injectedFault(
            .afterRenameBeforeDirectorySync
        )
    ) {
        _ = try await store.replace(expected: nil, with: receipt)
    }
    #expect(try await store.current() == receipt)
}

@Test func postClearFailureConvergesOnAbsentReceipt() async throws {
    let directory = try updateReceiptStoreDirectoryV0()
    defer { try? FileManager.default.removeItem(at: directory) }
    let receipt = try platformUpdateReceiptV0()
    let writer = try AtomicFileMacUpdateAgentReactivationStoreV0(
        directory: directory
    )
    #expect(try await writer.replace(expected: nil, with: receipt))
    let clearing = try AtomicFileMacUpdateAgentReactivationStoreV0(
        directory: directory,
        injectedFaults: [.afterClearBeforeDirectorySync]
    )

    await #expect(
        throws: MacUpdateAgentReactivationStoreErrorV0.injectedFault(
            .afterClearBeforeDirectorySync
        )
    ) {
        _ = try await clearing.clear(expected: receipt)
    }
    #expect(try await writer.current() == nil)
}

@Test func updateReceiptStoreRejectsSymlinksAndUnexpectedEntries()
throws {
    let symlinkDirectory = try updateReceiptStoreDirectoryV0()
    defer { try? FileManager.default.removeItem(at: symlinkDirectory) }
    let destination = symlinkDirectory.appendingPathComponent(
        "update-agent-reactivation.json"
    )
    try FileManager.default.createSymbolicLink(
        at: destination,
        withDestinationURL: URL(fileURLWithPath: "/dev/null")
    )
    #expect(throws: MacUpdateAgentReactivationStoreErrorV0.unsafeStorage) {
        _ = try AtomicFileMacUpdateAgentReactivationStoreV0(
            directory: symlinkDirectory
        )
    }

    let extraDirectory = try updateReceiptStoreDirectoryV0()
    defer { try? FileManager.default.removeItem(at: extraDirectory) }
    try Data("unexpected".utf8).write(
        to: extraDirectory.appendingPathComponent("other")
    )
    #expect(throws: MacUpdateAgentReactivationStoreErrorV0.unsafeStorage) {
        _ = try AtomicFileMacUpdateAgentReactivationStoreV0(
            directory: extraDirectory
        )
    }
}

@Test func concurrentReceiptInsertionHasOneWinner() async throws {
    let directory = try updateReceiptStoreDirectoryV0()
    defer { try? FileManager.default.removeItem(at: directory) }
    let firstStore = try AtomicFileMacUpdateAgentReactivationStoreV0(
        directory: directory
    )
    let secondStore = try AtomicFileMacUpdateAgentReactivationStoreV0(
        directory: directory
    )
    let firstReceipt = try platformUpdateReceiptV0(candidateBuild: 11)
    let secondReceipt = try platformUpdateReceiptV0(candidateBuild: 12)

    async let first = firstStore.replace(
        expected: nil,
        with: firstReceipt
    )
    async let second = secondStore.replace(
        expected: nil,
        with: secondReceipt
    )
    let outcomes = try await [first, second]
    #expect(outcomes.filter { $0 }.count == 1)
    #expect(try await firstStore.current() != nil)
}
#endif
