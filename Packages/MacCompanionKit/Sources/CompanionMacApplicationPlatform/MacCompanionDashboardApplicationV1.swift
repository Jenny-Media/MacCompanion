#if os(macOS)
import CompanionAgentPlatform
import CompanionMacApp
import Observation

@available(macOS 26.0, *)
public enum MacCompanionDashboardApplicationErrorV1:
    Error,
    Equatable,
    Sendable
{
    case lifecycleUnavailable
}

@available(macOS 26.0, *)
package protocol MacCompanionDashboardProductV1: Sendable {
    func start() async throws
    func retryStatus() async -> MacAgentDashboardEffectOutcomeV0
    func finish() async
}

@available(macOS 26.0, *)
extension MacLocalXPCDashboardProductV1: MacCompanionDashboardProductV1 {}

/// Permanent menu-process ownership of the already-constructed dashboard
/// product. Construction is deliberately transport-inert: only an explicit
/// start may create the local XPC session. The permanent application does not
/// call start until reciprocal signed-process and ready-Agent gates are open.
@available(macOS 26.0, *)
@MainActor
@Observable
public final class MacCompanionDashboardApplicationV1 {
    private enum Phase {
        case idle
        case starting
        case active
        case finishing
        case finished
    }

    public private(set) var source: MacAgentDashboardSourceV0 = .unavailable

    @ObservationIgnored
    private let product: any MacCompanionDashboardProductV1
    @ObservationIgnored
    private let stateRelay: MacCompanionDashboardStateRelayV1
    @ObservationIgnored
    private var phase: Phase = .idle
    @ObservationIgnored
    private var finishTask: Task<Void, Never>?

    public convenience init() {
        self.init { owner in
            MacLocalXPCDashboardProductV1(owner: owner)
        }
    }

    package init(
        productFactory: (
            MacAgentDashboardApplicationOwnerV0
        ) -> any MacCompanionDashboardProductV1
    ) {
        let relay = MacCompanionDashboardStateRelayV1()
        let owner = MacAgentDashboardApplicationOwnerV0 {
            [weak relay] source in
            await relay?.receive(source)
        }
        stateRelay = relay
        product = productFactory(owner)
        relay.application = self
    }

    /// Reserved for the signed-runtime checkpoint. Calling this method is the
    /// sole transition that may activate the constructed local XPC product.
    package func start() async throws {
        guard phase == .idle else {
            throw MacCompanionDashboardApplicationErrorV1
                .lifecycleUnavailable
        }
        phase = .starting
        do {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await product.start()
                try Task.checkCancellation()
            } onCancel: { [weak self] in
                Task { @MainActor in
                    await self?.finish()
                }
            }
        } catch {
            await finish()
            throw error
        }
        guard phase == .starting else {
            await finish()
            throw MacCompanionDashboardApplicationErrorV1
                .lifecycleUnavailable
        }
        phase = .active
    }

    @discardableResult
    public func retryStatus() async -> MacAgentDashboardEffectOutcomeV0 {
        guard phase == .active else { return .notCompleted }
        let outcome = await product.retryStatus()
        guard phase == .active else { return .notCompleted }
        return outcome
    }

    public func finish() async {
        if let finishTask {
            await finishTask.value
            return
        }
        guard phase != .finished else { return }
        phase = .finishing
        let product = self.product
        let task = Task { @MainActor [weak self] in
            await product.finish()
            guard let self else { return }
            self.source = .unavailable
            self.phase = .finished
        }
        finishTask = task
        await task.value
    }

    fileprivate func receive(_ source: MacAgentDashboardSourceV0) {
        guard phase == .starting || phase == .active || phase == .finishing
        else { return }
        self.source = source
    }

    deinit {
        guard finishTask == nil else { return }
        let product = self.product
        Task { await product.finish() }
    }
}

@available(macOS 26.0, *)
@MainActor
private final class MacCompanionDashboardStateRelayV1 {
    weak var application: MacCompanionDashboardApplicationV1?

    func receive(_ source: MacAgentDashboardSourceV0) {
        application?.receive(source)
    }
}
#endif
