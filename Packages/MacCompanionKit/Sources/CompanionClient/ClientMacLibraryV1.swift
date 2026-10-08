import Darwin
import Foundation

public struct ClientSavedMacV1: Identifiable, Equatable, Sendable {
    public var id: UUID { hostID }
    public let hostID: UUID
    public let name: String
    public let needsRouteSetup: Bool

    public init(hostID: UUID, name: String, needsRouteSetup: Bool) {
        self.hostID = hostID
        self.name = name
        self.needsRouteSetup = needsRouteSetup
    }
}

/// Local presentation and interrupted-removal metadata, never connection
/// authority. A pending removal fences a host before any key is deleted.
public struct ClientMacLibraryPreferencesV1: Codable, Equatable, Sendable {
    public private(set) var names: [UUID: String] = [:]
    public private(set) var pendingRemovals: Set<UUID> = []

    public init() {}

    public mutating func rename(hostID: UUID, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(trimmed.count),
              !trimmed.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ClientMacLibraryErrorV1.invalidName
        }
        names[hostID] = trimmed
    }

    public mutating func beginRemoval(hostID: UUID) { pendingRemovals.insert(hostID) }
    public mutating func finishRemoval(hostID: UUID) {
        pendingRemovals.remove(hostID)
        names.removeValue(forKey: hostID)
    }

    public func visibleRecords(_ records: [ClientDurablePairedHostV0], clientID: UUID) throws
        -> [ClientDurablePairedHostV0] {
        var hosts: Set<UUID> = [], devices: Set<UUID> = [], pairings: Set<UUID> = []
        var keys: Set<ClientSigningKeyReferenceV0> = []
        for record in records {
            guard record.clientID == clientID, hosts.insert(record.hostID).inserted,
                  devices.insert(record.deviceID).inserted, pairings.insert(record.pairingID).inserted,
                  keys.insert(record.sessionKey.reference).inserted,
                  keys.insert(record.approvalKey.reference).inserted else {
                throw ClientMacLibraryErrorV1.conflictingInventory
            }
        }
        return records.filter { !pendingRemovals.contains($0.hostID) }
    }

    public func library(records: [ClientDurablePairedHostV0], clientID: UUID,
                        configuredHostIDs: Set<UUID>) throws -> [ClientSavedMacV1] {
        try visibleRecords(records, clientID: clientID).enumerated().map { index, record in
            ClientSavedMacV1(hostID: record.hostID, name: names[record.hostID] ?? "Mac \(index + 1)",
                needsRouteSetup: !configuredHostIDs.contains(record.hostID))
        }.sorted {
            let comparison = $0.name.localizedStandardCompare($1.name)
            return comparison == .orderedSame ? $0.hostID.uuidString < $1.hostID.uuidString
                : comparison == .orderedAscending
        }
    }

    fileprivate func validate() throws {
        guard names.count <= 64, pendingRemovals.count <= 64 else {
            throw ClientMacLibraryErrorV1.unsafeStorage
        }
        var copy = ClientMacLibraryPreferencesV1()
        for (hostID, name) in names {
            try copy.rename(hostID: hostID, name: name)
            guard copy.names[hostID] == name else { throw ClientMacLibraryErrorV1.unsafeStorage }
        }
    }
}

public enum ClientMacLibraryErrorV1: Error, Equatable, Sendable {
    case invalidName, conflictingInventory, unsafeStorage, ioFailure
}

public actor AtomicFileClientMacLibraryStoreV1 {
    private struct Stored: Codable {
        let schemaVersion: Int
        let names: [String: String]
        let pendingRemovals: [String]
    }
    private let directory: URL
    private var url: URL { directory.appendingPathComponent("library.json") }

    public init(directory: URL) throws {
        guard directory.isFileURL else { throw ClientMacLibraryErrorV1.unsafeStorage }
        self.directory = directory
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw ClientMacLibraryErrorV1.unsafeStorage
        }
    }

    public func snapshot() throws -> ClientMacLibraryPreferencesV1 {
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, (1...32_768).contains(size) else {
            throw ClientMacLibraryErrorV1.unsafeStorage
        }
        let data = try Data(contentsOf: url)
        let stored = try JSONDecoder().decode(Stored.self, from: data)
        guard stored.schemaVersion == 1 else { throw ClientMacLibraryErrorV1.unsafeStorage }
        var value = ClientMacLibraryPreferencesV1()
        for (key, name) in stored.names {
            guard let id = UUID(uuidString: key), id.uuidString.lowercased() == key else {
                throw ClientMacLibraryErrorV1.unsafeStorage
            }
            try value.rename(hostID: id, name: name)
        }
        for key in stored.pendingRemovals {
            guard let id = UUID(uuidString: key), id.uuidString.lowercased() == key,
                  !value.pendingRemovals.contains(id) else { throw ClientMacLibraryErrorV1.unsafeStorage }
            value.beginRemoval(hostID: id)
        }
        try value.validate()
        guard try encode(value) == data else { throw ClientMacLibraryErrorV1.unsafeStorage }
        return value
    }

    public func replace(_ value: ClientMacLibraryPreferencesV1) throws {
        try value.validate()
        // Validate the current file before replacing it, including symlinks.
        _ = try snapshot()
        let data = try encode(value)
        guard data.count <= 32_768 else { throw ClientMacLibraryErrorV1.unsafeStorage }
        let temporary = directory.appendingPathComponent(".pending-\(UUID().uuidString.lowercased())")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: temporary.path)
        #endif
        try synchronize(temporary, directory: false)
        guard rename(temporary.path, url.path) == 0 else { throw ClientMacLibraryErrorV1.ioFailure }
        try synchronize(directory, directory: true)
    }

    private func encode(_ value: ClientMacLibraryPreferencesV1) throws -> Data {
        let stored = Stored(schemaVersion: 1,
            names: Dictionary(uniqueKeysWithValues: value.names.map { ($0.key.uuidString.lowercased(), $0.value) }),
            pendingRemovals: value.pendingRemovals.map { $0.uuidString.lowercased() }.sorted())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(stored)
    }

    private func synchronize(_ path: URL, directory: Bool) throws {
        let descriptor = open(path.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | (directory ? O_DIRECTORY : 0))
        guard descriptor >= 0 else { throw ClientMacLibraryErrorV1.ioFailure }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw ClientMacLibraryErrorV1.ioFailure }
    }
}
