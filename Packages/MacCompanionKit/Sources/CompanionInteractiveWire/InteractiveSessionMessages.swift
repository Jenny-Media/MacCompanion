import CompanionDomain
import CompanionInteractiveShared
import CompanionSecurity
import CompanionWire
import Foundation

public enum InteractiveControlEffect: String, Codable, CaseIterable, Comparable, Sendable {
    case keyboard
    case pointer
    case text
    case view

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

private func validateEffects(_ effects: [InteractiveControlEffect]) throws {
    guard effects == effects.sorted(), Set(effects).count == effects.count,
          effects.contains(.view), !effects.contains(.text) || effects.contains(.keyboard) else {
        throw WireError.invalidFrame(reason: "invalid Interactive Control effects")
    }
}

public extension Array where Element == InteractiveControlEffect {
    var securityEffects: InteractiveApprovalEffects {
        reduce(into: []) { result, value in
            switch value {
            case .view: result.insert(.view)
            case .pointer: result.insert(.pointer)
            case .keyboard: result.insert(.keyboard)
            case .text: result.insert(.text)
            }
        }
    }
}

public struct InteractiveSessionRequestBody: WireBody {
    private enum CodingKeys: String, CodingKey { case initialSurface, effects }
    public static let kind = WireMessageKind.interactiveSessionRequest
    public let initialSurface: InteractiveSurfaceKind
    public let effects: [InteractiveControlEffect]

    public init(
        initialSurface: InteractiveSurfaceKind = .desktop,
        effects: Set<InteractiveControlEffect>
    ) throws {
        self.initialSurface = initialSurface
        self.effects = effects.sorted()
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["initialSurface", "effects"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        initialSurface = try container.decode(InteractiveSurfaceKind.self, forKey: .initialSurface)
        effects = try container.decode([InteractiveControlEffect].self, forKey: .effects)
        try validate()
    }

    public func validate() throws {
        guard initialSurface == .desktop else {
            throw WireError.invalidFrame(reason: "v0.1 session must start on Desktop")
        }
        try validateEffects(effects)
    }
}

public struct InteractiveApprovalChallengeBody: WireBody {
    private enum CodingKeys: String, CodingKey {
        case hostID, hostFingerprint, clientID, primaryConnectionID, requestID
        case approvalID, serverChallenge, authorizationEpoch, grantRevision
        case policyRevision, selectedDisplayID, initialSurface, effects
        case issuedAtUnixMilliseconds, expiresAtUnixMilliseconds
    }
    public static let kind = WireMessageKind.interactiveSessionApprovalRequired
    public let hostID: WireUUID
    public let hostFingerprint: WireFingerprint
    public let clientID: WireUUID
    public let primaryConnectionID: WireBytes16
    public let requestID: WireUUID
    public let approvalID: WireUUID
    public let serverChallenge: WireBytes32
    public let authorizationEpoch: AuthorizationEpoch
    public let grantRevision: GrantRevision
    public let policyRevision: PolicyRevision
    public let selectedDisplayID: WireUUID
    public let initialSurface: InteractiveSurfaceKind
    public let effects: [InteractiveControlEffect]
    public let issuedAtUnixMilliseconds: Int64
    public let expiresAtUnixMilliseconds: Int64

    public init(
        hostID: WireUUID,
        hostFingerprint: WireFingerprint,
        clientID: WireUUID,
        primaryConnectionID: WireBytes16,
        requestID: WireUUID,
        approvalID: WireUUID,
        serverChallenge: WireBytes32,
        authorizationEpoch: AuthorizationEpoch,
        grantRevision: GrantRevision,
        policyRevision: PolicyRevision,
        selectedDisplayID: WireUUID,
        initialSurface: InteractiveSurfaceKind,
        effects: Set<InteractiveControlEffect>,
        issuedAtUnixMilliseconds: Int64,
        expiresAtUnixMilliseconds: Int64
    ) throws {
        self.hostID = hostID
        self.hostFingerprint = hostFingerprint
        self.clientID = clientID
        self.primaryConnectionID = primaryConnectionID
        self.requestID = requestID
        self.approvalID = approvalID
        self.serverChallenge = serverChallenge
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.policyRevision = policyRevision
        self.selectedDisplayID = selectedDisplayID
        self.initialSurface = initialSurface
        self.effects = effects.sorted()
        self.issuedAtUnixMilliseconds = issuedAtUnixMilliseconds
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, [
            "hostID", "hostFingerprint", "clientID", "primaryConnectionID",
            "requestID", "approvalID", "serverChallenge", "authorizationEpoch",
            "grantRevision", "policyRevision", "selectedDisplayID", "initialSurface",
            "effects", "issuedAtUnixMilliseconds", "expiresAtUnixMilliseconds",
        ])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hostID = try c.decode(WireUUID.self, forKey: .hostID)
        hostFingerprint = try c.decode(WireFingerprint.self, forKey: .hostFingerprint)
        clientID = try c.decode(WireUUID.self, forKey: .clientID)
        primaryConnectionID = try c.decode(WireBytes16.self, forKey: .primaryConnectionID)
        requestID = try c.decode(WireUUID.self, forKey: .requestID)
        approvalID = try c.decode(WireUUID.self, forKey: .approvalID)
        serverChallenge = try c.decode(WireBytes32.self, forKey: .serverChallenge)
        authorizationEpoch = try c.decode(AuthorizationEpoch.self, forKey: .authorizationEpoch)
        grantRevision = try c.decode(GrantRevision.self, forKey: .grantRevision)
        policyRevision = try c.decode(PolicyRevision.self, forKey: .policyRevision)
        selectedDisplayID = try c.decode(WireUUID.self, forKey: .selectedDisplayID)
        initialSurface = try c.decode(InteractiveSurfaceKind.self, forKey: .initialSurface)
        effects = try c.decode([InteractiveControlEffect].self, forKey: .effects)
        issuedAtUnixMilliseconds = try c.decode(Int64.self, forKey: .issuedAtUnixMilliseconds)
        expiresAtUnixMilliseconds = try c.decode(Int64.self, forKey: .expiresAtUnixMilliseconds)
        try validate()
    }

    public func validate() throws {
        guard authorizationEpoch.rawValue >= 1, grantRevision.rawValue >= 1,
              policyRevision.rawValue >= 1, initialSurface == .desktop else {
            throw WireError.invalidFrame(reason: "invalid approval security binding")
        }
        try validateEffects(effects)
        guard issuedAtUnixMilliseconds >= 0,
              expiresAtUnixMilliseconds > issuedAtUnixMilliseconds,
              expiresAtUnixMilliseconds <= WireLimits.maximumSafeInteger,
              expiresAtUnixMilliseconds - issuedAtUnixMilliseconds <= 60_000 else {
            throw WireError.boundsExceeded(field: "approvalLifetime", limit: 60_000)
        }
    }

    public func signingInput(version: WireVersion) throws -> Data {
        try CompanionSecurityV0.interactiveApprovalSigningInput(
            hostID: hostID.rawValue,
            hostFingerprint: hostFingerprint.rawValue,
            clientID: clientID.rawValue,
            primaryConnectionID: primaryConnectionID.rawValue,
            requestID: requestID.rawValue,
            approvalID: approvalID.rawValue,
            serverChallenge: serverChallenge.rawValue,
            authorizationEpoch: authorizationEpoch.rawValue,
            grantRevision: grantRevision.rawValue,
            policyRevision: policyRevision.rawValue,
            selectedDisplayID: selectedDisplayID.rawValue,
            initialSurface: .desktop,
            effects: effects.securityEffects,
            issuedAtUnixMilliseconds: UInt64(issuedAtUnixMilliseconds),
            expiresAtUnixMilliseconds: UInt64(expiresAtUnixMilliseconds),
            selectedMajor: version.major,
            selectedMinor: version.minor
        )
    }
}

public struct InteractiveApprovalProofBody: WireBody {
    private enum CodingKeys: String, CodingKey { case approvalID, signature }
    public static let kind = WireMessageKind.interactiveSessionApprove
    public let approvalID: WireUUID
    public let signature: WireBytes64

    public init(approvalID: WireUUID, signature: WireBytes64) {
        self.approvalID = approvalID
        self.signature = signature
    }
    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["approvalID", "signature"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        approvalID = try c.decode(WireUUID.self, forKey: .approvalID)
        signature = try c.decode(WireBytes64.self, forKey: .signature)
    }
    public func validate() throws {}
}

public struct InteractiveChannelOffer: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case channelID, role, credential, issuedAtUnixMilliseconds, expiresAtUnixMilliseconds
    }
    public let channelID: WireUUID
    public let role: InteractiveChannelRoleName
    public let credential: WireBytes32
    public let issuedAtUnixMilliseconds: Int64
    public let expiresAtUnixMilliseconds: Int64

    public init(
        channelID: WireUUID,
        role: InteractiveChannelRoleName,
        credential: WireBytes32,
        issuedAtUnixMilliseconds: Int64,
        expiresAtUnixMilliseconds: Int64
    ) throws {
        self.channelID = channelID
        self.role = role
        self.credential = credential
        self.issuedAtUnixMilliseconds = issuedAtUnixMilliseconds
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
        try validate()
    }
    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, [
            "channelID", "role", "credential",
            "issuedAtUnixMilliseconds", "expiresAtUnixMilliseconds",
        ])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        channelID = try c.decode(WireUUID.self, forKey: .channelID)
        role = try c.decode(InteractiveChannelRoleName.self, forKey: .role)
        credential = try c.decode(WireBytes32.self, forKey: .credential)
        issuedAtUnixMilliseconds = try c.decode(Int64.self, forKey: .issuedAtUnixMilliseconds)
        expiresAtUnixMilliseconds = try c.decode(Int64.self, forKey: .expiresAtUnixMilliseconds)
        try validate()
    }
    public func validate() throws {
        guard issuedAtUnixMilliseconds >= 0,
              expiresAtUnixMilliseconds > issuedAtUnixMilliseconds,
              expiresAtUnixMilliseconds <= WireLimits.maximumSafeInteger,
              expiresAtUnixMilliseconds - issuedAtUnixMilliseconds <= 30_000 else {
            throw WireError.boundsExceeded(field: "channelLifetime", limit: 30_000)
        }
    }
}

public enum InteractiveChannelRoleName: String, Codable, CaseIterable, Sendable {
    case input
    case media
    public var securityRole: InteractiveChannelRole { self == .input ? .input : .media }
}

public struct InteractiveSessionAcceptedBody: WireBody {
    private enum CodingKeys: String, CodingKey {
        case interactiveSessionID, authorizationEpoch, expiresAtUnixMilliseconds
        case inputChannel, mediaChannel
    }
    public static let kind = WireMessageKind.interactiveSessionAccepted
    public let interactiveSessionID: WireUUID
    public let authorizationEpoch: AuthorizationEpoch
    public let expiresAtUnixMilliseconds: Int64
    public let inputChannel: InteractiveChannelOffer
    public let mediaChannel: InteractiveChannelOffer

    public init(
        interactiveSessionID: WireUUID,
        authorizationEpoch: AuthorizationEpoch,
        expiresAtUnixMilliseconds: Int64,
        inputChannel: InteractiveChannelOffer,
        mediaChannel: InteractiveChannelOffer
    ) throws {
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
        self.inputChannel = inputChannel
        self.mediaChannel = mediaChannel
        try validate()
    }
    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, [
            "interactiveSessionID", "authorizationEpoch", "expiresAtUnixMilliseconds",
            "inputChannel", "mediaChannel",
        ])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        interactiveSessionID = try c.decode(WireUUID.self, forKey: .interactiveSessionID)
        authorizationEpoch = try c.decode(AuthorizationEpoch.self, forKey: .authorizationEpoch)
        expiresAtUnixMilliseconds = try c.decode(Int64.self, forKey: .expiresAtUnixMilliseconds)
        inputChannel = try c.decode(InteractiveChannelOffer.self, forKey: .inputChannel)
        mediaChannel = try c.decode(InteractiveChannelOffer.self, forKey: .mediaChannel)
        try validate()
    }
    public func validate() throws {
        guard authorizationEpoch.rawValue >= 1,
              expiresAtUnixMilliseconds >= 0,
              expiresAtUnixMilliseconds <= WireLimits.maximumSafeInteger,
              inputChannel.role == .input, mediaChannel.role == .media,
              inputChannel.channelID != mediaChannel.channelID,
              inputChannel.credential != mediaChannel.credential,
              inputChannel.expiresAtUnixMilliseconds <= expiresAtUnixMilliseconds,
              mediaChannel.expiresAtUnixMilliseconds <= expiresAtUnixMilliseconds else {
            throw WireError.invalidFrame(reason: "invalid accepted Interactive Control session")
        }
        try inputChannel.validate()
        try mediaChannel.validate()
    }
}

public struct InteractiveSessionEndBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey {
        case interactiveSessionID, authorizationEpoch
    }

    public static let kind = WireMessageKind.interactiveSessionEnd
    public let interactiveSessionID: WireUUID
    public let authorizationEpoch: AuthorizationEpoch

    public init(
        interactiveSessionID: WireUUID,
        authorizationEpoch: AuthorizationEpoch
    ) throws {
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            ["interactiveSessionID", "authorizationEpoch"]
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
        try validate()
    }

    public func validate() throws {
        guard authorizationEpoch.rawValue >= 1 else {
            throw WireError.invalidFrame(
                reason: "authorization epoch must be positive"
            )
        }
    }
}

public struct InteractiveSessionEndedBodyV0: WireBody {
    private enum CodingKeys: String, CodingKey {
        case interactiveSessionID, authorizationEpoch
        case endedAtUnixMilliseconds
    }

    public static let kind = WireMessageKind.interactiveSessionEnded
    public let interactiveSessionID: WireUUID
    public let authorizationEpoch: AuthorizationEpoch
    public let endedAtUnixMilliseconds: Int64

    public init(
        interactiveSessionID: WireUUID,
        authorizationEpoch: AuthorizationEpoch,
        endedAtUnixMilliseconds: Int64
    ) throws {
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.endedAtUnixMilliseconds = endedAtUnixMilliseconds
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(
            decoder,
            [
                "interactiveSessionID", "authorizationEpoch",
                "endedAtUnixMilliseconds",
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
        endedAtUnixMilliseconds = try container.decode(
            Int64.self,
            forKey: .endedAtUnixMilliseconds
        )
        try validate()
    }

    public func validate() throws {
        guard authorizationEpoch.rawValue >= 1,
              (0...WireLimits.maximumSafeInteger).contains(
                endedAtUnixMilliseconds
              ) else {
            throw WireError.invalidFrame(
                reason: "invalid Interactive Control end receipt"
            )
        }
    }
}
