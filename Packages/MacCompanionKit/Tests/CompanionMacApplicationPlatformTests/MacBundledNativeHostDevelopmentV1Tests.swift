#if os(macOS)
@testable import CompanionMacApplicationPlatform
import CryptoKit
import Foundation
import Testing

@available(macOS 26.0, *)
@Test func selectedCaptureRootUsesPhysicalPathForOwnedChild() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.appendingPathComponent("maccompanion-selected-root-\(UUID().uuidString)")
    let alias = root.deletingLastPathComponent().appendingPathComponent(root.lastPathComponent + ".alias")
    try manager.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? manager.removeItem(at: alias); try? manager.removeItem(at: root) }
    try manager.createSymbolicLink(at: alias, withDestinationURL: root)
    let physical = try MacManagedSunshineEnrollmentBackendV1.physicalRoot(root)
    let fromAlias = try MacManagedSunshineEnrollmentBackendV1.physicalRoot(alias)
    #expect(physical == fromAlias)
    #expect(physical.path != alias.path)
    #expect(throws: MacManagedSunshineEnrollmentBackendV1.Failure.invalidPath) {
        try MacManagedSunshineEnrollmentBackendV1.physicalRoot(root.appendingPathComponent("missing"))
    }
}

@available(macOS 26.0, *)
@Test func bundledNativeInventoryRejectsMissingChangedExtraAndLinkedFiles() throws {
    let manager = FileManager.default
    let root = manager.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
    try manager.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? manager.removeItem(at: root) }
    let file = root.appendingPathComponent("host")
    let bytes = Data("approved".utf8)
    let checksum = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    let expected = ["host": checksum]
    try bytes.write(to: file)
    try MacBundledNativeHostDevelopmentV1.validateFiles(in: root, expected: expected)
    try Data("changed".utf8).write(to: file)
    #expect(throws: MacBundledNativeHostDevelopmentV1.Failure.changedResources) {
        try MacBundledNativeHostDevelopmentV1.validateFiles(in: root, expected: expected)
    }
    try bytes.write(to: file)
    let extra = root.appendingPathComponent("unlisted")
    try Data().write(to: extra)
    #expect(throws: MacBundledNativeHostDevelopmentV1.Failure.changedResources) {
        try MacBundledNativeHostDevelopmentV1.validateFiles(in: root, expected: expected)
    }
    try manager.removeItem(at: extra)
    try manager.removeItem(at: file)
    #expect(throws: MacBundledNativeHostDevelopmentV1.Failure.changedResources) {
        try MacBundledNativeHostDevelopmentV1.validateFiles(in: root, expected: expected)
    }
    try bytes.write(to: extra)
    try manager.createSymbolicLink(at: file, withDestinationURL: extra)
    #expect(throws: MacBundledNativeHostDevelopmentV1.Failure.changedResources) {
        try MacBundledNativeHostDevelopmentV1.validateFiles(in: root, expected: expected)
    }
}

@available(macOS 26.0, *)
@Test func missingBundledNativeCatalogIsUnavailableAndUnsignedCatalogCannotAdmitHost() throws {
    let manager = FileManager.default
    let app = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
    try manager.createDirectory(at: app.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: app) }
    #expect(try MacBundledNativeHostDevelopmentV1.factoryIfPresent(in: app) == nil)
    try Data("{}".utf8).write(to: app.appendingPathComponent("Contents/Resources/NativeHostDevelopment.json"))
    #if DEBUG
    #expect(throws: MacBundledNativeHostDevelopmentV1.Failure.invalidSignature) {
        _ = try MacBundledNativeHostDevelopmentV1.factoryIfPresent(in: app)
    }
    #else
    #expect(try MacBundledNativeHostDevelopmentV1.factoryIfPresent(in: app) == nil)
    #endif
}
#endif
