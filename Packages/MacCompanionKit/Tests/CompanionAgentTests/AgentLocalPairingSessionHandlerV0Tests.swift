import CompanionAgent
import CompanionDiscovery
import CompanionDomain
import CompanionIPC
import CompanionPairing
import CompanionPersistence
import CompanionWire
import Foundation
import Testing

private let pairingHandlerID = UUID(
    uuidString: "018f4000-0000-7000-8000-0000000000c1"
)!
private let pairingHandlerCreatedAt: Int64 = 1_787_198_400_000
private let pairingHandlerMonotonic: Int64 = 10_000
private let pairingHandlerFingerprint = Data(0x20...0x3f)

private actor NoopPairingCommitterV0: PairingCommitter {
    func commitPairing(
        pairingID: UUID,
        record: StoredDeviceRecord,
        displayName: DeviceDisplayName
    ) async throws {}
}

private func pairingHandlerContext(
    endpoints: [EndpointCandidate]? = nil
) throws -> AgentLocalPairingContextV0 {
    try AgentLocalPairingContextV0(
        hostFingerprint: pairingHandlerFingerprint,
        endpoints: endpoints ?? [
            try EndpointCandidate(
                kind: .ipv4,
                value: "192.168.50.20",
                port: 47_474
            ),
            try EndpointCandidate(
                kind: .bonjour,
                value: "studio._maccompanion._tcp.local.",
                port: 47_474
            ),
        ]
    )
}

private func pairingHandlerTime(
    wall: Int64 = pairingHandlerCreatedAt,
    monotonic: Int64 = pairingHandlerMonotonic
) throws -> AgentLocalPairingTimeSampleV0 {
    try AgentLocalPairingTimeSampleV0(
        wallNowUnixMilliseconds: wall,
        monotonicNowMilliseconds: monotonic
    )
}

private final class SequencedPairingTimeSourceV0:
    AgentLocalPairingTimeSamplingV0,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var samples: [AgentLocalPairingTimeSampleV0]

    init(_ samples: [AgentLocalPairingTimeSampleV0]) {
        self.samples = samples
    }

    func currentPairingTime() throws -> AgentLocalPairingTimeSampleV0 {
        lock.lock()
        defer { lock.unlock() }
        guard !samples.isEmpty else {
            throw AgentLocalPairingSessionErrorV0.invalidClock
        }
        return samples.removeFirst()
    }
}

private struct FailingPairingContextSourceV0:
    AgentLocalPairingContextReadingV0,
    Sendable
{
    func currentPairingContext() async throws -> AgentLocalPairingContextV0 {
        throw AgentLocalPairingSessionErrorV0.invalidContext
    }
}

private struct FailingPairingTimeSourceV0:
    AgentLocalPairingTimeSamplingV0,
    Sendable
{
    func currentPairingTime() throws -> AgentLocalPairingTimeSampleV0 {
        throw AgentLocalPairingSessionErrorV0.invalidClock
    }
}

private actor SuspendingPairingManagerV0:
    AgentLocalPairingSessionManagingV0
{
    private let authority: PairingSessionAuthority
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(authority: PairingSessionAuthority) {
        self.authority = authority
    }

    func createLocalPairingSession(
        pairingID: UUID,
        hostFingerprint: Data,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: Int64
    ) async throws -> PairingAdvertisement {
        started = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
        return try await authority.createSession(
            pairingID: pairingID,
            hostFingerprint: hostFingerprint,
            wallNowUnixMilliseconds: wallNowUnixMilliseconds,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
    }

    func cancelLocalPairingSession(
        pairingID: UUID,
        monotonicNowMilliseconds: Int64
    ) async throws {
        try await authority.cancel(
            pairingID: pairingID,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
    }

    func waitUntilStarted() async {
        while !started { await Task.yield() }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private func pairingHandler(
    authority: PairingSessionAuthority? = nil,
    contextSource: (any AgentLocalPairingContextReadingV0)? = nil,
    timeSource: (any AgentLocalPairingTimeSamplingV0)? = nil,
    pairingID: UUID = pairingHandlerID
) throws -> (AgentLocalPairingSessionHandlerV0, PairingSessionAuthority) {
    let authority = authority ?? PairingSessionAuthority(
        committer: NoopPairingCommitterV0()
    )
    let resolvedContextSource: any AgentLocalPairingContextReadingV0
    if let contextSource {
        resolvedContextSource = contextSource
    } else {
        resolvedContextSource = StaticAgentLocalPairingContextSourceV0(
            try pairingHandlerContext()
        )
    }
    let resolvedTimeSource: any AgentLocalPairingTimeSamplingV0
    if let timeSource {
        resolvedTimeSource = timeSource
    } else {
        resolvedTimeSource = StaticAgentLocalPairingTimeSourceV0(
            try pairingHandlerTime()
        )
    }
    return (
        AgentLocalPairingSessionHandlerV0(
            authority: authority,
            contextSource: resolvedContextSource,
            timeSource: resolvedTimeSource,
            pairingIDGenerator: { pairingID }
        ),
        authority
    )
}

@Test func agentCreatesExactBoundQRCodeAndReplaysOnlyActiveCommand() async throws {
    let (handler, _) = try pairingHandler()
    let command = try LocalPairingSessionCreateCommandV0(commandID: UUID())
    let first = try await handler.create(command)
    let replay = try await handler.create(command)

    #expect(first == replay)
    #expect(first.correlationID == command.commandID)
    #expect(first.pairingID == pairingHandlerID)
    #expect(first.expiresAtUnixMilliseconds
        == pairingHandlerCreatedAt + PairingSessionAuthority.lifetimeMilliseconds)
    let decoded = try PairingQRCodeCodec.decode(
        first.encodedQRCode,
        nowUnixMilliseconds: first.createdAtUnixMilliseconds
    )
    #expect(decoded.pairingID.rawValue == pairingHandlerID)
    #expect(decoded.hostFingerprint.rawValue == pairingHandlerFingerprint)
    #expect(decoded.endpoints == (try pairingHandlerContext()).endpoints)

    await #expect(
        throws: AgentLocalPairingSessionErrorV0.presentationAlreadyActive
    ) {
        _ = try await handler.create(
            LocalPairingSessionCreateCommandV0(commandID: UUID())
        )
    }
}

@Test func agentRejectsPairingCreationAtPairedDeviceCapacity() async throws {
    let authority = PairingSessionAuthority(
        committer: NoopPairingCommitterV0()
    )
    let handler = AgentLocalPairingSessionHandlerV0(
        authority: authority,
        contextSource: StaticAgentLocalPairingContextSourceV0(
            try pairingHandlerContext()
        ),
        timeSource: StaticAgentLocalPairingTimeSourceV0(
            try pairingHandlerTime()
        ),
        capacitySource: StaticAgentLocalPairingCapacitySourceV0(
            Int(LocalAgentStatusSnapshot.maximumPairedDeviceCount)
        )
    )

    await #expect(throws: AgentLocalPairingSessionErrorV0.capacityReached) {
        _ = try await handler.create(
            LocalPairingSessionCreateCommandV0(commandID: UUID())
        )
    }
}

@Test func dismissalTombstonesSecretAndReplaysExactReceipt() async throws {
    let (handler, authority) = try pairingHandler()
    let create = try LocalPairingSessionCreateCommandV0(commandID: UUID())
    let created = try await handler.create(create)
    let dismiss = try LocalPairingSessionDismissCommandV0(
        commandID: UUID(),
        pairingID: created.pairingID
    )
    let first = try await handler.dismiss(dismiss)
    let replay = try await handler.dismiss(dismiss)

    #expect(first == replay)
    #expect(first.correlationID == dismiss.commandID)
    await #expect(throws: PairingSessionError.alreadyConsumed) {
        _ = try await authority.begin(
            pairingID: created.pairingID,
            clientID: UUID(),
            sessionPublicKeyX963: Data(),
            approvalPublicKeyX963: Data(),
            clientNonce: Data(),
            monotonicNowMilliseconds: pairingHandlerMonotonic + 1
        )
    }
    await #expect(throws: AgentLocalPairingSessionErrorV0.staleCommand) {
        _ = try await handler.create(create)
    }
}

@Test func mismatchedDismissalCannotCancelVisiblePairingCode() async throws {
    let (handler, _) = try pairingHandler()
    let created = try await handler.create(
        LocalPairingSessionCreateCommandV0(commandID: UUID())
    )
    await #expect(throws: AgentLocalPairingSessionErrorV0.bindingMismatch) {
        _ = try await handler.dismiss(
            LocalPairingSessionDismissCommandV0(
                commandID: UUID(),
                pairingID: UUID()
            )
        )
    }
    let correct = try LocalPairingSessionDismissCommandV0(
        commandID: UUID(),
        pairingID: created.pairingID
    )
    #expect(try await handler.dismiss(correct).pairingID == created.pairingID)
}

@Test func remotelyConsumedPairingConfirmsCodeIsAlreadyInactive() async throws {
    let authority = PairingSessionAuthority(committer: NoopPairingCommitterV0())
    let handler = AgentLocalPairingSessionHandlerV0(
        authority: authority,
        contextSource: StaticAgentLocalPairingContextSourceV0(
            try pairingHandlerContext()
        ),
        timeSource: StaticAgentLocalPairingTimeSourceV0(
            try pairingHandlerTime()
        )
    )
    let first = try await handler.create(
        LocalPairingSessionCreateCommandV0(commandID: UUID())
    )
    try await authority.cancel(
        pairingID: first.pairingID,
        monotonicNowMilliseconds: pairingHandlerMonotonic + 1
    )
    let dismiss = try LocalPairingSessionDismissCommandV0(
        commandID: UUID(),
        pairingID: first.pairingID
    )
    let receipt = try await handler.dismiss(dismiss)
    let replay = try await handler.dismiss(dismiss)

    #expect(receipt == replay)
    #expect(receipt.correlationID == dismiss.commandID)
    #expect(receipt.pairingID == first.pairingID)
    let replacement = try await handler.create(
        LocalPairingSessionCreateCommandV0(commandID: UUID())
    )
    #expect(replacement.pairingID != first.pairingID)
}

@Test func unknownDismissalWithoutLocalPresentationRemainsRejected() async throws {
    let (handler, _) = try pairingHandler()

    await #expect(throws: AgentLocalPairingSessionErrorV0.notActive) {
        _ = try await handler.dismiss(
            LocalPairingSessionDismissCommandV0(
                commandID: UUID(),
                pairingID: UUID()
            )
        )
    }
}

@Test func expiredVisiblePairingConfirmsCodeIsAlreadyInactive() async throws {
    let expiryWall = pairingHandlerCreatedAt
        + PairingSessionAuthority.lifetimeMilliseconds
    let source = SequencedPairingTimeSourceV0([
        try pairingHandlerTime(),
        try pairingHandlerTime(
            wall: expiryWall,
            monotonic: pairingHandlerMonotonic
                + PairingSessionAuthority.lifetimeMilliseconds
        ),
    ])
    let handler = AgentLocalPairingSessionHandlerV0(
        authority: PairingSessionAuthority(
            committer: NoopPairingCommitterV0()
        ),
        contextSource: StaticAgentLocalPairingContextSourceV0(
            try pairingHandlerContext()
        ),
        timeSource: source,
        pairingIDGenerator: { pairingHandlerID }
    )
    let created = try await handler.create(
        LocalPairingSessionCreateCommandV0(commandID: UUID())
    )
    let dismiss = try LocalPairingSessionDismissCommandV0(
        commandID: UUID(),
        pairingID: created.pairingID
    )

    let receipt = try await handler.dismiss(dismiss)

    #expect(receipt.correlationID == dismiss.commandID)
    #expect(receipt.pairingID == created.pairingID)
    #expect(receipt.completedAtUnixMilliseconds == expiryWall)
}

@Test func expiredPresentationIsClearedBeforeCreatingReplacement() async throws {
    let expiryWall = pairingHandlerCreatedAt
        + PairingSessionAuthority.lifetimeMilliseconds
    let source = SequencedPairingTimeSourceV0([
        try pairingHandlerTime(),
        try pairingHandlerTime(
            wall: expiryWall,
            monotonic: pairingHandlerMonotonic
                + PairingSessionAuthority.lifetimeMilliseconds
        ),
    ])
    let authority = PairingSessionAuthority(committer: NoopPairingCommitterV0())
    let handler = AgentLocalPairingSessionHandlerV0(
        authority: authority,
        contextSource: StaticAgentLocalPairingContextSourceV0(
            try pairingHandlerContext()
        ),
        timeSource: source
    )
    let first = try await handler.create(
        LocalPairingSessionCreateCommandV0(commandID: UUID())
    )
    let second = try await handler.create(
        LocalPairingSessionCreateCommandV0(commandID: UUID())
    )
    #expect(first.pairingID != second.pairingID)
    await #expect(throws: PairingSessionError.expired) {
        _ = try await authority.begin(
            pairingID: first.pairingID,
            clientID: UUID(),
            sessionPublicKeyX963: Data(),
            approvalPublicKeyX963: Data(),
            clientNonce: Data(),
            monotonicNowMilliseconds: pairingHandlerMonotonic
                + PairingSessionAuthority.lifetimeMilliseconds
        )
    }
}

@Test func oversizedQRCodeIsCompensatedWithAuthorityTombstone() async throws {
    let labels = [
        String(repeating: "a", count: 63),
        String(repeating: "b", count: 63),
        String(repeating: "c", count: 63),
    ]
    let endpoints = try (0..<8).map { index in
        try EndpointCandidate(
            kind: .dns,
            value: (labels + [String(repeating: "d", count: 60) + "\(index)"])
                .joined(separator: "."),
            port: UInt16(47_470 + index)
        )
    }
    let context = try pairingHandlerContext(endpoints: endpoints)
    let authority = PairingSessionAuthority(committer: NoopPairingCommitterV0())
    let handler = AgentLocalPairingSessionHandlerV0(
        authority: authority,
        contextSource: StaticAgentLocalPairingContextSourceV0(context),
        timeSource: StaticAgentLocalPairingTimeSourceV0(
            try pairingHandlerTime()
        ),
        pairingIDGenerator: { pairingHandlerID }
    )
    await #expect(throws: AgentLocalPairingSessionErrorV0.qrConstructionFailed) {
        _ = try await handler.create(
            LocalPairingSessionCreateCommandV0(commandID: UUID())
        )
    }
    await #expect(throws: PairingSessionError.alreadyConsumed) {
        _ = try await authority.begin(
            pairingID: pairingHandlerID,
            clientID: UUID(),
            sessionPublicKeyX963: Data(),
            approvalPublicKeyX963: Data(),
            clientNonce: Data(),
            monotonicNowMilliseconds: pairingHandlerMonotonic + 1
        )
    }
}

@Test func invalidAgentOwnedSourcesFailBeforeSessionCreation() async throws {
    let authority = PairingSessionAuthority(committer: NoopPairingCommitterV0())
    let invalidClock = AgentLocalPairingSessionHandlerV0(
        authority: authority,
        contextSource: StaticAgentLocalPairingContextSourceV0(
            try pairingHandlerContext()
        ),
        timeSource: FailingPairingTimeSourceV0()
    )
    await #expect(throws: AgentLocalPairingSessionErrorV0.invalidClock) {
        _ = try await invalidClock.create(
            LocalPairingSessionCreateCommandV0(commandID: UUID())
        )
    }

    let invalidContext = AgentLocalPairingSessionHandlerV0(
        authority: authority,
        contextSource: FailingPairingContextSourceV0(),
        timeSource: StaticAgentLocalPairingTimeSourceV0(
            try pairingHandlerTime()
        )
    )
    await #expect(throws: AgentLocalPairingSessionErrorV0.invalidContext) {
        _ = try await invalidContext.create(
            LocalPairingSessionCreateCommandV0(commandID: UUID())
        )
    }
}

@Test func concurrentMutationIsDeniedWhileAuthorityCreateIsSuspended() async throws {
    let authority = PairingSessionAuthority(committer: NoopPairingCommitterV0())
    let manager = SuspendingPairingManagerV0(authority: authority)
    let handler = AgentLocalPairingSessionHandlerV0(
        authority: manager,
        contextSource: StaticAgentLocalPairingContextSourceV0(
            try pairingHandlerContext()
        ),
        timeSource: StaticAgentLocalPairingTimeSourceV0(
            try pairingHandlerTime()
        ),
        pairingIDGenerator: { pairingHandlerID }
    )
    let first = Task {
        try await handler.create(
            LocalPairingSessionCreateCommandV0(commandID: UUID())
        )
    }
    await manager.waitUntilStarted()
    await #expect(throws: AgentLocalPairingSessionErrorV0.busy) {
        _ = try await handler.create(
            LocalPairingSessionCreateCommandV0(commandID: UUID())
        )
    }
    await manager.resume()
    #expect(try await first.value.pairingID == pairingHandlerID)
}

@Test func terminalNetworkLossWinsSuspendedCreateAndCompensatesSecret() async throws {
    let authority = PairingSessionAuthority(committer: NoopPairingCommitterV0())
    let manager = SuspendingPairingManagerV0(authority: authority)
    let handler = AgentLocalPairingSessionHandlerV0(
        authority: manager,
        contextSource: StaticAgentLocalPairingContextSourceV0(
            try pairingHandlerContext()
        ),
        timeSource: StaticAgentLocalPairingTimeSourceV0(
            try pairingHandlerTime()
        ),
        pairingIDGenerator: { pairingHandlerID }
    )
    let create = Task {
        try await handler.create(
            LocalPairingSessionCreateCommandV0(commandID: UUID())
        )
    }
    await manager.waitUntilStarted()
    try await handler.invalidateForNetworkLoss(
        monotonicNowMilliseconds: UInt64(pairingHandlerMonotonic + 1),
        terminal: true
    )
    await manager.resume()

    await #expect(throws: AgentLocalPairingSessionErrorV0.invalidContext) {
        _ = try await create.value
    }
    await #expect(throws: PairingSessionError.alreadyConsumed) {
        _ = try await authority.begin(
            pairingID: pairingHandlerID,
            clientID: UUID(),
            sessionPublicKeyX963: Data(),
            approvalPublicKeyX963: Data(),
            clientNonce: Data(),
            monotonicNowMilliseconds: pairingHandlerMonotonic + 2
        )
    }
    await #expect(throws: AgentLocalPairingSessionErrorV0.invalidContext) {
        _ = try await handler.create(
            LocalPairingSessionCreateCommandV0(commandID: UUID())
        )
    }
}

@Test func menuLossTombstonesVisibleQRAndPermitsFreshPresentation() async throws {
    let authority = PairingSessionAuthority(committer: NoopPairingCommitterV0())
    let handler = AgentLocalPairingSessionHandlerV0(authority: authority,
        contextSource: StaticAgentLocalPairingContextSourceV0(try pairingHandlerContext()),
        timeSource: StaticAgentLocalPairingTimeSourceV0(try pairingHandlerTime()))
    let command = try LocalPairingSessionCreateCommandV0(commandID: UUID())
    let first = try await handler.create(command)
    try await handler.invalidateForPresentationLoss()
    await #expect(throws: AgentLocalPairingSessionErrorV0.staleCommand) {
        _ = try await handler.create(command)
    }
    await #expect(throws: PairingSessionError.alreadyConsumed) {
        _ = try await authority.begin(pairingID: first.pairingID, clientID: UUID(),
            sessionPublicKeyX963: Data(), approvalPublicKeyX963: Data(), clientNonce: Data(),
            monotonicNowMilliseconds: pairingHandlerMonotonic + 1)
    }
    let replacement = try await handler.create(.init(commandID: UUID()))
    #expect(replacement.pairingID != first.pairingID)
    #expect(replacement.encodedQRCode != first.encodedQRCode)
}

@Test(arguments: [true, false])
func nonterminalLossFencesSuspendedQRCreation(menuLoss: Bool) async throws {
    let authority = PairingSessionAuthority(committer: NoopPairingCommitterV0())
    let manager = SuspendingPairingManagerV0(authority: authority)
    let handler = AgentLocalPairingSessionHandlerV0(authority: manager,
        contextSource: StaticAgentLocalPairingContextSourceV0(try pairingHandlerContext()),
        timeSource: StaticAgentLocalPairingTimeSourceV0(try pairingHandlerTime()),
        pairingIDGenerator: { pairingHandlerID })
    let create = Task { try await handler.create(.init(commandID: UUID())) }
    await manager.waitUntilStarted()
    if menuLoss { try await handler.invalidateForPresentationLoss() }
    else {
        try await handler.invalidateForNetworkLoss(
            monotonicNowMilliseconds: UInt64(pairingHandlerMonotonic), terminal: false)
    }
    await manager.resume()
    await #expect(throws: AgentLocalPairingSessionErrorV0.invalidContext) { _ = try await create.value }
    await #expect(throws: PairingSessionError.alreadyConsumed) {
        _ = try await authority.begin(pairingID: pairingHandlerID, clientID: UUID(),
            sessionPublicKeyX963: Data(), approvalPublicKeyX963: Data(), clientNonce: Data(),
            monotonicNowMilliseconds: pairingHandlerMonotonic + 1)
    }
}

private actor RetirementFailurePairingManagerV0: AgentLocalPairingSessionManagingV0 {
    let authority = PairingSessionAuthority(committer: NoopPairingCommitterV0())
    func createLocalPairingSession(pairingID: UUID, hostFingerprint: Data,
        wallNowUnixMilliseconds: Int64, monotonicNowMilliseconds: Int64) async throws -> PairingAdvertisement {
        try await authority.createSession(pairingID: pairingID, hostFingerprint: hostFingerprint,
            wallNowUnixMilliseconds: wallNowUnixMilliseconds, monotonicNowMilliseconds: monotonicNowMilliseconds)
    }
    func cancelLocalPairingSession(pairingID: UUID, monotonicNowMilliseconds: Int64) throws {
        throw AgentLocalPairingSessionErrorV0.authorityUnavailable
    }
}

@Test func unexpectedMenuRetirementFailureDisablesQRCreation() async throws {
    let handler = AgentLocalPairingSessionHandlerV0(authority: RetirementFailurePairingManagerV0(),
        contextSource: StaticAgentLocalPairingContextSourceV0(try pairingHandlerContext()),
        timeSource: StaticAgentLocalPairingTimeSourceV0(try pairingHandlerTime()))
    let command = try LocalPairingSessionCreateCommandV0(commandID: UUID())
    _ = try await handler.create(command)
    await #expect(throws: AgentLocalPairingSessionErrorV0.authorityUnavailable) {
        try await handler.invalidateForPresentationLoss()
    }
    await #expect(throws: AgentLocalPairingSessionErrorV0.invalidContext) { _ = try await handler.create(command) }
    await #expect(throws: AgentLocalPairingSessionErrorV0.invalidContext) {
        _ = try await handler.create(.init(commandID: UUID()))
    }
}

@Test func invalidClockDuringMenuLossDisablesQRCreation() async throws {
    let handler = AgentLocalPairingSessionHandlerV0(
        authority: PairingSessionAuthority(committer: NoopPairingCommitterV0()),
        contextSource: StaticAgentLocalPairingContextSourceV0(try pairingHandlerContext()),
        timeSource: SequencedPairingTimeSourceV0([try pairingHandlerTime()]))
    let command = try LocalPairingSessionCreateCommandV0(commandID: UUID())
    _ = try await handler.create(command)
    await #expect(throws: AgentLocalPairingSessionErrorV0.invalidClock) { try await handler.invalidateForPresentationLoss() }
    await #expect(throws: AgentLocalPairingSessionErrorV0.invalidContext) { _ = try await handler.create(command) }
}
