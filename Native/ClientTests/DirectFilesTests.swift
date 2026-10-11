import XCTest
import Foundation
import NIO
@testable import Citadel
#if os(iOS)
@testable import Mac_Companion
#else
@testable import MacCompanion
#endif

@MainActor final class DirectFilesTests: XCTestCase {
    func testFilesPresentationUsesOwnerSnapshotAfterSavedMacChanges() {
        let original = DirectMacRecordV1(id: UUID(), name: "Original Files Mac", addresses: ["127.0.0.1"], sshPort: 22)
        let owner = DirectFilesSession(mac: original); defer { owner.close() }
        var edited = original; edited.name = "Edited Files Mac"; edited.addresses = ["127.0.0.2"]; edited.sshPort = 2222
        let view = DirectFilesView(mac: edited, session: owner)
        XCTAssertEqual(view.mac.name, original.name)
        XCTAssertEqual(view.mac.addresses, original.addresses)
        XCTAssertEqual(view.mac.sshPort, original.sshPort)
        let reopened = DirectFilesSession(mac: edited); defer { reopened.close() }
        XCTAssertEqual(DirectFilesView(mac: edited, session: reopened).mac.sshPort, 2222)
    }
    func testIndexedStandaloneAndRetainedDismissalPolicy() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-files-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for item in try XCTUnwrap(fixture["dismissalCases"] as? [[String: Bool]]) {
            XCTAssertEqual(DirectFilesPolicy.preventsDismissal(retained: try XCTUnwrap(item["retained"]), active: try XCTUnwrap(item["active"]), pending: try XCTUnwrap(item["pending"])), item["blocked"])
        }
    }
    func testIndexedAtomicReplacementPacketAndV3RenameFraming() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-files-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let packet = try XCTUnwrap(fixture["replacePacket"] as? [String: Any])
        let id = try XCTUnwrap(packet["id"] as? UInt32), source = try XCTUnwrap(packet["source"] as? String), destination = try XCTUnwrap(packet["destination"] as? String)
        var bytes = ByteBuffer()
        try SFTPMessageSerializer().encode(data: .posixRename(.init(requestId: id, oldPath: source, newPath: destination)), out: &bytes)
        XCTAssertEqual(bytes.readableBytesView.map { String(format: "%02x", $0) }.joined(), packet["hex"] as? String)
        bytes.clear()
        try SFTPMessageSerializer().encode(data: .rename(.init(requestId: id, oldPath: source, newPath: destination, flags: 0)), out: &bytes)
        // v3 RENAME has two SSH strings and no later-version flags field.
        XCTAssertEqual(bytes.readableBytes, 4 + 1 + 4 + 4 + source.utf8.count + 4 + destination.utf8.count)
        let metadata = try XCTUnwrap(fixture["metadataPacket"] as? [String: Any])
        bytes.clear()
        try SFTPMessageSerializer().encode(data: .lstat(.init(requestId: try XCTUnwrap(metadata["id"] as? UInt32), path: try XCTUnwrap(metadata["path"] as? String))), out: &bytes)
        XCTAssertEqual(bytes.readableBytesView.map { String(format: "%02x", $0) }.joined(), metadata["hex"] as? String)
    }
    func testIndexedFilenameAndPathAdmission() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-files-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for item in try XCTUnwrap(fixture["nameCases"] as? [[String: Any]]) {
            let name = try XCTUnwrap(item["name"] as? String)
            XCTAssertEqual(DirectFilesPolicy.validName(name), item["valid"] as? Bool, name)
        }
        for item in try XCTUnwrap(fixture["pathCases"] as? [[String: Any]]) {
            let path = try XCTUnwrap(item["path"] as? String)
            XCTAssertEqual(DirectFilesPolicy.validPath(path), item["valid"] as? Bool)
        }
        XCTAssertEqual(try DirectFilesPolicy.child("report.txt", of: "/"), "/report.txt")
        XCTAssertEqual(DirectFilesPolicy.duplicateName("report.txt", number: 2), "report (2).txt")
        XCTAssertThrowsError(try DirectFilesPolicy.child("report", of: String(repeating: "/a", count: 2048)))
    }
    func testUploadStreamsChunksAndClosesBeforePublishing() async throws {
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        let source = try DirectFilesLocalStore.emptyFile(in: root, name: "report.txt")
        let data = Data((0..<100_000).map { UInt8($0 % 251) }); try data.write(to: source)
        let store = FilesTestStore(), destination = "/home/report.txt"
        var progress: [UInt64] = []
        try await DirectFilesTransfer.upload(source: source, name: "report.txt", folder: "/home", replace: false,
            store: store, check: {}, progress: { progress.append($0); XCTAssertEqual($1, UInt64(data.count)) })
        XCTAssertEqual(store.files[destination], data)
        XCTAssertEqual(store.largestWrite, DirectFilesPolicy.chunkSize)
        XCTAssertEqual(store.commits, 1); XCTAssertTrue(store.closedBeforeCommit)
        XCTAssertEqual(progress.last, UInt64(data.count)); XCTAssertEqual(try Data(contentsOf: source), data)
        XCTAssertEqual(store.files.count, 1)
    }
    func testFailedUploadAndCancellationKeepOriginalAndRemoveOnlyOwnedTemporary() async throws {
        for cancelled in [false, true] {
            let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
            let source = try DirectFilesLocalStore.emptyFile(in: root, name: "existing.txt")
            try Data(repeating: 1, count: 100_000).write(to: source)
            let store = FilesTestStore(); let original = Data([7, 8, 9]); store.files["/home/existing.txt"] = original
            var stop = false
            store.wrote = { stop = true; if !cancelled { throw DirectFilesFailure.interrupted } }
            do {
                try await DirectFilesTransfer.upload(source: source, name: "existing.txt", folder: "/home", replace: true,
                    store: store, check: { if stop { throw CancellationError() } }, progress: { _, _ in })
                XCTFail("Interrupted upload succeeded")
            } catch {}
            XCTAssertEqual(store.files["/home/existing.txt"], original)
            XCTAssertEqual(store.commits, 0); XCTAssertEqual(store.files.count, 1)
            XCTAssertEqual(store.removed.count, 1); XCTAssertTrue(store.removed[0].contains(".maccompanion-upload-"))
        }
    }
    func testAtomicCommitFailureNeverDeletesExistingDestination() async throws {
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        let source = try DirectFilesLocalStore.emptyFile(in: root, name: "existing.txt")
        try Data([1, 2]).write(to: source)
        let store = FilesTestStore(); store.failCommit = true; store.files["/home/existing.txt"] = Data([9])
        do { try await DirectFilesTransfer.upload(source: source, name: "existing.txt", folder: "/home", replace: true,
            store: store, check: {}, progress: { _, _ in }); XCTFail("Commit should fail") } catch {}
        XCTAssertEqual(store.files["/home/existing.txt"], Data([9]))
        XCTAssertFalse(store.removed.contains("/home/existing.txt")); XCTAssertEqual(store.files.count, 1)
    }
    func testNewDestinationRaceDoesNotOverwrite() async throws {
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        let source = try DirectFilesLocalStore.emptyFile(in: root, name: "race.txt"); try Data([1]).write(to: source)
        let store = FilesTestStore(); store.files["/home/race.txt"] = Data([9])
        do { try await DirectFilesTransfer.upload(source: source, name: "race.txt", folder: "/home", replace: false,
            store: store, check: {}, progress: { _, _ in }); XCTFail("Should not replace") } catch {}
        XCTAssertEqual(store.files["/home/race.txt"], Data([9]))
    }
    func testDownloadStreamsAndRejectsTruncatedOrSpecialFilesWithoutExporting() async throws {
        for kind in [DirectFilesEntry.Kind.file, .other] {
            let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
            let destination = try DirectFilesLocalStore.emptyFile(in: root, name: "download.txt")
            let store = FilesTestStore(); store.files["/home/download.txt"] = Data([1, 2]); store.reportedSize = 3; store.kind = kind
            do { try await DirectFilesTransfer.download(path: "/home/download.txt", to: destination,
                store: store, check: {}, progress: { _, _ in }); XCTFail("Invalid download succeeded") } catch {}
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path)); XCTAssertEqual(store.handleCloses, kind == .file ? 1 : 0)
        }
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        let destination = try DirectFilesLocalStore.emptyFile(in: root, name: "download.txt")
        let store = FilesTestStore(); let data = Data(repeating: 3, count: 100_000); store.files["/home/download.txt"] = data
        try await DirectFilesTransfer.download(path: "/home/download.txt", to: destination, store: store, check: {}, progress: { _, _ in })
        XCTAssertEqual(try Data(contentsOf: destination), data); XCTAssertLessThanOrEqual(store.largestRead, DirectFilesPolicy.chunkSize)
    }
    func testIndexedDownloadAdmissionChecksPathBeforeOpenAndHandleAfterOpen() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "direct-files-v1", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for item in try XCTUnwrap(fixture["downloadAdmissionCases"] as? [[String: Any]]) {
            let pathKind = try XCTUnwrap(item["pathKind"] as? String), handleKind = try XCTUnwrap(item["handleKind"] as? String)
            let accepted = try XCTUnwrap(item["accepted"] as? Bool)
            let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
            let destination = try DirectFilesLocalStore.emptyFile(in: root, name: "selected.txt")
            let store = FilesTestStore(), path = "/home/selected.txt", bytes = Data([1, 2, 3])
            if pathKind != "missing" { store.files[path] = bytes }
            store.kind = pathKind == "file" ? .file : .other
            store.handleKind = handleKind == "file" ? .file : .other
            do {
                try await DirectFilesTransfer.download(path: path, to: destination, store: store, check: {}, progress: { _, _ in })
                XCTAssertTrue(accepted); XCTAssertEqual(try Data(contentsOf: destination), bytes)
            } catch {
                XCTAssertFalse(accepted); XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            }
            XCTAssertEqual(store.opens, pathKind == "file" ? 1 : 0)
            XCTAssertEqual(store.handleCloses, pathKind == "file" ? 1 : 0)
            XCTAssertEqual(store.pathChecks, 1)
        }
    }
    func testStagePreservesOriginalAndRejectsFoldersAndLinks() throws {
        let root = try DirectFilesLocalStore.root(); defer { try? FileManager.default.removeItem(at: root) }
        let source = try DirectFilesLocalStore.emptyFile(in: root, name: "Résumé.txt"); let bytes = Data([0, 1, 255]); try bytes.write(to: source)
        let staged = try DirectFilesLocalStore.stage(source, in: root)
        XCTAssertEqual(try Data(contentsOf: staged), bytes); XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertNotEqual(source, staged)
        XCTAssertThrowsError(try DirectFilesLocalStore.stage(source.deletingLastPathComponent(), in: root))
        let link = root.appendingPathComponent("link"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        XCTAssertThrowsError(try DirectFilesLocalStore.stage(link, in: root))
    }
}

@MainActor private final class FilesTestStore: DirectFilesRemoteStore {
    var files: [String: Data] = [:]
    var largestWrite = 0, largestRead = 0, commits = 0, handleCloses = 0, opens = 0, pathChecks = 0
    var closedBeforeCommit = false, failCommit = false
    var removed: [String] = []
    var wrote: (() throws -> Void)?
    var reportedSize: UInt64?
    var kind = DirectFilesEntry.Kind.file
    var handleKind: DirectFilesEntry.Kind?
    func directory(_ path: String) async throws -> DirectFilesDirectory { .init(path: path, entries: []) }
    func attributes(_ path: String) async throws -> DirectFilesAttributes? { pathChecks += 1; return files[path].map { .init(kind: kind, size: reportedSize ?? UInt64($0.count)) } }
    func createDirectory(_ path: String) async throws {}
    func open(_ path: String, writing: Bool) async throws -> any DirectFilesRemoteHandle {
        opens += 1
        if writing { guard files[path] == nil else { throw DirectFilesFailure.unavailable }; files[path] = Data() }
        guard files[path] != nil else { throw DirectFilesFailure.unavailable }
        return FilesTestHandle(path: path, store: self)
    }
    func commit(_ temporary: String, to destination: String, replace: Bool) async throws {
        commits += 1; closedBeforeCommit = handleCloses > 0
        guard !failCommit, replace || files[destination] == nil else { throw DirectFilesFailure.unsupportedReplace }
        files[destination] = files.removeValue(forKey: temporary)
    }
    func removeTemporary(_ path: String) async throws { removed.append(path); files.removeValue(forKey: path) }
    func close() {}
}
@MainActor private final class FilesTestHandle: DirectFilesRemoteHandle {
    let path: String; let store: FilesTestStore; var closed = false
    init(path: String, store: FilesTestStore) { self.path = path; self.store = store }
    func attributes() async throws -> DirectFilesAttributes { .init(kind: store.handleKind ?? store.kind, size: store.reportedSize ?? UInt64(store.files[path]!.count)) }
    func read(offset: UInt64, length: UInt32) async throws -> Data {
        store.largestRead = max(store.largestRead, Int(length))
        return Data(store.files[path]!.dropFirst(Int(offset)).prefix(Int(length)))
    }
    func write(_ data: Data, offset: UInt64) async throws {
        store.largestWrite = max(store.largestWrite, data.count); store.files[path]!.append(data); try store.wrote?()
    }
    func close() async throws { if !closed { closed = true; store.handleCloses += 1 } }
}
