#if !DEBUG
#error("Authenticated journey host is test-only")
#endif
@testable import CompanionAgent
@testable import CompanionAgentNetworkPlatform
import CompanionAuthentication
import CompanionDiscovery
import CompanionDomain
import CompanionHost
@testable import CompanionHostPlatform
@testable import CompanionHostSession
import CompanionHostWire
import CompanionIPC
import CompanionInteractiveHost
import CompanionInteractiveWire
@testable import CompanionNetworkPlatform
import CompanionPairing
import CompanionOperations
import CompanionPersistence
import CompanionSecurity
import CompanionTransport
import CompanionWire
import CryptoKit
import Foundation
import LiveControlLabSupport
import Network
import Security

func journeyWall() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }
func journeyMono() -> UInt64 { DispatchTime.now().uptimeNanoseconds / 1_000_000 }

private struct JourneyPairingClock: AgentLocalPairingTimeSamplingV0 {
    func currentPairingTime() throws -> AgentLocalPairingTimeSampleV0 {
        try .init(wallNowUnixMilliseconds: journeyWall(), monotonicNowMilliseconds: Int64(journeyMono()))
    }
}

/// Replaces only the local human decision in this disposable host. The exact
/// review and production decision/atomic commit implementation are preserved.
private struct JourneyConsent: AgentHostPairingReviewPublishingV0 {
    let decisions: AgentLocalPairingDecisionHandlerV0
    func publishHostPairingReview(_ review: LocalPairingReviewV0) async throws {
        _ = try await decisions.handle(.init(commandID: UUID(), review: review,
            deviceDisplayName: DeviceDisplayName("Simulator journey"), decision: .approve,
            decidedAtUnixMilliseconds: journeyWall()))
    }
    func withdrawHostPairingReview(reviewID: UUID) async {}
}

private actor JourneySequence: StatusSequenceCommitting {
    func commit(expected: StatusSequenceState, replacement: StatusSequenceState) async throws {}
}

private actor JourneyRoutes: AuthenticatedRouteObservationPublishingV1 {
    func publish(connectionID: Data, routeClass: ConfiguredRouteClassV1, observedAtMonotonicMilliseconds: UInt64) async {}
    func withdraw(connectionID: Data) async {}
}

private struct JourneyUnsupportedCommands: AuthenticatedOperationWireDispatchingV0,
    AuthenticatedCapabilityRegistryDispatchingV1 {
    func dispatch(requestJSON: Data, context: AuthenticatedOperationCommandContextV0,
                  responseMessageID: WireUUID) async throws -> Data { throw LabError.unsupported }
    func dispatch(requestJSON: Data, principal: AuthenticatedDevicePrincipal,
                  responseMessageID: WireUUID, sentAtUnixMilliseconds: Int64) async throws -> Data {
        throw LabError.unsupported
    }
}

actor AuthenticatedJourneyHost {
    let hostID: UUID
    let fixture: LabFixture
    let realTarget: RealMacTarget?
    let directory: URL
    private let identity: SecurityHostIssuedIdentityV0
    private var store: SQLiteSecurityStore
    private var storePath: String
    private var pairing: PairingSessionAuthority
    private var decisions: AgentLocalPairingDecisionHandlerV0
    private var listener: NetworkHostListenerOwnerV0?
    private var primaries: [UUID: NetworkHostPrimaryFramePumpV0] = [:]
    private var primarySessions: [UUID: AuthenticatedPrimarySessionV0] = [:]
    private var countedAuthentications: Set<UUID> = []
    private var interactive: [UUID: JourneyInteractiveDispatcher] = [:]
    // Set only after an interactive role handshake selects the sole primary.
    // Recovery can briefly retain multiple primary dispatchers, so later
    // Control commands must not depend on Dictionary.values ordering.
    private var controlOwnerID: UUID?
    private var pairings: [UUID: AgentNetworkHostPairingConnectionV0] = [:]
    private var status: HostStatusAuthority
    private var tlsCount = 0
    private var authenticatedCount = 0
    private var observeCount = 0
    private var lastDeviceID: UUID?
    private var port: UInt16 = 0
    private let bootID = UUID()

    init(fixture: LabFixture, realTarget: RealMacTarget?, directory: URL) throws {
        self.fixture = fixture; self.realTarget = realTarget
        hostID = fixture.hostID; self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        // Memory-only SecIdentity backed by a disposable software test key so
        // process death can be tested. Never use or mutate the host Keychain.
        let keyURL = directory.appendingPathComponent("software-host-key.bin")
        let key: P256.Signing.PrivateKey
        if FileManager.default.fileExists(atPath: keyURL.path) {
            key = try P256.Signing.PrivateKey(rawRepresentation: Data(contentsOf: keyURL))
        } else {
            key = P256.Signing.PrivateKey()
            try key.rawRepresentation.write(to: keyURL, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyURL.path)
        }
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(key.x963Representation as CFData,
            [kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom, kSecAttrKeyClass: kSecAttrKeyClassPrivate,
             kSecAttrKeySizeInBits: 256] as CFDictionary, &error) else { throw LabError.unsupported }
        identity = try SecurityHostIdentityKeyCustodyV0.assembleIssuedIdentity(privateKey: secKey,
            applicationTag: Data("dev.maccompanion.journey.ephemeral".utf8),
            serialNumber: withUnsafeBytes(of: UUID().uuid) { Data($0) },
            issuanceTimeUnixMilliseconds: journeyWall())
        let pathURL = directory.appendingPathComponent("active-store.txt")
        let storeFile = FileManager.default.fileExists(atPath: pathURL.path)
            ? try String(contentsOf: pathURL, encoding: .utf8) : "security.sqlite3"
        guard storeFile == "security.sqlite3" || (storeFile.hasPrefix("case-") && storeFile.hasSuffix(".sqlite3")
            && UUID(uuidString: String(storeFile.dropFirst(5).dropLast(8))) != nil) else { throw LabError.invalidFrame }
        storePath = directory.appendingPathComponent(storeFile).path
        let store = try SQLiteSecurityStore(path: storePath)
        self.store = store
        let pairing = PairingSessionAuthority(committer: store)
        self.pairing = pairing
        decisions = AgentLocalPairingDecisionHandlerV0(authority: pairing, timeSource: JourneyPairingClock(),
            policySource: StaticAgentLocalPairingPolicySourceV0(.init(rawValue: 1)))
        status = try HostStatusAuthority(hostID: hostID, sequence: .init(generation: UUID()),
            sampler: MacSystemStatusSampler(), clock: SystemHostStatusClock(), sequenceCommitter: JourneySequence())
    }

    func start() async throws -> UInt16 {
        let configuration = try NetworkHostTLSListenerConfigurationV0(issuedIdentity: identity,
            requiredHostFingerprint: identity.key.hostFingerprint, wallNowUnixMilliseconds: journeyWall())
        let (owner, actualPort) = try configuration.makeUnstartedLoopbackListener(
            port: NWEndpoint.Port(rawValue: fixture.journeyPort ?? port) ?? .any)
        listener = owner
        let stream = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
        try owner.start(queue: DispatchQueue(label: "MacCompanion.Journey.listener"),
            ready: { stream.continuation.yield(true) },
            accepted: { [weak self] accepted in
                guard let self else { accepted.cancel(); return }
                do {
                    try accepted.start(queue: DispatchQueue(label: "MacCompanion.Journey.accepted"),
                        ready: { verified in Task { await self.accept(verified) } })
                } catch { accepted.cancel() }
            }, terminal: { _ in stream.continuation.yield(false) })
        for await ready in stream.stream {
            guard ready, let actual = actualPort() else { throw LabError.closed }
            port = actual; return actual
        }
        throw LabError.closed
    }

    func command(_ action: String) async throws -> JourneyReport {
        var qr: String?
        switch action {
        case "journey-restart-process": break // the runner restarts this child after acknowledgement and exit
        case "journey-host-offline":
            listener?.cancel(); listener = nil
            await disconnect()
        case "journey-host-online":
            guard listener == nil else { break }
            _ = try await start()
        case "journey-grant-control":
            let handler = try LocalInteractiveControlGrantHandlerV0(store: store, primary: JourneyGrantFence(host: self))
            let review = try await handler.makeReview(.init(commandID: UUID(), requestedAtUnixMilliseconds: journeyWall()))
            _ = try await handler.decide(review.makeDecisionCommand(commandID: UUID(), decision: .approve,
                decidedAtUnixMilliseconds: journeyWall()))
        case "journey-focus":
            try await controlOwner()?.focus()
        case "journey-reject-renewal":
            try await controlOwner()?.renewalFault("reject-renewal")
        case "journey-expire-renewal":
            try await controlOwner()?.renewalFault("expire-renewal")
        case "journey-reset":
            await disconnect()
            storePath = directory.appendingPathComponent("case-\(UUID()).sqlite3").path
            try Data(URL(fileURLWithPath: storePath).lastPathComponent.utf8)
                .write(to: directory.appendingPathComponent("active-store.txt"), options: .atomic)
            store = try SQLiteSecurityStore(path: storePath)
            pairing = PairingSessionAuthority(committer: store)
            decisions = AgentLocalPairingDecisionHandlerV0(authority: pairing, timeSource: JourneyPairingClock(),
                policySource: StaticAgentLocalPairingPolicySourceV0(.init(rawValue: 1)))
            lastDeviceID = nil
        case "journey-pair", "journey-wrong-pin":
            let advertisement = try await pairing.createSession(hostFingerprint: identity.key.hostFingerprint,
                wallNowUnixMilliseconds: journeyWall(), monotonicNowMilliseconds: Int64(journeyMono()))
            qr = try PairingQRCodeCodec.encode(.init(pairingID: .init(advertisement.pairingID),
                oneTimeSecret: .init(advertisement.oneTimeSecret), expiresAtUnixMilliseconds: advertisement.expiresAtUnixMilliseconds,
                hostFingerprint: .init(action == "journey-wrong-pin" ? Data(repeating: 0, count: 32) : identity.key.hostFingerprint),
                endpoints: [.init(kind: .ipv4, value: "127.0.0.1", port: port)]))
        case "journey-drop":
            await disconnect()
        case "journey-reopen-store":
            await disconnect()
            // Reopen the durable store and discard all previous authorities.
            store = try SQLiteSecurityStore(path: storePath)
            pairing = PairingSessionAuthority(committer: store)
            decisions = AgentLocalPairingDecisionHandlerV0(authority: pairing, timeSource: JourneyPairingClock(),
                policySource: StaticAgentLocalPairingPolicySourceV0(.init(rawValue: 1)))
        case "journey-revoke":
            guard let lastDeviceID else { throw LabError.unauthorized }
            _ = try await store.transitionDevice(lastDeviceID, event: .revoke, occurredAtUnixMilliseconds: journeyWall())
            await disconnect()
        case "journey-status": break
        default: throw LabError.unsupported
        }
        for (id, session) in primarySessions {
            if await session.authenticatedPrimaryConnectionID() != nil,
               countedAuthentications.insert(id).inserted { authenticatedCount += 1 }
        }
        return JourneyReport(qr: qr, pairedDevices: try await store.activePairedDeviceCount(),
            tlsConnections: tlsCount, authentications: authenticatedCount, observations: observeCount,
            control: await controlOwner()?.report(), bootID: bootID)
    }

    func disconnect() async {
        let old = primaries; primaries.removeAll()
        primarySessions.removeAll()
        for pump in old.values { await pump.cancel() }
        let oldPairings = pairings; pairings.removeAll()
        for connection in oldPairings.values { await connection.cancel() }
        interactive.removeAll()
        controlOwnerID = nil
    }

    private func accept(_ verified: NetworkHostVerifiedReadyConnectionV0) async {
        tlsCount += 1
        do {
            let classifier = try NetworkHostIngressClassifierV0(verifiedReadyConnection: verified,
                acceptedAtMonotonicMilliseconds: journeyMono(), monotonicNowMilliseconds: journeyMono)
            let classified = try await classifier.classify()
            let id = UUID()
            switch classified.role {
            case .pairing:
                let factory = AgentNetworkHostPairingConnectionFactoryV0(hostID: hostID, authority: pairing,
                    recovery: SQLiteAgentHostPairingRecoveryAuthorityV0(store: store), decisions: decisions,
                    reviewPublisher: JourneyConsent(decisions: decisions))
                let connection = try await factory.bind(classifiedConnection: classified,
                    acceptedAtMonotonicMilliseconds: journeyMono(), context: {
                        .init(wallNowUnixMilliseconds: journeyWall(), monotonicNowMilliseconds: journeyMono(), responseMessageID: .init(UUID()))
                    },
                    terminal: { [weak self] _ in Task { await self?.removePairing(id) } })
                pairings[id] = connection
                try await connection.begin()
            case .applicationPrimary:
                let interactive = JourneyInteractiveDispatcher(fixture: fixture, realTarget: realTarget, store: store)
                let observed = JourneyObservedStatus(host: self, status: status)
                let session = try AuthenticatedPrimarySessionV0(hostID: hostID, tlsBinding: classified.tlsBinding,
                    acceptedAtMonotonicMilliseconds: journeyMono(),
                    authentication: ApplicationAuthenticationAuthority(deviceReader: store), status: observed,
                    operations: JourneyUnsupportedCommands(), capabilities: JourneyUnsupportedCommands(), interactive: interactive,
                    routeObservationPublisher: JourneyRoutes())
                let pump = try NetworkHostPrimaryFramePumpV0(classifiedConnection: classified, session: session,
                    context: Self.context, terminal: { [weak self] reason in
                        FileHandle.standardError.write(Data("JOURNEY_PRIMARY_ENDED \(reason.rawValue)\n".utf8))
                        Task { await self?.removePrimary(id) }
                    })
                primaries[id] = pump
                primarySessions[id] = session
                self.interactive[id] = interactive
                await interactive.bind(pump)
                try await pump.beginOnClassifiedConnection()
                let activeDevices = try await store.activeDeviceGrantIdentitySnapshots()
                if activeDevices.count == 1 {
                    lastDeviceID = activeDevices[0].device.deviceID
                }
            case .interactiveInput, .interactiveMedia:
                guard interactive.count == 1, let (ownerID, owner) = interactive.first else {
                    classified.cancel(); throw LabError.unauthorized
                }
                let handshake = try NetworkHostInteractiveRoleConnectionV0(classifiedConnection: classified,
                    authenticator: owner)
                let ready = try await handshake.beginOnClassifiedConnection()
                controlOwnerID = ownerID
                try await owner.attach(ready)
            }
        } catch {
            verified.cancel()
            FileHandle.standardError.write(Data("JOURNEY_CONNECTION_ENDED \(type(of: error))\n".utf8))
        }
    }

    private func removePairing(_ id: UUID) { pairings[id] = nil }
    private func controlOwner() -> JourneyInteractiveDispatcher? {
        guard let controlOwnerID else { return nil }
        return interactive[controlOwnerID]
    }
    private func removePrimary(_ id: UUID) {
        primaries[id] = nil; primarySessions[id] = nil; interactive[id] = nil
        if controlOwnerID == id { controlOwnerID = nil }
    }
    func observed() { observeCount += 1 }
    nonisolated private static func context() -> NetworkHostRequestContextV0 {
        .init(hostState: .userSessionActive, wallNowUnixMilliseconds: journeyWall(),
            monotonicNowMilliseconds: journeyMono(), responseMessageID: .init(UUID()))
    }
}

private struct JourneyObservedStatus: HostStatusSnapshotProvidingV0 {
    let host: AuthenticatedJourneyHost
    let status: HostStatusAuthority
    func snapshot(hostState: HostState) async throws -> HostStatusSnapshot {
        do {
            let result = try await status.snapshot(hostState: hostState)
            await host.observed()
            return result
        } catch {
            // These local sampler errors contain only fixed syscall/metric
            // identifiers and numeric status, never captured/input content.
            if let sample = error as? MacSystemStatusSamplerError {
                FileHandle.standardError.write(Data("JOURNEY_STATUS_FAILED \(sample)\n".utf8))
            }
            throw error
        }
    }
}

private struct JourneyGrantFence: AgentDeviceRevocationPrimaryFencingV0 {
    let host: AuthenticatedJourneyHost
    func fenceForSecurityAdministration() async { await host.disconnect() }
    func releaseSecurityAdministrationFence() async {}
}
