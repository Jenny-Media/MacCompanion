#if !DEBUG || !os(macOS)
#error("Disposable native session is macOS Debug only")
#endif
import CompanionMacApplicationPlatform
import CompanionClient
import CompanionClientNetworkPlatform
import Foundation
#if MACCOMPANION_NATIVE_LAB
import NativeTLS
import CompanionInteractiveHost
import CompanionInteractiveClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionClientPlatform
import CoreVideo
import Security
import CryptoKit

private struct ProbeTracedNativeBackend: MacInteractiveNativeStreamReplacingV1 {
    let base: ManagedSunshineEnrollmentBackend
    func prepare(operationID: UUID, authority: InteractiveNativeVideoAuthorityV0, clientCertificateDER: Data) async throws -> Data {
        let started = DispatchTime.now().uptimeNanoseconds
        defer { FileHandle.standardError.write(Data("native-managed-prepare-elapsed-ms=\((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)\n".utf8)) }
        FileHandle.standardError.write(Data("native-managed-prepare-entered\n".utf8))
        do { return try await base.prepare(operationID: operationID, authority: authority, clientCertificateDER: clientCertificateDER) }
        catch {
            let reason = (error as? ManagedSunshineEnrollmentBackend.Failure).map { String(describing: $0) } ?? String(reflecting: type(of: error))
            FileHandle.standardError.write(Data("native-managed-prepare-failed \(reason)\n".utf8)); throw error
        }
    }
    func activate(operationID: UUID) async throws -> InteractiveNativeVideoEndpointV0 {
        let started = DispatchTime.now().uptimeNanoseconds
        defer { FileHandle.standardError.write(Data("native-managed-activate-elapsed-ms=\((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)\n".utf8)) }
        do { return try await base.activate(operationID: operationID) }
        catch {
            let reason = (error as? ManagedSunshineEnrollmentBackend.Failure).map { String(describing: $0) } ?? String(reflecting: type(of: error))
            FileHandle.standardError.write(Data("native-managed-activate-failed \(reason)\n".utf8)); throw error
        }
    }
    func isActive(operationID: UUID) async -> Bool { await base.isActive(operationID: operationID) }
    func captureEvidence(operationID: UUID) async throws -> InteractiveNativeVideoCaptureEvidenceV0? { try await base.captureEvidence(operationID: operationID) }
    func canPostInput(operationID: UUID) async -> Bool { await base.canPostInput(operationID: operationID) }
    func postInputBatch(operationID: UUID, beforeDeadlineNanoseconds: UInt64,
                        batch: @escaping @Sendable () throws -> Void) async throws {
        try await base.postInputBatch(operationID: operationID, beforeDeadlineNanoseconds: beforeDeadlineNanoseconds, batch: batch)
    }
    func supportsStreamContinuity(operationID: UUID) async -> Bool { await base.supportsStreamContinuity(operationID: operationID) }
    func retainStream(operationID: UUID) async throws {
        try await base.retainStream(operationID: operationID)
        FileHandle.standardError.write(Data("native-managed-stream-retained\n".utf8))
    }
    func isStreamRetained(operationID: UUID) async -> Bool { await base.isStreamRetained(operationID: operationID) }
    func configureRetainedReplacement(predecessorOperationID: UUID, authority: InteractiveNativeVideoAuthorityV0,
        physicalDisplayID: UInt32, geometry: InteractiveNativeVideoContentGeometryV0, selected: MacManagedNativeSelectedCaptureV1?) async throws {
        try await base.configureRetainedReplacement(predecessorOperationID: predecessorOperationID,
            authority: authority, physicalDisplayID: physicalDisplayID, geometry: geometry, selected: selected)
    }
    func retire(operationID: UUID) async { await base.retire(operationID: operationID) }
}

private final class ProbeNativeIdentity: @unchecked Sendable {
    let value: CompanionNativeTLS
    init() throws { value = try CompanionNativeTLS.create() }
    func retire() { value.retire() }
}

/// This renderer actually decodes the generated bootstrap stream and accepts
/// one retained pixel buffer. It is explicitly not a phone/UI presentation test.
private actor ProbeBootstrapRenderer: ClientInteractiveInitialMediaRenderingV0 {
    private var authority = ClientDecoderRenderAuthorityV0()
    private var activation: NetworkClientInteractiveInitialDesktopActivationV0?
    private var retained: VideoToolboxClientDecodedFrameV0?
    private lazy var decoder = VideoToolboxClientDecoderV0 { [weak self] result in
        Task { await self?.received(result) }
    }
    func bind(_ activation: NetworkClientInteractiveInitialDesktopActivationV0) async throws {
        self.activation = activation
        if let retained { try await activation.reportRendered(retained.receipt) }
    }
    func process(header: MediaRecordHeader, payload: Data, admission: ClientMediaAdmissionV0) throws {
        switch try authority.process(header: header, payload: payload, admission: admission) {
        case .configure(let command): try decoder.configure(command)
        case .decode(let command): try decoder.decode(command)
        case .reset: retained = nil; decoder.invalidate()
        case .end: retained = nil; decoder.invalidate()
        }
    }
    private func received(_ result: VideoToolboxClientDecodeResultV0) async {
        guard case let .frame(frame) = result,
              CVPixelBufferGetWidth(frame.pixelBuffer) == Int(frame.receipt.fence.encodedWidth),
              CVPixelBufferGetHeight(frame.pixelBuffer) == Int(frame.receipt.fence.encodedHeight),
              authority.admitDecodedFrame(frame.receipt) != .discardedStale else { return }
        retained = frame
        try? await activation?.reportRendered(frame.receipt)
    }
    func close() { authority.close(); retained = nil; activation = nil; decoder.invalidate() }
}
#endif

@available(macOS 26.0, *)
enum ProbeNativeFlow {
    enum Failure: Error { case unavailable, notActive, cleanup }
    static func factory() throws -> MacInteractiveNativeBackendFactoryV1 {
        #if MACCOMPANION_NATIVE_LAB
        guard let path = ProcessInfo.processInfo.environment["MACCOMPANION_NATIVE_LAB_ROOT"] else { throw Failure.unavailable }
        let root = URL(fileURLWithPath: path, isDirectory: true)
        guard let ownerPath = ProcessInfo.processInfo.environment["MACCOMPANION_NATIVE_LAB_OWNER_DIR"] else { throw Failure.unavailable }
        let owned = URL(fileURLWithPath: ownerPath, isDirectory: true)
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let portable = ProcessInfo.processInfo.environment["MACCOMPANION_NATIVE_LAB_HOST_BUNDLE"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        let sunshine = portable?.appendingPathComponent("Contents/MacOS/Sunshine")
            ?? root.appendingPathComponent("upstream/Sunshine/cmake-build-maccompanion-reference/Sunshine.app/Contents/MacOS/Sunshine")
        let supervisor = portable?.appendingPathComponent("Contents/Helpers/companion-supervisor")
            ?? root.appendingPathComponent("managed-host-supervisor")
        let openssl = portable?.appendingPathComponent("Contents/Helpers/openssl")
            ?? URL(fileURLWithPath: "/opt/homebrew/opt/openssl@3/bin/openssl")
        // The outer lab runner verifies the complete package/signature graph.
        // Bind this factory to those exact local executables at construction.
        let artifacts = try [sunshine, supervisor, openssl].map { url in
            (url, Data(SHA256.hash(data: try Data(contentsOf: url))))
        }
        let factory = MacManagedSunshineBackendFactoryV1.make(root: owned,
            // Keep the disposable listener and all Sunshine offset ports
            // separate from the installed Mac host's 58989 port range.
            sunshine: sunshine, supervisor: supervisor, openssl: openssl, port: 59089,
            listenerScope: ProcessInfo.processInfo.environment["MACCOMPANION_NATIVE_LAB_IPV4_INTERFACES"] == "1"
                ? .ipv4Interfaces : .loopback,
            streamContinuityEnabled: true,
            validateArtifacts: {
                for (url, expected) in artifacts {
                    guard Data(SHA256.hash(data: try Data(contentsOf: url))) == expected else {
                        throw Failure.unavailable
                    }
                }
            })
        return { physicalID, geometry, permit, selected in
            FileHandle.standardError.write(Data("native-managed-factory permitCurrent=\(permit.isCurrent)\n".utf8))
            FileHandle.standardError.write(Data("native-menu-capture-geometry-verified capture=\(geometry.capturePixelWidth)x\(geometry.capturePixelHeight) logical=\(geometry.logicalWidthPoints)x\(geometry.logicalHeightPoints) encoded=\(geometry.encodedWidth)x\(geometry.encodedHeight)\n".utf8))
            let backend = try await factory(physicalID, geometry, permit, selected)
            guard let managed = backend as? MacManagedSunshineEnrollmentBackendV1 else { throw Failure.unavailable }
            return ProbeTracedNativeBackend(base: managed)
        }
        #else
        throw Failure.unavailable
        #endif
    }
    static func run(network: NetworkClientConfiguredRouteApplicationProductV1,
        signer: any ClientSessionAuthenticationSigningV0,
        emit: @escaping @Sendable (String) -> Void) async throws -> (retire: @Sendable () -> Void, verify: @Sendable () async throws -> Void) {
        #if MACCOMPANION_NATIVE_LAB
        let renderer = ProbeBootstrapRenderer()
        let initial = try await network.interactiveRoles.startInitialDesktop(renderer: renderer)
        try await renderer.bind(initial.activation)
        let deadline = ContinuousClock.now + .seconds(8)
        while !(await network.interactiveRoles.refreshInitialDesktopState()), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard case .active = await network.interactiveRoles.state else { throw Failure.notActive }
        emit("native-bootstrap-decoded-and-acknowledged")
        let held = try ProbeNativeIdentity()
        let identity = held.value
        var published = false
        defer { if !published { held.retire() } }
        guard let der = identity.certificateDER else { throw Failure.unavailable }
        let enrolled = try await network.interactiveRoles.enrollNativeVideo(descriptor: initial.descriptor,
            clientCertificateDER: der, signer: signer, validateCertificate: {
                CompanionNativeTLS.validateCertificateDER($0, server: true) || CompanionNativeTLS.validateCertificateDER($0, server: false)
            })
        guard await network.interactiveRoles.isNativeVideoEnrollmentCurrent() else { throw Failure.notActive }
        emit("native-primary-and-local-xpc-enrollment-verified")
        // The runner proves both primary and managed host exclusively loopback.
        // This injected route does not claim shipping route/TCC admission.
        _ = try identity.bindAddress("127.0.0.1", portBase: enrolled.portBase, hostCertificateDER: enrolled.hostCertificateDER)
        let info = try NativeLaunchXML.parse(identity.requestPath("/serverinfo?uniqueid=probe"))
        guard info.fields["PairStatus"] == "1" else { throw Failure.notActive }
        emit("native-enrolled-client-mtls-verified")
        guard await network.interactiveRoles.isNativeVideoEnrollmentCurrent() else { throw Failure.notActive }
        let list = try NativeLaunchXML.parse(identity.requestPath("/applist?uniqueid=probe"))
        guard list.apps.count == 1, list.apps[0]["AppTitle"] == "Desktop",
              let appID = list.apps[0]["ID"].flatMap(UInt32.init), appID > 0 else { throw Failure.notActive }
        let material = NSMutableData(length: 16)!
        defer { material.resetBytes(in: NSRange(location: 0, length: material.length)) }
        var keyID: UInt32 = 0
        guard SecRandomCopyBytes(kSecRandomDefault, 16, material.mutableBytes) == errSecSuccess,
              SecRandomCopyBytes(kSecRandomDefault, MemoryLayout.size(ofValue: keyID), &keyID) == errSecSuccess else { throw Failure.unavailable }
        let hex = (material as Data).map { String(format: "%02x", $0) }.joined()
        let path = "/launch?uniqueid=\(initial.descriptor.interactiveSessionID.uuidString)&appid=\(appID)&mode=\(initial.descriptor.encodedWidth)x\(initial.descriptor.encodedHeight)x60&additionalStates=1&sops=0&rikey=\(hex)&rikeyid=\(Int32(bitPattern: keyID))&localAudioPlayMode=0&surroundAudioInfo=196610&remoteControllersBitmap=0&gcmap=0&gcpersist=0&corever=1"
        let launch = try NativeLaunchXML.parse(identity.requestPath(path))
        guard launch.fields["gamesession"] == "1", let stream = launch.fields["sessionUrl0"],
              NativeLaunchValidationV0.validStreamURL(stream, address: "127.0.0.1", port: Int(enrolled.portBase) + 21),
              await network.interactiveRoles.isNativeVideoEnrollmentCurrent() else { throw Failure.notActive }
        emit("native-authenticated-https-launch-verified")
        published = true
        return (retire: { held.retire() }, verify: {
            guard await network.interactiveRoles.isNativeVideoEnrollmentCurrent() else { throw Failure.notActive }
            let response = try NativeLaunchXML.parse(held.value.requestPath("/serverinfo?uniqueid=probe"))
            guard response.fields["PairStatus"] == "1", await network.interactiveRoles.isNativeVideoEnrollmentCurrent() else { throw Failure.notActive }
        })
        // Keep enrollment active until the real primary Stop retires its host.
        #else
        throw Failure.unavailable
        #endif
    }
    static func requireCleanup() throws {
        #if MACCOMPANION_NATIVE_LAB
        guard let path = ProcessInfo.processInfo.environment["MACCOMPANION_NATIVE_LAB_OWNER_DIR"] else { throw Failure.cleanup }
        let owned = URL(fileURLWithPath: path)
        guard try FileManager.default.contentsOfDirectory(at: owned, includingPropertiesForKeys: nil).isEmpty else { throw Failure.cleanup }
        try FileManager.default.removeItem(at: owned)
        #else
        throw Failure.unavailable
        #endif
    }
}
