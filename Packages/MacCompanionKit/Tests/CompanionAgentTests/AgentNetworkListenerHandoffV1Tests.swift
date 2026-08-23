import CompanionAgentNetworkPlatform
import CompanionDomain
@testable import CompanionNetworkPlatform
import CompanionSecurity
import CompanionTransport
import CompanionWire
import CryptoKit
import Dispatch
import Foundation
import Network
import Testing

private enum AgentNetworkListenerHandoffTestErrorV1: Error {
    case bindingFailed
    case beginFailed
}

private final class AgentNetworkAcceptedFakeV1:
    AgentNetworkAcceptedConnectionStartingV1,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var readyHandler: (@Sendable (
        NetworkHostVerifiedReadyConnectionV0
    ) -> Void)?
    private var terminalHandler: (@Sendable (
        NetworkHostAcceptedConnectionTerminationReasonV0
    ) -> Void)?
    private var starts = 0
    private var cancels = 0

    var startCount: Int { lock.withLock { starts } }
    var cancelCount: Int { lock.withLock { cancels } }

    func start(
        queue: DispatchQueue,
        ready: @escaping @Sendable (
            NetworkHostVerifiedReadyConnectionV0
        ) -> Void,
        terminal: @escaping @Sendable (
            NetworkHostAcceptedConnectionTerminationReasonV0
        ) -> Void
    ) throws {
        lock.withLock {
            starts += 1
            readyHandler = ready
            terminalHandler = terminal
        }
    }

    func cancel() {
        lock.withLock { cancels += 1 }
    }

    func emitReady(_ verified: NetworkHostVerifiedReadyConnectionV0) {
        lock.withLock { readyHandler }?(verified)
    }

    func emitTerminal(
        _ reason: NetworkHostAcceptedConnectionTerminationReasonV0
    ) {
        lock.withLock { terminalHandler }?(reason)
    }
}

private final class AgentNetworkBoundFakeV1:
    AgentNetworkBoundPrimaryConnectionV1,
    @unchecked Sendable
{
    enum BeginBehavior: Sendable {
        case succeed
        case fail
        case terminate(NetworkHostPrimaryTerminationReasonV0)
    }

    private let lock = NSLock()
    private let beginBehavior: BeginBehavior
    private var terminalHandler: (@Sendable (
        NetworkHostPrimaryTerminationReasonV0
    ) -> Void)?
    private var begins = 0
    private var cancels = 0

    init(beginBehavior: BeginBehavior = .succeed) {
        self.beginBehavior = beginBehavior
    }

    var beginCount: Int { lock.withLock { begins } }
    var cancelCount: Int { lock.withLock { cancels } }

    func installTerminal(
        _ terminal: @escaping @Sendable (
            NetworkHostPrimaryTerminationReasonV0
        ) -> Void
    ) {
        lock.withLock { terminalHandler = terminal }
    }

    func begin() async throws {
        let terminal = lock.withLock { () -> (@Sendable (
            NetworkHostPrimaryTerminationReasonV0
        ) -> Void)? in
            begins += 1
            return terminalHandler
        }
        switch beginBehavior {
        case .succeed:
            return
        case .fail:
            throw AgentNetworkListenerHandoffTestErrorV1.beginFailed
        case .terminate(let reason):
            terminal?(reason)
        }
    }

    func cancel() async {
        lock.withLock { cancels += 1 }
    }
}

private actor AgentNetworkBinderFakeV1:
    AgentNetworkPrimaryConnectionBindingV1
{
    struct Plan: Sendable {
        let connection: AgentNetworkBoundFakeV1?

        static var failure: Self { Plan(connection: nil) }
        static func connection(_ value: AgentNetworkBoundFakeV1) -> Self {
            Plan(connection: value)
        }
    }

    private var plans: [Plan]
    private var acceptedTimes: [UInt64] = []
    private var terminals: [@Sendable (
        NetworkHostPrimaryTerminationReasonV0
    ) -> Void] = []

    init(plans: [Plan]) {
        self.plans = plans
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
        terminals.append(terminal)
        let plan = plans.removeFirst()
        guard let connection = plan.connection else {
            throw AgentNetworkListenerHandoffTestErrorV1.bindingFailed
        }
        verifiedReadyConnection.cancel()
        connection.installTerminal(terminal)
        return connection
    }

    func bindingCount() -> Int { acceptedTimes.count }
    func recordedAcceptedTimes() -> [UInt64] { acceptedTimes }

    func emitTerminal(
        at index: Int,
        reason: NetworkHostPrimaryTerminationReasonV0
    ) {
        terminals[index](reason)
    }
}

private actor AgentNetworkSuspendingBinderFakeV1:
    AgentNetworkPrimaryConnectionBindingV1
{
    private let connection: AgentNetworkBoundFakeV1
    private var continuation: CheckedContinuation<Void, Never>?
    private var started = false

    init(connection: AgentNetworkBoundFakeV1) {
        self.connection = connection
    }

    func bindPrimaryConnection(
        verifiedReadyConnection: NetworkHostVerifiedReadyConnectionV0,
        acceptedAtMonotonicMilliseconds: UInt64,
        context: @escaping @Sendable () -> NetworkHostRequestContextV0,
        terminal: @escaping @Sendable (
            NetworkHostPrimaryTerminationReasonV0
        ) -> Void
    ) async throws -> any AgentNetworkBoundPrimaryConnectionV1 {
        verifiedReadyConnection.cancel()
        connection.installTerminal(terminal)
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            started = true
        }
        return connection
    }

    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private final class AgentNetworkTerminalRecorderV1: @unchecked Sendable {
    private let lock = NSLock()
    private var acceptedReasons:
        [NetworkHostAcceptedConnectionTerminationReasonV0] = []
    private var primaryReasons: [NetworkHostPrimaryTerminationReasonV0] = []

    var accepted: [NetworkHostAcceptedConnectionTerminationReasonV0] {
        lock.withLock { acceptedReasons }
    }
    var primary: [NetworkHostPrimaryTerminationReasonV0] {
        lock.withLock { primaryReasons }
    }

    func recordAccepted(
        _ reason: NetworkHostAcceptedConnectionTerminationReasonV0
    ) {
        lock.withLock { acceptedReasons.append(reason) }
    }

    func recordPrimary(_ reason: NetworkHostPrimaryTerminationReasonV0) {
        lock.withLock { primaryReasons.append(reason) }
    }
}

private func agentNetworkVerifiedConnectionV1() throws
    -> NetworkHostVerifiedReadyConnectionV0
{
    let key = P256.Signing.PrivateKey()
    let spki = try CompanionSecurityV0.p256SubjectPublicKeyInfoDER(
        publicKeyX963: key.publicKey.x963Representation
    )
    let fingerprint = try CompanionSecurityV0.hostFingerprint(
        subjectPublicKeyInfoDER: spki
    )
    let binding = try HostApplicationTLSBinding(
        evidence: HostTLSListenerEvidence(
            negotiatedTLSMajor: 1,
            negotiatedTLSMinor: 3,
            earlyDataAccepted: false,
            servedSubjectPublicKeyInfoDER: spki
        ),
        requiredHostFingerprint: fingerprint
    )
    return NetworkHostVerifiedReadyConnectionV0(
        connection: NWConnection(
            host: "127.0.0.1",
            port: 9,
            using: .tcp
        ),
        tlsBinding: binding
    )
}

private func agentNetworkRequestContextV1() -> NetworkHostRequestContextV0 {
    NetworkHostRequestContextV0(
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 1,
        monotonicNowMilliseconds: 1,
        responseMessageID: WireUUID(UUID())
    )
}

private func agentNetworkEventuallyV1(
    _ condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    for _ in 0..<1_000 {
        if await condition() { return true }
        await Task.yield()
    }
    return false
}

@Test func listenerHandoffAdmitsOnlyTheNewestPendingTLSCandidate() async throws {
    let bound = AgentNetworkBoundFakeV1()
    let binder = AgentNetworkBinderFakeV1(plans: [.connection(bound)])
    let handoff = AgentNetworkListenerHandoffV1(
        binder: binder,
        queue: DispatchQueue(label: "MacCompanionTests.ListenerHandoffNewest"),
        context: agentNetworkRequestContextV1
    )
    let first = AgentNetworkAcceptedFakeV1()
    let second = AgentNetworkAcceptedFakeV1()

    try await handoff.admit(
        first,
        acceptedAtMonotonicMilliseconds: 10
    )
    try await handoff.admit(
        second,
        acceptedAtMonotonicMilliseconds: 20
    )
    #expect(first.cancelCount == 1)
    #expect(second.startCount == 1)

    first.emitReady(try agentNetworkVerifiedConnectionV1())
    second.emitReady(try agentNetworkVerifiedConnectionV1())

    #expect(await agentNetworkEventuallyV1 {
        bound.beginCount == 1
    })
    #expect(await binder.bindingCount() == 1)
    #expect(await binder.recordedAcceptedTimes() == [20])
    #expect(await handoff.snapshot() == AgentNetworkListenerHandoffSnapshotV1(
        isCancelled: false,
        hasPendingTLS: false,
        isBinding: false,
        hasActivePrimary: true
    ))
}

@Test func listenerHandoffCleansUpBindingAndBeginFailures() async throws {
    let failingBegin = AgentNetworkBoundFakeV1(beginBehavior: .fail)
    let binder = AgentNetworkBinderFakeV1(
        plans: [.failure, .connection(failingBegin)]
    )
    let handoff = AgentNetworkListenerHandoffV1(
        binder: binder,
        queue: DispatchQueue(label: "MacCompanionTests.ListenerHandoffFailure"),
        context: agentNetworkRequestContextV1
    )
    let bindFailure = AgentNetworkAcceptedFakeV1()
    let unconsumed = try agentNetworkVerifiedConnectionV1()

    try await handoff.admit(
        bindFailure,
        acceptedAtMonotonicMilliseconds: 1
    )
    bindFailure.emitReady(unconsumed)
    #expect(await agentNetworkEventuallyV1 {
        let bindingCount = await binder.bindingCount()
        let snapshot = await handoff.snapshot()
        return bindingCount == 1 && !snapshot.isBinding
    })
    #expect(throws: NetworkHostAcceptedConnectionErrorV0
        .verifiedConnectionAlreadyConsumed) {
        try unconsumed.consumeConnection()
    }

    let beginFailure = AgentNetworkAcceptedFakeV1()
    try await handoff.admit(
        beginFailure,
        acceptedAtMonotonicMilliseconds: 2
    )
    beginFailure.emitReady(try agentNetworkVerifiedConnectionV1())
    #expect(await agentNetworkEventuallyV1 {
        failingBegin.cancelCount == 1
    })
    #expect(failingBegin.beginCount == 1)
    #expect(!(await handoff.snapshot()).hasActivePrimary)
}

@Test func listenerHandoffCannotPublishATransportThatTerminatesDuringBegin() async throws {
    let terminated = AgentNetworkBoundFakeV1(
        beginBehavior: .terminate(.remoteClosed)
    )
    let binder = AgentNetworkBinderFakeV1(plans: [.connection(terminated)])
    let recorder = AgentNetworkTerminalRecorderV1()
    let handoff = AgentNetworkListenerHandoffV1(
        binder: binder,
        queue: DispatchQueue(label: "MacCompanionTests.ListenerHandoffBeginRace"),
        context: agentNetworkRequestContextV1,
        primaryTerminal: recorder.recordPrimary
    )
    let accepted = AgentNetworkAcceptedFakeV1()

    try await handoff.admit(accepted, acceptedAtMonotonicMilliseconds: 1)
    accepted.emitReady(try agentNetworkVerifiedConnectionV1())

    #expect(await agentNetworkEventuallyV1 {
        terminated.cancelCount == 1
    })
    #expect(recorder.primary == [.remoteClosed])
    #expect(await handoff.snapshot() == AgentNetworkListenerHandoffSnapshotV1(
        isCancelled: false,
        hasPendingTLS: false,
        isBinding: false,
        hasActivePrimary: false
    ))
}

@Test func listenerHandoffIgnoresStaleTerminalAfterPrimaryReplacement() async throws {
    let firstBound = AgentNetworkBoundFakeV1()
    let secondBound = AgentNetworkBoundFakeV1()
    let binder = AgentNetworkBinderFakeV1(
        plans: [.connection(firstBound), .connection(secondBound)]
    )
    let recorder = AgentNetworkTerminalRecorderV1()
    let handoff = AgentNetworkListenerHandoffV1(
        binder: binder,
        queue: DispatchQueue(label: "MacCompanionTests.ListenerHandoffReplace"),
        context: agentNetworkRequestContextV1,
        primaryTerminal: recorder.recordPrimary
    )

    let first = AgentNetworkAcceptedFakeV1()
    try await handoff.admit(first, acceptedAtMonotonicMilliseconds: 1)
    first.emitReady(try agentNetworkVerifiedConnectionV1())
    #expect(await agentNetworkEventuallyV1 { firstBound.beginCount == 1 })

    let second = AgentNetworkAcceptedFakeV1()
    try await handoff.admit(second, acceptedAtMonotonicMilliseconds: 2)
    second.emitReady(try agentNetworkVerifiedConnectionV1())
    #expect(await agentNetworkEventuallyV1 {
        secondBound.beginCount == 1 && firstBound.cancelCount == 1
    })

    await binder.emitTerminal(at: 0, reason: .connectionFailed)
    for _ in 0..<100 { await Task.yield() }
    #expect(recorder.primary.isEmpty)
    #expect((await handoff.snapshot()).hasActivePrimary)

    await binder.emitTerminal(at: 1, reason: .remoteClosed)
    #expect(await agentNetworkEventuallyV1 {
        recorder.primary == [.remoteClosed]
    })
    #expect(!(await handoff.snapshot()).hasActivePrimary)
}

@Test func listenerHandoffCancellationOwnsPendingAndActiveConnections() async throws {
    let activeBound = AgentNetworkBoundFakeV1()
    let binder = AgentNetworkBinderFakeV1(plans: [.connection(activeBound)])
    let recorder = AgentNetworkTerminalRecorderV1()
    let handoff = AgentNetworkListenerHandoffV1(
        binder: binder,
        queue: DispatchQueue(label: "MacCompanionTests.ListenerHandoffCancel"),
        context: agentNetworkRequestContextV1,
        acceptedTerminal: recorder.recordAccepted,
        primaryTerminal: recorder.recordPrimary
    )
    let active = AgentNetworkAcceptedFakeV1()
    try await handoff.admit(active, acceptedAtMonotonicMilliseconds: 1)
    active.emitReady(try agentNetworkVerifiedConnectionV1())
    #expect(await agentNetworkEventuallyV1 { activeBound.beginCount == 1 })

    let pending = AgentNetworkAcceptedFakeV1()
    try await handoff.admit(pending, acceptedAtMonotonicMilliseconds: 2)
    await handoff.cancel()
    await handoff.cancel()

    #expect(pending.cancelCount == 1)
    #expect(activeBound.cancelCount == 1)
    #expect(await handoff.snapshot() == AgentNetworkListenerHandoffSnapshotV1(
        isCancelled: true,
        hasPendingTLS: false,
        isBinding: false,
        hasActivePrimary: false
    ))
    pending.emitTerminal(.connectionFailed)
    await binder.emitTerminal(at: 0, reason: .connectionCancelled)
    for _ in 0..<100 { await Task.yield() }
    #expect(recorder.accepted.isEmpty)
    #expect(recorder.primary.isEmpty)
}

@Test func listenerHandoffReplacementRetiresAnInFlightBinding() async throws {
    let staleBound = AgentNetworkBoundFakeV1()
    let binder = AgentNetworkSuspendingBinderFakeV1(connection: staleBound)
    let handoff = AgentNetworkListenerHandoffV1(
        binder: binder,
        queue: DispatchQueue(label: "MacCompanionTests.ListenerHandoffBindingReplace"),
        context: agentNetworkRequestContextV1
    )
    let stale = AgentNetworkAcceptedFakeV1()
    try await handoff.admit(stale, acceptedAtMonotonicMilliseconds: 1)
    stale.emitReady(try agentNetworkVerifiedConnectionV1())
    await binder.waitUntilStarted()
    #expect((await handoff.snapshot()).isBinding)

    let newest = AgentNetworkAcceptedFakeV1()
    try await handoff.admit(newest, acceptedAtMonotonicMilliseconds: 2)
    await binder.resume()

    #expect(await agentNetworkEventuallyV1 { staleBound.cancelCount == 1 })
    #expect(staleBound.beginCount == 0)
    #expect(await handoff.snapshot() == AgentNetworkListenerHandoffSnapshotV1(
        isCancelled: false,
        hasPendingTLS: true,
        isBinding: false,
        hasActivePrimary: false
    ))
}

@Test func listenerHandoffCancellationRetiresAnInFlightBinding() async throws {
    let staleBound = AgentNetworkBoundFakeV1()
    let binder = AgentNetworkSuspendingBinderFakeV1(connection: staleBound)
    let handoff = AgentNetworkListenerHandoffV1(
        binder: binder,
        queue: DispatchQueue(label: "MacCompanionTests.ListenerHandoffBindingCancel"),
        context: agentNetworkRequestContextV1
    )
    let accepted = AgentNetworkAcceptedFakeV1()
    try await handoff.admit(accepted, acceptedAtMonotonicMilliseconds: 1)
    accepted.emitReady(try agentNetworkVerifiedConnectionV1())
    await binder.waitUntilStarted()

    await handoff.cancel()
    await binder.resume()

    #expect(await agentNetworkEventuallyV1 { staleBound.cancelCount == 1 })
    #expect(staleBound.beginCount == 0)
    #expect(await handoff.snapshot() == AgentNetworkListenerHandoffSnapshotV1(
        isCancelled: true,
        hasPendingTLS: false,
        isBinding: false,
        hasActivePrimary: false
    ))
}

@Test func listenerHandoffAdmissionCloseInvalidatesSuspendedBindWithoutTerminalCancel()
    async throws
{
    let staleBound = AgentNetworkBoundFakeV1()
    let binder = AgentNetworkSuspendingBinderFakeV1(connection: staleBound)
    let handoff = AgentNetworkListenerHandoffV1(
        binder: binder,
        queue: DispatchQueue(label: "MacCompanionTests.ListenerHandoffUpdateClose"),
        context: agentNetworkRequestContextV1
    )
    let accepted = AgentNetworkAcceptedFakeV1()
    try await handoff.admit(accepted, acceptedAtMonotonicMilliseconds: 1)
    accepted.emitReady(try agentNetworkVerifiedConnectionV1())
    await binder.waitUntilStarted()

    await handoff.closeAdmission()
    await binder.resume()

    #expect(await agentNetworkEventuallyV1 { staleBound.cancelCount == 1 })
    #expect(staleBound.beginCount == 0)
    #expect(await handoff.snapshot() == AgentNetworkListenerHandoffSnapshotV1(
        isCancelled: false,
        hasPendingTLS: false,
        isBinding: false,
        hasActivePrimary: false
    ))

    let rejected = AgentNetworkAcceptedFakeV1()
    try await handoff.admit(rejected, acceptedAtMonotonicMilliseconds: 2)
    #expect(rejected.cancelCount == 1)
    #expect(rejected.startCount == 0)

    await handoff.reopenAdmission()
    #expect(!(await handoff.snapshot()).isCancelled)
}
