import Foundation
@testable import CompanionLifecycle
import Testing

private let releaseEvidenceKeyV0 =
    Data(repeating: 0x53, count: 32).base64EncodedString()
private let releaseEvidenceSignatureV0 =
    Data(repeating: 0x35, count: 64).base64EncodedString()

private func releaseEvidenceCandidateV0() throws
    -> MacUpdateFeedCandidateV0
{
    let authority = try MacUpdateReleaseAuthorityV0(
        profile: MacUpdateReleaseAuthorityV0.profile,
        channel: "beta",
        feedURL: "https://updates.example.com/mac/beta/appcast.xml",
        publicEd25519KeyBase64: releaseEvidenceKeyV0
    )
    return try MacUpdateFeedCandidateV0(
        authority: authority,
        currentBuild: 10,
        itemChannel: "beta",
        candidateBuild: "11",
        displayVersion: "0.2.0",
        archiveURL:
            "https://updates.example.com/mac/beta/MacCompanion-11.zip",
        informationOnly: false,
        installationType: "application",
        deltaCount: 0,
        signedFeedValidationSucceeded: true,
        archiveContentLength: 13_301_944,
        archiveEd25519Signature: releaseEvidenceSignatureV0
    )
}

private func releaseEvidenceV0(
    candidate: MacUpdateFeedCandidateV0,
    attributes: [String: String]
) throws -> MacUpdateReleaseEvidenceV0 {
    try MacUpdateReleaseEvidenceV0(
        feedCandidate: candidate,
        attributes: attributes
    )
}

@Test func releaseEvidenceAcceptsOneExactSignedCandidate() throws {
    let candidate = try releaseEvidenceCandidateV0()
    let evidence = try releaseEvidenceV0(
        candidate: candidate,
        attributes: releaseEvidenceAttributesV0(for: candidate)
    )
    #expect(evidence.channel == .beta)
    #expect(evidence.candidateBuild == 11)
    #expect(evidence.archiveContentLength == 13_301_944)
}

@Test func releaseEvidenceRequiresClosedAttributeSet() throws {
    let candidate = try releaseEvidenceCandidateV0()
    var missing = releaseEvidenceAttributesV0(for: candidate)
    missing.removeValue(
        forKey: MacUpdateReleaseEvidenceV0.Attribute.archiveSHA256
    )
    #expect(throws: MacUpdateReleaseEvidenceErrorV0.invalidAttributes) {
        try releaseEvidenceV0(
            candidate: candidate,
            attributes: missing
        )
    }

    var extra = releaseEvidenceAttributesV0(for: candidate)
    extra["maccompanion:futureClaim"] = "passed"
    #expect(throws: MacUpdateReleaseEvidenceErrorV0.invalidAttributes) {
        try releaseEvidenceV0(candidate: candidate, attributes: extra)
    }
}

@Test func releaseEvidenceRequiresExactProfileAndSignedCandidateLevel()
throws {
    let candidate = try releaseEvidenceCandidateV0()
    var attributes = releaseEvidenceAttributesV0(for: candidate)
    attributes[MacUpdateReleaseEvidenceV0.Attribute.profile] =
        "maccompanion.update-release-evidence.v2"
    #expect(throws: MacUpdateReleaseEvidenceErrorV0.invalidProfile) {
        try releaseEvidenceV0(
            candidate: candidate,
            attributes: attributes
        )
    }

    attributes = releaseEvidenceAttributesV0(for: candidate)
    attributes[MacUpdateReleaseEvidenceV0.Attribute.level] =
        "promotionReady"
    #expect(
        throws: MacUpdateReleaseEvidenceErrorV0.invalidEvidenceLevel
    ) {
        try releaseEvidenceV0(
            candidate: candidate,
            attributes: attributes
        )
    }
}

@Test func releaseEvidenceRejectsInvalidEncodingAndEverySubstitution()
throws {
    let candidate = try releaseEvidenceCandidateV0()
    let attribute = MacUpdateReleaseEvidenceV0.Attribute.self
    for mutation in [
        (attribute.channel, "gamma", true),
        (attribute.build, "011", true),
        (attribute.archiveLength, "-1", true),
        (attribute.channel, "stable", false),
        (attribute.build, "12", false),
        (attribute.displayVersion, "0.2.1", false),
        (
            attribute.archiveURL,
            "https://updates.example.com/mac/beta/MacCompanion-12.zip",
            false
        ),
        (
            attribute.archiveURL,
            "https://UPDATES.example.com/mac/beta/MacCompanion-11.zip",
            false
        ),
        (attribute.archiveLength, "13301945", false),
        (
            attribute.archiveSignature,
            Data(repeating: 0x36, count: 64).base64EncodedString(),
            false
        ),
    ] {
        var attributes = releaseEvidenceAttributesV0(for: candidate)
        attributes[mutation.0] = mutation.1
        let expected: MacUpdateReleaseEvidenceErrorV0 = mutation.2
            ? .invalidCandidateEncoding
            : .candidateMismatch
        #expect(throws: expected) {
            try releaseEvidenceV0(
                candidate: candidate,
                attributes: attributes
            )
        }
    }
}

@Test func releaseEvidenceRejectsMissingTrustAndInvalidDigests()
throws {
    let candidate = try releaseEvidenceCandidateV0()
    let attribute = MacUpdateReleaseEvidenceV0.Attribute.self
    for claim in [
        attribute.developerIDGraph,
        attribute.notarization,
        attribute.applicationStapling,
        attribute.wholeApplicationZIP,
    ] {
        var attributes = releaseEvidenceAttributesV0(for: candidate)
        attributes[claim] = "failed"
        #expect(
            throws: MacUpdateReleaseEvidenceErrorV0
                .trustRequirementMissing
        ) {
            try releaseEvidenceV0(
                candidate: candidate,
                attributes: attributes
            )
        }
    }

    for invalidDigest in [
        "1",
        "gg" + String(repeating: "a", count: 62),
        String(repeating: "1", count: 64),
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    ] {
        var attributes = releaseEvidenceAttributesV0(for: candidate)
        attributes[attribute.archiveSHA256] = invalidDigest
        #expect(throws: MacUpdateReleaseEvidenceErrorV0.invalidDigest) {
            try releaseEvidenceV0(
                candidate: candidate,
                attributes: attributes
            )
        }
    }
}
