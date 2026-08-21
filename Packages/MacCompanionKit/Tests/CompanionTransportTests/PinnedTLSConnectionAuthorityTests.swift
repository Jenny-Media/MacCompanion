import CompanionTestSupport
import CompanionTransport
import CryptoKit
import Foundation
import Testing

private let transportSPKI = Data((0x00...0x5a).map(UInt8.init))
private let otherTransportSPKI = Data((0x01...0x5b).map(UInt8.init))

private func transportFingerprint(_ spki: Data = transportSPKI) -> Data {
    Data(SHA256.hash(data: spki))
}

private func peerEvidence(
    spki: Data = transportSPKI,
    major: UInt16 = 1,
    minor: UInt16 = 3,
    earlyData: Bool = false,
    trust: Bool = true
) -> TLSPeerEvidence {
    TLSPeerEvidence(
        negotiatedTLSMajor: major,
        negotiatedTLSMinor: minor,
        earlyDataAccepted: earlyData,
        pinnedLeafPolicyAccepted: trust,
        subjectPublicKeyInfoDER: spki
    )
}

private struct TLSSPKIFixture: Decodable {
    let subjectPublicKeyInfoDERHex: String
    let hostFingerprintSHA256Hex: String
    let mismatchedHostFingerprintSHA256Hex: String
}

private func transportData(hex: String) throws -> Data {
    guard hex.count.isMultiple(of: 2) else { throw CocoaError(.fileReadCorruptFile) }
    var data = Data()
    data.reserveCapacity(hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
        let end = hex.index(index, offsetBy: 2)
        guard let byte = UInt8(hex[index..<end], radix: 16) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data.append(byte)
        index = end
    }
    return data
}

@Test func authoritativeSPKIFixtureProducesExactPinnedFingerprint() throws {
    let url = FixturePaths.authoritativeFixtures()
        .appendingPathComponent("crypto/tls-spki-v0.1.json")
    let fixture = try JSONDecoder().decode(TLSSPKIFixture.self, from: Data(contentsOf: url))
    let spki = try transportData(hex: fixture.subjectPublicKeyInfoDERHex)
    let expected = try transportData(hex: fixture.hostFingerprintSHA256Hex)
    let mismatch = try transportData(hex: fixture.mismatchedHostFingerprintSHA256Hex)
    #expect(try PinnedTLSConnectionAuthority.hostFingerprint(
        subjectPublicKeyInfoDER: spki
    ) == expected)
    #expect(expected != mismatch)
}

@Test func pinnedTLS13PermitsOnlyRoleAuthenticationBeforeReady() throws {
    var authority = try PinnedTLSConnectionAuthority(
        role: .applicationPrimary,
        requiredHostFingerprint: transportFingerprint()
    )
    try authority.didConnectTCP()
    try authority.acceptPeer(peerEvidence())
    #expect(authority.phase == .awaitingRoleAuthentication)
    #expect(authority.observedHostFingerprint == transportFingerprint())
    try authority.admit(.applicationAuthentication)
    try authority.roleAuthenticationSucceeded()
    try authority.admit(.commandFrame)
    try authority.admit(.eventFrame)
    #expect(authority.phase == .ready)
}

@Test func noApplicationTrafficIsAdmittedBeforePinVerification() throws {
    var authority = try PinnedTLSConnectionAuthority(
        role: .pairingPrimary,
        requiredHostFingerprint: transportFingerprint()
    )
    #expect(throws: PinnedTLSAuthorityError.trafficNotAuthorized(
        role: .pairingPrimary,
        phase: .awaitingTCP,
        traffic: .pairingHandshake
    )) {
        try authority.admit(.pairingHandshake)
    }
    #expect(authority.phase == .closed)
}

@Test func pinMismatchIsTerminalAndNeverPublishesReadyIdentity() throws {
    var authority = try PinnedTLSConnectionAuthority(
        role: .applicationPrimary,
        requiredHostFingerprint: transportFingerprint()
    )
    try authority.didConnectTCP()
    #expect(throws: PinnedTLSAuthorityError.hostFingerprintMismatch) {
        try authority.acceptPeer(peerEvidence(spki: otherTransportSPKI))
    }
    #expect(authority.phase == .closed)
    #expect(authority.observedHostFingerprint == transportFingerprint(otherTransportSPKI))
}

@Test func earlyDataTLS12AndRejectedPinnedLeafPolicyAllFailClosed() throws {
    for evidence in [
        peerEvidence(earlyData: true),
        peerEvidence(major: 1, minor: 2),
        peerEvidence(trust: false),
    ] {
        var authority = try PinnedTLSConnectionAuthority(
            role: .applicationPrimary,
            requiredHostFingerprint: transportFingerprint()
        )
        try authority.didConnectTCP()
        #expect(throws: (any Error).self) {
            try authority.acceptPeer(evidence)
        }
        #expect(authority.phase == .closed)
    }
}

@Test func roleSeparationRejectsCrossChannelTrafficTerminally() throws {
    var input = try PinnedTLSConnectionAuthority(
        role: .interactiveInput,
        requiredHostFingerprint: transportFingerprint()
    )
    try input.didConnectTCP()
    try input.acceptPeer(peerEvidence())
    try input.admit(.interactiveChannelAuthentication)
    try input.roleAuthenticationSucceeded()
    #expect(throws: PinnedTLSAuthorityError.trafficNotAuthorized(
        role: .interactiveInput,
        phase: .ready,
        traffic: .mediaRecord
    )) {
        try input.admit(.mediaRecord)
    }
    #expect(input.phase == .closed)
}

@Test func malformedSPKIAndPrematurePromotionCannotBypassTLSGate() throws {
    #expect(throws: PinnedTLSAuthorityError.invalidPeerEvidence) {
        try PinnedTLSConnectionAuthority.hostFingerprint(subjectPublicKeyInfoDER: Data())
    }
    #expect(throws: PinnedTLSAuthorityError.invalidPeerEvidence) {
        try PinnedTLSConnectionAuthority.hostFingerprint(
            subjectPublicKeyInfoDER: Data(
                repeating: 0,
                count: PinnedTLSConnectionAuthority.maximumSubjectPublicKeyInfoBytes + 1
            )
        )
    }

    var authority = try PinnedTLSConnectionAuthority(
        role: .interactiveMedia,
        requiredHostFingerprint: transportFingerprint()
    )
    #expect(throws: PinnedTLSAuthorityError.invalidTransition(.awaitingTCP)) {
        try authority.roleAuthenticationSucceeded()
    }
    #expect(authority.phase == .awaitingTCP)
}

@Test func hostListenerBindingSeparatesServedIdentityFromClientPinAuthority() throws {
    let binding = try HostApplicationTLSBinding(
        evidence: HostTLSListenerEvidence(
            negotiatedTLSMajor: 1,
            negotiatedTLSMinor: 3,
            earlyDataAccepted: false,
            servedSubjectPublicKeyInfoDER: transportSPKI
        ),
        requiredHostFingerprint: transportFingerprint()
    )
    #expect(binding.hostFingerprint == transportFingerprint())
}

@Test func hostListenerBindingRejectsWrongIdentityTLSVersionAndEarlyData() throws {
    #expect(throws: HostTLSListenerBindingError.servedHostIdentityMismatch) {
        _ = try HostApplicationTLSBinding(
            evidence: HostTLSListenerEvidence(
                negotiatedTLSMajor: 1,
                negotiatedTLSMinor: 3,
                earlyDataAccepted: false,
                servedSubjectPublicKeyInfoDER: otherTransportSPKI
            ),
            requiredHostFingerprint: transportFingerprint()
        )
    }
    #expect(throws: HostTLSListenerBindingError.unsupportedTLSVersion) {
        _ = try HostApplicationTLSBinding(
            evidence: HostTLSListenerEvidence(
                negotiatedTLSMajor: 1,
                negotiatedTLSMinor: 2,
                earlyDataAccepted: false,
                servedSubjectPublicKeyInfoDER: transportSPKI
            ),
            requiredHostFingerprint: transportFingerprint()
        )
    }
    #expect(throws: HostTLSListenerBindingError.earlyDataAccepted) {
        _ = try HostApplicationTLSBinding(
            evidence: HostTLSListenerEvidence(
                negotiatedTLSMajor: 1,
                negotiatedTLSMinor: 3,
                earlyDataAccepted: true,
                servedSubjectPublicKeyInfoDER: transportSPKI
            ),
            requiredHostFingerprint: transportFingerprint()
        )
    }
}
