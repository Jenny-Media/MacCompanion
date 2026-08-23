import Foundation
@testable import CompanionLifecycle

func admittedReleaseEvidenceV0(
    for candidate: MacUpdateFeedCandidateV0
) throws -> MacUpdateReleaseEvidenceV0 {
    try MacUpdateReleaseEvidenceV0(
        feedCandidate: candidate,
        attributes: releaseEvidenceAttributesV0(for: candidate)
    )
}

func publishedUpdateCandidateV0(
    for candidate: MacUpdateFeedCandidateV0
) throws -> MacUpdatePublishedCandidateV0 {
    try MacUpdatePublishedCandidateV0(
        feedCandidate: candidate,
        releaseEvidence: admittedReleaseEvidenceV0(for: candidate)
    )
}

func releaseEvidenceAttributesV0(
    for candidate: MacUpdateFeedCandidateV0
) -> [String: String] {
    let attribute = MacUpdateReleaseEvidenceV0.Attribute.self
    return [
        attribute.profile: MacUpdateReleaseEvidenceV0.profile,
        attribute.level: MacUpdateReleaseEvidenceV0.evidenceLevel,
        attribute.channel: candidate.channel.rawValue,
        attribute.build: String(candidate.candidateBuild),
        attribute.displayVersion: candidate.displayVersion,
        attribute.archiveURL: candidate.archiveURL.absoluteString,
        attribute.archiveLength:
            String(candidate.archiveContentLength),
        attribute.archiveSignature:
            candidate.archiveEd25519Signature,
        attribute.archiveSHA256:
            "12" + String(repeating: "a", count: 62),
        attribute.releaseManifestSHA256:
            "23" + String(repeating: "a", count: 62),
        attribute.platformSigningRecordSHA256:
            "34" + String(repeating: "a", count: 62),
        attribute.notarizationRecordSHA256:
            "45" + String(repeating: "a", count: 62),
        attribute.packagingReceiptSHA256:
            "56" + String(repeating: "a", count: 62),
        attribute.developerIDGraph: "passed",
        attribute.notarization: "passed",
        attribute.applicationStapling: "passed",
        attribute.wholeApplicationZIP: "passed",
    ]
}

func updateTestFeedCandidateV0(
    channel: MacUpdateChannelV0 = .beta,
    currentBuild: UInt64 = 10,
    candidateBuild: UInt64 = 11
) throws -> MacUpdateFeedCandidateV0 {
    let key = Data(repeating: 0x42, count: 32).base64EncodedString()
    let signature = Data(repeating: 0x24, count: 64)
        .base64EncodedString()
    let channelText = channel.rawValue
    let authority = try MacUpdateReleaseAuthorityV0(
        profile: MacUpdateReleaseAuthorityV0.profile,
        channel: channelText,
        feedURL:
            "https://updates.example.com/mac/\(channelText)/appcast.xml",
        publicEd25519KeyBase64: key
    )
    return try MacUpdateFeedCandidateV0(
        authority: authority,
        currentBuild: currentBuild,
        itemChannel: channel == .beta ? "beta" : nil,
        candidateBuild: String(candidateBuild),
        displayVersion: "0.2.0",
        archiveURL:
            "https://updates.example.com/mac/\(channelText)/MacCompanion-\(candidateBuild).zip",
        informationOnly: false,
        installationType: "application",
        deltaCount: 0,
        signedFeedValidationSucceeded: true,
        archiveContentLength: 13_301_944,
        archiveEd25519Signature: signature
    )
}
