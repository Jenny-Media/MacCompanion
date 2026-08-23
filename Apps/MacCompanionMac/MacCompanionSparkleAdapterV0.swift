import AppKit
import CompanionLifecycle
import CompanionMacApplicationPlatform
import Combine
import Foundation
import Sparkle

enum MacCompanionUpdatePhaseV0: Equatable {
    case notConfigured
    case invalidConfiguration
    case ready(channel: MacUpdateChannelV0)
    case checking(channel: MacUpdateChannelV0)
    case current(channel: MacUpdateChannelV0)
    case updateAvailable(
        channel: MacUpdateChannelV0,
        displayVersion: String,
        build: UInt64
    )
    case awaitingInstallationConfirmation(
        channel: MacUpdateChannelV0,
        displayVersion: String,
        build: UInt64
    )
    case preparingInstallation(
        channel: MacUpdateChannelV0,
        displayVersion: String,
        build: UInt64
    )
    case installationFailed(
        channel: MacUpdateChannelV0,
        displayVersion: String,
        build: UInt64,
        failure: MacUpdateInstallationApplicationFailureV0
    )
    case failed(channel: MacUpdateChannelV0)
}

private struct MacCompanionUpdateCandidateSummaryV0: Equatable {
    let channel: MacUpdateChannelV0
    let displayVersion: String
    let build: UInt64
}

/// Containing-app-only Sparkle boundary. Missing protected release authority
/// is an ordinary inert state: no Sparkle object is constructed and no network
/// work begins. Configured builds permit explicit informational probes only;
/// every download/install check remains denied. If Sparkle reaches its held
/// ready callback, only the package-owned runtime gate may hand off the exact
/// admitted candidate after a second explicit local confirmation.
@MainActor
final class MacCompanionSparkleAdapterV0:
    NSObject,
    ObservableObject,
    SPUUpdaterDelegate
{
    static let authorityProfileKey =
        "MacCompanionUpdateAuthorityProfile"
    static let channelKey = "MacCompanionUpdateChannel"
    static let feedURLKey = "MacCompanionUpdateFeedURL"
    static let publicKey = "SUPublicEDKey"

    @Published private(set) var phase: MacCompanionUpdatePhaseV0

    private let bundle: Bundle
    private let authority: MacUpdateReleaseAuthorityV0?
    private let currentBuild: UInt64?
    private var userDriver: MacCompanionSparkleUserDriverV0?
    private var updaterInstance: SPUUpdater?
    private var probePermit = false
    private var pendingOffer: MacUpdatePublishedCandidateV0?
    private var activeCorrelation: MacUpdateValidationCorrelationV0?
    private var validationLifecycleTask: Task<Void, Never>?
    private var readinessTask: Task<Void, Never>?
    private var runtimeComposition:
        MacCompanionUpdateRuntimeCompositionV0?
    private var installationApplication:
        MacUpdateInstallationApplicationV0?
    private var installationSummary:
        MacCompanionUpdateCandidateSummaryV0?
    private var installationTask: Task<Void, Never>?

    init(bundle: Bundle = .main) {
        self.bundle = bundle
        switch Self.loadAuthority(from: bundle.infoDictionary ?? [:]) {
        case .absent:
            authority = nil
            currentBuild = nil
            phase = .notConfigured
        case .invalid:
            authority = nil
            currentBuild = nil
            phase = .invalidConfiguration
        case let .valid(value, build):
            authority = value
            currentBuild = build
            phase = .ready(channel: value.channel)
        }
        super.init()
    }

    var canProbe: Bool {
        guard updaterInstance?.canCheckForUpdates == true else {
            return false
        }
        switch phase {
        case .ready, .current, .updateAvailable, .installationFailed,
                .failed:
            return true
        case .notConfigured, .invalidConfiguration, .checking,
                .awaitingInstallationConfirmation,
                .preparingInstallation:
            return false
        }
    }

    func installRuntimeComposition(
        _ runtimeComposition: MacCompanionUpdateRuntimeCompositionV0
    ) {
        precondition(self.runtimeComposition == nil)
        precondition(updaterInstance == nil)
        self.runtimeComposition = runtimeComposition
    }

    /// Starts only Sparkle's inert scheduler with automatic checks and downloads
    /// disabled. This method never performs an update check itself.
    func start() {
        guard let authority, updaterInstance == nil else { return }

        let userDriver = MacCompanionSparkleUserDriverV0(
            hostBundle: bundle
        ) { [weak self] reply in
            self?.handleReadyToInstall(reply: reply) ?? reply(.skip)
        }
        let updater = SPUUpdater(
            hostBundle: bundle,
            applicationBundle: bundle,
            userDriver: userDriver,
            delegate: self
        )
        updater.sendsSystemProfile = false
        updater.automaticallyChecksForUpdates = false
        updater.automaticallyDownloadsUpdates = false
        updater.httpHeaders = nil

        do {
            try updater.start()
            self.userDriver = userDriver
            updaterInstance = updater
            phase = .ready(channel: authority.channel)
        } catch {
            phase = .failed(channel: authority.channel)
        }
    }

    func probeForUpdates() {
        guard let authority,
              let updater = updaterInstance,
              updater.canCheckForUpdates,
              canProbe else {
            return
        }
        probePermit = true
        retireValidationLifecycle()
        pendingOffer = nil
        phase = .checking(channel: authority.channel)
        updater.checkForUpdateInformation()
    }

    func confirmPendingInstallation() {
        guard installationTask == nil,
              let application = installationApplication,
              let summary = installationSummary,
              case .awaitingInstallationConfirmation = phase else {
            return
        }
        phase = .preparingInstallation(
            channel: summary.channel,
            displayVersion: summary.displayVersion,
            build: summary.build
        )
        let task = Task { @MainActor [weak self, weak application] in
            guard let application else { return }
            await application.confirmAndInstall()
            guard let self,
                  self.installationApplication === application else {
                return
            }
            self.installationTask = nil
            self.reconcileInstallationPresentation(application: application)
        }
        installationTask = task
    }

    func cancelPendingInstallation() {
        guard installationTask == nil,
              let application = installationApplication,
              case .awaitingInstallationConfirmation = phase else {
            return
        }
        installationTask = Task { @MainActor [weak self, weak application] in
            guard let application else { return }
            await application.cancel()
            guard let self,
                  self.installationApplication === application else {
                return
            }
            self.installationTask = nil
            self.reconcileInstallationPresentation(application: application)
        }
    }

    func applicationForegroundDidChange(_ foreground: Bool) {
        guard !foreground,
              let application = installationApplication else { return }
        Task { @MainActor [weak self, weak application] in
            guard let application else { return }
            await application.menuForegroundDidChange(false)
            guard let self,
                  self.installationApplication === application else {
                return
            }
            self.reconcileInstallationPresentation(application: application)
        }
    }

    /// Termination barrier for informational/validation state. A later runtime
    /// binding also joins its installation application here before AppKit is
    /// allowed to terminate the process.
    func prepareForApplicationTermination() async {
        probePermit = false
        let validationLifecycleTask = self.validationLifecycleTask
        validationLifecycleTask?.cancel()
        self.validationLifecycleTask = nil
        if let validationLifecycleTask {
            await validationLifecycleTask.value
        }
        let readinessTask = self.readinessTask
        readinessTask?.cancel()
        self.readinessTask = nil
        if let readinessTask { await readinessTask.value }
        let correlation = activeCorrelation
        activeCorrelation = nil
        pendingOffer = nil
        if let correlation { await correlation.cancel() }
        if let installationApplication {
            await installationApplication
                .applicationTerminationRequested()
        }
        if let installationTask { await installationTask.value }
        installationTask = nil
        installationApplication = nil
        installationSummary = nil
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        authority?.feedURL.absoluteString
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        switch authority?.channel {
        case .beta:
            ["beta"]
        case .stable, nil:
            []
        }
    }

    func feedParameters(
        for updater: SPUUpdater,
        sendingSystemProfile: Bool
    ) -> [[String: String]] {
        []
    }

    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? {
        []
    }

    func updater(
        _ updater: SPUUpdater,
        mayPerform updateCheck: SPUUpdateCheck
    ) throws {
        guard updateCheck == .updateInformation,
              probePermit,
              case .checking = phase else {
            throw Self.deniedError(
                "Mac Companion has not authorized this update check."
            )
        }
        probePermit = false
    }

    func updater(
        _ updater: SPUUpdater,
        shouldProceedWithUpdate item: SUAppcastItem,
        updateCheck: SPUUpdateCheck
    ) throws {
        guard updateCheck == .updateInformation,
              case .checking = phase,
              let authority,
              let currentBuild,
              Self.candidateOffer(
                  item,
                  authority: authority,
                  currentBuild: currentBuild
              ) != nil else {
            throw Self.deniedError(
                "Update installation remains closed until local confirmation and safe runtime shutdown complete."
            )
        }
    }

    func updater(
        _ updater: SPUUpdater,
        didFindValidUpdate item: SUAppcastItem
    ) {
        guard let authority,
              let currentBuild,
              case .checking = phase,
              let offer = Self.candidateOffer(
                  item,
                  authority: authority,
                  currentBuild: currentBuild
              ) else {
            if let channel = authority?.channel {
                phase = .failed(channel: channel)
            }
            return
        }
        pendingOffer = offer
        phase = .updateAvailable(
            channel: authority.channel,
            displayVersion: offer.feedCandidate.displayVersion,
            build: offer.feedCandidate.candidateBuild
        )
    }

    func updater(
        _ updater: SPUUpdater,
        willExtractUpdate item: SUAppcastItem
    ) {
        guard let authority,
              let currentBuild,
              let pendingOffer,
              let observed = Self.candidateOffer(
                  item,
                  authority: authority,
                  currentBuild: currentBuild
              ),
              observed == pendingOffer else {
            retireValidationLifecycle(asFailure: true)
            return
        }

        let correlation = MacUpdateValidationCorrelationV0(
            publication: pendingOffer
        )
        self.pendingOffer = nil
        activeCorrelation = correlation
        enqueueValidationEvent(correlation: correlation) {
            try await correlation.willExtract(publication: observed)
        }
    }

    func updater(
        _ updater: SPUUpdater,
        didExtractUpdate item: SUAppcastItem
    ) {
        guard let authority,
              let currentBuild,
              let correlation = activeCorrelation,
              let observed = Self.candidateOffer(
                  item,
                  authority: authority,
                  currentBuild: currentBuild
              ) else {
            retireValidationLifecycle(asFailure: true)
            return
        }

        enqueueValidationEvent(correlation: correlation) {
            try await correlation.installerDidStart(
                publication: observed
            )
        }
    }

    func userDidCancelDownload(_ updater: SPUUpdater) {
        guard activeCorrelation != nil
                || validationLifecycleTask != nil else { return }
        retireValidationLifecycle()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        guard activeCorrelation != nil
                || validationLifecycleTask != nil else { return }
        retireValidationLifecycle(asFailure: true)
    }

    func updaterDidNotFindUpdate(
        _ updater: SPUUpdater,
        error: Error
    ) {
        guard let authority, case .checking = phase else { return }
        pendingOffer = nil
        phase = .current(channel: authority.channel)
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        guard let authority, updateCheck == .updateInformation else {
            return
        }
        probePermit = false
        if error != nil, case .checking = phase {
            pendingOffer = nil
            phase = .failed(channel: authority.channel)
        } else if case .checking = phase {
            pendingOffer = nil
            phase = .current(channel: authority.channel)
        }
    }

    private func enqueueValidationEvent(
        correlation: MacUpdateValidationCorrelationV0,
        operation: @escaping @MainActor () async throws -> Void
    ) {
        let previous = validationLifecycleTask
        validationLifecycleTask = Task { @MainActor [weak self] in
            if let previous { await previous.value }
            guard !Task.isCancelled else {
                await correlation.cancel()
                return
            }
            do {
                try await operation()
            } catch {
                await correlation.cancel()
                guard let self, !Task.isCancelled else { return }
                activeCorrelation = nil
                if let authority {
                    phase = .failed(channel: authority.channel)
                }
            }
        }
    }

    private func handleReadyToInstall(
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        let preparedInstaller = Self.preparedInstaller(reply: reply)
        guard let correlation = activeCorrelation,
              let validationLifecycleTask,
              let runtimeComposition,
              readinessTask == nil,
              installationApplication == nil,
              case let .updateAvailable(
                  channel,
                  displayVersion,
                  build
              ) = phase else {
            preparedInstaller.cancel()
            return
        }
        activeCorrelation = nil
        self.validationLifecycleTask = nil

        let task = Task { @MainActor [weak self] in
            defer { self?.readinessTask = nil }
            await validationLifecycleTask.value
            guard !Task.isCancelled,
                  await correlation.currentPhase()
                    == .awaitingInstallationReadiness else {
                await correlation.cancel()
                preparedInstaller.cancel()
                return
            }

            do {
                let admission = try await correlation
                    .reachedReadyToInstall()
                guard !Task.isCancelled,
                      admission.candidateBuild == build,
                      admission.displayVersion == displayVersion,
                      let self,
                      self.installationApplication == nil else {
                    preparedInstaller.cancel()
                    return
                }
                let application = try runtimeComposition
                    .makeInstallationApplication(
                        admission: admission,
                        preparedInstaller: preparedInstaller
                    )
                let summary = MacCompanionUpdateCandidateSummaryV0(
                    channel: channel,
                    displayVersion: displayVersion,
                    build: build
                )
                installationApplication = application
                installationSummary = summary
                phase = .awaitingInstallationConfirmation(
                    channel: channel,
                    displayVersion: displayVersion,
                    build: build
                )
                NSApp.requestUserAttention(.informationalRequest)
            } catch {
                await correlation.cancel()
                preparedInstaller.cancel()
                guard let self else { return }
                phase = .installationFailed(
                    channel: channel,
                    displayVersion: displayVersion,
                    build: build,
                    failure: .invalidState
                )
            }
        }
        readinessTask = task
    }

    private func reconcileInstallationPresentation(
        application: MacUpdateInstallationApplicationV0
    ) {
        guard installationApplication === application,
              let summary = installationSummary else { return }
        switch application.phase {
        case .awaitingConfirmation:
            phase = .awaitingInstallationConfirmation(
                channel: summary.channel,
                displayVersion: summary.displayVersion,
                build: summary.build
            )
        case .confirming, .installing, .handedOff:
            phase = .preparingInstallation(
                channel: summary.channel,
                displayVersion: summary.displayVersion,
                build: summary.build
            )
        case .cancelled:
            installationApplication = nil
            installationSummary = nil
            phase = .updateAvailable(
                channel: summary.channel,
                displayVersion: summary.displayVersion,
                build: summary.build
            )
        case let .failed(failure):
            installationApplication = nil
            installationSummary = nil
            phase = .installationFailed(
                channel: summary.channel,
                displayVersion: summary.displayVersion,
                build: summary.build,
                failure: failure
            )
        }
    }

    private static func preparedInstaller(
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) -> MacUpdatePreparedInstallerReplyOwnerV0 {
        MacUpdatePreparedInstallerReplyOwnerV0 { choice in
            switch choice {
            case .install:
                reply(.install)
            case .skip:
                reply(.skip)
            }
        }
    }

    private func retireValidationLifecycle(asFailure: Bool = false) {
        validationLifecycleTask?.cancel()
        validationLifecycleTask = nil
        readinessTask?.cancel()
        readinessTask = nil
        let correlation = activeCorrelation
        activeCorrelation = nil
        pendingOffer = nil
        if let correlation {
            Task { await correlation.cancel() }
        }
        if asFailure, let authority {
            phase = .failed(channel: authority.channel)
        }
    }

    private enum LoadedAuthority {
        case absent
        case invalid
        case valid(MacUpdateReleaseAuthorityV0, currentBuild: UInt64)
    }

    private static func loadAuthority(
        from dictionary: [String: Any]
    ) -> LoadedAuthority {
        let keys = [authorityProfileKey, channelKey, feedURLKey, publicKey]
        let values = keys.map { dictionary[$0] as? String }
        let present = values.compactMap { $0 }.filter { !$0.isEmpty }
        guard !present.isEmpty else { return .absent }
        guard values.allSatisfy({ $0?.isEmpty == false }) else {
            return .invalid
        }
        do {
            let authority = try MacUpdateReleaseAuthorityV0(
                    profile: values[0]!,
                    channel: values[1]!,
                    feedURL: values[2]!,
                    publicEd25519KeyBase64: values[3]!
                )
            guard let buildText = dictionary["CFBundleVersion"] as? String,
                  let build = canonicalBuild(buildText) else {
                return .invalid
            }
            return .valid(authority, currentBuild: build)
        } catch {
            return .invalid
        }
    }

    private static func canonicalBuild(_ value: String) -> UInt64? {
        guard !value.isEmpty,
              value.utf8.count <= 20,
              value.first != "0" || value == "0",
              let build = UInt64(value),
              String(build) == value else {
            return nil
        }
        return build
    }

    private static func candidateOffer(
        _ item: SUAppcastItem,
        authority: MacUpdateReleaseAuthorityV0,
        currentBuild: UInt64
    ) -> MacUpdatePublishedCandidateV0? {
        guard let archiveURL = item.fileURL?.absoluteString else {
            return nil
        }
        guard let enclosure = item.propertiesDictionary["enclosure"]
                as? [String: Any],
              let archiveSignature =
                enclosure["sparkle:edSignature"] as? String else {
            return nil
        }
        guard let candidate = try? MacUpdateFeedCandidateV0(
            authority: authority,
            currentBuild: currentBuild,
            itemChannel: item.channel,
            candidateBuild: item.versionString,
            displayVersion: item.displayVersionString,
            archiveURL: archiveURL,
            informationOnly: item.isInformationOnlyUpdate,
            installationType: item.installationType,
            deltaCount: item.deltaUpdates?.count ?? 0,
            signedFeedValidationSucceeded:
                item.signingValidationStatus == .succeeded,
            archiveContentLength: item.contentLength,
            archiveEd25519Signature: archiveSignature
        ),
        let releaseEvidence = releaseEvidence(
            enclosure: enclosure,
            candidate: candidate
        ) else {
            return nil
        }
        return try? MacUpdatePublishedCandidateV0(
            feedCandidate: candidate,
            releaseEvidence: releaseEvidence
        )
    }

    private static func releaseEvidence(
        enclosure: [String: Any],
        candidate: MacUpdateFeedCandidateV0
    ) -> MacUpdateReleaseEvidenceV0? {
        var attributes: [String: String] = [:]
        for (key, value) in enclosure
        where key.hasPrefix(MacUpdateReleaseEvidenceV0.Attribute.prefix) {
            guard let string = value as? String,
                  attributes.updateValue(string, forKey: key) == nil else {
                return nil
            }
        }
        return try? MacUpdateReleaseEvidenceV0(
            feedCandidate: candidate,
            attributes: attributes
        )
    }

    private static func deniedError(_ description: String) -> NSError {
        NSError(
            domain: "media.jenny.maccompanion.update",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}
