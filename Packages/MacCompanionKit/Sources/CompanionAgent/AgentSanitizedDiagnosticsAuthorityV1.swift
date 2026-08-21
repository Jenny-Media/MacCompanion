import CompanionDomain
import CompanionIPC
import Foundation

public enum AgentSanitizedDiagnosticsAuthorityErrorV1:
    Error,
    Equatable,
    Sendable
{
    case invalidTime
    case sequenceExhausted
}

public enum AgentLocalDiagnosticExportServiceErrorV1:
    Error,
    Equatable,
    Sendable
{
    case sourceUnavailable
}

package protocol AgentSanitizedDiagnosticEventReadingV1: Sendable {
    func readAll() async throws -> [SanitizedDiagnosticEvent]
}

public protocol AgentLocalDiagnosticExportingV1: Sendable {
    func export() async throws -> LocalDiagnosticExport
}

/// Agent-owned, boot-scoped storage for content-free operational diagnostics.
/// This is deliberately not durable audit history: it stores no arbitrary
/// strings and retains only the newest bounded set of events.
package actor AgentSanitizedDiagnosticsAuthorityV1:
    AgentSanitizedDiagnosticEventReadingV1
{
    package static let maximumRetainedEventCount = 256

    private var events: [SanitizedDiagnosticEvent] = []
    private var lastSequence: UInt64

    package init(startingAfter sequence: UInt64 = 0) {
        lastSequence = sequence
    }

    @discardableResult
    package func record(
        occurredAtUnixMilliseconds: Int64,
        component: SanitizedDiagnosticComponent,
        severity: SanitizedDiagnosticSeverity,
        code: SanitizedDiagnosticCode
    ) throws -> SanitizedDiagnosticEvent {
        guard occurredAtUnixMilliseconds >= 0,
              occurredAtUnixMilliseconds
                <= Int64(MonotonicRevision<AuthorizationEpochTag>.maximumWireValue)
        else {
            throw AgentSanitizedDiagnosticsAuthorityErrorV1.invalidTime
        }
        guard lastSequence
                < MonotonicRevision<AuthorizationEpochTag>.maximumWireValue
        else {
            throw AgentSanitizedDiagnosticsAuthorityErrorV1.sequenceExhausted
        }

        let event = try SanitizedDiagnosticEvent(
            sequence: lastSequence + 1,
            occurredAtUnixMilliseconds: occurredAtUnixMilliseconds,
            component: component,
            severity: severity,
            code: code
        )
        events.append(event)
        if events.count > Self.maximumRetainedEventCount {
            events.removeFirst(events.count - Self.maximumRetainedEventCount)
        }
        lastSequence = event.sequence
        return event
    }

    package func readAll() -> [SanitizedDiagnosticEvent] {
        events
    }
}

/// The only event-producing facet handed to Agent coordinators. Consumers
/// cannot inspect, replace, or inject sequence numbers into the authority.
package struct AgentSanitizedDiagnosticEventPublisherV1: Sendable {
    private let authority: AgentSanitizedDiagnosticsAuthorityV1

    package init(authority: AgentSanitizedDiagnosticsAuthorityV1) {
        self.authority = authority
    }

    @discardableResult
    package func publish(
        occurredAtUnixMilliseconds: Int64,
        component: SanitizedDiagnosticComponent,
        severity: SanitizedDiagnosticSeverity,
        code: SanitizedDiagnosticCode
    ) async throws -> SanitizedDiagnosticEvent {
        try await authority.record(
            occurredAtUnixMilliseconds: occurredAtUnixMilliseconds,
            component: component,
            severity: severity,
            code: code
        )
    }
}

/// Bundle-independent export boundary for an already-authenticated local IPC
/// adapter. Platform peer authentication and method authorization happen
/// before the adapter receives this capability.
public struct AgentLocalDiagnosticExportServiceV1:
    AgentLocalDiagnosticExportingV1,
    Sendable
{
    private let status: any AgentLocalStatusReadingV1
    private let events: any AgentSanitizedDiagnosticEventReadingV1

    package init(
        status: any AgentLocalStatusReadingV1,
        events: any AgentSanitizedDiagnosticEventReadingV1
    ) {
        self.status = status
        self.events = events
    }

    public func export() async throws -> LocalDiagnosticExport {
        do {
            let status = try await status.read()
            let events = try await events.readAll()
            return try LocalDiagnosticExport(status: status, events: events)
        } catch {
            throw AgentLocalDiagnosticExportServiceErrorV1.sourceUnavailable
        }
    }
}
