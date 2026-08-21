import Darwin
import Foundation

public enum ClientPairedHostFileFaultPointV0: String, CaseIterable, Sendable {
    case afterTemporaryWrite
    case afterTemporarySync
    case beforeRename
    case afterRenameBeforeDirectorySync
}

public enum ClientPairedHostFileStoreErrorV0: Error, Equatable, Sendable {
    case unsafeStorage
    case quotaExceeded
    case ioFailure
    case injectedFault(ClientPairedHostFileFaultPointV0)
}

/// A bundle-independent public-record store suitable for an app-owned
/// Application Support directory. It never stores private-key bytes: the sole
/// serialization path is `ClientPairedHostStorageCodecV0`, whose key fields are
/// opaque references, public keys, roles, and protection profiles.
///
/// The final iOS composition must supply a protected container and prove its
/// Data Protection behavior. This type supplies atomic replacement, fsync
/// boundaries, strict restart decoding, bounded inventory, and injected crash
/// seams without claiming those platform tests.
public actor AtomicFileClientPairedHostStoreV0:
    ClientPairedHostPersistenceV0,
    ClientPairedHostRecoveryPersistenceV0,
    ClientPairedHostInventoryV1
{
    public static let maximumRecordBytes = 64 * 1_024
    public static let defaultMaximumRecordCount = 64

    private let directory: URL
    private let maximumRecordCount: Int
    private let injectedFaults: Set<ClientPairedHostFileFaultPointV0>
    private let fileManager: FileManager

    public init(
        directory: URL,
        maximumRecordCount: Int = defaultMaximumRecordCount,
        injectedFaults: Set<ClientPairedHostFileFaultPointV0> = [],
        fileManager: FileManager = .default
    ) throws {
        guard directory.isFileURL,
              (1...Self.defaultMaximumRecordCount).contains(
                maximumRecordCount
              ) else {
            throw ClientPairedHostFileStoreErrorV0.unsafeStorage
        }
        self.directory = directory.standardizedFileURL
        self.maximumRecordCount = maximumRecordCount
        self.injectedFaults = injectedFaults
        self.fileManager = fileManager
        try Self.prepareDirectory(
            self.directory,
            fileManager: fileManager
        )
    }

    public func commitAtomically(
        _ record: ClientDurablePairedHostV0
    ) async throws -> ClientPairedHostCommitResultV0 {
        let records = try loadAllRecords()
        for existing in records {
            if existing.pairingID == record.pairingID {
                guard existing == record else {
                    throw ClientIdentityPublicationErrorV0.persistenceConflict
                }
                return .alreadyPresentExactRecord
            }
            guard existing.hostID != record.hostID,
                  existing.deviceID != record.deviceID,
                  existing.sessionKey.reference != record.sessionKey.reference,
                  existing.approvalKey.reference != record.approvalKey.reference,
                  existing.sessionKey.reference != record.approvalKey.reference,
                  existing.approvalKey.reference != record.sessionKey.reference else {
                throw ClientIdentityPublicationErrorV0.persistenceConflict
            }
        }
        guard records.count < maximumRecordCount else {
            throw ClientPairedHostFileStoreErrorV0.quotaExceeded
        }

        let data = try ClientPairedHostStorageCodecV0.encode(record)
        guard data.count <= Self.maximumRecordBytes else {
            throw ClientPairedHostFileStoreErrorV0.quotaExceeded
        }
        let destination = recordURL(
            pairingID: record.pairingID,
            clientID: record.clientID
        )
        let temporary = directory.appendingPathComponent(
            ".pending-\(UUID().uuidString.lowercased())",
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
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw ClientIdentityPublicationErrorV0.persistenceConflict
            }
            try inject(.beforeRename)
            try fileManager.moveItem(at: temporary, to: destination)
            try inject(.afterRenameBeforeDirectorySync)
            try Self.synchronizeDirectory(directory)
            return .inserted
        } catch {
            if fileManager.fileExists(atPath: temporary.path) {
                try? fileManager.removeItem(at: temporary)
            }
            throw error
        }
    }

    public func storedRecord(
        pairingID: UUID,
        clientID: UUID
    ) async throws -> ClientDurablePairedHostV0? {
        let records = try loadAllRecords().filter {
            $0.pairingID == pairingID && $0.clientID == clientID
        }
        guard records.count <= 1 else {
            throw ClientPairedHostFileStoreErrorV0.unsafeStorage
        }
        return records.first
    }

    public func allRecords() async throws -> [ClientDurablePairedHostV0] {
        try loadAllRecords()
    }

    public func pairedHost(
        hostID: UUID
    ) async throws -> ClientDurablePairedHostV0? {
        let matches = try loadAllRecords().filter { $0.hostID == hostID }
        guard matches.count <= 1 else {
            throw ClientPairedHostFileStoreErrorV0.unsafeStorage
        }
        return matches.first
    }

    private func loadAllRecords() throws -> [ClientDurablePairedHostV0] {
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
                ],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw ClientPairedHostFileStoreErrorV0.ioFailure
        }
        guard entries.count <= maximumRecordCount else {
            throw ClientPairedHostFileStoreErrorV0.quotaExceeded
        }
        var records: [ClientDurablePairedHostV0] = []
        var filenames: Set<String> = []
        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard entry.pathExtension == "json",
                  filenames.insert(entry.lastPathComponent).inserted else {
                throw ClientPairedHostFileStoreErrorV0.unsafeStorage
            }
            let values: URLResourceValues
            do {
                values = try entry.resourceValues(forKeys: [
                    .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
                ])
            } catch {
                throw ClientPairedHostFileStoreErrorV0.ioFailure
            }
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let size = values.fileSize,
                  (1...Self.maximumRecordBytes).contains(size) else {
                throw ClientPairedHostFileStoreErrorV0.unsafeStorage
            }
            let data: Data
            do {
                data = try Data(contentsOf: entry, options: .mappedIfSafe)
            } catch {
                throw ClientPairedHostFileStoreErrorV0.ioFailure
            }
            let record = try ClientPairedHostStorageCodecV0.decode(data)
            guard entry.lastPathComponent == recordURL(
                pairingID: record.pairingID,
                clientID: record.clientID
            ).lastPathComponent else {
                throw ClientPairedHostFileStoreErrorV0.unsafeStorage
            }
            records.append(record)
        }
        return records
    }

    private func recordURL(pairingID: UUID, clientID: UUID) -> URL {
        directory.appendingPathComponent(
            "\(pairingID.uuidString.lowercased())-\(clientID.uuidString.lowercased()).json",
            isDirectory: false
        )
    }

    private func inject(_ point: ClientPairedHostFileFaultPointV0) throws {
        if injectedFaults.contains(point) {
            throw ClientPairedHostFileStoreErrorV0.injectedFault(point)
        }
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
                throw ClientPairedHostFileStoreErrorV0.unsafeStorage
            }
        } else {
            do {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
            } catch {
                throw ClientPairedHostFileStoreErrorV0.ioFailure
            }
        }
        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        } catch {
            throw ClientPairedHostFileStoreErrorV0.ioFailure
        }
    }

    private static func synchronizeFile(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw ClientPairedHostFileStoreErrorV0.ioFailure
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw ClientPairedHostFileStoreErrorV0.ioFailure
        }
    }

    private static func synchronizeDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_DIRECTORY)
        guard descriptor >= 0 else {
            throw ClientPairedHostFileStoreErrorV0.ioFailure
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw ClientPairedHostFileStoreErrorV0.ioFailure
        }
    }
}
