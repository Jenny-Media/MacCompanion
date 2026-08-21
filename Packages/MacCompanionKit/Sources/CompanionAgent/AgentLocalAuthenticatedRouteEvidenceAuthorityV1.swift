import CompanionDomain
import CompanionHostSession
import CompanionWire
import Foundation

package enum AgentLocalAuthenticatedRouteEvidenceErrorV1:
    Error, Equatable, Sendable
{
    case generationExhausted
}

/// The only facet issued to one primary session. Its generation is assigned
/// by the Agent's primary-session owner, so a callback retained by an older
/// session cannot publish or withdraw a replacement session's route evidence.
public struct AgentAuthenticatedRouteObservationPublisherV1:
    AuthenticatedRouteObservationPublishingV1, Sendable
{
    private let authority: AgentLocalAuthenticatedRouteEvidenceAuthorityV1
    private let ownerGeneration: UInt64

    package init(
        authority: AgentLocalAuthenticatedRouteEvidenceAuthorityV1,
        ownerGeneration: UInt64
    ) {
        self.authority = authority
        self.ownerGeneration = ownerGeneration
    }

    public func publish(
        connectionID: Data,
        routeClass: ConfiguredRouteClassV1,
        observedAtMonotonicMilliseconds: UInt64
    ) async {
        await authority.publish(
            ownerGeneration: ownerGeneration,
            connectionID: connectionID,
            routeClass: routeClass,
            observedAtMonotonicMilliseconds:
                observedAtMonotonicMilliseconds
        )
    }

    public func withdraw(connectionID: Data) async {
        await authority.withdraw(
            ownerGeneration: ownerGeneration,
            connectionID: connectionID
        )
    }
}

/// Narrow publisher factory retained by the primary-session owner. It exposes
/// neither the shared route monitor nor local status mutation.
package struct AgentAuthenticatedRouteObservationPublisherFactoryV1:
    Sendable
{
    private let authority: AgentLocalAuthenticatedRouteEvidenceAuthorityV1

    package init(
        authority: AgentLocalAuthenticatedRouteEvidenceAuthorityV1
    ) {
        self.authority = authority
    }

    package func makePublisher() async throws
        -> AgentAuthenticatedRouteObservationPublisherV1
    {
        try await authority.makePublisher()
    }
}

/// Projects authenticated, explicitly configured route observations into the
/// content-free local diagnostic model. Failures are deliberately contained:
/// route diagnostics can degrade, but can never alter authentication state.
package actor AgentLocalAuthenticatedRouteEvidenceAuthorityV1 {
    private let routes: AgentLocalRouteMonitorAuthorityV1
    private let monotonicNowMilliseconds: @Sendable () -> Int64
    private var ownerGeneration: UInt64 = 0
    private var connectionID: Data?
    private var transitionRevision: UInt64 = 0

    package init(
        routes: AgentLocalRouteMonitorAuthorityV1,
        monotonicNowMilliseconds: @escaping @Sendable () -> Int64
    ) {
        self.routes = routes
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
    }

    package func makePublisher() throws
        -> AgentAuthenticatedRouteObservationPublisherV1
    {
        guard ownerGeneration
                < MonotonicRevision<AuthorizationEpochTag>.maximumWireValue
        else {
            throw AgentLocalAuthenticatedRouteEvidenceErrorV1
                .generationExhausted
        }
        ownerGeneration += 1
        connectionID = nil
        transitionRevision = 0
        return AgentAuthenticatedRouteObservationPublisherV1(
            authority: self,
            ownerGeneration: ownerGeneration
        )
    }

    package func publish(
        ownerGeneration: UInt64,
        connectionID: Data,
        routeClass: ConfiguredRouteClassV1,
        observedAtMonotonicMilliseconds: UInt64
    ) async {
        guard ownerGeneration == self.ownerGeneration,
              connectionID.count == 16,
              observedAtMonotonicMilliseconds
                <= UInt64(WireLimits.maximumSafeInteger),
              transitionRevision < UInt64.max else {
            return
        }
        if let current = self.connectionID {
            guard current == connectionID else { return }
        } else {
            self.connectionID = connectionID
        }
        transitionRevision += 1
        do {
            _ = try await routes.publishAuthenticatedRouteAvailability(
                routeClass: routeClass,
                observedAtMonotonicMilliseconds:
                    Int64(observedAtMonotonicMilliseconds)
            )
        } catch {
            // Diagnostics are explicitly non-authorizing and fail isolated.
        }
    }

    package func withdraw(
        ownerGeneration: UInt64,
        connectionID: Data
    ) async {
        guard ownerGeneration == self.ownerGeneration,
              connectionID.count == 16,
              transitionRevision < UInt64.max else {
            return
        }
        if let current = self.connectionID {
            guard current == connectionID else { return }
        }
        transitionRevision += 1
        let revision = transitionRevision
        do {
            _ = try await routes.publishAuthenticatedRouteAvailability(
                routeClass: nil,
                observedAtMonotonicMilliseconds:
                    monotonicNowMilliseconds()
            )
            if ownerGeneration == self.ownerGeneration,
               transitionRevision == revision,
               self.connectionID == connectionID {
                self.connectionID = nil
            }
        } catch {
            // A failed diagnostic withdrawal does not alter session teardown.
        }
    }
}
