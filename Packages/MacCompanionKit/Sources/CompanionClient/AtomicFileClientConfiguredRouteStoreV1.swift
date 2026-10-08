import CompanionDomain
import CompanionWire
import Darwin
import Foundation

public enum ClientConfiguredRouteFileFaultPointV1:
    String, CaseIterable, Sendable
{
    case afterTemporaryWrite
    case afterTemporarySync
    case beforeRename
    case afterRenameBeforeDirectorySync
}

public enum ClientConfiguredRouteFileStoreErrorV1:
    Error, Equatable, Sendable
{
    case unsafeStorage
    case quotaExceeded
    case revisionConflict
    case ioFailure
    case injectedFault(ClientConfiguredRouteFileFaultPointV1)
}

public enum ClientConfiguredRouteCommitResultV1:
    Equatable, Sendable
{
    case inserted
    case replaced
    case alreadyPresentExactSnapshot
}

public protocol ClientConfiguredRoutePersistenceV1: Sendable {
    func snapshot(
        hostID: UUID
    ) async throws -> ClientConfiguredRouteCatalogSnapshotV1?

    func replaceAtomically(
        _ value: ClientConfiguredRouteCatalogSnapshotV1,
        expectedRevision: UInt64?
    ) async throws -> ClientConfiguredRouteCommitResultV1
}

public struct ClientConfiguredRouteCatalogSnapshotV1:
    Codable, Equatable, Sendable
{
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, hostID, revision, records
    }

    public let hostID: UUID
    public let revision: UInt64
    public let catalog: ClientConfiguredRouteCatalogV1

    public init(
        hostID: UUID,
        revision: UInt64,
        catalog: ClientConfiguredRouteCatalogV1
    ) throws {
        guard revision > 0,
              revision <= MonotonicRevision<AuthorizationEpochTag>
                .maximumWireValue else {
            throw ClientConfiguredRouteFileStoreErrorV1.revisionConflict
        }
        self.hostID = hostID
        self.revision = revision
        self.catalog = catalog
    }

    public init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy: RouteStoreAnyCodingKey.self)
        guard Set(keys.allKeys.map(\.stringValue))
                == Set(CodingKeys.allCases.map(\.stringValue)) else {
            throw ClientConfiguredRouteFileStoreErrorV1.unsafeStorage
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(UInt16.self, forKey: .schemaVersion) == 1
        else {
            throw ClientConfiguredRouteFileStoreErrorV1.unsafeStorage
        }
        try self.init(
            hostID: container.decode(WireUUID.self, forKey: .hostID).rawValue,
            revision: container.decode(UInt64.self, forKey: .revision),
            catalog: ClientConfiguredRouteCatalogV1(
                records: container.decode(
                    [ClientConfiguredRouteRecordV1].self,
                    forKey: .records
                )
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(UInt16(1), forKey: .schemaVersion)
        try container.encode(WireUUID(hostID), forKey: .hostID)
        try container.encode(revision, forKey: .revision)
        try container.encode(catalog.records, forKey: .records)
    }
}

private struct RouteStoreAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

public enum ClientConfiguredRouteCatalogStorageCodecV1 {
    public static func encode(
        _ value: ClientConfiguredRouteCatalogSnapshotV1
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    public static func decode(
        _ data: Data
    ) throws -> ClientConfiguredRouteCatalogSnapshotV1 {
        do {
            try StrictJSON.validate(data)
            let value = try JSONDecoder().decode(
                ClientConfiguredRouteCatalogSnapshotV1.self,
                from: data
            )
            guard try encode(value) == data else {
                throw ClientConfiguredRouteFileStoreErrorV1.unsafeStorage
            }
            return value
        } catch let error as ClientConfiguredRouteFileStoreErrorV1 {
            throw error
        } catch {
            throw ClientConfiguredRouteFileStoreErrorV1.unsafeStorage
        }
    }
}

/// Atomic, revision-fenced configured-route persistence for an app-owned
/// Application Support subdirectory. Endpoint text is durable by design;
/// credentials, DNS results, peer identities, and traffic are unrepresentable.
public actor AtomicFileClientConfiguredRouteStoreV1:
    ClientConfiguredRoutePersistenceV1
{
    public static let maximumRecordBytes = 16 * 1_024
    public static let maximumHostCount = 64

    private let directory: URL
    private let injectedFaults: Set<ClientConfiguredRouteFileFaultPointV1>
    private let fileManager: FileManager
    private let lockDescriptor: Int32

    public init(
        directory: URL,
        injectedFaults: Set<ClientConfiguredRouteFileFaultPointV1> = [],
        fileManager: FileManager = .default
    ) throws {
        guard directory.isFileURL else {
            throw ClientConfiguredRouteFileStoreErrorV1.unsafeStorage
        }
        self.directory = directory.standardizedFileURL
        self.injectedFaults = injectedFaults
        self.fileManager = fileManager
        try Self.prepareDirectory(self.directory, fileManager: fileManager)
        let lockURL = self.directory.appendingPathComponent(".lock")
        let descriptor = open(
            lockURL.path,
            O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
            0o600
        )
        guard descriptor >= 0, fchmod(descriptor, 0o600) == 0 else {
            if descriptor >= 0 { close(descriptor) }
            throw ClientConfiguredRouteFileStoreErrorV1.ioFailure
        }
        lockDescriptor = descriptor
        do {
            try Self.withExclusiveLock(descriptor: descriptor) {
                try Self.recoverPendingFiles(
                    in: self.directory,
                    fileManager: fileManager
                )
            }
        } catch {
            close(descriptor)
            throw error
        }
    }

    deinit {
        close(lockDescriptor)
    }

    public func snapshot(
        hostID: UUID
    ) async throws -> ClientConfiguredRouteCatalogSnapshotV1? {
        try withExclusiveLock {
            try Self.recoverPendingFiles(
                in: directory,
                fileManager: fileManager
            )
            _ = try visibleRecordURLs()
            return try loadSnapshot(
                at: recordURL(hostID: hostID),
                expectedHostID: hostID
            )
        }
    }

    public func replaceAtomically(
        _ value: ClientConfiguredRouteCatalogSnapshotV1,
        expectedRevision: UInt64?
    ) async throws -> ClientConfiguredRouteCommitResultV1 {
        try withExclusiveLock {
            try Self.recoverPendingFiles(
                in: directory,
                fileManager: fileManager
            )
            return try replaceAtomicallyLocked(
                value,
                expectedRevision: expectedRevision
            )
        }
    }

    public func remove(hostID: UUID) async throws {
        try withExclusiveLock {
            _ = try visibleRecordURLs()
            let url = recordURL(hostID: hostID)
            guard try loadSnapshot(at: url, expectedHostID: hostID) != nil else { return }
            try fileManager.removeItem(at: url)
            try Self.synchronizeDirectory(directory)
        }
    }

    private func replaceAtomicallyLocked(
        _ value: ClientConfiguredRouteCatalogSnapshotV1,
        expectedRevision: UInt64?
    ) throws -> ClientConfiguredRouteCommitResultV1 {
        let entries = try visibleRecordURLs()
        let destination = recordURL(hostID: value.hostID)
        let existing = try loadSnapshot(
            at: destination,
            expectedHostID: value.hostID
        )
        if existing == value { return .alreadyPresentExactSnapshot }
        if let existing {
            guard expectedRevision == existing.revision,
                  existing.revision
                    < MonotonicRevision<AuthorizationEpochTag>
                        .maximumWireValue,
                  value.revision == existing.revision + 1 else {
                throw ClientConfiguredRouteFileStoreErrorV1.revisionConflict
            }
        } else {
            guard expectedRevision == nil, value.revision == 1,
                  entries.count < Self.maximumHostCount else {
                throw entries.count >= Self.maximumHostCount
                    ? ClientConfiguredRouteFileStoreErrorV1.quotaExceeded
                    : ClientConfiguredRouteFileStoreErrorV1.revisionConflict
            }
        }

        let data = try ClientConfiguredRouteCatalogStorageCodecV1.encode(value)
        guard data.count <= Self.maximumRecordBytes else {
            throw ClientConfiguredRouteFileStoreErrorV1.quotaExceeded
        }
        let temporary = directory.appendingPathComponent(
            ".pending-\(UUID().uuidString.lowercased())"
        )
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: temporary.path
            )
            try inject(.afterTemporaryWrite)
            try Self.synchronizeFile(temporary)
            try inject(.afterTemporarySync)
            try inject(.beforeRename)
            guard Darwin.rename(temporary.path, destination.path) == 0 else {
                throw ClientConfiguredRouteFileStoreErrorV1.ioFailure
            }
            try inject(.afterRenameBeforeDirectorySync)
            try Self.synchronizeDirectory(directory)
            return existing == nil ? .inserted : .replaced
        } catch {
            if fileManager.fileExists(atPath: temporary.path) {
                try? fileManager.removeItem(at: temporary)
            }
            throw error
        }
    }

    private func visibleRecordURLs() throws -> [URL] {
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
                ],
                options: []
            )
        } catch {
            throw ClientConfiguredRouteFileStoreErrorV1.ioFailure
        }
        var records: [URL] = []
        for entry in entries {
            if entry.lastPathComponent == ".lock" {
                let values = try entry.resourceValues(forKeys: [
                    .isRegularFileKey, .isSymbolicLinkKey,
                ])
                guard values.isRegularFile == true,
                      values.isSymbolicLink != true else {
                    throw ClientConfiguredRouteFileStoreErrorV1.unsafeStorage
                }
                continue
            }
            guard !entry.lastPathComponent.hasPrefix("."),
                  entry.pathExtension == "json" else {
                throw ClientConfiguredRouteFileStoreErrorV1.unsafeStorage
            }
            records.append(entry)
        }
        guard records.count <= Self.maximumHostCount else {
            throw ClientConfiguredRouteFileStoreErrorV1.unsafeStorage
        }
        for entry in records {
            let stem = entry.deletingPathExtension().lastPathComponent
            guard stem == stem.lowercased(),
                  let hostID = UUID(uuidString: stem),
                  hostID.uuidString.lowercased() == stem,
                  try loadSnapshot(at: entry, expectedHostID: hostID) != nil
            else {
                throw ClientConfiguredRouteFileStoreErrorV1.unsafeStorage
            }
        }
        return records
    }

    private func withExclusiveLock<T>(
        _ body: () throws -> T
    ) throws -> T {
        try Self.withExclusiveLock(descriptor: lockDescriptor, body)
    }

    private static func withExclusiveLock<T>(
        descriptor: Int32,
        _ body: () throws -> T
    ) throws -> T {
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw ClientConfiguredRouteFileStoreErrorV1.ioFailure
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try body()
    }

    private static func recoverPendingFiles(
        in directory: URL,
        fileManager: FileManager
    ) throws {
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
                ],
                options: []
            )
        } catch {
            throw ClientConfiguredRouteFileStoreErrorV1.ioFailure
        }
        var removed = false
        for entry in entries where entry.lastPathComponent.hasPrefix(".pending-") {
            let suffix = String(entry.lastPathComponent.dropFirst(".pending-".count))
            let values = try entry.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
            ])
            guard suffix == suffix.lowercased(),
                  let identifier = UUID(uuidString: suffix),
                  identifier.uuidString.lowercased() == suffix,
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let size = values.fileSize,
                  size <= maximumRecordBytes else {
                throw ClientConfiguredRouteFileStoreErrorV1.unsafeStorage
            }
            do {
                try fileManager.removeItem(at: entry)
                removed = true
            } catch {
                throw ClientConfiguredRouteFileStoreErrorV1.ioFailure
            }
        }
        if removed { try synchronizeDirectory(directory) }
    }

    private func loadSnapshot(
        at url: URL,
        expectedHostID: UUID
    ) throws -> ClientConfiguredRouteCatalogSnapshotV1? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
        ])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              (1...Self.maximumRecordBytes).contains(size) else {
            throw ClientConfiguredRouteFileStoreErrorV1.unsafeStorage
        }
        let value = try ClientConfiguredRouteCatalogStorageCodecV1.decode(
            Data(contentsOf: url, options: .mappedIfSafe)
        )
        guard value.hostID == expectedHostID else {
            throw ClientConfiguredRouteFileStoreErrorV1.unsafeStorage
        }
        return value
    }

    private func recordURL(hostID: UUID) -> URL {
        directory.appendingPathComponent(
            "\(hostID.uuidString.lowercased()).json"
        )
    }

    private func inject(_ point: ClientConfiguredRouteFileFaultPointV1) throws {
        if injectedFaults.contains(point) {
            throw ClientConfiguredRouteFileStoreErrorV1.injectedFault(point)
        }
    }

    private static func prepareDirectory(
        _ directory: URL,
        fileManager: FileManager
    ) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            let values = try directory.resourceValues(forKeys: [
                .isDirectoryKey, .isSymbolicLinkKey,
            ])
            guard isDirectory.boolValue, values.isDirectory == true,
                  values.isSymbolicLink != true else {
                throw ClientConfiguredRouteFileStoreErrorV1.unsafeStorage
            }
        } else {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
    }

    private static func synchronizeFile(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw ClientConfiguredRouteFileStoreErrorV1.ioFailure
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw ClientConfiguredRouteFileStoreErrorV1.ioFailure
        }
    }

    private static func synchronizeDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_DIRECTORY)
        guard descriptor >= 0 else {
            throw ClientConfiguredRouteFileStoreErrorV1.ioFailure
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw ClientConfiguredRouteFileStoreErrorV1.ioFailure
        }
    }
}
