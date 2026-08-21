import CryptoKit
import Foundation

func data(_ range: ClosedRange<UInt8>) -> Data {
    Data(range)
}

func scalar(_ value: UInt8) -> Data {
    Data(repeating: 0, count: 31) + Data([value])
}

func ascii(_ value: String) -> Data {
    Data(value.utf8)
}

func u16be(_ value: UInt16) -> Data {
    Data([UInt8(value >> 8), UInt8(value & 0xff)])
}

func u32be(_ value: Int) -> Data {
    precondition(value >= 0 && value <= Int(UInt32.max))
    let number = UInt32(value)
    return Data([
        UInt8(number >> 24),
        UInt8((number >> 16) & 0xff),
        UInt8((number >> 8) & 0xff),
        UInt8(number & 0xff),
    ])
}

func lp(_ value: Data) -> Data {
    u32be(value.count) + value
}

func uuidBytes(_ value: String) -> Data {
    guard var uuid = UUID(uuidString: value)?.uuid else {
        fatalError("invalid fixture UUID")
    }
    return withUnsafeBytes(of: &uuid) { Data($0) }
}

extension Data {
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }

    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

let clientID = "018f2000-0000-7000-8000-000000000001"
let pairingID = "018f4000-0000-7000-8000-000000000001"
let connectionID = data(0x00...0x0f)
let clientNonce = data(0x10...0x2f)
let serverNonce = data(0x30...0x4f)
let hostFingerprint = data(0x80...0x9f)
let oneTimeSecret = data(0xc0...0xdf)

let sessionPrivateBytes = scalar(1)
let approvalPrivateBytes = scalar(2)
let sessionKey = try P256.Signing.PrivateKey(rawRepresentation: sessionPrivateBytes)
let approvalKey = try P256.Signing.PrivateKey(rawRepresentation: approvalPrivateBytes)
let sessionPublicKey = sessionKey.publicKey.x963Representation
let approvalPublicKey = approvalKey.publicKey.x963Representation

let authSigningInput = ascii("MacCompanion/Auth/v0.1")
    + lp(uuidBytes(clientID))
    + lp(connectionID)
    + lp(clientNonce)
    + lp(serverNonce)
    + lp(hostFingerprint)
    + u16be(0)
    + u16be(1)
let authSignature = try sessionKey.signature(for: authSigningInput)

let pairingTranscriptInput = ascii("MacCompanion/Pairing/v0.1")
    + lp(uuidBytes(pairingID))
    + lp(hostFingerprint)
    + lp(uuidBytes(clientID))
    + lp(sessionPublicKey)
    + lp(approvalPublicKey)
    + lp(clientNonce)
    + lp(serverNonce)
    + u16be(0)
    + u16be(1)
let transcriptDigest = Data(SHA256.hash(data: pairingTranscriptInput))

let secretProofInput = ascii("MacCompanion/PairingProof/v0.1") + transcriptDigest
let secretProof = Data(HMAC<SHA256>.authenticationCode(
    for: secretProofInput,
    using: SymmetricKey(data: oneTimeSecret)
))

let pairingSignatureInput = ascii("MacCompanion/PairingSignature/v0.1") + transcriptDigest
let pairingSignature = try sessionKey.signature(for: pairingSignatureInput)

let sasInput = ascii("MacCompanion/SAS/v0.1") + transcriptDigest
let sasBytes = Data(HMAC<SHA256>.authenticationCode(
    for: sasInput,
    using: SymmetricKey(data: oneTimeSecret)
))
let sasPrefix = sasBytes.prefix(3).map { String(format: "%02X", $0) }.joined()
let authenticationString = "\(sasPrefix.prefix(3))-\(sasPrefix.suffix(3))"

let vector: [String: Any] = [
    "profile": "MacCompanion capability protocol v0.1",
    "warning": "Public conformance-only private keys. Never use in a product build.",
    "inputs": [
        "clientID": clientID,
        "pairingID": pairingID,
        "connectionIDBase64URL": connectionID.base64URL,
        "clientNonceBase64URL": clientNonce.base64URL,
        "serverNonceBase64URL": serverNonce.base64URL,
        "hostFingerprintHex": hostFingerprint.hex,
        "oneTimeSecretHex": oneTimeSecret.hex,
        "sessionPrivateKeyHex": sessionPrivateBytes.hex,
        "approvalPrivateKeyHex": approvalPrivateBytes.hex,
        "selectedMajor": 0,
        "selectedMinor": 1,
    ],
    "derived": [
        "sessionPublicKeyX963Base64URL": sessionPublicKey.base64URL,
        "approvalPublicKeyX963Base64URL": approvalPublicKey.base64URL,
        "authSigningInputHex": authSigningInput.hex,
        "authSigningInputSHA256Hex": Data(SHA256.hash(data: authSigningInput)).hex,
        "authSignatureRawBase64URL": authSignature.rawRepresentation.base64URL,
        "authSignatureVerifies": sessionKey.publicKey.isValidSignature(authSignature, for: authSigningInput),
        "pairingTranscriptInputHex": pairingTranscriptInput.hex,
        "pairingTranscriptDigestHex": transcriptDigest.hex,
        "secretProofInputHex": secretProofInput.hex,
        "secretProofHex": secretProof.hex,
        "pairingSignatureInputHex": pairingSignatureInput.hex,
        "pairingSignatureRawBase64URL": pairingSignature.rawRepresentation.base64URL,
        "pairingSignatureVerifies": sessionKey.publicKey.isValidSignature(pairingSignature, for: pairingSignatureInput),
        "sasInputHex": sasInput.hex,
        "sasBytesHex": sasBytes.hex,
        "authenticationString": authenticationString,
    ],
]

let output = try JSONSerialization.data(
    withJSONObject: vector,
    options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
)
print(String(decoding: output, as: UTF8.self))
