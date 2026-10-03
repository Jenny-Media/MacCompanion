#if os(macOS)
import CompanionInteractiveHost
import CompanionInteractiveShared
@testable import CompanionMacApplicationPlatform
import CryptoKit
import Foundation
import Testing

@available(macOS 26.0, *)
@MainActor
@Test func managedNativeRetirementJoinsSuspendedCertificateCommand() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("maccompanion-command-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    defer { try? FileManager.default.removeItem(at: root) }
    let executable = root.appendingPathComponent("inert-openssl")
    // No certificate, listener, capture or proof is produced. A deliberately
    // suspended helper verifies that Stop can run while preparation awaits it.
    try Data("#!/bin/sh\n: > \"$0.started\"\nexec /bin/sleep 30\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    let binding = try InteractiveNativeVideoBindingV0(hostID: UUID(), hostFingerprint: Data(repeating: 1, count: 32),
        clientID: UUID(), primaryConnectionID: Data(repeating: 2, count: 16), interactiveSessionID: UUID(),
        authorizationEpoch: 1, grantRevision: 1, policyRevision: 1, controlGeneration: UUID(),
        expiresAtMonotonicMilliseconds: DispatchTime.now().uptimeNanoseconds / 1_000_000 + 60_000)
    let surface = try InteractiveNativeVideoSurfaceV0(surfaceID: UUID(), surfaceRevision: 1,
        coordinateSpaceRevision: 1, encodedWidth: 640, encodedHeight: 480)
    let authority = try InteractiveNativeVideoAuthorityV0(binding: binding, surface: surface,
        sessionPublicKeyX963: P256.Signing.PrivateKey().publicKey.x963Representation)
    let geometry = try InteractiveNativeVideoContentGeometryV0(encodedWidth: 640, encodedHeight: 480,
        capturePixelWidth: 640, capturePixelHeight: 480, logicalWidthPoints: 640, logicalHeightPoints: 480)
    for cancelPreparation in [false, true] {
        let backend = try MacManagedSunshineEnrollmentBackendV1(root: root, sunshine: executable,
            supervisor: executable, openssl: executable, port: 58989, approvedDesktopDisplayID: 1,
            approvedCaptureGeometry: geometry, currentControl: { true })
        let operation = UUID()
        let pending = Task { try await backend.prepare(operationID: operation, authority: authority, clientCertificateDER: Data([1])) }
        let started = URL(fileURLWithPath: executable.path + ".started")
        let timeout = ContinuousClock.now.advanced(by: .seconds(3))
        while !FileManager.default.fileExists(atPath: started.path), ContinuousClock.now < timeout {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(FileManager.default.fileExists(atPath: started.path), "Preparation must yield the main actor while its helper runs")
        if cancelPreparation { pending.cancel() }
        async let first: Void = backend.retire(operationID: operation)
        async let second: Void = backend.retire(operationID: operation)
        _ = await (first, second)
        do { _ = try await pending.value; Issue.record("Retired preparation produced a certificate") } catch {}
        #expect(await backend.isActive(operationID: operation) == false)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("managed-" + operation.uuidString).path))
        try FileManager.default.removeItem(at: started)
    }
}
#endif
