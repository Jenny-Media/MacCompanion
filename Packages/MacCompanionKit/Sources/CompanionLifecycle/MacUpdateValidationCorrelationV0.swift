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
    case awaitingInstallationReadiness
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

/// Single-use correlation boundary for Sparkle's update lifecycle. The
/// containing-app adapter must construct item-bearing observations from the
/// exact callback item. `didExtractUpdate` is only an installer-start
/// acknowledgement in Sparkle 2.9.6; admission remains closed until the
/// standard user driver reports that the validated update is ready to install
/// and relaunch. Cancellation, mismatch, reordering, and reuse consume the
/// correlation permanently.
public actor MacUpdateValidationCorrelationV0 {
    private let expected: MacUpdatePublishedCandidateV0
    private let admissionOwner: MacUpdateInstallCandidateAdmissionV0
    private var phase =
        MacUpdateValidationCorrelationPhaseV0.awaitingExtraction
    private var correlatedPublication: MacUpdatePublishedCandidateV0?

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
        correlatedPublication = publication
        phase = .extracting
    }

    public func installerDidStart(
        publication: MacUpdatePublishedCandidateV0
    ) async throws {
        guard phase != .closed else {
            throw MacUpdateValidationCorrelationErrorV0.closed
        }
        guard phase == .extracting, let correlatedPublication else {
            await close()
            throw MacUpdateValidationCorrelationErrorV0.invalidSequence
        }

        guard publication == expected,
              publication == correlatedPublication else {
            await close()
            throw MacUpdateValidationCorrelationErrorV0
                .candidateMismatch
        }

        phase = .awaitingInstallationReadiness
    }

    /// Called only when the containing app's Sparkle user-driver bridge receives
    /// `showReadyToInstallAndRelaunch`. At that point Sparkle has completed its
    /// asynchronous extraction, validation, and stage-one preparation.
    public func reachedReadyToInstall()
        async throws -> MacUpdateInstallAdmissionV0
    {
        guard phase != .closed else {
            throw MacUpdateValidationCorrelationErrorV0.closed
        }
        guard phase == .awaitingInstallationReadiness,
              let correlatedPublication else {
            await close()
            throw MacUpdateValidationCorrelationErrorV0.invalidSequence
        }

        // Close before the awaited admission call so actor reentrancy cannot
        // admit the same prepared update twice.
        phase = .closed
        self.correlatedPublication = nil

        do {
            return try await admissionOwner.admitPreparedUpdate(
                publication: correlatedPublication
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
        correlatedPublication = nil
        await admissionOwner.cancel()
    }
}
