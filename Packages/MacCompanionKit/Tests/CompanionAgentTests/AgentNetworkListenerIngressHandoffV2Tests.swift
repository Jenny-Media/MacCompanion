import CompanionAgentNetworkPlatform
import CompanionDomain
import CompanionInteractiveHost
import CompanionInteractiveWire
@testable import CompanionNetworkPlatform
import CompanionSecurity
import CompanionTransport
import CompanionWire
import CryptoKit
import Dispatch
import Foundation
import Network
import Testing

private enum AgentNetworkIngressHandoffTestErrorV2: Error {
    case cancelled
    case noPlan
}

private final class AgentNetworkIngressAcceptedFakeV2:
    AgentNetworkAcceptedConnectionStartingV1,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var ready: (@Sendable (
        NetworkHostVerifiedReadyConnectionV0
    ) -> Void)?
    private var terminal: (@Sendable (
        NetworkHostAcceptedConnectionTerminationReasonV0
    ) -> Void)?
    private var cancelCountStorage = 0
    private var startedStorage = false

    var cancelCount: Int { lock.withLock { cancelCountStorage } }
    var started: Bool { lock.withLock { startedStorage } }

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
            startedStorage = true
            self.ready = ready
            self.terminal = terminal
        }
    }

    func cancel() {
        lock.withLock { cancelCountStorage += 1 }
    }

    func emitReady(_ value: NetworkHostVerifiedReadyConnectionV0) {
        lock.withLock { ready }?(value)
    }
}

private final class AgentNetworkIngressUnusedIOV2:
    NetworkHostIngressFrameIOV0,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var cancelCountStorage = 0

    var cancelCount: Int { lock.withLock { cancelCountStorage } }

    func receive(maximumLength: Int) async throws
        -> NetworkHostIngressFrameChunkV0
    {
        throw AgentNetworkIngressHandoffTestErrorV2.noPlan
    }

    func send(_ data: Data) async throws {
        throw AgentNetworkIngressHandoffTestErrorV2.noPlan
    }

    func cancel() {
        lock.withLock { cancelCountStorage += 1 }
    }
}

private final class AgentNetworkIngressClassifierFakeV2:
    AgentNetworkIngressClassifyingV2,
    @unchecked Sendable
{
    enum Behavior {
        case immediate(NetworkHostClassifiedConnectionV0)
        case suspended(NetworkHostClassifiedConnectionV0)
    }

    private let lock = NSLock()
    private let behavior: Behavior
    private var continuation: CheckedContinuation<
        NetworkHostClassifiedConnectionV0,
        Error
    >?
    private var cancelCountStorage = 0
    private var startedStorage = false

    init(_ behavior: Behavior) {
        self.behavior = behavior
    }

    var cancelCount: Int { lock.withLock { cancelCountStorage } }
    var started: Bool { lock.withLock { startedStorage } }

    func classify() async throws -> NetworkHostClassifiedConnectionV0 {
        switch behavior {
        case .immediate(let value):
            lock.withLock { startedStorage = true }
            return value
        case .suspended:
            return try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    startedStorage = true
                    self.continuation = continuation
                }
            }
        }
    }

    func cancel() async {
        let continuation = lock.withLock { () -> CheckedContinuation<
            NetworkHostClassifiedConnectionV0,
            Error
        >? in
            cancelCountStorage += 1
            let value = self.continuation
            self.continuation = nil
            return value
        }
        continuation?.resume(
            throwing: AgentNetworkIngressHandoffTestErrorV2.cancelled
        )
    }

    func resume() {
        let pair = lock.withLock { () -> (
            CheckedContinuation<NetworkHostClassifiedConnectionV0, Error>?,
            NetworkHostClassifiedConnectionV0?
        ) in
            let continuation = self.continuation
            self.continuation = nil
            if case .suspended(let value) = behavior {
                return (continuation, value)
            }
            return (continuation, nil)
        }
        if let continuation = pair.0, let value = pair.1 {
            continuation.resume(returning: value)
        }
    }
}

private final class AgentNetworkIngressClassifierFactoryFakeV2:
    AgentNetworkIngressClassifierMakingV2,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var plans: [AgentNetworkIngressClassifierFakeV2]

    init(_ plans: [AgentNetworkIngressClassifierFakeV2]) {
        self.plans = plans
    }

    func makeClassifier(
        verifiedReadyConnection: NetworkHostVerifiedReadyConnectionV0,
        acceptedAtMonotonicMilliseconds: UInt64,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64
    ) throws -> any AgentNetworkIngressClassifyingV2 {
        verifiedReadyConnection.cancel()
        return try lock.withLock {
            guard !plans.isEmpty else {
                throw AgentNetworkIngressHandoffTestErrorV2.noPlan
            }
            return plans.removeFirst()
        }
    }
}

private final class AgentNetworkBoundIngressFakeV2:
    AgentNetworkBoundIngressConnectionV2,
    @unchecked Sendable
{
    enum BeginBehavior {
        case immediate
        case suspended
    }

    private let lock = NSLock()
    private let beginBehavior: BeginBehavior
    private let readyChannel: HostInteractiveReadyRoleChannelV0?
    private let readyConnection:
        NetworkHostInteractiveReadyRoleConnectionV0?
    private let primaryConnectionID: Data
    private var beginCountStorage = 0
    private var cancelCountStorage = 0
    private var sentEventsStorage: [Data] = []
    private var beginContinuation: CheckedContinuation<Void, Error>?

    init(
        beginBehavior: BeginBehavior = .immediate,
        primaryConnectionID: Data = Data(repeating: 0x31, count: 16),
        readyChannel: HostInteractiveReadyRoleChannelV0? = nil,
        readyConnection:
            NetworkHostInteractiveReadyRoleConnectionV0? = nil
    ) {
        self.beginBehavior = beginBehavior
        self.primaryConnectionID = primaryConnectionID
        self.readyChannel = readyChannel ?? readyConnection?.channel
        self.readyConnection = readyConnection
    }

    var beginCount: Int { lock.withLock { beginCountStorage } }
    var cancelCount: Int { lock.withLock { cancelCountStorage } }
    var sentEvents: [Data] { lock.withLock { sentEventsStorage } }

    func begin() async throws {
        switch beginBehavior {
        case .immediate:
            lock.withLock { beginCountStorage += 1 }
        case .suspended:
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    beginCountStorage += 1
                    beginContinuation = continuation
                }
            }
        }
    }

    func cancel() async {
        let continuation = lock.withLock { () -> CheckedContinuation<
            Void,
            Error
        >? in
            cancelCountStorage += 1
            let value = beginContinuation
            beginContinuation = nil
            return value
        }
        continuation?.resume(
            throwing: AgentNetworkIngressHandoffTestErrorV2.cancelled
        )
    }

    func authenticatedPrimaryConnectionID() async -> Data? {
        primaryConnectionID
    }

    func sendAuthenticatedEvent(
        _ eventJSON: Data,
        primaryConnectionID: Data
    ) async throws {
        guard primaryConnectionID == self.primaryConnectionID else {
            throw AgentNetworkAuthenticatedEventSinkErrorV2.unavailable
        }
        lock.withLock { sentEventsStorage.append(eventJSON) }
    }

    func resumeBegin() {
        let continuation = lock.withLock { () -> CheckedContinuation<
            Void,
            Error
        >? in
            let value = beginContinuation
            beginContinuation = nil
            return value
        }
        continuation?.resume()
    }

    func readyInteractiveChannel() async
        -> HostInteractiveReadyRoleChannelV0?
    {
        readyChannel
    }

    func readyInteractiveConnection() async
        -> NetworkHostInteractiveReadyRoleConnectionV0?
    {
        readyConnection
    }
}

private actor AgentNetworkIngressBinderFakeV2:
    AgentNetworkPrimaryIngressBindingV2,
    AgentNetworkPairingIngressBindingV2,
    AgentNetworkInteractiveIngressBindingV2
{
    private var primaryPlans: [AgentNetworkBoundIngressFakeV2]
    private var pairingPlans: [AgentNetworkBoundIngressFakeV2]
    private var inputPlans: [AgentNetworkBoundIngressFakeV2]
    private var mediaPlans: [AgentNetworkBoundIngressFakeV2]
    private var primaryTerminals: [@Sendable (
        NetworkHostPrimaryTerminationReasonV0
    ) -> Void] = []
    private var pairingTerminals: [@Sendable (
        NetworkHostPairingTerminationReasonV0
    ) -> Void] = []

    init(
        primary: [AgentNetworkBoundIngressFakeV2],
        pairing: [AgentNetworkBoundIngressFakeV2],
        input: [AgentNetworkBoundIngressFakeV2] = [],
        media: [AgentNetworkBoundIngressFakeV2] = []
    ) {
        primaryPlans = primary
        pairingPlans = pairing
        inputPlans = input
        mediaPlans = media
    }

    func bindPrimaryIngress(
        classifiedConnection: NetworkHostClassifiedConnectionV0,
        acceptedAtMonotonicMilliseconds: UInt64,
        context: @escaping @Sendable () -> NetworkHostRequestContextV0,
        terminal: @escaping @Sendable (
            NetworkHostPrimaryTerminationReasonV0
        ) -> Void
    ) throws -> any AgentNetworkBoundIngressConnectionV2 {
        classifiedConnection.cancel()
        primaryTerminals.append(terminal)
        guard !primaryPlans.isEmpty else {
            throw AgentNetworkIngressHandoffTestErrorV2.noPlan
        }
        return primaryPlans.removeFirst()
    }

    func bindPairingIngress(
        classifiedConnection: NetworkHostClassifiedConnectionV0,
        acceptedAtMonotonicMilliseconds: UInt64,
        context: @escaping @Sendable () ->
            NetworkHostPairingRequestContextV0,
        terminal: @escaping @Sendable (
            NetworkHostPairingTerminationReasonV0
        ) -> Void
    ) throws -> any AgentNetworkBoundIngressConnectionV2 {
        classifiedConnection.cancel()
        pairingTerminals.append(terminal)
        guard !pairingPlans.isEmpty else {
            throw AgentNetworkIngressHandoffTestErrorV2.noPlan
        }
        return pairingPlans.removeFirst()
    }

    func bindInteractiveIngress(
        classifiedConnection: NetworkHostClassifiedConnectionV0,
        terminal: @escaping @Sendable (
            HostInteractiveRoleHandshakePumpErrorV0
        ) -> Void
    ) throws -> any AgentNetworkBoundIngressConnectionV2 {
        let role = classifiedConnection.role
        classifiedConnection.cancel()
        switch role {
        case .interactiveInput:
            guard !inputPlans.isEmpty else {
                throw AgentNetworkIngressHandoffTestErrorV2.noPlan
            }
            return inputPlans.removeFirst()
        case .interactiveMedia:
            guard !mediaPlans.isEmpty else {
                throw AgentNetworkIngressHandoffTestErrorV2.noPlan
            }
            return mediaPlans.removeFirst()
        case .applicationPrimary, .pairing:
            throw AgentNetworkIngressHandoffTestErrorV2.noPlan
        }
    }

    func primaryBindCount() -> Int { primaryTerminals.count }
    func pairingBindCount() -> Int { pairingTerminals.count }

    func endPrimary(_ index: Int) {
        primaryTerminals[index](.remoteClosed)
    }

    func endPairing(_ index: Int) {
        pairingTerminals[index](.remoteClosed)
    }
}

private func agentNetworkIngressVerifiedV2() throws
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

private func agentNetworkIngressClassifiedV2(
    role: NetworkHostIngressRoleV0
) throws -> NetworkHostClassifiedConnectionV0 {
    let verified = try agentNetworkIngressVerifiedV2()
    let binding = verified.tlsBinding
    verified.cancel()
    return NetworkHostClassifiedConnectionV0(
        role: role,
        tlsBinding: binding,
        io: AgentNetworkIngressUnusedIOV2(),
        initialFrame: Data([1])
    )
}

private func agentNetworkIngressPrimaryContextV2()
    -> NetworkHostRequestContextV0
{
    NetworkHostRequestContextV0(
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 1,
        monotonicNowMilliseconds: 1,
        responseMessageID: WireUUID(UUID())
    )
}

private func agentNetworkIngressPairingContextV2()
    -> NetworkHostPairingRequestContextV0
{
    NetworkHostPairingRequestContextV0(
        wallNowUnixMilliseconds: 1,
        monotonicNowMilliseconds: 1,
        responseMessageID: WireUUID(UUID())
    )
}

private func agentNetworkIngressEventuallyV2(
    _ condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    for _ in 0..<2_000 {
        if await condition() { return true }
        await Task.yield()
    }
    return false
}

private func agentNetworkIngressHandoffV2(
    classifiers: [AgentNetworkIngressClassifierFakeV2],
    binder: AgentNetworkIngressBinderFakeV2,
    interactivePairReady: (@Sendable (
        AgentInteractiveReadyRolePairV0
    ) async throws -> Void)? = nil
) -> AgentNetworkListenerIngressHandoffV2 {
    AgentNetworkListenerIngressHandoffV2(
        classifierFactory: AgentNetworkIngressClassifierFactoryFakeV2(
            classifiers
        ),
        primaryBinder: binder,
        pairingBinder: binder,
        interactiveBinder: binder,
        interactivePairReady: interactivePairReady,
        queue: DispatchQueue(label: "MacCompanionTests.IngressV2"),
        monotonicNowMilliseconds: { 1 },
        primaryContext: agentNetworkIngressPrimaryContextV2,
        pairingContext: agentNetworkIngressPairingContextV2
    )
}

private actor AgentNetworkInteractivePairRecorderV2 {
    private(set) var sessionIDs: [UUID] = []

    func record(_ pair: AgentInteractiveReadyRolePairV0) {
        sessionIDs.append(pair.interactiveSessionID)
    }
}

private func agentNetworkInteractiveReadyConnectionV2(
    role: InteractiveChannelRoleName,
    sessionID: UUID
) throws -> NetworkHostInteractiveReadyRoleConnectionV0 {
    let key = P256.Signing.PrivateKey()
    let spki = try CompanionSecurityV0.p256SubjectPublicKeyInfoDER(
        publicKeyX963: key.publicKey.x963Representation
    )
    let binding = try HostApplicationTLSBinding(
        evidence: HostTLSListenerEvidence(
            negotiatedTLSMajor: 1,
            negotiatedTLSMinor: 3,
            earlyDataAccepted: false,
            servedSubjectPublicKeyInfoDER: spki
        ),
        requiredHostFingerprint: CompanionSecurityV0.hostFingerprint(
            subjectPublicKeyInfoDER: spki
        )
    )
    return NetworkHostInteractiveReadyRoleConnectionV0(
        tlsBinding: binding,
        channel: try agentNetworkInteractiveReadyChannelV2(
            role: role,
            sessionID: sessionID
        ),
        receive: { _ in
            throw AgentNetworkIngressHandoffTestErrorV2.noPlan
        },
        send: { _ in },
        cancel: {}
    )
}

private func agentNetworkInteractiveReadyChannelV2(
    role: InteractiveChannelRoleName,
    sessionID: UUID,
    epoch: UInt64 = 1
) throws -> HostInteractiveReadyRoleChannelV0 {
    HostInteractiveReadyRoleChannelV0(hello:
        try InteractiveChannelHelloBody(
            channelID: WireUUID(UUID()),
            role: role,
            clientID: WireUUID(UUID(uuidString:
                "11111111-1111-4111-8111-111111111111"
            )!),
            primaryConnectionID: try WireBytes16(
                Data(repeating: 7, count: 16)
            ),
            interactiveSessionID: WireUUID(sessionID),
            authorizationEpoch: AuthorizationEpoch(rawValue: epoch),
            clientNonce: try WireBytes32(Data(repeating: 8, count: 32))
        )
    )
}

@Test func ingressAdmissionCloseCancelsSuspendedClassificationAndReopens()
    async throws
{
    let staleClassified = try agentNetworkIngressClassifiedV2(
        role: .applicationPrimary
    )
    let staleClassifier = AgentNetworkIngressClassifierFakeV2(
        .suspended(staleClassified)
    )
    let freshBound = AgentNetworkBoundIngressFakeV2()
    let freshClassifier = AgentNetworkIngressClassifierFakeV2(
        .immediate(try agentNetworkIngressClassifiedV2(
            role: .applicationPrimary
        ))
    )
    let binder = AgentNetworkIngressBinderFakeV2(
        primary: [freshBound],
        pairing: []
    )
    let handoff = agentNetworkIngressHandoffV2(
        classifiers: [staleClassifier, freshClassifier],
        binder: binder
    )
    let stale = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(stale, acceptedAtMonotonicMilliseconds: 1)
    stale.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 { staleClassifier.started })

    await handoff.closeAdmission()
    #expect(staleClassifier.cancelCount == 1)
    #expect(!(await handoff.snapshot()).isCancelled)
    #expect(!(await handoff.snapshot()).isClassifying)

    let rejected = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(rejected, acceptedAtMonotonicMilliseconds: 2)
    #expect(rejected.cancelCount == 1)
    #expect(!rejected.started)

    await handoff.reopenAdmission()
    let fresh = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(fresh, acceptedAtMonotonicMilliseconds: 3)
    fresh.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 {
        let active = await handoff.snapshot().hasActivePrimary
        return freshBound.beginCount == 1 && active
    })
}

@Test func ingressAdmissionDrainRetiresEveryEstablishedRoleWithoutTerminalCancel()
    async throws
{
    let sessionID = UUID()
    let primary = AgentNetworkBoundIngressFakeV2()
    let pairing = AgentNetworkBoundIngressFakeV2()
    let input = AgentNetworkBoundIngressFakeV2(
        readyChannel: try agentNetworkInteractiveReadyChannelV2(
            role: .input,
            sessionID: sessionID
        )
    )
    let media = AgentNetworkBoundIngressFakeV2(
        readyChannel: try agentNetworkInteractiveReadyChannelV2(
            role: .media,
            sessionID: sessionID
        )
    )
    let roles: [NetworkHostIngressRoleV0] = [
        .applicationPrimary,
        .pairing,
        .interactiveInput,
        .interactiveMedia,
    ]
    let classifiers = try roles.map { role in
        AgentNetworkIngressClassifierFakeV2(
            .immediate(try agentNetworkIngressClassifiedV2(role: role))
        )
    }
    let binder = AgentNetworkIngressBinderFakeV2(
        primary: [primary],
        pairing: [pairing],
        input: [input],
        media: [media]
    )
    let handoff = agentNetworkIngressHandoffV2(
        classifiers: classifiers,
        binder: binder
    )
    for index in roles.indices {
        let accepted = AgentNetworkIngressAcceptedFakeV2()
        try await handoff.admit(
            accepted,
            acceptedAtMonotonicMilliseconds: UInt64(index + 1)
        )
        accepted.emitReady(try agentNetworkIngressVerifiedV2())
        #expect(await agentNetworkIngressEventuallyV2 {
            let snapshot = await handoff.snapshot()
            switch roles[index] {
            case .applicationPrimary: return snapshot.hasActivePrimary
            case .pairing: return snapshot.hasActivePairing
            case .interactiveInput:
                return snapshot.hasActiveInteractiveInput
            case .interactiveMedia:
                return snapshot.hasActiveInteractiveMedia
            }
        })
    }

    await handoff.closeAdmission()
    let closed = await handoff.snapshot()
    #expect(closed.hasActivePrimary)
    #expect(closed.hasActivePairing)
    #expect(closed.hasActiveInteractiveInput)
    #expect(closed.hasActiveInteractiveMedia)

    await handoff.drainConnections()
    let drained = await handoff.snapshot()
    #expect(!drained.isCancelled)
    #expect(!drained.hasActivePrimary)
    #expect(!drained.hasActivePairing)
    #expect(!drained.hasActiveInteractiveInput)
    #expect(!drained.hasActiveInteractiveMedia)
    #expect(primary.cancelCount == 1)
    #expect(pairing.cancelCount == 1)
    #expect(input.cancelCount == 1)
    #expect(media.cancelCount == 1)

    await handoff.reopenAdmission()
    #expect(!(await handoff.snapshot()).isCancelled)
}

@Test func interactiveIngressPublishesOnlyOneExactRolePair() async throws {
    let sessionID = UUID()
    let input = AgentNetworkBoundIngressFakeV2(
        readyChannel: try agentNetworkInteractiveReadyChannelV2(
            role: .input,
            sessionID: sessionID
        )
    )
    let media = AgentNetworkBoundIngressFakeV2(
        readyChannel: try agentNetworkInteractiveReadyChannelV2(
            role: .media,
            sessionID: sessionID
        )
    )
    let binder = AgentNetworkIngressBinderFakeV2(
        primary: [],
        pairing: [],
        input: [input],
        media: [media]
    )
    let handoff = agentNetworkIngressHandoffV2(
        classifiers: [
            AgentNetworkIngressClassifierFakeV2(.immediate(
                try agentNetworkIngressClassifiedV2(
                    role: .interactiveInput
                )
            )),
            AgentNetworkIngressClassifierFakeV2(.immediate(
                try agentNetworkIngressClassifiedV2(
                    role: .interactiveMedia
                )
            )),
        ],
        binder: binder
    )

    let first = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(first, acceptedAtMonotonicMilliseconds: 1)
    let second = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(second, acceptedAtMonotonicMilliseconds: 2)
    #expect(!second.started)
    first.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 {
        second.started
    })
    second.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 {
        let snapshot = await handoff.snapshot()
        return snapshot.hasActiveInteractiveInput
            && snapshot.hasActiveInteractiveMedia
    })
    #expect(input.cancelCount == 0)
    #expect(media.cancelCount == 0)
}

@Test func interactiveIngressTransfersExactReadyConnectionsToPairOwner()
    async throws
{
    let sessionID = UUID()
    let input = AgentNetworkBoundIngressFakeV2(
        readyConnection: try agentNetworkInteractiveReadyConnectionV2(
            role: .input,
            sessionID: sessionID
        )
    )
    let media = AgentNetworkBoundIngressFakeV2(
        readyConnection: try agentNetworkInteractiveReadyConnectionV2(
            role: .media,
            sessionID: sessionID
        )
    )
    let binder = AgentNetworkIngressBinderFakeV2(
        primary: [],
        pairing: [],
        input: [input],
        media: [media]
    )
    let recorder = AgentNetworkInteractivePairRecorderV2()
    let handoff = agentNetworkIngressHandoffV2(
        classifiers: [
            AgentNetworkIngressClassifierFakeV2(.immediate(
                try agentNetworkIngressClassifiedV2(
                    role: .interactiveInput
                )
            )),
            AgentNetworkIngressClassifierFakeV2(.immediate(
                try agentNetworkIngressClassifiedV2(
                    role: .interactiveMedia
                )
            )),
        ],
        binder: binder,
        interactivePairReady: { pair in await recorder.record(pair) }
    )

    let first = AgentNetworkIngressAcceptedFakeV2()
    let second = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(first, acceptedAtMonotonicMilliseconds: 1)
    try await handoff.admit(second, acceptedAtMonotonicMilliseconds: 2)
    first.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 { second.started })
    second.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 {
        await recorder.sessionIDs == [sessionID]
    })
    #expect(input.cancelCount == 0)
    #expect(media.cancelCount == 0)
}

@Test func interactiveIngressRejectsCrossSessionRolePair() async throws {
    let input = AgentNetworkBoundIngressFakeV2(
        readyChannel: try agentNetworkInteractiveReadyChannelV2(
            role: .input,
            sessionID: UUID()
        )
    )
    let media = AgentNetworkBoundIngressFakeV2(
        readyChannel: try agentNetworkInteractiveReadyChannelV2(
            role: .media,
            sessionID: UUID()
        )
    )
    let binder = AgentNetworkIngressBinderFakeV2(
        primary: [],
        pairing: [],
        input: [input],
        media: [media]
    )
    let handoff = agentNetworkIngressHandoffV2(
        classifiers: [
            AgentNetworkIngressClassifierFakeV2(.immediate(
                try agentNetworkIngressClassifiedV2(
                    role: .interactiveInput
                )
            )),
            AgentNetworkIngressClassifierFakeV2(.immediate(
                try agentNetworkIngressClassifiedV2(
                    role: .interactiveMedia
                )
            )),
        ],
        binder: binder
    )

    let first = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(first, acceptedAtMonotonicMilliseconds: 1)
    first.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 {
        await handoff.snapshot().hasActiveInteractiveInput
    })

    let second = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(second, acceptedAtMonotonicMilliseconds: 2)
    second.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 {
        let snapshot = await handoff.snapshot()
        return !snapshot.hasActiveInteractiveInput
            && !snapshot.hasActiveInteractiveMedia
    })
    #expect(input.cancelCount == 1)
    #expect(media.cancelCount == 1)
}

@Test func pairingIngressDoesNotReplaceAnActivePrimary() async throws {
    let primary = AgentNetworkBoundIngressFakeV2()
    let pairing = AgentNetworkBoundIngressFakeV2()
    let primaryClassifier = AgentNetworkIngressClassifierFakeV2(
        .immediate(try agentNetworkIngressClassifiedV2(
            role: .applicationPrimary
        ))
    )
    let pairingClassifier = AgentNetworkIngressClassifierFakeV2(
        .immediate(try agentNetworkIngressClassifiedV2(role: .pairing))
    )
    let binder = AgentNetworkIngressBinderFakeV2(
        primary: [primary],
        pairing: [pairing]
    )
    let handoff = agentNetworkIngressHandoffV2(
        classifiers: [primaryClassifier, pairingClassifier],
        binder: binder
    )

    let first = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(first, acceptedAtMonotonicMilliseconds: 1)
    first.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 {
        await handoff.snapshot().hasActivePrimary
    })

    let second = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(second, acceptedAtMonotonicMilliseconds: 2)
    second.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 {
        let snapshot = await handoff.snapshot()
        return snapshot.hasActivePrimary && snapshot.hasActivePairing
    })
    #expect(primary.cancelCount == 0)
    #expect(primary.beginCount == 1)
    #expect(pairing.beginCount == 1)
}

@Test func secondPairingIngressCannotDisplaceVisibleDecisionOwner()
    async throws
{
    let active = AgentNetworkBoundIngressFakeV2()
    let firstClassifier = AgentNetworkIngressClassifierFakeV2(
        .immediate(try agentNetworkIngressClassifiedV2(role: .pairing))
    )
    let secondIO = AgentNetworkIngressUnusedIOV2()
    let secondClassified = NetworkHostClassifiedConnectionV0(
        role: .pairing,
        tlsBinding: try agentNetworkIngressVerifiedV2().tlsBinding,
        io: secondIO,
        initialFrame: Data([1])
    )
    let secondClassifier = AgentNetworkIngressClassifierFakeV2(
        .immediate(secondClassified)
    )
    let binder = AgentNetworkIngressBinderFakeV2(
        primary: [],
        pairing: [active]
    )
    let handoff = agentNetworkIngressHandoffV2(
        classifiers: [firstClassifier, secondClassifier],
        binder: binder
    )

    let first = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(first, acceptedAtMonotonicMilliseconds: 1)
    first.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 {
        await handoff.snapshot().hasActivePairing
    })

    let second = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(second, acceptedAtMonotonicMilliseconds: 2)
    second.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 {
        secondIO.cancelCount == 1
    })
    #expect(await binder.pairingBindCount() == 1)
    #expect(active.cancelCount == 0)
    #expect((await handoff.snapshot()).hasActivePairing)
}

@Test func validPrimaryConnectionsRemainIndependent() async throws {
    let firstBound = AgentNetworkBoundIngressFakeV2()
    let secondBound = AgentNetworkBoundIngressFakeV2()
    let binder = AgentNetworkIngressBinderFakeV2(
        primary: [firstBound, secondBound],
        pairing: []
    )
    let handoff = agentNetworkIngressHandoffV2(
        classifiers: [
            AgentNetworkIngressClassifierFakeV2(
                .immediate(try agentNetworkIngressClassifiedV2(
                    role: .applicationPrimary
                ))
            ),
            AgentNetworkIngressClassifierFakeV2(
                .immediate(try agentNetworkIngressClassifiedV2(
                    role: .applicationPrimary
                ))
            ),
        ],
        binder: binder
    )

    let first = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(first, acceptedAtMonotonicMilliseconds: 1)
    first.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 {
        firstBound.beginCount == 1
    })
    let second = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(second, acceptedAtMonotonicMilliseconds: 2)
    second.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 {
        secondBound.beginCount == 1
    })
    #expect(firstBound.cancelCount == 0)
    #expect(secondBound.cancelCount == 0)
    #expect((await handoff.snapshot()).hasActivePrimary)
}

@Test func onePrimaryTerminalLeavesTheOtherPrimaryActive() async throws {
    let firstID = Data(repeating: 0x51, count: 16)
    let secondID = Data(repeating: 0x52, count: 16)
    let firstBound = AgentNetworkBoundIngressFakeV2(
        primaryConnectionID: firstID
    )
    let secondBound = AgentNetworkBoundIngressFakeV2(
        primaryConnectionID: secondID
    )
    let binder = AgentNetworkIngressBinderFakeV2(
        primary: [firstBound, secondBound],
        pairing: []
    )
    let handoff = agentNetworkIngressHandoffV2(
        classifiers: [
            AgentNetworkIngressClassifierFakeV2(
                .immediate(try agentNetworkIngressClassifiedV2(
                    role: .applicationPrimary
                ))
            ),
            AgentNetworkIngressClassifierFakeV2(
                .immediate(try agentNetworkIngressClassifiedV2(
                    role: .applicationPrimary
                ))
            ),
        ],
        binder: binder
    )

    let first = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(first, acceptedAtMonotonicMilliseconds: 1)
    first.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 {
        await handoff.hasAuthenticatedPrimaryEventSink(
            primaryConnectionID: firstID
        )
    })

    let second = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(second, acceptedAtMonotonicMilliseconds: 2)
    second.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 {
        await handoff.hasAuthenticatedPrimaryEventSink(
            primaryConnectionID: secondID
        )
    })

    await binder.endPrimary(0)
    #expect(await agentNetworkIngressEventuallyV2 {
        !(await handoff.hasAuthenticatedPrimaryEventSink(
            primaryConnectionID: firstID
        ))
    })
    #expect(await handoff.hasAuthenticatedPrimaryEventSink(
        primaryConnectionID: secondID
    ))
    #expect((await handoff.snapshot()).hasActivePrimary)
}

@Test func authenticatedEventUsesOnlyCurrentPrimaryGeneration() async throws {
    let firstID = Data(repeating: 0x41, count: 16)
    let secondID = Data(repeating: 0x42, count: 16)
    let firstBound = AgentNetworkBoundIngressFakeV2(
        primaryConnectionID: firstID
    )
    let secondBound = AgentNetworkBoundIngressFakeV2(
        primaryConnectionID: secondID
    )
    let binder = AgentNetworkIngressBinderFakeV2(
        primary: [firstBound, secondBound],
        pairing: []
    )
    let handoff = agentNetworkIngressHandoffV2(
        classifiers: [
            AgentNetworkIngressClassifierFakeV2(
                .immediate(try agentNetworkIngressClassifiedV2(
                    role: .applicationPrimary
                ))
            ),
            AgentNetworkIngressClassifierFakeV2(
                .immediate(try agentNetworkIngressClassifiedV2(
                    role: .applicationPrimary
                ))
            ),
        ],
        binder: binder
    )

    await #expect(throws: AgentNetworkAuthenticatedEventSinkErrorV2.unavailable) {
        try await handoff.sendAuthenticatedPrimaryEvent(
            Data([0]), primaryConnectionID: firstID
        )
    }

    let first = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(first, acceptedAtMonotonicMilliseconds: 1)
    first.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 {
        firstBound.beginCount == 1
    })
    #expect(await agentNetworkIngressEventuallyV2 {
        await handoff.hasAuthenticatedPrimaryEventSink(
            primaryConnectionID: firstID
        )
    })
    try await handoff.sendAuthenticatedPrimaryEvent(
        Data([1]), primaryConnectionID: firstID
    )
    #expect(firstBound.sentEvents == [Data([1])])

    let second = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(second, acceptedAtMonotonicMilliseconds: 2)
    second.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 {
        secondBound.beginCount == 1
    })
    #expect(await handoff.hasAuthenticatedPrimaryEventSink(
        primaryConnectionID: firstID
    ))
    #expect(await agentNetworkIngressEventuallyV2 {
        await handoff.hasAuthenticatedPrimaryEventSink(
            primaryConnectionID: secondID
        )
    })
    try await handoff.sendAuthenticatedPrimaryEvent(
        Data([8]), primaryConnectionID: firstID
    )
    try await handoff.sendAuthenticatedPrimaryEvent(
        Data([2]), primaryConnectionID: secondID
    )
    #expect(firstBound.sentEvents == [Data([1]), Data([8])])
    #expect(secondBound.sentEvents == [Data([2])])

    await handoff.cancel()
    await #expect(throws: AgentNetworkAuthenticatedEventSinkErrorV2.unavailable) {
        try await handoff.sendAuthenticatedPrimaryEvent(
            Data([3]), primaryConnectionID: secondID
        )
    }
}

@Test func newerTLSCandidateQueuesBehindSuspendedClassification()
    async throws
{
    let staleClassified = try agentNetworkIngressClassifiedV2(role: .pairing)
    let stale = AgentNetworkIngressClassifierFakeV2(
        .suspended(staleClassified)
    )
    let winner = AgentNetworkIngressClassifierFakeV2(
        .immediate(try agentNetworkIngressClassifiedV2(
            role: .applicationPrimary
        ))
    )
    let bound = AgentNetworkBoundIngressFakeV2()
    let binder = AgentNetworkIngressBinderFakeV2(
        primary: [bound],
        pairing: [AgentNetworkBoundIngressFakeV2()]
    )
    let handoff = agentNetworkIngressHandoffV2(
        classifiers: [stale, winner],
        binder: binder
    )

    let first = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(first, acceptedAtMonotonicMilliseconds: 1)
    first.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 { stale.started })

    let second = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(second, acceptedAtMonotonicMilliseconds: 2)
    #expect(!second.started)
    stale.resume()
    #expect(await agentNetworkIngressEventuallyV2 { second.started })
    second.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 {
        bound.beginCount == 1
    })
    #expect(stale.cancelCount == 0)
    #expect(await binder.pairingBindCount() == 1)
    #expect(await agentNetworkIngressEventuallyV2 {
        await handoff.snapshot().hasActivePrimary
    })
}

@Test func roleTerminalAndGlobalCancelRemainIsolatedAndExact() async throws {
    let primary = AgentNetworkBoundIngressFakeV2()
    let pairing = AgentNetworkBoundIngressFakeV2()
    let binder = AgentNetworkIngressBinderFakeV2(
        primary: [primary],
        pairing: [pairing]
    )
    let handoff = agentNetworkIngressHandoffV2(
        classifiers: [
            AgentNetworkIngressClassifierFakeV2(
                .immediate(try agentNetworkIngressClassifiedV2(
                    role: .applicationPrimary
                ))
            ),
            AgentNetworkIngressClassifierFakeV2(
                .immediate(try agentNetworkIngressClassifiedV2(
                    role: .pairing
                ))
            ),
        ],
        binder: binder
    )

    let first = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(first, acceptedAtMonotonicMilliseconds: 1)
    first.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 {
        await handoff.snapshot().hasActivePrimary
    })
    let second = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(second, acceptedAtMonotonicMilliseconds: 2)
    second.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 {
        await handoff.snapshot().hasActivePairing
    })

    await binder.endPairing(0)
    #expect(await agentNetworkIngressEventuallyV2 {
        let snapshot = await handoff.snapshot()
        return snapshot.hasActivePrimary && !snapshot.hasActivePairing
    })
    #expect(primary.cancelCount == 0)

    await handoff.cancel()
    #expect(primary.cancelCount == 1)
    #expect(pairing.cancelCount == 0)
    #expect((await handoff.snapshot()).isCancelled)
}

@Test func unprovenPrimaryCandidateCannotEvictAuthenticatedPrimary()
    async throws
{
    let active = AgentNetworkBoundIngressFakeV2()
    let unproven = AgentNetworkBoundIngressFakeV2(
        beginBehavior: .suspended
    )
    let pairing = AgentNetworkBoundIngressFakeV2()
    let binder = AgentNetworkIngressBinderFakeV2(
        primary: [active, unproven],
        pairing: [pairing]
    )
    let handoff = agentNetworkIngressHandoffV2(
        classifiers: [
            AgentNetworkIngressClassifierFakeV2(
                .immediate(try agentNetworkIngressClassifiedV2(
                    role: .applicationPrimary
                ))
            ),
            AgentNetworkIngressClassifierFakeV2(
                .immediate(try agentNetworkIngressClassifiedV2(
                    role: .applicationPrimary
                ))
            ),
            AgentNetworkIngressClassifierFakeV2(
                .immediate(try agentNetworkIngressClassifiedV2(
                    role: .pairing
                ))
            ),
        ],
        binder: binder
    )

    let first = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(first, acceptedAtMonotonicMilliseconds: 1)
    first.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 {
        await handoff.snapshot().hasActivePrimary
    })

    let second = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(second, acceptedAtMonotonicMilliseconds: 2)
    second.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 {
        let snapshot = await handoff.snapshot()
        return unproven.beginCount == 1
            && snapshot.bindingRole == .applicationPrimary
            && snapshot.hasActivePrimary
    })
    #expect(active.cancelCount == 0)

    let third = AgentNetworkIngressAcceptedFakeV2()
    try await handoff.admit(third, acceptedAtMonotonicMilliseconds: 3)
    #expect(!third.started)
    unproven.resumeBegin()
    #expect(await agentNetworkIngressEventuallyV2 { third.started })
    third.emitReady(try agentNetworkIngressVerifiedV2())
    #expect(await agentNetworkIngressEventuallyV2 {
        let snapshot = await handoff.snapshot()
        return unproven.cancelCount == 0
            && snapshot.hasActivePrimary
            && snapshot.hasActivePairing
    })
    #expect(active.cancelCount == 0)
}
