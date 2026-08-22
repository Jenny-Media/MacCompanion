#if os(macOS)
import CompanionAgent
import CompanionAgentPlatform
import CompanionDomain
@testable import CompanionAgentProductPlatform
import CompanionLifecycle
import CompanionNetworkPlatform
import CompanionWire
import Dispatch
import Foundation
import Testing

private enum EnabledProductRuntimeProbeErrorV1: Error, Equatable {
    case composition
    case listener
}

private final class EnabledProductContextOrderProbeV1: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []

    func record(_ value: Bool) { lock.withLock { values.append(value) } }
    func snapshot() -> [Bool] { lock.withLock { values } }
}

@available(macOS 26.0, *)
private actor EnabledProductRuntimeProbeV1:
    MacAgentEnabledProductRuntimeProductV1
{
    private let compositionError: Bool
    private let listenerError: Bool
    private var events: [String] = []

    init(compositionError: Bool = false, listenerError: Bool = false) {
        self.compositionError = compositionError
        self.listenerError = listenerError
    }

    func composeForEnabledRuntime(
        port: UInt16,
        timeSource: any AgentLocalPairingTimeSamplingV0,
        policySource: any AgentLocalPairingPolicyReadingV0
    ) async throws {
        let time = try timeSource.currentPairingTime()
        let policy = try await policySource.currentPairingPolicyRevision()
        events.append(
            "compose:\(port):\(policy.rawValue):" +
                "\(time.wallNowUnixMilliseconds >= 0)"
        )
        if compositionError {
            throw EnabledProductRuntimeProbeErrorV1.composition
        }
    }

    func startListenerForEnabledRuntime(
        queue _: DispatchQueue,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64,
        primaryContext: @escaping @Sendable () ->
            NetworkHostRequestContextV0,
        pairingContext: @escaping @Sendable () ->
            NetworkHostPairingRequestContextV0
    ) async throws {
        let primary = primaryContext()
        let pairing = pairingContext()
        events.append(
            "listener:\(monotonicNowMilliseconds()):" +
                "\(primary.hostState.rawValue):" +
                "\(pairing.monotonicNowMilliseconds)"
        )
        if listenerError {
            throw EnabledProductRuntimeProbeErrorV1.listener
        }
    }

    func finish() async { events.append("finish") }

    func snapshot() -> [String] { events }
}

@available(macOS 26.0, *)
private func enabledRuntimePrimaryContextV1()
    -> NetworkHostRequestContextV0
{
    NetworkHostRequestContextV0(
        hostState: .otherConsoleUserActive,
        wallNowUnixMilliseconds: 1_000,
        monotonicNowMilliseconds: 2_000,
        responseMessageID: WireUUID(UUID())
    )
}

@available(macOS 26.0, *)
private func enabledRuntimePairingContextV1()
    -> NetworkHostPairingRequestContextV0
{
    NetworkHostPairingRequestContextV0(
        wallNowUnixMilliseconds: 1_001,
        monotonicNowMilliseconds: 2_001,
        responseMessageID: WireUUID(UUID())
    )
}

@available(macOS 26.0, *)
@Test func enabledRuntimeUsesOneFixedPrivatePortAndOrderedContexts()
    async throws
{
    #expect((49_152...65_535).contains(
        MacAgentEnabledProductProfileV1.listenerPort
    ))
    #expect(
        MacAgentEnabledProductProfileV1
            .initialPairingPolicyRevision.rawValue == 1
    )

    let probe = EnabledProductRuntimeProbeV1()
    let runtime = MacAgentEnabledProductRuntimeV1(
        product: probe,
        monotonicNowMilliseconds: { 77 }
    )
    try await runtime.start(
        primaryContext: enabledRuntimePrimaryContextV1,
        pairingContext: enabledRuntimePairingContextV1
    )
    #expect(await probe.snapshot() == [
        "compose:59653:1:true",
        "listener:77:otherConsoleUserActive:2001",
    ])

    await #expect(
        throws:
            MacAgentPreparedProductCompositionErrorV1
                .networkListenerAlreadyStarted
    ) {
        try await runtime.start(
            primaryContext: enabledRuntimePrimaryContextV1,
            pairingContext: enabledRuntimePairingContextV1
        )
    }
    await runtime.finish()
    await runtime.finish()
    #expect(await probe.snapshot().last == "finish")
    #expect(await probe.snapshot().filter { $0 == "finish" }.count == 1)
}

@available(macOS 26.0, *)
@Test(arguments: [true, false])
func enabledRuntimeFailureRetiresTheWholeProduct(
    compositionFailure: Bool
) async {
    let probe = EnabledProductRuntimeProbeV1(
        compositionError: compositionFailure,
        listenerError: !compositionFailure
    )
    let runtime = MacAgentEnabledProductRuntimeV1(product: probe)
    if compositionFailure {
        await #expect(throws: EnabledProductRuntimeProbeErrorV1.composition) {
            try await runtime.start(
                primaryContext: enabledRuntimePrimaryContextV1,
                pairingContext: enabledRuntimePairingContextV1
            )
        }
        #expect(await probe.snapshot().count == 2)
    } else {
        await #expect(throws: EnabledProductRuntimeProbeErrorV1.listener) {
            try await runtime.start(
                primaryContext: enabledRuntimePrimaryContextV1,
                pairingContext: enabledRuntimePairingContextV1
            )
        }
        #expect(await probe.snapshot().count == 3)
    }
    #expect(await probe.snapshot().last == "finish")
    await #expect(
        throws: MacAgentPreparedProductCompositionErrorV1.terminal
    ) {
        try await runtime.start(
            primaryContext: enabledRuntimePrimaryContextV1,
            pairingContext: enabledRuntimePairingContextV1
        )
    }
}

@available(macOS 26.0, *)
@Test func systemPairingTimeSourceProducesValidLiveSamples() throws {
    let source = SystemAgentLocalPairingTimeSourceV1()
    let first = try source.currentPairingTime()
    let second = try source.currentPairingTime()
    #expect(first.wallNowUnixMilliseconds > 0)
    #expect(first.monotonicNowMilliseconds > 0)
    #expect(second.wallNowUnixMilliseconds >= first.wallNowUnixMilliseconds)
    #expect(
        second.monotonicNowMilliseconds >= first.monotonicNowMilliseconds
    )
}

@available(macOS 26.0, *)
@Test func enabledLifecycleStartsContextsBeforeTheSelectedProduct()
    async throws
{
    let base = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-enabled-context-order-\(UUID())",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: base,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: base) }

    let storage = try MacAgentReleaseStorageV1(
        baseApplicationSupportDirectory: base
    )
    let contexts = MacAgentConservativeRequestContextProductV1()
    let probe = EnabledProductContextOrderProbeV1()
    let state = ProductLifecycleState(
        desiredEnabled: true,
        consoleSession: .otherConsoleUserActive,
        agent: .starting,
        menuApp: .starting
    )
    let prepared = MacAgentPreparedProductHandleV1(
        hostID: UUID(),
        storagePaths: storage.paths,
        currentLifecycle: {
            AgentRemoteLifecycleSnapshotV1(revision: 0, state: state)
        },
        startLocalService: {
            probe.record(contexts.snapshot().started)
        },
        finish: {}
    )
    let lifecycle = MacAgentInertApplicationLifecycleV1(
        requestContexts: contexts,
        prepared: prepared,
        intentStore: try AtomicFileMacRemoteAccessIntentStoreV1(
            directory: storage.paths.remoteAccessIntentDirectory
        )
    )

    #expect(!contexts.snapshot().started)
    try await lifecycle.startPreparedLocalService()
    #expect(probe.snapshot() == [true])
    #expect(contexts.snapshot().started)
    await lifecycle.finish()
    #expect(contexts.snapshot().finished)
}
#endif
