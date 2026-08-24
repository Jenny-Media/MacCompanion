import CompanionClient
import CompanionDiscovery
import CompanionPresentation
import CompanionTransport
import CompanionWire
import Dispatch
import Foundation

public enum ClientPairingApplicationOwnerErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidConfiguration
    case invalidPhase
    case invalidClock
    case invalidRandomness
    case identifierReuse
    case revisionExhausted
}

public struct ClientPairingTimeSampleV0: Equatable, Sendable {
    public let wallUnixMilliseconds: Int64
    public let monotonicMilliseconds: UInt64

    public init(
        wallUnixMilliseconds: Int64,
        monotonicMilliseconds: UInt64
    ) throws {
        guard wallUnixMilliseconds >= 0,
              monotonicMilliseconds <= UInt64(Int64.max) else {
            throw ClientPairingApplicationOwnerErrorV0.invalidClock
        }
        self.wallUnixMilliseconds = wallUnixMilliseconds
        self.monotonicMilliseconds = monotonicMilliseconds
    }
}

public protocol ClientPairingClockV0: Sendable {
    func sample() throws -> ClientPairingTimeSampleV0
}

public struct SystemClientPairingClockV0: ClientPairingClockV0 {
    public init() {}

    public func sample() throws -> ClientPairingTimeSampleV0 {
        let wall = Int64(Date().timeIntervalSince1970 * 1_000)
        let uptime = DispatchTime.now().uptimeNanoseconds / 1_000_000
        return try ClientPairingTimeSampleV0(
            wallUnixMilliseconds: wall,
            monotonicMilliseconds: uptime
        )
    }
}

public protocol ClientPairingRandomnessV0: Sendable {
    func randomBytes(count: Int) throws -> Data
    func randomUUID() -> UUID
}

public struct SystemClientPairingRandomnessV0: ClientPairingRandomnessV0 {
    public init() {}

    public func randomBytes(count: Int) throws -> Data {
        guard count > 0, count <= 64 else {
            throw ClientPairingApplicationOwnerErrorV0.invalidRandomness
        }
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max) })
    }

    public func randomUUID() -> UUID { UUID() }
}

public struct ClientPairingConnectionRequestV0: Equatable, Sendable {
    public let pairingID: UUID
    public let requiredHostFingerprint: Data
    public let endpoints: [EndpointCandidate]
    public let expiresAtUnixMilliseconds: Int64

    public init(
        pairingID: UUID,
        requiredHostFingerprint: Data,
        endpoints: [EndpointCandidate],
        expiresAtUnixMilliseconds: Int64
    ) throws {
        guard requiredHostFingerprint.count == 32,
              (1...8).contains(endpoints.count),
              Set(endpoints).count == endpoints.count,
              expiresAtUnixMilliseconds > 0 else {
            throw ClientPairingApplicationOwnerErrorV0.invalidConfiguration
        }
        self.pairingID = pairingID
        self.requiredHostFingerprint = requiredHostFingerprint
        self.endpoints = endpoints
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
    }
}

/// One exact connection attempt. The platform adapter must keep TCP, TLS peer
/// evidence, framed sends, receives, cancellation, and the request's immutable
/// pin on this same object; it may not replace the connection after returning.
public protocol ClientPairingConnectionV0: Sendable {
    func connectTCP() async throws
    func acceptPinnedTLS() async throws -> TLSPeerEvidence
    func send(
        _ frame: Data,
        deadlineMonotonicMilliseconds: UInt64
    ) async throws
    func receive(
        deadlineMonotonicMilliseconds: UInt64
    ) async throws -> Data
    func close() async
}

public protocol ClientPairingConnectionCreatingV0: Sendable {
    func makeConnection(
        _ request: ClientPairingConnectionRequestV0
    ) async throws -> any ClientPairingConnectionV0
}

private struct ClientPairingApplicationFlowFailureV0: Error {
    let presentation: PairingClientPresentationFailure
}

/// Application-global, bundle-independent owner for one accepted QR attempt.
/// It composes already-frozen security, presentation, custody, persistence, and
/// exact-connection seams. Views receive only snapshots and never retain the
/// QR secret, transport, private-key reference, or partially published host.
public actor ClientPairingApplicationOwnerV0 {
    public typealias StateChanged =
        @Sendable (PairingClientPresentation) async -> Void

    private struct AttemptResources: Sendable {
        let session: ClientPairingSessionV0?
        let recoverySession: ClientPairingRecoverySessionV0?
        let connection: (any ClientPairingConnectionV0)?
        let publication: ClientIdentityPublicationAuthorityV0?
    }

    private let clientID: UUID
    private let custody: any ClientIdentityKeyCustodyV0
    private let persistence: any ClientPairedHostPersistenceV0
    private let connections: any ClientPairingConnectionCreatingV0
    private let clock: any ClientPairingClockV0
    private let randomness: any ClientPairingRandomnessV0
    private let stateChanged: StateChanged

    private var presentation = PairingClientPresentation()
    private var revision: UInt64 = 0
    private var activeRevision: UInt64?
    private var issuedIdentifiers: Set<UUID> = []
    private var publicationCommitRevision: UInt64?
    private var session: ClientPairingSessionV0?
    private var recoverySession: ClientPairingRecoverySessionV0?
    private var connection: (any ClientPairingConnectionV0)?
    private var publication: ClientIdentityPublicationAuthorityV0?

    package init(
        clientID: UUID,
        custody: any ClientIdentityKeyCustodyV0,
        persistence: any ClientPairedHostPersistenceV0,
        connections: any ClientPairingConnectionCreatingV0,
        clock: any ClientPairingClockV0 = SystemClientPairingClockV0(),
        randomness: any ClientPairingRandomnessV0 =
            SystemClientPairingRandomnessV0(),
        stateChanged: @escaping StateChanged = { _ in }
    ) throws {
        guard clientID != UUID(
            uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        ) else {
            throw ClientPairingApplicationOwnerErrorV0.invalidConfiguration
        }
        self.clientID = clientID
        self.custody = custody
        self.persistence = persistence
        self.connections = connections
        self.clock = clock
        self.randomness = randomness
        self.stateChanged = stateChanged
    }

    public func snapshot() -> PairingClientPresentation { presentation }

    public func receiveScan(_ text: String) async throws {
        guard activeRevision == nil else {
            throw ClientPairingApplicationOwnerErrorV0.invalidPhase
        }
        let sample = try clock.sample()
        do {
            try presentation.receiveScan(
                text,
                nowUnixMilliseconds: sample.wallUnixMilliseconds
            )
        } catch PairingClientPresentationError.invalidOrExpiredQRCode {
            await publish()
            throw PairingClientPresentationError.invalidOrExpiredQRCode
        } catch {
            throw ClientPairingApplicationOwnerErrorV0.invalidPhase
        }
        await publish()
    }

    /// Runs the accepted attempt through durable publication. Long waits for
    /// local Mac approval are intentionally cancellable through `cancel()`.
    /// Expected network/security/storage failures are reflected in the closed
    /// presentation failure enum rather than escaping provider error text.
    public func acceptPreview() async throws {
        guard activeRevision == nil,
              presentation.phase == .preview else {
            throw ClientPairingApplicationOwnerErrorV0.invalidPhase
        }
        let requestID = try issueIdentifier()
        let attemptRevision = try activateAttempt()
        let intent: PairingStartIntent
        do {
            intent = try presentation.acceptPreview(requestID: requestID)
        } catch {
            activeRevision = nil
            throw ClientPairingApplicationOwnerErrorV0.invalidPhase
        }
        await publish()
        guard isCurrent(attemptRevision) else { return }

        do {
            try await run(
                intent: intent,
                requestID: requestID,
                attemptRevision: attemptRevision
            )
        } catch let failure as ClientPairingApplicationFlowFailureV0 {
            await failCurrent(
                expectedRevision: attemptRevision,
                reason: failure.presentation
            )
        } catch {
            await failCurrent(
                expectedRevision: attemptRevision,
                reason: .unknown
            )
        }
    }

    public func cancel() async {
        // Once the atomic record commit starts, cancellation cannot safely
        // distinguish pre-commit from post-commit. Let publication converge;
        // the saving UI exposes no cancel action, and restart reconciliation
        // handles process death during this same window.
        guard publicationCommitRevision == nil else { return }
        let resources = invalidateAttempt(resetPresentation: true)
        await publish()
        await cleanUp(resources)
    }

    private func run(
        intent: PairingStartIntent,
        requestID: UUID,
        attemptRevision: UInt64
    ) async throws {
        let pairingID = intent.qr.pairingID.rawValue
        let authority = ClientIdentityPublicationAuthorityV0(
            custody: custody,
            persistence: persistence
        )
        publication = authority
        let identity: ClientPreparedIdentityV0
        do {
            identity = try await authority.prepare(
                pairingID: pairingID,
                clientID: clientID
            )
        } catch {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .clientStorageUnavailable
            )
        }
        guard isCurrent(attemptRevision) else {
            try? await authority.discard()
            return
        }

        let signer: ClientCustodiedSessionSignerV0
        let pairingSession: ClientPairingSessionV0
        do {
            signer = try ClientCustodiedSessionSignerV0(
                custody: custody,
                sessionKey: identity.sessionKey
            )
            pairingSession = try ClientPairingSessionV0(
                qr: intent.qr,
                clientID: clientID,
                sessionPublicKeyX963: identity.sessionKey.publicKeyX963,
                approvalPublicKeyX963: identity.approvalKey.publicKeyX963,
                signer: signer
            )
        } catch {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .identityVerificationFailed
            )
        }
        session = pairingSession

        let request = try ClientPairingConnectionRequestV0(
            pairingID: pairingID,
            requiredHostFingerprint: intent.qr.hostFingerprint.rawValue,
            endpoints: intent.qr.endpoints,
            expiresAtUnixMilliseconds: intent.qr.expiresAtUnixMilliseconds
        )
        let exactConnection: any ClientPairingConnectionV0
        do {
            exactConnection = try await connections.makeConnection(request)
        } catch {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .connectionFailed
            )
        }
        guard isCurrent(attemptRevision) else {
            await exactConnection.close()
            return
        }
        connection = exactConnection

        do {
            try presentation.transportStarted(
                requestID: requestID,
                pairingID: pairingID
            )
        } catch {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .unknown
            )
        }
        await publish()
        guard isCurrent(attemptRevision) else { return }

        do {
            try await exactConnection.connectTCP()
        } catch {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .connectionFailed
            )
        }
        try await performPairing {
            let time = try self.clock.sample()
            try await pairingSession.didConnectTCP(
                wallNowUnixMilliseconds: time.wallUnixMilliseconds,
                monotonicNowMilliseconds: time.monotonicMilliseconds
            )
        }
        guard isCurrent(attemptRevision) else { return }

        let evidence: TLSPeerEvidence
        do {
            evidence = try await exactConnection.acceptPinnedTLS()
        } catch {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .connectionFailed
            )
        }
        try await performPairing {
            let time = try self.clock.sample()
            try await pairingSession.acceptPinnedPeer(
                evidence,
                at: time.monotonicMilliseconds
            )
        }
        guard isCurrent(attemptRevision) else { return }
        do {
            try presentation.pinnedTLSAccepted(
                requestID: requestID,
                pairingID: pairingID
            )
        } catch {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .unknown
            )
        }
        await publish()
        guard isCurrent(attemptRevision) else { return }

        let nonce = try randomBytes32()
        let beginID = try issueIdentifier()
        let begin = try await performPairing {
            let time = try self.clock.sample()
            return try await pairingSession.begin(
                clientNonce: WireBytes32(nonce),
                messageID: WireUUID(beginID),
                sentAtUnixMilliseconds: time.wallUnixMilliseconds,
                monotonicNowMilliseconds: time.monotonicMilliseconds
            )
        }
        try await send(begin, on: exactConnection, session: pairingSession)
        let challenge = try await receive(
            on: exactConnection,
            session: pairingSession
        )
        guard isCurrent(attemptRevision) else { return }

        do {
            try presentation.transcriptVerificationStarted(
                requestID: requestID,
                pairingID: pairingID
            )
        } catch {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .unknown
            )
        }
        await publish()
        guard isCurrent(attemptRevision) else { return }

        let proofID = try issueIdentifier()
        let proof = try await performPairing {
            let time = try self.clock.sample()
            return try await pairingSession.receiveChallenge(
                challenge,
                proofMessageID: WireUUID(proofID),
                sentAtUnixMilliseconds: time.wallUnixMilliseconds,
                monotonicNowMilliseconds: time.monotonicMilliseconds
            )
        }
        guard isCurrent(attemptRevision) else { return }
        try await send(proof, on: exactConnection, session: pairingSession)
        let pending = try await receive(
            on: exactConnection,
            session: pairingSession
        )
        guard isCurrent(attemptRevision) else { return }

        let approval = try await performPairing {
            let time = try self.clock.sample()
            return try await pairingSession.receivePendingApproval(
                pending,
                wallNowUnixMilliseconds: time.wallUnixMilliseconds,
                monotonicNowMilliseconds: time.monotonicMilliseconds
            )
        }
        do {
            try presentation.receiveVerifiedApproval(
                requestID: requestID,
                approval: approval
            )
        } catch {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .identityVerificationFailed
            )
        }
        await publish()
        guard isCurrent(attemptRevision) else { return }

        let host: ClientPairedHostV0
        do {
            let completion = try await receive(
                on: exactConnection,
                session: pairingSession
            )
            guard isCurrent(attemptRevision) else { return }
            host = try await performPairing {
                let time = try self.clock.sample()
                return try await pairingSession.receiveCompletion(
                    completion,
                    monotonicNowMilliseconds: time.monotonicMilliseconds
                )
            }
        } catch let failure as ClientPairingApplicationFlowFailureV0
            where failure.presentation == .connectionFailed
        {
            await exactConnection.close()
            guard isCurrent(attemptRevision) else { return }
            do {
                try presentation.completionRecoveryStarted(
                    requestID: requestID,
                    pairingID: pairingID
                )
            } catch {
                throw ClientPairingApplicationFlowFailureV0(
                    presentation: .unknown
                )
            }
            await publish()
            guard isCurrent(attemptRevision) else { return }
            host = try await recoverCompletion(
                identity: identity,
                signer: signer,
                request: request,
                attemptRevision: attemptRevision
            )
        }
        let commitID = try issueIdentifier()
        do {
            _ = try presentation.receiveVerifiedCompletion(
                requestID: requestID,
                host: host,
                commitID: commitID
            )
        } catch {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .identityVerificationFailed
            )
        }
        await publish()
        guard isCurrent(attemptRevision) else { return }

        connection = nil
        await exactConnection.close()
        guard isCurrent(attemptRevision) else { return }
        publicationCommitRevision = attemptRevision
        do {
            _ = try await authority.publish(host)
        } catch {
            if publicationCommitRevision == attemptRevision {
                publicationCommitRevision = nil
            }
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .clientStorageUnavailable
            )
        }
        guard isCurrent(attemptRevision) else { return }
        publicationCommitRevision = nil
        do {
            try presentation.durableCommitSucceeded(
                commitID: commitID,
                storedHost: host
            )
        } catch {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .clientStorageUnavailable
            )
        }
        session = nil
        recoverySession = nil
        publication = nil
        publicationCommitRevision = nil
        activeRevision = nil
        await publish()
    }

    private func send(
        _ frame: Data,
        on connection: any ClientPairingConnectionV0,
        session: ClientPairingSessionV0
    ) async throws {
        guard let deadline = await session
            .nextDeadlineMonotonicMilliseconds() else {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .unknown
            )
        }
        do {
            try await connection.send(
                frame,
                deadlineMonotonicMilliseconds: deadline
            )
        } catch {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .connectionFailed
            )
        }
    }

    private func receive(
        on connection: any ClientPairingConnectionV0,
        session: ClientPairingSessionV0
    ) async throws -> Data {
        guard let deadline = await session
            .nextDeadlineMonotonicMilliseconds() else {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .unknown
            )
        }
        do {
            return try await connection.receive(
                deadlineMonotonicMilliseconds: deadline
            )
        } catch {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .connectionFailed
            )
        }
    }

    private func recoverCompletion(
        identity: ClientPreparedIdentityV0,
        signer: ClientCustodiedSessionSignerV0,
        request: ClientPairingConnectionRequestV0,
        attemptRevision: UInt64
    ) async throws -> ClientPairedHostV0 {
        let recovery: ClientPairingRecoverySessionV0
        do {
            recovery = try ClientPairingRecoverySessionV0(
                identity: identity,
                hostFingerprint: request.requiredHostFingerprint,
                endpoints: request.endpoints,
                signer: signer
            )
        } catch {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .identityVerificationFailed
            )
        }
        recoverySession = recovery

        let replacement: any ClientPairingConnectionV0
        do {
            replacement = try await connections.makeConnection(request)
        } catch {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .connectionFailed
            )
        }
        guard isCurrent(attemptRevision) else {
            await replacement.close()
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .connectionFailed
            )
        }
        connection = replacement

        do {
            try await replacement.connectTCP()
            let connected = try clock.sample()
            try await recovery.didConnectTCP(
                monotonicNowMilliseconds: connected.monotonicMilliseconds
            )
            let evidence = try await replacement.acceptPinnedTLS()
            let pinned = try clock.sample()
            try await recovery.acceptPinnedPeer(
                evidence,
                at: pinned.monotonicMilliseconds
            )
            let resumeTime = try clock.sample()
            let resume = try await recovery.resume(
                clientNonce: WireBytes32(try randomBytes32()),
                messageID: WireUUID(try issueIdentifier()),
                sentAtUnixMilliseconds: resumeTime.wallUnixMilliseconds,
                monotonicNowMilliseconds: resumeTime.monotonicMilliseconds
            )
            try await sendRecovery(resume, on: replacement, session: recovery)
            let challenge = try await receiveRecovery(
                on: replacement,
                session: recovery
            )
            let proveTime = try clock.sample()
            let proof = try await recovery.receiveChallenge(
                challenge,
                proofMessageID: WireUUID(try issueIdentifier()),
                sentAtUnixMilliseconds: proveTime.wallUnixMilliseconds,
                monotonicNowMilliseconds: proveTime.monotonicMilliseconds
            )
            try await sendRecovery(proof, on: replacement, session: recovery)
            let completion = try await receiveRecovery(
                on: replacement,
                session: recovery
            )
            let completionTime = try clock.sample()
            let host = try await recovery.receiveCompletion(
                completion,
                monotonicNowMilliseconds:
                    completionTime.monotonicMilliseconds
            )
            await replacement.close()
            if isCurrent(attemptRevision) {
                connection = nil
            }
            return host
        } catch let error as ClientPairingRecoveryErrorV0 {
            let presentation: PairingClientPresentationFailure = switch error {
            case .remoteError:
                .hostRejected
            case .hostFingerprintMismatch, .invalidSignatureLength,
                 .invalidCorrelation, .duplicateMessage,
                 .unexpectedMessage, .invalidConfiguration:
                .identityVerificationFailed
            case .invalidClock, .invalidPhase:
                .unknown
            }
            throw ClientPairingApplicationFlowFailureV0(
                presentation: presentation
            )
        } catch let failure as ClientPairingApplicationFlowFailureV0 {
            throw failure
        } catch {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .connectionFailed
            )
        }
    }

    private func sendRecovery(
        _ frame: Data,
        on connection: any ClientPairingConnectionV0,
        session: ClientPairingRecoverySessionV0
    ) async throws {
        guard let deadline = await session.nextDeadlineMonotonicMilliseconds() else {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .unknown
            )
        }
        do {
            try await connection.send(
                frame,
                deadlineMonotonicMilliseconds: deadline
            )
        } catch {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .connectionFailed
            )
        }
    }

    private func receiveRecovery(
        on connection: any ClientPairingConnectionV0,
        session: ClientPairingRecoverySessionV0
    ) async throws -> Data {
        guard let deadline = await session.nextDeadlineMonotonicMilliseconds() else {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .unknown
            )
        }
        do {
            return try await connection.receive(
                deadlineMonotonicMilliseconds: deadline
            )
        } catch {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .connectionFailed
            )
        }
    }

    private func performPairing<T: Sendable>(
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch let error as ClientPairingSessionErrorV0 {
            let failure: PairingClientPresentationFailure = switch error {
            case .expired:
                .invalidOrExpiredCode
            case .remoteError:
                .hostRejected
            case .hostFingerprintMismatch, .transcriptMismatch,
                 .authenticationStringMismatch, .expiryMismatch,
                 .invalidSignatureLength, .invalidCorrelation,
                 .duplicateMessage, .unexpectedMessage,
                 .invalidConfiguration:
                .identityVerificationFailed
            case .invalidClock, .invalidPhase:
                .unknown
            }
            throw ClientPairingApplicationFlowFailureV0(
                presentation: failure
            )
        } catch is ClientPairingApplicationOwnerErrorV0 {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .unknown
            )
        } catch {
            throw ClientPairingApplicationFlowFailureV0(
                presentation: .identityVerificationFailed
            )
        }
    }

    private func failCurrent(
        expectedRevision: UInt64,
        reason: PairingClientPresentationFailure
    ) async {
        guard isCurrent(expectedRevision) else { return }
        let resources = detachAttempt()
        invalidateRevision()
        do {
            try presentation.fail(reason)
        } catch {
            presentation.reset()
        }
        await publish()
        await cleanUp(resources)
    }

    private func invalidateAttempt(
        resetPresentation: Bool
    ) -> AttemptResources {
        let resources = detachAttempt()
        invalidateRevision()
        if resetPresentation { presentation.reset() }
        return resources
    }

    private func detachAttempt() -> AttemptResources {
        let resources = AttemptResources(
            session: session,
            recoverySession: recoverySession,
            connection: connection,
            publication: publication
        )
        session = nil
        recoverySession = nil
        connection = nil
        publication = nil
        activeRevision = nil
        return resources
    }

    private func cleanUp(_ resources: AttemptResources) async {
        await resources.session?.close()
        await resources.recoverySession?.cancel()
        await resources.connection?.close()
        if let publication = resources.publication,
           await publication.phase == .ready {
            try? await publication.discard()
        }
    }

    private func randomBytes32() throws -> Data {
        let value = try randomness.randomBytes(count: 32)
        guard value.count == 32 else {
            throw ClientPairingApplicationOwnerErrorV0.invalidRandomness
        }
        return value
    }

    private func issueIdentifier() throws -> UUID {
        let value = randomness.randomUUID()
        guard value != UUID(
            uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        ) else {
            throw ClientPairingApplicationOwnerErrorV0.invalidRandomness
        }
        guard issuedIdentifiers.insert(value).inserted else {
            throw ClientPairingApplicationOwnerErrorV0.identifierReuse
        }
        return value
    }

    private func activateAttempt() throws -> UInt64 {
        guard revision < UInt64.max else {
            throw ClientPairingApplicationOwnerErrorV0.revisionExhausted
        }
        revision += 1
        activeRevision = revision
        return revision
    }

    private func invalidateRevision() {
        if revision < UInt64.max { revision += 1 }
        activeRevision = nil
    }

    private func isCurrent(_ value: UInt64) -> Bool {
        activeRevision == value && revision == value
    }

    private func publish() async {
        await stateChanged(presentation)
    }
}
