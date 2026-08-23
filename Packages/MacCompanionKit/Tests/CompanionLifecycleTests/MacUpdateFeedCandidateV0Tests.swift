import CompanionLifecycle
import Foundation
import Testing

private let candidateKeyV0 =
    Data(repeating: 0x5A, count: 32).base64EncodedString()
private let archiveSignatureV0 =
    Data(repeating: 0xA5, count: 64).base64EncodedString()

private func candidateAuthority(
    channel: String = "beta"
) throws -> MacUpdateReleaseAuthorityV0 {
    try MacUpdateReleaseAuthorityV0(
        profile: MacUpdateReleaseAuthorityV0.profile,
        channel: channel,
        feedURL: "https://updates.example.com/mac/\(channel)/appcast.xml",
        publicEd25519KeyBase64: candidateKeyV0
    )
}

private func feedCandidate(
    authority: MacUpdateReleaseAuthorityV0? = nil,
    currentBuild: UInt64 = 10,
    itemChannel: String? = "beta",
    candidateBuild: String = "11",
    displayVersion: String = "0.2.0",
    archiveURL: String = "https://updates.example.com/mac/beta/MacCompanion-11.zip",
    informationOnly: Bool = false,
    installationType: String = "application",
    deltaCount: Int = 0,
    signedFeedValidationSucceeded: Bool = true,
    archiveContentLength: UInt64 = 13_301_944,
    archiveEd25519Signature: String = archiveSignatureV0
) throws -> MacUpdateFeedCandidateV0 {
    try MacUpdateFeedCandidateV0(
        authority: authority ?? candidateAuthority(),
        currentBuild: currentBuild,
        itemChannel: itemChannel,
        candidateBuild: candidateBuild,
        displayVersion: displayVersion,
        archiveURL: archiveURL,
        informationOnly: informationOnly,
        installationType: installationType,
        deltaCount: deltaCount,
        signedFeedValidationSucceeded: signedFeedValidationSucceeded,
        archiveContentLength: archiveContentLength,
        archiveEd25519Signature: archiveEd25519Signature
    )
}

@Test func feedCandidateAcceptsExactBetaAndStableItems() throws {
    let beta = try feedCandidate()
    #expect(beta.channel == .beta)
    #expect(beta.currentBuild == 10)
    #expect(beta.candidateBuild == 11)

    let stable = try feedCandidate(
        authority: candidateAuthority(channel: "stable"),
        itemChannel: nil,
        archiveURL: "https://updates.example.com/mac/stable/MacCompanion-11.zip"
    )
    #expect(stable.channel == .stable)
}

@Test func feedCandidateRejectsCrossChannelAndNonIncreasingBuilds() {
    #expect(throws: MacUpdateFeedCandidateErrorV0.channelMismatch) {
        try feedCandidate(itemChannel: nil)
    }
    #expect(throws: MacUpdateFeedCandidateErrorV0.channelMismatch) {
        try feedCandidate(
            authority: candidateAuthority(channel: "stable"),
            itemChannel: "beta"
        )
    }
    #expect(throws: MacUpdateFeedCandidateErrorV0.nonIncreasingBuild) {
        try feedCandidate(candidateBuild: "10")
    }
    #expect(throws: MacUpdateFeedCandidateErrorV0.invalidBuild) {
        try feedCandidate(candidateBuild: "011")
    }
}

@Test func feedCandidateRejectsPackagesDeltasAndInformationOnlyItems() {
    #expect(throws: MacUpdateFeedCandidateErrorV0.unsupportedItem) {
        try feedCandidate(informationOnly: true)
    }
    #expect(throws: MacUpdateFeedCandidateErrorV0.unsupportedItem) {
        try feedCandidate(installationType: "package")
    }
    #expect(throws: MacUpdateFeedCandidateErrorV0.unsupportedItem) {
        try feedCandidate(deltaCount: 1)
    }
}

@Test func feedCandidateRequiresSignedAppcastValidationAndBoundedArchive() {
    #expect(throws: MacUpdateFeedCandidateErrorV0.signedFeedRequired) {
        try feedCandidate(signedFeedValidationSucceeded: false)
    }
    #expect(throws: MacUpdateFeedCandidateErrorV0.invalidArchiveLength) {
        try feedCandidate(archiveContentLength: 0)
    }
    #expect(throws: MacUpdateFeedCandidateErrorV0.invalidArchiveLength) {
        try feedCandidate(
            archiveContentLength:
                MacUpdateFeedCandidateV0.maximumArchiveBytes + 1
        )
    }
}

@Test func feedCandidateRequiresCanonicalEd25519ArchiveSignature() {
    for signature in [
        "",
        Data(repeating: 0xA5, count: 63).base64EncodedString(),
        archiveSignatureV0 + "=",
        String(repeating: "!", count: 88),
    ] {
        #expect(
            throws: MacUpdateFeedCandidateErrorV0
                .invalidArchiveSignature
        ) {
            try feedCandidate(archiveEd25519Signature: signature)
        }
    }
}

@Test(
    arguments: [
        "http://updates.example.com/mac/beta/MacCompanion-11.zip",
        "https://user@updates.example.com/mac/beta/MacCompanion-11.zip",
        "https://updates.example.com:443/mac/beta/MacCompanion-11.zip",
        "https://updates.example.com/mac/beta/MacCompanion-11.zip?token=x",
        "https://updates.example.com/mac/beta/MacCompanion-11.zip#download",
        "https://localhost/mac/beta/MacCompanion-11.zip",
        "https://updates.local/mac/beta/MacCompanion-11.zip",
        "https://UPDATES.example.com/mac/beta/MacCompanion-11.zip",
        "https://updates.example.com/mac//beta/MacCompanion-11.zip",
        "https://updates.example.com/mac/beta/MacCompanion-11.pkg",
        "https://updates.example.com/mac/beta/Mac%20Companion-11.zip",
    ]
)
func feedCandidateRejectsUnsafeOrAmbiguousArchiveURLs(_ value: String) {
    #expect(throws: MacUpdateFeedCandidateErrorV0.invalidArchiveURL) {
        try feedCandidate(archiveURL: value)
    }
}

@Test func feedCandidateRejectsUnboundedOrControlDisplayVersions() {
    #expect(throws: MacUpdateFeedCandidateErrorV0.invalidDisplayVersion) {
        try feedCandidate(displayVersion: "")
    }
    #expect(throws: MacUpdateFeedCandidateErrorV0.invalidDisplayVersion) {
        try feedCandidate(displayVersion: "1.0\nUntrusted")
    }
    #expect(throws: MacUpdateFeedCandidateErrorV0.invalidDisplayVersion) {
        try feedCandidate(displayVersion: String(repeating: "x", count: 65))
    }
}
