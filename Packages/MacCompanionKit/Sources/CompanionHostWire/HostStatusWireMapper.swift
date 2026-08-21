import CompanionHost
import CompanionWire
import Foundation

public enum HostStatusWireMapper {
    public static func response(
        for request: WireEnvelope<StatusSnapshotRequestBody>,
        snapshot: HostStatusSnapshot,
        responseMessageID: UUID,
        sentAtUnixMilliseconds: Int64
    ) throws -> WireEnvelope<StatusSnapshotBody> {
        let body = try responseBody(from: snapshot)
        return try WireEnvelope(
            version: request.version,
            messageID: WireUUID(responseMessageID),
            correlationID: request.messageID,
            channel: .command,
            sentAtUnixMilliseconds: sentAtUnixMilliseconds,
            body: body
        )
    }

    public static func responseBody(
        from snapshot: HostStatusSnapshot
    ) throws -> StatusSnapshotBody {
        let system = snapshot.system
        return try StatusSnapshotBody(
            hostID: WireUUID(snapshot.hostID),
            generation: WireUUID(snapshot.generation),
            revision: try signedSafeInteger(snapshot.revision),
            observedAtUnixMilliseconds: snapshot.observedAtUnixMilliseconds,
            validForMilliseconds: snapshot.validForMilliseconds,
            hostState: snapshot.hostState,
            system: SystemOverview(
                osName: system.osName,
                osVersion: system.osVersion,
                osBuild: system.osBuild,
                uptimeSeconds: try signedSafeInteger(system.uptimeSeconds),
                cpuUtilizationBasisPoints: system.cpuUtilizationBasisPoints,
                memoryTotalBytes: try signedSafeInteger(system.memoryTotalBytes),
                memoryUsedBytes: try signedSafeInteger(system.memoryUsedBytes),
                storageTotalBytes: try signedSafeInteger(system.storageTotalBytes),
                storageAvailableBytes: try signedSafeInteger(system.storageAvailableBytes),
                powerSource: powerSource(system.powerSource),
                batteryLevelPercent: system.batteryLevelPercent
            )
        )
    }

    private static func signedSafeInteger(_ value: UInt64) throws -> Int64 {
        guard value <= UInt64(WireLimits.maximumSafeInteger) else {
            throw WireError.boundsExceeded(
                field: "hostStatusInteger",
                limit: Int(WireLimits.maximumSafeInteger)
            )
        }
        return Int64(value)
    }

    private static func powerSource(_ value: HostPowerSource) -> PowerSource {
        switch value {
        case .ac: .ac
        case .battery: .battery
        case .unknown: .unknown
        }
    }
}
