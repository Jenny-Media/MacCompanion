import CompanionClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionWire
import Foundation

private func clientInteractiveDebugTraceV0(_ message: String) {
#if DEBUG
    FileHandle.standardError.write(
        Data("[MacCompanion interactive] \(message)\n".utf8)
    )
#endif
}

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
    /// OS-backed user presence or local approval-key signing did not complete.
    /// This is a Control-request failure, not a primary protocol failure.
    case approvalFailed
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
    case mediaOffer(WireEnvelope<InteractiveWebRTCOfferBodyV0>)
    case mediaReady(WireEnvelope<InteractiveWebRTCReadyBodyV0>)
    case mediaRejected(ClientInteractiveRemoteErrorV0)
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
    case surfaceTransitionDeadlineExceeded
    case displayCommandDeadlineExceeded
    case cancelled
}

/// One primary-connection owner for the Interactive session approval flow.
/// Accepted role offers are inert until the separate role-channel and initial
/// Desktop authorities complete their own admission gates.
public actor ClientInteractivePrimaryChannelV0:
    ClientPrimaryReplyReceivingV0
{
    public nonisolated let primary: ClientInteractivePrimaryBindingV0

    private var authority: ClientInteractiveSessionAuthorityV0
    private let signer: any ClientInteractiveApprovalSigningV0
    private let sender: any ClientAuthenticatedCommandSendingV1
    private let environment: ClientInteractivePrimaryEnvironmentV0
    private let publish: @Sendable (
        ClientInteractivePrimarySessionEventV0
    ) -> Void
    private let publishFocus: @Sendable (ClientSurfaceFocusEventV0) -> Void
    private var requestedEffects: [InteractiveControlEffect]?
    private var initialSurface: ClientInitialSurfaceCoordinatorV0?
    private var replacementSurface: ClientSurfaceControlCoordinatorV0?
    private var descriptorWaiter: CheckedContinuation<
        AdaptiveSurfaceDescriptor, any Error
    >?
    private var descriptorWaiterID: UUID?
    private var descriptorDeadlineTask: Task<Void, Never>?
    private var endRequestMessageID: WireUUID?
    private var localInputStopped = false
    private var endingInteractiveSessionID: UUID?
    private var mediaOfferRequestMessageID: WireUUID?
    private var mediaAnswerRequestMessageID: WireUUID?
    private var mediaExpectedFence: InteractiveWebRTCNegotiationFenceV0?
    private var mediaCurrentOffer: WireEnvelope<InteractiveWebRTCOfferBodyV0>?
    private var mediaGeneration: Int64 = 0
    private var discardedMediaRequestIDs: Set<WireUUID> = []
    private var displayCatalogRequestMessageID: WireUUID?
    private var displayCatalogWaiter: CheckedContinuation<
        InteractiveDisplayCatalogResponseBodyV1, any Error
    >?
    private var displayCatalogDeadlineTask: Task<Void, Never>?
    private var displaySelectRequestMessageID: WireUUID?
    private var displaySelectWaiter: CheckedContinuation<
        InteractiveDisplaySelectedBodyV1, any Error
    >?
    private var displaySelectDeadlineTask: Task<Void, Never>?
    private enum NativeReply: Sendable {
        case challenge(WireEnvelope<InteractiveNativeVideoEnrollmentChallengeBodyV0>)
        case ready(WireEnvelope<InteractiveNativeVideoReadyBodyV0>)
        case presented(WireEnvelope<InteractiveNativeVideoPresentationReceiptBodyV0>)
        case cancelled(InteractiveNativeVideoRequestFenceV0)
    }
    private let nativeSessionPublicKeyX963: Data
    private var nativeOriginalControlDeadline: UInt64?
    private var nativeGeneration: Int64 = 0
    private var nativeCancellationTask: Task<Void, Error>?
    private var nativeCancellationToken: UUID?
    private var nativeFence: InteractiveNativeVideoRequestFenceV0?
    private var nativeEnrollmentOwnerID: UUID?
    private var nativeChallenge: WireEnvelope<InteractiveNativeVideoEnrollmentChallengeBodyV0>?
    private var nativeReady = false
    private var nativePresentationGeneration: Int64?
    private var nativeRequestID: WireUUID?
    private var nativeReplyKind: WireMessageKind?
    private var nativeWaiter: CheckedContinuation<NativeReply, any Error>?
    private var nativeDeadlineTask: Task<Void, Never>?
    private var discardedNativeReplies: [WireUUID: WireMessageKind] = [:]
    private var invalidated = false

    public init(
        pairedHost: ClientDurablePairedHostV0,
        authenticatedSession: ClientAuthenticatedSessionV0,
        signer: any ClientInteractiveApprovalSigningV0,
        sender: any ClientAuthenticatedCommandSendingV1,
        environment: ClientInteractivePrimaryEnvironmentV0,
        publish: @escaping @Sendable (
            ClientInteractivePrimarySessionEventV0
        ) -> Void = { _ in },
        publishFocus: @escaping @Sendable (
            ClientSurfaceFocusEventV0
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
        self.nativeSessionPublicKeyX963 = pairedHost.sessionKey.publicKeyX963
        self.signer = signer
        authority = ClientInteractiveSessionAuthorityV0(
            primary: primary,
            signer: signer
        )
        self.sender = sender
        self.environment = environment
        self.publish = publish
        self.publishFocus = publishFocus
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
            mediaGeneration = 0
            mediaCurrentOffer = nil
            mediaExpectedFence = nil
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

    public func requestDisplayCatalog(
        timeoutMilliseconds: UInt64
    ) async throws -> InteractiveDisplayCatalogResponseBodyV1 {
        let phase = await authority.phase
        guard !invalidated,
              displayCatalogRequestMessageID == nil,
              displaySelectRequestMessageID == nil,
              timeoutMilliseconds > 0,
              phase == .readyToRequest || phase == .closed
                || phase == .accepted else {
            throw ClientInteractivePrimaryChannelErrorV0.unavailable
        }
        let messageID = environment.makeMessageID()
        let frame = try WireCodec.encode(WireEnvelope(
            messageID: messageID,
            correlationID: nil,
            sentAtUnixMilliseconds: environment.wallNowUnixMilliseconds(),
            body: try InteractiveDisplayCatalogRequestBodyV1(
                authorizationEpoch: primary.authorizationEpoch
            )
        ))
        displayCatalogRequestMessageID = messageID
        let requestID = messageID.rawValue
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                displayCatalogWaiter = continuation
                displayCatalogDeadlineTask = Task { [weak self] in
                    do {
                        try await Task.sleep(
                            nanoseconds: min(
                                timeoutMilliseconds,
                                UInt64.max / 1_000_000
                            ) * 1_000_000
                        )
                    } catch { return }
                    await self?.displayCatalogDeadlineReached(requestID)
                }
                Task { [weak self, sender] in
                    do { try await sender.sendAuthenticatedCommand(frame) }
                    catch { await self?.failDisplayCatalogSend(requestID, error: error) }
                }
            }
        } onCancel: { [weak self] in
            Task { await self?.cancelDisplayCatalog(requestID) }
        }
    }

    public func requestDisplayCatalog() async throws
        -> InteractiveDisplayCatalogResponseBodyV1
    {
        try await requestDisplayCatalog(timeoutMilliseconds: 10_000)
    }

    public func selectDisplay(
        _ displayID: UUID,
        expectedAdmissionRevision: Int64,
        timeoutMilliseconds: UInt64 = 10_000
    ) async throws -> InteractiveDisplaySelectedBodyV1 {
        let phase = await authority.phase
        guard !invalidated,
              displayCatalogRequestMessageID == nil,
              displaySelectRequestMessageID == nil,
              timeoutMilliseconds > 0,
              phase == .readyToRequest || phase == .closed else {
            throw ClientInteractivePrimaryChannelErrorV0.unavailable
        }
        let messageID = environment.makeMessageID()
        let frame = try WireCodec.encode(WireEnvelope(
            messageID: messageID,
            correlationID: nil,
            sentAtUnixMilliseconds: environment.wallNowUnixMilliseconds(),
            body: try InteractiveDisplaySelectBodyV1(
                authorizationEpoch: primary.authorizationEpoch,
                expectedAdmissionRevision: expectedAdmissionRevision,
                displayID: WireUUID(displayID)
            )
        ))
        displaySelectRequestMessageID = messageID
        let requestID = messageID.rawValue
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                displaySelectWaiter = continuation
                displaySelectDeadlineTask = Task { [weak self] in
                    do {
                        try await Task.sleep(
                            nanoseconds: min(
                                timeoutMilliseconds,
                                UInt64.max / 1_000_000
                            ) * 1_000_000
                        )
                    } catch { return }
                    await self?.displaySelectDeadlineReached(requestID)
                }
                Task { [weak self, sender] in
                    do { try await sender.sendAuthenticatedCommand(frame) }
                    catch { await self?.failDisplaySelectSend(requestID, error: error) }
                }
            }
        } onCancel: { [weak self] in
            Task { await self?.cancelDisplaySelect(requestID) }
        }
    }

    public func requestNativeEnrollment(for descriptor: AdaptiveSurfaceDescriptor,
                                        clientCertificateDER: Data, localOwnerID: UUID? = nil,
                                        timeoutMilliseconds: UInt64 = 15_000) async throws
        -> WireEnvelope<InteractiveNativeVideoEnrollmentChallengeBodyV0> {
        guard let accepted = await authority.acceptedSession, !Task.isCancelled, !invalidated, endRequestMessageID == nil,
              nativeFence == nil, nativeRequestID == nil, nativeCancellationTask == nil, nativeGeneration < WireLimits.maximumSafeInteger,
              (descriptor.kind == .desktop || descriptor.kind == .application
                || descriptor.kind == .window),
              descriptor.interactiveSessionID == accepted.interactiveSessionID,
              descriptor.authorizationEpoch == accepted.authorizationEpoch, isCurrentNativeDescriptor(descriptor),
              nativeClockIsCurrent(), (1...4096).contains(clientCertificateDER.count),
              let surfaceRevision = Int64(exactly: descriptor.surfaceRevision.rawValue),
              let coordinateRevision = Int64(exactly: descriptor.coordinateSpaceRevision.rawValue) else {
            clientInteractiveDebugTraceV0("native request denied descriptorCurrent=\(isCurrentNativeDescriptor(descriptor)) clockCurrent=\(nativeClockIsCurrent()) initialPhase=\(String(describing: initialSurface?.phase)) replacementPhase=\(String(describing: replacementSurface?.phase))")
            throw ClientInteractivePrimaryChannelErrorV0.unavailable
        }
        clientInteractiveDebugTraceV0("native request admitted")
        nativeGeneration += 1
        let fence = try InteractiveNativeVideoRequestFenceV0(interactiveSessionID: WireUUID(descriptor.interactiveSessionID),
            authorizationEpoch: descriptor.authorizationEpoch, negotiationID: environment.makeMessageID(), peerGeneration: nativeGeneration,
            surfaceID: WireUUID(descriptor.surfaceID), surfaceRevision: surfaceRevision,
            coordinateSpaceRevision: coordinateRevision)
        nativeFence = fence
        nativeEnrollmentOwnerID = localOwnerID
        let body = try InteractiveNativeVideoEnrollmentRequestBodyV0(fence: fence, clientCertificateDERBase64: clientCertificateDER.base64EncodedString())
        let reply = try await waitNative(body, expected: .nativeEnrollChallenge, timeout: timeoutMilliseconds)
        guard case .challenge(let challenge) = reply else { throw ClientInteractivePrimaryChannelErrorV0.unavailable }
        return challenge
    }

    /// Uses the exact stored, correlated challenge to build trusted local facts.
    public func nativeAttestationAuthority(for challenge: WireEnvelope<InteractiveNativeVideoEnrollmentChallengeBodyV0>)
        -> ClientNativeVideoAttestationAuthorityV0? {
        guard !invalidated, endRequestMessageID == nil, nativeChallenge == challenge,
              nativeFence == challenge.body.fence, nativeClockIsCurrent(),
              let descriptor = currentNativeDescriptor(), isCurrentNativeDescriptor(descriptor),
              Int(descriptor.encodedWidth) == Int(challenge.body.encodedWidth),
              Int(descriptor.encodedHeight) == Int(challenge.body.encodedHeight),
              let deadline = nativeOriginalControlDeadline,
              let epoch = Int64(exactly: primary.authorizationEpoch.rawValue),
              let grant = Int64(exactly: primary.grantRevision.rawValue), let policy = Int64(exactly: primary.policyRevision.rawValue),
              let surfaceRevision = Int64(exactly: descriptor.surfaceRevision.rawValue),
              let coordinateRevision = Int64(exactly: descriptor.coordinateSpaceRevision.rawValue) else { return nil }
        guard let binding = try? InteractiveNativeVideoBindingV0(hostID: primary.hostID, hostFingerprint: primary.hostFingerprint,
            clientID: primary.clientID, primaryConnectionID: primary.primaryConnectionID,
            interactiveSessionID: descriptor.interactiveSessionID, authorizationEpoch: epoch,
            grantRevision: grant, policyRevision: policy,
            controlGeneration: challenge.body.controlGeneration.rawValue,
            expiresAtMonotonicMilliseconds: deadline),
            let surface = try? InteractiveNativeVideoSurfaceV0(surfaceID: descriptor.surfaceID, surfaceRevision: surfaceRevision,
                coordinateSpaceRevision: coordinateRevision, encodedWidth: Int(descriptor.encodedWidth), encodedHeight: Int(descriptor.encodedHeight)) else { return nil }
        return try? .init(binding: binding, surface: surface, sessionPublicKeyX963: nativeSessionPublicKeyX963)
    }

    public func submitNativeEnrollmentProof(for challenge: WireEnvelope<InteractiveNativeVideoEnrollmentChallengeBodyV0>,
                                            signature: Data, timeoutMilliseconds: UInt64 = 15_000) async throws
        -> WireEnvelope<InteractiveNativeVideoReadyBodyV0> {
        guard nativeAttestationAuthority(for: challenge) != nil, nativeRequestID == nil else {
            throw ClientInteractivePrimaryChannelErrorV0.unavailable
        }
        let body = try InteractiveNativeVideoEnrollmentProofBodyV0(fence: challenge.body.fence,
            challengeMessageID: challenge.messageID, signatureBase64: signature.base64EncodedString())
        let reply = try await waitNative(body, expected: .nativeReady, timeout: timeoutMilliseconds)
        guard case .ready(let ready) = reply else { throw ClientInteractivePrimaryChannelErrorV0.unavailable }
        return ready
    }

    /// The native renderer owner calls this only after its exact frame is
    /// visible. The receipt remains separate from an input admission permit.
    public func acknowledgeNativePresentation(nativeGeneration: Int64, encodedWidth: UInt16,
                                               encodedHeight: UInt16, timeoutMilliseconds: UInt64 = 5_000) async throws
        -> WireEnvelope<InteractiveNativeVideoPresentationReceiptBodyV0> {
        guard nativeReady, nativeRequestID == nil, nativeCancellationTask == nil,
              let challenge = nativeChallenge, nativeAttestationAuthority(for: challenge) != nil,
              encodedWidth == challenge.body.encodedWidth, encodedHeight == challenge.body.encodedHeight,
              nativePresentationGeneration == nil || nativePresentationGeneration == nativeGeneration else {
            throw ClientInteractivePrimaryChannelErrorV0.unavailable
        }
        let body = try InteractiveNativeVideoPresentationRequestBodyV0(fence: challenge.body.fence,
            challengeMessageID: challenge.messageID, nativeGeneration: nativeGeneration,
            encodedWidth: encodedWidth, encodedHeight: encodedHeight)
        nativePresentationGeneration = nativeGeneration
        let reply = try await waitNative(body, expected: .nativePresentReceipt, timeout: timeoutMilliseconds)
        guard case .presented(let receipt) = reply else { throw ClientInteractivePrimaryChannelErrorV0.unavailable }
        return receipt
    }

    public func cancelNativeEnrollment(ownedBy localOwnerID: UUID, timeoutMilliseconds: UInt64 = 15_000) async throws {
        guard nativeEnrollmentOwnerID == localOwnerID else { return }
        try await cancelNativeEnrollment(timeoutMilliseconds: timeoutMilliseconds)
    }

    public func cancelNativeEnrollment(timeoutMilliseconds: UInt64 = 15_000) async throws {
        if let nativeCancellationTask {
            let token = nativeCancellationToken
            defer {
                if nativeCancellationToken == token { self.nativeCancellationTask = nil; nativeCancellationToken = nil }
            }
            try await nativeCancellationTask.value
            return
        }
        guard !invalidated, endRequestMessageID == nil, let fence = nativeFence else { return }
        let token = UUID()
        let task = Task { try await self.performNativeCancellation(fence, timeoutMilliseconds: timeoutMilliseconds) }
        nativeCancellationTask = task
        nativeCancellationToken = token
        defer {
            if nativeCancellationToken == token { nativeCancellationTask = nil; nativeCancellationToken = nil }
        }
        try await task.value
    }

    private func performNativeCancellation(_ fence: InteractiveNativeVideoRequestFenceV0, timeoutMilliseconds: UInt64) async throws {
        guard !invalidated, endRequestMessageID == nil, nativeFence == fence else { return }
        if let requestID = nativeRequestID { discardNativeWaiter(requestID) }
        let reply = try await waitNative(InteractiveNativeVideoCancelBodyV0(fence: fence), expected: .nativeCancelled, timeout: timeoutMilliseconds)
        guard case .cancelled = reply else { throw ClientInteractivePrimaryChannelErrorV0.unavailable }
    }

    private func currentNativeDescriptor() -> AdaptiveSurfaceDescriptor? {
        if let replacementSurface, replacementSurface.phase != .closed { return replacementSurface.descriptor }
        return initialSurface?.descriptor
    }
    private func isCurrentNativeDescriptor(_ descriptor: AdaptiveSurfaceDescriptor) -> Bool {
        let phaseIsActive = replacementSurface.map { $0.phase == .active } ?? (initialSurface?.phase == .active)
        // Wire validity measures freshness for admission. An acknowledged
        // active surface remains fenced by Control and its exact revisions.
        return phaseIsActive && isCurrentMediaDescriptor(descriptor)
    }
    private func nativeClockIsCurrent() -> Bool {
        guard let deadline = nativeOriginalControlDeadline else { return false }
        return environment.monotonicNowMilliseconds() < deadline
    }

    private func waitNative<B: WireBody>(_ body: B, expected: WireMessageKind, timeout: UInt64) async throws -> NativeReply {
        guard !invalidated, nativeRequestID == nil, endRequestMessageID == nil, (1...15_000).contains(timeout) else {
            throw ClientInteractivePrimaryChannelErrorV0.unavailable
        }
        let requestID = environment.makeMessageID()
        let frame = try WireCodec.encode(WireEnvelope(messageID: requestID, correlationID: nil,
            sentAtUnixMilliseconds: environment.wallNowUnixMilliseconds(), body: body))
        nativeRequestID = requestID; nativeReplyKind = expected
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // Reserve the waiter before send: a synchronous transport reply
                // is safe and cannot be lost between send and suspension.
                nativeWaiter = continuation
                nativeDeadlineTask = Task { [weak self] in
                    do { try await Task.sleep(for: .milliseconds(timeout)) } catch { return }
                    await self?.abandonNative(requestID)
                }
                Task { [weak self, sender] in
                    do { try await sender.sendAuthenticatedCommand(frame) }
                    catch { await self?.abandonNative(requestID) }
                }
            }
        } onCancel: { [weak self] in Task { await self?.abandonNative(requestID) } }
    }

    private func prepareNativeReply(_ frame: Data, requestID: WireUUID, kind: WireMessageKind) throws -> ClientPrimaryPreparedReplyV0? {
        if let expected = discardedNativeReplies.removeValue(forKey: requestID) {
            _ = try decodeNativeReply(frame, kind: kind, expected: expected)
            return ClientPrimaryPreparedReplyV0 {}
        }
        guard nativeRequestID == requestID, let expected = nativeReplyKind else { return nil }
        let result = try decodeNativeReply(frame, kind: kind, expected: expected)
        return ClientPrimaryPreparedReplyV0 { [weak self] in
            Task { await self?.commitNativeReply(result, requestID: requestID) }
        }
    }
    private func decodeNativeReply(_ frame: Data, kind: WireMessageKind, expected: WireMessageKind) throws -> Result<NativeReply, any Error> {
        if kind == .error {
            let response = try WireCodec.decode(WireEnvelope<ProtocolErrorResponseBody>.self, from: frame)
            return .failure(ClientInteractiveSessionErrorV0.remoteError(code: response.body.code, retry: response.body.retry))
        }
        guard kind == expected else { throw ClientInteractivePrimaryChannelErrorV0.unavailable }
        switch kind {
        case .nativeEnrollChallenge:
            return .success(.challenge(try WireCodec.decode(WireEnvelope<InteractiveNativeVideoEnrollmentChallengeBodyV0>.self, from: frame)))
        case .nativeReady:
            return .success(.ready(try WireCodec.decode(WireEnvelope<InteractiveNativeVideoReadyBodyV0>.self, from: frame)))
        case .nativePresentReceipt:
            return .success(.presented(try WireCodec.decode(WireEnvelope<InteractiveNativeVideoPresentationReceiptBodyV0>.self, from: frame)))
        case .nativeCancelled:
            let response = try WireCodec.decode(WireEnvelope<InteractiveNativeVideoCancelledBodyV0>.self, from: frame)
            return .success(.cancelled(response.body.fence))
        default: throw ClientInteractivePrimaryChannelErrorV0.unavailable
        }
    }
    private func commitNativeReply(_ result: Result<NativeReply, any Error>, requestID: WireUUID) {
        guard nativeRequestID == requestID, !invalidated, endRequestMessageID == nil else { return }
        switch result {
        case .success(.challenge(let challenge)):
            guard challenge.body.fence == nativeFence, nativeClockIsCurrent(),
                  let descriptor = currentNativeDescriptor(), isCurrentNativeDescriptor(descriptor),
                  descriptor.encodedWidth == challenge.body.encodedWidth, descriptor.encodedHeight == challenge.body.encodedHeight else {
                finishNativeWaiter(.failure(ClientInteractivePrimaryChannelErrorV0.unavailable)); return
            }
            nativeChallenge = challenge
        case .success(.ready(let ready)):
            guard ready.body.fence == nativeFence, ready.body.challengeMessageID == nativeChallenge?.messageID,
                  let challenge = nativeChallenge, nativeAttestationAuthority(for: challenge) != nil else {
                finishNativeWaiter(.failure(ClientInteractivePrimaryChannelErrorV0.unavailable)); return
            }
            nativeReady = true
        case .success(.presented(let receipt)):
            guard nativeReady, receipt.body.fence == nativeFence,
                  receipt.body.challengeMessageID == nativeChallenge?.messageID,
                  receipt.body.nativeGeneration == nativePresentationGeneration,
                  let challenge = nativeChallenge, nativeAttestationAuthority(for: challenge) != nil,
                  let descriptor = currentNativeDescriptor(), isCurrentNativeDescriptor(descriptor),
                  receipt.body.encodedWidth == descriptor.encodedWidth,
                  receipt.body.encodedHeight == descriptor.encodedHeight,
                  receipt.body.logicalWidthPoints == descriptor.logicalWidthPoints,
                  receipt.body.logicalHeightPoints == descriptor.logicalHeightPoints else {
                finishNativeWaiter(.failure(ClientInteractivePrimaryChannelErrorV0.unavailable)); return
            }
        case .success(.cancelled(let fence)):
            guard nativeFence == fence else { finishNativeWaiter(.failure(ClientInteractivePrimaryChannelErrorV0.unavailable)); return }
            nativeFence = nil; nativeEnrollmentOwnerID = nil
            nativeChallenge = nil; nativeReady = false; nativePresentationGeneration = nil
        case .failure: break
        }
        finishNativeWaiter(result)
    }
    private func finishNativeWaiter(_ result: Result<NativeReply, any Error>) {
        nativeDeadlineTask?.cancel(); nativeDeadlineTask = nil
        let waiter = nativeWaiter; nativeWaiter = nil; nativeRequestID = nil; nativeReplyKind = nil
        waiter?.resume(with: result)
    }
    private func discardNativeWaiter(_ requestID: WireUUID) {
        guard nativeRequestID == requestID else { return }
        if let kind = nativeReplyKind {
            if discardedNativeReplies.count >= 64, let oldest = discardedNativeReplies.keys.first { discardedNativeReplies.removeValue(forKey: oldest) }
            discardedNativeReplies[requestID] = kind
        }
        finishNativeWaiter(.failure(ClientInteractivePrimaryChannelErrorV0.cancelled))
    }
    private func abandonNative(_ requestID: WireUUID) async {
        guard nativeRequestID == requestID else { return }
        let cancelling = nativeReplyKind == .nativeCancelled
        discardNativeWaiter(requestID)
        if !cancelling, !invalidated, endRequestMessageID == nil { try? await cancelNativeEnrollment() }
    }
    private func fenceNativeSession() {
        nativeCancellationTask?.cancel(); nativeCancellationTask = nil; nativeCancellationToken = nil
        if let id = nativeRequestID { discardNativeWaiter(id) }
        nativeFence = nil; nativeEnrollmentOwnerID = nil
        nativeChallenge = nil; nativeReady = false; nativePresentationGeneration = nil
    }

    /// Starts one complete-gathering negotiation on the current acknowledged
    /// or awaiting-media surface. The caller owns WebRTC peer creation and
    /// must replace its old peer before invoking this method.
    public func requestWebRTCOffer(
        for descriptor: AdaptiveSurfaceDescriptor
    ) async throws -> InteractiveWebRTCNegotiationFenceV0 {
        guard !invalidated,
              endRequestMessageID == nil,
              mediaOfferRequestMessageID == nil,
              mediaAnswerRequestMessageID == nil,
              mediaGeneration < WireLimits.maximumSafeInteger,
              let accepted = await authority.acceptedSession,
              environment.wallNowUnixMilliseconds()
                < accepted.expiresAtUnixMilliseconds,
              descriptor.interactiveSessionID
                == accepted.interactiveSessionID,
              descriptor.authorizationEpoch == accepted.authorizationEpoch,
              let surfaceRevision = Int64(
                exactly: descriptor.surfaceRevision.rawValue
              ),
              let coordinateSpaceRevision = Int64(
                exactly: descriptor.coordinateSpaceRevision.rawValue
              ),
              isCurrentMediaDescriptor(descriptor) else {
            throw ClientInteractivePrimaryChannelErrorV0.unavailable
        }
        mediaGeneration += 1
        let fence = try InteractiveWebRTCNegotiationFenceV0(
            interactiveSessionID: WireUUID(accepted.interactiveSessionID),
            authorizationEpoch: accepted.authorizationEpoch,
            negotiationID: environment.makeMessageID(),
            peerGeneration: mediaGeneration,
            surfaceID: WireUUID(descriptor.surfaceID),
            surfaceRevision: surfaceRevision,
            coordinateSpaceRevision: coordinateSpaceRevision
        )
        let messageID = environment.makeMessageID()
        let frame = try WireCodec.encode(WireEnvelope(
            messageID: messageID, correlationID: nil,
            sentAtUnixMilliseconds:
                environment.wallNowUnixMilliseconds(),
            body: try InteractiveWebRTCOfferRequestBodyV0(fence: fence)
        ))
        mediaOfferRequestMessageID = messageID
        mediaExpectedFence = fence
        mediaCurrentOffer = nil
        do {
            try await sender.sendAuthenticatedCommand(frame)
        } catch {
            mediaOfferRequestMessageID = nil
            mediaExpectedFence = nil
            throw error
        }
        return fence
    }

    public func submitWebRTCAnswer(
        for offer: WireEnvelope<InteractiveWebRTCOfferBodyV0>,
        sdp: String,
        dtlsFingerprintHex: String
    ) async throws {
        guard !invalidated,
              endRequestMessageID == nil,
              mediaOfferRequestMessageID == nil,
              mediaAnswerRequestMessageID == nil,
              mediaCurrentOffer == offer,
              mediaExpectedFence == offer.body.fence,
              isCurrentMediaFence(offer.body.fence),
              let accepted = await authority.acceptedSession,
              environment.wallNowUnixMilliseconds()
                < accepted.expiresAtUnixMilliseconds else {
            throw ClientInteractivePrimaryChannelErrorV0.unavailable
        }
        let messageID = environment.makeMessageID()
        let frame = try WireCodec.encode(WireEnvelope(
            messageID: messageID, correlationID: nil,
            sentAtUnixMilliseconds:
                environment.wallNowUnixMilliseconds(),
            body: try InteractiveWebRTCAnswerBodyV0(
                fence: offer.body.fence,
                offerMessageID: offer.messageID,
                sdp: sdp,
                dtlsFingerprintHex: dtlsFingerprintHex
            )
        ))
        mediaAnswerRequestMessageID = messageID
        do {
            try await sender.sendAuthenticatedCommand(frame)
        } catch {
            mediaAnswerRequestMessageID = nil
            throw error
        }
    }

    private func isCurrentMediaDescriptor(
        _ descriptor: AdaptiveSurfaceDescriptor
    ) -> Bool {
        if let replacementSurface,
           replacementSurface.phase != .closed {
            return sameMediaSurface(replacementSurface.descriptor, descriptor)
                && (replacementSurface.phase == .awaitingMedia
                    || replacementSurface.phase == .active)
        }
        if let initialSurface,
           let current = initialSurface.descriptor,
           sameMediaSurface(current, descriptor),
           (initialSurface.phase == .awaitingMedia
            || initialSurface.phase == .active) {
            return true
        }
        return false
    }

    private func sameMediaSurface(
        _ current: AdaptiveSurfaceDescriptor,
        _ candidate: AdaptiveSurfaceDescriptor
    ) -> Bool {
        current.interactiveSessionID == candidate.interactiveSessionID
            && current.authorizationEpoch == candidate.authorizationEpoch
            && current.surfaceID == candidate.surfaceID
            && current.surfaceRevision == candidate.surfaceRevision
            && current.coordinateSpaceRevision
                == candidate.coordinateSpaceRevision
    }

    private func isCurrentMediaFence(
        _ fence: InteractiveWebRTCNegotiationFenceV0
    ) -> Bool {
        let descriptor: AdaptiveSurfaceDescriptor?
        if let replacementSurface,
           replacementSurface.phase != .closed {
            descriptor = replacementSurface.descriptor
        } else {
            descriptor = initialSurface?.descriptor
        }
        guard let descriptor,
              isCurrentMediaDescriptor(descriptor) else { return false }
        return descriptor.interactiveSessionID
                == fence.interactiveSessionID.rawValue
            && descriptor.authorizationEpoch == fence.authorizationEpoch
            && descriptor.surfaceID == fence.surfaceID.rawValue
            && Int64(exactly: descriptor.surfaceRevision.rawValue)
                == fence.surfaceRevision
            && Int64(exactly: descriptor.coordinateSpaceRevision.rawValue)
                == fence.coordinateSpaceRevision
    }

    public func preparePrimaryReply(
        _ frame: Data
    ) async throws -> ClientPrimaryPreparedReplyV0 {
        guard !invalidated else {
            throw ClientInteractivePrimaryChannelErrorV0.unavailable
        }
        let kind = try WireCodec.messageKind(from: frame)
        let correlationID = try WireCodec.routingMetadata(from: frame)
            .correlationID
        if let correlationID, let prepared = try prepareNativeReply(frame, requestID: correlationID, kind: kind) { return prepared }
        if let correlationID,
           discardedMediaRequestIDs.remove(correlationID) != nil {
            switch kind {
            case .interactiveMediaOffer:
                _ = try WireCodec.decode(
                    WireEnvelope<InteractiveWebRTCOfferBodyV0>.self,
                    from: frame
                )
            case .interactiveMediaReady:
                _ = try WireCodec.decode(
                    WireEnvelope<InteractiveWebRTCReadyBodyV0>.self,
                    from: frame
                )
            case .error:
                _ = try WireCodec.decode(
                    WireEnvelope<ProtocolErrorResponseBody>.self,
                    from: frame
                )
            default:
                throw ClientInteractivePrimaryChannelErrorV0.unavailable
            }
            return ClientPrimaryPreparedReplyV0 {}
        }
        if correlationID == mediaOfferRequestMessageID,
           mediaOfferRequestMessageID != nil {
            mediaOfferRequestMessageID = nil
            if kind == .error {
                let response = try WireCodec.decode(
                    WireEnvelope<ProtocolErrorResponseBody>.self,
                    from: frame
                )
                mediaCurrentOffer = nil
                mediaExpectedFence = nil
                let event = ClientInteractivePrimarySessionEventV0
                    .mediaRejected(ClientInteractiveRemoteErrorV0(
                        code: response.body.code, retry: response.body.retry
                    ))
                return ClientPrimaryPreparedReplyV0 { [publish] in
                    publish(event)
                }
            }
            guard kind == .interactiveMediaOffer else {
                throw ClientInteractivePrimaryChannelErrorV0.unavailable
            }
            let response = try WireCodec.decode(
                WireEnvelope<InteractiveWebRTCOfferBodyV0>.self,
                from: frame
            )
            guard response.body.fence == mediaExpectedFence,
                  !invalidated, endRequestMessageID == nil,
                  let accepted = await authority.acceptedSession,
                  environment.wallNowUnixMilliseconds()
                    < accepted.expiresAtUnixMilliseconds else {
                throw ClientInteractivePrimaryChannelErrorV0.unavailable
            }
            guard isCurrentMediaFence(response.body.fence) else {
                mediaExpectedFence = nil
                return ClientPrimaryPreparedReplyV0 {}
            }
            mediaCurrentOffer = response
            let event = ClientInteractivePrimarySessionEventV0
                .mediaOffer(response)
            return ClientPrimaryPreparedReplyV0 { [publish] in
                publish(event)
            }
        }
        if correlationID == mediaAnswerRequestMessageID,
           mediaAnswerRequestMessageID != nil {
            mediaAnswerRequestMessageID = nil
            if kind == .error {
                let response = try WireCodec.decode(
                    WireEnvelope<ProtocolErrorResponseBody>.self,
                    from: frame
                )
                mediaCurrentOffer = nil
                mediaExpectedFence = nil
                let event = ClientInteractivePrimarySessionEventV0
                    .mediaRejected(ClientInteractiveRemoteErrorV0(
                        code: response.body.code, retry: response.body.retry
                    ))
                return ClientPrimaryPreparedReplyV0 { [publish] in
                    publish(event)
                }
            }
            guard kind == .interactiveMediaReady,
                  let offer = mediaCurrentOffer else {
                throw ClientInteractivePrimaryChannelErrorV0.unavailable
            }
            let response = try WireCodec.decode(
                WireEnvelope<InteractiveWebRTCReadyBodyV0>.self,
                from: frame
            )
            guard response.body.fence == mediaExpectedFence,
                  response.body.offerMessageID == offer.messageID,
                  !invalidated, endRequestMessageID == nil,
                  let accepted = await authority.acceptedSession,
                  environment.wallNowUnixMilliseconds()
                    < accepted.expiresAtUnixMilliseconds else {
                throw ClientInteractivePrimaryChannelErrorV0.unavailable
            }
            guard isCurrentMediaFence(response.body.fence) else {
                mediaCurrentOffer = nil
                mediaExpectedFence = nil
                return ClientPrimaryPreparedReplyV0 {}
            }
            mediaCurrentOffer = nil
            mediaExpectedFence = nil
            let event = ClientInteractivePrimarySessionEventV0
                .mediaReady(response)
            return ClientPrimaryPreparedReplyV0 { [publish] in
                publish(event)
            }
        }
        if let requestID = displayCatalogRequestMessageID,
           correlationID == requestID {
            if kind == .error {
                let response = try WireCodec.decode(
                    WireEnvelope<ProtocolErrorResponseBody>.self,
                    from: frame
                )
                guard response.correlationID == requestID else {
                    throw ClientInteractivePrimaryChannelErrorV0.unavailable
                }
                finishDisplayCatalog(.failure(
                    ClientInteractiveSessionErrorV0.remoteError(
                        code: response.body.code,
                        retry: response.body.retry
                    )
                ))
                return ClientPrimaryPreparedReplyV0 {}
            }
            guard kind == .interactiveDisplayCatalogResponse else {
                throw ClientInteractivePrimaryChannelErrorV0.unavailable
            }
            let response = try WireCodec.decode(
                WireEnvelope<InteractiveDisplayCatalogResponseBodyV1>.self,
                from: frame
            )
            guard response.correlationID == requestID,
                  response.body.authorizationEpoch
                    == primary.authorizationEpoch else {
                throw ClientInteractivePrimaryChannelErrorV0.unavailable
            }
            finishDisplayCatalog(.success(response.body))
            return ClientPrimaryPreparedReplyV0 {}
        }
        if let requestID = displaySelectRequestMessageID,
           correlationID == requestID {
            if kind == .error {
                let response = try WireCodec.decode(
                    WireEnvelope<ProtocolErrorResponseBody>.self,
                    from: frame
                )
                guard response.correlationID == requestID else {
                    throw ClientInteractivePrimaryChannelErrorV0.unavailable
                }
                finishDisplaySelect(.failure(
                    ClientInteractiveSessionErrorV0.remoteError(
                        code: response.body.code,
                        retry: response.body.retry
                    )
                ))
                return ClientPrimaryPreparedReplyV0 {}
            }
            guard kind == .interactiveDisplaySelected else {
                throw ClientInteractivePrimaryChannelErrorV0.unavailable
            }
            let response = try WireCodec.decode(
                WireEnvelope<InteractiveDisplaySelectedBodyV1>.self,
                from: frame
            )
            guard response.correlationID == requestID,
                  response.body.authorizationEpoch
                    == primary.authorizationEpoch else {
                throw ClientInteractivePrimaryChannelErrorV0.unavailable
            }
            finishDisplaySelect(.success(response.body))
            return ClientPrimaryPreparedReplyV0 {}
        }
        guard let effects = requestedEffects else {
            throw ClientInteractivePrimaryChannelErrorV0.unavailable
        }
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
            mediaCurrentOffer = nil
            mediaExpectedFence = nil
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
        if kind == .interactiveSurfaceSelected,
           replacementSurface?.phase == .awaitingSelection {
            let response = try WireCodec.decode(
                WireEnvelope<InteractiveSurfaceSelectedBodyV0>.self,
                from: frame
            )
            guard let boundary = UInt64(exactly: response.body.mediaSequenceBeforeTransition) else {
                throw ClientInteractivePrimaryChannelErrorV0.invalidConfiguration
            }
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while let coordinator = replacementSurface,
                  coordinator.phase == .awaitingSelection,
                  coordinator.media.lastMediaSequence < boundary {
                guard !invalidated, ContinuousClock.now < deadline else {
                    throw ClientInteractivePrimaryChannelErrorV0
                        .surfaceTransitionDeadlineExceeded
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            guard !invalidated else {
                throw ClientInteractivePrimaryChannelErrorV0.unavailable
            }
        }
        // Re-read after suspension: media admission may have advanced the
        // old-surface boundary while the primary response was waiting.
        if var coordinator = replacementSurface {
            defer { replacementSurface = coordinator }
            switch (coordinator.phase, kind) {
            case (.active, .interactiveSurfaceTargetsResponse):
                try coordinator.receiveTargetInventory(
                    frame,
                    clientMonotonicNowMilliseconds:
                        try initialMonotonicMilliseconds()
                )
                return ClientPrimaryPreparedReplyV0 {}
            case (.awaitingSelection, .interactiveSurfaceSelected):
                try coordinator.receiveSelected(
                    frame,
                    clientMonotonicNowMilliseconds:
                        try initialMonotonicMilliseconds()
                )
                return ClientPrimaryPreparedReplyV0 {}
            case (.awaitingAcknowledgement,
                  .interactiveSurfaceAcknowledged):
                try coordinator.receiveAcknowledged(frame)
                return ClientPrimaryPreparedReplyV0 {}
            default:
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
                clientInteractiveDebugTraceV0("approval proof send started")
                do {
                    try await sender.sendAuthenticatedCommand(proof)
                    clientInteractiveDebugTraceV0(
                        "approval proof send completed"
                    )
                } catch {
                    clientInteractiveDebugTraceV0(
                        "approval proof send failed type=\(String(reflecting: type(of: error)))"
                    )
                    throw error
                }
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
            } catch {
                // LocalAuthentication cancellation, protected-key
                // unavailability, and local signing failures do not make an
                // authenticated Mac peer or its reply invalid. The authority
                // has already closed this one request; keep the primary router
                // alive so Observe, Act, and an explicit Control retry remain
                // available.
                requestedEffects = nil
                clientInteractiveDebugTraceV0(
                    "local approval failed type=\(String(reflecting: type(of: error)))"
                )
                return ClientPrimaryPreparedReplyV0 { [publish] in
                    publish(.approvalFailed)
                }
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
                let acceptedEnvelope = try WireCodec.decode(WireEnvelope<InteractiveSessionAcceptedBody>.self, from: frame)
                localInputStopped = false
                let (lifetime, lifetimeOverflow) = session.expiresAtUnixMilliseconds.subtractingReportingOverflow(acceptedEnvelope.sentAtUnixMilliseconds)
                let (remaining, wallOverflow) = session.expiresAtUnixMilliseconds.subtractingReportingOverflow(environment.wallNowUnixMilliseconds())
                nativeOriginalControlDeadline = nil
                if !lifetimeOverflow, !wallOverflow, lifetime > 0,
                   lifetime <= InteractiveSessionStateMachine.maximumDurationMilliseconds, remaining > 0 {
                    let (deadline, overflow) = environment.monotonicNowMilliseconds().addingReportingOverflow(UInt64(min(lifetime, remaining)))
                    if !overflow { nativeOriginalControlDeadline = deadline }
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

    public func preparePrimaryEvent(
        _ frame: Data
    ) async throws -> ClientPrimaryPreparedEventV0 {
        guard !invalidated, var coordinator = replacementSurface else {
            throw ClientInteractivePrimaryChannelErrorV0.unavailable
        }
        defer { replacementSurface = coordinator }
        let event = try coordinator.receiveFocusEvent(
            frame,
            clientMonotonicNowMilliseconds:
                try initialMonotonicMilliseconds()
        )
        return ClientPrimaryPreparedEventV0 { [publishFocus] in
            publishFocus(event)
        }
    }

    public func invalidatePrimaryReplyReceiver() async {
        guard !invalidated else { return }
        invalidated = true
        fenceNativeSession()
        discardedNativeReplies.removeAll()
        nativeOriginalControlDeadline = nil
        requestedEffects = nil
        endRequestMessageID = nil
        endingInteractiveSessionID = nil
        mediaOfferRequestMessageID = nil
        mediaAnswerRequestMessageID = nil
        mediaCurrentOffer = nil
        mediaExpectedFence = nil
        discardedMediaRequestIDs.removeAll()
        initialSurface = nil
        replacementSurface = nil
        finishDisplayCatalog(.failure(
            ClientInteractivePrimaryChannelErrorV0.cancelled
        ))
        finishDisplaySelect(.failure(
            ClientInteractivePrimaryChannelErrorV0.cancelled
        ))
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
    public func endSession(expectedInteractiveSessionID: UUID? = nil)
        async throws -> ClientInteractivePrimarySessionEventV0
    {
        // Read the authority before reserving the end slot. That cross-actor
        // read can suspend while another failure callback submits Stop.
        let accepted = await authority.acceptedSession
        guard !invalidated,
              endRequestMessageID == nil,
              let effects = requestedEffects,
              let accepted,
              expectedInteractiveSessionID == nil
                || expectedInteractiveSessionID == accepted.interactiveSessionID else {
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
        localInputStopped = true
        endingInteractiveSessionID = accepted.interactiveSessionID
        discardPendingMediaReplies()
        fenceNativeSession()
        nativeOriginalControlDeadline = nil
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
    ) async throws -> ClientMediaAdmissionV0 {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while let coordinator = replacementSurface,
              coordinator.phase == .awaitingSelection,
              header.surfaceID != coordinator.media.currentDescriptor.surfaceID
                || header.surfaceRevision
                    != coordinator.media.currentDescriptor.surfaceRevision
                || header.coordinateSpaceRevision
                    != coordinator.media.currentDescriptor.coordinateSpaceRevision {
            guard !invalidated, ContinuousClock.now < deadline else {
                throw ClientInteractivePrimaryChannelErrorV0
                    .surfaceTransitionDeadlineExceeded
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard !invalidated else {
            throw ClientInteractivePrimaryChannelErrorV0.unavailable
        }
        if var replacementSurface {
            defer { self.replacementSurface = replacementSurface }
            let admission = try replacementSurface.admitMedia(
                header: header,
                payloadByteCount: payloadByteCount
            )
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
        // A correlated reply may arrive while the send is suspended. Reserve
        // its receiving phase now, and preserve any state the reply commits.
        initialSurface = coordinator
        do {
            try await sender.sendAuthenticatedCommand(frame)
        } catch {
            if initialSurface?.descriptor == coordinator.descriptor {
                initialSurface = nil
                await authority.close()
            }
            throw error
        }
        guard !invalidated, !localInputStopped, endRequestMessageID == nil,
              initialSurface?.descriptor == coordinator.descriptor else {
            throw ClientInteractivePrimaryChannelErrorV0.initialSurfaceUnavailable
        }
    }

    public func requestReplacementSurfaceTargets() async throws {
        guard !invalidated, var coordinator = replacementSurface else {
            throw ClientInteractivePrimaryChannelErrorV0
                .initialSurfaceUnavailable
        }
        let frame: Data
        do {
            frame = try coordinator.makeTargetInventoryRequest(
                messageID: environment.makeMessageID(),
                sentAtUnixMilliseconds:
                    environment.wallNowUnixMilliseconds()
            )
        } catch {
            replacementSurface = coordinator
            throw error
        }
        // A correlated inventory can arrive while the transport send awaits.
        // Publish the pending request before that suspension, then leave any
        // reply committed during the send in place.
        replacementSurface = coordinator
        do {
            try await sender.sendAuthenticatedCommand(frame)
        } catch {
            replacementSurface = nil
            await authority.close()
            throw error
        }
        guard !invalidated, replacementSurface?.phase == .active else {
            throw ClientInteractivePrimaryChannelErrorV0.unavailable
        }
    }

    /// `nil` means the requested inventory has not completed. Empty is a
    /// completed, privacy-limited result.
    public func replacementSurfaceTargets()
        -> [InteractiveSurfaceTargetCandidateV0]?
    {
        replacementSurface?.availableTargetCandidates
    }

    public func prepareReplacementSurfaceSelection(
        targetKind: InteractiveSurfaceKind,
        targetToken: UUID?
    ) throws -> ClientSurfaceSelectionRequestV0 {
        try prepareReplacementSurfaceSelection(
            targetKind: targetKind,
            targetToken: targetToken,
            targetDisplayID: nil
        )
    }

    public func prepareReplacementSurfaceSelection(
        targetKind: InteractiveSurfaceKind,
        targetToken: UUID?,
        targetDisplayID: UUID?
    ) throws -> ClientSurfaceSelectionRequestV0 {
        guard !invalidated, var coordinator = replacementSurface else {
            throw ClientInteractivePrimaryChannelErrorV0
                .initialSurfaceUnavailable
        }
        defer { replacementSurface = coordinator }
        let request = try coordinator.beginSelection(
            targetKind: targetKind,
            targetToken: targetToken.map(WireUUID.init),
            targetDisplayID: targetDisplayID.map(WireUUID.init),
            resetMessageID: environment.makeMessageID(),
            requestMessageID: environment.makeMessageID(),
            sentAtUnixMilliseconds:
                environment.wallNowUnixMilliseconds(),
            clientMonotonicMilliseconds:
                environment.monotonicNowMilliseconds()
        )
        return request
    }

    public func sendReplacementSurfaceSelection(
        _ frame: Data
    ) async throws {
        guard !invalidated,
              replacementSurface?.phase == .awaitingSelection else {
            throw ClientInteractivePrimaryChannelErrorV0
                .initialSurfaceUnavailable
        }
        do {
            try await sender.sendAuthenticatedCommand(frame)
        } catch {
            replacementSurface = nil
            await authority.close()
            throw error
        }
    }

    public func replacementSurfacePhase()
        -> ClientSurfaceControlPhaseV0?
    {
        replacementSurface?.phase
    }

    public func replacementSurfaceDescriptor()
        -> AdaptiveSurfaceDescriptor?
    {
        replacementSurface?.descriptor
    }

    public func latestFocusEvent() -> ClientSurfaceFocusEventV0? {
        replacementSurface?.latestFocusEvent
    }

    @discardableResult
    public func confirmReplacementRenderedFrame(
        _ receipt: ClientDecodedFrameReceiptV0
    ) throws -> Bool {
        guard !invalidated, var coordinator = replacementSurface else {
            throw ClientInteractivePrimaryChannelErrorV0
                .initialSurfaceUnavailable
        }
        defer { replacementSurface = coordinator }
        guard coordinator.phase == .awaitingMedia else { return false }
        let matched = try coordinator.confirmRenderedFrame(receipt)
        return matched
    }

    public func acknowledgeReplacementSurface() async throws {
        guard !invalidated, var coordinator = replacementSurface else {
            throw ClientInteractivePrimaryChannelErrorV0
                .initialSurfaceUnavailable
        }
        let frame: Data
        do {
            frame = try coordinator.makeAcknowledgement(
                messageID: environment.makeMessageID(),
                sentAtUnixMilliseconds:
                    environment.wallNowUnixMilliseconds()
            )
        } catch {
            replacementSurface = coordinator
            throw error
        }
        replacementSurface = coordinator
        do {
            try await sender.sendAuthenticatedCommand(frame)
        } catch {
            replacementSurface = nil
            await authority.close()
            throw error
        }
        guard !invalidated, replacementSurface?.phase == .awaitingAcknowledgement
                || replacementSurface?.phase == .active else {
            throw ClientInteractivePrimaryChannelErrorV0.unavailable
        }
    }

    public func makeInitialInputFrame(
        _ payload: InteractiveInputPayload
    ) throws -> Data {
        guard !invalidated, !localInputStopped, endRequestMessageID == nil else {
            throw ClientInteractivePrimaryChannelErrorV0.unavailable
        }
        if var replacementSurface {
            defer { self.replacementSurface = replacementSurface }
            let envelope = try replacementSurface.makeInput(
                messageID: environment.makeMessageID(),
                clientMonotonicMilliseconds:
                    environment.monotonicNowMilliseconds(),
                payload: payload
            )
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
            defer { self.replacementSurface = replacementSurface }
            let envelope = try replacementSurface.closeInput(
                messageID: environment.makeMessageID(),
                clientMonotonicMilliseconds:
                    environment.monotonicNowMilliseconds()
            )
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

    private func discardPendingMediaReplies() {
        if let mediaOfferRequestMessageID {
            discardedMediaRequestIDs.insert(mediaOfferRequestMessageID)
        }
        if let mediaAnswerRequestMessageID {
            discardedMediaRequestIDs.insert(mediaAnswerRequestMessageID)
        }
        mediaOfferRequestMessageID = nil
        mediaAnswerRequestMessageID = nil
        mediaCurrentOffer = nil
        mediaExpectedFence = nil
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

    private func failDisplayCatalogSend(_ requestID: UUID, error: any Error) {
        guard displayCatalogRequestMessageID?.rawValue == requestID else {
            return
        }
        finishDisplayCatalog(.failure(error))
    }

    private func displayCatalogDeadlineReached(_ requestID: UUID) {
        guard displayCatalogRequestMessageID?.rawValue == requestID else {
            return
        }
        finishDisplayCatalog(.failure(
            ClientInteractivePrimaryChannelErrorV0
                .displayCommandDeadlineExceeded
        ))
    }

    private func cancelDisplayCatalog(_ requestID: UUID) {
        guard displayCatalogRequestMessageID?.rawValue == requestID else {
            return
        }
        finishDisplayCatalog(.failure(
            ClientInteractivePrimaryChannelErrorV0.cancelled
        ))
    }

    private func finishDisplayCatalog(
        _ result: Result<
            InteractiveDisplayCatalogResponseBodyV1,
            any Error
        >
    ) {
        displayCatalogDeadlineTask?.cancel()
        displayCatalogDeadlineTask = nil
        displayCatalogRequestMessageID = nil
        let waiter = displayCatalogWaiter
        displayCatalogWaiter = nil
        waiter?.resume(with: result)
    }

    private func failDisplaySelectSend(_ requestID: UUID, error: any Error) {
        guard displaySelectRequestMessageID?.rawValue == requestID else {
            return
        }
        finishDisplaySelect(.failure(error))
    }

    private func displaySelectDeadlineReached(_ requestID: UUID) {
        guard displaySelectRequestMessageID?.rawValue == requestID else {
            return
        }
        finishDisplaySelect(.failure(
            ClientInteractivePrimaryChannelErrorV0
                .displayCommandDeadlineExceeded
        ))
    }

    private func cancelDisplaySelect(_ requestID: UUID) {
        guard displaySelectRequestMessageID?.rawValue == requestID else {
            return
        }
        finishDisplaySelect(.failure(
            ClientInteractivePrimaryChannelErrorV0.cancelled
        ))
    }

    private func finishDisplaySelect(
        _ result: Result<InteractiveDisplaySelectedBodyV1, any Error>
    ) {
        displaySelectDeadlineTask?.cancel()
        displaySelectDeadlineTask = nil
        displaySelectRequestMessageID = nil
        let waiter = displaySelectWaiter
        displaySelectWaiter = nil
        waiter?.resume(with: result)
    }
}
