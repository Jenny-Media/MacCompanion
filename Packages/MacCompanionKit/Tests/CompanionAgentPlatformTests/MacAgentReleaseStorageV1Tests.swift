#if os(macOS)
@testable import CompanionAgentPlatform
import CompanionPersistence
import Foundation
import Testing

private func releaseStorageTemporaryBaseV1() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-release-storage-\(UUID().uuidString.lowercased())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: url,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: url.path
    )
    return url
}

private func releaseStorageModeV1(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(
        atPath: url.path
    )
    return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

@Test func releaseStorageCreatesOnePrivateComposedRoot() async throws {
    let base = try releaseStorageTemporaryBaseV1()
    defer { try? FileManager.default.removeItem(at: base) }

    let storage = try MacAgentReleaseStorageV1(
        baseApplicationSupportDirectory: base
    )
    #expect(storage.paths.root.path.hasSuffix(
        "/\(base.lastPathComponent)/media.jenny.maccompanion/Agent/v1"
    ))
    #expect(try releaseStorageModeV1(storage.paths.root) == 0o700)
    #expect(try releaseStorageModeV1(storage.paths.securityDatabase) == 0o600)
    #expect(try releaseStorageModeV1(storage.paths.detailedAuditDatabase) == 0o600)
    #expect(try releaseStorageModeV1(storage.paths.emergencyDenyLatch) == 0o600)

    let latch = try EmergencyDenyLatch(url: storage.paths.emergencyDenyLatch)
    #expect(try await latch.snapshot().health == .clear)
    #expect((await storage.requiredAudit.healthSnapshot()).degradedProducers.isEmpty)
}

@Test func releaseStorageReopensExactExistingAuthority() async throws {
    let base = try releaseStorageTemporaryBaseV1()
    defer { try? FileManager.default.removeItem(at: base) }

    let first = try MacAgentReleaseStorageV1(
        baseApplicationSupportDirectory: base
    )
    let activated = try EmergencyDenyLatch(
        url: first.paths.emergencyDenyLatch
    )
    _ = try await activated.activate(
        pendingDeviceID: nil,
        reason: .securityStoreUnavailable,
        recordedAtUnixMilliseconds: 1
    )

    let reopened = try MacAgentReleaseStorageV1(
        baseApplicationSupportDirectory: base
    )
    #expect(reopened.paths == first.paths)
    let latch = try EmergencyDenyLatch(url: reopened.paths.emergencyDenyLatch)
    #expect(try await latch.snapshot().health == .active)
}

@Test func releaseStorageRejectsSymlinkBase() throws {
    let parent = try releaseStorageTemporaryBaseV1()
    defer { try? FileManager.default.removeItem(at: parent) }
    let target = parent.appendingPathComponent("target", isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: target.path
    )
    let link = parent.appendingPathComponent("link", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    #expect(throws: MacAgentReleaseStorageErrorV1.invalidBaseDirectory) {
        _ = try MacAgentReleaseStorageV1(
            baseApplicationSupportDirectory: link
        )
    }
}

@Test func releaseStorageRejectsBroadExistingProductDirectory() throws {
    let base = try releaseStorageTemporaryBaseV1()
    defer { try? FileManager.default.removeItem(at: base) }
    let product = base.appendingPathComponent(
        "media.jenny.maccompanion",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: product, withIntermediateDirectories: false)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: product.path
    )

    #expect(throws: MacAgentReleaseStorageErrorV1.insecureDirectory(
        "media.jenny.maccompanion"
    )) {
        _ = try MacAgentReleaseStorageV1(
            baseApplicationSupportDirectory: base
        )
    }
}

@Test func releaseStorageRejectsSymlinkedNestedComponent() throws {
    let base = try releaseStorageTemporaryBaseV1()
    defer { try? FileManager.default.removeItem(at: base) }
    let product = base.appendingPathComponent(
        "media.jenny.maccompanion",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: product,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o700],
        ofItemAtPath: product.path
    )
    let target = base.appendingPathComponent("target", isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
    let link = product.appendingPathComponent("Agent", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    #expect(throws: MacAgentReleaseStorageErrorV1.insecureDirectory("Agent")) {
        _ = try MacAgentReleaseStorageV1(
            baseApplicationSupportDirectory: base
        )
    }
}

@Test func releaseStorageRejectsPreexistingDatabaseSymlink() throws {
    let base = try releaseStorageTemporaryBaseV1()
    defer { try? FileManager.default.removeItem(at: base) }
    let root = MacAgentReleaseStorageV1.applicationSupportComponents.reduce(base) {
        $0.appendingPathComponent($1, isDirectory: true)
    }
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    var cursor = base
    for component in MacAgentReleaseStorageV1.applicationSupportComponents {
        cursor.appendPathComponent(component, isDirectory: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: cursor.path
        )
    }
    let target = base.appendingPathComponent("target.sqlite3")
    _ = FileManager.default.createFile(atPath: target.path, contents: Data())
    let link = root.appendingPathComponent("security-v1.sqlite3")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    #expect(throws: SecurityStoreError.insecureStoragePath) {
        _ = try MacAgentReleaseStorageV1(
            baseApplicationSupportDirectory: base
        )
    }
}

@Test func releaseStorageRejectsDatabasePathSubstitutionAfterOpen() throws {
    let base = try releaseStorageTemporaryBaseV1()
    defer { try? FileManager.default.removeItem(at: base) }

    #expect(throws: SecurityStoreError.insecureStoragePath) {
        _ = try MacAgentReleaseStorageV1(
            baseApplicationSupportDirectory: base,
            afterArtifactsConstructed: { paths in
                let displaced = paths.securityDatabase.appendingPathExtension(
                    "displaced"
                )
                try FileManager.default.moveItem(
                    at: paths.securityDatabase,
                    to: displaced
                )
                guard FileManager.default.createFile(
                    atPath: paths.securityDatabase.path,
                    contents: Data()
                ) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: paths.securityDatabase.path
                )
            }
        )
    }
}

@Test func releaseStorageRejectsAuditPathSubstitutionAfterOpen() throws {
    let base = try releaseStorageTemporaryBaseV1()
    defer { try? FileManager.default.removeItem(at: base) }

    #expect(throws: AuditStoreErrorV0.insecureStoragePath) {
        _ = try MacAgentReleaseStorageV1(
            baseApplicationSupportDirectory: base,
            afterArtifactsConstructed: { paths in
                let displaced = paths.detailedAuditDatabase
                    .appendingPathExtension("displaced")
                try FileManager.default.moveItem(
                    at: paths.detailedAuditDatabase,
                    to: displaced
                )
                guard FileManager.default.createFile(
                    atPath: paths.detailedAuditDatabase.path,
                    contents: Data()
                ) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: paths.detailedAuditDatabase.path
                )
            }
        )
    }
}

@Test func releaseStorageRejectsLatchPathSubstitutionAfterOpen() throws {
    let base = try releaseStorageTemporaryBaseV1()
    defer { try? FileManager.default.removeItem(at: base) }

    #expect(throws: EmergencyDenyLatchError.verificationFailed) {
        _ = try MacAgentReleaseStorageV1(
            baseApplicationSupportDirectory: base,
            afterArtifactsConstructed: { paths in
                let displaced = paths.emergencyDenyLatch
                    .appendingPathExtension("displaced")
                try FileManager.default.moveItem(
                    at: paths.emergencyDenyLatch,
                    to: displaced
                )
                guard FileManager.default.createFile(
                    atPath: paths.emergencyDenyLatch.path,
                    contents: Data(
                        repeating: 0,
                        count: EmergencyDenyLatch.fileSize
                    )
                ) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: paths.emergencyDenyLatch.path
                )
            }
        )
    }
}
#endif
