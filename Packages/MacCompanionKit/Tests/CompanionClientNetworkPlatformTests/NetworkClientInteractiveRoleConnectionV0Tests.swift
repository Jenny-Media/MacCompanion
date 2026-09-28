@testable import CompanionClient
@testable import CompanionClientNetworkPlatform
import CompanionDiscovery
import CompanionDomain
@testable import CompanionInteractiveClient
import CompanionInteractiveWire
import CompanionWire
import Foundation
import Testing

private final class RoleConnectionCancellationRecorder:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var values: [InteractiveChannelRoleName] = []

    func record(_ role: InteractiveChannelRoleName) {
        lock.lock()
        values.append(role)
        lock.unlock()
    }

    func snapshot() -> [InteractiveChannelRoleName] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

private final class RoleConnectionCurrentBox: @unchecked Sendable {
    private let lock = NSLock()
    private var valueStorage = true

    func value() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return valueStorage
    }

    func replace() {
        lock.lock()
        valueStorage = false
        lock.unlock()
    }
}

private final class RoleProductProgressRecorder: @unchecked Sendable {
    struct Value: Equatable {
        let connectionID: Data
        let interactiveSessionID: UUID
        let progress: NetworkClientInteractiveProductProgressV0
    }

    private let lock = NSLock()
    private var valuesStorage: [Value] = []

    func record(
        connectionID: Data,
        interactiveSessionID: UUID,
        progress: NetworkClientInteractiveProductProgressV0
    ) {
        lock.lock()
        valuesStorage.append(Value(
            connectionID: connectionID,
            interactiveSessionID: interactiveSessionID,
            progress: progress
        ))
        lock.unlock()
    }

    func values() -> [Value] {
        lock.lock()
        defer { lock.unlock() }
        return valuesStorage
    }
}

private final class TestInteractiveRoleConnector:
    NetworkClientInteractiveRoleConnectingV0, @unchecked Sendable
{
    struct Call: Equatable {
        let endpoint: EndpointCandidate
        let role: InteractiveChannelRoleName
    }

    private let lock = NSLock()
    private var callsStorage: [Call] = []
    private let failingRole: InteractiveChannelRoleName?
    private let replaceAfterCalls: Int?
    private let current: RoleConnectionCurrentBox
    let cancellations = RoleConnectionCancellationRecorder()

    init(
        failingRole: InteractiveChannelRoleName? = nil,
        replaceAfterCalls: Int? = nil,
        current: RoleConnectionCurrentBox
    ) {
        self.failingRole = failingRole
        self.replaceAfterCalls = replaceAfterCalls
        self.current = current
    }

    func connect(
        endpoint: EndpointCandidate,
        session: ClientInteractiveAcceptedSessionV0,
        role: InteractiveChannelRoleName
    ) async throws -> NetworkClientInteractiveReadyRoleConnectionV0 {
        let count = record(Call(endpoint: endpoint, role: role))
        if count == replaceAfterCalls { current.replace() }
        if role == failingRole {
            throw NetworkClientInteractiveRoleConnectionErrorV0
                .handshakeFailed
        }
        let channelID = role == .input
            ? session.inputChannel.channelID : session.mediaChannel.channelID
        let cancellations = self.cancellations
        return NetworkClientInteractiveReadyRoleConnectionV0(
            endpoint: endpoint,
            role: role,
            channelID: channelID,
            cancel: { cancellations.record(role) }
        )
    }

    func calls() -> [Call] {
        lock.lock()
        defer { lock.unlock() }
        return callsStorage
    }

    private func record(_ call: Call) -> Int {
        lock.lock()
        defer { lock.unlock() }
        callsStorage.append(call)
        return callsStorage.count
    }
}

private func roleConnectionComposition() throws
    -> NetworkClientInteractiveRoleCompositionV0
{
    let clientID = UUID()
    let hostID = UUID()
    let connectionID = Data(repeating: 0x41, count: 16)
    let epoch = AuthorizationEpoch(rawValue: 4)
    let authenticated = ClientAuthenticatedSessionV0(
        clientID: clientID,
        hostID: hostID,
        deviceID: UUID(),
        connectionID: connectionID,
        deviceState: .activeGranted,
        authorizationEpoch: epoch,
        grantRevision: GrantRevision(rawValue: 5),
        policyRevision: PolicyRevision(rawValue: 6),
        hostState: .userSessionActive,
        features: [],
        serverTimeUnixMilliseconds: 1_000
    )
    let primary = try ClientInteractivePrimaryBindingV0(
        hostID: hostID,
        hostFingerprint: Data(repeating: 0x22, count: 32),
        clientID: clientID,
        primaryConnectionID: connectionID,
        authorizationEpoch: epoch,
        grantRevision: GrantRevision(rawValue: 5),
        policyRevision: PolicyRevision(rawValue: 6)
    )
    let input = try InteractiveChannelOffer(
        channelID: WireUUID(UUID()),
        role: .input,
        credential: WireBytes32(Data(repeating: 0x31, count: 32)),
        issuedAtUnixMilliseconds: 1_000,
        expiresAtUnixMilliseconds: 31_000
    )
    let media = try InteractiveChannelOffer(
        channelID: WireUUID(UUID()),
        role: .media,
        credential: WireBytes32(Data(repeating: 0x32, count: 32)),
        issuedAtUnixMilliseconds: 1_000,
        expiresAtUnixMilliseconds: 31_000
    )
    let interactive = ClientInteractiveAcceptedSessionV0(
        primary: primary,
        interactiveSessionID: UUID(),
        authorizationEpoch: epoch,
        expiresAtUnixMilliseconds: 61_000,
        inputChannel: input,
        mediaChannel: media
    )
    return NetworkClientInteractiveRoleCompositionV0(
        endpoint: try EndpointCandidate(
            kind: .ipv4,
            value: "192.168.1.20",
            port: 47_474
        ),
        authenticatedSession: authenticated,
        interactiveSession: interactive
    )
}

@Test func interactiveRolePairUsesOneExactEndpointAndExactTermination()
    async throws
{
    let composition = try roleConnectionComposition()
    let current = RoleConnectionCurrentBox()
    let connector = TestInteractiveRoleConnector(current: current)
    let owner = NetworkClientInteractiveRolePairOwnerV0(
        composition: composition,
        connector: connector,
        isCurrent: { hostID, connectionID in
            current.value()
                && hostID == composition.authenticatedSession.hostID
                && connectionID
                    == composition.authenticatedSession.connectionID
        }
    )
    let pair = try await owner.connect()
    #expect(await owner.phase == .ready)
    #expect(pair.endpoint == composition.endpoint)
    #expect(Set(connector.calls().map(\.endpoint)) == [composition.endpoint])
    #expect(Set(connector.calls().map(\.role)) == [.input, .media])

    await owner.primaryTerminated(
        hostID: composition.authenticatedSession.hostID,
        connectionID: Data(repeating: 0xff, count: 16)
    )
    #expect(await owner.phase == .ready)
    #expect(connector.cancellations.snapshot().isEmpty)

    await owner.primaryTerminated(
        hostID: composition.authenticatedSession.hostID,
        connectionID: composition.authenticatedSession.connectionID
    )
    #expect(await owner.phase == .closed)
    #expect(Set(connector.cancellations.snapshot()) == [.input, .media])
}

@Test func interactiveRolePairClosesReadySiblingOnRoleFailure() async throws {
    let composition = try roleConnectionComposition()
    let current = RoleConnectionCurrentBox()
    let connector = TestInteractiveRoleConnector(
        failingRole: .media,
        current: current
    )
    let owner = NetworkClientInteractiveRolePairOwnerV0(
        composition: composition,
        connector: connector,
        isCurrent: { _, _ in current.value() }
    )
    await #expect(
        throws: NetworkClientInteractiveRoleConnectionErrorV0.rolePairFailed
    ) {
        _ = try await owner.connect()
    }
    #expect(await owner.phase == .closed)
    #expect(connector.cancellations.snapshot() == [.input])
}

@Test func interactiveRolePairRevalidatesPrimaryAfterBothProofs() async throws {
    let composition = try roleConnectionComposition()
    let current = RoleConnectionCurrentBox()
    let connector = TestInteractiveRoleConnector(
        replaceAfterCalls: 2,
        current: current
    )
    let owner = NetworkClientInteractiveRolePairOwnerV0(
        composition: composition,
        connector: connector,
        isCurrent: { _, _ in current.value() }
    )
    await #expect(
        throws: NetworkClientInteractiveRoleConnectionErrorV0.primaryReplaced
    ) {
        _ = try await owner.connect()
    }
    #expect(await owner.phase == .closed)
    #expect(Set(connector.cancellations.snapshot()) == [.input, .media])
}

private actor TestInteractiveRolePairOwner:
    NetworkClientInteractiveRolePairOwningV0
{
    enum Mode { case succeeds, fails, suspends }

    private let mode: Mode
    private let composition: NetworkClientInteractiveRoleCompositionV0
    private var continuation: CheckedContinuation<
        NetworkClientInteractiveReadyRolePairV0, any Error
    >?
    private(set) var terminationCount = 0
    private(set) var closeCount = 0

    init(
        mode: Mode,
        composition: NetworkClientInteractiveRoleCompositionV0
    ) {
        self.mode = mode
        self.composition = composition
    }

    func connect() async throws -> NetworkClientInteractiveReadyRolePairV0 {
        switch mode {
        case .succeeds: return readyPair()
        case .fails:
            throw NetworkClientInteractiveRoleConnectionErrorV0.rolePairFailed
        case .suspends:
            return try await withCheckedThrowingContinuation {
                continuation = $0
            }
        }
    }

    func primaryTerminated(hostID: UUID, connectionID: Data) async {
        terminationCount += 1
        failSuspended()
    }

    func close() async {
        closeCount += 1
        failSuspended()
    }

    private func readyPair() -> NetworkClientInteractiveReadyRolePairV0 {
        NetworkClientInteractiveReadyRolePairV0(
            endpoint: composition.endpoint,
            input: NetworkClientInteractiveReadyRoleConnectionV0(
                endpoint: composition.endpoint,
                role: .input,
                channelID:
                    composition.interactiveSession.inputChannel.channelID,
                cancel: {}
            ),
            media: NetworkClientInteractiveReadyRoleConnectionV0(
                endpoint: composition.endpoint,
                role: .media,
                channelID:
                    composition.interactiveSession.mediaChannel.channelID,
                cancel: {}
            )
        )
    }

    private func failSuspended() {
        continuation?.resume(
            throwing:
                NetworkClientInteractiveRoleConnectionErrorV0.primaryReplaced
        )
        continuation = nil
    }
}

private func waitForRoleProductState(
    _ binding: NetworkClientInteractiveRoleProductBindingV0,
    _ expected: NetworkClientInteractiveRoleProductStateV0
) async -> Bool {
    for _ in 0..<1_000 {
        if await binding.state == expected { return true }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    return false
}

@Test func roleProductBindingPublishesReadyOnlyAfterPairSuccess() async throws {
    let composition = try roleConnectionComposition()
    let pair = TestInteractiveRolePairOwner(
        mode: .succeeds,
        composition: composition
    )
    let progress = RoleProductProgressRecorder()
    let binding = NetworkClientInteractiveRoleProductBindingV0(
        hostID: composition.authenticatedSession.hostID,
        pairFactory: { pair },
        progressPublisher: { connectionID, sessionID, value in
            progress.record(
                connectionID: connectionID,
                interactiveSessionID: sessionID,
                progress: value
            )
        }
    )
    binding.productEvents.publishControl(NetworkClientControlPublicationV0(
        hostID: composition.authenticatedSession.hostID,
        connectionID: composition.authenticatedSession.connectionID,
        event: .accepted(
            session: composition.interactiveSession,
            effects: [.view]
        )
    ))
    #expect(await waitForRoleProductState(
        binding,
        .roleChannelsReady(interactiveSessionID:
            composition.interactiveSession.interactiveSessionID)
    ))
    #expect(await pair.closeCount == 0)
    #expect(progress.values() == [
        .init(
            connectionID: composition.authenticatedSession.connectionID,
            interactiveSessionID:
                composition.interactiveSession.interactiveSessionID,
            progress: .roleChannelsConnecting
        ),
        .init(
            connectionID: composition.authenticatedSession.connectionID,
            interactiveSessionID:
                composition.interactiveSession.interactiveSessionID,
            progress: .roleChannelsReady
        ),
    ])

    binding.productEvents.publishControl(NetworkClientControlPublicationV0(
        hostID: composition.authenticatedSession.hostID,
        connectionID: composition.authenticatedSession.connectionID,
        event: .endSubmitted(
            interactiveSessionID:
                composition.interactiveSession.interactiveSessionID,
            effects: [.view]
        )
    ))
    #expect(await waitForRoleProductState(
        binding,
        .ending(interactiveSessionID:
            composition.interactiveSession.interactiveSessionID)
    ))
    #expect(await pair.closeCount == 0)
    binding.productEvents.publishControl(NetworkClientControlPublicationV0(
        hostID: composition.authenticatedSession.hostID,
        connectionID: composition.authenticatedSession.connectionID,
        event: .ended(
            interactiveSessionID:
                composition.interactiveSession.interactiveSessionID,
            endedAtUnixMilliseconds: 2_000
        )
    ))
    #expect(await waitForRoleProductState(binding, .inactive))
    #expect(await pair.closeCount == 1)
}

@Test func roleProductBindingTerminationWinsSuspendedActivation() async throws {
    let composition = try roleConnectionComposition()
    let pair = TestInteractiveRolePairOwner(
        mode: .suspends,
        composition: composition
    )
    let binding = NetworkClientInteractiveRoleProductBindingV0(
        hostID: composition.authenticatedSession.hostID,
        pairFactory: { pair }
    )
    binding.productEvents.publishControl(NetworkClientControlPublicationV0(
        hostID: composition.authenticatedSession.hostID,
        connectionID: composition.authenticatedSession.connectionID,
        event: .accepted(
            session: composition.interactiveSession,
            effects: [.view]
        )
    ))
    #expect(await waitForRoleProductState(
        binding,
        .connecting(interactiveSessionID:
            composition.interactiveSession.interactiveSessionID)
    ))
    binding.productEvents.primaryTerminated(
        composition.authenticatedSession.hostID,
        composition.authenticatedSession.connectionID
    )
    #expect(await waitForRoleProductState(binding, .inactive))
    #expect(await pair.terminationCount == 1)
    #expect(await pair.closeCount == 0)
    try? await Task.sleep(nanoseconds: 2_000_000)
    #expect(await binding.state == .inactive)
}

@Test func transientPrimaryInterruptionPreservesRolesUntilPrimaryTerminates()
    async throws
{
    let composition = try roleConnectionComposition()
    let pair = TestInteractiveRolePairOwner(
        mode: .succeeds,
        composition: composition
    )
    let binding = NetworkClientInteractiveRoleProductBindingV0(
        hostID: composition.authenticatedSession.hostID,
        pairFactory: { pair }
    )
    binding.productEvents.publishControl(NetworkClientControlPublicationV0(
        hostID: composition.authenticatedSession.hostID,
        connectionID: composition.authenticatedSession.connectionID,
        event: .accepted(
            session: composition.interactiveSession,
            effects: [.view]
        )
    ))
    #expect(await waitForRoleProductState(
        binding,
        .roleChannelsReady(interactiveSessionID:
            composition.interactiveSession.interactiveSessionID)
    ))

    binding.productEvents.primaryTransportInterrupted(
        composition.authenticatedSession.hostID,
        composition.authenticatedSession.connectionID
    )
    try? await Task.sleep(nanoseconds: 2_000_000)
    #expect(await binding.state == .roleChannelsReady(
        interactiveSessionID:
            composition.interactiveSession.interactiveSessionID
    ))
    #expect(await pair.closeCount == 0)
    #expect(await pair.terminationCount == 0)

    binding.productEvents.primaryTransportRecovered(
        composition.authenticatedSession.hostID,
        composition.authenticatedSession.connectionID
    )
    try? await Task.sleep(nanoseconds: 2_000_000)
    #expect(await binding.state == .roleChannelsReady(
        interactiveSessionID:
            composition.interactiveSession.interactiveSessionID
    ))

    binding.productEvents.primaryTerminated(
        composition.authenticatedSession.hostID,
        composition.authenticatedSession.connectionID
    )
    #expect(await waitForRoleProductState(binding, .inactive))
    #expect(await pair.terminationCount == 1)
}

@Test func roleProductBindingFailurePublishesNoReadyState() async throws {
    let composition = try roleConnectionComposition()
    let pair = TestInteractiveRolePairOwner(
        mode: .fails,
        composition: composition
    )
    let progress = RoleProductProgressRecorder()
    let binding = NetworkClientInteractiveRoleProductBindingV0(
        hostID: composition.authenticatedSession.hostID,
        pairFactory: { pair },
        progressPublisher: { connectionID, sessionID, value in
            progress.record(
                connectionID: connectionID,
                interactiveSessionID: sessionID,
                progress: value
            )
        }
    )
    binding.productEvents.publishControl(NetworkClientControlPublicationV0(
        hostID: composition.authenticatedSession.hostID,
        connectionID: composition.authenticatedSession.connectionID,
        event: .accepted(
            session: composition.interactiveSession,
            effects: [.view]
        )
    ))
    #expect(await waitForRoleProductState(
        binding,
        .failed(interactiveSessionID:
            composition.interactiveSession.interactiveSessionID)
    ))
    #expect(await pair.closeCount == 1)
    #expect(progress.values().map(\.progress) == [
        .roleChannelsConnecting,
        .failed(.roleChannelsConnecting),
    ])
}
