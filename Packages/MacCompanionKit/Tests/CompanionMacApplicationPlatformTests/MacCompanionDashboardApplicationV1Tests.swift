#if os(macOS)
import CompanionIPC
import CompanionLifecycle
import CompanionLocalXPCPlatform
import CompanionMacApp
@testable import CompanionMacApplicationPlatform
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
private final class DashboardApplicationProductRegistryV1:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var products: [DashboardApplicationTestProductV1] = []

    func append(_ product: DashboardApplicationTestProductV1) {
        lock.withLock { products.append(product) }
    }

    func snapshot() -> [DashboardApplicationTestProductV1] {
        lock.withLock { products }
    }
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
    private let retryOutcome: MacAgentDashboardEffectOutcomeV0
    private let startGate = DashboardApplicationOneShotGateV1()
    private let finishGate = DashboardApplicationOneShotGateV1()
    private var suspendFinish = false
    private var starts = 0
    private var retries = 0
    private var closes = 0
    private var drains = 0
    private var reopens = 0
    private var finishes = 0
    private var pairingCreations = 0
    private var connectionToken: MacAgentDashboardConnectionTokenV0?

    init(
        owner: MacAgentDashboardApplicationOwnerV0,
        behavior: StartBehavior = .succeeds,
        retryOutcome: MacAgentDashboardEffectOutcomeV0 = .completed
    ) {
        self.owner = owner
        self.behavior = behavior
        self.retryOutcome = retryOutcome
    }

    func start() async throws {
        lock.withLock { starts += 1 }
        let token = try await owner.beginConnection()
        lock.withLock { connectionToken = token }
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
        return retryOutcome
    }

    func closeNetworkAdmissionForUpdate() async throws {
        lock.withLock { closes += 1 }
    }

    func drainNetworkConnectionsForUpdate() async throws {
        lock.withLock { drains += 1 }
    }

    func reopenNetworkAdmissionAfterUpdateFailure() async throws {
        lock.withLock { reopens += 1 }
    }

    func createPairingSession(
        _: LocalPairingSessionCreateCommandV0
    ) async throws -> LocalPairingSessionCreatedReceiptV0 {
        lock.withLock { pairingCreations += 1 }
        throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
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

    func reopenCount() -> Int { lock.withLock { reopens } }

    func pairingCreationCount() -> Int {
        lock.withLock { pairingCreations }
    }

    func publishReadyStatus(pairedDeviceCount: UInt16) async throws {
        let token = lock.withLock { connectionToken }
        guard let token else { throw StartError.injected }
        try await owner.receive(
            LocalAgentStatusSnapshot(
                desiredEnabled: true,
                consoleSession: .active,
                agentProcess: .ready,
                menuAppProcess: .ready,
                networkState: .listening,
                securityPosture: .nominal,
                routeKinds: [.lan],
                pairedDeviceCount: pairedDeviceCount,
                activeRemoteSessionCount: 0,
                providerCount: 1,
                warningCodes: [],
                diagnosticSequence: 1,
                generatedAtUnixMilliseconds: 1_787_198_400_000
            ),
            from: token
        )
    }

    func publishConnectionUnavailable() async throws {
        let token = lock.withLock { connectionToken }
        guard let token else { throw StartError.injected }
        try await owner.connectionUnavailable(token)
    }

    func updateCommandCounts() -> (closes: Int, drains: Int, reopens: Int) {
        lock.withLock { (closes, drains, reopens) }
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
        let application = MacCompanionDashboardApplicationV1(
            productFactory: { owner in
                let value = DashboardApplicationTestProductV1(
                    owner: owner,
                    behavior: behavior
                )
                product = value
                return value
            }
        )
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
func unavailableAutomaticallyReplacesOneShotProductAndStartsFreshGeneration()
    async throws
{
    let registry = DashboardApplicationProductRegistryV1()
    let application = await MainActor.run {
        let application = MacCompanionDashboardApplicationV1(
            productFactory: { owner in
                let product = DashboardApplicationTestProductV1(
                    owner: owner,
                    retryOutcome: .notCompleted
                )
                registry.append(product)
                return product
            }
        )
        return application
    }
    let first = try #require(registry.snapshot().first)

    try await application.start()
    try await first.publishConnectionUnavailable()
    #expect(await application.source == .unavailable)

    for _ in 0..<200 where registry.snapshot().count == 1 {
        try await Task.sleep(for: .milliseconds(5))
    }

    let replacement = try #require(registry.snapshot().last)
    #expect(replacement !== first)
    #expect(first.snapshot() == (1, 1, 1))
    #expect(replacement.snapshot() == (1, 0, 0))
    #expect(await application.source == .loading)

    await application.finish()
    #expect(replacement.snapshot() == (1, 0, 1))
}

@Test
@available(macOS 26.0, *)
func pairingStateRelayRemainsAliveForApplicationLifetime() async throws {
    let (application, product): (
        MacCompanionDashboardApplicationV1,
        DashboardApplicationTestProductV1
    ) = await MainActor.run {
        var product: DashboardApplicationTestProductV1?
        let application = MacCompanionDashboardApplicationV1(
            testingPairingStateRelay: (),
            productFactory: { owner in
                let value = DashboardApplicationTestProductV1(owner: owner)
                product = value
                return value
            }
        )
        return (application, product!)
    }

    try await application.start()
    try await product.publishReadyStatus(pairedDeviceCount: 0)
    await application.beginPairing()

    #expect(product.pairingCreationCount() == 1)
    let phase = await application.pairingSession.phase
    let creationFailed = if case .creationFailed = phase {
        true
    } else {
        false
    }
    #expect(creationFailed)
    await application.finish()
}

@Test
@available(macOS 26.0, *)
func existingPairedDevicePreventsASecondPairingSession() async throws {
    let (application, product): (
        MacCompanionDashboardApplicationV1,
        DashboardApplicationTestProductV1
    ) = await MainActor.run {
        var product: DashboardApplicationTestProductV1?
        let application = MacCompanionDashboardApplicationV1(
            testingPairingStateRelay: (),
            productFactory: { owner in
                let value = DashboardApplicationTestProductV1(owner: owner)
                product = value
                return value
            }
        )
        return (application, product!)
    }

    try await application.start()
    try await product.publishReadyStatus(pairedDeviceCount: 1)
    await application.beginPairing()

    #expect(product.pairingCreationCount() == 0)
    #expect(await application.pairingSession.phase == .idle)
    await application.finish()
}

@Test
@available(macOS 26.0, *)
func updateCommandsAreForwardedOnlyWhileDashboardIsActive()
async throws {
    let (application, product) = await makeDashboardApplicationV1()

    await #expect(throws: MacLocalXPCUpdateQuiescenceErrorV0.unavailable) {
        try await application.closeNetworkAdmissionForUpdate()
    }
    try await application.start()
    try await application.closeNetworkAdmissionForUpdate()
    try await application.drainNetworkConnectionsForUpdate()
    try await application.reopenNetworkAdmissionAfterUpdateFailure()
    #expect(product.updateCommandCounts() == (1, 1, 1))

    await application.finish()
    await #expect(throws: MacLocalXPCUpdateQuiescenceErrorV0.unavailable) {
        try await application.drainNetworkConnectionsForUpdate()
    }
    #expect(product.updateCommandCounts() == (1, 1, 1))
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
            MacCompanionDashboardApplicationV1(productFactory: { owner in
                let value = DashboardApplicationTestProductV1(owner: owner)
                retained = value
                return value
            })
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

@Test
@available(macOS 26.0, *)
func applicationDelegateLaunchStartsDashboardExactlyOnce() async {
    let (application, product) = await makeDashboardApplicationV1()
    let delegate = await MainActor.run {
        MacCompanionDashboardApplicationDelegateV1(
            dashboard: application
        )
    }

    await MainActor.run {
        delegate.beginLaunch()
        delegate.beginLaunch()
    }
    await delegate.waitForLaunch()
    #expect(product.snapshot() == (1, 0, 0))
    #expect(await application.source == .loading)

    await delegate.finish()
    await delegate.finish()
    #expect(product.snapshot() == (1, 0, 1))
    #expect(await application.source == .unavailable)
}

@Test
@available(macOS 26.0, *)
func applicationDelegateLaunchFailureConvergesTerminally() async {
    let (application, product) = await makeDashboardApplicationV1(
        behavior: .fails
    )
    let delegate = await MainActor.run {
        MacCompanionDashboardApplicationDelegateV1(
            dashboard: application
        )
    }

    await delegate.beginLaunch()
    await delegate.waitForLaunch()
    #expect(product.snapshot() == (1, 0, 1))
    #expect(await application.source == .unavailable)
    #expect(await application.retryStatus() == .notCompleted)
    await delegate.finish()
    #expect(product.snapshot() == (1, 0, 1))
}

@Test
@available(macOS 26.0, *)
func applicationDelegateFinishCancelsAndAwaitsSuspendedLaunch() async {
    let (application, product) = await makeDashboardApplicationV1(
        behavior: .suspends
    )
    let delegate = await MainActor.run {
        MacCompanionDashboardApplicationDelegateV1(
            dashboard: application
        )
    }
    await delegate.beginLaunch()
    #expect(
        await eventuallyDashboardApplicationV1 {
            await application.source == .loading
                && product.startIsSuspended()
        }
    )

    await delegate.finish()
    await delegate.waitForLaunch()
    #expect(product.snapshot() == (1, 0, 1))
    #expect(await application.source == .unavailable)
}
#endif
