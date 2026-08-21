import CompanionInteractiveHost
import CompanionSecurity
import CryptoKit
import Foundation
import Testing

private let bootstrapHostID = UUID(uuidString: "018f1000-0000-7000-8000-000000000001")!
private let bootstrapClientID = UUID(uuidString: "018f2000-0000-7000-8000-000000000001")!
private let bootstrapRequestID = UUID(uuidString: "018f6500-0000-7000-8000-000000000001")!
private let bootstrapApprovalID = UUID(uuidString: "018f6600-0000-7000-8000-000000000001")!
private let bootstrapDisplayID = UUID(uuidString: "018f6700-0000-7000-8000-000000000001")!
private let bootstrapSessionID = UUID(uuidString: "018f6000-0000-7000-8000-000000000001")!
private let bootstrapInputChannelID = UUID(uuidString: "018f6800-0000-7000-8000-000000000001")!
private let bootstrapMediaChannelID = UUID(uuidString: "018f6800-0000-7000-8000-000000000002")!
private let bootstrapFingerprint = Data((0x80..<0xa0).map(UInt8.init))
private let bootstrapConnectionID = Data((0x00..<0x10).map(UInt8.init))
private let bootstrapChallenge = Data((0x30..<0x50).map(UInt8.init))
private let bootstrapInputCredential = Data((0x40..<0x60).map(UInt8.init))
private let bootstrapMediaCredential = Data((0x60..<0x80).map(UInt8.init))

private func bootstrapApprovalKey() throws -> P256.Signing.PrivateKey {
    var scalar = Data(repeating: 0, count: 32)
    scalar[31] = 2
    return try P256.Signing.PrivateKey(rawRepresentation: scalar)
}

private func bootstrapApprovalAuthority() throws -> InteractiveApprovalAuthority {
    try InteractiveApprovalAuthority(
        hostID: bootstrapHostID,
        hostFingerprint: bootstrapFingerprint,
        clientID: bootstrapClientID,
        primaryConnectionID: bootstrapConnectionID,
        requestID: bootstrapRequestID,
        approvalID: bootstrapApprovalID,
        serverChallenge: bootstrapChallenge,
        authorizationEpoch: 4,
        grantRevision: 5,
        policyRevision: 6,
        selectedDisplayID: bootstrapDisplayID,
        initialSurface: .desktop,
        effects: [.view, .pointer, .keyboard, .text],
        issuedAtUnixMilliseconds: 1_724_000_000_000,
        expiresAtUnixMilliseconds: 1_724_000_060_000,
        approvalPublicKeyX963: try bootstrapApprovalKey().publicKey.x963Representation,
        issuedAtMonotonicMilliseconds: 1_000,
        expiresAtMonotonicMilliseconds: 61_000
    )
}

private func bootstrapCurrent(epoch: UInt64 = 4) throws -> InteractiveApprovalCurrentState {
    InteractiveApprovalCurrentState(
        clientID: bootstrapClientID,
        primaryConnectionID: bootstrapConnectionID,
        authorizationEpoch: epoch,
        grantRevision: 5,
        policyRevision: 6,
        approvalPublicKeyX963: try bootstrapApprovalKey().publicKey.x963Representation
    )
}

private func bootstrapSignature() throws -> Data {
    let input = try CompanionSecurityV0.interactiveApprovalSigningInput(
        hostID: bootstrapHostID,
        hostFingerprint: bootstrapFingerprint,
        clientID: bootstrapClientID,
        primaryConnectionID: bootstrapConnectionID,
        requestID: bootstrapRequestID,
        approvalID: bootstrapApprovalID,
        serverChallenge: bootstrapChallenge,
        authorizationEpoch: 4,
        grantRevision: 5,
        policyRevision: 6,
        selectedDisplayID: bootstrapDisplayID,
        initialSurface: .desktop,
        effects: [.view, .pointer, .keyboard, .text],
        issuedAtUnixMilliseconds: 1_724_000_000_000,
        expiresAtUnixMilliseconds: 1_724_000_060_000,
        selectedMajor: 0,
        selectedMinor: 1
    )
    return try bootstrapApprovalKey().signature(for: input).rawRepresentation
}

private func bootstrapMaterials(
    inputCredential: Data = bootstrapInputCredential,
    mediaCredential: Data = bootstrapMediaCredential
) -> InteractiveSessionBootstrapMaterials {
    InteractiveSessionBootstrapMaterials(
        interactiveSessionID: bootstrapSessionID,
        inputChannelID: bootstrapInputChannelID,
        inputCredential: inputCredential,
        mediaChannelID: bootstrapMediaChannelID,
        mediaCredential: mediaCredential
    )
}

@Test func approvalCreatesStartingSessionAndBothRoleAuthoritiesAtomically() throws {
    var authority = InteractiveSessionBootstrapAuthority(
        approvalAuthority: try bootstrapApprovalAuthority()
    )
    var result = try authority.verifyAndCreate(
        rawApprovalSignature: bootstrapSignature(),
        current: bootstrapCurrent(),
        materials: bootstrapMaterials(),
        wallNowUnixMilliseconds: 1_724_000_010_000,
        monotonicNowMilliseconds: 2_000
    )

    #expect(authority.didCreateSession)
    #expect(authority.approvalAuthority.state == .consumed)
    #expect(result.session.state == .starting)
    #expect(result.session.sessionID == bootstrapSessionID)
    #expect(result.session.sessionDeadlineMonotonicMilliseconds == 14_402_000)
    #expect(result.effects == [.beginExecutorSetup, .publishState])
    #expect(result.approvedEffects == [.view, .pointer, .keyboard, .text])
    #expect(result.approvedInteractionClasses
        == [.view, .pointer, .keyboard, .text])
    #expect(result.acceptedBody.authorizationEpoch.rawValue == 4)
    #expect(result.acceptedBody.expiresAtUnixMilliseconds == 1_724_014_410_000)
    #expect(result.acceptedBody.inputChannel.role == .input)
    #expect(result.acceptedBody.mediaChannel.role == .media)

    let current = InteractiveChannelCurrentState(
        clientID: bootstrapClientID,
        primaryConnectionID: bootstrapConnectionID,
        interactiveSessionID: bootstrapSessionID,
        authorizationEpoch: 4
    )
    let inputChallenge = try result.inputChannelAuthority.beginChallenge(
        clientNonce: Data(repeating: 1, count: 32),
        hostNonce: Data(repeating: 2, count: 32),
        current: current,
        monotonicNowMilliseconds: 2_001
    )
    let mediaChallenge = try result.mediaChannelAuthority.beginChallenge(
        clientNonce: Data(repeating: 3, count: 32),
        hostNonce: Data(repeating: 4, count: 32),
        current: current,
        monotonicNowMilliseconds: 2_001
    )
    #expect(inputChallenge.role == .input)
    #expect(mediaChallenge.role == .media)
}

@Test func successfulBootstrapCannotCreateASecondSession() throws {
    var authority = InteractiveSessionBootstrapAuthority(
        approvalAuthority: try bootstrapApprovalAuthority()
    )
    _ = try authority.verifyAndCreate(
        rawApprovalSignature: bootstrapSignature(),
        current: bootstrapCurrent(),
        materials: bootstrapMaterials(),
        wallNowUnixMilliseconds: 1_724_000_010_000,
        monotonicNowMilliseconds: 2_000
    )
    #expect(throws: InteractiveSessionBootstrapError.alreadyCreated) {
        try authority.verifyAndCreate(
            rawApprovalSignature: bootstrapSignature(),
            current: bootstrapCurrent(),
            materials: bootstrapMaterials(),
            wallNowUnixMilliseconds: 1_724_000_010_001,
            monotonicNowMilliseconds: 2_001
        )
    }
}

@Test func invalidHostMaterialsRollBackApprovalConsumption() throws {
    var authority = InteractiveSessionBootstrapAuthority(
        approvalAuthority: try bootstrapApprovalAuthority()
    )
    #expect(throws: (any Error).self) {
        try authority.verifyAndCreate(
            rawApprovalSignature: bootstrapSignature(),
            current: bootstrapCurrent(),
            materials: bootstrapMaterials(mediaCredential: bootstrapInputCredential),
            wallNowUnixMilliseconds: 1_724_000_010_000,
            monotonicNowMilliseconds: 2_000
        )
    }
    #expect(!authority.didCreateSession)
    #expect(authority.approvalAuthority.state == .pending)

    let result = try authority.verifyAndCreate(
        rawApprovalSignature: bootstrapSignature(),
        current: bootstrapCurrent(),
        materials: bootstrapMaterials(),
        wallNowUnixMilliseconds: 1_724_000_010_000,
        monotonicNowMilliseconds: 2_000
    )
    #expect(result.session.state == .starting)
}

@Test func proofOrLiveStateFailureIsTerminalAndCreatesNoSession() throws {
    var badProof = InteractiveSessionBootstrapAuthority(
        approvalAuthority: try bootstrapApprovalAuthority()
    )
    var signature = try bootstrapSignature()
    signature[0] ^= 1
    #expect(throws: InteractiveSecurityAuthorityError.invalidProof) {
        try badProof.verifyAndCreate(
            rawApprovalSignature: signature,
            current: bootstrapCurrent(),
            materials: bootstrapMaterials(),
            wallNowUnixMilliseconds: 1_724_000_010_000,
            monotonicNowMilliseconds: 2_000
        )
    }
    #expect(!badProof.didCreateSession)
    #expect(badProof.approvalAuthority.state == .rejected)

    var changed = InteractiveSessionBootstrapAuthority(
        approvalAuthority: try bootstrapApprovalAuthority()
    )
    #expect(throws: InteractiveSecurityAuthorityError.currentStateChanged) {
        try changed.verifyAndCreate(
            rawApprovalSignature: bootstrapSignature(),
            current: bootstrapCurrent(epoch: 5),
            materials: bootstrapMaterials(),
            wallNowUnixMilliseconds: 1_724_000_010_000,
            monotonicNowMilliseconds: 2_000
        )
    }
    #expect(!changed.didCreateSession)
    #expect(changed.approvalAuthority.state == .invalidated)
}
