import CompanionDomain
import Foundation

public struct AuthHelloBody: WireBody {
    public static let kind = WireMessageKind.authHello
    private enum CodingKeys: String, CodingKey {
        case clientID, clientNonce, minimumVersion, maximumVersion
    }

    public let clientID: WireUUID
    public let clientNonce: WireBytes32
    public let minimumVersion: WireVersion
    public let maximumVersion: WireVersion

    public init(
        clientID: WireUUID,
        clientNonce: WireBytes32,
        minimumVersion: WireVersion = .init(),
        maximumVersion: WireVersion = .init()
    ) throws {
        self.clientID = clientID
        self.clientNonce = clientNonce
        self.minimumVersion = minimumVersion
        self.maximumVersion = maximumVersion
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["clientID", "clientNonce", "minimumVersion", "maximumVersion"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clientID = try container.decode(WireUUID.self, forKey: .clientID)
        clientNonce = try container.decode(WireBytes32.self, forKey: .clientNonce)
        minimumVersion = try container.decode(WireVersion.self, forKey: .minimumVersion)
        maximumVersion = try container.decode(WireVersion.self, forKey: .maximumVersion)
        try validate()
    }

    public func validate() throws {
        guard minimumVersion == WireVersion(), maximumVersion == WireVersion() else {
            throw WireError.unsupportedVersion(
                major: maximumVersion.major,
                minor: maximumVersion.minor
            )
        }
    }
}

public struct AuthChallengeBody: WireBody {
    public static let kind = WireMessageKind.authChallenge
    private enum CodingKeys: String, CodingKey {
        case connectionID, serverNonce, selectedVersion, hostFingerprint
    }

    public let connectionID: WireBytes16
    public let serverNonce: WireBytes32
    public let selectedVersion: WireVersion
    public let hostFingerprint: WireFingerprint

    public init(
        connectionID: WireBytes16,
        serverNonce: WireBytes32,
        selectedVersion: WireVersion = .init(),
        hostFingerprint: WireFingerprint
    ) throws {
        self.connectionID = connectionID
        self.serverNonce = serverNonce
        self.selectedVersion = selectedVersion
        self.hostFingerprint = hostFingerprint
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["connectionID", "serverNonce", "selectedVersion", "hostFingerprint"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        connectionID = try container.decode(WireBytes16.self, forKey: .connectionID)
        serverNonce = try container.decode(WireBytes32.self, forKey: .serverNonce)
        selectedVersion = try container.decode(WireVersion.self, forKey: .selectedVersion)
        hostFingerprint = try container.decode(WireFingerprint.self, forKey: .hostFingerprint)
        try validate()
    }

    public func validate() throws {
        guard selectedVersion == WireVersion() else {
            throw WireError.unsupportedVersion(major: selectedVersion.major, minor: selectedVersion.minor)
        }
    }
}

public struct AuthProofBody: WireBody {
    public static let kind = WireMessageKind.authProof
    public let signature: WireBytes64

    public init(signature: WireBytes64) { self.signature = signature }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["signature"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        signature = try container.decode(WireBytes64.self, forKey: .signature)
    }

    public func validate() throws {}
}

public struct PairingBeginBody: WireBody {
    public static let kind = WireMessageKind.pairingBegin
    private enum CodingKeys: String, CodingKey {
        case pairingID, clientID, sessionPublicKey, approvalPublicKey, clientNonce
    }

    public let pairingID: WireUUID
    public let clientID: WireUUID
    public let sessionPublicKey: WireBytes65
    public let approvalPublicKey: WireBytes65
    public let clientNonce: WireBytes32

    public init(
        pairingID: WireUUID,
        clientID: WireUUID,
        sessionPublicKey: WireBytes65,
        approvalPublicKey: WireBytes65,
        clientNonce: WireBytes32
    ) {
        self.pairingID = pairingID
        self.clientID = clientID
        self.sessionPublicKey = sessionPublicKey
        self.approvalPublicKey = approvalPublicKey
        self.clientNonce = clientNonce
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["pairingID", "clientID", "sessionPublicKey", "approvalPublicKey", "clientNonce"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pairingID = try container.decode(WireUUID.self, forKey: .pairingID)
        clientID = try container.decode(WireUUID.self, forKey: .clientID)
        sessionPublicKey = try container.decode(WireBytes65.self, forKey: .sessionPublicKey)
        approvalPublicKey = try container.decode(WireBytes65.self, forKey: .approvalPublicKey)
        clientNonce = try container.decode(WireBytes32.self, forKey: .clientNonce)
    }

    public func validate() throws {}
}

public struct PairingChallengeBody: WireBody {
    public static let kind = WireMessageKind.pairingChallenge
    private enum CodingKeys: String, CodingKey {
        case hostNonce, selectedVersion, hostFingerprint
    }

    public let hostNonce: WireBytes32
    public let selectedVersion: WireVersion
    public let hostFingerprint: WireFingerprint

    public init(
        hostNonce: WireBytes32,
        selectedVersion: WireVersion = .init(),
        hostFingerprint: WireFingerprint
    ) throws {
        self.hostNonce = hostNonce
        self.selectedVersion = selectedVersion
        self.hostFingerprint = hostFingerprint
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["hostNonce", "selectedVersion", "hostFingerprint"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hostNonce = try container.decode(WireBytes32.self, forKey: .hostNonce)
        selectedVersion = try container.decode(WireVersion.self, forKey: .selectedVersion)
        hostFingerprint = try container.decode(WireFingerprint.self, forKey: .hostFingerprint)
        try validate()
    }

    public func validate() throws {
        guard selectedVersion == WireVersion() else {
            throw WireError.unsupportedVersion(major: selectedVersion.major, minor: selectedVersion.minor)
        }
    }
}

public struct PairingProveBody: WireBody {
    public static let kind = WireMessageKind.pairingProve
    public let secretProof: WireBytes32
    public let signature: WireBytes64

    public init(secretProof: WireBytes32, signature: WireBytes64) {
        self.secretProof = secretProof
        self.signature = signature
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["secretProof", "signature"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        secretProof = try container.decode(WireBytes32.self, forKey: .secretProof)
        signature = try container.decode(WireBytes64.self, forKey: .signature)
    }

    public func validate() throws {}
}

public struct PairingPendingApprovalBody: WireBody {
    public static let kind = WireMessageKind.pairingPendingApproval
    private enum CodingKeys: String, CodingKey {
        case transcriptDigest, authenticationString, expiresAtUnixMilliseconds
    }

    public let transcriptDigest: WireBytes32
    public let authenticationString: PairingAuthenticationString
    public let expiresAtUnixMilliseconds: Int64

    public init(
        transcriptDigest: WireBytes32,
        authenticationString: PairingAuthenticationString,
        expiresAtUnixMilliseconds: Int64
    ) throws {
        self.transcriptDigest = transcriptDigest
        self.authenticationString = authenticationString
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["transcriptDigest", "authenticationString", "expiresAtUnixMilliseconds"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        transcriptDigest = try container.decode(WireBytes32.self, forKey: .transcriptDigest)
        authenticationString = try container.decode(PairingAuthenticationString.self, forKey: .authenticationString)
        expiresAtUnixMilliseconds = try container.decode(Int64.self, forKey: .expiresAtUnixMilliseconds)
        try validate()
    }

    public func validate() throws {
        guard expiresAtUnixMilliseconds >= 0,
              expiresAtUnixMilliseconds <= WireLimits.maximumSafeInteger else {
            throw WireError.boundsExceeded(
                field: "expiresAtUnixMilliseconds",
                limit: Int(WireLimits.maximumSafeInteger)
            )
        }
    }
}

public struct PairingCompleteBody: WireBody {
    public static let kind = WireMessageKind.pairingComplete
    private enum CodingKeys: String, CodingKey {
        case hostID, deviceID, deviceState, authorizationEpoch, grantRevision, policyRevision, hostFingerprint
    }

    public let hostID: WireUUID
    public let deviceID: WireUUID
    public let deviceState: DeviceAuthorizationState
    public let authorizationEpoch: AuthorizationEpoch
    public let grantRevision: GrantRevision
    public let policyRevision: PolicyRevision
    public let hostFingerprint: WireFingerprint

    public init(
        hostID: WireUUID,
        deviceID: WireUUID,
        deviceState: DeviceAuthorizationState = .activeMonitorOnly,
        authorizationEpoch: AuthorizationEpoch = .init(rawValue: 1),
        grantRevision: GrantRevision = .init(rawValue: 1),
        policyRevision: PolicyRevision,
        hostFingerprint: WireFingerprint
    ) throws {
        self.hostID = hostID
        self.deviceID = deviceID
        self.deviceState = deviceState
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.policyRevision = policyRevision
        self.hostFingerprint = hostFingerprint
        try validate()
    }

    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["hostID", "deviceID", "deviceState", "authorizationEpoch", "grantRevision", "policyRevision", "hostFingerprint"])
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hostID = try container.decode(WireUUID.self, forKey: .hostID)
        deviceID = try container.decode(WireUUID.self, forKey: .deviceID)
        deviceState = try container.decode(DeviceAuthorizationState.self, forKey: .deviceState)
        authorizationEpoch = try container.decode(AuthorizationEpoch.self, forKey: .authorizationEpoch)
        grantRevision = try container.decode(GrantRevision.self, forKey: .grantRevision)
        policyRevision = try container.decode(PolicyRevision.self, forKey: .policyRevision)
        hostFingerprint = try container.decode(WireFingerprint.self, forKey: .hostFingerprint)
        try validate()
    }

    public func validate() throws {
        guard deviceState == .activeMonitorOnly,
              authorizationEpoch.rawValue == 1,
              grantRevision.rawValue == 1,
              policyRevision.rawValue >= 1 else {
            throw WireError.invalidFrame(reason: "invalid initial pairing authorization")
        }
    }
}
