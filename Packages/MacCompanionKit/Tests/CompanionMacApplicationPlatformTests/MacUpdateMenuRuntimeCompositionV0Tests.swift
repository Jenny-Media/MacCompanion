#if os(macOS)
import CompanionLifecycle
import CompanionMacApplicationPlatform
import Foundation
import Testing

private enum MenuUpdateCompositionFailureV0: Error {
    case injected
}

private actor MenuUpdateCompositionHarnessV0:
    MacUpdateMenuAgentCommandingV0,
    MacUpdatePreparedInstallerStartingV0
{
    private var events: [String] = []
    private let failingEvent: String?

    init(failingEvent: String? = nil) {
        self.failingEvent = failingEvent
    }

    func closeNetworkAdmissionForUpdate() throws {
        try record("closeNetwork")
    }

    func drainNetworkConnectionsForUpdate() throws {
        try record("drainNetwork")
    }

    func reopenNetworkAdmissionAfterUpdateFailure() throws {
        try record("reopenNetwork")
    }

    @MainActor
    func startPreparedUpdate() async throws {
        try await record("startInstaller")
    }

    func registrationState() -> MacUpdateAgentRegistrationStateV0 {
        events.append("registrationState")
        return .notRegistered
    }

    func currentReceipt()
        -> MacUpdateAgentReactivationReceiptV0?
    {
        events.append("currentReceipt")
        return nil
    }

    func reconcileNetworkAdmission() throws {
        try record("reconcileNetworkAdmission")
    }

    func snapshot() -> [String] {
        events
    }

    private func record(_ event: String) throws {
        events.append(event)
        if event == failingEvent {
            throw MenuUpdateCompositionFailureV0.injected
        }
    }
}

private actor MenuUpdateObservationGateV0 {
    private var entered = false
    private var continuation: CheckedContinuation<Void, Never>?

    func observe() async -> MacUpdateRuntimeGateObservationV0 {
        entered = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return MacUpdateRuntimeGateObservationV0(
            monotonicNowMilliseconds: 10,
            menuForeground: true,
            controlState: .inactive
        )
    }

    func hasEntered() -> Bool { entered }

    func release() {
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume()
    }
}

private actor MenuUpdateSecondObservationGateV0 {
    private var observations = 0
    private var suspended = false
    private var continuation: CheckedContinuation<Void, Never>?

    func observe() async -> MacUpdateRuntimeGateObservationV0 {
        observations += 1
        if observations == 2 {
            suspended = true
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        return MacUpdateRuntimeGateObservationV0(
            monotonicNowMilliseconds: 10,
            menuForeground: true,
            controlState: .inactive
        )
    }

    func isSuspended() -> Bool { suspended }

    func release() {
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume()
    }
}

@Test @MainActor
func preparedInstallerReplyOwnerInstallsExactlyOnce() async throws {
    var replies: [MacUpdatePreparedInstallerReplyV0] = []
    let owner = MacUpdatePreparedInstallerReplyOwnerV0 {
        replies.append($0)
    }

    try await owner.startPreparedUpdate()
    owner.cancel()
    await #expect(
        throws: MacUpdatePreparedInstallerReplyOwnerErrorV0.alreadyResolved
    ) {
        try await owner.startPreparedUpdate()
    }

    #expect(replies == [.install])
}

@Test @MainActor
func preparedInstallerReplyOwnerCancelsOrRetiresToSkip() async {
    var replies: [MacUpdatePreparedInstallerReplyV0] = []
    var owner: MacUpdatePreparedInstallerReplyOwnerV0? =
        MacUpdatePreparedInstallerReplyOwnerV0 {
            replies.append($0)
        }
    owner?.cancel()
    owner?.cancel()
    owner = nil

    var retired: MacUpdatePreparedInstallerReplyOwnerV0? =
        MacUpdatePreparedInstallerReplyOwnerV0 {
            replies.append($0)
        }
    retired = nil
    _ = retired

    #expect(replies == [.skip, .skip])
}

private func menuUpdateAdmissionV0() async throws
    -> MacUpdateInstallAdmissionV0
{
    let key = Data(repeating: 0x41, count: 32).base64EncodedString()
    let signature = Data(repeating: 0x14, count: 64)
        .base64EncodedString()
    let authority = try MacUpdateReleaseAuthorityV0(
        profile: MacUpdateReleaseAuthorityV0.profile,
        channel: "beta",
        feedURL: "https://updates.example.com/mac/beta/appcast.xml",
        publicEd25519KeyBase64: key
    )
    let candidate = try MacUpdateFeedCandidateV0(
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
        archiveEd25519Signature: signature
    )
    let attribute = MacUpdateReleaseEvidenceV0.Attribute.self
    let evidence = try MacUpdateReleaseEvidenceV0(
        feedCandidate: candidate,
        attributes: [
            attribute.profile: MacUpdateReleaseEvidenceV0.profile,
            attribute.level: MacUpdateReleaseEvidenceV0.evidenceLevel,
            attribute.channel: "beta",
            attribute.build: "11",
            attribute.displayVersion: "0.2.0",
            attribute.archiveURL: candidate.archiveURL.absoluteString,
            attribute.archiveLength: "13301944",
            attribute.archiveSignature: signature,
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
    )
    let publication = try MacUpdatePublishedCandidateV0(
        feedCandidate: candidate,
        releaseEvidence: evidence
    )
    let correlation = MacUpdateValidationCorrelationV0(
        publication: publication
    )
    try await correlation.willExtract(publication: publication)
    try await correlation.installerDidStart(publication: publication)
    return try await correlation.reachedReadyToInstall()
}

private func menuUpdateStopOwnerV0(
    harness: MenuUpdateCompositionHarnessV0
) throws -> MacUpdateAgentStopOwnerV0 {
    try MacUpdateAgentStopOwnerV0(
        sourceBuild: 10,
        candidateBuild: 11,
        dependencies: MacUpdateAgentReactivationDependenciesV0(
            registrationState: {
                await harness.registrationState()
            },
            currentReceipt: {
                await harness.currentReceipt()
            },
            replaceReceipt: { _, _ in false },
            clearReceipt: { _ in false },
            currentAgentBuild: { nil },
            unregisterAndWait: {},
            registerAndWait: {}
        )
    )
}

private func menuUpdateCoordinatorV0(
    harness: MenuUpdateCompositionHarnessV0
) async throws -> MacUpdateRuntimeShutdownCoordinatorV0 {
    MacUpdateMenuRuntimeCompositionV0.coordinator(
        admission: try await menuUpdateAdmissionV0(),
        agentCommands: harness,
        agentStopOwner: try menuUpdateStopOwnerV0(harness: harness),
        observeGate: {
            MacUpdateRuntimeGateObservationV0(
                monotonicNowMilliseconds: 10,
                menuForeground: true,
                controlState: .inactive
            )
        },
        installer: harness,
        recovery: MacUpdateMenuRuntimeRecoveryV0(
            reconcileNetworkAdmission: {
                try await harness.reconcileNetworkAdmission()
            }
        )
    )
}

@MainActor
private func menuUpdateInstallationApplicationV0(
    harness: MenuUpdateCompositionHarnessV0,
    observation: MacUpdateRuntimeGateObservationV0 = .init(
        monotonicNowMilliseconds: 10,
        menuForeground: true,
        controlState: .inactive
    ),
    replies: @escaping @MainActor (
        MacUpdatePreparedInstallerReplyV0
    ) -> Void
) async throws -> MacUpdateInstallationApplicationV0 {
    let preparedInstaller = MacUpdatePreparedInstallerReplyOwnerV0(
        reply: replies
    )
    return MacUpdateMenuRuntimeCompositionV0.installationApplication(
        admission: try await menuUpdateAdmissionV0(),
        agentCommands: harness,
        agentStopOwner: try menuUpdateStopOwnerV0(harness: harness),
        observeGate: { observation },
        preparedInstaller: preparedInstaller,
        recovery: MacUpdateMenuRuntimeRecoveryV0(
            reconcileNetworkAdmission: {
                try await harness.reconcileNetworkAdmission()
            }
        )
    )
}

@Test @MainActor
func updateInstallationApplicationConfirmsAndHandsOffExactlyOnce()
async throws {
    let harness = MenuUpdateCompositionHarnessV0()
    var replies: [MacUpdatePreparedInstallerReplyV0] = []
    let application = try await menuUpdateInstallationApplicationV0(
        harness: harness,
        replies: { replies.append($0) }
    )

    await application.confirmAndInstall()
    await application.confirmAndInstall()
    await application.cancel()

    #expect(application.phase == .handedOff)
    #expect(replies == [.install])
    #expect(await harness.snapshot() == [
        "closeNetwork", "drainNetwork", "registrationState",
    ])
}

@Test @MainActor
func updateInstallationApplicationCancelAndForegroundLossStayClosed()
async throws {
    let harness = MenuUpdateCompositionHarnessV0()
    var replies: [MacUpdatePreparedInstallerReplyV0] = []
    var application: MacUpdateInstallationApplicationV0? = try await
        menuUpdateInstallationApplicationV0(
            harness: harness,
            replies: { replies.append($0) }
        )

    await application?.menuForegroundDidChange(false)
    await application?.confirmAndInstall()
    await application?.cancel()
    #expect(application?.phase == .cancelled)
    application = nil

    #expect(replies == [.skip])
    #expect(await harness.snapshot().isEmpty)
}

@Test @MainActor
func updateInstallationApplicationReportsControlAndRuntimeFailure()
async throws {
    let activeHarness = MenuUpdateCompositionHarnessV0()
    var activeReplies: [MacUpdatePreparedInstallerReplyV0] = []
    let active = try await menuUpdateInstallationApplicationV0(
        harness: activeHarness,
        observation: .init(
            monotonicNowMilliseconds: 10,
            menuForeground: true,
            controlState: .active
        ),
        replies: { activeReplies.append($0) }
    )

    await active.confirmAndInstall()
    #expect(active.phase == .failed(.controlActive))
    #expect(activeReplies == [.skip])
    #expect(await activeHarness.snapshot().isEmpty)

    let failingHarness = MenuUpdateCompositionHarnessV0(
        failingEvent: "drainNetwork"
    )
    var failingReplies: [MacUpdatePreparedInstallerReplyV0] = []
    let failing = try await menuUpdateInstallationApplicationV0(
        harness: failingHarness,
        replies: { failingReplies.append($0) }
    )

    await failing.confirmAndInstall()
    #expect(failing.phase == .failed(.runtimeEffectFailed))
    #expect(failingReplies == [.skip])
    #expect(await failingHarness.snapshot() == [
        "closeNetwork", "drainNetwork", "reconcileNetworkAdmission",
    ])
}

@Test @MainActor
func foregroundLossFencesSuspendedUpdateConfirmation() async throws {
    let harness = MenuUpdateCompositionHarnessV0()
    let observationGate = MenuUpdateObservationGateV0()
    var replies: [MacUpdatePreparedInstallerReplyV0] = []
    let preparedInstaller = MacUpdatePreparedInstallerReplyOwnerV0 {
        replies.append($0)
    }
    let application = MacUpdateMenuRuntimeCompositionV0
        .installationApplication(
            admission: try await menuUpdateAdmissionV0(),
            agentCommands: harness,
            agentStopOwner: try menuUpdateStopOwnerV0(harness: harness),
            observeGate: { await observationGate.observe() },
            preparedInstaller: preparedInstaller,
            recovery: MacUpdateMenuRuntimeRecoveryV0(
                reconcileNetworkAdmission: {
                    try await harness.reconcileNetworkAdmission()
                }
            )
        )

    let confirmation = Task { @MainActor in
        await application.confirmAndInstall()
    }
    for _ in 0..<500 {
        if await observationGate.hasEntered() { break }
        await Task.yield()
    }
    #expect(await observationGate.hasEntered())

    let foregroundLoss = Task { @MainActor in
        await application.menuForegroundDidChange(false)
    }
    for _ in 0..<500 {
        if application.phase == .cancelled { break }
        await Task.yield()
    }
    #expect(application.phase == .cancelled)
    #expect(replies == [.skip])

    await observationGate.release()
    await confirmation.value
    await foregroundLoss.value

    #expect(application.phase == .cancelled)
    #expect(replies == [.skip])
    #expect(await harness.snapshot().isEmpty)
}

@Test @MainActor
func applicationTerminationWaitsForInFlightUpdateRecovery() async throws {
    let harness = MenuUpdateCompositionHarnessV0()
    let observationGate = MenuUpdateSecondObservationGateV0()
    var replies: [MacUpdatePreparedInstallerReplyV0] = []
    let preparedInstaller = MacUpdatePreparedInstallerReplyOwnerV0 {
        replies.append($0)
    }
    let application = MacUpdateMenuRuntimeCompositionV0
        .installationApplication(
            admission: try await menuUpdateAdmissionV0(),
            agentCommands: harness,
            agentStopOwner: try menuUpdateStopOwnerV0(harness: harness),
            observeGate: { await observationGate.observe() },
            preparedInstaller: preparedInstaller,
            recovery: MacUpdateMenuRuntimeRecoveryV0(
                reconcileNetworkAdmission: {
                    try await harness.reconcileNetworkAdmission()
                }
            )
        )

    let installation = Task { @MainActor in
        await application.confirmAndInstall()
    }
    for _ in 0..<500 {
        if await observationGate.isSuspended() { break }
        await Task.yield()
    }
    #expect(await observationGate.isSuspended())
    #expect(application.phase == .installing)

    let termination = Task { @MainActor in
        await application.applicationTerminationRequested()
    }
    await Task.yield()
    #expect(!termination.isCancelled)
    #expect(replies.isEmpty)

    await observationGate.release()
    await installation.value
    await termination.value

    #expect(application.phase == .failed(.authorityDenied))
    #expect(replies == [.skip])
    #expect(await harness.snapshot().isEmpty)
}

@Test func menuUpdateCompositionRunsExactPreparedInstallOrder()
async throws {
    let harness = MenuUpdateCompositionHarnessV0()
    let coordinator = try await menuUpdateCoordinatorV0(harness: harness)

    try await coordinator.confirm()
    try await coordinator.install()

    #expect(await harness.snapshot() == [
        "closeNetwork", "drainNetwork", "registrationState",
        "startInstaller",
    ])
    #expect(await coordinator.currentPhase() == .finished)
}

@Test func preStopFailureReconcilesNetworkAdmission()
async throws {
    let harness = MenuUpdateCompositionHarnessV0(
        failingEvent: "drainNetwork"
    )
    let coordinator = try await menuUpdateCoordinatorV0(harness: harness)

    try await coordinator.confirm()
    await #expect(
        throws: MacUpdateRuntimeShutdownCoordinatorErrorV0
            .runtimeEffectFailed
    ) {
        try await coordinator.install()
    }

    #expect(await harness.snapshot() == [
        "closeNetwork", "drainNetwork", "reconcileNetworkAdmission",
    ])
}

@Test func postStopFailureRecoversAgentBeforeReplacementSession()
async throws {
    let harness = MenuUpdateCompositionHarnessV0(
        failingEvent: "startInstaller"
    )
    let coordinator = try await menuUpdateCoordinatorV0(harness: harness)

    try await coordinator.confirm()
    await #expect(
        throws: MacUpdateRuntimeShutdownCoordinatorErrorV0
            .authority(.updaterRejected)
    ) {
        try await coordinator.install()
    }

    #expect(await harness.snapshot() == [
        "closeNetwork", "drainNetwork", "registrationState",
        "startInstaller", "currentReceipt", "reconcileNetworkAdmission",
    ])
}
#endif
