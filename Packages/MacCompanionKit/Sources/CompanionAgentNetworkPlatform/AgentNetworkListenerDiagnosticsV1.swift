import CompanionAgent
import CompanionIPC

public struct AgentNetworkListenerDiagnosticsV1: Equatable, Sendable {
    public let networkState: LocalAgentNetworkState
    public let activeRemoteSessionCount: UInt16
    public let warningCodes: Set<SanitizedDiagnosticCode>

    public init(
        networkState: LocalAgentNetworkState,
        activeRemoteSessionCount: UInt16,
        warningCodes: Set<SanitizedDiagnosticCode>
    ) {
        self.networkState = networkState
        self.activeRemoteSessionCount = activeRemoteSessionCount
        self.warningCodes = warningCodes
    }
}

public enum AgentNetworkListenerDiagnosticProjectionV1 {
    public static func project(
        _ snapshot: AgentNetworkListenerServiceSnapshotV1
    ) -> AgentNetworkListenerDiagnosticsV1 {
        let networkState: LocalAgentNetworkState
        var warnings: Set<SanitizedDiagnosticCode> = []
        switch snapshot.state {
        case .idle:
            networkState = .stopped
        case .starting:
            networkState = .starting
        case .listening:
            switch snapshot.updateAdmissionState {
            case .open:
                networkState = .listening
            case .unavailable, .closing, .closed, .draining, .drained,
                 .reopening, .terminal:
                networkState = .stopped
            }
        case .terminal:
            if snapshot.lastListenerTerminationReason == .localCancel {
                networkState = .stopped
            } else {
                networkState = .degraded
                warnings.insert(.routeUnavailable)
            }
        }
        if snapshot.hasAcceptedConnectionStartFailure {
            warnings.insert(.routeUnavailable)
        }
        return AgentNetworkListenerDiagnosticsV1(
            networkState: networkState,
            activeRemoteSessionCount:
                snapshot.handoff.hasActivePrimary ? 1 : 0,
            warningCodes: warnings
        )
    }
}

public extension AgentLocalNetworkStatusPublisherV1 {
    func publish(
        _ diagnostics: AgentNetworkListenerDiagnosticsV1
    ) async throws {
        try await publish(
            state: diagnostics.networkState,
            activeRemoteSessionCount:
                diagnostics.activeRemoteSessionCount,
            warningCodes: diagnostics.warningCodes
        )
    }

    package func publish(
        _ diagnostics: AgentNetworkListenerDiagnosticsV1,
        generation: UInt64
    ) async throws {
        try await publish(
            state: diagnostics.networkState,
            activeRemoteSessionCount:
                diagnostics.activeRemoteSessionCount,
            warningCodes: diagnostics.warningCodes,
            generation: generation
        )
    }
}
