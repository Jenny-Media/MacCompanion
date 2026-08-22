#if os(macOS)
@testable import CompanionMacApplicationPlatform
import CompanionMacApp
import Foundation
import Testing

private final class DashboardApplicationOneShotGateV1: @unchecked Sendable {
    private let lock = NSLock()
    private var entered = false
    private var signaled = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeImmediately = lock.withLock {
                entered = true
                guard !signaled else { return true }
                precondition(self.continuation == nil)
                self.continuation = continuation
                return false
            }
            if resumeImmediately { continuation.resume() }
        }
    }

    func signal() {
        let continuation = lock.withLock {
            signaled = true
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume()
    }

    func hasEntered() -> Bool { lock.withLock { entered } }
}

@available(macOS 26.0, *)
private final class DashboardApplicationTestProductV1:
    MacCompanionDashboardProductV1,
    @unchecked Sendable
{
    enum StartBehavior {
        case succeeds
        case fails
        case suspends
    }

    enum StartError: Error { case injected }

    private let lock = NSLock()
    private let owner: MacAgentDashboardApplicationOwnerV0
    private let behavior: StartBehavior
    private let startGate = DashboardApplicationOneShotGateV1()
    private let finishGate = DashboardApplicationOneShotGateV1()
    private var suspendFinish = false
    private var starts = 0
    private var retries = 0
    private var finishes = 0

    init(
        owner: MacAgentDashboardApplicationOwnerV0,
        behavior: StartBehavior = .succeeds
    ) {
        self.owner = owner
        self.behavior = behavior
    }

    func start() async throws {
        lock.withLock { starts += 1 }
        _ = try await owner.beginConnection()
        switch behavior {
        case .succeeds:
            return
        case .fails:
            throw StartError.injected
        case .suspends:
            await startGate.wait()
        }
    }

    func retryStatus() async -> MacAgentDashboardEffectOutcomeV0 {
        lock.withLock { retries += 1 }
        return .completed
    }

    func finish() async {
        let shouldSuspend = lock.withLock {
            finishes += 1
            return suspendFinish
        }
        startGate.signal()
        guard shouldSuspend else { return }
        await finishGate.wait()
    }

    func armFinishSuspension() {
        lock.withLock { suspendFinish = true }
    }

    func releaseFinish() {
        lock.withLock { suspendFinish = false }
        finishGate.signal()
    }

    func startIsSuspended() -> Bool { startGate.hasEntered() }
    func finishIsSuspended() -> Bool { finishGate.hasEntered() }

    func snapshot() -> (starts: Int, retries: Int, finishes: Int) {
        lock.withLock { (starts, retries, finishes) }
    }
}

@available(macOS 26.0, *)
private func makeDashboardApplicationV1(
    behavior: DashboardApplicationTestProductV1.StartBehavior = .succeeds
) async -> (
    MacCompanionDashboardApplicationV1,
    DashboardApplicationTestProductV1
) {
    await MainActor.run {
        var product: DashboardApplicationTestProductV1?
        let application = MacCompanionDashboardApplicationV1 { owner in
            let value = DashboardApplicationTestProductV1(
                owner: owner,
                behavior: behavior
            )
            product = value
            return value
        }
        return (application, product!)
    }
}

private func eventuallyDashboardApplicationV1(
    _ condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    for _ in 0..<500 {
        if await condition() { return true }
        await Task.yield()
    }
    return false
}

@Test
@available(macOS 26.0, *)
func constructionIsUnavailableAndStartsNoTransport() async {
    let (application, product) = await makeDashboardApplicationV1()

    #expect(await application.source == .unavailable)
    #expect(await application.retryStatus() == .notCompleted)
    #expect(product.snapshot() == (0, 0, 0))
    await application.finish()
}

@Test
@available(macOS 26.0, *)
func explicitStartPublishesOnlyOwnerProducedLoadingAndEnablesRetry()
    async throws
{
    let (application, product) = await makeDashboardApplicationV1()

    try await application.start()
    #expect(await application.source == .loading)
    #expect(await application.retryStatus() == .completed)
    #expect(product.snapshot() == (1, 1, 0))

    await application.finish()
    #expect(await application.source == .unavailable)
    #expect(await application.retryStatus() == .notCompleted)
    #expect(product.snapshot() == (1, 1, 1))
}

@Test
@available(macOS 26.0, *)
func startFailureConvergesUnavailableAndFinishesExactlyOnce() async {
    let (application, product) = await makeDashboardApplicationV1(
        behavior: .fails
    )

    await #expect(throws: DashboardApplicationTestProductV1.StartError.injected) {
        try await application.start()
    }
    #expect(await application.source == .unavailable)
    #expect(product.snapshot() == (1, 0, 1))
    await application.finish()
    #expect(product.snapshot() == (1, 0, 1))
}

@Test
@available(macOS 26.0, *)
func finishFencesASuspendedStartAndBothAwaitOneBarrier() async {
    let (application, product) = await makeDashboardApplicationV1(
        behavior: .suspends
    )
    product.armFinishSuspension()
    let start = Task { try await application.start() }
    #expect(
        await eventuallyDashboardApplicationV1 {
            await application.source == .loading
                && product.startIsSuspended()
        }
    )

    let firstFinish = Task {
        await application.finish()
        return await application.source
    }
    let secondFinish = Task {
        await application.finish()
        return await application.source
    }
    #expect(
        await eventuallyDashboardApplicationV1 {
            product.snapshot().finishes == 1
                && product.finishIsSuspended()
        }
    )
    product.releaseFinish()
    #expect(await firstFinish.value == .unavailable)
    #expect(await secondFinish.value == .unavailable)
    await #expect(
        throws: MacCompanionDashboardApplicationErrorV1.lifecycleUnavailable
    ) {
        try await start.value
    }
    #expect(product.snapshot() == (1, 0, 1))
    #expect(await application.source == .unavailable)
}

@Test
@available(macOS 26.0, *)
func cancellationOfSuspendedStartAwaitsTerminalCleanup() async {
    let (application, product) = await makeDashboardApplicationV1(
        behavior: .suspends
    )
    let start = Task { try await application.start() }
    #expect(
        await eventuallyDashboardApplicationV1 {
            await application.source == .loading
                && product.startIsSuspended()
        }
    )

    start.cancel()
    await #expect(throws: CancellationError.self) {
        try await start.value
    }
    #expect(product.snapshot() == (1, 0, 1))
    #expect(await application.source == .unavailable)
    #expect(await application.retryStatus() == .notCompleted)
}

@Test
@available(macOS 26.0, *)
func repeatedStartIsRejectedWithoutASecondProductStart() async throws {
    let (application, product) = await makeDashboardApplicationV1()
    try await application.start()

    await #expect(
        throws: MacCompanionDashboardApplicationErrorV1.lifecycleUnavailable
    ) {
        try await application.start()
    }
    #expect(product.snapshot().starts == 1)
    await application.finish()
}

@Test
@available(macOS 26.0, *)
func deinitBeginsBestEffortCleanupWithoutStartingTransport() async {
    let product: DashboardApplicationTestProductV1 = await MainActor.run {
        var retained: DashboardApplicationTestProductV1?
        var application: MacCompanionDashboardApplicationV1? =
            MacCompanionDashboardApplicationV1 { owner in
                let value = DashboardApplicationTestProductV1(owner: owner)
                retained = value
                return value
            }
        #expect(application?.source == .unavailable)
        application = nil
        return retained!
    }

    #expect(
        await eventuallyDashboardApplicationV1 {
            product.snapshot().finishes == 1
        }
    )
    #expect(product.snapshot() == (0, 0, 1))
}
#endif
