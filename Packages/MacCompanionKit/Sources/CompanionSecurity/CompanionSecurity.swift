import CompanionDomain
import CryptoKit
import Foundation

public enum CompanionSecurityError: Error, Equatable, Sendable {
    case invalidLength(field: String, expected: Int, actual: Int)
    case invalidPublicKey
    case invalidSignature
    case unsupportedVersion(major: UInt16, minor: UInt16)
    case invalidValue(field: String)
}

public enum InteractiveInitialSurfaceCode: UInt8, CaseIterable, Sendable {
    case desktop = 1
    case application = 2
    case window = 3
    case focusedRegion = 4
}

public struct InteractiveApprovalEffects: OptionSet, Equatable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) { self.rawValue = rawValue }

    public static let view = Self(rawValue: 1 << 0)
    public static let pointer = Self(rawValue: 1 << 1)
    public static let keyboard = Self(rawValue: 1 << 2)
    public static let text = Self(rawValue: 1 << 3)
}

public enum InteractiveChannelRole: UInt8, CaseIterable, Sendable {
    case input = 1
    case media = 2
}

/// Pure, deterministic constructions from the capability protocol v0.1
/// cryptographic profile. This namespace deliberately has no Keychain,
/// authorization, transport, or persistent state authority.
public enum CompanionSecurityV0 {
    public static let maximumSubjectPublicKeyInfoBytes = 4_096

    private static let p256SubjectPublicKeyInfoPrefix = Data([
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86,
        0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a,
        0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03,
        0x42, 0x00,
    ])
    private static let authDomain = Data("MacCompanion/Auth/v0.1".utf8)
    private static let pairingDomain = Data("MacCompanion/Pairing/v0.1".utf8)
    private static let pairingProofDomain = Data("MacCompanion/PairingProof/v0.1".utf8)
    private static let pairingSignatureDomain = Data("MacCompanion/PairingSignature/v0.1".utf8)
    private static let sasDomain = Data("MacCompanion/SAS/v0.1".utf8)
    private static let interactiveApprovalDomain = Data("MacCompanion/InteractiveApproval/v0.1".utf8)
    private static let interactiveChannelDomain = Data("MacCompanion/InteractiveChannel/v0.1".utf8)
    private static let interactiveChannelProofDomain = Data("MacCompanion/InteractiveChannelProof/v0.1".utf8)
    private static let interactiveChannelAcceptDomain = Data("MacCompanion/InteractiveChannelAccept/v0.1".utf8)
    private static let operationDomain = Data("MacCompanion/Operation/v0.1".utf8)
    private static let operationApprovalDomain = Data("MacCompanion/OperationApproval/v0.1".utf8)

    public static func authenticationSigningInput(
        clientID: UUID,
        connectionID: Data,
        clientNonce: Data,
        serverNonce: Data,
        hostFingerprint: Data,
        selectedMajor: UInt16,
        selectedMinor: UInt16
    ) throws -> Data {
        try requireVersion(major: selectedMajor, minor: selectedMinor)
        try requireLength(connectionID, field: "connectionID", expected: 16)
        try requireLength(clientNonce, field: "clientNonce", expected: 32)
        try requireLength(serverNonce, field: "serverNonce", expected: 32)
        try requireLength(hostFingerprint, field: "hostFingerprint", expected: 32)

        var result = authDomain
        result.append(lengthPrefixed(uuidBytes(clientID)))
        result.append(lengthPrefixed(connectionID))
        result.append(lengthPrefixed(clientNonce))
        result.append(lengthPrefixed(serverNonce))
        result.append(lengthPrefixed(hostFingerprint))
        result.append(u16BE(selectedMajor))
        result.append(u16BE(selectedMinor))
        return result
    }

    public static func pairingTranscriptInput(
        pairingID: UUID,
        hostFingerprint: Data,
        clientID: UUID,
        sessionPublicKeyX963: Data,
        approvalPublicKeyX963: Data,
        clientNonce: Data,
        hostNonce: Data,
        selectedMajor: UInt16,
        selectedMinor: UInt16
    ) throws -> Data {
        try requireVersion(major: selectedMajor, minor: selectedMinor)
        try requireLength(hostFingerprint, field: "hostFingerprint", expected: 32)
        try validatePublicKey(sessionPublicKeyX963)
        try validatePublicKey(approvalPublicKeyX963)
        try requireLength(clientNonce, field: "clientNonce", expected: 32)
        try requireLength(hostNonce, field: "hostNonce", expected: 32)

        var result = pairingDomain
        result.append(lengthPrefixed(uuidBytes(pairingID)))
        result.append(lengthPrefixed(hostFingerprint))
        result.append(lengthPrefixed(uuidBytes(clientID)))
        result.append(lengthPrefixed(sessionPublicKeyX963))
        result.append(lengthPrefixed(approvalPublicKeyX963))
        result.append(lengthPrefixed(clientNonce))
        result.append(lengthPrefixed(hostNonce))
        result.append(u16BE(selectedMajor))
        result.append(u16BE(selectedMinor))
        return result
    }

    public static func pairingTranscriptDigest(_ transcriptInput: Data) -> Data {
        Data(SHA256.hash(data: transcriptInput))
    }

    public static func pairingSecretProofInput(transcriptDigest: Data) throws -> Data {
        try requireLength(transcriptDigest, field: "transcriptDigest", expected: 32)
        return pairingProofDomain + transcriptDigest
    }

    public static func pairingSecretProof(
        oneTimeSecret: Data,
        transcriptDigest: Data
    ) throws -> Data {
        try requireLength(oneTimeSecret, field: "oneTimeSecret", expected: 32)
        let input = try pairingSecretProofInput(transcriptDigest: transcriptDigest)
        return Data(HMAC<SHA256>.authenticationCode(
            for: input,
            using: SymmetricKey(data: oneTimeSecret)
        ))
    }

    public static func verifyPairingSecretProof(
        _ proof: Data,
        oneTimeSecret: Data,
        transcriptDigest: Data
    ) throws -> Bool {
        try requireLength(proof, field: "secretProof", expected: 32)
        try requireLength(oneTimeSecret, field: "oneTimeSecret", expected: 32)
        let input = try pairingSecretProofInput(transcriptDigest: transcriptDigest)
        return HMAC<SHA256>.isValidAuthenticationCode(
            proof,
            authenticating: input,
            using: SymmetricKey(data: oneTimeSecret)
        )
    }

    public static func pairingSignatureInput(transcriptDigest: Data) throws -> Data {
        try requireLength(transcriptDigest, field: "transcriptDigest", expected: 32)
        return pairingSignatureDomain + transcriptDigest
    }

    public static func verifySignature(
        rawSignature: Data,
        signingInput: Data,
        publicKeyX963: Data
    ) throws -> Bool {
        try requireLength(rawSignature, field: "signature", expected: 64)
        let publicKey: P256.Signing.PublicKey
        let signature: P256.Signing.ECDSASignature
        do {
            publicKey = try P256.Signing.PublicKey(x963Representation: publicKeyX963)
        } catch {
            throw CompanionSecurityError.invalidPublicKey
        }
        do {
            signature = try P256.Signing.ECDSASignature(rawRepresentation: rawSignature)
        } catch {
            throw CompanionSecurityError.invalidSignature
        }
        return publicKey.isValidSignature(signature, for: signingInput)
    }

    public static func validateSigningPublicKey(_ publicKeyX963: Data) throws {
        try validatePublicKey(publicKeyX963)
    }

    public static func p256SubjectPublicKeyInfoDER(
        publicKeyX963: Data
    ) throws -> Data {
        try validatePublicKey(publicKeyX963)
        return p256SubjectPublicKeyInfoPrefix + publicKeyX963
    }

    public static func hostFingerprint(
        subjectPublicKeyInfoDER: Data
    ) throws -> Data {
        guard (1...maximumSubjectPublicKeyInfoBytes).contains(
            subjectPublicKeyInfoDER.count
        ) else {
            throw CompanionSecurityError.invalidValue(field: "subjectPublicKeyInfoDER")
        }
        return Data(SHA256.hash(data: subjectPublicKeyInfoDER))
    }

    public static func hostFingerprint(publicKeyX963: Data) throws -> Data {
        try hostFingerprint(
            subjectPublicKeyInfoDER: p256SubjectPublicKeyInfoDER(
                publicKeyX963: publicKeyX963
            )
        )
    }

    public static func operationDigestInput(
        hostID: UUID,
        deviceID: UUID,
        clientID: UUID,
        operationID: UUID,
        capabilityID: String,
        schemaVersion: UInt32,
        providerID: String,
        providerVersion: String,
        providerGeneration: UUID,
        executionRevision: UUID,
        canonicalParametersSHA256: Data,
        effects: CapabilityEffectFacts,
        requiredHostState: HostState,
        authorizationEpoch: UInt64,
        grantRevision: UInt64,
        policyRevision: UInt64,
        expiresAtUnixMilliseconds: UInt64,
        selectedMajor: UInt16,
        selectedMinor: UInt16
    ) throws -> Data {
        try requireVersion(major: selectedMajor, minor: selectedMinor)
        try requireASCIIIdentifier(capabilityID, field: "capabilityID", maximum: 96)
        try requireASCIIIdentifier(providerID, field: "providerID", maximum: 96)
        try requireASCIIIdentifier(providerVersion, field: "providerVersion", maximum: 64)
        guard schemaVersion >= 1 else {
            throw CompanionSecurityError.invalidValue(field: "schemaVersion")
        }
        try requireLength(
            canonicalParametersSHA256,
            field: "canonicalParametersSHA256",
            expected: 32
        )
        try requireSafePositive(authorizationEpoch, field: "authorizationEpoch")
        try requireSafePositive(grantRevision, field: "grantRevision")
        try requireSafePositive(policyRevision, field: "policyRevision")
        try requireSafePositive(
            expiresAtUnixMilliseconds,
            field: "expiresAtUnixMilliseconds"
        )

        var result = operationDomain
        result.append(lengthPrefixed(uuidBytes(hostID)))
        result.append(lengthPrefixed(uuidBytes(deviceID)))
        result.append(lengthPrefixed(uuidBytes(clientID)))
        result.append(lengthPrefixed(uuidBytes(operationID)))
        result.append(lengthPrefixed(Data(capabilityID.utf8)))
        result.append(u32BE(schemaVersion))
        result.append(lengthPrefixed(Data(providerID.utf8)))
        result.append(lengthPrefixed(Data(providerVersion.utf8)))
        result.append(lengthPrefixed(uuidBytes(providerGeneration)))
        result.append(lengthPrefixed(uuidBytes(executionRevision)))
        result.append(lengthPrefixed(canonicalParametersSHA256))
        result.append(Data(effects.securityEncoding))
        result.append(Data([requiredHostState.securityCode]))
        result.append(u64BE(authorizationEpoch))
        result.append(u64BE(grantRevision))
        result.append(u64BE(policyRevision))
        result.append(u64BE(expiresAtUnixMilliseconds))
        result.append(u16BE(selectedMajor))
        result.append(u16BE(selectedMinor))
        return result
    }

    public static func operationDigest(_ input: Data) -> Data {
        Data(SHA256.hash(data: input))
    }

    public static func operationApprovalSigningInput(
        hostFingerprint: Data,
        clientID: UUID,
        primaryConnectionID: Data,
        approvalID: UUID,
        operationDigest: Data,
        serverChallenge: Data,
        issuedAtUnixMilliseconds: UInt64,
        expiresAtUnixMilliseconds: UInt64,
        selectedMajor: UInt16,
        selectedMinor: UInt16
    ) throws -> Data {
        try requireVersion(major: selectedMajor, minor: selectedMinor)
        try requireLength(hostFingerprint, field: "hostFingerprint", expected: 32)
        try requireLength(primaryConnectionID, field: "primaryConnectionID", expected: 16)
        try requireLength(operationDigest, field: "operationDigest", expected: 32)
        try requireLength(serverChallenge, field: "serverChallenge", expected: 32)
        try requireSafePositive(
            issuedAtUnixMilliseconds,
            field: "issuedAtUnixMilliseconds"
        )
        try requireSafePositive(
            expiresAtUnixMilliseconds,
            field: "expiresAtUnixMilliseconds"
        )
        guard expiresAtUnixMilliseconds > issuedAtUnixMilliseconds,
              expiresAtUnixMilliseconds - issuedAtUnixMilliseconds <= 60_000 else {
            throw CompanionSecurityError.invalidValue(
                field: "expiresAtUnixMilliseconds"
            )
        }

        var result = operationApprovalDomain
        result.append(lengthPrefixed(hostFingerprint))
        result.append(lengthPrefixed(uuidBytes(clientID)))
        result.append(lengthPrefixed(primaryConnectionID))
        result.append(lengthPrefixed(uuidBytes(approvalID)))
        result.append(lengthPrefixed(operationDigest))
        result.append(lengthPrefixed(serverChallenge))
        result.append(u64BE(issuedAtUnixMilliseconds))
        result.append(u64BE(expiresAtUnixMilliseconds))
        result.append(u16BE(selectedMajor))
        result.append(u16BE(selectedMinor))
        return result
    }

    public static func sasBytes(
        oneTimeSecret: Data,
        transcriptDigest: Data
    ) throws -> Data {
        try requireLength(oneTimeSecret, field: "oneTimeSecret", expected: 32)
        try requireLength(transcriptDigest, field: "transcriptDigest", expected: 32)
        return Data(HMAC<SHA256>.authenticationCode(
            for: sasDomain + transcriptDigest,
            using: SymmetricKey(data: oneTimeSecret)
        ))
    }

    public static func authenticationString(
        oneTimeSecret: Data,
        transcriptDigest: Data
    ) throws -> String {
        let prefix = try sasBytes(
            oneTimeSecret: oneTimeSecret,
            transcriptDigest: transcriptDigest
        ).prefix(3)
        let hex = prefix.map { String(format: "%02X", $0) }.joined()
        return "\(hex.prefix(3))-\(hex.suffix(3))"
    }

    public static func interactiveApprovalSigningInput(
        hostID: UUID,
        hostFingerprint: Data,
        clientID: UUID,
        primaryConnectionID: Data,
        requestID: UUID,
        approvalID: UUID,
        serverChallenge: Data,
        authorizationEpoch: UInt64,
        grantRevision: UInt64,
        policyRevision: UInt64,
        selectedDisplayID: UUID,
        initialSurface: InteractiveInitialSurfaceCode,
        effects: InteractiveApprovalEffects,
        issuedAtUnixMilliseconds: UInt64,
        expiresAtUnixMilliseconds: UInt64,
        selectedMajor: UInt16,
        selectedMinor: UInt16
    ) throws -> Data {
        try requireVersion(major: selectedMajor, minor: selectedMinor)
        try requireLength(hostFingerprint, field: "hostFingerprint", expected: 32)
        try requireLength(primaryConnectionID, field: "primaryConnectionID", expected: 16)
        try requireLength(serverChallenge, field: "serverChallenge", expected: 32)
        try requireSafePositive(authorizationEpoch, field: "authorizationEpoch")
        try requireSafePositive(grantRevision, field: "grantRevision")
        try requireSafePositive(policyRevision, field: "policyRevision")
        let allowedEffects: InteractiveApprovalEffects = [.view, .pointer, .keyboard, .text]
        guard effects.contains(.view), effects.subtracting(allowedEffects).isEmpty,
              !effects.contains(.text) || effects.contains(.keyboard) else {
            throw CompanionSecurityError.invalidValue(field: "effects")
        }
        guard issuedAtUnixMilliseconds <= 9_007_199_254_740_991,
              expiresAtUnixMilliseconds <= 9_007_199_254_740_991,
              expiresAtUnixMilliseconds > issuedAtUnixMilliseconds,
              expiresAtUnixMilliseconds - issuedAtUnixMilliseconds <= 60_000 else {
            throw CompanionSecurityError.invalidValue(field: "approvalLifetime")
        }

        var result = interactiveApprovalDomain
        result.append(lengthPrefixed(uuidBytes(hostID)))
        result.append(lengthPrefixed(hostFingerprint))
        result.append(lengthPrefixed(uuidBytes(clientID)))
        result.append(lengthPrefixed(primaryConnectionID))
        result.append(lengthPrefixed(uuidBytes(requestID)))
        result.append(lengthPrefixed(uuidBytes(approvalID)))
        result.append(lengthPrefixed(serverChallenge))
        result.append(u64BE(authorizationEpoch))
        result.append(u64BE(grantRevision))
        result.append(u64BE(policyRevision))
        result.append(lengthPrefixed(uuidBytes(selectedDisplayID)))
        result.append(Data([initialSurface.rawValue]))
        result.append(u16BE(effects.rawValue))
        result.append(u64BE(issuedAtUnixMilliseconds))
        result.append(u64BE(expiresAtUnixMilliseconds))
        result.append(u16BE(selectedMajor))
        result.append(u16BE(selectedMinor))
        return result
    }

    public static func interactiveChannelTranscriptInput(
        channelID: UUID,
        role: InteractiveChannelRole,
        hostID: UUID,
        hostFingerprint: Data,
        clientID: UUID,
        primaryConnectionID: Data,
        interactiveSessionID: UUID,
        authorizationEpoch: UInt64,
        clientNonce: Data,
        hostNonce: Data,
        selectedMajor: UInt16,
        selectedMinor: UInt16
    ) throws -> Data {
        try requireVersion(major: selectedMajor, minor: selectedMinor)
        try requireLength(hostFingerprint, field: "hostFingerprint", expected: 32)
        try requireLength(primaryConnectionID, field: "primaryConnectionID", expected: 16)
        try requireLength(clientNonce, field: "clientNonce", expected: 32)
        try requireLength(hostNonce, field: "hostNonce", expected: 32)
        try requireSafePositive(authorizationEpoch, field: "authorizationEpoch")

        var result = interactiveChannelDomain
        result.append(lengthPrefixed(uuidBytes(channelID)))
        result.append(Data([role.rawValue]))
        result.append(lengthPrefixed(uuidBytes(hostID)))
        result.append(lengthPrefixed(hostFingerprint))
        result.append(lengthPrefixed(uuidBytes(clientID)))
        result.append(lengthPrefixed(primaryConnectionID))
        result.append(lengthPrefixed(uuidBytes(interactiveSessionID)))
        result.append(u64BE(authorizationEpoch))
        result.append(lengthPrefixed(clientNonce))
        result.append(lengthPrefixed(hostNonce))
        result.append(u16BE(selectedMajor))
        result.append(u16BE(selectedMinor))
        return result
    }

    public static func interactiveChannelTranscriptDigest(_ input: Data) -> Data {
        Data(SHA256.hash(data: input))
    }

    public static func interactiveChannelClientProof(
        credential: Data,
        transcriptDigest: Data
    ) throws -> Data {
        try requireLength(credential, field: "channelCredential", expected: 32)
        try requireLength(transcriptDigest, field: "transcriptDigest", expected: 32)
        return Data(HMAC<SHA256>.authenticationCode(
            for: interactiveChannelProofDomain + transcriptDigest,
            using: SymmetricKey(data: credential)
        ))
    }

    public static func interactiveChannelServerProof(
        credential: Data,
        transcriptDigest: Data
    ) throws -> Data {
        try requireLength(credential, field: "channelCredential", expected: 32)
        try requireLength(transcriptDigest, field: "transcriptDigest", expected: 32)
        return Data(HMAC<SHA256>.authenticationCode(
            for: interactiveChannelAcceptDomain + transcriptDigest,
            using: SymmetricKey(data: credential)
        ))
    }

    public static func verifyInteractiveChannelClientProof(
        _ proof: Data,
        credential: Data,
        transcriptDigest: Data
    ) throws -> Bool {
        try requireLength(proof, field: "channelProof", expected: 32)
        let expected = try interactiveChannelClientProof(
            credential: credential,
            transcriptDigest: transcriptDigest
        )
        return timingSafeEqual(proof, expected)
    }

    private static func validatePublicKey(_ data: Data) throws {
        try requireLength(data, field: "publicKeyX963", expected: 65)
        guard data.first == 0x04 else {
            throw CompanionSecurityError.invalidPublicKey
        }
        do {
            _ = try P256.Signing.PublicKey(x963Representation: data)
        } catch {
            throw CompanionSecurityError.invalidPublicKey
        }
    }

    private static func requireLength(
        _ data: Data,
        field: String,
        expected: Int
    ) throws {
        guard data.count == expected else {
            throw CompanionSecurityError.invalidLength(
                field: field,
                expected: expected,
                actual: data.count
            )
        }
    }

    private static func requireVersion(major: UInt16, minor: UInt16) throws {
        guard major == 0, minor == 1 else {
            throw CompanionSecurityError.unsupportedVersion(major: major, minor: minor)
        }
    }

    private static func requireSafePositive(_ value: UInt64, field: String) throws {
        guard value >= 1, value <= 9_007_199_254_740_991 else {
            throw CompanionSecurityError.invalidValue(field: field)
        }
    }

    private static func requireASCIIIdentifier(
        _ value: String,
        field: String,
        maximum: Int
    ) throws {
        let bytes = Array(value.utf8)
        guard (1...maximum).contains(bytes.count),
              bytes.allSatisfy({ byte in
                  (byte >= 0x30 && byte <= 0x39)
                      || (byte >= 0x41 && byte <= 0x5a)
                      || (byte >= 0x61 && byte <= 0x7a)
                      || byte == 0x2d || byte == 0x2e || byte == 0x5f
              }) else {
            throw CompanionSecurityError.invalidValue(field: field)
        }
    }

    private static func lengthPrefixed(_ data: Data) -> Data {
        precondition(data.count <= Int(UInt32.max))
        let count = UInt32(data.count)
        return Data([
            UInt8(count >> 24),
            UInt8((count >> 16) & 0xff),
            UInt8((count >> 8) & 0xff),
            UInt8(count & 0xff),
        ]) + data
    }

    private static func u16BE(_ value: UInt16) -> Data {
        Data([UInt8(value >> 8), UInt8(value & 0xff)])
    }

    private static func u32BE(_ value: UInt32) -> Data {
        Data([
            UInt8(value >> 24),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff),
        ])
    }

    private static func u64BE(_ value: UInt64) -> Data {
        Data((0..<8).map { shift in
            UInt8((value >> UInt64(56 - shift * 8)) & 0xff)
        })
    }

    private static func timingSafeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    private static func uuidBytes(_ value: UUID) -> Data {
        let hex = value.uuidString.replacingOccurrences(of: "-", with: "")
        precondition(hex.utf8.count == 32)
        var bytes = Data()
        bytes.reserveCapacity(16)
        var index = hex.startIndex
        for _ in 0..<16 {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return bytes
    }
}

private extension HostState {
    var securityCode: UInt8 {
        switch self {
        case .userSessionActive: 1
        case .userSessionLocked: 2
        case .otherConsoleUserActive: 3
        case .serviceStoppingForLogout: 4
        case .hostPreparingForSleep: 5
        }
    }
}
