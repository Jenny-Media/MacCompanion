#if !DEBUG || !os(macOS)
#error("Disposable Agent/XPC integration executable is macOS Debug only")
#endif
@testable import CompanionAgentApplicationPlatform
import CompanionIPC
import CompanionLocalXPCPlatform
import CompanionWire
import Dispatch
import Foundation

private func emit(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

private enum ProbeError: Error { case arguments, timeout, unexpectedEvent, invalidSnapshot }

private final class Events<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Value] = []
    func append(_ value: Value) { lock.withLock { values.append(value) } }
    func next() async throws -> Value {
        let deadline = ContinuousClock.now + .seconds(12)
        while ContinuousClock.now < deadline {
            if let value = lock.withLock({ values.isEmpty ? nil : values.removeFirst() }) {
                return value
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ProbeError.timeout
    }
    var isEmpty: Bool { lock.withLock { values.isEmpty } }
}

private actor StatusReader: MacLocalXPCStatusReadingV1 {
    let mode: String
    var sequence: UInt64 = 0
    init(mode: String) { self.mode = mode }
    func readStatus() async -> Result<LocalAgentStatusSnapshot, MacLocalXPCStatusReadErrorV1> {
        sequence += 1
        let value = sequence
        emit("status-read-started")
        if mode == "slow" {
            // Deliberately ignore cancellation and deliver a late completion.
            await Task.detached { try? await Task.sleep(for: .seconds(3)) }.value
            emit("late-status-returned")
        }
        if mode == "unavailable" { return .failure(.sourceUnavailable) }
        do {
            return .success(try LocalAgentStatusSnapshot(
                desiredEnabled: true, consoleSession: .otherConsoleUserActive,
                agentProcess: .ready, menuAppProcess: .ready,
                networkState: .stopped, securityPosture: .nominal,
                routeKinds: [], pairedDeviceCount: 0, activeRemoteSessionCount: 0,
                providerCount: 0, warningCodes: [], diagnosticSequence: value,
                generatedAtUnixMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)))
        } catch { return .failure(.sourceUnavailable) }
    }
}

@available(macOS 26.0, *)
@main private enum AgentXPCProbe {
    static func main() async {
        emit("probe-entered")
        do {
            let args = CommandLine.arguments
            guard args.count == 4, let testID = UUID(uuidString: args[2]) else {
                throw ProbeError.arguments
            }
            switch args[1] {
            case "server": try await server(testID: testID, mode: args[3])
            case "client": try await client(testID: testID, mode: args[3])
            case "bootstrap": try await bootstrap(testID: testID, mode: args[3])
            default: throw ProbeError.arguments
            }
        } catch {
            // Only closed error types/cases: no payload, identifiers, or user data.
            emit("failure:\(error)")
            exit(1)
        }
    }

    static func server(testID: UUID, mode: String) async throws {
        let startupMode = (mode == "productionPaired" || mode == "productionInteractive" || mode == "productionActPaused") ? .productionPresentation
            : MacCompanionAgentIsolatedStartupTestV1.Mode(rawValue: mode) ?? .durableIntent
        let finishes = Events<Bool>()
        let (signals, continuation) = AsyncStream<Void>.makeStream()
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
        source.setEventHandler { continuation.yield(()) }
        source.resume()
        defer { source.cancel(); continuation.finish() }
        let outcome: MacCompanionAgentLocalServiceStartupOutcomeV1
        do {
            emit("startup-preparing")
            outcome = try await MacCompanionAgentIsolatedStartupTestV1.start(
                testID: testID, mode: startupMode, statusReader: StatusReader(mode: mode),
                primaryInputs: { storage, state, store in
                    try await ProbePrimaryInputs.make(storage: storage, state: state, store: store,
                        pauseAudioResult: mode == "productionActPaused")
                },
                presentationReview: mode == "productionPresentation" ? try probePresentationReview(testID: testID) : nil,
                activeTestSession: mode == "productionInteractive" || mode == "productionActPaused",
                onPhase: emit,
                onEvent: { event in
                    switch event {
                    case .authenticatedMenu: emit("authenticated-menu")
                    case .menuReady: emit("menu-ready")
                    case .invalidatedMenu: emit("invalidated-menu")
                    case .remoteAccessEnabled: emit("remote-access-enabled")
                    }
                },
                onFinish: { finishes.append(true); emit("prepared-finished") })
        } catch {
            switch startupMode {
            case .preparationFailure:
                guard error is MacCompanionAgentIsolatedStartupTestV1.Failure else { throw error }
            case .invalidRevision:
                guard String(describing: error) == "unsafeInitialLifecycleState", !finishes.isEmpty else { throw error }
            case .listenerFailure:
                guard error as? MacLocalXPCConstructionErrorV1 == .invalidAgentBuild, !finishes.isEmpty else { throw error }
            default: throw error
            }
            emit("startup-failed-closed")
            return
        }
        if case .retryAfterFirstUnlock = outcome {
            guard startupMode == .firstUnlock, finishes.isEmpty else { throw ProbeError.unexpectedEvent }
            emit("first-unlock-deferred")
            return
        }
        guard case let .running(owner) = outcome else { throw ProbeError.unexpectedEvent }
        let restart = Task {
            await owner.waitForRestartRequest()
            emit("restart-requested")
        }
        // restart's waiter is intentionally process-owned, just like the Agent.
        defer { restart.cancel() }
        emit("service-running")
        for await _ in signals { break }
        async let a: Void = owner.finish()
        async let b: Void = owner.finish()
        _ = await (a, b)
        _ = try await finishes.next()
        guard finishes.isEmpty else { throw ProbeError.unexpectedEvent }
        emit("service-finished")
    }

    static func bootstrap(testID: UUID, mode: String) async throws {
        let events = Events<MacLocalXPCRemoteAccessBootstrapClientEventV1>()
        let client = MacLocalXPCRemoteAccessBootstrapClientV1(isolatedTestID: testID, onEvent: events.append)
        defer { client.cancel() }
        try client.start()
        guard case .authenticatedAgent = try await events.next() else { throw ProbeError.unexpectedEvent }
        client.readOffer()
        if mode == "denied" {
            guard case .invalidated = try await events.next() else { throw ProbeError.unexpectedEvent }
            emit("bootstrap-rejected")
            return
        }
        guard case let .offer(_, offer) = try await events.next(), offer.expectedIntentRevision == 0 else {
            throw ProbeError.unexpectedEvent
        }
        let command = try LocalRemoteAccessEnableCommandV0(
            commandID: UUID(), offer: offer,
            confirmedAtUnixMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000))
        client.enable(command)
        guard case let .enabled(_, receipt) = try await events.next(),
              receipt.correlationID == command.commandID,
              receipt.offerID == offer.offerID, receipt.intentRevision == 1 else {
            throw ProbeError.unexpectedEvent
        }
        emit("enabled-receipt-verified")
    }

    static func client(testID: UUID, mode: String) async throws {
        let events = Events<MacLocalXPCClientEventV1>()
        let surfaces = ProbePresentationSurface()
        let nativeSimulator = mode.hasPrefix("presentation-native-simulator")
        let interactive = mode == "presentation-simulator" || nativeSimulator
            ? try ProbeInteractiveMenu(scenario: nativeSimulator ? (mode.hasSuffix("-continuous") ? .nativeContinuous : .native) : .simulator)
            : mode.hasPrefix("presentation-control")
            ? try ProbeInteractiveMenu(scenario: mode == "presentation-control-native" ? .native : mode == "presentation-control-admission-race" ? .admissionRace
                : mode == "presentation-control-menu-loss" ? .menuLoss
                : mode == "presentation-control-revoke" ? .revoke
                : mode == "presentation-control-revocation-race" ? .revocationRace : .lifecycle) : nil
        let revocationReviewOnly = mode == "presentation-revocation-review"
        let revocationReplay = mode == "presentation-revocation-replay"
        let receive: @Sendable (MacLocalXPCClientEventV1) -> Void = { event in
            events.append(event)
            if case .invalidated = event { emit("local-xpc-invalidated") }
        }
        let client = mode.hasPrefix("presentation")
            ? MacLocalXPCClientV1(isolatedTestID: testID, pairingReviews: surfaces,
                hostIdentityRecovery: surfaces, interactiveLeaseHandler: interactive?.leaseHandler,
                interactiveInputHandler: interactive?.adapter, onEvent: receive)
            : MacLocalXPCClientV1(isolatedTestID: testID, onEvent: receive)
        var simulatorMediaDrain: Task<Void, Never>?
        defer { simulatorMediaDrain?.cancel(); client.cancel() }
        do { try client.start() } catch {
            // Only absent service/failed activation is an expected start failure.
            if mode == "absent", error as? MacLocalXPCConstructionErrorV1 == .activation {
                emit("connection-rejected"); return
            }
            throw error
        }
        let first = try await events.next()
        if mode == "reject" || mode == "absent" {
            guard first == .invalidated else { throw ProbeError.unexpectedEvent }
            emit("connection-rejected")
            return
        }
        guard first == .authenticatedAgent(build: 1) else { throw ProbeError.unexpectedEvent }
        emit("authenticated-agent")
        if mode == "before-ready" {
            client.readAgentStatus()
            guard try await events.next() == .invalidated else { throw ProbeError.unexpectedEvent }
            emit("pre-readiness-rejected")
            return
        }
        client.publishMenuReady()
        if mode == "denied-ready" {
            guard try await events.next() == .invalidated else { throw ProbeError.unexpectedEvent }
            emit("readiness-rejected")
            return
        }
        guard try await events.next() == .menuReadyAcknowledged else { throw ProbeError.unexpectedEvent }
        if mode == "presentation-wait-listener" {
            let deadline = ContinuousClock.now + .seconds(8)
            while ContinuousClock.now < deadline {
                client.readAgentStatus()
                let status = try await events.next()
                if case let .agentStatus(_, snapshot) = status, snapshot.networkState == .listening {
                    emit("production-listener-readiness-verified")
                    return
                }
                guard case .agentStatus = status else { throw ProbeError.unexpectedEvent }
                try await Task.sleep(for: .milliseconds(50))
            }
            throw ProbeError.timeout
        }
        if mode == "presentation-simulator" || nativeSimulator || mode == "presentation-control-native" {
            guard let interactive else { throw ProbeError.unexpectedEvent }
            // Debug-only equivalent of the shipping one-record-at-a-time menu
            // drain. Every record still crosses the signed local-XPC method
            // and waits for its exact acknowledgement before the next dequeue.
            simulatorMediaDrain = Task {
                while !Task.isCancelled {
                    if let record = interactive.mediaQueue.dequeue() {
                        do {
                            try await client.publishInteractiveMedia(
                                header: record.header, payload: record.payload)
                        } catch let error as MacLocalXPCInteractiveRoleDataErrorV1 {
                            emit("signed-simulator-media-drain-failed-\(String(describing: error))")
                            return
                        } catch {
                            emit("signed-simulator-media-drain-failed-other")
                            return
                        }
                    } else {
                        try? await Task.sleep(for: .milliseconds(3))
                    }
                }
            }
        }
        if mode == "presentation-simulator" || nativeSimulator {
            guard let interactive else { throw ProbeError.unexpectedEvent }
            try await ProbeSimulatorMenu.run(testID: testID, menu: client, surfaces: surfaces,
                interactive: interactive,
                status: {
                    client.readAgentStatus()
                    guard case let .agentStatus(_, snapshot) = try await events.next() else {
                        throw ProbeError.invalidSnapshot
                    }
                    return snapshot
                }, emit: emit)
            return
        }
        if mode == "presentation" {
            try await presentation(client: client, surfaces: surfaces, testID: testID)
        }
        if mode == "presentation-abandon" || mode == "presentation-recover-qr" {
            let receipt = try await client.createPairingSession(.init(commandID: UUID()))
            if mode == "presentation-recover-qr" {
                _ = try await client.dismissPairingSession(.init(commandID: UUID(), pairingID: receipt.pairingID))
                emit("replacement-menu-qr-verified")
            } else {
                emit("outstanding-qr-created")
            }
            return
        }
        if mode == "presentation-pair" || mode == "presentation-reconnect" || interactive != nil || revocationReviewOnly || revocationReplay || mode.hasPrefix("presentation-act") {
            try await ProbePairingClient.run(testID: testID, menu: client, surfaces: surfaces,
                create: mode == "presentation-pair" || interactive?.scenario == .revocationRace, interactive: interactive,
                revocationReviewOnly: revocationReviewOnly, revocationReplay: revocationReplay,
                act: mode == "presentation-act", actReplay: mode == "presentation-act-replay",
                actDenial: mode == "presentation-act-denial",
                actFault: mode.hasPrefix("presentation-act-fault-") ? String(mode.dropFirst("presentation-act-fault-".count)) : nil,
                emit: emit)
            if mode == "presentation-act-fault-interrupt" { return }
            if interactive?.scenario == .menuLoss { return }
            let revoked = interactive?.scenario == .revoke || interactive?.scenario == .revocationRace || revocationReplay
            client.readAgentStatus()
            guard case let .agentStatus(_, snapshot) = try await events.next(),
                  snapshot.pairedDeviceCount == (revoked ? 0 : 1),
                  snapshot.interactiveControlGranted == (!revoked && (interactive != nil || revocationReviewOnly)),
                  snapshot.networkState == .listening else { throw ProbeError.invalidSnapshot }
            emit("paired-agent-status-verified")
            return
        }
        if mode == "duplicate-ready" {
            client.publishMenuReady()
            guard try await events.next() == .invalidated else { throw ProbeError.unexpectedEvent }
            emit("duplicate-readiness-rejected")
            return
        }
        if mode == "wait-invalidation" {
            emit("waiting-for-invalidation")
            guard try await events.next() == .invalidated else { throw ProbeError.unexpectedEvent }
            emit("peer-loss-observed")
            return
        }
        var lastSequence: UInt64 = 0
        var sawReadyLifecycle = false
        for _ in 0..<3 {
            client.readAgentStatus()
            let event = try await events.next()
            if mode == "pending-death" || mode == "timeout" {
                guard event == .invalidated else { throw ProbeError.unexpectedEvent }
                // A deliberately late read must never revive the old generation.
                try await Task.sleep(for: .seconds(2))
                guard events.isEmpty else { throw ProbeError.unexpectedEvent }
                emit("pending-read-failed-closed")
                return
            }
            if mode == "unavailable" {
                guard case .agentStatusUnavailable = event else { throw ProbeError.unexpectedEvent }
                continue
            }
            guard case let .agentStatus(_, snapshot) = event,
                  snapshot.desiredEnabled,
                  snapshot.networkState == (mode == "presentation" ? .listening : .stopped),
                  snapshot.routeKinds.isEmpty, snapshot.pairedDeviceCount == 0,
                  !snapshot.interactiveControlGranted, snapshot.activeRemoteSessionCount == 0,
                  snapshot.diagnosticSequence > lastSequence else { throw ProbeError.invalidSnapshot }
            lastSequence = snapshot.diagnosticSequence
            sawReadyLifecycle = snapshot.agentProcess == .ready && snapshot.menuAppProcess == .ready
        }
        if mode == "production" {
            // Transport acknowledgement and lifecycle publication are distinct
            // events. Wait for the actual owner, never substitute a ready flag.
            let deadline = ContinuousClock.now + .seconds(5)
            while !sawReadyLifecycle, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
                client.readAgentStatus()
                guard case let .agentStatus(_, snapshot) = try await events.next(),
                      snapshot.desiredEnabled, snapshot.networkState == .stopped,
                      snapshot.routeKinds.isEmpty, snapshot.pairedDeviceCount == 0,
                      snapshot.activeRemoteSessionCount == 0, !snapshot.interactiveControlGranted,
                      snapshot.diagnosticSequence > lastSequence else { throw ProbeError.invalidSnapshot }
                lastSequence = snapshot.diagnosticSequence
                sawReadyLifecycle = snapshot.agentProcess == .ready && snapshot.menuAppProcess == .ready
            }
            guard sawReadyLifecycle else { throw ProbeError.invalidSnapshot }
            emit("production-lifecycle-status-verified")
        }
        emit(mode == "unavailable" ? "unavailable-status-verified" : "status-verified")
        if mode == "reconnect" {
            client.cancel()
            // Explicit cancellation is silent; only unexpected peer loss emits
            // invalidated. Late callbacks from that lifetime must stay fenced.
            guard events.isEmpty else { throw ProbeError.unexpectedEvent }
            try client.start()
            guard try await events.next() == .authenticatedAgent(build: 1) else { throw ProbeError.unexpectedEvent }
            client.publishMenuReady()
            guard try await events.next() == .menuReadyAcknowledged else { throw ProbeError.unexpectedEvent }
            client.readAgentStatus()
            guard case let .agentStatus(_, snapshot) = try await events.next(),
                  snapshot.diagnosticSequence > lastSequence else { throw ProbeError.unexpectedEvent }
            emit("reconnect-verified")
        }
    }

    static func presentation(client: MacLocalXPCClientV1, surfaces: ProbePresentationSurface, testID: UUID) async throws {
        guard case let .presented(review) = try await surfaces.next(),
              review.reviewID == testID, review.pairingID == testID, review.clientID == testID,
              review.authenticationString.rawValue == "ABC-123",
              review.sessionPublicKeyFingerprint.rawValue == Data(repeating: 1, count: 32),
              review.approvalPublicKeyFingerprint.rawValue == Data(repeating: 2, count: 32),
              review.transcriptDigest.rawValue == Data(repeating: 3, count: 32),
              review.expectedPolicyRevision.rawValue == 1,
              review.expiresAtUnixMilliseconds > Int64(Date().timeIntervalSince1970 * 1_000),
              try await surfaces.next() == .withdrawn(testID), await surfaces.isEmpty else {
            throw ProbeError.unexpectedEvent
        }
        emit("presentation-delivery-idempotence-verified")

        let create = try LocalPairingSessionCreateCommandV0(commandID: UUID())
        let first = try await client.createPairingSession(create)
        let duplicate = try await client.createPairingSession(create)
        guard first == duplicate else { throw ProbeError.unexpectedEvent }
        let qr = try PairingQRCodeCodec.decode(first.encodedQRCode,
            nowUnixMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000))
        guard qr.pairingID.rawValue == first.pairingID,
              qr.endpoints.count == 1,
              qr.endpoints.allSatisfy({ $0.kind == .ipv4 && $0.value == "127.0.0.1" && $0.port == 59_654 }) else {
            throw ProbeError.unexpectedEvent
        }
        let dismiss = try LocalPairingSessionDismissCommandV0(commandID: UUID(), pairingID: first.pairingID)
        let dismissed = try await client.dismissPairingSession(dismiss)
        guard try await client.dismissPairingSession(dismiss) == dismissed else { throw ProbeError.unexpectedEvent }
        let next = try await client.createPairingSession(.init(commandID: UUID()))
        guard next.pairingID != first.pairingID else { throw ProbeError.unexpectedEvent }
        _ = try await client.dismissPairingSession(.init(commandID: UUID(), pairingID: next.pairingID))
        emit("pairing-create-dismiss-retry-verified")

        do {
            _ = try await client.makeInteractiveControlGrantReview(.init(commandID: UUID(),
                requestedAtUnixMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)))
            throw ProbeError.unexpectedEvent
        } catch MacLocalXPCMenuPairingCommandErrorV1.commandFailed {
            emit("grant-without-device-rejected")
        }
    }
}
