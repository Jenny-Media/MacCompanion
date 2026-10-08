import CompanionLifecycle
import CompanionWire
import Darwin
import Foundation

public enum MacRemoteAccessIntentFileFaultPointV1:
    String, CaseIterable, Sendable
{
    case afterTemporaryWrite
    case afterTemporarySync
    case beforeRename
    case afterRenameBeforeDirectorySync
}

public enum MacRemoteAccessIntentStoreErrorV1:
    Error, Equatable, Sendable
{
    case unsafeStorage
    case revisionConflict
    case ioFailure
    case injectedFault(MacRemoteAccessIntentFileFaultPointV1)
}

public enum MacRemoteAccessIntentCommitResultV1:
    Equatable, Sendable
{
    case inserted
    case replaced
    case alreadyPresentExactSnapshot
}

public struct MacRemoteAccessIntentSnapshotV1:
    Codable, Equatable, Sendable
{
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion, revision, desiredEnabled, commandID
        case recordedAtUnixMilliseconds
    }

    public static let maximumSafeInteger: UInt64 = 9_007_199_254_740_991

    public let revision: UInt64
    public let desiredEnabled: Bool
    public let commandID: UUID
    public let recordedAtUnixMilliseconds: Int64

    public init(
        revision: UInt64,
        desiredEnabled: Bool,
        commandID: UUID,
        recordedAtUnixMilliseconds: Int64
    ) throws {
        guard (1...Self.maximumSafeInteger).contains(revision),
              recordedAtUnixMilliseconds >= 0,
              UInt64(recordedAtUnixMilliseconds) <= Self.maximumSafeInteger
        else {
            throw MacRemoteAccessIntentStoreErrorV1.unsafeStorage
        }
        self.revision = revision
        self.desiredEnabled = desiredEnabled
        self.commandID = commandID
        self.recordedAtUnixMilliseconds = recordedAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        let keys = try decoder.container(
            keyedBy: MacRemoteAccessIntentAnyCodingKeyV1.self
        )
        guard Set(keys.allKeys.map(\.stringValue))
                == Set(CodingKeys.allCases.map(\.stringValue)) else {
            throw MacRemoteAccessIntentStoreErrorV1.unsafeStorage
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(UInt16.self, forKey: .schemaVersion) == 1,
              let commandID = UUID(
                  uuidString: try container.decode(
                      String.self,
                      forKey: .commandID
                  )
              ) else {
            throw MacRemoteAccessIntentStoreErrorV1.unsafeStorage
        }
        try self.init(
            revision: container.decode(UInt64.self, forKey: .revision),
            desiredEnabled: container.decode(
                Bool.self,
                forKey: .desiredEnabled
            ),
            commandID: commandID,
            recordedAtUnixMilliseconds: container.decode(
                Int64.self,
                forKey: .recordedAtUnixMilliseconds
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(UInt16(1), forKey: .schemaVersion)
        try container.encode(revision, forKey: .revision)
        try container.encode(desiredEnabled, forKey: .desiredEnabled)
        try container.encode(
            commandID.uuidString.lowercased(),
            forKey: .commandID
        )
        try container.encode(
            recordedAtUnixMilliseconds,
            forKey: .recordedAtUnixMilliseconds
        )
    }
}

private struct MacRemoteAccessIntentAnyCodingKeyV1: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

public enum MacRemoteAccessIntentStorageCodecV1 {
    public static func encode(
        _ value: MacRemoteAccessIntentSnapshotV1
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    public static func decode(
        _ data: Data
    ) throws -> MacRemoteAccessIntentSnapshotV1 {
        do {
            try StrictJSON.validate(data)
            let value = try JSONDecoder().decode(
                MacRemoteAccessIntentSnapshotV1.self,
                from: data
            )
            guard try encode(value) == data else {
                throw MacRemoteAccessIntentStoreErrorV1.unsafeStorage
            }
            return value
        } catch let error as MacRemoteAccessIntentStoreErrorV1 {
            throw error
        } catch {
            throw MacRemoteAccessIntentStoreErrorV1.unsafeStorage
        }
    }
}

public protocol MacRemoteAccessIntentPersistenceV1: Sendable {
    func current() async throws -> MacRemoteAccessIntentSnapshotV1?

    func replaceAtomically(
        _ snapshot: MacRemoteAccessIntentSnapshotV1,
        expectedRevision: UInt64?
    ) async throws -> MacRemoteAccessIntentCommitResultV1
}

/// A final-identity-neutral, single-record Application Support store. The
/// containing app supplies the directory. The store uses a process-shared
/// advisory lock, canonical bounded JSON, no-follow opens, 0700/0600 modes,
/// fsync before rename, atomic replacement, and directory fsync afterward.
public actor AtomicFileMacRemoteAccessIntentStoreV1:
    MacRemoteAccessIntentPersistenceV1
{
    public static let maximumRecordBytes = 1_024

    private let directory: URL
    private let destination: URL
    private let injectedFaults: Set<MacRemoteAccessIntentFileFaultPointV1>
    private let fileManager: FileManager
    private let lockDescriptor: Int32

    public init(
        directory: URL,
        injectedFaults: Set<MacRemoteAccessIntentFileFaultPointV1> = [],
        fileManager: FileManager = .default
    ) throws {
        guard directory.isFileURL else {
            throw MacRemoteAccessIntentStoreErrorV1.unsafeStorage
        }
        self.directory = directory.standardizedFileURL
        destination = self.directory.appendingPathComponent(
            "remote-access-intent.json",
            isDirectory: false
        )
        self.injectedFaults = injectedFaults
        self.fileManager = fileManager
        try Self.prepareDirectory(self.directory, fileManager: fileManager)

        let lockURL = self.directory.appendingPathComponent(
            ".remote-access-intent.lock",
            isDirectory: false
        )
        let descriptor = open(
            lockURL.path,
            O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
            0o600
        )
        guard descriptor >= 0, fchmod(descriptor, 0o600) == 0 else {
            if descriptor >= 0 { close(descriptor) }
            throw MacRemoteAccessIntentStoreErrorV1.ioFailure
        }
        // Transfer ownership only after validation; a throwing initialized
        // actor otherwise closes once here and again from deinit.
        let checkedDirectory = self.directory
        let checkedDestination = destination
        do {
            try Self.withExclusiveLock(descriptor: descriptor) {
                try Self.recoverPendingFiles(
                    in: checkedDirectory,
                    fileManager: fileManager
                )
                try Self.validateDirectoryContents(
                    checkedDirectory,
                    destination: checkedDestination,
                    fileManager: fileManager
                )
            }
        } catch {
            close(descriptor)
            throw error
        }
        lockDescriptor = descriptor
    }

    deinit { close(lockDescriptor) }

    public func current() async throws -> MacRemoteAccessIntentSnapshotV1? {
        try withExclusiveLock {
            try Self.recoverPendingFiles(
                in: directory,
                fileManager: fileManager
            )
            try Self.validateDirectoryContents(
                directory,
                destination: destination,
                fileManager: fileManager
            )
            return try loadCurrent()
        }
    }

    public func replaceAtomically(
        _ snapshot: MacRemoteAccessIntentSnapshotV1,
        expectedRevision: UInt64?
    ) async throws -> MacRemoteAccessIntentCommitResultV1 {
        try withExclusiveLock {
            try Self.recoverPendingFiles(
                in: directory,
                fileManager: fileManager
            )
            try Self.validateDirectoryContents(
                directory,
                destination: destination,
                fileManager: fileManager
            )
            let existing = try loadCurrent()
            if existing == snapshot { return .alreadyPresentExactSnapshot }
            if let existing {
                guard expectedRevision == existing.revision,
                      existing.revision <
                          MacRemoteAccessIntentSnapshotV1.maximumSafeInteger,
                      snapshot.revision == existing.revision + 1 else {
                    throw MacRemoteAccessIntentStoreErrorV1.revisionConflict
                }
            } else {
                guard expectedRevision == nil, snapshot.revision == 1 else {
                    throw MacRemoteAccessIntentStoreErrorV1.revisionConflict
                }
            }

            let data = try MacRemoteAccessIntentStorageCodecV1.encode(snapshot)
            guard data.count <= Self.maximumRecordBytes else {
                throw MacRemoteAccessIntentStoreErrorV1.unsafeStorage
            }
            let temporary = directory.appendingPathComponent(
                ".remote-access-intent.pending-\(UUID().uuidString.lowercased())"
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
                    throw MacRemoteAccessIntentStoreErrorV1.ioFailure
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
    }

    private func loadCurrent() throws -> MacRemoteAccessIntentSnapshotV1? {
        guard fileManager.fileExists(atPath: destination.path) else {
            return nil
        }
        let values: URLResourceValues
        do {
            values = try destination.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
            ])
        } catch {
            throw MacRemoteAccessIntentStoreErrorV1.ioFailure
        }
        guard values.isRegularFile == true,
              values.isSymbolicLink != true,
              let size = values.fileSize,
              (1...Self.maximumRecordBytes).contains(size) else {
            throw MacRemoteAccessIntentStoreErrorV1.unsafeStorage
        }
        let descriptor = open(
            destination.path,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw MacRemoteAccessIntentStoreErrorV1.ioFailure
        }
        defer { close(descriptor) }
        var statBuffer = stat()
        guard fstat(descriptor, &statBuffer) == 0,
              (statBuffer.st_mode & S_IFMT) == S_IFREG,
              (statBuffer.st_mode & 0o777) == 0o600,
              statBuffer.st_size == size else {
            throw MacRemoteAccessIntentStoreErrorV1.unsafeStorage
        }
        let data: Data
        do {
            data = try FileHandle(
                fileDescriptor: descriptor,
                closeOnDealloc: false
            ).readToEnd() ?? Data()
        } catch {
            throw MacRemoteAccessIntentStoreErrorV1.ioFailure
        }
        return try MacRemoteAccessIntentStorageCodecV1.decode(data)
    }

    private func inject(
        _ point: MacRemoteAccessIntentFileFaultPointV1
    ) throws {
        if injectedFaults.contains(point) {
            throw MacRemoteAccessIntentStoreErrorV1.injectedFault(point)
        }
    }

    private func withExclusiveLock<T>(_ operation: () throws -> T) throws -> T {
        try Self.withExclusiveLock(
            descriptor: lockDescriptor,
            operation
        )
    }

    private static func withExclusiveLock<T>(
        descriptor: Int32,
        _ operation: () throws -> T
    ) throws -> T {
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw MacRemoteAccessIntentStoreErrorV1.ioFailure
        }
        defer { _ = flock(descriptor, LOCK_UN) }
        return try operation()
    }

    private static func prepareDirectory(
        _ directory: URL,
        fileManager: FileManager
    ) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(
            atPath: directory.path,
            isDirectory: &isDirectory
        ) {
            let values = try directory.resourceValues(forKeys: [
                .isDirectoryKey, .isSymbolicLinkKey,
            ])
            guard isDirectory.boolValue,
                  values.isDirectory == true,
                  values.isSymbolicLink != true else {
                throw MacRemoteAccessIntentStoreErrorV1.unsafeStorage
            }
        } else {
            do {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                throw MacRemoteAccessIntentStoreErrorV1.ioFailure
            }
        }
        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        } catch {
            throw MacRemoteAccessIntentStoreErrorV1.ioFailure
        }
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
                    .isRegularFileKey, .isSymbolicLinkKey,
                ],
                options: []
            )
        } catch {
            throw MacRemoteAccessIntentStoreErrorV1.ioFailure
        }
        for entry in entries where entry.lastPathComponent.hasPrefix(
            ".remote-access-intent.pending-"
        ) {
            let values = try entry.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                throw MacRemoteAccessIntentStoreErrorV1.unsafeStorage
            }
            do {
                try fileManager.removeItem(at: entry)
            } catch {
                throw MacRemoteAccessIntentStoreErrorV1.ioFailure
            }
        }
    }

    private static func validateDirectoryContents(
        _ directory: URL,
        destination: URL,
        fileManager: FileManager
    ) throws {
        let allowed = Set([
            destination.lastPathComponent,
            ".remote-access-intent.lock",
        ])
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .isRegularFileKey, .isSymbolicLinkKey,
                ],
                options: []
            )
        } catch {
            throw MacRemoteAccessIntentStoreErrorV1.ioFailure
        }
        for entry in entries {
            guard allowed.contains(entry.lastPathComponent) else {
                throw MacRemoteAccessIntentStoreErrorV1.unsafeStorage
            }
            let values = try entry.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                throw MacRemoteAccessIntentStoreErrorV1.unsafeStorage
            }
        }
    }

    private static func synchronizeFile(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw MacRemoteAccessIntentStoreErrorV1.ioFailure
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw MacRemoteAccessIntentStoreErrorV1.ioFailure
        }
    }

    private static func synchronizeDirectory(_ directory: URL) throws {
        let descriptor = open(
            directory.path,
            O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw MacRemoteAccessIntentStoreErrorV1.ioFailure
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw MacRemoteAccessIntentStoreErrorV1.ioFailure
        }
    }
}

/// Loads the durable intent before the Agent lifecycle authority is created.
/// An absent record is a deliberate safe-disabled default. Process states are
/// never restored as ready. An enabled eligible session starts both roles in
/// `starting` so fresh observations can advance them after start requests.
public struct MacDashboardLifecycleStartupStateLoaderV1: Sendable {
    private let intentStore: any MacRemoteAccessIntentPersistenceV1

    public init(intentStore: any MacRemoteAccessIntentPersistenceV1) {
        self.intentStore = intentStore
    }

    public func loadInitialState(
        consoleSession: ConsoleSessionState
    ) async throws -> ProductLifecycleState {
        let durable = try await intentStore.current()
        let enabled = durable?.desiredEnabled ?? false
        let processState: ManagedProcessState = enabled
            && consoleSession != .loggedOut
            ? .starting
            : .stopped
        return ProductLifecycleState(
            desiredEnabled: enabled,
            consoleSession: consoleSession,
            agent: processState,
            menuApp: processState
        )
    }
}
