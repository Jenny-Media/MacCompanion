import CompanionDomain
import Foundation

public enum AuditActorV0: String, Codable, CaseIterable, Sendable {
    case localUser
    case agent
    case menuApp
    case diagnosticCLI
    case pairedDevice
    case system
}

public enum AuditVisibilityV0: String, Codable, CaseIterable, Sendable {
    case localOnly
    case subjectDevice
    case allPairedDevices
}

public enum AuditEventCodeV0: String, Codable, CaseIterable, Sendable {
    case pairingApproved = "pairing.approved"
    case deviceNameConfirmed = "device.nameConfirmed"
    case deviceSuspended = "device.suspended"
    case deviceResumed = "device.resumed"
    case deviceRevoked = "device.revoked"
    case authenticationSucceeded = "auth.succeeded"
    case authenticationRejected = "auth.rejected"
    case connectionOpened = "connection.opened"
    case connectionClosed = "connection.closed"
    case hostAvailabilityChanged = "host.availabilityChanged"
    case hostSecurityStateChanged = "host.securityStateChanged"
    case capabilityRegistryChanged = "capability.registryChanged"
    case operationRequested = "operation.requested"
    case operationDenied = "operation.denied"
    case operationApproved = "operation.approved"
    case operationAdmitted = "operation.admitted"
    case operationCompleted = "operation.completed"
    case operationFailed = "operation.failed"
    case operationCancelled = "operation.cancelled"
    case operationOutcomeUnknown = "operation.outcomeUnknown"
    case interactiveRequested = "interactive.requested"
    case interactiveApproved = "interactive.approved"
    case interactiveStarted = "interactive.started"
    case interactivePaused = "interactive.paused"
    case interactiveSurfaceChanged = "interactive.surfaceChanged"
    case interactiveStopped = "interactive.stopped"
    case interactiveFailed = "interactive.failed"
    case permissionChanged = "permission.changed"
    case policyChanged = "policy.changed"
    case protocolRejected = "protocol.rejected"
    case rateLimitApplied = "rateLimit.applied"
    case auditStorageDegraded = "audit.storageDegraded"

    public var permitsGlobalVisibility: Bool {
        switch self {
        case .hostAvailabilityChanged, .hostSecurityStateChanged,
             .auditStorageDegraded:
            true
        default:
            false
        }
    }
}

public enum AuditRouteClassV0: String, Codable, CaseIterable, Sendable {
    case localDiscovery
    case directPrivateAddress
    case privateHostname
}

public enum AuditSurfaceKindV0: String, Codable, CaseIterable, Sendable {
    case desktop
    case application
    case window
    case focusedRegion
}

public enum AuditOutcomeV0: String, Codable, CaseIterable, Sendable {
    case allowed
    case denied
    case succeeded
    case failed
    case cancelled
    case outcomeUnknown
    case expired
    case unavailable
}

public enum AuditImportanceV0: String, Codable, CaseIterable, Sendable {
    case bestEffort
    case requiredBeforeEffect
}

public enum AuditRecordErrorV0: Error, Equatable, Sendable {
    case invalidRecord
}

public struct AuditEventDraftV0: Equatable, Sendable {
    public static let maximumLogicalSize = 1_024

    public let eventID: UUID
    public let observedAtUnixMilliseconds: Int64
    public let actor: AuditActorV0
    public let visibility: AuditVisibilityV0
    public let subjectDeviceID: UUID?
    public let correlationID: UUID?
    public let operationID: UUID?
    public let interactiveSessionID: UUID?
    public let code: AuditEventCodeV0
    public let capabilityID: String?
    public let policyRevision: PolicyRevision?
    public let authorizationEpoch: AuthorizationEpoch?
    public let grantRevision: GrantRevision?
    public let routeClass: AuditRouteClassV0?
    public let surfaceKind: AuditSurfaceKindV0?
    public let outcome: AuditOutcomeV0?
    public let importance: AuditImportanceV0
    public let logicalSize: Int

    public init(
        eventID: UUID,
        observedAtUnixMilliseconds: Int64,
        actor: AuditActorV0,
        visibility: AuditVisibilityV0,
        subjectDeviceID: UUID? = nil,
        correlationID: UUID? = nil,
        operationID: UUID? = nil,
        interactiveSessionID: UUID? = nil,
        code: AuditEventCodeV0,
        capabilityID: String? = nil,
        policyRevision: PolicyRevision? = nil,
        authorizationEpoch: AuthorizationEpoch? = nil,
        grantRevision: GrantRevision? = nil,
        routeClass: AuditRouteClassV0? = nil,
        surfaceKind: AuditSurfaceKindV0? = nil,
        outcome: AuditOutcomeV0? = nil,
        importance: AuditImportanceV0
    ) throws {
        let capabilityIsValid = capabilityID.map {
            (try? CapabilityGrantSet([$0])) != nil
        } ?? true
        let revisionsAreValid = [
            policyRevision?.rawValue,
            authorizationEpoch?.rawValue,
            grantRevision?.rawValue,
        ].compactMap { $0 }.allSatisfy { $0 >= 1 }
        let pairedActorIsValid = actor != .pairedDevice || subjectDeviceID != nil
        let visibilityIsValid: Bool
        switch visibility {
        case .localOnly:
            visibilityIsValid = true
        case .subjectDevice:
            visibilityIsValid = subjectDeviceID != nil
        case .allPairedDevices:
            visibilityIsValid = code.permitsGlobalVisibility
                && (actor == .agent || actor == .system)
                && subjectDeviceID == nil
                && correlationID == nil
                && capabilityID == nil
                && operationID == nil
                && interactiveSessionID == nil
                && authorizationEpoch == nil
                && grantRevision == nil
                && routeClass == nil
                && surfaceKind == nil
        }
        let size = Self.logicalSize(
            actor: actor,
            visibility: visibility,
            code: code,
            capabilityID: capabilityID,
            routeClass: routeClass,
            surfaceKind: surfaceKind,
            outcome: outcome
        )
        guard observedAtUnixMilliseconds >= 0,
              capabilityIsValid,
              revisionsAreValid,
              pairedActorIsValid,
              visibilityIsValid,
              size <= Self.maximumLogicalSize else {
            throw AuditRecordErrorV0.invalidRecord
        }
        self.eventID = eventID
        self.observedAtUnixMilliseconds = observedAtUnixMilliseconds
        self.actor = actor
        self.visibility = visibility
        self.subjectDeviceID = subjectDeviceID
        self.correlationID = correlationID
        self.operationID = operationID
        self.interactiveSessionID = interactiveSessionID
        self.code = code
        self.capabilityID = capabilityID
        self.policyRevision = policyRevision
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.routeClass = routeClass
        self.surfaceKind = surfaceKind
        self.outcome = outcome
        self.importance = importance
        logicalSize = size
    }

    public var rateLimitBucket: String {
        actor.rawValue + ":" + (subjectDeviceID?.uuidString.lowercased() ?? "-")
    }

    private static func logicalSize(
        actor: AuditActorV0,
        visibility: AuditVisibilityV0,
        code: AuditEventCodeV0,
        capabilityID: String?,
        routeClass: AuditRouteClassV0?,
        surfaceKind: AuditSurfaceKindV0?,
        outcome: AuditOutcomeV0?
    ) -> Int {
        256
            + actor.rawValue.utf8.count
            + visibility.rawValue.utf8.count
            + code.rawValue.utf8.count
            + (capabilityID?.utf8.count ?? 0)
            + (routeClass?.rawValue.utf8.count ?? 0)
            + (surfaceKind?.rawValue.utf8.count ?? 0)
            + (outcome?.rawValue.utf8.count ?? 0)
    }
}

public struct StoredAuditEventV0: Equatable, Sendable {
    public let sequence: UInt64
    public let draft: AuditEventDraftV0

    public init(sequence: UInt64, draft: AuditEventDraftV0) {
        self.sequence = sequence
        self.draft = draft
    }
}

public enum AuditReadScopeV0: Equatable, Sendable {
    case localAdministration
    case requestingDevice(UUID)
}

public struct AuditGapSummaryV0: Equatable, Sendable {
    public let prunedThroughSequence: UInt64?
    public let droppedEventCount: UInt64

    public var historyIsIncomplete: Bool {
        prunedThroughSequence != nil || droppedEventCount > 0
    }

    public init(
        prunedThroughSequence: UInt64?,
        droppedEventCount: UInt64
    ) {
        self.prunedThroughSequence = prunedThroughSequence
        self.droppedEventCount = droppedEventCount
    }
}

public struct AuditPageV0: Equatable, Sendable {
    public let events: [StoredAuditEventV0]
    public let nextBeforeSequence: UInt64?
    public let oldestVisibleSequence: UInt64?
    public let newestVisibleSequence: UInt64?
    public let gaps: AuditGapSummaryV0

    public init(
        events: [StoredAuditEventV0],
        nextBeforeSequence: UInt64?,
        oldestVisibleSequence: UInt64?,
        newestVisibleSequence: UInt64?,
        gaps: AuditGapSummaryV0
    ) {
        self.events = events
        self.nextBeforeSequence = nextBeforeSequence
        self.oldestVisibleSequence = oldestVisibleSequence
        self.newestVisibleSequence = newestVisibleSequence
        self.gaps = gaps
    }
}

public enum AuditAppendResultV0: Equatable, Sendable {
    case recorded(StoredAuditEventV0)
    case droppedRateLimited
    case droppedQuotaExceeded

    public var wasRecorded: Bool {
        if case .recorded = self { return true }
        return false
    }
}
