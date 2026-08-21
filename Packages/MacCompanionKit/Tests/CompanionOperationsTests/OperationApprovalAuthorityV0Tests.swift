import CompanionOperations
import CompanionTestSupport
import Foundation
import Testing

private struct ApprovalAuthorityFixture: Decodable {
    struct Inputs: Decodable {
        let hostFingerprintHex: String
        let clientID: UUID
        let primaryConnectionIDHex: String
        let approvalID: UUID
        let operationDigestHex: String
        let serverChallengeHex: String
        let issuedAtUnixMilliseconds: UInt64
        let expiresAtUnixMilliseconds: UInt64
    }
    struct Derived: Decodable {
        let approvalPublicKeyX963Hex: String
        let rawSignatureHex: String
    }
    let inputs: Inputs
    let derived: Derived
}

private func authorityApprovalFixture() throws -> ApprovalAuthorityFixture {
    let url = FixturePaths.authoritativeFixtures()
        .appendingPathComponent("crypto/operation-approval-v0.1.json")
    return try JSONDecoder().decode(
        ApprovalAuthorityFixture.self,
        from: Data(contentsOf: url)
    )
}

private func authorityApprovalData(_ hex: String) throws -> Data {
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

private let approvalProviderGeneration = UUID(
    uuidString: "018f8100-0000-7000-8000-000000000001"
)!
private let approvalExecutionRevision = UUID(
    uuidString: "018f8200-0000-7000-8000-000000000001"
)!

private func approvalAuthority() throws -> OperationApprovalAuthorityV0 {
    let fixture = try authorityApprovalFixture()
    return try OperationApprovalAuthorityV0(
        hostFingerprint: authorityApprovalData(fixture.inputs.hostFingerprintHex),
        clientID: fixture.inputs.clientID,
        primaryConnectionID: authorityApprovalData(
            fixture.inputs.primaryConnectionIDHex
        ),
        approvalID: fixture.inputs.approvalID,
        operationDigest: authorityApprovalData(fixture.inputs.operationDigestHex),
        serverChallenge: authorityApprovalData(fixture.inputs.serverChallengeHex),
        authorizationEpoch: 4,
        grantRevision: 5,
        policyRevision: 6,
        providerGeneration: approvalProviderGeneration,
        executionRevision: approvalExecutionRevision,
        issuedAtUnixMilliseconds: fixture.inputs.issuedAtUnixMilliseconds,
        expiresAtUnixMilliseconds: fixture.inputs.expiresAtUnixMilliseconds,
        approvalPublicKeyX963: authorityApprovalData(
            fixture.derived.approvalPublicKeyX963Hex
        ),
        issuedAtMonotonicMilliseconds: 10_000,
        expiresAtMonotonicMilliseconds: 70_000
    )
}

private func approvalCurrentState() throws -> OperationApprovalCurrentStateV0 {
    let fixture = try authorityApprovalFixture()
    return OperationApprovalCurrentStateV0(
        clientID: fixture.inputs.clientID,
        primaryConnectionID: try authorityApprovalData(
            fixture.inputs.primaryConnectionIDHex
        ),
        authorizationEpoch: 4,
        grantRevision: 5,
        policyRevision: 6,
        providerGeneration: approvalProviderGeneration,
        executionRevision: approvalExecutionRevision,
        approvalPublicKeyX963: try authorityApprovalData(
            fixture.derived.approvalPublicKeyX963Hex
        )
    )
}

@Test func operationApprovalConsumesGoldenSignatureExactlyOnce() throws {
    let fixture = try authorityApprovalFixture()
    var authority = try approvalAuthority()
    let intent = try authority.verifyAndConsume(
        rawSignature: authorityApprovalData(fixture.derived.rawSignatureHex),
        current: approvalCurrentState(),
        monotonicNowMilliseconds: 20_000
    )
    #expect(authority.state == .consumed)
    #expect(intent.approvalID == fixture.inputs.approvalID)
    #expect(intent.operationDigest == (try authorityApprovalData(
        fixture.inputs.operationDigestHex
    )))
    #expect(intent.deadlineMonotonicMilliseconds == 70_000)
    #expect(throws: OperationApprovalErrorV0.notPending) {
        try authority.verifyAndConsume(
            rawSignature: authorityApprovalData(fixture.derived.rawSignatureHex),
            current: approvalCurrentState(),
            monotonicNowMilliseconds: 21_000
        )
    }
}

@Test func staleApprovalStateInvalidatesBeforeSignatureVerification() throws {
    let fixture = try authorityApprovalFixture()
    var authority = try approvalAuthority()
    var current = try approvalCurrentState()
    current = OperationApprovalCurrentStateV0(
        clientID: current.clientID,
        primaryConnectionID: current.primaryConnectionID,
        authorizationEpoch: 5,
        grantRevision: current.grantRevision,
        policyRevision: current.policyRevision,
        providerGeneration: current.providerGeneration,
        executionRevision: current.executionRevision,
        approvalPublicKeyX963: current.approvalPublicKeyX963
    )
    #expect(throws: OperationApprovalErrorV0.currentStateChanged) {
        try authority.verifyAndConsume(
            rawSignature: authorityApprovalData(fixture.derived.rawSignatureHex),
            current: current,
            monotonicNowMilliseconds: 20_000
        )
    }
    #expect(authority.state == .invalidated)
}

@Test func operationApprovalExpiresMonotonicallyAndBadProofIsTerminal() throws {
    let fixture = try authorityApprovalFixture()
    var expired = try approvalAuthority()
    #expect(throws: OperationApprovalErrorV0.expired) {
        try expired.verifyAndConsume(
            rawSignature: authorityApprovalData(fixture.derived.rawSignatureHex),
            current: approvalCurrentState(),
            monotonicNowMilliseconds: 70_000
        )
    }
    #expect(expired.state == .expired)

    var rejected = try approvalAuthority()
    #expect(throws: OperationApprovalErrorV0.invalidProof) {
        try rejected.verifyAndConsume(
            rawSignature: Data(repeating: 0, count: 64),
            current: approvalCurrentState(),
            monotonicNowMilliseconds: 20_000
        )
    }
    #expect(rejected.state == .rejected)
}
