import CompanionSecurity
import CompanionTestSupport
import CryptoKit
import Foundation
import Testing

private struct InteractiveCryptoVector: Decodable {
    struct Inputs: Decodable {
        let approvalID: UUID
        let approvalPrivateKeyHex: String
        let trustedSessionPrivateKeyHex: String
        let authorizationEpoch: UInt64
        let channelCredentialHex: String
        let channelID: UUID
        let channelRole: String
        let clientID: UUID
        let clientNonceHex: String
        let effectsRawValue: UInt16
        let expiresAtUnixMilliseconds: UInt64
        let grantRevision: UInt64
        let hostFingerprintHex: String
        let hostID: UUID
        let hostNonceHex: String
        let initialSurface: String
        let interactiveSessionID: UUID
        let issuedAtUnixMilliseconds: UInt64
        let policyRevision: UInt64
        let primaryConnectionIDHex: String
        let requestID: UUID
        let selectedDisplayID: UUID
        let selectedMajor: UInt16
        let selectedMinor: UInt16
        let serverChallengeHex: String
    }
    struct Derived: Decodable {
        let approvalSignatureRawBase64URL: String
        let trustedSessionSignatureRawBase64URL: String
        let approvalSigningInputHex: String
        let approvalSigningInputSHA256Hex: String
        let channelClientProofHex: String
        let channelServerProofHex: String
        let channelTranscriptDigestHex: String
        let channelTranscriptInputHex: String
    }
    let profile: String
    let warning: String
    let inputs: Inputs
    let derived: Derived
}

private func interactiveVector() throws -> InteractiveCryptoVector {
    let url = FixturePaths.authoritativeFixtures()
        .appendingPathComponent("crypto/interactive-v0.1.json")
    return try JSONDecoder().decode(
        InteractiveCryptoVector.self,
        from: Data(contentsOf: url)
    )
}

@Test func interactiveApprovalAndChannelGoldenVectorMatches() throws {
    let vector = try interactiveVector()
    #expect(vector.profile == "Mac Companion Interactive Control security v0.1")
    #expect(vector.warning.contains("Never use in a product build"))
    let input = vector.inputs
    let derived = vector.derived

    let approvalInput = try CompanionSecurityV0.interactiveApprovalSigningInput(
        hostID: input.hostID,
        hostFingerprint: Data(interactiveHex: input.hostFingerprintHex),
        clientID: input.clientID,
        primaryConnectionID: Data(interactiveHex: input.primaryConnectionIDHex),
        requestID: input.requestID,
        approvalID: input.approvalID,
        serverChallenge: Data(interactiveHex: input.serverChallengeHex),
        authorizationEpoch: input.authorizationEpoch,
        grantRevision: input.grantRevision,
        policyRevision: input.policyRevision,
        selectedDisplayID: input.selectedDisplayID,
        initialSurface: .desktop,
        effects: .init(rawValue: input.effectsRawValue),
        issuedAtUnixMilliseconds: input.issuedAtUnixMilliseconds,
        expiresAtUnixMilliseconds: input.expiresAtUnixMilliseconds,
        selectedMajor: input.selectedMajor,
        selectedMinor: input.selectedMinor
    )
    #expect(approvalInput == Data(interactiveHex: derived.approvalSigningInputHex))
    #expect(Data(SHA256.hash(data: approvalInput)) ==
        Data(interactiveHex: derived.approvalSigningInputSHA256Hex))
    let approvalKey = try P256.Signing.PrivateKey(
        rawRepresentation: Data(interactiveHex: input.approvalPrivateKeyHex)
    )
    #expect(try CompanionSecurityV0.verifySignature(
        rawSignature: Data(interactiveBase64URL: derived.approvalSignatureRawBase64URL),
        signingInput: approvalInput,
        publicKeyX963: approvalKey.publicKey.x963Representation
    ))

    let trustedKey = try P256.Signing.PrivateKey(
        rawRepresentation: Data(interactiveHex: input.trustedSessionPrivateKeyHex)
    )
    let trustedSignature = Data(interactiveBase64URL: derived.trustedSessionSignatureRawBase64URL)
    #expect(try CompanionSecurityV0.verifySignature(
        rawSignature: trustedSignature, signingInput: approvalInput,
        publicKeyX963: trustedKey.publicKey.x963Representation
    ))
    #expect(try !CompanionSecurityV0.verifySignature(
        rawSignature: trustedSignature, signingInput: approvalInput,
        publicKeyX963: approvalKey.publicKey.x963Representation
    ))
    #expect(try !CompanionSecurityV0.verifySignature(
        rawSignature: Data(interactiveBase64URL: derived.approvalSignatureRawBase64URL),
        signingInput: approvalInput, publicKeyX963: trustedKey.publicKey.x963Representation
    ))

    let channelInput = try CompanionSecurityV0.interactiveChannelTranscriptInput(
        channelID: input.channelID,
        role: .media,
        hostID: input.hostID,
        hostFingerprint: Data(interactiveHex: input.hostFingerprintHex),
        clientID: input.clientID,
        primaryConnectionID: Data(interactiveHex: input.primaryConnectionIDHex),
        interactiveSessionID: input.interactiveSessionID,
        authorizationEpoch: input.authorizationEpoch,
        clientNonce: Data(interactiveHex: input.clientNonceHex),
        hostNonce: Data(interactiveHex: input.hostNonceHex),
        selectedMajor: input.selectedMajor,
        selectedMinor: input.selectedMinor
    )
    #expect(channelInput == Data(interactiveHex: derived.channelTranscriptInputHex))
    let digest = CompanionSecurityV0.interactiveChannelTranscriptDigest(channelInput)
    #expect(digest == Data(interactiveHex: derived.channelTranscriptDigestHex))
    let credential = Data(interactiveHex: input.channelCredentialHex)
    let clientProof = try CompanionSecurityV0.interactiveChannelClientProof(
        credential: credential,
        transcriptDigest: digest
    )
    #expect(clientProof == Data(interactiveHex: derived.channelClientProofHex))
    #expect(try CompanionSecurityV0.verifyInteractiveChannelClientProof(
        clientProof,
        credential: credential,
        transcriptDigest: digest
    ))
    #expect(try CompanionSecurityV0.interactiveChannelServerProof(
        credential: credential,
        transcriptDigest: digest
    ) == Data(interactiveHex: derived.channelServerProofHex))
}

@Test func interactiveApprovalRejectsBroadenedEffectsAndLifetime() throws {
    let vector = try interactiveVector()
    let input = vector.inputs
    func construct(effects: InteractiveApprovalEffects, expires: UInt64) throws {
        _ = try CompanionSecurityV0.interactiveApprovalSigningInput(
            hostID: input.hostID,
            hostFingerprint: Data(interactiveHex: input.hostFingerprintHex),
            clientID: input.clientID,
            primaryConnectionID: Data(interactiveHex: input.primaryConnectionIDHex),
            requestID: input.requestID,
            approvalID: input.approvalID,
            serverChallenge: Data(interactiveHex: input.serverChallengeHex),
            authorizationEpoch: input.authorizationEpoch,
            grantRevision: input.grantRevision,
            policyRevision: input.policyRevision,
            selectedDisplayID: input.selectedDisplayID,
            initialSurface: .desktop,
            effects: effects,
            issuedAtUnixMilliseconds: input.issuedAtUnixMilliseconds,
            expiresAtUnixMilliseconds: expires,
            selectedMajor: 0,
            selectedMinor: 1
        )
    }
    #expect(throws: CompanionSecurityError.invalidValue(field: "effects")) {
        try construct(effects: [.view, .text], expires: input.expiresAtUnixMilliseconds)
    }
    #expect(throws: CompanionSecurityError.invalidValue(field: "effects")) {
        try construct(effects: .init(rawValue: 0x8001), expires: input.expiresAtUnixMilliseconds)
    }
    #expect(throws: CompanionSecurityError.invalidValue(field: "approvalLifetime")) {
        try construct(effects: [.view], expires: input.issuedAtUnixMilliseconds + 60_001)
    }
}

@Test func channelProofIsRoleSessionAndNonceBound() throws {
    let vector = try interactiveVector()
    let input = vector.inputs
    let credential = Data(interactiveHex: input.channelCredentialHex)
    let validDigest = Data(interactiveHex: vector.derived.channelTranscriptDigestHex)
    let proof = try CompanionSecurityV0.interactiveChannelClientProof(
        credential: credential,
        transcriptDigest: validDigest
    )
    var changedDigest = validDigest
    changedDigest[0] ^= 1
    #expect(try !CompanionSecurityV0.verifyInteractiveChannelClientProof(
        proof,
        credential: credential,
        transcriptDigest: changedDigest
    ))
}

private extension Data {
    init(interactiveHex value: String) {
        precondition(value.utf8.count.isMultiple(of: 2))
        self.init()
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            append(UInt8(value[index..<next], radix: 16)!)
            index = next
        }
    }

    init(interactiveBase64URL value: String) {
        var text = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        text.append(String(repeating: "=", count: (4 - text.count % 4) % 4))
        self = Data(base64Encoded: text)!
    }
}
