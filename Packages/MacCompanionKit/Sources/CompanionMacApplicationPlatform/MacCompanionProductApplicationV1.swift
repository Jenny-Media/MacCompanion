#if os(macOS)
import CompanionAgent
import CompanionLocalXPCPlatform
import CompanionMacApp
import Observation

@available(macOS 26.0, *)
public enum MacCompanionProductRouteV1: Equatable, Sendable {
    case checking
    case setup
    case dashboard
    case requiresLoginItemApproval
    case unavailable
}

public enum MacCompanionUpdateNetworkReconciliationErrorV0:
    Error,
    Equatable,
    Sendable
{
    case unavailable
    case registrationUnavailable
    case effectFailed
    case exhausted
}

/// Process-level containing-app router. Login registration is only a routing
/// input: an enabled registration attempts the authenticated dashboard but is
/// never published as Agent readiness. An absent registration exposes the
/// explicit setup transaction. Only the setup's exact durable receipt may
/// advance that path into a fresh dashboard attempt.
@available(macOS 26.0, *)
@MainActor
@Observable
public final class MacCompanionProductApplicationV1 {
    public typealias DashboardFactory = @MainActor @Sendable ()
        -> MacCompanionDashboardApplicationV1
    public typealias StartupRepair = @MainActor @Sendable () async throws
        -> Void
    public typealias UpdateReconciliationDelay =
        @MainActor @Sendable () async throws -> Void

    private enum Phase {
        case idle
        case active
        case finishing
        case finished
    }

    public private(set) var route: MacCompanionProductRouteV1 = .checking
    public private(set) var dashboard: MacCompanionDashboardApplicationV1?
    public let setup: MacRemoteAccessSetupApplicationV1

    @ObservationIgnored
    private let agentRegistration: any AgentLoginRoleRawServiceV1
    @ObservationIgnored
    private let startupRepair: StartupRepair
    @ObservationIgnored
    private let dashboardFactory: DashboardFactory
    @ObservationIgnored
    private let updateReconciliationDelay: UpdateReconciliationDelay
    @ObservationIgnored
    private var phase: Phase = .idle
    @ObservationIgnored
    private var dashboardStartTask: Task<Void, Never>?
    @ObservationIgnored
    private var updateReconciliationActive = false
    @ObservationIgnored
    private var finishTask: Task<Void, Never>?

    public init(
        agentRegistration: any AgentLoginRoleRawServiceV1,
        setup: MacRemoteAccessSetupApplicationV1,
        startupRepair: @escaping StartupRepair = {},
        dashboardFactory: @escaping DashboardFactory = {
            MacCompanionDashboardApplicationV1()
        },
        updateReconciliationDelay:
            @escaping UpdateReconciliationDelay = {
                try await Task.sleep(for: .milliseconds(250))
            }
    ) {
        self.agentRegistration = agentRegistration
        self.setup = setup
        self.startupRepair = startupRepair
        self.dashboardFactory = dashboardFactory
        self.updateReconciliationDelay = updateReconciliationDelay
        setup.installStateObserver { [weak self] state in
            self?.receiveSetupState(state)
        }
    }

    public func start() async {
        guard phase == .idle else { return }
        phase = .active
        do {
            try await startupRepair()
        } catch {
            guard phase == .active else { return }
            route = .unavailable
            return
        }
        guard phase == .active else { return }
        await reconcileRoute()
    }

    public func retryRoute() async {
        guard phase == .active,
              dashboardStartTask == nil,
              !updateReconciliationActive else { return }
        route = .checking
        await reconcileRoute()
    }

    public func finish() async {
        if let finishTask {
            await finishTask.value
            return
        }
        phase = .finishing
        let setup = self.setup
        let dashboard = self.dashboard
        let dashboardStartTask = self.dashboardStartTask
        dashboardStartTask?.cancel()
        let task = Task { @MainActor [weak self] in
            if let dashboardStartTask { await dashboardStartTask.value }
            await setup.finish()
            await dashboard?.finish()
            guard let self else { return }
            self.dashboardStartTask = nil
            self.dashboard = nil
            self.route = .unavailable
            self.phase = .finished
        }
        finishTask = task
        await task.value
    }

    private func reconcileRoute() async {
        switch await agentRegistration.status() {
        case .notRegistered:
            route = .setup
        case .enabled:
            await startFreshDashboard(failureRoute: .setup)
        case .requiresApproval:
            route = .requiresLoginItemApproval
        case .notFound, .unknown:
            route = .unavailable
        }
    }

    private func receiveSetupState(_ state: MacRemoteAccessSetupStateV1) {
        guard phase == .active, !updateReconciliationActive else { return }
        switch state {
        case .enabled:
            beginDashboardAfterSetupReceipt()
        case .idle, .registeringAgent, .connecting, .readingOffer,
                .awaitingConsent, .enabling, .convergingMenu, .declined,
                .failed, .outcomeUnknown:
            route = .setup
        }
    }

    private func beginDashboardAfterSetupReceipt() {
        guard dashboardStartTask == nil,
              !updateReconciliationActive else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.startFreshDashboard(failureRoute: .unavailable)
            self.dashboardStartTask = nil
        }
        dashboardStartTask = task
    }

    @discardableResult
    private func startFreshDashboard(
        failureRoute: MacCompanionProductRouteV1
    ) async -> Bool {
        guard phase == .active else { return false }
        if let dashboard {
            await dashboard.finish()
            guard phase == .active else { return false }
        }
        let candidate = dashboardFactory()
        dashboard = candidate
        route = .dashboard
        do {
            try await candidate.start()
            return phase == .active && dashboard === candidate
        } catch {
            await candidate.finish()
            guard phase == .active else { return false }
            dashboard = nil
            route = failureRoute
            return false
        }
    }

    /// Reconciles only Agent listener admission after a failed update attempt.
    /// It prefers the current authenticated dashboard, permits one bounded
    /// replacement after transport ambiguity, and never starts an updater.
    public func reconcileNetworkAdmissionForUpdate() async throws {
        guard phase == .active, dashboardStartTask == nil,
              !updateReconciliationActive else {
            throw MacCompanionUpdateNetworkReconciliationErrorV0.unavailable
        }
        updateReconciliationActive = true
        defer { updateReconciliationActive = false }

        for generationAttempt in 0...1 {
            guard phase == .active else {
                throw MacCompanionUpdateNetworkReconciliationErrorV0
                    .unavailable
            }
            if generationAttempt > 0 || dashboard == nil {
                guard await agentRegistration.status() == .enabled else {
                    throw MacCompanionUpdateNetworkReconciliationErrorV0
                        .registrationUnavailable
                }
                guard await startFreshDashboard(
                    failureRoute: .unavailable
                ) else {
                    throw MacCompanionUpdateNetworkReconciliationErrorV0
                        .unavailable
                }
            }
            guard let dashboard else {
                throw MacCompanionUpdateNetworkReconciliationErrorV0
                    .unavailable
            }

            let disposition = try await reconcile(
                dashboard: dashboard,
                permitsReplacement: generationAttempt == 0
            )
            if disposition == .reconciled { return }
        }
        throw MacCompanionUpdateNetworkReconciliationErrorV0.exhausted
    }

    private enum UpdateReconciliationDisposition {
        case reconciled
        case replaceGeneration
    }

    private func reconcile(
        dashboard: MacCompanionDashboardApplicationV1,
        permitsReplacement: Bool
    ) async throws -> UpdateReconciliationDisposition {
        for attempt in 0..<40 {
            guard phase == .active, self.dashboard === dashboard else {
                throw MacCompanionUpdateNetworkReconciliationErrorV0
                    .unavailable
            }
            do {
                try await dashboard
                    .reopenNetworkAdmissionAfterUpdateFailure()
                return .reconciled
            } catch let error as MacLocalXPCUpdateQuiescenceErrorV0 {
                switch error {
                case .commandFailed:
                    break
                case .unavailable:
                    if permitsReplacement { return .replaceGeneration }
                case .malformedOrTransportError, .replyTimedOut,
                     .cancelledAfterSend:
                    if permitsReplacement { return .replaceGeneration }
                    throw MacCompanionUpdateNetworkReconciliationErrorV0
                        .exhausted
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw MacCompanionUpdateNetworkReconciliationErrorV0
                    .effectFailed
            }
            guard attempt < 39 else {
                if permitsReplacement { return .replaceGeneration }
                throw MacCompanionUpdateNetworkReconciliationErrorV0
                    .exhausted
            }
            do {
                try await updateReconciliationDelay()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw MacCompanionUpdateNetworkReconciliationErrorV0
                    .effectFailed
            }
        }
        throw MacCompanionUpdateNetworkReconciliationErrorV0.exhausted
    }

    isolated deinit {
        dashboardStartTask?.cancel()
        guard finishTask == nil else { return }
        let setup = self.setup
        let dashboard = self.dashboard
        Task {
            await setup.finish()
            await dashboard?.finish()
        }
    }
}
#endif
