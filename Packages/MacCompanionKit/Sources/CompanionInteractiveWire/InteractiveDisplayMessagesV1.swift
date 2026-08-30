import CompanionDomain
import CompanionWire
import Foundation

public enum InteractiveDisplayMessageErrorV1:
    Error, Equatable, Sendable
{
    case invalidAuthorization
    case invalidRevision
    case invalidDisplay
    case invalidCatalog
}

public struct InteractiveDisplayCatalogRequestBodyV1: WireBody {
    private enum CodingKeys: String, CodingKey {
        case authorizationEpoch
    }

    public static let kind =
        WireMessageKind.interactiveDisplayCatalogRequest
    public let authorizationEpoch: AuthorizationEpoch

    public init(authorizationEpoch: AuthorizationEpoch) throws {
        self.authorizationEpoch = authorizationEpoch
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["authorizationEpoch"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authorizationEpoch = try container.decode(
            AuthorizationEpoch.self,
            forKey: .authorizationEpoch
        )
        try validate()
    }

    public func validate() throws {
        guard authorizationEpoch.rawValue >= 1 else {
            throw InteractiveDisplayMessageErrorV1.invalidAuthorization
        }
    }
}

public struct InteractiveDisplayCandidateV1:
    Codable, Equatable, Identifiable, Sendable
{
    private enum CodingKeys: String, CodingKey {
        case displayID, ordinal, pixelWidth, pixelHeight, isMain
    }

    public let displayID: WireUUID
    public let ordinal: UInt8
    public let pixelWidth: UInt16
    public let pixelHeight: UInt16
    public let isMain: Bool

    public var id: UUID { displayID.rawValue }

    public init(
        displayID: WireUUID,
        ordinal: UInt8,
        pixelWidth: UInt16,
        pixelHeight: UInt16,
        isMain: Bool
    ) throws {
        self.displayID = displayID
        self.ordinal = ordinal
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.isMain = isMain
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            ["displayID", "ordinal", "pixelWidth", "pixelHeight", "isMain"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayID = try container.decode(WireUUID.self, forKey: .displayID)
        ordinal = try container.decode(UInt8.self, forKey: .ordinal)
        pixelWidth = try container.decode(UInt16.self, forKey: .pixelWidth)
        pixelHeight = try container.decode(UInt16.self, forKey: .pixelHeight)
        isMain = try container.decode(Bool.self, forKey: .isMain)
        try validate()
    }

    public func validate() throws {
        guard ordinal >= 1,
              pixelWidth > 0,
              pixelHeight > 0 else {
            throw InteractiveDisplayMessageErrorV1.invalidDisplay
        }
    }
}

public struct InteractiveDisplayCatalogResponseBodyV1: WireBody {
    private enum CodingKeys: String, CodingKey {
        case authorizationEpoch, admissionRevision, selectedDisplayID
        case validForMilliseconds, displays
    }

    public static let kind =
        WireMessageKind.interactiveDisplayCatalogResponse
    public let authorizationEpoch: AuthorizationEpoch
    public let admissionRevision: Int64
    public let selectedDisplayID: WireUUID
    public let validForMilliseconds: Int64
    public let displays: [InteractiveDisplayCandidateV1]

    public init(
        authorizationEpoch: AuthorizationEpoch,
        admissionRevision: Int64,
        selectedDisplayID: WireUUID,
        validForMilliseconds: Int64,
        displays: [InteractiveDisplayCandidateV1]
    ) throws {
        self.authorizationEpoch = authorizationEpoch
        self.admissionRevision = admissionRevision
        self.selectedDisplayID = selectedDisplayID
        self.validForMilliseconds = validForMilliseconds
        self.displays = displays
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            [
                "authorizationEpoch", "admissionRevision",
                "selectedDisplayID", "validForMilliseconds", "displays",
            ]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authorizationEpoch = try container.decode(
            AuthorizationEpoch.self,
            forKey: .authorizationEpoch
        )
        admissionRevision = try container.decode(
            Int64.self,
            forKey: .admissionRevision
        )
        selectedDisplayID = try container.decode(
            WireUUID.self,
            forKey: .selectedDisplayID
        )
        validForMilliseconds = try container.decode(
            Int64.self,
            forKey: .validForMilliseconds
        )
        displays = try container.decode(
            [InteractiveDisplayCandidateV1].self,
            forKey: .displays
        )
        try validate()
    }

    public func validate() throws {
        guard authorizationEpoch.rawValue >= 1,
              (1...WireLimits.maximumSafeInteger).contains(admissionRevision),
              (1...10_000).contains(validForMilliseconds),
              (1...16).contains(displays.count),
              Set(displays.map(\.displayID)).count == displays.count,
              Set(displays.map(\.ordinal)).count == displays.count,
              displays.contains(where: { $0.displayID == selectedDisplayID }),
              displays.filter(\.isMain).count <= 1 else {
            throw InteractiveDisplayMessageErrorV1.invalidCatalog
        }
        try displays.forEach { try $0.validate() }
    }
}

public struct InteractiveDisplaySelectBodyV1: WireBody {
    private enum CodingKeys: String, CodingKey {
        case authorizationEpoch, expectedAdmissionRevision, displayID
    }

    public static let kind = WireMessageKind.interactiveDisplaySelect
    public let authorizationEpoch: AuthorizationEpoch
    public let expectedAdmissionRevision: Int64
    public let displayID: WireUUID

    public init(
        authorizationEpoch: AuthorizationEpoch,
        expectedAdmissionRevision: Int64,
        displayID: WireUUID
    ) throws {
        self.authorizationEpoch = authorizationEpoch
        self.expectedAdmissionRevision = expectedAdmissionRevision
        self.displayID = displayID
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            ["authorizationEpoch", "expectedAdmissionRevision", "displayID"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authorizationEpoch = try container.decode(
            AuthorizationEpoch.self,
            forKey: .authorizationEpoch
        )
        expectedAdmissionRevision = try container.decode(
            Int64.self,
            forKey: .expectedAdmissionRevision
        )
        displayID = try container.decode(WireUUID.self, forKey: .displayID)
        try validate()
    }

    public func validate() throws {
        guard authorizationEpoch.rawValue >= 1 else {
            throw InteractiveDisplayMessageErrorV1.invalidAuthorization
        }
        guard (1...WireLimits.maximumSafeInteger)
                .contains(expectedAdmissionRevision) else {
            throw InteractiveDisplayMessageErrorV1.invalidRevision
        }
    }
}

public struct InteractiveDisplaySelectedBodyV1: WireBody {
    private enum CodingKeys: String, CodingKey {
        case authorizationEpoch, admissionRevision, selectedDisplayID
    }

    public static let kind = WireMessageKind.interactiveDisplaySelected
    public let authorizationEpoch: AuthorizationEpoch
    public let admissionRevision: Int64
    public let selectedDisplayID: WireUUID

    public init(
        authorizationEpoch: AuthorizationEpoch,
        admissionRevision: Int64,
        selectedDisplayID: WireUUID
    ) throws {
        self.authorizationEpoch = authorizationEpoch
        self.admissionRevision = admissionRevision
        self.selectedDisplayID = selectedDisplayID
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            ["authorizationEpoch", "admissionRevision", "selectedDisplayID"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        authorizationEpoch = try container.decode(
            AuthorizationEpoch.self,
            forKey: .authorizationEpoch
        )
        admissionRevision = try container.decode(
            Int64.self,
            forKey: .admissionRevision
        )
        selectedDisplayID = try container.decode(
            WireUUID.self,
            forKey: .selectedDisplayID
        )
        try validate()
    }

    public func validate() throws {
        guard authorizationEpoch.rawValue >= 1 else {
            throw InteractiveDisplayMessageErrorV1.invalidAuthorization
        }
        guard (1...WireLimits.maximumSafeInteger).contains(admissionRevision)
        else {
            throw InteractiveDisplayMessageErrorV1.invalidRevision
        }
    }
}
