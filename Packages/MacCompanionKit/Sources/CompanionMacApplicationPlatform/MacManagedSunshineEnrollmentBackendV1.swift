#if os(macOS)
import Foundation
import Darwin
import CoreGraphics
import OSLog
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionIPC

private let managedNativeCaptureDiagnosticsLoggerV1 = Logger(
    subsystem: "media.jenny.maccompanion.mac", category: "native-host-diagnostics")

/// Menu-owned backend with isolated, finite-lived enrollment state.
/// Only the coordinator's valid proof may call activate. Private state belongs
/// exclusively to this instance; the installed Sunshine state is never read.
@MainActor
public final class MacManagedSunshineEnrollmentBackendV1: MacInteractiveNativeStreamReplacingV1 {
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
    private var approvedDesktopDisplayID: UInt32
    private var approvedCaptureGeometry: InteractiveNativeVideoContentGeometryV0
    private var approvedSelectedCapture: MacManagedNativeSelectedCaptureV1?
    private let originalControl: @MainActor () -> Bool
    private let streamContinuityEnabled: Bool
    private var originalAuthority: InteractiveNativeVideoAuthorityV0?
    private var clientDER: Data?
    private var captureOperationID: UUID?
    private var handoff: MacManagedCaptureHandoffV1?
    private var retained = false
    private var retaining = false
    private var retainedUntil: UInt64?
    private var replacement: (authority: InteractiveNativeVideoAuthorityV0, physicalDisplayID: UInt32,
        geometry: InteractiveNativeVideoContentGeometryV0, selected: MacManagedNativeSelectedCaptureV1?)?
    private var replacementContext: Data?
    private var reportedControlFailure = false
    private var currentControl: @MainActor () -> Bool {
        { [weak self] in
            guard let self, !self.retired else { return false }
            guard self.originalControl() else {
                self.recordControlFailure(selectedReason: 0)
                return false
            }
            if self.retained { return true }
            if let reason = self.approvedSelectedCapture?.validationFailure {
                self.recordControlFailure(selectedReason: reason.rawValue)
                return false
            }
            return true
        }
    }
    private let withCurrentControl: (@MainActor (UInt64, () throws -> Void) throws -> Void)?
    private var operation: UUID?
    private var directory: URL?
    private var hostDER: Data?
    private var clientPEM: String?
    private var deadline: UInt64?
    private var processOwner: MacManagedSunshineProcessOwnerV1?
    private var probe: Process?
    private var commandProcess: Process?
    private var commandTask: Task<Int32, Error>?
    private var retired = false
    private var ready = false
    private var captureReported = false
    private var captureShapeReported = false
    private var lastEvidenceFailure: String? = nil
    private var drain: Task<Void, Never>?

    private func recordControlFailure(selectedReason: Int) {
        guard !reportedControlFailure else { return }
        reportedControlFailure = true
        // 0 means original local permit loss; 1...9 are the closed selected
        // capture codes. No identities, bounds, titles or input are formatted.
        managedNativeCaptureDiagnosticsLoggerV1.error("native-control-invalid selectedReason=\(selectedReason, privacy: .public)")
    }

    public init(root: URL, sunshine: URL, supervisor: URL, openssl: URL,
         opensslConfiguration: URL = URL(fileURLWithPath: "/dev/null"),
         port: UInt16, approvedDesktopDisplayID: UInt32, approvedCaptureGeometry: InteractiveNativeVideoContentGeometryV0, currentControl: @escaping @MainActor () -> Bool,
        withCurrentControl: (@MainActor (UInt64, () throws -> Void) throws -> Void)? = nil,
        listenerScope: ListenerScope = .loopback,
        approvedSelectedCapture: MacManagedNativeSelectedCaptureV1? = nil,
        streamContinuityEnabled: Bool = false) throws {
        for url in [root, sunshine, supervisor, openssl, opensslConfiguration] {
            guard url.isFileURL, url.path.hasPrefix("/"), !url.path.contains("\n"), !url.path.contains("\r") else { throw Failure.invalidPath }
        }
        guard approvedDesktopDisplayID != 0 else { throw Failure.invalidPath }
        _ = try InteractiveNativeVideoEndpointV0(portBase: port)
        guard approvedSelectedCapture == nil || approvedSelectedCapture?.geometry == approvedCaptureGeometry else { throw Failure.invalidPhase }
        self.root = try approvedSelectedCapture == nil && !streamContinuityEnabled ? root : Self.physicalRoot(root)
        self.sunshine = sunshine; self.supervisor = supervisor
        self.openssl = openssl; self.port = port
        self.opensslConfiguration = opensslConfiguration
        self.approvedDesktopDisplayID = approvedSelectedCapture?.physicalDisplayID ?? approvedDesktopDisplayID
        self.originalControl = currentControl
        self.streamContinuityEnabled = streamContinuityEnabled
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
        if operation != nil {
            return try prepareRetainedReplacement(operationID: operationID, authority: authority, clientCertificateDER: clientCertificateDER)
        }
        guard !retired, currentControl(), (1...4096).contains(clientCertificateDER.count) else { throw Failure.invalidPhase }
        guard authority.surface.encodedWidth == approvedCaptureGeometry.encodedWidth,
              authority.surface.encodedHeight == approvedCaptureGeometry.encodedHeight else { throw Failure.invalidPhase }
        // Validate the complete existing authority before retaining any local
        // selected metadata. This projection supplies no substitute proof.
        let selectedContext = try captureContext(operationID: operationID, authority: authority)
        operation = operationID
        let dir = root.appendingPathComponent("managed-" + operationID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        directory = dir
        if let selectedContext { try write(selectedContext, "selected-capture.json") }
        try write(clientCertificateDER, "client.der")
        // Exact DER roundtrip and a valid, current self-signed TLS client identity.
        try await command(["x509", "-inform", "DER", "-in", path("client.der"), "-out", path("client.pem")])
        try await command(["x509", "-in", path("client.pem"), "-outform", "DER", "-out", path("canonical.der")])
        guard try Data(contentsOf: dir.appendingPathComponent("canonical.der")) == clientCertificateDER else { throw Failure.invalidCertificate }
        try await command(["verify", "-check_ss_sig", "-purpose", "sslclient", "-CAfile", path("client.pem"), path("client.pem")])
        // The relocated helper retains its developer OPENSSLDIR. Select the
        // admitted configuration even after that build directory is removed.
        try await command(["req", "-config", opensslConfiguration.path, "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256", "-days", "1",
                     "-subj", "/CN=localhost", "-addext", "extendedKeyUsage=serverAuth", "-addext", "subjectAltName=DNS:localhost",
                     "-keyout", path("key.pem"), "-out", path("cert.pem")])
        try await command(["x509", "-in", path("cert.pem"), "-outform", "DER", "-out", path("host.der")])
        let cert = try Data(contentsOf: dir.appendingPathComponent("host.der"))
        guard (1...4096).contains(cert.count) else { throw Failure.invalidCertificate }
        for name in ["client.pem", "canonical.der", "key.pem", "cert.pem", "host.der"] {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path(name))
        }
        clientPEM = try String(contentsOf: dir.appendingPathComponent("client.pem"), encoding: .utf8)
        hostDER = cert
        deadline = authority.binding.expiresAtMonotonicMilliseconds
        originalAuthority = authority; clientDER = clientCertificateDER; captureOperationID = operationID
        return cert
    }

    public func activate(operationID: UUID) async throws -> InteractiveNativeVideoEndpointV0 {
        if processOwner != nil { return try await activateRetainedReplacement(operationID: operationID) }
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
        if streamContinuityEnabled {
            handoff = try MacManagedCaptureHandoffV1(directory: dir, transport: operationID,
                expiryNanoseconds: deadline * 1_000_000, current: { [weak self] in
                    guard let self else { return false }; return !self.retired && self.originalControl() && self.processOwner?.isRunning == true
                })
        }
        let owner = MacManagedSunshineProcessOwnerV1(revalidateControl: currentControl, didExit: { [weak self] _ in
            // A helper crash destroys its credentials as well as its listener.
            Task { @MainActor [weak self] in
                guard let self, let currentOperation = self.operation else { return }
                await self.retire(operationID: currentOperation)
            }
        })
        processOwner = owner
        try owner.start(supervisor: supervisor, sunshine: sunshine, configuration: dir.appendingPathComponent("sunshine.conf"),
                        dataDirectory: dir, log: dir.appendingPathComponent("startup.log"), expiresAtMonotonicNanoseconds: deadline * 1_000_000, managedEnrollment: true,
                        nativeCapture: (operationID, dir.appendingPathComponent("capture-geometry.json"),
                            "\(approvedCaptureGeometry.encodedWidth)x\(approvedCaptureGeometry.encodedHeight)x60"),
                        selectedCaptureContext: approvedSelectedCapture == nil && !streamContinuityEnabled ? nil : dir.appendingPathComponent("selected-capture.json"))
        // Require the listening peer to present the prepared certificate. A
        // service already using the port cannot masquerade as this operation.
        let startupUntil = min(deadline, DispatchTime.now().uptimeNanoseconds / 1_000_000
            + LocalInteractiveNativeBackendOperationV1.activationStartupMilliseconds)
        while DispatchTime.now().uptimeNanoseconds / 1_000_000 < startupUntil {
            guard !Task.isCancelled, !retired, currentControl(), DispatchTime.now().uptimeNanoseconds / 1_000_000 < deadline else { throw Failure.startupFailed }
            if try await matchesPreparedServerCertificate() {
                guard !Task.isCancelled, !retired, currentControl(), processOwner?.isRunning == true,
                      DispatchTime.now().uptimeNanoseconds / 1_000_000 < startupUntil else { throw Failure.startupFailed }
                ready = true
                return try .init(portBase: port)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        managedNativeCaptureDiagnosticsLoggerV1.error("native startup rejected reason=startup-budget")
        throw Failure.startupFailed
    }

    public func isActive(operationID: UUID) async -> Bool {
        !retired && !retained && ready && operation == operationID && processOwner?.isRunning == true
    }

    public func supportsStreamContinuity(operationID: UUID) async -> Bool {
        streamContinuityEnabled && handoff != nil && !retired && !retained && ready
            && operation == operationID && processOwner?.isRunning == true && currentControl()
    }
    public func retainStream(operationID: UUID) async throws {
        guard await supportsStreamContinuity(operationID: operationID), let handoff, let deadline else { throw Failure.invalidPhase }
        let now = DispatchTime.now().uptimeNanoseconds / 1_000_000
        retainedUntil = min(deadline, now + 15_000)
        // Fence backend posting before any child acknowledgement. The menu
        // owner separately revokes the exact installed input authorization.
        retained = true; retaining = true
        do {
            try await handoff.pause(operationID: operationID)
            guard !Task.isCancelled, !retired, operation == operationID, originalControl(),
                  processOwner?.isRunning == true, let retainedUntil,
                  DispatchTime.now().uptimeNanoseconds / 1_000_000 < retainedUntil else { throw Failure.invalidPhase }
            retaining = false; captureReported = false; captureShapeReported = false
        } catch {
            if let reason = error as? MacManagedCaptureHandoffV1.Failure {
                managedNativeCaptureDiagnosticsLoggerV1.error("capture-handoff-failed reason=\(reason.rawValue, privacy: .public)")
            }
            await retire(operationID: operationID); throw error
        }
    }
    public func isStreamRetained(operationID: UUID) async -> Bool {
        !retired && retained && !retaining && operation == operationID && processOwner?.isRunning == true
            && originalControl() && (retainedUntil.map { DispatchTime.now().uptimeNanoseconds / 1_000_000 < $0 } ?? false)
    }

    /// Only the menu's current runtime/display projection supplies these local
    /// values. No serialized physical metadata is accepted from a peer.
    public func configureRetainedReplacement(predecessorOperationID: UUID,
        authority: InteractiveNativeVideoAuthorityV0, physicalDisplayID: UInt32,
        geometry: InteractiveNativeVideoContentGeometryV0, selected: MacManagedNativeSelectedCaptureV1?) async throws {
        guard await isStreamRetained(operationID: predecessorOperationID), replacement == nil, replacementContext == nil,
              let originalAuthority, authority.binding == originalAuthority.binding,
              authority.sessionPublicKeyX963 == originalAuthority.sessionPublicKeyX963,
              authority.surface.encodedWidth == originalAuthority.surface.encodedWidth,
              authority.surface.encodedHeight == originalAuthority.surface.encodedHeight,
              geometry.encodedWidth == authority.surface.encodedWidth, geometry.encodedHeight == authority.surface.encodedHeight,
              physicalDisplayID != 0, selected == nil || selected?.geometry == geometry else { throw Failure.invalidPhase }
        replacement = (authority, physicalDisplayID, geometry, selected)
    }
    private func prepareRetainedReplacement(operationID: UUID, authority: InteractiveNativeVideoAuthorityV0,
        clientCertificateDER: Data) throws -> Data {
        guard !Task.isCancelled, !retired, retained, !retaining, originalControl(), processOwner?.isRunning == true,
              let oldOperation = operation, operationID != oldOperation, clientDER == clientCertificateDER,
              let replacement, replacement.authority == authority, let hostDER, let retainedUntil,
              DispatchTime.now().uptimeNanoseconds / 1_000_000 < retainedUntil else { throw Failure.invalidPhase }
        // Validate and encode before moving the logical owner. Old-operation
        // retirement is harmless after this exact transfer; Stop owns the new one.
        let oldDisplay = approvedDesktopDisplayID, oldGeometry = approvedCaptureGeometry, oldSelected = approvedSelectedCapture
        approvedDesktopDisplayID = replacement.physicalDisplayID
        approvedCaptureGeometry = replacement.geometry; approvedSelectedCapture = replacement.selected
        do {
            guard replacement.selected?.isCurrent ?? true,
                  let context = try captureContext(operationID: operationID, authority: authority) else { throw Failure.invalidPhase }
            replacementContext = context; operation = operationID; self.replacement = nil
            captureReported = false; captureShapeReported = false
            return hostDER
        } catch {
            approvedDesktopDisplayID = oldDisplay; approvedCaptureGeometry = oldGeometry; approvedSelectedCapture = oldSelected
            throw error
        }
    }
    private func activateRetainedReplacement(operationID: UUID) async throws -> InteractiveNativeVideoEndpointV0 {
        guard !retired, retained, !retaining, operation == operationID, originalControl(),
              let context = replacementContext, let previous = captureOperationID, let handoff,
              let retainedUntil, DispatchTime.now().uptimeNanoseconds / 1_000_000 < retainedUntil,
              approvedSelectedCapture?.isCurrent ?? true else { throw Failure.invalidPhase }
        do {
            try await handoff.select(operationID: operationID, previousOperationID: previous, context: context)
            guard !Task.isCancelled, !retired, operation == operationID, originalControl(), processOwner?.isRunning == true,
                  DispatchTime.now().uptimeNanoseconds / 1_000_000 < retainedUntil,
                  approvedSelectedCapture?.isCurrent ?? true else { throw Failure.invalidPhase }
            captureOperationID = operationID; replacementContext = nil; retained = false; self.retainedUntil = nil
            return try .init(portBase: port)
        } catch {
            if let reason = error as? MacManagedCaptureHandoffV1.Failure {
                managedNativeCaptureDiagnosticsLoggerV1.error("capture-handoff-failed reason=\(reason.rawValue, privacy: .public)")
            }
            await retire(operationID: operationID); throw error
        }
    }
    private func captureContext(operationID: UUID, authority: InteractiveNativeVideoAuthorityV0) throws -> Data? {
        let epoch = try streamContinuityEnabled ? authority.surface.frameEpochData() : nil
        if let selected = approvedSelectedCapture {
            return try selected.contextData(operationID: operationID, authority: authority, frameEpoch: epoch)
        }
        guard streamContinuityEnabled else { return nil }
        let bounds = CGDisplayBounds(approvedDesktopDisplayID)
        guard bounds.width == Double(approvedCaptureGeometry.logicalWidthPoints),
              bounds.height == Double(approvedCaptureGeometry.logicalHeightPoints), CGDisplayIsActive(approvedDesktopDisplayID) != 0,
              CGDisplayRotation(approvedDesktopDisplayID) == 0,
              authority.binding.expiresAtMonotonicMilliseconds <= UInt64.max / 1_000_000 else { throw Failure.invalidPhase }
        let scale = Double(approvedCaptureGeometry.capturePixelWidth) / bounds.width
        return try MacManagedNativeSelectedCaptureV1.encodeContext(operationID: operationID, kind: "desktop",
            physicalDisplayID: approvedDesktopDisplayID, windowID: 0, processID: 0, bundleIdentifier: "", processLaunchMilliseconds: 0,
            bounds: bounds, backingScale: scale, geometry: approvedCaptureGeometry,
            expiryNanoseconds: authority.binding.expiresAtMonotonicMilliseconds * 1_000_000, frameEpoch: epoch)
    }

    public func captureEvidence(operationID: UUID) async throws -> InteractiveNativeVideoCaptureEvidenceV0? {
        guard currentControl() else { return nil }
        return try readCaptureEvidence(operationID: operationID)
    }

    // Synchronous: also called under the atomic permit. It must not reenter
    // currentControl(), which reads that permit's lock.
    private func readCaptureEvidence(operationID: UUID) throws -> InteractiveNativeVideoCaptureEvidenceV0? {
        lastEvidenceFailure = "not-active"
        guard !retired, !retained, ready, operation == operationID, processOwner?.isRunning == true,
              approvedSelectedCapture?.isCurrent ?? true,
              let directory else { return nil }
        let url = directory.appendingPathComponent("capture-geometry.json")
        lastEvidenceFailure = "file-absent"
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)
        if fd < 0 { if errno == ENOENT { return nil }; throw Failure.invalidPhase }
        defer { close(fd) }
        var facts = stat()
        lastEvidenceFailure = "unsafe-file"
        guard fstat(fd, &facts) == 0, (facts.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              facts.st_uid == geteuid(), (facts.st_mode & 0o777) == 0o600,
              facts.st_size >= 0, facts.st_size <= 2048 else { throw Failure.invalidPhase }
        if facts.st_size == 0 {
            lastEvidenceFailure = "empty-file"
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: Int(facts.st_size))
        let count = bytes.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
        lastEvidenceFailure = "short-read"
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
        lastEvidenceFailure = "malformed-evidence"
        let evidence = try InteractiveNativeVideoCaptureEvidenceV0.decode(Data(bytes))
        lastEvidenceFailure = "evidence-validation"
        do {
            try evidence.validate(operationID: operationID, geometry: approvedCaptureGeometry,
                nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
        } catch InteractiveNativeVideoCaptureEvidenceErrorV0.notCurrent {
            lastEvidenceFailure = "evidence-not-current"
            return nil
        }
        lastEvidenceFailure = "owner-changed"
        guard !retired, !retained, ready, operation == operationID, processOwner?.isRunning == true else { return nil }
        lastEvidenceFailure = nil
        if !captureReported {
            captureReported = true
            FileHandle.standardError.write(Data("native-backend-sample-geometry-verified\n".utf8))
        }
        return evidence
    }

    public func canPostInput(operationID: UUID) async -> Bool {
        !Task.isCancelled && !retired && !retained && ready && operation == operationID && processOwner?.isRunning == true
            && currentControl() && withCurrentControl != nil
    }

    public func postInputBatch(operationID: UUID, beforeDeadlineNanoseconds: UInt64,
                        batch: @escaping @Sendable () throws -> Void) async throws {
        guard !Task.isCancelled, currentControl(), let withCurrentControl else { throw Failure.invalidPhase }
        try withCurrentControl(beforeDeadlineNanoseconds) {
            guard !Task.isCancelled, !retired, !retained, ready, operation == operationID, processOwner?.isRunning == true,
                  let deadline else {
                managedNativeCaptureDiagnosticsLoggerV1.error("native-input-rejected stage=native-post reason=backend.invalidPhase")
                throw Failure.invalidPhase
            }
            guard let evidence = try readCaptureEvidence(operationID: operationID) else {
                managedNativeCaptureDiagnosticsLoggerV1.error("native-input-capture-evidence-unavailable reason=\(self.lastEvidenceFailure ?? "unclassified", privacy: .public)")
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
        ready = false; retained = false; retaining = false; retainedUntil = nil
        handoff?.close(); handoff = nil; replacement = nil; replacementContext = nil
        let pendingProbe = probe
        pendingProbe?.terminate()
        let pendingCommand = commandTask, pendingProcess = commandProcess
        pendingCommand?.cancel()
        if pendingProcess?.isRunning == true { pendingProcess?.terminate() }
        let owner = processOwner
        let task = Task { @MainActor in
            if let pendingProcess {
                let deadline = DispatchTime.now().uptimeNanoseconds + 1_000_000_000
                while pendingProcess.isRunning, DispatchTime.now().uptimeNanoseconds < deadline {
                    try? await Task.sleep(for: .milliseconds(10))
                }
                if pendingProcess.isRunning { kill(pendingProcess.processIdentifier, SIGKILL) }
            }
            _ = try? await pendingCommand?.value
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
        clientPEM = nil; hostDER = nil; clientDER = nil; originalAuthority = nil
        if let directory {
            let codes = Set(["startup.log", "sunshine.log"].flatMap {
                MacManagedNativeCaptureDiagnosticsV1.codes(file: directory.appendingPathComponent($0))
            })
            let kind = approvedSelectedCapture?.surfaceKind.rawValue ?? "desktop"
            for code in codes.sorted() {
                managedNativeCaptureDiagnosticsLoggerV1.notice(
                    "managed native child retired kind=\(kind, privacy: .public) diagnostic=\(code, privacy: .public)")
            }
            try? FileManager.default.removeItem(at: directory)
        }
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
        while child.isRunning, !Task.isCancelled, !retired, DispatchTime.now().uptimeNanoseconds < timeout {
            try? await Task.sleep(for: .milliseconds(10))
        }
        if child.isRunning { kill(child.processIdentifier, SIGKILL) }
        child.waitUntilExit()
        probe = nil
        guard !retired else { return false }
        // No client key lives on the host, so TLS rejects the missing client
        // certificate after exposing the server certificate. Check exact DER.
        do {
            try await command(["x509", "-in", outputURL.path, "-outform", "DER", "-out", path("peer.der")])
            return try Data(contentsOf: directory.appendingPathComponent("peer.der")) == hostDER
        } catch { return false }
    }
    private func path(_ name: String) -> String { directory!.appendingPathComponent(name).path }
    private func write(_ data: Data, _ name: String) throws {
        try data.write(to: URL(fileURLWithPath: path(name)), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path(name))
    }
    private func command(_ arguments: [String]) async throws {
        guard !retired, !Task.isCancelled, currentControl(), commandProcess == nil else { throw Failure.invalidPhase }
        let child = Process(); child.executableURL = openssl; child.arguments = arguments
        child.standardInput = FileHandle.nullDevice; child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
        commandProcess = child
        let task = Task { @MainActor in
            guard !retired, !Task.isCancelled else { throw Failure.invalidPhase }
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                child.terminationHandler = { process in continuation.resume(returning: process.terminationStatus) }
                do { try child.run() }
                catch { child.terminationHandler = nil; continuation.resume(throwing: error) }
            }
        }
        commandTask = task
        defer {
            if commandProcess === child { commandProcess = nil; commandTask = nil }
        }
        // Process.waitUntilExit polls the caller's run loop. On this Mac it
        // adds about 65 ms even to /usr/bin/true and blocks menu input/lease
        // checks. Await termination instead, preserving every validation.
        let status = try await withTaskCancellationHandler { try await task.value } onCancel: {
            task.cancel()
            if child.isRunning { child.terminate() }
        }
        guard !retired, !Task.isCancelled, currentControl() else { throw Failure.invalidPhase }
        guard status == 0 else { throw Failure.invalidCertificate }
    }
}

#endif
