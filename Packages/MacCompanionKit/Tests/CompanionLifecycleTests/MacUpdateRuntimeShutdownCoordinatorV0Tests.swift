import CompanionLifecycle
import Foundation
import Testing

private let coordinatorKeyV0 =
    Data(repeating: 0x71, count: 32).base64EncodedString()
private let coordinatorArchiveSignatureV0 =
    Data(repeating: 0x17, count: 64).base64EncodedString()

private func runtimeAdmissionV0() async throws
    -> MacUpdateInstallAdmissionV0
{
    let release = try MacUpdateReleaseAuthorityV0(
        profile: MacUpdateReleaseAuthorityV0.profile,
        channel: "beta",
        feedURL: "https://updates.example.com/mac/beta/appcast.xml",
        publicEd25519KeyBase64: coordinatorKeyV0
    )
    let candidate = try MacUpdateFeedCandidateV0(
        authority: release,
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
        archiveEd25519Signature: coordinatorArchiveSignatureV0
    )
    let owner = MacUpdateInstallCandidateAdmissionV0(
        feedCandidate: candidate
    )
    return try await owner.admit(
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

private func runtimeDependenciesV0(
    _ harness: UpdateRuntimeHarnessV0
) -> MacUpdateRuntimeShutdownDependenciesV0 {
    MacUpdateRuntimeShutdownDependenciesV0(
        observeGate: { await harness.observe() },
        closeNetworkAdmission: {
            try await harness.effect("closeNetwork")
        },
        drainBoundedWork: {
            try await harness.effect("drainWork")
        },
        stopAgent: {
            try await harness.stopAgent()
        },
        startUpdater: {
            try await harness.effect("startUpdater")
        },
        reconcileNetworkAdmission: {
            try await harness.effect("recoverNetwork")
        },
        reconcileAgentAndNetworkAdmission: {
            try await harness.effect("recoverAgentAndNetwork")
        }
    )
}

@Test func coordinatorRunsExactShutdownOrderThenOneUpdaterHandoff()
async throws {
    let harness = UpdateRuntimeHarnessV0()
    let coordinator = MacUpdateRuntimeShutdownCoordinatorV0(
        admission: try await runtimeAdmissionV0(),
        dependencies: runtimeDependenciesV0(harness)
    )

    try await coordinator.confirm()
    await #expect(
        throws: MacUpdateRuntimeShutdownCoordinatorErrorV0.invalidPhase
    ) {
        try await coordinator.confirm()
    }
    try await coordinator.install()

    #expect(
        await harness.events
            == ["closeNetwork", "drainWork", "stopAgent", "startUpdater"]
    )
    #expect(await coordinator.currentPhase() == .finished)
    #expect(await coordinator.authoritySnapshot().phase == .closed)
    #expect(
        await coordinator.authoritySnapshot().recoveryRequirement == .none
    )
    await #expect(
        throws: MacUpdateRuntimeShutdownCoordinatorErrorV0.invalidPhase
    ) {
        try await coordinator.install()
    }
}

@Test func eachRuntimeFailureUsesTheMinimumRecoveryScope() async throws {
    let cases = [
        (
            "closeNetwork", "recoverNetwork",
            MacUpdateRuntimeShutdownCoordinatorErrorV0.runtimeEffectFailed
        ),
        (
            "drainWork", "recoverNetwork",
            MacUpdateRuntimeShutdownCoordinatorErrorV0.runtimeEffectFailed
        ),
        (
            "stopAgent", "recoverAgentAndNetwork",
            MacUpdateRuntimeShutdownCoordinatorErrorV0.runtimeEffectFailed
        ),
        (
            "startUpdater", "recoverAgentAndNetwork",
            MacUpdateRuntimeShutdownCoordinatorErrorV0
                .authority(.updaterRejected)
        ),
    ]

    for (failure, recovery, expected) in cases {
        let harness = UpdateRuntimeHarnessV0(failingEffect: failure)
        let coordinator = MacUpdateRuntimeShutdownCoordinatorV0(
            admission: try await runtimeAdmissionV0(),
            dependencies: runtimeDependenciesV0(harness)
        )
        try await coordinator.confirm()
        await #expect(
            throws: expected
        ) {
            try await coordinator.install()
        }
        #expect(await harness.events.last == recovery)
        #expect(await coordinator.currentPhase() == .finished)
    }
}

@Test func versionMismatchAndForegroundLossRecoverBeforeReturning()
async throws {
    let mismatchHarness = UpdateRuntimeHarnessV0(exactVersionMatch: false)
    let mismatch = MacUpdateRuntimeShutdownCoordinatorV0(
        admission: try await runtimeAdmissionV0(),
        dependencies: runtimeDependenciesV0(mismatchHarness)
    )
    try await mismatch.confirm()
    await #expect(
        throws: MacUpdateRuntimeShutdownCoordinatorErrorV0
            .authority(.agentVersionMismatch)
    ) {
        try await mismatch.install()
    }
    #expect(
        await mismatchHarness.events.last
            == "recoverAgentAndNetwork"
    )

    let foregroundHarness = UpdateRuntimeHarnessV0(
        foregroundObservations: [true, true, false]
    )
    let foreground = MacUpdateRuntimeShutdownCoordinatorV0(
        admission: try await runtimeAdmissionV0(),
        dependencies: runtimeDependenciesV0(foregroundHarness)
    )
    try await foreground.confirm()
    await #expect(
        throws: MacUpdateRuntimeShutdownCoordinatorErrorV0
            .authority(.foregroundRequired)
    ) {
        try await foreground.install()
    }
    #expect(await foregroundHarness.events.last == "recoverNetwork")
}

@Test func failedRecoveryIsAClosedSanitizedTerminalResult() async throws {
    let harness = UpdateRuntimeHarnessV0(
        failingEffect: "closeNetwork",
        failingRecovery: true
    )
    let coordinator = MacUpdateRuntimeShutdownCoordinatorV0(
        admission: try await runtimeAdmissionV0(),
        dependencies: runtimeDependenciesV0(harness)
    )
    try await coordinator.confirm()

    await #expect(
        throws: MacUpdateRuntimeShutdownCoordinatorErrorV0.recoveryFailed
    ) {
        try await coordinator.install()
    }
    #expect(await coordinator.currentPhase() == .finished)
    #expect(await coordinator.authoritySnapshot().phase == .closed)
}

@Test func backgroundConfirmationAndCancellationCannotStartEffects()
async throws {
    let backgroundHarness = UpdateRuntimeHarnessV0(
        foregroundObservations: [false]
    )
    let background = MacUpdateRuntimeShutdownCoordinatorV0(
        admission: try await runtimeAdmissionV0(),
        dependencies: runtimeDependenciesV0(backgroundHarness)
    )
    await #expect(
        throws: MacUpdateRuntimeShutdownCoordinatorErrorV0
            .authority(.foregroundRequired)
    ) {
        try await background.confirm()
    }
    #expect(await backgroundHarness.events.isEmpty)

    let cancelHarness = UpdateRuntimeHarnessV0()
    let cancelled = MacUpdateRuntimeShutdownCoordinatorV0(
        admission: try await runtimeAdmissionV0(),
        dependencies: runtimeDependenciesV0(cancelHarness)
    )
    try await cancelled.confirm()
    await cancelled.cancel()
    await #expect(
        throws: MacUpdateRuntimeShutdownCoordinatorErrorV0.invalidPhase
    ) {
        try await cancelled.install()
    }
    #expect(await cancelHarness.events.isEmpty)
}

private enum SyntheticUpdateRuntimeFailureV0: Error {
    case failed
}

private actor UpdateRuntimeHarnessV0 {
    private(set) var events: [String] = []
    private var nextObservation = 0
    private let foregroundObservations: [Bool]
    private let failingEffect: String?
    private let failingRecovery: Bool
    private let exactVersionMatch: Bool

    init(
        foregroundObservations: [Bool] = [],
        failingEffect: String? = nil,
        failingRecovery: Bool = false,
        exactVersionMatch: Bool = true
    ) {
        self.foregroundObservations = foregroundObservations
        self.failingEffect = failingEffect
        self.failingRecovery = failingRecovery
        self.exactVersionMatch = exactVersionMatch
    }

    func observe() -> MacUpdateRuntimeGateObservationV0 {
        let index = nextObservation
        nextObservation += 1
        let foreground = index < foregroundObservations.count
            ? foregroundObservations[index] : true
        return MacUpdateRuntimeGateObservationV0(
            monotonicNowMilliseconds: Int64(index),
            menuForeground: foreground,
            controlState: .inactive
        )
    }

    func effect(_ name: String) throws {
        events.append(name)
        if failingRecovery, name.hasPrefix("recover") {
            throw SyntheticUpdateRuntimeFailureV0.failed
        }
        if failingEffect == name {
            throw SyntheticUpdateRuntimeFailureV0.failed
        }
    }

    func stopAgent() throws -> Bool {
        try effect("stopAgent")
        return exactVersionMatch
    }
}
