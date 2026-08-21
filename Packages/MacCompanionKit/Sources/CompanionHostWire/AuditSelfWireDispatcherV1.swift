import CompanionAuthentication
import CompanionDomain
import CompanionPersistence
import CompanionWire
import Foundation

public enum AuditSelfWireDispatcherErrorV1: Error, Equatable, Sendable {
    case stalePrincipal
    case notGranted
    case unmappableRecord
}

public protocol AuditSelfGrantSnapshotReadingV1: Sendable {
    func deviceGrantSnapshot(
        _ deviceID: UUID
    ) async throws -> StoredDeviceGrantSnapshot
}

extension SQLiteSecurityStore: AuditSelfGrantSnapshotReadingV1 {}

public actor AuditSelfWireDispatcherV1 {
    public static let capabilityID = "audit.readSelf"

    private let securityStore: any AuditSelfGrantSnapshotReadingV1
    private let auditStore: SQLiteBoundedAuditStoreV0

    public init(
        securityStore: any AuditSelfGrantSnapshotReadingV1,
        auditStore: SQLiteBoundedAuditStoreV0
    ) {
        self.securityStore = securityStore
        self.auditStore = auditStore
    }

    public func dispatch(
        requestJSON: Data,
        principal: AuthenticatedDevicePrincipal,
        responseMessageID: WireUUID,
        sentAtUnixMilliseconds: Int64
    ) async throws -> Data {
        let request = try WireCodec.decode(
            WireEnvelope<AuditListRequestBodyV1>.self,
            from: requestJSON
        )
        do {
            let grant = try await securityStore.deviceGrantSnapshot(
                principal.deviceID
            )
            guard grant.device.clientID == principal.clientID,
                  grant.device.authorization.state == principal.deviceState,
                  grant.device.authorization.authorizationEpoch
                    == principal.authorizationEpoch,
                  grant.device.authorization.grantRevision
                    == principal.grantRevision,
                  grant.device.policyRevision == principal.policyRevision else {
                throw AuditSelfWireDispatcherErrorV1.stalePrincipal
            }
            guard principal.deviceState == .activeGranted,
                  grant.grants.capabilityIDs.contains(Self.capabilityID) else {
                throw AuditSelfWireDispatcherErrorV1.notGranted
            }
            let page = try await auditStore.page(
                scope: .requestingDevice(principal.deviceID),
                beforeSequence: request.body.beforeSequence.map(UInt64.init),
                limit: Int(request.body.limit)
            )
            return try WireCodec.encode(WireEnvelope(
                version: request.version,
                messageID: responseMessageID,
                correlationID: request.messageID,
                sentAtUnixMilliseconds: sentAtUnixMilliseconds,
                body: try Self.map(page)
            ))
        } catch AuditSelfWireDispatcherErrorV1.notGranted,
                AuditSelfWireDispatcherErrorV1.stalePrincipal {
            return try safeError(
                request: request,
                responseMessageID: responseMessageID,
                sentAtUnixMilliseconds: sentAtUnixMilliseconds,
                body: ProtocolErrorResponseBody(
                    code: "policy.denied",
                    retry: .afterUserAction,
                    safeArguments: .object([
                        .init(
                            key: "capabilityID",
                            value: .string(Self.capabilityID)
                        ),
                    ])
                )
            )
        } catch is AuditStoreErrorV0 {
            return try safeError(
                request: request,
                responseMessageID: responseMessageID,
                sentAtUnixMilliseconds: sentAtUnixMilliseconds,
                body: ProtocolErrorResponseBody(
                    code: "storage.securityUnavailable",
                    retry: .afterUserAction,
                    safeArguments: .object([
                        .init(
                            key: "recovery",
                            value: .string("localRepair")
                        ),
                    ])
                )
            )
        }
    }

    private func safeError(
        request: WireEnvelope<AuditListRequestBodyV1>,
        responseMessageID: WireUUID,
        sentAtUnixMilliseconds: Int64,
        body: ProtocolErrorResponseBody
    ) throws -> Data {
        try WireCodec.encode(WireEnvelope(
            version: request.version,
            messageID: responseMessageID,
            correlationID: request.messageID,
            sentAtUnixMilliseconds: sentAtUnixMilliseconds,
            body: body
        ))
    }

    public static func map(
        _ page: AuditPageV0
    ) throws -> AuditListResponseBodyV1 {
        try AuditListResponseBodyV1(
            events: page.events.map(map),
            nextBeforeSequence: try signed(page.nextBeforeSequence),
            oldestVisibleSequence: try signed(page.oldestVisibleSequence),
            newestVisibleSequence: try signed(page.newestVisibleSequence),
            gaps: AuditGapWireV1(
                prunedThroughSequence: try signed(
                    page.gaps.prunedThroughSequence
                ),
                droppedEventCount: try requireSigned(
                    page.gaps.droppedEventCount
                )
            )
        )
    }

    private static func map(
        _ event: StoredAuditEventV0
    ) throws -> AuditSelfEventWireV1 {
        let value = event.draft
        let scope: AuditSelfEventScopeWireV1 = switch value.visibility {
        case .subjectDevice: .selfDevice
        case .allPairedDevices: .host
        case .localOnly:
            throw AuditSelfWireDispatcherErrorV1.unmappableRecord
        }
        guard let actor = AuditActorWireV1(rawValue: value.actor.rawValue),
              let code = AuditEventCodeWireV1(rawValue: value.code.rawValue) else {
            throw AuditSelfWireDispatcherErrorV1.unmappableRecord
        }
        return try AuditSelfEventWireV1(
            sequence: try requireSigned(event.sequence),
            eventID: WireUUID(value.eventID),
            observedAtUnixMilliseconds: value.observedAtUnixMilliseconds,
            scope: scope,
            actor: actor,
            code: code,
            correlationID: value.correlationID.map(WireUUID.init),
            operationID: value.operationID.map(WireUUID.init),
            interactiveSessionID: value.interactiveSessionID.map(WireUUID.init),
            capabilityID: value.capabilityID,
            policyRevision: try signed(value.policyRevision?.rawValue),
            authorizationEpoch: try signed(
                value.authorizationEpoch?.rawValue
            ),
            grantRevision: try signed(value.grantRevision?.rawValue),
            routeClass: try map(value.routeClass, as: AuditRouteClassWireV1.self),
            surfaceKind: try map(
                value.surfaceKind,
                as: AuditSurfaceKindWireV1.self
            ),
            outcome: try map(value.outcome, as: AuditOutcomeWireV1.self)
        )
    }

    private static func map<Source, Destination>(
        _ source: Source?,
        as type: Destination.Type
    ) throws -> Destination?
        where Source: RawRepresentable,
              Destination: RawRepresentable,
              Source.RawValue == String,
              Destination.RawValue == String {
        guard let source else { return nil }
        guard let mapped = Destination(rawValue: source.rawValue) else {
            throw AuditSelfWireDispatcherErrorV1.unmappableRecord
        }
        return mapped
    }

    private static func signed(_ value: UInt64?) throws -> Int64? {
        guard let value else { return nil }
        return try requireSigned(value)
    }

    private static func requireSigned(_ value: UInt64) throws -> Int64 {
        guard value <= UInt64(WireLimits.maximumSafeInteger) else {
            throw AuditSelfWireDispatcherErrorV1.unmappableRecord
        }
        return Int64(value)
    }
}
