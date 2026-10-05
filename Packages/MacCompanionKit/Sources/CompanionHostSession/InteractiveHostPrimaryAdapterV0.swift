import CompanionInteractiveHost
import CompanionWire
import Foundation

extension InteractiveSessionWireDispatcherV0: AuthenticatedInteractiveWireDispatchingV0 {
    public func authorizeDesktop(sessionID: UUID, context: AuthenticatedInteractiveCommandContextV0) async throws {
        try await authorizeDesktop(sessionID: sessionID, context: InteractiveSessionCommandContextV0(
            deviceID: context.principal.deviceID, clientID: context.principal.clientID,
            deviceState: context.principal.deviceState, authorizationEpoch: context.principal.authorizationEpoch,
            grantRevision: context.principal.grantRevision, policyRevision: context.principal.policyRevision,
            primaryConnectionID: context.primaryConnectionID, hostID: context.hostID,
            hostFingerprint: context.hostFingerprint, hostState: context.hostState,
            wallNowUnixMilliseconds: context.wallNowUnixMilliseconds, monotonicNowMilliseconds: context.monotonicNowMilliseconds))
    }

    public func dispatch(
        requestJSON: Data,
        context: AuthenticatedInteractiveCommandContextV0,
        responseMessageID: WireUUID
    ) async throws -> Data {
        try await dispatch(
            requestJSON: requestJSON,
            context: InteractiveSessionCommandContextV0(
                deviceID: context.principal.deviceID,
                clientID: context.principal.clientID,
                deviceState: context.principal.deviceState,
                authorizationEpoch: context.principal.authorizationEpoch,
                grantRevision: context.principal.grantRevision,
                policyRevision: context.principal.policyRevision,
                primaryConnectionID: context.primaryConnectionID,
                hostID: context.hostID,
                hostFingerprint: context.hostFingerprint,
                hostState: context.hostState,
                wallNowUnixMilliseconds: context.wallNowUnixMilliseconds,
                monotonicNowMilliseconds: context.monotonicNowMilliseconds
            ),
            responseMessageID: responseMessageID
        )
    }
}
