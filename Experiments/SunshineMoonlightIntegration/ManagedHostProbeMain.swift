import NativeTLS
import Foundation
import CryptoKit
import CoreGraphics
import Security
import Darwin
import CompanionIPC
import CompanionDomain
import CompanionInteractiveWire
import CompanionAgentProductPlatform
import CompanionMacApplicationPlatform
import CompanionLocalXPCPlatform
import CompanionInteractiveRuntime
import CompanionInteractiveHost
import CompanionInteractiveClient
import CompanionClient
import CompanionInteractiveShared

@MainActor
private final class ProbeAuthority {
    var current: InteractiveNativeVideoAuthorityV0?
    var runtimes: [InteractiveMenuRuntimeOwnerV0] = []
}

private struct ProbeSessionSigner: ClientSessionAuthenticationSigningV0 {
    let key: P256.Signing.PrivateKey
    func signAuthenticationInput(_ input: Data) async throws -> Data { try key.signature(for: input).rawRepresentation }
}

// In-process bounded wire bridge for component integration. It deliberately
// does not claim a real authenticated local-XPC or normal primary journey.
@available(macOS 26.0, *)
private struct ProbeNativeMenuSender: MacLocalXPCInteractiveLeaseSendingV1 {
    let owner: MacInteractiveNativeBackendOwnerV1
    func nativeBackend(_ command: LocalInteractiveNativeBackendCommandV1) async throws -> LocalInteractiveNativeBackendReceiptV1 {
        let request = try LocalInteractiveLeaseWireCodecV1.decodeNativeBackendCommand(
            LocalInteractiveLeaseWireCodecV1.encodeNativeBackendCommand(command))
        let receipt = try await owner.handle(request)
        return try LocalInteractiveLeaseWireCodecV1.decodeNativeBackendReceipt(
            LocalInteractiveLeaseWireCodecV1.encodeNativeBackendReceipt(receipt))
    }
    func prepareInitialInteractiveDesktop(_ command: LocalInteractiveInitialDesktopPreparationCommandV1) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
        throw LocalInteractiveNativeBackendErrorV1.unavailable
    }
    func installInteractiveLease(_ command: InteractiveRuntimeInstallCommandV0) throws -> InteractiveRuntimeInstallReceiptV0 {
        throw LocalInteractiveNativeBackendErrorV1.unavailable
    }
    func renewInteractiveLease(_ command: InteractiveRuntimeLeaseRenewalV0) throws { throw LocalInteractiveNativeBackendErrorV1.unavailable }
    func revokeInteractiveLease(_ command: InteractiveRuntimeRevokeCommandV0) throws -> InteractiveRuntimeRevokedReceiptV0 {
        throw LocalInteractiveNativeBackendErrorV1.unavailable
    }
}

// Platform effects are explicit substitutes: this bootstrap sample is not a
// decoded phone frame or permission/TCC proof. Admission itself uses the real owner.
private actor ProbeMenuRuntimeEffects: InteractiveRuntimeIndicatorControllingV0,
    InteractiveRuntimeCaptureControllingV0, InteractiveRuntimeInputControllingV0,
    InteractiveRuntimeFrameControllingV0, InteractiveRuntimeInputPostingV0 {
    let generation: UUID
    init(generation: UUID) { self.generation = generation }
    func showInteractiveIndicator(deviceDisplayName: DeviceDisplayName, interactiveSessionID: UUID) throws -> InteractiveRuntimeIndicatorSnapshotV0 {
        try .init(menuAppGeneration: generation, menuAppRevision: 1)
    }
    func clearInteractiveIndicator() {}
    func startInteractiveCapture(_ command: InteractiveRuntimeInstallCommandV0) -> Set<SurfaceInteractionClass> { [.view] }
    func adoptInteractiveLeaseRenewal(_ renewal: InteractiveRuntimeLeaseRenewalV0) {}
    func prepareInteractiveCaptureTransition(_ command: InteractiveRuntimeSurfaceTransitionCommandV0) throws -> Set<SurfaceInteractionClass> { throw LocalInteractiveNativeBackendErrorV1.unavailable }
    func activatePreparedInteractiveCaptureTransition(_ command: InteractiveRuntimeSurfaceTransitionCommandV0, mediaSequenceBeforeTransition: UInt64) throws { throw LocalInteractiveNativeBackendErrorV1.unavailable }
    func stopInteractiveCapture() {}
    func releaseAllInteractiveInput() {}
    func blankLastInteractiveFrame() {}
    func postInteractiveInput(_ envelope: InteractiveInputEnvelope) throws { throw LocalInteractiveNativeBackendErrorV1.unavailable }
}

private func acknowledgeProbeDesktop(_ runtime: InteractiveMenuRuntimeOwnerV0, command: InteractiveRuntimeInstallCommandV0) async throws {
    let lease = command.lease
    let fence = InteractiveCommandFence(leaseID: lease.leaseID, hostID: lease.hostID, deviceID: lease.deviceID,
        interactiveSessionID: lease.interactiveSessionID, authorizationEpoch: lease.authorizationEpoch,
        selectedDisplayID: lease.selectedDisplayID, surfaceID: lease.surfaceID, surfaceRevision: lease.surfaceRevision,
        coordinateRevision: lease.coordinateRevision)
    // Disposable synthetic bootstrap records accepted by the production media
    // state machine. They do not claim hardware decode or native presentation.
    let configuration = Data([1, 66, 0, 30, 255, 225, 0, 4, 103, 66, 0, 30, 1, 0, 2, 104, 0])
    for (sequence, type, flags, payload) in [(UInt64(1), MediaRecordType.decoderConfiguration, MediaRecordFlags(), configuration),
            (UInt64(2), MediaRecordType.videoAccessUnit, MediaRecordFlags.cleanKeyframe, Data([0, 0, 0, 2, 101, 0]))] {
        let header = try MediaRecordHeader(type: type, flags: flags, payloadLength: UInt32(payload.count),
            interactiveSessionID: lease.interactiveSessionID, authorizationEpoch: lease.authorizationEpoch,
            surfaceID: lease.surfaceID, surfaceRevision: .init(rawValue: lease.surfaceRevision.rawValue),
            coordinateSpaceRevision: .init(rawValue: lease.coordinateRevision.rawValue), mediaSequence: sequence,
            presentationTimeNanoseconds: sequence * 1000, encodedWidth: command.surfaceDescriptor.encodedWidth,
            encodedHeight: command.surfaceDescriptor.encodedHeight)
        try await runtime.publishMedia(.init(commandID: UUID(), fence: fence, header: header, payload: payload),
            nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
    }
    _ = try await runtime.acknowledgeSurface(.init(commandID: UUID(), transitionCommandID: command.commandID,
        leaseID: lease.leaseID, interactiveSessionID: lease.interactiveSessionID, surfaceID: lease.surfaceID,
        surfaceRevision: lease.surfaceRevision, coordinateRevision: lease.coordinateRevision, readyMediaSequence: 2),
        nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
}

@available(macOS 26.0, *)
@main
struct ManagedHostProbeMain {
    @MainActor static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 3 else { fatalError("Expected isolated experiment root and local IPv4 peer") }
        let peerAddress = args[2]
        // This probe can connect only to an IPv4 address actually owned by this
        // Mac. A caller-supplied external address is not a test authority.
        var interfaceList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceList) == 0 else { throw CocoaError(.featureUnsupported) }
        defer { freeifaddrs(interfaceList) }
        var item = interfaceList
        var ownsPeer = false
        while let current = item {
            if let address = current.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET) {
                let ipv4 = UnsafeRawPointer(address).assumingMemoryBound(to: sockaddr_in.self).pointee
                if ipv4.sin_addr.s_addr == inet_addr(peerAddress) { ownsPeer = true }
            }
            item = current.pointee.ifa_next
        }
        guard ownsPeer else { throw CocoaError(.featureUnsupported) }
        let listenerScope: MacManagedSunshineEnrollmentBackendV1.ListenerScope =
            peerAddress == "127.0.0.1" ? .loopback : .ipv4Interfaces
        let root = URL(fileURLWithPath: args[1], isDirectory: true)
        let dir = root.appendingPathComponent("managed-probe-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: dir) }
        let openssl = URL(fileURLWithPath: "/opt/homebrew/opt/openssl@3/bin/openssl")
        func command(_ executable: URL, _ arguments: [String], output: URL? = nil) throws -> Int32 {
            let child = Process(); child.executableURL = executable; child.arguments = arguments
            child.standardInput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
            var handle: FileHandle?
            if let output {
                FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
                handle = try FileHandle(forWritingTo: output); child.standardOutput = handle
            } else { child.standardOutput = FileHandle.nullDevice }
            defer { try? handle?.close() }
            try child.run(); child.waitUntilExit(); return child.terminationStatus
        }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "ManagedHostProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let nativeTLS = try CompanionNativeTLS.create()
        defer { nativeTLS.retire() }
        guard let nativeClientDER = nativeTLS.certificateDER else { throw CocoaError(.fileReadCorruptFile) }
        for name in ["other"] {
            try require(try command(openssl, ["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256", "-days", "1",
                "-subj", "/CN=Disposable Native Probe", "-addext", "extendedKeyUsage=clientAuth",
                "-keyout", dir.appendingPathComponent(name + ".key").path, "-out", dir.appendingPathComponent(name + ".pem").path]) == 0, "Certificate generation")
        }
        let key = P256.Signing.PrivateKey()
        let now = DispatchTime.now().uptimeNanoseconds / 1_000_000
        let b = try InteractiveNativeVideoBindingV0(hostID: UUID(), hostFingerprint: Data(repeating: 1, count: 32),
            clientID: UUID(), primaryConnectionID: Data(repeating: 2, count: 16), interactiveSessionID: UUID(),
            authorizationEpoch: 1, grantRevision: 1, policyRevision: 1, controlGeneration: UUID(),
            expiresAtMonotonicMilliseconds: now + 30_000)
        let displaySelection = try MacInteractiveOpaqueDisplaySelectionV1()
        guard let displayID = displaySelection.opaqueSelectedDisplayID() else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
        let preparedDesktop = try await MacInteractiveInitialDesktopPreparerV1(displaySelection: displaySelection)
            .prepareInitialInteractiveDesktop(.init(commandID: UUID(), interactiveSessionID: b.interactiveSessionID,
                authorizationEpoch: .init(rawValue: UInt64(b.authorizationEpoch)), selectedDisplayID: displayID,
                interactionClasses: [.view]), nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds).descriptor
        let surface = try InteractiveNativeVideoSurfaceV0(surfaceID: preparedDesktop.surfaceID, surfaceRevision: 1,
            coordinateSpaceRevision: 1, encodedWidth: Int(preparedDesktop.encodedWidth), encodedHeight: Int(preparedDesktop.encodedHeight))
        let authority = try InteractiveNativeVideoAuthorityV0(binding: b, surface: surface, sessionPublicKeyX963: key.publicKey.x963Representation)
        let source = ProbeAuthority(); source.current = authority
        let menuGeneration = UUID()
        func makeOwner(acknowledged: Bool = true) async throws -> InteractiveNativeVideoEnrollmentCoordinatorV0 {
            let nowNS = DispatchTime.now().uptimeNanoseconds
            let lease = try InteractiveExecutionLease(leaseID: UUID(), hostID: b.hostID, deviceID: UUID(),
                interactiveSessionID: b.interactiveSessionID, authorizationEpoch: .init(rawValue: UInt64(b.authorizationEpoch)),
                selectedDisplayID: displayID, surfaceID: surface.surfaceID, surfaceRevision: .init(rawValue: UInt64(surface.surfaceRevision)),
                coordinateRevision: .init(rawValue: UInt64(surface.coordinateSpaceRevision)), allowedInteractionClasses: [.view],
                renewalCounter: 0, issuedAtMonotonicNanoseconds: nowNS, expiresAtMonotonicNanoseconds: nowNS + 10_000_000_000)
            let descriptor = try AdaptiveSurfaceDescriptor(interactiveSessionID: b.interactiveSessionID,
                authorizationEpoch: lease.authorizationEpoch, surfaceID: surface.surfaceID, kind: .desktop,
                surfaceRevision: .init(rawValue: UInt64(surface.surfaceRevision)), coordinateSpaceRevision: .init(rawValue: UInt64(surface.coordinateSpaceRevision)),
                encodedWidth: UInt16(surface.encodedWidth), encodedHeight: UInt16(surface.encodedHeight),
                logicalWidthPoints: preparedDesktop.logicalWidthPoints, logicalHeightPoints: preparedDesktop.logicalHeightPoints,
                rotation: preparedDesktop.rotation, interactionClasses: [.view], privacyProfile: .visualOnly,
                metadataFields: [], createdAtMonotonicMilliseconds: Int64(nowNS / 1_000_000), expiresAtMonotonicMilliseconds: Int64(nowNS / 1_000_000) + 30_000)
            let install = try InteractiveRuntimeInstallCommandV0(commandID: b.controlGeneration, lease: lease,
                deviceDisplayName: .init("Native Probe"), surfaceDescriptor: descriptor,
                sessionDeadlineMonotonicNanoseconds: b.expiresAtMonotonicMilliseconds * 1_000_000)
            let effects = ProbeMenuRuntimeEffects(generation: menuGeneration)
            let queue = try BoundedInteractiveMediaQueueV0(maximumRecords: 4, maximumBytes: 4096)
            let runtime = InteractiveMenuRuntimeOwnerV0(indicator: effects, capture: effects, input: effects,
                frame: effects, inputPoster: effects, mediaQueue: queue)
            _ = try await runtime.install(install, nowMonotonicNanoseconds: nowNS)
            source.runtimes.append(runtime)
            if acknowledged { try await acknowledgeProbeDesktop(runtime, command: install) }
            let menu = MacInteractiveNativeBackendOwnerV1.make(displaySelection: displaySelection,
                readSnapshot: { fence, now in
                    guard await source.current == authority else { return nil }
                    return try await runtime.currentNativeVideoSnapshot(fence: fence, nowMonotonicNanoseconds: now)
                }, pauseInput: { fence, now in
                    try await runtime.pauseInputForNativePresentation(fence: fence, nowMonotonicNanoseconds: now)
                }, factory: { physicalDisplayID, geometry, permit, _ in
                    try await MainActor.run {
                        try ManagedSunshineEnrollmentBackend(root: dir,
                            sunshine: root.appendingPathComponent("upstream/Sunshine/cmake-build-maccompanion-reference/Sunshine.app/Contents/MacOS/Sunshine"),
                            supervisor: root.appendingPathComponent("managed-host-supervisor"), openssl: openssl, port: 58989,
                            approvedDesktopDisplayID: physicalDisplayID, approvedCaptureGeometry: geometry,
                            currentControl: { permit.isCurrent && source.current == authority }, listenerScope: listenerScope)
                    }
                })
            let backend = MacLocalXPCNativeEnrollmentBackendV1(sender: ProbeNativeMenuSender(owner: menu),
                snapshot: .init(binding: b, surface: surface,
                    logicalWidthPoints: descriptor.logicalWidthPoints, logicalHeightPoints: descriptor.logicalHeightPoints, rotation: descriptor.rotation,
                    selectedDisplayID: displayID,
                    visibleMenuAppGeneration: menuGeneration, visibleMenuAppRevision: 1))
            return InteractiveNativeVideoEnrollmentCoordinatorV0(authority: authority, backend: backend,
                readAuthority: { await source.current }, monotonicMilliseconds: { DispatchTime.now().uptimeNanoseconds / 1_000_000 },
                unixMilliseconds: { UInt64(Date().timeIntervalSince1970 * 1000) })
        }
        let unacknowledged = try await makeOwner(acknowledged: false)
        do {
            _ = try await unacknowledged.prepare(clientCertificateDER: nativeClientDER)
            throw NSError(domain: "ManagedHostProbe", code: 5, userInfo: [NSLocalizedDescriptionKey: "Unacknowledged Desktop admitted"])
        } catch {
            await unacknowledged.retire()
            if (error as NSError).domain == "ManagedHostProbe" { throw error }
        }
        let owner = try await makeOwner()
        do {
            let challenge = try await owner.prepare(clientCertificateDER: nativeClientDER)
            let managed = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("managed-") }!
            try require(!FileManager.default.fileExists(atPath: managed.appendingPathComponent("state.json").path), "Registration before proof")
            let clientAuthority = try ClientNativeVideoAttestationAuthorityV0(binding: b, surface: surface, sessionPublicKeyX963: key.publicKey.x963Representation)
            let client = try ClientNativeVideoAttestationOwnerV0(authority: clientAuthority,
                clientCertificateDER: nativeClientDER, signer: ProbeSessionSigner(key: key),
                readAuthority: { await source.current == authority ? clientAuthority : nil },
                validateCertificate: { SecCertificateCreateWithData(nil, $0 as CFData) != nil },
                monotonicMilliseconds: { DispatchTime.now().uptimeNanoseconds / 1_000_000 })
            let endpoint = try await owner.activate(rawSignature: client.attest(challenge))
            try require(endpoint.portBase == 58989, "Unexpected endpoint")
            let curl = URL(fileURLWithPath: "/usr/bin/curl")
            _ = try nativeTLS.bindAddress(peerAddress, portBase: endpoint.portBase, hostCertificateDER: challenge.hostCertificateDER)
            let response = try nativeTLS.requestPath("/serverinfo?uniqueid=probe")
            try require(String(data: response, encoding: .utf8)?.contains("<PairStatus>1</PairStatus>") == true,
                        "In-memory native identity rejected")
            let apps = try nativeTLS.requestPath("/applist?uniqueid=probe")
            let appList = try NativeLaunchXML.parse(apps)
            try require(appList.apps.count == 1 && appList.apps[0]["AppTitle"] == "Desktop", "Native Desktop inventory unavailable")
            guard let appID = appList.apps[0]["ID"].flatMap(UInt32.init), appID > 0 else { throw NativeLaunchFailure.invalidResponse }
            let streamKey = NSMutableData(length: 16)!
            defer { streamKey.resetBytes(in: NSRange(location: 0, length: streamKey.length)) }
            try require(SecRandomCopyBytes(kSecRandomDefault, 16, streamKey.mutableBytes) == errSecSuccess, "Stream material generation")
            var keyID: UInt32 = 0
            try require(SecRandomCopyBytes(kSecRandomDefault, MemoryLayout.size(ofValue: keyID), &keyID) == errSecSuccess, "Stream material generation")
            let hex = (streamKey as Data).map { String(format: "%02x", $0) }.joined()
            let launchPath = "/launch?uniqueid=\(b.interactiveSessionID.uuidString)&appid=\(appID)&mode=\(surface.encodedWidth)x\(surface.encodedHeight)x60&additionalStates=1&sops=0&rikey=\(hex)&rikeyid=\(Int32(bitPattern: keyID))&localAudioPlayMode=0&surroundAudioInfo=196610&remoteControllersBitmap=0&gcmap=0&gcpersist=0&corever=1"
            let wrongMode = "\(surface.encodedWidth + 2)x\(surface.encodedHeight)x60"
            let deniedPath = launchPath.replacingOccurrences(of: "mode=\(surface.encodedWidth)x\(surface.encodedHeight)x60", with: "mode=" + wrongMode)
            let denied = try nativeTLS.requestPath(deniedPath)
            try require(String(data: denied, encoding: .utf8)?.contains("status_code=\"400\"") == true,
                        "Different native launch mode admitted")
            for downgrade in [launchPath.replacingOccurrences(of: "&corever=1", with: ""),
                              launchPath.replacingOccurrences(of: "&corever=1", with: "&corever=0")] {
                let response = String(data: try nativeTLS.requestPath(downgrade), encoding: .utf8)
                try require(response?.contains("status_code=\"403\"") == true &&
                            response?.contains("<gamesession>0</gamesession>") == true,
                            "Unencrypted RTSP launch admitted")
            }
            let launch = try NativeLaunchXML.parse(nativeTLS.requestPath(launchPath))
            try require(launch.fields["gamesession"] == "1", "Native launch rejected")
            guard let streamURL = launch.fields["sessionUrl0"],
                  NativeLaunchValidationV0.validStreamURL(streamURL, address: peerAddress, port: Int(endpoint.portBase) + 21) else {
                throw NativeLaunchFailure.invalidRoute
            }
            // A socket may see the pending launch, but it must prove possession
            // of that launch's key before any RTSP command can be dispatched.
            let socketFD = socket(AF_INET, SOCK_STREAM, 0)
            try require(socketFD >= 0, "RTSP downgrade socket unavailable")
            do {
                defer { close(socketFD) }
                var timeout = timeval(tv_sec: 2, tv_usec: 0)
                try require(setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, &timeout,
                            socklen_t(MemoryLayout<timeval>.size)) == 0, "RTSP timeout unavailable")
                var noSignal: Int32 = 1
                try require(setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &noSignal,
                            socklen_t(MemoryLayout<Int32>.size)) == 0, "RTSP signal guard unavailable")
                var peer = sockaddr_in()
                peer.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                peer.sin_family = sa_family_t(AF_INET)
                peer.sin_port = UInt16(Int(endpoint.portBase) + 21).bigEndian
                peer.sin_addr.s_addr = inet_addr(peerAddress)
                let connected = withUnsafePointer(to: &peer) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        connect(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                try require(connected == 0, "RTSP downgrade connection failed")
                let plaintext = Data("OPTIONS rtsp://\(peerAddress)/ RTSP/1.0\r\nCSeq: 1\r\n\r\n".utf8)
                let sent = plaintext.withUnsafeBytes { send(socketFD, $0.baseAddress, $0.count, 0) }
                try require(sent == plaintext.count, "RTSP downgrade request failed")
                var response = [UInt8](repeating: 0, count: 1024)
                var totalReceived = 0
                while true {
                    let received = response.withUnsafeMutableBytes { recv(socketFD, $0.baseAddress, $0.count, 0) }
                    let receiveError = errno
                    if received == 0 || (received < 0 && receiveError == ECONNRESET) { break }
                    try require(received > 0 && totalReceived + received <= 4096,
                                "Plaintext RTSP connection was not closed")
                    // Upstream sends an encrypted error before closing. No
                    // plaintext RTSP response or unbounded stream is allowed.
                    if totalReceived == 0 {
                        try require(response[0] & 0x80 != 0, "Plaintext RTSP response received")
                    }
                    totalReceived += received
                }
            }
            for path in ["/pair", "/resume", "/appasset"] {
                let denial = try nativeTLS.requestPath(path + "?uniqueid=probe")
                try require(String(data: denial, encoding: .utf8)?.contains("status_code=\"404\"") == true,
                            "Forbidden native route available")
            }
            // Bounded local checks while the admitted HTTPS server is live.
            for port in [58989, 58990] {
                let status = try command(curl, ["--silent", "--max-time", "1", "--noproxy", "*",
                    "http://\(peerAddress):\(port)/"])
                try require(status == 7, "Unwanted management or HTTP listener")
            }
            for name in ["other"] {
                let output = dir.appendingPathComponent("response.xml")
                let status = try command(curl, ["--silent", "--show-error", "--max-time", "3",
                    "--cacert", managed.appendingPathComponent("cert.pem").path,
                    "--cert", dir.appendingPathComponent(name + ".pem").path, "--key", dir.appendingPathComponent(name + ".key").path,
                    "--noproxy", "*", "--connect-to", "::\(peerAddress):58984", "https://localhost:58984/serverinfo?uniqueid=probe"], output: output)
                try require(status == 0, "HTTPS probe failed")
                let xml = try String(contentsOf: output, encoding: .utf8)
                try require(xml.contains("401"), "Certificate admission mismatch")
            }
            // A conflicting owned launch must not return the first server's
            // endpoint merely because that port is already listening.
            let conflicting = try await makeOwner()
            do {
                let proof = try await conflicting.prepare(clientCertificateDER: nativeClientDER)
                _ = try await conflicting.activate(rawSignature: key.signature(for: proof.signingInput).rawRepresentation)
                await conflicting.retire()
                throw NSError(domain: "ManagedHostProbe", code: 2, userInfo: [NSLocalizedDescriptionKey: "Port conflict admitted"])
            } catch {
                await conflicting.retire()
                if (error as NSError).domain == "ManagedHostProbe" { throw error }
            }
            let invalid = try await makeOwner()
            do {
                _ = try await invalid.prepare(clientCertificateDER: Data([0, 1, 2]))
                throw NSError(domain: "ManagedHostProbe", code: 3, userInfo: [NSLocalizedDescriptionKey: "Malformed certificate admitted"])
            } catch {
                await invalid.retire()
                if (error as NSError).domain == "ManagedHostProbe" { throw error }
            }
            let badProof = try await makeOwner()
            _ = try await badProof.prepare(clientCertificateDER: nativeClientDER)
            do {
                _ = try await badProof.activate(rawSignature: Data([0]))
                throw NSError(domain: "ManagedHostProbe", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid proof admitted"])
            } catch {
                await badProof.retire()
                if (error as NSError).domain == "ManagedHostProbe" { throw error }
            }
            let remaining = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("managed-") }
            try require(remaining == [managed], "Rejected operation retained credentials")
            // Revoke the actual menu runtime while primary authority remains
            // otherwise current. Its watchdog must independently retire the host.
            guard let activeRuntime = source.runtimes.dropFirst().first else { throw LocalInteractiveNativeBackendErrorV1.unavailable }
            try await activeRuntime.invalidateAgentAuthority()
            let stopDeadline = ContinuousClock.now + .seconds(3)
            while FileManager.default.fileExists(atPath: managed.path), ContinuousClock.now < stopDeadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            try require(!FileManager.default.fileExists(atPath: managed.path), "Menu Stop did not retire host")
            source.current = nil
            _ = await owner.refreshAuthority()
            try require(await owner.phase == .retired, "Revocation did not retire")
            try require(!FileManager.default.fileExists(atPath: managed.path), "Private credentials survived retirement")
            for port in [Int(endpoint.portBase) - 5, Int(endpoint.portBase) + 21] {
                let status = try command(curl, ["--silent", "--max-time", "1", "--noproxy", "*",
                    "http://\(peerAddress):\(port)/"])
                try require(status == 7, "Native network listener survived retirement")
            }
            for runtime in source.runtimes { try await runtime.invalidateAgentAuthority() }
            print("Managed host probe passed: proof before registration; exact certificate accepted; other certificate rejected; port conflict, malformed certificate and invalid proof rejected; revocation stopped host and removed private state.")
        } catch {
            await owner.retire()
            for runtime in source.runtimes { try? await runtime.invalidateAgentAuthority() }
            throw error
        }
    }
}
