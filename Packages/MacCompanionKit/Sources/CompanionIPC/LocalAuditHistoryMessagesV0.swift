import CompanionDomain
import CompanionPersistence
import Foundation

private struct LocalAuditAnyCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private enum LocalAuditCodingV0 {
    static let maximumSafeInteger =
        MonotonicRevision<AuthorizationEpochTag>.maximumWireValue

    static func rejectUnknown<Key: CodingKey & CaseIterable>(
        from decoder: Decoder,
        as type: Key.Type
    ) throws where Key.AllCases: Collection {
        let container = try decoder.container(
            keyedBy: LocalAuditAnyCodingKey.self
        )
        let allowed = Set(type.allCases.map(\.stringValue))
        guard container.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "local audit payload contains an unknown field"
                )
            )
        }
    }
}

public enum LocalAuditHistoryMessageErrorV0: Error, Equatable, Sendable {
    case invalidVersion
    case invalidRequest
    case invalidEvent
    case invalidPage
}

public struct LocalAuditPageRequestV0: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, requestID, beforeSequence, limit
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let requestID: UUID
    public let beforeSequence: UInt64?
    public let limit: UInt16

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        requestID: UUID,
        beforeSequence: UInt64? = nil,
        limit: UInt16
    ) throws {
        guard protocolVersion == .init() else {
            throw LocalAuditHistoryMessageErrorV0.invalidVersion
        }
        let cursorIsValid: Bool
        if let beforeSequence {
            cursorIsValid = (1...LocalAuditCodingV0.maximumSafeInteger)
                .contains(beforeSequence)
        } else {
            cursorIsValid = true
        }
        guard (1...100).contains(limit),
              cursorIsValid else {
            throw LocalAuditHistoryMessageErrorV0.invalidRequest
        }
        self.protocolVersion = protocolVersion
        self.requestID = requestID
        self.beforeSequence = beforeSequence
        self.limit = limit
    }

    public init(from decoder: Decoder) throws {
        try LocalAuditCodingV0.rejectUnknown(from: decoder, as: CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            protocolVersion: values.decode(
                LocalIPCProtocolVersion.self,
                forKey: .protocolVersion
            ),
            requestID: values.decode(UUID.self, forKey: .requestID),
            beforeSequence: values.decodeIfPresent(
                UInt64.self,
                forKey: .beforeSequence
            ),
            limit: values.decode(UInt16.self, forKey: .limit)
        )
    }
}

public struct LocalAuditEventV0: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sequence, eventID, observedAtUnixMilliseconds, actor, visibility
        case subjectDeviceID, code, capabilityID, routeClass, surfaceKind
        case outcome
    }

    public let sequence: UInt64
    public let eventID: UUID
    public let observedAtUnixMilliseconds: Int64
    public let actor: AuditActorV0
    public let visibility: AuditVisibilityV0
    public let subjectDeviceID: UUID?
    public let code: AuditEventCodeV0
    public let capabilityID: String?
    public let routeClass: AuditRouteClassV0?
    public let surfaceKind: AuditSurfaceKindV0?
    public let outcome: AuditOutcomeV0?

    public init(
        sequence: UInt64,
        eventID: UUID,
        observedAtUnixMilliseconds: Int64,
        actor: AuditActorV0,
        visibility: AuditVisibilityV0,
        subjectDeviceID: UUID?,
        code: AuditEventCodeV0,
        capabilityID: String?,
        routeClass: AuditRouteClassV0?,
        surfaceKind: AuditSurfaceKindV0?,
        outcome: AuditOutcomeV0?
    ) throws {
        let capabilityIsValid = capabilityID.map {
            (try? CapabilityGrantSet([$0])) != nil
        } ?? true
        let actorIsValid = actor != .pairedDevice || subjectDeviceID != nil
        let visibilityIsValid: Bool
        switch visibility {
        case .localOnly:
            visibilityIsValid = true
        case .subjectDevice:
            visibilityIsValid = subjectDeviceID != nil
        case .allPairedDevices:
            visibilityIsValid = code.permitsGlobalVisibility
                && subjectDeviceID == nil
                && capabilityID == nil
                && routeClass == nil
                && surfaceKind == nil
        }
        guard (1...LocalAuditCodingV0.maximumSafeInteger).contains(sequence),
              observedAtUnixMilliseconds >= 0,
              UInt64(observedAtUnixMilliseconds)
                <= LocalAuditCodingV0.maximumSafeInteger,
              capabilityIsValid,
              actorIsValid,
              visibilityIsValid else {
            throw LocalAuditHistoryMessageErrorV0.invalidEvent
        }
        self.sequence = sequence
        self.eventID = eventID
        self.observedAtUnixMilliseconds = observedAtUnixMilliseconds
        self.actor = actor
        self.visibility = visibility
        self.subjectDeviceID = subjectDeviceID
        self.code = code
        self.capabilityID = capabilityID
        self.routeClass = routeClass
        self.surfaceKind = surfaceKind
        self.outcome = outcome
    }

    public init(from decoder: Decoder) throws {
        try LocalAuditCodingV0.rejectUnknown(from: decoder, as: CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            sequence: values.decode(UInt64.self, forKey: .sequence),
            eventID: values.decode(UUID.self, forKey: .eventID),
            observedAtUnixMilliseconds: values.decode(
                Int64.self,
                forKey: .observedAtUnixMilliseconds
            ),
            actor: values.decode(AuditActorV0.self, forKey: .actor),
            visibility: values.decode(
                AuditVisibilityV0.self,
                forKey: .visibility
            ),
            subjectDeviceID: values.decodeIfPresent(
                UUID.self,
                forKey: .subjectDeviceID
            ),
            code: values.decode(AuditEventCodeV0.self, forKey: .code),
            capabilityID: values.decodeIfPresent(
                String.self,
                forKey: .capabilityID
            ),
            routeClass: values.decodeIfPresent(
                AuditRouteClassV0.self,
                forKey: .routeClass
            ),
            surfaceKind: values.decodeIfPresent(
                AuditSurfaceKindV0.self,
                forKey: .surfaceKind
            ),
            outcome: values.decodeIfPresent(
                AuditOutcomeV0.self,
                forKey: .outcome
            )
        )
    }
}

public struct LocalAuditGapSummaryV0: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case prunedThroughSequence, droppedEventCount
    }

    public let prunedThroughSequence: UInt64?
    public let droppedEventCount: UInt64

    public init(
        prunedThroughSequence: UInt64?,
        droppedEventCount: UInt64
    ) throws {
        let pruneBoundIsValid: Bool
        if let prunedThroughSequence {
            pruneBoundIsValid = (1...LocalAuditCodingV0.maximumSafeInteger)
                .contains(prunedThroughSequence)
        } else {
            pruneBoundIsValid = true
        }
        guard pruneBoundIsValid,
              droppedEventCount <= LocalAuditCodingV0.maximumSafeInteger else {
            throw LocalAuditHistoryMessageErrorV0.invalidPage
        }
        self.prunedThroughSequence = prunedThroughSequence
        self.droppedEventCount = droppedEventCount
    }

    public init(from decoder: Decoder) throws {
        try LocalAuditCodingV0.rejectUnknown(from: decoder, as: CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            prunedThroughSequence: values.decodeIfPresent(
                UInt64.self,
                forKey: .prunedThroughSequence
            ),
            droppedEventCount: values.decode(
                UInt64.self,
                forKey: .droppedEventCount
            )
        )
    }
}

public struct LocalAuditPageResponseV0: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, correlationID, events, nextBeforeSequence
        case oldestVisibleSequence, newestVisibleSequence, gaps
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let correlationID: UUID
    public let events: [LocalAuditEventV0]
    public let nextBeforeSequence: UInt64?
    public let oldestVisibleSequence: UInt64?
    public let newestVisibleSequence: UInt64?
    public let gaps: LocalAuditGapSummaryV0

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        correlationID: UUID,
        events: [LocalAuditEventV0],
        nextBeforeSequence: UInt64?,
        oldestVisibleSequence: UInt64?,
        newestVisibleSequence: UInt64?,
        gaps: LocalAuditGapSummaryV0
    ) throws {
        guard protocolVersion == .init() else {
            throw LocalAuditHistoryMessageErrorV0.invalidVersion
        }
        let boundsArePaired = (oldestVisibleSequence == nil)
            == (newestVisibleSequence == nil)
        let boundsAreValid: Bool
        if let oldestVisibleSequence, let newestVisibleSequence {
            boundsAreValid =
                (1...LocalAuditCodingV0.maximumSafeInteger).contains(
                    oldestVisibleSequence
                )
                && oldestVisibleSequence <= newestVisibleSequence
                && newestVisibleSequence <= LocalAuditCodingV0.maximumSafeInteger
        } else {
            boundsAreValid = boundsArePaired
        }
        var previous: UInt64?
        var orderingIsValid = true
        for event in events {
            if let previous, event.sequence >= previous {
                orderingIsValid = false
            }
            previous = event.sequence
        }
        let cursorIsValid = nextBeforeSequence.map {
            events.last?.sequence == $0
        } ?? true
        let eventsFitBounds = events.allSatisfy { event in
            guard let oldestVisibleSequence, let newestVisibleSequence else {
                return false
            }
            return (oldestVisibleSequence...newestVisibleSequence)
                .contains(event.sequence)
        }
        guard events.count <= 100,
              boundsArePaired,
              boundsAreValid,
              orderingIsValid,
              cursorIsValid,
              events.isEmpty ? nextBeforeSequence == nil : eventsFitBounds else {
            throw LocalAuditHistoryMessageErrorV0.invalidPage
        }
        self.protocolVersion = protocolVersion
        self.correlationID = correlationID
        self.events = events
        self.nextBeforeSequence = nextBeforeSequence
        self.oldestVisibleSequence = oldestVisibleSequence
        self.newestVisibleSequence = newestVisibleSequence
        self.gaps = gaps
    }

    public init(from decoder: Decoder) throws {
        try LocalAuditCodingV0.rejectUnknown(from: decoder, as: CodingKeys.self)
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            protocolVersion: values.decode(
                LocalIPCProtocolVersion.self,
                forKey: .protocolVersion
            ),
            correlationID: values.decode(UUID.self, forKey: .correlationID),
            events: values.decode([LocalAuditEventV0].self, forKey: .events),
            nextBeforeSequence: values.decodeIfPresent(
                UInt64.self,
                forKey: .nextBeforeSequence
            ),
            oldestVisibleSequence: values.decodeIfPresent(
                UInt64.self,
                forKey: .oldestVisibleSequence
            ),
            newestVisibleSequence: values.decodeIfPresent(
                UInt64.self,
                forKey: .newestVisibleSequence
            ),
            gaps: values.decode(LocalAuditGapSummaryV0.self, forKey: .gaps)
        )
    }

    public func validate(against request: LocalAuditPageRequestV0) throws {
        guard correlationID == request.requestID,
              events.count <= Int(request.limit),
              events.allSatisfy({ event in
                  request.beforeSequence.map { event.sequence < $0 } ?? true
              }) else {
            throw LocalAuditHistoryMessageErrorV0.invalidPage
        }
    }
}
