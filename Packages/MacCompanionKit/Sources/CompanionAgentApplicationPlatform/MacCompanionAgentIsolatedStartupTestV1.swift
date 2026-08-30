#if os(macOS) && DEBUG
import CompanionAgent
import CompanionAgentNetworkPlatform
import CompanionAgentPlatform
import CompanionAgentProductPlatform
import CompanionHostPlatform
import CompanionIPC
import CompanionLifecycle
import CompanionLocalXPCPlatform
import CompanionNetworkPlatform
import CompanionPersistence
import Darwin
import Foundation

/// Internal, @testable-only integration seam. Exercises the production startup
/// coordinator with disposable intent storage and real signed XPC. Preparation
/// is injected in the fault matrix. The productionPrimary mode instead uses
/// real primary/lifecycle/status owners with explicit software identity inputs.
/// Presentation mode uses a loopback-only listener. No mode uses production
/// Keychain custody or advertises on LAN.
@available(macOS 26.0, *)
enum MacCompanionAgentIsolatedStartupTestV1 {
    enum Mode: String, Sendable {
        case durableIntent, firstUnlock, preparationFailure
        case invalidRevision, listenerFailure
        case productionPrimary, productionPresentation
    }

    enum Failure: Error { case injected, unsafeDirectory }

    typealias PrimaryInputs = @Sendable (
        MacAgentReleaseStorageV1, ProductLifecycleState, SQLiteSecurityStore
    ) async throws -> (SecurityHostIdentityStartupResultV0, AgentNetworkPrimaryStartupInputsV1)

    static func start(
        testID: UUID,
        mode: Mode,
        statusReader: any MacLocalXPCStatusReadingV1,
        primaryInputs: PrimaryInputs? = nil,
        presentationReview: LocalPairingReviewV0? = nil,
        activeTestSession: Bool = false,
        onPhase: @escaping @Sendable (String) -> Void = { _ in },
        onEvent: @escaping MacLocalXPCServerV1.EventHandler,
        onFinish: @escaping @Sendable () -> Void
    ) async throws -> MacCompanionAgentLocalServiceStartupOutcomeV1 {
        try await MacCompanionAgentLocalServiceStartupV1.start(
            prepare: {
                if mode == .firstUnlock { return .deferred(.firstUnlockRequired) }
                if mode == .preparationFailure { throw Failure.injected }
                let base = URL(fileURLWithPath:
                    "/private/tmp/maccompanion-agent-xpc-\(testID.uuidString.lowercased())")
                let attributes = try FileManager.default.attributesOfItem(atPath: base.path)
                let canonical = realpath(base.path, nil)
                defer { free(canonical) }
                guard canonical.map({ String(cString: $0) }) == base.path,
                      attributes[.type] as? FileAttributeType == .typeDirectory,
                      (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
                      (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700 else {
                    throw Failure.unsafeDirectory
                }
                let storage = try MacAgentReleaseStorageV1(baseApplicationSupportDirectory: base)
                let intent = try AtomicFileMacRemoteAccessIntentStoreV1(
                    directory: storage.paths.remoteAccessIntentDirectory)
                let enabled = try await intent.current()?.desiredEnabled == true
                let process: ManagedProcessState = enabled ? .starting : .stopped
                if mode == .productionPrimary || mode == .productionPresentation {
                    guard let primaryInputs else { throw Failure.injected }
                    let initial = ProductLifecycleState(
                        desiredEnabled: enabled, consoleSession: activeTestSession ? .active : .otherConsoleUserActive,
                        agent: process, menuApp: process)
                    let (identity, inputs) = try await primaryInputs(storage, initial, storage.requiredAudit.securityStore)
                    guard inputs.lifecycleState == initial else { throw Failure.injected }
                    let result: MacAgentProductBootstrapResultV1
                    if mode == .productionPresentation {
                        result = try await MacAgentProductBootstrapV1.prepareIsolatedPresentation(
                            storage: storage, hostIdentityStartup: { identity }, inputs: inputs,
                            testID: testID, onEvent: onEvent)
                    } else {
                        result = try await MacAgentProductBootstrapV1.prepareInert(
                        storage: storage, hostIdentityStartup: { identity }, inputs: inputs,
                        makeLocalXPC: { services in
                            let observations = try await MacAgentLifecycleObservationRootV1
                                .afterAgentBootstrap(services: services,
                                    processStarter: InertMacDashboardLifecycleProcessStarterV1())
                            return MacLocalXPCAgentProductV1.compose(
                                lifecycleFactory: observations,
                                statusReader: MacLocalXPCStatusReaderV1(
                                    statusReader: services.localServices.statusReader),
                                serverFactory: { profile, reader, consume in
                                    MacLocalXPCServerV1(isolatedTestID: testID,
                                        profile: profile, statusReader: reader,
                                        onEvent: { event in consume(event); onEvent(event) })
                                })
                        })
                    }
                    guard case let .ready(product) = result else { throw Failure.injected }
                    let contexts = MacAgentConservativeRequestContextProductV1()
                    let presentationRuntime = mode == .productionPresentation
                        ? IsolatedPresentationRuntime(product: product, contexts: contexts,
                            review: presentationReview, activeTestSession: activeTestSession, onPhase: onPhase)
                        : nil
                    // Intentionally start only local authorization. The ordinary
                    // enabled handle also starts a fixed-port LAN listener.
                    let handle = MacAgentPreparedProductHandleV1(
                        hostID: product.hostID, storagePaths: product.storagePaths,
                        currentLifecycle: { await product.lifecycleSnapshot() },
                        startLocalService: {
                            if let presentationRuntime { try await presentationRuntime.start() }
                            else { try await product.startLocalAuthorization() }
                        },
                        finish: {
                            if let presentationRuntime { await presentationRuntime.finish() }
                            else { await product.finish() }
                            onFinish()
                        })
                    return .ready(MacCompanionAgentInertSystemOwnerV1(
                        prepared: MacAgentInertApplicationLifecycleV1(
                            requestContexts: contexts,
                            prepared: handle, intentStore: intent)))
                }
                let server = MacLocalXPCServerV1(
                    isolatedTestID: testID,
                    profile: .menuLifecycleReadinessAndStatus,
                    statusReader: statusReader,
                    agentBuild: mode == .listenerFailure ? nil : 1,
                    onEvent: onEvent)
                let prepared = MacAgentPreparedProductHandleV1(
                    hostID: testID,
                    storagePaths: storage.paths,
                    currentLifecycle: {
                        AgentRemoteLifecycleSnapshotV1(
                            revision: mode == .invalidRevision ? 1 : 0,
                            state: ProductLifecycleState(
                                desiredEnabled: enabled,
                                consoleSession: .otherConsoleUserActive,
                                agent: process, menuApp: process))
                    },
                    startLocalService: { try server.start() },
                    finish: { server.cancel(); onFinish() })
                return .ready(MacCompanionAgentInertSystemOwnerV1(
                    prepared: MacAgentInertApplicationLifecycleV1(
                        requestContexts: MacAgentConservativeRequestContextProductV1(),
                        prepared: prepared, intentStore: intent)))
            },
            makeAuthenticationOnly: {
                // No production service fallback is permitted in this seam.
                preconditionFailure("Isolated startup unexpectedly selected recovery")
            },
            makeDisabledBootstrap: { intent, restart in
                MacCompanionAgentDisabledBootstrapRuntimeV1(
                    isolatedTestID: testID, intentStore: intent, restartRequest: restart)
            })
    }
}

/// Retains the production menu/pairing composition while the disposable peer
/// connects. The real listener is bound only to 127.0.0.1; no LAN advertising.
@available(macOS 26.0, *)
private actor IsolatedPresentationRuntime {
    let runtime: MacAgentEnabledProductRuntimeV1
    let contexts: MacAgentConservativeRequestContextProductV1
    let activeTestSession: Bool

    init(product: MacAgentPreparedProductV1, contexts: MacAgentConservativeRequestContextProductV1,
         review: LocalPairingReviewV0?, activeTestSession: Bool, onPhase: @escaping @Sendable (String) -> Void) {
        runtime = MacAgentEnabledProductRuntimeV1(product:
            IsolatedLoopbackProduct(product: product, review: review, onPhase: onPhase))
        self.contexts = contexts
        self.activeTestSession = activeTestSession
    }

    func start() async throws {
        let contexts = contexts
        let active = activeTestSession
        try await runtime.start(primaryContext: {
            guard active else { return contexts.primaryContext() }
            // Test-only session fact, never a claim about the actual console.
            return NetworkHostRequestContextV0(hostState: .userSessionActive,
                wallNowUnixMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000),
                monotonicNowMilliseconds: DispatchTime.now().uptimeNanoseconds / 1_000_000,
                responseMessageID: .init(UUID()))
        }, pairingContext: contexts.pairingContext)
    }

    func finish() async { await runtime.finish() }
}

/// Only the listener profile/port and visible test stimulus differ. The
/// production enabled runtime owns ordering, cancellation and joined teardown.
@available(macOS 26.0, *)
private actor IsolatedLoopbackProduct: MacAgentEnabledProductRuntimeProductV1 {
    let product: MacAgentPreparedProductV1
    let review: LocalPairingReviewV0?
    let onPhase: @Sendable (String) -> Void

    init(product: MacAgentPreparedProductV1, review: LocalPairingReviewV0?, onPhase: @escaping @Sendable (String) -> Void) {
        self.product = product; self.review = review; self.onPhase = onPhase
    }

    func composeForEnabledRuntime(port: UInt16, timeSource: any AgentLocalPairingTimeSamplingV0,
                                  policySource: any AgentLocalPairingPolicyReadingV0) async throws {
        try await product.startLocalAuthorization()
        onPhase("local-xpc-listening")
        try await product.startAndComposeNetworkPairingProduct(port: 59_654,
            timeSource: timeSource, policySource: policySource, binding: .isolatedLoopback)
        onPhase("pairing-composed")
    }

    func startListenerForEnabledRuntime(queue: DispatchQueue,
        monotonicNowMilliseconds: @escaping @Sendable () -> UInt64,
        primaryContext: @escaping @Sendable () -> NetworkHostRequestContextV0,
        pairingContext: @escaping @Sendable () -> NetworkHostPairingRequestContextV0) async throws {
        try await product.startNetworkListener(queue: queue,
            monotonicNowMilliseconds: monotonicNowMilliseconds,
            primaryContext: primaryContext, pairingRequestContext: pairingContext)
        let deadline = ContinuousClock.now + .seconds(5)
        var ready = false
        while ContinuousClock.now < deadline {
            if try await product.confirmIsolatedLoopbackEndpoint() { ready = true; break }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard ready else { throw MacCompanionAgentIsolatedStartupTestV1.Failure.injected }
        onPhase("isolated-loopback-ready")
        if let review {
            // Generated, non-authorizing transport payload, not a pairing transcript.
            let surface = await product.authorizedPairingReviewSurface()
            try await surface.presentLocalPairingReview(review)
            try await surface.presentLocalPairingReview(review)
            await surface.withdrawLocalPairingReview(reviewID: UUID())
            await surface.withdrawLocalPairingReview(reviewID: review.reviewID)
            onPhase("presentation-cycle-complete")
        }
    }

    func finish() async { await product.finish() }
}
#endif
