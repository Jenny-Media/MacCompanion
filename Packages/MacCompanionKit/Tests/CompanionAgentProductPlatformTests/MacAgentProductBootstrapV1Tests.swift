#if os(macOS)
import CompanionAgent
@testable import CompanionAgentNetworkPlatform
import CompanionAgentPlatform
@testable import CompanionAgentProductPlatform
import CompanionDiscovery
import CompanionDomain
import CompanionHost
@testable import CompanionHostPlatform
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionIPC
import CompanionLifecycle
import CompanionLocalXPCPlatform
import CompanionNetworkPlatform
import CompanionOperations
import CompanionPersistence
import CompanionSecurity
import CompanionWire
import CryptoKit
import Foundation
import Security
import Testing

private let productBootstrapTimeV1: Int64 = 1_724_100_000_000

private enum ProductBootstrapProbeErrorV1: Error, Equatable, Sendable {
    case unused
    case rejectedLocalXPC
    case rejectedNetworkListener
}

@available(macOS 26.0, *)
private actor ProductBootstrapNetworkListenerV1:
    MacAgentNetworkListenerRuntimeV1
{
    private let rejectStart: Bool
    private let startGate: ProductBootstrapFinishGateV1?
    private let cancelReleasesStart: Bool
    private var state: AgentNetworkListenerServiceStateV1 = .idle
    private var admissionState: AgentNetworkUpdateAdmissionStateV1 =
        .unavailable
    private var starts = 0
    private var cancellations = 0
    private var admissionCloses = 0
    private var connectionDrains = 0
    private var admissionReopens = 0

    init(
        rejectStart: Bool = false,
        startGate: ProductBootstrapFinishGateV1? = nil,
        cancelReleasesStart: Bool = false
    ) {
        self.rejectStart = rejectStart
        self.startGate = startGate
        self.cancelReleasesStart = cancelReleasesStart
    }

    func start() async throws {
        starts += 1
        state = .starting
        await startGate?.run()
        guard state != .terminal else { throw CancellationError() }
        if rejectStart {
            throw ProductBootstrapProbeErrorV1.rejectedNetworkListener
        }
        state = .listening
        admissionState = .open
    }

    func closeNetworkAdmission() throws {
        guard state != .terminal else {
            throw AgentNetworkUpdateAdmissionErrorV1.terminal
        }
        guard admissionState == .open else {
            throw AgentNetworkUpdateAdmissionErrorV1
                .invalidTransition(admissionState)
        }
        admissionCloses += 1
        admissionState = .closed
    }

    func drainNetworkConnections() throws {
        guard state != .terminal else {
            throw AgentNetworkUpdateAdmissionErrorV1.terminal
        }
        guard admissionState == .closed else {
            throw AgentNetworkUpdateAdmissionErrorV1
                .invalidTransition(admissionState)
        }
        connectionDrains += 1
        admissionState = .drained
    }

    func reopenNetworkAdmission() throws {
        guard state != .terminal else {
            throw AgentNetworkUpdateAdmissionErrorV1.terminal
        }
        guard admissionState == .closed || admissionState == .drained else {
            throw AgentNetworkUpdateAdmissionErrorV1
                .invalidTransition(admissionState)
        }
        admissionReopens += 1
        admissionState = .open
    }

    func cancel() async {
        cancellations += 1
        state = .terminal
        admissionState = .terminal
        if cancelReleasesStart {
            await startGate?.release()
        }
    }

    func snapshot() -> AgentNetworkListenerServiceSnapshotV1 {
        AgentNetworkListenerServiceSnapshotV1(
            state: state,
            updateAdmissionState: admissionState,
            handoff: AgentNetworkListenerHandoffSnapshotV1(
                isCancelled: state == .terminal,
                hasPendingTLS: false,
                isBinding: false,
                hasActivePrimary: false
            ),
            lastListenerTerminationReason:
                state == .terminal ? .localCancel : nil,
            hasAcceptedConnectionStartFailure: false
        )
    }

    func counts() -> (
        starts: Int,
        cancellations: Int,
        admissionCloses: Int,
        connectionDrains: Int,
        admissionReopens: Int
    ) {
        (
            starts,
            cancellations,
            admissionCloses,
            connectionDrains,
            admissionReopens
        )
    }
}

private actor ProductBootstrapCountingLoaderV1:
    AgentCapabilityProviderLoadingV1
{
    private var count = 0

    func loadProviders() async throws -> [any CapabilityProviderV1] {
        count += 1
        return []
    }

    func loadCount() -> Int { count }
}

private actor ProductBootstrapLocalXPCProbeV1 {
    private var hostIDs: [UUID] = []

    func record(_ hostID: UUID) { hostIDs.append(hostID) }
    func recordedHostIDs() -> [UUID] { hostIDs }
}

private actor ProductBootstrapFactoryCountV1 {
    private var value = 0

    func record() { value += 1 }
    func count() -> Int { value }
}

@available(macOS 26.0, *)
private actor ProductBootstrapLocalXPCRetentionV1 {
    private var product: MacLocalXPCAgentProductV1?

    func retain(_ product: MacLocalXPCAgentProductV1) {
        self.product = product
    }
}

private final class ProductBootstrapSyncStartGateV1:
    @unchecked Sendable
{
    private let condition = NSCondition()
    private var entered = false
    private var released = false

    func waitForRelease() {
        condition.lock()
        entered = true
        condition.broadcast()
        while !released {
            _ = condition.wait(
                until: Date().addingTimeInterval(0.005)
            )
        }
        condition.unlock()
    }

    func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }

    func hasEntered() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        return entered
    }
}

@available(macOS 26.0, *)
private final class ProductBootstrapDeferredServerV1:
    MacLocalXPCAgentServerV1,
    @unchecked Sendable
{
    private let lock = NSLock()
    private let startGate: ProductBootstrapSyncStartGateV1?
    private let rejectStart: Bool
    private var starts = 0
    private var cancellations = 0

    init(
        startGate: ProductBootstrapSyncStartGateV1? = nil,
        rejectStart: Bool = false
    ) {
        self.startGate = startGate
        self.rejectStart = rejectStart
    }

    func start() throws {
        lock.withLock { starts += 1 }
        startGate?.waitForRelease()
        if rejectStart {
            throw ProductBootstrapProbeErrorV1.rejectedLocalXPC
        }
    }

    func cancel() { lock.withLock { cancellations += 1 } }
    func cancelPeer(generation _: UInt64) {}

    func counts() -> (starts: Int, cancellations: Int) {
        lock.withLock { (starts, cancellations) }
    }
}

private actor ProductBootstrapFinishGateV1 {
    private var entered = false
    private var released = false
    private var runCount = 0
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func run() async {
        runCount += 1
        entered = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        guard !released else { return }
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
    }

    func count() -> Int { runCount }
}

private actor ProductBootstrapCompletionProbeV1 {
    private var value = false

    func record() { value = true }
    func snapshot() -> Bool { value }
}

private actor ProductBootstrapMenuGenerationGateV1 {
    private var armed = false
    private var entered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func arm() {
        armed = true
        entered = false
    }

    func waitIfArmed() async {
        guard armed else { return }
        entered = true
        let waiters = enteredWaiters
        enteredWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        await withCheckedContinuation { releaseWaiter = $0 }
        armed = false
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

private actor ProductBootstrapMenuEndpointV1:
    MacLocalXPCAuthenticatedMenuSurfaceEndpointV1
{
    func installAuthenticatedMenuTerminalFence(
        _: MacLocalXPCMenuSurfaceTerminalFenceV1
    ) {}
    func invalidateAuthenticatedMenuSurface() {}
    func presentLocalPairingReview(_: LocalPairingReviewV0) async throws {}
    func withdrawLocalPairingReview(reviewID _: UUID) {}
    func presentHostIdentityRecoveryReview(
        _: LocalHostIdentityRecoveryReviewV0
    ) async throws {}
    func presentHostIdentityRecoveryResume(
        _: LocalHostIdentityRecoveryCommandV0
    ) async throws {}
    func withdrawHostIdentityRecovery(reviewID _: UUID) {}
}

private struct ProductBootstrapSamplerV1: HostSystemSampling {
    func sample() async throws -> HostSystemMeasurement {
        try HostSystemMeasurement(
            osName: "macOS",
            osVersion: "26.6",
            osBuild: "25G100",
            uptimeSeconds: 1,
            cpuUtilizationBasisPoints: 1,
            memoryTotalBytes: 1,
            memoryUsedBytes: 1,
            storageTotalBytes: 1,
            storageAvailableBytes: 1,
            powerSource: .ac,
            batteryLevelPercent: nil
        )
    }
}

private struct ProductBootstrapClockV1: HostStatusClock {
    func nowUnixMilliseconds() -> Int64 { productBootstrapTimeV1 }
}

private struct ProductBootstrapVisibleAdmissionV1:
    VisibleInteractiveAdmissionReadingV0
{
    func snapshot() async throws -> VisibleInteractiveAdmissionStateV0 {
        VisibleInteractiveAdmissionStateV0(
            generation: UUID(),
            revision: 1,
            visibleMenuAppAvailable: true,
            selectedDisplayID: UUID()
        )
    }
}

private struct ProductBootstrapMaterialsV1:
    InteractiveSessionMaterialGeneratingV0
{
    func approvalMaterials() async throws -> InteractiveApprovalMaterialsV0 {
        throw ProductBootstrapProbeErrorV1.unused
    }

    func bootstrapMaterials() async throws
        -> InteractiveSessionBootstrapMaterials
    {
        throw ProductBootstrapProbeErrorV1.unused
    }
}

private actor ProductBootstrapRuntimeV1:
    InteractiveSessionRuntimeOwningV0
{
    func install(
        _ bootstrap: InteractiveSessionBootstrap,
        requirement: InteractiveSessionRuntimeRequirementV0
    ) async throws {
        throw ProductBootstrapProbeErrorV1.unused
    }

    func terminate(
        interactiveSessionID: UUID,
        primaryConnectionID: Data,
        reason: InteractiveSessionEndReason
    ) async {}
}

private struct ProductBootstrapLifecycleFactoryV1:
    MacLocalXPCMenuLifecycleConnectionFactoryV1
{
    func makeLocalXPCMenuLifecycleConnection(
        generation: UUID
    ) async throws -> any MacLocalXPCMenuLifecycleConnectionV1 {
        throw ProductBootstrapProbeErrorV1.unused
    }
}

private struct ProductBootstrapStatusReaderV1:
    MacLocalXPCStatusReadingV1
{
    func readStatus() async
        -> Result<LocalAgentStatusSnapshot, MacLocalXPCStatusReadErrorV1>
    {
        .failure(.sourceUnavailable)
    }
}

@available(macOS 26.0, *)
private func productBootstrapLocalXPCV1() -> MacLocalXPCAgentProductV1 {
    MacLocalXPCAgentProductV1.compose(
        lifecycleFactory: ProductBootstrapLifecycleFactoryV1(),
        statusReader: ProductBootstrapStatusReaderV1()
    )
}

@available(macOS 26.0, *)
private func productBootstrapLocalXPCV1(
    server: ProductBootstrapDeferredServerV1
) -> MacLocalXPCAgentProductV1 {
    MacLocalXPCAgentProductV1.compose(
        lifecycleFactory: ProductBootstrapLifecycleFactoryV1(),
        statusReader: ProductBootstrapStatusReaderV1(),
        serverFactory: { _, _, _ in server }
    )
}

private struct ProductBootstrapIdentityV1 {
    let issued: SecurityHostIssuedIdentityV0
    let stored: StoredHostIdentityRecord
}

private func productBootstrapIdentityV1() throws
    -> ProductBootstrapIdentityV1
{
    let softwareKey = P256.Signing.PrivateKey()
    var creationError: Unmanaged<CFError>?
    guard let privateKey = SecKeyCreateWithData(
        softwareKey.x963Representation as CFData,
        [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits: 256,
        ] as CFDictionary,
        &creationError
    ) else {
        let error = creationError?.takeRetainedValue()
        throw error ?? CocoaError(.featureUnsupported)
    }
    let issued = try SecurityHostIdentityKeyCustodyV0.assembleIssuedIdentity(
        privateKey: privateKey,
        applicationTag: Data("example.product-bootstrap.ephemeral".utf8),
        serialNumber: Data(repeating: 0x41, count: 16),
        issuanceTimeUnixMilliseconds: productBootstrapTimeV1
    )
    let stored = try StoredHostIdentityRecord(
        hostID: UUID(),
        keyApplicationTag: issued.key.applicationTag,
        hostFingerprint: issued.key.hostFingerprint,
        certificateDER: issued.certificateDER,
        certificateNotBeforeUnixMilliseconds:
            issued.validity.notBeforeUnixMilliseconds,
        certificateNotAfterUnixMilliseconds:
            issued.validity.notAfterUnixMilliseconds,
        establishedAtUnixMilliseconds: productBootstrapTimeV1,
        updatedAtUnixMilliseconds: productBootstrapTimeV1
    )
    return ProductBootstrapIdentityV1(issued: issued, stored: stored)
}

private func productBootstrapInputsV1(
    loader: any AgentCapabilityProviderLoadingV1,
    lifecycleState: ProductLifecycleState = ProductLifecycleState(
        desiredEnabled: true,
        consoleSession: .active,
        agent: .starting,
        menuApp: .starting
    )
) throws -> AgentNetworkPrimaryStartupInputsV1 {
    AgentNetworkPrimaryStartupInputsV1(
        registry: try CapabilityRegistrySnapshotV1(
            generation: UUID(),
            capabilities: []
        ),
        providerLoader: loader,
        wallNowUnixMilliseconds: productBootstrapTimeV1,
        lifecycleState: lifecycleState,
        statusPlatform: AgentHostStatusPlatformServicesV1(
            sampler: ProductBootstrapSamplerV1(),
            clock: ProductBootstrapClockV1(),
            initialGeneration: UUID()
        ),
        interactivePlatform: AgentInteractivePlatformServicesV1(
            visibleAdmission: ProductBootstrapVisibleAdmissionV1(),
            materials: ProductBootstrapMaterialsV1(),
            runtime: ProductBootstrapRuntimeV1()
        )
    )
}

private func productBootstrapStorageV1(
    base: URL
) throws -> MacAgentReleaseStorageV1 {
    try MacAgentReleaseStorageV1(
        baseApplicationSupportDirectory: base
    )
}

@available(macOS 26.0, *)
private func productBootstrapPreparedPrimaryV1(
    storage: MacAgentReleaseStorageV1
) async throws -> AgentPreparedPrimaryStartupV1 {
    let identity = try productBootstrapIdentityV1()
    try await storage.requiredAudit.securityStore.establishHostIdentity(
        identity.stored
    )
    guard case let .ready(prepared) = try await
        AgentNetworkPrimaryStartupFactoryV1.prepare(
            hostIdentityStartup: {
                .ready(
                    record: identity.stored,
                    issuedIdentity: identity.issued,
                    renewalRecommended: false
                )
            },
            requiredAudit: storage.requiredAudit,
            inputs: try productBootstrapInputsV1(
                loader: ProductBootstrapCountingLoaderV1()
            )
        ) else {
        throw ProductBootstrapProbeErrorV1.unused
    }
    return prepared
}

private final class ProductApplicationPreparationProbeV1:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var events: [String] = []
    private var states: [ProductLifecycleState] = []
    private var finishCount = 0

    func record(_ event: String) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func record(_ state: ProductLifecycleState) {
        lock.lock()
        states.append(state)
        lock.unlock()
    }

    func recordFinish() {
        lock.lock()
        finishCount += 1
        lock.unlock()
    }

    func snapshot() -> (
        events: [String],
        states: [ProductLifecycleState],
        finishes: Int
    ) {
        lock.lock()
        defer { lock.unlock() }
        return (events, states, finishCount)
    }
}

private actor ProductApplicationIntentStoreV1:
    MacRemoteAccessIntentPersistenceV1
{
    private let value: MacRemoteAccessIntentSnapshotV1?
    private let probe: ProductApplicationPreparationProbeV1
    private let readGate: ProductBootstrapFinishGateV1?

    init(
        value: MacRemoteAccessIntentSnapshotV1?,
        probe: ProductApplicationPreparationProbeV1,
        readGate: ProductBootstrapFinishGateV1? = nil
    ) {
        self.value = value
        self.probe = probe
        self.readGate = readGate
    }

    func current() async throws -> MacRemoteAccessIntentSnapshotV1? {
        probe.record("intentRead")
        await readGate?.run()
        return value
    }

    func replaceAtomically(
        _: MacRemoteAccessIntentSnapshotV1,
        expectedRevision _: UInt64?
    ) async throws -> MacRemoteAccessIntentCommitResultV1 {
        throw ProductBootstrapProbeErrorV1.unused
    }
}

private actor ProductApplicationFinishSignalV1 {
    private var count = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func record() {
        count += 1
        let retained = waiters
        waiters.removeAll()
        for waiter in retained { waiter.resume() }
    }

    func waitForFinish() async {
        guard count == 0 else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func finishCount() -> Int { count }
}

@available(macOS 26.0, *)
private actor ProductApplicationRecoveryModeProbeV1 {
    private var recorded: [MacAgentHostIdentityRecoveryModeV1] = []

    func record(_ mode: MacAgentHostIdentityRecoveryModeV1) {
        recorded.append(mode)
    }

    func values() -> [MacAgentHostIdentityRecoveryModeV1] { recorded }
}

private func productApplicationIntentV1(
    enabled: Bool
) throws -> MacRemoteAccessIntentSnapshotV1 {
    try MacRemoteAccessIntentSnapshotV1(
        revision: 1,
        desiredEnabled: enabled,
        commandID: UUID(
            uuidString: "018f5000-0000-7000-8000-000000000101"
        )!,
        recordedAtUnixMilliseconds: productBootstrapTimeV1
    )
}

@available(macOS 26.0, *)
private func productApplicationPrepareV1(
    storage: MacAgentReleaseStorageV1,
    intent: MacRemoteAccessIntentSnapshotV1?,
    probe: ProductApplicationPreparationProbeV1,
    loader: any AgentCapabilityProviderLoadingV1,
    readGate: ProductBootstrapFinishGateV1? = nil,
    prepareRoot: @escaping @Sendable (
        MacAgentReleaseStorageV1,
        AgentNetworkPrimaryStartupInputsV1
    ) async throws -> MacAgentPreparedApplicationRootResultV1,
    makeHostIdentityRecovery: @escaping @Sendable (
        MacAgentReleaseStorageV1,
        MacAgentHostIdentityRecoveryModeV1
    ) async throws -> MacAgentHostIdentityRecoveryProductV1? = { _, _ in nil }
) async throws -> MacAgentApplicationPreparationResultV1 {
    let intentStore = ProductApplicationIntentStoreV1(
        value: intent,
        probe: probe,
        readGate: readGate
    )
    return try await MacAgentApplicationPreparationFacadeV1.prepare(
        makeStorage: {
            probe.record("storage")
            return storage
        },
        makeIntentStore: { directory in
            probe.record("intentStore:\(directory.path)")
            return intentStore
        },
        makePrimaryInputs: { state in
            probe.record("inputs")
            probe.record(state)
            return try productBootstrapInputsV1(
                loader: loader,
                lifecycleState: state
            )
        },
        prepareRoot: prepareRoot,
        makeHostIdentityRecovery: makeHostIdentityRecovery
    )
}

@available(macOS 26.0, *)
@Test func applicationPreparationRejectsEveryUnsafeInitialLifecycleClass() {
    let valid = [
        ProductLifecycleState(consoleSession: .otherConsoleUserActive),
        ProductLifecycleState(
            desiredEnabled: true,
            consoleSession: .otherConsoleUserActive,
            agent: .starting,
            menuApp: .starting
        ),
        ProductLifecycleState(consoleSession: .active),
        ProductLifecycleState(
            desiredEnabled: true,
            consoleSession: .active,
            agent: .starting,
            menuApp: .starting
        ),
    ]
    for state in valid {
        #expect(throws: Never.self) {
            try MacAgentApplicationPreparationFacadeV1
                .validateInitialLifecycleState(state)
        }
    }

    let invalid = [
        ProductLifecycleState(
            desiredEnabled: true,
            consoleSession: .locked,
            agent: .starting,
            menuApp: .starting
        ),
        ProductLifecycleState(consoleSession: .loggedOut),
        ProductLifecycleState(
            desiredEnabled: true,
            consoleSession: .otherConsoleUserActive,
            agent: .ready,
            menuApp: .starting
        ),
        ProductLifecycleState(
            desiredEnabled: true,
            consoleSession: .otherConsoleUserActive,
            agent: .starting,
            menuApp: .ready
        ),
        ProductLifecycleState(
            desiredEnabled: false,
            consoleSession: .otherConsoleUserActive,
            agent: .starting,
            menuApp: .stopped
        ),
    ]
    for state in invalid {
        #expect(
            throws:
                MacAgentApplicationPreparationErrorV1
                    .unsafeInitialLifecycleState
        ) {
            try MacAgentApplicationPreparationFacadeV1
                .validateInitialLifecycleState(state)
        }
    }
}

@available(macOS 26.0, *)
@Test func canonicalInertPreparationDefersReadinessProducingLocalXPC()
    async throws
{
    let lifecycleStates = [
        ProductLifecycleState(consoleSession: .otherConsoleUserActive),
        ProductLifecycleState(
            desiredEnabled: true,
            consoleSession: .otherConsoleUserActive,
            agent: .starting,
            menuApp: .starting
        ),
    ]

    for (index, state) in lifecycleStates.enumerated() {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "maccompanion-canonical-inert-\(index)-\(UUID())",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: base,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: base) }
        let storage = try productBootstrapStorageV1(base: base)
        let identity = try productBootstrapIdentityV1()
        try await storage.requiredAudit.securityStore.establishHostIdentity(
            identity.stored
        )
        let loader = ProductBootstrapCountingLoaderV1()
        let localXPCProbe = ProductBootstrapLocalXPCProbeV1()

        guard case let .ready(product) = try await
            MacAgentProductBootstrapV1.prepareInert(
                storage: storage,
                hostIdentityStartup: {
                    .ready(
                        record: identity.stored,
                        issuedIdentity: identity.issued,
                        renewalRecommended: false
                    )
                },
                inputs: try productBootstrapInputsV1(
                    loader: loader,
                    lifecycleState: state
                ),
                makeLocalXPC: { services in
                    await localXPCProbe.record(services.hostID)
                    return productBootstrapLocalXPCV1()
                }
            ) else {
            Issue.record("expected canonical inert prepared root")
            continue
        }

        #expect(await localXPCProbe.recordedHostIDs().isEmpty)
        #expect((await product.lifecycleSnapshot()).state == state)
        #expect(!(await product.preparedPrimarySnapshot().consumed))
        await product.finish()
        #expect(await localXPCProbe.recordedHostIDs().isEmpty)
        #expect((await product.lifecycleSnapshot()).state == state)
    }
}

@available(macOS 26.0, *)
@Test func deferredLocalXPCOwnerStartsOnceAndCleansStartFailure()
    async throws
{
    let successServer = ProductBootstrapDeferredServerV1()
    let successFactory = ProductBootstrapFactoryCountV1()
    let successOwner = MacAgentDeferredLocalXPCOwnerV1 {
        await successFactory.record()
        return productBootstrapLocalXPCV1(server: successServer)
    }

    async let first: Void = successOwner.start()
    async let second: Void = successOwner.start()
    _ = try await (first, second)
    #expect(await successFactory.count() == 1)
    #expect(successServer.counts().starts == 1)
    await successOwner.finish()
    await successOwner.finish()
    #expect(successServer.counts().cancellations == 1)

    let failureServer = ProductBootstrapDeferredServerV1(
        rejectStart: true
    )
    let failureFactory = ProductBootstrapFactoryCountV1()
    let failureRetention = ProductBootstrapLocalXPCRetentionV1()
    let failureOwner = MacAgentDeferredLocalXPCOwnerV1 {
        await failureFactory.record()
        let product = productBootstrapLocalXPCV1(server: failureServer)
        await failureRetention.retain(product)
        return product
    }
    await #expect(
        throws: ProductBootstrapProbeErrorV1.rejectedLocalXPC
    ) {
        try await failureOwner.start()
    }
    #expect(await failureFactory.count() == 1)
    #expect(failureServer.counts().starts == 1)
    #expect(failureServer.counts().cancellations == 1)
    await #expect(
        throws: MacAgentPreparedProductCompositionErrorV1.terminal
    ) {
        try await failureOwner.start()
    }

    let joinedGate = ProductBootstrapSyncStartGateV1()
    let joinedServer = ProductBootstrapDeferredServerV1(
        startGate: joinedGate
    )
    let joinedFactory = ProductBootstrapFactoryCountV1()
    let joinedRetention = ProductBootstrapLocalXPCRetentionV1()
    let joinedOwner = MacAgentDeferredLocalXPCOwnerV1 {
        await joinedFactory.record()
        let product = productBootstrapLocalXPCV1(server: joinedServer)
        await joinedRetention.retain(product)
        return product
    }
    let firstStart = Task { try await joinedOwner.start() }
    while !joinedGate.hasEntered() { await Task.yield() }
    let cancelledJoin = Task { try await joinedOwner.start() }
    cancelledJoin.cancel()
    joinedGate.release()
    await #expect(throws: CancellationError.self) {
        try await cancelledJoin.value
    }
    // The first caller may finish before the newly scheduled join installs
    // its cancellation handler. Cancellation cannot retroactively fail that
    // completed caller. If it loses the race, only cancellation/terminal is
    // valid. In every order the cancelled caller fails and cleanup below
    // proves the shared product is retired exactly once.
    if case let .failure(error) = await firstStart.result {
        #expect(error is CancellationError ||
            error as? MacAgentPreparedProductCompositionErrorV1 == .terminal)
    }
    #expect(await joinedFactory.count() == 1)
    #expect(joinedServer.counts().starts == 1)
    #expect(joinedServer.counts().cancellations == 1)
    await #expect(
        throws: MacAgentPreparedProductCompositionErrorV1.terminal
    ) {
        try await joinedOwner.start()
    }
}

@available(macOS 26.0, *)
@Test func cancelledDeferredActivationFencesLateStartAndFinishesProduct()
    async throws
{
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-deferred-activation-cancel-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: base,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let storage = try productBootstrapStorageV1(base: base)
    let prepared = try await productBootstrapPreparedPrimaryV1(
        storage: storage
    )
    let startGate = ProductBootstrapSyncStartGateV1()
    let server = ProductBootstrapDeferredServerV1(startGate: startGate)
    let factory = ProductBootstrapFactoryCountV1()
    let retention = ProductBootstrapLocalXPCRetentionV1()
    let product = MacAgentPreparedProductV1(
        storage: storage,
        preparedPrimary: prepared,
        makeLocalXPC: { _ in
            await factory.record()
            let product = productBootstrapLocalXPCV1(server: server)
            await retention.retain(product)
            return product
        }
    )

    let activation = Task { try await product.startLocalAuthorization() }
    while !startGate.hasEntered() { await Task.yield() }
    activation.cancel()
    startGate.release()

    await #expect(throws: CancellationError.self) {
        try await activation.value
    }
    #expect(await factory.count() == 1)
    #expect(server.counts().starts == 1)
    #expect(server.counts().cancellations == 1)
    #expect(await product.snapshot().finished)
    #expect(await prepared.snapshot().consumed)
    await #expect(
        throws: MacAgentPreparedProductCompositionErrorV1.terminal
    ) {
        try await product.startLocalAuthorization()
    }
}

@available(macOS 26.0, *)
@Test func applicationPreparationRejectsLifecycleSubstitutionAtBothSeams()
    async throws
{
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-application-lifecycle-correlation-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: base,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let storage = try productBootstrapStorageV1(base: base)
    let inputProbe = ProductApplicationPreparationProbeV1()
    let inputIntentStore = ProductApplicationIntentStoreV1(
        value: nil,
        probe: inputProbe
    )
    await #expect(
        throws:
            MacAgentApplicationPreparationErrorV1
                .unsafeInitialLifecycleState
    ) {
        try await MacAgentApplicationPreparationFacadeV1.prepare(
            makeStorage: { storage },
            makeIntentStore: { _ in inputIntentStore },
            makePrimaryInputs: { _ in
                try productBootstrapInputsV1(
                    loader: ProductBootstrapCountingLoaderV1(),
                    lifecycleState: ProductLifecycleState(
                        consoleSession: .active
                    )
                )
            },
            prepareRoot: { _, _ in
                inputProbe.record("unexpectedRoot")
                return .waitForFirstUnlock
            }
        )
    }
    #expect(!inputProbe.snapshot().events.contains("unexpectedRoot"))

    let initialState = ProductLifecycleState(
        consoleSession: .otherConsoleUserActive
    )
    let substitutedSnapshots = [
        AgentRemoteLifecycleSnapshotV1(
            revision: 0,
            state: ProductLifecycleState(consoleSession: .active)
        ),
        AgentRemoteLifecycleSnapshotV1(
            revision: 1,
            state: initialState
        ),
        AgentRemoteLifecycleSnapshotV1(
            revision: 0,
            agentObservationEpoch: 1,
            state: initialState
        ),
        AgentRemoteLifecycleSnapshotV1(
            revision: 0,
            menuAppObservationEpoch: 1,
            state: initialState
        ),
    ]
    for substituted in substitutedSnapshots {
        let preparedProbe = ProductApplicationPreparationProbeV1()
        await #expect(
            throws:
                MacAgentApplicationPreparationErrorV1
                    .unsafeInitialLifecycleState
        ) {
            try await productApplicationPrepareV1(
                storage: storage,
                intent: nil,
                probe: preparedProbe,
                loader: ProductBootstrapCountingLoaderV1(),
                prepareRoot: { storage, _ in
                    .prepared(MacAgentPreparedProductHandleV1(
                        hostID: UUID(),
                        storagePaths: storage.paths,
                        currentLifecycle: { substituted },
                        finish: { preparedProbe.recordFinish() }
                    ))
                }
            )
        }
        #expect(preparedProbe.snapshot().finishes == 1)
    }
}

@available(macOS 26.0, *)
@Test func applicationPreparationLoadsAbsentIntentBeforePrimaryConstruction()
    async throws
{
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-application-preparation-order-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: base,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let storage = try productBootstrapStorageV1(base: base)
    let probe = ProductApplicationPreparationProbeV1()
    let loader = ProductBootstrapCountingLoaderV1()

    guard case .waitForFirstUnlock = try await productApplicationPrepareV1(
        storage: storage,
        intent: nil,
        probe: probe,
        loader: loader,
        prepareRoot: { _, inputs in
            probe.record("prepareRoot")
            #expect(!inputs.lifecycleState.desiredEnabled)
            return .waitForFirstUnlock
        }
    ) else {
        Issue.record("expected first-unlock wait")
        return
    }

    let snapshot = probe.snapshot()
    #expect(
        snapshot.events == [
            "storage",
            "intentStore:\(storage.paths.remoteAccessIntentDirectory.path)",
            "intentRead",
            "inputs",
            "prepareRoot",
        ]
    )
    #expect(
        snapshot.states == [
            ProductLifecycleState(consoleSession: .otherConsoleUserActive),
        ]
    )
    #expect(await loader.loadCount() == 0)
    #expect(
        storage.paths.remoteAccessIntentDirectory
            == storage.paths.root.appendingPathComponent(
                "remote-access-intent-v1",
                isDirectory: true
            )
    )
}

@available(macOS 26.0, *)
@Test func applicationPreparationRestoresEnabledIntentWithoutReadiness()
    async throws
{
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-application-preparation-enabled-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: base,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let storage = try productBootstrapStorageV1(base: base)
    let probe = ProductApplicationPreparationProbeV1()
    let loader = ProductBootstrapCountingLoaderV1()

    guard case .requireLocalRecovery(.invalidEstablishedKey) = try await
        productApplicationPrepareV1(
            storage: storage,
            intent: try productApplicationIntentV1(enabled: true),
            probe: probe,
            loader: loader,
            prepareRoot: { _, inputs in
                let state = inputs.lifecycleState
                #expect(state.desiredEnabled)
                #expect(state.consoleSession == .otherConsoleUserActive)
                #expect(state.agent == .starting)
                #expect(state.menuApp == .starting)
                #expect(!state.observeAvailable)
                #expect(!state.newInteractiveControlAvailable)
                #expect(!state.localAdministrationVisible)
                return .requireLocalRecovery(.invalidEstablishedKey)
            }
        ) else {
        Issue.record("expected local recovery requirement")
        return
    }
}

@available(macOS 26.0, *)
@Test func preparedApplicationOwnerIsActivationInertAndFinishesOnce()
    async throws
{
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-application-preparation-ready-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: base,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let storage = try productBootstrapStorageV1(base: base)
    let probe = ProductApplicationPreparationProbeV1()
    let loader = ProductBootstrapCountingLoaderV1()
    let hostID = UUID(
        uuidString: "018f5000-0000-7000-8000-000000000102"
    )!

    guard case let .prepared(owner) = try await
        productApplicationPrepareV1(
            storage: storage,
            intent: try productApplicationIntentV1(enabled: true),
            probe: probe,
            loader: loader,
            prepareRoot: { storage, inputs in
                probe.record("preparedRoot")
                return .prepared(MacAgentPreparedProductHandleV1(
                    hostID: hostID,
                    storagePaths: storage.paths,
                    currentLifecycle: {
                        AgentRemoteLifecycleSnapshotV1(
                            revision: 0,
                            state: inputs.lifecycleState
                        )
                    },
                    finish: { probe.recordFinish() }
                ))
            }
        ) else {
        Issue.record("expected inert prepared owner")
        return
    }

    let initial = await owner.snapshot()
    #expect(initial.hostID == hostID)
    #expect(initial.storagePaths == storage.paths)
    #expect(initial.lifecycle.state.desiredEnabled)
    #expect(
        initial.lifecycle.state.consoleSession
            == .otherConsoleUserActive
    )
    #expect(initial.lifecycle.state.agent == .starting)
    #expect(initial.lifecycle.state.menuApp == .starting)
    #expect(!initial.requestContexts.started)
    #expect(!initial.finished)

    async let first: Void = owner.finish()
    async let second: Void = owner.finish()
    _ = await (first, second)
    #expect((await owner.snapshot()).finished)
    #expect(
        (await owner.snapshot()).requestContexts.hostState
            == .serviceStoppingForLogout
    )
    #expect(probe.snapshot().finishes == 1)
}

@available(macOS 26.0, *)
@Test func applicationPreparationCancellationDuringIntentReadSkipsRoot()
    async throws
{
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-application-preparation-read-cancel-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: base,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let storage = try productBootstrapStorageV1(base: base)
    let probe = ProductApplicationPreparationProbeV1()
    let gate = ProductBootstrapFinishGateV1()
    let loader = ProductBootstrapCountingLoaderV1()
    let task = Task {
        try await productApplicationPrepareV1(
            storage: storage,
            intent: nil,
            probe: probe,
            loader: loader,
            readGate: gate,
            prepareRoot: { _, _ in
                probe.record("unexpectedRoot")
                return .waitForFirstUnlock
            }
        )
    }
    await gate.waitUntilEntered()
    task.cancel()
    await gate.release()

    do {
        _ = try await task.value
        Issue.record("expected cancellation")
    } catch is CancellationError {
        #expect(!probe.snapshot().events.contains("unexpectedRoot"))
    }
}

@available(macOS 26.0, *)
@Test func preparedApplicationOwnerDeinitBeginsBestEffortRetirement()
    async throws
{
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-application-preparation-deinit-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: base,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let storage = try productBootstrapStorageV1(base: base)
    let signal = ProductApplicationFinishSignalV1()
    var owner: MacAgentInertApplicationLifecycleV1?
    var result: MacAgentApplicationPreparationResultV1? = try await
        productApplicationPrepareV1(
            storage: storage,
            intent: nil,
            probe: ProductApplicationPreparationProbeV1(),
            loader: ProductBootstrapCountingLoaderV1(),
            prepareRoot: { storage, inputs in
                .prepared(MacAgentPreparedProductHandleV1(
                    hostID: UUID(
                        uuidString:
                            "018f5000-0000-7000-8000-000000000105"
                    )!,
                    storagePaths: storage.paths,
                    currentLifecycle: {
                        AgentRemoteLifecycleSnapshotV1(
                            revision: 0,
                            state: inputs.lifecycleState
                        )
                    },
                    finish: { await signal.record() }
                ))
            }
        )
    switch result {
    case let .prepared(prepared):
        owner = prepared
    default:
        Issue.record("expected prepared owner")
        return
    }
    result = nil
    weak let weakOwner = owner
    owner = nil
    #expect(weakOwner == nil)
    await signal.waitForFinish()
    #expect(await signal.finishCount() == 1)
}

@available(macOS 26.0, *)
@Test func cancellationAfterPreparedRootCompensatesExactlyOnce()
    async throws
{
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-application-preparation-ready-cancel-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: base,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let storage = try productBootstrapStorageV1(base: base)
    let probe = ProductApplicationPreparationProbeV1()
    let gate = ProductBootstrapFinishGateV1()
    let loader = ProductBootstrapCountingLoaderV1()
    let hostID = UUID(
        uuidString: "018f5000-0000-7000-8000-000000000103"
    )!
    let task = Task {
        try await productApplicationPrepareV1(
            storage: storage,
            intent: nil,
            probe: probe,
            loader: loader,
            prepareRoot: { storage, inputs in
                await gate.run()
                return .prepared(MacAgentPreparedProductHandleV1(
                    hostID: hostID,
                    storagePaths: storage.paths,
                    currentLifecycle: {
                        AgentRemoteLifecycleSnapshotV1(
                            revision: 0,
                            state: inputs.lifecycleState
                        )
                    },
                    finish: { probe.recordFinish() }
                ))
            }
        )
    }
    await gate.waitUntilEntered()
    task.cancel()
    await gate.release()

    do {
        _ = try await task.value
        Issue.record("expected cancellation")
    } catch is CancellationError {
        #expect(probe.snapshot().finishes == 1)
    }
}

@available(macOS 26.0, *)
@Test func preparationMapsEveryNonreadyResultWithoutPreparedAuthority()
    async throws
{
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-application-preparation-nonready-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: base,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let storage = try productBootstrapStorageV1(base: base)
    let recoveryID = UUID(
        uuidString: "018f5000-0000-7000-8000-000000000104"
    )!
    let roots: [MacAgentPreparedApplicationRootResultV1] = [
        .waitForFirstUnlock,
        .requireLocalRecovery(.missingEstablishedKey),
        .recoveryFenced(recoveryID),
    ]

    for root in roots {
        let probe = ProductApplicationPreparationProbeV1()
        let result = try await productApplicationPrepareV1(
            storage: storage,
            intent: nil,
            probe: probe,
            loader: ProductBootstrapCountingLoaderV1(),
            prepareRoot: { _, _ in root }
        )
        switch (root, result) {
        case (.waitForFirstUnlock, .waitForFirstUnlock),
             (
                .requireLocalRecovery(.missingEstablishedKey),
                .requireLocalRecovery(.missingEstablishedKey)
             ),
             (.recoveryFenced(recoveryID), .recoveryFenced(recoveryID)):
            break
        default:
            Issue.record("nonready result mapping changed")
        }
        #expect(probe.snapshot().finishes == 0)
    }
}

@available(macOS 26.0, *)
@Test func productionRecoveryFactoryReceivesExactFreshAndResumeModes()
    async throws
{
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-application-preparation-recovery-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: base,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let storage = try productBootstrapStorageV1(base: base)
    let recoveryID = UUID(
        uuidString: "018f5000-0000-7000-8000-000000000106"
    )!
    let configuration = try SecurityHostIdentityKeyCustodyConfigurationV0(
        applicationTagPrefix: "media.jenny.maccompanion.tests.recovery"
    )
    let cases: [(
        root: MacAgentPreparedApplicationRootResultV1,
        expected: MacAgentHostIdentityRecoveryModeV1
    )] = [
        (
            .requireLocalRecovery(.invalidEstablishedKey),
            .fresh(.invalidEstablishedKey)
        ),
        (.recoveryFenced(recoveryID), .resume(recoveryID)),
    ]

    for entry in cases {
        let recorded = ProductApplicationRecoveryModeProbeV1()
        let result = try await productApplicationPrepareV1(
            storage: storage,
            intent: nil,
            probe: ProductApplicationPreparationProbeV1(),
            loader: ProductBootstrapCountingLoaderV1(),
            prepareRoot: { _, _ in entry.root },
            makeHostIdentityRecovery: { storage, mode in
                await recorded.record(mode)
                return MacAgentHostIdentityRecoveryProductV1(
                    storage: storage,
                    hostIdentityConfiguration: configuration,
                    mode: mode
                )
            }
        )
        guard case let .hostIdentityRecovery(product) = result else {
            Issue.record("expected recovery product")
            continue
        }
        #expect(await recorded.values() == [entry.expected])
        #expect(await product.authenticatedMenuGeneration() == nil)
        await product.finish()
    }
}

@available(macOS 26.0, *)
@Test func preparationReopensExactDurableIntentDirectory()
    async throws
{
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-application-preparation-reopen-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: base,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let makeStorage: @Sendable () throws -> MacAgentReleaseStorageV1 = {
        try productBootstrapStorageV1(base: base)
    }
    let loader = ProductBootstrapCountingLoaderV1()

    func prepare() async throws -> ProductLifecycleState {
        let capture = ProductApplicationPreparationProbeV1()
        _ = try await MacAgentApplicationPreparationFacadeV1.prepare(
            makeStorage: makeStorage,
            makeIntentStore: {
                try AtomicFileMacRemoteAccessIntentStoreV1(directory: $0)
            },
            makePrimaryInputs: { state in
                capture.record(state)
                return try productBootstrapInputsV1(
                    loader: loader,
                    lifecycleState: state
                )
            },
            prepareRoot: { _, _ in .waitForFirstUnlock }
        )
        return try #require(capture.snapshot().states.last)
    }

    #expect(!(try await prepare()).desiredEnabled)
    let storage = try makeStorage()
    let store = try AtomicFileMacRemoteAccessIntentStoreV1(
        directory: storage.paths.remoteAccessIntentDirectory
    )
    #expect(
        try await store.replaceAtomically(
            productApplicationIntentV1(enabled: true),
            expectedRevision: nil
        ) == .inserted
    )
    let restored = try await prepare()
    #expect(restored.desiredEnabled)
    #expect(restored.consoleSession == .otherConsoleUserActive)
    #expect(restored.agent == .starting)
    #expect(restored.menuApp == .starting)
}

@available(macOS 26.0, *)
@Test func productBootstrapRetainsExactPreparedRootAndFinishesOnce()
    async throws
{
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-product-bootstrap-ready-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: base,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let storage = try productBootstrapStorageV1(base: base)
    let identity = try productBootstrapIdentityV1()
    try await storage.requiredAudit.securityStore.establishHostIdentity(
        identity.stored
    )
    let loader = ProductBootstrapCountingLoaderV1()
    let localXPCProbe = ProductBootstrapLocalXPCProbeV1()

    guard case let .ready(product) = try await
        MacAgentProductBootstrapV1.prepare(
            storage: storage,
            hostIdentityStartup: {
                .ready(
                    record: identity.stored,
                    issuedIdentity: identity.issued,
                    renewalRecommended: false
                )
            },
            inputs: try productBootstrapInputsV1(loader: loader),
            makeLocalXPC: { services in
                await localXPCProbe.record(services.hostID)
                return productBootstrapLocalXPCV1()
            }
        ) else {
        Issue.record("expected ready prepared Mac Agent product")
        return
    }
    #expect(product.hostID == identity.stored.hostID)
    #expect(product.storagePaths == storage.paths)
    #expect(await localXPCProbe.recordedHostIDs() == [identity.stored.hostID])
    #expect(await loader.loadCount() == 1)
    #expect(!(await product.preparedPrimarySnapshot().consumed))
    #expect(!(await product.snapshot().finished))

    await product.finish()
    await product.finish()
    #expect(await product.snapshot().finished)
    #expect(await product.preparedPrimarySnapshot().consumed)
}

@available(macOS 26.0, *)
@Test func productBootstrapNonreadyResultsConstructNoLocalXPC()
    async throws
{
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-product-bootstrap-nonready-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: base,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let storage = try productBootstrapStorageV1(base: base)
    let loader = ProductBootstrapCountingLoaderV1()
    let localXPCProbe = ProductBootstrapLocalXPCProbeV1()
    let makeLocalXPC: MacAgentProductBootstrapV1.LocalXPCFactory = {
        services in
        await localXPCProbe.record(services.hostID)
        return productBootstrapLocalXPCV1()
    }
    let inputs = try productBootstrapInputsV1(loader: loader)

    guard case .waitForFirstUnlock = try await
        MacAgentProductBootstrapV1.prepare(
            storage: storage,
            hostIdentityStartup: { .waitForFirstUnlock },
            inputs: inputs,
            makeLocalXPC: makeLocalXPC
        ) else {
        Issue.record("expected first-unlock wait")
        return
    }
    guard case .requireLocalRecovery(.invalidEstablishedKey) = try await
        MacAgentProductBootstrapV1.prepare(
            storage: storage,
            hostIdentityStartup: {
                .requireLocalRecovery(.invalidEstablishedKey)
            },
            inputs: inputs,
            makeLocalXPC: makeLocalXPC
        ) else {
        Issue.record("expected local recovery requirement")
        return
    }
    let recoveryID = UUID()
    guard case .recoveryFenced(recoveryID) = try await
        MacAgentProductBootstrapV1.prepare(
            storage: storage,
            hostIdentityStartup: { .recoveryFenced(recoveryID) },
            inputs: inputs,
            makeLocalXPC: makeLocalXPC
        ) else {
        Issue.record("expected fenced recovery")
        return
    }
    #expect(await loader.loadCount() == 0)
    #expect(await localXPCProbe.recordedHostIDs().isEmpty)
}

@available(macOS 26.0, *)
@Test func concurrentFinishCallsAwaitOneTerminalBarrier() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-product-bootstrap-finish-barrier-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: base,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let storage = try productBootstrapStorageV1(base: base)
    let identity = try productBootstrapIdentityV1()
    try await storage.requiredAudit.securityStore.establishHostIdentity(
        identity.stored
    )
    let loader = ProductBootstrapCountingLoaderV1()
    guard case let .ready(prepared) = try await
        AgentNetworkPrimaryStartupFactoryV1.prepare(
            hostIdentityStartup: {
                .ready(
                    record: identity.stored,
                    issuedIdentity: identity.issued,
                    renewalRecommended: false
                )
            },
            requiredAudit: storage.requiredAudit,
            inputs: try productBootstrapInputsV1(loader: loader)
        ) else {
        Issue.record("expected prepared primary root")
        return
    }
    let finishGate = ProductBootstrapFinishGateV1()
    let interactiveRuntimeAuthority =
        AgentInteractiveRuntimeBindingAuthorityV1()
    let product = MacAgentPreparedProductV1(
        storage: storage,
        preparedPrimary: prepared,
        finishLocalXPC: { await finishGate.run() },
        interactiveRuntimeAuthority: interactiveRuntimeAuthority
    )
    let first = Task { await product.finish() }
    await finishGate.waitUntilEntered()
    let secondStarted = ProductBootstrapCompletionProbeV1()
    let secondCompleted = ProductBootstrapCompletionProbeV1()
    let second = Task {
        await secondStarted.record()
        await product.finish()
        await secondCompleted.record()
    }
    while !(await secondStarted.snapshot()) { await Task.yield() }
    for _ in 0..<100 { await Task.yield() }

    #expect(!(await secondCompleted.snapshot()))
    #expect(!(await product.snapshot().finished))
    #expect(!(await prepared.snapshot().consumed))
    #expect(await interactiveRuntimeAuthority.state() == .terminal)
    #expect(await finishGate.count() == 1)

    await finishGate.release()
    await first.value
    await second.value
    #expect(await secondCompleted.snapshot())
    #expect(await product.snapshot().finished)
    #expect(await prepared.snapshot().consumed)
    #expect(await finishGate.count() == 1)
}

@available(macOS 26.0, *)
@Test func localXPCConstructionFailureConsumesPreparedPrimary() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-product-bootstrap-xpc-failure-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: base,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let storage = try productBootstrapStorageV1(base: base)
    let identity = try productBootstrapIdentityV1()
    try await storage.requiredAudit.securityStore.establishHostIdentity(
        identity.stored
    )
    let loader = ProductBootstrapCountingLoaderV1()
    guard case let .ready(prepared) = try await
        AgentNetworkPrimaryStartupFactoryV1.prepare(
            hostIdentityStartup: {
                .ready(
                    record: identity.stored,
                    issuedIdentity: identity.issued,
                    renewalRecommended: false
                )
            },
            requiredAudit: storage.requiredAudit,
            inputs: try productBootstrapInputsV1(loader: loader)
        ) else {
        Issue.record("expected prepared primary root")
        return
    }

    await #expect(throws: ProductBootstrapProbeErrorV1.rejectedLocalXPC) {
        _ = try await MacAgentProductBootstrapV1.compose(
            storage: storage,
            preparation: .ready(prepared),
            makeLocalXPC: { _ in
                throw ProductBootstrapProbeErrorV1.rejectedLocalXPC
            }
        )
    }
    #expect(await prepared.snapshot().consumed)
}

@available(macOS 26.0, *)
@Test func existingLocalStartCannotReportSuccessAcrossFinish() async throws {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-product-bootstrap-start-finish-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: base,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let storage = try productBootstrapStorageV1(base: base)
    let identity = try productBootstrapIdentityV1()
    try await storage.requiredAudit.securityStore.establishHostIdentity(
        identity.stored
    )
    guard case let .ready(prepared) = try await
        AgentNetworkPrimaryStartupFactoryV1.prepare(
            hostIdentityStartup: {
                .ready(
                    record: identity.stored,
                    issuedIdentity: identity.issued,
                    renewalRecommended: false
                )
            },
            requiredAudit: storage.requiredAudit,
            inputs: try productBootstrapInputsV1(
                loader: ProductBootstrapCountingLoaderV1()
            )
        ) else {
        Issue.record("expected prepared primary root")
        return
    }
    let startGate = ProductBootstrapFinishGateV1()
    let finishEntered = ProductBootstrapCompletionProbeV1()
    let product = MacAgentPreparedProductV1(
        storage: storage,
        preparedPrimary: prepared,
        startLocalXPC: { await startGate.run() },
        finishLocalXPC: { await finishEntered.record() }
    )

    let firstStart = Task { try await product.startLocalAuthorization() }
    await startGate.waitUntilEntered()
    let secondStart = Task { try await product.startLocalAuthorization() }
    for _ in 0..<100 { await Task.yield() }
    let finish = Task { await product.finish() }
    while !(await finishEntered.snapshot()) { await Task.yield() }

    await startGate.release()
    await #expect(
        throws: MacAgentPreparedProductCompositionErrorV1.terminal
    ) {
        try await firstStart.value
    }
    await #expect(
        throws: MacAgentPreparedProductCompositionErrorV1.terminal
    ) {
        try await secondStart.value
    }
    await finish.value
    #expect(await product.snapshot().finished)
}

@available(macOS 26.0, *)
@Test func preparedProductConsumesNetworkRootOnlyAfterMenuAuthorization()
    async throws
{
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-product-bootstrap-authorized-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: base,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: base) }
    let storage = try productBootstrapStorageV1(base: base)
    let identity = try productBootstrapIdentityV1()
    try await storage.requiredAudit.securityStore.establishHostIdentity(
        identity.stored
    )
    guard case let .ready(prepared) = try await
        AgentNetworkPrimaryStartupFactoryV1.prepare(
            hostIdentityStartup: {
                .ready(
                    record: identity.stored,
                    issuedIdentity: identity.issued,
                    renewalRecommended: false
                )
            },
            requiredAudit: storage.requiredAudit,
            inputs: try productBootstrapInputsV1(
                loader: ProductBootstrapCountingLoaderV1()
            )
        ) else {
        Issue.record("expected prepared primary root")
        return
    }
    let authority = MacAgentAuthenticatedMenuSurfaceAuthorityV1()
    let compositionGate = ProductBootstrapMenuGenerationGateV1()
    let localStart = ProductBootstrapCompletionProbeV1()
    let product = MacAgentPreparedProductV1(
        storage: storage,
        preparedPrimary: prepared,
        startLocalXPC: { await localStart.record() },
        finishLocalXPC: {},
        menuSurfaceAuthority: authority,
        currentMenuGeneration: {
            await compositionGate.waitIfArmed()
            return await authority.currentGeneration()
        }
    )
    let time = try AgentLocalPairingTimeSampleV0(
        wallNowUnixMilliseconds: productBootstrapTimeV1,
        monotonicNowMilliseconds: 100
    )
    let timeSource = StaticAgentLocalPairingTimeSourceV0(time)
    let policy = StaticAgentLocalPairingPolicySourceV0(
        PolicyRevision(rawValue: 1)
    )
    let listenerQueue = DispatchQueue(
        label: "media.jenny.maccompanion.tests.listener-preparation"
    )
    let primaryContext: @Sendable () -> NetworkHostRequestContextV0 = {
        NetworkHostRequestContextV0(
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: productBootstrapTimeV1,
            monotonicNowMilliseconds: 100,
            responseMessageID: WireUUID(UUID())
        )
    }
    let pairingContext: @Sendable () ->
        NetworkHostPairingRequestContextV0 = {
        NetworkHostPairingRequestContextV0(
            wallNowUnixMilliseconds: productBootstrapTimeV1,
            monotonicNowMilliseconds: 100,
            responseMessageID: WireUUID(UUID())
        )
    }

    await #expect(
        throws:
            MacAgentPreparedProductCompositionErrorV1
                .networkProductUnavailable
    ) {
        try await product.prepareNetworkListener(
            queue: listenerQueue,
            monotonicNowMilliseconds: { 100 },
            primaryContext: primaryContext,
            pairingRequestContext: pairingContext
        )
    }

    await #expect(
        throws:
            MacAgentPreparedProductCompositionErrorV1
                .authenticatedMenuUnavailable
    ) {
        _ = try await product.composeNetworkPairingProduct(
            port: 43_210,
            timeSource: timeSource,
            policySource: policy
        )
    }
    #expect(!(await prepared.snapshot().consumed))

    let activationCompleted = ProductBootstrapCompletionProbeV1()
    let activation = Task {
        try await product.startAndComposeNetworkPairingProduct(
                port: 43_210,
                timeSource: timeSource,
                policySource: policy
            )
        await activationCompleted.record()
    }
    while !(await localStart.snapshot()) { await Task.yield() }
    for _ in 0..<100 { await Task.yield() }
    #expect(!(await activationCompleted.snapshot()))
    #expect(!(await prepared.snapshot().consumed))

    let router = MacLocalXPCAuthenticatedMenuSurfaceRouterV1()
    let surfaces = try await router.bindAuthenticated(
        generation: 1,
        endpointFactory: { ProductBootstrapMenuEndpointV1() }
    )
    await compositionGate.arm()
    try await authority.install(surfaces)
    await compositionGate.waitUntilEntered()
    await #expect(
        throws:
            MacAgentPreparedProductCompositionErrorV1
                .networkProductAlreadyComposed
    ) {
        _ = try await product.composeNetworkPairingProduct(
            port: 43_210,
            timeSource: timeSource,
            policySource: policy
        )
    }
    await compositionGate.release()
    try await activation.value
    #expect(await prepared.snapshot().consumed)
    #expect(await product.networkPairingProductSnapshot()
        == AgentNetworkPairingProductCompositionSnapshotV0(
            listenerServiceConstructed: false,
            terminal: false
        ))
    try await product.prepareNetworkListener(
        queue: listenerQueue,
        monotonicNowMilliseconds: { 100 },
        primaryContext: primaryContext,
        pairingRequestContext: pairingContext
    )
    #expect(await product.networkPairingProductSnapshot()
        == AgentNetworkPairingProductCompositionSnapshotV0(
            listenerServiceConstructed: true,
            terminal: false
        ))
    #expect(await product.networkListenerSnapshot()?.state == .idle)
    await #expect(
        throws:
            MacAgentPreparedProductCompositionErrorV1
                .networkListenerAlreadyStarted
    ) {
        try await product.prepareNetworkListener(
            queue: listenerQueue,
            monotonicNowMilliseconds: { 100 },
            primaryContext: primaryContext,
            pairingRequestContext: pairingContext
        )
    }
    await #expect(
        throws:
            MacAgentPreparedProductCompositionErrorV1
                .networkProductAlreadyComposed
    ) {
        _ = try await product.composeNetworkPairingProduct(
            port: 43_210,
            timeSource: timeSource,
            policySource: policy
        )
    }

    await product.authenticatedMenuSurfaceUnavailable(generation: 1)
    #expect(await product.authenticatedMenuSurfaceGeneration() == nil)
    #expect(await product.networkPairingProductSnapshot()
        == AgentNetworkPairingProductCompositionSnapshotV0(
            listenerServiceConstructed: true,
            terminal: false
        ))
    #expect(await product.networkListenerSnapshot()?.state == .idle)

    let replacement = try await router.bindAuthenticated(
        generation: 2,
        endpointFactory: { ProductBootstrapMenuEndpointV1() }
    )
    try await authority.install(replacement)
    #expect(await product.authenticatedMenuSurfaceGeneration() == 2)

    let terminalHandler = await product.networkListenerTerminalHandler()
    terminalHandler(.listenerFailed)
    while await product.networkListenerSnapshot()?.state != .terminal {
        await Task.yield()
    }
    await product.finish()
    #expect(await product.networkPairingProductSnapshot()
        == AgentNetworkPairingProductCompositionSnapshotV0(
            listenerServiceConstructed: true,
            terminal: true
        ))
    #expect(await product.networkListenerSnapshot()?.state == .terminal)
    await router.finish()
}

@available(macOS 26.0, *)
@Test func networkListenerRuntimeOwnerRollsBackFailureAndCancellation()
    async throws
{
    let rejected = ProductBootstrapNetworkListenerV1(rejectStart: true)
    let rejectedOwner = MacAgentNetworkListenerRuntimeOwnerV1(
        runtime: rejected
    )

    await #expect(
        throws: ProductBootstrapProbeErrorV1.rejectedNetworkListener
    ) {
        try await rejectedOwner.start()
    }
    #expect(await rejected.counts().starts == 1)
    #expect(await rejected.counts().cancellations == 1)
    #expect(await rejectedOwner.snapshot().state == .terminal)

    let gate = ProductBootstrapFinishGateV1()
    let suspended = ProductBootstrapNetworkListenerV1(
        startGate: gate,
        cancelReleasesStart: true
    )
    let suspendedOwner = MacAgentNetworkListenerRuntimeOwnerV1(
        runtime: suspended
    )
    let start = Task { try await suspendedOwner.start() }
    await gate.waitUntilEntered()
    start.cancel()
    await #expect(throws: CancellationError.self) {
        try await start.value
    }
    await suspendedOwner.finish()
    #expect(await suspended.counts().starts == 1)
    #expect(await suspended.counts().cancellations == 1)
    #expect(await suspendedOwner.snapshot().state == .terminal)

    let finishGate = ProductBootstrapFinishGateV1()
    let finishBlocked = ProductBootstrapNetworkListenerV1(
        startGate: finishGate
    )
    let finishBlockedOwner = MacAgentNetworkListenerRuntimeOwnerV1(
        runtime: finishBlocked
    )
    let blockedStart = Task { try await finishBlockedOwner.start() }
    await finishGate.waitUntilEntered()
    let finishCompleted = ProductBootstrapCompletionProbeV1()
    let finish = Task {
        await finishBlockedOwner.finish()
        await finishCompleted.record()
    }
    while await finishBlocked.counts().cancellations == 0 {
        await Task.yield()
    }
    #expect(!(await finishCompleted.snapshot()))
    #expect(await finishBlocked.counts().cancellations == 1)
    await finishGate.release()
    await finish.value
    _ = await blockedStart.result
    #expect(await finishBlockedOwner.snapshot().state == .terminal)

    let listening = ProductBootstrapNetworkListenerV1()
    let listeningOwner = MacAgentNetworkListenerRuntimeOwnerV1(
        runtime: listening
    )
    try await listeningOwner.start()
    await #expect(
        throws:
            MacAgentPreparedProductCompositionErrorV1
                .networkListenerAlreadyStarted
    ) {
        try await listeningOwner.start()
    }
    #expect(await listening.counts().starts == 1)
    #expect(await listening.counts().cancellations == 0)
    #expect(await listeningOwner.snapshot().state == .listening)
    try await listeningOwner.closeNetworkAdmission()
    #expect(await listeningOwner.snapshot().updateAdmissionState == .closed)
    try await listeningOwner.drainNetworkConnections()
    #expect(await listeningOwner.snapshot().updateAdmissionState == .drained)
    try await listeningOwner.reopenNetworkAdmission()
    #expect(await listeningOwner.snapshot().updateAdmissionState == .open)
    #expect(await listening.counts().admissionCloses == 1)
    #expect(await listening.counts().connectionDrains == 1)
    #expect(await listening.counts().admissionReopens == 1)
    await listeningOwner.finish()
    await #expect(
        throws: MacAgentPreparedProductCompositionErrorV1.terminal
    ) {
        try await listeningOwner.reopenNetworkAdmission()
    }

    let concurrentGate = ProductBootstrapFinishGateV1()
    let concurrent = ProductBootstrapNetworkListenerV1(
        startGate: concurrentGate
    )
    let concurrentOwner = MacAgentNetworkListenerRuntimeOwnerV1(
        runtime: concurrent
    )
    let firstStart = Task { try await concurrentOwner.start() }
    await concurrentGate.waitUntilEntered()
    await #expect(
        throws:
            MacAgentPreparedProductCompositionErrorV1
                .networkListenerAlreadyStarted
    ) {
        try await concurrentOwner.start()
    }
    #expect(await concurrent.counts().starts == 1)
    #expect(await concurrent.counts().cancellations == 0)
    await concurrentGate.release()
    try await firstStart.value
    #expect(await concurrentOwner.snapshot().state == .listening)
    await concurrentOwner.finish()
}
#endif
