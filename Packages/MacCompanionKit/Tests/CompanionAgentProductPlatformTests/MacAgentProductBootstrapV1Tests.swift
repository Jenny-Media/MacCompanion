#if os(macOS)
import CompanionAgent
@testable import CompanionAgentNetworkPlatform
import CompanionAgentPlatform
@testable import CompanionAgentProductPlatform
import CompanionDiscovery
import CompanionHost
@testable import CompanionHostPlatform
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionIPC
import CompanionLifecycle
import CompanionLocalXPCPlatform
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
    loader: any AgentCapabilityProviderLoadingV1
) throws -> AgentNetworkPrimaryStartupInputsV1 {
    AgentNetworkPrimaryStartupInputsV1(
        registry: try CapabilityRegistrySnapshotV1(
            generation: UUID(),
            capabilities: []
        ),
        providerLoader: loader,
        wallNowUnixMilliseconds: productBootstrapTimeV1,
        lifecycleState: ProductLifecycleState(
            desiredEnabled: true,
            consoleSession: .active,
            agent: .starting,
            menuApp: .starting
        ),
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
    let product = MacAgentPreparedProductV1(
        storage: storage,
        preparedPrimary: prepared,
        finishLocalXPC: { await finishGate.run() }
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
#endif
