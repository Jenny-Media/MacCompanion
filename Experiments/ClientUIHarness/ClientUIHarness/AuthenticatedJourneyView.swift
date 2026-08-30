#if !DEBUG || !targetEnvironment(simulator)
#error("Authenticated journey is Simulator Debug-only")
#endif
import CompanionClient
import CompanionClientApp
import CompanionClientNetworkPlatform
import CompanionClientPlatform
import CompanionClientUI
import CompanionDiscovery
import CompanionPresentation
import CompanionWire
import CryptoKit
import Foundation
import LiveControlLabSupport
import Network
import SwiftUI
import UIKit

/// Software custody is the only key/user-presence substitution. Private bytes
/// live solely in this disposable Simulator test directory, never in fixtures.
private actor JourneySoftwareCustody: ClientIdentityKeyCustodyV0 {
    private struct Keys: Codable {
        let session: Data
        let approval: Data
        let sessionReference: UUID
        let approvalReference: UUID
    }
    private let location: URL
    private var keys: Keys?
    init(directory: URL) throws {
        location = directory.appendingPathComponent("software-test-keys.json")
        if FileManager.default.fileExists(atPath: location.path) {
            keys = try JSONDecoder().decode(Keys.self, from: Data(contentsOf: location))
        }
    }
    func prepareIdentity(pairingID: UUID, clientID: UUID) throws -> ClientPreparedIdentityV0 {
        if keys == nil {
            let generated = Keys(session: P256.Signing.PrivateKey().rawRepresentation,
                approval: P256.Signing.PrivateKey().rawRepresentation,
                sessionReference: UUID(), approvalReference: UUID())
            try JSONEncoder().encode(generated).write(to: location, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: location.path)
            keys = generated
        }
        guard let keys else { throw LabError.closed }
        return try .init(pairingID: pairingID, clientID: clientID,
            sessionKey: .init(role: .session, reference: .init(keys.sessionReference),
                publicKeyX963: P256.Signing.PrivateKey(rawRepresentation: keys.session).publicKey.x963Representation,
                protection: .afterFirstUnlockThisDeviceOnly),
            approvalKey: .init(role: .approval, reference: .init(keys.approvalReference),
                publicKeyX963: P256.Signing.PrivateKey(rawRepresentation: keys.approval).publicKey.x963Representation,
                protection: .whenUnlockedThisDeviceOnlyUserPresence))
    }
    func validatePreparedIdentity(_ identity: ClientPreparedIdentityV0) throws -> Bool {
        guard keys != nil else { return false }
        return try prepareIdentity(pairingID: identity.pairingID, clientID: identity.clientID) == identity
    }
    func signSessionInput(_ input: Data, using reference: ClientSigningKeyReferenceV0) throws -> Data {
        guard let keys, reference.rawValue == keys.sessionReference else { throw LabError.unauthorized }
        return try P256.Signing.PrivateKey(rawRepresentation: keys.session).signature(for: input).rawRepresentation
    }
    func signApprovalInput(_ input: Data, using reference: ClientSigningKeyReferenceV0,
                           reason: ClientApprovalPresenceReasonV0) throws -> Data {
        guard let keys, reference.rawValue == keys.approvalReference else { throw LabError.unauthorized }
        return try P256.Signing.PrivateKey(rawRepresentation: keys.approval).signature(for: input).rawRepresentation
    }
    func discardPreparedIdentity(_ identity: ClientPreparedIdentityV0) throws {
        guard try validatePreparedIdentity(identity) else { return }
        try FileManager.default.removeItem(at: location); keys = nil
    }
}

@MainActor
private final class JourneyReachability: ClientCoarseReachabilitySourceV1 {
    let events: AsyncStream<Bool>
    private let continuation: AsyncStream<Bool>.Continuation
    init() {
        let pair = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        events = pair.stream; continuation = pair.continuation
    }
    func start() throws { continuation.yield(true) }
    func stop() { continuation.finish() }
    func set(_ value: Bool) { continuation.yield(value) }
}

@MainActor
private final class AuthenticatedJourneyModel: ObservableObject {
    @Published var phase = "Preparing"
    @Published var connected = false
    @Published var failure = "None"
    @Published var saved = 0
    @Published var observations = 0
    @Published var authentications = 0
    @Published var control = "unavailable"
    @Published var hostControl = LabStatus()
    @Published var pinRejectionVerified = false
    @Published var hostBoot = "Unknown"
    @Published var sourceName = "Unknown"
    @Published var verifiedObservation = "None"
    @Published var selectedPrimary = "None"
    @Published var statusError = "None"
    @Published var administration = "None"
    @Published var workspace: ClientPrimaryWorkspaceModelV0?
    private(set) var network: NetworkClientConfiguredRouteApplicationProductV1?
    private var fixture: LabFixture?
    private var store: AtomicFileClientPairedHostStoreV0?
    private var routes: AtomicFileClientConfiguredRouteStoreV1?
    private var custody: JourneySoftwareCustody?
    private var pairing: ClientPairingApplicationOwnerV0?
    private var owner: UIKitClientConfiguredRouteNetworkApplicationOwnerV1?
    private var source: JourneyReachability?
    private var monitor: Task<Void, Never>?
    private var telemetryMonitor: Task<Void, Never>?
    private var busy = false
    private var commandInFlight = false

    func start() async {
        do {
            fixture = try JSONDecoder().decode(LabFixture.self,
                from: Data(contentsOf: URL.documentsDirectory.appendingPathComponent("lab-fixture.json")))
            sourceName = fixture?.source ?? "Unknown"
            let args = ProcessInfo.processInfo.arguments
            guard let index = args.firstIndex(of: "--journey-case"), index + 1 < args.count,
                  let id = UUID(uuidString: args[index + 1]), fixture?.journeyPort != nil else { throw LabError.unsupported }
            let directory = URL.documentsDirectory.appendingPathComponent("journey-tests").appendingPathComponent(id.uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            store = try AtomicFileClientPairedHostStoreV0(directory: directory.appendingPathComponent("paired"))
            routes = try AtomicFileClientConfiguredRouteStoreV1(directory: directory.appendingPathComponent("routes"))
            custody = try JourneySoftwareCustody(directory: directory)
            guard let store else { throw LabError.closed }
            let records = try await store.allRecords()
            saved = records.count
            if let record = records.first { try await connect(record) } else { phase = "Unpaired" }
        } catch { failure = String(describing: error); phase = "Failed" }
    }

    func pair(wrongPin: Bool = false) async {
        guard !busy, let fixture, let store, let custody else { return }
        busy = true; defer { busy = false }
        do {
            guard let qr = try await command(wrongPin ? "journey-wrong-pin" : "journey-pair").qr else { throw LabError.invalidFrame }
            if wrongPin {
                let payload = try PairingQRCodeCodec.decode(qr, nowUnixMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000))
                let context = try NetworkClientTLSAttemptContextV0(endpoint: payload.endpoints[0],
                    requiredHostFingerprint: payload.hostFingerprint.rawValue,
                    verificationQueue: DispatchQueue(label: "Journey.negative.verify"),
                    pinnedLeafEvaluator: SecurityClientPinnedLeafEvaluatorV0.make(wallNowUnixMilliseconds: {
                        Int64(Date().timeIntervalSince1970 * 1_000)
                    }))
                let socket = LabConnection(try context.makeUnstartedConnection())
                let deadline = Task { try? await Task.sleep(for: .seconds(5)); if !Task.isCancelled { await socket.close() } }
                do { try await socket.start() } catch { /* inspect the actual callback result below */ }
                deadline.cancel(); await socket.close()
                pinRejectionVerified = context.verificationStatus() == .rejected
                guard pinRejectionVerified else { throw LabError.unauthorized }
            }
            let pairing = try NetworkClientPairingApplicationCompositionV0.makeOwner(clientID: fixture.clientID,
                custody: custody, persistence: store,
                verificationQueue: DispatchQueue(label: "Journey.pair.verify"), connectionQueue: DispatchQueue(label: "Journey.pair.socket"),
                stateChanged: { [weak self] snapshot in
                    await MainActor.run { self?.phase = snapshot.phase.rawValue }
                })
            self.pairing = pairing
            try await pairing.receiveScan(qr)
            try await pairing.acceptPreview()
            let records = try await store.allRecords()
            saved = records.count
            if let record = records.first { try await connect(record) }
            else { phase = wrongPin ? "Wrong pin rejected" : "Pairing failed" }
        } catch { failure = String(describing: error); phase = "Failed" }
    }

    private func connect(_ record: ClientDurablePairedHostV0) async throws {
        guard let store, let routes, let custody else { throw LabError.closed }
        if try await routes.snapshot(hostID: record.hostID) == nil {
            let plan = try ClientConfiguredRouteBootstrapPlanV1(pairedHost: record)
            let choices = Dictionary(uniqueKeysWithValues: plan.endpointsRequiringExplicitChoice.map { ($0, ClientConfiguredRouteProvenanceV1.privateNetwork) })
            let catalog = try plan.complete(explicitChoices: choices,
                routeID: { _ in try WireBytes16(withUnsafeBytes(of: UUID().uuid) { Data($0) }) })
            _ = try await routes.replaceAtomically(catalog, expectedRevision: nil)
        }
        let network = try await NetworkClientConfiguredRouteApplicationProductFactoryV1.make(hostID: record.hostID,
            pairedHosts: store, routes: routes,
            runtime: .init(custody: custody,
                clock: { .init(wallNowUnixMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000),
                    monotonicNowMilliseconds: DispatchTime.now().uptimeNanoseconds / 1_000_000) },
                verificationQueue: DispatchQueue(label: "Journey.verify"), connectionQueue: DispatchQueue(label: "Journey.socket"),
                monotonicNow: { Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000) }, jitterBasisPoints: { 10_000 }))
        self.network = network
        workspace = try ClientPrimaryWorkspaceModelV0(macName: "Authenticated Test Mac", primaryState: network.primaryState,
            monotonicNowMilliseconds: { Int64(DispatchTime.now().uptimeNanoseconds / 1_000_000) })
        let source = JourneyReachability()
        self.source = source
        let owner = UIKitClientConfiguredRouteNetworkApplicationOwnerV1(binding: network.binding, source: source,
            failure: { [weak self] error in self?.failure = String(describing: error) })
        self.owner = owner
        try await owner.start()
        phase = "Saved pairing loaded"
        monitor = Task { [weak self] in
            while !Task.isCancelled, let self {
                // Project the production network state before optional
                // test-administration telemetry. A failed/hung diagnostics
                // read must never hide a Control transition from the UI or
                // from acceptance tests.
                let state = network.primaryState.snapshot()
                connected = state.availability == .connected
                let primary = state.authenticatedSession?.connectionID.base64EncodedString() ?? "None"
                if sourceName == "signed-agent", primary != "None", primary != selectedPrimary { authentications += 1 }
                selectedPrimary = primary
                statusError = state.statusError?.code ?? "None"
                if let status = state.observedStatus?.snapshot {
                    let observation = "\(status.generation.rawValue)/\(status.revision)"
                    if sourceName == "signed-agent", observation != verifiedObservation { observations += 1 }
                    verifiedObservation = observation
                }
                control = Self.controlName(state.controlState)
                for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
                    for window in scene.windows { Self.identifyVideo(in: window) }
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        telemetryMonitor = Task { [weak self] in
            while !Task.isCancelled, let self {
                if let report = try? await command("journey-status") {
                    if sourceName != "signed-agent" {
                        observations = report.observations; authentications = report.authentications
                    }
                    hostControl = report.control ?? LabStatus()
                    hostBoot = report.bootID?.uuidString ?? "Unknown"
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }
    func setReachable(_ value: Bool) { source?.set(value) }
    private static func controlName(_ state: NetworkClientPrimaryControlStateV0) -> String {
        switch state {
        case .inactive: "ready"
        case .requestSubmitted: "requesting"
        case .approvalSubmitted: "awaitingAcceptance"
        case .accepted: "acceptedPreparingChannels"
        case let .preparing(_, _, _, phase): String(describing: phase)
        case .active: "active"
        case .ending: "ending"
        case .endFailed: "endFailed"
        case .preparationFailed: "preparationFailed"
        case .remoteRejected: "remoteRejected"
        }
    }
    private static func identifyVideo(in view: UIView) {
        if let surface = view as? UIKitClientLiveSurfaceViewV0 {
            surface.accessibilityIdentifier = "Journey live surface"
        }
        for child in view.subviews { identifyVideo(in: child) }
    }
    func observe() async {
        do { try await workspace?.refreshStatus() }
        catch { failure = String(describing: error) }
    }
    func hostAction(_ action: String) async {
        administration = "Working"
        do { _ = try await command(action); administration = "Completed" }
        catch { failure = String(describing: error); administration = "Failed" }
    }
    private func command(_ action: String) async throws -> JourneyReport {
        guard let fixture else { throw LabError.closed }
        let deadline = ContinuousClock.now + .seconds(3)
        while commandInFlight, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard !commandInFlight else { throw LabError.deadline }
        commandInFlight = true
        defer { commandInFlight = false }
        let connection = try await LabConnection.connect(fixture: fixture, role: "control")
        do {
            try await connection.sendFrame(JSONEncoder().encode(LabCommand(action)))
            let result = try JSONDecoder().decode(JourneyReport.self, from: await connection.readFrame())
            await connection.close(); return result
        } catch { await connection.close(); throw error }
    }
    func close() async {
        monitor?.cancel(); monitor = nil
        telemetryMonitor?.cancel(); telemetryMonitor = nil
        await pairing?.cancel()
        workspace?.stop()
        await owner?.stop(); owner = nil
        await network?.interactiveRoles.close()
        await network?.lifecycle.close()
        network = nil; workspace = nil
    }
}

struct AuthenticatedJourneyView: View {
    @StateObject private var model = AuthenticatedJourneyModel()
    var body: some View {
        VStack(spacing: 4) {
            if model.sourceName == "signed-agent" {
                signedAgentHeader
            } else {
            HStack {
                Text(model.sourceName).accessibilityIdentifier("Lab source")
                Text(model.pinRejectionVerified ? "Verified" : "Pending").accessibilityIdentifier("Journey pin rejection")
                Text(model.hostBoot).accessibilityIdentifier("Journey host boot").lineLimit(1)
            }.font(.caption2)
            HStack {
                Text(model.phase).accessibilityIdentifier("Journey phase")
                Text(model.connected ? "Connected" : "Disconnected").accessibilityIdentifier("Journey connection")
            }
            HStack {
                Text("\(model.saved)").accessibilityIdentifier("Journey saved")
                Text("\(model.observations)").accessibilityIdentifier("Journey observations")
                Text("\(model.authentications)").accessibilityIdentifier("Journey authentications")
                Text(model.failure).accessibilityIdentifier("Journey failure")
            }.font(.caption)
            Text(model.verifiedObservation).accessibilityIdentifier("Journey verified observation").font(.caption2).lineLimit(1)
            Text(model.selectedPrimary).accessibilityIdentifier("Journey primary").font(.caption2).lineLimit(1)
            Text(model.statusError).accessibilityIdentifier("Journey status error").font(.caption2)
            HStack {
                Text(model.control).accessibilityIdentifier("Journey control")
                Text(model.hostControl.captureActive ? "Capturing" : "Stopped").accessibilityIdentifier("Journey capture")
                Text("\(model.hostControl.queuedMediaRecords)").accessibilityIdentifier("Journey queue")
                Text(model.hostControl.directTextMatches ? "Matched" : "Pending").accessibilityIdentifier("Journey text")
                Text("\(model.hostControl.acknowledgements)").accessibilityIdentifier("Journey surface acknowledgements")
            }.font(.caption)
            HStack {
                Text("\(model.hostControl.renewals)").accessibilityIdentifier("Journey renewals")
                Text("\(model.hostControl.renewalAttempts)").accessibilityIdentifier("Journey renewal attempts")
                Text(model.hostControl.renewalFailure ?? "None").accessibilityIdentifier("Journey renewal failure")
                Text(model.hostControl.runtimeIdle ? "Idle" : "Active").accessibilityIdentifier("Journey runtime")
                Button("Lose Renewal") { Task { await model.hostAction("journey-reject-renewal") } }
                Button("Expire Lease") { Task { await model.hostAction("journey-expire-renewal") } }
            }.font(.caption2)
            HStack {
                Button("Pair") { Task { await model.pair() } }.accessibilityIdentifier("Journey pair")
                Button("Wrong Pin") { Task { await model.pair(wrongPin: true) } }.accessibilityIdentifier("Journey wrong pin")
                Button("Drop") { Task { await model.hostAction("journey-drop") } }
                Button("Reopen Host") { Task { await model.hostAction("journey-reopen-store") } }
                Button("Revoke") { Task { await model.hostAction("journey-revoke") } }
                Button("Reset Host") { Task { await model.hostAction("journey-reset") } }
            }.font(.caption)
            HStack {
                Button("Restart Host") { Task { await model.hostAction("journey-restart-process") } }
                Button("Host Off") { Task { await model.hostAction("journey-host-offline") } }
                Button("Host On") { Task { await model.hostAction("journey-host-online") } }
            }.font(.caption)
            HStack {
                Button("Grant Control") { Task { await model.hostAction("journey-grant-control") } }
                Button("Focus") { Task { await model.hostAction("journey-focus") } }
                Button("Observe") { Task { await model.observe() } }.accessibilityIdentifier("Journey observe")
                Button("Offline") { model.setReachable(false) }
                Button("Online") { model.setReachable(true) }
            }.font(.caption)
            }
            if let workspace = model.workspace, let network = model.network {
                ClientPrimaryWorkspaceApplicationViewV1(macName: "Authenticated Test Mac", model: workspace,
                    interactiveRoles: network.interactiveRoles,
                    onCommandFailure: { model.failure = String(describing: $0) })
            } else { Spacer() }
        }
        .task { await model.start() }
    }

    private var signedAgentHeader: some View {
        VStack(spacing: 4) {
            Text("Signed Agent · test-owned consent, media, input and audio").font(.caption2)
            HStack {
                Text(model.phase).accessibilityIdentifier("Journey phase")
                Text(model.connected ? "Connected" : "Disconnected").accessibilityIdentifier("Journey connection")
                Text("\(model.saved)").accessibilityIdentifier("Journey saved")
            }.font(.caption)
            HStack {
                Text(model.failure).accessibilityIdentifier("Journey failure")
                Text("\(model.observations)").accessibilityIdentifier("Journey observations")
                Text(model.administration).accessibilityIdentifier("Signed administration")
            }.font(.caption2)
            Text(model.verifiedObservation).accessibilityIdentifier("Journey verified observation").font(.caption2).lineLimit(1)
            Text(model.selectedPrimary).accessibilityIdentifier("Journey primary").font(.caption2).lineLimit(1)
            HStack {
                Text(model.control).accessibilityIdentifier("Journey control")
                Text(model.hostControl.captureActive ? "Capturing" : "Stopped")
                    .accessibilityIdentifier("Journey capture")
                Text("\(model.hostControl.inputEvents)").accessibilityIdentifier("Signed input events")
                Text("\(model.hostControl.mediaRecords)").accessibilityIdentifier("Signed encoded frames")
                Text("\(model.hostControl.queuedMediaRecords)").accessibilityIdentifier("Journey queue")
                Text("\(model.hostControl.acknowledgements)")
                    .accessibilityIdentifier("Journey surface acknowledgements")
            }.font(.caption2)
            HStack {
                Button("Pair") { Task { await model.pair() } }.accessibilityIdentifier("Journey pair")
                Button("Observe") { Task { await model.observe() } }.accessibilityIdentifier("Journey observe")
            }.buttonStyle(.bordered).font(.caption)
            HStack {
                Button("Grant Act") { Task { await model.hostAction("journey-grant-act") } }
                Button("Grant Control") { Task { await model.hostAction("journey-grant-control") } }
            }.buttonStyle(.bordered).font(.caption)
            HStack {
                Button("Offline") { model.setReachable(false) }
                    .accessibilityIdentifier("Signed offline")
                Button("Online") { model.setReachable(true) }
                    .accessibilityIdentifier("Signed online")
            }.buttonStyle(.bordered).font(.caption)
        }
    }
}
