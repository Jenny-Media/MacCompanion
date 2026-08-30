#if !DEBUG || !os(macOS)
#error("Simulator administration bridge is macOS Debug-only")
#endif
import CompanionIPC
import CompanionLocalXPCPlatform
import CompanionNativeProviders
import CompanionWire
import Foundation
import LiveControlLabSupport
import Network

/// Test-only local consent driver, not a remote product administration API.
/// A private per-run bearer token protects a loopback-only, bounded command
/// channel. All actual pairing and grant changes traverse signed local XPC.
@available(macOS 26.0, *)
actor ProbeSimulatorMenu {
    let menu: MacLocalXPCClientV1
    let surfaces: ProbePresentationSurface
    let interactive: ProbeInteractiveMenu
    let status: @Sendable () async throws -> LocalAgentStatusSnapshot
    let emit: @Sendable (String) -> Void
    private var fixture = LabFixture(source: "signed-agent")
    private var deviceID: UUID?
    private var decision: Task<Void, Error>?
    private var active: LabConnection?
    private var reportedMedia = false
    private var reportedInput = false
    private var reportedStop = false

    init(menu: MacLocalXPCClientV1, surfaces: ProbePresentationSurface,
         interactive: ProbeInteractiveMenu,
         status: @escaping @Sendable () async throws -> LocalAgentStatusSnapshot,
         emit: @escaping @Sendable (String) -> Void) {
        self.menu = menu; self.surfaces = surfaces; self.interactive = interactive
        self.status = status; self.emit = emit
    }

    static func run(testID: UUID, menu: MacLocalXPCClientV1, surfaces: ProbePresentationSurface,
                    interactive: ProbeInteractiveMenu,
                    status: @escaping @Sendable () async throws -> LocalAgentStatusSnapshot,
                    emit: @escaping @Sendable (String) -> Void) async throws {
        let directory = URL(fileURLWithPath: "/private/tmp/maccompanion-agent-xpc-\(testID.uuidString.lowercased())")
        let canonical = realpath(directory.path, nil)
        defer { free(canonical) }
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard canonical.map({ String(cString: $0) }) == directory.path,
              attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw LabError.unauthorized }
        let driver = ProbeSimulatorMenu(menu: menu, surfaces: surfaces,
            interactive: interactive, status: status, emit: emit)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let (states, continuation) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        listener.stateUpdateHandler = { state in
            if case .ready = state { continuation.yield(true) }
            if case .failed = state { continuation.yield(false); continuation.finish() }
            if case .cancelled = state { continuation.finish() }
        }
        listener.newConnectionHandler = { connection in Task { await driver.accept(connection) } }
        listener.start(queue: DispatchQueue(label: "Probe.simulator.loopback"))
        defer { listener.cancel(); continuation.finish() }
        for await ready in states {
            guard ready, let port = listener.port else { throw LabError.closed }
            try await driver.publishFixture(port: port.rawValue, directory: directory)
            emit("signed-simulator-menu-ready")
        }
    }

    private func publishFixture(port: UInt16, directory: URL) throws {
        fixture.port = port
        fixture.journeyPort = 59_654
        let file = directory.appendingPathComponent("simulator-fixture.json")
        try JSONEncoder().encode(fixture).write(to: file, options: .withoutOverwriting)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private func accept(_ socket: NWConnection) async {
        // One administrative caller at a time, including incomplete handshakes.
        guard active == nil else { socket.cancel(); return }
        let connection = LabConnection(socket)
        active = connection
        let deadline = Task {
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            await connection.close()
        }
        defer { deadline.cancel(); active = nil }
        do {
            try await connection.start()
            let hello = try JSONDecoder().decode(LabHello.self, from: await connection.readFrame())
            guard hello.token == fixture.token, hello.role == "control", hello.connectionID == nil else { throw LabError.unauthorized }
            try await connection.sendFrame(Data("ready".utf8))
            let request = try JSONDecoder().decode(LabCommand.self, from: await connection.readFrame())
            let report = try await command(request.action)
            try await connection.sendFrame(JSONEncoder().encode(report))
        } catch { emit("signed-simulator-command-rejected") }
        await connection.close()
    }

    private func command(_ action: String) async throws -> JourneyReport {
        var qr: String?
        switch action {
        case "journey-pair":
            guard deviceID == nil, decision == nil else { throw LabError.unauthorized }
            let receipt = try await menu.createPairingSession(.init(commandID: UUID()))
            qr = receipt.encodedQRCode
            decision = Task { try await self.approvePairing() }
        case "journey-grant-act":
            guard let deviceID else { throw LabError.unauthorized }
            let review = try await menu.makeCapabilityGrantReview(.init(commandID: UUID(), deviceID: deviceID,
                capabilityID: NativeAudioMuteCapabilityV1.capabilityID, requestedAtUnixMilliseconds: ProbePairingClient.wall()))
            guard review.currentGrantIDs.isEmpty,
                  try review.descriptor.domainValue() == NativeAudioMuteCapabilityV1.descriptor() else { throw LabError.unauthorized }
            let receipt = try await menu.decideCapabilityGrant(review.command(commandID: UUID(), decision: .approve,
                decidedAtUnixMilliseconds: ProbePairingClient.wall()))
            guard receipt.storedGrantIDs == [NativeAudioMuteCapabilityV1.capabilityID] else { throw LabError.unauthorized }
            emit("signed-simulator-act-granted")
        case "journey-grant-control":
            guard deviceID != nil else { throw LabError.unauthorized }
            let review = try await menu.makeInteractiveControlGrantReview(.init(
                commandID: UUID(), requestedAtUnixMilliseconds: ProbePairingClient.wall()))
            guard review.currentGrantIDs == [NativeAudioMuteCapabilityV1.capabilityID] else {
                throw LabError.unauthorized
            }
            let receipt = try await menu.decideInteractiveControlGrant(
                review.makeDecisionCommand(commandID: UUID(), decision: .approve,
                    decidedAtUnixMilliseconds: ProbePairingClient.wall()))
            guard Set(receipt.storedGrantIDs) == Set([
                NativeAudioMuteCapabilityV1.capabilityID,
                InteractiveControlDurableGrantV0.identifier
            ]) else { throw LabError.unauthorized }
            let admission = try LocalInteractiveAdmissionPublicationV1(commandID: UUID(),
                menuAppGeneration: interactive.effects.menuGeneration, revision: 1,
                selectedDisplayID: interactive.effects.displayID)
            try (await menu.publishInteractiveAdmission(admission)).validate(against: admission)
            emit("signed-simulator-control-granted")
        case "journey-status": break
        default: throw LabError.unsupported
        }
        let snapshot = try await status()
        guard snapshot.networkState == .listening else { throw LabError.unauthorized }
        if action == "journey-grant-control" {
            guard snapshot.interactiveControlGranted else { throw LabError.unauthorized }
        }
        let runtime = await interactive.simulatorSnapshot()
        if runtime.captureActive, runtime.encodedFrames > 0, !reportedMedia {
            reportedMedia = true
            emit("signed-simulator-control-media-active")
        }
        if runtime.inputEvents > 0, !reportedInput {
            reportedInput = true
            emit("signed-simulator-control-input-observed")
        }
        if reportedMedia, !runtime.captureActive, runtime.runtimeIdle,
           runtime.queuedRecords == 0, !reportedStop {
            reportedStop = true
            emit("signed-simulator-control-stop-clean")
        }
        var control = LabStatus()
        control.source = "signed-agent"
        control.inputEvents = runtime.inputEvents
        control.captureActive = runtime.captureActive
        control.mediaRecords = runtime.encodedFrames
        control.runtimeIdle = runtime.runtimeIdle
        control.queuedMediaRecords = runtime.queuedRecords
        control.acknowledgements = runtime.acknowledgements
        return JourneyReport(qr: qr, pairedDevices: Int(snapshot.pairedDeviceCount),
            tlsConnections: 0, authentications: 0, observations: 0, control: control)
    }

    private func approvePairing() async throws {
        guard case let .presented(review) = try await surfaces.next(),
              review.clientID == fixture.clientID else { throw LabError.unauthorized }
        let command = try LocalPairingDecisionCommandV0(commandID: UUID(), review: review,
            deviceDisplayName: .init("Signed Simulator client"), decision: .approve,
            decidedAtUnixMilliseconds: ProbePairingClient.wall())
        let receipt = try await menu.resolveLocalApproval(command)
        try receipt.validate(against: command)
        guard let deviceID = receipt.deviceID else { throw LabError.unauthorized }
        self.deviceID = deviceID
        emit("signed-simulator-pairing-approved")
    }
}
