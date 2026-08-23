public enum MacUpdatePublishedCandidateErrorV0:
    Error, Equatable, Sendable
{
    case evidenceMismatch
}

/// One exact signed-appcast candidate and the protected release evidence
/// authenticated by that same publication. This is still not archive or
/// installation authority.
public struct MacUpdatePublishedCandidateV0: Equatable, Sendable {
    public let feedCandidate: MacUpdateFeedCandidateV0
    public let releaseEvidence: MacUpdateReleaseEvidenceV0

    public init(
        feedCandidate: MacUpdateFeedCandidateV0,
        releaseEvidence: MacUpdateReleaseEvidenceV0
    ) throws {
        guard releaseEvidence.isBound(to: feedCandidate) else {
            throw MacUpdatePublishedCandidateErrorV0.evidenceMismatch
        }
        self.feedCandidate = feedCandidate
        self.releaseEvidence = releaseEvidence
    }
}

public enum MacUpdateValidationCorrelationPhaseV0:
    String, Equatable, Sendable
{
    case awaitingExtraction
    case extracting
    case closed
}

public enum MacUpdateValidationCorrelationErrorV0:
    Error, Equatable, Sendable
{
    case closed
    case invalidSequence
    case candidateMismatch
    case trustRequirementMissing
}

/// Single-use correlation boundary for Sparkle's extraction callbacks. The
/// containing-app adapter must construct every observation from the exact
/// callback item. Only one matching will-extract / did-extract sequence can
/// reach installation admission; cancellation, mismatch, reordering, and reuse
/// consume the correlation permanently.
public actor MacUpdateValidationCorrelationV0 {
    private let expected: MacUpdatePublishedCandidateV0
    private let admissionOwner: MacUpdateInstallCandidateAdmissionV0
    private var phase =
        MacUpdateValidationCorrelationPhaseV0.awaitingExtraction
    private var extracting: MacUpdatePublishedCandidateV0?

    public init(publication: MacUpdatePublishedCandidateV0) {
        expected = publication
        admissionOwner = MacUpdateInstallCandidateAdmissionV0(
            publication: publication
        )
    }

    public func currentPhase()
        -> MacUpdateValidationCorrelationPhaseV0
    {
        phase
    }

    public func willExtract(
        publication: MacUpdatePublishedCandidateV0
    ) async throws {
        guard phase != .closed else {
            throw MacUpdateValidationCorrelationErrorV0.closed
        }
        guard phase == .awaitingExtraction else {
            await close()
            throw MacUpdateValidationCorrelationErrorV0.invalidSequence
        }
        guard publication == expected else {
            await close()
            throw MacUpdateValidationCorrelationErrorV0
                .candidateMismatch
        }
        extracting = publication
        phase = .extracting
    }

    public func didExtract(
        publication: MacUpdatePublishedCandidateV0
    ) async throws -> MacUpdateInstallAdmissionV0 {
        guard phase != .closed else {
            throw MacUpdateValidationCorrelationErrorV0.closed
        }
        guard phase == .extracting, let extracting else {
            await close()
            throw MacUpdateValidationCorrelationErrorV0.invalidSequence
        }

        // Close before the awaited admission call so actor reentrancy cannot
        // admit the same callback sequence twice.
        phase = .closed
        self.extracting = nil
        guard publication == expected, publication == extracting else {
            await admissionOwner.cancel()
            throw MacUpdateValidationCorrelationErrorV0
                .candidateMismatch
        }

        do {
            return try await admissionOwner.admitPostExtraction(
                publication: publication
            )
        } catch MacUpdateInstallCandidateAdmissionErrorV0
            .candidateMismatch {
            throw MacUpdateValidationCorrelationErrorV0
                .candidateMismatch
        } catch {
            throw MacUpdateValidationCorrelationErrorV0
                .trustRequirementMissing
        }
    }

    public func cancel() async {
        await close()
    }

    private func close() async {
        guard phase != .closed else { return }
        phase = .closed
        extracting = nil
        await admissionOwner.cancel()
    }
}
