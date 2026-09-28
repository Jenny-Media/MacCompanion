import CompanionDomain
import CompanionInteractiveShared
import CompanionWire
import Foundation

public enum InteractiveSurfaceTargetMessageErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidSequence
    case invalidName
    case invalidCandidate
    case invalidInventory
}

public struct InteractiveSurfaceTargetsRequestBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey {
        case interactiveSessionID, authorizationEpoch, sequence
    }

    public static let kind = WireMessageKind.interactiveSurfaceTargetsRequest
    public let interactiveSessionID: WireUUID
    public let authorizationEpoch: AuthorizationEpoch
    public let sequence: Int64

    public init(
        interactiveSessionID: WireUUID,
        authorizationEpoch: AuthorizationEpoch,
        sequence: Int64
    ) throws {
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.sequence = sequence
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            ["interactiveSessionID", "authorizationEpoch", "sequence"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interactiveSessionID = try container.decode(
            WireUUID.self,
            forKey: .interactiveSessionID
        )
        authorizationEpoch = try container.decode(
            AuthorizationEpoch.self,
            forKey: .authorizationEpoch
        )
        sequence = try container.decode(Int64.self, forKey: .sequence)
        try validate()
    }

    public func validate() throws {
        guard authorizationEpoch.rawValue >= 1,
              sequence >= 1,
              sequence <= WireLimits.maximumSafeInteger else {
            throw InteractiveSurfaceTargetMessageErrorV0.invalidSequence
        }
    }
}

public struct InteractiveSurfaceTargetCandidateV0:
    Codable,
    Equatable,
    Sendable
{
    private enum CodingKeys: String, CodingKey {
        case targetToken, kind, applicationToken, applicationName
        case windowOrdinal, currentWindowAvailable
    }

    public let targetToken: WireUUID
    public let kind: InteractiveSurfaceKind
    public let applicationToken: WireUUID
    public let applicationName: String
    public let windowOrdinal: Int64?
    public let currentWindowAvailable: Bool

    public init(
        targetToken: WireUUID,
        kind: InteractiveSurfaceKind,
        applicationToken: WireUUID,
        applicationName: String,
        windowOrdinal: Int64?,
        currentWindowAvailable: Bool
    ) throws {
        self.targetToken = targetToken
        self.kind = kind
        self.applicationToken = applicationToken
        self.applicationName = applicationName
        self.windowOrdinal = windowOrdinal
        self.currentWindowAvailable = currentWindowAvailable
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            [
                "targetToken", "kind", "applicationToken",
                "applicationName", "windowOrdinal",
                "currentWindowAvailable",
            ]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        targetToken = try container.decode(WireUUID.self, forKey: .targetToken)
        kind = try container.decode(InteractiveSurfaceKind.self, forKey: .kind)
        applicationToken = try container.decode(
            WireUUID.self,
            forKey: .applicationToken
        )
        applicationName = try container.decode(
            String.self,
            forKey: .applicationName
        )
        windowOrdinal = try container.decodeIfPresent(
            Int64.self,
            forKey: .windowOrdinal
        )
        currentWindowAvailable = try container.decode(
            Bool.self,
            forKey: .currentWindowAvailable
        )
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targetToken, forKey: .targetToken)
        try container.encode(kind, forKey: .kind)
        try container.encode(applicationToken, forKey: .applicationToken)
        try container.encode(applicationName, forKey: .applicationName)
        if let windowOrdinal {
            try container.encode(windowOrdinal, forKey: .windowOrdinal)
        } else {
            try container.encodeNil(forKey: .windowOrdinal)
        }
        try container.encode(
            currentWindowAvailable,
            forKey: .currentWindowAvailable
        )
    }

    public func validate() throws {
        guard !applicationName.isEmpty,
              applicationName.utf8.count <= 128,
              applicationName.unicodeScalars.allSatisfy({ scalar in
                  scalar.value >= 0x20
                      && scalar.value != 0x7f
                      && scalar.value != 0x2028
                      && scalar.value != 0x2029
              }) else {
            throw InteractiveSurfaceTargetMessageErrorV0.invalidName
        }
        switch kind {
        case .application:
            guard targetToken == applicationToken,
                  windowOrdinal == nil else {
                throw InteractiveSurfaceTargetMessageErrorV0.invalidCandidate
            }
        case .window:
            guard targetToken != applicationToken,
                  let windowOrdinal,
                  (1...64).contains(windowOrdinal) else {
                throw InteractiveSurfaceTargetMessageErrorV0.invalidCandidate
            }
        case .desktop, .focusedRegion:
            throw InteractiveSurfaceTargetMessageErrorV0.invalidCandidate
        }
    }
}

public struct InteractiveSurfaceTargetsResponseBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey {
        case interactiveSessionID, authorizationEpoch, inventoryRevision
        case validForMilliseconds, candidates, sequence
    }

    public static let kind = WireMessageKind.interactiveSurfaceTargetsResponse
    public let interactiveSessionID: WireUUID
    public let authorizationEpoch: AuthorizationEpoch
    public let inventoryRevision: Int64
    public let validForMilliseconds: Int64
    public let candidates: [InteractiveSurfaceTargetCandidateV0]
    public let sequence: Int64

    public init(
        interactiveSessionID: WireUUID,
        authorizationEpoch: AuthorizationEpoch,
        inventoryRevision: Int64,
        validForMilliseconds: Int64,
        candidates: [InteractiveSurfaceTargetCandidateV0],
        sequence: Int64
    ) throws {
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.inventoryRevision = inventoryRevision
        self.validForMilliseconds = validForMilliseconds
        self.candidates = candidates
        self.sequence = sequence
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            [
                "interactiveSessionID", "authorizationEpoch",
                "inventoryRevision", "validForMilliseconds", "candidates",
                "sequence",
            ]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interactiveSessionID = try container.decode(
            WireUUID.self,
            forKey: .interactiveSessionID
        )
        authorizationEpoch = try container.decode(
            AuthorizationEpoch.self,
            forKey: .authorizationEpoch
        )
        inventoryRevision = try container.decode(
            Int64.self,
            forKey: .inventoryRevision
        )
        validForMilliseconds = try container.decode(
            Int64.self,
            forKey: .validForMilliseconds
        )
        candidates = try container.decode(
            [InteractiveSurfaceTargetCandidateV0].self,
            forKey: .candidates
        )
        sequence = try container.decode(Int64.self, forKey: .sequence)
        try validate()
    }

    public func validate() throws {
        try candidates.forEach { try $0.validate() }
        guard authorizationEpoch.rawValue >= 1,
              inventoryRevision >= 1,
              inventoryRevision <= WireLimits.maximumSafeInteger,
              (1...AdaptiveSurfaceTargetInventoryV0.maximumLifetimeMilliseconds)
                .contains(validForMilliseconds),
              candidates.count <= 192,
              sequence >= 1,
              sequence <= WireLimits.maximumSafeInteger,
              Set(candidates.map(\.targetToken)).count == candidates.count,
              candidates == candidates.sorted(by: Self.precedes) else {
            throw InteractiveSurfaceTargetMessageErrorV0.invalidInventory
        }
        let applications = Set(
            candidates.lazy.filter { $0.kind == .application }
                .map(\.targetToken)
        )
        guard candidates.allSatisfy({ candidate in
            candidate.kind == .application
                || applications.contains(candidate.applicationToken)
        }) else {
            throw InteractiveSurfaceTargetMessageErrorV0.invalidInventory
        }
    }

    private static func precedes(
        _ lhs: InteractiveSurfaceTargetCandidateV0,
        _ rhs: InteractiveSurfaceTargetCandidateV0
    ) -> Bool {
        let leftName = lhs.applicationName.unicodeScalars.map(\.value)
        let rightName = rhs.applicationName.unicodeScalars.map(\.value)
        if leftName != rightName {
            return leftName.lexicographicallyPrecedes(rightName)
        }
        if lhs.kind != rhs.kind {
            return lhs.kind == .application
        }
        if lhs.windowOrdinal != rhs.windowOrdinal {
            return (lhs.windowOrdinal ?? 0) < (rhs.windowOrdinal ?? 0)
        }
        return lhs.targetToken.description < rhs.targetToken.description
    }
}
