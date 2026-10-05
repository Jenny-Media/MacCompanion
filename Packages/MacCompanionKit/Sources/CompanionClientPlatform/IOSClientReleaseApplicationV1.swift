#if os(iOS)
import CompanionClient
import CompanionClientApp
import CompanionClientNetworkPlatform
import CompanionDiscovery
import CompanionPresentation
import CompanionStudy
import CompanionWire
import Dispatch
import Foundation
import Observation

public enum IOSClientReleaseApplicationPhaseV1:
    String, Equatable, Sendable
{
    case idle
    case preparing
    case pairing
    case macLibrary
    case routeSetup
    case routeSetupDeferred
    case connecting
    case workspace
    case unavailable
    case closed
}

public enum IOSClientReleaseApplicationFailureV1:
    String, Equatable, Sendable
{
    case protectedStorageUnavailable
    case invalidInstallationIdentity
    case ambiguousSavedState
    case protectedKeyUnavailable
    case routeConfigurationUnavailable
    case pairingCompositionUnavailable
    case networkCompositionUnavailable
}

@available(iOS 17.0, *)
@MainActor
public struct IOSClientReleaseWorkspaceV1: Identifiable {
    /// One UI ownership generation. An explicit reconnect constructs new
    /// connection-owned state and must also construct a new SwiftUI subtree;
    /// retaining the previous model would keep rendering a retired primary.
    public let id: UUID
    public let hostID: UUID
    public let macName: String
    public let primaryState: NetworkClientPrimaryApplicationStateV0
    public let interactiveRoles:
        NetworkClientInteractiveRoleProductBindingV0
    public let initialDesktopProductFactory:
        UIKitClientNativeVideoCompositionV1.ProductFactory?
    public let studyCapture: Stage3StudyLocalCaptureV1
    public let studyCaptureFailure:
        @MainActor @Sendable () -> Void

    package init(
        id: UUID = UUID(),
        hostID: UUID,
        macName: String,
        primaryState: NetworkClientPrimaryApplicationStateV0,
        interactiveRoles:
            NetworkClientInteractiveRoleProductBindingV0,
        initialDesktopProductFactory:
            UIKitClientNativeVideoCompositionV1.ProductFactory? = nil,
        studyCapture: Stage3StudyLocalCaptureV1,
        studyCaptureFailure:
            @escaping @MainActor @Sendable () -> Void
    ) {
        self.id = id
        self.hostID = hostID
        self.macName = macName
        self.primaryState = primaryState
        self.interactiveRoles = interactiveRoles
        self.initialDesktopProductFactory = initialDesktopProductFactory
        self.studyCapture = studyCapture
        self.studyCaptureFailure = studyCaptureFailure
    }
}

@available(iOS 17.0, *)
@MainActor
public struct IOSClientReleaseApplicationSnapshotV1 {
    public static let idle = IOSClientReleaseApplicationSnapshotV1(
        revision: 0,
        phase: .idle,
        pairing: nil,
        routePlan: nil,
        workspace: nil,
        failure: nil
    )

    public let revision: UInt64
    public let phase: IOSClientReleaseApplicationPhaseV1
    public let pairing: PairingClientPresentation?
    public let routePlan: ClientConfiguredRouteBootstrapPlanV1?
    public let workspace: IOSClientReleaseWorkspaceV1?
    public let failure: IOSClientReleaseApplicationFailureV1?

    package init(
        revision: UInt64,
        phase: IOSClientReleaseApplicationPhaseV1,
        pairing: PairingClientPresentation?,
        routePlan: ClientConfiguredRouteBootstrapPlanV1?,
        workspace: IOSClientReleaseWorkspaceV1?,
        failure: IOSClientReleaseApplicationFailureV1?
    ) {
        self.revision = revision
        self.phase = phase
        self.pairing = pairing
        self.routePlan = routePlan
        self.workspace = workspace
        self.failure = failure
    }
}

/// One release-shaped iOS application owner. It is the only target-facing
/// composition surface for protected bootstrap, verified pairing, first-route
/// publication, configured reconnect, Observe, Act, and optional Control.
/// Pairing never starts Control; route provenance never grants authority; and
/// a partially completed pairing resumes route setup without dialing.
@available(iOS 17.0, *)
@MainActor
@Observable
public final class IOSClientReleaseApplicationV1 {
    public private(set) var snapshot =
        IOSClientReleaseApplicationSnapshotV1.idle
    public private(set) var studyReportOwner:
        Stage3StudyLocalReportOwnerV1?
    public private(set) var studyCapture: Stage3StudyLocalCaptureV1?
    public private(set) var studyCaptureFailed = false
    public private(set) var savedMacs: [ClientSavedMacV1] = []
    public private(set) var macManagementFailed = false

    private var bootstrap: IOSClientReleaseBootstrapV1?
    private var storage: IOSClientReleaseStorageV1?
    private var pairingOwner: ClientPairingApplicationOwnerV0?
    private var pairingGeneration: UUID?
    private var routePlan: ClientConfiguredRouteBootstrapPlanV1?
    private var networkProduct: UIKitClientConfiguredRouteNetworkProductV1?
    private var networkGeneration: UUID?
    private var networkDrain: Task<Void, Never>?
    private var transitionInProgress = false
    private var studyPairingStartedAtMilliseconds: Int64?
    private let nativeVideoAdapterFactory:
        UIKitClientNativeVideoCompositionV1.AdapterFactory?
    private let desktopCredentialRemoval: @Sendable (UUID) throws -> Void
    private let bootstrapFactory: @Sendable () -> IOSClientReleaseBootstrapV1

    public init(
        nativeVideoAdapterFactory: UIKitClientNativeVideoCompositionV1.AdapterFactory? = nil,
        desktopCredentialRemoval: @escaping @Sendable (UUID) throws -> Void = { _ in }
    ) {
        self.desktopCredentialRemoval = desktopCredentialRemoval
        self.nativeVideoAdapterFactory = nativeVideoAdapterFactory
        bootstrapFactory = { IOSClientReleaseBootstrapV1() }
    }

    #if DEBUG && targetEnvironment(simulator)
    public init(simulatorDevelopmentNativeVideoAdapterFactory:
        UIKitClientNativeVideoCompositionV1.AdapterFactory?,
        desktopCredentialRemoval: @escaping @Sendable (UUID) throws -> Void = { _ in }) {
        self.desktopCredentialRemoval = desktopCredentialRemoval
        nativeVideoAdapterFactory = simulatorDevelopmentNativeVideoAdapterFactory
        bootstrapFactory = { IOSClientReleaseBootstrapV1(simulatorDevelopment: ()) }
    }
    #endif

    public func start() async {
        guard !transitionInProgress else { return }
        switch snapshot.phase {
        case .idle, .unavailable:
            break
        case .preparing, .pairing, .macLibrary, .routeSetup, .routeSetupDeferred,
             .connecting, .workspace, .closed:
            return
        }
        transitionInProgress = true
        publish(phase: .preparing)
        defer { transitionInProgress = false }

        let bootstrap = bootstrapFactory()
        self.bootstrap = bootstrap
        let bootstrapSnapshot = await bootstrap.start()
        guard let storage = await bootstrap
            .preparedStorageForReleaseComposition() else {
            publish(
                phase: .unavailable,
                failure: Self.failure(for: bootstrapSnapshot.phase)
            )
            return
        }
        self.storage = storage
        studyReportOwner = storage.studyReportOwner
        studyCapture = storage.studyCapture
        guard await refreshMacLibrary(storage: storage) else { return }

        switch bootstrapSnapshot.phase {
        case .unpaired:
            preparePairing(storage: storage)
        case .macLibrary:
            publish(phase: .macLibrary)
        case let .pairedRouteConfigurationRequired(hostID):
            await prepareRouteSetup(
                expectedHostID: hostID,
                storage: storage,
                beginImmediately: false
            )
        case let .paired(hostID):
            await prepareWorkspace(
                expectedHostID: hostID,
                storage: storage
            )
        case .idle, .preparing, .unavailable, .closed:
            publish(
                phase: .unavailable,
                failure: Self.failure(for: bootstrapSnapshot.phase)
            )
        }
    }

    public func receivePairingScan(_ value: String) async {
        guard snapshot.phase == .pairing, let pairingOwner else { return }
        await beginStudyPairingIfActive()
        do {
            try await pairingOwner.receiveScan(value)
        } catch {
            await refreshPairingPresentation(from: pairingOwner)
        }
    }

    public func acceptPairingPreview() async {
        guard snapshot.phase == .pairing, let pairingOwner else { return }
        do {
            try await pairingOwner.acceptPreview()
        } catch {
            await refreshPairingPresentation(from: pairingOwner)
        }
    }

    public func cancelPairing() async {
        guard snapshot.phase == .pairing, let pairingOwner else { return }
        await pairingOwner.cancel()
        await refreshPairingPresentation(from: pairingOwner)
    }

    public func continueAfterPairing() async {
        guard snapshot.phase == .pairing, !transitionInProgress,
              let storage else { return }
        transitionInProgress = true
        defer { transitionInProgress = false }
        await prepareRouteSetup(
            expectedHostID: snapshot.pairing?.pairedHost?.hostID,
            storage: storage,
            beginImmediately: true
        )
    }

    public func deferRouteSetup() {
        guard snapshot.phase == .routeSetup, routePlan != nil else { return }
        publish(phase: .routeSetupDeferred, routePlan: routePlan)
    }

    public func resumeRouteSetup() {
        guard snapshot.phase == .routeSetupDeferred,
              routePlan != nil else { return }
        publish(phase: .routeSetup, routePlan: routePlan)
    }

    public func completeRouteSetup(
        _ choices: [
            EndpointCandidate: ClientConfiguredRouteProvenanceV1
        ]
    ) async {
        guard snapshot.phase == .routeSetup, !transitionInProgress,
              let routePlan, let storage else { return }
        transitionInProgress = true
        publish(phase: .connecting, routePlan: routePlan)
        defer { transitionInProgress = false }
        await publishRouteSetup(
            choices,
            routePlan: routePlan,
            storage: storage
        )
    }

    private func publishRouteSetup(
        _ choices: [
            EndpointCandidate: ClientConfiguredRouteProvenanceV1
        ],
        routePlan: ClientConfiguredRouteBootstrapPlanV1,
        storage: IOSClientReleaseStorageV1
    ) async {
        do {
            let authority = ClientConfiguredRouteBootstrapAuthorityV1(
                plan: routePlan,
                routeID: Self.makeRouteID,
                publish: { value in
                    _ = try await storage.routes.replaceAtomically(
                        value,
                        expectedRevision: nil
                    )
                }
            )
            _ = try await authority.complete(explicitChoices: choices)
            await prepareWorkspace(
                expectedHostID: routePlan.hostID,
                storage: storage
            )
        } catch {
            publish(
                phase: .routeSetup,
                routePlan: routePlan,
                failure: .routeConfigurationUnavailable
            )
        }
    }

    public func retry() async {
        guard snapshot.phase == .unavailable else { return }
        await retireOwnedProducts()
        publish(phase: .idle)
        await start()
    }

    /// Rebuilds the network product from the existing protected paired-host
    /// and configured-route stores. This neither repairs nor replaces trust,
    /// pairing, grants, routes, or approval keys; it is only an explicit retry
    /// of the same durable configured connection.
    public func reconnect() async {
        guard snapshot.phase == .workspace,
              !transitionInProgress,
              let storage,
              let workspace = snapshot.workspace else { return }
        transitionInProgress = true
        let hostID = workspace.hostID
        await retireOwnedProducts()
        publish(phase: .connecting)
        await prepareWorkspace(
            expectedHostID: hostID,
            storage: storage
        )
        transitionInProgress = false
    }

    public func showMacLibrary() async {
        guard !transitionInProgress, let storage, snapshot.phase != .closed else { return }
        transitionInProgress = true
        defer { transitionInProgress = false }
        await retireOwnedProducts()
        routePlan = nil
        guard await refreshMacLibrary(storage: storage) else { return }
        publish(phase: .macLibrary)
    }

    public func pairAnotherMac() async {
        guard snapshot.phase == .macLibrary, !transitionInProgress, let storage else { return }
        transitionInProgress = true
        defer { transitionInProgress = false }
        await retireOwnedProducts()
        preparePairing(storage: storage)
    }

    public func selectMac(_ hostID: UUID) async {
        guard snapshot.phase == .macLibrary, !transitionInProgress, let storage,
              savedMacs.contains(where: { $0.hostID == hostID }) else { return }
        transitionInProgress = true
        defer { transitionInProgress = false }
        await retireOwnedProducts()
        publish(phase: .connecting)
        do {
            guard !(try await storage.macLibrary.snapshot()).pendingRemovals.contains(hostID),
                  let record = try await storage.pairedHosts.pairedHost(hostID: hostID),
                  record.clientID == storage.clientID else { throw ClientMacLibraryErrorV1.conflictingInventory }
            try await storage.custody.registerPublishedIdentity(record)
            if try await storage.routes.snapshot(hostID: hostID) == nil {
                await prepareRouteSetup(expectedHostID: hostID, storage: storage, beginImmediately: true)
            } else { await prepareWorkspace(expectedHostID: hostID, storage: storage) }
        } catch {
            macManagementFailed = true
            publish(phase: .macLibrary)
        }
    }

    public func renameMac(_ hostID: UUID, name: String) async {
        guard snapshot.phase == .macLibrary, !transitionInProgress, let storage,
              savedMacs.contains(where: { $0.hostID == hostID }) else { return }
        transitionInProgress = true
        defer { transitionInProgress = false }
        do {
            var preferences = try await storage.macLibrary.snapshot()
            try preferences.rename(hostID: hostID, name: name)
            try await storage.macLibrary.replace(preferences)
            _ = await refreshMacLibrary(storage: storage)
        } catch { macManagementFailed = true }
    }

    public func forgetMac(_ hostID: UUID) async {
        guard snapshot.phase == .macLibrary, !transitionInProgress, let storage,
              savedMacs.contains(where: { $0.hostID == hostID }) else { return }
        transitionInProgress = true
        defer { transitionInProgress = false }
        await retireOwnedProducts()
        do {
            try desktopCredentialRemoval(hostID)
            var preferences = try await storage.macLibrary.snapshot()
            preferences.beginRemoval(hostID: hostID)
            try await storage.macLibrary.replace(preferences)
            try await storage.resumePendingMacRemovals()
            _ = await refreshMacLibrary(storage: storage)
            macManagementFailed = try await storage.macLibrary.snapshot().pendingRemovals.contains(hostID)
            if savedMacs.isEmpty, !macManagementFailed { preparePairing(storage: storage) }
        } catch { macManagementFailed = true }
    }

    private func refreshMacLibrary(storage: IOSClientReleaseStorageV1) async -> Bool {
        do {
            let preferences = try await storage.macLibrary.snapshot()
            savedMacs = try preferences.library(records: await storage.pairedHosts.allRecords(),
                clientID: storage.clientID, configuredHostIDs: storage.storedRouteHostIDs())
            macManagementFailed = false
            return true
        } catch {
            publish(phase: .unavailable, failure: .protectedStorageUnavailable)
            return false
        }
    }

    public func finish() async {
        guard snapshot.phase != .closed else { return }
        transitionInProgress = true
        await retireOwnedProducts()
        await bootstrap?.finish()
        bootstrap = nil
        storage = nil
        studyReportOwner = nil
        studyCapture = nil
        studyPairingStartedAtMilliseconds = nil
        routePlan = nil
        transitionInProgress = false
        publish(phase: .closed)
    }

    private func preparePairing(storage: IOSClientReleaseStorageV1) {
        do {
            let generation = UUID()
            pairingGeneration = generation
            let owner = try NetworkClientPairingApplicationCompositionV0
                .makeOwner(
                    clientID: storage.clientID,
                    custody: storage.custody,
                    persistence: storage.pairedHosts,
                    verificationQueue: DispatchQueue(
                        label: "media.jenny.maccompanion.ios.pairing.verify"
                    ),
                    connectionQueue: DispatchQueue(
                        label: "media.jenny.maccompanion.ios.pairing.connection"
                    ),
                    stateChanged: { [weak self] presentation in
                        await MainActor.run {
                            guard self?.pairingGeneration == generation else { return }
                            self?.pairingDidChange(presentation)
                        }
                    }
                )
            pairingOwner = owner
            publish(
                phase: .pairing,
                pairing: PairingClientPresentation()
            )
        } catch {
            publish(
                phase: .unavailable,
                failure: .pairingCompositionUnavailable
            )
        }
    }

    private func pairingDidChange(
        _ presentation: PairingClientPresentation
    ) {
        guard snapshot.phase == .pairing else { return }
        publish(phase: .pairing, pairing: presentation)
        switch presentation.phase {
        case .paired:
            Task { [weak self] in
                await self?.recordStudyPairingResult(
                    .completed,
                    developerIntervention: false
                )
            }
        case .failed:
            let result: Stage3StudyAttemptResultV1 = switch
                presentation.failure {
            case .hostRejected: .denied
            case .clientStorageUnavailable, .unknown, nil: .outcomeUnknown
            case .invalidOrExpiredCode, .connectionFailed,
                 .identityVerificationFailed: .failed
            }
            Task { [weak self] in
                await self?.recordStudyPairingResult(
                    result,
                    developerIntervention: false
                )
            }
        case .scanning, .preview, .starting, .securing, .compareOnMac,
             .recovering, .saving:
            break
        }
    }

    private func refreshPairingPresentation(
        from owner: ClientPairingApplicationOwnerV0
    ) async {
        pairingDidChange(await owner.snapshot())
    }

    private func prepareRouteSetup(
        expectedHostID: UUID?,
        storage: IOSClientReleaseStorageV1,
        beginImmediately: Bool
    ) async {
        let records: [ClientDurablePairedHostV0]
        do {
            records = try await storage.pairedHosts.allRecords()
        } catch {
            publish(
                phase: .unavailable,
                failure: .protectedStorageUnavailable
            )
            return
        }
        let pending = (try? await storage.macLibrary.snapshot())?.pendingRemovals
        guard let expectedHostID,
              let record = records.first(where: { $0.hostID == expectedHostID }),
              record.clientID == storage.clientID,
              pending?.contains(record.hostID) == false else {
            publish(
                phase: .unavailable,
                failure: .ambiguousSavedState
            )
            return
        }
        guard await refreshMacLibrary(storage: storage) else { return }
        let plan = ClientConfiguredRouteBootstrapPlanV1(
            pairedHost: record
        )
        routePlan = plan
        pairingOwner = nil
        if plan.endpointsRequiringExplicitChoice.isEmpty {
            publish(phase: .connecting, routePlan: plan)
            await publishRouteSetup(
                [:],
                routePlan: plan,
                storage: storage
            )
        } else {
            publish(
                phase: beginImmediately ? .routeSetup : .routeSetupDeferred,
                routePlan: plan
            )
        }
    }

    private func prepareWorkspace(
        expectedHostID: UUID,
        storage: IOSClientReleaseStorageV1
    ) async {
        guard !transitionInProgress || snapshot.phase == .connecting
                || snapshot.phase == .preparing else { return }
        publish(phase: .connecting)
        do {
            // Only native composition needs an additional session signer.
            // Resolve it from this workspace's exact durable paired host, using
            // the same protected custody as the normal primary connection.
            let nativeSigner: (any ClientSessionAuthenticationSigningV0)?
            if nativeVideoAdapterFactory != nil {
                guard let record = try await storage.pairedHosts.pairedHost(hostID: expectedHostID),
                      record.hostID == expectedHostID,
                      record.clientID == storage.clientID else {
                    throw IOSClientNativeVideoCompositionErrorV1.pairedHostUnavailable
                }
                nativeSigner = try ClientCustodiedSessionSignerV0(
                    custody: storage.custody, sessionKey: record.sessionKey
                )
            } else {
                nativeSigner = nil
            }
            let runtime = NetworkClientReconnectRuntimeV1(
                custody: storage.custody,
                sessionConsentProfile: .trustedDevice,
                clock: Self.clock,
                verificationQueue: DispatchQueue(
                    label: "media.jenny.maccompanion.ios.primary.verify"
                ),
                connectionQueue: DispatchQueue(
                    label: "media.jenny.maccompanion.ios.primary.connection"
                ),
                monotonicNow: Self.monotonicNow,
                jitterBasisPoints: {
                    UInt16.random(in: 8_000 ... 12_000)
                }
            )
            let generation = UUID()
            networkGeneration = generation
            let product = try await
                UIKitClientConfiguredRouteNetworkProductFactoryV1.make(
                    hostID: expectedHostID,
                    pairedHosts: storage.pairedHosts,
                    routes: storage.routes,
                    runtime: runtime,
                    failure: { [weak self] _ in
                        self?.networkDidFail(generation: generation)
                    }
            )
            do {
                try await product.applicationOwner.start()
                guard networkGeneration == generation, snapshot.phase == .connecting else {
                    throw IOSClientNativeVideoCompositionErrorV1.pairedHostUnavailable
                }
            } catch {
                await product.applicationOwner.stop()
                await product.interactiveRoles.close()
                await product.lifecycle.close()
                throw error
            }
            networkProduct = product
            routePlan = nil
            publish(
                phase: .workspace,
                workspace: IOSClientReleaseWorkspaceV1(
                    hostID: expectedHostID,
                    macName: savedMacs.first(where: { $0.hostID == expectedHostID })?.name ?? "Mac",
                    primaryState: product.primaryState,
                    interactiveRoles: product.interactiveRoles,
                    initialDesktopProductFactory: nativeSigner.flatMap { signer in
                        nativeVideoAdapterFactory.map { factory in
                            UIKitClientNativeVideoCompositionV1.productFactory(
                                signer: signer, primaryState: product.primaryState,
                                roles: product.interactiveRoles, adapterFactory: factory
                            )
                        }
                    },
                    studyCapture: storage.studyCapture,
                    studyCaptureFailure: { [weak self] in
                        self?.studyCaptureFailed = true
                    }
                )
            )
        } catch {
            publish(
                phase: .unavailable,
                failure: .networkCompositionUnavailable
            )
        }
    }

    private func networkDidFail(generation: UUID) {
        guard generation == networkGeneration else { return }
        guard snapshot.phase == .workspace || snapshot.phase == .connecting
        else { return }
        let product = networkProduct
        networkProduct = nil
        networkGeneration = nil
        publish(
            phase: .unavailable,
            failure: .networkCompositionUnavailable
        )
        networkDrain = Task {
            await product?.applicationOwner.stop()
            await product?.interactiveRoles.close()
            await product?.lifecycle.close()
        }
    }

    private func retireOwnedProducts() async {
        networkGeneration = nil
        pairingGeneration = nil
        if let networkDrain {
            await networkDrain.value
            self.networkDrain = nil
        }
        if let pairingOwner { await pairingOwner.cancel() }
        pairingOwner = nil
        if let networkProduct {
            await networkProduct.applicationOwner.stop()
            await networkProduct.interactiveRoles.close()
            await networkProduct.lifecycle.close()
        }
        networkProduct = nil
    }

    private func beginStudyPairingIfActive() async {
        guard let studyCapture else { return }
        do {
            _ = try await studyCapture.recordSetupAttempted()
            if studyPairingStartedAtMilliseconds == nil {
                let now = Self.monotonicNow()
                guard now >= 0 else {
                    throw Stage3StudyLocalCaptureErrorV1.invalidTransition
                }
                studyPairingStartedAtMilliseconds = now
            }
        } catch let error as Stage3StudyLocalCaptureErrorV1
            where error == .noActiveSession || error == .noEnrollment {
            return
        } catch {
            studyCaptureFailed = true
        }
    }

    private func recordStudyPairingResult(
        _ result: Stage3StudyAttemptResultV1,
        developerIntervention: Bool
    ) async {
        guard let studyCapture else { return }
        let duration: Int64?
        if result == .completed,
           let start = studyPairingStartedAtMilliseconds {
            duration = max(0, Self.monotonicNow() - start)
        } else {
            duration = nil
        }
        do {
            _ = try await studyCapture.recordPairingResult(
                result,
                developerIntervention: developerIntervention,
                durationMilliseconds: duration
            )
            if result == .completed {
                studyPairingStartedAtMilliseconds = nil
            }
        } catch let error as Stage3StudyLocalCaptureErrorV1
            where error == .noActiveSession || error == .noEnrollment {
            return
        } catch {
            studyCaptureFailed = true
        }
    }

    private func publish(
        phase: IOSClientReleaseApplicationPhaseV1,
        pairing: PairingClientPresentation? = nil,
        routePlan: ClientConfiguredRouteBootstrapPlanV1? = nil,
        workspace: IOSClientReleaseWorkspaceV1? = nil,
        failure: IOSClientReleaseApplicationFailureV1? = nil
    ) {
        snapshot = IOSClientReleaseApplicationSnapshotV1(
            revision: snapshot.revision + 1,
            phase: phase,
            pairing: pairing,
            routePlan: routePlan,
            workspace: workspace,
            failure: failure
        )
    }

    private static func failure(
        for phase: IOSClientReleaseBootstrapPhaseV1
    ) -> IOSClientReleaseApplicationFailureV1 {
        guard case let .unavailable(value) = phase else {
            return .protectedStorageUnavailable
        }
        return switch value {
        case .storageUnavailable:
            .protectedStorageUnavailable
        case .invalidInstallationIdentity:
            .invalidInstallationIdentity
        case .ambiguousSavedState:
            .ambiguousSavedState
        case .keyUnavailable:
            .protectedKeyUnavailable
        case .routeConfigurationMissing:
            .routeConfigurationUnavailable
        }
    }

    nonisolated private static func makeRouteID(
        _ endpoint: EndpointCandidate
    ) throws -> WireBytes16 {
        _ = endpoint
        var identifier = UUID().uuid
        return try withUnsafeBytes(of: &identifier) {
            try WireBytes16(Data($0))
        }
    }

    nonisolated private static func clock()
        -> NetworkClientClockSnapshotV0
    {
        NetworkClientClockSnapshotV0(
            wallNowUnixMilliseconds: max(
                0,
                Int64(Date().timeIntervalSince1970 * 1_000)
            ),
            monotonicNowMilliseconds:
                DispatchTime.now().uptimeNanoseconds / 1_000_000
        )
    }

    nonisolated private static func monotonicNow() -> Int64 {
        let value = DispatchTime.now().uptimeNanoseconds / 1_000_000
        return value <= UInt64(Int64.max) ? Int64(value) : -1
    }
}
private enum IOSClientNativeVideoCompositionErrorV1: Error {
    case pairedHostUnavailable
}
#endif
