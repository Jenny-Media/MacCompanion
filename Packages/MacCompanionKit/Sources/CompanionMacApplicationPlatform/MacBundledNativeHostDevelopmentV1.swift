#if os(macOS)
import CryptoKit
import Foundation
import Security

/// Local Debug resource authority for the exact reviewed production-supervisor
/// package. Remote enrollment cannot supply a catalog or executable location.
@available(macOS 26.0, *)
public enum MacBundledNativeHostDevelopmentV1 {
    public enum Failure: Error { case invalidSignature, invalidCatalog, changedResources }
    private static let catalogSHA256 = "e6a46019ecbd18104400ef5a1891f05691029c1cb547bbcb44def70c7a67bb8f"

    public static func factoryIfPresent(in app: URL) throws -> MacInteractiveNativeBackendFactoryV1? {
        #if DEBUG
        let catalog = app.appendingPathComponent("Contents/Resources/NativeHostDevelopment.json")
        guard FileManager.default.fileExists(atPath: catalog.path) else { return nil }
        let host = app.appendingPathComponent("Contents/Helpers/Sunshine.app", isDirectory: true)
        let validate: @Sendable () throws -> Void = {
            try validateContainingApp(app)
            let data = try Data(contentsOf: catalog)
            guard data.count <= 65_536, hex(data) == catalogSHA256,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  Set(object.keys) == ["profile", "releaseAdmitted", "files"],
                  object["profile"] as? String == "maccompanion.bundled-native-host-development.v1",
                  object["releaseAdmitted"] as? Bool == false,
                  let files = object["files"] as? [String: String] else { throw Failure.invalidCatalog }
            try validateFiles(in: host, expected: files)
        }
        try validate()
        // Fresh private state per app composition; enrollment owns and removes
        // its operation's credentials. No installed Sunshine state is reused.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("maccompanion-native-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        return MacManagedSunshineBackendFactoryV1.make(root: root,
            sunshine: host.appendingPathComponent("Contents/MacOS/Sunshine"),
            supervisor: host.appendingPathComponent("Contents/Helpers/companion-supervisor"),
            openssl: host.appendingPathComponent("Contents/Helpers/openssl"), port: 58989,
            opensslConfiguration: host.appendingPathComponent("Contents/Resources/DependencyNotices/openssl.cnf"),
            listenerScope: .dualStackInterfaces,
            validateArtifacts: validate)
        #else
        return nil
        #endif
    }

    private static func validateContainingApp(_ app: URL) throws {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString("identifier \"media.jenny.maccompanion\" and anchor apple generic" as CFString,
                                             [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCheckValidity(code,
                SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode | kSecCSCheckAllArchitectures),
                requirement) == errSecSuccess else { throw Failure.invalidSignature }
    }

    // Internal seam for file-integrity tests; production authority is the fixed
    // catalog digest and containing signature above, never this argument alone.
    static func validateFiles(in host: URL, expected: [String: String]) throws {
        let manager = FileManager.default
        let base = host.standardizedFileURL.path
        guard host.isFileURL, base == host.resolvingSymlinksInPath().standardizedFileURL.path,
              !expected.isEmpty, expected.count <= 256,
              let iterator = manager.enumerator(at: host, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey],
                options: [], errorHandler: { _, _ in false }) else { throw Failure.changedResources }
        var observed: [String: String] = [:]
        for case let url as URL in iterator {
            let facts = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
            guard facts.isSymbolicLink != true else { throw Failure.changedResources }
            if facts.isDirectory == true { continue }
            let prefix = base.hasSuffix("/") ? base : base + "/"
            let path = url.standardizedFileURL.path
            guard facts.isRegularFile == true, path.hasPrefix(prefix) else { throw Failure.changedResources }
            let relative = String(path.dropFirst(prefix.count))
            guard let checksum = expected[relative] else { throw Failure.changedResources }
            let actual = hex(try Data(contentsOf: url))
            guard actual == checksum else { throw Failure.changedResources }
            observed[relative] = actual
        }
        guard observed == expected else { throw Failure.changedResources }
    }

    private static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
#endif
