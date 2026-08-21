import CompanionDomain
import CompanionIPC
import CompanionLifecycle
import CompanionPersistence
import Foundation

public enum AgentLocalServiceBootstrapErrorV1:
    Error,
    Equatable,
    Sendable
{
    case inventoryBoundsExceeded
}

public enum AgentLocalServiceBootstrapDegradationV1:
    String,
    CaseIterable,
    Comparable,
    Sendable
{
    case auditHistory
    case inventoryStorage
    case securityStorage

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct AgentLocalServiceBootstrapReportV1: Equatable, Sendable {
    public let degradedSources: [AgentLocalServiceBootstrapDegradationV1]

    public init(
        degradedSources: Set<AgentLocalServiceBootstrapDegradationV1>
    ) {
        self.degradedSources = degradedSources.sorted()
    }
}

/// The only network-owned local-status mutation facet. A future listener
/// adapter receives this value rather than the underlying status authority.
public actor AgentLocalNetworkStatusPublisherV1 {
    private let status: AgentLocalStatusAuthorityV1
    private var generation: UInt64 = 0

    package init(status: AgentLocalStatusAuthorityV1) {
        self.status = status
    }

    package func reserveGeneration() throws -> UInt64 {
        guard generation
                < MonotonicRevision<AuthorizationEpochTag>.maximumWireValue
        else {
            throw AgentLocalStatusAuthorityErrorV1.staleNetworkGeneration
        }
        generation += 1
        return generation
    }

    package func publish(
        state: LocalAgentNetworkState,
        activeRemoteSessionCount: UInt16,
        warningCodes: Set<SanitizedDiagnosticCode>
    ) async throws {
        let next = try reserveGeneration()
        try await publish(
            state: state,
            activeRemoteSessionCount: activeRemoteSessionCount,
            warningCodes: warningCodes,
            generation: next
        )
    }

    package func publish(
        state: LocalAgentNetworkState,
        activeRemoteSessionCount: UInt16,
        warningCodes: Set<SanitizedDiagnosticCode>,
        generation: UInt64
    ) async throws {
        guard generation <= self.generation else {
            throw AgentLocalStatusAuthorityErrorV1.staleNetworkGeneration
        }
        try await status.updateNetwork(
            state: state,
            activeRemoteSessionCount: activeRemoteSessionCount,
            warningCodes: warningCodes,
            generation: generation
        )
    }
}

package struct AgentLocalLifecycleStatusPublisherV1: Sendable {
    private let status: AgentLocalStatusAuthorityV1

    package init(status: AgentLocalStatusAuthorityV1) {
        self.status = status
    }

    package func publish(_ lifecycle: ProductLifecycleState) async {
        await status.updateLifecycle(lifecycle)
    }
}

package struct AgentLocalAuditHealthPublisherV1: Sendable {
    private let status: AgentLocalStatusAuthorityV1

    package init(status: AgentLocalStatusAuthorityV1) {
        self.status = status
    }

    package func publish(degraded: Bool) async {
        await status.updateAuditHistoryDegraded(degraded)
    }
}

/// Complete bundle-independent local-service construction returned only after
/// its initial security, audit, and inventory facts have been projected. It
/// never exposes the multi-field mutable status authority.
public struct AgentLocalServiceRootV1: Sendable {
    public let statusReader: AgentLocalStatusReadServiceV1
    public let diagnosticExporter: AgentLocalDiagnosticExportServiceV1
    public let networkStatus: AgentLocalNetworkStatusPublisherV1
    public let lanRoutes: AgentLocalLANRouteEvidenceAuthorityV1
    public let bootstrapReport: AgentLocalServiceBootstrapReportV1

    private let routes: AgentLocalRouteMonitorAuthorityV1
    package let authenticatedRouteObservationPublishers:
        AgentAuthenticatedRouteObservationPublisherFactoryV1
    private let inventory: AgentLocalStatusInventoryRefresherV1
    private let security: AgentLocalStatusSecurityRefresherV1
    package let lifecycleStatus: AgentLocalLifecycleStatusPublisherV1
    package let auditHealth: AgentLocalAuditHealthPublisherV1
    package let diagnosticEvents: AgentSanitizedDiagnosticEventPublisherV1

    package static func bootstrap(
        lifecycle: ProductLifecycleState,
        pairedDevices: any AgentActivePairedDeviceCountReadingV1,
        capabilities: any AgentActiveProviderCountReadingV1,
        denyLatch: EmergencyDenyLatch,
        auditHistoryDegraded: Bool,
        monotonicNowMilliseconds: @escaping @Sendable () -> Int64 = {
            Int64(ProcessInfo.processInfo.systemUptime * 1_000)
        },
        wallClock: any AgentLocalStatusWallClockV1 =
            SystemAgentLocalStatusWallClockV1()
    ) async throws -> AgentLocalServiceRootV1 {
        let status = try AgentLocalStatusAuthorityV1(
            lifecycle: lifecycle,
            networkState: .stopped,
            securityPosture: .storageUnavailable,
            routeKinds: [],
            pairedDeviceCount: 0,
            activeRemoteSessionCount: 0,
            providerCount: 0,
            auditHistoryDegraded: auditHistoryDegraded
        )
        let inventory = AgentLocalStatusInventoryRefresherV1(
            pairedDevices: pairedDevices,
            capabilities: capabilities,
            localStatus: status
        )
        let security = AgentLocalStatusSecurityRefresherV1(
            denyLatch: denyLatch,
            localStatus: status
        )
        var degraded: Set<AgentLocalServiceBootstrapDegradationV1> = []
        if auditHistoryDegraded { degraded.insert(.auditHistory) }
        if await security.refresh() == .storageUnavailable {
            degraded.insert(.securityStorage)
        }
        do {
            try await inventory.refresh()
        } catch AgentLocalStatusSourceRefreshErrorV1.storageUnavailable {
            degraded.insert(.inventoryStorage)
        } catch AgentLocalStatusSourceRefreshErrorV1.boundsExceeded {
            throw AgentLocalServiceBootstrapErrorV1.inventoryBoundsExceeded
        } catch {
            throw AgentLocalServiceBootstrapErrorV1.inventoryBoundsExceeded
        }
        let routes = AgentLocalRouteMonitorAuthorityV1(localStatus: status)
        let authenticatedRoutes =
            AgentLocalAuthenticatedRouteEvidenceAuthorityV1(
                routes: routes,
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
        let statusReader = AgentLocalStatusReadServiceV1(
            status: status,
            wallClock: wallClock
        )
        let diagnosticEvents = AgentSanitizedDiagnosticsAuthorityV1()
        return AgentLocalServiceRootV1(
            statusReader: statusReader,
            diagnosticExporter: AgentLocalDiagnosticExportServiceV1(
                status: statusReader,
                events: diagnosticEvents
            ),
            networkStatus: AgentLocalNetworkStatusPublisherV1(status: status),
            lanRoutes: AgentLocalLANRouteEvidenceAuthorityV1(
                routes: routes,
                monotonicNowMilliseconds: monotonicNowMilliseconds
            ),
            bootstrapReport: AgentLocalServiceBootstrapReportV1(
                degradedSources: degraded
            ),
            routes: routes,
            authenticatedRouteObservationPublishers:
                AgentAuthenticatedRouteObservationPublisherFactoryV1(
                    authority: authenticatedRoutes
                ),
            inventory: inventory,
            security: security,
            lifecycleStatus: AgentLocalLifecycleStatusPublisherV1(
                status: status
            ),
            auditHealth: AgentLocalAuditHealthPublisherV1(status: status),
            diagnosticEvents: AgentSanitizedDiagnosticEventPublisherV1(
                authority: diagnosticEvents
            )
        )
    }

    public func refreshInventory() async throws {
        try await inventory.refresh()
    }

    /// Issues a connection-scoped pairing capability only to the platform
    /// adapter that has already authenticated the visible menu-app endpoint.
    /// Caller identity is deliberately absent from this bundle-independent
    /// boundary and remains a final-identity XPC responsibility.
    public func makePairingReviewService(
        decisions: AgentLocalPairingDecisionHandlerV0,
        alreadyAuthorizedSurface: any LocalPairingReviewSurfaceV0
    ) -> AgentLocalPairingReviewServiceV0 {
        AgentLocalPairingReviewServiceV0(
            decisions: decisions,
            alreadyAuthorizedSurface: alreadyAuthorizedSurface
        )
    }

    @discardableResult
    public func refreshSecurity() async -> LocalSecurityPosture {
        await security.refresh()
    }

    /// Stops transient route/listener facts while retaining local diagnostic
    /// reads and durable inventory/security posture for shutdown presentation.
    public func stopTransientSources(
        observedAtMonotonicMilliseconds: Int64
    ) async throws {
        try await lanRoutes.stop(
            observedAtMonotonicMilliseconds:
                observedAtMonotonicMilliseconds
        )
        try await networkStatus.publish(
            state: .stopped,
            activeRemoteSessionCount: 0,
            warningCodes: []
        )
    }
}
