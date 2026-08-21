import CompanionDomain
import CompanionSecurity
import CompanionTestSupport
import CryptoKit
import Foundation
import Testing

private struct OperationBindingFixture: Decodable {
    struct Inputs: Decodable {
        let hostID: UUID
        let deviceID: UUID
        let clientID: UUID
        let operationID: UUID
        let capabilityID: String
        let schemaVersion: UInt32
        let providerID: String
        let providerVersion: String
        let providerGeneration: UUID
        let executionRevision: UUID
        let canonicalParametersUTF8: String
        let requiredHostState: HostState
        let authorizationEpoch: UInt64
        let grantRevision: UInt64
        let policyRevision: UInt64
        let expiresAtUnixMilliseconds: UInt64
        let selectedMajor: UInt16
        let selectedMinor: UInt16
    }
    struct Derived: Decodable {
        let canonicalParametersSHA256Hex: String
        let operationDigestInputHex: String
        let operationDigestSHA256Hex: String
    }
    let inputs: Inputs
    let derived: Derived
}

private func operationFixture() throws -> OperationBindingFixture {
    let url = FixturePaths.authoritativeFixtures()
        .appendingPathComponent("crypto/operation-v0.1.json")
    return try JSONDecoder().decode(
        OperationBindingFixture.self,
        from: Data(contentsOf: url)
    )
}

private func operationData(hex: String) throws -> Data {
    guard hex.count.isMultiple(of: 2) else { throw CocoaError(.fileReadCorruptFile) }
    var result = Data()
    var index = hex.startIndex
    while index < hex.endIndex {
        let end = hex.index(index, offsetBy: 2)
        guard let byte = UInt8(hex[index..<end], radix: 16) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        result.append(byte)
        index = end
    }
    return result
}

private func fixtureEffects() throws -> CapabilityEffectFacts {
    try CapabilityEffectFacts(
        dataAccess: .none,
        changesLocalState: .reversible,
        mayDisruptUser: false,
        invokesExternalService: false,
        usesCredentials: false,
        destructive: false,
        requiresForegroundSession: false,
        allowedWhileLocked: true,
        cancellation: .notApplicable
    )
}

private func fixtureOperationInput(
    operationID: UUID? = nil,
    authorizationEpoch: UInt64? = nil,
    effects: CapabilityEffectFacts? = nil
) throws -> Data {
    let fixture = try operationFixture()
    let input = fixture.inputs
    return try CompanionSecurityV0.operationDigestInput(
        hostID: input.hostID,
        deviceID: input.deviceID,
        clientID: input.clientID,
        operationID: operationID ?? input.operationID,
        capabilityID: input.capabilityID,
        schemaVersion: input.schemaVersion,
        providerID: input.providerID,
        providerVersion: input.providerVersion,
        providerGeneration: input.providerGeneration,
        executionRevision: input.executionRevision,
        canonicalParametersSHA256: Data(SHA256.hash(
            data: Data(input.canonicalParametersUTF8.utf8)
        )),
        effects: try effects ?? fixtureEffects(),
        requiredHostState: input.requiredHostState,
        authorizationEpoch: authorizationEpoch ?? input.authorizationEpoch,
        grantRevision: input.grantRevision,
        policyRevision: input.policyRevision,
        expiresAtUnixMilliseconds: input.expiresAtUnixMilliseconds,
        selectedMajor: input.selectedMajor,
        selectedMinor: input.selectedMinor
    )
}

@Test func operationBindingMatchesIndependentGoldenVector() throws {
    let fixture = try operationFixture()
    let input = try fixtureOperationInput()
    let parametersDigest = Data(SHA256.hash(
        data: Data(fixture.inputs.canonicalParametersUTF8.utf8)
    ))
    #expect(parametersDigest == (try operationData(
        hex: fixture.derived.canonicalParametersSHA256Hex
    )))
    #expect(input == (try operationData(hex: fixture.derived.operationDigestInputHex)))
    #expect(CompanionSecurityV0.operationDigest(input) == (try operationData(
        hex: fixture.derived.operationDigestSHA256Hex
    )))
}

@Test func operationBindingFencesIdentityEpochAndEffects() throws {
    let baseline = CompanionSecurityV0.operationDigest(try fixtureOperationInput())
    let changedEffects = try CapabilityEffectFacts(
        dataAccess: .none,
        changesLocalState: .irreversible,
        mayDisruptUser: false,
        invokesExternalService: false,
        usesCredentials: false,
        destructive: true,
        requiresForegroundSession: false,
        allowedWhileLocked: true,
        cancellation: .notApplicable
    )
    #expect(CompanionSecurityV0.operationDigest(try fixtureOperationInput(
        operationID: UUID()
    )) != baseline)
    #expect(CompanionSecurityV0.operationDigest(try fixtureOperationInput(
        authorizationEpoch: 5
    )) != baseline)
    #expect(CompanionSecurityV0.operationDigest(try fixtureOperationInput(
        effects: changedEffects
    )) != baseline)
}

@Test func operationBindingRejectsAmbiguousIdentifiersAndUnsafeRevisions() throws {
    let fixture = try operationFixture()
    let input = fixture.inputs
    #expect(throws: CompanionSecurityError.invalidValue(field: "capabilityID")) {
        try CompanionSecurityV0.operationDigestInput(
            hostID: input.hostID,
            deviceID: input.deviceID,
            clientID: input.clientID,
            operationID: input.operationID,
            capabilityID: "not canonical/space",
            schemaVersion: 1,
            providerID: input.providerID,
            providerVersion: input.providerVersion,
            providerGeneration: input.providerGeneration,
            executionRevision: input.executionRevision,
            canonicalParametersSHA256: Data(repeating: 0, count: 32),
            effects: fixtureEffects(),
            requiredHostState: .userSessionActive,
            authorizationEpoch: 1,
            grantRevision: 1,
            policyRevision: 1,
            expiresAtUnixMilliseconds: 1,
            selectedMajor: 0,
            selectedMinor: 1
        )
    }
    #expect(throws: CompanionSecurityError.invalidValue(field: "authorizationEpoch")) {
        try fixtureOperationInput(authorizationEpoch: 0)
    }
}
