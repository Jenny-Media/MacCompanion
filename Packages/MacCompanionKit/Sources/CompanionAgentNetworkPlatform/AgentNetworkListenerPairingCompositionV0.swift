import CompanionAgent
import CompanionDiscovery
import CompanionIPC
import CompanionInteractiveHost
import CompanionNetworkPlatform
import Foundation
import Network

public enum AgentNetworkListenerPairingCompositionErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidPort
    case invalidAdditionalEndpoint
}

public struct AgentNetworkListenerPairingCompositionV0: Sendable {
    package let listener: NetworkHostListenerOwnerV0
    package let pairingContext: AgentNetworkPairingContextAuthorityV0

    package init(
        listener: NetworkHostListenerOwnerV0,
        pairingContext: AgentNetworkPairingContextAuthorityV0
    ) {
        self.listener = listener
        self.pairingContext = pairingContext
    }
}

/// Consumes one sealed TLS listener configuration to produce both the exact
/// listener and its initially unavailable pairing-context authority. The
/// canonical Bonjour candidate is derived from that same configuration and
/// every additional private-route candidate must use the same listener port.
public enum AgentNetworkListenerPairingCompositionFactoryV0 {
    package static func make(
        configuration: NetworkHostTLSListenerConfigurationV0,
        port: UInt16,
        additionalEndpoints: [EndpointCandidate] = []
    ) throws -> AgentNetworkListenerPairingCompositionV0 {
        guard port > 0, let networkPort = NWEndpoint.Port(rawValue: port) else {
            throw AgentNetworkListenerPairingCompositionErrorV0.invalidPort
        }
        guard additionalEndpoints.count <= 7,
              additionalEndpoints.allSatisfy({ endpoint in
                  endpoint.kind != .bonjour && endpoint.port == port
              }) else {
            throw AgentNetworkListenerPairingCompositionErrorV0
                .invalidAdditionalEndpoint
        }
        let facts = configuration.bonjourFacts
        let bonjour = try EndpointCandidate(
            kind: .bonjour,
            value: "\(facts.instanceName).\(facts.serviceType).\(facts.domain)",
            port: port
        )
        let context = try AgentLocalPairingContextV0(
            hostFingerprint: configuration.hostFingerprint,
            endpoints: [bonjour] + additionalEndpoints
        )
        let listener = try configuration.makeUnstartedListenerOwner(
            port: networkPort
        )
        return AgentNetworkListenerPairingCompositionV0(
            listener: listener,
            pairingContext: AgentNetworkPairingContextAuthorityV0(
                context: context
            )
        )
    }
}

public enum AgentNetworkPairingProductCompositionErrorV0:
    Error,
    Equatable,
    Sendable
{
    case hostIdentityMismatch
    case listenerServiceAlreadyConstructed
    case terminal
}

public struct AgentNetworkPairingProductCompositionSnapshotV0:
    Equatable,
    Sendable
{
    public let listenerServiceConstructed: Bool
    public let terminal: Bool

    public init(
        listenerServiceConstructed: Bool,
        terminal: Bool
    ) {
        self.listenerServiceConstructed = listenerServiceConstructed
        self.terminal = terminal
    }
}

/// Complete production pairing graph for one listener lifetime and one
/// already-authorized visible menu-app endpoint. Its constituents are package
/// implementation details so an application cannot cross-wire them. The actor
/// also owns one-time listener construction and terminal endpoint-loss
/// teardown, preventing the aggregate from being reused after authorization
/// disappears.
public actor AgentNetworkPairingProductCompositionV0 {
    package nonisolated let listener: NetworkHostListenerOwnerV0
    package nonisolated let pairingContext:
        AgentNetworkPairingContextAuthorityV0
    package nonisolated let pairingServices: AgentPairingServicesV0
    package nonisolated let primaryServices: AgentPrimaryServicesV1
    private var listenerService: AgentNetworkListenerServiceV1?
    private var terminal = false

    package init(
        listener: NetworkHostListenerOwnerV0,
        pairingContext: AgentNetworkPairingContextAuthorityV0,
        pairingServices: AgentPairingServicesV0,
        primaryServices: AgentPrimaryServicesV1
    ) {
        self.listener = listener
        self.pairingContext = pairingContext
        self.pairingServices = pairingServices
        self.primaryServices = primaryServices
    }

    public nonisolated var localPairingSessions:
        AgentLocalPairingSessionHandlerV0
    {
        pairingServices.localPairingSessions
    }

    public nonisolated var localPairingReviews:
        AgentLocalPairingReviewServiceV0
    {
        pairingServices.localPairingReviews
    }

    /// The only public production construction for a role-safe shared
    /// listener. All pairing ingress is bound to this aggregate's listener,
    /// context, durable authority, decision owner, and review publisher.
    public func makeListenerService(
        queue: DispatchQueue,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64,
        primaryContext: @escaping @Sendable () ->
            NetworkHostRequestContextV0,
        pairingRequestContext: @escaping @Sendable () ->
            NetworkHostPairingRequestContextV0,
        interactiveAuthenticator:
            (any HostInteractiveChannelAuthenticatingV0)? = nil,
        interactivePairReady: (@Sendable (
            AgentInteractiveReadyRolePairV0
        ) async throws -> Void)? = nil,
        acceptedTerminal: @escaping @Sendable (
            NetworkHostAcceptedConnectionTerminationReasonV0
        ) -> Void = { _ in },
        primaryTerminal: @escaping @Sendable (
            NetworkHostPrimaryTerminationReasonV0
        ) -> Void = { _ in },
        pairingTerminal: @escaping @Sendable (
            NetworkHostPairingTerminationReasonV0
        ) -> Void = { _ in },
        listenerTerminal: @escaping @Sendable (
            NetworkHostListenerTerminationReasonV0
        ) -> Void = { _ in },
        admissionFailure: @escaping @Sendable (
            AgentNetworkListenerAdmissionFailureV1
        ) -> Void = { _ in },
        makeReviewID: @escaping @Sendable () -> UUID = { UUID() }
    ) throws -> AgentNetworkListenerServiceV1 {
        guard !terminal else {
            throw AgentNetworkPairingProductCompositionErrorV0.terminal
        }
        guard listenerService == nil else {
            throw AgentNetworkPairingProductCompositionErrorV0
                .listenerServiceAlreadyConstructed
        }
        let interactiveBinder: any AgentNetworkInteractiveIngressBindingV2
        let pairReady: (@Sendable (
            AgentInteractiveReadyRolePairV0
        ) async throws -> Void)?
        if let interactiveAuthenticator {
            interactiveBinder = AgentNetworkInteractiveIngressFactoryV2(
                authenticator: interactiveAuthenticator,
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
            pairReady = interactivePairReady ?? { _ in
                throw AgentNetworkInteractiveIngressBindingErrorV2
                    .unavailable
            }
        } else {
            interactiveBinder =
                AgentNetworkRejectingInteractiveIngressBinderV2()
            pairReady = nil
        }
        let service = AgentNetworkListenerServiceV1(
            listener: listener,
            primarySessions: primaryServices.primarySessions,
            pairingConnections: AgentNetworkHostPairingConnectionFactoryV0(
                hostID: primaryServices.hostID,
                pairingServices: pairingServices,
                makeReviewID: makeReviewID
            ),
            interactiveBinder: interactiveBinder,
            interactivePairReady: pairReady,
            networkStatus: primaryServices.localServices.networkStatus,
            lanRoutes: primaryServices.localServices.lanRoutes,
            pairingAvailability: pairingContext,
            pairingSessions: pairingServices.sessions,
            queue: queue,
            monotonicNowMilliseconds: monotonicNowMilliseconds,
            primaryContext: primaryContext,
            pairingRequestContext: pairingRequestContext,
            acceptedTerminal: acceptedTerminal,
            primaryTerminal: primaryTerminal,
            pairingTerminal: pairingTerminal,
            listenerTerminal: listenerTerminal,
            admissionFailure: admissionFailure
        )
        listenerService = service
        return service
    }

    /// Nonterminal loss of the replaceable authenticated menu generation.
    /// Pairing review delivery converges immediately, including cancellation of
    /// any still-pending visible review, while the listener, primary ingress,
    /// QR context, and Observe services remain owned by this product. A later
    /// authenticated menu generation may publish a fresh review through the
    /// stable presentation authority retained by the review service.
    public func authenticatedMenuSurfaceUnavailable() async {
        guard !terminal else { return }
        await pairingServices.reviews.authenticatedMenuSurfaceUnavailable()
    }

    /// Terminal loss of the authenticated visible menu endpoint. Review
    /// delivery is closed first, then the exact listener service retires all
    /// pairing and primary ingress plus its QR context/session authority.
    /// Calling this before listener construction is also terminal and consumes
    /// the unused listener/context; no QR could have been issued while that
    /// context was unavailable.
    public func authorizedSurfaceLost() async {
        guard !terminal else { return }
        terminal = true
        await pairingServices.reviews.invalidate()
        if let listenerService {
            await listenerService.cancel()
        } else {
            listener.cancel()
            await pairingContext.stop()
            _ = try? await pairingServices.sessions.invalidateForNetworkLoss(
                monotonicNowMilliseconds: 0,
                terminal: true
            )
        }
    }

    public func snapshot()
        -> AgentNetworkPairingProductCompositionSnapshotV0
    {
        AgentNetworkPairingProductCompositionSnapshotV0(
            listenerServiceConstructed: listenerService != nil,
            terminal: terminal
        )
    }
}

public enum AgentNetworkPairingProductCompositionFactoryV0 {
    /// Consumes one sealed TLS listener configuration and constructs every
    /// pairing owner from one required-audit composition. The authorized
    /// surface must already have passed final-identity XPC verification.
    public static func make(
        configuration: NetworkHostTLSListenerConfigurationV0,
        port: UInt16,
        additionalEndpoints: [EndpointCandidate] = [],
        primaryServices: AgentPrimaryServicesV1,
        timeSource: any AgentLocalPairingTimeSamplingV0,
        policySource: any AgentLocalPairingPolicyReadingV0,
        alreadyAuthorizedSurface: any LocalPairingReviewSurfaceV0,
        pairingIDGenerator: @escaping @Sendable () -> UUID = { UUID() },
        deviceIDGenerator: @escaping @Sendable () -> UUID = { UUID() }
    ) throws -> AgentNetworkPairingProductCompositionV0 {
        guard configuration.hostFingerprint
                == primaryServices.hostIdentity.hostFingerprint,
              configuration.certificateDER
                == primaryServices.hostIdentity.certificateDER else {
            throw AgentNetworkPairingProductCompositionErrorV0
                .hostIdentityMismatch
        }
        let listenerComposition = try
            AgentNetworkListenerPairingCompositionFactoryV0.make(
                configuration: configuration,
                port: port,
                additionalEndpoints: additionalEndpoints
            )
        let pairingServices = primaryServices.makePairingServices(
            contextSource: listenerComposition.pairingContext,
            timeSource: timeSource,
            policySource: policySource,
            alreadyAuthorizedSurface: alreadyAuthorizedSurface,
            pairingIDGenerator: pairingIDGenerator,
            deviceIDGenerator: deviceIDGenerator
        )
        return AgentNetworkPairingProductCompositionV0(
            listener: listenerComposition.listener,
            pairingContext: listenerComposition.pairingContext,
            pairingServices: pairingServices,
            primaryServices: primaryServices
        )
    }
}
