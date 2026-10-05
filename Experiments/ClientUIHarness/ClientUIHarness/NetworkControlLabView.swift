#if !DEBUG || !targetEnvironment(simulator)
#error("Network Control Lab is Simulator Debug-only")
#endif
@testable import CompanionClient
@testable import CompanionClientNetworkPlatform
import CompanionClientPlatform
import CompanionClientUI
import CompanionDiscovery
import CompanionInteractiveClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionPresentation
import CompanionTransport
import CompanionWire
import CryptoKit
import Foundation
import LiveControlLabSupport
import SwiftUI
import UIKit

private struct LabApprovalSigner: ClientInteractiveApprovalSigningV0 {
    let key: Data
    func signSessionChallenge(_ input: Data) async throws -> Data {
        try P256.Signing.PrivateKey(rawRepresentation: key).signature(for: input).rawRepresentation
    }
}
private struct LabPrimarySender: ClientAuthenticatedCommandSendingV1 {
    let connection: LabConnection
    func sendAuthenticatedCommand(_ frame: Data) async throws { try await connection.sendFrame(frame) }
}

private actor LabRolePair: NetworkClientInteractiveRolePairOwningV0 {
    let fixture: LabFixture
    var connections: [LabConnection] = []
    init(_ fixture: LabFixture) { self.fixture = fixture }
    func connect() async throws -> NetworkClientInteractiveReadyRolePairV0 {
        let endpoint = try EndpointCandidate(kind: .ipv4, value: "127.0.0.1", port: fixture.port)
        func make(_ role: InteractiveChannelRoleName) async throws -> NetworkClientInteractiveReadyRoleConnectionV0 {
            let connection = try await LabConnection.connect(fixture: fixture, role: role.rawValue)
            connections.append(connection)
            return .init(endpoint: endpoint, role: role, channelID: WireUUID(UUID()),
                receive: { count in .init(data: try await connection.read(count), isComplete: false) },
                send: { try await connection.send($0) }, cancel: { await connection.close() })
        }
        let input = try await make(.input)
        let media = try await make(.media)
        return .init(endpoint: endpoint, input: input, media: media)
    }
    func primaryTerminated(hostID: UUID, connectionID: Data) async { await close() }
    func close() async { for connection in connections { await connection.close() }; connections = [] }
}

private final class LabEventRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var roles: NetworkClientInteractiveRoleProductBindingV0?
    private var accepted: ClientInteractiveAcceptedSessionV0?
    private var latestFocus: ClientSurfaceFocusEventV0?
    let fixture: LabFixture
    init(_ fixture: LabFixture) { self.fixture = fixture }
    func bind(_ roles: NetworkClientInteractiveRoleProductBindingV0) { lock.withLock { self.roles = roles } }
    func session() -> ClientInteractiveAcceptedSessionV0? { lock.withLock { accepted } }
    func latestFocusEvent() -> ClientSurfaceFocusEventV0? {
        lock.withLock { latestFocus }
    }
    func control(_ event: ClientInteractivePrimarySessionEventV0) {
        let roles = lock.withLock {
            if case .accepted(let session, _) = event { accepted = session }
            return roles
        }
        roles?.productEvents.publishControl(.init(hostID: fixture.hostID, connectionID: fixture.connectionID, event: event))
    }
    func focus(_ event: ClientSurfaceFocusEventV0) {
        let roles = lock.withLock {
            latestFocus = event
            return roles
        }
        roles?.productEvents.publishFocus(.init(hostID: fixture.hostID, connectionID: fixture.connectionID, event: event))
    }
}

@MainActor
final class NetworkControlLabTelemetry: ObservableObject {
    @Published var frameSequence: UInt64 = 0
    @Published var surfaceKind = "none"
    @Published var focusPauseRaceInjections = 0
    @Published var desktopRefreshRecoveries = 0
    @Published var disabledZoomPauseRecoveries = 0
    @Published var staleFocusFallbackRecoveries = 0
    @Published var visualZoomed = false
    @Published var hostStatus = LabStatus()
}

@MainActor
final class NetworkControlLabModel: ObservableObject {
    @Published var state = "Disconnected"
    @Published var failure = "None"
    let telemetry = NetworkControlLabTelemetry()
    @Published var revision: UInt64 = 1
    @Published var coordinator: ClientPrimaryLiveControlCoordinatorV0?
    @Published var control = ClientControlWorkspaceProjectionV0(connected: false, deviceState: .activeGranted, state: .inactive)
    private var fixture: LabFixture?
    private var primary: LabConnection?
    private var roles: NetworkClientInteractiveRoleProductBindingV0?
    private var channel: ClientInteractivePrimaryChannelV0?
    private var eventRelay: LabEventRelay?
    private var reader: Task<Void, Never>?
    private var monitor: Task<Void, Never>?
    private var generation = UUID()

    func connect() async {
        await disconnect()
        generation = UUID()
        let token = generation
        state = "Connecting"; failure = "None"; telemetry.frameSequence = 0
        do {
            let path = URL.documentsDirectory.appending(path: "lab-fixture.json")
            let fixture = try JSONDecoder().decode(LabFixture.self, from: Data(contentsOf: path))
            self.fixture = fixture
            let endpoint = try EndpointCandidate(kind: .ipv4, value: "127.0.0.1", port: fixture.port)
            let host = try ClientDurablePairedHostV0(
                host: .init(pairingID: fixture.pairingID, clientID: fixture.clientID, hostID: fixture.hostID,
                    deviceID: fixture.deviceID, hostFingerprint: fixture.fingerprint, endpoints: [endpoint], deviceState: .activeMonitorOnly,
                    authorizationEpoch: .init(rawValue: 1), grantRevision: .init(rawValue: 1), policyRevision: .init(rawValue: 1)),
                identity: .init(pairingID: fixture.pairingID, clientID: fixture.clientID,
                    sessionKey: .init(role: .session, reference: .init(UUID()), publicKeyX963: P256.Signing.PrivateKey(rawRepresentation: fixture.sessionKey).publicKey.x963Representation, protection: .afterFirstUnlockThisDeviceOnly),
                    approvalKey: .init(role: .approval, reference: .init(UUID()), publicKeyX963: P256.Signing.PrivateKey(rawRepresentation: fixture.approvalKey).publicKey.x963Representation, protection: .whenUnlockedThisDeviceOnlyUserPresence)))
            let session = ClientAuthenticatedSessionV0(clientID: fixture.clientID, hostID: fixture.hostID, deviceID: fixture.deviceID,
                connectionID: fixture.connectionID, deviceState: .activeGranted, authorizationEpoch: .init(rawValue: 1),
                grantRevision: .init(rawValue: 1), policyRevision: .init(rawValue: 1), hostState: .userSessionActive,
                features: [], serverTimeUnixMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000))
            let primary = try await LabConnection.connect(fixture: fixture, role: "primary")
            self.primary = primary
            let router = try ClientPrimaryCommandRouterV0(authenticatedSession: session, transport: LabPrimarySender(connection: primary),
                monotonicNowNanoseconds: { DispatchTime.now().uptimeNanoseconds })
            let relay = LabEventRelay(fixture)
            eventRelay = relay
            let channel = try ClientInteractivePrimaryChannelV0(pairedHost: host, authenticatedSession: session,
                signer: LabApprovalSigner(key: fixture.approvalKey), sender: router.sender(for: .control),
                environment: .init(makeMessageID: { WireUUID(UUID()) }, wallNowUnixMilliseconds: { Int64(Date().timeIntervalSince1970 * 1_000) },
                    monotonicNowMilliseconds: { DispatchTime.now().uptimeNanoseconds / 1_000_000 }),
                publish: { relay.control($0) }, publishFocus: { relay.focus($0) })
            self.channel = channel
            let pair = LabRolePair(fixture)
            let roles = NetworkClientInteractiveRoleProductBindingV0(hostID: fixture.hostID, pairFactory: { pair }, channelFactory: { channel })
            relay.bind(roles); self.roles = roles
            try await router.installReceiver(channel, for: .control)
            try await router.activate()
            reader = Task { [weak self] in
                do { while !Task.isCancelled { try await router.receive(primary.readFrame()) } }
                catch {
                    if let self, self.generation == token {
                        if self.failure == "None" { self.failure = "primary: \(error)" }
                        await self.disconnect()
                    }
                }
            }
            _ = try await channel.beginSession(effects: [.view, .pointer, .keyboard, .text])
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while true {
                if case .roleChannelsReady = await roles.state { break }
                guard ContinuousClock.now < deadline else { throw LabError.deadline }
                try await Task.sleep(for: .milliseconds(20))
            }
            guard let accepted = relay.session() else { throw LabError.unauthorized }
            control = .init(connected: true, deviceState: .activeGranted, state: .active(interactiveSessionID: accepted.interactiveSessionID,
                expiresAtUnixMilliseconds: accepted.expiresAtUnixMilliseconds, effects: [.view, .pointer, .keyboard, .text]))
            coordinator = .init(roles: roles, failure: { [weak self] error in
                guard let self, self.generation == token else { return }
                if self.failure == "None" { self.failure = "product: \(error)" }
                self.state = "Failed"
            })
            revision += 1
            monitor = Task { [weak self] in
                while !Task.isCancelled, let self, self.generation == token {
                    if let product = self.coordinator?.product as? UIKitClientInitialDesktopProductV0 {
                        product.surface.accessibilityIdentifier = "Lab live surface"
                        self.telemetry.frameSequence = product.decoderRenderer.authority.latestFrame?.mediaSequence ?? 0
                        self.telemetry.surfaceKind = product.descriptor.kind.rawValue
                        self.telemetry.visualZoomed =
                            product.surface.isVisuallyZoomed
                        let nextState = self.coordinator?.phase == .active ? "Streaming" : "Preparing"
                        if self.failure == "None", self.state != nextState { self.state = nextState }
                    }
                    do {
                        let status = try await self.command("status")
                        guard self.generation == token else { return }
                        self.telemetry.hostStatus = status
                    } catch {
                        if self.generation == token, self.failure == "None" { self.failure = "status: \(error)" }
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        } catch {
            failure = String(describing: error)
            print("LAB_CLIENT_FAILURE \(failure)")
            state = "Failed"
        }
    }
    func command(_ action: String) async throws -> LabStatus {
        guard let fixture else { throw LabError.closed }
        let connection = try await LabConnection.connect(fixture: fixture, role: "control")
        do {
            try await connection.sendFrame(JSONEncoder().encode(LabCommand(action)))
            let status = try JSONDecoder().decode(LabStatus.self, from: await connection.readFrame())
            await connection.close()
            return status
        } catch { await connection.close(); throw error }
    }
    func focus(
        delayed: Bool = false,
        forceRemoteSurface: Bool = true
    ) async {
        do {
            let priorSequence = eventRelay?.latestFocusEvent()?.eventSequence
            if delayed { _ = try await command("delay-selected") }
            _ = try await command("focus")
            if forceRemoteSurface {
                try await forceFocusedSurface(after: priorSequence)
            }
        }
        catch { failure = String(describing: error) }
    }
    func localFocus() async {
        await focus(forceRemoteSurface: false)
    }
    func localFocusChurn() async {
        do { _ = try await command("focus-churn") }
        catch { failure = String(describing: error) }
    }
    func resumeSmartZoom() async {
        do { try await coordinator?.product?.resumeAutomaticSmartZoom() }
        catch { failure = String(describing: error) }
    }
    func focusChurn() async {
        do {
            let priorSequence = eventRelay?.latestFocusEvent()?.eventSequence
            _ = try await command("focus-churn")
            try await forceFocusedSurface(after: priorSequence)
        }
        catch { failure = String(describing: error) }
    }

    private func forceFocusedSurface(after priorSequence: Int64?) async throws {
        guard let eventRelay, let product = coordinator?.product else {
            throw LabError.closed
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while eventRelay.latestFocusEvent()?.eventSequence == priorSequence {
            guard ContinuousClock.now < deadline else {
                throw LabError.deadline
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        // Churn commands intentionally publish focus -> ambiguous Desktop ->
        // focus in 100 ms. Let the relay reach the final selectable authority;
        // choosing the first token would correctly fail closed as stale.
        try await Task.sleep(for: .milliseconds(175))
        guard let event = eventRelay.latestFocusEvent(),
              event.recommendedTargetKind == .focusedRegion,
              let targetToken = event.targetToken?.rawValue else {
            throw LabError.deadline
        }
        // User-facing Smart Zoom deliberately stays on the broad Desktop/App
        // stream. These stress lanes still need the exact narrow host surface
        // so they select it explicitly instead of coupling visual presentation
        // to the native text-composer preparation path.
        try await product.selectSurface(
            kind: .focusedRegion,
            targetToken: targetToken
        )
    }
    /// Forces the exact production race where a verified focus token becomes
    /// stale after selection starts. The host must safely return Desktop and
    /// the client must keep the primary Control session alive.
    func recoverStaleFocusedSelection() async {
        do {
            guard let product = coordinator?.product else {
                throw LabError.closed
            }
            let before = telemetry.hostStatus.transitions
            let priorSequence = eventRelay?.latestFocusEvent()?.eventSequence
            _ = try await command("focus-stale-selection")
            try await forceFocusedSurface(after: priorSequence)
            let deadline = ContinuousClock.now.advanced(by: .seconds(8))
            while true {
                let host = try await command("status")
                if host.transitions > before,
                   product.descriptor.kind == .desktop {
                    telemetry.hostStatus = host
                    telemetry.staleFocusFallbackRecoveries += 1
                    return
                }
                guard ContinuousClock.now < deadline else {
                    throw LabError.deadline
                }
                try await Task.sleep(for: .milliseconds(20))
            }
        } catch {
            failure = String(describing: error)
        }
    }
    /// Deterministically reproduces input already queued while a verified
    /// focused -> focused event has paused the current input authority. The
    /// production UIKit relay must drop that one stale submission without
    /// retiring Control or masking any other error.
    func focusWithQueuedInputRace() async {
        do {
            guard let eventRelay, let product = coordinator?.product else {
                throw LabError.closed
            }
            _ = try await command("delay-selected")
            _ = try await command("focus")
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while eventRelay.latestFocusEvent()?.inputPaused != true {
                guard ContinuousClock.now < deadline else {
                    throw LabError.deadline
                }
                try await Task.sleep(for: .milliseconds(5))
            }
            product.surface.sendKeyboardAction(.tab)
            // Let the production relay observe inputPausedByFocusEvent while
            // the focus fence is still current. That one stale submission is
            // nonterminal; ordinary Smart Zoom must then settle normally.
            try await Task.sleep(for: .milliseconds(50))
            telemetry.focusPauseRaceInjections += 1
        } catch {
            failure = String(describing: error)
        }
    }
    /// A presentation preference cannot strand the host's input authority in
    /// a focus pause. With Smart Zoom disabled, a paused focus event must
    /// recover to Desktop and resume ordinary pointer/keyboard input.
    func recoverPausedFocusWithSmartZoomDisabled() async {
        do {
            guard let eventRelay, let product = coordinator?.product else {
                throw LabError.closed
            }
            try await product.setAutomaticSmartZoomEnabled(false)
            _ = try await command("focus")
            let eventDeadline = ContinuousClock.now.advanced(by: .seconds(2))
            while eventRelay.latestFocusEvent()?.inputPaused != true {
                guard ContinuousClock.now < eventDeadline else {
                    throw LabError.deadline
                }
                try await Task.sleep(for: .milliseconds(5))
            }
            let recoveryDeadline = ContinuousClock.now.advanced(by: .seconds(8))
            while product.descriptor.kind != .desktop {
                guard ContinuousClock.now < recoveryDeadline else {
                    throw LabError.deadline
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            telemetry.disabledZoomPauseRecoveries += 1
            try await product.setAutomaticSmartZoomEnabled(true)
        } catch {
            failure = String(describing: error)
        }
    }
    /// Production refreshes a paused Desktop recommendation before its
    /// one-second authority expires. Repeated refreshes must not starve the
    /// client's longer presentation debounce.
    func recoverPausedDesktopAcrossAuthorityRefreshes() async {
        do {
            guard let product = coordinator?.product else {
                throw LabError.closed
            }
            _ = try await command("desktop-focus-refreshes")
            let deadline = ContinuousClock.now.advanced(by: .seconds(3))
            while product.descriptor.kind != .desktop {
                guard ContinuousClock.now < deadline else {
                    throw LabError.deadline
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            telemetry.desktopRefreshRecoveries += 1
        } catch {
            failure = String(describing: error)
        }
    }
    func desktop() async {
        do {
            try await coordinator?.product?.selectSurface(kind: .desktop, targetToken: nil)
        } catch { failure = String(describing: error) }
    }
    func stop() async throws { _ = try await channel?.endSession(); await disconnect() }
    func probeCleanup() async {
        do { telemetry.hostStatus = try await command("status") }
        catch { failure = "cleanup probe: \(error)" }
    }
    func disconnect() async {
        generation = UUID()
        reader?.cancel(); monitor?.cancel()
        await coordinator?.product?.close(); await roles?.close(); await primary?.close()
        coordinator = nil; roles = nil; primary = nil; channel = nil
        eventRelay = nil
        state = "Disconnected"; control = .init(connected: false, deviceState: .activeGranted, state: .inactive)
    }
}

struct NetworkControlLabView: View {
    @StateObject private var model = NetworkControlLabModel()
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Button("Lab Reconnect") { Task { await model.connect() } }
                Button("Lab Focus") { Task { await model.focus() } }
                Button("Lab Local Focus") {
                    Task { await model.localFocus() }
                }
                Button("Lab Local Focus Churn") {
                    Task { await model.localFocusChurn() }
                }
                Button("Lab Resume Smart Zoom") {
                    Task { await model.resumeSmartZoom() }
                }
                Button("Lab Focus Churn") { Task { await model.focusChurn() } }
                Button("Lab Stale Focus") {
                    Task { await model.recoverStaleFocusedSelection() }
                }
                Button("Lab Delayed Focus") { Task { await model.focus(delayed: true) } }
                Button("Lab Focus Input Race") {
                    Task { await model.focusWithQueuedInputRace() }
                }
                Button("Lab Disabled Zoom Pause") {
                    Task {
                        await model.recoverPausedFocusWithSmartZoomDisabled()
                    }
                }
                Button("Lab Desktop Refresh Pause") {
                    Task {
                        await model
                            .recoverPausedDesktopAcrossAuthorityRefreshes()
                    }
                }
                Button("Lab Desktop") { Task { await model.desktop() } }
                Button("Lab Drop") { Task { _ = try? await model.command("drop") } }
                Button("Lab Cleanup") { Task { await model.probeCleanup() } }
            }.font(.caption)
            Text(model.state).accessibilityIdentifier("Lab state")
            Text(model.failure).accessibilityIdentifier("Lab failure")
            NetworkControlLabTelemetryView(telemetry: model.telemetry)
            if let coordinator = model.coordinator {
                ClientPrimaryLiveControlViewV0(macName: "Loopback Test Mac", revision: model.revision, control: model.control,
                    coordinator: coordinator, onStop: { try await model.stop() }, onRecordStudyJob: { _, _ in })
            } else { Spacer() }
        }
        .task { await model.connect() }
        .onDisappear { Task { await model.disconnect() } }
    }
}

private struct NetworkControlLabTelemetryView: View {
    @ObservedObject var telemetry: NetworkControlLabTelemetry
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(telemetry.hostStatus.source).accessibilityIdentifier("Lab source")
                Text(String(telemetry.frameSequence)).accessibilityIdentifier("Lab rendered sequence")
                Text(telemetry.surfaceKind).accessibilityIdentifier("Lab surface")
                Text(String(telemetry.hostStatus.acknowledgements)).accessibilityIdentifier("Lab acknowledgements")
                Text(String(telemetry.hostStatus.renewals)).accessibilityIdentifier("Lab renewals")
            }
            HStack {
                Text(String(telemetry.desktopRefreshRecoveries))
                    .accessibilityIdentifier(
                        "Lab desktop refresh recoveries"
                    )
                Text(telemetry.hostStatus.failure ?? "None").accessibilityIdentifier("Lab host failure")
                Text(telemetry.hostStatus.closed ? "Closed" : "Open").accessibilityIdentifier("Lab host session")
                Text(telemetry.hostStatus.captureActive ? "Running" : "Stopped").accessibilityIdentifier("Lab capture")
                Text(telemetry.hostStatus.runtimeIdle ? "Idle" : "Active").accessibilityIdentifier("Lab runtime")
                Text(String(telemetry.hostStatus.queuedMediaRecords)).accessibilityIdentifier("Lab queued media")
            }
            HStack {
                Text(String(telemetry.hostStatus.selectedDisplayOrdinal ?? 0))
                    .accessibilityIdentifier("Lab selected display")
                Text(String(telemetry.hostStatus.activeDisplayOrdinal ?? 0))
                    .accessibilityIdentifier("Lab active display")
                Text(String(telemetry.hostStatus.displayCatalogRequests))
                    .accessibilityIdentifier("Lab display catalog requests")
                Text(telemetry.hostStatus.textMatches ? "Matched" : "Waiting").accessibilityIdentifier("Lab input match")
                Text(telemetry.hostStatus.directTextMatches ? "Matched" : "Waiting").accessibilityIdentifier("Lab direct input match")
                Text(telemetry.hostStatus.pointerDelivered ? "Delivered" : "Waiting").accessibilityIdentifier("Lab pointer")
                Text(telemetry.hostStatus.returnKeyDelivered ? "Delivered" : "Waiting").accessibilityIdentifier("Lab physical key")
                Text(String(telemetry.focusPauseRaceInjections)).accessibilityIdentifier("Lab focus pause race injections")
                Text(String(telemetry.disabledZoomPauseRecoveries)).accessibilityIdentifier("Lab disabled zoom pause recoveries")
                Text(String(telemetry.staleFocusFallbackRecoveries))
                    .accessibilityIdentifier(
                        "Lab stale focus fallback recoveries"
                    )
                Text(telemetry.visualZoomed ? "Focused" : "Fit")
                    .accessibilityIdentifier("Lab visual zoom")
                Text(String(telemetry.hostStatus.inputEvents))
                    .accessibilityIdentifier("Lab input events")
            }
        }.font(.caption)
    }
}

// MARK: Production lifecycle + workspace integration
// Only test identity, transport establishment, and user presence are replaced.
private struct IntegratedLabSigner: ClientOperationApprovalSigningV1, ClientInteractiveApprovalSigningV0 {
    let key: Data
    func signOperationApprovalInput(_ input: Data) async throws -> Data {
        throw LabError.unsupported // No Act execution in this lane.
    }
    func signSessionChallenge(_ input: Data) async throws -> Data {
        try P256.Signing.PrivateKey(rawRepresentation: key).signature(for: input).rawRepresentation
    }
}

private actor IntegratedLabInventory: ClientPairedHostInventoryV1 {
    let host: ClientDurablePairedHostV0
    init(_ host: ClientDurablePairedHostV0) { self.host = host }
    func pairedHost(hostID: UUID) -> ClientDurablePairedHostV0? { hostID == host.hostID ? host : nil }
}

private actor IntegratedLabDialGate {
    var reachable = true
    var delayMilliseconds = 0
    var attempts = 0
    var selections = 0
    var closures = 0
    func configure(reachable: Bool, delay: Int = 0) { self.reachable = reachable; delayMilliseconds = delay }
    func begin() -> (Bool, Int) { attempts += 1; return (reachable, delayMilliseconds) }
    func selected() { selections += 1 }
    func closed() { closures += 1 }
    func counts() -> (Int, Int, Int) { (attempts, selections, closures) }
}

private actor IntegratedLabPrimaryConnection {
    let connection: LabConnection
    let candidate: NetworkClientPrimaryProductCandidateV0
    let gate: IntegratedLabDialGate
    var reader: Task<Void, Never>?
    var closed = false
    init(connection: LabConnection, candidate: NetworkClientPrimaryProductCandidateV0, gate: IntegratedLabDialGate) {
        self.connection = connection; self.candidate = candidate; self.gate = gate
    }
    func start() {
        reader = Task {
            do { while !Task.isCancelled { try await candidate.receive(connection.readFrame()) } }
            catch { await close() }
        }
    }
    func select() async {
        guard !closed else { return }
        await candidate.selectedAsPrimary()
        await gate.selected()
    }
    func close() async {
        guard !closed else { return }; closed = true
        reader?.cancel()
        // Unblock pending I/O before invalidating command/channel owners.
        await connection.close()
        await candidate.primaryTerminated()
        await gate.closed()
    }
}

private struct IntegratedLabDialer: DialRouteAttemptingV0 {
    let fixture: LabFixture
    let host: ClientDurablePairedHostV0
    let events: NetworkClientPrimaryProductEventsV0
    let gate: IntegratedLabDialGate
    func attempt(_ attempt: DialAttempt, roundID: UUID, requiredHostFingerprint: Data) async -> DialRouteAttemptOutcomeV0 {
        let (reachable, delay) = await gate.begin()
        guard reachable, attempt.endpoint.value == "127.0.0.1",
              attempt.endpoint.port == fixture.port,
              requiredHostFingerprint == fixture.fingerprint else { return .transientFailure }
        do {
            if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) }
            try Task.checkCancellation()
            let id = withUnsafeBytes(of: UUID().uuid) { Data($0) }
            let connection = try await LabConnection.connect(fixture: fixture, role: "primary", connectionID: id)
            let signer = IntegratedLabSigner(key: fixture.approvalKey)
            let candidate = NetworkClientPrimaryProductCandidateV0(endpoint: attempt.endpoint,
                authenticatedRouteClass: .privateNetwork,
                configuration: .init(pairedHost: host, approvalSigner: signer, interactiveApprovalSigner: signer,
                    clock: { .init(wallNowUnixMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000),
                                   monotonicNowMilliseconds: DispatchTime.now().uptimeNanoseconds / 1_000_000) },
                    messageID: { WireUUID(UUID()) }, events: events))
            let owner = IntegratedLabPrimaryConnection(connection: connection, candidate: candidate, gate: gate)
            do {
                try await candidate.bindAuthenticatedTransport(LabPrimarySender(connection: connection))
                try await candidate.authenticated(.init(clientID: fixture.clientID, hostID: fixture.hostID,
                    deviceID: fixture.deviceID, connectionID: id, deviceState: .activeGranted,
                    authorizationEpoch: .init(rawValue: 1), grantRevision: .init(rawValue: 1),
                    policyRevision: .init(rawValue: 1), hostState: .userSessionActive,
                    features: [], serverTimeUnixMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)))
                try Task.checkCancellation()
                await owner.start()
                return .authenticated(.init(endpoint: attempt.endpoint,
                    send: { try await connection.sendFrame($0) },
                    selected: { await owner.select() }, close: { await owner.close() }))
            } catch { await owner.close(); return .transientFailure }
        } catch { return .transientFailure }
    }
}

private struct IntegratedLabRoleConnector: NetworkClientInteractiveRoleConnectingV0 {
    let fixture: LabFixture
    func connect(endpoint: EndpointCandidate, session: ClientInteractiveAcceptedSessionV0,
                 role: InteractiveChannelRoleName) async throws -> NetworkClientInteractiveReadyRoleConnectionV0 {
        guard endpoint.value == "127.0.0.1", endpoint.port == fixture.port,
              session.primary.hostID == fixture.hostID else { throw LabError.unauthorized }
        let connection = try await LabConnection.connect(fixture: fixture, role: role.rawValue,
            connectionID: session.primary.primaryConnectionID)
        return .init(endpoint: endpoint, role: role,
            channelID: role == .input ? session.inputChannel.channelID : session.mediaChannel.channelID,
            receive: { .init(data: try await connection.read($0), isComplete: false) },
            send: { try await connection.send($0) }, cancel: { await connection.close() })
    }
}

@MainActor
private final class IntegratedLabReachability: ClientCoarseReachabilitySourceV1 {
    let events: AsyncStream<Bool>
    private let continuation: AsyncStream<Bool>.Continuation
    init() {
        let pair = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        events = pair.stream; continuation = pair.continuation
    }
    func start() throws {}
    func stop() { continuation.finish() }
    func send(_ value: Bool) { continuation.yield(value) }
}

@MainActor
private final class IntegratedLabTelemetry: ObservableObject {
    @Published var lifecycle = "Preparing"
    @Published var control = "unavailable"
    @Published var connected = false
    @Published var attempts = 0
    @Published var selections = 0
    @Published var closures = 0
    @Published var terminalFailures = 0
    @Published var visualZoomed = false
    @Published var host = LabStatus()
}

@MainActor
private final class IntegratedControlLabModel: ObservableObject {
    @Published var workspace: ClientPrimaryWorkspaceModelV0?
    @Published var failure = "None"
    let telemetry = IntegratedLabTelemetry()
    private(set) var network: NetworkClientConfiguredRouteApplicationProductV1?
    private var applicationOwner: UIKitClientConfiguredRouteNetworkApplicationOwnerV1?
    private var source: IntegratedLabReachability?
    private var fixture: LabFixture?
    private let gate = IntegratedLabDialGate()
    private var monitor: Task<Void, Never>?
    private var directory: URL?
    private var starting = false
    private var reachable = true

    func start() async {
        guard network == nil, !starting else { return }
        starting = true
        defer { starting = false }
        do {
            let fixture = try JSONDecoder().decode(LabFixture.self,
                from: Data(contentsOf: URL.documentsDirectory.appending(path: "lab-fixture.json")))
            self.fixture = fixture
            let endpoint = try EndpointCandidate(kind: .ipv4, value: "127.0.0.1", port: fixture.port)
            let host = try ClientDurablePairedHostV0(
                host: .init(pairingID: fixture.pairingID, clientID: fixture.clientID, hostID: fixture.hostID,
                    deviceID: fixture.deviceID, hostFingerprint: fixture.fingerprint, endpoints: [endpoint],
                    deviceState: .activeMonitorOnly, authorizationEpoch: .init(rawValue: 1),
                    grantRevision: .init(rawValue: 1), policyRevision: .init(rawValue: 1)),
                identity: .init(pairingID: fixture.pairingID, clientID: fixture.clientID,
                    sessionKey: .init(role: .session, reference: .init(UUID()),
                        publicKeyX963: P256.Signing.PrivateKey(rawRepresentation: fixture.sessionKey).publicKey.x963Representation,
                        protection: .afterFirstUnlockThisDeviceOnly),
                    approvalKey: .init(role: .approval, reference: .init(UUID()),
                        publicKeyX963: P256.Signing.PrivateKey(rawRepresentation: fixture.approvalKey).publicKey.x963Representation,
                        protection: .whenUnlockedThisDeviceOnlyUserPresence)))
            let directory = FileManager.default.temporaryDirectory.appending(path: "integrated-lab-\(UUID())")
            self.directory = directory
            let routes = try AtomicFileClientConfiguredRouteStoreV1(directory: directory)
            let record = try ClientConfiguredRouteRecordV1(
                configuredRouteID: WireBytes16(Data(repeating: 1, count: 16)),
                endpoint: endpoint, provenance: .privateNetwork)
            _ = try await routes.replaceAtomically(.init(hostID: fixture.hostID, revision: 1,
                catalog: .init(records: [record])), expectedRevision: nil)
            let gate = self.gate
            let network = try await NetworkClientConfiguredRouteApplicationProductFactoryV1.make(
                hostID: fixture.hostID, pairedHosts: IntegratedLabInventory(host), routes: routes,
                connector: IntegratedLabRoleConnector(fixture: fixture),
                monotonicNow: { Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000) },
                newRouteID: { try WireBytes16(withUnsafeBytes(of: UUID().uuid) { Data($0) }) },
                roundID: { UUID() },
                makeController: { configuration, foreground, reachable, events in
                    ReconnectControllerV0(
                        state: try configuration.makeReconnectState(foreground: foreground, networkReachable: reachable),
                        executor: .init(attempter: IntegratedLabDialer(fixture: fixture,
                            host: configuration.pairedHost, events: events, gate: gate)),
                        monotonicNow: { Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000) },
                        jitterBasisPoints: { 10_000 })
                })
            self.network = network
            workspace = try ClientPrimaryWorkspaceModelV0(macName: "Integrated Lab Mac",
                primaryState: network.primaryState,
                monotonicNowMilliseconds: { Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000) })
            let source = IntegratedLabReachability()
            self.source = source
            let owner = UIKitClientConfiguredRouteNetworkApplicationOwnerV1(binding: network.binding,
                source: source, failure: { [weak self] error in
                    self?.telemetry.terminalFailures += 1
                    self?.failure = String(describing: error)
                }, stateChanged: { [weak self] snapshot in
                    self?.telemetry.lifecycle = !snapshot.foreground ? "Background"
                        : snapshot.networkReachable ? "Foreground" : "Offline"
                })
            applicationOwner = owner
            try await owner.start()
            source.send(reachable)
            monitor = Task { [weak self] in
                while !Task.isCancelled, let self {
                    self.telemetry.connected = network.primaryState.snapshot().availability == .connected
                    self.telemetry.control = String(describing: self.workspace?.projection.control.mode ?? .unavailable)
                    (self.telemetry.attempts, self.telemetry.selections, self.telemetry.closures) = await gate.counts()
                    if let status = try? await self.command("status") { self.telemetry.host = status }
                    var visualZoomed = false
                    for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                        for window in scene.windows {
                            visualZoomed = Self.identifyVideo(in: window)
                                || visualZoomed
                        }
                    }
                    self.telemetry.visualZoomed = visualZoomed
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
        } catch { failure = String(describing: error); await close() }
    }
    private static func identifyVideo(in view: UIView) -> Bool {
        var visualZoomed = false
        if let surface = view as? UIKitClientLiveSurfaceViewV0 {
            surface.accessibilityIdentifier = "Integrated live surface"
            surface.videoView.accessibilityIdentifier = "Integrated video"
            visualZoomed = surface.isVisuallyZoomed
        }
        for child in view.subviews {
            visualZoomed = identifyVideo(in: child) || visualZoomed
        }
        return visualZoomed
    }
    func command(_ action: String) async throws -> LabStatus {
        guard let fixture else { throw LabError.closed }
        let connection = try await LabConnection.connect(fixture: fixture, role: "control")
        do {
            try await connection.sendFrame(JSONEncoder().encode(LabCommand(action)))
            let result = try JSONDecoder().decode(LabStatus.self, from: await connection.readFrame())
            await connection.close(); return result
        } catch { await connection.close(); throw error }
    }
    func setReachable(_ value: Bool, delay: Int = 0) async {
        reachable = value
        await gate.configure(reachable: value, delay: delay)
        source?.send(value)
    }
    func close() async {
        monitor?.cancel(); monitor = nil
        workspace?.stop()
        await applicationOwner?.stop()
        await network?.interactiveRoles.close()
        await network?.lifecycle.close()
        applicationOwner = nil; network = nil; workspace = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }
}

struct IntegratedControlLabView: View {
    @StateObject private var model = IntegratedControlLabModel()
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Button("Lab Offline") { Task { await model.setReachable(false) } }
                Button("Lab Online") { Task { await model.setReachable(true) } }
                Button("Lab Slow Online") { Task { await model.setReachable(true, delay: 2_000) } }
                Button("Lab Drop") { Task { _ = try? await model.command("drop") } }
                Button("Lab Focus") { Task { _ = try? await model.command("focus") } }
            }.font(.caption)
            Text(model.failure).accessibilityIdentifier("Integrated failure")
            IntegratedLabTelemetryView(telemetry: model.telemetry)
            if let workspace = model.workspace, let network = model.network {
                ClientPrimaryWorkspaceApplicationViewV1(macName: "Integrated Lab Mac",
                    model: workspace, interactiveRoles: network.interactiveRoles,
                    onReconnect: { await model.close(); await model.start() },
                    onCommandFailure: { model.failure = String(describing: $0) })
            } else { Spacer() }
        }
        .task { await model.start() }
        .onDisappear { Task { await model.close() } }
    }
}

private struct IntegratedLabTelemetryView: View {
    @ObservedObject var telemetry: IntegratedLabTelemetry
    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(telemetry.lifecycle).accessibilityIdentifier("Integrated lifecycle")
                Text(telemetry.connected ? "Connected" : "Disconnected").accessibilityIdentifier("Integrated connection")
                Text(telemetry.control).accessibilityIdentifier("Integrated Control")
                Text(String(telemetry.terminalFailures)).accessibilityIdentifier("Integrated terminal failures")
            }
            HStack {
                Text(String(telemetry.attempts)).accessibilityIdentifier("Integrated attempts")
                Text(String(telemetry.selections)).accessibilityIdentifier("Integrated selections")
                Text(String(telemetry.closures)).accessibilityIdentifier("Integrated closures")
                Text(String(telemetry.host.retiredSessions)).accessibilityIdentifier("Integrated retired sessions")
                Text(String(telemetry.host.uncleanRetirements)).accessibilityIdentifier("Integrated unclean retirements")
                Text(String(telemetry.host.statusRequests)).accessibilityIdentifier("Integrated status requests")
                Text(String(telemetry.host.acknowledgements)).accessibilityIdentifier("Integrated surface acknowledgements")
                Text(telemetry.visualZoomed ? "Focused" : "Fit")
                    .accessibilityIdentifier("Integrated visual zoom")
            }
            HStack {
                Text(telemetry.host.runtimeIdle ? "Idle" : "Active").accessibilityIdentifier("Integrated runtime")
                Text(telemetry.host.captureActive ? "Running" : "Stopped").accessibilityIdentifier("Integrated capture")
                Text(String(telemetry.host.queuedMediaRecords)).accessibilityIdentifier("Integrated queue")
                Text(String(telemetry.host.mediaRecords)).accessibilityIdentifier("Integrated media")
                Text(telemetry.host.source).accessibilityIdentifier("Lab source")
                Text(telemetry.host.textMatches ? "Matched" : "Waiting").accessibilityIdentifier("Integrated text")
            }
        }.font(.caption2)
    }
}
