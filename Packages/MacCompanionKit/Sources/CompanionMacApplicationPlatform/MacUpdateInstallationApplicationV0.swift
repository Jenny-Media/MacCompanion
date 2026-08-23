#if os(macOS)
import CompanionLifecycle
import Observation

public enum MacUpdateInstallationApplicationFailureV0:
    Equatable,
    Sendable
{
    case authorityDenied
    case controlActive
    case controlCleanupUncertain
    case runtimeEffectFailed
    case recoveryFailed
    case invalidState
}

public enum MacUpdateInstallationApplicationPhaseV0:
    Equatable,
    Sendable
{
    case awaitingConfirmation
    case confirming
    case installing
    case handedOff
    case cancelled
    case failed(MacUpdateInstallationApplicationFailureV0)
}

/// Foreground presentation owner for one already admitted and prepared update.
/// It has no feed, archive, or candidate-construction authority. Confirmation
/// and cancellation are single-use, and the same reply owner is retained by
/// both this lifecycle and the runtime coordinator built by the composition.
@MainActor
@Observable
public final class MacUpdateInstallationApplicationV0 {
    public private(set) var phase:
        MacUpdateInstallationApplicationPhaseV0 = .awaitingConfirmation

    @ObservationIgnored
    private let coordinator: MacUpdateRuntimeShutdownCoordinatorV0
    @ObservationIgnored
    private let preparedInstaller: MacUpdatePreparedInstallerReplyOwnerV0
    @ObservationIgnored
    private var terminalWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        coordinator: MacUpdateRuntimeShutdownCoordinatorV0,
        preparedInstaller: MacUpdatePreparedInstallerReplyOwnerV0
    ) {
        self.coordinator = coordinator
        self.preparedInstaller = preparedInstaller
    }

    public func confirmAndInstall() async {
        guard phase == .awaitingConfirmation else { return }
        phase = .confirming

        do {
            try await coordinator.confirm()
        } catch {
            guard phase != .cancelled else { return }
            preparedInstaller.cancel()
            transitionToTerminal(.failed(Self.map(error)))
            return
        }

        guard phase == .confirming else {
            await coordinator.cancel()
            preparedInstaller.cancel()
            return
        }
        phase = .installing

        do {
            try await coordinator.install()
            guard phase == .installing else { return }
            transitionToTerminal(.handedOff)
        } catch {
            preparedInstaller.cancel()
            transitionToTerminal(.failed(Self.map(error)))
        }
    }

    public func cancel() async {
        switch phase {
        case .awaitingConfirmation, .confirming:
            transitionToTerminal(.cancelled)
            preparedInstaller.cancel()
            await coordinator.cancel()
        case .installing, .handedOff, .cancelled, .failed:
            return
        }
    }

    /// Foreground restoration does not resurrect a cancelled authority. Loss
    /// before installation begins cancels immediately; loss during shutdown is
    /// forwarded to the authority so its next boundary fails and recovers.
    public func menuForegroundDidChange(_ foreground: Bool) async {
        guard !foreground else { return }
        switch phase {
        case .awaitingConfirmation, .confirming:
            transitionToTerminal(.cancelled)
            preparedInstaller.cancel()
            await coordinator.menuForegroundDidChange(false)
        case .installing:
            await coordinator.menuForegroundDidChange(false)
        case .handedOff, .cancelled, .failed:
            return
        }
    }

    /// Application termination is a barrier, not best effort. Before shutdown
    /// it cancels immediately. During shutdown it closes foreground authority
    /// and waits until the in-flight coordinator either hands off or completes
    /// its minimum recorded recovery.
    public func applicationTerminationRequested() async {
        switch phase {
        case .awaitingConfirmation, .confirming:
            await cancel()
        case .installing:
            await coordinator.menuForegroundDidChange(false)
            await waitForTerminal()
        case .handedOff, .cancelled, .failed:
            return
        }
    }

    private func waitForTerminal() async {
        guard !phase.isTerminal else { return }
        await withCheckedContinuation { continuation in
            terminalWaiters.append(continuation)
        }
    }

    private func transitionToTerminal(
        _ terminal: MacUpdateInstallationApplicationPhaseV0
    ) {
        precondition(terminal.isTerminal)
        phase = terminal
        let waiters = terminalWaiters
        terminalWaiters.removeAll(keepingCapacity: false)
        for waiter in waiters { waiter.resume() }
    }

    private static func map(_ error: Error)
        -> MacUpdateInstallationApplicationFailureV0
    {
        guard let error = error as?
                MacUpdateRuntimeShutdownCoordinatorErrorV0 else {
            return .invalidState
        }
        switch error {
        case .invalidPhase:
            return .invalidState
        case let .authority(authority):
            switch authority {
            case .controlActive:
                return .controlActive
            case .controlCleanupUncertain:
                return .controlCleanupUncertain
            case .invalidPhase, .invalidClock, .foregroundRequired,
                    .confirmationExpired, .agentVersionMismatch,
                    .updaterRejected, .closed:
                return .authorityDenied
            }
        case .runtimeEffectFailed:
            return .runtimeEffectFailed
        case .recoveryFailed:
            return .recoveryFailed
        }
    }

    isolated deinit {
        preparedInstaller.cancel()
        for waiter in terminalWaiters { waiter.resume() }
        let coordinator = self.coordinator
        Task { await coordinator.cancel() }
    }
}

private extension MacUpdateInstallationApplicationPhaseV0 {
    var isTerminal: Bool {
        switch self {
        case .awaitingConfirmation, .confirming, .installing:
            return false
        case .handedOff, .cancelled, .failed:
            return true
        }
    }
}
#endif
