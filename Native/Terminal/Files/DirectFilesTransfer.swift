#if (os(iOS) || os(macOS)) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Darwin

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
        var remote: (any DirectFilesRemoteHandle)?
        var local: DirectFilesDiskFile?
        do {
            guard let current = try await store.attributes(path), current.kind == .file else { throw DirectFilesFailure.notRegular }
            try check()
            let file = try await store.open(path, writing: false); remote = file
            let attrs = try await file.attributes(); try check()
            guard attrs.kind == .file else { throw DirectFilesFailure.notRegular }
            local = try DirectFilesDiskFile(url: destination, writing: true)
            var offset: UInt64 = 0
            while true {
                try check()
                let data = try await file.read(offset: offset, length: UInt32(DirectFilesPolicy.chunkSize)); try check()
                guard data.count <= DirectFilesPolicy.chunkSize else { throw DirectFilesFailure.changedFile }
                if data.isEmpty { break }
                guard offset <= UInt64.max - UInt64(data.count) else { throw DirectFilesFailure.changedFile }
                offset += UInt64(data.count)
                if let size = attrs.size, offset > size { throw DirectFilesFailure.changedFile }
                try await local!.write(data); try check(); progress(offset, attrs.size)
            }
            if let size = attrs.size, offset != size { throw DirectFilesFailure.changedFile }
            try await file.close(); remote = nil; try await local!.finish(); try check()
        } catch {
            try? await remote?.close(); await local?.close()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}

/// Admission and copying share one descriptor, even if a local writer replaces
/// the selected path. Nonblocking admission also rejects FIFOs without waiting.
final class DirectFilesStagingInput {
    private let handle: FileHandle
    private let size: UInt64
    init(url: URL) throws {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        }
        guard descriptor >= 0 else {
            throw errno == ELOOP ? DirectFilesFailure.notRegular : DirectFilesFailure.unavailable
        }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0 else {
            Darwin.close(descriptor); throw DirectFilesFailure.unavailable
        }
        guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), metadata.st_size >= 0 else {
            Darwin.close(descriptor); throw DirectFilesFailure.notRegular
        }
        size = UInt64(metadata.st_size)
        handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
    deinit { try? handle.close() }
    func copy(to destination: URL) throws {
        defer { try? handle.close() }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var count: UInt64 = 0
        while true {
            try Task.checkCancellation()
            let data = try handle.read(upToCount: DirectFilesPolicy.chunkSize) ?? Data()
            if data.isEmpty { break }
            count += UInt64(data.count)
            guard count <= size else { throw DirectFilesFailure.changedFile }
            try output.write(contentsOf: data)
        }
        guard count == size else { throw DirectFilesFailure.changedFile }
        try output.synchronize()
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
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: attributes) else {
            try? FileManager.default.removeItem(at: folder)
            throw DirectFilesFailure.unavailable
        }
        return url
    }
    static func removeStaged(_ urls: [URL], in root: URL) {
        for url in urls {
            let folder = url.deletingLastPathComponent()
            guard folder.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL,
                  UUID(uuidString: folder.lastPathComponent) != nil else { continue }
            try? FileManager.default.removeItem(at: folder)
        }
    }
    static func stageBatch(_ sources: [URL], in root: URL) throws -> [URL] {
        var staged: [URL] = []
        do {
            for source in sources {
                try Task.checkCancellation()
                staged.append(try stage(source, in: root))
            }
            try Task.checkCancellation()
            return staged
        } catch {
            removeStaged(staged, in: root)
            throw error
        }
    }
    static func stage(_ source: URL, in root: URL) throws -> URL {
        guard source.isFileURL, DirectFilesPolicy.validName(source.lastPathComponent) else { throw DirectFilesFailure.invalidName }
        let scope = source.startAccessingSecurityScopedResource()
        defer { if scope { source.stopAccessingSecurityScopedResource() } }
        // Foundation can open the path before invoking its accessor. Avoid
        // coordinating an already-special file (notably a blocking FIFO).
        // This preflight is advisory; the opened descriptor is authoritative.
        var metadata = stat()
        let inspected = source.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return lstat(path, &metadata) == 0
        }
        // A provider may not materialize a cloud file until coordination. An
        // unavailable preflight must not prevent that coordinated download.
        if inspected, metadata.st_mode & mode_t(S_IFMT) != mode_t(S_IFREG) { throw DirectFilesFailure.notRegular }
        let destination = try emptyFile(in: root, name: source.lastPathComponent)
        var coordinationError: NSError?, result: Result<Void, Error> = .failure(DirectFilesFailure.unavailable)
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
            result = Result {
                try DirectFilesStagingInput(url: url).copy(to: destination)
            }
        }
        do { if let coordinationError { throw coordinationError }; try result.get(); try Task.checkCancellation(); return destination }
        catch { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()); throw error }
    }
}
#endif
