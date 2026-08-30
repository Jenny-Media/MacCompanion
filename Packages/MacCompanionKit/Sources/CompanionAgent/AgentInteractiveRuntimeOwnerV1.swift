import CompanionDomain
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionIPC
import CompanionWire
import Foundation
import OSLog

private let agentInteractiveRuntimeLoggerV1 = Logger(
    subsystem: "media.jenny.maccompanion.agent",
    category: "interactive-runtime"
)

public enum AgentInteractiveRuntimeOwnerErrorV1:
    Error,
    Equatable,
    Sendable
{
    case unavailable
    case finalAdmissionChanged
    case invalidDesktop
    case runtimeReceiptRejected
    case safetyRecoveryRequired
}

public enum AgentInteractiveRuntimeOwnerStateV1:
    Equatable,
    Sendable
{
    case idle
    case installing(interactiveSessionID: UUID)
    case active(interactiveSessionID: UUID, leaseID: UUID)
    case terminating(interactiveSessionID: UUID, leaseID: UUID)
    case safetyRecoveryRequired(interactiveSessionID: UUID)
}

public struct AgentInteractiveInitialDesktopRequestV1:
    Equatable,
    Sendable
{
    public let interactiveSessionID: UUID
    public let authorizationEpoch: AuthorizationEpoch
    public let selectedDisplayID: UUID
    public let interactionClasses: Set<SurfaceInteractionClass>
    public let nowMonotonicNanoseconds: UInt64

    public init(
        interactiveSessionID: UUID,
        authorizationEpoch: AuthorizationEpoch,
        selectedDisplayID: UUID,
        interactionClasses: Set<SurfaceInteractionClass>,
        nowMonotonicNanoseconds: UInt64
    ) {
        self.interactiveSessionID = interactiveSessionID
        self.authorizationEpoch = authorizationEpoch
        self.selectedDisplayID = selectedDisplayID
        self.interactionClasses = interactionClasses
        self.nowMonotonicNanoseconds = nowMonotonicNanoseconds
    }
}

/// Menu-backed preparation of the first Desktop descriptor. The later macOS
/// adapter owns the opaque UUID-to-CGDisplay mapping and may not return titles,
/// process identifiers, or platform capture objects through this seam.
public protocol AgentInteractiveInitialDesktopPreparingV1: Sendable {
    func prepareInitialDesktop(
        _ request: AgentInteractiveInitialDesktopRequestV1
    ) async throws -> AdaptiveSurfaceDescriptor
}

/// Narrow authenticated menu-runtime route. The production adapter is the
/// current-ready local-XPC generation; tests may provide a deterministic
/// in-memory implementation.
public protocol AgentInteractiveMenuRuntimeRoutingV1: Sendable {
    func installInteractiveLease(
        _ command: InteractiveRuntimeInstallCommandV0
    ) async throws -> InteractiveRuntimeInstallReceiptV0

    func renewInteractiveLease(
        _ renewal: InteractiveRuntimeLeaseRenewalV0
    ) async throws

    func revokeInteractiveLease(
        _ command: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0
}

public protocol AgentInteractiveSurfaceMenuRoutingV1:
    InteractiveSurfaceRuntimeRoutingV0,
    InteractiveSurfaceTargetResolvingV0,
    InteractiveSurfaceTargetInventoryProvidingV0
{}

public protocol AgentInteractiveDisplayMenuRoutingV1: Sendable {
    func interactiveDisplayCatalog()
        async throws -> LocalInteractiveDisplayCatalogReceiptV1
    func selectInteractiveDisplay(_ displayID: UUID)
        async throws -> LocalInteractiveDisplaySelectedReceiptV1
}

private struct AgentInteractiveSystemMonotonicClockV1:
    InteractiveSurfaceMonotonicClockV0
{
    func nowNanoseconds() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }
}

/// Agent-owned final installation boundary for one Interactive session. It
/// re-reads the durable-plus-visible admission on both sides of menu-backed
/// Desktop preparation, then transfers credentials only after the exact menu
/// runtime receipt is accepted. Operations are explicitly sequenced so a
/// concurrent termination cannot interleave with a suspended install.
public actor AgentInteractiveRuntimeOwnerV1:
    InteractiveSessionRuntimeOwningV0,
    HostInteractiveChannelAuthenticatingV0,
    InteractiveSurfaceControlDispatchingV0,
    InteractiveDisplaySelectionDispatchingV1
{
    private struct Active: Sendable {
        var bootstrap: InteractiveSessionBootstrap
        let preparation: InteractiveInitialRuntimePreparationV1
        let primaryConnectionID: Data
        var requirement: InteractiveSessionRuntimeRequirementV0
        var currentLease: InteractiveExecutionLease
        let surfaceCoordinator: InteractiveSurfaceRuntimeCoordinatorV0?
        let surfaceControl: InteractiveSurfaceControlHandlerV0?
    }

    private enum Storage: Sendable {
        case idle
        case installing(UUID)
        case active(Active)
        case terminating(Active)
        case safetyRecoveryRequired(UUID)
    }

    private let admission: any InteractiveSessionAdmissionReadingV0
    private let desktop: any AgentInteractiveInitialDesktopPreparingV1
    private let runtime: any AgentInteractiveMenuRuntimeRoutingV1
    private let surfaceRuntime:
        (any AgentInteractiveSurfaceMenuRoutingV1)?
    private let displayRuntime:
        (any AgentInteractiveDisplayMenuRoutingV1)?
    private let monotonicNowNanoseconds: @Sendable () -> UInt64
    private let identifier: @Sendable () -> UUID
    private var storage: Storage = .idle
    private struct PendingInstall {
        let token: UUID
        let sessionID: UUID
        let primaryConnectionID: Data
        var terminationReason: InteractiveSessionEndReason?
    }
    private var pendingInstall: PendingInstall?
    private var sequencingTail = Task<Void, Never> {}

    public init(
        admission: any InteractiveSessionAdmissionReadingV0,
        desktop: any AgentInteractiveInitialDesktopPreparingV1,
        runtime: any AgentInteractiveMenuRuntimeRoutingV1,
        surfaceRuntime:
            (any AgentInteractiveSurfaceMenuRoutingV1)? = nil,
        displayRuntime:
            (any AgentInteractiveDisplayMenuRoutingV1)? = nil,
        monotonicNowNanoseconds: @escaping @Sendable () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds
        },
        identifier: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.admission = admission
        self.desktop = desktop
        self.runtime = runtime
        self.surfaceRuntime = surfaceRuntime
        self.displayRuntime = displayRuntime
        self.monotonicNowNanoseconds = monotonicNowNanoseconds
        self.identifier = identifier
    }

    public func displayCatalog(
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveDisplayCatalogResponseBodyV1 {
        guard let displayRuntime,
              displayCatalogIsAvailable(context: context),
              let current = try await admission.snapshot(
                deviceID: context.deviceID
              ),
              current.authorizationEpoch == context.authorizationEpoch,
              let selectedDisplayID = current.selectedDisplayID,
              let admissionRevision = Int64(
                exactly: current.visibleMenuAppRevision
              ) else {
            throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
        }
        let local = try await displayRuntime.interactiveDisplayCatalog()
        guard local.selectedDisplayID == selectedDisplayID else {
            throw AgentInteractiveRuntimeOwnerErrorV1.finalAdmissionChanged
        }
        return try InteractiveDisplayCatalogResponseBodyV1(
            authorizationEpoch: context.authorizationEpoch,
            admissionRevision: admissionRevision,
            selectedDisplayID: WireUUID(selectedDisplayID),
            validForMilliseconds: 5_000,
            displays: try local.candidates.map {
                try InteractiveDisplayCandidateV1(
                    displayID: WireUUID($0.displayID),
                    ordinal: $0.ordinal,
                    pixelWidth: $0.pixelWidth,
                    pixelHeight: $0.pixelHeight,
                    isMain: $0.isMain
                )
            }
        )
    }

    private func displayCatalogIsAvailable(
        context: InteractiveSessionCommandContextV0
    ) -> Bool {
        switch storage {
        case .idle:
            true
        case let .active(active):
            active.currentLease.deviceID == context.deviceID
                && active.currentLease.hostID == context.hostID
                && active.currentLease.authorizationEpoch
                    == context.authorizationEpoch
        case .installing, .terminating, .safetyRecoveryRequired:
            false
        }
    }

    public func selectDisplay(
        _ request: InteractiveDisplaySelectBodyV1,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveDisplaySelectedBodyV1 {
        guard case .idle = storage,
              request.authorizationEpoch == context.authorizationEpoch,
              let displayRuntime else {
            throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
        }
        let receipt = try await displayRuntime.selectInteractiveDisplay(
            request.displayID.rawValue
        )
        guard receipt.selectedDisplayID == request.displayID.rawValue,
              let current = try await admission.snapshot(
                deviceID: context.deviceID
              ),
              current.authorizationEpoch == context.authorizationEpoch,
              current.selectedDisplayID == request.displayID.rawValue,
              let admissionRevision = Int64(
                exactly: current.visibleMenuAppRevision
              ) else {
            throw AgentInteractiveRuntimeOwnerErrorV1.finalAdmissionChanged
        }
        return try InteractiveDisplaySelectedBodyV1(
            authorizationEpoch: context.authorizationEpoch,
            admissionRevision: admissionRevision,
            selectedDisplayID: request.displayID
        )
    }

    public func state() -> AgentInteractiveRuntimeOwnerStateV1 {
        switch storage {
        case .idle:
            .idle
        case let .installing(sessionID):
            .installing(interactiveSessionID: sessionID)
        case let .active(active):
            .active(
                interactiveSessionID:
                    active.currentLease.interactiveSessionID,
                leaseID: active.currentLease.leaseID
            )
        case let .terminating(active):
            .terminating(
                interactiveSessionID:
                    active.currentLease.interactiveSessionID,
                leaseID: active.currentLease.leaseID
            )
        case let .safetyRecoveryRequired(sessionID):
            .safetyRecoveryRequired(interactiveSessionID: sessionID)
        }
    }

    public func activeLeaseForScheduling() -> InteractiveExecutionLease? {
        guard case .active(let active) = storage else { return nil }
        return active.currentLease
    }

    public func beginInteractiveChannel(
        hello: InteractiveChannelHelloBody,
        hostNonce: WireBytes32,
        monotonicNowMilliseconds: UInt64
    ) async throws -> InteractiveChannelChallengeBody {
        guard case var .active(active) = storage,
              matches(hello, active: active) else {
            throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
        }
        var authority = channelAuthority(
            for: hello.role,
            active: active
        )
        do {
            let challenge = try authority.beginChallenge(
                clientNonce: hello.clientNonce.rawValue,
                hostNonce: hostNonce.rawValue,
                current: channelCurrentState(active),
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
            guard challenge.channelID == hello.channelID.rawValue,
                  challenge.role == hello.role.securityRole else {
                authority.invalidate()
                throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
            }
            setChannelAuthority(
                authority,
                for: hello.role,
                active: &active
            )
            storage = .active(active)
            return InteractiveChannelChallengeBody(
                channelID: hello.channelID,
                role: hello.role,
                hostID: WireUUID(active.requirement.command.hostID),
                hostFingerprint: try WireFingerprint(
                    active.requirement.command.hostFingerprint
                ),
                hostNonce: hostNonce
            )
        } catch {
            setChannelAuthority(
                authority,
                for: hello.role,
                active: &active
            )
            storage = .active(active)
            throw error
        }
    }

    public func consumeInteractiveChannel(
        hello: InteractiveChannelHelloBody,
        proof: InteractiveChannelProofBody,
        monotonicNowMilliseconds: UInt64
    ) async throws -> InteractiveChannelAcceptedBody {
        guard case var .active(active) = storage,
              matches(hello, active: active),
              proof.channelID == hello.channelID else {
            throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
        }
        var authority = channelAuthority(
            for: hello.role,
            active: active
        )
        do {
            let acceptance = try authority.verifyAndConsume(
                clientProof: proof.clientProof.rawValue,
                current: channelCurrentState(active),
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
            setChannelAuthority(
                authority,
                for: hello.role,
                active: &active
            )
            storage = .active(active)
            guard acceptance.channelID == hello.channelID.rawValue,
                  acceptance.role == hello.role.securityRole else {
                throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
            }
            return InteractiveChannelAcceptedBody(
                channelID: hello.channelID,
                role: hello.role,
                serverProof: try WireBytes32(acceptance.serverProof)
            )
        } catch {
            setChannelAuthority(
                authority,
                for: hello.role,
                active: &active
            )
            storage = .active(active)
            throw error
        }
    }

    public func invalidateInteractiveChannel(
        channelID: UUID,
        role: InteractiveChannelRoleName
    ) async {
        guard case var .active(active) = storage,
              offeredChannelID(for: role, active: active) == channelID else {
            return
        }
        var authority = channelAuthority(for: role, active: active)
        authority.invalidate()
        setChannelAuthority(authority, for: role, active: &active)
        storage = .active(active)
    }

    public func install(
        _ bootstrap: InteractiveSessionBootstrap,
        requirement: InteractiveSessionRuntimeRequirementV0
    ) async throws {
        guard pendingInstall == nil else {
            throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
        }
        let token = UUID()
        pendingInstall = PendingInstall(token: token,
            sessionID: bootstrap.acceptedBody.interactiveSessionID.rawValue,
            primaryConnectionID: requirement.command.primaryConnectionID)
        defer {
            if pendingInstall?.token == token { pendingInstall = nil }
        }
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            try await performInstall(
                bootstrap,
                requirement: requirement,
                token: token
            )
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func terminate(
        interactiveSessionID: UUID,
        primaryConnectionID: Data,
        reason: InteractiveSessionEndReason
    ) async {
        if pendingInstall?.sessionID == interactiveSessionID,
           pendingInstall?.primaryConnectionID == primaryConnectionID {
            pendingInstall?.terminationReason = reason
        }
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            await performTerminate(
                interactiveSessionID: interactiveSessionID,
                primaryConnectionID: primaryConnectionID,
                reason: reason
            )
        }
        sequencingTail = operation
        await operation.value
    }

    /// Renews only the exact active lease after another final admission read.
    /// A higher-level product scheduler calls this before the current deadline;
    /// this owner never infers success from a send or silently retries an
    /// ambiguous acknowledgement.
    public func renewActiveLease(
        nowMonotonicNanoseconds: UInt64
    ) async throws -> AgentInteractiveLeaseRenewalResultV1 {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            return try await performRenewal(
                nowMonotonicNanoseconds: nowMonotonicNanoseconds
            )
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func requestInitial(
        _ request: InteractiveInitialSurfaceRequestBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveInitialSurfaceDescriptorBodyV0 {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard case let .active(active) = storage,
                  let control = active.surfaceControl else {
                throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
            }
            return try await control.requestInitial(request, context: context)
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func acknowledgeInitial(
        _ request: InteractiveInitialSurfaceAcknowledgementBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveInitialSurfaceAcknowledgedBodyV0 {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard case let .active(active) = storage,
                  let control = active.surfaceControl else {
                throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
            }
            return try await control.acknowledgeInitial(
                request,
                context: context
            )
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func targets(
        _ request: InteractiveSurfaceTargetsRequestBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveSurfaceTargetsResponseBodyV0 {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard case let .active(active) = storage,
                  let control = active.surfaceControl else {
                throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
            }
            return try await control.targets(request, context: context)
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func select(
        _ request: InteractiveSurfaceSelectBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveSurfaceSelectedBodyV0 {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard case let .active(active) = storage,
                  let control = active.surfaceControl,
                  let coordinator = active.surfaceCoordinator else {
                throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
            }
            let response = try await control.select(request, context: context)
            try await synchronizeSurfaceLease(
                coordinator,
                interactiveSessionID:
                    request.interactiveSessionID.rawValue
            )
            if let selectedDisplayID = request.targetDisplayID?.rawValue {
                try await refreshDisplayAdmission(
                    selectedDisplayID: selectedDisplayID,
                    interactiveSessionID:
                        request.interactiveSessionID.rawValue
                )
            }
            return response
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func acknowledge(
        _ request: InteractiveSurfaceAcknowledgementBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveSurfaceAcknowledgedBodyV0 {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard case let .active(active) = storage,
                  let control = active.surfaceControl,
                  let coordinator = active.surfaceCoordinator else {
                throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
            }
            let response = try await control.acknowledge(
                request,
                context: context
            )
            try await synchronizeSurfaceLease(
                coordinator,
                interactiveSessionID:
                    request.interactiveSessionID.rawValue
            )
            return response
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func primarySessionClosed() async {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard case let .active(active) = storage,
                  let control = active.surfaceControl else { return }
            await control.primarySessionClosed()
        }
        sequencingTail = operation
        await operation.value
    }

    public func currentFocusEventReadiness() async
        -> InteractiveFocusEventReadinessV0?
    {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard case let .active(active) = storage,
                  let control = active.surfaceControl else {
                return Optional<InteractiveFocusEventReadinessV0>.none
            }
            return await control.currentFocusEventReadiness()
        }
        sequencingTail = Task { _ = await operation.value }
        return await operation.value
    }

    public func prepareFocusEvent(
        candidate: InteractiveFocusEventCandidateV0,
        hostContext: InteractiveFocusEventHostContextV0
    ) async throws -> InteractivePreparedFocusEventV0 {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard case let .active(active) = storage,
                  let control = active.surfaceControl else {
                throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
            }
            return try await control.prepareFocusEvent(
                candidate: candidate,
                hostContext: hostContext
            )
        }
        sequencingTail = Task { _ = try? await operation.value }
        return try await operation.value
    }

    public func revokePreparedFocusEvent() async {
        let predecessor = sequencingTail
        let operation = Task { [self] in
            await predecessor.value
            guard case let .active(active) = storage,
                  let control = active.surfaceControl else { return }
            await control.revokePreparedFocusEvent()
        }
        sequencingTail = operation
        await operation.value
    }

    private func synchronizeSurfaceLease(
        _ coordinator: InteractiveSurfaceRuntimeCoordinatorV0,
        interactiveSessionID: UUID
    ) async throws {
        let lease = await coordinator.lease()
        guard case var .active(active) = storage,
              active.currentLease.interactiveSessionID
                == interactiveSessionID,
              lease.interactiveSessionID == interactiveSessionID else {
            throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
        }
        active.currentLease = lease
        storage = .active(active)
    }

    private func refreshDisplayAdmission(
        selectedDisplayID: UUID,
        interactiveSessionID: UUID
    ) async throws {
        guard case var .active(active) = storage,
              active.currentLease.interactiveSessionID
                == interactiveSessionID,
              active.currentLease.selectedDisplayID
                == selectedDisplayID,
              let current = try await admission.snapshot(
                deviceID: active.requirement.command.deviceID
              ),
              current.selectedDisplayID == selectedDisplayID else {
            throw AgentInteractiveRuntimeOwnerErrorV1
                .finalAdmissionChanged
        }
        let refreshed = InteractiveSessionRuntimeRequirementV0(
            command: active.requirement.command,
            admission: current
        )
        guard refreshed.isEligibleForInteractiveControl,
              current.deviceID == active.requirement.admission.deviceID,
              current.clientID == active.requirement.admission.clientID,
              current.deviceState
                == active.requirement.admission.deviceState,
              current.authorizationEpoch
                == active.requirement.admission.authorizationEpoch,
              current.grantRevision
                == active.requirement.admission.grantRevision,
              current.approvalPublicKeyX963
                == active.requirement.admission.approvalPublicKeyX963,
              current.grants == active.requirement.admission.grants,
              current.deviceDisplayName
                == active.requirement.admission.deviceDisplayName,
              current.visibleMenuAppAvailable,
              current.visibleMenuAppGeneration
                == active.requirement.admission.visibleMenuAppGeneration else {
            throw AgentInteractiveRuntimeOwnerErrorV1
                .finalAdmissionChanged
        }
        active.requirement = refreshed
        storage = .active(active)
    }

    private func performInstall(
        _ suppliedBootstrap: InteractiveSessionBootstrap,
        requirement: InteractiveSessionRuntimeRequirementV0,
        token: UUID
    ) async throws {
        guard case .idle = storage,
              requirement.isEligibleForInteractiveControl,
              let sessionID = suppliedBootstrap.session.sessionID,
              sessionID
                == suppliedBootstrap.acceptedBody.interactiveSessionID.rawValue,
              let selectedDisplayID = requirement.admission.selectedDisplayID
        else {
            throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
        }
        storage = .installing(sessionID)
        var bootstrap = suppliedBootstrap

        do {
            agentInteractiveRuntimeLoggerV1.notice(
                "runtime install final admission started"
            )
            try await requireExactFinalAdmission(requirement)
            try requireUnfencedInstall(token)
            let desktopRequestNow = monotonicNowNanoseconds()
            agentInteractiveRuntimeLoggerV1.notice(
                "initial desktop preparation started"
            )
            let descriptor = try await desktop.prepareInitialDesktop(
                AgentInteractiveInitialDesktopRequestV1(
                    interactiveSessionID: sessionID,
                    authorizationEpoch: requirement.command.authorizationEpoch,
                    selectedDisplayID: selectedDisplayID,
                    interactionClasses: bootstrap.approvedInteractionClasses,
                    nowMonotonicNanoseconds: desktopRequestNow
                )
            )
            agentInteractiveRuntimeLoggerV1.notice(
                "initial desktop preparation completed"
            )
            try await requireExactFinalAdmission(requirement)
            try requireUnfencedInstall(token)
            guard descriptor.interactiveSessionID == sessionID,
                  descriptor.authorizationEpoch
                    == requirement.command.authorizationEpoch,
                  descriptor.kind == .desktop,
                  Set(descriptor.interactionClasses)
                    == bootstrap.approvedInteractionClasses else {
                throw AgentInteractiveRuntimeOwnerErrorV1.invalidDesktop
            }

            var authority = try InteractiveInitialRuntimeCommandAuthorityV1(
                bootstrap: bootstrap,
                requirement: requirement,
                desktop: descriptor
            )
            // The visible menu process creates the descriptor after receiving
            // the request and samples its own monotonic clock. Reusing the
            // Agent's pre-request sample can therefore make a valid descriptor
            // appear to have been created in the future. Sample again only
            // after the correlated descriptor and final admission return.
            let preparationNow = monotonicNowNanoseconds()
            let preparation = try authority.prepare(
                commandID: identifier(),
                leaseID: identifier(),
                nowMonotonicNanoseconds: preparationNow
            )
            agentInteractiveRuntimeLoggerV1.notice(
                "first execution lease prepared"
            )

            let receipt: InteractiveRuntimeInstallReceiptV0
            do {
                agentInteractiveRuntimeLoggerV1.notice(
                    "menu runtime install started"
                )
                receipt = try await runtime.installInteractiveLease(
                    preparation.command
                )
                agentInteractiveRuntimeLoggerV1.notice(
                    "menu runtime install completed"
                )
            } catch {
                agentInteractiveRuntimeLoggerV1.error(
                    "menu runtime install failed: \(String(describing: error), privacy: .public)"
                )
                let revoked = await attemptRevoke(
                    lease: preparation.command.lease,
                    bootstrap: &bootstrap,
                    reason: .protocolViolation
                )
                storage = revoked
                    ? .idle : .safetyRecoveryRequired(sessionID)
                throw revoked
                    ? AgentInteractiveRuntimeOwnerErrorV1.unavailable
                    : AgentInteractiveRuntimeOwnerErrorV1
                        .safetyRecoveryRequired
            }

            do {
                try requireUnfencedInstall(token)
                try authority.accept(
                    receipt,
                    nowMonotonicNanoseconds: monotonicNowNanoseconds()
                )
                bootstrap = try authority.takeInstalledBootstrap()
                agentInteractiveRuntimeLoggerV1.notice(
                    "menu runtime receipt accepted"
                )
            } catch {
                agentInteractiveRuntimeLoggerV1.error(
                    "menu runtime receipt rejected: \(String(describing: error), privacy: .public)"
                )
                let revoked = await attemptRevoke(
                    lease: preparation.command.lease,
                    bootstrap: &bootstrap,
                    reason: .protocolViolation
                )
                storage = revoked
                    ? .idle : .safetyRecoveryRequired(sessionID)
                throw AgentInteractiveRuntimeOwnerErrorV1
                    .runtimeReceiptRejected
            }
            let surfaceCoordinator: InteractiveSurfaceRuntimeCoordinatorV0?
            let surfaceControl: InteractiveSurfaceControlHandlerV0?
            if let surfaceRuntime {
                do {
                    let surfaceNow = monotonicNowNanoseconds()
                    guard surfaceNow / 1_000_000 <= UInt64(Int64.max) else {
                        throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
                    }
                    let authority = try AdaptiveSurfaceAuthority(
                        desktop: descriptor,
                        monotonicNowMilliseconds: Int64(
                            surfaceNow / 1_000_000
                        )
                    )
                    let coordinator = try InteractiveSurfaceRuntimeCoordinatorV0(
                        surfaceAuthority: authority,
                        currentLease: preparation.command.lease,
                        sessionDeadlineMonotonicNanoseconds:
                            preparation.command
                                .sessionDeadlineMonotonicNanoseconds,
                        runtime: surfaceRuntime,
                        initialActivationCommandID:
                            preparation.command.commandID,
                        identifier: identifier
                    )
                    surfaceCoordinator = coordinator
                    surfaceControl = InteractiveSurfaceControlHandlerV0(
                        coordinator: coordinator,
                        resolver: surfaceRuntime,
                        inventoryProvider: surfaceRuntime,
                        displaySelector: displayRuntime,
                        clock: AgentInteractiveSystemMonotonicClockV1()
                    )
                } catch {
                    let revoked = await attemptRevoke(
                        lease: preparation.command.lease,
                        bootstrap: &bootstrap,
                        reason: .protocolViolation
                    )
                    storage = revoked
                        ? .idle : .safetyRecoveryRequired(sessionID)
                    throw revoked
                        ? AgentInteractiveRuntimeOwnerErrorV1.unavailable
                        : AgentInteractiveRuntimeOwnerErrorV1
                            .safetyRecoveryRequired
                }
            } else {
                surfaceCoordinator = nil
                surfaceControl = nil
            }
            storage = .active(Active(
                bootstrap: bootstrap,
                preparation: preparation,
                primaryConnectionID: requirement.command.primaryConnectionID,
                requirement: requirement,
                currentLease: preparation.command.lease,
                surfaceCoordinator: surfaceCoordinator,
                surfaceControl: surfaceControl
            ))
            agentInteractiveRuntimeLoggerV1.notice(
                "runtime install became active"
            )
        } catch let error as AgentInteractiveRuntimeOwnerErrorV1 {
            agentInteractiveRuntimeLoggerV1.error(
                "runtime install failed: \(String(describing: error), privacy: .public)"
            )
            if case .installing = storage {
                invalidateCredentials(&bootstrap)
                storage = .idle
            }
            throw error
        } catch {
            agentInteractiveRuntimeLoggerV1.error(
                "runtime install failed: \(String(describing: error), privacy: .public)"
            )
            if case .installing = storage {
                invalidateCredentials(&bootstrap)
                storage = .idle
            }
            throw error
        }
    }

    private func performRenewal(
        nowMonotonicNanoseconds requestSample: UInt64
    ) async throws -> AgentInteractiveLeaseRenewalResultV1 {
        guard case var .active(active) = storage else {
            if case .safetyRecoveryRequired = storage {
                throw AgentInteractiveRuntimeOwnerErrorV1
                    .safetyRecoveryRequired
            }
            throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
        }
        do {
            agentInteractiveRuntimeLoggerV1.notice(
                "runtime renewal final admission started counter=\(active.currentLease.renewalCounter, privacy: .public)"
            )
            try await requireExactFinalAdmission(active.requirement)
            agentInteractiveRuntimeLoggerV1.notice(
                "runtime renewal final admission completed"
            )
            // A surface transition/final admission may have awaited work since
            // the scheduler woke. Issue against the current serialized state,
            // not a timestamp captured before that transition's new lease.
            let nowMonotonicNanoseconds = monotonicNowNanoseconds()
            guard nowMonotonicNanoseconds >= requestSample else {
                throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
            }
            let current = active.currentLease
            guard nowMonotonicNanoseconds
                    >= current.issuedAtMonotonicNanoseconds,
                  nowMonotonicNanoseconds
                    < current.expiresAtMonotonicNanoseconds,
                  nowMonotonicNanoseconds
                    < active.preparation.command
                        .sessionDeadlineMonotonicNanoseconds,
                  current.renewalCounter
                    < MonotonicRevision<AuthorizationEpochTag>
                        .maximumWireValue else {
                throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
            }
            let (maximumExpiry, overflow) = nowMonotonicNanoseconds
                .addingReportingOverflow(
                    InteractiveExecutionLease.maximumLifetimeNanoseconds
                )
            guard !overflow else {
                throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
            }
            let expiry = min(
                maximumExpiry,
                active.preparation.command
                    .sessionDeadlineMonotonicNanoseconds
            )
            guard expiry > nowMonotonicNanoseconds else {
                throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
            }
            let replacement = try InteractiveExecutionLease(
                leaseID: identifier(),
                hostID: current.hostID,
                deviceID: current.deviceID,
                interactiveSessionID: current.interactiveSessionID,
                authorizationEpoch: current.authorizationEpoch,
                selectedDisplayID: current.selectedDisplayID,
                surfaceID: current.surfaceID,
                surfaceRevision: current.surfaceRevision,
                coordinateRevision: current.coordinateRevision,
                allowedInteractionClasses:
                    Set(current.allowedInteractionClasses),
                renewalCounter: current.renewalCounter + 1,
                issuedAtMonotonicNanoseconds: nowMonotonicNanoseconds,
                expiresAtMonotonicNanoseconds: expiry
            )
            let renewal = try InteractiveRuntimeLeaseRenewalV0(
                commandID: identifier(),
                previousLeaseID: current.leaseID,
                replacement: replacement
            )
            try renewal.validate(current: current)
            agentInteractiveRuntimeLoggerV1.notice(
                "menu runtime renewal started counter=\(replacement.renewalCounter, privacy: .public)"
            )
            try await runtime.renewInteractiveLease(renewal)
            agentInteractiveRuntimeLoggerV1.notice(
                "menu runtime renewal completed counter=\(replacement.renewalCounter, privacy: .public)"
            )
            active.currentLease = replacement
            if let coordinator = active.surfaceCoordinator {
                try await coordinator.adoptRenewedLease(replacement)
            }
            storage = .active(active)
            return AgentInteractiveLeaseRenewalResultV1(previous: current, renewal: renewal)
        } catch let error as AgentInteractiveRuntimeOwnerErrorV1 {
            agentInteractiveRuntimeLoggerV1.error(
                "runtime renewal rejected before revoke error=\(String(describing: error), privacy: .public)"
            )
            let revoked = await attemptRevoke(
                lease: active.currentLease,
                bootstrap: &active.bootstrap,
                reason: .authorizationChanged
            )
            storage = revoked ? .idle : .safetyRecoveryRequired(
                active.currentLease.interactiveSessionID
            )
            throw error
        } catch {
            agentInteractiveRuntimeLoggerV1.error(
                "runtime renewal failed before revoke error=\(String(describing: error), privacy: .public)"
            )
            let revoked = await attemptRevoke(
                lease: active.currentLease,
                bootstrap: &active.bootstrap,
                reason: .protocolViolation
            )
            storage = revoked ? .idle : .safetyRecoveryRequired(
                active.currentLease.interactiveSessionID
            )
            if revoked { throw error }
            throw AgentInteractiveRuntimeOwnerErrorV1.safetyRecoveryRequired
        }
    }

    private func performTerminate(
        interactiveSessionID: UUID,
        primaryConnectionID: Data,
        reason: InteractiveSessionEndReason
    ) async {
        guard case var .active(active) = storage,
              active.currentLease.interactiveSessionID == interactiveSessionID,
              active.bootstrap.acceptedBody.interactiveSessionID.rawValue
                == interactiveSessionID,
              active.primaryConnectionID == primaryConnectionID else {
            return
        }
        storage = .terminating(active)
        if await attemptRevoke(
            lease: active.currentLease,
            bootstrap: &active.bootstrap,
            reason: reason
        ) {
            storage = .idle
        } else {
            storage = .safetyRecoveryRequired(interactiveSessionID)
        }
    }

    private func attemptRevoke(
        lease: InteractiveExecutionLease,
        bootstrap: inout InteractiveSessionBootstrap,
        reason: InteractiveSessionEndReason
    ) async -> Bool {
        defer { invalidateCredentials(&bootstrap) }
        do {
            let command = try InteractiveRuntimeRevokeCommandV0(
                commandID: identifier(),
                leaseID: lease.leaseID,
                interactiveSessionID: lease.interactiveSessionID,
                reason: reason
            )
            let receipt = try await runtime.revokeInteractiveLease(command)
            try receipt.validate(against: command)
            return true
        } catch {
            return false
        }
    }

    private func requireExactFinalAdmission(
        _ requirement: InteractiveSessionRuntimeRequirementV0
    ) async throws {
        guard let current = try await admission.snapshot(
            deviceID: requirement.command.deviceID
        ), current == requirement.admission,
        InteractiveSessionRuntimeRequirementV0(
            command: requirement.command,
            admission: current
        ).isEligibleForInteractiveControl else {
            throw AgentInteractiveRuntimeOwnerErrorV1
                .finalAdmissionChanged
        }
    }

    private func requireUnfencedInstall(_ token: UUID) throws {
        guard pendingInstall?.token == token,
              pendingInstall?.terminationReason == nil else {
            throw AgentInteractiveRuntimeOwnerErrorV1.unavailable
        }
    }

    private func invalidateCredentials(
        _ bootstrap: inout InteractiveSessionBootstrap
    ) {
        bootstrap.inputChannelAuthority.invalidate()
        bootstrap.mediaChannelAuthority.invalidate()
    }

    private func matches(
        _ hello: InteractiveChannelHelloBody,
        active: Active
    ) -> Bool {
        hello.channelID.rawValue
            == offeredChannelID(for: hello.role, active: active)
            && hello.clientID.rawValue
                == active.requirement.command.clientID
            && hello.primaryConnectionID.rawValue
                == active.primaryConnectionID
            && hello.interactiveSessionID.rawValue
                == active.currentLease.interactiveSessionID
            && hello.authorizationEpoch
                == active.currentLease.authorizationEpoch
    }

    private func offeredChannelID(
        for role: InteractiveChannelRoleName,
        active: Active
    ) -> UUID {
        switch role {
        case .input:
            active.bootstrap.acceptedBody.inputChannel.channelID.rawValue
        case .media:
            active.bootstrap.acceptedBody.mediaChannel.channelID.rawValue
        }
    }

    private func channelCurrentState(
        _ active: Active
    ) -> InteractiveChannelCurrentState {
        InteractiveChannelCurrentState(
            clientID: active.requirement.command.clientID,
            primaryConnectionID: active.primaryConnectionID,
            interactiveSessionID:
                active.currentLease.interactiveSessionID,
            authorizationEpoch:
                active.currentLease.authorizationEpoch.rawValue
        )
    }

    private func channelAuthority(
        for role: InteractiveChannelRoleName,
        active: Active
    ) -> InteractiveChannelCredentialAuthority {
        switch role {
        case .input: active.bootstrap.inputChannelAuthority
        case .media: active.bootstrap.mediaChannelAuthority
        }
    }

    private func setChannelAuthority(
        _ authority: InteractiveChannelCredentialAuthority,
        for role: InteractiveChannelRoleName,
        active: inout Active
    ) {
        switch role {
        case .input:
            active.bootstrap.inputChannelAuthority = authority
        case .media:
            active.bootstrap.mediaChannelAuthority = authority
        }
    }
}
