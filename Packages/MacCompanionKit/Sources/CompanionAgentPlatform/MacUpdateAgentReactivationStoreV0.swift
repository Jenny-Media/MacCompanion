#if os(macOS)
import CompanionLifecycle
import Darwin
import Foundation

public enum MacUpdateAgentReactivationStoreFaultV0:
    String, Equatable, Hashable, Sendable
{
    case afterTemporaryWrite
    case afterTemporarySync
    case beforeRename
    case afterRenameBeforeDirectorySync
    case afterClearBeforeDirectorySync
}

public enum MacUpdateAgentReactivationStoreErrorV0:
    Error, Equatable, Sendable
{
    case invalidDirectory
    case unsafeStorage
    case ioFailure
    case invalidRecord
    case injectedFault(MacUpdateAgentReactivationStoreFaultV0)
}

private struct MacUpdateAgentReactivationWireV0: Codable {
    let candidateBuild: UInt64
    let phase: String
    let profile: String
    let sourceBuild: UInt64
}

public enum MacUpdateAgentReactivationStorageCodecV0 {
    public static let maximumRecordBytes = 512

    public static func encode(
        _ receipt: MacUpdateAgentReactivationReceiptV0
    ) throws -> Data {
        let wire = MacUpdateAgentReactivationWireV0(
            candidateBuild: receipt.candidateBuild,
            phase: receipt.phase.rawValue,
            profile: receipt.profile,
            sourceBuild: receipt.sourceBuild
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data: Data
        do {
            data = try encoder.encode(wire)
        } catch {
            throw MacUpdateAgentReactivationStoreErrorV0.invalidRecord
        }
        data.append(0x0A)
        guard data.count <= maximumRecordBytes else {
            throw MacUpdateAgentReactivationStoreErrorV0.invalidRecord
        }
        return data
    }

    public static func decode(
        _ data: Data
    ) throws -> MacUpdateAgentReactivationReceiptV0 {
        guard (1...maximumRecordBytes).contains(data.count),
              data.last == 0x0A else {
            throw MacUpdateAgentReactivationStoreErrorV0.invalidRecord
        }
        do {
            let wire = try JSONDecoder().decode(
                MacUpdateAgentReactivationWireV0.self,
                from: data
            )
            guard let phase =
                    MacUpdateAgentReactivationReceiptPhaseV0(
                        rawValue: wire.phase
                    ) else {
                throw MacUpdateAgentReactivationStoreErrorV0.invalidRecord
            }
            let receipt = try MacUpdateAgentReactivationReceiptV0(
                profile: wire.profile,
                sourceBuild: wire.sourceBuild,
                candidateBuild: wire.candidateBuild,
                phase: phase
            )
            guard try encode(receipt) == data else {
                throw MacUpdateAgentReactivationStoreErrorV0.invalidRecord
            }
            return receipt
        } catch let error as MacUpdateAgentReactivationStoreErrorV0 {
            throw error
        } catch {
            throw MacUpdateAgentReactivationStoreErrorV0.invalidRecord
        }
    }
}

/// Private single-record Application Support store. It uses a process-shared
/// advisory lock, canonical bounded JSON, no-follow opens, 0700/0600 modes,
/// fsync before atomic rename, and directory fsync after replacement or clear.
public actor AtomicFileMacUpdateAgentReactivationStoreV0:
    MacUpdateAgentReactivationPersistenceV0
{
    public static let applicationSupportComponents = [
        "media.jenny.maccompanion", "Menu", "update-v0",
    ]

    private let directory: URL
    private let destination: URL
    private let faults: Set<MacUpdateAgentReactivationStoreFaultV0>
    private let fileManager: FileManager
    private let lockDescriptor: Int32

    public static func systemDefault() throws -> Self {
        let base: URL
        do {
            base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            throw MacUpdateAgentReactivationStoreErrorV0.invalidDirectory
        }
        let directory = applicationSupportComponents.reduce(base) {
            $0.appendingPathComponent($1, isDirectory: true)
        }
        return try Self(directory: directory)
    }

    public init(
        directory: URL,
        injectedFaults: Set<MacUpdateAgentReactivationStoreFaultV0> = [],
        fileManager: FileManager = .default
    ) throws {
        guard directory.isFileURL else {
            throw MacUpdateAgentReactivationStoreErrorV0.invalidDirectory
        }
        self.directory = directory.standardizedFileURL
        destination = self.directory.appendingPathComponent(
            "update-agent-reactivation.json",
            isDirectory: false
        )
        faults = injectedFaults
        self.fileManager = fileManager
        try Self.prepareDirectory(self.directory, fileManager: fileManager)

        let lockURL = self.directory.appendingPathComponent(
            ".update-agent-reactivation.lock",
            isDirectory: false
        )
        let descriptor = open(
            lockURL.path,
            O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW,
            0o600
        )
        guard descriptor >= 0, fchmod(descriptor, 0o600) == 0 else {
            if descriptor >= 0 { close(descriptor) }
            throw MacUpdateAgentReactivationStoreErrorV0.ioFailure
        }
        // Keep the descriptor local until validation succeeds. A fully
        // initialized throwing actor runs deinit, so assigning it before the
        // catch would close it twice and could close a newly reused descriptor.
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

    public func current() async throws
        -> MacUpdateAgentReactivationReceiptV0?
    {
        try withExclusiveLock {
            try prepareForAccess()
            return try loadCurrent()
        }
    }

    public func replace(
        expected: MacUpdateAgentReactivationReceiptV0?,
        with replacement: MacUpdateAgentReactivationReceiptV0
    ) async throws -> Bool {
        try withExclusiveLock {
            try prepareForAccess()
            let existing = try loadCurrent()
            guard existing == expected else { return false }
            if existing == replacement { return true }

            let data = try MacUpdateAgentReactivationStorageCodecV0
                .encode(replacement)
            let temporary = directory.appendingPathComponent(
                ".update-agent-reactivation.pending-"
                    + UUID().uuidString.lowercased(),
                isDirectory: false
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
                guard Darwin.rename(
                    temporary.path,
                    destination.path
                ) == 0 else {
                    throw MacUpdateAgentReactivationStoreErrorV0.ioFailure
                }
                try inject(.afterRenameBeforeDirectorySync)
                try Self.synchronizeDirectory(directory)
                return true
            } catch {
                if fileManager.fileExists(atPath: temporary.path) {
                    try? fileManager.removeItem(at: temporary)
                }
                throw error
            }
        }
    }

    public func clear(
        expected: MacUpdateAgentReactivationReceiptV0
    ) async throws -> Bool {
        try withExclusiveLock {
            try prepareForAccess()
            guard try loadCurrent() == expected else { return false }
            guard unlink(destination.path) == 0 else {
                throw MacUpdateAgentReactivationStoreErrorV0.ioFailure
            }
            try inject(.afterClearBeforeDirectorySync)
            try Self.synchronizeDirectory(directory)
            return true
        }
    }

    private func prepareForAccess() throws {
        try Self.recoverPendingFiles(
            in: directory,
            fileManager: fileManager
        )
        try Self.validateDirectoryContents(
            directory,
            destination: destination,
            fileManager: fileManager
        )
    }

    private func loadCurrent() throws
        -> MacUpdateAgentReactivationReceiptV0?
    {
        let descriptor = open(
            destination.path,
            O_RDONLY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw MacUpdateAgentReactivationStoreErrorV0.ioFailure
        }
        defer { close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              (status.st_mode & 0o777) == 0o600,
              status.st_size >= 1,
              status.st_size <= MacUpdateAgentReactivationStorageCodecV0
                .maximumRecordBytes else {
            throw MacUpdateAgentReactivationStoreErrorV0.unsafeStorage
        }
        let data: Data
        do {
            data = try FileHandle(
                fileDescriptor: descriptor,
                closeOnDealloc: false
            ).readToEnd() ?? Data()
        } catch {
            throw MacUpdateAgentReactivationStoreErrorV0.ioFailure
        }
        guard data.count == status.st_size else {
            throw MacUpdateAgentReactivationStoreErrorV0.unsafeStorage
        }
        return try MacUpdateAgentReactivationStorageCodecV0.decode(data)
    }

    private func inject(
        _ fault: MacUpdateAgentReactivationStoreFaultV0
    ) throws {
        if faults.contains(fault) {
            throw MacUpdateAgentReactivationStoreErrorV0
                .injectedFault(fault)
        }
    }

    private func withExclusiveLock<T>(
        _ operation: () throws -> T
    ) throws -> T {
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
            throw MacUpdateAgentReactivationStoreErrorV0.ioFailure
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
                throw MacUpdateAgentReactivationStoreErrorV0.unsafeStorage
            }
        } else {
            do {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                throw MacUpdateAgentReactivationStoreErrorV0.ioFailure
            }
        }
        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        } catch {
            throw MacUpdateAgentReactivationStoreErrorV0.ioFailure
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
                ]
            )
        } catch {
            throw MacUpdateAgentReactivationStoreErrorV0.ioFailure
        }
        for entry in entries where entry.lastPathComponent.hasPrefix(
            ".update-agent-reactivation.pending-"
        ) {
            let values = try entry.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                throw MacUpdateAgentReactivationStoreErrorV0.unsafeStorage
            }
            do {
                try fileManager.removeItem(at: entry)
            } catch {
                throw MacUpdateAgentReactivationStoreErrorV0.ioFailure
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
            ".update-agent-reactivation.lock",
        ])
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .isRegularFileKey, .isSymbolicLinkKey,
                ]
            )
        } catch {
            throw MacUpdateAgentReactivationStoreErrorV0.ioFailure
        }
        for entry in entries {
            guard allowed.contains(entry.lastPathComponent) else {
                throw MacUpdateAgentReactivationStoreErrorV0.unsafeStorage
            }
            let values = try entry.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                throw MacUpdateAgentReactivationStoreErrorV0.unsafeStorage
            }
        }
    }

    private static func synchronizeFile(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw MacUpdateAgentReactivationStoreErrorV0.ioFailure
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw MacUpdateAgentReactivationStoreErrorV0.ioFailure
        }
    }

    private static func synchronizeDirectory(_ directory: URL) throws {
        let descriptor = open(
            directory.path,
            O_RDONLY | O_CLOEXEC | O_DIRECTORY | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw MacUpdateAgentReactivationStoreErrorV0.ioFailure
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw MacUpdateAgentReactivationStoreErrorV0.ioFailure
        }
    }
}
#endif
