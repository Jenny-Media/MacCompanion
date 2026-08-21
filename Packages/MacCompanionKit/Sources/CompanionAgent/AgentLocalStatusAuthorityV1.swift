import CompanionDomain
import CompanionIPC
import CompanionLifecycle
import CompanionWire
import Foundation

public enum AgentLocalStatusAuthorityErrorV1:
    Error,
    Equatable,
    Sendable
{
    case invalidCount
    case invalidNetworkWarning
    case invalidTime
    case sequenceExhausted
    case staleNetworkGeneration
    case staleRouteGeneration
}

/// One actor-owned, content-free local status version. Product adapters publish
/// only closed facts after their source transition completes; readers never
/// assemble a payload by racing mutable authorities independently.
public actor AgentLocalStatusAuthorityV1 {
    public static let maximumPairedDeviceCount: UInt16 = 1
    public static let maximumActiveRemoteSessionCount: UInt16 = 1
    public static let maximumProviderCount: UInt16 = 128

    private static let allowedNetworkWarnings: Set<SanitizedDiagnosticCode> = [
        .localNetworkDenied,
        .routeUnavailable,
    ]

    private var lifecycle: ProductLifecycleState
    private var networkState: LocalAgentNetworkState
    private var networkWarnings: Set<SanitizedDiagnosticCode>
    private var networkGeneration: UInt64 = 0
    private var securityPosture: LocalSecurityPosture
    private var routeKinds: Set<LocalRouteKind>
    private var routeUnavailable: Bool
    private var routeGeneration: UInt64 = 0
    private var pairedDeviceCount: UInt16
    private var activeRemoteSessionCount: UInt16
    private var providerCount: UInt16
    private var auditHistoryDegraded: Bool
    private var diagnosticSequence: UInt64 = 0

    package init(
        lifecycle: ProductLifecycleState,
        networkState: LocalAgentNetworkState,
        networkWarnings: Set<SanitizedDiagnosticCode> = [],
        securityPosture: LocalSecurityPosture,
        routeKinds: Set<LocalRouteKind>,
        routeUnavailable: Bool = false,
        pairedDeviceCount: UInt16,
        activeRemoteSessionCount: UInt16,
        providerCount: UInt16,
        auditHistoryDegraded: Bool = false
    ) throws {
        try Self.validateCounts(
            pairedDeviceCount: pairedDeviceCount,
            activeRemoteSessionCount: activeRemoteSessionCount,
            providerCount: providerCount
        )
        try Self.validateNetworkWarnings(networkWarnings)
        self.lifecycle = lifecycle
        self.networkState = networkState
        self.networkWarnings = networkWarnings
        self.securityPosture = securityPosture
        self.routeKinds = routeKinds
        self.routeUnavailable = routeUnavailable
        self.pairedDeviceCount = pairedDeviceCount
        self.activeRemoteSessionCount = activeRemoteSessionCount
        self.providerCount = providerCount
        self.auditHistoryDegraded = auditHistoryDegraded
    }

    package func updateLifecycle(_ lifecycle: ProductLifecycleState) {
        self.lifecycle = lifecycle
    }

    package func updateNetwork(
        state: LocalAgentNetworkState,
        activeRemoteSessionCount: UInt16,
        warningCodes: Set<SanitizedDiagnosticCode>,
        generation: UInt64
    ) throws {
        guard generation > networkGeneration,
              generation
                <= MonotonicRevision<AuthorizationEpochTag>.maximumWireValue
        else {
            throw AgentLocalStatusAuthorityErrorV1.staleNetworkGeneration
        }
        guard activeRemoteSessionCount
                <= Self.maximumActiveRemoteSessionCount else {
            throw AgentLocalStatusAuthorityErrorV1.invalidCount
        }
        try Self.validateNetworkWarnings(warningCodes)
        networkState = state
        self.activeRemoteSessionCount = activeRemoteSessionCount
        networkWarnings = warningCodes
        networkGeneration = generation
    }

    package func updateSecurityPosture(_ posture: LocalSecurityPosture) {
        securityPosture = posture
    }

    package func updateRoutes(
        routeKinds: Set<LocalRouteKind>,
        routeUnavailable: Bool,
        generation: UInt64
    ) throws {
        guard generation > routeGeneration,
              generation
                <= MonotonicRevision<AuthorizationEpochTag>.maximumWireValue
        else {
            throw AgentLocalStatusAuthorityErrorV1.staleRouteGeneration
        }
        self.routeKinds = routeKinds
        self.routeUnavailable = routeUnavailable
        routeGeneration = generation
    }

    package func updateInventory(
        pairedDeviceCount: UInt16,
        providerCount: UInt16
    ) throws {
        try Self.validateCounts(
            pairedDeviceCount: pairedDeviceCount,
            activeRemoteSessionCount: activeRemoteSessionCount,
            providerCount: providerCount
        )
        self.pairedDeviceCount = pairedDeviceCount
        self.providerCount = providerCount
    }

    package func updateAuditHistoryDegraded(_ degraded: Bool) {
        auditHistoryDegraded = degraded
    }

    package func snapshot(
        generatedAtUnixMilliseconds: Int64
    ) throws -> LocalAgentStatusSnapshot {
        guard generatedAtUnixMilliseconds >= 0,
              generatedAtUnixMilliseconds <= WireLimits.maximumSafeInteger
        else {
            throw AgentLocalStatusAuthorityErrorV1.invalidTime
        }
        guard diagnosticSequence
                < MonotonicRevision<AuthorizationEpochTag>.maximumWireValue
        else {
            throw AgentLocalStatusAuthorityErrorV1.sequenceExhausted
        }
        let nextSequence = diagnosticSequence + 1
        let value = try LocalAgentStatusSnapshot(
            desiredEnabled: lifecycle.desiredEnabled,
            consoleSession: lifecycle.consoleSession,
            agentProcess: lifecycle.agent,
            menuAppProcess: lifecycle.menuApp,
            networkState: networkState,
            securityPosture: securityPosture,
            routeKinds: routeKinds,
            pairedDeviceCount: pairedDeviceCount,
            activeRemoteSessionCount: activeRemoteSessionCount,
            providerCount: providerCount,
            warningCodes: derivedWarnings(),
            diagnosticSequence: nextSequence,
            generatedAtUnixMilliseconds: generatedAtUnixMilliseconds
        )
        diagnosticSequence = nextSequence
        return value
    }

    private func derivedWarnings() -> Set<SanitizedDiagnosticCode> {
        var warnings = networkWarnings
        if lifecycle.desiredEnabled, lifecycle.agent != .ready {
            warnings.insert(.agentUnavailable)
        }
        if lifecycle.desiredEnabled, lifecycle.menuApp != .ready {
            warnings.insert(.menuAppUnavailable)
        }
        switch securityPosture {
        case .nominal:
            break
        case .denyLatched:
            warnings.insert(.denyLatchArmed)
        case .storageUnavailable:
            warnings.insert(.storageUnavailable)
        }
        if auditHistoryDegraded {
            warnings.insert(.auditHistoryDegraded)
        }
        if routeUnavailable {
            warnings.insert(.routeUnavailable)
        }
        return warnings
    }

    private static func validateCounts(
        pairedDeviceCount: UInt16,
        activeRemoteSessionCount: UInt16,
        providerCount: UInt16
    ) throws {
        guard pairedDeviceCount <= maximumPairedDeviceCount,
              activeRemoteSessionCount <= maximumActiveRemoteSessionCount,
              providerCount <= maximumProviderCount else {
            throw AgentLocalStatusAuthorityErrorV1.invalidCount
        }
    }

    private static func validateNetworkWarnings(
        _ warnings: Set<SanitizedDiagnosticCode>
    ) throws {
        guard warnings.isSubset(of: allowedNetworkWarnings) else {
            throw AgentLocalStatusAuthorityErrorV1.invalidNetworkWarning
        }
    }
}
