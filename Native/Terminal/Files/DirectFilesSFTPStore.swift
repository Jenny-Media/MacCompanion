#if (os(iOS) || os(macOS)) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
@preconcurrency import Citadel
@preconcurrency import NIO
import Logging

@MainActor final class DirectFilesSFTPStore: DirectFilesRemoteStore {
    let client: SFTPClient
    init(client: SFTPClient) { self.client = client }
    static func attributes(_ value: SFTPFileAttributes) -> DirectFilesAttributes {
        let type = (value.permissions ?? 0) & 0o170000
        return .init(kind: type == 0o040000 ? .folder : type == 0o100000 ? .file : .other, size: value.size)
    }
    func directory(_ path: String) async throws -> DirectFilesDirectory {
        let canonical = try await client.getRealPath(atPath: path)
        guard DirectFilesPolicy.validPath(canonical) else { throw DirectFilesFailure.invalidPath }
        let listing = try await client.listDirectoryBounded(atPath: canonical, maximumEntries: 10_000)
        let entries = try listing.flatMap(\.components).filter { $0.filename != "." && $0.filename != ".." }.map { item -> DirectFilesEntry in
            guard DirectFilesPolicy.validName(item.filename) else { throw DirectFilesFailure.invalidName }
            let attrs = Self.attributes(item.attributes)
            return .init(name: item.filename, kind: attrs.kind, size: attrs.size)
        }
        guard Set(entries.map(\.name)).count == entries.count else { throw DirectFilesFailure.invalidName }
        return .init(path: canonical, entries: entries.sorted {
            if ($0.kind == .folder) != ($1.kind == .folder) { return $0.kind == .folder }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        })
    }
    func attributes(_ path: String) async throws -> DirectFilesAttributes? {
        do { return Self.attributes(try await client.getLinkAttributes(at: path)) }
        catch let status as SFTPMessage.Status where status.errorCode == .noSuchFile { return nil }
    }
    func createDirectory(_ path: String) async throws { try await client.createDirectory(atPath: path) }
    func open(_ path: String, writing: Bool) async throws -> any DirectFilesRemoteHandle {
        var attrs = SFTPFileAttributes.none; attrs.permissions = 0o600
        let file = try await client.openFile(filePath: path, flags: writing ? [.write, .create, .forceCreate] : [.read], attributes: writing ? attrs : .none)
        return DirectFilesSFTPHandle(file: file)
    }
    func commit(_ temporary: String, to destination: String, replace: Bool) async throws {
        if replace {
            guard try await client.supportsAtomicReplace() else { throw DirectFilesFailure.unsupportedReplace }
            try await client.renameReplacing(at: temporary, to: destination)
        } else { try await client.rename(at: temporary, to: destination) }
    }
    func removeTemporary(_ path: String) async throws { try await client.remove(at: path) }
    func close() { Task { try? await client.close() } }
}

// Used serially by one Files owner; Citadel's mutable file handle never escapes.
private final class DirectFilesSFTPHandle: DirectFilesRemoteHandle, @unchecked Sendable {
    private let file: SFTPFile
    init(file: SFTPFile) { self.file = file }
    func attributes() async throws -> DirectFilesAttributes { DirectFilesSFTPStore.attributes(try await file.readAttributes()) }
    func read(offset: UInt64, length: UInt32) async throws -> Data {
        let bytes = try await file.read(from: offset, length: length)
        return Data(bytes.readableBytesView)
    }
    func write(_ data: Data, offset: UInt64) async throws { try await file.write(ByteBuffer(bytes: data), at: offset) }
    func close() async throws { try await file.close() }
}
#endif
