#if (os(iOS) || os(macOS)) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation

@MainActor protocol DirectFilesRemoteHandle {
    func attributes() async throws -> DirectFilesAttributes
    func read(offset: UInt64, length: UInt32) async throws -> Data
    func write(_ data: Data, offset: UInt64) async throws
    func close() async throws
}
@MainActor protocol DirectFilesRemoteStore {
    func directory(_ path: String) async throws -> DirectFilesDirectory
    func attributes(_ path: String) async throws -> DirectFilesAttributes?
    func createDirectory(_ path: String) async throws
    func open(_ path: String, writing: Bool) async throws -> any DirectFilesRemoteHandle
    func commit(_ temporary: String, to destination: String, replace: Bool) async throws
    func removeTemporary(_ path: String) async throws
    func close()
}

/// Local IO runs off the main actor. Only staged regular files reach this owner.
actor DirectFilesDiskFile {
    private let handle: FileHandle
    init(url: URL, writing: Bool) throws {
        handle = try writing ? FileHandle(forWritingTo: url) : FileHandle(forReadingFrom: url)
    }
    func read() throws -> Data { try handle.read(upToCount: DirectFilesPolicy.chunkSize) ?? Data() }
    func write(_ data: Data) throws { try handle.write(contentsOf: data) }
    func finish() throws { try handle.synchronize(); try handle.close() }
    func close() { try? handle.close() }
}

@MainActor enum DirectFilesTransfer {
    typealias Check = @MainActor () throws -> Void
    typealias Progress = @MainActor (UInt64, UInt64?) -> Void
    static func upload(source: URL, name: String, folder: String, replace: Bool,
                       store: any DirectFilesRemoteStore, check: Check, progress: Progress) async throws {
        let destination = try DirectFilesPolicy.child(name, of: folder)
        let temporary = try DirectFilesPolicy.child(".maccompanion-upload-" + UUID().uuidString + ".part", of: folder)
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let count = values.fileSize, count >= 0 else { throw DirectFilesFailure.notRegular }
        try check()
        let local = try DirectFilesDiskFile(url: source, writing: false)
        var remote: (any DirectFilesRemoteHandle)?
        var ownsTemporary = false
        do {
            remote = try await store.open(temporary, writing: true); ownsTemporary = true
            try check()
            let file = remote!
            var offset: UInt64 = 0
            while true {
                try check(); let data = try await local.read(); try check()
                if data.isEmpty { break }
                guard offset + UInt64(data.count) <= UInt64(count) else { throw DirectFilesFailure.changedFile }
                try await file.write(data, offset: offset); try check()
                offset += UInt64(data.count); progress(offset, UInt64(count))
            }
            guard offset == UInt64(count) else { throw DirectFilesFailure.changedFile }
            try await file.close(); remote = nil
            await local.close(); try check()
            try await store.commit(temporary, to: destination, replace: replace)
            ownsTemporary = false
            // The caller still checks its generation before publishing success.
        } catch {
            if let remote { try? await remote.close() }
            await local.close()
            if ownsTemporary { try? await store.removeTemporary(temporary) }
            throw error
        }
    }
    static func download(path: String, to destination: URL, store: any DirectFilesRemoteStore,
                         check: Check, progress: Progress) async throws {
        try check()
        let remote = try await store.open(path, writing: false)
        var local: DirectFilesDiskFile?
        do {
            let attrs = try await remote.attributes(); try check()
            guard attrs.kind == .file else { throw DirectFilesFailure.notRegular }
            local = try DirectFilesDiskFile(url: destination, writing: true)
            var offset: UInt64 = 0
            while true {
                try check()
                let data = try await remote.read(offset: offset, length: UInt32(DirectFilesPolicy.chunkSize)); try check()
                guard data.count <= DirectFilesPolicy.chunkSize else { throw DirectFilesFailure.changedFile }
                if data.isEmpty { break }
                guard offset <= UInt64.max - UInt64(data.count) else { throw DirectFilesFailure.changedFile }
                offset += UInt64(data.count)
                if let size = attrs.size, offset > size { throw DirectFilesFailure.changedFile }
                try await local!.write(data); try check(); progress(offset, attrs.size)
            }
            if let size = attrs.size, offset != size { throw DirectFilesFailure.changedFile }
            try await remote.close(); try await local!.finish(); try check()
        } catch {
            try? await remote.close(); await local?.close()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}

/// Private, ephemeral files. Names and bytes are never written to app diagnostics.
enum DirectFilesLocalStore {
    static func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Files-" + UUID().uuidString, isDirectory: true)
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o700]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.complete
        #endif
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: attributes)
        return url
    }
    static func emptyFile(in root: URL, name: String) throws -> URL {
        guard DirectFilesPolicy.validName(name) else { throw DirectFilesFailure.invalidName }
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let url = folder.appendingPathComponent(name)
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.complete
        #endif
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: attributes) else { throw DirectFilesFailure.unavailable }
        return url
    }
    static func stage(_ source: URL, in root: URL) throws -> URL {
        guard source.isFileURL, DirectFilesPolicy.validName(source.lastPathComponent) else { throw DirectFilesFailure.invalidName }
        let scope = source.startAccessingSecurityScopedResource()
        defer { if scope { source.stopAccessingSecurityScopedResource() } }
        let destination = try emptyFile(in: root, name: source.lastPathComponent)
        var coordinationError: NSError?, result: Result<Void, Error> = .failure(DirectFilesFailure.unavailable)
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
            result = Result {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize, size >= 0 else { throw DirectFilesFailure.notRegular }
                let input = try FileHandle(forReadingFrom: url), output = try FileHandle(forWritingTo: destination)
                defer { try? input.close(); try? output.close() }
                var count: UInt64 = 0
                while true {
                    try Task.checkCancellation()
                    let data = try input.read(upToCount: DirectFilesPolicy.chunkSize) ?? Data()
                    if data.isEmpty { break }
                    count += UInt64(data.count)
                    guard count <= UInt64(size) else { throw DirectFilesFailure.changedFile }
                    try output.write(contentsOf: data)
                }
                guard count == UInt64(size) else { throw DirectFilesFailure.changedFile }
                try output.synchronize()
            }
        }
        do { if let coordinationError { throw coordinationError }; try result.get(); try Task.checkCancellation(); return destination }
        catch { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()); throw error }
    }
}
#endif
