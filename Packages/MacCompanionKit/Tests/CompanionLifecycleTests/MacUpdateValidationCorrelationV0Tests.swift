@testable import CompanionLifecycle
import Testing

private func correlationPublicationV0(
    candidateBuild: UInt64 = 11,
    archiveDigest: String? = nil
) throws -> MacUpdatePublishedCandidateV0 {
    let candidate = try updateTestFeedCandidateV0(
        candidateBuild: candidateBuild
    )
    var attributes = releaseEvidenceAttributesV0(for: candidate)
    if let archiveDigest {
        attributes[
            MacUpdateReleaseEvidenceV0.Attribute.archiveSHA256
        ] = archiveDigest
    }
    return try MacUpdatePublishedCandidateV0(
        feedCandidate: candidate,
        releaseEvidence: MacUpdateReleaseEvidenceV0(
            feedCandidate: candidate,
            attributes: attributes
        )
    )
}

@Test func publishedCandidateRequiresEvidenceForTheExactCandidate()
throws {
    let candidate = try updateTestFeedCandidateV0(candidateBuild: 11)
    let otherCandidate = try updateTestFeedCandidateV0(
        candidateBuild: 12
    )
    #expect(throws: MacUpdatePublishedCandidateErrorV0.evidenceMismatch) {
        _ = try MacUpdatePublishedCandidateV0(
            feedCandidate: candidate,
            releaseEvidence:
                admittedReleaseEvidenceV0(for: otherCandidate)
        )
    }
}

@Test func exactValidationSequenceMintsOneInstallAdmission()
async throws {
    let publication = try correlationPublicationV0()
    let correlation = MacUpdateValidationCorrelationV0(
        publication: publication
    )

    #expect(await correlation.currentPhase() == .awaitingExtraction)
    try await correlation.willExtract(publication: publication)
    #expect(await correlation.currentPhase() == .extracting)
    try await correlation.installerDidStart(
        publication: publication
    )
    #expect(
        await correlation.currentPhase()
            == .awaitingInstallationReadiness
    )
    let admission = try await correlation.reachedReadyToInstall()
    #expect(admission.candidateBuild == 11)

    #expect(admission.displayVersion == "0.2.0")
    #expect(
        admission.archiveURL
            == publication.feedCandidate.archiveURL
    )
    #expect(await correlation.currentPhase() == .closed)
    await #expect(throws: MacUpdateValidationCorrelationErrorV0.closed) {
        _ = try await correlation.reachedReadyToInstall()
    }
}

@Test func reorderedLifecycleCallbacksCloseCorrelation()
async throws {
    let publication = try correlationPublicationV0()
    let installerFirst = MacUpdateValidationCorrelationV0(
        publication: publication
    )

    await #expect(
        throws: MacUpdateValidationCorrelationErrorV0.invalidSequence
    ) {
        try await installerFirst.installerDidStart(
            publication: publication
        )
    }
    #expect(await installerFirst.currentPhase() == .closed)
    await #expect(throws: MacUpdateValidationCorrelationErrorV0.closed) {
        try await installerFirst.willExtract(publication: publication)
    }

    let readyBeforeInstaller = MacUpdateValidationCorrelationV0(
        publication: publication
    )
    try await readyBeforeInstaller.willExtract(
        publication: publication
    )
    await #expect(
        throws: MacUpdateValidationCorrelationErrorV0.invalidSequence
    ) {
        _ = try await readyBeforeInstaller.reachedReadyToInstall()
    }
    #expect(await readyBeforeInstaller.currentPhase() == .closed)
}

@Test func repeatedWillExtractIsTerminal() async throws {
    let publication = try correlationPublicationV0()
    let correlation = MacUpdateValidationCorrelationV0(
        publication: publication
    )

    try await correlation.willExtract(publication: publication)
    await #expect(
        throws: MacUpdateValidationCorrelationErrorV0.invalidSequence
    ) {
        try await correlation.willExtract(publication: publication)
    }
    #expect(await correlation.currentPhase() == .closed)
}

@Test func candidateAndEvidenceSubstitutionFailTerminally()
async throws {
    let publication = try correlationPublicationV0()
    let otherCandidate = try correlationPublicationV0(
        candidateBuild: 12
    )
    let candidateMismatch = MacUpdateValidationCorrelationV0(
        publication: publication
    )
    await #expect(
        throws: MacUpdateValidationCorrelationErrorV0
            .candidateMismatch
    ) {
        try await candidateMismatch.willExtract(
            publication: otherCandidate
        )
    }
    #expect(await candidateMismatch.currentPhase() == .closed)

    let differentEvidence = try correlationPublicationV0(
        archiveDigest: "67" + String(repeating: "a", count: 62)
    )
    let evidenceMismatch = MacUpdateValidationCorrelationV0(
        publication: publication
    )
    try await evidenceMismatch.willExtract(publication: publication)
    await #expect(
        throws: MacUpdateValidationCorrelationErrorV0
            .candidateMismatch
    ) {
        try await evidenceMismatch.installerDidStart(
            publication: differentEvidence
        )
    }
    #expect(await evidenceMismatch.currentPhase() == .closed)
}

@Test func cancellationAtEveryLifecyclePhaseIsTerminal()
async throws {
    let publication = try correlationPublicationV0()
    let before = MacUpdateValidationCorrelationV0(
        publication: publication
    )
    await before.cancel()
    await before.cancel()
    await #expect(throws: MacUpdateValidationCorrelationErrorV0.closed) {
        try await before.willExtract(publication: publication)
    }

    let during = MacUpdateValidationCorrelationV0(
        publication: publication
    )
    try await during.willExtract(publication: publication)
    await during.cancel()
    await #expect(throws: MacUpdateValidationCorrelationErrorV0.closed) {
        try await during.installerDidStart(publication: publication)
    }

    let awaitingReadiness = MacUpdateValidationCorrelationV0(
        publication: publication
    )
    try await awaitingReadiness.willExtract(publication: publication)
    try await awaitingReadiness.installerDidStart(
        publication: publication
    )
    await awaitingReadiness.cancel()
    await #expect(throws: MacUpdateValidationCorrelationErrorV0.closed) {
        _ = try await awaitingReadiness.reachedReadyToInstall()
    }
}

@Test func concurrentReadyCallbacksMintExactlyOneAdmission()
async throws {
    let publication = try correlationPublicationV0()
    let correlation = MacUpdateValidationCorrelationV0(
        publication: publication
    )
    try await correlation.willExtract(publication: publication)
    try await correlation.installerDidStart(publication: publication)

    let first = Task {
        do {
            _ = try await correlation.reachedReadyToInstall()
            return true
        } catch {
            return false
        }
    }
    let second = Task {
        do {
            _ = try await correlation.reachedReadyToInstall()
            return true
        } catch {
            return false
        }
    }
    let firstOutcome = await first.value
    let secondOutcome = await second.value
    let outcomes = [firstOutcome, secondOutcome]
    #expect(outcomes.filter { $0 }.count == 1)
    #expect(await correlation.currentPhase() == .closed)
}
