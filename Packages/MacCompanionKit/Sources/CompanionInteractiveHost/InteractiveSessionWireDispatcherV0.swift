import CompanionDomain
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionSecurity
import CompanionWire
import Foundation

public enum InteractiveControlCapabilityV0 {
    public static let identifier = "maccompanion.interactive.control"
}

public enum InteractiveSessionWireDispatcherErrorV0: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidTransition
    case admissionChanged
    case unsupportedMessage(WireMessageKind)
}

public struct InteractiveLocalAuthorityBindingV0: Equatable, Sendable {
    public let deviceID: UUID
    public let requestID: UUID
    public let approvalID: UUID
    public let interactiveSessionID: UUID?

    public init(
        deviceID: UUID,
        requestID: UUID,
        approvalID: UUID,
        interactiveSessionID: UUID?
    ) {
        self.deviceID = deviceID
        self.requestID = requestID
        self.approvalID = approvalID
        self.interactiveSessionID = interactiveSessionID
    }
}

public struct InteractiveSessionCommandContextV0: Equatable, Sendable {
    public let deviceID: UUID
    public let clientID: UUID
    public let deviceState: DeviceAuthorizationState
    public let authorizationEpoch: AuthorizationEpoch
    public let grantRevision: GrantRevision
    public let policyRevision: PolicyRevision
    public let primaryConnectionID: Data
    public let hostID: UUID
    public let hostFingerprint: Data
    public let hostState: HostState
    public let wallNowUnixMilliseconds: Int64
    public let monotonicNowMilliseconds: UInt64

    public init(
        deviceID: UUID,
        clientID: UUID,
        deviceState: DeviceAuthorizationState,
        authorizationEpoch: AuthorizationEpoch,
        grantRevision: GrantRevision,
        policyRevision: PolicyRevision,
        primaryConnectionID: Data,
        hostID: UUID,
        hostFingerprint: Data,
        hostState: HostState,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64
    ) throws {
        guard authorizationEpoch.rawValue >= 1,
              grantRevision.rawValue >= 1,
              policyRevision.rawValue >= 1,
              primaryConnectionID.count == 16,
              hostFingerprint.count == 32,
              wallNowUnixMilliseconds >= 0,
              wallNowUnixMilliseconds <= WireLimits.maximumSafeInteger - 60_000,
              monotonicNowMilliseconds <= UInt64(Int64.max) - 60_000 else {
            throw InteractiveSessionWireDispatcherErrorV0.invalidConfiguration
        }
        self.deviceID = deviceID
        self.clientID = clientID
        self.deviceState = deviceState
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.policyRevision = policyRevision
        self.primaryConnectionID = primaryConnectionID
        self.hostID = hostID
        self.hostFingerprint = hostFingerprint
        self.hostState = hostState
        self.wallNowUnixMilliseconds = wallNowUnixMilliseconds
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
    }
}

/// Fresh non-principal facts used by an Agent-owned background event. Device,
/// grant, policy, host identity, and primary binding remain inherited from the
/// last authenticated command admitted by the active surface authority.
public struct InteractiveFocusEventHostContextV0: Equatable, Sendable {
    public let hostState: HostState
    public let wallNowUnixMilliseconds: Int64
    public let monotonicNowMilliseconds: UInt64
    public let eventMessageID: WireUUID

    public init(
        hostState: HostState,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64,
        eventMessageID: WireUUID
    ) throws {
        guard wallNowUnixMilliseconds >= 0,
              wallNowUnixMilliseconds
                <= WireLimits.maximumSafeInteger - 60_000,
              monotonicNowMilliseconds <= UInt64(Int64.max) - 60_000 else {
            throw InteractiveSessionWireDispatcherErrorV0.invalidConfiguration
        }
        self.hostState = hostState
        self.wallNowUnixMilliseconds = wallNowUnixMilliseconds
        self.monotonicNowMilliseconds = monotonicNowMilliseconds
        self.eventMessageID = eventMessageID
    }
}

public struct InteractiveFocusEventReadinessV0: Equatable, Sendable {
    public let descriptor: AdaptiveSurfaceDescriptor
    public let primaryConnectionID: Data

    public init(
        descriptor: AdaptiveSurfaceDescriptor,
        primaryConnectionID: Data
    ) throws {
        guard primaryConnectionID.count == 16 else {
            throw InteractiveSessionWireDispatcherErrorV0.invalidConfiguration
        }
        self.descriptor = descriptor
        self.primaryConnectionID = primaryConnectionID
    }
}

public struct InteractiveSessionAdmissionSnapshotV0: Equatable, Sendable {
    public let deviceID: UUID
    public let clientID: UUID
    public let deviceState: DeviceAuthorizationState
    public let authorizationEpoch: AuthorizationEpoch
    public let grantRevision: GrantRevision
    public let policyRevision: PolicyRevision
    public let approvalPublicKeyX963: Data
    public let grants: CapabilityGrantSet
    public let deviceDisplayName: DeviceDisplayName
    public let visibleMenuAppAvailable: Bool
    public let visibleMenuAppGeneration: UUID
    public let visibleMenuAppRevision: UInt64
    public let selectedDisplayID: UUID?

    public init(
        deviceID: UUID,
        clientID: UUID,
        deviceState: DeviceAuthorizationState,
        authorizationEpoch: AuthorizationEpoch,
        grantRevision: GrantRevision,
        policyRevision: PolicyRevision,
        approvalPublicKeyX963: Data,
        grants: CapabilityGrantSet,
        deviceDisplayName: DeviceDisplayName,
        visibleMenuAppAvailable: Bool,
        visibleMenuAppGeneration: UUID,
        visibleMenuAppRevision: UInt64,
        selectedDisplayID: UUID?
    ) throws {
        try CompanionSecurityV0.validateSigningPublicKey(approvalPublicKeyX963)
        guard visibleMenuAppRevision >= 1 else {
            throw InteractiveSessionWireDispatcherErrorV0.invalidConfiguration
        }
        self.deviceID = deviceID
        self.clientID = clientID
        self.deviceState = deviceState
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.policyRevision = policyRevision
        self.approvalPublicKeyX963 = approvalPublicKeyX963
        self.grants = grants
        self.deviceDisplayName = deviceDisplayName
        self.visibleMenuAppAvailable = visibleMenuAppAvailable
        self.visibleMenuAppGeneration = visibleMenuAppGeneration
        self.visibleMenuAppRevision = visibleMenuAppRevision
        self.selectedDisplayID = selectedDisplayID
    }
}

public protocol InteractiveSessionAdmissionReadingV0: Sendable {
    /// Reads the durable device/grant record and the current visible-menu-app
    /// display selection as one conservative admission snapshot.
    func snapshot(deviceID: UUID) async throws
        -> InteractiveSessionAdmissionSnapshotV0?
}

public struct InteractiveApprovalMaterialsV0: Equatable, Sendable {
    public let approvalID: UUID
    public let serverChallenge: Data

    public init(approvalID: UUID, serverChallenge: Data) throws {
        guard serverChallenge.count == 32 else {
            throw InteractiveSessionWireDispatcherErrorV0.invalidConfiguration
        }
        self.approvalID = approvalID
        self.serverChallenge = serverChallenge
    }
}

public protocol InteractiveSessionMaterialGeneratingV0: Sendable {
    /// A platform implementation uses an OS cryptographic RNG. Deterministic
    /// implementations are permitted only in tests and fixtures.
    func approvalMaterials() async throws -> InteractiveApprovalMaterialsV0
    func bootstrapMaterials() async throws -> InteractiveSessionBootstrapMaterials
}

public struct InteractiveSessionRuntimeRequirementV0: Equatable, Sendable {
    public let command: InteractiveSessionCommandContextV0
    public let admission: InteractiveSessionAdmissionSnapshotV0

    public init(
        command: InteractiveSessionCommandContextV0,
        admission: InteractiveSessionAdmissionSnapshotV0
    ) {
        self.command = command
        self.admission = admission
    }

    /// Shared closed predicate used by the preflight dispatcher and every
    /// final runtime admission implementation. Keeping one projection avoids
    /// policy drift between challenge, proof, and install boundaries.
    public var isEligibleForInteractiveControl: Bool {
        command.hostState == .userSessionActive
            && command.deviceState == .activeGranted
            && admission.deviceID == command.deviceID
            && admission.clientID == command.clientID
            && admission.deviceState == command.deviceState
            && admission.authorizationEpoch == command.authorizationEpoch
            && admission.grantRevision == command.grantRevision
            && admission.policyRevision == command.policyRevision
            && admission.visibleMenuAppAvailable
            && admission.selectedDisplayID != nil
            && admission.grants.capabilityIDs.contains(
                InteractiveControlCapabilityV0.identifier
            )
    }
}

public protocol InteractiveSessionRuntimeOwningV0: Sendable {
    /// Atomically installs the starting session and both one-time channel
    /// authorities before the accepted response can be disclosed. Inside the
    /// same serialized boundary, the implementation re-reads durable device,
    /// grant, approval-key, revision, visible-menu-app, and selected-display
    /// state and requires exact equality with `requirement`; the dispatcher's
    /// earlier snapshot is never the final authority.
    func install(
        _ bootstrap: InteractiveSessionBootstrap,
        requirement: InteractiveSessionRuntimeRequirementV0
    ) async throws

    /// Idempotently ends the runtime and destroys unused role credentials.
    func terminate(
        interactiveSessionID: UUID,
        primaryConnectionID: Data,
        reason: InteractiveSessionEndReason
    ) async
}

/// Agent-owned surface authority reached only through the authenticated
/// application-primary dispatcher. Implementations resolve opaque target
/// tokens and own request/reply sequencing; the wire dispatcher supplies only
/// authenticated current-session facts.
public protocol InteractiveSurfaceControlDispatchingV0: Sendable {
    func requestInitial(
        _ request: InteractiveInitialSurfaceRequestBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveInitialSurfaceDescriptorBodyV0

    func acknowledgeInitial(
        _ request: InteractiveInitialSurfaceAcknowledgementBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveInitialSurfaceAcknowledgedBodyV0

    func targets(
        _ request: InteractiveSurfaceTargetsRequestBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveSurfaceTargetsResponseBodyV0

    func select(
        _ request: InteractiveSurfaceSelectBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveSurfaceSelectedBodyV0

    func acknowledge(
        _ request: InteractiveSurfaceAcknowledgementBodyV0,
        context: InteractiveSessionCommandContextV0
    ) async throws -> InteractiveSurfaceAcknowledgedBodyV0

    func primarySessionClosed() async

    func currentFocusEventReadiness() async
        -> InteractiveFocusEventReadinessV0?

    func prepareFocusEvent(
        candidate: InteractiveFocusEventCandidateV0,
        hostContext: InteractiveFocusEventHostContextV0
    ) async throws -> InteractivePreparedFocusEventV0

    func revokePreparedFocusEvent() async
}

public extension InteractiveSurfaceControlDispatchingV0 {
    func currentFocusEventReadiness() async
        -> InteractiveFocusEventReadinessV0?
    {
        nil
    }

    func prepareFocusEvent(
        candidate: InteractiveFocusEventCandidateV0,
        hostContext: InteractiveFocusEventHostContextV0
    ) async throws -> InteractivePreparedFocusEventV0 {
        throw InteractiveFocusEventAuthorityErrorV0.unavailable
    }

    func revokePreparedFocusEvent() async {}
}

public actor InteractiveSessionWireDispatcherV0 {
    public static let approvalLifetimeMilliseconds: Int64 = 60_000

    private struct Pending: Sendable {
        let requestID: WireUUID
        let challengeMessageID: WireUUID
        let approvalID: WireUUID
        let selectedDisplayID: UUID
        let binding: InteractiveSessionCommandContextV0
        var bootstrapAuthority: InteractiveSessionBootstrapAuthority
    }

    private struct Active: Sendable {
        let deviceID: UUID
        let requestID: UUID
        let approvalID: UUID
        let interactiveSessionID: UUID
        let primaryConnectionID: Data
        let auditContext: InteractiveSessionCommandContextV0
    }

    private let admission: any InteractiveSessionAdmissionReadingV0
    private let materials: any InteractiveSessionMaterialGeneratingV0
    private let runtime: any InteractiveSessionRuntimeOwningV0
    private let auditWriter: (any InteractiveAuditWritingV0)?
    private let auditWallClock: any InteractiveAuditWallClockV0
    private let surfaceControl:
        (any InteractiveSurfaceControlDispatchingV0)?
    private var pending: Pending?
    private var active: Active?
    private var transitionMessageID: WireUUID?
    private var transitionLocalBinding: InteractiveLocalAuthorityBindingV0?
    private var lastLocalEnd: InteractiveLocalAuthorityBindingV0?

    package init(
        admission: any InteractiveSessionAdmissionReadingV0,
        materials: any InteractiveSessionMaterialGeneratingV0,
        runtime: any InteractiveSessionRuntimeOwningV0,
        surfaceControl:
            (any InteractiveSurfaceControlDispatchingV0)? = nil,
        auditWriter: (any InteractiveAuditWritingV0)? = nil,
        auditWallClock: any InteractiveAuditWallClockV0 =
            SystemInteractiveAuditWallClockV0()
    ) {
        self.admission = admission
        self.materials = materials
        self.runtime = runtime
        self.surfaceControl = surfaceControl
        self.auditWriter = auditWriter
        self.auditWallClock = auditWallClock
    }

    public var hasPendingApproval: Bool { pending != nil }
    public var activeInteractiveSessionID: UUID? { active?.interactiveSessionID }

    public func dispatch(
        requestJSON: Data,
        context: InteractiveSessionCommandContextV0,
        responseMessageID: WireUUID
    ) async throws -> Data {
        switch try WireCodec.messageKind(from: requestJSON) {
        case .interactiveSessionRequest:
            return try await requestSession(
                requestJSON,
                context: context,
                responseMessageID: responseMessageID
            )
        case .interactiveSessionApprove:
            return try await approveSession(
                requestJSON,
                context: context,
                responseMessageID: responseMessageID
            )
        case .interactiveSessionEnd:
            return try await endSession(
                requestJSON,
                context: context,
                responseMessageID: responseMessageID
            )
        case .interactiveInitialSurfaceRequest:
            return try await requestInitialSurface(
                requestJSON,
                context: context,
                responseMessageID: responseMessageID
            )
        case .interactiveInitialSurfaceAcknowledgement:
            return try await acknowledgeInitialSurface(
                requestJSON,
                context: context,
                responseMessageID: responseMessageID
            )
        case .interactiveSurfaceTargetsRequest:
            return try await requestSurfaceTargets(
                requestJSON,
                context: context,
                responseMessageID: responseMessageID
            )
        case .interactiveSurfaceSelect:
            return try await selectSurface(
                requestJSON,
                context: context,
                responseMessageID: responseMessageID
            )
        case .interactiveSurfaceAcknowledgement:
            return try await acknowledgeSurface(
                requestJSON,
                context: context,
                responseMessageID: responseMessageID
            )
        case let kind:
            throw InteractiveSessionWireDispatcherErrorV0.unsupportedMessage(kind)
        }
    }

    private func requestInitialSurface(
        _ requestJSON: Data,
        context: InteractiveSessionCommandContextV0,
        responseMessageID: WireUUID
    ) async throws -> Data {
        let request = try WireCodec.decode(
            WireEnvelope<InteractiveInitialSurfaceRequestBodyV0>.self,
            from: requestJSON
        )
        let control = try requireSurfaceControl(
            sessionID: request.body.interactiveSessionID.rawValue,
            authorizationEpoch: request.body.authorizationEpoch,
            context: context
        )
        guard transitionMessageID == nil else {
            throw InteractiveSessionWireDispatcherErrorV0.invalidTransition
        }
        transitionMessageID = request.messageID
        defer {
            if transitionMessageID == request.messageID {
                transitionMessageID = nil
            }
        }
        guard let snapshot = try await admission.snapshot(deviceID: context.deviceID),
              transitionMessageID == request.messageID,
              isEligible(snapshot, for: context) else {
            throw InteractiveSessionWireDispatcherErrorV0.admissionChanged
        }
        let body = try await control.requestInitial(request.body, context: context)
        guard transitionMessageID == request.messageID,
              active?.interactiveSessionID
                == request.body.interactiveSessionID.rawValue else {
            throw InteractiveSessionWireDispatcherErrorV0.admissionChanged
        }
        return try WireCodec.encode(WireEnvelope(
            version: request.version,
            messageID: responseMessageID,
            correlationID: request.messageID,
            sentAtUnixMilliseconds: context.wallNowUnixMilliseconds,
            body: body
        ))
    }

    private func acknowledgeInitialSurface(
        _ requestJSON: Data,
        context: InteractiveSessionCommandContextV0,
        responseMessageID: WireUUID
    ) async throws -> Data {
        let request = try WireCodec.decode(
            WireEnvelope<InteractiveInitialSurfaceAcknowledgementBodyV0>.self,
            from: requestJSON
        )
        let control = try requireSurfaceControl(
            sessionID: request.body.interactiveSessionID.rawValue,
            authorizationEpoch: request.body.authorizationEpoch,
            context: context
        )
        guard transitionMessageID == nil else {
            throw InteractiveSessionWireDispatcherErrorV0.invalidTransition
        }
        transitionMessageID = request.messageID
        defer {
            if transitionMessageID == request.messageID {
                transitionMessageID = nil
            }
        }
        guard let snapshot = try await admission.snapshot(deviceID: context.deviceID),
              transitionMessageID == request.messageID,
              isEligible(snapshot, for: context) else {
            throw InteractiveSessionWireDispatcherErrorV0.admissionChanged
        }
        let body = try await control.acknowledgeInitial(
            request.body,
            context: context
        )
        guard transitionMessageID == request.messageID,
              active?.interactiveSessionID
                == request.body.interactiveSessionID.rawValue else {
            throw InteractiveSessionWireDispatcherErrorV0.admissionChanged
        }
        return try WireCodec.encode(WireEnvelope(
            version: request.version,
            messageID: responseMessageID,
            correlationID: request.messageID,
            sentAtUnixMilliseconds: context.wallNowUnixMilliseconds,
            body: body
        ))
    }

    public func primarySessionClosed() async {
        transitionMessageID = nil
        transitionLocalBinding = nil
        pending = nil
        guard let active else { return }
        self.active = nil
        await surfaceControl?.primarySessionClosed()
        await runtime.terminate(
            interactiveSessionID: active.interactiveSessionID,
            primaryConnectionID: active.primaryConnectionID,
            reason: .clientDisconnected
        )
        await auditWriter?.recordTerminal(
            requestID: active.requestID,
            interactiveSessionID: active.interactiveSessionID,
            code: .interactiveStopped,
            outcome: .cancelled,
            observedAtUnixMilliseconds: max(
                active.auditContext.wallNowUnixMilliseconds,
                auditWallClock.nowUnixMilliseconds()
            ),
            context: active.auditContext
        )
    }

    private func endSession(
        _ requestJSON: Data,
        context: InteractiveSessionCommandContextV0,
        responseMessageID: WireUUID
    ) async throws -> Data {
        let request = try WireCodec.decode(
            WireEnvelope<InteractiveSessionEndBodyV0>.self,
            from: requestJSON
        )
        guard let active,
              active.deviceID == context.deviceID,
              active.interactiveSessionID
                == request.body.interactiveSessionID.rawValue,
              active.primaryConnectionID == context.primaryConnectionID,
              request.body.authorizationEpoch
                == context.authorizationEpoch else {
            throw InteractiveSessionWireDispatcherErrorV0.admissionChanged
        }

        // End admission before any suspension so an in-flight surface command
        // cannot re-enter after teardown begins.
        self.active = nil
        pending = nil
        transitionMessageID = nil
        transitionLocalBinding = nil
        await surfaceControl?.primarySessionClosed()
        await runtime.terminate(
            interactiveSessionID: active.interactiveSessionID,
            primaryConnectionID: active.primaryConnectionID,
            reason: .clientRequested
        )
        await auditWriter?.recordTerminal(
            requestID: active.requestID,
            interactiveSessionID: active.interactiveSessionID,
            code: .interactiveStopped,
            outcome: .cancelled,
            observedAtUnixMilliseconds:
                context.wallNowUnixMilliseconds,
            context: active.auditContext
        )
        return try WireCodec.encode(WireEnvelope(
            version: request.version,
            messageID: responseMessageID,
            correlationID: request.messageID,
            sentAtUnixMilliseconds: context.wallNowUnixMilliseconds,
            body: try InteractiveSessionEndedBodyV0(
                interactiveSessionID: request.body.interactiveSessionID,
                authorizationEpoch: request.body.authorizationEpoch,
                endedAtUnixMilliseconds:
                    context.wallNowUnixMilliseconds
            )
        ))
    }

    private func requestSurfaceTargets(
        _ requestJSON: Data,
        context: InteractiveSessionCommandContextV0,
        responseMessageID: WireUUID
    ) async throws -> Data {
        let request = try WireCodec.decode(
            WireEnvelope<InteractiveSurfaceTargetsRequestBodyV0>.self,
            from: requestJSON
        )
        let control = try requireSurfaceControl(
            sessionID: request.body.interactiveSessionID.rawValue,
            authorizationEpoch: request.body.authorizationEpoch,
            context: context
        )
        guard transitionMessageID == nil else {
            throw InteractiveSessionWireDispatcherErrorV0.invalidTransition
        }
        transitionMessageID = request.messageID
        defer {
            if transitionMessageID == request.messageID {
                transitionMessageID = nil
            }
        }
        guard let snapshot = try await admission.snapshot(
            deviceID: context.deviceID
        ), transitionMessageID == request.messageID,
            isEligible(snapshot, for: context) else {
            throw InteractiveSessionWireDispatcherErrorV0.admissionChanged
        }
        let body = try await control.targets(request.body, context: context)
        guard transitionMessageID == request.messageID,
              active?.interactiveSessionID
                == request.body.interactiveSessionID.rawValue else {
            throw InteractiveSessionWireDispatcherErrorV0.admissionChanged
        }
        return try WireCodec.encode(WireEnvelope(
            version: request.version,
            messageID: responseMessageID,
            correlationID: request.messageID,
            sentAtUnixMilliseconds: context.wallNowUnixMilliseconds,
            body: body
        ))
    }

    private func selectSurface(
        _ requestJSON: Data,
        context: InteractiveSessionCommandContextV0,
        responseMessageID: WireUUID
    ) async throws -> Data {
        let request = try WireCodec.decode(
            WireEnvelope<InteractiveSurfaceSelectBodyV0>.self,
            from: requestJSON
        )
        let control = try requireSurfaceControl(
            sessionID: request.body.interactiveSessionID.rawValue,
            authorizationEpoch: request.body.authorizationEpoch,
            context: context
        )
        guard transitionMessageID == nil else {
            throw InteractiveSessionWireDispatcherErrorV0
                .invalidTransition
        }
        transitionMessageID = request.messageID
        defer {
            if transitionMessageID == request.messageID {
                transitionMessageID = nil
            }
        }
        guard let snapshot = try await admission.snapshot(
            deviceID: context.deviceID
        ), transitionMessageID == request.messageID,
            isEligible(snapshot, for: context) else {
            throw InteractiveSessionWireDispatcherErrorV0
                .admissionChanged
        }
        let body = try await control.select(request.body, context: context)
        guard transitionMessageID == request.messageID,
              active?.interactiveSessionID
                == request.body.interactiveSessionID.rawValue else {
            throw InteractiveSessionWireDispatcherErrorV0
                .admissionChanged
        }
        return try WireCodec.encode(WireEnvelope(
            version: request.version,
            messageID: responseMessageID,
            correlationID: request.messageID,
            sentAtUnixMilliseconds: context.wallNowUnixMilliseconds,
            body: body
        ))
    }

    private func acknowledgeSurface(
        _ requestJSON: Data,
        context: InteractiveSessionCommandContextV0,
        responseMessageID: WireUUID
    ) async throws -> Data {
        let request = try WireCodec.decode(
            WireEnvelope<InteractiveSurfaceAcknowledgementBodyV0>.self,
            from: requestJSON
        )
        let control = try requireSurfaceControl(
            sessionID: request.body.interactiveSessionID.rawValue,
            authorizationEpoch: request.body.authorizationEpoch,
            context: context
        )
        guard transitionMessageID == nil else {
            throw InteractiveSessionWireDispatcherErrorV0
                .invalidTransition
        }
        transitionMessageID = request.messageID
        defer {
            if transitionMessageID == request.messageID {
                transitionMessageID = nil
            }
        }
        guard let snapshot = try await admission.snapshot(
            deviceID: context.deviceID
        ), transitionMessageID == request.messageID,
            isEligible(snapshot, for: context) else {
            throw InteractiveSessionWireDispatcherErrorV0
                .admissionChanged
        }
        let body = try await control.acknowledge(
            request.body,
            context: context
        )
        guard transitionMessageID == request.messageID,
              active?.interactiveSessionID
                == request.body.interactiveSessionID.rawValue else {
            throw InteractiveSessionWireDispatcherErrorV0
                .admissionChanged
        }
        return try WireCodec.encode(WireEnvelope(
            version: request.version,
            messageID: responseMessageID,
            correlationID: request.messageID,
            sentAtUnixMilliseconds: context.wallNowUnixMilliseconds,
            body: body
        ))
    }

    private func requireSurfaceControl(
        sessionID: UUID,
        authorizationEpoch: AuthorizationEpoch,
        context: InteractiveSessionCommandContextV0
    ) throws -> any InteractiveSurfaceControlDispatchingV0 {
        guard context.hostState == .userSessionActive,
              let active,
              active.deviceID == context.deviceID,
              active.interactiveSessionID == sessionID,
              active.primaryConnectionID == context.primaryConnectionID,
              authorizationEpoch == context.authorizationEpoch,
              let surfaceControl else {
            throw InteractiveSessionWireDispatcherErrorV0
                .admissionChanged
        }
        return surfaceControl
    }

    /// Ends the exact pending approval, approval-to-runtime transition, or
    /// active remote session selected by local visible UI. State is cleared
    /// before runtime termination is awaited, so no new remote work can enter
    /// after this method reports success. Exact retries are idempotent.
    public func endFromLocalAuthority(
        binding: InteractiveLocalAuthorityBindingV0,
        reason: InteractiveSessionEndReason
    ) async -> Bool {
        if lastLocalEnd == binding { return true }

        if let pending,
           binding.interactiveSessionID == nil,
           pending.binding.deviceID == binding.deviceID,
           pending.requestID.rawValue == binding.requestID,
           pending.approvalID.rawValue == binding.approvalID {
            self.pending = nil
            transitionMessageID = nil
            transitionLocalBinding = nil
            lastLocalEnd = binding
            return true
        }

        if transitionLocalBinding == binding {
            transitionMessageID = nil
            transitionLocalBinding = nil
            pending = nil
            lastLocalEnd = binding
            return true
        }

        guard let active,
              binding.interactiveSessionID == active.interactiveSessionID,
              binding.deviceID == active.deviceID,
              binding.requestID == active.requestID,
              binding.approvalID == active.approvalID else {
            return false
        }
        self.active = nil
        transitionMessageID = nil
        transitionLocalBinding = nil
        lastLocalEnd = binding
        await runtime.terminate(
            interactiveSessionID: active.interactiveSessionID,
            primaryConnectionID: active.primaryConnectionID,
            reason: reason
        )
        return true
    }

    private func requestSession(
        _ requestJSON: Data,
        context: InteractiveSessionCommandContextV0,
        responseMessageID: WireUUID
    ) async throws -> Data {
        let request = try WireCodec.decode(
            WireEnvelope<InteractiveSessionRequestBody>.self,
            from: requestJSON
        )
        await auditWriter?.recordRequested(
            requestID: request.messageID.rawValue,
            context: context
        )
        guard pending == nil, active == nil, transitionMessageID == nil else {
            return try errorResponse(
                correlationID: request.messageID,
                responseMessageID: responseMessageID,
                sentAtUnixMilliseconds: context.wallNowUnixMilliseconds,
                code: "rateLimit.exceeded",
                retry: .backoff,
                safeArguments: .object([
                    .init(key: "retryAfterMilliseconds", value: .integer(1_000)),
                ])
            )
        }
        transitionMessageID = request.messageID
        defer {
            if transitionMessageID == request.messageID {
                transitionMessageID = nil
            }
        }
        guard let snapshot = try await admission.snapshot(deviceID: context.deviceID),
              transitionMessageID == request.messageID,
              InteractiveSessionRuntimeRequirementV0(
                command: context,
                admission: snapshot
              ).isEligibleForInteractiveControl,
              let selectedDisplayID = snapshot.selectedDisplayID else {
            return try denied(
                correlationID: request.messageID,
                responseMessageID: responseMessageID,
                sentAtUnixMilliseconds: context.wallNowUnixMilliseconds
            )
        }
        let generated = try await materials.approvalMaterials()
        guard transitionMessageID == request.messageID else {
            return try authenticationFailure(
                correlationID: request.messageID,
                responseMessageID: responseMessageID,
                sentAtUnixMilliseconds: context.wallNowUnixMilliseconds
            )
        }
        let expiresAtWall = context.wallNowUnixMilliseconds
            + Self.approvalLifetimeMilliseconds
        let expiresAtMonotonic = context.monotonicNowMilliseconds
            + UInt64(Self.approvalLifetimeMilliseconds)
        let approval = try InteractiveApprovalAuthority(
            hostID: context.hostID,
            hostFingerprint: context.hostFingerprint,
            clientID: context.clientID,
            primaryConnectionID: context.primaryConnectionID,
            requestID: request.messageID.rawValue,
            approvalID: generated.approvalID,
            serverChallenge: generated.serverChallenge,
            authorizationEpoch: context.authorizationEpoch.rawValue,
            grantRevision: context.grantRevision.rawValue,
            policyRevision: context.policyRevision.rawValue,
            selectedDisplayID: selectedDisplayID,
            initialSurface: .desktop,
            effects: request.body.effects.securityEffects,
            issuedAtUnixMilliseconds: UInt64(context.wallNowUnixMilliseconds),
            expiresAtUnixMilliseconds: UInt64(expiresAtWall),
            selectedMajor: request.version.major,
            selectedMinor: request.version.minor,
            approvalPublicKeyX963: snapshot.approvalPublicKeyX963,
            issuedAtMonotonicMilliseconds: context.monotonicNowMilliseconds,
            expiresAtMonotonicMilliseconds: expiresAtMonotonic
        )
        let challenge = try WireEnvelope(
            version: request.version,
            messageID: responseMessageID,
            correlationID: request.messageID,
            sentAtUnixMilliseconds: context.wallNowUnixMilliseconds,
            body: try InteractiveApprovalChallengeBody(
                hostID: WireUUID(context.hostID),
                hostFingerprint: WireFingerprint(context.hostFingerprint),
                clientID: WireUUID(context.clientID),
                primaryConnectionID: WireBytes16(context.primaryConnectionID),
                requestID: request.messageID,
                approvalID: WireUUID(generated.approvalID),
                serverChallenge: WireBytes32(generated.serverChallenge),
                authorizationEpoch: context.authorizationEpoch,
                grantRevision: context.grantRevision,
                policyRevision: context.policyRevision,
                selectedDisplayID: WireUUID(selectedDisplayID),
                initialSurface: .desktop,
                effects: Set(request.body.effects),
                issuedAtUnixMilliseconds: context.wallNowUnixMilliseconds,
                expiresAtUnixMilliseconds: expiresAtWall
            )
        )
        pending = Pending(
            requestID: request.messageID,
            challengeMessageID: responseMessageID,
            approvalID: WireUUID(generated.approvalID),
            selectedDisplayID: selectedDisplayID,
            binding: context,
            bootstrapAuthority: InteractiveSessionBootstrapAuthority(
                approvalAuthority: approval
            )
        )
        return try WireCodec.encode(challenge)
    }

    private func approveSession(
        _ requestJSON: Data,
        context: InteractiveSessionCommandContextV0,
        responseMessageID: WireUUID
    ) async throws -> Data {
        let request = try WireCodec.decode(
            WireEnvelope<InteractiveApprovalProofBody>.self,
            from: requestJSON
        )
        guard transitionMessageID == nil else {
            return try errorResponse(
                correlationID: request.messageID,
                responseMessageID: responseMessageID,
                sentAtUnixMilliseconds: context.wallNowUnixMilliseconds,
                code: "rateLimit.exceeded",
                retry: .backoff,
                safeArguments: .object([
                    .init(key: "retryAfterMilliseconds", value: .integer(1_000)),
                ])
            )
        }
        guard var pending,
              request.correlationID == pending.challengeMessageID,
              request.body.approvalID == pending.approvalID,
              samePrimary(context, pending.binding) else {
            self.pending = nil
            return try authenticationFailure(
                correlationID: request.messageID,
                responseMessageID: responseMessageID,
                sentAtUnixMilliseconds: context.wallNowUnixMilliseconds
            )
        }
        self.pending = nil
        transitionMessageID = request.messageID
        transitionLocalBinding = InteractiveLocalAuthorityBindingV0(
            deviceID: context.deviceID,
            requestID: pending.requestID.rawValue,
            approvalID: pending.approvalID.rawValue,
            interactiveSessionID: nil
        )
        defer {
            if transitionMessageID == request.messageID {
                transitionMessageID = nil
            }
            transitionLocalBinding = nil
        }
        guard let snapshot = try await admission.snapshot(deviceID: context.deviceID),
              transitionMessageID == request.messageID,
              InteractiveSessionRuntimeRequirementV0(
                command: context,
                admission: snapshot
              ).isEligibleForInteractiveControl,
              snapshot.selectedDisplayID == pending.selectedDisplayID else {
            return try denied(
                correlationID: request.messageID,
                responseMessageID: responseMessageID,
                sentAtUnixMilliseconds: context.wallNowUnixMilliseconds
            )
        }
        do {
            let generatedMaterials = try await materials.bootstrapMaterials()
            guard transitionMessageID == request.messageID else {
                return try authenticationFailure(
                    correlationID: request.messageID,
                    responseMessageID: responseMessageID,
                    sentAtUnixMilliseconds: context.wallNowUnixMilliseconds
                )
            }
            let bootstrap = try pending.bootstrapAuthority.verifyAndCreate(
                rawApprovalSignature: request.body.signature.rawValue,
                current: InteractiveApprovalCurrentState(
                    clientID: context.clientID,
                    primaryConnectionID: context.primaryConnectionID,
                    authorizationEpoch: context.authorizationEpoch.rawValue,
                    grantRevision: context.grantRevision.rawValue,
                    policyRevision: context.policyRevision.rawValue,
                    approvalPublicKeyX963: snapshot.approvalPublicKeyX963
                ),
                materials: generatedMaterials,
                wallNowUnixMilliseconds: context.wallNowUnixMilliseconds,
                monotonicNowMilliseconds: context.monotonicNowMilliseconds
            )
            let acceptedData = try WireCodec.encode(WireEnvelope(
                version: request.version,
                messageID: responseMessageID,
                correlationID: request.messageID,
                sentAtUnixMilliseconds: context.wallNowUnixMilliseconds,
                body: bootstrap.acceptedBody
            ))
            let sessionID = bootstrap.acceptedBody.interactiveSessionID.rawValue
            do {
                try await auditWriter?.recordRequiredApproval(
                    requestID: pending.requestID.rawValue,
                    approvalID: pending.approvalID.rawValue,
                    interactiveSessionID: sessionID,
                    context: context
                )
            } catch {
                return try errorResponse(
                    correlationID: request.messageID,
                    responseMessageID: responseMessageID,
                    sentAtUnixMilliseconds: context.wallNowUnixMilliseconds,
                    code: "storage.securityUnavailable",
                    retry: .afterUserAction,
                    safeArguments: .object([
                        .init(key: "recovery", value: .string("localRepair")),
                    ])
                )
            }
            let activeReservation = Active(
                deviceID: context.deviceID,
                requestID: pending.requestID.rawValue,
                approvalID: pending.approvalID.rawValue,
                interactiveSessionID: sessionID,
                primaryConnectionID: context.primaryConnectionID,
                auditContext: context
            )
            transitionLocalBinding = InteractiveLocalAuthorityBindingV0(
                deviceID: context.deviceID,
                requestID: pending.requestID.rawValue,
                approvalID: pending.approvalID.rawValue,
                interactiveSessionID: sessionID
            )
            active = activeReservation
            try await runtime.install(
                bootstrap,
                requirement: InteractiveSessionRuntimeRequirementV0(
                    command: context,
                    admission: snapshot
                )
            )
            await auditWriter?.recordStarted(
                requestID: pending.requestID.rawValue,
                interactiveSessionID: sessionID,
                context: context
            )
            guard transitionMessageID == request.messageID,
                  active?.interactiveSessionID
                    == activeReservation.interactiveSessionID,
                  active?.primaryConnectionID
                    == activeReservation.primaryConnectionID else {
                await runtime.terminate(
                    interactiveSessionID: activeReservation.interactiveSessionID,
                    primaryConnectionID: activeReservation.primaryConnectionID,
                    reason: .clientDisconnected
                )
                return try authenticationFailure(
                    correlationID: request.messageID,
                    responseMessageID: responseMessageID,
                    sentAtUnixMilliseconds: context.wallNowUnixMilliseconds
                )
            }
            return acceptedData
        } catch let error as InteractiveSecurityAuthorityError {
            switch error {
            case .currentStateChanged:
                return try denied(
                    correlationID: request.messageID,
                    responseMessageID: responseMessageID,
                    sentAtUnixMilliseconds: context.wallNowUnixMilliseconds
                )
            default:
                return try authenticationFailure(
                    correlationID: request.messageID,
                    responseMessageID: responseMessageID,
                    sentAtUnixMilliseconds: context.wallNowUnixMilliseconds
                )
            }
        } catch {
            if let failed = active,
               failed.primaryConnectionID == context.primaryConnectionID {
                active = nil
                await auditWriter?.recordTerminal(
                    requestID: failed.requestID,
                    interactiveSessionID: failed.interactiveSessionID,
                    code: .interactiveFailed,
                    outcome: .failed,
                    observedAtUnixMilliseconds:
                        context.wallNowUnixMilliseconds,
                    context: context
                )
            }
            return try errorResponse(
                correlationID: request.messageID,
                responseMessageID: responseMessageID,
                sentAtUnixMilliseconds: context.wallNowUnixMilliseconds,
                code: "provider.unavailable",
                retry: .backoff
            )
        }
    }

    private func samePrimary(
        _ lhs: InteractiveSessionCommandContextV0,
        _ rhs: InteractiveSessionCommandContextV0
    ) -> Bool {
        lhs.deviceID == rhs.deviceID
            && lhs.clientID == rhs.clientID
            && lhs.deviceState == rhs.deviceState
            && lhs.authorizationEpoch == rhs.authorizationEpoch
            && lhs.grantRevision == rhs.grantRevision
            && lhs.policyRevision == rhs.policyRevision
            && lhs.primaryConnectionID == rhs.primaryConnectionID
            && lhs.hostID == rhs.hostID
            && lhs.hostFingerprint == rhs.hostFingerprint
    }

    private func isEligible(
        _ snapshot: InteractiveSessionAdmissionSnapshotV0,
        for context: InteractiveSessionCommandContextV0
    ) -> Bool {
        InteractiveSessionRuntimeRequirementV0(
            command: context,
            admission: snapshot
        ).isEligibleForInteractiveControl
    }

    private func denied(
        correlationID: WireUUID,
        responseMessageID: WireUUID,
        sentAtUnixMilliseconds: Int64
    ) throws -> Data {
        try errorResponse(
            correlationID: correlationID,
            responseMessageID: responseMessageID,
            sentAtUnixMilliseconds: sentAtUnixMilliseconds,
            code: "policy.denied",
            retry: .afterUserAction,
            safeArguments: .object([
                .init(
                    key: "capabilityID",
                    value: .string(InteractiveControlCapabilityV0.identifier)
                ),
            ])
        )
    }

    private func authenticationFailure(
        correlationID: WireUUID,
        responseMessageID: WireUUID,
        sentAtUnixMilliseconds: Int64
    ) throws -> Data {
        try errorResponse(
            correlationID: correlationID,
            responseMessageID: responseMessageID,
            sentAtUnixMilliseconds: sentAtUnixMilliseconds,
            code: "auth.invalidProof",
            retry: .never
        )
    }

    private func errorResponse(
        correlationID: WireUUID,
        responseMessageID: WireUUID,
        sentAtUnixMilliseconds: Int64,
        code: String,
        retry: ProtocolErrorRetry,
        safeArguments: CanonicalJSONValue = .object([])
    ) throws -> Data {
        try WireCodec.encode(WireEnvelope(
            messageID: responseMessageID,
            correlationID: correlationID,
            sentAtUnixMilliseconds: sentAtUnixMilliseconds,
            body: try ProtocolErrorResponseBody(
                code: code,
                retry: retry,
                safeArguments: safeArguments
            )
        ))
    }
}
