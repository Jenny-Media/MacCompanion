import AppKit
import CompanionLifecycle
import CompanionMacApplicationPlatform
import Foundation

enum MacCompanionUpdateRuntimeCompositionErrorV0: Error {
    case dashboardUnavailable
}

/// Permanent containing-app composition for one already admitted prepared
/// update. Construction is effect-inert. The Sparkle hold point does not yet
/// invoke this factory, so it cannot close the listener or start an installer.
@MainActor
final class MacCompanionUpdateRuntimeCompositionV0 {
    typealias MonotonicMilliseconds = @MainActor @Sendable () -> Int64
    typealias Foreground = @MainActor @Sendable () -> Bool

    private let product: MacCompanionProductApplicationV1
    private let agentReactivation:
        MacCompanionUpdateAgentReactivationCompositionV0
    private let interactiveIndicator: MacInteractiveActivityIndicatorV1
    private let monotonicMilliseconds: MonotonicMilliseconds
    private let foreground: Foreground

    init(
        product: MacCompanionProductApplicationV1,
        agentReactivation:
            MacCompanionUpdateAgentReactivationCompositionV0,
        interactiveIndicator: MacInteractiveActivityIndicatorV1,
        monotonicMilliseconds:
            @escaping MonotonicMilliseconds = {
                let milliseconds =
                    ProcessInfo.processInfo.systemUptime * 1_000
                guard milliseconds.isFinite,
                      milliseconds >= 0,
                      milliseconds <= Double(Int64.max) else {
                    return -1
                }
                return Int64(milliseconds.rounded(.down))
            },
        foreground: @escaping Foreground = { NSApp.isActive }
    ) {
        self.product = product
        self.agentReactivation = agentReactivation
        self.interactiveIndicator = interactiveIndicator
        self.monotonicMilliseconds = monotonicMilliseconds
        self.foreground = foreground
    }

    func makeInstallationApplication(
        admission: MacUpdateInstallAdmissionV0,
        preparedInstaller: MacUpdatePreparedInstallerReplyOwnerV0
    ) throws -> MacUpdateInstallationApplicationV0 {
        guard product.route == .dashboard,
              let dashboard = product.dashboard else {
            throw MacCompanionUpdateRuntimeCompositionErrorV0
                .dashboardUnavailable
        }
        let stopOwner = try agentReactivation.makeStopOwner(
            candidateBuild: admission.candidateBuild
        )
        let recovery = product.makeUpdateNetworkAdmissionRecovery()
        let indicator = interactiveIndicator
        let monotonicMilliseconds = self.monotonicMilliseconds
        let foreground = self.foreground
        return MacUpdateMenuRuntimeCompositionV0.installationApplication(
            admission: admission,
            agentCommands: dashboard,
            agentStopOwner: stopOwner,
            observeGate: { @MainActor in
                MacUpdateRuntimeGateObservationV0(
                    monotonicNowMilliseconds: monotonicMilliseconds(),
                    menuForeground: foreground(),
                    controlState: indicator.updateControlState
                )
            },
            preparedInstaller: preparedInstaller,
            recovery: recovery
        )
    }
}
