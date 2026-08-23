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
    developerIDValidated: Bool = true,
    notarizedReplacement: Bool = true,
    wholeApplicationZIP: Bool = true
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
        developerIDValidated: developerIDValidated,
        notarizedReplacement: notarizedReplacement,
        wholeApplicationZIP: wholeApplicationZIP
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
}

@Test(
    arguments: [
        "signedFeed", "archiveSignature", "beforeExtraction",
        "developerID", "notarization", "wholeBundle",
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
            verifiedBeforeExtraction: missing != "beforeExtraction",
            developerIDValidated: missing != "developerID",
            notarizedReplacement: missing != "notarization",
            wholeApplicationZIP: missing != "wholeBundle"
        )
    }
}

@Test func admissionMintsOneRuntimeAuthorityForTheExactCandidate()
async throws {
    let candidate = try bindingFeedCandidate()
    let owner = MacUpdateInstallCandidateAdmissionV0(
        feedCandidate: candidate
    )

    let admission = try await owner.admit(
        validatedChannel: candidate.channel,
        validatedCurrentBuild: candidate.currentBuild,
        validatedCandidateBuild: candidate.candidateBuild,
        validatedDisplayVersion: candidate.displayVersion,
        validatedArchiveURL: candidate.archiveURL,
        validatedArchiveContentLength: candidate.archiveContentLength,
        validatedArchiveEd25519Signature:
            candidate.archiveEd25519Signature,
        signedFeedVerified: true,
        archiveSignatureVerified: true,
        verifiedBeforeExtraction: true,
        developerIDValidated: true,
        notarizedReplacement: true,
        wholeApplicationZIP: true
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
        _ = try await owner.admit(
            validatedChannel: candidate.channel,
            validatedCurrentBuild: candidate.currentBuild,
            validatedCandidateBuild: candidate.candidateBuild,
            validatedDisplayVersion: candidate.displayVersion,
            validatedArchiveURL: candidate.archiveURL,
            validatedArchiveContentLength: candidate.archiveContentLength,
            validatedArchiveEd25519Signature:
                candidate.archiveEd25519Signature,
            signedFeedVerified: true,
            archiveSignatureVerified: true,
            verifiedBeforeExtraction: true,
            developerIDValidated: true,
            notarizedReplacement: true,
            wholeApplicationZIP: true
        )
    }
}

@Test func rejectedOrCancelledObservationCannotBeRetried() async throws {
    let candidate = try bindingFeedCandidate()
    let mismatch = MacUpdateInstallCandidateAdmissionV0(
        feedCandidate: candidate
    )
    await #expect(
        throws: MacUpdateInstallCandidateAdmissionErrorV0
            .candidateMismatch
    ) {
        _ = try await mismatch.admit(
            validatedChannel: candidate.channel,
            validatedCurrentBuild: candidate.currentBuild,
            validatedCandidateBuild: candidate.candidateBuild + 1,
            validatedDisplayVersion: candidate.displayVersion,
            validatedArchiveURL: candidate.archiveURL,
            validatedArchiveContentLength: candidate.archiveContentLength,
            validatedArchiveEd25519Signature:
                candidate.archiveEd25519Signature,
            signedFeedVerified: true,
            archiveSignatureVerified: true,
            verifiedBeforeExtraction: true,
            developerIDValidated: true,
            notarizedReplacement: true,
            wholeApplicationZIP: true
        )
    }
    await #expect(
        throws: MacUpdateInstallCandidateAdmissionErrorV0.closed
    ) {
        _ = try await mismatch.admit(
            validatedChannel: candidate.channel,
            validatedCurrentBuild: candidate.currentBuild,
            validatedCandidateBuild: candidate.candidateBuild,
            validatedDisplayVersion: candidate.displayVersion,
            validatedArchiveURL: candidate.archiveURL,
            validatedArchiveContentLength: candidate.archiveContentLength,
            validatedArchiveEd25519Signature:
                candidate.archiveEd25519Signature,
            signedFeedVerified: true,
            archiveSignatureVerified: true,
            verifiedBeforeExtraction: true,
            developerIDValidated: true,
            notarizedReplacement: true,
            wholeApplicationZIP: true
        )
    }

    let cancelled = MacUpdateInstallCandidateAdmissionV0(
        feedCandidate: candidate
    )
    await cancelled.cancel()
    await #expect(
        throws: MacUpdateInstallCandidateAdmissionErrorV0.closed
    ) {
        _ = try await cancelled.admit(
            validatedChannel: candidate.channel,
            validatedCurrentBuild: candidate.currentBuild,
            validatedCandidateBuild: candidate.candidateBuild,
            validatedDisplayVersion: candidate.displayVersion,
            validatedArchiveURL: candidate.archiveURL,
            validatedArchiveContentLength: candidate.archiveContentLength,
            validatedArchiveEd25519Signature:
                candidate.archiveEd25519Signature,
            signedFeedVerified: true,
            archiveSignatureVerified: true,
            verifiedBeforeExtraction: true,
            developerIDValidated: true,
            notarizedReplacement: true,
            wholeApplicationZIP: true
        )
    }
}
