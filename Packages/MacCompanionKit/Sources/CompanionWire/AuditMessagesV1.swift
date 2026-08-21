import Foundation

public enum AuditSelfEventScopeWireV1: String, Codable, CaseIterable, Sendable {
    case selfDevice
    case host
}

public enum AuditActorWireV1: String, Codable, CaseIterable, Sendable {
    case localUser
    case agent
    case menuApp
    case diagnosticCLI
    case pairedDevice
    case system
}

public enum AuditEventCodeWireV1: String, Codable, CaseIterable, Sendable {
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

    var permitsHostScope: Bool {
        switch self {
        case .hostAvailabilityChanged, .hostSecurityStateChanged,
             .auditStorageDegraded:
            true
        default:
            false
        }
    }
}

public enum AuditRouteClassWireV1: String, Codable, CaseIterable, Sendable {
    case localDiscovery
    case directPrivateAddress
    case privateHostname
}

public enum AuditSurfaceKindWireV1: String, Codable, CaseIterable, Sendable {
    case desktop
    case application
    case window
    case focusedRegion
}

public enum AuditOutcomeWireV1: String, Codable, CaseIterable, Sendable {
    case allowed
    case denied
    case succeeded
    case failed
    case cancelled
    case outcomeUnknown
    case expired
    case unavailable
}

public struct AuditListRequestBodyV1: WireBody {
    private enum CodingKeys: String, CodingKey {
        case beforeSequence
        case limit
    }

    public static let kind = WireMessageKind.auditListRequest
    public let beforeSequence: Int64?
    public let limit: UInt8

    public init(beforeSequence: Int64?, limit: UInt8) throws {
        self.beforeSequence = beforeSequence
        self.limit = limit
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["beforeSequence", "limit"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        beforeSequence = try container.decodeIfPresent(
            Int64.self,
            forKey: .beforeSequence
        )
        limit = try container.decode(UInt8.self, forKey: .limit)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if let beforeSequence {
            try container.encode(beforeSequence, forKey: .beforeSequence)
        } else {
            try container.encodeNil(forKey: .beforeSequence)
        }
        try container.encode(limit, forKey: .limit)
    }

    public func validate() throws {
        guard (1...100).contains(limit),
              beforeSequence.map({
                  $0 >= 1 && $0 <= WireLimits.maximumSafeInteger
              }) ?? true else {
            throw WireError.invalidFrame(reason: "invalid audit page request")
        }
    }
}

public struct AuditSelfEventWireV1: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case sequence, eventID, observedAtUnixMilliseconds, scope, actor, code
        case correlationID, operationID, interactiveSessionID, capabilityID
        case policyRevision, authorizationEpoch, grantRevision
        case routeClass, surfaceKind, outcome
    }

    public let sequence: Int64
    public let eventID: WireUUID
    public let observedAtUnixMilliseconds: Int64
    public let scope: AuditSelfEventScopeWireV1
    public let actor: AuditActorWireV1
    public let code: AuditEventCodeWireV1
    public let correlationID: WireUUID?
    public let operationID: WireUUID?
    public let interactiveSessionID: WireUUID?
    public let capabilityID: String?
    public let policyRevision: Int64?
    public let authorizationEpoch: Int64?
    public let grantRevision: Int64?
    public let routeClass: AuditRouteClassWireV1?
    public let surfaceKind: AuditSurfaceKindWireV1?
    public let outcome: AuditOutcomeWireV1?

    public init(
        sequence: Int64,
        eventID: WireUUID,
        observedAtUnixMilliseconds: Int64,
        scope: AuditSelfEventScopeWireV1,
        actor: AuditActorWireV1,
        code: AuditEventCodeWireV1,
        correlationID: WireUUID? = nil,
        operationID: WireUUID? = nil,
        interactiveSessionID: WireUUID? = nil,
        capabilityID: String? = nil,
        policyRevision: Int64? = nil,
        authorizationEpoch: Int64? = nil,
        grantRevision: Int64? = nil,
        routeClass: AuditRouteClassWireV1? = nil,
        surfaceKind: AuditSurfaceKindWireV1? = nil,
        outcome: AuditOutcomeWireV1? = nil
    ) throws {
        self.sequence = sequence
        self.eventID = eventID
        self.observedAtUnixMilliseconds = observedAtUnixMilliseconds
        self.scope = scope
        self.actor = actor
        self.code = code
        self.correlationID = correlationID
        self.operationID = operationID
        self.interactiveSessionID = interactiveSessionID
        self.capabilityID = capabilityID
        self.policyRevision = policyRevision
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.routeClass = routeClass
        self.surfaceKind = surfaceKind
        self.outcome = outcome
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            [
                "sequence", "eventID", "observedAtUnixMilliseconds", "scope",
                "actor", "code", "correlationID", "operationID",
                "interactiveSessionID", "capabilityID", "policyRevision",
                "authorizationEpoch", "grantRevision", "routeClass",
                "surfaceKind", "outcome",
            ]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sequence = try container.decode(Int64.self, forKey: .sequence)
        eventID = try container.decode(WireUUID.self, forKey: .eventID)
        observedAtUnixMilliseconds = try container.decode(
            Int64.self,
            forKey: .observedAtUnixMilliseconds
        )
        scope = try container.decode(
            AuditSelfEventScopeWireV1.self,
            forKey: .scope
        )
        actor = try container.decode(AuditActorWireV1.self, forKey: .actor)
        code = try container.decode(AuditEventCodeWireV1.self, forKey: .code)
        correlationID = try container.decodeIfPresent(
            WireUUID.self,
            forKey: .correlationID
        )
        operationID = try container.decodeIfPresent(
            WireUUID.self,
            forKey: .operationID
        )
        interactiveSessionID = try container.decodeIfPresent(
            WireUUID.self,
            forKey: .interactiveSessionID
        )
        capabilityID = try container.decodeIfPresent(
            String.self,
            forKey: .capabilityID
        )
        policyRevision = try container.decodeIfPresent(
            Int64.self,
            forKey: .policyRevision
        )
        authorizationEpoch = try container.decodeIfPresent(
            Int64.self,
            forKey: .authorizationEpoch
        )
        grantRevision = try container.decodeIfPresent(
            Int64.self,
            forKey: .grantRevision
        )
        routeClass = try container.decodeIfPresent(
            AuditRouteClassWireV1.self,
            forKey: .routeClass
        )
        surfaceKind = try container.decodeIfPresent(
            AuditSurfaceKindWireV1.self,
            forKey: .surfaceKind
        )
        outcome = try container.decodeIfPresent(
            AuditOutcomeWireV1.self,
            forKey: .outcome
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(eventID, forKey: .eventID)
        try container.encode(
            observedAtUnixMilliseconds,
            forKey: .observedAtUnixMilliseconds
        )
        try container.encode(scope, forKey: .scope)
        try container.encode(actor, forKey: .actor)
        try container.encode(code, forKey: .code)
        try container.encodeOptional(correlationID, forKey: .correlationID)
        try container.encodeOptional(operationID, forKey: .operationID)
        try container.encodeOptional(
            interactiveSessionID,
            forKey: .interactiveSessionID
        )
        try container.encodeOptional(capabilityID, forKey: .capabilityID)
        try container.encodeOptional(policyRevision, forKey: .policyRevision)
        try container.encodeOptional(
            authorizationEpoch,
            forKey: .authorizationEpoch
        )
        try container.encodeOptional(grantRevision, forKey: .grantRevision)
        try container.encodeOptional(routeClass, forKey: .routeClass)
        try container.encodeOptional(surfaceKind, forKey: .surfaceKind)
        try container.encodeOptional(outcome, forKey: .outcome)
    }

    public func validate() throws {
        let revisions = [
            policyRevision, authorizationEpoch, grantRevision,
        ].compactMap { $0 }
        guard sequence >= 1,
              sequence <= WireLimits.maximumSafeInteger,
              observedAtUnixMilliseconds >= 0,
              observedAtUnixMilliseconds <= WireLimits.maximumSafeInteger,
              revisions.allSatisfy({
                  $0 >= 1 && $0 <= WireLimits.maximumSafeInteger
              }),
              capabilityID.map({
                  CapabilityDescriptorV1.isIdentifier($0, maximum: 96)
              }) ?? true else {
            throw WireError.invalidFrame(reason: "invalid audit event")
        }
        if scope == .host {
            guard code.permitsHostScope,
                  actor == .system || actor == .agent,
                  correlationID == nil,
                  operationID == nil,
                  interactiveSessionID == nil,
                  capabilityID == nil,
                  authorizationEpoch == nil,
                  grantRevision == nil,
                  routeClass == nil,
                  surfaceKind == nil else {
                throw WireError.invalidFrame(
                    reason: "host audit event contains device-scoped fields"
                )
            }
        }
    }
}

public struct AuditGapWireV1: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case prunedThroughSequence
        case droppedEventCount
    }

    public let prunedThroughSequence: Int64?
    public let droppedEventCount: Int64

    public init(
        prunedThroughSequence: Int64?,
        droppedEventCount: Int64
    ) throws {
        self.prunedThroughSequence = prunedThroughSequence
        self.droppedEventCount = droppedEventCount
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            ["prunedThroughSequence", "droppedEventCount"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        prunedThroughSequence = try container.decodeIfPresent(
            Int64.self,
            forKey: .prunedThroughSequence
        )
        droppedEventCount = try container.decode(
            Int64.self,
            forKey: .droppedEventCount
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeOptional(
            prunedThroughSequence,
            forKey: .prunedThroughSequence
        )
        try container.encode(droppedEventCount, forKey: .droppedEventCount)
    }

    private func validate() throws {
        guard prunedThroughSequence.map({
            $0 >= 1 && $0 <= WireLimits.maximumSafeInteger
        }) ?? true,
        droppedEventCount >= 0,
        droppedEventCount <= WireLimits.maximumSafeInteger else {
            throw WireError.invalidFrame(reason: "invalid audit gap")
        }
    }
}

public struct AuditListResponseBodyV1: WireBody {
    private enum CodingKeys: String, CodingKey {
        case events, nextBeforeSequence, oldestVisibleSequence
        case newestVisibleSequence, gaps
    }

    public static let kind = WireMessageKind.auditListResponse
    public let events: [AuditSelfEventWireV1]
    public let nextBeforeSequence: Int64?
    public let oldestVisibleSequence: Int64?
    public let newestVisibleSequence: Int64?
    public let gaps: AuditGapWireV1

    public init(
        events: [AuditSelfEventWireV1],
        nextBeforeSequence: Int64?,
        oldestVisibleSequence: Int64?,
        newestVisibleSequence: Int64?,
        gaps: AuditGapWireV1
    ) throws {
        self.events = events
        self.nextBeforeSequence = nextBeforeSequence
        self.oldestVisibleSequence = oldestVisibleSequence
        self.newestVisibleSequence = newestVisibleSequence
        self.gaps = gaps
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            [
                "events", "nextBeforeSequence", "oldestVisibleSequence",
                "newestVisibleSequence", "gaps",
            ]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        events = try container.decode(
            [AuditSelfEventWireV1].self,
            forKey: .events
        )
        nextBeforeSequence = try container.decodeIfPresent(
            Int64.self,
            forKey: .nextBeforeSequence
        )
        oldestVisibleSequence = try container.decodeIfPresent(
            Int64.self,
            forKey: .oldestVisibleSequence
        )
        newestVisibleSequence = try container.decodeIfPresent(
            Int64.self,
            forKey: .newestVisibleSequence
        )
        gaps = try container.decode(AuditGapWireV1.self, forKey: .gaps)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(events, forKey: .events)
        try container.encodeOptional(
            nextBeforeSequence,
            forKey: .nextBeforeSequence
        )
        try container.encodeOptional(
            oldestVisibleSequence,
            forKey: .oldestVisibleSequence
        )
        try container.encodeOptional(
            newestVisibleSequence,
            forKey: .newestVisibleSequence
        )
        try container.encode(gaps, forKey: .gaps)
    }

    public func validate() throws {
        let sequences = events.map(\.sequence)
        let boundsArePaired = (oldestVisibleSequence == nil)
            == (newestVisibleSequence == nil)
        let boundsAreValid = switch (
            oldestVisibleSequence,
            newestVisibleSequence
        ) {
        case (nil, nil): true
        case let (oldest?, newest?):
            oldest >= 1
                && oldest <= newest
                && newest <= WireLimits.maximumSafeInteger
        default: false
        }
        guard events.count <= 100,
              sequences == sequences.sorted(by: >),
              Set(sequences).count == sequences.count,
              boundsArePaired,
              boundsAreValid,
              events.allSatisfy({ event in
                  guard let oldestVisibleSequence,
                        let newestVisibleSequence else { return false }
                  return event.sequence >= oldestVisibleSequence
                      && event.sequence <= newestVisibleSequence
              }),
              nextBeforeSequence.map({ cursor in
                  !events.isEmpty
                      && cursor == events.last?.sequence
              }) ?? true else {
            throw WireError.invalidFrame(reason: "invalid audit page response")
        }
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeOptional<Value: Encodable>(
        _ value: Value?,
        forKey key: Key
    ) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
