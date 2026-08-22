#if os(macOS)
import CompanionAgent
import CompanionPersistence
import Darwin
import Foundation

public enum MacAgentReleaseStorageErrorV1:
    Error, Equatable, Sendable
{
    case invalidBaseDirectory
    case insecureDirectory(String)
    case directoryIdentityChanged
}

/// Stable, non-secret locations owned by the per-user Agent. These values are
/// diagnostic paths, not an in-process security boundary: same-UID trusted
/// code can name the same files independently.
public struct MacAgentReleaseStoragePathsV1:
    Equatable, Sendable
{
    public let root: URL
    public let securityDatabase: URL
    public let detailedAuditDatabase: URL
    public let emergencyDenyLatch: URL
    public let remoteAccessIntentDirectory: URL

    fileprivate init(root: URL) {
        self.root = root
        securityDatabase = root.appendingPathComponent(
            "security-v1.sqlite3",
            isDirectory: false
        )
        detailedAuditDatabase = root.appendingPathComponent(
            "audit-v1.sqlite3",
            isDirectory: false
        )
        emergencyDenyLatch = root.appendingPathComponent(
            "emergency-deny-v1.latch",
            isDirectory: false
        )
        remoteAccessIntentDirectory = root.appendingPathComponent(
            "remote-access-intent-v1",
            isDirectory: true
        )
    }
}

/// Creates the complete durable storage authority required before an Agent
/// bootstrap may publish readiness. All three security artifacts are rooted
/// in one exact, private Application Support directory. The release factory
/// returns their required-audit composition without exposing retained store
/// or latch objects.
///
/// Construction never deletes or replaces visible state after an error. A
/// later launch must inspect and recover the same paths rather than silently
/// starting with a different security root.
public struct MacAgentReleaseStorageV1: Sendable {
    public static let applicationSupportComponents = [
        "media.jenny.maccompanion",
        "Agent",
        "v1",
    ]
    public static let securityMaximumPageCount: Int32 = 16_384
    public static let auditMaximumPageCount: Int32 = 8_192

    public let paths: MacAgentReleaseStoragePathsV1
    public let requiredAudit: AgentRequiredAuditCompositionV0

    public static func systemDefault() throws -> MacAgentReleaseStorageV1 {
        let base: URL
        do {
            base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            throw MacAgentReleaseStorageErrorV1.invalidBaseDirectory
        }
        return try MacAgentReleaseStorageV1(
            baseApplicationSupportDirectory: base
        )
    }

    package init(
        baseApplicationSupportDirectory base: URL,
        securityMaximumPageCount: Int32 =
            MacAgentReleaseStorageV1.securityMaximumPageCount,
        auditMaximumPageCount: Int32 =
            MacAgentReleaseStorageV1.auditMaximumPageCount
    ) throws {
        try self.init(
            baseApplicationSupportDirectory: base,
            securityMaximumPageCount: securityMaximumPageCount,
            auditMaximumPageCount: auditMaximumPageCount,
            afterArtifactsConstructed: { _ in }
        )
    }

    package init(
        baseApplicationSupportDirectory base: URL,
        securityMaximumPageCount: Int32 =
            MacAgentReleaseStorageV1.securityMaximumPageCount,
        auditMaximumPageCount: Int32 =
            MacAgentReleaseStorageV1.auditMaximumPageCount,
        afterArtifactsConstructed: @Sendable (
            MacAgentReleaseStoragePathsV1
        ) throws -> Void
    ) throws {
        let root = try Self.prepareRoot(beneath: base)
        let identity = try Self.directoryIdentity(
            root,
            error: .insecureDirectory(root.lastPathComponent)
        )
        let paths = MacAgentReleaseStoragePathsV1(root: root)

        let security = try SQLiteSecurityStore(
            path: paths.securityDatabase.path,
            maximumPageCount: securityMaximumPageCount
        )
        let audit = try SQLiteBoundedAuditStoreV0(
            path: paths.detailedAuditDatabase.path,
            maximumPageCount: auditMaximumPageCount
        )
        let latch = try EmergencyDenyLatch(
            url: paths.emergencyDenyLatch
        )
        try afterArtifactsConstructed(paths)

        guard try Self.directoryIdentity(
            root,
            error: .directoryIdentityChanged
        ) == identity else {
            throw MacAgentReleaseStorageErrorV1.directoryIdentityChanged
        }
        try Self.requirePrivateRegularFile(paths.securityDatabase)
        try Self.requirePrivateRegularFile(paths.detailedAuditDatabase)
        try Self.requirePrivateRegularFile(paths.emergencyDenyLatch)
        try security.validateStorageBinding()
        try audit.validateStorageBinding()
        try latch.validateStorageBinding()

        self.paths = paths
        requiredAudit = AgentRequiredAuditCompositionV0(
            securityStore: security,
            detailedAuditStore: audit,
            denyLatch: latch
        )
    }

    private struct DirectoryIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
    }

    private static func prepareRoot(beneath base: URL) throws -> URL {
        guard base.isFileURL,
              base.path.hasPrefix("/"),
              !base.path.utf8.contains(0) else {
            throw MacAgentReleaseStorageErrorV1.invalidBaseDirectory
        }
        let standardized = base.standardizedFileURL
        let canonicalBase = try validateBaseDirectory(standardized)

        var current = canonicalBase
        for component in applicationSupportComponents {
            current.appendPathComponent(component, isDirectory: true)
            try preparePrivateDirectory(current, component: component)
        }
        return current
    }

    private static func validateBaseDirectory(_ url: URL) throws -> URL {
        var status = stat()
        guard lstat(url.path, &status) == 0,
              (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              status.st_uid == geteuid(),
              (status.st_mode & 0o022) == 0 else {
            throw MacAgentReleaseStorageErrorV1.invalidBaseDirectory
        }
        return URL(
            fileURLWithPath: try canonicalPath(url.path),
            isDirectory: true
        )
    }

    private static func preparePrivateDirectory(
        _ url: URL,
        component: String
    ) throws {
        var status = stat()
        if lstat(url.path, &status) != 0 {
            guard errno == ENOENT,
                  mkdir(url.path, 0o700) == 0 else {
                throw MacAgentReleaseStorageErrorV1
                    .insecureDirectory(component)
            }
            let descriptor = open(
                url.path,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
            guard descriptor >= 0 else {
                throw MacAgentReleaseStorageErrorV1
                    .insecureDirectory(component)
            }
            defer { close(descriptor) }
            guard fchmod(descriptor, 0o700) == 0,
                  fsync(descriptor) == 0 else {
                throw MacAgentReleaseStorageErrorV1
                    .insecureDirectory(component)
            }
            try synchronizeDirectory(url.deletingLastPathComponent())
        }
        _ = try directoryIdentity(
            url,
            error: .insecureDirectory(component)
        )
    }

    private static func directoryIdentity(
        _ url: URL,
        error: MacAgentReleaseStorageErrorV1
    ) throws -> DirectoryIdentity {
        var status = stat()
        guard lstat(url.path, &status) == 0,
              (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              status.st_uid == geteuid(),
              (status.st_mode & 0o777) == 0o700,
              try canonicalPath(url.path) == url.path else {
            throw error
        }
        return DirectoryIdentity(
            device: UInt64(status.st_dev),
            inode: UInt64(status.st_ino)
        )
    }

    private static func requirePrivateRegularFile(_ url: URL) throws {
        var status = stat()
        guard lstat(url.path, &status) == 0,
              (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              status.st_uid == geteuid(),
              status.st_nlink == 1,
              (status.st_mode & 0o777) == 0o600 else {
            throw MacAgentReleaseStorageErrorV1.directoryIdentityChanged
        }
    }

    private static func canonicalPath(_ path: String) throws -> String {
        var resolved = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard realpath(path, &resolved) != nil,
              let end = resolved.firstIndex(of: 0) else {
            throw MacAgentReleaseStorageErrorV1.invalidBaseDirectory
        }
        return String(
            decoding: resolved[..<end].map { UInt8(bitPattern: $0) },
            as: UTF8.self
        )
    }

    private static func synchronizeDirectory(_ url: URL) throws {
        let descriptor = open(
            url.path,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw MacAgentReleaseStorageErrorV1.directoryIdentityChanged
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw MacAgentReleaseStorageErrorV1.directoryIdentityChanged
        }
    }
}
#endif
