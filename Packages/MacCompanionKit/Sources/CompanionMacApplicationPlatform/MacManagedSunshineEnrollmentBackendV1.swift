#if os(macOS)
import Foundation
import Darwin
import CompanionInteractiveHost
import CompanionInteractiveShared

/// Menu-owned backend with isolated, finite-lived enrollment state.
/// Only the coordinator's valid proof may call activate. Private state belongs
/// exclusively to this instance; the installed Sunshine state is never read.
@MainActor
public final class MacManagedSunshineEnrollmentBackendV1: InteractiveNativeVideoEnrollmentBackendV0 {
    public enum ListenerScope: Sendable {
        case loopback, ipv4Interfaces, dualStackInterfaces
        package var bindAddress: String {
            switch self {
            case .loopback: "127.0.0.1"
            case .ipv4Interfaces: "0.0.0.0"
            case .dualStackInterfaces: "::"
            }
        }
        package var addressFamily: String { self == .dualStackInterfaces ? "both" : "ipv4" }
    }
    public enum Failure: Error { case invalidPhase, invalidCertificate, startupFailed, invalidPath }
    private let root: URL
    private let sunshine: URL
    private let supervisor: URL
    private let openssl: URL
    private let opensslConfiguration: URL
    private let port: UInt16
    private let listenerScope: ListenerScope
    private let approvedDesktopDisplayID: UInt32
    private let approvedCaptureGeometry: InteractiveNativeVideoContentGeometryV0
    private let approvedSelectedCapture: MacManagedNativeSelectedCaptureV1?
    private let currentControl: @MainActor () -> Bool
    private let withCurrentControl: (@MainActor (UInt64, () throws -> Void) throws -> Void)?
    private var operation: UUID?
    private var directory: URL?
    private var hostDER: Data?
    private var clientPEM: String?
    private var deadline: UInt64?
    private var processOwner: MacManagedSunshineProcessOwnerV1?
    private var probe: Process?
    private var retired = false
    private var ready = false
    private var captureReported = false
    private var captureShapeReported = false
    private var drain: Task<Void, Never>?

    public init(root: URL, sunshine: URL, supervisor: URL, openssl: URL,
         opensslConfiguration: URL = URL(fileURLWithPath: "/dev/null"),
         port: UInt16, approvedDesktopDisplayID: UInt32, approvedCaptureGeometry: InteractiveNativeVideoContentGeometryV0, currentControl: @escaping @MainActor () -> Bool,
        withCurrentControl: (@MainActor (UInt64, () throws -> Void) throws -> Void)? = nil,
        listenerScope: ListenerScope = .loopback,
        approvedSelectedCapture: MacManagedNativeSelectedCaptureV1? = nil) throws {
        for url in [root, sunshine, supervisor, openssl, opensslConfiguration] {
            guard url.isFileURL, url.path.hasPrefix("/"), !url.path.contains("\n"), !url.path.contains("\r") else { throw Failure.invalidPath }
        }
        guard approvedDesktopDisplayID != 0 else { throw Failure.invalidPath }
        _ = try InteractiveNativeVideoEndpointV0(portBase: port)
        guard approvedSelectedCapture == nil || approvedSelectedCapture?.geometry == approvedCaptureGeometry else { throw Failure.invalidPhase }
        self.root = try approvedSelectedCapture == nil ? root : Self.physicalRoot(root)
        self.sunshine = sunshine; self.supervisor = supervisor
        self.openssl = openssl; self.port = port
        self.opensslConfiguration = opensslConfiguration
        self.approvedDesktopDisplayID = approvedSelectedCapture?.physicalDisplayID ?? approvedDesktopDisplayID
        self.currentControl = {
            let controlIsCurrent = currentControl()
            let selectionIsCurrent = approvedSelectedCapture?.isCurrent ?? true
            #if DEBUG
            if !controlIsCurrent || !selectionIsCurrent {
                NSLog("[MacCompanion selected capture] current control=%@ selection=%@",
                      controlIsCurrent ? "true" : "false",
                      selectionIsCurrent ? "true" : "false")
            }
            #endif
            return controlIsCurrent && selectionIsCurrent
        }
        self.approvedCaptureGeometry = approvedCaptureGeometry
        self.approvedSelectedCapture = approvedSelectedCapture
        self.withCurrentControl = withCurrentControl
        self.listenerScope = listenerScope
    }

    // Foundation's URL symlink resolver can preserve /tmp as a literal path on
    // macOS. The selected child intentionally rejects that alias, so pass the
    // physical directory returned by POSIX realpath instead.
    nonisolated static func physicalRoot(_ root: URL) throws -> URL {
        guard root.isFileURL, let pointer = realpath(root.path, nil) else { throw Failure.invalidPath }
        defer { free(pointer) }
        guard let path = String(validatingCString: pointer), path.hasPrefix("/"),
              !path.contains("\n"), !path.contains("\r") else { throw Failure.invalidPath }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Failure.invalidPath
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    public func prepare(operationID: UUID, authority: InteractiveNativeVideoAuthorityV0, clientCertificateDER: Data) async throws -> Data {
        guard !retired, operation == nil, currentControl(), (1...4096).contains(clientCertificateDER.count) else { throw Failure.invalidPhase }
        guard authority.surface.encodedWidth == approvedCaptureGeometry.encodedWidth,
              authority.surface.encodedHeight == approvedCaptureGeometry.encodedHeight else { throw Failure.invalidPhase }
        // Validate the complete existing authority before retaining any local
        // selected metadata. This projection supplies no substitute proof.
        let selectedContext = try approvedSelectedCapture?.contextData(operationID: operationID, authority: authority)
        operation = operationID
        let dir = root.appendingPathComponent("managed-" + operationID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        directory = dir
        if let selectedContext { try write(selectedContext, "selected-capture.json") }
        try write(clientCertificateDER, "client.der")
        // Exact DER roundtrip and a valid, current self-signed TLS client identity.
        try command(["x509", "-inform", "DER", "-in", path("client.der"), "-out", path("client.pem")])
        try command(["x509", "-in", path("client.pem"), "-outform", "DER", "-out", path("canonical.der")])
        guard try Data(contentsOf: dir.appendingPathComponent("canonical.der")) == clientCertificateDER else { throw Failure.invalidCertificate }
        try command(["verify", "-check_ss_sig", "-purpose", "sslclient", "-CAfile", path("client.pem"), path("client.pem")])
        // The relocated helper retains its developer OPENSSLDIR. Select the
        // admitted configuration even after that build directory is removed.
        try command(["req", "-config", opensslConfiguration.path, "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256", "-days", "1",
                     "-subj", "/CN=localhost", "-addext", "extendedKeyUsage=serverAuth", "-addext", "subjectAltName=DNS:localhost",
                     "-keyout", path("key.pem"), "-out", path("cert.pem")])
        try command(["x509", "-in", path("cert.pem"), "-outform", "DER", "-out", path("host.der")])
        let cert = try Data(contentsOf: dir.appendingPathComponent("host.der"))
        guard (1...4096).contains(cert.count) else { throw Failure.invalidCertificate }
        for name in ["client.pem", "canonical.der", "key.pem", "cert.pem", "host.der"] {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path(name))
        }
        clientPEM = try String(contentsOf: dir.appendingPathComponent("client.pem"), encoding: .utf8)
        hostDER = cert
        deadline = authority.binding.expiresAtMonotonicMilliseconds
        return cert
    }

    public func activate(operationID: UUID) async throws -> InteractiveNativeVideoEndpointV0 {
        guard !retired, operation == operationID, processOwner == nil, currentControl(),
              let dir = directory, let clientPEM, let deadline,
              deadline > DispatchTime.now().uptimeNanoseconds / 1_000_000,
              deadline <= UInt64.max / 1_000_000 else { throw Failure.invalidPhase }
        // Sunshine loads only this exact attested certificate on first startup.
        let state: [String: Any] = ["root": ["uniqueid": operationID.uuidString,
            "named_devices": [["name": "MacCompanion approved client", "uuid": UUID().uuidString,
                                "cert": clientPEM, "enabled": true]]]]
        try write(try JSONSerialization.data(withJSONObject: state), "state.json")
        try write(try JSONSerialization.data(withJSONObject: ["env": [:], "apps": [["name": "Desktop", "image-path": "desktop.png"]]]), "apps.json")
        let values: [String: String] = ["port": String(port), "bind_address": listenerScope.bindAddress, "address_family": listenerScope.addressFamily,
            "lan_encryption_mode": "2", "wan_encryption_mode": "2",
            "keyboard": "disabled", "mouse": "disabled", "controller": "disabled", "native_pen_touch": "disabled",
            "upnp": "disabled", "stream_audio": "disabled", "origin_web_ui_allowed": "pc", "encoder": "videotoolbox",
            "output_name": String(approvedDesktopDisplayID), "file_apps": path("apps.json"), "file_state": path("state.json"), "credentials_file": path("credentials.json"),
            "pkey": path("key.pem"), "cert": path("cert.pem"), "log_path": path("sunshine.log")]
        try write(Data(values.keys.sorted().map { "\($0) = \(values[$0]!)\n" }.joined().utf8), "sunshine.conf")
        try write(Data(), "startup.log")
        try write(Data(), "capture-geometry.json")
        let owner = MacManagedSunshineProcessOwnerV1(revalidateControl: currentControl, didExit: { [weak self] _ in
            // A helper crash destroys its credentials as well as its listener.
            Task { @MainActor [weak self] in await self?.retire(operationID: operationID) }
        })
        processOwner = owner
        try owner.start(supervisor: supervisor, sunshine: sunshine, configuration: dir.appendingPathComponent("sunshine.conf"),
                        dataDirectory: dir, log: dir.appendingPathComponent("startup.log"), expiresAtMonotonicNanoseconds: deadline * 1_000_000, managedEnrollment: true,
                        nativeCapture: (operationID, dir.appendingPathComponent("capture-geometry.json"),
                            "\(approvedCaptureGeometry.encodedWidth)x\(approvedCaptureGeometry.encodedHeight)x60"),
                        selectedCaptureContext: approvedSelectedCapture == nil ? nil : dir.appendingPathComponent("selected-capture.json"))
        // Require the listening peer to present the prepared certificate. A
        // service already using the port cannot masquerade as this operation.
        for _ in 0..<30 {
            guard !retired, currentControl(), DispatchTime.now().uptimeNanoseconds / 1_000_000 < deadline else { throw Failure.startupFailed }
            if try await matchesPreparedServerCertificate() {
                guard !retired, processOwner?.isRunning == true else { throw Failure.startupFailed }
                ready = true
                return try .init(portBase: port)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw Failure.startupFailed
    }

    public func isActive(operationID: UUID) async -> Bool {
        !retired && ready && operation == operationID && processOwner?.isRunning == true
    }

    public func captureEvidence(operationID: UUID) async throws -> InteractiveNativeVideoCaptureEvidenceV0? {
        guard currentControl() else { return nil }
        return try readCaptureEvidence(operationID: operationID)
    }

    // Synchronous: also called under the atomic permit. It must not reenter
    // currentControl(), which reads that permit's lock.
    private func readCaptureEvidence(operationID: UUID) throws -> InteractiveNativeVideoCaptureEvidenceV0? {
        guard !retired, ready, operation == operationID, processOwner?.isRunning == true,
              approvedSelectedCapture?.isCurrent ?? true,
              let directory else { return nil }
        let url = directory.appendingPathComponent("capture-geometry.json")
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if fd < 0 { if errno == ENOENT { return nil }; throw Failure.invalidPhase }
        defer { close(fd) }
        var facts = stat()
        guard fstat(fd, &facts) == 0, (facts.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              facts.st_uid == geteuid(), (facts.st_mode & 0o777) == 0o600,
              facts.st_size >= 0, facts.st_size <= 2048 else { throw Failure.invalidPhase }
        if facts.st_size == 0 { return nil }
        var bytes = [UInt8](repeating: 0, count: Int(facts.st_size))
        let count = bytes.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
        guard count == bytes.count else { throw Failure.invalidPhase }
        if !captureShapeReported, let object = try? JSONSerialization.jsonObject(with: Data(bytes)) as? [String: Any] {
            let keys: Set<String> = ["encodedWidth", "encodedHeight", "formatWidth", "formatHeight", "cleanX", "cleanY", "cleanWidth", "cleanHeight", "aspectFitConfigured"]
            let metrics = object.filter { keys.contains($0.key) && $0.value is NSNumber }
            if let data = try? JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys]),
               String(data: data, encoding: .utf8) != nil {
                captureShapeReported = true
                FileHandle.standardError.write(Data("native-backend-sample-shape " .utf8) + data + Data("\n".utf8))
            }
        }
        let evidence = try InteractiveNativeVideoCaptureEvidenceV0.decode(Data(bytes))
        do {
            try evidence.validate(operationID: operationID, geometry: approvedCaptureGeometry,
                nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
        } catch InteractiveNativeVideoCaptureEvidenceErrorV0.notCurrent { return nil }
        guard !retired, ready, operation == operationID, processOwner?.isRunning == true else { return nil }
        if !captureReported {
            captureReported = true
            FileHandle.standardError.write(Data("native-backend-sample-geometry-verified\n".utf8))
        }
        return evidence
    }

    public func canPostInput(operationID: UUID) async -> Bool {
        !Task.isCancelled && !retired && ready && operation == operationID && processOwner?.isRunning == true
            && currentControl() && withCurrentControl != nil
    }

    public func postInputBatch(operationID: UUID, beforeDeadlineNanoseconds: UInt64,
                        batch: @escaping @Sendable () throws -> Void) async throws {
        guard !Task.isCancelled, currentControl(), let withCurrentControl else { throw Failure.invalidPhase }
        try withCurrentControl(beforeDeadlineNanoseconds) {
            guard !Task.isCancelled, !retired, ready, operation == operationID, processOwner?.isRunning == true,
                  let deadline, let evidence = try readCaptureEvidence(operationID: operationID) else {
                throw Failure.invalidPhase
            }
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < beforeDeadlineNanoseconds, now / 1_000_000 < deadline else { throw Failure.invalidPhase }
            try evidence.validate(operationID: operationID, geometry: approvedCaptureGeometry,
                nowMonotonicNanoseconds: now)
            try batch()
        }
    }

    public func retire(operationID: UUID) async {
        guard operation == nil || operation == operationID else { return }
        if let drain { await drain.value; return }
        retired = true
        ready = false
        let pendingProbe = probe
        pendingProbe?.terminate()
        let owner = processOwner
        let task = Task { @MainActor in
            if let pendingProbe {
                let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
                while pendingProbe.isRunning, DispatchTime.now().uptimeNanoseconds < deadline {
                    try? await Task.sleep(for: .milliseconds(10))
                }
                if pendingProbe.isRunning { kill(pendingProbe.processIdentifier, SIGKILL) }
                pendingProbe.waitUntilExit()
            }
            await owner?.stop()
        }
        drain = task
        await task.value
        processOwner = nil
        clientPEM = nil; hostDER = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }

    private func matchesPreparedServerCertificate() async throws -> Bool {
        guard !retired, let directory, let hostDER else { return false }
        let outputURL = directory.appendingPathComponent("tls-probe.pem")
        try write(Data(), "tls-probe.pem")
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }
        let child = Process()
        child.executableURL = openssl
        child.arguments = ["s_client", "-connect", "127.0.0.1:\(port - 5)", "-showcerts", "-CAfile", path("cert.pem"), "-verify_return_error"]
        child.standardInput = FileHandle.nullDevice; child.standardOutput = output; child.standardError = FileHandle.nullDevice
        probe = child
        try child.run()
        let timeout = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
        while child.isRunning, !retired, DispatchTime.now().uptimeNanoseconds < timeout {
            try? await Task.sleep(for: .milliseconds(10))
        }
        if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        child.waitUntilExit()
        probe = nil
        guard !retired else { return false }
        // No client key lives on the host, so TLS rejects the missing client
        // certificate after exposing the server certificate. Check exact DER.
        do {
            try command(["x509", "-in", outputURL.path, "-outform", "DER", "-out", path("peer.der")])
            return try Data(contentsOf: directory.appendingPathComponent("peer.der")) == hostDER
        } catch { return false }
    }
    private func path(_ name: String) -> String { directory!.appendingPathComponent(name).path }
    private func write(_ data: Data, _ name: String) throws {
        try data.write(to: URL(fileURLWithPath: path(name)), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path(name))
    }
    private func command(_ arguments: [String]) throws {
        let child = Process(); child.executableURL = openssl; child.arguments = arguments
        child.standardInput = FileHandle.nullDevice; child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
        try child.run(); child.waitUntilExit()
        guard child.terminationStatus == 0 else { throw Failure.invalidCertificate }
    }
}

#endif
