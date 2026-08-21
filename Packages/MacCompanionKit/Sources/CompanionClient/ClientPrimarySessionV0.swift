import CompanionDomain
import CompanionSecurity
import CompanionTransport
import CompanionWire
import Foundation

public protocol ClientSessionAuthenticationSigningV0: Sendable {
    /// Returns the fixed-width 64-byte P-256 `r || s` signature required by
    /// the v0.1 crypto profile. Key custody remains outside this module.
    func signAuthenticationInput(_ input: Data) async throws -> Data
}

public enum ClientPrimarySessionPhaseV0: String, Equatable, Sendable {
    case awaitingTCP
    case awaitingPinnedTLS
    case readyToAuthenticate
    case awaitingChallenge
    case awaitingDescription
    case authenticated
    case closed
}

public enum ClientPrimarySessionErrorV0: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidClock
    case authenticationDeadlineExceeded
    case invalidPhase(ClientPrimarySessionPhaseV0)
    case unexpectedMessage(WireMessageKind)
    case invalidCorrelation
    case duplicateMessage(WireUUID)
    case hostFingerprintMismatch
    case hostIdentityMismatch
    case deviceIdentityMismatch
    case invalidSignatureLength
    case configuredRouteUnavailable
    case routeObservationPending
    case remoteError(code: String, retry: ProtocolErrorRetry)
}

public struct ClientAuthenticatedSessionV0: Equatable, Sendable {
    public let clientID: UUID
    public let hostID: UUID
    public let deviceID: UUID
    public let connectionID: Data
    public let deviceState: DeviceAuthorizationState
    public let authorizationEpoch: AuthorizationEpoch
    public let grantRevision: GrantRevision
    public let policyRevision: PolicyRevision
    public let hostState: HostState
    public let features: [String]
    public let serverTimeUnixMilliseconds: Int64
}

/// Bundle-independent client owner for one application-primary connection.
/// It admits no application-authentication bytes before pinned TLS succeeds,
/// owns exact handshake correlation and replay, and publishes no authenticated
/// identity until `session.describe.response` matches the paired host/device.
public actor ClientPrimarySessionV0 {
    public let clientID: UUID
    public let expectedHostID: UUID
    public let expectedDeviceID: UUID
    public let requiredHostFingerprint: Data
    public private(set) var phase: ClientPrimarySessionPhaseV0 = .awaitingTCP
    public private(set) var authenticatedSession: ClientAuthenticatedSessionV0?

    private let signer: any ClientSessionAuthenticationSigningV0
    private let configuredRoute: ClientConfiguredRouteRecordV1?
    private var transport: PinnedTLSConnectionAuthority
    private var replay = ConnectionReplayWindow()
    private var lastMonotonicMilliseconds: UInt64?
    private var authenticationDeadlineMonotonicMilliseconds: UInt64?
    private var clientNonce: Data?
    private var helloMessageID: WireUUID?
    private var challengeMessageID: WireUUID?
    private var proofMessageID: WireUUID?
    private var connectionID: Data?
    private var routeObservationSequence: Int64 = 0
    private var pendingRouteObservation:
        WireEnvelope<RouteObservationBodyV1>?
    private var lastRouteObservationMonotonicMilliseconds: UInt64?

    package init(
        clientID: UUID,
        expectedHostID: UUID,
        expectedDeviceID: UUID,
        requiredHostFingerprint: Data,
        signer: any ClientSessionAuthenticationSigningV0,
        configuredRoute: ClientConfiguredRouteRecordV1? = nil
    ) throws {
        guard requiredHostFingerprint.count == 32 else {
            throw ClientPrimarySessionErrorV0.invalidConfiguration
        }
        self.clientID = clientID
        self.expectedHostID = expectedHostID
        self.expectedDeviceID = expectedDeviceID
        self.requiredHostFingerprint = requiredHostFingerprint
        self.signer = signer
        self.configuredRoute = configuredRoute
        transport = try PinnedTLSConnectionAuthority(
            role: .applicationPrimary,
            requiredHostFingerprint: requiredHostFingerprint
        )
    }

    public var pinnedTLSPhase: PinnedTLSConnectionPhase {
        transport.phase
    }

    public func didConnectTCP(at monotonicNowMilliseconds: UInt64) throws {
        do {
            try requirePhase(.awaitingTCP)
            try observe(monotonicNowMilliseconds)
            let lifetime = UInt64(
                V0ConnectionTiming.authenticationNanoseconds / 1_000_000
            )
            let (deadline, overflow) = monotonicNowMilliseconds
                .addingReportingOverflow(lifetime)
            guard !overflow, deadline <= UInt64(Int64.max) else {
                throw ClientPrimarySessionErrorV0.invalidClock
            }
            try transport.didConnectTCP()
            authenticationDeadlineMonotonicMilliseconds = deadline
            phase = .awaitingPinnedTLS
        } catch {
            terminate()
            throw error
        }
    }

    public func acceptPinnedPeer(
        _ evidence: TLSPeerEvidence,
        at monotonicNowMilliseconds: UInt64
    ) throws {
        do {
            try requirePhase(.awaitingPinnedTLS)
            try observeAndEnforceAuthenticationDeadline(monotonicNowMilliseconds)
            try transport.acceptPeer(evidence)
            phase = .readyToAuthenticate
        } catch {
            terminate()
            throw error
        }
    }

    public func beginAuthentication(
        clientNonce: WireBytes32,
        messageID: WireUUID,
        sentAtUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64
    ) throws -> Data {
        do {
            try requirePhase(.readyToAuthenticate)
            try observeAndEnforceAuthenticationDeadline(monotonicNowMilliseconds)
            try transport.admit(.applicationAuthentication)
            try admitReplay(messageID)
            let request = try WireEnvelope(
                messageID: messageID,
                correlationID: nil,
                sentAtUnixMilliseconds: sentAtUnixMilliseconds,
                body: try AuthHelloBody(
                    clientID: WireUUID(clientID),
                    clientNonce: clientNonce
                )
            )
            self.clientNonce = clientNonce.rawValue
            helloMessageID = messageID
            phase = .awaitingChallenge
            return try WireCodec.encode(request)
        } catch {
            terminate()
            throw error
        }
    }

    public func receiveChallenge(
        _ responseJSON: Data,
        proofMessageID: WireUUID,
        sentAtUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64
    ) async throws -> Data {
        do {
            try requirePhase(.awaitingChallenge)
            try observeAndEnforceAuthenticationDeadline(monotonicNowMilliseconds)
            try transport.admit(.applicationAuthentication)
            let kind = try WireCodec.messageKind(from: responseJSON)
            if kind == .error {
                try receiveRemoteError(responseJSON, expectedCorrelation: helloMessageID)
            }
            guard kind == .authChallenge else {
                throw ClientPrimarySessionErrorV0.unexpectedMessage(kind)
            }
            let challenge = try WireCodec.decode(
                WireEnvelope<AuthChallengeBody>.self,
                from: responseJSON
            )
            try admitReplay(challenge.messageID)
            guard challenge.correlationID == helloMessageID,
                  let clientNonce else {
                throw ClientPrimarySessionErrorV0.invalidCorrelation
            }
            guard challenge.body.hostFingerprint.rawValue == requiredHostFingerprint else {
                throw ClientPrimarySessionErrorV0.hostFingerprintMismatch
            }
            try admitReplay(proofMessageID)
            let signingInput = try CompanionSecurityV0.authenticationSigningInput(
                clientID: clientID,
                connectionID: challenge.body.connectionID.rawValue,
                clientNonce: clientNonce,
                serverNonce: challenge.body.serverNonce.rawValue,
                hostFingerprint: requiredHostFingerprint,
                selectedMajor: challenge.body.selectedVersion.major,
                selectedMinor: challenge.body.selectedVersion.minor
            )
            let signature = try await signer.signAuthenticationInput(signingInput)
            guard signature.count == 64 else {
                throw ClientPrimarySessionErrorV0.invalidSignatureLength
            }
            let proof = try WireEnvelope(
                messageID: proofMessageID,
                correlationID: challenge.messageID,
                sentAtUnixMilliseconds: sentAtUnixMilliseconds,
                body: AuthProofBody(signature: try WireBytes64(signature))
            )
            challengeMessageID = challenge.messageID
            self.proofMessageID = proofMessageID
            connectionID = challenge.body.connectionID.rawValue
            phase = .awaitingDescription
            return try WireCodec.encode(proof)
        } catch {
            terminate()
            throw error
        }
    }

    @discardableResult
    public func receiveSessionDescription(
        _ responseJSON: Data,
        monotonicNowMilliseconds: UInt64
    ) throws -> ClientAuthenticatedSessionV0 {
        do {
            try requirePhase(.awaitingDescription)
            try observeAndEnforceAuthenticationDeadline(monotonicNowMilliseconds)
            try transport.admit(.applicationAuthentication)
            let kind = try WireCodec.messageKind(from: responseJSON)
            if kind == .error {
                try receiveRemoteError(responseJSON, expectedCorrelation: proofMessageID)
            }
            guard kind == .sessionDescribeResponse else {
                throw ClientPrimarySessionErrorV0.unexpectedMessage(kind)
            }
            let response = try WireCodec.decode(
                WireEnvelope<SessionDescriptionBody>.self,
                from: responseJSON
            )
            try admitReplay(response.messageID)
            guard response.correlationID == proofMessageID else {
                throw ClientPrimarySessionErrorV0.invalidCorrelation
            }
            guard response.body.hostID.rawValue == expectedHostID else {
                throw ClientPrimarySessionErrorV0.hostIdentityMismatch
            }
            guard response.body.deviceID.rawValue == expectedDeviceID else {
                throw ClientPrimarySessionErrorV0.deviceIdentityMismatch
            }
            guard let connectionID else {
                throw ClientPrimarySessionErrorV0.invalidCorrelation
            }
            let result = ClientAuthenticatedSessionV0(
                clientID: clientID,
                hostID: response.body.hostID.rawValue,
                deviceID: response.body.deviceID.rawValue,
                connectionID: connectionID,
                deviceState: response.body.deviceState,
                authorizationEpoch: response.body.authorizationEpoch,
                grantRevision: response.body.grantRevision,
                policyRevision: response.body.policyRevision,
                hostState: response.body.hostState,
                features: response.body.features,
                serverTimeUnixMilliseconds: response.body.serverTimeUnixMilliseconds
            )
            try transport.roleAuthenticationSucceeded()
            authenticatedSession = result
            phase = .authenticated
            clearHandshakeSecrets()
            return result
        } catch {
            terminate()
            throw error
        }
    }

    public func admitAuthenticatedTraffic(
        _ traffic: PinnedTLSTrafficClass
    ) throws {
        do {
            try requirePhase(.authenticated)
            guard traffic == .commandFrame || traffic == .eventFrame else {
                throw ClientPrimarySessionErrorV0.invalidConfiguration
            }
            try transport.admit(traffic)
        } catch {
            terminate()
            throw error
        }
    }

    /// Creates the initial configured-route observation or a later heartbeat.
    /// Bonjour and direct-address records intentionally produce no message.
    public func beginConfiguredRouteObservation(
        messageID: WireUUID,
        sentAtUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64
    ) throws -> Data? {
        do {
            try requirePhase(.authenticated)
            try observe(monotonicNowMilliseconds)
            guard pendingRouteObservation == nil else {
                throw ClientPrimarySessionErrorV0.routeObservationPending
            }
            guard let configuredRoute,
                  let routeClass = configuredRoute.observedRouteClass,
                  let connectionID else {
                return nil
            }
            try transport.admit(.commandFrame)
            try admitReplay(messageID)
            guard routeObservationSequence < WireLimits.maximumSafeInteger
            else {
                throw ClientPrimarySessionErrorV0.invalidConfiguration
            }
            routeObservationSequence += 1
            let request = try WireEnvelope(
                messageID: messageID,
                correlationID: nil,
                sentAtUnixMilliseconds: sentAtUnixMilliseconds,
                body: try RouteObservationBodyV1(
                    connectionID: WireBytes16(connectionID),
                    configuredRouteID:
                        configuredRoute.configuredRouteID,
                    routeClass: routeClass,
                    observationSequence: routeObservationSequence
                )
            )
            pendingRouteObservation = request
            lastRouteObservationMonotonicMilliseconds =
                monotonicNowMilliseconds
            return try WireCodec.encode(request)
        } catch {
            terminate()
            throw error
        }
    }

    public func receiveConfiguredRouteAcknowledgement(
        _ responseJSON: Data,
        monotonicNowMilliseconds: UInt64
    ) throws {
        do {
            try requirePhase(.authenticated)
            try observe(monotonicNowMilliseconds)
            guard let pendingRouteObservation else {
                throw ClientPrimarySessionErrorV0.configuredRouteUnavailable
            }
            try transport.admit(.commandFrame)
            let kind = try WireCodec.messageKind(from: responseJSON)
            guard kind == .routeObservationAck else {
                throw ClientPrimarySessionErrorV0.unexpectedMessage(kind)
            }
            let response = try WireCodec.decode(
                WireEnvelope<RouteObservationAcknowledgementBodyV1>.self,
                from: responseJSON
            )
            try admitReplay(response.messageID)
            guard response.correlationID
                    == pendingRouteObservation.messageID,
                  response.body.connectionID
                    == pendingRouteObservation.body.connectionID,
                  response.body.configuredRouteID
                    == pendingRouteObservation.body.configuredRouteID,
                  response.body.routeClass
                    == pendingRouteObservation.body.routeClass,
                  response.body.observationSequence
                    == pendingRouteObservation.body.observationSequence else {
                throw ClientPrimarySessionErrorV0.invalidCorrelation
            }
            self.pendingRouteObservation = nil
        } catch {
            terminate()
            throw error
        }
    }

    public func nextRouteObservationDeadlineMonotonicMilliseconds()
        -> UInt64?
    {
        guard phase == .authenticated,
              pendingRouteObservation == nil,
              configuredRoute?.observedRouteClass != nil,
              let lastRouteObservationMonotonicMilliseconds else {
            return nil
        }
        return lastRouteObservationMonotonicMilliseconds + 15_000
    }

    public func nextAuthenticationDeadlineMonotonicMilliseconds() -> UInt64? {
        switch phase {
        case .awaitingPinnedTLS, .readyToAuthenticate, .awaitingChallenge,
             .awaitingDescription:
            return authenticationDeadlineMonotonicMilliseconds
        case .awaitingTCP, .authenticated, .closed:
            return nil
        }
    }

    @discardableResult
    public func expireAuthenticationIfRequired(
        at monotonicNowMilliseconds: UInt64
    ) -> Bool {
        guard phase != .authenticated, phase != .closed else { return false }
        do {
            try observeAndEnforceAuthenticationDeadline(monotonicNowMilliseconds)
            return false
        } catch {
            terminate()
            return true
        }
    }

    public func close() {
        terminate()
    }

    private func receiveRemoteError(
        _ responseJSON: Data,
        expectedCorrelation: WireUUID?
    ) throws -> Never {
        let response = try WireCodec.decode(
            WireEnvelope<ProtocolErrorResponseBody>.self,
            from: responseJSON
        )
        try admitReplay(response.messageID)
        guard response.correlationID == expectedCorrelation else {
            throw ClientPrimarySessionErrorV0.invalidCorrelation
        }
        throw ClientPrimarySessionErrorV0.remoteError(
            code: response.body.code,
            retry: response.body.retry
        )
    }

    private func admitReplay(_ messageID: WireUUID) throws {
        do {
            try replay.admit(messageID)
        } catch TransportGuardError.duplicateMessage {
            throw ClientPrimarySessionErrorV0.duplicateMessage(messageID)
        }
    }

    private func requirePhase(_ expected: ClientPrimarySessionPhaseV0) throws {
        guard phase == expected else {
            throw ClientPrimarySessionErrorV0.invalidPhase(phase)
        }
    }

    private func observeAndEnforceAuthenticationDeadline(
        _ value: UInt64
    ) throws {
        try observe(value)
        guard let deadline = authenticationDeadlineMonotonicMilliseconds else {
            throw ClientPrimarySessionErrorV0.invalidClock
        }
        guard value < deadline else {
            throw ClientPrimarySessionErrorV0.authenticationDeadlineExceeded
        }
    }

    private func observe(_ value: UInt64) throws {
        guard value <= UInt64(Int64.max),
              lastMonotonicMilliseconds.map({ value >= $0 }) ?? true else {
            throw ClientPrimarySessionErrorV0.invalidClock
        }
        lastMonotonicMilliseconds = value
    }

    private func terminate() {
        transport.close()
        phase = .closed
        authenticatedSession = nil
        connectionID = nil
        pendingRouteObservation = nil
        lastRouteObservationMonotonicMilliseconds = nil
        authenticationDeadlineMonotonicMilliseconds = nil
        clearHandshakeSecrets()
    }

    private func clearHandshakeSecrets() {
        clientNonce = nil
        helloMessageID = nil
        challengeMessageID = nil
        proofMessageID = nil
    }
}
