#if os(macOS)
import CompanionPersistence
import Darwin
import Foundation
import Testing

@Test func latchIsPreallocatedPrivateAndInitiallyClear() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let url = temporary.directory.appendingPathComponent("emergency-deny.latch")
    let latch = try EmergencyDenyLatch(url: url)

    let snapshot = try await latch.snapshot()
    #expect(snapshot.health == .clear)
    #expect(snapshot.generation == 0)
    #expect(snapshot.pendingDeviceID == nil)

    var status = stat()
    #expect(lstat(url.path, &status) == 0)
    #expect(status.st_size == EmergencyDenyLatch.fileSize)
    #expect((status.st_mode & 0o077) == 0)
    #expect(status.st_blocks * 512 >= EmergencyDenyLatch.fileSize)
}

@Test func activationAndClearSurviveReopenWithMonotonicGeneration() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let url = temporary.directory.appendingPathComponent("emergency-deny.latch")
    let deviceID = UUID(uuidString: "018f2100-0000-7000-8000-000000000001")!
    let latch = try EmergencyDenyLatch(url: url)

    let active = try await latch.activate(
        pendingDeviceID: deviceID,
        reason: .revocationInProgress,
        recordedAtUnixMilliseconds: 1_000
    )
    #expect(active.health == .active)
    #expect(active.generation == 1)
    #expect(active.pendingDeviceID == deviceID)

    let reopened = try EmergencyDenyLatch(url: url)
    #expect(try await reopened.snapshot() == active)
    let clear = try await reopened.clear(recordedAtUnixMilliseconds: 2_000)
    #expect(clear.health == .clear)
    #expect(clear.generation == 2)
    #expect(clear.pendingDeviceID == nil)
    #expect(clear.reason == nil)
}

@Test func tornOrCorruptSlotFailsClosedEvenWhenOtherSlotIsClear() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let url = temporary.directory.appendingPathComponent("emergency-deny.latch")
    let latch = try EmergencyDenyLatch(url: url)
    _ = try await latch.activate(
        pendingDeviceID: UUID(uuidString: "018f2100-0000-7000-8000-000000000001")!,
        reason: .revocationInProgress,
        recordedAtUnixMilliseconds: 1_000
    )

    let handle = try FileHandle(forUpdating: url)
    try handle.seek(toOffset: 48)
    try handle.write(contentsOf: Data([0xff]))
    try handle.synchronize()
    try handle.close()

    let snapshot = try await latch.snapshot()
    #expect(snapshot.health == .corrupt)
    await #expect(throws: EmergencyDenyLatchError.corruptRequiresLocalRepair) {
        _ = try await latch.clear(recordedAtUnixMilliseconds: 2_000)
    }
}

@Test func insecurePermissionsAndSymlinksAreRefused() async throws {
    let permissions = try TemporaryDatabase()
    defer { permissions.remove() }
    let latchURL = permissions.directory.appendingPathComponent("emergency-deny.latch")
    _ = try EmergencyDenyLatch(url: latchURL)
    #expect(chmod(latchURL.path, 0o644) == 0)
    #expect(throws: EmergencyDenyLatchError.invalidPermissions) {
        _ = try EmergencyDenyLatch(url: latchURL)
    }

    let symlink = try TemporaryDatabase()
    defer { symlink.remove() }
    let target = symlink.directory.appendingPathComponent("target")
    try Data(repeating: 0, count: EmergencyDenyLatch.fileSize).write(to: target)
    #expect(chmod(target.path, 0o600) == 0)
    let link = symlink.directory.appendingPathComponent("link")
    #expect(Darwin.symlink(target.path, link.path) == 0)
    #expect(throws: EmergencyDenyLatchError.self) {
        _ = try EmergencyDenyLatch(url: link)
    }
}

@Test func latchRejectsUnsafeWallTimeWithoutChangingState() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let url = temporary.directory.appendingPathComponent("emergency-deny.latch")
    let latch = try EmergencyDenyLatch(url: url)

    await #expect(throws: EmergencyDenyLatchError.invalidRecord) {
        _ = try await latch.activate(
            pendingDeviceID: nil,
            reason: .securityStoreUnavailable,
            recordedAtUnixMilliseconds: -1
        )
    }
    #expect(try await latch.snapshot().health == .clear)
    #expect(try await latch.snapshot().generation == 0)

    await #expect(throws: EmergencyDenyLatchError.invalidRecord) {
        _ = try await latch.activate(
            pendingDeviceID: nil,
            reason: .revocationInProgress,
            recordedAtUnixMilliseconds: 1_000
        )
    }
}

@Test func separateLatchInstancesSerializeConcurrentUpdates() async throws {
    let temporary = try TemporaryDatabase()
    defer { temporary.remove() }
    let url = temporary.directory.appendingPathComponent("emergency-deny.latch")
    let first = try EmergencyDenyLatch(url: url)
    let second = try EmergencyDenyLatch(url: url)

    try await withThrowingTaskGroup(of: Void.self) { group in
        for index in 1...100 {
            let latch = index.isMultiple(of: 2) ? first : second
            group.addTask {
                _ = try await latch.activate(
                    pendingDeviceID: nil,
                    reason: .securityStoreUnavailable,
                    recordedAtUnixMilliseconds: Int64(index)
                )
            }
        }
        try await group.waitForAll()
    }

    let snapshot = try await first.snapshot()
    #expect(snapshot.health == .active)
    #expect(snapshot.generation == 100)
}
#endif
