#if !DEBUG
#error("Journey transport is test-only")
#endif
import CompanionAuthentication
import CompanionDomain
import CompanionHostSession
import CompanionIPC
import CompanionInteractiveHost
import CompanionInteractiveWire
import CompanionNetworkPlatform
import CompanionPersistence
import CompanionSecurity
import CompanionWire
import Foundation
import LiveControlLabSupport

/// In-process bridge to the existing owned-window runtime. It never declares a
/// socket authenticated: only the production primary dispatcher can call it.
actor JourneyCommandBridge: LabByteConnection {
    private var reader: CheckedContinuation<Data, Error>?
    private var response: CheckedContinuation<Data, Error>?
    private var pending: Data?
    private var closed = false
    let event: @Sendable (Data) async throws -> Void
    let received: @Sendable (Data) async throws -> Void
    init(event: @escaping @Sendable (Data) async throws -> Void,
         received: @escaping @Sendable (Data) async throws -> Void) {
        self.event = event; self.received = received
    }
    func exchange(_ frame: Data) async throws -> Data {
        guard !closed, response == nil else { throw LabError.closed }
        return try await withCheckedThrowingContinuation { continuation in
            response = continuation
            if let reader { self.reader = nil; reader.resume(returning: frame) }
            else { pending = frame }
        }
    }
    func readFrame() async throws -> Data {
        guard !closed, reader == nil else { throw LabError.closed }
        if let pending { self.pending = nil; return pending }
        return try await withCheckedThrowingContinuation { reader = $0 }
    }
    func sendFrame(_ frame: Data) async throws {
        guard !closed else { throw LabError.closed }
        let header = try JSONSerialization.jsonObject(with: frame) as? [String: Any]
        if header?["channel"] as? String == "events" { try await event(frame); return }
        try await received(frame)
        guard let response else { throw LabError.invalidFrame }
        self.response = nil; response.resume(returning: frame)
    }
    func read(_ count: Int) async throws -> Data { throw LabError.unsupported }
    func send(_ data: Data) async throws { throw LabError.unsupported }
    func close() {
        guard !closed else { return }; closed = true
        let reader = reader; self.reader = nil
        let response = response; self.response = nil
        reader?.resume(throwing: LabError.closed); response?.resume(throwing: LabError.closed)
        pending = nil
    }
}

/// Role traffic enters only after TLS and the production mutual-HMAC pump.
private actor JourneyRoleBytes: LabByteConnection {
    let connection: NetworkHostInteractiveReadyRoleConnectionV0
    init(_ connection: NetworkHostInteractiveReadyRoleConnectionV0) { self.connection = connection }
    func read(_ count: Int) async throws -> Data {
        guard (0...4_194_304).contains(count) else { throw LabError.invalidFrame }
        var result = Data()
        while result.count < count {
            let chunk = try await connection.receiveRoleBytes(maximumLength: count - result.count)
            guard !chunk.data.isEmpty else { throw LabError.closed }
            result.append(chunk.data)
        }
        return result
    }
    func readFrame() async throws -> Data {
        let count = try await read(4).reduce(0) { ($0 << 8) | Int($1) }
        return try await read(count)
    }
    func send(_ data: Data) async throws { try await connection.sendRoleBytes(data) }
    func sendFrame(_ data: Data) async throws { throw LabError.unsupported }
    func close() async { await connection.cancel() }
}

actor JourneyInteractiveDispatcher: AuthenticatedInteractiveWireDispatchingV0, HostInteractiveChannelAuthenticatingV0 {
    let baseFixture: LabFixture
    let realTarget: RealMacTarget?
    let store: SQLiteSecurityStore
    private var primary: NetworkHostPrimaryFramePumpV0?
    private var session: HostSession?
    private var bridge: JourneyCommandBridge?
    private var approval: InteractiveApprovalAuthority?
    private var approvalState: InteractiveApprovalCurrentState?
    private var channelState: InteractiveChannelCurrentState?
    private var authorities: [UUID: InteractiveChannelCredentialAuthority] = [:]
    private var roles: [UUID: InteractiveChannelRoleName] = [:]
    private var closed = false
    private let secondDisplayID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000002"
    )!
    private var selectedDisplayID: UUID
    private var displayAdmissionRevision: Int64 = 1
    private var activeDisplayOrdinal: Int?
    private var displayCatalogRequests = 0
    init(fixture: LabFixture, realTarget: RealMacTarget?, store: SQLiteSecurityStore) {
        baseFixture = fixture; self.realTarget = realTarget; self.store = store
        selectedDisplayID = fixture.displayID
    }
    func bind(_ primary: NetworkHostPrimaryFramePumpV0) { self.primary = primary }
    func dispatch(requestJSON: Data, context: AuthenticatedInteractiveCommandContextV0,
                  responseMessageID: WireUUID) async throws -> Data {
        guard !closed, let record = try await store.device(context.principal.deviceID),
              record.authorization.state == .activeGranted,
              record.authorization.authorizationEpoch == context.principal.authorizationEpoch,
              try await store.deviceGrants(record.deviceID).capabilityIDs.contains(InteractiveControlDurableGrantV0.identifier)
        else { throw LabError.unauthorized }
        let kind = try WireCodec.messageKind(from: requestJSON)
        if kind == .interactiveDisplayCatalogRequest {
            let request = try WireCodec.decode(
                WireEnvelope<InteractiveDisplayCatalogRequestBodyV1>.self,
                from: requestJSON
            )
            guard request.body.authorizationEpoch
                    == context.principal.authorizationEpoch else {
                throw LabError.unauthorized
            }
            displayCatalogRequests += 1
            return try WireCodec.encode(WireEnvelope(
                messageID: responseMessageID,
                correlationID: request.messageID,
                sentAtUnixMilliseconds: journeyWall(),
                body: try makeDisplayCatalog(
                    authorizationEpoch:
                        context.principal.authorizationEpoch
                )
            ))
        }
        if kind == .interactiveDisplaySelect {
            let request = try WireCodec.decode(
                WireEnvelope<InteractiveDisplaySelectBodyV1>.self,
                from: requestJSON
            )
            guard bridge == nil,
                  request.body.authorizationEpoch
                    == context.principal.authorizationEpoch,
                  request.body.expectedAdmissionRevision
                    == displayAdmissionRevision,
                  request.body.displayID.rawValue == baseFixture.displayID
                    || request.body.displayID.rawValue == secondDisplayID,
                  request.body.displayID.rawValue != selectedDisplayID,
                  displayAdmissionRevision
                    < WireLimits.maximumSafeInteger else {
                throw LabError.unauthorized
            }
            selectedDisplayID = request.body.displayID.rawValue
            displayAdmissionRevision += 1
            return try WireCodec.encode(WireEnvelope(
                messageID: responseMessageID,
                correlationID: request.messageID,
                sentAtUnixMilliseconds: journeyWall(),
                body: try InteractiveDisplaySelectedBodyV1(
                    authorizationEpoch:
                        context.principal.authorizationEpoch,
                    admissionRevision: displayAdmissionRevision,
                    selectedDisplayID: request.body.displayID
                )
            ))
        }
        if kind == .interactiveSessionRequest {
            await retireControl()
            var fixture = baseFixture
            fixture.clientID = record.clientID; fixture.deviceID = record.deviceID
            fixture.fingerprint = context.hostFingerprint; fixture.connectionID = context.primaryConnectionID
            fixture.approvalPublicKey = record.approvalPublicKeyX963
            fixture.authorizationEpoch = record.authorization.authorizationEpoch.rawValue
            fixture.grantRevision = record.authorization.grantRevision.rawValue
            fixture.displayID = selectedDisplayID
            approvalState = .init(clientID: record.clientID, primaryConnectionID: context.primaryConnectionID,
                authorizationEpoch: record.authorization.authorizationEpoch.rawValue,
                grantRevision: record.authorization.grantRevision.rawValue, policyRevision: record.policyRevision.rawValue,
                approvalPublicKeyX963: record.approvalPublicKeyX963)
            let bridge = JourneyCommandBridge(event: { [weak self] frame in
                guard let pump = await self?.primary else { throw LabError.closed }
                try await pump.sendAuthenticatedEvent(frame)
            }, received: { [weak self] frame in try await self?.received(frame) })
            let session = try HostSession(fixture: fixture, primary: bridge, realTarget: realTarget, usesAgentRenewal: true)
            self.bridge = bridge; self.session = session
            activeDisplayOrdinal = selectedDisplayID == baseFixture.displayID
                ? 1 : 2
            await session.prepare()
            Task { await session.start() }
        } else if kind == .interactiveSessionApprove {
            let proof = try WireCodec.decode(WireEnvelope<InteractiveApprovalProofBody>.self, from: requestJSON)
            guard var authority = approval, let state = approvalState else { throw LabError.unauthorized }
            defer { approval = authority }
            _ = try authority.verifyAndConsume(rawSignature: proof.body.signature.rawValue, current: state,
                monotonicNowMilliseconds: journeyMono())
        }
        if kind == .interactiveSessionEnd, let session, await session.report().closed {
            // Runtime may already have retired after a renewal error. The
            // authenticated primary still owns the exact accepted session and
            // can acknowledge its Stop without reopening capture or roles.
            let request = try WireCodec.decode(WireEnvelope<InteractiveSessionEndBodyV0>.self, from: requestJSON)
            let retiredSessionID = await session.sessionID
            guard request.body.interactiveSessionID.rawValue == retiredSessionID,
                  request.body.authorizationEpoch.rawValue == context.principal.authorizationEpoch.rawValue else {
                throw LabError.unauthorized
            }
            await retireControl()
            return try WireCodec.encode(WireEnvelope(messageID: responseMessageID,
                correlationID: request.messageID, sentAtUnixMilliseconds: journeyWall(),
                body: InteractiveSessionEndedBodyV0(interactiveSessionID: request.body.interactiveSessionID,
                    authorizationEpoch: request.body.authorizationEpoch, endedAtUnixMilliseconds: journeyWall())))
        }
        guard let bridge else { throw LabError.closed }
        if kind == .interactiveSurfaceSelect {
            let selection = try WireCodec.decode(
                WireEnvelope<InteractiveSurfaceSelectBodyV0>.self,
                from: requestJSON
            )
            if let displayID = selection.body.targetDisplayID?.rawValue {
                guard selection.body.targetKind == .desktop,
                      displayID == baseFixture.displayID
                        || displayID == secondDisplayID,
                      displayID != selectedDisplayID,
                      displayAdmissionRevision
                        < WireLimits.maximumSafeInteger else {
                    throw LabError.unauthorized
                }
                selectedDisplayID = displayID
                displayAdmissionRevision += 1
                activeDisplayOrdinal = displayID == baseFixture.displayID
                    ? 1 : 2
            }
        }
        let result = try await bridge.exchange(requestJSON)
        if kind == .interactiveSessionEnd {
            // Wait for runtime/input/media retirement before reporting Stop.
            // The authenticated Observe primary deliberately remains open.
            await retireControl()
        }
        return result
    }

    private func makeDisplayCatalog(
        authorizationEpoch: AuthorizationEpoch
    ) throws -> InteractiveDisplayCatalogResponseBodyV1 {
        try InteractiveDisplayCatalogResponseBodyV1(
            authorizationEpoch: authorizationEpoch,
            admissionRevision: displayAdmissionRevision,
            selectedDisplayID: WireUUID(selectedDisplayID),
            validForMilliseconds: 5_000,
            displays: [
                try InteractiveDisplayCandidateV1(
                    displayID: WireUUID(baseFixture.displayID),
                    ordinal: 1,
                    pixelWidth: 1512,
                    pixelHeight: 982,
                    isMain: true
                ),
                try InteractiveDisplayCandidateV1(
                    displayID: WireUUID(secondDisplayID),
                    ordinal: 2,
                    pixelWidth: 2560,
                    pixelHeight: 1440,
                    isMain: false
                ),
            ]
        )
    }
    private func received(_ frame: Data) throws {
        switch try WireCodec.messageKind(from: frame) {
        case .interactiveSessionApprovalRequired:
            let body = try WireCodec.decode(WireEnvelope<InteractiveApprovalChallengeBody>.self, from: frame).body
            guard let state = approvalState else { throw LabError.unauthorized }
            approval = try .init(hostID: body.hostID.rawValue, hostFingerprint: body.hostFingerprint.rawValue,
                clientID: body.clientID.rawValue, primaryConnectionID: body.primaryConnectionID.rawValue,
                requestID: body.requestID.rawValue, approvalID: body.approvalID.rawValue,
                serverChallenge: body.serverChallenge.rawValue, authorizationEpoch: body.authorizationEpoch.rawValue,
                grantRevision: body.grantRevision.rawValue, policyRevision: body.policyRevision.rawValue,
                selectedDisplayID: body.selectedDisplayID.rawValue, initialSurface: .desktop,
                effects: body.effects.securityEffects,
                issuedAtUnixMilliseconds: UInt64(body.issuedAtUnixMilliseconds),
                expiresAtUnixMilliseconds: UInt64(body.expiresAtUnixMilliseconds),
                approvalPublicKeyX963: state.approvalPublicKeyX963,
                issuedAtMonotonicMilliseconds: journeyMono(), expiresAtMonotonicMilliseconds: journeyMono() + 60_000)
        case .interactiveSessionAccepted:
            let body = try WireCodec.decode(WireEnvelope<InteractiveSessionAcceptedBody>.self, from: frame).body
            guard let state = approvalState else { throw LabError.unauthorized }
            channelState = .init(clientID: state.clientID, primaryConnectionID: state.primaryConnectionID,
                interactiveSessionID: body.interactiveSessionID.rawValue, authorizationEpoch: state.authorizationEpoch)
            for offer in [body.inputChannel, body.mediaChannel] {
                authorities[offer.channelID.rawValue] = try .init(channelID: offer.channelID.rawValue,
                    role: offer.role == .input ? .input : .media, credential: offer.credential.rawValue,
                    hostID: baseFixture.hostID, hostFingerprint: session!.fixture.fingerprint,
                    clientID: state.clientID, primaryConnectionID: state.primaryConnectionID,
                    interactiveSessionID: body.interactiveSessionID.rawValue, authorizationEpoch: state.authorizationEpoch,
                    issuedAtMonotonicMilliseconds: journeyMono(), expiresAtMonotonicMilliseconds: journeyMono() + 29_999)
                roles[offer.channelID.rawValue] = offer.role
            }
        default: break
        }
    }
    func beginInteractiveChannel(hello: InteractiveChannelHelloBody, hostNonce: WireBytes32,
                                 monotonicNowMilliseconds: UInt64) throws -> InteractiveChannelChallengeBody {
        guard var authority = authorities[hello.channelID.rawValue], roles[hello.channelID.rawValue] == hello.role,
              let current = channelState, matches(hello, current) else { throw LabError.unauthorized }
        defer { authorities[hello.channelID.rawValue] = authority }
        _ = try authority.beginChallenge(clientNonce: hello.clientNonce.rawValue, hostNonce: hostNonce.rawValue,
            current: current, monotonicNowMilliseconds: monotonicNowMilliseconds)
        return .init(channelID: hello.channelID, role: hello.role, hostID: .init(baseFixture.hostID),
            hostFingerprint: try .init(session!.fixture.fingerprint), hostNonce: hostNonce)
    }
    func consumeInteractiveChannel(hello: InteractiveChannelHelloBody, proof: InteractiveChannelProofBody,
                                   monotonicNowMilliseconds: UInt64) throws -> InteractiveChannelAcceptedBody {
        guard var authority = authorities[hello.channelID.rawValue], proof.channelID == hello.channelID,
              let current = channelState, matches(hello, current) else { throw LabError.unauthorized }
        defer { authorities[hello.channelID.rawValue] = authority }
        let accepted = try authority.verifyAndConsume(clientProof: proof.clientProof.rawValue,
            current: current, monotonicNowMilliseconds: monotonicNowMilliseconds)
        return .init(channelID: hello.channelID, role: hello.role, serverProof: try .init(accepted.serverProof))
    }
    func invalidateInteractiveChannel(channelID: UUID, role: InteractiveChannelRoleName) {
        authorities[channelID]?.invalidate()
    }
    private func matches(_ hello: InteractiveChannelHelloBody, _ current: InteractiveChannelCurrentState) -> Bool {
        !closed && hello.clientID.rawValue == current.clientID && hello.primaryConnectionID.rawValue == current.primaryConnectionID
            && hello.interactiveSessionID.rawValue == current.interactiveSessionID
            && hello.authorizationEpoch.rawValue == current.authorizationEpoch
    }
    func attach(_ connection: NetworkHostInteractiveReadyRoleConnectionV0) async throws {
        guard let session, let current = channelState, !closed,
              connection.channel.primaryConnectionID.rawValue == current.primaryConnectionID,
              connection.channel.interactiveSessionID.rawValue == current.interactiveSessionID else {
            await connection.cancel(); throw LabError.unauthorized
        }
        try await session.attach(JourneyRoleBytes(connection), role: connection.channel.role.rawValue)
    }
    func report() async -> LabStatus {
        var report = await session?.report() ?? LabStatus()
        report.selectedDisplayOrdinal =
            selectedDisplayID == baseFixture.displayID ? 1 : 2
        report.activeDisplayOrdinal = activeDisplayOrdinal
        report.displayCatalogRequests = displayCatalogRequests
        return report
    }
    func focus() async throws { try await session?.control("focus") }
    func renewalFault(_ action: String) async throws { try await session?.control(action) }
    private func retireControl() async {
        authorities.removeAll(); roles.removeAll(); channelState = nil; approval = nil
        if let session { await session.close() }
        bridge = nil
        activeDisplayOrdinal = nil
    }
    func primarySessionClosed() async {
        guard !closed else { return }; closed = true
        await retireControl(); primary = nil
    }
}
