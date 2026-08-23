import Foundation
import Sparkle

/// Retains Sparkle's standard UI through complete protocol forwarding while
/// intercepting its only post-validation, pre-install reply. The adapter
/// decides whether `.install` may be forwarded; loss of the adapter cancels
/// the staged update instead.
@MainActor
final class MacCompanionSparkleUserDriverV0:
    NSObject,
    SPUUserDriver
{
    typealias ReadyToInstallHandler =
        (@escaping (SPUUserUpdateChoice) -> Void) -> Void

    private let readyToInstallHandler: ReadyToInstallHandler
    private let standard: SPUStandardUserDriver

    init(
        hostBundle: Bundle,
        readyToInstallHandler: @escaping ReadyToInstallHandler
    ) {
        self.readyToInstallHandler = readyToInstallHandler
        standard = SPUStandardUserDriver(
            hostBundle: hostBundle,
            delegate: nil
        )
        super.init()
    }

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping (SUUpdatePermissionResponse) -> Void
    ) {
        standard.show(request, reply: reply)
    }

    func showUserInitiatedUpdateCheck(
        cancellation: @escaping () -> Void
    ) {
        standard.showUserInitiatedUpdateCheck(
            cancellation: cancellation
        )
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        standard.showUpdateFound(
            with: appcastItem,
            state: state,
            reply: reply
        )
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        standard.showUpdateReleaseNotes(with: downloadData)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(
        _ error: Error
    ) {
        standard.showUpdateReleaseNotesFailedToDownloadWithError(error)
    }

    func showUpdateNotFoundWithError(
        _ error: Error,
        acknowledgement: @escaping () -> Void
    ) {
        standard.showUpdateNotFoundWithError(
            error,
            acknowledgement: acknowledgement
        )
    }

    func showUpdaterError(
        _ error: Error,
        acknowledgement: @escaping () -> Void
    ) {
        standard.showUpdaterError(
            error,
            acknowledgement: acknowledgement
        )
    }

    func showDownloadInitiated(
        cancellation: @escaping () -> Void
    ) {
        standard.showDownloadInitiated(cancellation: cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(
        _ expectedContentLength: UInt64
    ) {
        standard.showDownloadDidReceiveExpectedContentLength(
            expectedContentLength
        )
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        standard.showDownloadDidReceiveData(ofLength: length)
    }

    func showDownloadDidStartExtractingUpdate() {
        standard.showDownloadDidStartExtractingUpdate()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        standard.showExtractionReceivedProgress(progress)
    }

    func showReady(
        toInstallAndRelaunch reply:
            @escaping (SPUUserUpdateChoice) -> Void
    ) {
        standard.showReady(toInstallAndRelaunch: { [weak self] choice in
            guard choice == .install else {
                reply(choice)
                return
            }
            guard let self else {
                reply(.skip)
                return
            }
            readyToInstallHandler(reply)
        })
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        standard.showInstallingUpdate(
            withApplicationTerminated: applicationTerminated,
            retryTerminatingApplication: retryTerminatingApplication
        )
    }

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        standard.showUpdateInstalledAndRelaunched(
            relaunched,
            acknowledgement: acknowledgement
        )
    }

    func dismissUpdateInstallation() {
        standard.dismissUpdateInstallation()
    }
}
