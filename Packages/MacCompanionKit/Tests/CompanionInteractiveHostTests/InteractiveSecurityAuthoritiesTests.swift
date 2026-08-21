import CompanionInteractiveHost
import CompanionSecurity
import CryptoKit
import Foundation
import Testing

private let securityHostID = UUID(uuidString: "018f1000-0000-7000-8000-000000000001")!
private let securityClientID = UUID(uuidString: "018f2000-0000-7000-8000-000000000001")!
private let securityRequestID = UUID(uuidString: "018f6500-0000-7000-8000-000000000001")!
private let securityApprovalID = UUID(uuidString: "018f6600-0000-7000-8000-000000000001")!
private let securityDisplayID = UUID(uuidString: "018f6700-0000-7000-8000-000000000001")!
private let securityChannelID = UUID(uuidString: "018f6800-0000-7000-8000-000000000001")!
private let securitySessionID = UUID(uuidString: "018f6000-0000-7000-8000-000000000001")!
private let securityFingerprint = Data((0x80..<0xa0).map(UInt8.init))
private let securityConnectionID = Data((0x00..<0x10).map(UInt8.init))
private let securityServerChallenge = Data((0x30..<0x50).map(UInt8.init))
private let securityCredential = Data((0xe0...0xff).map(UInt8.init))
private let securityClientNonce = Data((0x10..<0x30).map(UInt8.init))
private let securityHostNonce = Data((0x30..<0x50).map(UInt8.init))

private func approvalKey() throws -> P256.Signing.PrivateKey {
    var scalar = Data(repeating: 0, count: 32)
    scalar[31] = 2
    return try P256.Signing.PrivateKey(rawRepresentation: scalar)
}

private func approvalAuthority() throws -> InteractiveApprovalAuthority {
    try InteractiveApprovalAuthority(
        hostID: securityHostID,
        hostFingerprint: securityFingerprint,
        clientID: securityClientID,
        primaryConnectionID: securityConnectionID,
        requestID: securityRequestID,
        approvalID: securityApprovalID,
        serverChallenge: securityServerChallenge,
        authorizationEpoch: 4,
        grantRevision: 5,
        policyRevision: 6,
        selectedDisplayID: securityDisplayID,
        initialSurface: .desktop,
        effects: [.view, .pointer, .keyboard, .text],
        issuedAtUnixMilliseconds: 1_724_000_000_000,
        expiresAtUnixMilliseconds: 1_724_000_060_000,
        approvalPublicKeyX963: try approvalKey().publicKey.x963Representation,
        issuedAtMonotonicMilliseconds: 1_000,
        expiresAtMonotonicMilliseconds: 61_000
    )
}

private func approvalCurrent(epoch: UInt64 = 4) throws -> InteractiveApprovalCurrentState {
    InteractiveApprovalCurrentState(
        clientID: securityClientID,
        primaryConnectionID: securityConnectionID,
        authorizationEpoch: epoch,
        grantRevision: 5,
        policyRevision: 6,
        approvalPublicKeyX963: try approvalKey().publicKey.x963Representation
    )
}

private func approvalSignature() throws -> Data {
    let input = try CompanionSecurityV0.interactiveApprovalSigningInput(
        hostID: securityHostID,
        hostFingerprint: securityFingerprint,
        clientID: securityClientID,
        primaryConnectionID: securityConnectionID,
        requestID: securityRequestID,
        approvalID: securityApprovalID,
        serverChallenge: securityServerChallenge,
        authorizationEpoch: 4,
        grantRevision: 5,
        policyRevision: 6,
        selectedDisplayID: securityDisplayID,
        initialSurface: .desktop,
        effects: [.view, .pointer, .keyboard, .text],
        issuedAtUnixMilliseconds: 1_724_000_000_000,
        expiresAtUnixMilliseconds: 1_724_000_060_000,
        selectedMajor: 0,
        selectedMinor: 1
    )
    return try approvalKey().signature(for: input).rawRepresentation
}

private func channelCurrent(epoch: UInt64 = 4) -> InteractiveChannelCurrentState {
    InteractiveChannelCurrentState(
        clientID: securityClientID,
        primaryConnectionID: securityConnectionID,
        interactiveSessionID: securitySessionID,
        authorizationEpoch: epoch
    )
}

private func channelAuthority(role: InteractiveChannelRole = .media) throws -> InteractiveChannelCredentialAuthority {
    try InteractiveChannelCredentialAuthority(
        channelID: securityChannelID,
        role: role,
        credential: securityCredential,
        hostID: securityHostID,
        hostFingerprint: securityFingerprint,
        clientID: securityClientID,
        primaryConnectionID: securityConnectionID,
        interactiveSessionID: securitySessionID,
        authorizationEpoch: 4,
        issuedAtMonotonicMilliseconds: 1_000,
        expiresAtMonotonicMilliseconds: 31_000
    )
}

private func channelProof(role: InteractiveChannelRole = .media) throws -> Data {
    let transcript = try CompanionSecurityV0.interactiveChannelTranscriptInput(
        channelID: securityChannelID,
        role: role,
        hostID: securityHostID,
        hostFingerprint: securityFingerprint,
        clientID: securityClientID,
        primaryConnectionID: securityConnectionID,
        interactiveSessionID: securitySessionID,
        authorizationEpoch: 4,
        clientNonce: securityClientNonce,
        hostNonce: securityHostNonce,
        selectedMajor: 0,
        selectedMinor: 1
    )
    return try CompanionSecurityV0.interactiveChannelClientProof(
        credential: securityCredential,
        transcriptDigest: CompanionSecurityV0.interactiveChannelTranscriptDigest(transcript)
    )
}

@Test func approvalSuccessConsumesExactlyOnceAndReturnsBoundIntent() throws {
    var authority = try approvalAuthority()
    let intent = try authority.verifyAndConsume(
        rawSignature: approvalSignature(),
        current: approvalCurrent(),
        monotonicNowMilliseconds: 60_999
    )
    #expect(authority.state == .consumed)
    #expect(intent.requestID == securityRequestID)
    #expect(intent.effects == [.view, .pointer, .keyboard, .text])
    #expect(throws: InteractiveSecurityAuthorityError.notPending) {
        try authority.verifyAndConsume(
            rawSignature: approvalSignature(),
            current: approvalCurrent(),
            monotonicNowMilliseconds: 60_999
        )
    }
}

@Test func approvalEpochChangeAndExactExpiryConsumeNoSession() throws {
    var changed = try approvalAuthority()
    #expect(throws: InteractiveSecurityAuthorityError.currentStateChanged) {
        try changed.verifyAndConsume(
            rawSignature: approvalSignature(),
            current: approvalCurrent(epoch: 5),
            monotonicNowMilliseconds: 2_000
        )
    }
    #expect(changed.state == .invalidated)

    var expired = try approvalAuthority()
    #expect(throws: InteractiveSecurityAuthorityError.expired) {
        try expired.verifyAndConsume(
            rawSignature: approvalSignature(),
            current: approvalCurrent(),
            monotonicNowMilliseconds: 61_000
        )
    }
    #expect(expired.state == .expired)
}

@Test func invalidApprovalProofIsTerminalNotRetryable() throws {
    var authority = try approvalAuthority()
    var signature = try approvalSignature()
    signature[0] ^= 1
    #expect(throws: InteractiveSecurityAuthorityError.invalidProof) {
        try authority.verifyAndConsume(
            rawSignature: signature,
            current: approvalCurrent(),
            monotonicNowMilliseconds: 2_000
        )
    }
    #expect(authority.state == .rejected)
}

@Test func channelCredentialConsumesOnceAndReturnsServerProof() throws {
    var authority = try channelAuthority()
    let challenge = try authority.beginChallenge(
        clientNonce: securityClientNonce,
        hostNonce: securityHostNonce,
        current: channelCurrent(),
        monotonicNowMilliseconds: 2_000
    )
    #expect(challenge.role == .media)
    let acceptance = try authority.verifyAndConsume(
        clientProof: channelProof(),
        current: channelCurrent(),
        monotonicNowMilliseconds: 2_001
    )
    #expect(authority.state == .consumed)
    #expect(acceptance.serverProof.count == 32)
    #expect(throws: InteractiveSecurityAuthorityError.notChallenged) {
        try authority.verifyAndConsume(
            clientProof: channelProof(),
            current: channelCurrent(),
            monotonicNowMilliseconds: 2_002
        )
    }
}

@Test func channelRoleSwapProofIsRejectedTerminally() throws {
    var authority = try channelAuthority(role: .input)
    _ = try authority.beginChallenge(
        clientNonce: securityClientNonce,
        hostNonce: securityHostNonce,
        current: channelCurrent(),
        monotonicNowMilliseconds: 2_000
    )
    #expect(throws: InteractiveSecurityAuthorityError.invalidProof) {
        try authority.verifyAndConsume(
            clientProof: channelProof(role: .media),
            current: channelCurrent(),
            monotonicNowMilliseconds: 2_001
        )
    }
    #expect(authority.state == .rejected)
}

@Test func channelExpiryAndPrimaryStateChangeDestroyCredential() throws {
    var expired = try channelAuthority()
    #expect(throws: InteractiveSecurityAuthorityError.expired) {
        try expired.beginChallenge(
            clientNonce: securityClientNonce,
            hostNonce: securityHostNonce,
            current: channelCurrent(),
            monotonicNowMilliseconds: 31_000
        )
    }
    #expect(expired.state == .expired)

    var changed = try channelAuthority()
    _ = try changed.beginChallenge(
        clientNonce: securityClientNonce,
        hostNonce: securityHostNonce,
        current: channelCurrent(),
        monotonicNowMilliseconds: 2_000
    )
    #expect(throws: InteractiveSecurityAuthorityError.currentStateChanged) {
        try changed.verifyAndConsume(
            clientProof: channelProof(),
            current: channelCurrent(epoch: 5),
            monotonicNowMilliseconds: 2_001
        )
    }
    #expect(changed.state == .invalidated)
}

@Test func authorityConstructionRejectsMalformedStaticBindings() throws {
    #expect(throws: CompanionSecurityError.invalidPublicKey) {
        try InteractiveApprovalAuthority(
            hostID: securityHostID,
            hostFingerprint: securityFingerprint,
            clientID: securityClientID,
            primaryConnectionID: securityConnectionID,
            requestID: securityRequestID,
            approvalID: securityApprovalID,
            serverChallenge: securityServerChallenge,
            authorizationEpoch: 4,
            grantRevision: 5,
            policyRevision: 6,
            selectedDisplayID: securityDisplayID,
            initialSurface: .desktop,
            effects: [.view],
            issuedAtUnixMilliseconds: 1,
            expiresAtUnixMilliseconds: 2,
            approvalPublicKeyX963: Data(repeating: 0, count: 65),
            issuedAtMonotonicMilliseconds: 1,
            expiresAtMonotonicMilliseconds: 2
        )
    }
    #expect(throws: CompanionSecurityError.invalidLength(
        field: "hostFingerprint",
        expected: 32,
        actual: 31
    )) {
        try InteractiveChannelCredentialAuthority(
            channelID: securityChannelID,
            role: .media,
            credential: securityCredential,
            hostID: securityHostID,
            hostFingerprint: Data(repeating: 0, count: 31),
            clientID: securityClientID,
            primaryConnectionID: securityConnectionID,
            interactiveSessionID: securitySessionID,
            authorizationEpoch: 4,
            issuedAtMonotonicMilliseconds: 1,
            expiresAtMonotonicMilliseconds: 2
        )
    }
}
