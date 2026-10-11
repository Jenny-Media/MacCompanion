import XCTest
import UIKit
@testable import MacCompanionVision

private final class VisionMemoryCloud: DirectCloudTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func read() throws -> [Data] { lock.lock(); defer { lock.unlock() }; return Array(values.values) }
    func write(_ data: Data, account: String) throws { lock.lock(); defer { lock.unlock() }; values[account] = data }
    func removeAll() throws { lock.lock(); defer { lock.unlock() }; values = [:] }
}

@MainActor final class VisionMetadataPrivacyTests: XCTestCase {
    func testNativeAppDeclaresBiometricAuthenticationPurpose() throws {
        let purpose = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "NSFaceIDUsageDescription") as? String)
        XCTAssertFalse(purpose.isEmpty)
    }
    func testNativePrivacyCoverRegistersExactlyOnceForItsSceneAndCoversSheets() throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let lock = DirectAppLockV1.shared
        lock.register(scene); lock.register(scene)
        let covers = scene.windows.filter { $0.windowLevel > .alert }
        XCTAssertEqual(covers.count, 1)
        lock.background(); defer { lock.foreground() }
        XCTAssertFalse(lock.canAccess); XCTAssertFalse(covers[0].isHidden)
        XCTAssertTrue(covers[0].rootViewController?.view.accessibilityViewIsModal == true)
        XCTAssertTrue(covers[0].windowScene === scene)
    }
    func testSimulatorCannotCreateAnotherMetadataNamespaceWithoutTheAuthorizedGroup() {
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "MacCompanionSharedKeychainGroup"))
        XCTAssertThrowsError(try DirectCloudKeychain(service: "synthetic-" + UUID().uuidString).read())
    }
    func testMetadataMergePreservesPhoneModesAndNeverCopiesSecrets() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let suiteA = "vision-metadata-a-" + UUID().uuidString, suiteB = "vision-metadata-b-" + UUID().uuidString
        let defaultsA = try XCTUnwrap(UserDefaults(suiteName: suiteA)), defaultsB = try XCTUnwrap(UserDefaults(suiteName: suiteB))
        defer { defaultsA.removePersistentDomain(forName: suiteA); defaultsB.removePersistentDomain(forName: suiteB); try? FileManager.default.removeItem(at: directory) }
        let transport = VisionMemoryCloud()
        let a = DirectMacLibraryV1(url: directory.appending(path: "a.json")), b = DirectMacLibraryV1(url: directory.appending(path: "b.json"))
        let cloudA = DirectCloudSyncV1(defaults: defaultsA, url: directory.appending(path: "a-cloud.json"), transport: transport, writerID: UUID())
        let cloudB = DirectCloudSyncV1(defaults: defaultsB, url: directory.appending(path: "b-cloud.json"), transport: transport, writerID: UUID())
        cloudA.attach(a); cloudB.attach(b)
        XCTAssertTrue(a.save(id: nil, name: "Synthetic phone default", addresses: ["127.0.0.1"], preferredConnection: .trackpad))
        let mac = try XCTUnwrap(a.macs.first)
        defer { try? DesktopCredentialStoreV1.remove(mac.id); try? TerminalSecretStore.remove(mac.id) }
        try DesktopCredentialStoreV1.save(.init(username: "synthetic-private-account", password: "synthetic-private-password"), hostID: mac.id)
        XCTAssertTrue(try transport.read().isEmpty)
        cloudA.setEnabled(true)
        for _ in 0..<100 { if !cloudA.busy { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNil(cloudA.recovery); XCTAssertFalse(try transport.read().isEmpty)
        cloudB.setEnabled(true)
        for _ in 0..<100 { if b.macs.first == mac { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(b.macs.first, mac); XCTAssertEqual(b.macs.first?.preferredConnection, .trackpad)
        let metadata = try transport.read().map { String(decoding: $0, as: UTF8.self) }.joined()
        XCTAssertFalse(metadata.contains("synthetic-private-account")); XCTAssertFalse(metadata.contains("synthetic-private-password"))
        XCTAssertFalse(metadata.contains("host-key")); XCTAssertFalse(metadata.contains("private-key"))
        cloudA.setEnabled(false); cloudB.setEnabled(false)
    }
}
