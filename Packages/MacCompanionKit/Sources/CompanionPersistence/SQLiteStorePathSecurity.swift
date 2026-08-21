#if os(macOS)
import Darwin
import Foundation

enum SQLiteStorePathSecurityError: Error {
    case unsafePath
}

enum SQLiteStorePathSecurity {
    private static let privateDirectoryMode: mode_t = 0o700
    private static let privateFileMode: mode_t = 0o600

    static func prepareDatabase(at path: String) throws -> String {
        guard !path.isEmpty,
              !path.utf8.contains(0),
              (path as NSString).isAbsolutePath else {
            throw SQLiteStorePathSecurityError.unsafePath
        }
        let unresolvedParent = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        guard !unresolvedParent.isEmpty,
              name != ".",
              name != ".." else {
            throw SQLiteStorePathSecurityError.unsafePath
        }
        let parent = try resolvedDirectory(unresolvedParent)
        let canonicalPath = (parent as NSString).appendingPathComponent(name)
        try validateDirectory(parent)

        var status = stat()
        if lstat(canonicalPath, &status) == 0 {
            try validateFileStatus(status)
        } else {
            guard errno == ENOENT else {
                throw SQLiteStorePathSecurityError.unsafePath
            }

            let descriptor = open(
                canonicalPath,
                O_CREAT | O_EXCL | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
                privateFileMode
            )
            guard descriptor >= 0 else {
                throw SQLiteStorePathSecurityError.unsafePath
            }
            defer { close(descriptor) }
            guard fchmod(descriptor, privateFileMode) == 0,
                  fstat(descriptor, &status) == 0 else {
                throw SQLiteStorePathSecurityError.unsafePath
            }
            try validateFileStatus(status)
        }
        try validateFile(canonicalPath + "-wal", required: false)
        try validateFile(canonicalPath + "-shm", required: false)
        try validateFile(canonicalPath + "-journal", required: false)
        return canonicalPath
    }

    static func validateDatabaseArtifacts(at path: String) throws {
        let parent = (path as NSString).deletingLastPathComponent
        try validateDirectory(parent)
        try validateFile(path, required: true)
        try validateFile(path + "-wal", required: false)
        try validateFile(path + "-shm", required: false)
        try validateFile(path + "-journal", required: false)
    }

    private static func validateDirectory(_ path: String) throws {
        var status = stat()
        guard lstat(path, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFDIR,
              status.st_uid == geteuid(),
              (status.st_mode & privateDirectoryMode)
                == privateDirectoryMode,
              (status.st_mode & 0o022) == 0 else {
            throw SQLiteStorePathSecurityError.unsafePath
        }
    }

    private static func resolvedDirectory(_ path: String) throws -> String {
        var resolved = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(path, &resolved) != nil,
              let end = resolved.firstIndex(of: 0) else {
            throw SQLiteStorePathSecurityError.unsafePath
        }
        return String(
            decoding: resolved[..<end].map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
    }

    private static func validateFile(
        _ path: String,
        required: Bool
    ) throws {
        var status = stat()
        if lstat(path, &status) == 0 {
            try validateFileStatus(status)
            return
        }
        guard !required, errno == ENOENT else {
            throw SQLiteStorePathSecurityError.unsafePath
        }
    }

    private static func validateFileStatus(_ status: stat) throws {
        guard (status.st_mode & S_IFMT) == S_IFREG,
              status.st_uid == geteuid(),
              status.st_nlink == 1,
              (status.st_mode & 0o777) == privateFileMode else {
            throw SQLiteStorePathSecurityError.unsafePath
        }
    }
}
#endif
