@testable import CompanionClient
import CompanionDiscovery
import CompanionDomain
import CompanionPresentation
import CompanionWire
import Foundation
import Testing

private let presentationPairingID = UUID(
    uuidString: "018f9300-0000-7000-8000-000000000001"
)!
private let presentationRequestID = UUID(
    uuidString: "018f9300-0000-7000-8000-000000000002"
)!
private let presentationHostID = UUID(
    uuidString: "018f9300-0000-7000-8000-000000000003"
)!
private let presentationDeviceID = UUID(
    uuidString: "018f9300-0000-7000-8000-000000000004"
)!
private let presentationClientID = UUID(
    uuidString: "018f9300-0000-7000-8000-000000000005"
)!
private let presentationFingerprint = Data(0x00...0x1f)

private func pairingPresentationQR(
    pairingID: UUID = presentationPairingID,
    expiresAt: Int64 = 2_000_000
) throws -> PairingQRCodePayload {
    try PairingQRCodePayload(
        pairingID: WireUUID(pairingID),
        oneTimeSecret: WireBytes32(Data(0x80...0x9f)),
        expiresAtUnixMilliseconds: expiresAt,
        hostFingerprint: WireFingerprint(presentationFingerprint),
        endpoints: [
            try EndpointCandidate(
                kind: .bonjour,
                value: "studio-mac._maccompanion._tcp.local.",
                port: 47_474
            ),
            try EndpointCandidate(
                kind: .ipv4,
                value: "192.168.10.42",
                port: 47_474
            ),
        ]
    )
}

private func pairingPresentationApproval(
    pairingID: UUID = presentationPairingID
) -> ClientPairingApprovalV0 {
    ClientPairingApprovalV0(
        pairingID: pairingID,
        transcriptDigest: Data(repeating: 0x44, count: 32),
        authenticationString: "12A-4BC",
        expiresAtUnixMilliseconds: 2_000_000
    )
}

private func pairingPresentationHost(
    pairingID: UUID = presentationPairingID,
    hostID: UUID = presentationHostID
) -> ClientPairedHostV0 {
    ClientPairedHostV0(
        pairingID: pairingID,
        clientID: presentationClientID,
        hostID: hostID,
        deviceID: presentationDeviceID,
        hostFingerprint: presentationFingerprint,
        endpoints: (try! pairingPresentationQR()).endpoints,
        deviceState: .activeMonitorOnly,
        authorizationEpoch: .init(rawValue: 1),
        grantRevision: .init(rawValue: 1),
        policyRevision: .init(rawValue: 7)
    )
}

private func acceptedPairingPresentation() throws -> PairingClientPresentation {
    var value = PairingClientPresentation()
    let qr = try pairingPresentationQR()
    try value.receiveScan(
        PairingQRCodeCodec.encode(qr),
        nowUnixMilliseconds: 1_000_000
    )
    _ = try value.acceptPreview(requestID: presentationRequestID)
    return value
}

private func verifiedPairingPresentation() throws -> PairingClientPresentation {
    var value = try acceptedPairingPresentation()
    try value.transportStarted(
        requestID: presentationRequestID,
        pairingID: presentationPairingID
    )
    try value.pinnedTLSAccepted(
        requestID: presentationRequestID,
        pairingID: presentationPairingID
    )
    try value.transcriptVerificationStarted(
        requestID: presentationRequestID,
        pairingID: presentationPairingID
    )
    try value.receiveVerifiedApproval(
        requestID: presentationRequestID,
        approval: pairingPresentationApproval()
    )
    return value
}

@Test func scanIsOnlyAnUntrustedPreviewUntilExplicitAcceptance() throws {
    var value = PairingClientPresentation()
    let qr = try pairingPresentationQR()
    try value.receiveScan(
        PairingQRCodeCodec.encode(qr),
        nowUnixMilliseconds: 1_000_000
    )

    #expect(value.phase == .preview)
    #expect(value.preview?.pairingID == presentationPairingID)
    #expect(value.preview?.fingerprintTrust == .unverifiedScan)
    #expect(value.preview?.routeKinds == [.bonjour, .ipv4])
    #expect(value.preview?.routeCandidateCount == 2)
    #expect(value.preview?.fingerprint
        == "00010203:04050607:08090a0b:0c0d0e0f:10111213:14151617:18191a1b:1c1d1e1f")

    let intent = try value.acceptPreview(requestID: presentationRequestID)
    #expect(intent.requestID == presentationRequestID)
    #expect(intent.qr == qr)
    #expect(value.phase == .starting)
    #expect(value.authentication == nil)
}

@Test func malformedOrExpiredScanPublishesOnlyAClosedFailure() throws {
    var malformed = PairingClientPresentation()
    #expect(throws: PairingClientPresentationError.invalidOrExpiredQRCode) {
        try malformed.receiveScan("not-a-pairing-code", nowUnixMilliseconds: 1)
    }
    #expect(malformed.phase == .failed)
    #expect(malformed.failure == .invalidOrExpiredCode)
    #expect(malformed.preview == nil)

    var expired = PairingClientPresentation()
    let qr = try pairingPresentationQR(expiresAt: 100)
    #expect(throws: PairingClientPresentationError.invalidOrExpiredQRCode) {
        try expired.receiveScan(
            PairingQRCodeCodec.encode(qr),
            nowUnixMilliseconds: 100
        )
    }
    #expect(expired.failure == .invalidOrExpiredCode)
}

@Test func fingerprintBecomesTrustedOnlyAfterPinnedTLS() throws {
    var value = try acceptedPairingPresentation()
    try value.transportStarted(
        requestID: presentationRequestID,
        pairingID: presentationPairingID
    )
    #expect(value.preview?.fingerprintTrust == .unverifiedScan)
    #expect(value.securityProgress == .connecting)

    try value.pinnedTLSAccepted(
        requestID: presentationRequestID,
        pairingID: presentationPairingID
    )
    #expect(value.preview?.fingerprintTrust == .pinnedTLSVerified)
    #expect(value.securityProgress == .pinnedTLSVerified)
}

@Test func authenticationStringCannotAppearBeforeTranscriptVerification() throws {
    var value = try acceptedPairingPresentation()
    try value.transportStarted(
        requestID: presentationRequestID,
        pairingID: presentationPairingID
    )

    #expect(throws: PairingClientPresentationError.invalidPhase) {
        try value.receiveVerifiedApproval(
            requestID: presentationRequestID,
            approval: pairingPresentationApproval()
        )
    }
    #expect(value.authentication == nil)

    try value.pinnedTLSAccepted(
        requestID: presentationRequestID,
        pairingID: presentationPairingID
    )
    try value.transcriptVerificationStarted(
        requestID: presentationRequestID,
        pairingID: presentationPairingID
    )
    try value.receiveVerifiedApproval(
        requestID: presentationRequestID,
        approval: pairingPresentationApproval()
    )
    #expect(value.phase == .compareOnMac)
    #expect(value.authentication?.authenticationString == "12A-4BC")
}

@Test func staleRequestAndDifferentPairingCannotAdvancePresentation() throws {
    var stale = try acceptedPairingPresentation()
    #expect(throws: PairingClientPresentationError.staleRequest) {
        try stale.transportStarted(
            requestID: UUID(),
            pairingID: presentationPairingID
        )
    }

    var mismatch = try acceptedPairingPresentation()
    #expect(throws: PairingClientPresentationError.pairingMismatch) {
        try mismatch.transportStarted(
            requestID: presentationRequestID,
            pairingID: UUID()
        )
    }
}

@Test func verifiedCompletionIsNotPairedUntilExactDurableCommit() throws {
    var value = try verifiedPairingPresentation()
    let host = pairingPresentationHost()
    let commitID = UUID()
    let intent = try value.receiveVerifiedCompletion(
        requestID: presentationRequestID,
        host: host,
        commitID: commitID
    )

    #expect(value.phase == .saving)
    #expect(value.pairedHost == nil)
    #expect(value.authentication == nil)
    #expect(intent.host == host)

    #expect(throws: PairingClientPresentationError.persistenceMismatch) {
        try value.durableCommitSucceeded(
            commitID: commitID,
            storedHost: pairingPresentationHost(hostID: UUID())
        )
    }
    #expect(value.phase == .saving)

    try value.durableCommitSucceeded(commitID: commitID, storedHost: host)
    #expect(value.phase == .paired)
    #expect(value.pairedHost?.hostID == presentationHostID)
    #expect(value.pairedHost?.deviceID == presentationDeviceID)
    #expect(value.pairedHost?.access == .activeMonitorOnly)
    #expect(value.preview == nil)
}

@Test func failureClearsSASAndAllAttemptPresentation() throws {
    var value = try verifiedPairingPresentation()
    try value.fail(.hostRejected)
    #expect(value.phase == .failed)
    #expect(value.failure == .hostRejected)
    #expect(value.authentication == nil)
    #expect(value.preview == nil)
    #expect(value.pairedHost == nil)

    value.reset()
    #expect(value.phase == .scanning)
    #expect(value.failure == nil)
}
