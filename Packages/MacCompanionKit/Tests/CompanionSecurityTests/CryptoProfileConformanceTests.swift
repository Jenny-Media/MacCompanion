import CompanionSecurity
import CompanionTestSupport
import CryptoKit
import Foundation
import Testing

private struct CryptoVector: Decodable {
    struct Inputs: Decodable {
        let approvalPrivateKeyHex: String
        let clientID: UUID
        let clientNonceBase64URL: String
        let connectionIDBase64URL: String
        let hostFingerprintHex: String
        let oneTimeSecretHex: String
        let pairingID: UUID
        let selectedMajor: UInt16
        let selectedMinor: UInt16
        let serverNonceBase64URL: String
        let sessionPrivateKeyHex: String
    }

    struct Derived: Decodable {
        let approvalPublicKeyFingerprintHex: String
        let approvalPublicKeyX963Base64URL: String
        let authenticationString: String
        let authSignatureRawBase64URL: String
        let authSigningInputHex: String
        let authSigningInputSHA256Hex: String
        let pairingSignatureInputHex: String
        let pairingSignatureRawBase64URL: String
        let pairingTranscriptDigestHex: String
        let pairingTranscriptInputHex: String
        let pairingRecoverySignatureInputHex: String
        let pairingRecoverySignatureRawBase64URL: String
        let pairingRecoveryTranscriptDigestHex: String
        let pairingRecoveryTranscriptInputHex: String
        let sasBytesHex: String
        let sasInputHex: String
        let secretProofHex: String
        let secretProofInputHex: String
        let sessionPublicKeyFingerprintHex: String
        let sessionPublicKeyX963Base64URL: String
    }

    let profile: String
    let warning: String
    let inputs: Inputs
    let derived: Derived
}

@Test func goldenCryptoVectorMatchesEveryNormativeConstruction() throws {
    let fixtureURL = FixturePaths.authoritativeFixtures()
        .appendingPathComponent("crypto/v0.1.json")
    let vector = try JSONDecoder().decode(
        CryptoVector.self,
        from: Data(contentsOf: fixtureURL)
    )
    #expect(vector.profile == "MacCompanion capability protocol v0.1")
    #expect(vector.warning.contains("Never use in a product build"))

    let sessionPrivateKey = try P256.Signing.PrivateKey(
        rawRepresentation: Data(hex: vector.inputs.sessionPrivateKeyHex)
    )
    let approvalPrivateKey = try P256.Signing.PrivateKey(
        rawRepresentation: Data(hex: vector.inputs.approvalPrivateKeyHex)
    )
    let sessionPublicKey = sessionPrivateKey.publicKey.x963Representation
    let approvalPublicKey = approvalPrivateKey.publicKey.x963Representation
    #expect(sessionPublicKey == Data(base64URL: vector.derived.sessionPublicKeyX963Base64URL))
    #expect(approvalPublicKey == Data(base64URL: vector.derived.approvalPublicKeyX963Base64URL))
    #expect(
        Data(SHA256.hash(data: sessionPublicKey))
            == Data(hex: vector.derived.sessionPublicKeyFingerprintHex)
    )
    #expect(
        Data(SHA256.hash(data: approvalPublicKey))
            == Data(hex: vector.derived.approvalPublicKeyFingerprintHex)
    )

    let connectionID = Data(base64URL: vector.inputs.connectionIDBase64URL)
    let clientNonce = Data(base64URL: vector.inputs.clientNonceBase64URL)
    let serverNonce = Data(base64URL: vector.inputs.serverNonceBase64URL)
    let hostFingerprint = Data(hex: vector.inputs.hostFingerprintHex)
    let oneTimeSecret = Data(hex: vector.inputs.oneTimeSecretHex)

    let authInput = try CompanionSecurityV0.authenticationSigningInput(
        clientID: vector.inputs.clientID,
        connectionID: connectionID,
        clientNonce: clientNonce,
        serverNonce: serverNonce,
        hostFingerprint: hostFingerprint,
        selectedMajor: vector.inputs.selectedMajor,
        selectedMinor: vector.inputs.selectedMinor
    )
    #expect(authInput == Data(hex: vector.derived.authSigningInputHex))
    #expect(Data(SHA256.hash(data: authInput)) == Data(hex: vector.derived.authSigningInputSHA256Hex))
    #expect(try CompanionSecurityV0.verifySignature(
        rawSignature: Data(base64URL: vector.derived.authSignatureRawBase64URL),
        signingInput: authInput,
        publicKeyX963: sessionPublicKey
    ))

    let transcriptInput = try CompanionSecurityV0.pairingTranscriptInput(
        pairingID: vector.inputs.pairingID,
        hostFingerprint: hostFingerprint,
        clientID: vector.inputs.clientID,
        sessionPublicKeyX963: sessionPublicKey,
        approvalPublicKeyX963: approvalPublicKey,
        clientNonce: clientNonce,
        hostNonce: serverNonce,
        selectedMajor: vector.inputs.selectedMajor,
        selectedMinor: vector.inputs.selectedMinor
    )
    #expect(transcriptInput == Data(hex: vector.derived.pairingTranscriptInputHex))

    let digest = CompanionSecurityV0.pairingTranscriptDigest(transcriptInput)
    #expect(digest == Data(hex: vector.derived.pairingTranscriptDigestHex))
    #expect(try CompanionSecurityV0.pairingSecretProofInput(transcriptDigest: digest)
        == Data(hex: vector.derived.secretProofInputHex))

    let proof = try CompanionSecurityV0.pairingSecretProof(
        oneTimeSecret: oneTimeSecret,
        transcriptDigest: digest
    )
    #expect(proof == Data(hex: vector.derived.secretProofHex))
    #expect(try CompanionSecurityV0.verifyPairingSecretProof(
        proof,
        oneTimeSecret: oneTimeSecret,
        transcriptDigest: digest
    ))

    let pairingSignatureInput = try CompanionSecurityV0.pairingSignatureInput(
        transcriptDigest: digest
    )
    #expect(pairingSignatureInput == Data(hex: vector.derived.pairingSignatureInputHex))
    #expect(try CompanionSecurityV0.verifySignature(
        rawSignature: Data(base64URL: vector.derived.pairingSignatureRawBase64URL),
        signingInput: pairingSignatureInput,
        publicKeyX963: sessionPublicKey
    ))

    let recoveryTranscript = try CompanionSecurityV0.pairingRecoveryTranscriptInput(
        pairingID: vector.inputs.pairingID,
        hostFingerprint: hostFingerprint,
        clientID: vector.inputs.clientID,
        sessionPublicKeyX963: sessionPublicKey,
        approvalPublicKeyX963: approvalPublicKey,
        clientNonce: clientNonce,
        hostNonce: serverNonce,
        selectedMajor: vector.inputs.selectedMajor,
        selectedMinor: vector.inputs.selectedMinor
    )
    #expect(recoveryTranscript == Data(hex: vector.derived.pairingRecoveryTranscriptInputHex))
    let recoveryDigest = CompanionSecurityV0.pairingRecoveryTranscriptDigest(
        recoveryTranscript
    )
    #expect(recoveryDigest == Data(hex: vector.derived.pairingRecoveryTranscriptDigestHex))
    let recoverySigningInput = try CompanionSecurityV0.pairingRecoverySignatureInput(
        transcriptDigest: recoveryDigest
    )
    #expect(recoverySigningInput == Data(hex: vector.derived.pairingRecoverySignatureInputHex))
    #expect(try CompanionSecurityV0.verifySignature(
        rawSignature: Data(base64URL: vector.derived.pairingRecoverySignatureRawBase64URL),
        signingInput: recoverySigningInput,
        publicKeyX963: sessionPublicKey
    ))

    let sasBytes = try CompanionSecurityV0.sasBytes(
        oneTimeSecret: oneTimeSecret,
        transcriptDigest: digest
    )
    #expect(sasBytes == Data(hex: vector.derived.sasBytesHex))
    #expect(Data("MacCompanion/SAS/v0.1".utf8) + digest == Data(hex: vector.derived.sasInputHex))
    #expect(try CompanionSecurityV0.authenticationString(
        oneTimeSecret: oneTimeSecret,
        transcriptDigest: digest
    ) == vector.derived.authenticationString)
}

@Test func malformedCryptoMaterialFailsClosed() throws {
    let validDigest = Data(repeating: 1, count: 32)

    #expect(throws: CompanionSecurityError.invalidLength(
        field: "oneTimeSecret",
        expected: 32,
        actual: 31
    )) {
        _ = try CompanionSecurityV0.pairingSecretProof(
            oneTimeSecret: Data(repeating: 0, count: 31),
            transcriptDigest: validDigest
        )
    }

    #expect(throws: CompanionSecurityError.unsupportedVersion(major: 1, minor: 0)) {
        _ = try CompanionSecurityV0.authenticationSigningInput(
            clientID: UUID(),
            connectionID: Data(repeating: 0, count: 16),
            clientNonce: Data(repeating: 0, count: 32),
            serverNonce: Data(repeating: 0, count: 32),
            hostFingerprint: Data(repeating: 0, count: 32),
            selectedMajor: 1,
            selectedMinor: 0
        )
    }
}

@Test func tamperingDoesNotVerify() throws {
    let fixtureURL = FixturePaths.authoritativeFixtures()
        .appendingPathComponent("crypto/v0.1.json")
    let vector = try JSONDecoder().decode(
        CryptoVector.self,
        from: Data(contentsOf: fixtureURL)
    )
    let signature = Data(base64URL: vector.derived.authSignatureRawBase64URL)
    let publicKey = Data(base64URL: vector.derived.sessionPublicKeyX963Base64URL)
    var input = Data(hex: vector.derived.authSigningInputHex)
    input[input.startIndex] ^= 0x01

    #expect(try !CompanionSecurityV0.verifySignature(
        rawSignature: signature,
        signingInput: input,
        publicKeyX963: publicKey
    ))
}

private extension Data {
    init(hex: String) {
        precondition(hex.utf8.count.isMultiple(of: 2))
        self.init()
        reserveCapacity(hex.utf8.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
    }

    init(base64URL: String) {
        var text = base64URL
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        text.append(String(repeating: "=", count: (4 - text.count % 4) % 4))
        self = Data(base64Encoded: text)!
    }
}
