import CompanionSecurity
import CompanionTestSupport
import Foundation
import Testing

private struct OperationApprovalFixture: Decodable {
    struct Inputs: Decodable {
        let hostFingerprintHex: String
        let clientID: UUID
        let primaryConnectionIDHex: String
        let approvalID: UUID
        let operationDigestHex: String
        let serverChallengeHex: String
        let issuedAtUnixMilliseconds: UInt64
        let expiresAtUnixMilliseconds: UInt64
        let selectedMajor: UInt16
        let selectedMinor: UInt16
    }
    struct Derived: Decodable {
        let signingInputHex: String
        let approvalPublicKeyX963Hex: String
        let rawSignatureHex: String
    }
    let inputs: Inputs
    let derived: Derived
}

private func approvalFixture() throws -> OperationApprovalFixture {
    let url = FixturePaths.authoritativeFixtures()
        .appendingPathComponent("crypto/operation-approval-v0.1.json")
    return try JSONDecoder().decode(
        OperationApprovalFixture.self,
        from: Data(contentsOf: url)
    )
}

private func approvalData(_ hex: String) throws -> Data {
    guard hex.count.isMultiple(of: 2) else { throw CocoaError(.fileReadCorruptFile) }
    var result = Data()
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        guard let byte = UInt8(hex[index..<next], radix: 16) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        result.append(byte)
        index = next
    }
    return result
}

private func approvalSigningInput(
    operationDigest: Data? = nil,
    connectionID: Data? = nil
) throws -> Data {
    let fixture = try approvalFixture()
    let input = fixture.inputs
    return try CompanionSecurityV0.operationApprovalSigningInput(
        hostFingerprint: approvalData(input.hostFingerprintHex),
        clientID: input.clientID,
        primaryConnectionID: connectionID
            ?? approvalData(input.primaryConnectionIDHex),
        approvalID: input.approvalID,
        operationDigest: operationDigest
            ?? approvalData(input.operationDigestHex),
        serverChallenge: approvalData(input.serverChallengeHex),
        issuedAtUnixMilliseconds: input.issuedAtUnixMilliseconds,
        expiresAtUnixMilliseconds: input.expiresAtUnixMilliseconds,
        selectedMajor: input.selectedMajor,
        selectedMinor: input.selectedMinor
    )
}

@Test func operationApprovalMatchesAndVerifiesIndependentGoldenVector() throws {
    let fixture = try approvalFixture()
    let signingInput = try approvalSigningInput()
    #expect(signingInput == (try approvalData(fixture.derived.signingInputHex)))
    #expect(try CompanionSecurityV0.verifySignature(
        rawSignature: approvalData(fixture.derived.rawSignatureHex),
        signingInput: signingInput,
        publicKeyX963: approvalData(fixture.derived.approvalPublicKeyX963Hex)
    ))
}

@Test func operationApprovalSignatureCannotCrossOperationOrConnection() throws {
    let fixture = try approvalFixture()
    let signature = try approvalData(fixture.derived.rawSignatureHex)
    let publicKey = try approvalData(fixture.derived.approvalPublicKeyX963Hex)
    #expect(try !CompanionSecurityV0.verifySignature(
        rawSignature: signature,
        signingInput: approvalSigningInput(operationDigest: Data(repeating: 9, count: 32)),
        publicKeyX963: publicKey
    ))
    #expect(try !CompanionSecurityV0.verifySignature(
        rawSignature: signature,
        signingInput: approvalSigningInput(connectionID: Data(repeating: 8, count: 16)),
        publicKeyX963: publicKey
    ))
}

@Test func operationApprovalRejectsWrongLengthsAndLongLifetime() throws {
    let fixture = try approvalFixture()
    let input = fixture.inputs
    #expect(throws: CompanionSecurityError.invalidLength(
        field: "operationDigest",
        expected: 32,
        actual: 31
    )) {
        try CompanionSecurityV0.operationApprovalSigningInput(
            hostFingerprint: approvalData(input.hostFingerprintHex),
            clientID: input.clientID,
            primaryConnectionID: approvalData(input.primaryConnectionIDHex),
            approvalID: input.approvalID,
            operationDigest: Data(repeating: 0, count: 31),
            serverChallenge: approvalData(input.serverChallengeHex),
            issuedAtUnixMilliseconds: 1,
            expiresAtUnixMilliseconds: 2,
            selectedMajor: 0,
            selectedMinor: 1
        )
    }
    #expect(throws: CompanionSecurityError.invalidValue(
        field: "expiresAtUnixMilliseconds"
    )) {
        try CompanionSecurityV0.operationApprovalSigningInput(
            hostFingerprint: approvalData(input.hostFingerprintHex),
            clientID: input.clientID,
            primaryConnectionID: approvalData(input.primaryConnectionIDHex),
            approvalID: input.approvalID,
            operationDigest: approvalData(input.operationDigestHex),
            serverChallenge: approvalData(input.serverChallengeHex),
            issuedAtUnixMilliseconds: 1,
            expiresAtUnixMilliseconds: 60_002,
            selectedMajor: 0,
            selectedMinor: 1
        )
    }
}
