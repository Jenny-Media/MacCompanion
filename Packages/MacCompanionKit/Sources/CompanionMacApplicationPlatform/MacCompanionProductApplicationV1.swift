#if os(macOS)
import CompanionAgent
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
    private let dashboardFactory: DashboardFactory
    @ObservationIgnored
    private var phase: Phase = .idle
    @ObservationIgnored
    private var dashboardStartTask: Task<Void, Never>?
    @ObservationIgnored
    private var finishTask: Task<Void, Never>?

    public init(
        agentRegistration: any AgentLoginRoleRawServiceV1,
        setup: MacRemoteAccessSetupApplicationV1,
        dashboardFactory: @escaping DashboardFactory = {
            MacCompanionDashboardApplicationV1()
        }
    ) {
        self.agentRegistration = agentRegistration
        self.setup = setup
        self.dashboardFactory = dashboardFactory
        setup.installStateObserver { [weak self] state in
            self?.receiveSetupState(state)
        }
    }

    public func start() async {
        guard phase == .idle else { return }
        phase = .active
        await reconcileRoute()
    }

    public func retryRoute() async {
        guard phase == .active,
              dashboardStartTask == nil else { return }
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
        guard phase == .active else { return }
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
        guard dashboardStartTask == nil else { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.startFreshDashboard(failureRoute: .unavailable)
            self.dashboardStartTask = nil
        }
        dashboardStartTask = task
    }

    private func startFreshDashboard(
        failureRoute: MacCompanionProductRouteV1
    ) async {
        guard phase == .active else { return }
        if let dashboard {
            await dashboard.finish()
            guard phase == .active else { return }
        }
        let candidate = dashboardFactory()
        dashboard = candidate
        route = .dashboard
        do {
            try await candidate.start()
        } catch {
            await candidate.finish()
            guard phase == .active else { return }
            dashboard = nil
            route = failureRoute
        }
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
