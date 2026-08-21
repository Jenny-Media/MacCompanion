import CompanionDomain
import CompanionSecurity
import CompanionWire
import Foundation

public enum InteractiveChannelMessageKind: String, Codable, CaseIterable, Sendable {
    case hello = "interactive.channel.hello"
    case challenge = "interactive.channel.challenge"
    case prove = "interactive.channel.prove"
    case accepted = "interactive.channel.accepted"
}

public protocol InteractiveChannelHandshakeBody: Codable, Equatable, Sendable {
    static var kind: InteractiveChannelMessageKind { get }
    func validate() throws
}

public struct InteractiveChannelEnvelope<Body: InteractiveChannelHandshakeBody>: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case version, messageID, correlationID, kind, body
    }
    public let version: WireVersion
    public let messageID: WireUUID
    public let correlationID: WireUUID?
    public let kind: InteractiveChannelMessageKind
    public let body: Body

    public init(
        version: WireVersion = .init(),
        messageID: WireUUID,
        correlationID: WireUUID?,
        body: Body
    ) throws {
        self.version = version
        self.messageID = messageID
        self.correlationID = correlationID
        self.kind = Body.kind
        self.body = body
        try validate()
    }
    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["version", "messageID", "correlationID", "kind", "body"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(WireVersion.self, forKey: .version)
        messageID = try c.decode(WireUUID.self, forKey: .messageID)
        correlationID = try c.decodeIfPresent(WireUUID.self, forKey: .correlationID)
        kind = try c.decode(InteractiveChannelMessageKind.self, forKey: .kind)
        body = try c.decode(Body.self, forKey: .body)
        try validate()
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(messageID, forKey: .messageID)
        try c.encode(correlationID, forKey: .correlationID)
        try c.encode(kind, forKey: .kind)
        try c.encode(body, forKey: .body)
    }
    public func validate() throws {
        guard kind == Body.kind else {
            throw WireError.kindMismatch(expected: Body.kind.rawValue, actual: kind.rawValue)
        }
        if kind == .hello {
            guard correlationID == nil else {
                throw WireError.invalidFrame(reason: "channel hello must have null correlationID")
            }
        } else {
            guard correlationID != nil else {
                throw WireError.invalidFrame(reason: "channel reply must have correlationID")
            }
        }
        try body.validate()
    }
}

public enum InteractiveChannelCodec {
    public static func decode<Body: InteractiveChannelHandshakeBody>(
        _ type: InteractiveChannelEnvelope<Body>.Type,
        from data: Data
    ) throws -> InteractiveChannelEnvelope<Body> {
        try StrictJSON.validate(data)
        return try JSONDecoder().decode(type, from: data)
    }
    public static func encode<Body: InteractiveChannelHandshakeBody>(
        _ value: InteractiveChannelEnvelope<Body>
    ) throws -> Data {
        try value.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

public struct InteractiveChannelHelloBody: InteractiveChannelHandshakeBody {
    private enum CodingKeys: String, CodingKey {
        case channelID, role, clientID, primaryConnectionID
        case interactiveSessionID, authorizationEpoch, clientNonce
    }
    public static let kind = InteractiveChannelMessageKind.hello
    public let channelID: WireUUID
    public let role: InteractiveChannelRoleName
    public let clientID: WireUUID
    public let primaryConnectionID: WireBytes16
    public let interactiveSessionID: WireUUID
    public let authorizationEpoch: AuthorizationEpoch
    public let clientNonce: WireBytes32

    public init(
        channelID: WireUUID,
        role: InteractiveChannelRoleName,
        clientID: WireUUID,
        primaryConnectionID: WireBytes16,
        interactiveSessionID: WireUUID,
        authorizationEpoch: AuthorizationEpoch,
        clientNonce: WireBytes32
    ) throws {
        self.channelID = channelID
        self.role = role
        self.clientID = clientID
        self.primaryConnectionID = primaryConnectionID
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.clientNonce = clientNonce
        try validate()
    }
    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, [
            "channelID", "role", "clientID", "primaryConnectionID",
            "interactiveSessionID", "authorizationEpoch", "clientNonce",
        ])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        channelID = try c.decode(WireUUID.self, forKey: .channelID)
        role = try c.decode(InteractiveChannelRoleName.self, forKey: .role)
        clientID = try c.decode(WireUUID.self, forKey: .clientID)
        primaryConnectionID = try c.decode(WireBytes16.self, forKey: .primaryConnectionID)
        interactiveSessionID = try c.decode(WireUUID.self, forKey: .interactiveSessionID)
        authorizationEpoch = try c.decode(AuthorizationEpoch.self, forKey: .authorizationEpoch)
        clientNonce = try c.decode(WireBytes32.self, forKey: .clientNonce)
        try validate()
    }
    public func validate() throws {
        guard authorizationEpoch.rawValue >= 1 else {
            throw WireError.invalidFrame(reason: "zero channel authorization epoch")
        }
    }

    public func transcriptInput(
        challenge: InteractiveChannelChallengeBody,
        version: WireVersion
    ) throws -> Data {
        guard challenge.channelID == channelID, challenge.role == role else {
            throw WireError.invalidFrame(reason: "channel challenge binding mismatch")
        }
        return try CompanionSecurityV0.interactiveChannelTranscriptInput(
            channelID: channelID.rawValue,
            role: role.securityRole,
            hostID: challenge.hostID.rawValue,
            hostFingerprint: challenge.hostFingerprint.rawValue,
            clientID: clientID.rawValue,
            primaryConnectionID: primaryConnectionID.rawValue,
            interactiveSessionID: interactiveSessionID.rawValue,
            authorizationEpoch: authorizationEpoch.rawValue,
            clientNonce: clientNonce.rawValue,
            hostNonce: challenge.hostNonce.rawValue,
            selectedMajor: version.major,
            selectedMinor: version.minor
        )
    }
}

public struct InteractiveChannelChallengeBody: InteractiveChannelHandshakeBody {
    private enum CodingKeys: String, CodingKey { case channelID, role, hostID, hostFingerprint, hostNonce }
    public static let kind = InteractiveChannelMessageKind.challenge
    public let channelID: WireUUID
    public let role: InteractiveChannelRoleName
    public let hostID: WireUUID
    public let hostFingerprint: WireFingerprint
    public let hostNonce: WireBytes32

    public init(
        channelID: WireUUID,
        role: InteractiveChannelRoleName,
        hostID: WireUUID,
        hostFingerprint: WireFingerprint,
        hostNonce: WireBytes32
    ) {
        self.channelID = channelID
        self.role = role
        self.hostID = hostID
        self.hostFingerprint = hostFingerprint
        self.hostNonce = hostNonce
    }
    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["channelID", "role", "hostID", "hostFingerprint", "hostNonce"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        channelID = try c.decode(WireUUID.self, forKey: .channelID)
        role = try c.decode(InteractiveChannelRoleName.self, forKey: .role)
        hostID = try c.decode(WireUUID.self, forKey: .hostID)
        hostFingerprint = try c.decode(WireFingerprint.self, forKey: .hostFingerprint)
        hostNonce = try c.decode(WireBytes32.self, forKey: .hostNonce)
    }
    public func validate() throws {}
}

public struct InteractiveChannelProofBody: InteractiveChannelHandshakeBody {
    private enum CodingKeys: String, CodingKey { case channelID, clientProof }
    public static let kind = InteractiveChannelMessageKind.prove
    public let channelID: WireUUID
    public let clientProof: WireBytes32
    public init(channelID: WireUUID, clientProof: WireBytes32) {
        self.channelID = channelID
        self.clientProof = clientProof
    }
    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["channelID", "clientProof"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        channelID = try c.decode(WireUUID.self, forKey: .channelID)
        clientProof = try c.decode(WireBytes32.self, forKey: .clientProof)
    }
    public func validate() throws {}
}

public struct InteractiveChannelAcceptedBody: InteractiveChannelHandshakeBody {
    private enum CodingKeys: String, CodingKey { case channelID, role, serverProof }
    public static let kind = InteractiveChannelMessageKind.accepted
    public let channelID: WireUUID
    public let role: InteractiveChannelRoleName
    public let serverProof: WireBytes32
    public init(channelID: WireUUID, role: InteractiveChannelRoleName, serverProof: WireBytes32) {
        self.channelID = channelID
        self.role = role
        self.serverProof = serverProof
    }
    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["channelID", "role", "serverProof"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        channelID = try c.decode(WireUUID.self, forKey: .channelID)
        role = try c.decode(InteractiveChannelRoleName.self, forKey: .role)
        serverProof = try c.decode(WireBytes32.self, forKey: .serverProof)
    }
    public func validate() throws {}
}
