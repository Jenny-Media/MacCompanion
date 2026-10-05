@testable import CompanionAgentNetworkPlatform
@testable import CompanionAgent
import CompanionDomain
import CompanionDiscovery
import CompanionIPC
import CompanionLifecycle
import CompanionPairing
import CompanionPersistence
@testable import CompanionNetworkPlatform
import CompanionSecurity
import CompanionTransport
import CompanionWire
import CryptoKit
import Dispatch
import Foundation
import Network
import Testing

private enum AgentNetworkListenerServiceTestErrorV1: Error {
    case startFailed
    case statusPublicationFailed
}

private actor AgentNetworkPairingCommitterV1: PairingCommitter {
    func commitPairing(
        pairingID: UUID,
        record: StoredDeviceRecord,
        displayName: DeviceDisplayName
    ) async throws {}
}

private func agentNetworkPairingContextV1() throws
    -> AgentLocalPairingContextV0
{
    try AgentLocalPairingContextV0(
        hostFingerprint: Data(0x40...0x5f),
        endpoints: [
            try EndpointCandidate(
                kind: .bonjour,
                value: "studio._maccompanion._tcp.local.",
                port: 47_474
            ),
        ]
    )
}

private final class AgentNetworkListenerFakeV1:
    AgentNetworkListenerStartingV1,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let failsStart: Bool
    private var acceptedHandler: (@Sendable (
        NetworkHostAcceptedConnectionV0
    ) -> Void)?
    private var readyHandler: (@Sendable () -> Void)?
    private var advertisementHandler: (@Sendable (Bool) -> Void)?
    private var terminalHandler: (@Sendable (
        NetworkHostListenerTerminationReasonV0
    ) -> Void)?
    private var starts = 0
    private var cancels = 0

    init(failsStart: Bool = false) {
        self.failsStart = failsStart
    }

    var startCount: Int { lock.withLock { starts } }
    var cancelCount: Int { lock.withLock { cancels } }

    func start(
        queue: DispatchQueue,
        ready: @escaping @Sendable () -> Void,
        advertisementChanged: @escaping @Sendable (Bool) -> Void,
        accepted: @escaping @Sendable (
            NetworkHostAcceptedConnectionV0
        ) -> Void,
        terminal: @escaping @Sendable (
            NetworkHostListenerTerminationReasonV0
        ) -> Void
    ) throws {
        lock.withLock {
            starts += 1
            readyHandler = ready
            advertisementHandler = advertisementChanged
            acceptedHandler = accepted
            terminalHandler = terminal
        }
        if failsStart { throw AgentNetworkListenerServiceTestErrorV1.startFailed }
    }

    func cancel() {
        lock.withLock { cancels += 1 }
    }

    func emitAccepted(_ accepted: NetworkHostAcceptedConnectionV0) {
        lock.withLock { acceptedHandler }?(accepted)
    }

    func emitReady() {
        lock.withLock { readyHandler }?()
    }

    func emitAdvertisement(_ ready: Bool) {
        lock.withLock { advertisementHandler }?(ready)
    }

    func emitTerminal(_ reason: NetworkHostListenerTerminationReasonV0) {
        lock.withLock { terminalHandler }?(reason)
    }
}

private final class AgentNetworkAcceptedIOFakeV1:
    NetworkHostAcceptedConnectionIOV0,
    @unchecked Sendable
{
    let connection = NWConnection(host: "127.0.0.1", port: 9, using: .tcp)
    private let lock = NSLock()
    private var stateHandler: (@Sendable (
        NetworkHostAcceptedConnectionIOStateV0
    ) -> Void)?
    private var starts = 0
    private var cancels = 0

    var startCount: Int { lock.withLock { starts } }
    var cancelCount: Int { lock.withLock { cancels } }

    func setStateUpdateHandler(
        _ handler: @escaping @Sendable (
            NetworkHostAcceptedConnectionIOStateV0
        ) -> Void
    ) {
        lock.withLock { stateHandler = handler }
    }

    func start(queue: DispatchQueue) {
        lock.withLock { starts += 1 }
    }

    func cancel() {
        lock.withLock { cancels += 1 }
    }

    func emit(_ state: NetworkHostAcceptedConnectionIOStateV0) {
        lock.withLock { stateHandler }?(state)
    }
}

private final class AgentNetworkServiceBoundFakeV1:
    AgentNetworkBoundPrimaryConnectionV1,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var begins = 0
    private var cancels = 0

    var beginCount: Int { lock.withLock { begins } }
    var cancelCount: Int { lock.withLock { cancels } }

    func begin() async throws {
        lock.withLock { begins += 1 }
    }

    func cancel() async {
        lock.withLock { cancels += 1 }
    }
}

private actor AgentNetworkServiceBinderFakeV1:
    AgentNetworkPrimaryConnectionBindingV1
{
    private let bound: AgentNetworkServiceBoundFakeV1
    private var acceptedTimes: [UInt64] = []

    init(bound: AgentNetworkServiceBoundFakeV1) {
        self.bound = bound
    }

    func bindPrimaryConnection(
        verifiedReadyConnection: NetworkHostVerifiedReadyConnectionV0,
        acceptedAtMonotonicMilliseconds: UInt64,
        context: @escaping @Sendable () -> NetworkHostRequestContextV0,
        terminal: @escaping @Sendable (
            NetworkHostPrimaryTerminationReasonV0
        ) -> Void
    ) async throws -> any AgentNetworkBoundPrimaryConnectionV1 {
        acceptedTimes.append(acceptedAtMonotonicMilliseconds)
        verifiedReadyConnection.cancel()
        return bound
    }

    func recordedAcceptedTimes() -> [UInt64] { acceptedTimes }
}

private actor AgentNetworkServiceSuspendedInstallHandoffV1:
    AgentNetworkListenerHandoffServingV1
{
    private var installEntered = false
    private var cancelled = false
    private var installWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func installStateChanged(
        _: @escaping @Sendable (UInt64) -> Void
    ) async {
        installEntered = true
        let waiters = installWaiters
        installWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilInstallEntered() async {
        guard !installEntered else { return }
        await withCheckedContinuation { installWaiters.append($0) }
    }

    func releaseInstall() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }

    func admitForService(
        _: any AgentNetworkAcceptedConnectionStartingV1,
        acceptedAtMonotonicMilliseconds _: UInt64
    ) async throws {
        throw AgentNetworkListenerServiceTestErrorV1.startFailed
    }

    func cancelForService() { cancelled = true }

    func snapshotForService() -> AgentNetworkListenerHandoffSnapshotV1 {
        AgentNetworkListenerHandoffSnapshotV1(
            isCancelled: cancelled,
            hasPendingTLS: false,
            isBinding: false,
            hasActivePrimary: false
        )
    }
}

private final class AgentNetworkServiceRecorderV1: @unchecked Sendable {
    private let lock = NSLock()
    private var terminals: [NetworkHostListenerTerminationReasonV0] = []
    private var failures: [AgentNetworkListenerAdmissionFailureV1] = []

    var terminalReasons: [NetworkHostListenerTerminationReasonV0] {
        lock.withLock { terminals }
    }
    var admissionFailures: [AgentNetworkListenerAdmissionFailureV1] {
        lock.withLock { failures }
    }

    func recordTerminal(_ reason: NetworkHostListenerTerminationReasonV0) {
        lock.withLock { terminals.append(reason) }
    }

    func recordFailure(_ failure: AgentNetworkListenerAdmissionFailureV1) {
        lock.withLock { failures.append(failure) }
    }
}

private actor AgentNetworkServiceStatusRecorderV1 {
    private let failsPublication: Bool
    private var values: [(AgentNetworkListenerDiagnosticsV1, UInt64)] = []

    init(failsPublication: Bool = false) {
        self.failsPublication = failsPublication
    }

    func publish(
        _ diagnostics: AgentNetworkListenerDiagnosticsV1,
        generation: UInt64
    ) throws {
        if failsPublication {
            throw AgentNetworkListenerServiceTestErrorV1
                .statusPublicationFailed
        }
        values.append((diagnostics, generation))
    }

    func diagnostics() -> [AgentNetworkListenerDiagnosticsV1] {
        values.map(\.0)
    }

    func generations() -> [UInt64] { values.map(\.1) }
}

private actor AgentNetworkServiceLANRecorderV1 {
    private let failsPublication: Bool
    private var values: [(Bool, UInt64)] = []

    init(failsPublication: Bool = false) {
        self.failsPublication = failsPublication
    }

    func publish(ready: Bool, generation: UInt64) throws {
        if failsPublication {
            throw AgentNetworkListenerServiceTestErrorV1
                .statusPublicationFailed
        }
        values.append((ready, generation))
    }

    func readiness() -> [Bool] { values.map(\.0) }
    func generations() -> [UInt64] { values.map(\.1) }
}

private func agentNetworkServiceAcceptedV1() throws
    -> (NetworkHostAcceptedConnectionV0, AgentNetworkAcceptedIOFakeV1)
{
    let key = P256.Signing.PrivateKey()
    let spki = try CompanionSecurityV0.p256SubjectPublicKeyInfoDER(
        publicKeyX963: key.publicKey.x963Representation
    )
    let fingerprint = try CompanionSecurityV0.hostFingerprint(
        subjectPublicKeyInfoDER: spki
    )
    let io = AgentNetworkAcceptedIOFakeV1()
    return (
        NetworkHostAcceptedConnectionV0(
            io: io,
            servedSubjectPublicKeyInfoDER: spki,
            requiredHostFingerprint: fingerprint,
            metadataEvaluator: { _ in
                NetworkHostTLSMetadataFactsV0(
                    negotiatedTLSMajor: 1,
                    negotiatedTLSMinor: 3,
                    earlyDataAccepted: false
                )
            }
        ),
        io
    )
}

private func agentNetworkServiceContextV1() -> NetworkHostRequestContextV0 {
    NetworkHostRequestContextV0(
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 1,
        monotonicNowMilliseconds: 1,
        responseMessageID: WireUUID(UUID())
    )
}

private func agentNetworkServiceEventuallyV1(
    _ condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))
    repeat {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(1))
    } while clock.now < deadline
    return await condition()
}

private func agentNetworkServiceHarnessV1(
    listener: AgentNetworkListenerFakeV1,
    recorder: AgentNetworkServiceRecorderV1 = AgentNetworkServiceRecorderV1(),
    acceptedAt: UInt64 = 42,
    statusRecorder: AgentNetworkServiceStatusRecorderV1? = nil,
    lanRecorder: AgentNetworkServiceLANRecorderV1? = nil,
    advertisementRecorder: AgentNetworkServiceLANRecorderV1? = nil,
    lanEvidence: AgentLocalLANRouteEvidenceAuthorityV1? = nil,
    pairingContext: AgentNetworkPairingContextAuthorityV0? = nil,
    pairingSessions: AgentLocalPairingSessionHandlerV0? = nil
) -> (
    AgentNetworkListenerServiceV1,
    AgentNetworkListenerHandoffV1,
    AgentNetworkServiceBinderFakeV1,
    AgentNetworkServiceBoundFakeV1,
    AgentNetworkServiceRecorderV1,
    AgentNetworkServiceStatusRecorderV1?
) {
    let bound = AgentNetworkServiceBoundFakeV1()
    let binder = AgentNetworkServiceBinderFakeV1(bound: bound)
    let queue = DispatchQueue(label: "MacCompanionTests.ListenerService")
    let handoff = AgentNetworkListenerHandoffV1(
        binder: binder,
        queue: queue,
        context: agentNetworkServiceContextV1
    )
    let statusPublisher: (@Sendable (
        AgentNetworkListenerDiagnosticsV1,
        UInt64
    ) async throws -> Void)?
    if let statusRecorder {
        statusPublisher = { diagnostics, generation in
            try await statusRecorder.publish(
                diagnostics,
                generation: generation
            )
        }
    } else {
        statusPublisher = nil
    }
    let listenerRoutePublisher: (@Sendable (
        Bool,
        UInt64
    ) async throws -> Void)?
    if let lanEvidence {
        listenerRoutePublisher = { ready, generation in
            try await lanEvidence.publishListenerReadiness(
                ready: ready,
                generation: generation
            )
        }
    } else if let lanRecorder {
        listenerRoutePublisher = { ready, generation in
            try await lanRecorder.publish(
                ready: ready,
                generation: generation
            )
        }
    } else {
        listenerRoutePublisher = nil
    }
    let advertisementRoutePublisher: (@Sendable (
        Bool,
        UInt64
    ) async throws -> Void)?
    if let lanEvidence {
        advertisementRoutePublisher = { ready, generation in
            try await lanEvidence.publishAdvertisementReadiness(
                ready: ready,
                generation: generation
            )
        }
    } else if let advertisementRecorder {
        advertisementRoutePublisher = { ready, generation in
            try await advertisementRecorder.publish(
                ready: ready,
                generation: generation
            )
        }
    } else {
        advertisementRoutePublisher = nil
    }
    let pairingListenerPublisher: (@Sendable (
        Bool,
        UInt64
    ) async throws -> Void)?
    let pairingAdvertisementPublisher: (@Sendable (
        Bool,
        UInt64
    ) async throws -> Void)?
    let pairingContextStop: (@Sendable () async -> Void)?
    if let source = pairingContext {
        pairingListenerPublisher = { ready, generation in
            try await source.publishListenerReadiness(
                ready: ready,
                generation: generation
            )
        }
        pairingAdvertisementPublisher = { ready, generation in
            try await source.publishAdvertisementReadiness(
                ready: ready,
                generation: generation
            )
        }
        pairingContextStop = { await source.stop() }
    } else {
        pairingListenerPublisher = nil
        pairingAdvertisementPublisher = nil
        pairingContextStop = nil
    }
    let pairingSessionInvalidator: (@Sendable (
        Bool
    ) async throws -> Void)?
    if let handler = pairingSessions {
        pairingSessionInvalidator = { terminal in
            try await handler.invalidateForNetworkLoss(
                monotonicNowMilliseconds: acceptedAt,
                terminal: terminal
            )
        }
    } else {
        pairingSessionInvalidator = nil
    }
    let service = AgentNetworkListenerServiceV1(
        listener: listener,
        handoff: handoff,
        queue: queue,
        monotonicNowMilliseconds: { acceptedAt },
        listenerTerminal: recorder.recordTerminal,
        admissionFailure: recorder.recordFailure,
        statusPublisher: statusPublisher,
        listenerRoutePublisher: listenerRoutePublisher,
        advertisementRoutePublisher: advertisementRoutePublisher,
        pairingListenerPublisher: pairingListenerPublisher,
        pairingAdvertisementPublisher: pairingAdvertisementPublisher,
        pairingContextStop: pairingContextStop,
        pairingSessionInvalidator: pairingSessionInvalidator
    )
    return (
        service,
        handoff,
        binder,
        bound,
        recorder,
        statusRecorder
    )
}

@Test func listenerCancellationDuringHandoffInstallCannotStartNativeListener()
    async
{
    let listener = AgentNetworkListenerFakeV1()
    let handoff = AgentNetworkServiceSuspendedInstallHandoffV1()
    let recorder = AgentNetworkServiceRecorderV1()
    let service = AgentNetworkListenerServiceV1(
        listener: listener,
        handoff: handoff,
        queue: DispatchQueue(
            label: "MacCompanionTests.ListenerService.StartCancellation"
        ),
        monotonicNowMilliseconds: { 42 },
        listenerTerminal: recorder.recordTerminal,
        admissionFailure: recorder.recordFailure
    )
    let start = Task { try await service.start() }
    await handoff.waitUntilInstallEntered()
    #expect((await service.snapshot()).state == .starting)

    await service.cancel()
    #expect(listener.startCount == 0)
    #expect(listener.cancelCount == 1)
    #expect((await service.snapshot()).state == .terminal)

    await handoff.releaseInstall()
    await #expect(throws: CancellationError.self) {
        try await start.value
    }
    #expect(listener.startCount == 0)
    #expect(listener.cancelCount == 1)
    #expect((await service.snapshot()).state == .terminal)
    #expect((await service.snapshot()).handoff.isCancelled)
    #expect(recorder.terminalReasons == [.localCancel])
}

@Test func listenerServiceOwnsStartAcceptanceTimestampAndHandoff() async throws {
    let listener = AgentNetworkListenerFakeV1()
    let harness = agentNetworkServiceHarnessV1(listener: listener)
    try await harness.0.start()
    #expect((await harness.0.snapshot()).state == .starting)
    await #expect(throws: AgentNetworkListenerServiceErrorV1.alreadyStarted) {
        try await harness.0.start()
    }
    listener.emitReady()
    let accepted = try agentNetworkServiceAcceptedV1()

    listener.emitAccepted(accepted.0)
    #expect(await agentNetworkServiceEventuallyV1 {
        accepted.1.startCount == 1
    })
    accepted.1.emit(.ready)

    #expect(await agentNetworkServiceEventuallyV1 {
        harness.3.beginCount == 1
    })
    #expect(await harness.2.recordedAcceptedTimes() == [42])
    #expect((await harness.0.snapshot()).state == .listening)
    #expect((await harness.0.snapshot()).handoff.hasActivePrimary)
}

@Test func listenerServiceLossRetiresTheActiveHandoffBeforeReporting() async throws {
    let listener = AgentNetworkListenerFakeV1()
    let harness = agentNetworkServiceHarnessV1(listener: listener)
    try await harness.0.start()
    listener.emitReady()
    #expect(await agentNetworkServiceEventuallyV1 {
        (await harness.0.snapshot()).state == .listening
    })
    let accepted = try agentNetworkServiceAcceptedV1()
    listener.emitAccepted(accepted.0)
    #expect(await agentNetworkServiceEventuallyV1 { accepted.1.startCount == 1 })
    accepted.1.emit(.ready)
    #expect(await agentNetworkServiceEventuallyV1 { harness.3.beginCount == 1 })

    listener.emitTerminal(.listenerFailed)

    #expect(await agentNetworkServiceEventuallyV1 {
        harness.4.terminalReasons == [.listenerFailed]
    })
    #expect(harness.3.cancelCount == 1)
    #expect((await harness.0.snapshot()).state == .terminal)
    #expect((await harness.0.snapshot()).handoff.isCancelled)
}

@Test func listenerServiceCancellationIsIdempotentAndRetiresPendingTLS() async throws {
    let listener = AgentNetworkListenerFakeV1()
    let harness = agentNetworkServiceHarnessV1(listener: listener)
    try await harness.0.start()
    listener.emitReady()
    #expect(await agentNetworkServiceEventuallyV1 {
        (await harness.0.snapshot()).state == .listening
    })
    let accepted = try agentNetworkServiceAcceptedV1()
    listener.emitAccepted(accepted.0)
    #expect(await agentNetworkServiceEventuallyV1 { accepted.1.startCount == 1 })

    await harness.0.cancel()
    await harness.0.cancel()

    #expect(listener.cancelCount == 1)
    #expect(accepted.1.cancelCount == 1)
    #expect(harness.4.terminalReasons == [.localCancel])
    #expect((await harness.0.snapshot()).handoff.isCancelled)
}

@Test func listenerServiceStartFailureFailsClosedAgainstLateAcceptance() async throws {
    let listener = AgentNetworkListenerFakeV1(failsStart: true)
    let harness = agentNetworkServiceHarnessV1(listener: listener)

    await #expect(throws: AgentNetworkListenerServiceTestErrorV1.startFailed) {
        try await harness.0.start()
    }
    #expect(listener.cancelCount == 1)
    #expect((await harness.0.snapshot()).state == .terminal)
    #expect((await harness.0.snapshot()).handoff.isCancelled)

    let late = try agentNetworkServiceAcceptedV1()
    listener.emitAccepted(late.0)
    #expect(await agentNetworkServiceEventuallyV1 { late.1.cancelCount == 1 })
    #expect(late.1.startCount == 0)
}

@Test func listenerServiceReportsOnlySanitizedAcceptedStartFailure() async throws {
    let listener = AgentNetworkListenerFakeV1()
    let harness = agentNetworkServiceHarnessV1(listener: listener)
    try await harness.0.start()
    listener.emitReady()
    #expect(await agentNetworkServiceEventuallyV1 {
        (await harness.0.snapshot()).state == .listening
    })
    let accepted = try agentNetworkServiceAcceptedV1()
    try accepted.0.start(
        queue: DispatchQueue(label: "MacCompanionTests.ListenerServicePrestart"),
        ready: { _ in },
        terminal: { _ in }
    )

    listener.emitAccepted(accepted.0)

    #expect(await agentNetworkServiceEventuallyV1 {
        harness.4.admissionFailures == [.acceptedConnectionStartFailed]
    })
    #expect(accepted.1.cancelCount == 1)
    #expect((await harness.0.snapshot()).state == .listening)
    #expect(!(await harness.0.snapshot()).handoff.hasPendingTLS)
}

@Test func listenerServicePublishesLifecycleAndHandoffFacts() async throws {
    let listener = AgentNetworkListenerFakeV1()
    let statuses = AgentNetworkServiceStatusRecorderV1()
    let harness = agentNetworkServiceHarnessV1(
        listener: listener,
        statusRecorder: statuses
    )

    try await harness.0.start()
    #expect((await statuses.diagnostics()).last?.networkState == .starting)
    listener.emitReady()
    #expect(await agentNetworkServiceEventuallyV1 {
        (await statuses.diagnostics()).contains {
            $0.networkState == .listening
                && $0.activeRemoteSessionCount == 0
        }
    })

    let accepted = try agentNetworkServiceAcceptedV1()
    listener.emitAccepted(accepted.0)
    #expect(await agentNetworkServiceEventuallyV1 { accepted.1.startCount == 1 })
    accepted.1.emit(.ready)
    #expect(await agentNetworkServiceEventuallyV1 {
        (await statuses.diagnostics()).contains {
            $0.networkState == .listening
                && $0.activeRemoteSessionCount == 1
        }
    })

    await harness.0.cancel()
    #expect((await statuses.diagnostics()).last == AgentNetworkListenerDiagnosticsV1(
        networkState: .stopped,
        activeRemoteSessionCount: 0,
        warningCodes: []
    ))
    let generations = await statuses.generations()
    #expect(generations == generations.sorted())
    #expect(Set(generations).count == generations.count)
}

@Test func listenerStatusFailureCannotGrantIngressOrPreventTeardown() async throws {
    let listener = AgentNetworkListenerFakeV1()
    let statuses = AgentNetworkServiceStatusRecorderV1(
        failsPublication: true
    )
    let harness = agentNetworkServiceHarnessV1(
        listener: listener,
        statusRecorder: statuses
    )

    try await harness.0.start()
    #expect(harness.4.admissionFailures == [.statusPublicationFailed])
    listener.emitReady()
    #expect(await agentNetworkServiceEventuallyV1 {
        (await harness.0.snapshot()).state == .listening
    })
    let accepted = try agentNetworkServiceAcceptedV1()
    listener.emitAccepted(accepted.0)
    #expect(await agentNetworkServiceEventuallyV1 { accepted.1.startCount == 1 })
    accepted.1.emit(.ready)
    #expect(await agentNetworkServiceEventuallyV1 { harness.3.beginCount == 1 })

    await harness.0.cancel()
    #expect(listener.cancelCount == 1)
    #expect(harness.3.cancelCount == 1)
    #expect((await harness.0.snapshot()).state == .terminal)
    #expect((await harness.0.snapshot()).handoff.isCancelled)
    #expect(harness.4.admissionFailures.allSatisfy {
        $0 == .statusPublicationFailed
    })
}

@Test func listenerPublishesOnlyExactReadyAndTerminalLANEvidence() async throws {
    let listener = AgentNetworkListenerFakeV1()
    let lan = AgentNetworkServiceLANRecorderV1()
    let harness = agentNetworkServiceHarnessV1(
        listener: listener,
        lanRecorder: lan
    )

    try await harness.0.start()
    #expect((await lan.readiness()).isEmpty)
    listener.emitReady()
    #expect(await agentNetworkServiceEventuallyV1 {
        await lan.readiness() == [true]
    })
    listener.emitTerminal(.listenerFailed)
    #expect(await agentNetworkServiceEventuallyV1 {
        await lan.readiness() == [true, false]
    })
    #expect(await lan.generations() == [1, 2])
}

@Test func listenerPublishesDistinctBonjourRegistrationEvidence() async throws {
    let listener = AgentNetworkListenerFakeV1()
    let advertisement = AgentNetworkServiceLANRecorderV1()
    let harness = agentNetworkServiceHarnessV1(
        listener: listener,
        advertisementRecorder: advertisement
    )

    try await harness.0.start()
    listener.emitAdvertisement(true)
    #expect(await agentNetworkServiceEventuallyV1 {
        await advertisement.readiness() == [true]
    })
    listener.emitAdvertisement(false)
    #expect(await agentNetworkServiceEventuallyV1 {
        await advertisement.readiness() == [true, false]
    })
    #expect(await advertisement.generations() == [1, 2])
}

@Test func exactListenerAndBonjourCallbacksPublishLANOnlyTogether() async throws {
    let status = try AgentLocalStatusAuthorityV1(
        lifecycle: ProductLifecycleState(
            desiredEnabled: true,
            consoleSession: .active,
            agent: .ready,
            menuApp: .ready
        ),
        networkState: .stopped,
        securityPosture: .nominal,
        routeKinds: [],
        pairedDeviceCount: 0,
        activeRemoteSessionCount: 0,
        providerCount: 0
    )
    let routes = AgentLocalRouteMonitorAuthorityV1(localStatus: status)
    let lan = AgentLocalLANRouteEvidenceAuthorityV1(
        routes: routes,
        monotonicNowMilliseconds: { 100 }
    )
    let listener = AgentNetworkListenerFakeV1()
    let harness = agentNetworkServiceHarnessV1(
        listener: listener,
        lanEvidence: lan
    )

    try await harness.0.start()
    listener.emitReady()
    #expect(await agentNetworkServiceEventuallyV1 {
        (await lan.snapshot()).listenerReady
    })
    var local = try await status.snapshot(generatedAtUnixMilliseconds: 1)
    #expect(local.routeKinds.isEmpty)

    listener.emitAdvertisement(true)
    #expect(await agentNetworkServiceEventuallyV1 {
        (await lan.snapshot()).lanPublished
    })
    local = try await status.snapshot(generatedAtUnixMilliseconds: 2)
    #expect(local.routeKinds == [.lan])

    listener.emitAdvertisement(false)
    #expect(await agentNetworkServiceEventuallyV1 {
        !(await lan.snapshot()).lanPublished
    })
    local = try await status.snapshot(generatedAtUnixMilliseconds: 3)
    #expect(local.routeKinds.isEmpty)
}

@Test func listenerLifecycleOwnsPairingAvailabilityAndActiveQRInvalidation() async throws {
    let listener = AgentNetworkListenerFakeV1()
    let context = AgentNetworkPairingContextAuthorityV0(
        context: try agentNetworkPairingContextV1()
    )
    let pairingAuthority = PairingSessionAuthority(
        committer: AgentNetworkPairingCommitterV1()
    )
    let pairingHandler = AgentLocalPairingSessionHandlerV0(
        authority: pairingAuthority,
        contextSource: context,
        timeSource: StaticAgentLocalPairingTimeSourceV0(
            try AgentLocalPairingTimeSampleV0(
                wallNowUnixMilliseconds: 1_787_198_400_000,
                monotonicNowMilliseconds: 100
            )
        )
    )
    let harness = agentNetworkServiceHarnessV1(
        listener: listener,
        acceptedAt: 101,
        pairingContext: context,
        pairingSessions: pairingHandler
    )

    await #expect(throws: AgentLocalPairingSessionErrorV0.invalidContext) {
        _ = try await pairingHandler.create(
            LocalPairingSessionCreateCommandV0(commandID: UUID())
        )
    }
    try await harness.0.start()
    listener.emitReady()
    #expect(await agentNetworkServiceEventuallyV1 {
        (await context.snapshot()).listenerReady
    })
    await #expect(throws: AgentLocalPairingSessionErrorV0.invalidContext) {
        _ = try await pairingHandler.create(
            LocalPairingSessionCreateCommandV0(commandID: UUID())
        )
    }

    listener.emitAdvertisement(true)
    #expect(await agentNetworkServiceEventuallyV1 {
        (await context.snapshot()).pairingAvailable
    })
    let firstCommand = try LocalPairingSessionCreateCommandV0(
        commandID: UUID()
    )
    let first = try await pairingHandler.create(firstCommand)

    listener.emitAdvertisement(false)
    #expect(await agentNetworkServiceEventuallyV1 {
        do {
            _ = try await pairingHandler.create(firstCommand)
            return false
        } catch AgentLocalPairingSessionErrorV0.staleCommand {
            return true
        } catch {
            return false
        }
    })
    await #expect(throws: PairingSessionError.alreadyConsumed) {
        _ = try await pairingAuthority.begin(
            pairingID: first.pairingID,
            clientID: UUID(),
            sessionPublicKeyX963: Data(),
            approvalPublicKeyX963: Data(),
            clientNonce: Data(),
            monotonicNowMilliseconds: 102
        )
    }

    listener.emitAdvertisement(true)
    #expect(await agentNetworkServiceEventuallyV1 {
        (await context.snapshot()).pairingAvailable
    })
    let replacement = try await pairingHandler.create(
        LocalPairingSessionCreateCommandV0(commandID: UUID())
    )
    await harness.0.cancel()
    #expect((await context.snapshot()).terminal)
    await #expect(throws: AgentLocalPairingSessionErrorV0.invalidContext) {
        _ = try await pairingHandler.create(
            LocalPairingSessionCreateCommandV0(commandID: UUID())
        )
    }
    await #expect(throws: PairingSessionError.alreadyConsumed) {
        _ = try await pairingAuthority.begin(
            pairingID: replacement.pairingID,
            clientID: UUID(),
            sessionPublicKeyX963: Data(),
            approvalPublicKeyX963: Data(),
            clientNonce: Data(),
            monotonicNowMilliseconds: 102
        )
    }
}

@Test func listenerRoutePublicationFailureCannotChangeTransportOwnership() async throws {
    let listener = AgentNetworkListenerFakeV1()
    let lan = AgentNetworkServiceLANRecorderV1(failsPublication: true)
    let harness = agentNetworkServiceHarnessV1(
        listener: listener,
        lanRecorder: lan
    )

    try await harness.0.start()
    listener.emitReady()
    #expect(await agentNetworkServiceEventuallyV1 {
        harness.4.admissionFailures == [.routePublicationFailed]
    })
    let accepted = try agentNetworkServiceAcceptedV1()
    listener.emitAccepted(accepted.0)
    #expect(await agentNetworkServiceEventuallyV1 { accepted.1.startCount == 1 })
    accepted.1.emit(.ready)
    #expect(await agentNetworkServiceEventuallyV1 { harness.3.beginCount == 1 })

    await harness.0.cancel()
    #expect(listener.cancelCount == 1)
    #expect(harness.3.cancelCount == 1)
    #expect(harness.4.admissionFailures == [
        .routePublicationFailed,
        .routePublicationFailed,
    ])
}

@Test func listenerDiagnosticProjectionKeepsLifecycleStatesContentFree() {
    let emptyHandoff = AgentNetworkListenerHandoffSnapshotV1(
        isCancelled: false,
        hasPendingTLS: false,
        isBinding: false,
        hasActivePrimary: false
    )
    let idle = AgentNetworkListenerDiagnosticProjectionV1.project(
        AgentNetworkListenerServiceSnapshotV1(
            state: .idle,
            handoff: emptyHandoff,
            lastListenerTerminationReason: nil,
            hasAcceptedConnectionStartFailure: false
        )
    )
    let starting = AgentNetworkListenerDiagnosticProjectionV1.project(
        AgentNetworkListenerServiceSnapshotV1(
            state: .starting,
            handoff: emptyHandoff,
            lastListenerTerminationReason: nil,
            hasAcceptedConnectionStartFailure: false
        )
    )
    let listening = AgentNetworkListenerDiagnosticProjectionV1.project(
        AgentNetworkListenerServiceSnapshotV1(
            state: .listening,
            handoff: emptyHandoff,
            lastListenerTerminationReason: nil,
            hasAcceptedConnectionStartFailure: false
        )
    )
    let stopped = AgentNetworkListenerDiagnosticProjectionV1.project(
        AgentNetworkListenerServiceSnapshotV1(
            state: .terminal,
            handoff: AgentNetworkListenerHandoffSnapshotV1(
                isCancelled: true,
                hasPendingTLS: false,
                isBinding: false,
                hasActivePrimary: false
            ),
            lastListenerTerminationReason: .localCancel,
            hasAcceptedConnectionStartFailure: false
        )
    )

    #expect(idle.networkState == .stopped)
    #expect(starting.networkState == .starting)
    #expect(listening.networkState == .listening)
    #expect(stopped.networkState == .stopped)
    #expect(idle.warningCodes.isEmpty)
    #expect(starting.warningCodes.isEmpty)
    #expect(listening.warningCodes.isEmpty)
    #expect(stopped.warningCodes.isEmpty)
}

@Test func listenerDiagnosticProjectionUsesOnlyClosedDegradedFactsAndCount() {
    let active = AgentNetworkListenerDiagnosticProjectionV1.project(
        AgentNetworkListenerServiceSnapshotV1(
            state: .listening,
            handoff: AgentNetworkListenerHandoffSnapshotV1(
                isCancelled: false,
                hasPendingTLS: false,
                isBinding: false,
                hasActivePrimary: true
            ),
            lastListenerTerminationReason: nil,
            hasAcceptedConnectionStartFailure: true
        )
    )
    let degraded = AgentNetworkListenerDiagnosticProjectionV1.project(
        AgentNetworkListenerServiceSnapshotV1(
            state: .terminal,
            handoff: AgentNetworkListenerHandoffSnapshotV1(
                isCancelled: true,
                hasPendingTLS: false,
                isBinding: false,
                hasActivePrimary: false
            ),
            lastListenerTerminationReason: .listenerFailed,
            hasAcceptedConnectionStartFailure: false
        )
    )

    #expect(active.networkState == .listening)
    #expect(active.activeRemoteSessionCount == 1)
    #expect(active.warningCodes == [.routeUnavailable])
    #expect(degraded.networkState == .degraded)
    #expect(degraded.activeRemoteSessionCount == 0)
    #expect(degraded.warningCodes == [.routeUnavailable])
}

@Test func listenerUpdateAdmissionClosesDrainsAndReopensWithoutTerminalTeardown()
    async throws
{
    let listener = AgentNetworkListenerFakeV1()
    let listenerRoutes = AgentNetworkServiceLANRecorderV1()
    let advertisementRoutes = AgentNetworkServiceLANRecorderV1()
    let harness = agentNetworkServiceHarnessV1(
        listener: listener,
        lanRecorder: listenerRoutes,
        advertisementRecorder: advertisementRoutes
    )
    try await harness.0.start()
    listener.emitReady()
    listener.emitAdvertisement(true)
    #expect(await agentNetworkServiceEventuallyV1 {
        let admission = await harness.0.snapshot().updateAdmissionState
        let listenerReady = await listenerRoutes.readiness()
        let advertisementReady = await advertisementRoutes.readiness()
        return admission == .open
            && listenerReady == [true]
            && advertisementReady == [true]
    })

    let active = try agentNetworkServiceAcceptedV1()
    listener.emitAccepted(active.0)
    #expect(await agentNetworkServiceEventuallyV1 { active.1.startCount == 1 })
    active.1.emit(.ready)
    #expect(await agentNetworkServiceEventuallyV1 { harness.3.beginCount == 1 })

    try await harness.0.closeNetworkAdmission()
    let closed = await harness.0.snapshot()
    #expect(closed.state == .listening)
    #expect(closed.updateAdmissionState == .closed)
    #expect(closed.handoff.hasActivePrimary)
    #expect(listener.cancelCount == 0)

    let rejected = try agentNetworkServiceAcceptedV1()
    listener.emitAccepted(rejected.0)
    #expect(await agentNetworkServiceEventuallyV1 {
        rejected.1.cancelCount == 1
    })
    #expect(rejected.1.startCount == 0)

    try await harness.0.drainNetworkConnections()
    #expect(harness.3.cancelCount == 1)
    #expect((await harness.0.snapshot()).updateAdmissionState == .drained)
    #expect(!(await harness.0.snapshot()).handoff.hasActivePrimary)
    #expect(listener.cancelCount == 0)

    try await harness.0.reopenNetworkAdmission()
    #expect((await harness.0.snapshot()).updateAdmissionState == .open)
    try await harness.0.reopenNetworkAdmission()
    #expect((await harness.0.snapshot()).updateAdmissionState == .open)
    #expect(await listenerRoutes.readiness() == [true, false, true])
    #expect(await advertisementRoutes.readiness() == [true, false, true])

    let replacement = try agentNetworkServiceAcceptedV1()
    listener.emitAccepted(replacement.0)
    #expect(await agentNetworkServiceEventuallyV1 {
        replacement.1.startCount == 1
    })
    replacement.1.emit(.ready)
    #expect(await agentNetworkServiceEventuallyV1 { harness.3.beginCount == 2 })
    #expect((await harness.0.snapshot()).handoff.hasActivePrimary)
}

@Test func listenerUpdateAdmissionRejectsInvalidOrderAndTerminalRecovery()
    async throws
{
    let listener = AgentNetworkListenerFakeV1()
    let harness = agentNetworkServiceHarnessV1(listener: listener)

    await #expect(throws: AgentNetworkUpdateAdmissionErrorV1
        .listenerUnavailable(.idle)) {
        try await harness.0.closeNetworkAdmission()
    }
    try await harness.0.start()
    await #expect(throws: AgentNetworkUpdateAdmissionErrorV1
        .listenerUnavailable(.starting)) {
        try await harness.0.closeNetworkAdmission()
    }
    listener.emitReady()
    #expect(await agentNetworkServiceEventuallyV1 {
        (await harness.0.snapshot()).updateAdmissionState == .open
    })
    await #expect(throws: AgentNetworkUpdateAdmissionErrorV1
        .invalidTransition(.open)) {
        try await harness.0.drainNetworkConnections()
    }
    try await harness.0.closeNetworkAdmission()
    await #expect(throws: AgentNetworkUpdateAdmissionErrorV1
        .invalidTransition(.closed)) {
        try await harness.0.closeNetworkAdmission()
    }
    try await harness.0.drainNetworkConnections()
    await #expect(throws: AgentNetworkUpdateAdmissionErrorV1
        .invalidTransition(.drained)) {
        try await harness.0.drainNetworkConnections()
    }
    try await harness.0.reopenNetworkAdmission()
    try await harness.0.reopenNetworkAdmission()
    #expect((await harness.0.snapshot()).updateAdmissionState == .open)
    await harness.0.cancel()
    await #expect(throws: AgentNetworkUpdateAdmissionErrorV1.terminal) {
        try await harness.0.reopenNetworkAdmission()
    }
}
