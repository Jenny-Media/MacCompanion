#if os(iOS)
import CompanionClient
import Darwin
import Foundation

public enum IOSClientReleaseBootstrapFailureV1:
    String, Equatable, Sendable
{
    case storageUnavailable
    case invalidInstallationIdentity
    case ambiguousSavedState
    case keyUnavailable
    case routeConfigurationMissing
}

public enum IOSClientReleaseBootstrapPhaseV1: Equatable, Sendable {
    case idle
    case preparing
    case unpaired
    case pairedRouteConfigurationRequired(hostID: UUID)
    case paired(hostID: UUID)
    case unavailable(IOSClientReleaseBootstrapFailureV1)
    case closed
}

public struct IOSClientReleaseBootstrapSnapshotV1:
    Equatable, Sendable
{
    public static let idle = IOSClientReleaseBootstrapSnapshotV1(
        revision: 0,
        phase: .idle
    )

    public let revision: UInt64
    public let phase: IOSClientReleaseBootstrapPhaseV1

    public init(
        revision: UInt64,
        phase: IOSClientReleaseBootstrapPhaseV1
    ) {
        self.revision = revision
        self.phase = phase
    }
}

public actor IOSClientReleaseBootstrapV1 {
    private typealias StorageFactory = @Sendable () throws
        -> IOSClientReleaseStorageV1

    private var snapshotValue = IOSClientReleaseBootstrapSnapshotV1.idle
    private var storage: IOSClientReleaseStorageV1?
    private var startInProgress = false
    private let storageFactory: StorageFactory

    public init() {
        storageFactory = { try IOSClientReleaseStorageV1.systemDefault() }
    }

    package init(
        storageFactory: @escaping @Sendable () throws
            -> IOSClientReleaseStorageV1
    ) {
        self.storageFactory = storageFactory
    }

    public func snapshot() -> IOSClientReleaseBootstrapSnapshotV1 {
        snapshotValue
    }

    @discardableResult
    public func start() async -> IOSClientReleaseBootstrapSnapshotV1 {
        guard !startInProgress else { return snapshotValue }
        switch snapshotValue.phase {
        case .idle, .unavailable:
            break
        case .preparing, .unpaired, .pairedRouteConfigurationRequired,
             .paired, .closed:
            return snapshotValue
        }

        startInProgress = true
        publish(.preparing)
        defer { startInProgress = false }

        let storage: IOSClientReleaseStorageV1
        do {
            storage = try storageFactory()
        } catch let error as IOSClientReleaseStorageErrorV1 {
            switch error {
            case .invalidInstallationIdentity:
                return publish(.unavailable(.invalidInstallationIdentity))
            default:
                return publish(.unavailable(.storageUnavailable))
            }
        } catch {
            return publish(.unavailable(.storageUnavailable))
        }

        let records: [ClientDurablePairedHostV0]
        do {
            records = try await storage.pairedHosts.allRecords()
        } catch {
            return publish(.unavailable(.storageUnavailable))
        }
        guard records.count <= 1 else {
            return publish(.unavailable(.ambiguousSavedState))
        }
        guard records.allSatisfy({ $0.clientID == storage.clientID }) else {
            return publish(.unavailable(.invalidInstallationIdentity))
        }

        let routeHostIDs: Set<UUID>
        do {
            routeHostIDs = try storage.storedRouteHostIDs()
        } catch {
            return publish(.unavailable(.storageUnavailable))
        }

        if let record = records.first {
            guard routeHostIDs.isEmpty || routeHostIDs == [record.hostID]
            else {
                return publish(.unavailable(.ambiguousSavedState))
            }
            do {
                try await storage.custody.registerPublishedIdentity(record)
            } catch {
                return publish(.unavailable(.keyUnavailable))
            }
            guard routeHostIDs == [record.hostID] else {
                self.storage = storage
                return publish(
                    .pairedRouteConfigurationRequired(
                        hostID: record.hostID
                    )
                )
            }
            do {
                guard try await storage.routes.snapshot(
                    hostID: record.hostID
                ) != nil else {
                    return publish(
                        .unavailable(.routeConfigurationMissing)
                    )
                }
            } catch {
                return publish(.unavailable(.storageUnavailable))
            }
            self.storage = storage
            return publish(.paired(hostID: record.hostID))
        }

        guard routeHostIDs.isEmpty else {
            return publish(.unavailable(.ambiguousSavedState))
        }

        self.storage = storage
        return publish(.unpaired)
    }

    package func preparedStorageForReleaseComposition()
        -> IOSClientReleaseStorageV1?
    {
        switch snapshotValue.phase {
        case .unpaired, .pairedRouteConfigurationRequired, .paired:
            storage
        case .idle, .preparing, .unavailable, .closed:
            nil
        }
    }

    public func finish() {
        guard snapshotValue.phase != .closed else { return }
        storage = nil
        startInProgress = false
        publish(.closed)
    }

    @discardableResult
    private func publish(
        _ phase: IOSClientReleaseBootstrapPhaseV1
    ) -> IOSClientReleaseBootstrapSnapshotV1 {
        let next = snapshotValue.revision + 1
        snapshotValue = IOSClientReleaseBootstrapSnapshotV1(
            revision: next,
            phase: phase
        )
        return snapshotValue
    }
}

package enum IOSClientReleaseStorageErrorV1:
    Error, Equatable, Sendable
{
    case invalidBaseDirectory
    case unsafeStorage
    case invalidInstallationIdentity
    case ioFailure
}

private struct IOSClientReleaseFileManagerV1: @unchecked Sendable {
    let value: FileManager

    init(_ value: FileManager) throws {
        guard value.delegate == nil else {
            throw IOSClientReleaseStorageErrorV1.unsafeStorage
        }
        self.value = value
    }
}

package struct IOSClientReleaseStorageV1: Sendable {
    package static let applicationSupportComponents = [
        "media.jenny.maccompanion", "iOS", "v1",
    ]
    package static let applicationTagPrefix =
        "media.jenny.maccompanion.ios.identity.v1"

    package let clientID: UUID
    package let pairedHosts: AtomicFileClientPairedHostStoreV0
    package let routes: AtomicFileClientConfiguredRouteStoreV1
    package let custody: SecurityClientIdentityKeyCustodyV0

    private let routeDirectory: URL
    private let fileManager: IOSClientReleaseFileManagerV1

    package static func systemDefault() throws
        -> IOSClientReleaseStorageV1
    {
        let base: URL
        do {
            base = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            throw IOSClientReleaseStorageErrorV1.invalidBaseDirectory
        }
        return try IOSClientReleaseStorageV1(
            baseApplicationSupportDirectory: base
        )
    }

    package init(
        baseApplicationSupportDirectory base: URL,
        fileManager: FileManager = .default
    ) throws {
        let root = try Self.prepareRoot(
            beneath: base,
            fileManager: fileManager
        )
        let identities = root.appendingPathComponent(
            "paired-hosts-v1",
            isDirectory: true
        )
        let routes = root.appendingPathComponent(
            "configured-routes-v1",
            isDirectory: true
        )
        try Self.prepareDirectory(identities, fileManager: fileManager)
        try Self.prepareDirectory(routes, fileManager: fileManager)
        routeDirectory = routes
        self.fileManager = try IOSClientReleaseFileManagerV1(fileManager)

        let installation = root.appendingPathComponent(
            "installation-v1.json",
            isDirectory: false
        )
        clientID = try Self.loadOrCreateClientID(
            at: installation,
            fileManager: fileManager
        )
        pairedHosts = try AtomicFileClientPairedHostStoreV0(
            directory: identities
        )
        self.routes = try AtomicFileClientConfiguredRouteStoreV1(
            directory: routes
        )
        custody = SecurityClientIdentityKeyCustodyV0(
            configuration: try SecurityClientKeyCustodyConfigurationV0(
                applicationTagPrefix: Self.applicationTagPrefix,
                prompts: SecurityClientPresencePromptsV0(
                    pairNewMac: "Confirm pairing this iPhone or iPad with your Mac.",
                    approveOperation: "Approve this bounded action on your Mac.",
                    startInteractiveControl: "Approve starting Remote Control for your Mac.",
                    expandGrant: "Approve the additional Mac capability shown."
                )
            )
        )
        try Self.protectTree(root, fileManager: fileManager)
    }

    package func storedRouteHostIDs() throws -> Set<UUID> {
        let entries: [URL]
        do {
            entries = try fileManager.value.contentsOfDirectory(
                at: routeDirectory,
                includingPropertiesForKeys: [
                    .isRegularFileKey, .isSymbolicLinkKey,
                ],
                options: []
            )
        } catch {
            throw IOSClientReleaseStorageErrorV1.ioFailure
        }
        var result: Set<UUID> = []
        for entry in entries {
            let values = try entry.resourceValues(forKeys: [
                .isRegularFileKey, .isSymbolicLinkKey,
            ])
            guard values.isRegularFile == true,
                  values.isSymbolicLink != true else {
                throw IOSClientReleaseStorageErrorV1.unsafeStorage
            }
            if entry.lastPathComponent == ".lock" { continue }
            guard !entry.lastPathComponent.hasPrefix("."),
                  entry.pathExtension == "json" else {
                throw IOSClientReleaseStorageErrorV1.unsafeStorage
            }
            let stem = entry.deletingPathExtension().lastPathComponent
            guard stem == stem.lowercased(),
                  let hostID = UUID(uuidString: stem),
                  hostID.uuidString.lowercased() == stem,
                  result.insert(hostID).inserted else {
                throw IOSClientReleaseStorageErrorV1.unsafeStorage
            }
        }
        guard result.count <= AtomicFileClientConfiguredRouteStoreV1
            .maximumHostCount else {
            throw IOSClientReleaseStorageErrorV1.unsafeStorage
        }
        return result
    }

    private static func prepareRoot(
        beneath base: URL,
        fileManager: FileManager
    ) throws -> URL {
        guard base.isFileURL else {
            throw IOSClientReleaseStorageErrorV1.invalidBaseDirectory
        }
        var current = base.standardizedFileURL
        try validateDirectory(current, fileManager: fileManager)
        for component in applicationSupportComponents {
            current.appendPathComponent(component, isDirectory: true)
            try prepareDirectory(current, fileManager: fileManager)
        }
        return current
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
                throw IOSClientReleaseStorageErrorV1.unsafeStorage
            }
        } else {
            do {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: false,
                    attributes: [
                        .posixPermissions: 0o700,
                        .protectionKey:
                            FileProtectionType
                                .completeUntilFirstUserAuthentication,
                    ]
                )
            } catch {
                throw IOSClientReleaseStorageErrorV1.ioFailure
            }
        }
        try applyProtection(to: directory, fileManager: fileManager)
    }

    private static func validateDirectory(
        _ directory: URL,
        fileManager: FileManager
    ) throws {
        let values: URLResourceValues
        do {
            values = try directory.resourceValues(forKeys: [
                .isDirectoryKey, .isSymbolicLinkKey,
            ])
        } catch {
            throw IOSClientReleaseStorageErrorV1.invalidBaseDirectory
        }
        guard values.isDirectory == true,
              values.isSymbolicLink != true else {
            throw IOSClientReleaseStorageErrorV1.invalidBaseDirectory
        }
    }

    private static func loadOrCreateClientID(
        at url: URL,
        fileManager: FileManager
    ) throws -> UUID {
        if fileManager.fileExists(atPath: url.path) {
            return try decodeClientID(Data(contentsOf: url))
        }
        let clientID = UUID()
        let data = encodeClientID(clientID)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(
            ".pending-installation-\(UUID().uuidString.lowercased())",
            isDirectory: false
        )
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
            try applyProtection(to: temporary, fileManager: fileManager)
            try synchronizeFile(temporary)
            guard renamex_np(
                temporary.path,
                url.path,
                UInt32(RENAME_EXCL)
            ) == 0 else {
                if errno == EEXIST,
                   fileManager.fileExists(atPath: url.path) {
                    try? fileManager.removeItem(at: temporary)
                    return try decodeClientID(Data(contentsOf: url))
                }
                throw IOSClientReleaseStorageErrorV1.ioFailure
            }
            try synchronizeDirectory(url.deletingLastPathComponent())
            return clientID
        } catch let error as IOSClientReleaseStorageErrorV1 {
            try? fileManager.removeItem(at: temporary)
            throw error
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw IOSClientReleaseStorageErrorV1.ioFailure
        }
    }

    private static func encodeClientID(_ clientID: UUID) -> Data {
        Data(
            #"{"clientID":"\#(clientID.uuidString.lowercased())","schemaVersion":1}"#.utf8
        )
    }

    private static func decodeClientID(_ data: Data) throws -> UUID {
        guard data.count <= 128,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              Set(dictionary.keys) == ["clientID", "schemaVersion"],
              dictionary["schemaVersion"] as? Int == 1,
              let string = dictionary["clientID"] as? String,
              string == string.lowercased(),
              let clientID = UUID(uuidString: string),
              clientID.uuidString.lowercased() == string,
              encodeClientID(clientID) == data,
              clientID != UUID(
                uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
              ) else {
            throw IOSClientReleaseStorageErrorV1
                .invalidInstallationIdentity
        }
        return clientID
    }

    private static func protectTree(
        _ root: URL,
        fileManager: FileManager
    ) throws {
        let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
            ],
            options: []
        )
        guard let enumerator else {
            throw IOSClientReleaseStorageErrorV1.ioFailure
        }
        try applyProtection(to: root, fileManager: fileManager)
        for case let entry as URL in enumerator {
            let values = try entry.resourceValues(forKeys: [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
            ])
            guard values.isSymbolicLink != true,
                  values.isDirectory == true
                    || values.isRegularFile == true else {
                throw IOSClientReleaseStorageErrorV1.unsafeStorage
            }
            try applyProtection(to: entry, fileManager: fileManager)
        }
    }

    private static func applyProtection(
        to url: URL,
        fileManager: FileManager
    ) throws {
        do {
            let resourceValues = try url.resourceValues(forKeys: [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
            ])
            guard resourceValues.isSymbolicLink != true,
                  resourceValues.isDirectory == true
                    || resourceValues.isRegularFile == true else {
                throw IOSClientReleaseStorageErrorV1.unsafeStorage
            }
            let permissions: NSNumber = resourceValues.isDirectory == true
                ? 0o700
                : 0o600
            try fileManager.setAttributes(
                [
                    .posixPermissions: permissions,
                    .protectionKey:
                        FileProtectionType
                            .completeUntilFirstUserAuthentication,
                ],
                ofItemAtPath: url.path
            )
            var mutable = url
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try mutable.setResourceValues(values)
            let attributes = try fileManager.attributesOfItem(
                atPath: url.path
            )
            guard attributes[.protectionKey] as? FileProtectionType
                    == .completeUntilFirstUserAuthentication,
                  try mutable.resourceValues(
                    forKeys: [.isExcludedFromBackupKey]
                  ).isExcludedFromBackup == true else {
                throw IOSClientReleaseStorageErrorV1.unsafeStorage
            }
        } catch let error as IOSClientReleaseStorageErrorV1 {
            throw error
        } catch {
            throw IOSClientReleaseStorageErrorV1.ioFailure
        }
    }

    private static func synchronizeFile(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw IOSClientReleaseStorageErrorV1.ioFailure
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw IOSClientReleaseStorageErrorV1.ioFailure
        }
    }

    private static func synchronizeDirectory(_ url: URL) throws {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_DIRECTORY)
        guard descriptor >= 0 else {
            throw IOSClientReleaseStorageErrorV1.ioFailure
        }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else {
            throw IOSClientReleaseStorageErrorV1.ioFailure
        }
    }
}
#endif
