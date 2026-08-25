#if os(macOS)
import AppKit
import CompanionAgentPlatform
import CompanionIPC
import CompanionInteractiveRuntime
import CompanionLocalXPCPlatform
import CompanionMacApp
import CompanionPresentation
import Observation
import OSLog

private let interactiveControlGrantLoggerV1 = Logger(
    subsystem: "media.jenny.maccompanion",
    category: "interactive-control-grant"
)

@available(macOS 26.0, *)
public enum MacCompanionDashboardApplicationErrorV1:
    Error,
    Equatable,
    Sendable
{
    case lifecycleUnavailable
}

@available(macOS 26.0, *)
public enum MacCompanionPairingActionV1: Sendable {
    case retryCreation
    case dismissPairing
    case retryDismissal
}

@available(macOS 26.0, *)
public enum MacCompanionPairingReviewActionV1: Sendable {
    case approve
    case decline
    case retryDecision
}

@available(macOS 26.0, *)
public enum MacCompanionInteractiveControlGrantActionV1:
    Equatable,
    Sendable
{
    case approve
    case decline
}

@available(macOS 26.0, *)
private final class MacCompanionPairingCommandProxyV1:
    MacPairingLocalIPCClientV0,
    MacPairingReviewLocalIPCClientV0,
    MacHostIdentityRecoveryLocalIPCClientV0,
    @unchecked Sendable
{
    private let lock = NSLock()
    private weak var product: (any MacCompanionDashboardProductV1)?

    func install(_ product: any MacCompanionDashboardProductV1) {
        lock.withLock {
            self.product = product
        }
    }

    func createPairingSession(
        _ command: LocalPairingSessionCreateCommandV0
    ) async throws -> LocalPairingSessionCreatedReceiptV0 {
        guard let product = lock.withLock({ self.product }) else {
            throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
        }
        return try await product.createPairingSession(command)
    }

    func dismissPairingSession(
        _ command: LocalPairingSessionDismissCommandV0
    ) async throws -> LocalPairingSessionDismissedReceiptV0 {
        guard let product = lock.withLock({ self.product }) else {
            throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
        }
        return try await product.dismissPairingSession(command)
    }

    func resolveLocalApproval(
        _ command: LocalPairingDecisionCommandV0
    ) async throws -> LocalPairingDecisionReceiptV0 {
        guard let product = lock.withLock({ self.product }) else {
            throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
        }
        return try await product.resolveLocalApproval(command)
    }

    func recoverHostIdentity(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) async throws -> LocalHostIdentityRecoveredReceiptV0 {
        guard let product = lock.withLock({ self.product }) else {
            throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
        }
        return try await product.recoverHostIdentity(command)
    }
}

@available(macOS 26.0, *)
package protocol MacCompanionDashboardProductV1: AnyObject, Sendable {
    func start() async throws
    func retryStatus() async -> MacAgentDashboardEffectOutcomeV0
    func createPairingSession(
        _ command: LocalPairingSessionCreateCommandV0
    ) async throws -> LocalPairingSessionCreatedReceiptV0
    func dismissPairingSession(
        _ command: LocalPairingSessionDismissCommandV0
    ) async throws -> LocalPairingSessionDismissedReceiptV0
    func resolveLocalApproval(
        _ command: LocalPairingDecisionCommandV0
    ) async throws -> LocalPairingDecisionReceiptV0
    func recoverHostIdentity(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) async throws -> LocalHostIdentityRecoveredReceiptV0
    func makeInteractiveControlGrantReview(
        _ request: LocalInteractiveControlGrantReviewRequestV0
    ) async throws -> LocalInteractiveControlGrantReviewV0
    func decideInteractiveControlGrant(
        _ command: LocalGrantDecisionCommandV0
    ) async throws -> LocalGrantDecisionReceiptV0
    func closeNetworkAdmissionForUpdate() async throws
    func drainNetworkConnectionsForUpdate() async throws
    func reopenNetworkAdmissionAfterUpdateFailure() async throws
    func finish() async
}

@available(macOS 26.0, *)
extension MacLocalXPCDashboardProductV1: MacCompanionDashboardProductV1 {}

@available(macOS 26.0, *)
extension MacCompanionDashboardProductV1 {
    package func createPairingSession(
        _: LocalPairingSessionCreateCommandV0
    ) async throws -> LocalPairingSessionCreatedReceiptV0 {
        throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
    }

    package func dismissPairingSession(
        _: LocalPairingSessionDismissCommandV0
    ) async throws -> LocalPairingSessionDismissedReceiptV0 {
        throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
    }

    package func resolveLocalApproval(
        _: LocalPairingDecisionCommandV0
    ) async throws -> LocalPairingDecisionReceiptV0 {
        throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
    }

    package func recoverHostIdentity(
        _: LocalHostIdentityRecoveryCommandV0
    ) async throws -> LocalHostIdentityRecoveredReceiptV0 {
        throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
    }

    package func makeInteractiveControlGrantReview(
        _: LocalInteractiveControlGrantReviewRequestV0
    ) async throws -> LocalInteractiveControlGrantReviewV0 {
        throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
    }

    package func decideInteractiveControlGrant(
        _: LocalGrantDecisionCommandV0
    ) async throws -> LocalGrantDecisionReceiptV0 {
        throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
    }

    package func closeNetworkAdmissionForUpdate() async throws {
        throw MacLocalXPCUpdateQuiescenceErrorV0.unavailable
    }

    package func drainNetworkConnectionsForUpdate() async throws {
        throw MacLocalXPCUpdateQuiescenceErrorV0.unavailable
    }

    package func reopenNetworkAdmissionAfterUpdateFailure() async throws {
        throw MacLocalXPCUpdateQuiescenceErrorV0.unavailable
    }
}

/// Permanent menu-process ownership of the already-constructed dashboard
/// product. Construction is deliberately transport-inert: only an explicit
/// start may create the local XPC session. The permanent application does not
/// call start until reciprocal signed-process and ready-Agent gates are open.
@available(macOS 26.0, *)
@MainActor
@Observable
public final class MacCompanionDashboardApplicationV1 {
    private typealias ProductFactory = @MainActor ()
        -> any MacCompanionDashboardProductV1

    private enum Phase {
        case idle
        case starting
        case active
        case finishing
        case finished
    }

    public private(set) var source: MacAgentDashboardSourceV0 = .unavailable
    public private(set) var pairingSession =
        MacPairingSessionPresentationV0()
    public private(set) var pairingReview =
        MacPairingReviewPresentationV0()
    public private(set) var hostIdentityRecovery =
        MacHostIdentityRecoveryPresentationV0()
    public private(set) var interactiveControlGrantReview:
        LocalGrantExpansionPresentation?
    public private(set) var interactiveControlGrantReviewLoading = false
    public private(set) var interactiveControlGrantReviewFailed = false
    public private(set) var interactiveControlGrantReviewFailureReason: String?
    public private(set) var interactiveControlGrantApproved = false

    @ObservationIgnored
    private var product: any MacCompanionDashboardProductV1
    @ObservationIgnored
    private let productFactory: ProductFactory
    @ObservationIgnored
    private let commandProxy: MacCompanionPairingCommandProxyV1?
    @ObservationIgnored
    private let stateRelay: MacCompanionDashboardStateRelayV1
    @ObservationIgnored
    private let pairingRelay: MacCompanionPairingStateRelayV1?
    @ObservationIgnored
    private let reviewRelay: MacCompanionPairingReviewStateRelayV1?
    @ObservationIgnored
    private let recoveryRelay: MacCompanionRecoveryStateRelayV1?
    @ObservationIgnored
    private let pairingOwner: MacPairingApplicationOwnerV0?
    @ObservationIgnored
    private let pairingReviewOwner: MacPairingReviewApplicationOwnerV0?
    @ObservationIgnored
    private let recoveryOwner: MacHostIdentityRecoveryApplicationOwnerV0?
    @ObservationIgnored
    private let interactiveDisplaySelection:
        MacInteractiveOpaqueDisplaySelectionV1?
    @ObservationIgnored
    private var phase: Phase = .idle
    @ObservationIgnored
    private var finishTask: Task<Void, Never>?
    @ObservationIgnored
    private var unavailableRecoveryTask: Task<Void, Never>?
    @ObservationIgnored
    private var unavailableRecoveryInProgress = false

    public convenience init() {
        self.init(interactiveRuntime: nil)
    }

    /// Release composition seam for the visible menu runtime. Passing a
    /// runtime does not start local XPC, capture, or input; those effects stay
    /// behind the existing explicit application start and an Agent-issued
    /// validated lease.
    public convenience init(
        interactiveRuntime: InteractiveMenuRuntimeOwnerV0
    ) {
        self.init(
            interactiveRuntime: Optional(interactiveRuntime),
            interactiveIndicator: nil,
            interactiveMediaQueue: nil,
            interactiveDisplaySelection: nil
        )
    }

    public convenience init(
        interactiveRuntime: InteractiveMenuRuntimeOwnerV0,
        interactiveIndicator: MacInteractiveActivityIndicatorV1
    ) {
        self.init(
            interactiveRuntime: Optional(interactiveRuntime),
            interactiveIndicator: interactiveIndicator,
            interactiveMediaQueue: nil,
            interactiveDisplaySelection: nil
        )
    }

    /// Permanent release composition. Construction is effect-inert: the
    /// concrete capture, encoder, media drain, and input poster remain behind
    /// the authenticated local-XPC lifecycle and an Agent-issued lease.
    public convenience init(
        interactiveIndicator: MacInteractiveActivityIndicatorV1,
        agentBuildLifetime: MacAuthenticatedAgentBuildLifetimeV0 = .init()
    ) {
        let displaySelection = try?
            MacInteractiveOpaqueDisplaySelectionV1()
        if let displaySelection,
           let composition = try?
            MacInteractiveControlRuntimeCompositionV1.make(
                indicator: interactiveIndicator,
                displaySelection: displaySelection
            ) {
            self.init(
                interactiveRuntime: composition.runtime,
                interactiveIndicator: interactiveIndicator,
                agentBuildLifetime: agentBuildLifetime,
                interactiveMediaQueue: composition.mediaQueue,
                interactiveDisplaySelection: displaySelection,
                interactiveSurfaceTargets: composition.surfaceTargets
            )
        } else {
            self.init(
                interactiveRuntime:
                    MacInteractiveUnavailableRuntimeCompositionV1.make(
                        indicator: interactiveIndicator
                    ),
                interactiveIndicator: interactiveIndicator,
                agentBuildLifetime: agentBuildLifetime,
                interactiveMediaQueue: nil,
                interactiveDisplaySelection: displaySelection
            )
        }
    }

    private convenience init(
        interactiveRuntime: InteractiveMenuRuntimeOwnerV0?,
        interactiveIndicator: MacInteractiveActivityIndicatorV1? = nil,
        agentBuildLifetime: MacAuthenticatedAgentBuildLifetimeV0 = .init(),
        interactiveMediaQueue: BoundedInteractiveMediaQueueV0? = nil,
        interactiveDisplaySelection providedDisplaySelection:
            MacInteractiveOpaqueDisplaySelectionV1? = nil,
        interactiveSurfaceTargets:
            MacInteractiveSurfaceTargetOwnerV1? = nil
    ) {
        let interactiveDisplaySelection = providedDisplaySelection
            ?? (try? MacInteractiveOpaqueDisplaySelectionV1())
        let interactiveLeaseHandler:
            (any MacLocalXPCInteractiveLeaseHandlingV1)?
        let interactiveInputHandler:
            (any MacLocalXPCInteractiveInputHandlingV1)?
        if let interactiveRuntime, let interactiveDisplaySelection {
            let desktop = MacInteractiveInitialDesktopPreparerV1(
                displaySelection: interactiveDisplaySelection,
                surfaceTargets: interactiveSurfaceTargets
            )
            let handler = if let interactiveSurfaceTargets {
                MacInteractiveLeaseRuntimeAdapterV1(
                    runtime: interactiveRuntime,
                    desktop: desktop,
                    surfaceTargets: interactiveSurfaceTargets
                )
            } else {
                MacInteractiveLeaseRuntimeAdapterV1(
                    runtime: interactiveRuntime,
                    desktop: desktop
                )
            }
            interactiveLeaseHandler = handler
            interactiveInputHandler = handler
            interactiveIndicator?.installStopAction { [weak handler] in
                guard let handler else {
                    throw MacInteractiveActivityIndicatorErrorV1
                        .stopUnavailable
                }
                try await handler.stopInteractiveControlLocally()
            }
        } else {
            interactiveLeaseHandler = nil
            interactiveInputHandler = nil
        }
        let dashboardRelay = MacCompanionDashboardStateRelayV1()
        let dashboardOwner = MacAgentDashboardApplicationOwnerV0 {
            [weak dashboardRelay] source in
            await dashboardRelay?.receive(source)
        }
        let commandProxy = MacCompanionPairingCommandProxyV1()
        let pairingRelay = MacCompanionPairingStateRelayV1()
        let reviewRelay = MacCompanionPairingReviewStateRelayV1()
        let recoveryRelay = MacCompanionRecoveryStateRelayV1()
        let pairingOwner = MacPairingApplicationOwnerV0(
            client: commandProxy,
            stateChanged: { [weak pairingRelay] in
                await pairingRelay?.receive($0)
            }
        )
        let reviewOwner = MacPairingReviewApplicationOwnerV0(
            client: commandProxy,
            stateChanged: { [weak reviewRelay] in
                await reviewRelay?.receive($0)
            }
        )
        let recoveryOwner = MacHostIdentityRecoveryApplicationOwnerV0(
            client: commandProxy,
            stateChanged: { [weak recoveryRelay] in
                await recoveryRelay?.receive($0)
            }
        )
        let product = MacLocalXPCDashboardProductV1(
            owner: dashboardOwner,
            agentBuildLifetime: agentBuildLifetime,
            pairingReviews: reviewOwner,
            hostIdentityRecovery: recoveryOwner,
            interactiveLeaseHandler: interactiveLeaseHandler,
            interactiveInputHandler: interactiveInputHandler,
            interactiveMediaQueue: interactiveMediaQueue,
            selectedDisplayID: interactiveDisplaySelection?
                .opaqueSelectedDisplayID()
        )
        self.init(
            product: product,
            productFactory: {
                MacLocalXPCDashboardProductV1(
                    owner: dashboardOwner,
                    pairingReviews: reviewOwner,
                    hostIdentityRecovery: recoveryOwner,
                    interactiveLeaseHandler: interactiveLeaseHandler,
                    interactiveInputHandler: interactiveInputHandler,
                    interactiveMediaQueue: interactiveMediaQueue,
                    selectedDisplayID: interactiveDisplaySelection?
                        .opaqueSelectedDisplayID()
                )
            },
            commandProxy: commandProxy,
            stateRelay: dashboardRelay,
            pairingOwner: pairingOwner,
            pairingReviewOwner: reviewOwner,
            recoveryOwner: recoveryOwner,
            pairingRelay: pairingRelay,
            reviewRelay: reviewRelay,
            recoveryRelay: recoveryRelay,
            interactiveDisplaySelection: interactiveDisplaySelection
        )
        commandProxy.install(product)
    }

    package convenience init(
        productFactory: @escaping (
            MacAgentDashboardApplicationOwnerV0
        ) -> any MacCompanionDashboardProductV1
    ) {
        let relay = MacCompanionDashboardStateRelayV1()
        let owner = MacAgentDashboardApplicationOwnerV0 {
            [weak relay] source in
            await relay?.receive(source)
        }
        self.init(
            product: productFactory(owner),
            productFactory: { productFactory(owner) },
            commandProxy: nil,
            stateRelay: relay,
            pairingOwner: nil,
            pairingReviewOwner: nil,
            recoveryOwner: nil,
            pairingRelay: nil,
            reviewRelay: nil,
            recoveryRelay: nil,
            interactiveDisplaySelection: nil
        )
    }

    /// Test composition that exercises the same retained pairing-state relay
    /// used by the release application without opening a real local-XPC
    /// connection.
    package convenience init(
        testingPairingStateRelay: Void,
        productFactory: @escaping (
            MacAgentDashboardApplicationOwnerV0
        ) -> any MacCompanionDashboardProductV1
    ) {
        let dashboardRelay = MacCompanionDashboardStateRelayV1()
        let dashboardOwner = MacAgentDashboardApplicationOwnerV0 {
            [weak dashboardRelay] source in
            await dashboardRelay?.receive(source)
        }
        let product = productFactory(dashboardOwner)
        let commandProxy = MacCompanionPairingCommandProxyV1()
        let pairingRelay = MacCompanionPairingStateRelayV1()
        let pairingOwner = MacPairingApplicationOwnerV0(
            client: commandProxy,
            stateChanged: { [weak pairingRelay] in
                await pairingRelay?.receive($0)
            }
        )
        self.init(
            product: product,
            productFactory: { productFactory(dashboardOwner) },
            commandProxy: commandProxy,
            stateRelay: dashboardRelay,
            pairingOwner: pairingOwner,
            pairingReviewOwner: nil,
            recoveryOwner: nil,
            pairingRelay: pairingRelay,
            reviewRelay: nil,
            recoveryRelay: nil,
            interactiveDisplaySelection: nil
        )
        commandProxy.install(product)
    }

    private init(
        product: any MacCompanionDashboardProductV1,
        productFactory: @escaping ProductFactory,
        commandProxy: MacCompanionPairingCommandProxyV1?,
        stateRelay: MacCompanionDashboardStateRelayV1,
        pairingOwner: MacPairingApplicationOwnerV0?,
        pairingReviewOwner: MacPairingReviewApplicationOwnerV0?,
        recoveryOwner: MacHostIdentityRecoveryApplicationOwnerV0?,
        pairingRelay: MacCompanionPairingStateRelayV1?,
        reviewRelay: MacCompanionPairingReviewStateRelayV1?,
        recoveryRelay: MacCompanionRecoveryStateRelayV1?,
        interactiveDisplaySelection:
            MacInteractiveOpaqueDisplaySelectionV1?
    ) {
        self.product = product
        self.productFactory = productFactory
        self.commandProxy = commandProxy
        self.stateRelay = stateRelay
        self.pairingRelay = pairingRelay
        self.reviewRelay = reviewRelay
        self.recoveryRelay = recoveryRelay
        self.pairingOwner = pairingOwner
        self.pairingReviewOwner = pairingReviewOwner
        self.recoveryOwner = recoveryOwner
        self.interactiveDisplaySelection = interactiveDisplaySelection
        stateRelay.application = self
        pairingRelay?.application = self
        reviewRelay?.application = self
        recoveryRelay?.application = self
    }

    /// Reserved for the signed-runtime checkpoint. Calling this method is the
    /// sole transition that may activate the constructed local XPC product.
    package func start() async throws {
        guard phase == .idle else {
            throw MacCompanionDashboardApplicationErrorV1
                .lifecycleUnavailable
        }
        phase = .starting
        do {
            try await withTaskCancellationHandler {
                try Task.checkCancellation()
                try await product.start()
                try Task.checkCancellation()
            } onCancel: { [weak self] in
                Task { @MainActor in
                    await self?.finish()
                }
            }
        } catch {
            await finish()
            throw error
        }
        guard phase == .starting else {
            await finish()
            throw MacCompanionDashboardApplicationErrorV1
                .lifecycleUnavailable
        }
        phase = .active
    }

    @discardableResult
    public func retryStatus() async -> MacAgentDashboardEffectOutcomeV0 {
        guard phase == .active else { return .notCompleted }
        let current = product
        let outcome = await current.retryStatus()
        guard phase == .active, product === current else {
            return .notCompleted
        }
        guard outcome == .notCompleted, source == .unavailable else {
            return outcome
        }
        return await replaceUnavailableProduct(current)
    }

    public func beginPairing() async {
        guard phase == .active,
              MacAgentDashboardActionPolicyV0.isEnabled(
                  .startPairing,
                  in: source
              ) else { return }
        try? await pairingOwner?.begin()
    }

    public func performPairingAction(
        _ action: MacCompanionPairingActionV1
    ) async {
        guard phase == .active, let pairingOwner else { return }
        switch action {
        case .retryCreation:
            try? await pairingOwner.retryCreation()
        case .dismissPairing:
            try? await pairingOwner.requestDismissal()
        case .retryDismissal:
            try? await pairingOwner.retryDismissal()
        }
    }

    public func updatePairingDeviceName(_ value: String) async {
        guard phase == .active else { return }
        try? await pairingReviewOwner?.updateDeviceNameDraft(value)
    }

    public func performPairingReviewAction(
        _ action: MacCompanionPairingReviewActionV1
    ) async {
        guard phase == .active, let pairingReviewOwner else { return }
        switch action {
        case .approve:
            try? await pairingReviewOwner.approve()
        case .decline:
            try? await pairingReviewOwner.decline()
        case .retryDecision:
            try? await pairingReviewOwner.retryDecision()
        }
    }

    public func beginInteractiveControlGrantReview() async {
        guard phase == .active,
              !interactiveControlGrantReviewLoading,
              interactiveControlGrantReview == nil,
              case let .status(status) = source,
              status.pairedDeviceCount == 1 else { return }
        interactiveControlGrantReviewLoading = true
        interactiveControlGrantReviewFailed = false
        interactiveControlGrantReviewFailureReason = nil
        let now = Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
        do {
            let request = try LocalInteractiveControlGrantReviewRequestV0(
                commandID: UUID(),
                requestedAtUnixMilliseconds: now
            )
            let review = try await product
                .makeInteractiveControlGrantReview(request)
            try review.validate(against: request)
            interactiveControlGrantReview = try
                LocalGrantExpansionPresentation(
                    reviewID: review.reviewID,
                    deviceID: review.deviceID,
                    deviceDisplayName: review.deviceDisplayName,
                    expectedAuthorizationEpoch: review.authorizationEpoch,
                    expectedGrantRevision: review.grantRevision,
                    expectedPolicyRevision: review.policyRevision,
                    currentGrants: review.currentGrantSet(),
                    requestedDescriptors: [
                        try InteractiveControlDurableGrantV0.descriptor(),
                    ]
                )
        } catch {
            interactiveControlGrantReviewFailed = true
            interactiveControlGrantReviewFailureReason = String(
                describing: error
            )
            interactiveControlGrantLoggerV1.error(
                "Review failed: \(String(describing: error), privacy: .public)"
            )
        }
        interactiveControlGrantReviewLoading = false
    }

    public func performInteractiveControlGrantAction(
        _ action: MacCompanionInteractiveControlGrantActionV1
    ) async {
        guard phase == .active,
              var presentation = interactiveControlGrantReview else { return }
        let commandID = UUID()
        let now = Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
        do {
            let intent: LocalGrantExpansionIntent
            switch action {
            case .approve:
                intent = try presentation.approve(decisionID: commandID)
            case .decline:
                intent = try presentation.decline(decisionID: commandID)
            }
            interactiveControlGrantReview = presentation
            let command = try intent.makeIPCCommand(
                decidedAtUnixMilliseconds: now
            )
            let receipt = try await product
                .decideInteractiveControlGrant(command)
            if action == .approve {
                try presentation.applicationSucceeded(
                    receipt: receipt,
                    command: command
                )
                interactiveControlGrantReview = presentation
                interactiveControlGrantApproved = true
                try? await Task.sleep(for: .milliseconds(650))
            }
            interactiveControlGrantReview = nil
            interactiveControlGrantReviewFailed = false
            interactiveControlGrantReviewFailureReason = nil
        } catch {
            interactiveControlGrantLoggerV1.error(
                "Decision failed: \(String(describing: error), privacy: .public)"
            )
            if action == .approve,
               case .applying(let decisionID) = presentation.phase {
                try? presentation.applicationFailed(decisionID: decisionID)
                interactiveControlGrantReview = presentation
            } else {
                interactiveControlGrantReview = nil
                interactiveControlGrantReviewFailed = true
                interactiveControlGrantReviewFailureReason = String(
                    describing: error
                )
            }
        }
    }

    public func dismissInteractiveControlGrantFailure() {
        interactiveControlGrantReviewFailed = false
        interactiveControlGrantReviewFailureReason = nil
    }

    /// Update-only commands over this exact dashboard generation. Construction
    /// and ordinary dashboard start never invoke them.
    public func closeNetworkAdmissionForUpdate() async throws {
        guard phase == .active else {
            throw MacLocalXPCUpdateQuiescenceErrorV0.unavailable
        }
        try await product.closeNetworkAdmissionForUpdate()
        guard phase == .active else {
            throw MacLocalXPCUpdateQuiescenceErrorV0.unavailable
        }
    }

    public func drainNetworkConnectionsForUpdate() async throws {
        guard phase == .active else {
            throw MacLocalXPCUpdateQuiescenceErrorV0.unavailable
        }
        try await product.drainNetworkConnectionsForUpdate()
        guard phase == .active else {
            throw MacLocalXPCUpdateQuiescenceErrorV0.unavailable
        }
    }

    public func reopenNetworkAdmissionAfterUpdateFailure() async throws {
        guard phase == .active else {
            throw MacLocalXPCUpdateQuiescenceErrorV0.unavailable
        }
        try await product.reopenNetworkAdmissionAfterUpdateFailure()
        guard phase == .active else {
            throw MacLocalXPCUpdateQuiescenceErrorV0.unavailable
        }
    }

    public func finish() async {
        if let finishTask {
            await finishTask.value
            return
        }
        guard phase != .finished else { return }
        phase = .finishing
        unavailableRecoveryTask?.cancel()
        unavailableRecoveryTask = nil
        let product = self.product
        let pairingOwner = self.pairingOwner
        let pairingReviewOwner = self.pairingReviewOwner
        let recoveryOwner = self.recoveryOwner
        let task = Task { @MainActor [weak self] in
            await pairingOwner?.agentInvalidated()
            await pairingReviewOwner?.agentInvalidated()
            await recoveryOwner?.agentInvalidated()
            await product.finish()
            guard let self else { return }
            self.source = .unavailable
            self.interactiveControlGrantReview = nil
            self.interactiveControlGrantReviewLoading = false
            self.interactiveControlGrantReviewFailed = false
            self.interactiveControlGrantReviewFailureReason = nil
            self.interactiveControlGrantApproved = false
            self.phase = .finished
        }
        finishTask = task
        await task.value
    }

    fileprivate func receive(_ source: MacAgentDashboardSourceV0) {
        guard phase == .starting || phase == .active || phase == .finishing
        else { return }
        self.source = source
        guard source == .unavailable else {
            unavailableRecoveryTask?.cancel()
            unavailableRecoveryTask = nil
            return
        }
        let pairingOwner = self.pairingOwner
        let pairingReviewOwner = self.pairingReviewOwner
        let recoveryOwner = self.recoveryOwner
        Task {
            await pairingOwner?.agentInvalidated()
            await pairingReviewOwner?.agentInvalidated()
            await recoveryOwner?.agentInvalidated()
        }
        scheduleUnavailableRecovery()
    }

    private func replaceUnavailableProduct(
        _ unavailableProduct: any MacCompanionDashboardProductV1
    ) async -> MacAgentDashboardEffectOutcomeV0 {
        guard !unavailableRecoveryInProgress else { return .notCompleted }
        unavailableRecoveryInProgress = true
        defer { unavailableRecoveryInProgress = false }

        await unavailableProduct.finish()
        guard phase == .active, product === unavailableProduct,
              source == .unavailable else {
            return .notCompleted
        }

        let replacement = productFactory()
        product = replacement
        commandProxy?.install(replacement)
        do {
            try await replacement.start()
        } catch {
            await replacement.finish()
            if phase == .active, product === replacement {
                source = .unavailable
            }
            return .notCompleted
        }
        guard phase == .active, product === replacement else {
            await replacement.finish()
            return .notCompleted
        }
        return .completed
    }

    private func scheduleUnavailableRecovery() {
        guard phase == .active,
              !unavailableRecoveryInProgress,
              unavailableRecoveryTask == nil else { return }
        unavailableRecoveryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard let self, self.phase == .active,
                  self.source == .unavailable else { return }
            self.unavailableRecoveryTask = nil
            _ = await self.retryStatus()
        }
    }

    fileprivate func receive(
        _ presentation: MacPairingSessionPresentationV0
    ) {
        pairingSession = presentation
    }

    fileprivate func receive(
        _ presentation: MacPairingReviewPresentationV0
    ) {
        pairingReview = presentation
    }

    fileprivate func receive(
        _ presentation: MacHostIdentityRecoveryPresentationV0
    ) {
        hostIdentityRecovery = presentation
    }

    deinit {
        guard finishTask == nil else { return }
        let product = self.product
        Task { await product.finish() }
    }
}

@available(macOS 26.0, *)
@MainActor
private final class MacCompanionDashboardStateRelayV1 {
    weak var application: MacCompanionDashboardApplicationV1?

    func receive(_ source: MacAgentDashboardSourceV0) {
        application?.receive(source)
    }
}

@available(macOS 26.0, *)
@MainActor
private final class MacCompanionPairingStateRelayV1 {
    weak var application: MacCompanionDashboardApplicationV1?

    func receive(_ presentation: MacPairingSessionPresentationV0) {
        application?.receive(presentation)
    }
}

@available(macOS 26.0, *)
@MainActor
private final class MacCompanionPairingReviewStateRelayV1 {
    weak var application: MacCompanionDashboardApplicationV1?

    func receive(_ presentation: MacPairingReviewPresentationV0) {
        application?.receive(presentation)
    }
}

@available(macOS 26.0, *)
@MainActor
private final class MacCompanionRecoveryStateRelayV1 {
    weak var application: MacCompanionDashboardApplicationV1?

    func receive(_ presentation: MacHostIdentityRecoveryPresentationV0) {
        application?.receive(presentation)
    }
}

/// Package-owned process-lifecycle bridge for the permanent containing app.
/// SwiftUI retains this object through `NSApplicationDelegateAdaptor`, but the
/// executable receives only the typed dashboard. It cannot call the package-
/// scoped transport start, construct a local-XPC product, or select a profile.
@available(macOS 26.0, *)
@MainActor
public final class MacCompanionDashboardApplicationDelegateV1:
    NSObject,
    NSApplicationDelegate
{
    public let dashboard: MacCompanionDashboardApplicationV1

    private var launchTask: Task<Void, Never>?
    private var finishTask: Task<Void, Never>?

    public override init() {
        dashboard = MacCompanionDashboardApplicationV1()
        super.init()
    }

    package init(dashboard: MacCompanionDashboardApplicationV1) {
        self.dashboard = dashboard
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        beginLaunch()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        beginBestEffortFinish()
    }

    package func beginLaunch() {
        guard launchTask == nil, finishTask == nil else { return }
        let dashboard = self.dashboard
        launchTask = Task { @MainActor in
            do {
                try await dashboard.start()
            } catch {
                await dashboard.finish()
            }
        }
    }

    package func waitForLaunch() async {
        await launchTask?.value
    }

    package func finish() async {
        if let finishTask {
            await finishTask.value
            return
        }
        let launchTask = self.launchTask
        let dashboard = self.dashboard
        launchTask?.cancel()
        let task = Task { @MainActor in
            if let launchTask { await launchTask.value }
            await dashboard.finish()
        }
        finishTask = task
        await task.value
    }

    private func beginBestEffortFinish() {
        Task { @MainActor [weak self] in
            await self?.finish()
        }
    }

    deinit {
        launchTask?.cancel()
        guard finishTask == nil else { return }
        let dashboard = self.dashboard
        Task { await dashboard.finish() }
    }
}
#endif
