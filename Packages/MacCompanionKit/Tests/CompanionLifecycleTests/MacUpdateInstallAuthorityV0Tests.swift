@testable import CompanionLifecycle
import Foundation
import Testing

private func updateCandidate(
    installedChannel: MacUpdateChannelV0 = .beta,
    candidateChannel: MacUpdateChannelV0 = .beta,
    currentBuild: UInt64 = 10,
    candidateBuild: UInt64 = 11,
    signedFeedVerified: Bool = true,
    archiveSignatureVerified: Bool = true,
    verifiedBeforeExtraction: Bool = true
) throws -> MacUpdateValidatedCandidateV0 {
    let evidenceBuild = candidateBuild > currentBuild
        ? candidateBuild
        : currentBuild + 1
    let evidenceCandidate = try updateTestFeedCandidateV0(
        channel: candidateChannel,
        currentBuild: currentBuild,
        candidateBuild: evidenceBuild
    )
    return try MacUpdateValidatedCandidateV0(
        installedChannel: installedChannel,
        candidateChannel: candidateChannel,
        currentBuild: currentBuild,
        candidateBuild: candidateBuild,
        signedFeedVerified: signedFeedVerified,
        archiveSignatureVerified: archiveSignatureVerified,
        verifiedBeforeExtraction: verifiedBeforeExtraction,
        releaseEvidence:
            admittedReleaseEvidenceV0(for: evidenceCandidate)
    )
}

@Test func updateCandidateRequiresSameChannelAndIncreasingBuild() {
    #expect(throws: MacUpdateCandidateValidationErrorV0.channelMismatch) {
        try updateCandidate(candidateChannel: .stable)
    }
    #expect(throws: MacUpdateCandidateValidationErrorV0.nonIncreasingBuild) {
        try updateCandidate(candidateBuild: 10)
    }
    #expect(throws: MacUpdateCandidateValidationErrorV0.nonIncreasingBuild) {
        try updateCandidate(candidateBuild: 9)
    }
}

@Test(
    arguments: [
        "signedFeed", "archiveSignature", "beforeExtraction",
    ]
)
func updateCandidateRequiresEveryTrustFact(_ missing: String) {
    #expect(throws: MacUpdateCandidateValidationErrorV0
        .trustRequirementMissing) {
        try updateCandidate(
            signedFeedVerified: missing != "signedFeed",
            archiveSignatureVerified: missing != "archiveSignature",
            verifiedBeforeExtraction: missing != "beforeExtraction"
        )
    }
}

@Test func updateInstallRunsEveryShutdownEffectBeforeOneHandoff() async throws {
    let authority = MacUpdateInstallAuthorityV0(
        candidate: try updateCandidate()
    )
    try await authority.confirm(
        monotonicNowMilliseconds: 1_000,
        menuForeground: true
    )
    #expect(try await authority.beginRuntimeShutdown(
        monotonicNowMilliseconds: 1_001,
        menuForeground: true,
        controlState: .inactive
    ) == .closeNetworkAdmission)
    #expect(try await authority.networkAdmissionDidClose(
        monotonicNowMilliseconds: 1_002,
        menuForeground: true
    ) == .drainBoundedWork)
    #expect(try await authority.boundedWorkDidDrain(
        monotonicNowMilliseconds: 1_003,
        menuForeground: true
    ) == .stopAgent)
    try await authority.agentDidStop(
        exactVersionMatch: true,
        monotonicNowMilliseconds: 1_004,
        menuForeground: true
    )

    let calls = LockedCounterV0()
    try await authority.handOffToUpdater(
        monotonicNowMilliseconds: 1_005,
        menuForeground: true
    ) {
        calls.increment()
    }
    #expect(calls.value == 1)
    #expect(await authority.snapshot().phase == .closed)
    #expect(await authority.snapshot().recoveryRequirement == .none)
    await #expect(throws: MacUpdateInstallAuthorityErrorV0.closed) {
        try await authority.handOffToUpdater(
            monotonicNowMilliseconds: 1_006,
            menuForeground: true
        ) {
            calls.increment()
        }
    }
    #expect(calls.value == 1)
}

@Test func activeOrUncertainControlCannotStartShutdownButCanRetryInactive()
async throws {
    for state in [MacUpdateControlStateV0.active, .cleanupUncertain] {
        let authority = MacUpdateInstallAuthorityV0(
            candidate: try updateCandidate()
        )
        try await authority.confirm(
            monotonicNowMilliseconds: 100,
            menuForeground: true
        )
        let expected: MacUpdateInstallAuthorityErrorV0 = state == .active
            ? .controlActive : .controlCleanupUncertain
        await #expect(throws: expected) {
            _ = try await authority.beginRuntimeShutdown(
                monotonicNowMilliseconds: 101,
                menuForeground: true,
                controlState: state
            )
        }
        #expect(await authority.snapshot().phase == .confirmationAccepted)
        #expect(try await authority.beginRuntimeShutdown(
            monotonicNowMilliseconds: 102,
            menuForeground: true,
            controlState: .inactive
        ) == .closeNetworkAdmission)
    }
}

@Test func confirmationRequiresSafeClockAndForeground() async throws {
    let background = MacUpdateInstallAuthorityV0(
        candidate: try updateCandidate()
    )
    await #expect(throws: MacUpdateInstallAuthorityErrorV0
        .foregroundRequired) {
        try await background.confirm(
            monotonicNowMilliseconds: 0,
            menuForeground: false
        )
    }
    #expect(await background.snapshot().phase == .closed)

    let overflow = MacUpdateInstallAuthorityV0(
        candidate: try updateCandidate()
    )
    await #expect(throws: MacUpdateInstallAuthorityErrorV0.invalidClock) {
        try await overflow.confirm(
            monotonicNowMilliseconds: Int64.max,
            menuForeground: true
        )
    }
    #expect(await overflow.snapshot().phase == .closed)
}

@Test func confirmationExpiresInclusivelyAndClosesAfterDeadline()
async throws {
    let atDeadline = MacUpdateInstallAuthorityV0(
        candidate: try updateCandidate()
    )
    try await atDeadline.confirm(
        monotonicNowMilliseconds: 0,
        menuForeground: true
    )
    #expect(try await atDeadline.beginRuntimeShutdown(
        monotonicNowMilliseconds: 300_000,
        menuForeground: true,
        controlState: .inactive
    ) == .closeNetworkAdmission)

    let expired = MacUpdateInstallAuthorityV0(
        candidate: try updateCandidate()
    )
    try await expired.confirm(
        monotonicNowMilliseconds: 0,
        menuForeground: true
    )
    await #expect(throws: MacUpdateInstallAuthorityErrorV0
        .confirmationExpired) {
        _ = try await expired.beginRuntimeShutdown(
            monotonicNowMilliseconds: 300_001,
            menuForeground: true,
            controlState: .inactive
        )
    }
    #expect(await expired.snapshot().phase == .closed)
}

@Test func foregroundLossRevokesEvenReadyInstallAuthority() async throws {
    let authority = MacUpdateInstallAuthorityV0(
        candidate: try updateCandidate()
    )
    try await prepareReady(authority)
    await authority.menuForegroundDidChange(false)
    #expect(await authority.snapshot().phase == .closed)
    #expect(
        await authority.snapshot().recoveryRequirement
            == .reconcileAgentAndNetworkAdmission
    )
    await #expect(throws: MacUpdateInstallAuthorityErrorV0.closed) {
        try await authority.handOffToUpdater(
            monotonicNowMilliseconds: 5,
            menuForeground: true
        ) {}
    }
}

@Test func wrongOrderCannotSkipShutdownStages() async throws {
    let authority = MacUpdateInstallAuthorityV0(
        candidate: try updateCandidate()
    )
    try await authority.confirm(
        monotonicNowMilliseconds: 0,
        menuForeground: true
    )
    await #expect(throws: MacUpdateInstallAuthorityErrorV0.invalidPhase) {
        _ = try await authority.boundedWorkDidDrain(
            monotonicNowMilliseconds: 1,
            menuForeground: true
        )
    }
    #expect(await authority.snapshot().phase == .confirmationAccepted)
}

@Test func agentVersionMismatchAndRuntimeFailureCloseAuthority()
async throws {
    let mismatch = MacUpdateInstallAuthorityV0(
        candidate: try updateCandidate()
    )
    try await prepareStoppingAgent(mismatch)
    await #expect(throws: MacUpdateInstallAuthorityErrorV0
        .agentVersionMismatch) {
        try await mismatch.agentDidStop(
            exactVersionMatch: false,
            monotonicNowMilliseconds: 4,
            menuForeground: true
        )
    }
    #expect(await mismatch.snapshot().phase == .closed)
    #expect(
        await mismatch.snapshot().recoveryRequirement
            == .reconcileAgentAndNetworkAdmission
    )

    let failure = MacUpdateInstallAuthorityV0(
        candidate: try updateCandidate()
    )
    try await failure.confirm(
        monotonicNowMilliseconds: 0,
        menuForeground: true
    )
    await failure.runtimeShutdownFailed()
    #expect(await failure.snapshot().phase == .closed)
    #expect(await failure.snapshot().recoveryRequirement == .none)
}

@Test func updaterFailureIsSanitizedAndCannotRetry() async throws {
    let authority = MacUpdateInstallAuthorityV0(
        candidate: try updateCandidate()
    )
    try await prepareReady(authority)
    await #expect(throws: MacUpdateInstallAuthorityErrorV0.updaterRejected) {
        try await authority.handOffToUpdater(
            monotonicNowMilliseconds: 5,
            menuForeground: true
        ) {
            throw SyntheticUpdaterFailureV0.failed
        }
    }
    #expect(await authority.snapshot().phase == .closed)
    #expect(
        await authority.snapshot().recoveryRequirement
            == .reconcileAgentAndNetworkAdmission
    )
}

@Test func handoffCannotBeRevokedOrReclassifiedAcrossSuspension()
async throws {
    let authority = MacUpdateInstallAuthorityV0(
        candidate: try updateCandidate()
    )
    try await prepareReady(authority)
    try await authority.handOffToUpdater(
        monotonicNowMilliseconds: 5,
        menuForeground: true
    ) {
        await authority.finish()
        await authority.runtimeShutdownFailed()
        await authority.menuForegroundDidChange(false)
    }
    let snapshot = await authority.snapshot()
    #expect(snapshot.phase == .closed)
    #expect(snapshot.recoveryRequirement == .none)
}

@Test func cancellationRecordsTheMinimumSafeReconciliationScope()
async throws {
    let duringAdmissionClose = MacUpdateInstallAuthorityV0(
        candidate: try updateCandidate()
    )
    try await duringAdmissionClose.confirm(
        monotonicNowMilliseconds: 0,
        menuForeground: true
    )
    _ = try await duringAdmissionClose.beginRuntimeShutdown(
        monotonicNowMilliseconds: 1,
        menuForeground: true,
        controlState: .inactive
    )
    await duringAdmissionClose.runtimeShutdownFailed()
    #expect(
        await duringAdmissionClose.snapshot().recoveryRequirement
            == .reconcileNetworkAdmission
    )

    let duringAgentStop = MacUpdateInstallAuthorityV0(
        candidate: try updateCandidate()
    )
    try await prepareStoppingAgent(duringAgentStop)
    await duringAgentStop.finish()
    #expect(
        await duringAgentStop.snapshot().recoveryRequirement
            == .reconcileAgentAndNetworkAdmission
    )
}

private func prepareStoppingAgent(
    _ authority: MacUpdateInstallAuthorityV0
) async throws {
    try await authority.confirm(
        monotonicNowMilliseconds: 0,
        menuForeground: true
    )
    _ = try await authority.beginRuntimeShutdown(
        monotonicNowMilliseconds: 1,
        menuForeground: true,
        controlState: .inactive
    )
    _ = try await authority.networkAdmissionDidClose(
        monotonicNowMilliseconds: 2,
        menuForeground: true
    )
    _ = try await authority.boundedWorkDidDrain(
        monotonicNowMilliseconds: 3,
        menuForeground: true
    )
}

private func prepareReady(
    _ authority: MacUpdateInstallAuthorityV0
) async throws {
    try await prepareStoppingAgent(authority)
    try await authority.agentDidStop(
        exactVersionMatch: true,
        monotonicNowMilliseconds: 4,
        menuForeground: true
    )
}

private enum SyntheticUpdaterFailureV0: Error {
    case failed
}

private final class LockedCounterV0: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.withLock { storage }
    }

    func increment() {
        lock.withLock { storage += 1 }
    }
}
