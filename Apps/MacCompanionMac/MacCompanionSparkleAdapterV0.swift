import CompanionLifecycle
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
    case failed(channel: MacUpdateChannelV0)
}

/// Inert handoff seed for the later post-validation bridge. Taking this value
/// starts no check, download, shutdown, or installation; it only preserves the
/// exact reviewed candidate and its signed release-evidence projection.
struct MacCompanionUpdateAdmissionSeedV0 {
    let admissionOwner: MacUpdateInstallCandidateAdmissionV0
    let releaseEvidence: MacUpdateReleaseEvidenceV0
}

/// Containing-app-only Sparkle boundary. Missing protected release authority
/// is an ordinary inert state: no Sparkle object is constructed and no network
/// work begins. Configured builds permit explicit informational probes only;
/// every download/install check remains denied until the package-owned runtime
/// installation gate hands off one exact candidate in a later checkpoint.
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
    private var userDriver: SPUStandardUserDriver?
    private var updaterInstance: SPUUpdater?
    private var probePermit = false
    private var pendingOffer: CandidateOffer?

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
        case .ready, .current, .updateAvailable, .failed:
            return true
        case .notConfigured, .invalidConfiguration, .checking:
            return false
        }
    }

    /// Starts only Sparkle's inert scheduler with automatic checks and downloads
    /// disabled. This method never performs an update check itself.
    func start() {
        guard let authority, updaterInstance == nil else { return }

        let userDriver = SPUStandardUserDriver(
            hostBundle: bundle,
            delegate: nil
        )
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
        pendingOffer = nil
        phase = .checking(channel: authority.channel)
        updater.checkForUpdateInformation()
    }

    func takePendingAdmissionSeed()
        -> MacCompanionUpdateAdmissionSeedV0?
    {
        guard case .updateAvailable = phase,
              let offer = pendingOffer else {
            return nil
        }
        pendingOffer = nil
        return MacCompanionUpdateAdmissionSeedV0(
            admissionOwner: MacUpdateInstallCandidateAdmissionV0(
                feedCandidate: offer.candidate
            ),
            releaseEvidence: offer.releaseEvidence
        )
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
            displayVersion: offer.candidate.displayVersion,
            build: offer.candidate.candidateBuild
        )
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

    private struct CandidateOffer {
        let candidate: MacUpdateFeedCandidateV0
        let releaseEvidence: MacUpdateReleaseEvidenceV0
    }

    private static func candidateOffer(
        _ item: SUAppcastItem,
        authority: MacUpdateReleaseAuthorityV0,
        currentBuild: UInt64
    ) -> CandidateOffer? {
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
        return CandidateOffer(
            candidate: candidate,
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
