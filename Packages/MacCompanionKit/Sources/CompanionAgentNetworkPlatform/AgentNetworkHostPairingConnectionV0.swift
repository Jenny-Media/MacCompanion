import CompanionAgent
import CompanionNetworkPlatform
import CompanionTransport
import CompanionWire
import Foundation

public actor AgentNetworkHostPairingSessionAdapterV0:
    NetworkHostPairingSessionHandlingV0
{
    public let owner: AgentHostPairingWireSessionV0

    public init(owner: AgentHostPairingWireSessionV0) {
        self.owner = owner
    }

    public func receivePairingRequest(
        requestJSON: Data,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64,
        responseMessageID: WireUUID
    ) async throws -> NetworkHostPairingSessionResponseV0 {
        let frame = try await owner.receive(
            requestJSON: requestJSON,
            wallNowUnixMilliseconds: wallNowUnixMilliseconds,
            monotonicNowMilliseconds: monotonicNowMilliseconds,
            responseMessageID: responseMessageID
        )
        let phase = await owner.phase
        let disposition: NetworkHostPairingResponseDispositionV0
        switch phase {
        case .awaitingProve, .awaitingResumeProve:
            disposition = .awaitPeer
        case .awaitingLocalDecision:
            disposition = .awaitLocalDecision
        case .completed, .closed:
            disposition = .terminal
        case .awaitingBegin, .processingBegin, .processingResume,
             .publishingReview,
             .resolvingLocalDecision:
            throw AgentHostPairingWireErrorV0.invalidPhase(phase)
        }
        return NetworkHostPairingSessionResponseV0(
            frame: frame,
            disposition: disposition
        )
    }

    public func takePairingCompletionIfAvailable(
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64,
        responseMessageID: WireUUID
    ) async throws -> Data? {
        try await owner.takeCompletionIfAvailable(
            wallNowUnixMilliseconds: wallNowUnixMilliseconds,
            monotonicNowMilliseconds: monotonicNowMilliseconds,
            responseMessageID: responseMessageID
        )
    }

    public func nextPairingDeadlineMonotonicMilliseconds() async -> UInt64? {
        await owner.nextDeadlineMonotonicMilliseconds()
    }

    public func cancelPairing(at monotonicNowMilliseconds: UInt64) async {
        await owner.cancel(at: monotonicNowMilliseconds)
    }
}

public struct AgentNetworkHostPairingConnectionV0: Sendable {
    public let session: AgentHostPairingWireSessionV0
    public let pump: NetworkHostPairingFramePumpV0

    fileprivate init(
        session: AgentHostPairingWireSessionV0,
        pump: NetworkHostPairingFramePumpV0
    ) {
        self.session = session
        self.pump = pump
    }

    public func begin() async throws {
        try await pump.beginOnClassifiedConnection()
    }

    public func cancel() async {
        await pump.cancel()
    }
}

/// Binds the classified pairing authority to the exact Agent pairing and local
/// decision owners. The socket supplies only its verified TLS binding and
/// listener-owned acceptance time; it cannot inject identity or policy facts.
public struct AgentNetworkHostPairingConnectionFactoryV0: Sendable {
    private let hostID: UUID
    private let authority: any AgentHostPairingAuthorityV0
    private let recovery: any AgentHostPairingRecoveryAuthorityV0
    private let decisions: any AgentHostPairingDecisionHandlingV0
    private let reviewPublisher: any AgentHostPairingReviewPublishingV0
    private let makeReviewID: @Sendable () -> UUID

    package init(
        hostID: UUID,
        authority: any AgentHostPairingAuthorityV0,
        recovery: any AgentHostPairingRecoveryAuthorityV0 =
            UnavailableAgentHostPairingRecoveryAuthorityV0(),
        decisions: any AgentHostPairingDecisionHandlingV0,
        reviewPublisher: any AgentHostPairingReviewPublishingV0,
        makeReviewID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.hostID = hostID
        self.authority = authority
        self.recovery = recovery
        self.decisions = decisions
        self.reviewPublisher = reviewPublisher
        self.makeReviewID = makeReviewID
    }

    /// Release-path construction accepts the sealed pairing graph so the
    /// authority, decision owner, and review publisher cannot be selected
    /// independently.
    public init(
        hostID: UUID,
        pairingServices: AgentPairingServicesV0,
        makeReviewID: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.init(
            hostID: hostID,
            authority: pairingServices.authority,
            recovery: pairingServices.recovery,
            decisions: pairingServices.decisions,
            reviewPublisher: pairingServices.reviews,
            makeReviewID: makeReviewID
        )
    }

    public func bind(
        classifiedConnection: NetworkHostClassifiedConnectionV0,
        acceptedAtMonotonicMilliseconds: UInt64,
        context: @escaping @Sendable () ->
            NetworkHostPairingRequestContextV0,
        terminal: @escaping @Sendable (
            NetworkHostPairingTerminationReasonV0
        ) -> Void = { _ in }
    ) async throws -> AgentNetworkHostPairingConnectionV0 {
        let session = try AgentHostPairingWireSessionV0(
            hostID: hostID,
            tlsBinding: classifiedConnection.tlsBinding,
            acceptedAtMonotonicMilliseconds:
                acceptedAtMonotonicMilliseconds,
            authority: authority,
            recovery: recovery,
            decisions: decisions,
            reviewPublisher: reviewPublisher,
            makeReviewID: makeReviewID
        )
        do {
            let adapter = AgentNetworkHostPairingSessionAdapterV0(
                owner: session
            )
            let pump = try NetworkHostPairingFramePumpV0(
                classifiedConnection: classifiedConnection,
                session: adapter,
                context: context,
                terminal: terminal
            )
            return AgentNetworkHostPairingConnectionV0(
                session: session,
                pump: pump
            )
        } catch {
            classifiedConnection.cancel()
            await session.cancel(
                at: min(
                    acceptedAtMonotonicMilliseconds,
                    UInt64(Int64.max)
                )
            )
            throw error
        }
    }
}
