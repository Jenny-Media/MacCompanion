import CompanionClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionWire
import Foundation

public struct ClientCustodiedInteractiveApprovalSignerV0:
    ClientInteractiveApprovalSigningV0,
    Sendable
{
    private let custody: any ClientIdentityKeyCustodyV0
    private let reference: ClientSigningKeyReferenceV0

    public init(
        custody: any ClientIdentityKeyCustodyV0,
        approvalKey: ClientCustodiedPublicKeyV0
    ) throws {
        guard approvalKey.role == .approval,
              approvalKey.protection
                == .whenUnlockedThisDeviceOnlyUserPresence else {
            throw ClientIdentityPublicationErrorV0.invalidIdentity
        }
        self.custody = custody
        reference = approvalKey.reference
    }

    public func signAfterUserPresence(_ input: Data) async throws -> Data {
        let signature = try await custody.signApprovalInput(
            input,
            using: reference,
            reason: .startInteractiveControl
        )
        guard signature.count == 64 else {
            throw ClientIdentityPublicationErrorV0.invalidIdentity
        }
        return signature
    }
}

public struct ClientInteractivePrimaryEnvironmentV0: Sendable {
    public let makeMessageID: @Sendable () -> WireUUID
    public let wallNowUnixMilliseconds: @Sendable () -> Int64
    public let monotonicNowMilliseconds: @Sendable () -> UInt64

    public init(
        makeMessageID: @escaping @Sendable () -> WireUUID,
        wallNowUnixMilliseconds: @escaping @Sendable () -> Int64,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64
    ) {
        self.makeMessageID = makeMessageID
        self.wallNowUnixMilliseconds = wallNowUnixMilliseconds
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
    }
}

public struct ClientInteractiveRemoteErrorV0: Equatable, Sendable {
    public let code: String
    public let retry: ProtocolErrorRetry

    public init(code: String, retry: ProtocolErrorRetry) {
        self.code = code
        self.retry = retry
    }
}

public enum ClientInteractivePrimarySessionEventV0: Equatable, Sendable {
    case requestSubmitted(effects: [InteractiveControlEffect])
    case approvalSubmitted(effects: [InteractiveControlEffect])
    case accepted(
        session: ClientInteractiveAcceptedSessionV0,
        effects: [InteractiveControlEffect]
    )
    case endSubmitted(
        interactiveSessionID: UUID,
        effects: [InteractiveControlEffect]
    )
    case ended(
        interactiveSessionID: UUID,
        endedAtUnixMilliseconds: Int64
    )
    case endRejected(
        interactiveSessionID: UUID,
        error: ClientInteractiveRemoteErrorV0
    )
    case remoteRejected(ClientInteractiveRemoteErrorV0)
}

public enum ClientInteractivePrimaryChannelErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidConfiguration
    case unavailable
    case initialSurfaceUnavailable
    case initialSurfaceDeadlineExceeded
    case cancelled
}

/// One primary-connection owner for the Interactive session approval flow.
/// Accepted role offers are inert until the separate role-channel and initial
/// Desktop authorities complete their own admission gates.
public actor ClientInteractivePrimaryChannelV0:
    ClientPrimaryReplyReceivingV0
{
    public let primary: ClientInteractivePrimaryBindingV0

    private var authority: ClientInteractiveSessionAuthorityV0
    private let signer: any ClientInteractiveApprovalSigningV0
    private let sender: any ClientAuthenticatedCommandSendingV1
    private let environment: ClientInteractivePrimaryEnvironmentV0
    private let publish: @Sendable (
        ClientInteractivePrimarySessionEventV0
    ) -> Void
    private var requestedEffects: [InteractiveControlEffect]?
    private var initialSurface: ClientInitialSurfaceCoordinatorV0?
    private var replacementSurface: ClientSurfaceControlCoordinatorV0?
    private var descriptorWaiter: CheckedContinuation<
        AdaptiveSurfaceDescriptor, any Error
    >?
    private var descriptorWaiterID: UUID?
    private var descriptorDeadlineTask: Task<Void, Never>?
    private var endRequestMessageID: WireUUID?
    private var endingInteractiveSessionID: UUID?
    private var invalidated = false

    public init(
        pairedHost: ClientDurablePairedHostV0,
        authenticatedSession: ClientAuthenticatedSessionV0,
        signer: any ClientInteractiveApprovalSigningV0,
        sender: any ClientAuthenticatedCommandSendingV1,
        environment: ClientInteractivePrimaryEnvironmentV0,
        publish: @escaping @Sendable (
            ClientInteractivePrimarySessionEventV0
        ) -> Void = { _ in }
    ) throws {
        guard pairedHost.clientID == authenticatedSession.clientID,
              pairedHost.hostID == authenticatedSession.hostID,
              pairedHost.deviceID == authenticatedSession.deviceID,
              pairedHost.hostFingerprint.count == 32,
              authenticatedSession.connectionID.count == 16 else {
            throw ClientInteractivePrimaryChannelErrorV0.invalidConfiguration
        }
        let primary = try ClientInteractivePrimaryBindingV0(
            hostID: authenticatedSession.hostID,
            hostFingerprint: pairedHost.hostFingerprint,
            clientID: authenticatedSession.clientID,
            primaryConnectionID: authenticatedSession.connectionID,
            authorizationEpoch: authenticatedSession.authorizationEpoch,
            grantRevision: authenticatedSession.grantRevision,
            policyRevision: authenticatedSession.policyRevision
        )
        self.primary = primary
        self.signer = signer
        authority = ClientInteractiveSessionAuthorityV0(
            primary: primary,
            signer: signer
        )
        self.sender = sender
        self.environment = environment
        self.publish = publish
    }

    @discardableResult
    public func beginSession(
        effects: Set<InteractiveControlEffect>
    ) async throws -> ClientInteractivePrimarySessionEventV0 {
        guard !invalidated else {
            throw ClientInteractivePrimaryChannelErrorV0.unavailable
        }
        if await authority.phase == .closed {
            authority = ClientInteractiveSessionAuthorityV0(
                primary: primary,
                signer: signer
            )
        }
        let sortedEffects = effects.sorted()
        let frame = try await authority.beginRequest(
            effects: effects,
            messageID: environment.makeMessageID(),
            sentAtUnixMilliseconds: environment.wallNowUnixMilliseconds()
        )
        do {
            try await sender.sendAuthenticatedCommand(frame)
        } catch {
            await authority.close()
            throw error
        }
        guard !invalidated else {
            await authority.close()
            throw ClientInteractivePrimaryChannelErrorV0.unavailable
        }
        requestedEffects = sortedEffects
        let event = ClientInteractivePrimarySessionEventV0
            .requestSubmitted(effects: sortedEffects)
        publish(event)
        return event
    }

    public func preparePrimaryReply(
        _ frame: Data
    ) async throws -> ClientPrimaryPreparedReplyV0 {
        guard !invalidated, let effects = requestedEffects else {
            throw ClientInteractivePrimaryChannelErrorV0.unavailable
        }
        let kind = try WireCodec.messageKind(from: frame)
        if let endRequestMessageID,
           let interactiveSessionID = endingInteractiveSessionID {
            if kind == .error {
                let response = try WireCodec.decode(
                    WireEnvelope<ProtocolErrorResponseBody>.self,
                    from: frame
                )
                guard response.correlationID == endRequestMessageID else {
                    throw ClientInteractivePrimaryChannelErrorV0.unavailable
                }
                self.endRequestMessageID = nil
                endingInteractiveSessionID = nil
                let event = ClientInteractivePrimarySessionEventV0
                    .endRejected(
                        interactiveSessionID: interactiveSessionID,
                        error: ClientInteractiveRemoteErrorV0(
                            code: response.body.code,
                            retry: response.body.retry
                        )
                    )
                return ClientPrimaryPreparedReplyV0 { [publish] in
                    publish(event)
                }
            }
            guard kind == .interactiveSessionEnded else {
                throw ClientInteractivePrimaryChannelErrorV0.unavailable
            }
            let response = try WireCodec.decode(
                WireEnvelope<InteractiveSessionEndedBodyV0>.self,
                from: frame
            )
            guard response.correlationID == endRequestMessageID,
                  response.body.interactiveSessionID.rawValue
                    == interactiveSessionID,
                  response.body.authorizationEpoch
                    == primary.authorizationEpoch else {
                throw ClientInteractivePrimaryChannelErrorV0.unavailable
            }
            self.endRequestMessageID = nil
            endingInteractiveSessionID = nil
            requestedEffects = nil
            initialSurface = nil
            replacementSurface = nil
            await authority.close()
            let event = ClientInteractivePrimarySessionEventV0.ended(
                interactiveSessionID: interactiveSessionID,
                endedAtUnixMilliseconds:
                    response.body.endedAtUnixMilliseconds
            )
            return ClientPrimaryPreparedReplyV0 { [publish] in
                publish(event)
            }
        }
        if var coordinator = initialSurface {
            switch coordinator.phase {
            case .awaitingDescriptor:
                let descriptor = try coordinator.receiveDescriptor(
                    frame,
                    clientMonotonicNowMilliseconds:
                        try initialMonotonicMilliseconds()
                )
                initialSurface = coordinator
                finishDescriptorWaiter(.success(descriptor))
                return ClientPrimaryPreparedReplyV0 {}
            case .awaitingAcknowledgement:
                try coordinator.receiveAcknowledged(frame)
                replacementSurface = try coordinator
                    .replacementCoordinator()
                initialSurface = coordinator
                return ClientPrimaryPreparedReplyV0 {}
            case .awaitingRequest, .awaitingMedia, .active, .closed:
                break
            }
        }
        switch await authority.phase {
        case .awaitingApprovalChallenge:
            do {
                let proof = try await authority.receiveApprovalChallenge(
                    frame,
                    approvalProofMessageID: environment.makeMessageID(),
                    sentAtUnixMilliseconds:
                        environment.wallNowUnixMilliseconds(),
                    monotonicNowMilliseconds:
                        environment.monotonicNowMilliseconds()
                )
                try await sender.sendAuthenticatedCommand(proof)
                guard !invalidated else {
                    throw ClientInteractivePrimaryChannelErrorV0.unavailable
                }
                let event = ClientInteractivePrimarySessionEventV0
                    .approvalSubmitted(effects: effects)
                return ClientPrimaryPreparedReplyV0 { [publish] in
                    publish(event)
                }
            } catch let error as ClientInteractiveSessionErrorV0 {
                return try remoteRejection(error, kind: kind)
            }
        case .awaitingAcceptance:
            do {
                let session = try await authority.receiveAcceptedSession(
                    frame,
                    monotonicNowMilliseconds:
                        environment.monotonicNowMilliseconds()
                )
                guard !invalidated else {
                    throw ClientInteractivePrimaryChannelErrorV0.unavailable
                }
                initialSurface = try ClientInitialSurfaceCoordinatorV0(
                    interactiveSessionID: session.interactiveSessionID,
                    authorizationEpoch: session.authorizationEpoch,
                    sessionAllowedInteractionClasses:
                        Self.interactionClasses(for: effects)
                )
                replacementSurface = nil
                let event = ClientInteractivePrimarySessionEventV0.accepted(
                    session: session,
                    effects: effects
                )
                return ClientPrimaryPreparedReplyV0 { [publish] in
                    publish(event)
                }
            } catch let error as ClientInteractiveSessionErrorV0 {
                return try remoteRejection(error, kind: kind)
            }
        default:
            throw ClientInteractivePrimaryChannelErrorV0.unavailable
        }
    }

    public func invalidatePrimaryReplyReceiver() async {
        guard !invalidated else { return }
        invalidated = true
        requestedEffects = nil
        endRequestMessageID = nil
        endingInteractiveSessionID = nil
        initialSurface = nil
        replacementSurface = nil
        finishDescriptorWaiter(.failure(
            ClientInteractivePrimaryChannelErrorV0.cancelled
        ))
        await authority.close()
    }

    public func phase() async -> ClientInteractiveSessionPhaseV0 {
        await authority.phase
    }

    public func initialSurfacePhase() -> ClientInitialSurfacePhaseV0? {
        initialSurface?.phase
    }

    public func waitForInitialDescriptor(
        timeoutMilliseconds: UInt64 = 30_000
    ) async throws -> AdaptiveSurfaceDescriptor {
        guard !invalidated,
              timeoutMilliseconds > 0,
              descriptorWaiter == nil,
              let coordinator = initialSurface else {
            throw ClientInteractivePrimaryChannelErrorV0
                .initialSurfaceUnavailable
        }
        if let descriptor = coordinator.descriptor { return descriptor }
        guard coordinator.phase == .awaitingDescriptor else {
            throw ClientInteractivePrimaryChannelErrorV0
                .initialSurfaceUnavailable
        }
        let waiterID = UUID()
        descriptorWaiterID = waiterID
        descriptorDeadlineTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: min(
                        timeoutMilliseconds,
                        UInt64.max / 1_000_000
                    ) * 1_000_000
                )
            } catch {
                return
            }
            await self?.descriptorDeadlineReached(waiterID)
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                continuation in
                descriptorWaiter = continuation
            }
        } onCancel: { [weak self] in
            Task { await self?.cancelDescriptorWaiter(waiterID) }
        }
    }

    public func beginInitialSurface() async throws {
        guard !invalidated,
              await authority.phase == .accepted,
              var coordinator = initialSurface else {
            throw ClientInteractivePrimaryChannelErrorV0
                .initialSurfaceUnavailable
        }
        let frame = try coordinator.makeDescriptorRequest(
            messageID: environment.makeMessageID(),
            sentAtUnixMilliseconds:
                environment.wallNowUnixMilliseconds()
        )
        do {
            try await sender.sendAuthenticatedCommand(frame)
        } catch {
            initialSurface = nil
            await authority.close()
            throw error
        }
        initialSurface = coordinator
    }

    @discardableResult
    public func endSession()
        async throws -> ClientInteractivePrimarySessionEventV0
    {
        guard !invalidated,
              endRequestMessageID == nil,
              let effects = requestedEffects,
              let accepted = await authority.acceptedSession else {
            throw ClientInteractivePrimaryChannelErrorV0.unavailable
        }
        let messageID = environment.makeMessageID()
        let frame = try WireCodec.encode(WireEnvelope(
            messageID: messageID,
            correlationID: nil,
            sentAtUnixMilliseconds:
                environment.wallNowUnixMilliseconds(),
            body: try InteractiveSessionEndBodyV0(
                interactiveSessionID: WireUUID(
                    accepted.interactiveSessionID
                ),
                authorizationEpoch: accepted.authorizationEpoch
            )
        ))
        endRequestMessageID = messageID
        endingInteractiveSessionID = accepted.interactiveSessionID
        do {
            try await sender.sendAuthenticatedCommand(frame)
        } catch {
            endRequestMessageID = nil
            endingInteractiveSessionID = nil
            throw error
        }
        guard !invalidated else {
            endRequestMessageID = nil
            endingInteractiveSessionID = nil
            throw ClientInteractivePrimaryChannelErrorV0.unavailable
        }
        let event = ClientInteractivePrimarySessionEventV0.endSubmitted(
            interactiveSessionID: accepted.interactiveSessionID,
            effects: effects
        )
        publish(event)
        return event
    }

    @discardableResult
    public func admitInitialMedia(
        header: MediaRecordHeader,
        payloadByteCount: Int
    ) throws -> ClientMediaAdmissionV0 {
        if var replacementSurface {
            let admission = try replacementSurface.admitMedia(
                header: header,
                payloadByteCount: payloadByteCount
            )
            self.replacementSurface = replacementSurface
            return admission
        }
        guard !invalidated, var coordinator = initialSurface else {
            throw ClientInteractivePrimaryChannelErrorV0
                .initialSurfaceUnavailable
        }
        let admission = try coordinator.admitMedia(
            header: header,
            payloadByteCount: payloadByteCount
        )
        initialSurface = coordinator
        return admission
    }

    @discardableResult
    public func confirmInitialRenderedFrame(
        _ receipt: ClientDecodedFrameReceiptV0
    ) throws -> Bool {
        guard !invalidated, var coordinator = initialSurface else {
            throw ClientInteractivePrimaryChannelErrorV0
                .initialSurfaceUnavailable
        }
        let matched = try coordinator.confirmRenderedFrame(receipt)
        initialSurface = coordinator
        return matched
    }

    public func acknowledgeInitialSurface() async throws {
        guard !invalidated, var coordinator = initialSurface else {
            throw ClientInteractivePrimaryChannelErrorV0
                .initialSurfaceUnavailable
        }
        let frame = try coordinator.makeAcknowledgement(
            messageID: environment.makeMessageID(),
            sentAtUnixMilliseconds:
                environment.wallNowUnixMilliseconds()
        )
        do {
            try await sender.sendAuthenticatedCommand(frame)
        } catch {
            initialSurface = nil
            await authority.close()
            throw error
        }
        initialSurface = coordinator
    }

    public func makeInitialInputFrame(
        _ payload: InteractiveInputPayload
    ) throws -> Data {
        if var replacementSurface {
            let envelope = try replacementSurface.makeInput(
                messageID: environment.makeMessageID(),
                clientMonotonicMilliseconds:
                    environment.monotonicNowMilliseconds(),
                payload: payload
            )
            self.replacementSurface = replacementSurface
            return try InteractiveInputCodec.encode(envelope)
        }
        guard !invalidated, var coordinator = initialSurface else {
            throw ClientInteractivePrimaryChannelErrorV0
                .initialSurfaceUnavailable
        }
        let envelope = try coordinator.makeInput(
            messageID: environment.makeMessageID(),
            clientMonotonicMilliseconds:
                environment.monotonicNowMilliseconds(),
            payload: payload
        )
        initialSurface = coordinator
        return try InteractiveInputCodec.encode(envelope)
    }

    public func closeInitialInputFrame() throws -> Data? {
        if var replacementSurface {
            let envelope = try replacementSurface.closeInput(
                messageID: environment.makeMessageID(),
                clientMonotonicMilliseconds:
                    environment.monotonicNowMilliseconds()
            )
            self.replacementSurface = replacementSurface
            return try envelope.map(InteractiveInputCodec.encode)
        }
        guard !invalidated, var coordinator = initialSurface else {
            return nil
        }
        let envelope = try coordinator.closeInput(
            messageID: environment.makeMessageID(),
            clientMonotonicMilliseconds:
                environment.monotonicNowMilliseconds()
        )
        initialSurface = coordinator
        return try envelope.map(InteractiveInputCodec.encode)
    }

    private func remoteRejection(
        _ error: ClientInteractiveSessionErrorV0,
        kind: WireMessageKind
    ) throws -> ClientPrimaryPreparedReplyV0 {
        guard kind == .error,
              case let .remoteError(code, retry) = error else {
            throw error
        }
        requestedEffects = nil
        let event = ClientInteractivePrimarySessionEventV0.remoteRejected(
            ClientInteractiveRemoteErrorV0(code: code, retry: retry)
        )
        return ClientPrimaryPreparedReplyV0 { [publish] in publish(event) }
    }

    private static func interactionClasses(
        for effects: [InteractiveControlEffect]
    ) -> Set<SurfaceInteractionClass> {
        Set(effects.compactMap {
            SurfaceInteractionClass(rawValue: $0.rawValue)
        })
    }

    private func initialMonotonicMilliseconds() throws -> Int64 {
        let value = environment.monotonicNowMilliseconds()
        guard value <= UInt64(Int64.max) else {
            throw ClientInteractivePrimaryChannelErrorV0
                .initialSurfaceUnavailable
        }
        return Int64(value)
    }

    private func descriptorDeadlineReached(_ waiterID: UUID) {
        guard descriptorWaiterID == waiterID else { return }
        finishDescriptorWaiter(.failure(
            ClientInteractivePrimaryChannelErrorV0
                .initialSurfaceDeadlineExceeded
        ))
    }

    private func cancelDescriptorWaiter(_ waiterID: UUID) {
        guard descriptorWaiterID == waiterID else { return }
        finishDescriptorWaiter(.failure(
            ClientInteractivePrimaryChannelErrorV0.cancelled
        ))
    }

    private func finishDescriptorWaiter(
        _ result: Result<AdaptiveSurfaceDescriptor, any Error>
    ) {
        descriptorDeadlineTask?.cancel()
        descriptorDeadlineTask = nil
        descriptorWaiterID = nil
        let waiter = descriptorWaiter
        descriptorWaiter = nil
        waiter?.resume(with: result)
    }
}
