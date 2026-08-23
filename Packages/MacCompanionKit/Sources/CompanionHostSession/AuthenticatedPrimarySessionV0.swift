import CompanionAuthentication
import CompanionDomain
import CompanionHost
import CompanionHostWire
import CompanionOperations
import CompanionTransport
import CompanionWire
import Foundation

public enum AuthenticatedPrimarySessionPhaseV0: String, Equatable, Sendable {
    case awaitingHello
    case awaitingProof
    case ready
    case closed
}

public enum AuthenticatedPrimarySessionErrorV0: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidClock
    case unexpectedMessage(
        phase: AuthenticatedPrimarySessionPhaseV0,
        kind: WireMessageKind
    )
    case invalidAuthenticationCorrelation
    case authenticationDeadlineExceeded
    case authenticatedLivenessExpired
    case unauthenticated
}

public protocol HostStatusSnapshotProvidingV0: Sendable {
    func snapshot(hostState: HostState) async throws -> HostStatusSnapshot
}

extension HostStatusAuthority: HostStatusSnapshotProvidingV0 {}

public protocol AuthenticatedOperationWireDispatchingV0: Sendable {
    func dispatch(
        requestJSON: Data,
        context: AuthenticatedOperationCommandContextV0,
        responseMessageID: WireUUID
    ) async throws -> Data
}

extension OperationWireCommandDispatcherV0: AuthenticatedOperationWireDispatchingV0 {}

public protocol AuthenticatedCapabilityRegistryDispatchingV1: Sendable {
    func dispatch(
        requestJSON: Data,
        principal: AuthenticatedDevicePrincipal,
        responseMessageID: WireUUID,
        sentAtUnixMilliseconds: Int64
    ) async throws -> Data
}

extension CapabilityRegistryWireDispatcherV1: AuthenticatedCapabilityRegistryDispatchingV1 {}

public protocol AuthenticatedAuditWireDispatchingV1: Sendable {
    func dispatch(
        requestJSON: Data,
        principal: AuthenticatedDevicePrincipal,
        responseMessageID: WireUUID,
        sentAtUnixMilliseconds: Int64
    ) async throws -> Data
}

public protocol AuthenticatedRouteObservationPublishingV1: Sendable {
    func publish(
        connectionID: Data,
        routeClass: ConfiguredRouteClassV1,
        observedAtMonotonicMilliseconds: UInt64
    ) async

    func withdraw(connectionID: Data) async
}

extension AuditSelfWireDispatcherV1: AuthenticatedAuditWireDispatchingV1 {}

public struct AuthenticatedInteractiveCommandContextV0: Equatable, Sendable {
    public let principal: AuthenticatedDevicePrincipal
    public let primaryConnectionID: Data
    public let hostID: UUID
    public let hostFingerprint: Data
    public let hostState: HostState
    public let wallNowUnixMilliseconds: Int64
    public let monotonicNowMilliseconds: UInt64

    public init(
        principal: AuthenticatedDevicePrincipal,
        primaryConnectionID: Data,
        hostID: UUID,
        hostFingerprint: Data,
        hostState: HostState,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64
    ) throws {
        guard primaryConnectionID.count == 16,
              hostFingerprint.count == 32,
              wallNowUnixMilliseconds >= 0,
              wallNowUnixMilliseconds <= WireLimits.maximumSafeInteger,
              monotonicNowMilliseconds <= UInt64(Int64.max) else {
            throw AuthenticatedPrimarySessionErrorV0.invalidConfiguration
        }
        self.principal = principal
        self.primaryConnectionID = primaryConnectionID
        self.hostID = hostID
        self.hostFingerprint = hostFingerprint
        self.hostState = hostState
        self.wallNowUnixMilliseconds = wallNowUnixMilliseconds
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
    }
}

/// The concrete Interactive Host composition owns request/proof correlation,
/// grant checks, approval-key lookup, visible-app availability, and atomic
/// bootstrap creation. The primary session supplies only authenticated facts.
public protocol AuthenticatedInteractiveWireDispatchingV0: Sendable {
    func dispatch(
        requestJSON: Data,
        context: AuthenticatedInteractiveCommandContextV0,
        responseMessageID: WireUUID
    ) async throws -> Data

    /// Destroys every approval, session, and unused role credential owned by
    /// this primary connection. Implementations must make this idempotent.
    func primarySessionClosed() async
}

/// Owns exactly one host-side application-primary connection after the
/// Network.framework adapter has produced a validated TLS listener binding.
/// No command path receives a principal or connection ID from request JSON.
public actor AuthenticatedPrimarySessionV0 {
    public let hostID: UUID
    public let tlsBinding: HostApplicationTLSBinding
    public private(set) var phase: AuthenticatedPrimarySessionPhaseV0 = .awaitingHello

    private let authentication: ApplicationAuthenticationAuthority
    private let status: any HostStatusSnapshotProvidingV0
    private let operations: any AuthenticatedOperationWireDispatchingV0
    private let capabilities: any AuthenticatedCapabilityRegistryDispatchingV1
    private let audit: (any AuthenticatedAuditWireDispatchingV1)?
    private let interactive: any AuthenticatedInteractiveWireDispatchingV0
    private let routeObservationPublisher:
        (any AuthenticatedRouteObservationPublishingV1)?
    private let detailedAudit: (any PrimarySessionAuditWritingV0)?
    private let detailedAuditWallClock: any PrimarySessionAuditWallClockV0
    private var replay = ConnectionReplayWindow()
    private let authenticationDeadlineMonotonicMilliseconds: UInt64
    private var lastAuthenticatedTrafficMonotonicMilliseconds: UInt64?
    private var challengeResponseMessageID: WireUUID?
    private var connectionID: Data?
    private var principal: AuthenticatedDevicePrincipal?
    private var routeObservationSession:
        AuthenticatedRouteObservationSessionV1?
    private var routeObservationDeadlineMonotonicMilliseconds: UInt64?

    /// Returns the server-issued connection binding only after the primary
    /// has completed authentication. The value is never accepted from wire
    /// input and is cleared by terminal teardown.
    public func authenticatedPrimaryConnectionID() -> Data? {
        guard phase == .ready else { return nil }
        return connectionID
    }

    package init(
        hostID: UUID,
        tlsBinding: HostApplicationTLSBinding,
        acceptedAtMonotonicMilliseconds: UInt64,
        authentication: ApplicationAuthenticationAuthority,
        status: any HostStatusSnapshotProvidingV0,
        operations: any AuthenticatedOperationWireDispatchingV0,
        capabilities: any AuthenticatedCapabilityRegistryDispatchingV1,
        audit: (any AuthenticatedAuditWireDispatchingV1)? = nil,
        interactive: any AuthenticatedInteractiveWireDispatchingV0,
        routeObservationPublisher:
            (any AuthenticatedRouteObservationPublishingV1)? = nil,
        detailedAudit: (any PrimarySessionAuditWritingV0)? = nil,
        detailedAuditWallClock: any PrimarySessionAuditWallClockV0 =
            SystemPrimarySessionAuditWallClockV0()
    ) throws {
        let authenticationLifetime = UInt64(
            V0ConnectionTiming.authenticationNanoseconds / 1_000_000
        )
        let (deadline, overflow) = acceptedAtMonotonicMilliseconds
            .addingReportingOverflow(authenticationLifetime)
        guard !overflow, deadline <= UInt64(Int64.max) else {
            throw AuthenticatedPrimarySessionErrorV0.invalidConfiguration
        }
        self.hostID = hostID
        self.tlsBinding = tlsBinding
        authenticationDeadlineMonotonicMilliseconds = deadline
        self.authentication = authentication
        self.status = status
        self.operations = operations
        self.capabilities = capabilities
        self.audit = audit
        self.interactive = interactive
        self.routeObservationPublisher = routeObservationPublisher
        self.detailedAudit = detailedAudit
        self.detailedAuditWallClock = detailedAuditWallClock
    }

    public func receive(
        requestJSON: Data,
        hostState: HostState,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64,
        responseMessageID: WireUUID
    ) async throws -> Data {
        do {
            guard wallNowUnixMilliseconds >= 0,
                  wallNowUnixMilliseconds <= WireLimits.maximumSafeInteger,
                  monotonicNowMilliseconds <= UInt64(Int64.max) else {
                throw AuthenticatedPrimarySessionErrorV0.invalidClock
            }
            try enforceTiming(at: monotonicNowMilliseconds)
            let kind = try WireCodec.messageKind(from: requestJSON)
            switch phase {
            case .awaitingHello:
                guard kind == .authHello else {
                    throw unexpected(kind)
                }
                return try await receiveHello(
                    requestJSON,
                    monotonicNowMilliseconds: Int64(monotonicNowMilliseconds),
                    wallNowUnixMilliseconds: wallNowUnixMilliseconds,
                    responseMessageID: responseMessageID
                )
            case .awaitingProof:
                guard kind == .authProof else {
                    throw unexpected(kind)
                }
                return try await receiveProof(
                    requestJSON,
                    hostState: hostState,
                    monotonicNowMilliseconds: Int64(monotonicNowMilliseconds),
                    wallNowUnixMilliseconds: wallNowUnixMilliseconds,
                    responseMessageID: responseMessageID
                )
            case .ready:
                return try await receiveReadyCommand(
                    kind: kind,
                    requestJSON: requestJSON,
                    hostState: hostState,
                    wallNowUnixMilliseconds: wallNowUnixMilliseconds,
                    monotonicNowMilliseconds: monotonicNowMilliseconds,
                    responseMessageID: responseMessageID
                )
            case .closed:
                throw AuthenticatedPrimarySessionErrorV0.unauthenticated
            }
        } catch let error as HostStatusError {
            // Sampling/commit failures are server-side and do not turn an
            // authenticated peer into a protocol violator.
            throw error
        } catch {
            if Self.isProtocolRejection(error) {
                await detailedAudit?.recordProtocolRejected(
                    responseMessageID: responseMessageID.rawValue,
                    observedAtUnixMilliseconds: wallNowUnixMilliseconds
                )
            }
            await close()
            throw error
        }
    }

    public func close() async {
        guard phase != .closed else { return }
        let closingPrincipal = principal
        let closingConnectionID = connectionID
        let closingRouteObservationSession = routeObservationSession
        phase = .closed
        challengeResponseMessageID = nil
        connectionID = nil
        principal = nil
        routeObservationSession = nil
        routeObservationDeadlineMonotonicMilliseconds = nil
        _ = await closingRouteObservationSession?.close()
        if let closingConnectionID {
            await routeObservationPublisher?.withdraw(
                connectionID: closingConnectionID
            )
        }
        await interactive.primarySessionClosed()
        if let closingPrincipal, let closingConnectionID {
            await detailedAudit?.recordClosed(
                principal: closingPrincipal,
                connectionID: closingConnectionID,
                observedAtUnixMilliseconds:
                    detailedAuditWallClock.nowUnixMilliseconds()
            )
        }
    }

    public func nextDeadlineMonotonicMilliseconds() -> UInt64? {
        switch phase {
        case .awaitingHello, .awaitingProof:
            return authenticationDeadlineMonotonicMilliseconds
        case .ready:
            guard let lastAuthenticatedTrafficMonotonicMilliseconds else {
                return nil
            }
            let lifetime = UInt64(
                V0ConnectionTiming.authenticatedLivenessNanoseconds / 1_000_000
            )
            let (deadline, overflow) = lastAuthenticatedTrafficMonotonicMilliseconds
                .addingReportingOverflow(lifetime)
            guard !overflow, deadline <= UInt64(Int64.max) else {
                // Wake the owner immediately. `expireIfRequired` treats this
                // unrepresentable clock state as terminal instead of silently
                // disabling the liveness timer.
                return lastAuthenticatedTrafficMonotonicMilliseconds
            }
            if let routeObservationDeadlineMonotonicMilliseconds {
                return min(
                    deadline,
                    routeObservationDeadlineMonotonicMilliseconds + 1
                )
            }
            return deadline
        case .closed:
            return nil
        }
    }

    /// Called by the socket owner even when no bytes arrive. Returns true only
    /// after terminally closing this session for a due or invalid clock.
    public func expireIfRequired(
        at monotonicNowMilliseconds: UInt64
    ) async -> Bool {
        guard monotonicNowMilliseconds <= UInt64(Int64.max) else {
            await close()
            return true
        }
        do {
            try enforceTiming(at: monotonicNowMilliseconds)
            if let deadline = routeObservationDeadlineMonotonicMilliseconds,
               monotonicNowMilliseconds > deadline,
               let routeObservationSession,
               let connectionID {
                _ = try await routeObservationSession.snapshot(
                    hostMonotonicMilliseconds:
                        monotonicNowMilliseconds
                )
                routeObservationDeadlineMonotonicMilliseconds = nil
                await routeObservationPublisher?.withdraw(
                    connectionID: connectionID
                )
            }
            return false
        } catch AuthenticatedPrimarySessionErrorV0.authenticationDeadlineExceeded,
                AuthenticatedPrimarySessionErrorV0.authenticatedLivenessExpired,
                AuthenticatedPrimarySessionErrorV0.invalidClock,
                AuthenticatedPrimarySessionErrorV0.unauthenticated {
            await close()
            return true
        } catch {
            return false
        }
    }

    private func receiveHello(
        _ requestJSON: Data,
        monotonicNowMilliseconds: Int64,
        wallNowUnixMilliseconds: Int64,
        responseMessageID: WireUUID
    ) async throws -> Data {
        let request = try WireCodec.decode(
            WireEnvelope<AuthHelloBody>.self,
            from: requestJSON
        )
        try replay.admit(request.messageID)
        let challenge = try await authentication.challenge(
            clientID: request.body.clientID.rawValue,
            clientNonce: request.body.clientNonce.rawValue,
            hostFingerprint: tlsBinding.hostFingerprint,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
        connectionID = challenge.connectionID
        challengeResponseMessageID = responseMessageID
        phase = .awaitingProof
        return try WireCodec.encode(WireEnvelope(
            version: request.version,
            messageID: responseMessageID,
            correlationID: request.messageID,
            sentAtUnixMilliseconds: wallNowUnixMilliseconds,
            body: try AuthChallengeBody(
                connectionID: WireBytes16(challenge.connectionID),
                serverNonce: WireBytes32(challenge.serverNonce),
                selectedVersion: WireVersion(
                    major: challenge.selectedMajor,
                    minor: challenge.selectedMinor
                ),
                hostFingerprint: WireFingerprint(challenge.hostFingerprint)
            )
        ))
    }

    private func receiveProof(
        _ requestJSON: Data,
        hostState: HostState,
        monotonicNowMilliseconds: Int64,
        wallNowUnixMilliseconds: Int64,
        responseMessageID: WireUUID
    ) async throws -> Data {
        let request = try WireCodec.decode(
            WireEnvelope<AuthProofBody>.self,
            from: requestJSON
        )
        try replay.admit(request.messageID)
        guard request.correlationID == challengeResponseMessageID,
              let connectionID else {
            throw AuthenticatedPrimarySessionErrorV0.invalidAuthenticationCorrelation
        }
        let authenticated: AuthenticatedDevicePrincipal
        do {
            authenticated = try await authentication.prove(
                connectionID: connectionID,
                signature: request.body.signature.rawValue,
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
        } catch {
            await detailedAudit?.recordRejectedProof(
                proofMessageID: request.messageID.rawValue,
                observedAtUnixMilliseconds: wallNowUnixMilliseconds
            )
            throw error
        }
        principal = authenticated
        if routeObservationPublisher != nil {
            routeObservationSession = try AuthenticatedRouteObservationSessionV1(
                connectionID: connectionID
            )
        }
        lastAuthenticatedTrafficMonotonicMilliseconds = UInt64(
            monotonicNowMilliseconds
        )
        phase = .ready
        await detailedAudit?.recordAuthenticated(
            principal: authenticated,
            connectionID: connectionID,
            observedAtUnixMilliseconds: wallNowUnixMilliseconds
        )
        let response = try SessionDescriptionWireMapper.response(
            for: request,
            principal: authenticated,
            hostID: hostID,
            hostState: hostState,
            responseMessageID: responseMessageID.rawValue,
            sentAtUnixMilliseconds: wallNowUnixMilliseconds
        )
        return try WireCodec.encode(response)
    }

    private func receiveReadyCommand(
        kind: WireMessageKind,
        requestJSON: Data,
        hostState: HostState,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64,
        responseMessageID: WireUUID
    ) async throws -> Data {
        guard let principal, let connectionID else {
            throw AuthenticatedPrimarySessionErrorV0.unauthenticated
        }
        _ = try await authentication.revalidate(principal)

        switch kind {
        case .routeObservation:
            let request = try WireCodec.decode(
                WireEnvelope<RouteObservationBodyV1>.self,
                from: requestJSON
            )
            try replay.admit(request.messageID)
            lastAuthenticatedTrafficMonotonicMilliseconds =
                monotonicNowMilliseconds
            guard let routeObservationSession,
                  let routeObservationPublisher else {
                throw unexpected(kind)
            }
            let routeSnapshot = try await routeObservationSession.admit(
                request.body,
                hostMonotonicMilliseconds: monotonicNowMilliseconds
            )
            routeObservationDeadlineMonotonicMilliseconds =
                routeSnapshot.freshThroughMonotonicMilliseconds
            await routeObservationPublisher.publish(
                connectionID: connectionID,
                routeClass: request.body.routeClass,
                observedAtMonotonicMilliseconds:
                    monotonicNowMilliseconds
            )
            guard phase == .ready,
                  self.connectionID == connectionID else {
                throw AuthenticatedPrimarySessionErrorV0.unauthenticated
            }
            return try WireCodec.encode(
                await routeObservationSession.acknowledgement(
                    for: request,
                    responseMessageID: responseMessageID,
                    sentAtUnixMilliseconds: wallNowUnixMilliseconds
                )
            )
        case .statusSnapshotRequest:
            let request = try WireCodec.decode(
                WireEnvelope<StatusSnapshotRequestBody>.self,
                from: requestJSON
            )
            try replay.admit(request.messageID)
            lastAuthenticatedTrafficMonotonicMilliseconds = monotonicNowMilliseconds
            let snapshot = try await status.snapshot(hostState: hostState)
            return try WireCodec.encode(HostStatusWireMapper.response(
                for: request,
                snapshot: snapshot,
                responseMessageID: responseMessageID.rawValue,
                sentAtUnixMilliseconds: wallNowUnixMilliseconds
            ))
        case .capabilityRegistryRequest:
            let request = try WireCodec.decode(
                WireEnvelope<CapabilityRegistryRequestBody>.self,
                from: requestJSON
            )
            try replay.admit(request.messageID)
            lastAuthenticatedTrafficMonotonicMilliseconds = monotonicNowMilliseconds
            return try await capabilities.dispatch(
                requestJSON: requestJSON,
                principal: principal,
                responseMessageID: responseMessageID,
                sentAtUnixMilliseconds: wallNowUnixMilliseconds
            )
        case .auditListRequest:
            let request = try WireCodec.decode(
                WireEnvelope<AuditListRequestBodyV1>.self,
                from: requestJSON
            )
            try replay.admit(request.messageID)
            lastAuthenticatedTrafficMonotonicMilliseconds = monotonicNowMilliseconds
            guard let audit else { throw unexpected(kind) }
            return try await audit.dispatch(
                requestJSON: requestJSON,
                principal: principal,
                responseMessageID: responseMessageID,
                sentAtUnixMilliseconds: wallNowUnixMilliseconds
            )
        case .operationInvoke, .operationApprove, .operationStatusRequest,
             .operationCancel:
            let messageID = try messageID(from: requestJSON)
            try replay.admit(messageID)
            lastAuthenticatedTrafficMonotonicMilliseconds = monotonicNowMilliseconds
            let context = try AuthenticatedOperationCommandContextV0(
                principal: principal,
                primaryConnectionID: connectionID,
                hostState: hostState,
                wallNowUnixMilliseconds: wallNowUnixMilliseconds,
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
            return try await operations.dispatch(
                requestJSON: requestJSON,
                context: context,
                responseMessageID: responseMessageID
            )
        case .interactiveSessionRequest, .interactiveSessionApprove,
             .interactiveSessionEnd,
             .interactiveInitialSurfaceRequest,
             .interactiveInitialSurfaceAcknowledgement,
             .interactiveSurfaceTargetsRequest,
             .interactiveSurfaceSelect,
             .interactiveSurfaceAcknowledgement:
            let messageID = try messageID(from: requestJSON)
            try replay.admit(messageID)
            lastAuthenticatedTrafficMonotonicMilliseconds = monotonicNowMilliseconds
            let context = try AuthenticatedInteractiveCommandContextV0(
                principal: principal,
                primaryConnectionID: connectionID,
                hostID: hostID,
                hostFingerprint: tlsBinding.hostFingerprint,
                hostState: hostState,
                wallNowUnixMilliseconds: wallNowUnixMilliseconds,
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
            return try await interactive.dispatch(
                requestJSON: requestJSON,
                context: context,
                responseMessageID: responseMessageID
            )
        default:
            throw unexpected(kind)
        }
    }

    private func messageID(from data: Data) throws -> WireUUID {
        guard case let .object(members) = try CanonicalJSON.parse(data),
              let member = members.first(where: { $0.key == "messageID" }),
              case let .string(text) = member.value,
              text.utf8.count == 36,
              text == text.lowercased(),
              let value = UUID(uuidString: text),
              value.uuidString.lowercased() == text else {
            throw WireError.invalidFrame(reason: "invalid message ID")
        }
        return WireUUID(value)
    }

    private func unexpected(
        _ kind: WireMessageKind
    ) -> AuthenticatedPrimarySessionErrorV0 {
        .unexpectedMessage(phase: phase, kind: kind)
    }

    private static func isProtocolRejection(_ error: any Error) -> Bool {
        if error is WireError
            || error is TransportGuardError
            || error is AuthenticatedRouteObservationSessionErrorV1
        {
            return true
        }
        guard let sessionError = error as? AuthenticatedPrimarySessionErrorV0 else {
            return false
        }
        return switch sessionError {
        case .unexpectedMessage, .invalidAuthenticationCorrelation:
            true
        case .invalidConfiguration, .invalidClock,
             .authenticationDeadlineExceeded, .authenticatedLivenessExpired,
             .unauthenticated:
            false
        }
    }

    private func enforceTiming(at monotonicNowMilliseconds: UInt64) throws {
        switch phase {
        case .awaitingHello, .awaitingProof:
            guard monotonicNowMilliseconds < authenticationDeadlineMonotonicMilliseconds else {
                throw AuthenticatedPrimarySessionErrorV0.authenticationDeadlineExceeded
            }
        case .ready:
            guard let lastAuthenticatedTrafficMonotonicMilliseconds else {
                throw AuthenticatedPrimarySessionErrorV0.unauthenticated
            }
            let lifetime = UInt64(
                V0ConnectionTiming.authenticatedLivenessNanoseconds / 1_000_000
            )
            guard lastAuthenticatedTrafficMonotonicMilliseconds
                    <= UInt64(Int64.max) - lifetime else {
                throw AuthenticatedPrimarySessionErrorV0.invalidClock
            }
            guard monotonicNowMilliseconds >= lastAuthenticatedTrafficMonotonicMilliseconds else {
                throw AuthenticatedPrimarySessionErrorV0.invalidClock
            }
            guard monotonicNowMilliseconds
                    - lastAuthenticatedTrafficMonotonicMilliseconds < lifetime else {
                throw AuthenticatedPrimarySessionErrorV0.authenticatedLivenessExpired
            }
        case .closed:
            throw AuthenticatedPrimarySessionErrorV0.unauthenticated
        }
    }
}
