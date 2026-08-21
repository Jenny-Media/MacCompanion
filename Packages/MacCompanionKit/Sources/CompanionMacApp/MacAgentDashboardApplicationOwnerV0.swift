import CompanionIPC
import Foundation

public enum MacAgentDashboardSourceV0: Equatable, Sendable {
    case loading
    case status(LocalAgentStatusSnapshot)
    case unavailable
}

public struct MacAgentDashboardConnectionTokenV0:
    Equatable,
    Sendable
{
    fileprivate let generation: UInt64
}

public enum MacAgentDashboardApplicationOwnerErrorV0:
    Error,
    Equatable,
    Sendable
{
    case connectionGenerationExhausted
    case staleConnection
    case invalidStatus
    case staleStatus
}

/// Menu-application owner for an already-authenticated local status channel.
/// It issues a fresh unforgeable-by-caller generation token for each bound
/// connection and prevents late replies from a retired Agent/XPC generation
/// from restoring stale availability in the dashboard.
public actor MacAgentDashboardApplicationOwnerV0 {
    public typealias StateChanged =
        @Sendable (MacAgentDashboardSourceV0) async -> Void

    private let stateChanged: StateChanged
    private var source: MacAgentDashboardSourceV0 = .loading
    private var currentGeneration: UInt64?
    private var nextGeneration: UInt64 = 0
    private var lastDiagnosticSequence: UInt64?
    private var lastGeneratedAtUnixMilliseconds: Int64?

    public init(
        stateChanged: @escaping StateChanged = { _ in }
    ) {
        self.stateChanged = stateChanged
    }

    public func snapshot() -> MacAgentDashboardSourceV0 { source }

    /// Called only after the platform adapter has accepted a new local XPC
    /// connection candidate. This token carries no peer-authentication claim;
    /// the adapter must still authenticate the peer before requesting status.
    public func beginConnection()
        async throws -> MacAgentDashboardConnectionTokenV0
    {
        guard nextGeneration < UInt64.max else {
            throw MacAgentDashboardApplicationOwnerErrorV0
                .connectionGenerationExhausted
        }
        nextGeneration += 1
        currentGeneration = nextGeneration
        lastDiagnosticSequence = nil
        lastGeneratedAtUnixMilliseconds = nil
        source = .loading
        await publish()
        return MacAgentDashboardConnectionTokenV0(
            generation: nextGeneration
        )
    }

    public func receive(
        _ status: LocalAgentStatusSnapshot,
        from token: MacAgentDashboardConnectionTokenV0
    ) async throws {
        try requireCurrent(token)
        do {
            try status.validate()
        } catch {
            throw MacAgentDashboardApplicationOwnerErrorV0.invalidStatus
        }
        if let lastDiagnosticSequence,
           status.diagnosticSequence <= lastDiagnosticSequence {
            throw MacAgentDashboardApplicationOwnerErrorV0.staleStatus
        }
        if let lastGeneratedAtUnixMilliseconds,
           status.generatedAtUnixMilliseconds
                < lastGeneratedAtUnixMilliseconds {
            throw MacAgentDashboardApplicationOwnerErrorV0.staleStatus
        }
        lastDiagnosticSequence = status.diagnosticSequence
        lastGeneratedAtUnixMilliseconds =
            status.generatedAtUnixMilliseconds
        source = .status(status)
        await publish()
    }

    public func connectionUnavailable(
        _ token: MacAgentDashboardConnectionTokenV0
    ) async throws {
        try requireCurrent(token)
        retireCurrentConnection()
        source = .unavailable
        await publish()
    }

    /// App teardown or a platform-wide local-service invalidation retires the
    /// current generation without requiring an already-lost connection token.
    public func applicationInvalidated() async {
        retireCurrentConnection()
        source = .unavailable
        await publish()
    }

    private func requireCurrent(
        _ token: MacAgentDashboardConnectionTokenV0
    ) throws {
        guard token.generation == currentGeneration else {
            throw MacAgentDashboardApplicationOwnerErrorV0.staleConnection
        }
    }

    private func retireCurrentConnection() {
        currentGeneration = nil
        lastDiagnosticSequence = nil
        lastGeneratedAtUnixMilliseconds = nil
    }

    private func publish() async { await stateChanged(source) }
}
