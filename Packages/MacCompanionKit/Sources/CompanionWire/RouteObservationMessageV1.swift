import Foundation

public enum ConfiguredRouteClassV1: String, Codable, Sendable {
    case privateDNS
    case privateNetwork
}

public struct RouteObservationBodyV1: WireBody {
    public static let kind = WireMessageKind.routeObservation

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case connectionID
        case configuredRouteID
        case routeClass
        case observationSequence
    }

    public let connectionID: WireBytes16
    public let configuredRouteID: WireBytes16
    public let routeClass: ConfiguredRouteClassV1
    public let observationSequence: Int64

    public init(
        connectionID: WireBytes16,
        configuredRouteID: WireBytes16,
        routeClass: ConfiguredRouteClassV1,
        observationSequence: Int64
    ) throws {
        self.connectionID = connectionID
        self.configuredRouteID = configuredRouteID
        self.routeClass = routeClass
        self.observationSequence = observationSequence
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        connectionID = try container.decode(
            WireBytes16.self,
            forKey: .connectionID
        )
        configuredRouteID = try container.decode(
            WireBytes16.self,
            forKey: .configuredRouteID
        )
        routeClass = try container.decode(
            ConfiguredRouteClassV1.self,
            forKey: .routeClass
        )
        observationSequence = try container.decode(
            Int64.self,
            forKey: .observationSequence
        )
        try validate()
    }

    public func validate() throws {
        guard (1...WireLimits.maximumSafeInteger).contains(
            observationSequence
        ) else {
            throw WireError.invalidFrame(
                reason: "invalid route observation sequence"
            )
        }
    }
}

public struct RouteObservationAcknowledgementBodyV1: WireBody {
    public static let kind = WireMessageKind.routeObservationAck
    public static let requiredValidForMilliseconds: Int64 = 30_000

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case connectionID
        case configuredRouteID
        case routeClass
        case observationSequence
        case validForMilliseconds
    }

    public let connectionID: WireBytes16
    public let configuredRouteID: WireBytes16
    public let routeClass: ConfiguredRouteClassV1
    public let observationSequence: Int64
    public let validForMilliseconds: Int64

    public init(
        connectionID: WireBytes16,
        configuredRouteID: WireBytes16,
        routeClass: ConfiguredRouteClassV1,
        observationSequence: Int64
    ) throws {
        self.connectionID = connectionID
        self.configuredRouteID = configuredRouteID
        self.routeClass = routeClass
        self.observationSequence = observationSequence
        validForMilliseconds = Self.requiredValidForMilliseconds
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        connectionID = try container.decode(
            WireBytes16.self,
            forKey: .connectionID
        )
        configuredRouteID = try container.decode(
            WireBytes16.self,
            forKey: .configuredRouteID
        )
        routeClass = try container.decode(
            ConfiguredRouteClassV1.self,
            forKey: .routeClass
        )
        observationSequence = try container.decode(
            Int64.self,
            forKey: .observationSequence
        )
        validForMilliseconds = try container.decode(
            Int64.self,
            forKey: .validForMilliseconds
        )
        try validate()
    }

    public func validate() throws {
        guard (1...WireLimits.maximumSafeInteger).contains(
            observationSequence
        ), validForMilliseconds == Self.requiredValidForMilliseconds else {
            throw WireError.invalidFrame(
                reason: "invalid route observation acknowledgement"
            )
        }
    }
}
