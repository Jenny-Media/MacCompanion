import Foundation
import CompanionDomain
import CompanionWire
import CompanionInteractiveWire
import CompanionInteractiveShared

/// Optional native engine seam for the authenticated Control dispatcher.
/// Factories must use current runtime Desktop/display/generation/deadline and
/// re-read durable session-key/grant authority through the coordinator reader.
public protocol InteractiveNativeVideoNegotiatingV0: Sendable {
    func prepare(_ request: InteractiveNativeVideoEnrollmentRequestBodyV0,
                 challengeMessageID: WireUUID, context: InteractiveSessionCommandContextV0,
                 sessionPublicKeyX963: Data) async throws -> InteractiveNativeVideoEnrollmentChallengeBodyV0
    func activate(_ proof: InteractiveNativeVideoEnrollmentProofBodyV0,
                  context: InteractiveSessionCommandContextV0, sessionPublicKeyX963: Data) async throws -> InteractiveNativeVideoReadyBodyV0
    func present(_ request: InteractiveNativeVideoPresentationRequestBodyV0,
                 context: InteractiveSessionCommandContextV0, sessionPublicKeyX963: Data) async throws
        -> InteractiveNativeVideoPresentationReceiptBodyV0
    func cancel(_ fence: InteractiveNativeVideoRequestFenceV0,
                context: InteractiveSessionCommandContextV0) async throws
    func retain(_ fence: InteractiveNativeVideoRequestFenceV0,
                context: InteractiveSessionCommandContextV0) async throws -> Bool
    func hasRetainedStream(context: InteractiveSessionCommandContextV0) async -> Bool
    func close(interactiveSessionID: UUID) async
}

public extension InteractiveNativeVideoNegotiatingV0 {
    func retain(_ fence: InteractiveNativeVideoRequestFenceV0,
                context: InteractiveSessionCommandContextV0) async throws -> Bool {
        try await cancel(fence, context: context)
        return false
    }
    func hasRetainedStream(context: InteractiveSessionCommandContextV0) async -> Bool { false }
    func present(_ request: InteractiveNativeVideoPresentationRequestBodyV0,
                 context: InteractiveSessionCommandContextV0, sessionPublicKeyX963: Data) async throws
        -> InteractiveNativeVideoPresentationReceiptBodyV0 {
        throw InteractiveNativeVideoCoordinatorFailureV0.backendUnavailable
    }
}

/// Retains pending construction and joins retirement before a replacement can
/// start. An old operation's compensation cannot close its replacement.
public actor InteractiveNativeVideoPrimaryBridgeV0: InteractiveNativeVideoNegotiatingV0 {
    public typealias Factory = @Sendable (InteractiveNativeVideoRequestFenceV0,
        InteractiveSessionCommandContextV0, Data) async throws -> InteractiveNativeVideoEnrollmentCoordinatorV0
    public typealias ReplacementFactory = @Sendable (InteractiveNativeVideoRequestFenceV0,
        InteractiveSessionCommandContextV0, Data, InteractiveNativeVideoRetainedEnrollmentV1) async throws -> InteractiveNativeVideoEnrollmentCoordinatorV0
    private enum Phase { case preparing, challenged, proving, active, presenting, retaining, retained }
    private struct Operation {
        let token: UUID
        let fence: InteractiveNativeVideoRequestFenceV0
        let context: InteractiveSessionCommandContextV0
        let key: Data
        let challengeID: WireUUID
        let continuityRequested: Bool
        var continuityAdmitted = false
        var rendererGeneration: Int64? = nil
        var phase: Phase
    }
    private let factory: Factory
    private let replacementFactory: ReplacementFactory?
    private var operation: Operation?
    private var creation: Task<InteractiveNativeVideoEnrollmentCoordinatorV0, Error>?
    private var owner: InteractiveNativeVideoEnrollmentCoordinatorV0?
    private var drain: Task<Void, Never>?
    private var drainToken: UUID?
    private var lastCancelled: (InteractiveNativeVideoRequestFenceV0, InteractiveSessionCommandContextV0)?
    private var predecessorOwner: InteractiveNativeVideoEnrollmentCoordinatorV0?
    private var retentionWatchdog: Task<Void, Never>?
    private var retentionToken: UUID?

    public init(factory: @escaping Factory, replacementFactory: ReplacementFactory? = nil) {
        self.factory = factory; self.replacementFactory = replacementFactory
    }

    public func prepare(_ request: InteractiveNativeVideoEnrollmentRequestBodyV0,
                        challengeMessageID: WireUUID, context: InteractiveSessionCommandContextV0,
                        sessionPublicKeyX963: Data) async throws -> InteractiveNativeVideoEnrollmentChallengeBodyV0 {
        guard creation == nil, drain == nil else {
            throw InteractiveNativeVideoCoordinatorFailureV0.invalidPhase
        }
        let retained: InteractiveNativeVideoRetainedEnrollmentV1?
        if let previousFence = request.previousFence {
            guard let previous = operation, previous.phase == .retained else {
                // A delayed request from an older selection cannot drain the
                // current replacement merely by naming its session.
                throw InteractiveNativeVideoCoordinatorFailureV0.invalidPhase
            }
            guard previous.fence == previousFence, samePrimary(previous.context, context),
                  previous.key == sessionPublicKeyX963, let owner, replacementFactory != nil else {
                await close(interactiveSessionID: request.fence.interactiveSessionID.rawValue)
                throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost
            }
            do { retained = try await owner.retainedEnrollment() }
            catch { await close(interactiveSessionID: request.fence.interactiveSessionID.rawValue); throw error }
            guard operation?.token == previous.token, drain == nil else {
                throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost
            }
            predecessorOwner = owner
            self.owner = nil
        } else {
            guard operation == nil, owner == nil else {
                if operation?.phase == .retained {
                    await close(interactiveSessionID: request.fence.interactiveSessionID.rawValue)
                }
                throw InteractiveNativeVideoCoordinatorFailureV0.invalidPhase
            }
            retained = nil
        }
        let token = UUID()
        operation = Operation(token: token, fence: request.fence, context: context, key: sessionPublicKeyX963,
                              challengeID: challengeMessageID, continuityRequested: request.streamContinuity == true, phase: .preparing)
        let factory = self.factory, replacementFactory = self.replacementFactory
        let construction = Task {
            if let retained, let replacementFactory {
                return try await replacementFactory(request.fence, context, sessionPublicKeyX963, retained)
            }
            return try await factory(request.fence, context, sessionPublicKeyX963)
        }
        creation = construction
        var constructed: InteractiveNativeVideoEnrollmentCoordinatorV0?
        do {
            let candidate = try await construction.value
            constructed = candidate
            guard operation?.token == token, drain == nil else { throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost }
            creation = nil
            owner = candidate
            let authority = candidate.authority
            guard matches(authority, context: context, fence: request.fence, key: sessionPublicKeyX963),
                  let clientDER = Data(base64Encoded: request.clientCertificateDERBase64) else {
                throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost
            }
            let material = try await candidate.prepare(clientCertificateDER: clientDER)
            guard operation?.token == token, drain == nil else { throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost }
            await predecessorOwner?.relinquishRetainedEnrollment()
            predecessorOwner = nil
            operation?.phase = .challenged
            return try .init(fence: request.fence, controlGeneration: WireUUID(authority.binding.controlGeneration),
                encodedWidth: UInt16(authority.surface.encodedWidth), encodedHeight: UInt16(authority.surface.encodedHeight),
                hostCertificateDERBase64: material.hostCertificateDER.base64EncodedString(),
                hostChallengeBase64: material.hostChallenge.base64EncodedString(), signingInputBase64: material.signingInput.base64EncodedString(),
                issuedAtUnixMilliseconds: material.issuedAtUnixMilliseconds, expiresAtUnixMilliseconds: material.expiresAtUnixMilliseconds)
        } catch {
            // Compensate this exact candidate even if a later operation exists.
            await constructed?.retire()
            if operation?.token == token { await close(interactiveSessionID: request.fence.interactiveSessionID.rawValue) }
            throw error
        }
    }

    public func activate(_ proof: InteractiveNativeVideoEnrollmentProofBodyV0,
                         context: InteractiveSessionCommandContextV0, sessionPublicKeyX963: Data) async throws -> InteractiveNativeVideoReadyBodyV0 {
        guard let current = operation, let owner, current.phase == .challenged,
              current.fence == proof.fence, samePrimary(current.context, context), drain == nil else {
            throw InteractiveNativeVideoCoordinatorFailureV0.invalidProof
        }
        guard current.challengeID == proof.challengeMessageID, current.key == sessionPublicKeyX963 else {
            await close(interactiveSessionID: proof.fence.interactiveSessionID.rawValue)
            throw InteractiveNativeVideoCoordinatorFailureV0.invalidProof
        }
        operation?.phase = .proving
        do {
            guard let signature = Data(base64Encoded: proof.signatureBase64) else { throw InteractiveNativeVideoCoordinatorFailureV0.invalidProof }
            let endpoint = try await owner.activate(rawSignature: signature)
            guard operation?.token == current.token, drain == nil else { throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost }
            operation?.phase = .active
            var supported = false
            if current.continuityRequested, replacementFactory != nil { supported = await owner.supportsStreamContinuity() }
            guard operation?.token == current.token, drain == nil else { throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost }
            retentionWatchdog?.cancel(); retentionWatchdog = nil; retentionToken = nil
            operation?.continuityAdmitted = supported
            return try .init(fence: proof.fence, challengeMessageID: proof.challengeMessageID,
                portBase: endpoint.portBase, streamContinuity: supported ? true : nil)
        } catch {
            await owner.retire()
            if operation?.token == current.token { await close(interactiveSessionID: proof.fence.interactiveSessionID.rawValue) }
            throw error
        }
    }

    public func retain(_ fence: InteractiveNativeVideoRequestFenceV0,
                       context: InteractiveSessionCommandContextV0) async throws -> Bool {
        if let current = operation, current.phase == .retained,
           current.fence == fence, samePrimary(current.context, context), let owner, drain == nil {
            _ = try await owner.retainedEnrollment()
            guard operation?.token == current.token, operation?.phase == .retained, drain == nil else {
                throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost
            }
            return true // Exact retry does not extend the handoff deadline.
        }
        guard let current = operation, current.fence == fence, samePrimary(current.context, context),
              current.phase == .active, current.rendererGeneration != nil, let owner, drain == nil else {
            throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost
        }
        guard current.continuityAdmitted, replacementFactory != nil, await owner.supportsStreamContinuity() else {
            try await cancel(fence, context: context)
            return false
        }
        guard operation?.token == current.token, drain == nil else {
            throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost
        }
        operation?.phase = .retaining
        do {
            try await owner.retainStream()
            guard operation?.token == current.token, drain == nil else {
                throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost
            }
            operation?.phase = .retained
            let token = UUID()
            retentionToken = token
            retentionWatchdog = Task { [weak self] in
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled, let self else { return }
                await self.expireRetention(token: token, sessionID: fence.interactiveSessionID.rawValue)
            }
            return true
        } catch {
            if operation?.token == current.token { await close(interactiveSessionID: fence.interactiveSessionID.rawValue) }
            throw error
        }
    }

    public func hasRetainedStream(context: InteractiveSessionCommandContextV0) async -> Bool {
        guard let current = operation, current.phase == .retained,
              samePrimary(current.context, context), let owner, drain == nil else { return false }
        do {
            _ = try await owner.retainedEnrollment()
            return operation?.token == current.token && operation?.phase == .retained && drain == nil
        } catch {
            if operation?.token == current.token { await close(interactiveSessionID: current.fence.interactiveSessionID.rawValue) }
            return false
        }
    }

    private func expireRetention(token: UUID, sessionID: UUID) async {
        guard retentionToken == token else { return }
        await close(interactiveSessionID: sessionID)
    }

    public func present(_ request: InteractiveNativeVideoPresentationRequestBodyV0,
                        context: InteractiveSessionCommandContextV0, sessionPublicKeyX963: Data) async throws
        -> InteractiveNativeVideoPresentationReceiptBodyV0 {
        try request.validate()
        guard let current = operation, let owner, current.phase == .active,
              current.fence == request.fence, current.challengeID == request.challengeMessageID,
              current.key == sessionPublicKeyX963, samePrimary(current.context, context), drain == nil,
              current.rendererGeneration == nil || current.rendererGeneration == request.nativeGeneration else {
            throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost
        }
        operation?.phase = .presenting
        do {
            let presentation = try await owner.acknowledgePresentation(encodedWidth: Int(request.encodedWidth),
                encodedHeight: Int(request.encodedHeight), nativeGeneration: request.nativeGeneration,
                presentationID: request.challengeMessageID.rawValue)
            let evidence = presentation.evidence
            guard operation?.token == current.token, operation?.phase == .presenting, drain == nil,
                  let logicalWidth = owner.logicalWidthPoints, let logicalHeight = owner.logicalHeightPoints else {
                throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost
            }
            let receipt = try InteractiveNativeVideoPresentationReceiptBodyV0(fence: request.fence,
                challengeMessageID: request.challengeMessageID, nativeGeneration: request.nativeGeneration,
                encodedWidth: request.encodedWidth, encodedHeight: request.encodedHeight,
                capturePixelWidth: UInt32(evidence.capturePixelWidth), capturePixelHeight: UInt32(evidence.capturePixelHeight),
                logicalWidthPoints: logicalWidth, logicalHeightPoints: logicalHeight, inputAdmitted: presentation.inputAdmitted)
            operation?.rendererGeneration = request.nativeGeneration
            operation?.phase = .active
            return receipt
        } catch {
            await owner.retire()
            if operation?.token == current.token { await close(interactiveSessionID: request.fence.interactiveSessionID.rawValue) }
            throw error
        }
    }

    public func cancel(_ fence: InteractiveNativeVideoRequestFenceV0,
                       context: InteractiveSessionCommandContextV0) async throws {
        if let current = operation, current.fence == fence, samePrimary(current.context, context) {
            await close(interactiveSessionID: fence.interactiveSessionID.rawValue)
            return
        }
        if let cancelled = lastCancelled, cancelled.0 == fence, samePrimary(cancelled.1, context) {
            if drain != nil { await close(interactiveSessionID: fence.interactiveSessionID.rawValue) }
            return
        }
        throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost
    }

    public func close(interactiveSessionID: UUID) async {
        if let drain {
            guard lastCancelled?.0.interactiveSessionID.rawValue == interactiveSessionID else { return }
            let token = drainToken
            await drain.value
            if drainToken == token { clearDrain() }
            return
        }
        guard let closing = operation, closing.fence.interactiveSessionID.rawValue == interactiveSessionID else { return }
        // Fence before waiting for factory work or native cleanup.
        lastCancelled = (closing.fence, closing.context)
        operation = nil
        retentionWatchdog?.cancel(); retentionWatchdog = nil; retentionToken = nil
        let pending = creation, current = owner, predecessor = predecessorOwner
        let task = Task {
            pending?.cancel()
            if let pending, let created = try? await pending.value { await created.retire() }
            await current?.retire()
            await predecessor?.retire()
        }
        drain = task
        drainToken = closing.token
        await task.value
        if drainToken == closing.token { clearDrain() }
    }

    private func clearDrain() { creation = nil; owner = nil; predecessorOwner = nil; drain = nil; drainToken = nil }

    private func samePrimary(_ a: InteractiveSessionCommandContextV0, _ b: InteractiveSessionCommandContextV0) -> Bool {
        a.deviceID == b.deviceID && a.clientID == b.clientID && a.primaryConnectionID == b.primaryConnectionID &&
        a.hostID == b.hostID && a.hostFingerprint == b.hostFingerprint && a.authorizationEpoch == b.authorizationEpoch &&
        a.grantRevision == b.grantRevision && a.policyRevision == b.policyRevision && a.deviceState == b.deviceState && a.hostState == b.hostState
    }
    private func matches(_ a: InteractiveNativeVideoAuthorityV0, context c: InteractiveSessionCommandContextV0,
                         fence f: InteractiveNativeVideoRequestFenceV0, key: Data) -> Bool {
        let b = a.binding, s = a.surface
        return b.hostID == c.hostID && b.hostFingerprint == c.hostFingerprint && b.clientID == c.clientID &&
            b.primaryConnectionID == c.primaryConnectionID && b.interactiveSessionID == f.interactiveSessionID.rawValue &&
            b.authorizationEpoch == c.authorizationEpoch.rawValue && b.grantRevision == c.grantRevision.rawValue &&
            b.policyRevision == c.policyRevision.rawValue && f.authorizationEpoch == c.authorizationEpoch &&
            s.surfaceID == f.surfaceID.rawValue && s.surfaceRevision == f.surfaceRevision &&
            s.coordinateSpaceRevision == f.coordinateSpaceRevision && a.sessionPublicKeyX963 == key
    }
}
