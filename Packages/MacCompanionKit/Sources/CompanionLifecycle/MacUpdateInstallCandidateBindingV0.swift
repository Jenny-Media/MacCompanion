import Foundation

enum MacUpdateInstallCandidateBindingErrorV0:
    Error, Equatable, Sendable
{
    case candidateMismatch
    case trustRequirementMissing
}

/// Exact bridge between a signed-feed observation and later updater-owned
/// validation plus protected release-evidence results. The observations are
/// deliberately independent: an informational item cannot become installation
/// authority merely by being copied into this value.
struct MacUpdateInstallCandidateBindingV0: Equatable, Sendable {
    let validatedCandidate: MacUpdateValidatedCandidateV0
    let displayVersion: String
    let archiveURL: URL

    init(
        feedCandidate: MacUpdateFeedCandidateV0,
        validatedChannel: MacUpdateChannelV0,
        validatedCurrentBuild: UInt64,
        validatedCandidateBuild: UInt64,
        validatedDisplayVersion: String,
        validatedArchiveURL: URL,
        validatedArchiveContentLength: UInt64,
        validatedArchiveEd25519Signature: String,
        signedFeedVerified: Bool,
        archiveSignatureVerified: Bool,
        verifiedBeforeExtraction: Bool,
        releaseEvidence: MacUpdateReleaseEvidenceV0
    ) throws {
        guard validatedChannel == feedCandidate.channel,
              validatedCurrentBuild == feedCandidate.currentBuild,
              validatedCandidateBuild == feedCandidate.candidateBuild,
              validatedDisplayVersion == feedCandidate.displayVersion,
              validatedArchiveURL == feedCandidate.archiveURL,
              validatedArchiveContentLength
                == feedCandidate.archiveContentLength,
              validatedArchiveEd25519Signature
                == feedCandidate.archiveEd25519Signature,
              releaseEvidence.isBound(to: feedCandidate) else {
            throw MacUpdateInstallCandidateBindingErrorV0
                .candidateMismatch
        }
        guard signedFeedVerified,
              archiveSignatureVerified,
              verifiedBeforeExtraction else {
            throw MacUpdateInstallCandidateBindingErrorV0
                .trustRequirementMissing
        }

        validatedCandidate = try MacUpdateValidatedCandidateV0(
            installedChannel: feedCandidate.channel,
            candidateChannel: validatedChannel,
            currentBuild: validatedCurrentBuild,
            candidateBuild: validatedCandidateBuild,
            signedFeedVerified: signedFeedVerified,
            archiveSignatureVerified: archiveSignatureVerified,
            verifiedBeforeExtraction: verifiedBeforeExtraction,
            releaseEvidence: releaseEvidence
        )
        displayVersion = validatedDisplayVersion
        archiveURL = validatedArchiveURL
    }
}

public enum MacUpdateInstallCandidateAdmissionErrorV0:
    Error, Equatable, Sendable
{
    case closed
    case candidateMismatch
    case trustRequirementMissing
}

public struct MacUpdateInstallAdmissionV0: Sendable {
    public let displayVersion: String
    public let archiveURL: URL
    let authority: MacUpdateInstallAuthorityV0
}

/// Single-use owner for one informational candidate. Any post-validation
/// rejection consumes the observation so a later updater callback cannot be
/// confused with the item the user reviewed.
public actor MacUpdateInstallCandidateAdmissionV0 {
    private var feedCandidate: MacUpdateFeedCandidateV0?

    public init(feedCandidate: MacUpdateFeedCandidateV0) {
        self.feedCandidate = feedCandidate
    }

    public func admit(
        validatedChannel: MacUpdateChannelV0,
        validatedCurrentBuild: UInt64,
        validatedCandidateBuild: UInt64,
        validatedDisplayVersion: String,
        validatedArchiveURL: URL,
        validatedArchiveContentLength: UInt64,
        validatedArchiveEd25519Signature: String,
        signedFeedVerified: Bool,
        archiveSignatureVerified: Bool,
        verifiedBeforeExtraction: Bool,
        releaseEvidence: MacUpdateReleaseEvidenceV0
    ) throws -> MacUpdateInstallAdmissionV0 {
        guard let feedCandidate else {
            throw MacUpdateInstallCandidateAdmissionErrorV0.closed
        }
        self.feedCandidate = nil

        let binding: MacUpdateInstallCandidateBindingV0
        do {
            binding = try MacUpdateInstallCandidateBindingV0(
                feedCandidate: feedCandidate,
                validatedChannel: validatedChannel,
                validatedCurrentBuild: validatedCurrentBuild,
                validatedCandidateBuild: validatedCandidateBuild,
                validatedDisplayVersion: validatedDisplayVersion,
                validatedArchiveURL: validatedArchiveURL,
                validatedArchiveContentLength:
                    validatedArchiveContentLength,
                validatedArchiveEd25519Signature:
                    validatedArchiveEd25519Signature,
                signedFeedVerified: signedFeedVerified,
                archiveSignatureVerified: archiveSignatureVerified,
                verifiedBeforeExtraction: verifiedBeforeExtraction,
                releaseEvidence: releaseEvidence
            )
        } catch MacUpdateInstallCandidateBindingErrorV0.candidateMismatch {
            throw MacUpdateInstallCandidateAdmissionErrorV0
                .candidateMismatch
        } catch {
            throw MacUpdateInstallCandidateAdmissionErrorV0
                .trustRequirementMissing
        }

        return MacUpdateInstallAdmissionV0(
            displayVersion: binding.displayVersion,
            archiveURL: binding.archiveURL,
            authority: MacUpdateInstallAuthorityV0(
                candidate: binding.validatedCandidate
            )
        )
    }

    public func cancel() {
        feedCandidate = nil
    }
}
