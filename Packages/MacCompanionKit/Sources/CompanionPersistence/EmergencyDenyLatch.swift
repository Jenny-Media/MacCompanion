#if os(macOS)
import CompanionDomain
import CryptoKit
import Darwin
import Foundation

public enum EmergencyDenyReason: UInt32, Equatable, Sendable {
    case revocationInProgress = 1
    case securityStoreUnavailable = 2
    case integrityFailure = 3
}

public enum EmergencyDenyLatchHealth: Equatable, Sendable {
    case clear
    case active
    case corrupt
}

public struct EmergencyDenyLatchSnapshot: Equatable, Sendable {
    public let health: EmergencyDenyLatchHealth
    public let generation: UInt64?
    public let pendingDeviceID: UUID?
    public let recordedAtUnixMilliseconds: Int64?
    public let reason: EmergencyDenyReason?
}

public enum EmergencyDenyLatchError: Error, Equatable, Sendable {
    case posix(operation: String, code: Int32)
    case invalidPermissions
    case corruptRequiresLocalRepair
    case generationExhausted
    case verificationFailed
    case invalidRecord
}

private final class EmergencyDenyLatchFileHandle: @unchecked Sendable {
    let descriptor: Int32

    init(_ descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        close(descriptor)
    }
}

public actor EmergencyDenyLatch {
    public static let fileSize = 4_096
    public static let slotSize = 2_048

    private let path: String
    private let file: EmergencyDenyLatchFileHandle

    public init(url: URL) throws {
        path = url.path
        try Self.createIfNeeded(path: path)
        let descriptor = try Self.openExisting(path: path)
        file = EmergencyDenyLatchFileHandle(descriptor)
        try Self.validateStorageBinding(
            path: path,
            descriptor: descriptor
        )
    }

    public func snapshot() throws -> EmergencyDenyLatchSnapshot {
        try withFileLock(LOCK_SH) { descriptor in
            try Self.readSnapshot(descriptor: descriptor)
        }
    }

    /// Proves that the retained descriptor and visible release path still
    /// designate the same private latch inode.
    public nonisolated func validateStorageBinding() throws {
        try Self.validateStorageBinding(
            path: path,
            descriptor: file.descriptor
        )
    }

    @discardableResult
    public func activate(
        pendingDeviceID: UUID?,
        reason: EmergencyDenyReason,
        recordedAtUnixMilliseconds: Int64
    ) throws -> EmergencyDenyLatchSnapshot {
        try update(
            active: true,
            pendingDeviceID: pendingDeviceID,
            reason: reason,
            recordedAtUnixMilliseconds: recordedAtUnixMilliseconds
        )
    }

    @discardableResult
    public func clear(
        recordedAtUnixMilliseconds: Int64
    ) throws -> EmergencyDenyLatchSnapshot {
        try update(
            active: false,
            pendingDeviceID: nil,
            reason: nil,
            recordedAtUnixMilliseconds: recordedAtUnixMilliseconds
        )
    }

    private func update(
        active: Bool,
        pendingDeviceID: UUID?,
        reason: EmergencyDenyReason?,
        recordedAtUnixMilliseconds: Int64
    ) throws -> EmergencyDenyLatchSnapshot {
        guard recordedAtUnixMilliseconds >= 0,
              recordedAtUnixMilliseconds <= Int64(MonotonicRevision<AuthorizationEpochTag>.maximumWireValue),
              active == (reason != nil),
              !(!active && pendingDeviceID != nil),
              reason != .revocationInProgress || pendingDeviceID != nil else {
            throw EmergencyDenyLatchError.invalidRecord
        }

        return try withFileLock(LOCK_EX) { descriptor in
            let records = try Self.readRecords(descriptor: descriptor)
            guard records.allSatisfy(\.isValid),
                  let current = Self.authoritativeRecord(records) else {
                throw EmergencyDenyLatchError.corruptRequiresLocalRepair
            }
            guard current.generation < UInt64.max else {
                throw EmergencyDenyLatchError.generationExhausted
            }

            let targetIndex: Int
            if records[0].generation == records[1].generation {
                targetIndex = 0
            } else {
                targetIndex = records[0].generation < records[1].generation ? 0 : 1
            }
            let next = SlotRecord(
                isValid: true,
                active: active,
                generation: current.generation + 1,
                pendingDeviceID: pendingDeviceID,
                recordedAtUnixMilliseconds: recordedAtUnixMilliseconds,
                reason: reason
            )

            try Self.writeAll(
                next.encoded(),
                descriptor: descriptor,
                offset: off_t(targetIndex * Self.slotSize)
            )
            guard fsync(descriptor) == 0 else {
                throw EmergencyDenyLatchError.posix(operation: "fsync latch", code: errno)
            }

            let verified = try Self.readSnapshot(descriptor: descriptor)
            guard verified.health == (active ? .active : .clear),
                  verified.generation == next.generation,
                  verified.pendingDeviceID == pendingDeviceID,
                  verified.reason == reason else {
                throw EmergencyDenyLatchError.verificationFailed
            }
            return verified
        }
    }

    private nonisolated func withFileLock<Result>(
        _ operation: Int32,
        body: (Int32) throws -> Result
    ) throws -> Result {
        let descriptor = file.descriptor
        guard flock(descriptor, operation) == 0 else {
            throw EmergencyDenyLatchError.posix(
                operation: "lock latch",
                code: errno
            )
        }
        defer { _ = flock(descriptor, LOCK_UN) }

        try Self.validateStorageBinding(
            path: path,
            descriptor: descriptor
        )
        let result = try body(descriptor)
        try Self.validateStorageBinding(
            path: path,
            descriptor: descriptor
        )
        return result
    }

    private static func createIfNeeded(path: String) throws {
        let descriptor = open(path, O_RDWR | O_CREAT | O_EXCL | O_CLOEXEC, S_IRUSR | S_IWUSR)
        if descriptor < 0 {
            if errno == EEXIST {
                let existing = try openExisting(path: path)
                close(existing)
                return
            }
            throw EmergencyDenyLatchError.posix(operation: "create latch", code: errno)
        }
        defer { close(descriptor) }

        var allocation = fstore_t(
            fst_flags: UInt32(F_ALLOCATECONTIG),
            fst_posmode: Int32(F_PEOFPOSMODE),
            fst_offset: 0,
            fst_length: off_t(fileSize),
            fst_bytesalloc: 0
        )
        if fcntl(descriptor, F_PREALLOCATE, &allocation) == -1 {
            allocation.fst_flags = UInt32(F_ALLOCATEALL)
            guard fcntl(descriptor, F_PREALLOCATE, &allocation) != -1 else {
                throw EmergencyDenyLatchError.posix(operation: "preallocate latch", code: errno)
            }
        }
        guard ftruncate(descriptor, off_t(fileSize)) == 0 else {
            throw EmergencyDenyLatchError.posix(operation: "size latch", code: errno)
        }

        let initial = SlotRecord(
            isValid: true,
            active: false,
            generation: 0,
            pendingDeviceID: nil,
            recordedAtUnixMilliseconds: 0,
            reason: nil
        ).encoded()
        try writeAll(initial, descriptor: descriptor, offset: 0)
        try writeAll(initial, descriptor: descriptor, offset: off_t(slotSize))
        guard fsync(descriptor) == 0 else {
            throw EmergencyDenyLatchError.posix(operation: "fsync new latch", code: errno)
        }

        let parentPath = URL(fileURLWithPath: path).deletingLastPathComponent().path
        let parent = open(parentPath, O_RDONLY | O_CLOEXEC)
        guard parent >= 0 else {
            throw EmergencyDenyLatchError.posix(operation: "open latch directory", code: errno)
        }
        defer { close(parent) }
        guard fsync(parent) == 0 else {
            throw EmergencyDenyLatchError.posix(operation: "fsync latch directory", code: errno)
        }
    }

    private static func openExisting(path: String) throws -> Int32 {
        let descriptor = open(path, O_RDWR | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw EmergencyDenyLatchError.posix(operation: "open latch", code: errno)
        }
        var status = stat()
        guard fstat(descriptor, &status) == 0 else {
            let code = errno
            close(descriptor)
            throw EmergencyDenyLatchError.posix(operation: "stat latch", code: code)
        }
        guard (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              status.st_uid == geteuid(),
              status.st_nlink == 1,
              (status.st_mode & 0o777) == 0o600,
              status.st_size == off_t(fileSize) else {
            close(descriptor)
            throw EmergencyDenyLatchError.invalidPermissions
        }
        return descriptor
    }

    private static func validateStorageBinding(
        path: String,
        descriptor: Int32
    ) throws {
        var descriptorStatus = stat()
        guard fstat(descriptor, &descriptorStatus) == 0 else {
            throw EmergencyDenyLatchError.posix(
                operation: "stat retained latch",
                code: errno
            )
        }
        var pathStatus = stat()
        guard lstat(path, &pathStatus) == 0 else {
            throw EmergencyDenyLatchError.verificationFailed
        }
        for status in [descriptorStatus, pathStatus] {
            guard (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
                  status.st_uid == geteuid(),
                  status.st_nlink == 1,
                  (status.st_mode & 0o777) == 0o600,
                  status.st_size == off_t(fileSize) else {
                throw EmergencyDenyLatchError.invalidPermissions
            }
        }
        guard descriptorStatus.st_dev == pathStatus.st_dev,
              descriptorStatus.st_ino == pathStatus.st_ino else {
            throw EmergencyDenyLatchError.verificationFailed
        }
    }

    private static func readSnapshot(
        descriptor: Int32
    ) throws -> EmergencyDenyLatchSnapshot {
        let records = try readRecords(descriptor: descriptor)
        guard records.allSatisfy(\.isValid),
              let record = authoritativeRecord(records) else {
            return EmergencyDenyLatchSnapshot(
                health: .corrupt,
                generation: nil,
                pendingDeviceID: nil,
                recordedAtUnixMilliseconds: nil,
                reason: nil
            )
        }
        return EmergencyDenyLatchSnapshot(
            health: record.active ? .active : .clear,
            generation: record.generation,
            pendingDeviceID: record.pendingDeviceID,
            recordedAtUnixMilliseconds: record.recordedAtUnixMilliseconds,
            reason: record.reason
        )
    }

    private static func readRecords(descriptor: Int32) throws -> [SlotRecord] {
        let bytes = try readAll(descriptor: descriptor)
        return [
            SlotRecord(decoding: Data(bytes[0..<slotSize])),
            SlotRecord(decoding: Data(bytes[slotSize..<fileSize])),
        ]
    }

    private static func authoritativeRecord(_ records: [SlotRecord]) -> SlotRecord? {
        guard records.count == 2 else { return nil }
        if records[0].generation == records[1].generation {
            return records[0] == records[1] ? records[0] : nil
        }
        return records[0].generation > records[1].generation ? records[0] : records[1]
    }

    private static func readAll(descriptor: Int32) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: fileSize)
        var total = 0
        while total < fileSize {
            let count = bytes.withUnsafeMutableBytes { buffer in
                pread(
                    descriptor,
                    buffer.baseAddress!.advanced(by: total),
                    fileSize - total,
                    off_t(total)
                )
            }
            guard count > 0 else {
                throw EmergencyDenyLatchError.posix(
                    operation: "read latch",
                    code: count == 0 ? EIO : errno
                )
            }
            total += count
        }
        return bytes
    }

    private static func writeAll(
        _ data: Data,
        descriptor: Int32,
        offset: off_t
    ) throws {
        var total = 0
        try data.withUnsafeBytes { buffer in
            while total < data.count {
                let count = pwrite(
                    descriptor,
                    buffer.baseAddress!.advanced(by: total),
                    data.count - total,
                    offset + off_t(total)
                )
                guard count > 0 else {
                    throw EmergencyDenyLatchError.posix(
                        operation: "write latch",
                        code: count == 0 ? EIO : errno
                    )
                }
                total += count
            }
        }
    }
}

private struct SlotRecord: Equatable {
    static let magic = Array("MCDENY01".utf8)
    static let digestDomain = Data("MacCompanion/EmergencyDenyLatch/v1".utf8)

    let isValid: Bool
    let active: Bool
    let generation: UInt64
    let pendingDeviceID: UUID?
    let recordedAtUnixMilliseconds: Int64
    let reason: EmergencyDenyReason?

    init(
        isValid: Bool,
        active: Bool,
        generation: UInt64,
        pendingDeviceID: UUID?,
        recordedAtUnixMilliseconds: Int64,
        reason: EmergencyDenyReason?
    ) {
        self.isValid = isValid
        self.active = active
        self.generation = generation
        self.pendingDeviceID = pendingDeviceID
        self.recordedAtUnixMilliseconds = recordedAtUnixMilliseconds
        self.reason = reason
    }

    init(decoding data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count == EmergencyDenyLatch.slotSize,
              Array(bytes[0..<8]) == Self.magic,
              readUInt16(bytes, at: 8) == 1,
              bytes[11] == 0,
              bytes[10] == 0 || bytes[10] == 1,
              bytes[80...].allSatisfy({ $0 == 0 }) else {
            self.init(invalid: ())
            return
        }

        let expectedDigest = Data(bytes[48..<80])
        let actualDigest = Data(SHA256.hash(data: Self.digestDomain + Data(bytes[0..<48])))
        guard expectedDigest == actualDigest else {
            self.init(invalid: ())
            return
        }

        let active = bytes[10] == 1
        let generation = readUInt64(bytes, at: 12)
        let uuidBytes = Array(bytes[20..<36])
        let deviceID = uuidBytes.allSatisfy({ $0 == 0 }) ? nil : uuid(from: uuidBytes)
        let recordedAt = readUInt64(bytes, at: 36)
        let reasonRaw = readUInt32(bytes, at: 44)
        let reason = EmergencyDenyReason(rawValue: reasonRaw)
        let maximum = MonotonicRevision<AuthorizationEpochTag>.maximumWireValue

        guard recordedAt <= maximum,
              (active && reason != nil) || (!active && reasonRaw == 0),
              active || deviceID == nil,
              reason != .revocationInProgress || deviceID != nil else {
            self.init(invalid: ())
            return
        }
        self.init(
            isValid: true,
            active: active,
            generation: generation,
            pendingDeviceID: deviceID,
            recordedAtUnixMilliseconds: Int64(recordedAt),
            reason: reason
        )
    }

    private init(invalid: Void) {
        self.init(
            isValid: false,
            active: true,
            generation: 0,
            pendingDeviceID: nil,
            recordedAtUnixMilliseconds: 0,
            reason: .integrityFailure
        )
    }

    func encoded() -> Data {
        var bytes = [UInt8](repeating: 0, count: EmergencyDenyLatch.slotSize)
        bytes.replaceSubrange(0..<8, with: Self.magic)
        writeUInt16(1, into: &bytes, at: 8)
        bytes[10] = active ? 1 : 0
        writeUInt64(generation, into: &bytes, at: 12)
        if let pendingDeviceID {
            bytes.replaceSubrange(20..<36, with: uuidBytes(pendingDeviceID))
        }
        writeUInt64(UInt64(recordedAtUnixMilliseconds), into: &bytes, at: 36)
        writeUInt32(reason?.rawValue ?? 0, into: &bytes, at: 44)
        let digest = SHA256.hash(data: Self.digestDomain + Data(bytes[0..<48]))
        bytes.replaceSubrange(48..<80, with: Array(digest))
        return Data(bytes)
    }
}

private func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
    (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
}

private func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
    (0..<4).reduce(0) { ($0 << 8) | UInt32(bytes[offset + $1]) }
}

private func readUInt64(_ bytes: [UInt8], at offset: Int) -> UInt64 {
    (0..<8).reduce(0) { ($0 << 8) | UInt64(bytes[offset + $1]) }
}

private func writeUInt16(_ value: UInt16, into bytes: inout [UInt8], at offset: Int) {
    bytes[offset] = UInt8(value >> 8)
    bytes[offset + 1] = UInt8(value & 0xff)
}

private func writeUInt32(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
    for index in 0..<4 {
        bytes[offset + index] = UInt8((value >> UInt32((3 - index) * 8)) & 0xff)
    }
}

private func writeUInt64(_ value: UInt64, into bytes: inout [UInt8], at offset: Int) {
    for index in 0..<8 {
        bytes[offset + index] = UInt8((value >> UInt64((7 - index) * 8)) & 0xff)
    }
}

private func uuidBytes(_ value: UUID) -> [UInt8] {
    let tuple = value.uuid
    return [
        tuple.0, tuple.1, tuple.2, tuple.3,
        tuple.4, tuple.5, tuple.6, tuple.7,
        tuple.8, tuple.9, tuple.10, tuple.11,
        tuple.12, tuple.13, tuple.14, tuple.15,
    ]
}

private func uuid(from bytes: [UInt8]) -> UUID? {
    guard bytes.count == 16 else { return nil }
    return UUID(uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3],
        bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11],
        bytes[12], bytes[13], bytes[14], bytes[15]
    ))
}
#endif
