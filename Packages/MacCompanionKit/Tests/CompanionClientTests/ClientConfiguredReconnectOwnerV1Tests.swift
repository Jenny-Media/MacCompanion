@testable import CompanionClient
import CompanionDiscovery
import CompanionDomain
import CompanionTransport
import CompanionWire
import CryptoKit
import Foundation
import Testing

private final class ConfiguredRouteBindingClockV1: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Int64

    init(_ value: Int64) {
        storage = value
    }

    var value: Int64 {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}

private actor ConfiguredReconnectAttemptRecorderV1: DialRouteAttemptingV0 {
    private(set) var attempts: [EndpointCandidate] = []
    private(set) var closes: [EndpointCandidate] = []

    func attempt(
        _ attempt: DialAttempt,
        roundID: UUID,
        requiredHostFingerprint: Data
    ) async -> DialRouteAttemptOutcomeV0 {
        attempts.append(attempt.endpoint)
        return .authenticated(AuthenticatedDialRouteV0(
            endpoint: attempt.endpoint,
            close: { [weak self] in
                await self?.recordClose(attempt.endpoint)
            }
        ))
    }

    private func recordClose(_ endpoint: EndpointCandidate) {
        closes.append(endpoint)
    }
}

private enum ConfiguredRouteIdentityInventoryErrorV1: Error, Equatable {
    case unreadable
}

private actor ConfiguredRouteIdentityInventoryV1:
    ClientPairedHostInventoryV1
{
    private var value: ClientDurablePairedHostV0?
    private var unreadable = false

    init(_ value: ClientDurablePairedHostV0?) {
        self.value = value
    }

    func pairedHost(
        hostID: UUID
    ) throws -> ClientDurablePairedHostV0? {
        if unreadable {
            throw ConfiguredRouteIdentityInventoryErrorV1.unreadable
        }
        return value?.hostID == hostID ? value : nil
    }

    func replace(_ value: ClientDurablePairedHostV0?) {
        self.value = value
    }

    func failReads() {
        unreadable = true
    }
}

private actor ConfiguredRouteSnapshotRecorderV1 {
    private(set) var values: [ClientConfiguredRouteCatalogSnapshotV1] = []

    func record(_ value: ClientConfiguredRouteCatalogSnapshotV1) {
        values.append(value)
    }
}

private actor ConfiguredRoutePublishingLatchV1 {
    private(set) var values: [ClientConfiguredRouteCatalogSnapshotV1] = []
    private var continuation: CheckedContinuation<Void, Never>?
    private var waitingObservers: [CheckedContinuation<Void, Never>] = []

    func publish(_ value: ClientConfiguredRouteCatalogSnapshotV1) async {
        values.append(value)
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            let observers = waitingObservers
            waitingObservers.removeAll()
            for observer in observers { observer.resume() }
        }
    }

    var isWaiting: Bool { continuation != nil }

    func waitUntilWaiting() async {
        if continuation != nil { return }
        await withCheckedContinuation { waitingObservers.append($0) }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private func configuredReconnectPairedHostV1(
    hostID: UUID,
    endpoint: EndpointCandidate
) throws -> ClientDurablePairedHostV0 {
    try configuredReconnectPairedHostWithEndpointsV1(
        hostID: hostID,
        endpoints: [endpoint]
    )
}

private func configuredReconnectPairedHostWithEndpointsV1(
    hostID: UUID,
    endpoints: [EndpointCandidate]
) throws -> ClientDurablePairedHostV0 {
    let pairingID = UUID()
    let clientID = UUID()
    let session = P256.Signing.PrivateKey()
    let approval = P256.Signing.PrivateKey()
    let identity = try ClientPreparedIdentityV0(
        pairingID: pairingID,
        clientID: clientID,
        sessionKey: ClientCustodiedPublicKeyV0(
            role: .session,
            reference: ClientSigningKeyReferenceV0(UUID()),
            publicKeyX963: session.publicKey.x963Representation,
            protection: .afterFirstUnlockThisDeviceOnly
        ),
        approvalKey: ClientCustodiedPublicKeyV0(
            role: .approval,
            reference: ClientSigningKeyReferenceV0(UUID()),
            publicKeyX963: approval.publicKey.x963Representation,
            protection: .whenUnlockedThisDeviceOnlyUserPresence
        )
    )
    return try ClientDurablePairedHostV0(
        host: ClientPairedHostV0(
            pairingID: pairingID,
            clientID: clientID,
            hostID: hostID,
            deviceID: UUID(),
            hostFingerprint: Data(repeating: 0x77, count: 32),
            endpoints: endpoints,
            deviceState: .activeMonitorOnly,
            authorizationEpoch: .init(rawValue: 1),
            grantRevision: .init(rawValue: 1),
            policyRevision: .init(rawValue: 2)
        ),
        identity: identity
    )
}

@Test func configuredRouteBootstrapRequiresExplicitAmbiguousChoices()
    throws
{
    let bonjour = try EndpointCandidate(
        kind: .bonjour,
        value: "studio._maccompanion._tcp.local.",
        port: 47_474
    )
    let privateAddress = try EndpointCandidate(
        kind: .ipv4,
        value: "192.168.1.9",
        port: 47_474
    )
    let dns = try EndpointCandidate(
        kind: .dns,
        value: "studio.example.net",
        port: 443
    )
    let publicAddress = try EndpointCandidate(
        kind: .ipv4,
        value: "203.0.113.9",
        port: 443
    )
    let pairedHost = try configuredReconnectPairedHostWithEndpointsV1(
        hostID: UUID(),
        endpoints: [bonjour, privateAddress, dns, publicAddress]
    )
    let plan = ClientConfiguredRouteBootstrapPlanV1(
        pairedHost: pairedHost
    )
    #expect(plan.entries.map(\.automaticProvenance) == [
        .localDiscovery,
        .directPrivateAddress,
        nil,
        nil,
    ])
    #expect(plan.endpointsRequiringExplicitChoice == [dns, publicAddress])
    #expect(throws: ClientConfiguredRouteBootstrapErrorV1.invalidChoices) {
        _ = try plan.complete(
            explicitChoices: [dns: .privateDNS],
            routeID: { _ in
                try WireBytes16(Data(repeating: 1, count: 16))
            }
        )
    }
    #expect(throws: ClientConfiguredRouteCatalogErrorV1.invalidRecord) {
        _ = try plan.complete(
            explicitChoices: [
                dns: .directPrivateAddress,
                publicAddress: .privateNetwork,
            ],
            routeID: { endpoint in
                let index = pairedHost.endpoints.firstIndex(of: endpoint)!
                return try WireBytes16(
                    Data(repeating: UInt8(index + 1), count: 16)
                )
            }
        )
    }

    let completed = try plan.complete(
        explicitChoices: [
            dns: .privateDNS,
            publicAddress: .privateNetwork,
        ],
        routeID: { endpoint in
            let index = pairedHost.endpoints.firstIndex(of: endpoint)!
            return try WireBytes16(
                Data(repeating: UInt8(index + 1), count: 16)
            )
        }
    )
    #expect(completed.revision == 1)
    #expect(completed.catalog.records.map(\.endpoint) == pairedHost.endpoints)
    #expect(completed.catalog.records.map(\.provenance) == [
        .localDiscovery,
        .directPrivateAddress,
        .privateDNS,
        .privateNetwork,
    ])
}

@Test func configuredRouteBootstrapCancelHasNoPublicationAuthority()
    async throws
{
    let endpoint = try EndpointCandidate(
        kind: .dns,
        value: "bootstrap.example.net",
        port: 443
    )
    let pairedHost = try configuredReconnectPairedHostV1(
        hostID: UUID(),
        endpoint: endpoint
    )
    let plan = ClientConfiguredRouteBootstrapPlanV1(
        pairedHost: pairedHost
    )
    let published = ConfiguredRouteSnapshotRecorderV1()
    let authority = ClientConfiguredRouteBootstrapAuthorityV1(
        plan: plan,
        routeID: { _ in
            try WireBytes16(Data(repeating: 0xa1, count: 16))
        },
        publish: { await published.record($0) }
    )

    try await authority.cancel()

    #expect(await authority.phase == .cancelled)
    #expect(await published.values.isEmpty)
    await #expect(throws: ClientConfiguredRouteBootstrapErrorV1.invalidPhase) {
        _ = try await authority.complete(
            explicitChoices: [endpoint: .privateDNS]
        )
    }
    #expect(await published.values.isEmpty)
}

@Test func configuredRouteBootstrapPublishesOnlyACompleteExplicitCatalog()
    async throws
{
    let endpoint = try EndpointCandidate(
        kind: .dns,
        value: "bootstrap.tailnet.ts.net",
        port: 47_474
    )
    let pairedHost = try configuredReconnectPairedHostV1(
        hostID: UUID(),
        endpoint: endpoint
    )
    let published = ConfiguredRouteSnapshotRecorderV1()
    let authority = ClientConfiguredRouteBootstrapAuthorityV1(
        plan: ClientConfiguredRouteBootstrapPlanV1(
            pairedHost: pairedHost
        ),
        routeID: { _ in
            try WireBytes16(Data(repeating: 0xa2, count: 16))
        },
        publish: { await published.record($0) }
    )

    await #expect(throws: ClientConfiguredRouteBootstrapErrorV1.invalidChoices) {
        _ = try await authority.complete(explicitChoices: [:])
    }
    #expect(await authority.phase == .pending)
    #expect(await published.values.isEmpty)

    let snapshot = try await authority.complete(
        explicitChoices: [endpoint: .privateNetwork]
    )
    #expect(snapshot.revision == 1)
    #expect(snapshot.catalog.records.map(\.provenance) == [.privateNetwork])
    #expect(await authority.phase == .published)
    #expect(await published.values == [snapshot])
}

private func configuredReconnectConfigurationV1(
    pairedHost: ClientDurablePairedHostV0,
    revision: UInt64,
    endpoint: EndpointCandidate,
    provenance: ClientConfiguredRouteProvenanceV1
) throws -> ClientReconnectConfigurationV1 {
    try ClientReconnectConfigurationV1(
        pairedHost: pairedHost,
        routeSnapshot: ClientConfiguredRouteCatalogSnapshotV1(
            hostID: pairedHost.hostID,
            revision: revision,
            catalog: ClientConfiguredRouteCatalogV1(records: [
                ClientConfiguredRouteRecordV1(
                    configuredRouteID: WireBytes16(
                        Data(repeating: UInt8(revision), count: 16)
                    ),
                    endpoint: endpoint,
                    provenance: provenance
                ),
            ])
        )
    )
}

private func waitForConfiguredReconnectPhaseV1(
    _ owner: ClientConfiguredReconnectOwnerV1,
    _ expected: ReconnectPhase
) async -> Bool {
    for _ in 0..<2_000 {
        if await owner.snapshot().reconnect.phase == expected { return true }
        await Task.yield()
    }
    return false
}

@Test func configuredReconnectReplacementRetiresExactOldController()
    async throws
{
    let routeA = try EndpointCandidate(
        kind: .ipv4,
        value: "10.0.0.4",
        port: 47_474
    )
    let routeB = try EndpointCandidate(
        kind: .dns,
        value: "mac.tailnet.ts.net",
        port: 47_474
    )
    let pairedHost = try configuredReconnectPairedHostV1(
        hostID: UUID(),
        endpoint: routeA
    )
    let first = try configuredReconnectConfigurationV1(
        pairedHost: pairedHost,
        revision: 1,
        endpoint: routeA,
        provenance: .directPrivateAddress
    )
    let second = try configuredReconnectConfigurationV1(
        pairedHost: pairedHost,
        revision: 2,
        endpoint: routeB,
        provenance: .privateNetwork
    )
    let attempts = ConfiguredReconnectAttemptRecorderV1()
    let owner = try await ClientConfiguredReconnectOwnerV1(
        configuration: first,
        foreground: true,
        networkReachable: true,
        makeController: { configuration, foreground, reachable in
            ReconnectControllerV0(
                state: try configuration.makeReconnectState(
                    foreground: foreground,
                    networkReachable: reachable
                ),
                executor: DialRoundExecutorV0(
                    attempter: attempts,
                    wait: { _ in }
                ),
                monotonicNow: { 1_000 },
                jitterBasisPoints: { 10_000 }
            )
        }
    )

    try await owner.startRound(
        roundID: UUID(),
        monotonicNowMilliseconds: 100
    )
    #expect(await waitForConfiguredReconnectPhaseV1(
        owner,
        .connected(routeA)
    ))

    try await owner.replaceConfiguration(second)
    let replaced = await owner.snapshot()
    #expect(replaced.configurationRevision == 2)
    #expect(replaced.reconnect.phase == .ready)
    #expect(replaced.reconnect.candidates == [routeB])
    #expect(await attempts.closes == [routeA])

    await #expect(throws: ClientConfiguredReconnectErrorV1.staleRevision) {
        try await owner.replaceConfiguration(first)
    }
    try await owner.startRound(
        roundID: UUID(),
        monotonicNowMilliseconds: 101
    )
    #expect(await waitForConfiguredReconnectPhaseV1(
        owner,
        .connected(routeB)
    ))
    try await owner.close()
    try await owner.close()
    #expect(await attempts.closes == [routeA, routeB])
    #expect(await owner.snapshot().isClosed)
}

@Test func configuredReconnectRejectsMixedIdentityAndControllerInputs()
    async throws
{
    let route = try EndpointCandidate(
        kind: .ipv4,
        value: "10.0.0.5",
        port: 47_474
    )
    let pairedHost = try configuredReconnectPairedHostV1(
        hostID: UUID(),
        endpoint: route
    )
    let configuration = try configuredReconnectConfigurationV1(
        pairedHost: pairedHost,
        revision: 1,
        endpoint: route,
        provenance: .directPrivateAddress
    )
    let wrongHostSnapshot = try ClientConfiguredRouteCatalogSnapshotV1(
        hostID: UUID(),
        revision: 1,
        catalog: configuration.catalog
    )
    #expect(throws: ClientConfiguredReconnectErrorV1.identityMismatch) {
        _ = try ClientReconnectConfigurationV1(
            pairedHost: pairedHost,
            routeSnapshot: wrongHostSnapshot
        )
    }

    let attempts = ConfiguredReconnectAttemptRecorderV1()
    await #expect(throws: ClientConfiguredReconnectErrorV1.invalidController) {
        _ = try await ClientConfiguredReconnectOwnerV1(
            configuration: configuration,
            foreground: true,
            networkReachable: true,
            makeController: { _, foreground, reachable in
                let wrong = try EndpointCandidate(
                    kind: .ipv4,
                    value: "10.0.0.99",
                    port: 47_474
                )
                return ReconnectControllerV0(
                    state: try ReconnectStateMachine(
                        candidates: [wrong],
                        requiredHostFingerprint: pairedHost.hostFingerprint,
                        foreground: foreground,
                        networkReachable: reachable
                    ),
                    executor: DialRoundExecutorV0(
                        attempter: attempts,
                        wait: { _ in }
                    ),
                    monotonicNow: { 1_000 },
                    jitterBasisPoints: { 10_000 }
                )
            }
        )
    }
}

private func configuredReconnectControllerFactoryV1(
    attempts: ConfiguredReconnectAttemptRecorderV1,
    invalidateRevision: UInt64? = nil
) -> ClientConfiguredReconnectOwnerV1.ControllerFactory {
    { configuration, foreground, reachable in
        let state: ReconnectStateMachine
        if configuration.revision == invalidateRevision {
            state = try ReconnectStateMachine(
                candidates: [EndpointCandidate(
                    kind: .ipv4,
                    value: "10.0.0.99",
                    port: 47_474
                )],
                requiredHostFingerprint:
                    configuration.pairedHost.hostFingerprint,
                foreground: foreground,
                networkReachable: reachable
            )
        } else {
            state = try configuration.makeReconnectState(
                foreground: foreground,
                networkReachable: reachable
            )
        }
        return ReconnectControllerV0(
            state: state,
            executor: DialRoundExecutorV0(
                attempter: attempts,
                wait: { _ in }
            ),
            monotonicNow: { 1_000 },
            jitterBasisPoints: { 10_000 }
        )
    }
}

@Test func configuredRouteUpdateCommitsThenRetiresOldRuntime() async throws {
    let routeA = try EndpointCandidate(
        kind: .ipv4,
        value: "10.0.0.6",
        port: 47_474
    )
    let routeB = try EndpointCandidate(
        kind: .dns,
        value: "mac.tailnet.ts.net",
        port: 47_474
    )
    let pairedHost = try configuredReconnectPairedHostV1(
        hostID: UUID(),
        endpoint: routeA
    )
    let initial = try configuredReconnectConfigurationV1(
        pairedHost: pairedHost,
        revision: 1,
        endpoint: routeA,
        provenance: .directPrivateAddress
    )
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-route-update-\(UUID())",
        isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try AtomicFileClientConfiguredRouteStoreV1(directory: root)
    _ = try await store.replaceAtomically(
        initial.routeSnapshot,
        expectedRevision: nil
    )
    let attempts = ConfiguredReconnectAttemptRecorderV1()
    let owner = try await ClientConfiguredReconnectOwnerV1(
        configuration: initial,
        foreground: true,
        networkReachable: true,
        makeController: configuredReconnectControllerFactoryV1(
            attempts: attempts
        )
    )
    try await owner.startRound(
        roundID: UUID(),
        monotonicNowMilliseconds: 100
    )
    #expect(await waitForConfiguredReconnectPhaseV1(
        owner,
        .connected(routeA)
    ))
    let newID = try WireBytes16(Data(repeating: 0xdd, count: 16))
    let service = try await ClientConfiguredRouteUpdateServiceV1(
        pairedHost: pairedHost,
        persistence: store,
        reconnectOwner: owner,
        newRouteID: { newID }
    )

    let updated = try await service.apply(.add(
        endpoint: routeB,
        provenance: .privateNetwork
    ))

    #expect(updated.revision == 2)
    #expect(updated.catalog.records.map(\.endpoint) == [routeA, routeB])
    #expect(try await store.snapshot(hostID: pairedHost.hostID) == updated)
    let runtime = await owner.snapshot()
    #expect(runtime.configurationRevision == 2)
    #expect(runtime.reconnect.candidates == [routeA, routeB])
    #expect(await attempts.closes == [routeA])
}

@Test func configuredRouteUpdateClosesRuntimeAfterActivationFailure()
    async throws
{
    let routeA = try EndpointCandidate(
        kind: .ipv4,
        value: "10.0.0.7",
        port: 47_474
    )
    let routeB = try EndpointCandidate(
        kind: .dns,
        value: "mac.example.net",
        port: 443
    )
    let pairedHost = try configuredReconnectPairedHostV1(
        hostID: UUID(),
        endpoint: routeA
    )
    let initial = try configuredReconnectConfigurationV1(
        pairedHost: pairedHost,
        revision: 1,
        endpoint: routeA,
        provenance: .directPrivateAddress
    )
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-route-runtime-failure-\(UUID())",
        isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try AtomicFileClientConfiguredRouteStoreV1(directory: root)
    _ = try await store.replaceAtomically(
        initial.routeSnapshot,
        expectedRevision: nil
    )
    let attempts = ConfiguredReconnectAttemptRecorderV1()
    let owner = try await ClientConfiguredReconnectOwnerV1(
        configuration: initial,
        foreground: true,
        networkReachable: true,
        makeController: configuredReconnectControllerFactoryV1(
            attempts: attempts,
            invalidateRevision: 2
        )
    )
    try await owner.startRound(
        roundID: UUID(),
        monotonicNowMilliseconds: 100
    )
    #expect(await waitForConfiguredReconnectPhaseV1(
        owner,
        .connected(routeA)
    ))
    let service = try await ClientConfiguredRouteUpdateServiceV1(
        pairedHost: pairedHost,
        persistence: store,
        reconnectOwner: owner,
        newRouteID: {
            try WireBytes16(Data(repeating: 0xee, count: 16))
        }
    )

    await #expect(
        throws: ClientConfiguredRouteUpdateErrorV1.runtimeOutOfSync
    ) {
        _ = try await service.apply(.add(
            endpoint: routeB,
            provenance: .privateDNS
        ))
    }
    #expect(try await store.snapshot(hostID: pairedHost.hostID)?.revision == 2)
    #expect(await owner.snapshot().isClosed)
    #expect(await attempts.closes == [routeA])
}

@Test func configuredRoutePostRenameFaultClosesStaleRuntime() async throws {
    let routeA = try EndpointCandidate(
        kind: .ipv4,
        value: "10.0.0.8",
        port: 47_474
    )
    let routeB = try EndpointCandidate(
        kind: .dns,
        value: "mac.tailnet.ts.net",
        port: 47_474
    )
    let pairedHost = try configuredReconnectPairedHostV1(
        hostID: UUID(),
        endpoint: routeA
    )
    let initial = try configuredReconnectConfigurationV1(
        pairedHost: pairedHost,
        revision: 1,
        endpoint: routeA,
        provenance: .directPrivateAddress
    )
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-route-post-rename-\(UUID())",
        isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let initialStore = try AtomicFileClientConfiguredRouteStoreV1(
        directory: root
    )
    _ = try await initialStore.replaceAtomically(
        initial.routeSnapshot,
        expectedRevision: nil
    )
    let faultingStore = try AtomicFileClientConfiguredRouteStoreV1(
        directory: root,
        injectedFaults: [.afterRenameBeforeDirectorySync]
    )
    let attempts = ConfiguredReconnectAttemptRecorderV1()
    let owner = try await ClientConfiguredReconnectOwnerV1(
        configuration: initial,
        foreground: true,
        networkReachable: true,
        makeController: configuredReconnectControllerFactoryV1(
            attempts: attempts
        )
    )
    try await owner.startRound(
        roundID: UUID(),
        monotonicNowMilliseconds: 100
    )
    #expect(await waitForConfiguredReconnectPhaseV1(
        owner,
        .connected(routeA)
    ))
    let service = try await ClientConfiguredRouteUpdateServiceV1(
        pairedHost: pairedHost,
        persistence: faultingStore,
        reconnectOwner: owner,
        newRouteID: {
            try WireBytes16(Data(repeating: 0xfa, count: 16))
        }
    )

    await #expect(throws: ClientConfiguredRouteFileStoreErrorV1.injectedFault(
        .afterRenameBeforeDirectorySync
    )) {
        _ = try await service.apply(.add(
            endpoint: routeB,
            provenance: .privateNetwork
        ))
    }
    let restarted = try AtomicFileClientConfiguredRouteStoreV1(directory: root)
    #expect(try await restarted.snapshot(hostID: pairedHost.hostID)?.revision == 2)
    #expect(await owner.snapshot().isClosed)
    #expect(await attempts.closes == [routeA])
}

@Test func configuredRoutePreRenameFaultPreservesExactRuntime() async throws {
    let routeA = try EndpointCandidate(
        kind: .ipv4,
        value: "10.0.0.9",
        port: 47_474
    )
    let routeB = try EndpointCandidate(
        kind: .dns,
        value: "studio.example.net",
        port: 443
    )
    let pairedHost = try configuredReconnectPairedHostV1(
        hostID: UUID(),
        endpoint: routeA
    )
    let initial = try configuredReconnectConfigurationV1(
        pairedHost: pairedHost,
        revision: 1,
        endpoint: routeA,
        provenance: .directPrivateAddress
    )
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-route-pre-rename-\(UUID())",
        isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let initialStore = try AtomicFileClientConfiguredRouteStoreV1(
        directory: root
    )
    _ = try await initialStore.replaceAtomically(
        initial.routeSnapshot,
        expectedRevision: nil
    )
    let faultingStore = try AtomicFileClientConfiguredRouteStoreV1(
        directory: root,
        injectedFaults: [.beforeRename]
    )
    let attempts = ConfiguredReconnectAttemptRecorderV1()
    let owner = try await ClientConfiguredReconnectOwnerV1(
        configuration: initial,
        foreground: true,
        networkReachable: true,
        makeController: configuredReconnectControllerFactoryV1(
            attempts: attempts
        )
    )
    try await owner.startRound(
        roundID: UUID(),
        monotonicNowMilliseconds: 100
    )
    #expect(await waitForConfiguredReconnectPhaseV1(
        owner,
        .connected(routeA)
    ))
    let service = try await ClientConfiguredRouteUpdateServiceV1(
        pairedHost: pairedHost,
        persistence: faultingStore,
        reconnectOwner: owner,
        newRouteID: {
            try WireBytes16(Data(repeating: 0xfb, count: 16))
        }
    )

    await #expect(throws: ClientConfiguredRouteFileStoreErrorV1.injectedFault(
        .beforeRename
    )) {
        _ = try await service.apply(.add(
            endpoint: routeB,
            provenance: .privateDNS
        ))
    }
    #expect(try await initialStore.snapshot(
        hostID: pairedHost.hostID
    )?.revision == 1)
    let runtime = await owner.snapshot()
    #expect(runtime.configurationRevision == 1)
    #expect(runtime.reconnect.phase == .connected(routeA))
    #expect(!runtime.isClosed)
    #expect(await attempts.closes.isEmpty)
}

@Test func configuredRouteReconcileActivatesExternallyPublishedRevision()
    async throws
{
    let routeA = try EndpointCandidate(
        kind: .ipv4,
        value: "10.0.0.10",
        port: 47_474
    )
    let routeB = try EndpointCandidate(
        kind: .dns,
        value: "studio.tailnet.ts.net",
        port: 47_474
    )
    let pairedHost = try configuredReconnectPairedHostV1(
        hostID: UUID(),
        endpoint: routeA
    )
    let initial = try configuredReconnectConfigurationV1(
        pairedHost: pairedHost,
        revision: 1,
        endpoint: routeA,
        provenance: .directPrivateAddress
    )
    let secondRecordID = try WireBytes16(Data(repeating: 0xfc, count: 16))
    let replacement = try ClientConfiguredRouteCatalogSnapshotV1(
        hostID: pairedHost.hostID,
        revision: 2,
        catalog: ClientConfiguredRouteCatalogV1(records: [
            initial.catalog.records[0],
            ClientConfiguredRouteRecordV1(
                configuredRouteID: secondRecordID,
                endpoint: routeB,
                provenance: .privateNetwork
            ),
        ])
    )
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-route-reconcile-\(UUID())",
        isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try AtomicFileClientConfiguredRouteStoreV1(directory: root)
    _ = try await store.replaceAtomically(
        initial.routeSnapshot,
        expectedRevision: nil
    )
    let attempts = ConfiguredReconnectAttemptRecorderV1()
    let owner = try await ClientConfiguredReconnectOwnerV1(
        configuration: initial,
        foreground: true,
        networkReachable: true,
        makeController: configuredReconnectControllerFactoryV1(
            attempts: attempts
        )
    )
    try await owner.startRound(
        roundID: UUID(),
        monotonicNowMilliseconds: 100
    )
    #expect(await waitForConfiguredReconnectPhaseV1(
        owner,
        .connected(routeA)
    ))
    let service = try await ClientConfiguredRouteUpdateServiceV1(
        pairedHost: pairedHost,
        persistence: store,
        reconnectOwner: owner,
        newRouteID: {
            try WireBytes16(Data(repeating: 0xfd, count: 16))
        }
    )
    _ = try await store.replaceAtomically(
        replacement,
        expectedRevision: 1
    )

    try await service.reconcileFromStorage()

    let runtime = await owner.snapshot()
    #expect(runtime.configurationRevision == 2)
    #expect(runtime.reconnect.candidates == [routeA, routeB])
    #expect(runtime.reconnect.phase == .ready)
    #expect(await attempts.closes == [routeA])
}

@Test func configuredRouteLifecycleReconcilesBeforeDialAndClosesOnIdentityLoss()
    async throws
{
    let routeA = try EndpointCandidate(
        kind: .ipv4,
        value: "10.0.0.11",
        port: 47_474
    )
    let routeB = try EndpointCandidate(
        kind: .dns,
        value: "lifecycle.tailnet.ts.net",
        port: 47_474
    )
    let pairedHost = try configuredReconnectPairedHostV1(
        hostID: UUID(),
        endpoint: routeA
    )
    let initial = try configuredReconnectConfigurationV1(
        pairedHost: pairedHost,
        revision: 1,
        endpoint: routeA,
        provenance: .directPrivateAddress
    )
    let replacement = try configuredReconnectConfigurationV1(
        pairedHost: pairedHost,
        revision: 2,
        endpoint: routeB,
        provenance: .privateNetwork
    )
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-route-lifecycle-\(UUID())",
        isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try AtomicFileClientConfiguredRouteStoreV1(directory: root)
    _ = try await store.replaceAtomically(
        initial.routeSnapshot,
        expectedRevision: nil
    )
    let inventory = ConfiguredRouteIdentityInventoryV1(pairedHost)
    let attempts = ConfiguredReconnectAttemptRecorderV1()
    let lifecycle = try await ClientConfiguredRouteLifecycleV1(
        hostID: pairedHost.hostID,
        pairedHosts: inventory,
        routes: store,
        foreground: true,
        networkReachable: true,
        makeController: configuredReconnectControllerFactoryV1(
            attempts: attempts
        ),
        newRouteID: {
            try WireBytes16(Data(repeating: 0xfe, count: 16))
        }
    )
    let startup = await lifecycle.snapshot()
    #expect(startup.phase == .active)
    #expect(startup.routeSnapshot.revision == 1)
    #expect(startup.reconnect.reconnect.phase == .ready)
    #expect(await attempts.attempts.isEmpty)

    _ = try await store.replaceAtomically(
        replacement.routeSnapshot,
        expectedRevision: 1
    )
    try await lifecycle.startRound(
        roundID: UUID(),
        monotonicNowMilliseconds: 100
    )
    for _ in 0..<2_000 {
        if await lifecycle.snapshot().reconnect.reconnect.phase
            == .connected(routeB) { break }
        await Task.yield()
    }
    let reconciled = await lifecycle.snapshot()
    #expect(reconciled.routeSnapshot.revision == 2)
    #expect(reconciled.reconnect.configurationRevision == 2)
    #expect(reconciled.reconnect.reconnect.phase == .connected(routeB))

    try await lifecycle.setForeground(
        false,
        monotonicNowMilliseconds: 101
    )
    #expect(await lifecycle.snapshot().phase == .background)
    await #expect(throws: ClientConfiguredRouteLifecycleErrorV1.background) {
        try await lifecycle.startRound(
            roundID: UUID(),
            monotonicNowMilliseconds: 102
        )
    }
    #expect(await attempts.closes == [routeB])

    try await lifecycle.setForeground(
        true,
        monotonicNowMilliseconds: 103
    )
    try await lifecycle.startRound(
        roundID: UUID(),
        monotonicNowMilliseconds: 104
    )
    for _ in 0..<2_000 {
        if await lifecycle.snapshot().reconnect.reconnect.phase
            == .connected(routeB) { break }
        await Task.yield()
    }
    await inventory.failReads()
    await #expect(throws: ConfiguredRouteIdentityInventoryErrorV1.unreadable) {
        try await lifecycle.startRound(
            roundID: UUID(),
            monotonicNowMilliseconds: 105
        )
    }
    #expect(await lifecycle.snapshot().phase == .closed)
    #expect(await attempts.closes == [routeB, routeB])
}

@Test func configuredRouteLifecycleRequiresBothDurableAuthorities()
    async throws
{
    let route = try EndpointCandidate(
        kind: .ipv4,
        value: "10.0.0.12",
        port: 47_474
    )
    let pairedHost = try configuredReconnectPairedHostV1(
        hostID: UUID(),
        endpoint: route
    )
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-route-lifecycle-empty-\(UUID())",
        isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try AtomicFileClientConfiguredRouteStoreV1(directory: root)
    let attempts = ConfiguredReconnectAttemptRecorderV1()

    await #expect(
        throws: ClientConfiguredRouteLifecycleErrorV1.missingPairedHost
    ) {
        _ = try await ClientConfiguredRouteLifecycleV1(
            hostID: pairedHost.hostID,
            pairedHosts: ConfiguredRouteIdentityInventoryV1(nil),
            routes: store,
            foreground: true,
            networkReachable: true,
            makeController: configuredReconnectControllerFactoryV1(
                attempts: attempts
            ),
            newRouteID: {
                try WireBytes16(Data(repeating: 1, count: 16))
            }
        )
    }
    await #expect(
        throws: ClientConfiguredRouteLifecycleErrorV1.missingCatalog
    ) {
        _ = try await ClientConfiguredRouteLifecycleV1(
            hostID: pairedHost.hostID,
            pairedHosts: ConfiguredRouteIdentityInventoryV1(pairedHost),
            routes: store,
            foreground: true,
            networkReachable: true,
            makeController: configuredReconnectControllerFactoryV1(
                attempts: attempts
            ),
            newRouteID: {
                try WireBytes16(Data(repeating: 2, count: 16))
            }
        )
    }
    #expect(await attempts.attempts.isEmpty)
}

@Test func applicationBindingNeverDialsPendingOrBackgroundAndRearamsEligibility()
    async throws
{
    let route = try EndpointCandidate(
        kind: .ipv4,
        value: "10.0.0.21",
        port: 47_474
    )
    let pairedHost = try configuredReconnectPairedHostV1(
        hostID: UUID(),
        endpoint: route
    )
    let configuration = try configuredReconnectConfigurationV1(
        pairedHost: pairedHost,
        revision: 1,
        endpoint: route,
        provenance: .directPrivateAddress
    )
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-application-binding-\(UUID())",
        isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try AtomicFileClientConfiguredRouteStoreV1(directory: root)
    _ = try await store.replaceAtomically(
        configuration.routeSnapshot,
        expectedRevision: nil
    )
    let attempts = ConfiguredReconnectAttemptRecorderV1()
    let lifecycle = try await ClientConfiguredRouteLifecycleV1(
        hostID: pairedHost.hostID,
        pairedHosts: ConfiguredRouteIdentityInventoryV1(pairedHost),
        routes: store,
        foreground: false,
        networkReachable: false,
        makeController: configuredReconnectControllerFactoryV1(
            attempts: attempts
        ),
        newRouteID: {
            try WireBytes16(Data(repeating: 0xb1, count: 16))
        }
    )
    let clock = ConfiguredRouteBindingClockV1(100)
    let binding = try await ClientConfiguredRouteApplicationBindingV1(
        lifecycle: lifecycle,
        monotonicNow: { clock.value },
        roundID: { UUID() }
    )
    let initialBinding = await binding.snapshot()
    #expect(initialBinding.lifecycle.phase == .background)
    #expect(initialBinding.lifecycle.reconnect.reconnect.phase
        == .waitingForForeground)

    try await binding.setNetworkReachable(true)
    #expect(await attempts.attempts.isEmpty)
    try await binding.start()
    #expect(await attempts.attempts.isEmpty)

    clock.value = 101
    try await binding.setForeground(true)
    for _ in 0..<2_000 {
        if await lifecycle.snapshot().reconnect.reconnect.phase
            == .connected(route) { break }
        await Task.yield()
    }
    #expect(await attempts.attempts == [route])
    try await binding.setForeground(true)
    try await binding.setNetworkReachable(true)
    #expect(await attempts.attempts == [route])

    clock.value = 102
    try await binding.setForeground(false)
    #expect(await lifecycle.snapshot().phase == .background)
    #expect(await attempts.closes == [route])
    clock.value = 103
    try await binding.setForeground(true)
    for _ in 0..<2_000 {
        if await attempts.attempts.count == 2 { break }
        await Task.yield()
    }
    #expect(await attempts.attempts == [route, route])
    #expect(await binding.snapshot().hasStartedEligibleRound)
    await binding.close()
    let closedBinding = await binding.snapshot()
    #expect(closedBinding.phase == .closed)
    #expect(closedBinding.lifecycle.phase == .closed)
    #expect(closedBinding.lifecycle.reconnect.isClosed)
    #expect(closedBinding.lifecycle.reconnect.reconnect.isShutdown)
}

@Test func applicationBindingStartReconcilesExternalRevisionBeforeFirstDial()
    async throws
{
    let routeA = try EndpointCandidate(
        kind: .ipv4,
        value: "10.0.0.22",
        port: 47_474
    )
    let routeB = try EndpointCandidate(
        kind: .dns,
        value: "binding.tailnet.ts.net",
        port: 47_474
    )
    let pairedHost = try configuredReconnectPairedHostV1(
        hostID: UUID(),
        endpoint: routeA
    )
    let initial = try configuredReconnectConfigurationV1(
        pairedHost: pairedHost,
        revision: 1,
        endpoint: routeA,
        provenance: .directPrivateAddress
    )
    let replacement = try configuredReconnectConfigurationV1(
        pairedHost: pairedHost,
        revision: 2,
        endpoint: routeB,
        provenance: .privateNetwork
    )
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-application-binding-reconcile-\(UUID())",
        isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try AtomicFileClientConfiguredRouteStoreV1(directory: root)
    _ = try await store.replaceAtomically(
        initial.routeSnapshot,
        expectedRevision: nil
    )
    let attempts = ConfiguredReconnectAttemptRecorderV1()
    let lifecycle = try await ClientConfiguredRouteLifecycleV1(
        hostID: pairedHost.hostID,
        pairedHosts: ConfiguredRouteIdentityInventoryV1(pairedHost),
        routes: store,
        foreground: true,
        networkReachable: true,
        makeController: configuredReconnectControllerFactoryV1(
            attempts: attempts
        ),
        newRouteID: {
            try WireBytes16(Data(repeating: 0xb2, count: 16))
        }
    )
    let binding = try await ClientConfiguredRouteApplicationBindingV1(
        lifecycle: lifecycle,
        monotonicNow: { 200 },
        roundID: { UUID() }
    )
    _ = try await store.replaceAtomically(
        replacement.routeSnapshot,
        expectedRevision: 1
    )

    try await binding.start()
    for _ in 0..<2_000 {
        if await attempts.attempts == [routeB] { break }
        await Task.yield()
    }
    #expect(await attempts.attempts == [routeB])
    let snapshot = await lifecycle.snapshot()
    #expect(snapshot.routeSnapshot.revision == 2)
    #expect(snapshot.reconnect.configurationRevision == 2)
    await binding.close()
}

@Test func applicationBindingInvalidLocalClockFailsClosedWithoutDial()
    async throws
{
    let route = try EndpointCandidate(
        kind: .ipv4,
        value: "10.0.0.23",
        port: 47_474
    )
    let pairedHost = try configuredReconnectPairedHostV1(
        hostID: UUID(),
        endpoint: route
    )
    let configuration = try configuredReconnectConfigurationV1(
        pairedHost: pairedHost,
        revision: 1,
        endpoint: route,
        provenance: .directPrivateAddress
    )
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-application-binding-clock-\(UUID())",
        isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try AtomicFileClientConfiguredRouteStoreV1(directory: root)
    _ = try await store.replaceAtomically(
        configuration.routeSnapshot,
        expectedRevision: nil
    )
    let attempts = ConfiguredReconnectAttemptRecorderV1()
    let lifecycle = try await ClientConfiguredRouteLifecycleV1(
        hostID: pairedHost.hostID,
        pairedHosts: ConfiguredRouteIdentityInventoryV1(pairedHost),
        routes: store,
        foreground: false,
        networkReachable: true,
        makeController: configuredReconnectControllerFactoryV1(
            attempts: attempts
        ),
        newRouteID: {
            try WireBytes16(Data(repeating: 0xb3, count: 16))
        }
    )
    let binding = try await ClientConfiguredRouteApplicationBindingV1(
        lifecycle: lifecycle,
        monotonicNow: { -1 },
        roundID: { UUID() }
    )

    await #expect(
        throws: ClientConfiguredRouteApplicationBindingErrorV1.invalidClock
    ) {
        try await binding.setForeground(true)
    }
    #expect(await binding.snapshot().phase == .closed)
    #expect(await lifecycle.snapshot().phase == .closed)
    #expect(await attempts.attempts.isEmpty)
}

@Test func applicationBindingInvalidRoundIDFailsClosedWithoutDial()
    async throws
{
    let route = try EndpointCandidate(
        kind: .ipv4,
        value: "10.0.0.24",
        port: 47_474
    )
    let pairedHost = try configuredReconnectPairedHostV1(
        hostID: UUID(),
        endpoint: route
    )
    let configuration = try configuredReconnectConfigurationV1(
        pairedHost: pairedHost,
        revision: 1,
        endpoint: route,
        provenance: .directPrivateAddress
    )
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-application-binding-round-id-\(UUID())",
        isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try AtomicFileClientConfiguredRouteStoreV1(directory: root)
    _ = try await store.replaceAtomically(
        configuration.routeSnapshot,
        expectedRevision: nil
    )
    let attempts = ConfiguredReconnectAttemptRecorderV1()
    let lifecycle = try await ClientConfiguredRouteLifecycleV1(
        hostID: pairedHost.hostID,
        pairedHosts: ConfiguredRouteIdentityInventoryV1(pairedHost),
        routes: store,
        foreground: true,
        networkReachable: true,
        makeController: configuredReconnectControllerFactoryV1(
            attempts: attempts
        ),
        newRouteID: {
            try WireBytes16(Data(repeating: 0xb4, count: 16))
        }
    )
    let binding = try await ClientConfiguredRouteApplicationBindingV1(
        lifecycle: lifecycle,
        monotonicNow: { 300 },
        roundID: {
            UUID(uuid: (
                0, 0, 0, 0, 0, 0, 0, 0,
                0, 0, 0, 0, 0, 0, 0, 0
            ))
        }
    )

    await #expect(
        throws: ClientConfiguredRouteApplicationBindingErrorV1.invalidRoundID
    ) {
        try await binding.start()
    }
    #expect(await binding.snapshot().phase == .closed)
    #expect(await lifecycle.snapshot().phase == .closed)
    #expect(await attempts.attempts.isEmpty)
}

@Test func configuredRouteIntentAdapterPublishesOnlyCommittedLiveRevision()
    async throws
{
    let routeA = try EndpointCandidate(
        kind: .ipv4,
        value: "10.0.0.13",
        port: 47_474
    )
    let routeB = try EndpointCandidate(
        kind: .dns,
        value: "adapter.tailnet.ts.net",
        port: 47_474
    )
    let pairedHost = try configuredReconnectPairedHostV1(
        hostID: UUID(),
        endpoint: routeA
    )
    let initial = try configuredReconnectConfigurationV1(
        pairedHost: pairedHost,
        revision: 1,
        endpoint: routeA,
        provenance: .directPrivateAddress
    )
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-route-adapter-\(UUID())",
        isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try AtomicFileClientConfiguredRouteStoreV1(directory: root)
    _ = try await store.replaceAtomically(
        initial.routeSnapshot,
        expectedRevision: nil
    )
    let lifecycle = try await ClientConfiguredRouteLifecycleV1(
        hostID: pairedHost.hostID,
        pairedHosts: ConfiguredRouteIdentityInventoryV1(pairedHost),
        routes: store,
        foreground: true,
        networkReachable: true,
        makeController: configuredReconnectControllerFactoryV1(
            attempts: ConfiguredReconnectAttemptRecorderV1()
        ),
        newRouteID: {
            try WireBytes16(Data(repeating: 0xa3, count: 16))
        }
    )
    let published = ConfiguredRoutePublishingLatchV1()
    let adapter = ClientRouteConfigurationIntentAdapterV1(
        lifecycle: lifecycle,
        publish: { await published.publish($0) }
    )

    let submission = Task {
        try await adapter.submit(.add(
            endpoint: routeB,
            provenance: .privateNetwork
        ))
    }
    await published.waitUntilWaiting()
    #expect(await published.isWaiting)
    await #expect(
        throws:
            ClientRouteConfigurationIntentAdapterErrorV1
                .transitionInProgress
    ) {
        _ = try await adapter.submit(.remove(
            configuredRouteID:
                initial.catalog.records[0].configuredRouteID
        ))
    }
    await published.release()
    let replacement = try await submission.value
    #expect(replacement.revision == 2)
    #expect(await published.values == [replacement])
    #expect(try await store.snapshot(
        hostID: pairedHost.hostID
    ) == replacement)
    #expect(await lifecycle.snapshot().reconnect.configurationRevision == 2)

    let first = replacement.catalog.records[0]
    await #expect(throws: ClientConfiguredRouteEditErrorV1.noChange) {
        _ = try await adapter.submit(.replace(
            configuredRouteID: first.configuredRouteID,
            endpoint: first.endpoint,
            provenance: first.provenance
        ))
    }
    #expect(await published.values == [replacement])

    await adapter.close()
    await #expect(throws: ClientRouteConfigurationIntentAdapterErrorV1.closed) {
        _ = try await adapter.submit(.remove(
            configuredRouteID: first.configuredRouteID
        ))
    }
}
