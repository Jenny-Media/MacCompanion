import CompanionDomain
import Foundation

public enum PowerSource: String, Codable, Sendable {
    case ac
    case battery
    case unknown
}

public struct StatusSnapshotRequestBody: WireBody {
    public static let kind = WireMessageKind.statusSnapshotRequest

    public init() {}

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, [])
    }

    public func validate() throws {}
}

public struct SessionDescriptionBody: WireBody {
    private enum CodingKeys: String, CodingKey {
        case hostID
        case deviceID
        case deviceState
        case authorizationEpoch
        case grantRevision
        case policyRevision
        case hostState
        case features
        case serverTimeUnixMilliseconds
    }

    public static let kind = WireMessageKind.sessionDescribeResponse

    public let hostID: WireUUID
    public let deviceID: WireUUID
    public let deviceState: DeviceAuthorizationState
    public let authorizationEpoch: AuthorizationEpoch
    public let grantRevision: GrantRevision
    public let policyRevision: PolicyRevision
    public let hostState: HostState
    public let features: [String]
    public let serverTimeUnixMilliseconds: Int64

    public init(
        hostID: WireUUID,
        deviceID: WireUUID,
        deviceState: DeviceAuthorizationState,
        authorizationEpoch: AuthorizationEpoch,
        grantRevision: GrantRevision,
        policyRevision: PolicyRevision,
        hostState: HostState,
        features: [String],
        serverTimeUnixMilliseconds: Int64
    ) throws {
        self.hostID = hostID
        self.deviceID = deviceID
        self.deviceState = deviceState
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.policyRevision = policyRevision
        self.hostState = hostState
        self.features = features
        self.serverTimeUnixMilliseconds = serverTimeUnixMilliseconds
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            [
                "hostID", "deviceID", "deviceState", "authorizationEpoch",
                "grantRevision", "policyRevision", "hostState", "features",
                "serverTimeUnixMilliseconds",
            ]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hostID = try container.decode(WireUUID.self, forKey: .hostID)
        deviceID = try container.decode(WireUUID.self, forKey: .deviceID)
        deviceState = try container.decode(DeviceAuthorizationState.self, forKey: .deviceState)
        authorizationEpoch = try container.decode(AuthorizationEpoch.self, forKey: .authorizationEpoch)
        grantRevision = try container.decode(GrantRevision.self, forKey: .grantRevision)
        policyRevision = try container.decode(PolicyRevision.self, forKey: .policyRevision)
        hostState = try container.decode(HostState.self, forKey: .hostState)
        features = try container.decode([String].self, forKey: .features)
        serverTimeUnixMilliseconds = try container.decode(Int64.self, forKey: .serverTimeUnixMilliseconds)
        try validate()
    }

    public func validate() throws {
        guard deviceState == .activeMonitorOnly || deviceState == .activeGranted else {
            throw WireError.invalidFrame(reason: "unauthenticated device state in session description")
        }
        guard authorizationEpoch.rawValue >= 1,
              grantRevision.rawValue >= 1,
              policyRevision.rawValue >= 1 else {
            throw WireError.invalidFrame(reason: "zero security revision")
        }
        guard features.count <= 32,
              features == features.sorted(),
              Set(features).count == features.count,
              features.allSatisfy({
                  $0 == "audit.readSelf"
                      || $0 == "interactive.control.v0.1"
                      || $0 == "status.snapshot"
              }) else {
            throw WireError.invalidFrame(reason: "invalid feature registry")
        }
        guard serverTimeUnixMilliseconds >= 0,
              serverTimeUnixMilliseconds <= WireLimits.maximumSafeInteger else {
            throw WireError.boundsExceeded(
                field: "serverTimeUnixMilliseconds",
                limit: Int(WireLimits.maximumSafeInteger)
            )
        }
    }
}

public struct SystemOverview: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case osName
        case osVersion
        case osBuild
        case uptimeSeconds
        case cpuUtilizationBasisPoints
        case memoryTotalBytes
        case memoryUsedBytes
        case storageTotalBytes
        case storageAvailableBytes
        case powerSource
        case batteryLevelPercent
    }

    public let osName: String
    public let osVersion: String
    public let osBuild: String
    public let uptimeSeconds: Int64
    public let cpuUtilizationBasisPoints: UInt16
    public let memoryTotalBytes: Int64
    public let memoryUsedBytes: Int64
    public let storageTotalBytes: Int64
    public let storageAvailableBytes: Int64
    public let powerSource: PowerSource
    public let batteryLevelPercent: UInt8?

    public init(
        osName: String,
        osVersion: String,
        osBuild: String,
        uptimeSeconds: Int64,
        cpuUtilizationBasisPoints: UInt16,
        memoryTotalBytes: Int64,
        memoryUsedBytes: Int64,
        storageTotalBytes: Int64,
        storageAvailableBytes: Int64,
        powerSource: PowerSource,
        batteryLevelPercent: UInt8?
    ) throws {
        self.osName = osName
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.uptimeSeconds = uptimeSeconds
        self.cpuUtilizationBasisPoints = cpuUtilizationBasisPoints
        self.memoryTotalBytes = memoryTotalBytes
        self.memoryUsedBytes = memoryUsedBytes
        self.storageTotalBytes = storageTotalBytes
        self.storageAvailableBytes = storageAvailableBytes
        self.powerSource = powerSource
        self.batteryLevelPercent = batteryLevelPercent
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            [
                "osName", "osVersion", "osBuild", "uptimeSeconds",
                "cpuUtilizationBasisPoints", "memoryTotalBytes", "memoryUsedBytes",
                "storageTotalBytes", "storageAvailableBytes", "powerSource",
                "batteryLevelPercent",
            ]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        osName = try container.decode(String.self, forKey: .osName)
        osVersion = try container.decode(String.self, forKey: .osVersion)
        osBuild = try container.decode(String.self, forKey: .osBuild)
        uptimeSeconds = try container.decode(Int64.self, forKey: .uptimeSeconds)
        cpuUtilizationBasisPoints = try container.decode(UInt16.self, forKey: .cpuUtilizationBasisPoints)
        memoryTotalBytes = try container.decode(Int64.self, forKey: .memoryTotalBytes)
        memoryUsedBytes = try container.decode(Int64.self, forKey: .memoryUsedBytes)
        storageTotalBytes = try container.decode(Int64.self, forKey: .storageTotalBytes)
        storageAvailableBytes = try container.decode(Int64.self, forKey: .storageAvailableBytes)
        powerSource = try container.decode(PowerSource.self, forKey: .powerSource)
        batteryLevelPercent = try container.decodeIfPresent(UInt8.self, forKey: .batteryLevelPercent)
        try validate(codingPath: decoder.codingPath)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(osName, forKey: .osName)
        try container.encode(osVersion, forKey: .osVersion)
        try container.encode(osBuild, forKey: .osBuild)
        try container.encode(uptimeSeconds, forKey: .uptimeSeconds)
        try container.encode(cpuUtilizationBasisPoints, forKey: .cpuUtilizationBasisPoints)
        try container.encode(memoryTotalBytes, forKey: .memoryTotalBytes)
        try container.encode(memoryUsedBytes, forKey: .memoryUsedBytes)
        try container.encode(storageTotalBytes, forKey: .storageTotalBytes)
        try container.encode(storageAvailableBytes, forKey: .storageAvailableBytes)
        try container.encode(powerSource, forKey: .powerSource)
        if let batteryLevelPercent {
            try container.encode(batteryLevelPercent, forKey: .batteryLevelPercent)
        } else {
            try container.encodeNil(forKey: .batteryLevelPercent)
        }
    }

    func validate(codingPath: [CodingKey] = []) throws {
        guard osName == "macOS",
              (1...32).contains(osVersion.utf8.count),
              (1...32).contains(osBuild.utf8.count) else {
            throw WireError.invalidFrame(reason: "invalid OS identity")
        }
        guard uptimeSeconds >= 0,
              uptimeSeconds <= WireLimits.maximumSafeInteger,
              cpuUtilizationBasisPoints <= 10_000,
              memoryTotalBytes > 0,
              memoryUsedBytes >= 0,
              memoryUsedBytes <= memoryTotalBytes,
              storageTotalBytes > 0,
              storageAvailableBytes >= 0,
              storageAvailableBytes <= storageTotalBytes,
              memoryTotalBytes <= WireLimits.maximumSafeInteger,
              storageTotalBytes <= WireLimits.maximumSafeInteger,
              batteryLevelPercent.map({ $0 <= 100 }) ?? true else {
            throw WireError.boundsExceeded(field: "system", limit: Int(WireLimits.maximumSafeInteger))
        }
    }
}

public struct StatusSnapshotBody: WireBody {
    private enum CodingKeys: String, CodingKey {
        case hostID
        case resourceID
        case generation
        case revision
        case observedAtUnixMilliseconds
        case validForMilliseconds
        case hostState
        case system
    }

    public static let kind = WireMessageKind.statusSnapshotResponse

    public let hostID: WireUUID
    public let resourceID: String
    public let generation: WireUUID
    public let revision: Int64
    public let observedAtUnixMilliseconds: Int64
    public let validForMilliseconds: UInt32
    public let hostState: HostState
    public let system: SystemOverview

    public init(
        hostID: WireUUID,
        resourceID: String = "host.status",
        generation: WireUUID,
        revision: Int64,
        observedAtUnixMilliseconds: Int64,
        validForMilliseconds: UInt32,
        hostState: HostState,
        system: SystemOverview
    ) throws {
        self.hostID = hostID
        self.resourceID = resourceID
        self.generation = generation
        self.revision = revision
        self.observedAtUnixMilliseconds = observedAtUnixMilliseconds
        self.validForMilliseconds = validForMilliseconds
        self.hostState = hostState
        self.system = system
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            [
                "hostID", "resourceID", "generation", "revision",
                "observedAtUnixMilliseconds", "validForMilliseconds",
                "hostState", "system",
            ]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hostID = try container.decode(WireUUID.self, forKey: .hostID)
        resourceID = try container.decode(String.self, forKey: .resourceID)
        generation = try container.decode(WireUUID.self, forKey: .generation)
        revision = try container.decode(Int64.self, forKey: .revision)
        observedAtUnixMilliseconds = try container.decode(Int64.self, forKey: .observedAtUnixMilliseconds)
        validForMilliseconds = try container.decode(UInt32.self, forKey: .validForMilliseconds)
        hostState = try container.decode(HostState.self, forKey: .hostState)
        system = try container.decode(SystemOverview.self, forKey: .system)
        try validate()
    }

    public func validate() throws {
        guard resourceID == "host.status" else {
            throw WireError.invalidFrame(reason: "invalid status resource ID")
        }
        guard revision >= 0, revision <= WireLimits.maximumSafeInteger,
              observedAtUnixMilliseconds >= 0,
              observedAtUnixMilliseconds <= WireLimits.maximumSafeInteger,
              (1...60_000).contains(validForMilliseconds) else {
            throw WireError.boundsExceeded(field: "statusSnapshot", limit: 60_000)
        }
        try system.validate()
    }
}
