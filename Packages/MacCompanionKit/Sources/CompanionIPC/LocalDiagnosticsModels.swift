import CompanionDomain
import CompanionLifecycle
import Foundation

public enum LocalAgentNetworkState: String, Codable, CaseIterable, Sendable {
    case stopped
    case starting
    case listening
    case degraded
}

public enum LocalSecurityPosture: String, Codable, CaseIterable, Sendable {
    case nominal
    case denyLatched
    case storageUnavailable
}

public enum LocalRouteKind: String, Codable, CaseIterable, Comparable, Sendable {
    case lan
    case privateDNS
    case privateNetwork

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum SanitizedDiagnosticComponent: String, Codable, CaseIterable, Sendable {
    case lifecycle
    case localIPC
    case network
    case persistence
    case security
    case interactiveControl
}

public enum SanitizedDiagnosticSeverity: String, Codable, CaseIterable, Sendable {
    case information
    case warning
    case error
}

public enum SanitizedDiagnosticCode: String, Codable, CaseIterable, Comparable, Sendable {
    case agentUnavailable
    case auditHistoryDegraded
    case authorizationChanged
    case captureUnavailable
    case denyLatchArmed
    case localNetworkDenied
    case menuAppUnavailable
    case permissionLost
    case routeUnavailable
    case storageUnavailable
    case versionMismatch

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum LocalDiagnosticsValidationError: Error, Equatable, Sendable {
    case invalidTime
    case invalidSequence
    case invalidCount
    case invalidOrdering
    case duplicateValue
    case boundsExceeded
    case sensitiveDetailNotOmitted
}

/// A content-free status payload suitable for the menu app and diagnostic CLI.
/// It intentionally has no arbitrary string, address, path, title, or message field.
public struct LocalAgentStatusSnapshot: Codable, Equatable, Sendable {
    public static let maximumPairedDeviceCount: UInt16 = 8

    public let protocolVersion: LocalIPCProtocolVersion
    public let desiredEnabled: Bool
    public let consoleSession: ConsoleSessionState
    public let agentProcess: ManagedProcessState
    public let menuAppProcess: ManagedProcessState
    public let networkState: LocalAgentNetworkState
    public let securityPosture: LocalSecurityPosture
    public let routeKinds: [LocalRouteKind]
    public let pairedDeviceCount: UInt16
    public let interactiveControlGranted: Bool
    public let activeRemoteSessionCount: UInt16
    public let providerCount: UInt16
    public let warningCodes: [SanitizedDiagnosticCode]
    public let diagnosticSequence: UInt64
    public let generatedAtUnixMilliseconds: Int64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        desiredEnabled: Bool,
        consoleSession: ConsoleSessionState,
        agentProcess: ManagedProcessState,
        menuAppProcess: ManagedProcessState,
        networkState: LocalAgentNetworkState,
        securityPosture: LocalSecurityPosture,
        routeKinds: Set<LocalRouteKind>,
        pairedDeviceCount: UInt16,
        interactiveControlGranted: Bool = false,
        activeRemoteSessionCount: UInt16,
        providerCount: UInt16,
        warningCodes: Set<SanitizedDiagnosticCode>,
        diagnosticSequence: UInt64,
        generatedAtUnixMilliseconds: Int64
    ) throws {
        self.protocolVersion = protocolVersion
        self.desiredEnabled = desiredEnabled
        self.consoleSession = consoleSession
        self.agentProcess = agentProcess
        self.menuAppProcess = menuAppProcess
        self.networkState = networkState
        self.securityPosture = securityPosture
        self.routeKinds = routeKinds.sorted()
        self.pairedDeviceCount = pairedDeviceCount
        self.interactiveControlGranted = interactiveControlGranted
        self.activeRemoteSessionCount = activeRemoteSessionCount
        self.providerCount = providerCount
        self.warningCodes = warningCodes.sorted()
        self.diagnosticSequence = diagnosticSequence
        self.generatedAtUnixMilliseconds = generatedAtUnixMilliseconds
        try validate()
    }

    public func validate() throws {
        guard protocolVersion == .init() else { throw LocalDiagnosticsValidationError.boundsExceeded }
        guard generatedAtUnixMilliseconds >= 0,
              generatedAtUnixMilliseconds
                <= Int64(MonotonicRevision<AuthorizationEpochTag>.maximumWireValue)
        else { throw LocalDiagnosticsValidationError.invalidTime }
        guard diagnosticSequence <= MonotonicRevision<AuthorizationEpochTag>.maximumWireValue else {
            throw LocalDiagnosticsValidationError.invalidSequence
        }
        guard pairedDeviceCount <= Self.maximumPairedDeviceCount,
              providerCount <= 128, activeRemoteSessionCount <= 64,
              routeKinds.count <= LocalRouteKind.allCases.count,
              warningCodes.count <= SanitizedDiagnosticCode.allCases.count else {
            throw LocalDiagnosticsValidationError.boundsExceeded
        }
        try Self.validateSortedUnique(routeKinds)
        try Self.validateSortedUnique(warningCodes)
    }

    private static func validateSortedUnique<Value: Comparable & Hashable>(
        _ values: [Value]
    ) throws {
        guard values == values.sorted() else { throw LocalDiagnosticsValidationError.invalidOrdering }
        guard Set(values).count == values.count else { throw LocalDiagnosticsValidationError.duplicateValue }
    }
}

public struct SanitizedDiagnosticEvent: Codable, Equatable, Sendable {
    public let sequence: UInt64
    public let occurredAtUnixMilliseconds: Int64
    public let component: SanitizedDiagnosticComponent
    public let severity: SanitizedDiagnosticSeverity
    public let code: SanitizedDiagnosticCode
    public let occurrenceCount: UInt32

    public init(
        sequence: UInt64,
        occurredAtUnixMilliseconds: Int64,
        component: SanitizedDiagnosticComponent,
        severity: SanitizedDiagnosticSeverity,
        code: SanitizedDiagnosticCode,
        occurrenceCount: UInt32 = 1
    ) throws {
        self.sequence = sequence
        self.occurredAtUnixMilliseconds = occurredAtUnixMilliseconds
        self.component = component
        self.severity = severity
        self.code = code
        self.occurrenceCount = occurrenceCount
        try validate()
    }

    public func validate() throws {
        guard sequence >= 1,
              sequence <= MonotonicRevision<AuthorizationEpochTag>.maximumWireValue else {
            throw LocalDiagnosticsValidationError.invalidSequence
        }
        guard occurredAtUnixMilliseconds >= 0,
              occurredAtUnixMilliseconds
                <= Int64(MonotonicRevision<AuthorizationEpochTag>.maximumWireValue)
        else {
            throw LocalDiagnosticsValidationError.invalidTime
        }
        guard (1...1_000_000).contains(occurrenceCount) else {
            throw LocalDiagnosticsValidationError.invalidCount
        }
    }
}

public struct SanitizedDiagnosticQuery: Codable, Equatable, Sendable {
    public let afterSequence: UInt64
    public let limit: UInt16

    public init(afterSequence: UInt64, limit: UInt16) throws {
        guard afterSequence <= MonotonicRevision<AuthorizationEpochTag>.maximumWireValue else {
            throw LocalDiagnosticsValidationError.invalidSequence
        }
        guard (1...256).contains(limit) else {
            throw LocalDiagnosticsValidationError.boundsExceeded
        }
        self.afterSequence = afterSequence
        self.limit = limit
    }
}

public struct LocalDiagnosticExport: Codable, Equatable, Sendable {
    public let status: LocalAgentStatusSnapshot
    public let events: [SanitizedDiagnosticEvent]
    public let privateRouteDetailsOmitted: Bool
    public let contentBearingDataOmitted: Bool

    public init(
        status: LocalAgentStatusSnapshot,
        events: [SanitizedDiagnosticEvent],
        privateRouteDetailsOmitted: Bool = true,
        contentBearingDataOmitted: Bool = true
    ) throws {
        self.status = status
        self.events = events
        self.privateRouteDetailsOmitted = privateRouteDetailsOmitted
        self.contentBearingDataOmitted = contentBearingDataOmitted
        try validate()
    }

    public func validate() throws {
        try status.validate()
        guard privateRouteDetailsOmitted, contentBearingDataOmitted else {
            throw LocalDiagnosticsValidationError.sensitiveDetailNotOmitted
        }
        guard events.count <= 256 else { throw LocalDiagnosticsValidationError.boundsExceeded }
        var prior: UInt64 = 0
        for event in events {
            try event.validate()
            guard event.sequence > prior else {
                throw LocalDiagnosticsValidationError.invalidOrdering
            }
            prior = event.sequence
        }
    }
}
