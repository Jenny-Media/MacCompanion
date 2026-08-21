import CompanionWire
import Foundation

public enum AuthenticatedRouteObservationSessionErrorV1:
    Error,
    Equatable,
    Sendable
{
    case closed
    case connectionMismatch
    case invalidTime
    case routeChanged
    case sequenceGap
    case sequenceReplay
}

public struct AuthenticatedRouteObservationSessionSnapshotV1:
    Equatable,
    Sendable
{
    public let connectionID: Data
    public let configuredRouteID: Data?
    public let routeClass: ConfiguredRouteClassV1?
    public let lastObservationSequence: Int64?
    public let freshThroughMonotonicMilliseconds: UInt64?
    public let closed: Bool
}

/// Connection-owned, non-authorizing route heartbeat state. The outer primary
/// session remains responsible for application authentication, replay-window
/// admission, principal revalidation, and closing this value on replacement.
public actor AuthenticatedRouteObservationSessionV1 {
    public static let freshnessWindowMilliseconds: UInt64 = 30_000

    private let connectionID: Data
    private var configuredRouteID: Data?
    private var boundRouteClass: ConfiguredRouteClassV1?
    private var publishedRouteClass: ConfiguredRouteClassV1?
    private var lastObservationSequence: Int64?
    private var freshThroughMonotonicMilliseconds: UInt64?
    private var lastAcceptedClockMilliseconds: UInt64?
    private var closed = false

    public init(connectionID: Data) throws {
        guard connectionID.count == 16 else {
            throw AuthenticatedRouteObservationSessionErrorV1
                .connectionMismatch
        }
        self.connectionID = connectionID
    }

    @discardableResult
    public func admit(
        _ body: RouteObservationBodyV1,
        hostMonotonicMilliseconds: UInt64
    ) throws -> AuthenticatedRouteObservationSessionSnapshotV1 {
        guard !closed else {
            throw AuthenticatedRouteObservationSessionErrorV1.closed
        }
        try validateClock(hostMonotonicMilliseconds)
        guard body.connectionID.rawValue == connectionID else {
            throw AuthenticatedRouteObservationSessionErrorV1
                .connectionMismatch
        }

        if let lastObservationSequence,
           let configuredRouteID,
           let boundRouteClass {
            guard body.observationSequence > lastObservationSequence else {
                throw AuthenticatedRouteObservationSessionErrorV1
                    .sequenceReplay
            }
            guard body.observationSequence == lastObservationSequence + 1 else {
                throw AuthenticatedRouteObservationSessionErrorV1.sequenceGap
            }
            guard body.configuredRouteID.rawValue == configuredRouteID,
                  body.routeClass == boundRouteClass else {
                throw AuthenticatedRouteObservationSessionErrorV1.routeChanged
            }
        } else {
            guard body.observationSequence == 1 else {
                throw AuthenticatedRouteObservationSessionErrorV1.sequenceGap
            }
            configuredRouteID = body.configuredRouteID.rawValue
            boundRouteClass = body.routeClass
        }

        lastObservationSequence = body.observationSequence
        publishedRouteClass = body.routeClass
        freshThroughMonotonicMilliseconds =
            hostMonotonicMilliseconds
                + Self.freshnessWindowMilliseconds
        lastAcceptedClockMilliseconds = hostMonotonicMilliseconds
        return currentSnapshot()
    }

    public func snapshot(
        hostMonotonicMilliseconds: UInt64
    ) throws -> AuthenticatedRouteObservationSessionSnapshotV1 {
        guard !closed else { return currentSnapshot() }
        try validateClock(hostMonotonicMilliseconds)
        if let deadline = freshThroughMonotonicMilliseconds,
           hostMonotonicMilliseconds > deadline {
            publishedRouteClass = nil
            freshThroughMonotonicMilliseconds = nil
        }
        lastAcceptedClockMilliseconds = hostMonotonicMilliseconds
        return currentSnapshot()
    }

    @discardableResult
    public func close() -> AuthenticatedRouteObservationSessionSnapshotV1 {
        closed = true
        publishedRouteClass = nil
        freshThroughMonotonicMilliseconds = nil
        return currentSnapshot()
    }

    public func acknowledgement(
        for request: WireEnvelope<RouteObservationBodyV1>,
        responseMessageID: WireUUID,
        sentAtUnixMilliseconds: Int64
    ) throws -> WireEnvelope<RouteObservationAcknowledgementBodyV1> {
        guard !closed,
              request.body.connectionID.rawValue == connectionID,
              request.body.configuredRouteID.rawValue == configuredRouteID,
              request.body.routeClass == boundRouteClass,
              request.body.observationSequence == lastObservationSequence else {
            throw AuthenticatedRouteObservationSessionErrorV1.routeChanged
        }
        return try WireEnvelope(
            version: request.version,
            messageID: responseMessageID,
            correlationID: request.messageID,
            sentAtUnixMilliseconds: sentAtUnixMilliseconds,
            body: RouteObservationAcknowledgementBodyV1(
                connectionID: request.body.connectionID,
                configuredRouteID: request.body.configuredRouteID,
                routeClass: request.body.routeClass,
                observationSequence: request.body.observationSequence
            )
        )
    }

    private func validateClock(_ value: UInt64) throws {
        guard value
                <= UInt64(Int64.max)
                    - Self.freshnessWindowMilliseconds,
              lastAcceptedClockMilliseconds.map({ value >= $0 }) ?? true
        else {
            throw AuthenticatedRouteObservationSessionErrorV1.invalidTime
        }
    }

    private func currentSnapshot()
        -> AuthenticatedRouteObservationSessionSnapshotV1
    {
        AuthenticatedRouteObservationSessionSnapshotV1(
            connectionID: connectionID,
            configuredRouteID: configuredRouteID,
            routeClass: publishedRouteClass,
            lastObservationSequence: lastObservationSequence,
            freshThroughMonotonicMilliseconds:
                freshThroughMonotonicMilliseconds,
            closed: closed
        )
    }
}
