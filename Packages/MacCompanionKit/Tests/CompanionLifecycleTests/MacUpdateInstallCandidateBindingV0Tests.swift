@testable import CompanionLifecycle
import Foundation
import Testing

private let bindingKeyV0 =
    Data(repeating: 0x39, count: 32).base64EncodedString()
private let bindingArchiveSignatureV0 =
    Data(repeating: 0x93, count: 64).base64EncodedString()

private func bindingFeedCandidate() throws -> MacUpdateFeedCandidateV0 {
    let authority = try MacUpdateReleaseAuthorityV0(
        profile: MacUpdateReleaseAuthorityV0.profile,
        channel: "beta",
        feedURL: "https://updates.example.com/mac/beta/appcast.xml",
        publicEd25519KeyBase64: bindingKeyV0
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
        archiveEd25519Signature: bindingArchiveSignatureV0
    )
}

private func candidateBinding(
    candidate: MacUpdateFeedCandidateV0? = nil,
    validatedChannel: MacUpdateChannelV0 = .beta,
    validatedCurrentBuild: UInt64 = 10,
    validatedCandidateBuild: UInt64 = 11,
    validatedDisplayVersion: String = "0.2.0",
    validatedArchiveURL: URL? = nil,
    validatedArchiveContentLength: UInt64 = 13_301_944,
    validatedArchiveEd25519Signature: String =
        bindingArchiveSignatureV0,
    signedFeedVerified: Bool = true,
    archiveSignatureVerified: Bool = true,
    verifiedBeforeExtraction: Bool = true,
    releaseEvidence: MacUpdateReleaseEvidenceV0? = nil
) throws -> MacUpdateInstallCandidateBindingV0 {
    let candidate = try candidate ?? bindingFeedCandidate()
    return try MacUpdateInstallCandidateBindingV0(
        feedCandidate: candidate,
        validatedChannel: validatedChannel,
        validatedCurrentBuild: validatedCurrentBuild,
        validatedCandidateBuild: validatedCandidateBuild,
        validatedDisplayVersion: validatedDisplayVersion,
        validatedArchiveURL:
            validatedArchiveURL ?? candidate.archiveURL,
        validatedArchiveContentLength: validatedArchiveContentLength,
        validatedArchiveEd25519Signature:
            validatedArchiveEd25519Signature,
        signedFeedVerified: signedFeedVerified,
        archiveSignatureVerified: archiveSignatureVerified,
        verifiedBeforeExtraction: verifiedBeforeExtraction,
        releaseEvidence:
            try releaseEvidence ?? admittedReleaseEvidenceV0(for: candidate)
    )
}

@Test func exactPostValidationObservationMintsInstallCandidate() throws {
    let binding = try candidateBinding()

    #expect(binding.validatedCandidate.channel == .beta)
    #expect(binding.validatedCandidate.currentBuild == 10)
    #expect(binding.validatedCandidate.candidateBuild == 11)
    #expect(binding.displayVersion == "0.2.0")
    #expect(
        binding.archiveURL.absoluteString
            == "https://updates.example.com/mac/beta/MacCompanion-11.zip"
    )
}

@Test func everyCandidateFactMustMatchTheInformationalObservation() throws {
    #expect(throws: MacUpdateInstallCandidateBindingErrorV0.candidateMismatch) {
        try candidateBinding(validatedChannel: .stable)
    }
    #expect(throws: MacUpdateInstallCandidateBindingErrorV0.candidateMismatch) {
        try candidateBinding(validatedCurrentBuild: 9)
    }
    #expect(throws: MacUpdateInstallCandidateBindingErrorV0.candidateMismatch) {
        try candidateBinding(validatedCandidateBuild: 12)
    }
    #expect(throws: MacUpdateInstallCandidateBindingErrorV0.candidateMismatch) {
        try candidateBinding(validatedDisplayVersion: "0.2.1")
    }
    #expect(throws: MacUpdateInstallCandidateBindingErrorV0.candidateMismatch) {
        try candidateBinding(
            validatedArchiveURL: URL(
                string:
                    "https://updates.example.com/mac/beta/MacCompanion-12.zip"
            )!
        )
    }
    #expect(throws: MacUpdateInstallCandidateBindingErrorV0.candidateMismatch) {
        try candidateBinding(validatedArchiveContentLength: 13_301_945)
    }
    #expect(throws: MacUpdateInstallCandidateBindingErrorV0.candidateMismatch) {
        try candidateBinding(
            validatedArchiveEd25519Signature:
                Data(repeating: 0x94, count: 64).base64EncodedString()
        )
    }
    let otherCandidate = try updateTestFeedCandidateV0(
        channel: .beta,
        currentBuild: 10,
        candidateBuild: 12
    )
    #expect(throws: MacUpdateInstallCandidateBindingErrorV0.candidateMismatch) {
        try candidateBinding(
            releaseEvidence:
                admittedReleaseEvidenceV0(for: otherCandidate)
        )
    }
}

@Test(
    arguments: [
        "signedFeed", "archiveSignature", "beforeExtraction",
    ]
)
func everyPostValidationTrustFactIsRequired(_ missing: String) {
    #expect(
        throws:
            MacUpdateInstallCandidateBindingErrorV0
                .trustRequirementMissing
    ) {
        try candidateBinding(
            signedFeedVerified: missing != "signedFeed",
            archiveSignatureVerified: missing != "archiveSignature",
            verifiedBeforeExtraction: missing != "beforeExtraction"
        )
    }
}

@Test func admissionMintsOneRuntimeAuthorityForTheExactCandidate()
async throws {
    let candidate = try bindingFeedCandidate()
    let publication = try publishedUpdateCandidateV0(for: candidate)
    let owner = MacUpdateInstallCandidateAdmissionV0(
        publication: publication
    )

    let admission = try await owner.admitPostExtraction(
        publication: publication
    )

    #expect(admission.displayVersion == candidate.displayVersion)
    #expect(admission.archiveURL == candidate.archiveURL)
    #expect(
        await admission.authority.snapshot().candidate.candidateBuild
            == candidate.candidateBuild
    )
    await #expect(
        throws: MacUpdateInstallCandidateAdmissionErrorV0.closed
    ) {
        _ = try await owner.admitPostExtraction(
            publication: publication
        )
    }
}

@Test func rejectedOrCancelledObservationCannotBeRetried() async throws {
    let candidate = try bindingFeedCandidate()
    let publication = try publishedUpdateCandidateV0(for: candidate)
    let mismatch = MacUpdateInstallCandidateAdmissionV0(
        publication: publication
    )
    let otherCandidate = try updateTestFeedCandidateV0(
        channel: .beta,
        currentBuild: candidate.currentBuild,
        candidateBuild: candidate.candidateBuild + 1
    )
    await #expect(
        throws: MacUpdateInstallCandidateAdmissionErrorV0
            .candidateMismatch
    ) {
        _ = try await mismatch.admitPostExtraction(
            publication: publishedUpdateCandidateV0(
                for: otherCandidate
            )
        )
    }
    await #expect(
        throws: MacUpdateInstallCandidateAdmissionErrorV0.closed
    ) {
        _ = try await mismatch.admitPostExtraction(
            publication: publication
        )
    }

    let cancelled = MacUpdateInstallCandidateAdmissionV0(
        publication: publication
    )
    await cancelled.cancel()
    await #expect(
        throws: MacUpdateInstallCandidateAdmissionErrorV0.closed
    ) {
        _ = try await cancelled.admitPostExtraction(
            publication: publication
        )
    }
}
