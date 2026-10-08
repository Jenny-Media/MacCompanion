#if os(macOS)
import Darwin
import Foundation
import CompanionWire

/// Exact private child exchange. This value has no grant, pairing, listener or
/// input authority; the backend supplies its original process/Control checks.
@MainActor
package final class MacManagedCaptureHandoffV1 {
    package enum Failure: String, Error { case invalidDirectory, unavailable, invalidRecord, timedOut }
    private let transport: UUID
    private let expiry: UInt64
    private let current: @MainActor () -> Bool
    private let clock: @MainActor () -> UInt64
    // Deterministic filesystem interleaving in package tests; normal callers
    // use the inert default and cannot change any receipt validation.
    private let receiptReadCheckpoint: @MainActor () throws -> Void
    private var directory: Int32 = -1
    private var sequence: UInt64 = 0
    private var pending = false
    private var closed = false
    private var lastReceipt: Data?

    package init(directory path: URL, transport: UUID, expiryNanoseconds: UInt64,
                 current: @escaping @MainActor () -> Bool,
                 clock: @escaping @MainActor () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
                 receiptReadCheckpoint: @escaping @MainActor () throws -> Void = {}) throws {
        let now = clock()
        guard path.isFileURL, path.path.hasPrefix("/"), path.path.utf8.count < Int(PATH_MAX),
              expiryNanoseconds > now, expiryNanoseconds - now <= 14_400_000_000_000 else {
            throw Failure.invalidDirectory
        }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        for part in path.path.split(separator: "/", omittingEmptySubsequences: false).dropFirst() {
            guard !part.isEmpty, part != ".", part != "..", fd >= 0 else {
                if fd >= 0 { Darwin.close(fd) }; throw Failure.invalidDirectory
            }
            let next = openat(fd, String(part), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            Darwin.close(fd); fd = next
        }
        var facts = stat()
        guard fd >= 0, fstat(fd, &facts) == 0, facts.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR),
              facts.st_uid == geteuid(), facts.st_mode & 0o777 == 0o700 else {
            if fd >= 0 { Darwin.close(fd) }; throw Failure.invalidDirectory
        }
        directory = fd; self.transport = transport; expiry = expiryNanoseconds
        self.current = current; self.clock = clock
        self.receiptReadCheckpoint = receiptReadCheckpoint
    }
    deinit { if directory >= 0 { Darwin.close(directory) } }
    package func close() { closed = true; if directory >= 0 { Darwin.close(directory); directory = -1 } }

    package func pause(operationID: UUID) async throws {
        try await send(operationID: operationID, action: "pause", previous: nil, context: nil)
    }
    package func select(operationID: UUID, previousOperationID: UUID, context: Data) async throws {
        guard operationID != previousOperationID else { throw Failure.invalidRecord }
        try await send(operationID: operationID, action: "select", previous: previousOperationID, context: context)
    }

    private func send(operationID: UUID, action: String, previous: UUID?, context: Data?) async throws {
        try check()
        guard !pending, sequence < 9_007_199_254_740_991 else { throw Failure.unavailable }
        pending = true; defer { pending = false }
        sequence += 1
        let candidate = sequence
        var record: [String: Any] = ["profile": "maccompanion.capture-handoff.v1",
            "transportOperationID": transport.uuidString, "operationID": operationID.uuidString,
            "sequence": candidate, "action": action, "expiresAtMonotonicNanoseconds": expiry]
        if let previous { record["previousOperationID"] = previous.uuidString }
        if let context {
            try StrictJSON.validate(context)
            let parsed = try CanonicalJSON.parse(context)
            guard CanonicalJSON.canonicalData(for: parsed) == context,
                  let object = try JSONSerialization.jsonObject(with: context) as? [String: Any],
                  object["profile"] as? String == "maccompanion.selected-capture-context.v0.2",
                  object["operationID"] as? String == operationID.uuidString,
                  (object["expiresAtMonotonicNanoseconds"] as? NSNumber)?.uint64Value == expiry else { throw Failure.invalidRecord }
            record["context"] = object
        }
        let bytes = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes])
        guard bytes.count <= 8192 else { throw Failure.invalidRecord }
        let temporary = "capture-command-" + UUID().uuidString
        let fd = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Failure.invalidRecord }
        let count = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        let closeResult = Darwin.close(fd)
        guard count == bytes.count, closeResult == 0 else { unlinkat(directory, temporary, 0); throw Failure.invalidRecord }
        guard renameat(directory, temporary, directory, "capture-handoff-command.json") == 0 else {
            unlinkat(directory, temporary, 0); throw Failure.invalidRecord
        }
        let now = clock(), until = min(expiry, now > UInt64.max - 2_000_000_000 ? UInt64.max : now + 2_000_000_000)
        while true {
            try check()
            guard clock() < until else { throw Failure.timedOut }
            if let reply = try readReceipt() {
                if reply != lastReceipt {
                    try StrictJSON.validate(reply)
                    let parsed = try CanonicalJSON.parse(reply)
                    guard CanonicalJSON.canonicalData(for: parsed) == reply,
                          let value = try JSONSerialization.jsonObject(with: reply) as? [String: Any],
                          Set(value.keys) == ["profile", "transportOperationID", "operationID", "sequence", "action", "result"],
                          value["profile"] as? String == "maccompanion.capture-handoff-receipt.v1",
                          value["transportOperationID"] as? String == transport.uuidString,
                          value["operationID"] as? String == operationID.uuidString,
                          value["action"] as? String == action,
                          let number = value["sequence"] as? NSNumber,
                          CFGetTypeID(number) != CFBooleanGetTypeID(), number.uint64Value == candidate,
                          number.doubleValue == Double(candidate),
                          value["result"] as? String == (action == "pause" ? "paused" : "selected") else { throw Failure.invalidRecord }
                    try check(); lastReceipt = reply; return
                }
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
    private func check() throws {
        guard !Task.isCancelled, !closed, directory >= 0, clock() < expiry, current() else { throw Failure.unavailable }
    }
    private func readReceipt() throws -> Data? {
        let fd = openat(directory, "capture-handoff-receipt.json", O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if fd < 0 { if errno == ENOENT { return nil }; throw Failure.invalidRecord }
        defer { Darwin.close(fd) }
        var facts = stat(), after = stat()
        guard fstat(fd, &facts) == 0, facts.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), facts.st_uid == geteuid(),
              facts.st_nlink <= 1, facts.st_mode & 0o777 == 0o600, (1...1024).contains(facts.st_size) else { throw Failure.invalidRecord }
        var data = Data(count: Int(facts.st_size))
        let count = data.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
        try receiptReadCheckpoint()
        guard count == data.count, fstat(fd, &after) == 0, after.st_size == facts.st_size, after.st_nlink <= 1,
              after.st_mode == facts.st_mode, after.st_uid == facts.st_uid,
              after.st_mtimespec.tv_sec == facts.st_mtimespec.tv_sec,
              after.st_mtimespec.tv_nsec == facts.st_mtimespec.tv_nsec else { throw Failure.invalidRecord }
        var named = stat()
        guard fstatat(directory, "capture-handoff-receipt.json", &named, AT_SYMLINK_NOFOLLOW) == 0,
              named.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), named.st_uid == geteuid(),
              named.st_nlink == 1, named.st_mode & 0o777 == 0o600,
              (1...1024).contains(named.st_size) else { throw Failure.invalidRecord }
        // Rename unlinks the old inode while an open descriptor remains valid.
        // Discard every byte from that snapshot; only a fresh open can admit
        // the independently checked replacement under the unchanged deadline.
        if named.st_dev != facts.st_dev || named.st_ino != facts.st_ino { return nil }
        guard after.st_nlink == 1,
              after.st_ctimespec.tv_sec == facts.st_ctimespec.tv_sec,
              after.st_ctimespec.tv_nsec == facts.st_ctimespec.tv_nsec else { throw Failure.invalidRecord }
        return data
    }
}
#endif
