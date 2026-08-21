import CompanionAuthentication
import CompanionDomain
import CompanionWire
import Foundation

public enum SessionDescriptionWireMapper {
    public static func response(
        for proof: WireEnvelope<AuthProofBody>,
        principal: AuthenticatedDevicePrincipal,
        hostID: UUID,
        hostState: HostState,
        responseMessageID: UUID,
        sentAtUnixMilliseconds: Int64
    ) throws -> WireEnvelope<SessionDescriptionBody> {
        let body = try SessionDescriptionBody(
            hostID: WireUUID(hostID),
            deviceID: WireUUID(principal.deviceID),
            deviceState: principal.deviceState,
            authorizationEpoch: principal.authorizationEpoch,
            grantRevision: principal.grantRevision,
            policyRevision: principal.policyRevision,
            hostState: hostState,
            features: ["audit.readSelf", "status.snapshot"],
            serverTimeUnixMilliseconds: sentAtUnixMilliseconds
        )
        return try WireEnvelope(
            version: proof.version,
            messageID: WireUUID(responseMessageID),
            correlationID: proof.messageID,
            channel: .command,
            sentAtUnixMilliseconds: sentAtUnixMilliseconds,
            body: body
        )
    }
}
