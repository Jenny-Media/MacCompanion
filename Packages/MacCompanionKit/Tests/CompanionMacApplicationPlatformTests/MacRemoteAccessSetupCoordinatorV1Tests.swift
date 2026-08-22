#if os(macOS)
import CompanionAgent
import CompanionIPC
import CompanionLocalXPCPlatform
import CompanionMacApp
@testable import CompanionMacApplicationPlatform
import Foundation
import Testing

private enum RemoteAccessSetupTestErrorV1: Error {
    case start
}

private final class RemoteAccessSetupEventLogV1: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String) { lock.withLock { values.append(value) } }
    func snapshot() -> [String] { lock.withLock { values } }
}

private actor RemoteAccessSetupRoleV1: AgentBootstrapLoginRoleServiceV1 {
    private let name: String
    private let log: RemoteAccessSetupEventLogV1
    private var remainingRegisterFailures: Int
    private let registerFailure: AgentLoginRoleConvergenceErrorV1
    private let acquisition: AgentLoginRoleRegistrationAcquisitionV1
    private var remainingUnregisterFailures: Int
    private var registrations = 0
    private var unregistrations = 0

    init(
        name: String,
        log: RemoteAccessSetupEventLogV1,
        registerFailures: Int = 0,
        registerFailure: AgentLoginRoleConvergenceErrorV1 = .platformFailure,
        acquisition: AgentLoginRoleRegistrationAcquisitionV1 =
            .newlyRegistered,
        unregisterFailures: Int = 0
    ) {
        self.name = name
        self.log = log
        remainingRegisterFailures = registerFailures
        self.registerFailure = registerFailure
        self.acquisition = acquisition
        remainingUnregisterFailures = unregisterFailures
    }

    func register() async throws {
        _ = try await acquireForBootstrap()
    }

    func acquireForBootstrap() async throws
        -> AgentLoginRoleRegistrationAcquisitionV1
    {
        registrations += 1
        log.append("\(name).register")
        guard remainingRegisterFailures > 0 else {
            return acquisition
        }
        remainingRegisterFailures -= 1
        throw registerFailure
    }

    func unregister() async throws {
        unregistrations += 1
        log.append("\(name).unregister")
        guard remainingUnregisterFailures > 0 else { return }
        remainingUnregisterFailures -= 1
        throw AgentLoginRoleConvergenceErrorV1.platformFailure
    }

    func counts() -> (registrations: Int, unregistrations: Int) {
        (registrations, unregistrations)
    }
}

@available(macOS 26.0, *)
private final class RemoteAccessSetupClientV1:
    MacRemoteAccessBootstrapClientV1,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let log: RemoteAccessSetupEventLogV1
    private let startFails: Bool
    private let eventHandler:
        MacLocalXPCRemoteAccessBootstrapClientV1.EventHandler?
    private var starts = 0
    private var reads = 0
    private var commands: [LocalRemoteAccessEnableCommandV0] = []
    private var cancellations = 0

    init(
        log: RemoteAccessSetupEventLogV1,
        startFails: Bool = false,
        eventHandler:
            MacLocalXPCRemoteAccessBootstrapClientV1.EventHandler? = nil
    ) {
        self.log = log
        self.startFails = startFails
        self.eventHandler = eventHandler
    }

    func start() throws {
        lock.withLock { starts += 1 }
        log.append("client.start")
        if startFails { throw RemoteAccessSetupTestErrorV1.start }
    }

    func readOffer() {
        lock.withLock { reads += 1 }
        log.append("client.read")
    }

    func enable(_ command: LocalRemoteAccessEnableCommandV0) {
        lock.withLock { commands.append(command) }
        log.append("client.enable")
    }

    func cancel() {
        lock.withLock { cancellations += 1 }
        log.append("client.cancel")
    }

    func snapshot() -> (
        starts: Int,
        reads: Int,
        commands: [LocalRemoteAccessEnableCommandV0],
        cancellations: Int
    ) {
        lock.withLock { (starts, reads, commands, cancellations) }
    }

    func emit(
        _ event: MacLocalXPCRemoteAccessBootstrapClientEventV1
    ) {
        eventHandler?(event)
    }
}

@available(macOS 26.0, *)
private final class RemoteAccessSetupClientBoxV1: @unchecked Sendable {
    private let lock = NSLock()
    private var value: RemoteAccessSetupClientV1?

    func install(_ value: RemoteAccessSetupClientV1) {
        lock.withLock {
            precondition(self.value == nil)
            self.value = value
        }
    }

    func require() throws -> RemoteAccessSetupClientV1 {
        try #require(lock.withLock { value })
    }
}

private actor RemoteAccessSetupRawRegistrationV1:
    AgentLoginRoleRawServiceV1
{
    private var value: AgentLoginRoleRegistrationStateV1

    init(_ value: AgentLoginRoleRegistrationStateV1) {
        self.value = value
    }

    func status() -> AgentLoginRoleRegistrationStateV1 { value }
    func register() throws { value = .enabled }
    func unregisterAndWait() throws { value = .notRegistered }
}

@available(macOS 26.0, *)
private final class RemoteAccessSetupDashboardProductV1:
    MacCompanionDashboardProductV1,
    @unchecked Sendable
{
    enum Failure: Error { case injected }

    private let lock = NSLock()
    private let fails: Bool
    private var starts = 0
    private var finishes = 0

    init(fails: Bool) { self.fails = fails }

    func start() async throws {
        lock.withLock { starts += 1 }
        if fails { throw Failure.injected }
    }

    func retryStatus() async -> MacAgentDashboardEffectOutcomeV0 {
        .notCompleted
    }

    func finish() async { lock.withLock { finishes += 1 } }

    func snapshot() -> (starts: Int, finishes: Int) {
        lock.withLock { (starts, finishes) }
    }
}

@available(macOS 26.0, *)
private final class RemoteAccessSetupDashboardBoxV1: @unchecked Sendable {
    private let lock = NSLock()
    private let fails: Bool
    private var values: [RemoteAccessSetupDashboardProductV1] = []

    init(fails: Bool = false) { self.fails = fails }

    @MainActor
    func makeApplication() -> MacCompanionDashboardApplicationV1 {
        var retained: RemoteAccessSetupDashboardProductV1?
        let application = MacCompanionDashboardApplicationV1 { _ in
            let product = RemoteAccessSetupDashboardProductV1(
                fails: self.fails
            )
            retained = product
            return product
        }
        lock.withLock { values.append(retained!) }
        return application
    }

    func products() -> [RemoteAccessSetupDashboardProductV1] {
        lock.withLock { values }
    }
}

@available(macOS 26.0, *)
private func remoteAccessSetupOfferV1() throws
    -> LocalRemoteAccessBootstrapOfferV0
{
    try LocalRemoteAccessBootstrapOfferV0(
        offerID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
        expectedIntentRevision: 0,
        createdAtUnixMilliseconds: 1_000,
        expiresAtUnixMilliseconds: 301_000
    )
}

@available(macOS 26.0, *)
private func remoteAccessSetupReceiptV1(
    command: LocalRemoteAccessEnableCommandV0
) throws -> LocalRemoteAccessEnabledReceiptV0 {
    try LocalRemoteAccessEnabledReceiptV0(
        correlationID: command.commandID,
        offerID: command.offer.offerID,
        intentRevision: command.offer.expectedIntentRevision + 1,
        completedAtUnixMilliseconds:
            command.confirmedAtUnixMilliseconds + 1
    )
}

@available(macOS 26.0, *)
private func makeRemoteAccessSetupCoordinatorV1(
    startFails: Bool = false,
    agentRegisterFailures: Int = 0,
    agentUnregisterFailures: Int = 0,
    menuRegisterFailures: Int = 0,
    agentAcquisition: AgentLoginRoleRegistrationAcquisitionV1 =
        .newlyRegistered
) -> (
    MacRemoteAccessSetupCoordinatorV1,
    RemoteAccessSetupRoleV1,
    RemoteAccessSetupRoleV1,
    RemoteAccessSetupClientV1,
    RemoteAccessSetupEventLogV1
) {
    let log = RemoteAccessSetupEventLogV1()
    let agent = RemoteAccessSetupRoleV1(
        name: "agent",
        log: log,
        registerFailures: agentRegisterFailures,
        acquisition: agentAcquisition,
        unregisterFailures: agentUnregisterFailures
    )
    let menu = RemoteAccessSetupRoleV1(
        name: "menu",
        log: log,
        registerFailures: menuRegisterFailures,
        registerFailure: .requiresApproval
    )
    let client = RemoteAccessSetupClientV1(
        log: log,
        startFails: startFails
    )
    let coordinator = MacRemoteAccessSetupCoordinatorV1(
        agent: agent,
        menuApp: menu,
        client: client,
        milliseconds: { 2_000 },
        commandID: {
            UUID(uuidString: "20000000-0000-4000-8000-000000000002")!
        }
    )
    return (coordinator, agent, menu, client, log)
}

@Test
@available(macOS 26.0, *)
func remoteAccessSetupConstructionIsInert() async {
    let (coordinator, agent, menu, client, log) =
        makeRemoteAccessSetupCoordinatorV1()

    #expect(await coordinator.snapshot() == .idle)
    #expect(await agent.counts() == (0, 0))
    #expect(await menu.counts() == (0, 0))
    #expect(client.snapshot().starts == 0)
    #expect(log.snapshot().isEmpty)
}

@Test
@available(macOS 26.0, *)
func remoteAccessSetupOrdersAgentConsentReceiptAndMenu() async throws {
    let (coordinator, agent, menu, client, log) =
        makeRemoteAccessSetupCoordinatorV1()
    let offer = try remoteAccessSetupOfferV1()

    try await coordinator.begin()
    #expect(await coordinator.snapshot() == .connecting)
    #expect(log.snapshot() == ["agent.register", "client.start"])

    await coordinator.receive(.authenticatedAgent(generation: 7))
    #expect(await coordinator.snapshot() == .readingOffer(generation: 7))
    await coordinator.receive(.offer(generation: 7, offer: offer))
    #expect(
        await coordinator.snapshot()
            == .awaitingConsent(generation: 7, offer: offer)
    )
    #expect(await menu.counts() == (0, 0))

    try await coordinator.confirm()
    let command = try #require(client.snapshot().commands.first)
    #expect(command.offer == offer)
    #expect(command.consentProfile == .agentRemoteAccessV1)
    #expect(command.confirmedAtUnixMilliseconds == 2_000)
    #expect(await menu.counts() == (0, 0))

    let receipt = try remoteAccessSetupReceiptV1(command: command)
    await coordinator.receive(.enabled(generation: 7, receipt: receipt))
    #expect(await coordinator.snapshot() == .enabled(receipt))
    #expect(await agent.counts() == (1, 0))
    #expect(await menu.counts() == (1, 0))
    #expect(log.snapshot() == [
        "agent.register", "client.start", "client.read", "client.enable",
        "menu.register",
    ])
}

@Test
@available(macOS 26.0, *)
func remoteAccessSetupDeclineRemovesOnlyTheAgentRegistration() async throws {
    let (coordinator, agent, menu, client, log) =
        makeRemoteAccessSetupCoordinatorV1()
    let offer = try remoteAccessSetupOfferV1()
    try await coordinator.begin()
    await coordinator.receive(.authenticatedAgent(generation: 3))
    await coordinator.receive(.offer(generation: 3, offer: offer))

    try await coordinator.decline()

    #expect(await coordinator.snapshot() == .declined)
    #expect(await agent.counts() == (1, 1))
    #expect(await menu.counts() == (0, 0))
    #expect(client.snapshot().cancellations == 1)
    #expect(log.snapshot().suffix(2) == ["client.cancel", "agent.unregister"])
}

@Test
@available(macOS 26.0, *)
func preAuthenticationInvalidationCompensatesAgentRegistration() async throws {
    let (coordinator, agent, menu, _, _) =
        makeRemoteAccessSetupCoordinatorV1()
    try await coordinator.begin()

    await coordinator.receive(.invalidated(generation: 99))

    #expect(
        await coordinator.snapshot()
            == .failed(.transportUnavailable)
    )
    #expect(await agent.counts() == (1, 1))
    #expect(await menu.counts() == (0, 0))
}

@Test
@available(macOS 26.0, *)
func transportLossAfterEnableSendIsOutcomeUnknownAndKeepsAgent()
    async throws
{
    let (coordinator, agent, menu, client, _) =
        makeRemoteAccessSetupCoordinatorV1()
    let offer = try remoteAccessSetupOfferV1()
    try await coordinator.begin()
    await coordinator.receive(.authenticatedAgent(generation: 4))
    await coordinator.receive(.offer(generation: 4, offer: offer))
    try await coordinator.confirm()

    await coordinator.receive(.invalidated(generation: 4))

    #expect(await coordinator.snapshot() == .outcomeUnknown)
    #expect(await agent.counts() == (1, 0))
    #expect(await menu.counts() == (0, 0))
    #expect(client.snapshot().commands.count == 1)
}

@Test
@available(macOS 26.0, *)
func menuRegistrationFailureRetainsReceiptForExactRetry() async throws {
    let (coordinator, agent, menu, client, _) =
        makeRemoteAccessSetupCoordinatorV1(menuRegisterFailures: 1)
    let offer = try remoteAccessSetupOfferV1()
    try await coordinator.begin()
    await coordinator.receive(.authenticatedAgent(generation: 5))
    await coordinator.receive(.offer(generation: 5, offer: offer))
    try await coordinator.confirm()
    let command = try #require(client.snapshot().commands.first)
    let receipt = try remoteAccessSetupReceiptV1(command: command)

    await coordinator.receive(.enabled(generation: 5, receipt: receipt))
    #expect(
        await coordinator.snapshot()
            == .failed(.menuRegistrationPending(.requiresApproval))
    )
    #expect(await agent.counts() == (1, 0))
    #expect(await menu.counts() == (1, 0))

    try await coordinator.retryMenuConvergence()
    #expect(await coordinator.snapshot() == .enabled(receipt))
    #expect(await menu.counts() == (2, 0))
}

@Test
@available(macOS 26.0, *)
func invalidReceiptAfterEnableSendNeverRollsBackAgent() async throws {
    let (coordinator, agent, menu, client, _) =
        makeRemoteAccessSetupCoordinatorV1()
    let offer = try remoteAccessSetupOfferV1()
    try await coordinator.begin()
    await coordinator.receive(.authenticatedAgent(generation: 6))
    await coordinator.receive(.offer(generation: 6, offer: offer))
    try await coordinator.confirm()
    let command = try #require(client.snapshot().commands.first)
    let invalid = try LocalRemoteAccessEnabledReceiptV0(
        correlationID: UUID(),
        offerID: command.offer.offerID,
        intentRevision: 1,
        completedAtUnixMilliseconds: 2_001
    )

    await coordinator.receive(.enabled(generation: 6, receipt: invalid))

    #expect(await coordinator.snapshot() == .outcomeUnknown)
    #expect(await agent.counts() == (1, 0))
    #expect(await menu.counts() == (0, 0))
}

@Test
@available(macOS 26.0, *)
func transportStartFailureCompensatesAgentRegistration() async throws {
    let (coordinator, agent, menu, _, log) =
        makeRemoteAccessSetupCoordinatorV1(startFails: true)

    try await coordinator.begin()

    #expect(
        await coordinator.snapshot()
            == .failed(.transportUnavailable)
    )
    #expect(await agent.counts() == (1, 1))
    #expect(await menu.counts() == (0, 0))
    #expect(log.snapshot() == [
        "agent.register", "client.start", "agent.unregister",
    ])
}

@Test
@available(macOS 26.0, *)
func cleanupFailureRemainsExplicitAndCannotBeginAgain() async throws {
    let (coordinator, agent, _, _, _) =
        makeRemoteAccessSetupCoordinatorV1(
            startFails: true,
            agentUnregisterFailures: 1
        )

    try await coordinator.begin()

    #expect(
        await coordinator.snapshot()
            == .failed(.agentCleanup(.platformFailure))
    )
    #expect(await agent.counts() == (1, 1))
    await #expect(
        throws: MacRemoteAccessSetupCoordinatorErrorV1.transitionInProgress
    ) {
        try await coordinator.begin()
    }
}

private func eventuallyRemoteAccessSetupApplicationV1(
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
func setupApplicationRelaysOneOrderedTransactionAndFinishes() async throws {
    let log = RemoteAccessSetupEventLogV1()
    let agent = RemoteAccessSetupRoleV1(name: "agent", log: log)
    let menu = RemoteAccessSetupRoleV1(name: "menu", log: log)
    let box = RemoteAccessSetupClientBoxV1()
    let application = await MainActor.run {
        MacRemoteAccessSetupApplicationV1(
            agent: agent,
            menuApp: menu,
            milliseconds: { 2_000 },
            commandID: {
                UUID(
                    uuidString:
                        "20000000-0000-4000-8000-000000000002"
                )!
            },
            clientFactory: { handler in
                let client = RemoteAccessSetupClientV1(
                    log: log,
                    eventHandler: handler
                )
                box.install(client)
                return client
            }
        )
    }
    let client = try box.require()
    #expect(await application.state == .idle)
    #expect(client.snapshot().starts == 0)

    try await application.begin()
    #expect(
        await eventuallyRemoteAccessSetupApplicationV1 {
            await application.state == .connecting
        }
    )
    let offer = try remoteAccessSetupOfferV1()
    client.emit(.authenticatedAgent(generation: 12))
    client.emit(.offer(generation: 12, offer: offer))
    #expect(
        await eventuallyRemoteAccessSetupApplicationV1 {
            await application.state
                == .awaitingConsent(generation: 12, offer: offer)
        }
    )
    try await application.confirm()
    let command = try #require(client.snapshot().commands.first)
    let receipt = try remoteAccessSetupReceiptV1(command: command)
    client.emit(.enabled(generation: 12, receipt: receipt))
    #expect(
        await eventuallyRemoteAccessSetupApplicationV1 {
            await application.state == .enabled(receipt)
        }
    )

    await application.finish()
    #expect(await agent.counts() == (1, 0))
    #expect(await menu.counts() == (1, 0))
}

@Test
@available(macOS 26.0, *)
func productLaunchRoutesAbsentRegistrationToInertSetup() async throws {
    let log = RemoteAccessSetupEventLogV1()
    let agent = RemoteAccessSetupRoleV1(name: "agent", log: log)
    let menu = RemoteAccessSetupRoleV1(name: "menu", log: log)
    let clientBox = RemoteAccessSetupClientBoxV1()
    let dashboardBox = RemoteAccessSetupDashboardBoxV1()
    let registration = RemoteAccessSetupRawRegistrationV1(.notRegistered)
    let product = await MainActor.run {
        let setup = MacRemoteAccessSetupApplicationV1(
            agent: agent,
            menuApp: menu,
            clientFactory: { handler in
                let client = RemoteAccessSetupClientV1(
                    log: log,
                    eventHandler: handler
                )
                clientBox.install(client)
                return client
            }
        )
        return MacCompanionProductApplicationV1(
            agentRegistration: registration,
            setup: setup,
            dashboardFactory: { dashboardBox.makeApplication() }
        )
    }

    await product.start()

    #expect(await product.route == .setup)
    #expect(try clientBox.require().snapshot().starts == 0)
    #expect(dashboardBox.products().isEmpty)
    await product.finish()
}

@Test
@available(macOS 26.0, *)
func productLaunchUsesRegistrationOnlyToAttemptFreshDashboard() async {
    let log = RemoteAccessSetupEventLogV1()
    let agent = RemoteAccessSetupRoleV1(name: "agent", log: log)
    let menu = RemoteAccessSetupRoleV1(name: "menu", log: log)
    let dashboardBox = RemoteAccessSetupDashboardBoxV1()
    let registration = RemoteAccessSetupRawRegistrationV1(.enabled)
    let product = await MainActor.run {
        let setup = MacRemoteAccessSetupApplicationV1(
            agent: agent,
            menuApp: menu,
            clientFactory: { _ in
                RemoteAccessSetupClientV1(log: log)
            }
        )
        return MacCompanionProductApplicationV1(
            agentRegistration: registration,
            setup: setup,
            dashboardFactory: { dashboardBox.makeApplication() }
        )
    }

    await product.start()

    #expect(await product.route == .dashboard)
    #expect(dashboardBox.products().count == 1)
    #expect(dashboardBox.products().first?.snapshot().starts == 1)
    #expect(await agent.counts() == (0, 0))
    await product.finish()
}

@Test
@available(macOS 26.0, *)
func failedRegisteredDashboardAttemptFallsBackWithoutMutatingRoles()
    async
{
    let log = RemoteAccessSetupEventLogV1()
    let agent = RemoteAccessSetupRoleV1(name: "agent", log: log)
    let menu = RemoteAccessSetupRoleV1(name: "menu", log: log)
    let dashboardBox = RemoteAccessSetupDashboardBoxV1(fails: true)
    let registration = RemoteAccessSetupRawRegistrationV1(.enabled)
    let product = await MainActor.run {
        let setup = MacRemoteAccessSetupApplicationV1(
            agent: agent,
            menuApp: menu,
            clientFactory: { _ in
                RemoteAccessSetupClientV1(log: log)
            }
        )
        return MacCompanionProductApplicationV1(
            agentRegistration: registration,
            setup: setup,
            dashboardFactory: { dashboardBox.makeApplication() }
        )
    }

    await product.start()

    #expect(await product.route == .setup)
    let dashboard = dashboardBox.products().first?.snapshot()
    #expect(dashboard?.starts == 1)
    #expect(dashboard?.finishes == 1)
    #expect(await agent.counts() == (0, 0))
    #expect(await menu.counts() == (0, 0))
    await product.finish()
}

@Test
@available(macOS 26.0, *)
func exactSetupReceiptStartsOneFreshDashboard() async throws {
    let log = RemoteAccessSetupEventLogV1()
    let agent = RemoteAccessSetupRoleV1(name: "agent", log: log)
    let menu = RemoteAccessSetupRoleV1(name: "menu", log: log)
    let clientBox = RemoteAccessSetupClientBoxV1()
    let dashboardBox = RemoteAccessSetupDashboardBoxV1()
    let registration = RemoteAccessSetupRawRegistrationV1(.notRegistered)
    let product = await MainActor.run {
        let setup = MacRemoteAccessSetupApplicationV1(
            agent: agent,
            menuApp: menu,
            milliseconds: { 2_000 },
            commandID: {
                UUID(
                    uuidString:
                        "20000000-0000-4000-8000-000000000002"
                )!
            },
            clientFactory: { handler in
                let client = RemoteAccessSetupClientV1(
                    log: log,
                    eventHandler: handler
                )
                clientBox.install(client)
                return client
            }
        )
        return MacCompanionProductApplicationV1(
            agentRegistration: registration,
            setup: setup,
            dashboardFactory: { dashboardBox.makeApplication() }
        )
    }
    await product.start()
    let client = try clientBox.require()
    try await product.setup.begin()
    let offer = try remoteAccessSetupOfferV1()
    client.emit(.authenticatedAgent(generation: 21))
    client.emit(.offer(generation: 21, offer: offer))
    #expect(
        await eventuallyRemoteAccessSetupApplicationV1 {
            await product.setup.state
                == .awaitingConsent(generation: 21, offer: offer)
        }
    )
    try await product.setup.confirm()
    let command = try #require(client.snapshot().commands.first)
    let receipt = try remoteAccessSetupReceiptV1(command: command)

    client.emit(.enabled(generation: 21, receipt: receipt))

    #expect(
        await eventuallyRemoteAccessSetupApplicationV1 {
            await product.route == .dashboard
                && dashboardBox.products().first?.snapshot().starts == 1
        }
    )
    #expect(dashboardBox.products().count == 1)
    #expect(await agent.counts() == (1, 0))
    #expect(await menu.counts() == (1, 0))
    await product.finish()
}

@Test
@available(macOS 26.0, *)
func preexistingAgentIsRetainedWhenBootstrapOutcomeIsUnknown() async throws {
    let (coordinator, agent, menu, _, _) =
        makeRemoteAccessSetupCoordinatorV1(
            startFails: true,
            agentAcquisition: .alreadyRegistered
        )

    try await coordinator.begin()

    #expect(await coordinator.snapshot() == .outcomeUnknown)
    #expect(await agent.counts() == (1, 0))
    #expect(await menu.counts() == (0, 0))
}

@Test
@available(macOS 26.0, *)
func explicitDeclineCanRemoveAProvenDisabledPreexistingAgent() async throws {
    let (coordinator, agent, menu, _, _) =
        makeRemoteAccessSetupCoordinatorV1(
            agentAcquisition: .alreadyRegistered
        )
    let offer = try remoteAccessSetupOfferV1()
    try await coordinator.begin()
    await coordinator.receive(.authenticatedAgent(generation: 17))
    await coordinator.receive(.offer(generation: 17, offer: offer))

    try await coordinator.decline()

    #expect(await coordinator.snapshot() == .declined)
    #expect(await agent.counts() == (1, 1))
    #expect(await menu.counts() == (0, 0))
}
#endif
