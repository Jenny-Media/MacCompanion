import Foundation

public enum AuditPresentationCodeV0: String, CaseIterable, Sendable {
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

    public var title: String {
        switch self {
        case .pairingApproved: "Device paired"
        case .deviceNameConfirmed: "Device name confirmed"
        case .deviceSuspended: "Device suspended"
        case .deviceResumed: "Device resumed"
        case .deviceRevoked: "Device revoked"
        case .authenticationSucceeded: "Device authenticated"
        case .authenticationRejected: "Authentication rejected"
        case .connectionOpened: "Connection opened"
        case .connectionClosed: "Connection closed"
        case .hostAvailabilityChanged: "Mac availability changed"
        case .hostSecurityStateChanged: "Mac security state changed"
        case .capabilityRegistryChanged: "Available capabilities changed"
        case .operationRequested: "Action requested"
        case .operationDenied: "Action denied"
        case .operationApproved: "Action approved"
        case .operationAdmitted: "Action admitted"
        case .operationCompleted: "Action completed"
        case .operationFailed: "Action failed"
        case .operationCancelled: "Action cancelled"
        case .operationOutcomeUnknown: "Action outcome unknown"
        case .interactiveRequested: "Interactive Control requested"
        case .interactiveApproved: "Interactive Control approved"
        case .interactiveStarted: "Interactive Control started"
        case .interactivePaused: "Interactive Control paused"
        case .interactiveSurfaceChanged: "Interactive surface changed"
        case .interactiveStopped: "Interactive Control stopped"
        case .interactiveFailed: "Interactive Control failed"
        case .permissionChanged: "Mac permission changed"
        case .policyChanged: "Mac policy changed"
        case .protocolRejected: "Invalid protocol message rejected"
        case .rateLimitApplied: "Rate limit applied"
        case .auditStorageDegraded: "Audit history degraded"
        }
    }

    public var systemImage: String {
        switch self {
        case .pairingApproved, .authenticationSucceeded, .connectionOpened,
             .deviceResumed, .operationApproved, .operationAdmitted,
             .operationCompleted, .interactiveApproved, .interactiveStarted:
            "checkmark.circle"
        case .deviceSuspended, .interactivePaused:
            "pause.circle"
        case .deviceRevoked, .authenticationRejected, .operationDenied,
             .operationFailed, .interactiveFailed, .protocolRejected:
            "exclamationmark.triangle"
        case .operationOutcomeUnknown, .auditStorageDegraded:
            "questionmark.circle"
        case .operationCancelled, .interactiveStopped, .connectionClosed:
            "stop.circle"
        case .interactiveRequested, .interactiveSurfaceChanged:
            "rectangle.on.rectangle"
        case .deviceNameConfirmed, .hostAvailabilityChanged,
             .hostSecurityStateChanged, .capabilityRegistryChanged,
             .operationRequested, .permissionChanged, .policyChanged,
             .rateLimitApplied:
            "info.circle"
        }
    }
}

public enum AuditOutcomePresentationV0: String, CaseIterable, Sendable {
    case allowed
    case denied
    case succeeded
    case failed
    case cancelled
    case outcomeUnknown
    case expired
    case unavailable

    public var label: String {
        switch self {
        case .allowed: "Allowed"
        case .denied: "Denied"
        case .succeeded: "Succeeded"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        case .outcomeUnknown: "Outcome unknown"
        case .expired: "Expired"
        case .unavailable: "Unavailable"
        }
    }
}

public struct AuditGapPresentationV0: Equatable, Sendable {
    public let historyIsIncomplete: Bool
    public let messages: [String]

    public init(prunedThroughSequence: UInt64?, droppedEventCount: UInt64) {
        historyIsIncomplete = prunedThroughSequence != nil
            || droppedEventCount > 0
        var messages: [String] = []
        if prunedThroughSequence != nil {
            messages.append("Some older activity has expired or was compacted.")
        }
        if droppedEventCount > 0 {
            messages.append(
                "\(droppedEventCount) scoped event"
                    + (droppedEventCount == 1 ? " was" : "s were")
                    + " not retained."
            )
        }
        self.messages = messages
    }
}
