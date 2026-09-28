#if os(macOS)
import CompanionIPC
import CompanionInteractiveWire
import CompanionLocalXPCPlatformC
import Dispatch
import Foundation
import OSLog

private let macLocalXPCInteractiveInputLoggerV1 = Logger(
    subsystem: "media.jenny.maccompanion",
    category: "interactive-input-xpc"
)

private let macLocalXPCInteractiveLeaseLoggerV1 = Logger(
    subsystem: "media.jenny.maccompanion",
    category: "interactive-lease-xpc"
)

/// Preserves the XPC wire distinction between a payload-bearing reply and an
/// exact payload-free acknowledgement. Foundation may expose a non-null
/// sentinel base address for empty `Data`; that sentinel must never cross the
/// C boundary for a message whose closed shape forbids a payload field.
package enum MacLocalXPCReplyPayloadBytesV1 {
    package static func withBytes<Result>(
        _ payload: Data,
        _ body: (UnsafePointer<UInt8>?, Int) -> Result
    ) -> Result {
        payload.withUnsafeBytes { rawBuffer in
            let bytes: UnsafePointer<UInt8>? = payload.isEmpty
                ? nil
                : rawBuffer.bindMemory(to: UInt8.self).baseAddress
            return body(bytes, payload.count)
        }
    }
}

public enum MacLocalXPCIdentityV1 {
    public static let serviceName = "media.jenny.maccompanion.agent"
    public static let menuSigningIdentifier = "media.jenny.maccompanion"
    public static let agentSigningIdentifier =
        "media.jenny.maccompanion.agent"
}

#if DEBUG
/// A disposable Mach service address, never a substitute signing identity.
/// UUID-only input cannot name the installed service. Absent from Release.
public enum MacLocalXPCIsolatedTestAddressV1 {
    public static func serviceName(_ testID: UUID) -> String {
        "media.jenny.maccompanion.xpc-test.\(testID.uuidString.lowercased())"
    }
}
#endif

public enum MacLocalXPCServerEventV1: Equatable, Sendable {
    case authenticatedMenu(generation: UInt64)
    case menuReady(generation: UInt64)
    case remoteAccessEnabled(generation: UInt64)
    case invalidatedMenu(generation: UInt64)
}

public enum MacLocalXPCClientEventV1: Equatable, Sendable {
    case authenticatedAgent(build: UInt64)
    case menuReadyAcknowledged
    case agentStatus(
        generation: UInt64,
        snapshot: LocalAgentStatusSnapshot
    )
    case agentStatusUnavailable(generation: UInt64)
    case invalidated
}

public enum MacLocalXPCServerProfileV1: Equatable, Sendable {
    /// Closed recovery/default profile: authenticate and reject every later
    /// message. It can never receive the disabled bootstrap authority.
    case authenticationOnly

    /// Enables only the exact one-use disabled-to-enabled bootstrap exchange.
    /// This profile requires an injected durable bootstrap authority.
    case disabledRemoteAccessBootstrap

    /// Enables only the exact one-use lifecycle.menu-ready exchange.
    case menuLifecycleReadiness

    /// Enables readiness followed by bounded, content-free status reads.
    /// This profile requires an injected reader from the complete Agent root.
    case menuLifecycleReadinessAndStatus

    /// Package-only construction profile that additionally issues the five
    /// authenticated Agent-to-menu presentation capabilities after readiness.
    /// Permanent product roots must opt in explicitly.
    case menuLifecycleReadinessStatusAndPresentation

    /// Recovery-only profile: readiness, content-free unavailable status,
    /// recovery presentation, the exact destructive recovery command, and its
    /// receipt-bound completion acknowledgement. It admits no pairing,
    /// bootstrap, update, Interactive, or network authority.
    case hostIdentityRecovery

    var admitsMenuLifecycleReadiness: Bool {
        self == .menuLifecycleReadiness
            || self == .menuLifecycleReadinessAndStatus
            || self == .menuLifecycleReadinessStatusAndPresentation
            || self == .hostIdentityRecovery
    }

    var admitsRemoteAccessBootstrap: Bool {
        self == .disabledRemoteAccessBootstrap
    }

    var admitsAgentStatus: Bool {
        self == .menuLifecycleReadinessAndStatus
            || self == .menuLifecycleReadinessStatusAndPresentation
            || self == .hostIdentityRecovery
    }

    var admitsMenuPresentation: Bool {
        self == .menuLifecycleReadinessStatusAndPresentation
            || self == .hostIdentityRecovery
    }

    var admitsMenuPairingCommands: Bool {
        self == .menuLifecycleReadinessStatusAndPresentation
    }

    var admitsHostIdentityRecovery: Bool {
        self == .hostIdentityRecovery
    }

    var admitsInteractiveLeaseTransport: Bool {
        self == .menuLifecycleReadinessStatusAndPresentation
    }

    var admitsInteractiveAdmissionPublication: Bool {
        self == .menuLifecycleReadinessStatusAndPresentation
    }

    var admitsUpdateQuiescence: Bool {
        self == .menuLifecycleReadinessStatusAndPresentation
    }
}

public enum MacLocalXPCConstructionErrorV1: Error, Equatable, Sendable {
    case alreadyStarted
    case listenerConstruction
    case sessionConstruction
    case peerRequirement
    case activation
    case generationExhausted
    case invalidProfile
    case invalidAgentBuild
}

/// Reads the immutable numeric build owned by the current process bundle.
/// The value crosses local XPC only after signed-peer authentication and is
/// rejected unless it has one canonical decimal representation.
public enum MacLocalXPCProcessBuildV1 {
    public static func current(bundle: Bundle = .main) -> UInt64? {
        canonical(bundle.object(forInfoDictionaryKey: "CFBundleVersion"))
    }

    package static func canonical(_ value: Any?) -> UInt64? {
        guard let text = value as? String,
              !text.isEmpty,
              text.utf8.count <= 20,
              text.first != "0" || text == "0",
              let build = UInt64(text),
              String(build) == text else {
            return nil
        }
        return build
    }
}

@available(macOS 26.0, *)
enum MacLocalXPCExactMessageParserValidationV1 {
    static func selfTest() -> Bool {
        MCLocalXPCExactMessageParserSelfTest()
    }
}

public enum MacLocalXPCHandshakeActionV1: Equatable, Sendable {
    case acknowledgeAndAuthenticate
    case reject
}

public enum MacLocalXPCLifecycleReadyActionV1: Equatable, Sendable {
    case acknowledgeAndPublish
    case reject
}

/// Pure one-use pre-authentication gate shared by the platform listener and
/// its focused tests. An exact hello is the only value that can cross this
/// boundary; post-authentication methods use separate one-use gates.
public struct MacLocalXPCHandshakeGateV1: Sendable {
    public enum State: Equatable, Sendable {
        case awaitingHello
        case authenticated
        case invalidated
    }

    public private(set) var state: State = .awaitingHello

    public init() {}

    public mutating func receive(
        exactHello: Bool
    ) -> MacLocalXPCHandshakeActionV1 {
        guard state == .awaitingHello, exactHello else {
            state = .invalidated
            return .reject
        }
        state = .authenticated
        return .acknowledgeAndAuthenticate
    }

    public mutating func invalidate() {
        state = .invalidated
    }
}

/// Tracks the server event-publication boundary separately from transport
/// authentication. A peer is not an observable authenticated lifetime until
/// its exact acknowledgement has been sent successfully.
public struct MacLocalXPCAuthenticatedLifetimeV1: Sendable {
    private var handshake = MacLocalXPCHandshakeGateV1()
    public private(set) var authenticationPublished = false
    public private(set) var menuReadinessPublished = false
    private var menuReadinessAccepted = false

    public init() {}

    public mutating func receiveHello(
        exact: Bool
    ) -> MacLocalXPCHandshakeActionV1 {
        handshake.receive(exactHello: exact)
    }

    @discardableResult
    public mutating func publishAuthentication() -> Bool {
        guard handshake.state == .authenticated,
              !authenticationPublished else {
            return false
        }
        authenticationPublished = true
        return true
    }

    public mutating func receiveMenuReady(
        exact: Bool
    ) -> MacLocalXPCLifecycleReadyActionV1 {
        guard handshake.state == .authenticated,
              authenticationPublished,
              !menuReadinessAccepted,
              !menuReadinessPublished,
              exact else {
            handshake.invalidate()
            return .reject
        }
        menuReadinessAccepted = true
        return .acknowledgeAndPublish
    }

    @discardableResult
    public mutating func publishMenuReadiness() -> Bool {
        guard menuReadinessAccepted,
              !menuReadinessPublished else {
            return false
        }
        menuReadinessAccepted = false
        menuReadinessPublished = true
        return true
    }

    public mutating func invalidate() -> Bool {
        let shouldPublishInvalidation = authenticationPublished
        authenticationPublished = false
        menuReadinessAccepted = false
        menuReadinessPublished = false
        handshake.invalidate()
        return shouldPublishInvalidation
    }
}

/// Admits a transport generation only after its exact hello has completed.
/// Merely opening a candidate connection never displaces the current peer.
struct MacLocalXPCPeerGenerationGateV1: Sendable {
    private(set) var currentGeneration: UInt64?

    mutating func authenticate(
        generation: UInt64
    ) -> UInt64? {
        let replaced = currentGeneration
        currentGeneration = generation
        return replaced == generation ? nil : replaced
    }

    func admitsPostAuthenticationTraffic(
        generation: UInt64
    ) -> Bool {
        currentGeneration == generation
    }

    mutating func invalidate(generation: UInt64) -> Bool {
        guard currentGeneration == generation else { return false }
        currentGeneration = nil
        return true
    }
}

/// Gives each client session a monotonic identity so callbacks retained by a
/// cancelled session can never mutate its replacement.
struct MacLocalXPCClientGenerationGateV1: Sendable {
    private(set) var currentGeneration: UInt64?
    private var nextGeneration: UInt64 = 0

    mutating func begin() -> UInt64? {
        guard nextGeneration < UInt64.max else { return nil }
        nextGeneration += 1
        currentGeneration = nextGeneration
        return nextGeneration
    }

    func admitsCallback(generation: UInt64) -> Bool {
        currentGeneration == generation
    }

    mutating func invalidate(generation: UInt64) -> Bool {
        guard currentGeneration == generation else { return false }
        currentGeneration = nil
        return true
    }
}

/// Fences callbacks from an asynchronously cancelled listener run.
struct MacLocalXPCServerRunGateV1: Sendable {
    private(set) var currentGeneration: UInt64?
    private var nextGeneration: UInt64 = 0

    mutating func begin() -> UInt64? {
        guard currentGeneration == nil,
              nextGeneration < UInt64.max else {
            return nil
        }
        nextGeneration += 1
        currentGeneration = nextGeneration
        return nextGeneration
    }

    func admits(generation: UInt64) -> Bool {
        currentGeneration == generation
    }

    mutating func end(generation: UInt64) -> Bool {
        guard currentGeneration == generation else { return false }
        currentGeneration = nil
        return true
    }
}

/// Applies a fixed admission bound to sessions that have not completed hello.
struct MacLocalXPCPendingCandidateGateV1: Sendable {
    let limit: Int
    private(set) var generations: Set<UInt64> = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    mutating func admit(generation: UInt64) -> Bool {
        guard generations.count < limit else { return false }
        return generations.insert(generation).inserted
    }

    mutating func remove(generation: UInt64) {
        generations.remove(generation)
    }

    func contains(generation: UInt64) -> Bool {
        generations.contains(generation)
    }

    mutating func removeAll() {
        generations.removeAll()
    }
}

@available(macOS 26.0, *)
public final class MacLocalXPCServerV1:
    @unchecked Sendable,
    MacLocalXPCMenuPresentationSendingV1,
    MacLocalXPCGenerationBoundInteractiveLeaseSendingV1,
    MacLocalXPCInteractiveLeaseSendingV1,
    MacLocalXPCGenerationBoundInteractiveInputSendingV1,
    MacLocalXPCInteractiveInputSendingV1
{
    public typealias EventHandler = @Sendable (MacLocalXPCServerEventV1) -> Void
    package static let maximumAdmittedPresentationsPerGeneration = 8
    package static let presentationReplyTimeoutSeconds = 3
    package static let remoteAccessBootstrapTimeoutSeconds = 5
    package static let menuPairingCommandTimeoutSeconds = 4
    package static let updateQuiescenceCommandTimeoutSeconds = 4
    package static let interactiveLeaseReplyTimeoutSeconds = 5
    package static let interactiveAdmissionTimeoutSeconds = 3
    package static let interactiveInputReplyTimeoutSeconds = 2
    package static let interactiveMediaOperationTimeoutSeconds = 3

    private final class PendingInteractiveInput: @unchecked Sendable {
        let requestID: UUID
        let transaction:
            MacLocalXPCInteractiveRoleDataTransactionGateV1.Active
        let continuation: CheckedContinuation<Void, any Error>
        var deadline: DispatchWorkItem?

        init(
            requestID: UUID,
            transaction:
                MacLocalXPCInteractiveRoleDataTransactionGateV1.Active,
            continuation: CheckedContinuation<Void, any Error>
        ) {
            self.requestID = requestID
            self.transaction = transaction
            self.continuation = continuation
        }
    }

    private final class PendingInteractiveMediaPublication:
        @unchecked Sendable
    {
        let transaction:
            MacLocalXPCInteractiveRoleDataTransactionGateV1.Active
        var deadline: DispatchWorkItem?
        var task: Task<Void, Never>?
        private let requestLease:
            MacLocalXPCStatusRequestLeaseV1<MCLocalXPCMessageRef>

        init(
            transaction:
                MacLocalXPCInteractiveRoleDataTransactionGateV1.Active,
            request: MCLocalXPCMessageRef
        ) {
            self.transaction = transaction
            requestLease = MacLocalXPCStatusRequestLeaseV1(request: request)
        }

        func takeOwnedRequest() -> MCLocalXPCMessageRef? {
            requestLease.takeOwnedRequest()
        }

        func releaseOwnedRequest() {
            requestLease.releaseIfOwned()
        }
    }

    private final class PendingInteractiveAdmissionPublication:
        @unchecked Sendable
    {
        let transaction:
            MacLocalXPCInteractiveAdmissionTransactionGateV1.Active
        let publication: LocalInteractiveAdmissionPublicationV1
        var deadline: DispatchWorkItem?
        var task: Task<Void, Never>?
        private let requestLease:
            MacLocalXPCStatusRequestLeaseV1<MCLocalXPCMessageRef>

        init(
            transaction:
                MacLocalXPCInteractiveAdmissionTransactionGateV1.Active,
            publication: LocalInteractiveAdmissionPublicationV1,
            request: MCLocalXPCMessageRef
        ) {
            self.transaction = transaction
            self.publication = publication
            requestLease = MacLocalXPCStatusRequestLeaseV1(request: request)
        }

        func takeOwnedRequest() -> MCLocalXPCMessageRef? {
            requestLease.takeOwnedRequest()
        }

        func releaseOwnedRequest() {
            requestLease.releaseIfOwned()
        }
    }

    private enum InteractiveLeaseCommand: Sendable {
        case prepareInitialDesktop(
            LocalInteractiveInitialDesktopPreparationCommandV1
        )
        case install(InteractiveRuntimeInstallCommandV0)
        case renew(InteractiveRuntimeLeaseRenewalV0)
        case revoke(InteractiveRuntimeRevokeCommandV0)
        case surfaceTargets(LocalInteractiveSurfaceTargetsCommandV1)
        case surfaceResolve(LocalInteractiveSurfaceResolveCommandV1)
        case surfaceTransition(InteractiveRuntimeSurfaceTransitionCommandV0)
        case surfaceAcknowledgement(
            InteractiveRuntimeSurfaceAcknowledgementCommandV0
        )
        case surfaceFailure(LocalInteractiveSurfaceFailureCommandV1)
        case focusSnapshot(LocalInteractiveFocusSnapshotCommandV1)
        case displayCatalog(LocalInteractiveDisplayCatalogCommandV1)
        case displaySelect(LocalInteractiveDisplaySelectCommandV1)
        case nativeBackend(LocalInteractiveNativeBackendCommandV1)
        case nativeSnapshot(LocalInteractiveNativeSnapshotCommandV1)
        case webRTCOffer(LocalInteractiveWebRTCOfferCommandV1)
        case webRTCAnswer(LocalInteractiveWebRTCAnswerCommandV1)
        case webRTCClose(LocalInteractiveWebRTCCloseCommandV1)

        var kind: MacLocalXPCInteractiveLeaseCommandKindV1 {
            switch self {
            case .prepareInitialDesktop: .prepareInitialDesktop
            case .install: .install
            case .renew: .renew
            case .revoke: .revoke
            case .surfaceTargets: .surfaceTargets
            case .surfaceResolve: .surfaceResolve
            case .surfaceTransition: .surfaceTransition
            case .surfaceAcknowledgement: .surfaceAcknowledgement
            case .surfaceFailure: .surfaceFailure
            case .focusSnapshot: .focusSnapshot
            case .displayCatalog: .displayCatalog
            case .displaySelect: .displaySelect
            case .nativeBackend: .nativeBackend
            case .nativeSnapshot: .nativeSnapshot
            case .webRTCOffer: .webRTCOffer
            case .webRTCAnswer: .webRTCAnswer
            case .webRTCClose: .webRTCClose
            }
        }

        var authorizationMethod: LocalIPCMethod {
            switch self {
            case .prepareInitialDesktop: .applyInteractiveSurface
            case .install, .renew: .installInteractiveLease
            case .revoke: .revokeInteractiveLease
            case .surfaceTargets, .surfaceResolve,
                    .surfaceTransition, .surfaceAcknowledgement,
                    .surfaceFailure:
                .applyInteractiveSurface
            case .focusSnapshot:
                .applyInteractiveSurface
            case .displayCatalog, .displaySelect,
                 .nativeBackend, .nativeSnapshot, .webRTCOffer, .webRTCAnswer, .webRTCClose:
                .applyInteractiveSurface
            }
        }
    }

    private final class InteractiveLeaseCancellationMarker:
        @unchecked Sendable
    {
        private let lock = NSLock()
        private var cancelled = false

        func markCancelled() {
            lock.withLock { cancelled = true }
        }

        func isCancelled() -> Bool {
            lock.withLock { cancelled }
        }
    }

    private final class PendingInteractiveLeaseCommand:
        @unchecked Sendable
    {
        let requestID: UUID
        let transaction:
            MacLocalXPCInteractiveLeaseTransactionGateV1.Active
        let command: InteractiveLeaseCommand
        let continuation: CheckedContinuation<Data?, any Error>
        var deadline: DispatchWorkItem?

        init(
            requestID: UUID,
            transaction:
                MacLocalXPCInteractiveLeaseTransactionGateV1.Active,
            command: InteractiveLeaseCommand,
            continuation: CheckedContinuation<Data?, any Error>
        ) {
            self.requestID = requestID
            self.transaction = transaction
            self.command = command
            self.continuation = continuation
        }
    }

    private enum MenuPairingCommand: Sendable {
        case create(LocalPairingSessionCreateCommandV0)
        case dismiss(LocalPairingSessionDismissCommandV0)
        case resolveDecision(LocalPairingDecisionCommandV0)
        case recoverHostIdentity(LocalHostIdentityRecoveryCommandV0)
        case acknowledgeHostIdentityRecoveryCompletion(
            LocalHostIdentityRecoveredReceiptV0
        )
        case requestInteractiveControlGrantReview(
            LocalInteractiveControlGrantReviewRequestV0
        )
        case decideInteractiveControlGrant(LocalGrantDecisionCommandV0)
        case requestDeviceRevocationReview(LocalDeviceRevocationReviewRequestV1)
        case revokeDevice(LocalDeviceRevocationCommandV0)
        case requestCapabilityGrantReview(LocalCapabilityGrantReviewRequestV1)
        case decideCapabilityGrant(LocalGrantDecisionCommandV0)

        var kind: MacLocalXPCMenuPairingCommandKindV1 {
            switch self {
            case .create: .create
            case .dismiss: .dismiss
            case .resolveDecision: .resolveDecision
            case .recoverHostIdentity: .recoverHostIdentity
            case .acknowledgeHostIdentityRecoveryCompletion:
                .acknowledgeHostIdentityRecoveryCompletion
            case .requestInteractiveControlGrantReview:
                .requestInteractiveControlGrantReview
            case .decideInteractiveControlGrant:
                .decideInteractiveControlGrant
            case .requestDeviceRevocationReview: .requestDeviceRevocationReview
            case .revokeDevice: .revokeDevice
            case .requestCapabilityGrantReview: .requestCapabilityGrantReview
            case .decideCapabilityGrant: .decideCapabilityGrant
            }
        }

        var authorizationMethod: LocalIPCMethod {
            switch self {
            case .create: .createPairingSession
            case .dismiss: .dismissPairingSession
            case .resolveDecision: .resolveLocalApproval
            case .recoverHostIdentity: .recoverHostIdentity
            case .acknowledgeHostIdentityRecoveryCompletion:
                .acknowledgeHostIdentityRecoveryCompletion
            case .requestInteractiveControlGrantReview:
                .administerDevices
            case .decideInteractiveControlGrant:
                .decideGrantExpansion
            case .requestDeviceRevocationReview, .revokeDevice: .administerDevices
            case .requestCapabilityGrantReview: .administerDevices
            case .decideCapabilityGrant: .decideGrantExpansion
            }
        }

        var isPairing: Bool {
            switch self {
            case .create, .dismiss, .resolveDecision,
                    .requestInteractiveControlGrantReview,
                    .decideInteractiveControlGrant, .requestDeviceRevocationReview, .revokeDevice,
                    .requestCapabilityGrantReview, .decideCapabilityGrant:
                true
            case .recoverHostIdentity,
                    .acknowledgeHostIdentityRecoveryCompletion:
                false
            }
        }

        var isRecovery: Bool { !isPairing }
    }

    private enum MenuPairingCommandResult: Sendable {
        case created(LocalPairingSessionCreatedReceiptV0)
        case dismissed(LocalPairingSessionDismissedReceiptV0)
        case decision(LocalPairingDecisionReceiptV0)
        case recovered(LocalHostIdentityRecoveredReceiptV0)
        case recoveryCompletionAcknowledged(
            LocalHostIdentityRecoveredReceiptV0
        )
        case interactiveControlGrantReview(
            LocalInteractiveControlGrantReviewV0
        )
        case interactiveControlGrantDecision(LocalGrantDecisionReceiptV0)
        case deviceRevocationReview(LocalDeviceRevocationReviewReplyV1)
        case deviceRevoked(LocalDeviceRevokedReceiptV0)
        case capabilityGrantReview(LocalCapabilityGrantReviewV1)
        case capabilityGrantDecision(LocalGrantDecisionReceiptV0)
    }

    private final class PendingMenuPairingCommand: @unchecked Sendable {
        let transaction: MacLocalXPCMenuPairingCommandTransactionGateV1.Active
        let command: MenuPairingCommand
        var deadline: DispatchWorkItem?
        var task: Task<Void, Never>?
        private let requestLease:
            MacLocalXPCStatusRequestLeaseV1<MCLocalXPCMessageRef>

        init(
            transaction: MacLocalXPCMenuPairingCommandTransactionGateV1.Active,
            command: MenuPairingCommand,
            request: MCLocalXPCMessageRef
        ) {
            self.transaction = transaction
            self.command = command
            requestLease = MacLocalXPCStatusRequestLeaseV1(request: request)
        }

        func takeOwnedRequest() -> MCLocalXPCMessageRef? {
            requestLease.takeOwnedRequest()
        }

        func releaseOwnedRequest() {
            requestLease.releaseIfOwned()
        }
    }

    private final class PendingUpdateQuiescenceCommand:
        @unchecked Sendable
    {
        let transaction:
            MacLocalXPCUpdateQuiescenceTransactionGateV0.Active
        var deadline: DispatchWorkItem?
        var task: Task<Void, Never>?
        private let requestLease:
            MacLocalXPCStatusRequestLeaseV1<MCLocalXPCMessageRef>

        init(
            transaction:
                MacLocalXPCUpdateQuiescenceTransactionGateV0.Active,
            request: MCLocalXPCMessageRef
        ) {
            self.transaction = transaction
            requestLease = MacLocalXPCStatusRequestLeaseV1(request: request)
        }

        func takeOwnedRequest() -> MCLocalXPCMessageRef? {
            requestLease.takeOwnedRequest()
        }

        func releaseOwnedRequest() {
            requestLease.releaseIfOwned()
        }
    }

    private enum BootstrapRequestKind: Sendable {
        case offer
        case enable(LocalRemoteAccessEnableCommandV0)
    }

    private final class PendingBootstrapRequest: @unchecked Sendable {
        let operation: UInt64
        let kind: BootstrapRequestKind
        var deadline: DispatchWorkItem?
        var task: Task<Void, Never>?
        private let requestLease:
            MacLocalXPCStatusRequestLeaseV1<MCLocalXPCMessageRef>

        init(
            operation: UInt64,
            kind: BootstrapRequestKind,
            request: MCLocalXPCMessageRef
        ) {
            self.operation = operation
            self.kind = kind
            requestLease = MacLocalXPCStatusRequestLeaseV1(request: request)
        }

        func takeOwnedRequest() -> MCLocalXPCMessageRef? {
            requestLease.takeOwnedRequest()
        }

        func releaseOwnedRequest() {
            requestLease.releaseIfOwned()
        }
    }

    private final class PendingStatusRead: @unchecked Sendable {
        let operation: UInt64
        var deadline: DispatchWorkItem?
        var task: Task<Void, Never>?
        private let requestLease: MacLocalXPCStatusRequestLeaseV1<MCLocalXPCMessageRef>

        init(operation: UInt64, request: MCLocalXPCMessageRef) {
            self.operation = operation
            requestLease = MacLocalXPCStatusRequestLeaseV1(request: request)
        }

        func takeOwnedRequest() -> MCLocalXPCMessageRef? {
            requestLease.takeOwnedRequest()
        }

        func releaseOwnedRequest() {
            requestLease.releaseIfOwned()
        }
    }

    private final class PresentationCancellationMarker: @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false

        func markCancelled() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }

        func isCancelled() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        func performSendUnlessCancelled<T>(
            _ body: () -> T
        ) -> T? {
            lock.lock()
            defer { lock.unlock() }
            guard !cancelled else { return nil }
            return body()
        }
    }

    private final class PendingPresentation: @unchecked Sendable {
        let requestID: UUID
        let operation: UInt64
        let request: MacLocalXPCMenuPresentationRequestV1
        let cancellationMarker: PresentationCancellationMarker
        let continuation: CheckedContinuation<
            MacLocalXPCMenuPresentationSendOutcomeV1,
            any Error
        >
        var deadline: DispatchWorkItem?

        init(
            requestID: UUID,
            operation: UInt64,
            request: MacLocalXPCMenuPresentationRequestV1,
            cancellationMarker: PresentationCancellationMarker,
            continuation: CheckedContinuation<
                MacLocalXPCMenuPresentationSendOutcomeV1,
                any Error
            >
        ) {
            self.requestID = requestID
            self.operation = operation
            self.request = request
            self.cancellationMarker = cancellationMarker
            self.continuation = continuation
        }
    }

    private final class PeerState: @unchecked Sendable {
        let listenerGeneration: UInt64
        let generation: UInt64
        let peer: MCLocalXPCSessionRef
        var lifetime = MacLocalXPCAuthenticatedLifetimeV1()
        var bootstrapGate =
            MacLocalXPCRemoteAccessBootstrapTransactionGateV1()
        var pendingBootstrapRequest: PendingBootstrapRequest?
        var statusReadGate = MacLocalXPCStatusReadTransactionGateV1()
        var pendingStatusRead: PendingStatusRead?
        var menuPairingCommandGate =
            MacLocalXPCMenuPairingCommandTransactionGateV1()
        var pendingMenuPairingCommand: PendingMenuPairingCommand?
        var updateQuiescenceGate =
            MacLocalXPCUpdateQuiescenceTransactionGateV0()
        var pendingUpdateQuiescenceCommand:
            PendingUpdateQuiescenceCommand?
        var interactiveLeaseGate =
            MacLocalXPCInteractiveLeaseTransactionGateV1()
        var pendingInteractiveLeaseCommand:
            PendingInteractiveLeaseCommand?
        var interactiveAdmissionGate =
            MacLocalXPCInteractiveAdmissionTransactionGateV1()
        var pendingInteractiveAdmissionPublication:
            PendingInteractiveAdmissionPublication?
        var interactiveInputGate =
            MacLocalXPCInteractiveRoleDataTransactionGateV1()
        var pendingInteractiveInput: PendingInteractiveInput?
        var interactiveMediaGate =
            MacLocalXPCInteractiveRoleDataTransactionGateV1()
        var pendingInteractiveMediaPublication:
            PendingInteractiveMediaPublication?
        var presentationIssuanceGate:
            MacLocalXPCMenuPresentationEndpointIssuanceGateV1
        var presentationEndpoint:
            MacLocalXPCAuthenticatedMenuPresentationEndpointV1?
        var presentationFIFO: MacLocalXPCMenuPresentationFIFOStateV1
        var pendingPresentations: [UUID: PendingPresentation] = [:]
        var postAuthenticationFence = MacLocalXPCPostAuthenticationTrafficFenceV1()
        var handshakeDeadline: DispatchWorkItem?
        private var ownedPeer: MCLocalXPCSessionRef?

        init(
            listenerGeneration: UInt64,
            generation: UInt64,
            peer: MCLocalXPCSessionRef
        ) {
            self.listenerGeneration = listenerGeneration
            self.generation = generation
            self.peer = peer
            presentationIssuanceGate = .init(generation: generation)
            presentationFIFO = .init(
                limit: MacLocalXPCServerV1
                    .maximumAdmittedPresentationsPerGeneration
            )
            MCLocalXPCSessionRetain(peer)
            precondition(bootstrapGate.bind(generation: generation))
            precondition(statusReadGate.bind(generation: generation))
            precondition(menuPairingCommandGate.bind(generation: generation))
            precondition(updateQuiescenceGate.bind(generation: generation))
            precondition(interactiveLeaseGate.bind(generation: generation))
            precondition(
                interactiveAdmissionGate.bind(generation: generation)
            )
            precondition(interactiveInputGate.bind(generation: generation))
            precondition(interactiveMediaGate.bind(generation: generation))
            ownedPeer = peer
        }

        func takeOwnedPeer() -> MCLocalXPCSessionRef? {
            let peer = ownedPeer
            ownedPeer = nil
            return peer
        }

        func cancelPendingStatusRead() {
            _ = statusReadGate.invalidate(generation: generation)
            guard let pendingStatusRead else { return }
            self.pendingStatusRead = nil
            pendingStatusRead.deadline?.cancel()
            pendingStatusRead.deadline = nil
            pendingStatusRead.task?.cancel()
            pendingStatusRead.task = nil
            pendingStatusRead.releaseOwnedRequest()
        }

        func cancelPendingMenuPairingCommand() {
            _ = menuPairingCommandGate.invalidate(generation: generation)
            guard let pendingMenuPairingCommand else { return }
            self.pendingMenuPairingCommand = nil
            pendingMenuPairingCommand.deadline?.cancel()
            pendingMenuPairingCommand.deadline = nil
            pendingMenuPairingCommand.task?.cancel()
            pendingMenuPairingCommand.task = nil
            pendingMenuPairingCommand.releaseOwnedRequest()
        }

        func cancelPendingUpdateQuiescenceCommand() {
            _ = updateQuiescenceGate.invalidate(generation: generation)
            guard let pendingUpdateQuiescenceCommand else { return }
            self.pendingUpdateQuiescenceCommand = nil
            pendingUpdateQuiescenceCommand.deadline?.cancel()
            pendingUpdateQuiescenceCommand.deadline = nil
            pendingUpdateQuiescenceCommand.task?.cancel()
            pendingUpdateQuiescenceCommand.task = nil
            pendingUpdateQuiescenceCommand.releaseOwnedRequest()
        }

        func cancelPendingInteractiveLeaseCommand(
            error: MacLocalXPCInteractiveLeaseErrorV1
        ) {
            _ = interactiveLeaseGate.invalidate(generation: generation)
            guard let pendingInteractiveLeaseCommand else { return }
            self.pendingInteractiveLeaseCommand = nil
            pendingInteractiveLeaseCommand.deadline?.cancel()
            pendingInteractiveLeaseCommand.deadline = nil
            pendingInteractiveLeaseCommand.continuation.resume(
                throwing: error
            )
        }

        func cancelPendingInteractiveInput(
            error: MacLocalXPCInteractiveRoleDataErrorV1
        ) {
            _ = interactiveInputGate.invalidate(generation: generation)
            guard let pendingInteractiveInput else { return }
            self.pendingInteractiveInput = nil
            pendingInteractiveInput.deadline?.cancel()
            pendingInteractiveInput.deadline = nil
            pendingInteractiveInput.continuation.resume(throwing: error)
        }

        @discardableResult
        func cancelPendingInteractiveMediaPublication() -> Bool {
            let invalidated = interactiveMediaGate.invalidate(
                generation: generation
            ) != nil
            guard let pendingInteractiveMediaPublication else {
                return invalidated
            }
            self.pendingInteractiveMediaPublication = nil
            pendingInteractiveMediaPublication.deadline?.cancel()
            pendingInteractiveMediaPublication.deadline = nil
            pendingInteractiveMediaPublication.task?.cancel()
            pendingInteractiveMediaPublication.task = nil
            pendingInteractiveMediaPublication.releaseOwnedRequest()
            return true
        }

        @discardableResult
        func cancelPendingInteractiveAdmissionPublication() -> Bool {
            let invalidated = interactiveAdmissionGate.invalidate(
                generation: generation
            ) != nil
            guard let pendingInteractiveAdmissionPublication else {
                return invalidated
            }
            self.pendingInteractiveAdmissionPublication = nil
            pendingInteractiveAdmissionPublication.deadline?.cancel()
            pendingInteractiveAdmissionPublication.deadline = nil
            pendingInteractiveAdmissionPublication.task?.cancel()
            pendingInteractiveAdmissionPublication.task = nil
            pendingInteractiveAdmissionPublication.releaseOwnedRequest()
            return true
        }

        @discardableResult
        func cancelRemoteAccessBootstrap() -> Bool {
            let invalidated = bootstrapGate.invalidate(
                generation: generation
            )
            guard let pendingBootstrapRequest else {
                return invalidated
            }
            self.pendingBootstrapRequest = nil
            pendingBootstrapRequest.deadline?.cancel()
            pendingBootstrapRequest.deadline = nil
            pendingBootstrapRequest.task?.cancel()
            pendingBootstrapRequest.task = nil
            pendingBootstrapRequest.releaseOwnedRequest()
            return invalidated
        }

    }

    private let queue = DispatchQueue(
        label: "media.jenny.maccompanion.local-xpc.agent"
    )
    private let onEvent: EventHandler
    private var listener: MCLocalXPCListenerRef?
    private var peerRequirement: MCLocalXPCPeerRequirementRef?
    private let queueKey = DispatchSpecificKey<UInt8>()
    private var nextGeneration: UInt64 = 0
    private var currentPeerState: PeerState?
    private let bootstrapHandler:
        (any MacLocalXPCRemoteAccessBootstrapHandlingV1)?
    private let statusReader: (any MacLocalXPCStatusReadingV1)?
    private let menuPairingCommandHandler:
        (any MacLocalXPCMenuPairingCommandHandlingV1)?
    private let hostIdentityRecoveryHandler:
        (any MacLocalXPCHostIdentityRecoveryHandlingV1)?
    private let updateQuiescenceHandler:
        (any MacLocalXPCUpdateQuiescenceHandlingV0)?
    private let interactiveAdmissionHandler:
        (any MacLocalXPCInteractiveAdmissionHandlingV1)?
    private let interactiveMediaHandler:
        (any MacLocalXPCInteractiveMediaHandlingV1)?
    private let profile: MacLocalXPCServerProfileV1
    private let agentBuild: UInt64?
    #if DEBUG
    private var isolatedTestID: UUID?

    public convenience init(
        isolatedTestID: UUID,
        profile: MacLocalXPCServerProfileV1,
        bootstrapHandler: (any MacLocalXPCRemoteAccessBootstrapHandlingV1)? = nil,
        statusReader: (any MacLocalXPCStatusReadingV1)? = nil,
        menuPairingCommandHandler: (any MacLocalXPCMenuPairingCommandHandlingV1)? = nil,
        updateQuiescenceHandler: (any MacLocalXPCUpdateQuiescenceHandlingV0)? = nil,
        interactiveAdmissionHandler: (any MacLocalXPCInteractiveAdmissionHandlingV1)? = nil,
        interactiveMediaHandler: (any MacLocalXPCInteractiveMediaHandlingV1)? = nil,
        agentBuild: UInt64? = 1,
        onEvent: @escaping EventHandler
    ) {
        self.init(profile: profile, bootstrapHandler: bootstrapHandler,
                  statusReader: statusReader, menuPairingCommandHandler: menuPairingCommandHandler,
                  updateQuiescenceHandler: updateQuiescenceHandler,
                  interactiveAdmissionHandler: interactiveAdmissionHandler,
                  interactiveMediaHandler: interactiveMediaHandler,
                  agentBuild: agentBuild, onEvent: onEvent)
        self.isolatedTestID = isolatedTestID
    }
    #endif

    private var serviceName: String {
        #if DEBUG
        if let isolatedTestID {
            return MacLocalXPCIsolatedTestAddressV1.serviceName(isolatedTestID)
        }
        #endif
        return MacLocalXPCIdentityV1.serviceName
    }
    private let statusReadTimeout: DispatchTimeInterval = .seconds(2)
    private let bootstrapTimeout: DispatchTimeInterval = .seconds(
        remoteAccessBootstrapTimeoutSeconds
    )
    private let handshakeTimeout: DispatchTimeInterval = .seconds(10)
    private var generationGate = MacLocalXPCPeerGenerationGateV1()
    private var listenerRunGate = MacLocalXPCServerRunGateV1()
    private var pendingGate = MacLocalXPCPendingCandidateGateV1(limit: 8)
    private var peerStates: [UInt64: PeerState] = [:]

    public convenience init(
        profile: MacLocalXPCServerProfileV1 = .authenticationOnly,
        bootstrapHandler:
            (any MacLocalXPCRemoteAccessBootstrapHandlingV1)? = nil,
        statusReader: (any MacLocalXPCStatusReadingV1)? = nil,
        menuPairingCommandHandler:
            (any MacLocalXPCMenuPairingCommandHandlingV1)? = nil,
        hostIdentityRecoveryHandler:
            (any MacLocalXPCHostIdentityRecoveryHandlingV1)? = nil,
        updateQuiescenceHandler:
            (any MacLocalXPCUpdateQuiescenceHandlingV0)? = nil,
        interactiveAdmissionHandler:
            (any MacLocalXPCInteractiveAdmissionHandlingV1)? = nil,
        interactiveMediaHandler:
            (any MacLocalXPCInteractiveMediaHandlingV1)? = nil,
        onEvent: @escaping EventHandler
    ) {
        self.init(
            profile: profile,
            bootstrapHandler: bootstrapHandler,
            statusReader: statusReader,
            menuPairingCommandHandler: menuPairingCommandHandler,
            hostIdentityRecoveryHandler: hostIdentityRecoveryHandler,
            updateQuiescenceHandler: updateQuiescenceHandler,
            interactiveAdmissionHandler: interactiveAdmissionHandler,
            interactiveMediaHandler: interactiveMediaHandler,
            agentBuild: MacLocalXPCProcessBuildV1.current(),
            onEvent: onEvent
        )
    }

    /// Test-only construction seam. Permanent consumers cannot substitute a
    /// caller-selected build for the process bundle measurement.
    package init(
        profile: MacLocalXPCServerProfileV1 = .authenticationOnly,
        bootstrapHandler:
            (any MacLocalXPCRemoteAccessBootstrapHandlingV1)? = nil,
        statusReader: (any MacLocalXPCStatusReadingV1)? = nil,
        menuPairingCommandHandler:
            (any MacLocalXPCMenuPairingCommandHandlingV1)? = nil,
        hostIdentityRecoveryHandler:
            (any MacLocalXPCHostIdentityRecoveryHandlingV1)? = nil,
        updateQuiescenceHandler:
            (any MacLocalXPCUpdateQuiescenceHandlingV0)? = nil,
        interactiveAdmissionHandler:
            (any MacLocalXPCInteractiveAdmissionHandlingV1)? = nil,
        interactiveMediaHandler:
            (any MacLocalXPCInteractiveMediaHandlingV1)? = nil,
        agentBuild: UInt64?,
        onEvent: @escaping EventHandler
    ) {
        self.profile = profile
        self.bootstrapHandler = bootstrapHandler
        self.statusReader = statusReader
        self.menuPairingCommandHandler = menuPairingCommandHandler
        self.hostIdentityRecoveryHandler = hostIdentityRecoveryHandler
        self.updateQuiescenceHandler = updateQuiescenceHandler
        self.interactiveAdmissionHandler = interactiveAdmissionHandler
        self.interactiveMediaHandler = interactiveMediaHandler
        self.agentBuild = agentBuild
        self.onEvent = onEvent
        queue.setSpecific(key: queueKey, value: 1)
    }

    deinit {
        teardown(publishInvalidation: false)
    }

    public func start() throws {
        try syncOnQueue {
            guard listener == nil,
                  listenerRunGate.currentGeneration == nil else {
                throw MacLocalXPCConstructionErrorV1.alreadyStarted
            }
            guard profile.admitsAgentStatus == (statusReader != nil) else {
                throw MacLocalXPCConstructionErrorV1.invalidProfile
            }
            guard profile.admitsRemoteAccessBootstrap
                    == (bootstrapHandler != nil) else {
                throw MacLocalXPCConstructionErrorV1.invalidProfile
            }
            guard profile.admitsMenuPairingCommands
                    == (menuPairingCommandHandler != nil) else {
                throw MacLocalXPCConstructionErrorV1.invalidProfile
            }
            guard profile.admitsHostIdentityRecovery
                    == (hostIdentityRecoveryHandler != nil) else {
                throw MacLocalXPCConstructionErrorV1.invalidProfile
            }
            guard profile.admitsUpdateQuiescence
                    == (updateQuiescenceHandler != nil) else {
                throw MacLocalXPCConstructionErrorV1.invalidProfile
            }
            guard profile.admitsInteractiveAdmissionPublication
                    == (interactiveAdmissionHandler != nil) else {
                throw MacLocalXPCConstructionErrorV1.invalidProfile
            }
            guard agentBuild != nil else {
                throw MacLocalXPCConstructionErrorV1.invalidAgentBuild
            }

            var result = MCLocalXPCResultOK
            guard let requirement =
                    MCLocalXPCPeerRequirementCreateSameTeamIdentifier(
                        MacLocalXPCIdentityV1.menuSigningIdentifier,
                        &result
                    ),
                  result == MCLocalXPCResultOK else {
                throw MacLocalXPCConstructionErrorV1.peerRequirement
            }
            guard let listenerGeneration = listenerRunGate.begin() else {
                MCLocalXPCPeerRequirementRelease(requirement)
                throw MacLocalXPCConstructionErrorV1.generationExhausted
            }
            guard let candidate = MCLocalXPCListenerCreateInactive(
                serviceName,
                queue,
                { [weak self] peer in
                    guard let self else {
                        MCLocalXPCListenerRejectPeer(peer)
                        return
                    }
                    self.accept(
                        peer: peer,
                        listenerGeneration: listenerGeneration
                    )
                },
                &result
            ), result == MCLocalXPCResultOK else {
                _ = listenerRunGate.end(generation: listenerGeneration)
                MCLocalXPCPeerRequirementRelease(requirement)
                throw MacLocalXPCConstructionErrorV1.listenerConstruction
            }

            MCLocalXPCListenerSetPeerRequirement(candidate, requirement)
            listener = candidate
            peerRequirement = requirement
            guard MCLocalXPCListenerActivate(candidate)
                    == MCLocalXPCResultOK else {
                listener = nil
                peerRequirement = nil
                _ = listenerRunGate.end(generation: listenerGeneration)
                MCLocalXPCListenerCancel(candidate)
                MCLocalXPCPeerRequirementRelease(requirement)
                throw MacLocalXPCConstructionErrorV1.activation
            }
        }
    }

    public func cancel() {
        teardown(publishInvalidation: true)
    }

    private func teardown(publishInvalidation: Bool) {
        syncOnQueue {
            let listener = self.listener
            self.listener = nil
            let requirement = peerRequirement
            peerRequirement = nil
            if let listenerGeneration =
                    listenerRunGate.currentGeneration {
                _ = listenerRunGate.end(
                    generation: listenerGeneration
                )
            }

            let acceptedPeers = Array(peerStates.values)
            peerStates.removeAll()
            pendingGate.removeAll()
            var invalidatedGeneration: UInt64?
            if let currentPeerState {
                self.currentPeerState = nil
                _ = generationGate.invalidate(
                    generation: currentPeerState.generation
                )
                if currentPeerState.lifetime.invalidate() {
                    invalidatedGeneration = currentPeerState.generation
                }
            }

            for state in acceptedPeers {
                state.handshakeDeadline?.cancel()
                state.handshakeDeadline = nil
                fencePostAuthenticationTraffic(
                    state,
                    presentationError: .endpointUnavailable
                )
                if let ownedPeer = state.takeOwnedPeer() {
                    MCLocalXPCSessionCancelOwned(ownedPeer)
                }
            }
            if let listener {
                MCLocalXPCListenerCancel(listener)
            }
            if let requirement {
                MCLocalXPCPeerRequirementRelease(requirement)
            }
            if publishInvalidation, let invalidatedGeneration {
                onEvent(
                    .invalidatedMenu(generation: invalidatedGeneration)
                )
            }
        }
    }

    /// Fails closed only the still-current authenticated generation. The
    /// asynchronous hop is safe from lifecycle callbacks originating on the
    /// listener queue and cannot cancel a later replacement generation.
    public func cancelPeer(generation: UInt64) {
        queue.async { [weak self] in
            guard let self,
                  let currentPeerState,
                  currentPeerState.generation == generation,
                  listenerRunGate.admits(
                    generation: currentPeerState.listenerGeneration
                  ),
                  peerStates[generation] === currentPeerState else {
                return
            }
            self.cancelAuthenticatedPeer(
                currentPeerState,
                presentationError: .endpointUnavailable
            )
        }
    }

    public func applyInteractiveInput(
        _ envelope: InteractiveInputEnvelope
    ) async throws {
        try await applyInteractiveInput(envelope, endpointBinding: nil)
    }

    package func applyInteractiveInput(
        generation: UInt64,
        endpointToken: UUID,
        envelope: InteractiveInputEnvelope
    ) async throws {
        try await applyInteractiveInput(
            envelope,
            endpointBinding: .init(
                generation: generation,
                endpointToken: endpointToken
            )
        )
    }

    private func applyInteractiveInput(
        _ envelope: InteractiveInputEnvelope,
        endpointBinding: MacLocalXPCInteractiveLeaseEndpointBindingV1?
    ) async throws {
        let payload: Data
        do {
            payload = try InteractiveInputCodec.encode(envelope)
        } catch {
            throw MacLocalXPCInteractiveRoleDataErrorV1
                .malformedOrTransportError
        }
        let requestID = UUID()
        let marker = InteractiveLeaseCancellationMarker()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                queue.async { [weak self] in
                    guard let self else {
                        continuation.resume(throwing:
                            MacLocalXPCInteractiveRoleDataErrorV1.unavailable
                        )
                        return
                    }
                    self.admitInteractiveInput(
                        requestID: requestID,
                        payload: payload,
                        endpointBinding: endpointBinding,
                        cancellationMarker: marker,
                        continuation: continuation
                    )
                }
            }
        } onCancel: { [weak self] in
            marker.markCancelled()
            self?.queue.async { [weak self] in
                self?.cancelInteractiveInput(requestID: requestID)
            }
        }
    }

    private func admitInteractiveInput(
        requestID: UUID,
        payload: Data,
        endpointBinding: MacLocalXPCInteractiveLeaseEndpointBindingV1?,
        cancellationMarker: InteractiveLeaseCancellationMarker,
        continuation: CheckedContinuation<Void, any Error>
    ) {
        guard !cancellationMarker.isCancelled() else {
            continuation.resume(throwing: CancellationError())
            return
        }
        guard let state = currentPeerState,
              endpointBinding.map({
                  $0.admits(
                      generation: state.generation,
                      issuedEndpointToken:
                          state.presentationIssuanceGate.token
                  )
              }) ?? true,
              listenerRunGate.admits(generation: state.listenerGeneration),
              peerStates[state.generation] === state,
              generationGate.admitsPostAuthenticationTraffic(
                  generation: state.generation
              ),
              state.lifetime.menuReadinessPublished,
              state.postAuthenticationFence.admitsTraffic,
              profile.admitsMenuPresentation,
              payload.count > 0,
              payload.count <= Int(
                  MCLocalXPCMaximumInteractiveInputPayloadBytes
              ),
              authorizesAgentPresentationMethod(.applyInteractiveInput),
              let transaction = state.interactiveInputGate.begin(
                  generation: state.generation,
                  permitted: true
              ) else {
            continuation.resume(throwing:
                MacLocalXPCInteractiveRoleDataErrorV1.unavailable
            )
            return
        }
        let pending = PendingInteractiveInput(
            requestID: requestID,
            transaction: transaction,
            continuation: continuation
        )
        state.pendingInteractiveInput = pending
        let result = payload.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress
            else { return MCLocalXPCResultConstructionFailed }
            return MCLocalXPCSessionSendInteractiveInput(
                state.peer,
                bytes,
                payload.count
            ) { [weak self, weak state] malformed in
                self?.queue.async { [weak self, weak state] in
                    guard let self, let state else { return }
                    self.handleInteractiveInputReply(
                        state: state,
                        requestID: requestID,
                        transaction: transaction,
                        malformedOrTransportError: malformed
                    )
                }
            }
        }
        guard result == MCLocalXPCResultOK else {
            _ = state.interactiveInputGate.finish(transaction)
            state.pendingInteractiveInput = nil
            continuation.resume(throwing:
                MacLocalXPCInteractiveRoleDataErrorV1
                    .malformedOrTransportError
            )
            cancelAuthenticatedPeer(
                state,
                presentationError: .transportFailure
            )
            return
        }
        let deadline = DispatchWorkItem { [weak self, weak state] in
            guard let self, let state else { return }
            self.expireInteractiveInput(
                state: state,
                requestID: requestID,
                transaction: transaction
            )
        }
        pending.deadline = deadline
        queue.asyncAfter(
            deadline: .now() + .seconds(
                Self.interactiveInputReplyTimeoutSeconds
            ),
            execute: deadline
        )
    }

    private func handleInteractiveInputReply(
        state: PeerState,
        requestID: UUID,
        transaction:
            MacLocalXPCInteractiveRoleDataTransactionGateV1.Active,
        malformedOrTransportError: Bool
    ) {
        guard admitsInteractiveInputCompletion(
                state: state,
                transaction: transaction
              ),
              let pending = state.pendingInteractiveInput,
              pending.requestID == requestID,
              pending.transaction == transaction,
              state.interactiveInputGate.finish(transaction) else { return }
        state.pendingInteractiveInput = nil
        pending.deadline?.cancel()
        pending.deadline = nil
        guard !malformedOrTransportError else {
            pending.continuation.resume(throwing:
                MacLocalXPCInteractiveRoleDataErrorV1
                    .malformedOrTransportError
            )
            cancelAuthenticatedPeer(
                state,
                presentationError: .transportFailure
            )
            return
        }
        pending.continuation.resume()
    }

    private func expireInteractiveInput(
        state: PeerState,
        requestID: UUID,
        transaction:
            MacLocalXPCInteractiveRoleDataTransactionGateV1.Active
    ) {
        guard admitsInteractiveInputCompletion(
                state: state,
                transaction: transaction
              ),
              let pending = state.pendingInteractiveInput,
              pending.requestID == requestID,
              state.interactiveInputGate.finish(transaction) else { return }
        state.pendingInteractiveInput = nil
        pending.deadline = nil
        pending.continuation.resume(throwing:
            MacLocalXPCInteractiveRoleDataErrorV1.replyTimedOut
        )
        cancelAuthenticatedPeer(state, presentationError: .replyTimedOut)
    }

    private func cancelInteractiveInput(requestID: UUID) {
        guard let state = currentPeerState,
              let pending = state.pendingInteractiveInput,
              pending.requestID == requestID,
              state.interactiveInputGate.finish(pending.transaction) else {
            return
        }
        state.pendingInteractiveInput = nil
        pending.deadline?.cancel()
        pending.deadline = nil
        pending.continuation.resume(throwing:
            MacLocalXPCInteractiveRoleDataErrorV1.cancelledAfterSend
        )
        cancelAuthenticatedPeer(
            state,
            presentationError: .cancelledAfterSend
        )
    }

    private func admitsInteractiveInputCompletion(
        state: PeerState,
        transaction:
            MacLocalXPCInteractiveRoleDataTransactionGateV1.Active
    ) -> Bool {
        listenerRunGate.admits(generation: state.listenerGeneration)
            && peerStates[state.generation] === state
            && currentPeerState === state
            && generationGate.admitsPostAuthenticationTraffic(
                generation: state.generation
            )
            && state.lifetime.menuReadinessPublished
            && state.postAuthenticationFence.admitsTraffic
            && state.interactiveInputGate.admits(transaction)
    }

    public func prepareInitialInteractiveDesktop(
        _ command: LocalInteractiveInitialDesktopPreparationCommandV1
    ) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
        try await prepareInitialInteractiveDesktop(
            command,
            endpointBinding: nil
        )
    }

    package func prepareInitialInteractiveDesktop(
        generation: UInt64,
        endpointToken: UUID,
        command: LocalInteractiveInitialDesktopPreparationCommandV1
    ) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
        try await prepareInitialInteractiveDesktop(
            command,
            endpointBinding: .init(
                generation: generation,
                endpointToken: endpointToken
            )
        )
    }

    private func prepareInitialInteractiveDesktop(
        _ command: LocalInteractiveInitialDesktopPreparationCommandV1,
        endpointBinding: MacLocalXPCInteractiveLeaseEndpointBindingV1?
    ) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
        let payload: Data
        do {
            payload = try LocalInteractiveLeaseWireCodecV1
                .encodeInitialDesktopCommand(command)
        } catch {
            throw MacLocalXPCInteractiveLeaseErrorV1
                .malformedOrTransportError
        }
        let reply = try await sendInteractiveLeaseCommand(
            command: .prepareInitialDesktop(command),
            payload: payload,
            endpointBinding: endpointBinding
        )
        do {
            guard let reply else {
                throw MacLocalXPCInteractiveLeaseErrorV1
                    .malformedOrTransportError
            }
            let receipt = try LocalInteractiveLeaseWireCodecV1
                .decodeInitialDesktopReceipt(reply)
            try receipt.validate(against: command)
            return receipt
        } catch {
            cancelPeerAfterMalformedInteractiveReply(
                endpointBinding: endpointBinding
            )
            throw MacLocalXPCInteractiveLeaseErrorV1
                .malformedOrTransportError
        }
    }

    public func installInteractiveLease(
        _ command: InteractiveRuntimeInstallCommandV0
    ) async throws -> InteractiveRuntimeInstallReceiptV0 {
        try await installInteractiveLease(command, endpointBinding: nil)
    }

    package func installInteractiveLease(
        generation: UInt64,
        endpointToken: UUID,
        command: InteractiveRuntimeInstallCommandV0
    ) async throws -> InteractiveRuntimeInstallReceiptV0 {
        try await installInteractiveLease(
            command,
            endpointBinding: .init(
                generation: generation,
                endpointToken: endpointToken
            )
        )
    }

    private func installInteractiveLease(
        _ command: InteractiveRuntimeInstallCommandV0,
        endpointBinding: MacLocalXPCInteractiveLeaseEndpointBindingV1?
    ) async throws -> InteractiveRuntimeInstallReceiptV0 {
        let payload: Data
        do {
            payload = try LocalInteractiveLeaseWireCodecV1
                .encodeInstallCommand(command)
        } catch {
            throw MacLocalXPCInteractiveLeaseErrorV1
                .malformedOrTransportError
        }
        let reply = try await sendInteractiveLeaseCommand(
            command: .install(command),
            payload: payload,
            endpointBinding: endpointBinding
        )
        do {
            guard let reply else {
                throw MacLocalXPCInteractiveLeaseErrorV1
                    .malformedOrTransportError
            }
            let receipt = try LocalInteractiveLeaseWireCodecV1
                .decodeInstallReceipt(reply)
            try receipt.validate(against: command)
            return receipt
        } catch {
            cancelPeerAfterMalformedInteractiveReply(
                endpointBinding: endpointBinding
            )
            throw MacLocalXPCInteractiveLeaseErrorV1
                .malformedOrTransportError
        }
    }

    public func renewInteractiveLease(
        _ renewal: InteractiveRuntimeLeaseRenewalV0
    ) async throws {
        try await renewInteractiveLease(renewal, endpointBinding: nil)
    }

    package func renewInteractiveLease(
        generation: UInt64,
        endpointToken: UUID,
        renewal: InteractiveRuntimeLeaseRenewalV0
    ) async throws {
        try await renewInteractiveLease(
            renewal,
            endpointBinding: .init(
                generation: generation,
                endpointToken: endpointToken
            )
        )
    }

    private func renewInteractiveLease(
        _ renewal: InteractiveRuntimeLeaseRenewalV0,
        endpointBinding: MacLocalXPCInteractiveLeaseEndpointBindingV1?
    ) async throws {
        let payload: Data
        do {
            payload = try LocalInteractiveLeaseWireCodecV1
                .encodeRenewal(renewal)
        } catch {
            throw MacLocalXPCInteractiveLeaseErrorV1
                .malformedOrTransportError
        }
        let reply = try await sendInteractiveLeaseCommand(
            command: .renew(renewal),
            payload: payload,
            endpointBinding: endpointBinding
        )
        guard reply == nil else {
            cancelPeerAfterMalformedInteractiveReply(
                endpointBinding: endpointBinding
            )
            throw MacLocalXPCInteractiveLeaseErrorV1
                .malformedOrTransportError
        }
    }

    public func revokeInteractiveLease(
        _ command: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0 {
        try await revokeInteractiveLease(command, endpointBinding: nil)
    }

    package func revokeInteractiveLease(
        generation: UInt64,
        endpointToken: UUID,
        command: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0 {
        try await revokeInteractiveLease(
            command,
            endpointBinding: .init(
                generation: generation,
                endpointToken: endpointToken
            )
        )
    }

    private func revokeInteractiveLease(
        _ command: InteractiveRuntimeRevokeCommandV0,
        endpointBinding: MacLocalXPCInteractiveLeaseEndpointBindingV1?
    ) async throws -> InteractiveRuntimeRevokedReceiptV0 {
        let payload: Data
        do {
            payload = try LocalInteractiveLeaseWireCodecV1
                .encodeRevokeCommand(command)
        } catch {
            throw MacLocalXPCInteractiveLeaseErrorV1
                .malformedOrTransportError
        }
        let reply = try await sendInteractiveLeaseCommand(
            command: .revoke(command),
            payload: payload,
            endpointBinding: endpointBinding
        )
        do {
            guard let reply else {
                throw MacLocalXPCInteractiveLeaseErrorV1
                    .malformedOrTransportError
            }
            let receipt = try LocalInteractiveLeaseWireCodecV1
                .decodeRevokedReceipt(reply)
            try receipt.validate(against: command)
            return receipt
        } catch {
            cancelPeerAfterMalformedInteractiveReply(
                endpointBinding: endpointBinding
            )
            throw MacLocalXPCInteractiveLeaseErrorV1
                .malformedOrTransportError
        }
    }

    public func interactiveSurfaceTargets(
        _ command: LocalInteractiveSurfaceTargetsCommandV1
    ) async throws -> LocalInteractiveSurfaceTargetsReceiptV1 {
        try await interactiveSurfaceTargets(command, endpointBinding: nil)
    }

    package func interactiveSurfaceTargets(
        generation: UInt64,
        endpointToken: UUID,
        command: LocalInteractiveSurfaceTargetsCommandV1
    ) async throws -> LocalInteractiveSurfaceTargetsReceiptV1 {
        try await interactiveSurfaceTargets(
            command,
            endpointBinding: .init(
                generation: generation,
                endpointToken: endpointToken
            )
        )
    }

    private func interactiveSurfaceTargets(
        _ command: LocalInteractiveSurfaceTargetsCommandV1,
        endpointBinding: MacLocalXPCInteractiveLeaseEndpointBindingV1?
    ) async throws -> LocalInteractiveSurfaceTargetsReceiptV1 {
        let payload = try encodeInteractiveLeasePayload {
            try LocalInteractiveLeaseWireCodecV1
                .encodeSurfaceTargetsCommand(command)
        }
        let reply = try await sendInteractiveLeaseCommand(
            command: .surfaceTargets(command),
            payload: payload,
            endpointBinding: endpointBinding
        )
        do {
            guard let reply else { throw MacLocalXPCInteractiveLeaseErrorV1.malformedOrTransportError }
            let receipt = try LocalInteractiveLeaseWireCodecV1
                .decodeSurfaceTargetsReceipt(reply)
            try receipt.validate(against: command)
            return receipt
        } catch {
            cancelPeerAfterMalformedInteractiveReply(
                endpointBinding: endpointBinding
            )
            throw MacLocalXPCInteractiveLeaseErrorV1
                .malformedOrTransportError
        }
    }

    public func resolveInteractiveSurface(
        _ command: LocalInteractiveSurfaceResolveCommandV1
    ) async throws -> LocalInteractiveSurfaceResolvedReceiptV1 {
        try await resolveInteractiveSurface(command, endpointBinding: nil)
    }

    package func resolveInteractiveSurface(
        generation: UInt64,
        endpointToken: UUID,
        command: LocalInteractiveSurfaceResolveCommandV1
    ) async throws -> LocalInteractiveSurfaceResolvedReceiptV1 {
        try await resolveInteractiveSurface(
            command,
            endpointBinding: .init(
                generation: generation,
                endpointToken: endpointToken
            )
        )
    }

    private func resolveInteractiveSurface(
        _ command: LocalInteractiveSurfaceResolveCommandV1,
        endpointBinding: MacLocalXPCInteractiveLeaseEndpointBindingV1?
    ) async throws -> LocalInteractiveSurfaceResolvedReceiptV1 {
        let payload = try encodeInteractiveLeasePayload {
            try LocalInteractiveLeaseWireCodecV1
                .encodeSurfaceResolveCommand(command)
        }
        let reply = try await sendInteractiveLeaseCommand(
            command: .surfaceResolve(command),
            payload: payload,
            endpointBinding: endpointBinding
        )
        do {
            guard let reply else { throw MacLocalXPCInteractiveLeaseErrorV1.malformedOrTransportError }
            let receipt = try LocalInteractiveLeaseWireCodecV1
                .decodeSurfaceResolvedReceipt(reply)
            try receipt.validate(against: command)
            return receipt
        } catch {
            cancelPeerAfterMalformedInteractiveReply(
                endpointBinding: endpointBinding
            )
            throw MacLocalXPCInteractiveLeaseErrorV1
                .malformedOrTransportError
        }
    }

    public func prepareInteractiveSurfaceTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0 {
        try await prepareInteractiveSurfaceTransition(
            command,
            endpointBinding: nil
        )
    }

    package func prepareInteractiveSurfaceTransition(
        generation: UInt64,
        endpointToken: UUID,
        command: InteractiveRuntimeSurfaceTransitionCommandV0
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0 {
        try await prepareInteractiveSurfaceTransition(
            command,
            endpointBinding: .init(
                generation: generation,
                endpointToken: endpointToken
            )
        )
    }

    private func prepareInteractiveSurfaceTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0,
        endpointBinding: MacLocalXPCInteractiveLeaseEndpointBindingV1?
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0 {
        let payload = try encodeInteractiveLeasePayload {
            try LocalInteractiveLeaseWireCodecV1
                .encodeSurfaceTransitionCommand(command)
        }
        let reply = try await sendInteractiveLeaseCommand(
            command: .surfaceTransition(command),
            payload: payload,
            endpointBinding: endpointBinding
        )
        do {
            guard let reply else { throw MacLocalXPCInteractiveLeaseErrorV1.malformedOrTransportError }
            let receipt = try LocalInteractiveLeaseWireCodecV1
                .decodeSurfaceTransitionReceipt(reply)
            try receipt.validate(against: command)
            return receipt
        } catch {
            cancelPeerAfterMalformedInteractiveReply(
                endpointBinding: endpointBinding
            )
            throw MacLocalXPCInteractiveLeaseErrorV1
                .malformedOrTransportError
        }
    }

    public func acknowledgeInteractiveSurface(
        _ command: InteractiveRuntimeSurfaceAcknowledgementCommandV0
    ) async throws -> InteractiveRuntimeSurfaceAcknowledgementReceiptV0 {
        try await acknowledgeInteractiveSurface(command, endpointBinding: nil)
    }

    package func acknowledgeInteractiveSurface(
        generation: UInt64,
        endpointToken: UUID,
        command: InteractiveRuntimeSurfaceAcknowledgementCommandV0
    ) async throws -> InteractiveRuntimeSurfaceAcknowledgementReceiptV0 {
        try await acknowledgeInteractiveSurface(
            command,
            endpointBinding: .init(
                generation: generation,
                endpointToken: endpointToken
            )
        )
    }

    private func acknowledgeInteractiveSurface(
        _ command: InteractiveRuntimeSurfaceAcknowledgementCommandV0,
        endpointBinding: MacLocalXPCInteractiveLeaseEndpointBindingV1?
    ) async throws -> InteractiveRuntimeSurfaceAcknowledgementReceiptV0 {
        let payload = try encodeInteractiveLeasePayload {
            try LocalInteractiveLeaseWireCodecV1
                .encodeSurfaceAcknowledgementCommand(command)
        }
        let reply = try await sendInteractiveLeaseCommand(
            command: .surfaceAcknowledgement(command),
            payload: payload,
            endpointBinding: endpointBinding
        )
        do {
            guard let reply else { throw MacLocalXPCInteractiveLeaseErrorV1.malformedOrTransportError }
            let receipt = try LocalInteractiveLeaseWireCodecV1
                .decodeSurfaceAcknowledgementReceipt(reply)
            try receipt.validate(against: command)
            return receipt
        } catch {
            cancelPeerAfterMalformedInteractiveReply(
                endpointBinding: endpointBinding
            )
            throw MacLocalXPCInteractiveLeaseErrorV1
                .malformedOrTransportError
        }
    }

    public func terminateInteractiveSurfaceFailure(
        _ command: LocalInteractiveSurfaceFailureCommandV1
    ) async throws -> LocalInteractiveSurfaceFailureReceiptV1 {
        try await terminateInteractiveSurfaceFailure(
            command,
            endpointBinding: nil
        )
    }

    package func terminateInteractiveSurfaceFailure(
        generation: UInt64,
        endpointToken: UUID,
        command: LocalInteractiveSurfaceFailureCommandV1
    ) async throws -> LocalInteractiveSurfaceFailureReceiptV1 {
        try await terminateInteractiveSurfaceFailure(
            command,
            endpointBinding: .init(
                generation: generation,
                endpointToken: endpointToken
            )
        )
    }

    private func terminateInteractiveSurfaceFailure(
        _ command: LocalInteractiveSurfaceFailureCommandV1,
        endpointBinding: MacLocalXPCInteractiveLeaseEndpointBindingV1?
    ) async throws -> LocalInteractiveSurfaceFailureReceiptV1 {
        let payload = try encodeInteractiveLeasePayload {
            try LocalInteractiveLeaseWireCodecV1
                .encodeSurfaceFailureCommand(command)
        }
        let reply = try await sendInteractiveLeaseCommand(
            command: .surfaceFailure(command),
            payload: payload,
            endpointBinding: endpointBinding
        )
        do {
            guard let reply else { throw MacLocalXPCInteractiveLeaseErrorV1.malformedOrTransportError }
            let receipt = try LocalInteractiveLeaseWireCodecV1
                .decodeSurfaceFailureReceipt(reply)
            try receipt.validate(against: command)
            return receipt
        } catch {
            cancelPeerAfterMalformedInteractiveReply(
                endpointBinding: endpointBinding
            )
            throw MacLocalXPCInteractiveLeaseErrorV1
                .malformedOrTransportError
        }
    }

    public func interactiveFocusSnapshot(
        _ command: LocalInteractiveFocusSnapshotCommandV1
    ) async throws -> LocalInteractiveFocusSnapshotReceiptV1 {
        try await interactiveFocusSnapshot(command, endpointBinding: nil)
    }

    package func interactiveFocusSnapshot(
        generation: UInt64,
        endpointToken: UUID,
        command: LocalInteractiveFocusSnapshotCommandV1
    ) async throws -> LocalInteractiveFocusSnapshotReceiptV1 {
        try await interactiveFocusSnapshot(
            command,
            endpointBinding: .init(
                generation: generation,
                endpointToken: endpointToken
            )
        )
    }

    private func interactiveFocusSnapshot(
        _ command: LocalInteractiveFocusSnapshotCommandV1,
        endpointBinding: MacLocalXPCInteractiveLeaseEndpointBindingV1?
    ) async throws -> LocalInteractiveFocusSnapshotReceiptV1 {
        let payload = try encodeInteractiveLeasePayload {
            try LocalInteractiveLeaseWireCodecV1
                .encodeFocusSnapshotCommand(command)
        }
        let reply = try await sendInteractiveLeaseCommand(
            command: .focusSnapshot(command),
            payload: payload,
            endpointBinding: endpointBinding
        )
        do {
            guard let reply else {
                throw MacLocalXPCInteractiveLeaseErrorV1
                    .malformedOrTransportError
            }
            let receipt = try LocalInteractiveLeaseWireCodecV1
                .decodeFocusSnapshotReceipt(reply)
            try receipt.validate(against: command)
            return receipt
        } catch {
            cancelPeerAfterMalformedInteractiveReply(
                endpointBinding: endpointBinding
            )
            throw MacLocalXPCInteractiveLeaseErrorV1
                .malformedOrTransportError
        }
    }

    public func interactiveDisplayCatalog(
        _ command: LocalInteractiveDisplayCatalogCommandV1
    ) async throws -> LocalInteractiveDisplayCatalogReceiptV1 {
        try await interactiveDisplayCatalog(command, endpointBinding: nil)
    }

    package func interactiveDisplayCatalog(
        generation: UInt64,
        endpointToken: UUID,
        command: LocalInteractiveDisplayCatalogCommandV1
    ) async throws -> LocalInteractiveDisplayCatalogReceiptV1 {
        try await interactiveDisplayCatalog(
            command,
            endpointBinding: .init(
                generation: generation,
                endpointToken: endpointToken
            )
        )
    }

    private func interactiveDisplayCatalog(
        _ command: LocalInteractiveDisplayCatalogCommandV1,
        endpointBinding: MacLocalXPCInteractiveLeaseEndpointBindingV1?
    ) async throws -> LocalInteractiveDisplayCatalogReceiptV1 {
        let payload = try encodeInteractiveLeasePayload {
            try LocalInteractiveLeaseWireCodecV1
                .encodeDisplayCatalogCommand(command)
        }
        let reply = try await sendInteractiveLeaseCommand(
            command: .displayCatalog(command),
            payload: payload,
            endpointBinding: endpointBinding
        )
        do {
            guard let reply else {
                throw MacLocalXPCInteractiveLeaseErrorV1
                    .malformedOrTransportError
            }
            let receipt = try LocalInteractiveLeaseWireCodecV1
                .decodeDisplayCatalogReceipt(reply)
            try receipt.validate(against: command)
            return receipt
        } catch {
            cancelPeerAfterMalformedInteractiveReply(
                endpointBinding: endpointBinding
            )
            throw MacLocalXPCInteractiveLeaseErrorV1
                .malformedOrTransportError
        }
    }

    public func selectInteractiveDisplay(
        _ command: LocalInteractiveDisplaySelectCommandV1
    ) async throws -> LocalInteractiveDisplaySelectedReceiptV1 {
        try await selectInteractiveDisplay(command, endpointBinding: nil)
    }

    package func selectInteractiveDisplay(
        generation: UInt64,
        endpointToken: UUID,
        command: LocalInteractiveDisplaySelectCommandV1
    ) async throws -> LocalInteractiveDisplaySelectedReceiptV1 {
        try await selectInteractiveDisplay(
            command,
            endpointBinding: .init(
                generation: generation,
                endpointToken: endpointToken
            )
        )
    }

    private func selectInteractiveDisplay(
        _ command: LocalInteractiveDisplaySelectCommandV1,
        endpointBinding: MacLocalXPCInteractiveLeaseEndpointBindingV1?
    ) async throws -> LocalInteractiveDisplaySelectedReceiptV1 {
        let payload = try encodeInteractiveLeasePayload {
            try LocalInteractiveLeaseWireCodecV1
                .encodeDisplaySelectCommand(command)
        }
        let reply = try await sendInteractiveLeaseCommand(
            command: .displaySelect(command),
            payload: payload,
            endpointBinding: endpointBinding
        )
        do {
            guard let reply else {
                throw MacLocalXPCInteractiveLeaseErrorV1
                    .malformedOrTransportError
            }
            let receipt = try LocalInteractiveLeaseWireCodecV1
                .decodeDisplaySelectedReceipt(reply)
            try receipt.validate(against: command)
            return receipt
        } catch {
            cancelPeerAfterMalformedInteractiveReply(
                endpointBinding: endpointBinding
            )
            throw MacLocalXPCInteractiveLeaseErrorV1
                .malformedOrTransportError
        }
    }

    public func nativeBackend(_ command: LocalInteractiveNativeBackendCommandV1) async throws -> LocalInteractiveNativeBackendReceiptV1 {
        try await nativeBackend(command, endpointBinding: nil)
    }
    package func nativeBackend(generation: UInt64, endpointToken: UUID, command: LocalInteractiveNativeBackendCommandV1) async throws -> LocalInteractiveNativeBackendReceiptV1 {
        try await nativeBackend(command, endpointBinding: .init(generation: generation, endpointToken: endpointToken))
    }
    private func nativeBackend(_ command: LocalInteractiveNativeBackendCommandV1,
        endpointBinding: MacLocalXPCInteractiveLeaseEndpointBindingV1?) async throws -> LocalInteractiveNativeBackendReceiptV1 {
        let payload = try encodeInteractiveLeasePayload { try LocalInteractiveLeaseWireCodecV1.encodeNativeBackendCommand(command) }
        let reply = try await sendInteractiveLeaseCommand(command: .nativeBackend(command), payload: payload, endpointBinding: endpointBinding)
        do {
            guard let reply else { throw MacLocalXPCInteractiveLeaseErrorV1.malformedOrTransportError }
            let receipt = try LocalInteractiveLeaseWireCodecV1.decodeNativeBackendReceipt(reply)
            try receipt.validate(against: command)
            return receipt
        } catch {
            cancelPeerAfterMalformedInteractiveReply(endpointBinding: endpointBinding)
            throw MacLocalXPCInteractiveLeaseErrorV1.malformedOrTransportError
        }
    }

    public func nativeRuntimeSnapshot(_ command: LocalInteractiveNativeSnapshotCommandV1) async throws -> LocalInteractiveNativeSnapshotReceiptV1 {
        try await nativeRuntimeSnapshot(command, endpointBinding: nil)
    }
    package func nativeRuntimeSnapshot(generation: UInt64, endpointToken: UUID, command: LocalInteractiveNativeSnapshotCommandV1) async throws -> LocalInteractiveNativeSnapshotReceiptV1 {
        try await nativeRuntimeSnapshot(command, endpointBinding: .init(generation: generation, endpointToken: endpointToken))
    }
    private func nativeRuntimeSnapshot(_ command: LocalInteractiveNativeSnapshotCommandV1,
        endpointBinding: MacLocalXPCInteractiveLeaseEndpointBindingV1?) async throws -> LocalInteractiveNativeSnapshotReceiptV1 {
        let payload = try encodeInteractiveLeasePayload { try LocalInteractiveLeaseWireCodecV1.encodeNativeSnapshotCommand(command) }
        let reply = try await sendInteractiveLeaseCommand(command: .nativeSnapshot(command), payload: payload, endpointBinding: endpointBinding)
        do {
            guard let reply else { throw MacLocalXPCInteractiveLeaseErrorV1.malformedOrTransportError }
            let receipt = try LocalInteractiveLeaseWireCodecV1.decodeNativeSnapshotReceipt(reply)
            try receipt.validate(against: command)
            return receipt
        } catch {
            cancelPeerAfterMalformedInteractiveReply(endpointBinding: endpointBinding)
            throw MacLocalXPCInteractiveLeaseErrorV1.malformedOrTransportError
        }
    }

    public func makeWebRTCOffer(
        _ command: LocalInteractiveWebRTCOfferCommandV1
    ) async throws -> LocalInteractiveWebRTCOfferReceiptV1 {
        try await makeWebRTCOffer(command, endpointBinding: nil)
    }

    package func makeWebRTCOffer(
        generation: UInt64,
        endpointToken: UUID,
        command: LocalInteractiveWebRTCOfferCommandV1
    ) async throws -> LocalInteractiveWebRTCOfferReceiptV1 {
        try await makeWebRTCOffer(command, endpointBinding: .init(
            generation: generation, endpointToken: endpointToken
        ))
    }

    private func makeWebRTCOffer(
        _ command: LocalInteractiveWebRTCOfferCommandV1,
        endpointBinding: MacLocalXPCInteractiveLeaseEndpointBindingV1?
    ) async throws -> LocalInteractiveWebRTCOfferReceiptV1 {
        let payload = try encodeInteractiveLeasePayload {
            try LocalInteractiveLeaseWireCodecV1
                .encodeWebRTCOfferCommand(command)
        }
        let reply = try await sendInteractiveLeaseCommand(
            command: .webRTCOffer(command), payload: payload,
            endpointBinding: endpointBinding
        )
        do {
            guard let reply else {
                throw MacLocalXPCInteractiveLeaseErrorV1
                    .malformedOrTransportError
            }
            let receipt = try LocalInteractiveLeaseWireCodecV1
                .decodeWebRTCOfferReceipt(reply)
            try receipt.validate(against: command)
            return receipt
        } catch {
            cancelPeerAfterMalformedInteractiveReply(
                endpointBinding: endpointBinding
            )
            throw MacLocalXPCInteractiveLeaseErrorV1
                .malformedOrTransportError
        }
    }

    public func acceptWebRTCAnswer(
        _ command: LocalInteractiveWebRTCAnswerCommandV1
    ) async throws {
        try await acceptWebRTCAnswer(command, endpointBinding: nil)
    }

    package func acceptWebRTCAnswer(
        generation: UInt64,
        endpointToken: UUID,
        command: LocalInteractiveWebRTCAnswerCommandV1
    ) async throws {
        try await acceptWebRTCAnswer(command, endpointBinding: .init(
            generation: generation, endpointToken: endpointToken
        ))
    }

    private func acceptWebRTCAnswer(
        _ command: LocalInteractiveWebRTCAnswerCommandV1,
        endpointBinding: MacLocalXPCInteractiveLeaseEndpointBindingV1?
    ) async throws {
        let payload = try encodeInteractiveLeasePayload {
            try LocalInteractiveLeaseWireCodecV1
                .encodeWebRTCAnswerCommand(command)
        }
        let reply = try await sendInteractiveLeaseCommand(
            command: .webRTCAnswer(command), payload: payload,
            endpointBinding: endpointBinding
        )
        guard reply == nil else {
            cancelPeerAfterMalformedInteractiveReply(
                endpointBinding: endpointBinding
            )
            throw MacLocalXPCInteractiveLeaseErrorV1
                .malformedOrTransportError
        }
    }

    public func closeWebRTC(
        _ command: LocalInteractiveWebRTCCloseCommandV1
    ) async throws {
        try await closeWebRTC(command, endpointBinding: nil)
    }

    package func closeWebRTC(
        generation: UInt64,
        endpointToken: UUID,
        command: LocalInteractiveWebRTCCloseCommandV1
    ) async throws {
        try await closeWebRTC(command, endpointBinding: .init(
            generation: generation, endpointToken: endpointToken
        ))
    }

    private func closeWebRTC(
        _ command: LocalInteractiveWebRTCCloseCommandV1,
        endpointBinding: MacLocalXPCInteractiveLeaseEndpointBindingV1?
    ) async throws {
        let payload = try encodeInteractiveLeasePayload {
            try LocalInteractiveLeaseWireCodecV1
                .encodeWebRTCCloseCommand(command)
        }
        let reply = try await sendInteractiveLeaseCommand(
            command: .webRTCClose(command), payload: payload,
            endpointBinding: endpointBinding
        )
        guard reply == nil else {
            cancelPeerAfterMalformedInteractiveReply(
                endpointBinding: endpointBinding
            )
            throw MacLocalXPCInteractiveLeaseErrorV1
                .malformedOrTransportError
        }
    }

    private func encodeInteractiveLeasePayload(
        _ body: () throws -> Data
    ) throws -> Data {
        do { return try body() }
        catch {
            throw MacLocalXPCInteractiveLeaseErrorV1
                .malformedOrTransportError
        }
    }

    private func sendInteractiveLeaseCommand(
        command: InteractiveLeaseCommand,
        payload: Data,
        endpointBinding: MacLocalXPCInteractiveLeaseEndpointBindingV1?
    ) async throws -> Data? {
        let requestID = UUID()
        let marker = InteractiveLeaseCancellationMarker()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [weak self] in
                    guard let self else {
                        continuation.resume(
                            throwing: MacLocalXPCInteractiveLeaseErrorV1
                                .unavailable
                        )
                        return
                    }
                    self.admitInteractiveLeaseCommand(
                        requestID: requestID,
                        command: command,
                        payload: payload,
                        endpointBinding: endpointBinding,
                        cancellationMarker: marker,
                        continuation: continuation
                    )
                }
            }
        } onCancel: { [weak self] in
            marker.markCancelled()
            self?.queue.async { [weak self] in
                self?.cancelInteractiveLeaseCommand(requestID: requestID)
            }
        }
    }

    private func admitInteractiveLeaseCommand(
        requestID: UUID,
        command: InteractiveLeaseCommand,
        payload: Data,
        endpointBinding: MacLocalXPCInteractiveLeaseEndpointBindingV1?,
        cancellationMarker: InteractiveLeaseCancellationMarker,
        continuation: CheckedContinuation<Data?, any Error>
    ) {
        guard !cancellationMarker.isCancelled() else {
            continuation.resume(throwing: CancellationError())
            return
        }
        guard let state = currentPeerState,
              endpointBinding.map({
                  $0.admits(
                      generation: state.generation,
                      issuedEndpointToken:
                          state.presentationIssuanceGate.token
                  )
              }) ?? true,
              listenerRunGate.admits(generation: state.listenerGeneration),
              peerStates[state.generation] === state,
              generationGate.admitsPostAuthenticationTraffic(
                generation: state.generation
              ),
              state.lifetime.menuReadinessPublished,
              state.postAuthenticationFence.admitsTraffic,
              profile.admitsInteractiveLeaseTransport,
              payload.count > 0,
              payload.count <=
                LocalInteractiveLeaseWireCodecV1.maximumEncodedBytes,
              authorizesAgentPresentationMethod(
                command.authorizationMethod
              ),
              let transaction = state.interactiveLeaseGate.begin(
                generation: state.generation,
                kind: command.kind,
                permitted: true
              ) else {
            continuation.resume(
                throwing: MacLocalXPCInteractiveLeaseErrorV1.unavailable
            )
            return
        }

        let pending = PendingInteractiveLeaseCommand(
            requestID: requestID,
            transaction: transaction,
            command: command,
            continuation: continuation
        )
        state.pendingInteractiveLeaseCommand = pending
        let cKind = cInteractiveLeaseCommandKind(command.kind)
        let sendResult = payload.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress
            else { return MCLocalXPCResultConstructionFailed }
            return MCLocalXPCSessionSendInteractiveLeaseCommand(
                state.peer,
                cKind,
                bytes,
                payload.count
            ) { [weak self, weak state] bytes, length, malformed in
                let copiedPayload = bytes.map {
                    Data(bytes: $0, count: length)
                }
                self?.queue.async { [weak self, weak state] in
                    guard let self, let state else { return }
                    self.handleInteractiveLeaseReply(
                        state: state,
                        requestID: requestID,
                        transaction: transaction,
                        payload: copiedPayload,
                        malformedOrTransportError: malformed
                    )
                }
            }
        }
        guard sendResult == MCLocalXPCResultOK else {
            _ = state.interactiveLeaseGate.finish(transaction)
            state.pendingInteractiveLeaseCommand = nil
            continuation.resume(
                throwing: MacLocalXPCInteractiveLeaseErrorV1
                    .malformedOrTransportError
            )
            cancelAuthenticatedPeer(
                state,
                presentationError: .transportFailure
            )
            return
        }

        let deadline = DispatchWorkItem { [weak self, weak state] in
            guard let self, let state else { return }
            self.expireInteractiveLeaseCommand(
                state: state,
                requestID: requestID,
                transaction: transaction
            )
        }
        pending.deadline = deadline
        queue.asyncAfter(
            deadline: .now()
                + .seconds(Self.interactiveLeaseReplyTimeoutSeconds),
            execute: deadline
        )
    }

    private func handleInteractiveLeaseReply(
        state: PeerState,
        requestID: UUID,
        transaction: MacLocalXPCInteractiveLeaseTransactionGateV1.Active,
        payload: Data?,
        malformedOrTransportError: Bool
    ) {
        guard admitsInteractiveLeaseCompletion(
                state: state,
                transaction: transaction
              ),
              let pending = state.pendingInteractiveLeaseCommand,
              pending.requestID == requestID,
              pending.transaction == transaction,
              state.interactiveLeaseGate.finish(transaction) else { return }
        state.pendingInteractiveLeaseCommand = nil
        pending.deadline?.cancel()
        pending.deadline = nil

        let validPayloadShape: Bool = switch transaction.kind {
        case .surfaceTargets:
            payload.map {
                !$0.isEmpty
                    && $0.count <= LocalInteractiveLeaseWireCodecV1
                        .maximumSurfaceTargetsReceiptBytes
            } ?? false
        case .prepareInitialDesktop, .install, .revoke,
                .surfaceResolve, .surfaceTransition,
                .surfaceAcknowledgement, .surfaceFailure, .focusSnapshot,
                .displayCatalog, .displaySelect, .nativeBackend, .nativeSnapshot, .webRTCOffer:
            payload.map {
                !$0.isEmpty
                    && $0.count <= LocalInteractiveLeaseWireCodecV1
                        .maximumEncodedBytes
            } ?? false
        case .renew, .webRTCAnswer, .webRTCClose:
            payload == nil
        }
        guard !malformedOrTransportError, validPayloadShape else {
            macLocalXPCInteractiveLeaseLoggerV1.error(
                "agent rejected interactive reply kind=\(String(describing: transaction.kind), privacy: .public) malformed=\(malformedOrTransportError, privacy: .public) payloadBytes=\(payload?.count ?? -1, privacy: .public)"
            )
            pending.continuation.resume(
                throwing: MacLocalXPCInteractiveLeaseErrorV1
                    .malformedOrTransportError
            )
            cancelAuthenticatedPeer(
                state,
                presentationError: .transportFailure
            )
            return
        }
        macLocalXPCInteractiveLeaseLoggerV1.notice(
            "agent accepted interactive reply kind=\(String(describing: transaction.kind), privacy: .public) operation=\(transaction.operation, privacy: .public)"
        )
        pending.continuation.resume(returning: payload)
    }

    private func expireInteractiveLeaseCommand(
        state: PeerState,
        requestID: UUID,
        transaction: MacLocalXPCInteractiveLeaseTransactionGateV1.Active
    ) {
        guard admitsInteractiveLeaseCompletion(
                state: state,
                transaction: transaction
              ),
              let pending = state.pendingInteractiveLeaseCommand,
              pending.requestID == requestID,
              state.interactiveLeaseGate.finish(transaction) else { return }
        state.pendingInteractiveLeaseCommand = nil
        pending.deadline = nil
        pending.continuation.resume(
            throwing: MacLocalXPCInteractiveLeaseErrorV1.replyTimedOut
        )
        cancelAuthenticatedPeer(
            state,
            presentationError: .replyTimedOut
        )
    }

    private func cancelInteractiveLeaseCommand(requestID: UUID) {
        guard let state = currentPeerState,
              let pending = state.pendingInteractiveLeaseCommand,
              pending.requestID == requestID,
              state.interactiveLeaseGate.finish(pending.transaction) else {
            return
        }
        state.pendingInteractiveLeaseCommand = nil
        pending.deadline?.cancel()
        pending.deadline = nil
        pending.continuation.resume(
            throwing: MacLocalXPCInteractiveLeaseErrorV1.cancelledAfterSend
        )
        cancelAuthenticatedPeer(
            state,
            presentationError: .cancelledAfterSend
        )
    }

    private func admitsInteractiveLeaseCompletion(
        state: PeerState,
        transaction: MacLocalXPCInteractiveLeaseTransactionGateV1.Active
    ) -> Bool {
        listenerRunGate.admits(generation: state.listenerGeneration)
            && peerStates[state.generation] === state
            && currentPeerState === state
            && generationGate.admitsPostAuthenticationTraffic(
                generation: state.generation
            )
            && state.lifetime.menuReadinessPublished
            && state.postAuthenticationFence.admitsTraffic
            && state.interactiveLeaseGate.admits(transaction)
    }

    private func cancelPeerAfterMalformedInteractiveReply(
        endpointBinding: MacLocalXPCInteractiveLeaseEndpointBindingV1?
    ) {
        if let endpointBinding {
            cancelPeer(generation: endpointBinding.generation)
            return
        }
        queue.async { [weak self] in
            guard let self, let state = currentPeerState else { return }
            self.cancelAuthenticatedPeer(
                state,
                presentationError: .transportFailure
            )
        }
    }

    private func cInteractiveLeaseCommandKind(
        _ kind: MacLocalXPCInteractiveLeaseCommandKindV1
    ) -> MCLocalXPCInteractiveLeaseCommandKind {
        switch kind {
        case .prepareInitialDesktop:
            MCLocalXPCInteractiveLeaseCommandPrepareInitialDesktop
        case .install: MCLocalXPCInteractiveLeaseCommandInstall
        case .renew: MCLocalXPCInteractiveLeaseCommandRenew
        case .revoke: MCLocalXPCInteractiveLeaseCommandRevoke
        case .surfaceTargets:
            MCLocalXPCInteractiveLeaseCommandSurfaceTargets
        case .surfaceResolve:
            MCLocalXPCInteractiveLeaseCommandSurfaceResolve
        case .surfaceTransition:
            MCLocalXPCInteractiveLeaseCommandSurfaceTransition
        case .surfaceAcknowledgement:
            MCLocalXPCInteractiveLeaseCommandSurfaceAcknowledgement
        case .surfaceFailure:
            MCLocalXPCInteractiveLeaseCommandSurfaceFailure
        case .focusSnapshot:
            MCLocalXPCInteractiveLeaseCommandFocusSnapshot
        case .displayCatalog:
            MCLocalXPCInteractiveLeaseCommandDisplayCatalog
        case .displaySelect:
            MCLocalXPCInteractiveLeaseCommandDisplaySelect
        case .nativeBackend:
            MCLocalXPCInteractiveLeaseCommandNativeBackend
        case .nativeSnapshot:
            MCLocalXPCInteractiveLeaseCommandNativeSnapshot
        case .webRTCOffer:
            MCLocalXPCInteractiveLeaseCommandWebRTCOffer
        case .webRTCAnswer:
            MCLocalXPCInteractiveLeaseCommandWebRTCAnswer
        case .webRTCClose:
            MCLocalXPCInteractiveLeaseCommandWebRTCClose
        }
    }

    /// Returns the one cached opaque endpoint only for the exact current,
    /// authenticated, ready peer under the explicit presentation profile.
    /// The returned actor never owns or exposes the raw session.
    package func authenticatedMenuPresentationEndpoint(
        generation: UInt64
    ) async -> (any MacLocalXPCAuthenticatedMenuSurfaceEndpointV1)? {
        await withCheckedContinuation {
            (continuation: CheckedContinuation<
                (any MacLocalXPCAuthenticatedMenuSurfaceEndpointV1)?,
                Never
            >) in
            queue.async { [weak self] in
                guard let self,
                      let state = currentPeerState,
                      state.generation == generation,
                      listenerRunGate.admits(
                        generation: state.listenerGeneration
                      ),
                      peerStates[generation] === state,
                      generationGate.admitsPostAuthenticationTraffic(
                        generation: generation
                      ),
                      state.lifetime.menuReadinessPublished,
                      state.postAuthenticationFence.admitsTraffic,
                      !state.presentationFIFO.isTerminal,
                      let token = state.presentationIssuanceGate.issue(
                        generation: generation,
                        permitted: profile.admitsMenuPresentation
                      ) else {
                    continuation.resume(returning: nil)
                    return
                }
                if let endpoint = state.presentationEndpoint {
                    continuation.resume(returning: endpoint)
                    return
                }
                let endpoint =
                    MacLocalXPCAuthenticatedMenuPresentationEndpointV1(
                        generation: generation,
                        endpointToken: token,
                        sender: self
                    )
                state.presentationEndpoint = endpoint
                continuation.resume(returning: endpoint)
            }
        }
    }

    package func sendMenuPresentation(
        generation: UInt64,
        endpointToken: UUID,
        request: MacLocalXPCMenuPresentationRequestV1
    ) async throws -> MacLocalXPCMenuPresentationSendOutcomeV1 {
        let requestID = UUID()
        let marker = PresentationCancellationMarker()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [weak self] in
                    guard let self else {
                        continuation.resume(
                            throwing: MacLocalXPCMenuPresentationSendErrorV1
                                .endpointUnavailable
                        )
                        return
                    }
                    self.admitPresentation(
                        generation: generation,
                        endpointToken: endpointToken,
                        requestID: requestID,
                        request: request,
                        cancellationMarker: marker,
                        continuation: continuation
                    )
                }
            }
        } onCancel: { [weak self] in
            marker.markCancelled()
            self?.queue.async { [weak self] in
                self?.cancelPresentationRequest(
                    generation: generation,
                    endpointToken: endpointToken,
                    requestID: requestID
                )
            }
        }
    }

    package func retireMenuPresentationEndpoint(
        generation: UInt64,
        endpointToken: UUID
    ) async {
        await withCheckedContinuation {
            (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [weak self] in
                defer { continuation.resume() }
                guard let self,
                      let state = currentPeerState,
                      state.generation == generation,
                      state.presentationIssuanceGate.token == endpointToken,
                      peerStates[generation] === state else {
                    return
                }
                self.cancelAuthenticatedPeer(
                    state,
                    presentationError: .retired
                )
            }
        }
    }

    private func admitPresentation(
        generation: UInt64,
        endpointToken: UUID,
        requestID: UUID,
        request: MacLocalXPCMenuPresentationRequestV1,
        cancellationMarker: PresentationCancellationMarker,
        continuation: CheckedContinuation<
            MacLocalXPCMenuPresentationSendOutcomeV1,
            any Error
        >
    ) {
        guard let state = currentPeerState,
              state.generation == generation,
              listenerRunGate.admits(generation: state.listenerGeneration),
              peerStates[generation] === state,
              generationGate.admitsPostAuthenticationTraffic(
                generation: generation
              ),
              state.lifetime.menuReadinessPublished,
              state.postAuthenticationFence.admitsTraffic,
              profile.admitsMenuPresentation,
              state.presentationIssuanceGate.token == endpointToken,
              state.presentationEndpoint != nil,
              !state.presentationFIFO.isTerminal,
              authorizesAgentPresentationMethod(
                request.authorizationMethod
              ) else {
            continuation.resume(
                throwing: MacLocalXPCMenuPresentationSendErrorV1
                    .endpointUnavailable
            )
            return
        }
        let admission = state.presentationFIFO.admit(
            requestID: requestID,
            cancelled: cancellationMarker.isCancelled()
        )
        switch admission {
        case .cancelledBeforeAdmission:
            continuation.resume(throwing: CancellationError())
            return
        case .overflow(let drainedRequestIDs):
            continuation.resume(
                throwing: MacLocalXPCMenuPresentationSendErrorV1
                    .admissionOverflow
            )
            completePendingPresentations(
                state,
                requestIDs: drainedRequestIDs,
                error: .admissionOverflow
            )
            cancelAuthenticatedPeer(
                state,
                presentationError: .admissionOverflow
            )
            return
        case .operationExhausted(let drainedRequestIDs):
            continuation.resume(
                throwing: MacLocalXPCMenuPresentationSendErrorV1
                    .operationExhausted
            )
            completePendingPresentations(
                state,
                requestIDs: drainedRequestIDs,
                error: .operationExhausted
            )
            cancelAuthenticatedPeer(
                state,
                presentationError: .operationExhausted
            )
            return
        case .terminal:
            continuation.resume(
                throwing: MacLocalXPCMenuPresentationSendErrorV1
                    .endpointUnavailable
            )
            return
        case .admitted(let operation, let startsImmediately):
            state.pendingPresentations[requestID] = PendingPresentation(
                requestID: requestID,
                operation: operation,
                request: request,
                cancellationMarker: cancellationMarker,
                continuation: continuation
            )
            if startsImmediately {
                startNextPresentationIfNeeded(state)
            }
        }
    }

    private func startNextPresentationIfNeeded(_ state: PeerState) {
        guard let head = state.presentationFIFO.head,
              !head.sent,
              let pending = state.pendingPresentations[head.requestID],
              pending.operation == head.operation else {
            return
        }
        guard listenerRunGate.admits(
                generation: state.listenerGeneration
              ),
              peerStates[state.generation] === state,
              currentPeerState === state,
              generationGate.admitsPostAuthenticationTraffic(
                generation: state.generation
              ),
              state.lifetime.menuReadinessPublished,
              state.postAuthenticationFence.admitsTraffic,
              profile.admitsMenuPresentation,
              !state.presentationFIFO.isTerminal,
              let token = state.presentationIssuanceGate.token,
              state.presentationEndpoint != nil,
              authorizesAgentPresentationMethod(
                pending.request.authorizationMethod
              ) else {
            cancelAuthenticatedPeer(
                state,
                presentationError: .endpointUnavailable
            )
            return
        }
        let result = pending.cancellationMarker.performSendUnlessCancelled {
            guard state.presentationFIFO.claimHeadForSend(
                requestID: pending.requestID,
                operation: pending.operation
            ) else {
                return MCLocalXPCResultConstructionFailed
            }
            return sendPresentationRequest(
                pending.request,
                on: state.peer
            ) { [weak self, weak state] reply in
                guard let self, let state else { return }
                self.queue.async { [weak self, weak state] in
                    guard let self, let state else { return }
                    self.finishPresentationReply(
                        state: state,
                        endpointToken: token,
                        operation: pending.operation,
                        requestID: pending.requestID,
                        reply: reply
                    )
                }
            }
        }
        guard let result else {
            _ = state.presentationFIFO.cancel(requestID: pending.requestID)
            state.pendingPresentations.removeValue(
                forKey: pending.requestID
            )
            pending.continuation.resume(throwing: CancellationError())
            startNextPresentationIfNeeded(state)
            return
        }
        guard result == MCLocalXPCResultOK else {
            cancelAuthenticatedPeer(
                state,
                presentationError: .transportFailure
            )
            return
        }
        let deadline = DispatchWorkItem { [weak self, weak state] in
            guard let self, let state else { return }
            self.expirePresentation(
                state: state,
                endpointToken: token,
                operation: pending.operation,
                requestID: pending.requestID
            )
        }
        pending.deadline = deadline
        queue.asyncAfter(
            deadline: .now() + .seconds(Self.presentationReplyTimeoutSeconds),
            execute: deadline
        )
    }

    private func sendPresentationRequest(
        _ request: MacLocalXPCMenuPresentationRequestV1,
        on peer: MCLocalXPCSessionRef,
        reply: @escaping MCLocalXPCMenuPresentationReplyHandler
    ) -> MCLocalXPCResult {
        switch request {
        case .pairingReview(let payload):
            return payload.withUnsafeBytes { buffer in
                guard let bytes = buffer.bindMemory(to: UInt8.self)
                    .baseAddress else {
                    return MCLocalXPCResultConstructionFailed
                }
                return MCLocalXPCSessionSendPairingReviewPublish(
                    peer,
                    bytes,
                    payload.count,
                    reply
                )
            }
        case .pairingWithdrawal(let reviewID):
            var bytes = reviewID.uuid
            return withUnsafeBytes(of: &bytes) { buffer in
                MCLocalXPCSessionSendPairingReviewWithdrawal(
                    peer,
                    buffer.bindMemory(to: UInt8.self).baseAddress!,
                    buffer.count,
                    reply
                )
            }
        case .hostRecoveryReview(let payload):
            return payload.withUnsafeBytes { buffer in
                guard let bytes = buffer.bindMemory(to: UInt8.self)
                    .baseAddress else {
                    return MCLocalXPCResultConstructionFailed
                }
                return MCLocalXPCSessionSendHostRecoveryReviewPublish(
                    peer,
                    bytes,
                    payload.count,
                    reply
                )
            }
        case .hostRecoveryResume(let payload):
            return payload.withUnsafeBytes { buffer in
                guard let bytes = buffer.bindMemory(to: UInt8.self)
                    .baseAddress else {
                    return MCLocalXPCResultConstructionFailed
                }
                return MCLocalXPCSessionSendHostRecoveryResumePublish(
                    peer,
                    bytes,
                    payload.count,
                    reply
                )
            }
        case .hostRecoveryWithdrawal(let reviewID):
            var bytes = reviewID.uuid
            return withUnsafeBytes(of: &bytes) { buffer in
                MCLocalXPCSessionSendHostRecoveryWithdrawal(
                    peer,
                    buffer.bindMemory(to: UInt8.self).baseAddress!,
                    buffer.count,
                    reply
                )
            }
        }
    }

    private func finishPresentationReply(
        state: PeerState,
        endpointToken: UUID,
        operation: UInt64,
        requestID: UUID,
        reply: MCLocalXPCMenuPresentationReply
    ) {
        guard listenerRunGate.admits(
                generation: state.listenerGeneration
              ),
              peerStates[state.generation] === state,
              currentPeerState === state,
              generationGate.admitsPostAuthenticationTraffic(
                generation: state.generation
              ),
              state.presentationIssuanceGate.token == endpointToken,
              state.presentationFIFO.admitsActiveCallback(
                requestID: requestID,
                operation: operation
              ),
              let pending = state.pendingPresentations[requestID],
              pending.operation == operation else {
            return
        }
        pending.deadline?.cancel()
        pending.deadline = nil
        switch reply {
        case MCLocalXPCMenuPresentationReplyAcknowledged:
            guard state.presentationFIFO.completeHead(
                requestID: requestID,
                operation: operation
            ) else { return }
            state.pendingPresentations.removeValue(forKey: requestID)
            pending.continuation.resume(returning: .acknowledged)
            startNextPresentationIfNeeded(state)
        case MCLocalXPCMenuPresentationReplyRejected:
            guard pending.request.isPublish else {
                cancelAuthenticatedPeer(
                    state,
                    presentationError: .transportFailure
                )
                return
            }
            guard state.presentationFIFO.completeHead(
                requestID: requestID,
                operation: operation
            ) else { return }
            state.pendingPresentations.removeValue(forKey: requestID)
            pending.continuation.resume(
                returning: .rejectedWithoutRetainedState
            )
            startNextPresentationIfNeeded(state)
        default:
            cancelAuthenticatedPeer(
                state,
                presentationError: .transportFailure
            )
        }
    }

    private func expirePresentation(
        state: PeerState,
        endpointToken: UUID,
        operation: UInt64,
        requestID: UUID
    ) {
        guard peerStates[state.generation] === state,
              currentPeerState === state,
              state.presentationIssuanceGate.token == endpointToken,
              state.presentationFIFO.admitsActiveCallback(
                requestID: requestID,
                operation: operation
              ) else {
            return
        }
        cancelAuthenticatedPeer(state, presentationError: .replyTimedOut)
    }

    private func cancelPresentationRequest(
        generation: UInt64,
        endpointToken: UUID,
        requestID: UUID
    ) {
        guard let state = currentPeerState,
              state.generation == generation,
              state.presentationIssuanceGate.token == endpointToken else {
            return
        }
        switch state.presentationFIFO.cancel(requestID: requestID) {
        case .absent:
            return
        case .cancelledBeforeSend:
            guard let pending = state.pendingPresentations.removeValue(
                forKey: requestID
            ) else { return }
            pending.continuation.resume(throwing: CancellationError())
        case .terminalAfterSend(let drainedRequestIDs):
            completePendingPresentations(
                state,
                requestIDs: drainedRequestIDs,
                error: .cancelledAfterSend
            )
            cancelAuthenticatedPeer(
                state,
                presentationError: .cancelledAfterSend
            )
        }
    }

    private func fencePresentations(
        _ state: PeerState,
        error: MacLocalXPCMenuPresentationSendErrorV1
    ) {
        state.presentationIssuanceGate.invalidate(
            generation: state.generation
        )
        let requestIDs = state.presentationFIFO.fence()
        completePendingPresentations(
            state,
            requestIDs: requestIDs,
            error: error
        )
        // A terminal state created by overflow or active cancellation already
        // supplied its drain list to the caller. This invariant fallback keeps
        // exact-once completion fail-closed if future glue violates that order.
        if !state.pendingPresentations.isEmpty {
            completePendingPresentations(
                state,
                requestIDs: Array(state.pendingPresentations.keys),
                error: error
            )
        }
    }

    private func completePendingPresentations(
        _ state: PeerState,
        requestIDs: [UUID],
        error: MacLocalXPCMenuPresentationSendErrorV1
    ) {
        for requestID in requestIDs {
            guard let pending = state.pendingPresentations.removeValue(
                forKey: requestID
            ) else {
                continue
            }
            pending.deadline?.cancel()
            pending.deadline = nil
            pending.continuation.resume(throwing: error)
        }
    }

    private func cancelAuthenticatedPeer(
        _ state: PeerState,
        presentationError: MacLocalXPCMenuPresentationSendErrorV1
    ) {
        fencePostAuthenticationTraffic(
            state,
            presentationError: presentationError
        )
        guard state.postAuthenticationFence
                .claimSessionCancellation() else { return }
        MCLocalXPCSessionCancel(state.peer)
    }

    private func fencePostAuthenticationTraffic(
        _ state: PeerState,
        presentationError: MacLocalXPCMenuPresentationSendErrorV1
    ) {
        guard state.postAuthenticationFence.fence() else { return }
        invalidateRemoteAccessBootstrap(state)
        state.cancelPendingStatusRead()
        state.cancelPendingMenuPairingCommand()
        state.cancelPendingUpdateQuiescenceCommand()
        state.cancelPendingInteractiveLeaseCommand(error: .unavailable)
        state.cancelPendingInteractiveInput(error: .unavailable)
        invalidateInteractiveAdmission(state)
        invalidateInteractiveMedia(state)
        fencePresentations(state, error: presentationError)
    }

    private func invalidateInteractiveAdmission(_ state: PeerState) {
        _ = state.cancelPendingInteractiveAdmissionPublication()
        guard let interactiveAdmissionHandler else { return }
        let generation = state.generation
        Task {
            await interactiveAdmissionHandler
                .invalidateInteractiveAdmission(
                    transportGeneration: generation
                )
        }
    }

    private func invalidateInteractiveMedia(_ state: PeerState) {
        _ = state.cancelPendingInteractiveMediaPublication()
        guard let interactiveMediaHandler else { return }
        let generation = state.generation
        Task {
            await interactiveMediaHandler.invalidateInteractiveMedia(
                transportGeneration: generation
            )
        }
    }

    private func invalidateRemoteAccessBootstrap(_ state: PeerState) {
        guard state.cancelRemoteAccessBootstrap(),
              let bootstrapHandler else { return }
        let generation = state.generation
        Task {
            await bootstrapHandler.invalidate(generation: generation)
        }
    }

    private func authorizesAgentPresentationMethod(
        _ method: LocalIPCMethod
    ) -> Bool {
        do {
            try LocalIPCAuthorizationPolicy.authorize(
                authenticatedCaller: .agent,
                endpoint: .menuApp,
                method: method,
                version: .init()
            )
            return true
        } catch {
            return false
        }
    }

    private func accept(
        peer: MCLocalXPCSessionRef,
        listenerGeneration: UInt64
    ) {
        guard listenerRunGate.admits(generation: listenerGeneration),
              let peerRequirement,
              nextGeneration < UInt64.max else {
            MCLocalXPCListenerRejectPeer(peer)
            return
        }

        nextGeneration += 1
        guard pendingGate.admit(generation: nextGeneration) else {
            MCLocalXPCListenerRejectPeer(peer)
            return
        }
        MCLocalXPCSessionSetPeerRequirement(peer, peerRequirement)
        let state = PeerState(
            listenerGeneration: listenerGeneration,
            generation: nextGeneration,
            peer: peer
        )
        peerStates[state.generation] = state

        MCLocalXPCSessionSetCancelHandler(peer) { [weak self, state] in
            state.handshakeDeadline?.cancel()
            state.handshakeDeadline = nil
            state.cancelPendingStatusRead()
            if let ownedPeer = state.takeOwnedPeer() {
                MCLocalXPCSessionRelease(ownedPeer)
            }
            guard let self,
                  self.listenerRunGate.admits(
                    generation: state.listenerGeneration
                  ),
                  self.peerStates[state.generation] === state else {
                return
            }
            self.fencePostAuthenticationTraffic(
                state,
                presentationError: .endpointUnavailable
            )
            self.peerStates.removeValue(forKey: state.generation)
            self.pendingGate.remove(generation: state.generation)
            if self.currentPeerState === state {
                self.currentPeerState = nil
                _ = self.generationGate.invalidate(
                    generation: state.generation
                )
            }
            let wasAuthenticated = state.lifetime.invalidate()
            if wasAuthenticated {
                self.onEvent(
                    .invalidatedMenu(generation: state.generation)
                )
            }
        }
        MCLocalXPCSessionSetMessageHandler(peer) {
            [weak self, state] message in
            guard let self,
                  self.listenerRunGate.admits(
                    generation: state.listenerGeneration
                  ),
                  self.peerStates[state.generation] === state else {
                return
            }
            if !state.lifetime.authenticationPublished {
                let exact = MCLocalXPCMessageIsExactHello(message)
                guard state.lifetime.receiveHello(exact: exact)
                        == .acknowledgeAndAuthenticate,
                      let agentBuild,
                      MCLocalXPCSessionReplyToHello(
                        peer,
                        message,
                        agentBuild
                      )
                        == MCLocalXPCResultOK,
                      state.lifetime.publishAuthentication() else {
                    MCLocalXPCSessionCancel(peer)
                    return
                }
                state.handshakeDeadline?.cancel()
                state.handshakeDeadline = nil
                self.pendingGate.remove(generation: state.generation)
                if let replacedGeneration = self.generationGate.authenticate(
                    generation: state.generation
                ), let replaced = self.currentPeerState,
                   replaced.generation == replacedGeneration {
                    self.peerStates.removeValue(
                        forKey: replaced.generation
                    )
                    replaced.handshakeDeadline?.cancel()
                    replaced.handshakeDeadline = nil
                    _ = replaced.lifetime.invalidate()
                    self.fencePostAuthenticationTraffic(
                        replaced,
                        presentationError: .endpointUnavailable
                    )
                    if let ownedPeer = replaced.takeOwnedPeer() {
                        MCLocalXPCSessionCancelOwned(ownedPeer)
                    }
                }
                self.currentPeerState = state
                self.onEvent(
                    .authenticatedMenu(generation: state.generation)
                )
                return
            }

            guard self.currentPeerState === state,
                  state.postAuthenticationFence.admitsTraffic,
                  self.generationGate.admitsPostAuthenticationTraffic(
                    generation: state.generation
                  ) else {
                self.cancelAuthenticatedPeer(
                    state,
                    presentationError: .endpointUnavailable
                )
                return
            }

            if MCLocalXPCMessageIsExactRemoteAccessBootstrapRead(message) {
                guard self.beginRemoteAccessBootstrapOfferRead(
                    state: state,
                    request: message
                ) else {
                    self.cancelAuthenticatedPeer(
                        state,
                        presentationError: .transportFailure
                    )
                    return
                }
                return
            }

            var enablePayload: UnsafePointer<UInt8>?
            var enablePayloadLength = 0
            if MCLocalXPCMessageGetExactRemoteAccessEnable(
                message,
                &enablePayload,
                &enablePayloadLength
            ) {
                guard let enablePayload,
                      enablePayloadLength > 0 else {
                    self.cancelAuthenticatedPeer(
                        state,
                        presentationError: .transportFailure
                    )
                    return
                }
                let payload = Data(
                    bytes: enablePayload,
                    count: enablePayloadLength
                )
                guard let command = try?
                        LocalRemoteAccessBootstrapWireCodecV1
                            .decodeEnableCommand(payload),
                      self.beginRemoteAccessEnable(
                        state: state,
                        request: message,
                        command: command
                      ) else {
                    self.cancelAuthenticatedPeer(
                        state,
                        presentationError: .transportFailure
                    )
                    return
                }
                return
            }

            if MCLocalXPCMessageIsExactMenuReady(message) {
                guard self.profile.admitsMenuLifecycleReadiness,
                      self.authorizesMenuMethod(.publishMenuReady),
                      state.lifetime.receiveMenuReady(exact: true)
                        == .acknowledgeAndPublish,
                      MCLocalXPCSessionReplyToMenuReady(peer, message)
                        == MCLocalXPCResultOK,
                      state.lifetime.publishMenuReadiness() else {
                    self.cancelAuthenticatedPeer(
                        state,
                        presentationError: .transportFailure
                    )
                    return
                }
                guard state.presentationIssuanceGate.publishReadiness(
                    generation: state.generation
                ) else {
                    self.cancelAuthenticatedPeer(
                        state,
                        presentationError: .transportFailure
                    )
                    return
                }
                self.onEvent(.menuReady(generation: state.generation))
                return
            }

            var admissionPayload: UnsafePointer<UInt8>?
            var admissionPayloadLength = 0
            if MCLocalXPCMessageGetExactInteractiveAdmissionPublication(
                message,
                &admissionPayload,
                &admissionPayloadLength
            ) {
                guard let admissionPayload,
                      admissionPayloadLength > 0,
                      admissionPayloadLength <=
                        LocalInteractiveAdmissionWireCodecV1
                            .maximumEncodedBytes else {
                    self.cancelAuthenticatedPeer(
                        state,
                        presentationError: .transportFailure
                    )
                    return
                }
                let payload = Data(
                    bytes: admissionPayload,
                    count: admissionPayloadLength
                )
                guard let publication = try?
                        LocalInteractiveAdmissionWireCodecV1
                            .decodePublication(payload),
                      self.beginInteractiveAdmissionPublication(
                        state: state,
                        request: message,
                        publication: publication
                      ) else {
                    self.cancelAuthenticatedPeer(
                        state,
                        presentationError: .transportFailure
                    )
                    return
                }
                return
            }

            var mediaHeaderBytes: UnsafePointer<UInt8>?
            var mediaHeaderLength = 0
            var mediaPayloadBytes: UnsafePointer<UInt8>?
            var mediaPayloadLength = 0
            if MCLocalXPCMessageGetExactInteractiveMediaPublication(
                message,
                &mediaHeaderBytes,
                &mediaHeaderLength,
                &mediaPayloadBytes,
                &mediaPayloadLength
            ) {
                guard let mediaHeaderBytes,
                      mediaHeaderLength == MediaRecordHeader.byteCount,
                      mediaPayloadBytes != nil || mediaPayloadLength == 0,
                      let header = try? MediaRecordHeader.decode(Data(
                          bytes: mediaHeaderBytes,
                          count: mediaHeaderLength
                      )),
                      mediaPayloadLength == Int(header.payloadLength),
                      mediaPayloadLength <= Int(
                          MCLocalXPCMaximumInteractiveMediaPayloadBytes
                      ),
                      self.beginInteractiveMediaPublication(
                          state: state,
                          request: message,
                          header: header,
                          payload: mediaPayloadLength == 0
                            ? Data()
                            : Data(
                                bytes: mediaPayloadBytes!,
                                count: mediaPayloadLength
                            )
                      ) else {
                    self.cancelAuthenticatedPeer(
                        state,
                        presentationError: .transportFailure
                    )
                    return
                }
                return
            }

            var commandKind = MCLocalXPCMenuPairingCommandCreate
            var commandPayload: UnsafePointer<UInt8>?
            var commandPayloadLength = 0
            if MCLocalXPCMessageGetExactMenuPairingCommand(
                message,
                &commandKind,
                &commandPayload,
                &commandPayloadLength
            ) {
                guard let commandPayload,
                      commandPayloadLength > 0,
                      commandPayloadLength <=
                        LocalMenuPairingCommandWireCodecV1.maximumEncodedBytes
                else {
                    self.cancelAuthenticatedPeer(
                        state,
                        presentationError: .transportFailure
                    )
                    return
                }
                let payload = Data(
                    bytes: commandPayload,
                    count: commandPayloadLength
                )
                guard let command = self.decodeMenuPairingCommand(
                    kind: commandKind,
                    payload: payload
                ), self.beginMenuPairingCommand(
                    state: state,
                    request: message,
                    command: command
                ) else {
                    self.cancelAuthenticatedPeer(
                        state,
                        presentationError: .transportFailure
                    )
                    return
                }
                return
            }

            var updateCommand =
                MCLocalXPCUpdateQuiescenceCloseNetworkAdmission
            if MCLocalXPCMessageGetExactUpdateQuiescenceCommand(
                message,
                &updateCommand
            ) {
                guard let command = self.updateQuiescenceCommand(
                    updateCommand
                ), self.beginUpdateQuiescenceCommand(
                    state: state,
                    request: message,
                    command: command
                ) else {
                    self.cancelAuthenticatedPeer(
                        state,
                        presentationError: .transportFailure
                    )
                    return
                }
                return
            }

            guard MCLocalXPCMessageIsExactStatusRead(message),
                  self.beginStatusRead(state: state, request: message) else {
                self.cancelAuthenticatedPeer(
                    state,
                    presentationError: .transportFailure
                )
                return
            }
        }

        let deadline = DispatchWorkItem { [weak self, weak state] in
            guard let self, let state else { return }
            self.expireCandidate(state)
        }
        state.handshakeDeadline = deadline
        queue.asyncAfter(
            deadline: .now() + handshakeTimeout,
            execute: deadline
        )
    }

    private func authorizesMenuMethod(
        _ method: LocalIPCMethod
    ) -> Bool {
        do {
            try LocalIPCAuthorizationPolicy.authorize(
                authenticatedCaller: .menuApp,
                endpoint: .agent,
                method: method,
                version: .init()
            )
            return true
        } catch {
            return false
        }
    }

    private func beginInteractiveAdmissionPublication(
        state: PeerState,
        request: MCLocalXPCMessageRef,
        publication: LocalInteractiveAdmissionPublicationV1
    ) -> Bool {
        guard let interactiveAdmissionHandler,
              state.lifetime.menuReadinessPublished,
              let transaction = state.interactiveAdmissionGate.begin(
                generation: state.generation,
                permitted:
                    profile.admitsInteractiveAdmissionPublication
                    && authorizesMenuMethod(.publishInteractiveState)
                    && state.postAuthenticationFence.admitsTraffic
              ) else {
            return false
        }

        let pending = PendingInteractiveAdmissionPublication(
            transaction: transaction,
            publication: publication,
            request: request
        )
        state.pendingInteractiveAdmissionPublication = pending
        let queue = self.queue
        let generation = state.generation
        pending.task = Task {
            [weak self, weak state, interactiveAdmissionHandler] in
            do {
                let receipt = try await interactiveAdmissionHandler
                    .publishInteractiveAdmission(
                        publication,
                        transportGeneration: generation
                    )
                queue.async { [weak self, weak state] in
                    guard let self, let state else { return }
                    self.completeInteractiveAdmissionPublication(
                        state: state,
                        transaction: transaction,
                        receipt: receipt
                    )
                }
            } catch {
                queue.async { [weak self, weak state] in
                    guard let self, let state else { return }
                    self.terminateInteractiveAdmissionPublication(
                        state: state,
                        transaction: transaction
                    )
                }
            }
        }
        let deadline = DispatchWorkItem { [weak self, weak state] in
            guard let self, let state else { return }
            self.terminateInteractiveAdmissionPublication(
                state: state,
                transaction: transaction
            )
        }
        pending.deadline = deadline
        queue.asyncAfter(
            deadline: .now()
                + .seconds(Self.interactiveAdmissionTimeoutSeconds),
            execute: deadline
        )
        return true
    }

    private func completeInteractiveAdmissionPublication(
        state: PeerState,
        transaction:
            MacLocalXPCInteractiveAdmissionTransactionGateV1.Active,
        receipt: LocalInteractiveAdmissionPublishedReceiptV1
    ) {
        guard admitsInteractiveAdmissionCompletion(
                state: state,
                transaction: transaction
              ),
              let pending = state.pendingInteractiveAdmissionPublication,
              pending.transaction == transaction,
              (try? receipt.validate(against: pending.publication)) != nil,
              let payload = try? LocalInteractiveAdmissionWireCodecV1
                .encodeReceipt(receipt) else {
            terminateInteractiveAdmissionPublication(
                state: state,
                transaction: transaction
            )
            return
        }
        guard state.interactiveAdmissionGate.finish(transaction),
              let request = takeInteractiveAdmissionRequest(
                state: state,
                transaction: transaction
              ) else {
            cancelAuthenticatedPeer(
                state,
                presentationError: .transportFailure
            )
            return
        }
        defer { MCLocalXPCMessageRelease(request) }
        let result = payload.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress
            else { return MCLocalXPCResultConstructionFailed }
            return MCLocalXPCSessionReplyToInteractiveAdmissionPublication(
                state.peer,
                request,
                bytes,
                payload.count
            )
        }
        guard result == MCLocalXPCResultOK else {
            cancelAuthenticatedPeer(
                state,
                presentationError: .transportFailure
            )
            return
        }
    }

    private func admitsInteractiveAdmissionCompletion(
        state: PeerState,
        transaction:
            MacLocalXPCInteractiveAdmissionTransactionGateV1.Active
    ) -> Bool {
        listenerRunGate.admits(generation: state.listenerGeneration)
            && peerStates[state.generation] === state
            && currentPeerState === state
            && generationGate.admitsPostAuthenticationTraffic(
                generation: state.generation
            )
            && state.lifetime.menuReadinessPublished
            && state.postAuthenticationFence.admitsTraffic
            && state.interactiveAdmissionGate.admits(transaction)
    }

    private func takeInteractiveAdmissionRequest(
        state: PeerState,
        transaction:
            MacLocalXPCInteractiveAdmissionTransactionGateV1.Active
    ) -> MCLocalXPCMessageRef? {
        guard let pending = state.pendingInteractiveAdmissionPublication,
              pending.transaction == transaction else { return nil }
        state.pendingInteractiveAdmissionPublication = nil
        pending.deadline?.cancel()
        pending.deadline = nil
        pending.task = nil
        return pending.takeOwnedRequest()
    }

    private func terminateInteractiveAdmissionPublication(
        state: PeerState,
        transaction:
            MacLocalXPCInteractiveAdmissionTransactionGateV1.Active
    ) {
        guard state.interactiveAdmissionGate.admits(transaction) else {
            return
        }
        _ = state.cancelPendingInteractiveAdmissionPublication()
        cancelAuthenticatedPeer(
            state,
            presentationError: .transportFailure
        )
    }

    private func beginInteractiveMediaPublication(
        state: PeerState,
        request: MCLocalXPCMessageRef,
        header: MediaRecordHeader,
        payload: Data
    ) -> Bool {
        guard let interactiveMediaHandler,
              state.lifetime.menuReadinessPublished,
              let transaction = state.interactiveMediaGate.begin(
                generation: state.generation,
                permitted:
                    profile.admitsMenuPresentation
                    && authorizesMenuMethod(.publishInteractiveMedia)
                    && state.postAuthenticationFence.admitsTraffic
              ) else {
            return false
        }

        let pending = PendingInteractiveMediaPublication(
            transaction: transaction,
            request: request
        )
        state.pendingInteractiveMediaPublication = pending
        let queue = self.queue
        let generation = state.generation
        pending.task = Task {
            [weak self, weak state, interactiveMediaHandler] in
            do {
                try await interactiveMediaHandler.publishInteractiveMedia(
                    header: header,
                    payload: payload,
                    transportGeneration: generation
                )
                queue.async { [weak self, weak state] in
                    guard let self, let state else { return }
                    self.completeInteractiveMediaPublication(
                        state: state,
                        transaction: transaction
                    )
                }
            } catch {
                queue.async { [weak self, weak state] in
                    guard let self, let state else { return }
                    self.terminateInteractiveMediaPublication(
                        state: state,
                        transaction: transaction
                    )
                }
            }
        }
        let deadline = DispatchWorkItem { [weak self, weak state] in
            guard let self, let state else { return }
            self.terminateInteractiveMediaPublication(
                state: state,
                transaction: transaction
            )
        }
        pending.deadline = deadline
        queue.asyncAfter(
            deadline: .now()
                + .seconds(Self.interactiveMediaOperationTimeoutSeconds),
            execute: deadline
        )
        return true
    }

    private func completeInteractiveMediaPublication(
        state: PeerState,
        transaction: MacLocalXPCInteractiveRoleDataTransactionGateV1.Active
    ) {
        guard admitsInteractiveMediaCompletion(
                state: state,
                transaction: transaction
              ),
              let pending = state.pendingInteractiveMediaPublication,
              pending.transaction == transaction else {
            terminateInteractiveMediaPublication(
                state: state,
                transaction: transaction
            )
            return
        }
        guard state.interactiveMediaGate.finish(transaction),
              let request = takeInteractiveMediaRequest(
                state: state,
                transaction: transaction
              ) else {
            cancelAuthenticatedPeer(
                state,
                presentationError: .transportFailure
            )
            return
        }
        defer { MCLocalXPCMessageRelease(request) }
        guard MCLocalXPCSessionReplyToInteractiveMediaPublication(
            state.peer,
            request
        ) == MCLocalXPCResultOK else {
            cancelAuthenticatedPeer(
                state,
                presentationError: .transportFailure
            )
            return
        }
    }

    private func admitsInteractiveMediaCompletion(
        state: PeerState,
        transaction: MacLocalXPCInteractiveRoleDataTransactionGateV1.Active
    ) -> Bool {
        listenerRunGate.admits(generation: state.listenerGeneration)
            && peerStates[state.generation] === state
            && currentPeerState === state
            && generationGate.admitsPostAuthenticationTraffic(
                generation: state.generation
            )
            && state.lifetime.menuReadinessPublished
            && state.postAuthenticationFence.admitsTraffic
            && state.interactiveMediaGate.admits(transaction)
    }

    private func takeInteractiveMediaRequest(
        state: PeerState,
        transaction: MacLocalXPCInteractiveRoleDataTransactionGateV1.Active
    ) -> MCLocalXPCMessageRef? {
        guard let pending = state.pendingInteractiveMediaPublication,
              pending.transaction == transaction else { return nil }
        state.pendingInteractiveMediaPublication = nil
        pending.deadline?.cancel()
        pending.deadline = nil
        pending.task = nil
        return pending.takeOwnedRequest()
    }

    private func terminateInteractiveMediaPublication(
        state: PeerState,
        transaction: MacLocalXPCInteractiveRoleDataTransactionGateV1.Active
    ) {
        guard state.interactiveMediaGate.admits(transaction) else { return }
        invalidateInteractiveMedia(state)
        cancelAuthenticatedPeer(
            state,
            presentationError: .transportFailure
        )
    }

    private func decodeMenuPairingCommand(
        kind: MCLocalXPCMenuPairingCommandKind,
        payload: Data
    ) -> MenuPairingCommand? {
        do {
            switch kind {
            case MCLocalXPCMenuPairingCommandCreate:
                return .create(
                    try LocalMenuPairingCommandWireCodecV1
                        .decodeCreateCommand(payload)
                )
            case MCLocalXPCMenuPairingCommandDismiss:
                return .dismiss(
                    try LocalMenuPairingCommandWireCodecV1
                        .decodeDismissCommand(payload)
                )
            case MCLocalXPCMenuPairingCommandResolveDecision:
                return .resolveDecision(
                    try LocalMenuPairingCommandWireCodecV1
                        .decodeDecisionCommand(payload)
                )
            case MCLocalXPCMenuPairingCommandRecoverHostIdentity:
                return .recoverHostIdentity(
                    try LocalHostIdentityRecoveryWireCodecV1
                        .decodeCommand(payload)
                )
            case MCLocalXPCMenuPairingCommandAcknowledgeHostIdentityRecovery:
                return .acknowledgeHostIdentityRecoveryCompletion(
                    try LocalHostIdentityRecoveryWireCodecV1
                        .decodeReceipt(payload)
                )
            case MCLocalXPCMenuPairingCommandDeviceAdministration:
                if let request = try? LocalMenuPairingCommandWireCodecV1.decodeCapabilityGrantReviewRequest(payload) {
                    return .requestCapabilityGrantReview(request)
                }
                if let command = try? LocalMenuPairingCommandWireCodecV1.decodeCapabilityGrantDecision(payload) {
                    return .decideCapabilityGrant(command.decision)
                }
                if let request = try? LocalMenuPairingCommandWireCodecV1.decodeDeviceRevocationReviewRequest(payload) {
                    return .requestDeviceRevocationReview(request)
                }
                if let command = try? LocalMenuPairingCommandWireCodecV1.decodeDeviceRevocationCommand(payload) {
                    return .revokeDevice(command)
                }
                if let request = try? LocalMenuPairingCommandWireCodecV1
                    .decodeInteractiveControlGrantReviewRequest(payload) {
                    return .requestInteractiveControlGrantReview(request)
                }
                return .decideInteractiveControlGrant(
                    try LocalMenuPairingCommandWireCodecV1
                        .decodeGrantDecisionCommand(payload)
                )
            default:
                return nil
            }
        } catch {
            return nil
        }
    }

    private func beginMenuPairingCommand(
        state: PeerState,
        request: MCLocalXPCMessageRef,
        command: MenuPairingCommand
    ) -> Bool {
        guard state.lifetime.menuReadinessPublished,
              let transaction = state.menuPairingCommandGate.begin(
                generation: state.generation,
                kind: command.kind,
                permitted:
                    profile.admitsMenuPairingCommands
                        == command.isPairing
                    && profile.admitsHostIdentityRecovery
                        == command.isRecovery
                    && authorizesMenuMethod(command.authorizationMethod)
                    && state.postAuthenticationFence.admitsTraffic
              ) else {
            return false
        }

        let pending = PendingMenuPairingCommand(
            transaction: transaction,
            command: command,
            request: request
        )
        state.pendingMenuPairingCommand = pending
        let queue = self.queue
        pending.task = Task {
            [weak self, weak state, menuPairingCommandHandler,
             hostIdentityRecoveryHandler, command, queue] in
            do {
                let result: MenuPairingCommandResult
                switch command {
                case .create(let value):
                    guard let menuPairingCommandHandler else {
                        throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
                    }
                    result = .created(
                        try await menuPairingCommandHandler
                            .createPairingSession(value)
                    )
                case .dismiss(let value):
                    guard let menuPairingCommandHandler else {
                        throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
                    }
                    result = .dismissed(
                        try await menuPairingCommandHandler
                            .dismissPairingSession(value)
                    )
                case .resolveDecision(let value):
                    guard let menuPairingCommandHandler else {
                        throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
                    }
                    result = .decision(
                        try await menuPairingCommandHandler
                            .resolveLocalApproval(value)
                    )
                case .recoverHostIdentity(let value):
                    guard let hostIdentityRecoveryHandler else {
                        throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
                    }
                    result = .recovered(
                        try await hostIdentityRecoveryHandler
                            .recoverHostIdentity(value)
                    )
                case .acknowledgeHostIdentityRecoveryCompletion(let value):
                    guard let hostIdentityRecoveryHandler else {
                        throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
                    }
                    result = .recoveryCompletionAcknowledged(
                        try await hostIdentityRecoveryHandler
                            .acknowledgeHostIdentityRecoveryCompletion(value)
                    )
                case .requestInteractiveControlGrantReview(let value):
                    guard let menuPairingCommandHandler else {
                        throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
                    }
                    result = .interactiveControlGrantReview(
                        try await menuPairingCommandHandler
                            .makeInteractiveControlGrantReview(value)
                    )
                case .decideInteractiveControlGrant(let value):
                    guard let menuPairingCommandHandler else {
                        throw MacLocalXPCMenuPairingCommandErrorV1.unavailable
                    }
                    result = .interactiveControlGrantDecision(
                        try await menuPairingCommandHandler
                            .decideInteractiveControlGrant(value)
                    )
                case .requestDeviceRevocationReview(let value):
                    guard let menuPairingCommandHandler else { throw MacLocalXPCMenuPairingCommandErrorV1.unavailable }
                    result = .deviceRevocationReview(try await menuPairingCommandHandler.makeDeviceRevocationReview(value))
                case .revokeDevice(let value):
                    guard let menuPairingCommandHandler else { throw MacLocalXPCMenuPairingCommandErrorV1.unavailable }
                    result = .deviceRevoked(try await menuPairingCommandHandler.revokeDevice(value))
                case .requestCapabilityGrantReview(let value):
                    guard let menuPairingCommandHandler else { throw MacLocalXPCMenuPairingCommandErrorV1.unavailable }
                    result = .capabilityGrantReview(try await menuPairingCommandHandler.makeCapabilityGrantReview(value))
                case .decideCapabilityGrant(let value):
                    guard let menuPairingCommandHandler else { throw MacLocalXPCMenuPairingCommandErrorV1.unavailable }
                    result = .capabilityGrantDecision(try await menuPairingCommandHandler.decideCapabilityGrant(value))
                }
                queue.async {
                    [weak self, weak state, hostIdentityRecoveryHandler] in
                    guard let self, let state else {
                        if case let .recoveryCompletionAcknowledged(receipt) =
                            result,
                           let hostIdentityRecoveryHandler {
                            Task {
                                await hostIdentityRecoveryHandler
                                    .hostIdentityRecoveryCompletionAcknowledgementDidBecomeDurable(
                                        receipt,
                                        replyWasSent: false
                                    )
                            }
                        }
                        return
                    }
                    self.completeMenuPairingCommand(
                        state: state,
                        transaction: transaction,
                        result: result
                    )
                }
            } catch {
                queue.async { [weak self, weak state] in
                    guard let self, let state else { return }
                    self.failMenuPairingCommand(
                        state: state,
                        transaction: transaction
                    )
                }
            }
        }
        let deadline = DispatchWorkItem { [weak self, weak state] in
            guard let self, let state else { return }
            self.expireMenuPairingCommand(
                state: state,
                transaction: transaction
            )
        }
        pending.deadline = deadline
        queue.asyncAfter(
            deadline: .now()
                + .seconds(Self.menuPairingCommandTimeoutSeconds),
            execute: deadline
        )
        return true
    }

    private func beginUpdateQuiescenceCommand(
        state: PeerState,
        request: MCLocalXPCMessageRef,
        command: MacLocalXPCUpdateQuiescenceCommandV0
    ) -> Bool {
        guard let updateQuiescenceHandler,
              state.lifetime.menuReadinessPublished,
              let transaction = state.updateQuiescenceGate.begin(
                generation: state.generation,
                command: command,
                permitted:
                    profile.admitsUpdateQuiescence
                    && authorizesMenuMethod(
                        updateQuiescenceAuthorizationMethod(command)
                    )
                    && state.postAuthenticationFence.admitsTraffic
              ) else {
            return false
        }

        let pending = PendingUpdateQuiescenceCommand(
            transaction: transaction,
            request: request
        )
        state.pendingUpdateQuiescenceCommand = pending
        let queue = self.queue
        pending.task = Task {
            [weak self, weak state, updateQuiescenceHandler] in
            do {
                switch command {
                case .closeNetworkAdmission:
                    try await updateQuiescenceHandler
                        .closeNetworkAdmissionForUpdate()
                case .drainNetworkConnections:
                    try await updateQuiescenceHandler
                        .drainNetworkConnectionsForUpdate()
                case .reopenNetworkAdmission:
                    try await updateQuiescenceHandler
                        .reopenNetworkAdmissionAfterUpdateFailure()
                }
                queue.async { [weak self, weak state] in
                    guard let self, let state else { return }
                    self.completeUpdateQuiescenceCommand(
                        state: state,
                        transaction: transaction,
                        succeeded: true
                    )
                }
            } catch {
                queue.async { [weak self, weak state] in
                    guard let self, let state else { return }
                    self.completeUpdateQuiescenceCommand(
                        state: state,
                        transaction: transaction,
                        succeeded: false
                    )
                }
            }
        }
        let deadline = DispatchWorkItem { [weak self, weak state] in
            guard let self, let state else { return }
            self.terminateUpdateQuiescenceCommand(
                state: state,
                transaction: transaction
            )
        }
        pending.deadline = deadline
        queue.asyncAfter(
            deadline: .now()
                + .seconds(Self.updateQuiescenceCommandTimeoutSeconds),
            execute: deadline
        )
        return true
    }

    private func completeUpdateQuiescenceCommand(
        state: PeerState,
        transaction: MacLocalXPCUpdateQuiescenceTransactionGateV0.Active,
        succeeded: Bool
    ) {
        guard admitsUpdateQuiescenceCompletion(
                state: state,
                transaction: transaction
              ),
              state.updateQuiescenceGate.finish(transaction),
              let request = takeUpdateQuiescenceRequest(
                state: state,
                transaction: transaction
              ) else {
            terminateUpdateQuiescenceCommand(
                state: state,
                transaction: transaction
            )
            return
        }
        defer { MCLocalXPCMessageRelease(request) }
        let command = cUpdateQuiescenceCommand(transaction.command)
        let result = succeeded
            ? MCLocalXPCSessionReplyToUpdateQuiescenceSuccess(
                state.peer,
                request,
                command
            )
            : MCLocalXPCSessionReplyToUpdateQuiescenceFailure(
                state.peer,
                request,
                command
            )
        guard result == MCLocalXPCResultOK else {
            cancelAuthenticatedPeer(
                state,
                presentationError: .transportFailure
            )
            return
        }
    }

    private func terminateUpdateQuiescenceCommand(
        state: PeerState,
        transaction: MacLocalXPCUpdateQuiescenceTransactionGateV0.Active
    ) {
        guard state.updateQuiescenceGate.admits(transaction) else { return }
        state.cancelPendingUpdateQuiescenceCommand()
        cancelAuthenticatedPeer(
            state,
            presentationError: .transportFailure
        )
    }

    private func admitsUpdateQuiescenceCompletion(
        state: PeerState,
        transaction: MacLocalXPCUpdateQuiescenceTransactionGateV0.Active
    ) -> Bool {
        listenerRunGate.admits(generation: state.listenerGeneration)
            && peerStates[state.generation] === state
            && currentPeerState === state
            && generationGate.admitsPostAuthenticationTraffic(
                generation: state.generation
            )
            && state.lifetime.menuReadinessPublished
            && state.postAuthenticationFence.admitsTraffic
            && state.updateQuiescenceGate.admits(transaction)
    }

    private func takeUpdateQuiescenceRequest(
        state: PeerState,
        transaction: MacLocalXPCUpdateQuiescenceTransactionGateV0.Active
    ) -> MCLocalXPCMessageRef? {
        guard let pending = state.pendingUpdateQuiescenceCommand,
              pending.transaction == transaction else { return nil }
        state.pendingUpdateQuiescenceCommand = nil
        pending.deadline?.cancel()
        pending.deadline = nil
        pending.task = nil
        return pending.takeOwnedRequest()
    }

    private func updateQuiescenceCommand(
        _ command: MCLocalXPCUpdateQuiescenceCommand
    ) -> MacLocalXPCUpdateQuiescenceCommandV0? {
        switch command {
        case MCLocalXPCUpdateQuiescenceCloseNetworkAdmission:
            .closeNetworkAdmission
        case MCLocalXPCUpdateQuiescenceDrainNetworkConnections:
            .drainNetworkConnections
        case MCLocalXPCUpdateQuiescenceReopenNetworkAdmission:
            .reopenNetworkAdmission
        default:
            nil
        }
    }

    private func updateQuiescenceAuthorizationMethod(
        _ command: MacLocalXPCUpdateQuiescenceCommandV0
    ) -> LocalIPCMethod {
        switch command {
        case .closeNetworkAdmission:
            .closeNetworkAdmissionForUpdate
        case .drainNetworkConnections:
            .drainNetworkConnectionsForUpdate
        case .reopenNetworkAdmission:
            .reopenNetworkAdmissionAfterUpdateFailure
        }
    }

    private func cUpdateQuiescenceCommand(
        _ command: MacLocalXPCUpdateQuiescenceCommandV0
    ) -> MCLocalXPCUpdateQuiescenceCommand {
        switch command {
        case .closeNetworkAdmission:
            MCLocalXPCUpdateQuiescenceCloseNetworkAdmission
        case .drainNetworkConnections:
            MCLocalXPCUpdateQuiescenceDrainNetworkConnections
        case .reopenNetworkAdmission:
            MCLocalXPCUpdateQuiescenceReopenNetworkAdmission
        }
    }

    private func completeMenuPairingCommand(
        state: PeerState,
        transaction: MacLocalXPCMenuPairingCommandTransactionGateV1.Active,
        result: MenuPairingCommandResult
    ) {
        let durableAcknowledgement = recoveryAcknowledgementReceipt(result)
        guard admitsMenuPairingCommandCompletion(
                state: state,
                transaction: transaction
              ),
              let pending = state.pendingMenuPairingCommand,
              pending.transaction == transaction,
              let payload = validatedMenuPairingCommandReply(
                command: pending.command,
                result: result
              ) else {
            notifyRecoveryAcknowledgementDurable(
                durableAcknowledgement,
                replyWasSent: false
            )
            terminateMenuPairingCommand(
                state: state,
                transaction: transaction
            )
            return
        }
        guard state.menuPairingCommandGate.finish(transaction),
              let request = takeMenuPairingCommandRequest(
                state: state,
                transaction: transaction
              ) else {
            notifyRecoveryAcknowledgementDurable(
                durableAcknowledgement,
                replyWasSent: false
            )
            cancelAuthenticatedPeer(
                state,
                presentationError: .transportFailure
            )
            return
        }
        defer { MCLocalXPCMessageRelease(request) }
        let cKind = cMenuPairingCommandKind(transaction.kind)
        let reply = payload.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress
            else { return MCLocalXPCResultConstructionFailed }
            return MCLocalXPCSessionReplyToMenuPairingCommandSuccess(
                state.peer,
                request,
                cKind,
                bytes,
                payload.count
            )
        }
        guard reply == MCLocalXPCResultOK else {
            notifyRecoveryAcknowledgementDurable(
                durableAcknowledgement,
                replyWasSent: false
            )
            cancelAuthenticatedPeer(
                state,
                presentationError: .transportFailure
            )
            return
        }
        notifyRecoveryAcknowledgementDurable(
            durableAcknowledgement,
            replyWasSent: true
        )
    }

    private func recoveryAcknowledgementReceipt(
        _ result: MenuPairingCommandResult
    ) -> LocalHostIdentityRecoveredReceiptV0? {
        guard case let .recoveryCompletionAcknowledged(receipt) = result else {
            return nil
        }
        return receipt
    }

    private func notifyRecoveryAcknowledgementDurable(
        _ receipt: LocalHostIdentityRecoveredReceiptV0?,
        replyWasSent: Bool
    ) {
        guard let receipt, let hostIdentityRecoveryHandler else { return }
        Task {
            await hostIdentityRecoveryHandler
                .hostIdentityRecoveryCompletionAcknowledgementDidBecomeDurable(
                    receipt,
                    replyWasSent: replyWasSent
                )
        }
    }

    private func failMenuPairingCommand(
        state: PeerState,
        transaction: MacLocalXPCMenuPairingCommandTransactionGateV1.Active
    ) {
        guard admitsMenuPairingCommandCompletion(
                state: state,
                transaction: transaction
              ) else { return }
        guard state.menuPairingCommandGate.finish(transaction),
              let request = takeMenuPairingCommandRequest(
                state: state,
                transaction: transaction
              ) else {
            cancelAuthenticatedPeer(
                state,
                presentationError: .transportFailure
            )
            return
        }
        defer { MCLocalXPCMessageRelease(request) }
        guard MCLocalXPCSessionReplyToMenuPairingCommandFailure(
            state.peer,
            request,
            cMenuPairingCommandKind(transaction.kind)
        ) == MCLocalXPCResultOK else {
            cancelAuthenticatedPeer(
                state,
                presentationError: .transportFailure
            )
            return
        }
    }

    private func expireMenuPairingCommand(
        state: PeerState,
        transaction: MacLocalXPCMenuPairingCommandTransactionGateV1.Active
    ) {
        guard admitsMenuPairingCommandCompletion(
            state: state,
            transaction: transaction
        ) else { return }
        terminateMenuPairingCommand(
            state: state,
            transaction: transaction
        )
    }

    private func terminateMenuPairingCommand(
        state: PeerState,
        transaction: MacLocalXPCMenuPairingCommandTransactionGateV1.Active
    ) {
        guard state.menuPairingCommandGate.admits(transaction) else { return }
        state.cancelPendingMenuPairingCommand()
        cancelAuthenticatedPeer(
            state,
            presentationError: .transportFailure
        )
    }

    private func admitsMenuPairingCommandCompletion(
        state: PeerState,
        transaction: MacLocalXPCMenuPairingCommandTransactionGateV1.Active
    ) -> Bool {
        listenerRunGate.admits(generation: state.listenerGeneration)
            && peerStates[state.generation] === state
            && currentPeerState === state
            && generationGate.admitsPostAuthenticationTraffic(
                generation: state.generation
            )
            && state.lifetime.menuReadinessPublished
            && state.postAuthenticationFence.admitsTraffic
            && state.menuPairingCommandGate.admits(transaction)
    }

    private func takeMenuPairingCommandRequest(
        state: PeerState,
        transaction: MacLocalXPCMenuPairingCommandTransactionGateV1.Active
    ) -> MCLocalXPCMessageRef? {
        guard let pending = state.pendingMenuPairingCommand,
              pending.transaction == transaction else { return nil }
        state.pendingMenuPairingCommand = nil
        pending.deadline?.cancel()
        pending.deadline = nil
        pending.task = nil
        return pending.takeOwnedRequest()
    }

    private func validatedMenuPairingCommandReply(
        command: MenuPairingCommand,
        result: MenuPairingCommandResult
    ) -> Data? {
        do {
            switch (command, result) {
            case (.create(let command), .created(let receipt)):
                guard receipt.correlationID == command.commandID else {
                    return nil
                }
                return try LocalMenuPairingCommandWireCodecV1
                    .encodeCreatedReceipt(receipt)
            case (.dismiss(let command), .dismissed(let receipt)):
                guard receipt.correlationID == command.commandID,
                      receipt.pairingID == command.pairingID else { return nil }
                return try LocalMenuPairingCommandWireCodecV1
                    .encodeDismissedReceipt(receipt)
            case (.resolveDecision(let command), .decision(let receipt)):
                try receipt.validate(against: command)
                return try LocalMenuPairingCommandWireCodecV1
                    .encodeDecisionReceipt(receipt)
            case (.recoverHostIdentity(let command), .recovered(let receipt)):
                try receipt.validate(against: command)
                return try LocalHostIdentityRecoveryWireCodecV1
                    .encodeReceipt(receipt)
            case (
                .acknowledgeHostIdentityRecoveryCompletion(let expected),
                .recoveryCompletionAcknowledged(let receipt)
            ):
                guard receipt == expected else { return nil }
                return try LocalHostIdentityRecoveryWireCodecV1
                    .encodeReceipt(receipt)
            case (
                .requestInteractiveControlGrantReview(let request),
                .interactiveControlGrantReview(let review)
            ):
                try review.validate(against: request)
                return try LocalMenuPairingCommandWireCodecV1
                    .encodeInteractiveControlGrantReview(review)
            case (
                .decideInteractiveControlGrant(let command),
                .interactiveControlGrantDecision(let receipt)
            ):
                try receipt.validate(against: command)
                return try LocalMenuPairingCommandWireCodecV1
                    .encodeGrantDecisionReceipt(receipt)
            case (.requestDeviceRevocationReview(let request), .deviceRevocationReview(let reply)):
                try reply.validate(against: request)
                return try LocalMenuPairingCommandWireCodecV1.encodeDeviceRevocationReviewReply(reply)
            case (.revokeDevice(let command), .deviceRevoked(let receipt)):
                try receipt.validate(against: command)
                return try LocalMenuPairingCommandWireCodecV1.encodeDeviceRevokedReceipt(receipt)
            case (.requestCapabilityGrantReview(let request), .capabilityGrantReview(let review)):
                try review.validate(against: request)
                return try LocalMenuPairingCommandWireCodecV1.encodeCapabilityGrantReview(review)
            case (.decideCapabilityGrant(let command), .capabilityGrantDecision(let receipt)):
                try receipt.validate(against: command)
                return try LocalMenuPairingCommandWireCodecV1.encodeGrantDecisionReceipt(receipt)
            default:
                return nil
            }
        } catch {
            return nil
        }
    }

    private func cMenuPairingCommandKind(
        _ kind: MacLocalXPCMenuPairingCommandKindV1
    ) -> MCLocalXPCMenuPairingCommandKind {
        switch kind {
        case .create: MCLocalXPCMenuPairingCommandCreate
        case .dismiss: MCLocalXPCMenuPairingCommandDismiss
        case .resolveDecision: MCLocalXPCMenuPairingCommandResolveDecision
        case .recoverHostIdentity:
            MCLocalXPCMenuPairingCommandRecoverHostIdentity
        case .acknowledgeHostIdentityRecoveryCompletion:
            MCLocalXPCMenuPairingCommandAcknowledgeHostIdentityRecovery
        case .requestInteractiveControlGrantReview,
                .decideInteractiveControlGrant, .requestDeviceRevocationReview, .revokeDevice,
                .requestCapabilityGrantReview, .decideCapabilityGrant:
            MCLocalXPCMenuPairingCommandDeviceAdministration
        }
    }

    private func beginRemoteAccessBootstrapOfferRead(
        state: PeerState,
        request: MCLocalXPCMessageRef
    ) -> Bool {
        guard let bootstrapHandler,
              let operation = state.bootstrapGate.beginOfferRead(
                generation: state.generation,
                permitted:
                    profile.admitsRemoteAccessBootstrap
                    && authorizesMenuMethod(.readRemoteAccessBootstrap)
                    && state.postAuthenticationFence.admitsTraffic
              ) else {
            return false
        }

        let pending = PendingBootstrapRequest(
            operation: operation,
            kind: .offer,
            request: request
        )
        state.pendingBootstrapRequest = pending
        let queue = self.queue
        let generation = state.generation
        pending.task = Task { [weak self, weak state, bootstrapHandler] in
            do {
                let offer = try await bootstrapHandler.readOffer(
                    generation: generation
                )
                queue.async { [weak self, weak state] in
                    guard let self, let state else { return }
                    self.completeRemoteAccessBootstrapOfferRead(
                        state: state,
                        operation: operation,
                        offer: offer
                    )
                }
            } catch {
                queue.async { [weak self, weak state] in
                    guard let self, let state else { return }
                    self.failRemoteAccessBootstrap(
                        state: state,
                        operation: operation
                    )
                }
            }
        }
        installRemoteAccessBootstrapDeadline(
            pending,
            state: state,
            operation: operation
        )
        return true
    }

    private func beginRemoteAccessEnable(
        state: PeerState,
        request: MCLocalXPCMessageRef,
        command: LocalRemoteAccessEnableCommandV0
    ) -> Bool {
        guard let bootstrapHandler,
              let operation = state.bootstrapGate.beginEnable(
                generation: state.generation,
                permitted:
                    profile.admitsRemoteAccessBootstrap
                    && authorizesMenuMethod(.enableRemoteAccess)
                    && state.postAuthenticationFence.admitsTraffic,
                command: command
              ) else {
            return false
        }

        let pending = PendingBootstrapRequest(
            operation: operation,
            kind: .enable(command),
            request: request
        )
        state.pendingBootstrapRequest = pending
        let queue = self.queue
        let generation = state.generation
        pending.task = Task { [weak self, weak state, bootstrapHandler] in
            do {
                let receipt = try await bootstrapHandler.enable(
                    generation: generation,
                    command: command
                )
                queue.async { [weak self, weak state] in
                    guard let self, let state else { return }
                    self.completeRemoteAccessEnable(
                        state: state,
                        operation: operation,
                        receipt: receipt
                    )
                }
            } catch {
                queue.async { [weak self, weak state] in
                    guard let self, let state else { return }
                    self.failRemoteAccessBootstrap(
                        state: state,
                        operation: operation
                    )
                }
            }
        }
        installRemoteAccessBootstrapDeadline(
            pending,
            state: state,
            operation: operation
        )
        return true
    }

    private func installRemoteAccessBootstrapDeadline(
        _ pending: PendingBootstrapRequest,
        state: PeerState,
        operation: UInt64
    ) {
        let deadline = DispatchWorkItem { [weak self, weak state] in
            guard let self, let state else { return }
            self.expireRemoteAccessBootstrap(
                state: state,
                operation: operation
            )
        }
        pending.deadline = deadline
        queue.asyncAfter(
            deadline: .now() + bootstrapTimeout,
            execute: deadline
        )
    }

    private func completeRemoteAccessBootstrapOfferRead(
        state: PeerState,
        operation: UInt64,
        offer: LocalRemoteAccessBootstrapOfferV0
    ) {
        guard admitsRemoteAccessBootstrapCompletion(
                state: state,
                operation: operation
              ),
              case .offer? = state.pendingBootstrapRequest?.kind,
              state.bootstrapGate.finishOfferRead(
                generation: state.generation,
                operation: operation,
                offer: offer
              ),
              let payload = try?
                LocalRemoteAccessBootstrapWireCodecV1.encodeOffer(offer),
              let request = takeRemoteAccessBootstrapRequest(
                state: state,
                operation: operation
              ) else {
            failRemoteAccessBootstrap(
                state: state,
                operation: operation
            )
            return
        }
        defer { MCLocalXPCMessageRelease(request) }
        let reply = payload.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress
            else { return MCLocalXPCResultConstructionFailed }
            return MCLocalXPCSessionReplyToRemoteAccessBootstrapOffer(
                state.peer,
                request,
                bytes,
                payload.count
            )
        }
        guard reply == MCLocalXPCResultOK else {
            cancelAuthenticatedPeer(
                state,
                presentationError: .transportFailure
            )
            return
        }
    }

    private func completeRemoteAccessEnable(
        state: PeerState,
        operation: UInt64,
        receipt: LocalRemoteAccessEnabledReceiptV0
    ) {
        guard admitsRemoteAccessBootstrapCompletion(
                state: state,
                operation: operation
              ),
              case .enable? = state.pendingBootstrapRequest?.kind,
              state.bootstrapGate.finishEnable(
                generation: state.generation,
                operation: operation,
                receipt: receipt
              ),
              let payload = try?
                LocalRemoteAccessBootstrapWireCodecV1
                    .encodeEnabledReceipt(receipt),
              let request = takeRemoteAccessBootstrapRequest(
                state: state,
                operation: operation
              ) else {
            failCommittedRemoteAccessEnable(
                state: state,
                operation: operation
            )
            return
        }
        defer { MCLocalXPCMessageRelease(request) }
        let reply = payload.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress
            else { return MCLocalXPCResultConstructionFailed }
            return MCLocalXPCSessionReplyToRemoteAccessEnabled(
                state.peer,
                request,
                bytes,
                payload.count
            )
        }
        guard reply == MCLocalXPCResultOK else {
            notifyUnacknowledgedRemoteAccessEnable(state)
            cancelAuthenticatedPeer(
                state,
                presentationError: .transportFailure
            )
            return
        }
        onEvent(.remoteAccessEnabled(generation: state.generation))
    }

    private func failCommittedRemoteAccessEnable(
        state: PeerState,
        operation: UInt64
    ) {
        notifyUnacknowledgedRemoteAccessEnable(state)
        failRemoteAccessBootstrap(state: state, operation: operation)
    }

    private func notifyUnacknowledgedRemoteAccessEnable(_ state: PeerState) {
        guard let bootstrapHandler else { return }
        let generation = state.generation
        Task {
            await bootstrapHandler.enabledReceiptWasNotAcknowledged(
                generation: generation
            )
        }
    }

    private func admitsRemoteAccessBootstrapCompletion(
        state: PeerState,
        operation: UInt64
    ) -> Bool {
        listenerRunGate.admits(generation: state.listenerGeneration)
            && peerStates[state.generation] === state
            && currentPeerState === state
            && state.postAuthenticationFence.admitsTraffic
            && generationGate.admitsPostAuthenticationTraffic(
                generation: state.generation
            )
            && state.pendingBootstrapRequest?.operation == operation
    }

    private func takeRemoteAccessBootstrapRequest(
        state: PeerState,
        operation: UInt64
    ) -> MCLocalXPCMessageRef? {
        guard let pending = state.pendingBootstrapRequest,
              pending.operation == operation else { return nil }
        state.pendingBootstrapRequest = nil
        pending.deadline?.cancel()
        pending.deadline = nil
        pending.task = nil
        return pending.takeOwnedRequest()
    }

    private func failRemoteAccessBootstrap(
        state: PeerState,
        operation: UInt64
    ) {
        guard admitsRemoteAccessBootstrapCompletion(
            state: state,
            operation: operation
        ) else { return }
        _ = state.bootstrapGate.fail(
            generation: state.generation,
            operation: operation
        )
        cancelAuthenticatedPeer(
            state,
            presentationError: .transportFailure
        )
    }

    private func expireRemoteAccessBootstrap(
        state: PeerState,
        operation: UInt64
    ) {
        failRemoteAccessBootstrap(state: state, operation: operation)
    }

    private func beginStatusRead(
        state: PeerState,
        request: MCLocalXPCMessageRef
    ) -> Bool {
        guard let statusReader,
              let operation = state.statusReadGate.begin(
                generation: state.generation,
                permitted:
                    profile.admitsAgentStatus
                    && authorizesMenuMethod(.readAgentStatus)
                    && state.lifetime.menuReadinessPublished
                    && state.postAuthenticationFence.admitsTraffic
              ) else {
            return false
        }

        let pending = PendingStatusRead(
            operation: operation,
            request: request
        )
        state.pendingStatusRead = pending
        let queue = self.queue
        pending.task = Task { [weak self, weak state, statusReader] in
            let result = await statusReader.readStatus()
            queue.async { [weak self, weak state] in
                guard let self, let state else { return }
                self.completeStatusRead(
                    state: state,
                    operation: operation,
                    result: result
                )
            }
        }
        let deadline = DispatchWorkItem { [weak self, weak state] in
            guard let self, let state else { return }
            self.expireStatusRead(
                state: state,
                operation: operation
            )
        }
        pending.deadline = deadline
        queue.asyncAfter(
            deadline: .now() + statusReadTimeout,
            execute: deadline
        )
        return true
    }

    private func completeStatusRead(
        state: PeerState,
        operation: UInt64,
        result: Result<LocalAgentStatusSnapshot, MacLocalXPCStatusReadErrorV1>
    ) {
        guard listenerRunGate.admits(
                generation: state.listenerGeneration
              ),
              peerStates[state.generation] === state,
              currentPeerState === state,
              state.postAuthenticationFence.admitsTraffic,
              generationGate.admitsPostAuthenticationTraffic(
                generation: state.generation
              ),
              let pending = state.pendingStatusRead,
              pending.operation == operation,
              state.statusReadGate.finish(
                generation: state.generation,
                operation: operation
              ) else {
            return
        }

        state.pendingStatusRead = nil
        pending.deadline?.cancel()
        pending.deadline = nil
        pending.task = nil
        guard let request = pending.takeOwnedRequest() else {
            cancelAuthenticatedPeer(
                state,
                presentationError: .transportFailure
            )
            return
        }
        defer { MCLocalXPCMessageRelease(request) }

        let replyResult: MCLocalXPCResult
        switch result {
        case .success(let snapshot):
            guard let payload = try? LocalAgentStatusWireCodecV1.encode(
                snapshot
            ),
                  !payload.isEmpty,
                  payload.count <= MacLocalXPCStatusWireV1.maximumPayloadBytes else {
                cancelAuthenticatedPeer(
                    state,
                    presentationError: .transportFailure
                )
                return
            }
            replyResult = payload.withUnsafeBytes { rawBuffer in
                guard let bytes = rawBuffer
                    .bindMemory(to: UInt8.self).baseAddress else {
                    return MCLocalXPCResultConstructionFailed
                }
                return MCLocalXPCSessionReplyToStatusReadSuccess(
                    state.peer,
                    request,
                    bytes,
                    payload.count
                )
            }

        case .failure(.sourceUnavailable):
            replyResult = MCLocalXPCSessionReplyToStatusReadUnavailable(
                state.peer,
                request
            )
        }
        guard replyResult == MCLocalXPCResultOK else {
            cancelAuthenticatedPeer(
                state,
                presentationError: .transportFailure
            )
            return
        }
    }

    private func expireStatusRead(
        state: PeerState,
        operation: UInt64
    ) {
        guard listenerRunGate.admits(
                generation: state.listenerGeneration
              ),
              peerStates[state.generation] === state,
              currentPeerState === state,
              state.postAuthenticationFence.admitsTraffic,
              generationGate.admitsPostAuthenticationTraffic(
                generation: state.generation
              ),
              state.statusReadGate.admits(
                generation: state.generation,
                operation: operation
              ) else {
            return
        }
        // Status is diagnostic, non-authorizing state. A slow snapshot must
        // not tear down the authenticated menu generation that independently
        // carries pairing presentation and an active Control lease. Convert
        // the bounded source delay into the existing exact unavailable reply;
        // malformed replies and an actual reply-send failure remain terminal.
        state.pendingStatusRead?.task?.cancel()
        completeStatusRead(
            state: state,
            operation: operation,
            result: .failure(.sourceUnavailable)
        )
    }

    private func expireCandidate(_ state: PeerState) {
        guard listenerRunGate.admits(
                generation: state.listenerGeneration
              ),
              peerStates[state.generation] === state,
              pendingGate.contains(generation: state.generation) else {
            return
        }
        peerStates.removeValue(forKey: state.generation)
        pendingGate.remove(generation: state.generation)
        state.handshakeDeadline = nil
        if let ownedPeer = state.takeOwnedPeer() {
            MCLocalXPCSessionCancelOwned(ownedPeer)
        }
    }

    private func syncOnQueue<T>(
        _ body: () throws -> T
    ) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try body()
        }
        return try queue.sync(execute: body)
    }
}

@available(macOS 26.0, *)
public final class MacLocalXPCClientV1:
    @unchecked Sendable,
    MacLocalXPCUpdateQuiescenceHandlingV0,
    MacLocalXPCInteractiveAdmissionPublishingV1,
    MacLocalXPCInteractiveMediaPublishingV1
{
    public typealias EventHandler = @Sendable (MacLocalXPCClientEventV1) -> Void

    private final class MenuPairingCommandCancellationMarker:
        @unchecked Sendable
    {
        private let lock = NSLock()
        private var cancelled = false

        func markCancelled() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }

        func isCancelled() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
    }

    private final class PendingMenuPairingCommand: @unchecked Sendable {
        let requestID: UUID
        let transaction: MacLocalXPCMenuPairingCommandTransactionGateV1.Active
        let continuation: CheckedContinuation<Data, any Error>
        var deadline: DispatchWorkItem?

        init(
            requestID: UUID,
            transaction: MacLocalXPCMenuPairingCommandTransactionGateV1.Active,
            continuation: CheckedContinuation<Data, any Error>
        ) {
            self.requestID = requestID
            self.transaction = transaction
            self.continuation = continuation
        }
    }

    private final class PendingUpdateQuiescenceCommand:
        @unchecked Sendable
    {
        let requestID: UUID
        let transaction:
            MacLocalXPCUpdateQuiescenceTransactionGateV0.Active
        let continuation: CheckedContinuation<Void, any Error>
        var deadline: DispatchWorkItem?

        init(
            requestID: UUID,
            transaction:
                MacLocalXPCUpdateQuiescenceTransactionGateV0.Active,
            continuation: CheckedContinuation<Void, any Error>
        ) {
            self.requestID = requestID
            self.transaction = transaction
            self.continuation = continuation
        }
    }

    private final class PendingInteractiveAdmissionPublication:
        @unchecked Sendable
    {
        let requestID: UUID
        let transaction:
            MacLocalXPCInteractiveAdmissionTransactionGateV1.Active
        let continuation: CheckedContinuation<Data, any Error>
        var deadline: DispatchWorkItem?

        init(
            requestID: UUID,
            transaction:
                MacLocalXPCInteractiveAdmissionTransactionGateV1.Active,
            continuation: CheckedContinuation<Data, any Error>
        ) {
            self.requestID = requestID
            self.transaction = transaction
            self.continuation = continuation
        }
    }

    private final class PendingInteractiveMediaPublication:
        @unchecked Sendable
    {
        let requestID: UUID
        let transaction:
            MacLocalXPCInteractiveRoleDataTransactionGateV1.Active
        let continuation: CheckedContinuation<Void, any Error>
        var deadline: DispatchWorkItem?

        init(
            requestID: UUID,
            transaction:
                MacLocalXPCInteractiveRoleDataTransactionGateV1.Active,
            continuation: CheckedContinuation<Void, any Error>
        ) {
            self.requestID = requestID
            self.transaction = transaction
            self.continuation = continuation
        }
    }

    private final class PendingIncomingInteractiveInput:
        @unchecked Sendable
    {
        let transaction:
            MacLocalXPCInteractiveRoleDataTransactionGateV1.Active
        var deadline: DispatchWorkItem?
        var task: Task<Void, Never>?
        private let requestLease:
            MacLocalXPCStatusRequestLeaseV1<MCLocalXPCMessageRef>

        init(
            transaction:
                MacLocalXPCInteractiveRoleDataTransactionGateV1.Active,
            request: MCLocalXPCMessageRef
        ) {
            self.transaction = transaction
            requestLease = MacLocalXPCStatusRequestLeaseV1(request: request)
        }

        func takeOwnedRequest() -> MCLocalXPCMessageRef? {
            requestLease.takeOwnedRequest()
        }

        func releaseOwnedRequest() {
            requestLease.releaseIfOwned()
        }
    }

    private enum IncomingInteractiveLeaseCommand: Sendable {
        case prepareInitialDesktop(
            LocalInteractiveInitialDesktopPreparationCommandV1
        )
        case install(InteractiveRuntimeInstallCommandV0)
        case renew(InteractiveRuntimeLeaseRenewalV0)
        case revoke(InteractiveRuntimeRevokeCommandV0)
        case surfaceTargets(LocalInteractiveSurfaceTargetsCommandV1)
        case surfaceResolve(LocalInteractiveSurfaceResolveCommandV1)
        case surfaceTransition(InteractiveRuntimeSurfaceTransitionCommandV0)
        case surfaceAcknowledgement(
            InteractiveRuntimeSurfaceAcknowledgementCommandV0
        )
        case surfaceFailure(LocalInteractiveSurfaceFailureCommandV1)
        case focusSnapshot(LocalInteractiveFocusSnapshotCommandV1)
        case displayCatalog(LocalInteractiveDisplayCatalogCommandV1)
        case displaySelect(LocalInteractiveDisplaySelectCommandV1)
        case nativeBackend(LocalInteractiveNativeBackendCommandV1)
        case nativeSnapshot(LocalInteractiveNativeSnapshotCommandV1)
        case webRTCOffer(LocalInteractiveWebRTCOfferCommandV1)
        case webRTCAnswer(LocalInteractiveWebRTCAnswerCommandV1)
        case webRTCClose(LocalInteractiveWebRTCCloseCommandV1)

        var kind: MacLocalXPCInteractiveLeaseCommandKindV1 {
            switch self {
            case .prepareInitialDesktop: .prepareInitialDesktop
            case .install: .install
            case .renew: .renew
            case .revoke: .revoke
            case .surfaceTargets: .surfaceTargets
            case .surfaceResolve: .surfaceResolve
            case .surfaceTransition: .surfaceTransition
            case .surfaceAcknowledgement: .surfaceAcknowledgement
            case .surfaceFailure: .surfaceFailure
            case .focusSnapshot: .focusSnapshot
            case .displayCatalog: .displayCatalog
            case .displaySelect: .displaySelect
            case .nativeBackend: .nativeBackend
            case .nativeSnapshot: .nativeSnapshot
            case .webRTCOffer: .webRTCOffer
            case .webRTCAnswer: .webRTCAnswer
            case .webRTCClose: .webRTCClose
            }
        }

        var authorizationMethod: LocalIPCMethod {
            switch self {
            case .prepareInitialDesktop: .applyInteractiveSurface
            case .install, .renew: .installInteractiveLease
            case .revoke: .revokeInteractiveLease
            case .surfaceTargets, .surfaceResolve,
                    .surfaceTransition, .surfaceAcknowledgement,
                    .surfaceFailure:
                .applyInteractiveSurface
            case .focusSnapshot:
                .applyInteractiveSurface
            case .displayCatalog, .displaySelect,
                 .nativeBackend, .nativeSnapshot, .webRTCOffer, .webRTCAnswer, .webRTCClose:
                .applyInteractiveSurface
            }
        }
    }

    private enum IncomingInteractiveLeaseResult: Sendable {
        case preparedInitialDesktop(
            LocalInteractiveInitialDesktopPreparedReceiptV1
        )
        case install(InteractiveRuntimeInstallReceiptV0)
        case renewed
        case revoked(InteractiveRuntimeRevokedReceiptV0)
        case surfaceTargets(LocalInteractiveSurfaceTargetsReceiptV1)
        case surfaceResolved(LocalInteractiveSurfaceResolvedReceiptV1)
        case surfaceTransition(InteractiveRuntimeSurfaceTransitionReceiptV0)
        case surfaceAcknowledged(
            InteractiveRuntimeSurfaceAcknowledgementReceiptV0
        )
        case surfaceFailure(LocalInteractiveSurfaceFailureReceiptV1)
        case focusSnapshot(LocalInteractiveFocusSnapshotReceiptV1)
        case displayCatalog(LocalInteractiveDisplayCatalogReceiptV1)
        case displaySelected(LocalInteractiveDisplaySelectedReceiptV1)
        case nativeBackend(LocalInteractiveNativeBackendReceiptV1)
        case nativeSnapshot(LocalInteractiveNativeSnapshotReceiptV1)
        case webRTCOffer(LocalInteractiveWebRTCOfferReceiptV1)
        case webRTCAnswered
        case webRTCClosed
    }

    private final class PendingIncomingInteractiveLeaseCommand:
        @unchecked Sendable
    {
        let transaction:
            MacLocalXPCInteractiveLeaseTransactionGateV1.Active
        let command: IncomingInteractiveLeaseCommand
        var deadline: DispatchWorkItem?
        var task: Task<Void, Never>?
        private let requestLease:
            MacLocalXPCStatusRequestLeaseV1<MCLocalXPCMessageRef>

        init(
            transaction:
                MacLocalXPCInteractiveLeaseTransactionGateV1.Active,
            command: IncomingInteractiveLeaseCommand,
            request: MCLocalXPCMessageRef
        ) {
            self.transaction = transaction
            self.command = command
            requestLease = MacLocalXPCStatusRequestLeaseV1(request: request)
        }

        func takeOwnedRequest() -> MCLocalXPCMessageRef? {
            requestLease.takeOwnedRequest()
        }

        func releaseOwnedRequest() {
            requestLease.releaseIfOwned()
        }
    }

    private let queue = DispatchQueue(
        label: "media.jenny.maccompanion.local-xpc.menu"
    )
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let onEvent: EventHandler
    private let presentationSurfaces:
        MacLocalXPCMenuPresentationReceiverSurfacesV1?
    private let interactiveLeaseHandler:
        (any MacLocalXPCInteractiveLeaseHandlingV1)?
    private let interactiveInputHandler:
        (any MacLocalXPCInteractiveInputHandlingV1)?
    private let monotonicNowNanoseconds: @Sendable () -> UInt64
    private var session: MCLocalXPCSessionRef?
    private var gate = MacLocalXPCHandshakeGateV1()
    private var menuReadinessRequested = false
    private var menuReadinessPublished = false
    private var generationGate = MacLocalXPCClientGenerationGateV1()
    private var statusReadGate = MacLocalXPCStatusReadTransactionGateV1()
    private var statusReadDeadline: DispatchWorkItem?
    private let statusReadTimeout: DispatchTimeInterval = .seconds(3)
    private var menuPairingCommandGate =
        MacLocalXPCMenuPairingCommandTransactionGateV1()
    private var pendingMenuPairingCommand: PendingMenuPairingCommand?
    private let menuPairingCommandReplyTimeout: DispatchTimeInterval =
        .seconds(5)
    private var updateQuiescenceGate =
        MacLocalXPCUpdateQuiescenceTransactionGateV0()
    private var pendingUpdateQuiescenceCommand:
        PendingUpdateQuiescenceCommand?
    private let updateQuiescenceReplyTimeout: DispatchTimeInterval =
        .seconds(5)
    private var interactiveAdmissionGate =
        MacLocalXPCInteractiveAdmissionTransactionGateV1()
    private var pendingInteractiveAdmissionPublication:
        PendingInteractiveAdmissionPublication?
    private let interactiveAdmissionReplyTimeout: DispatchTimeInterval =
        .seconds(4)
    private var interactiveLeaseGate =
        MacLocalXPCInteractiveLeaseTransactionGateV1()
    private var pendingIncomingInteractiveLeaseCommand:
        PendingIncomingInteractiveLeaseCommand?
    private let interactiveLeaseOperationTimeout: DispatchTimeInterval =
        .seconds(4)
    private var interactiveMediaGate =
        MacLocalXPCInteractiveRoleDataTransactionGateV1()
    private var pendingInteractiveMediaPublication:
        PendingInteractiveMediaPublication?
    private let interactiveMediaReplyTimeout: DispatchTimeInterval =
        .seconds(4)
    private var interactiveInputGate =
        MacLocalXPCInteractiveRoleDataTransactionGateV1()
    private var pendingIncomingInteractiveInput:
        PendingIncomingInteractiveInput?
    private let interactiveInputOperationTimeout: DispatchTimeInterval =
        .milliseconds(1_500)
    package static let menuPresentationReceiverTimeout:
        DispatchTimeInterval =
            MacLocalXPCMenuPresentationReceiverGenerationV1<
                MCLocalXPCMessageRef
            >.operationTimeout
    private var presentationGeneration: UInt64?
    private var presentationReceiver:
        MacLocalXPCMenuPresentationReceiverGenerationV1<
            MCLocalXPCMessageRef
        >?
    private var presentationRetirement:
        (token: UUID, task: Task<Void, Never>)?

    public init(onEvent: @escaping EventHandler) {
        self.onEvent = onEvent
        presentationSurfaces = nil
        interactiveLeaseHandler = nil
        interactiveInputHandler = nil
        monotonicNowNanoseconds = {
            DispatchTime.now().uptimeNanoseconds
        }
        queue.setSpecific(key: queueKey, value: 1)
    }

    #if DEBUG
    private var isolatedTestID: UUID?

    public convenience init(isolatedTestID: UUID, onEvent: @escaping EventHandler) {
        self.init(onEvent: onEvent)
        self.isolatedTestID = isolatedTestID
    }

    public convenience init(
        isolatedTestID: UUID,
        pairingReviews: any LocalPairingReviewSurfaceV0,
        hostIdentityRecovery: any LocalHostIdentityRecoverySurfaceV0,
        interactiveLeaseHandler: (any MacLocalXPCInteractiveLeaseHandlingV1)? = nil,
        interactiveInputHandler: (any MacLocalXPCInteractiveInputHandlingV1)? = nil,
        onEvent: @escaping EventHandler
    ) {
        self.init(presentationSurfaces: .init(pairingReviews: pairingReviews,
            hostIdentityRecovery: hostIdentityRecovery),
            interactiveLeaseHandler: interactiveLeaseHandler,
            interactiveInputHandler: interactiveInputHandler, onEvent: onEvent)
        self.isolatedTestID = isolatedTestID
    }
    #endif

    private var serviceName: String {
        #if DEBUG
        if let isolatedTestID {
            return MacLocalXPCIsolatedTestAddressV1.serviceName(isolatedTestID)
        }
        #endif
        return MacLocalXPCIdentityV1.serviceName
    }

    package init(
        presentationSurfaces:
            MacLocalXPCMenuPresentationReceiverSurfacesV1,
        interactiveLeaseHandler:
            (any MacLocalXPCInteractiveLeaseHandlingV1)? = nil,
        interactiveInputHandler:
            (any MacLocalXPCInteractiveInputHandlingV1)? = nil,
        monotonicNowNanoseconds: @escaping @Sendable () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds
        },
        onEvent: @escaping EventHandler
    ) {
        self.onEvent = onEvent
        self.presentationSurfaces = presentationSurfaces
        self.interactiveLeaseHandler = interactiveLeaseHandler
        self.interactiveInputHandler = interactiveInputHandler
        self.monotonicNowNanoseconds = monotonicNowNanoseconds
        queue.setSpecific(key: queueKey, value: 1)
    }

    deinit {
        cancel()
    }

    public func start() throws {
        try syncOnQueue {
            guard session == nil,
                  presentationSurfaces == nil
                    || presentationRetirement == nil else {
                throw MacLocalXPCConstructionErrorV1.alreadyStarted
            }

            var result = MCLocalXPCResultOK
            guard let requirement =
                    MCLocalXPCPeerRequirementCreateSameTeamIdentifier(
                        MacLocalXPCIdentityV1.agentSigningIdentifier,
                        &result
                    ),
                  result == MCLocalXPCResultOK else {
                throw MacLocalXPCConstructionErrorV1.peerRequirement
            }
            guard let generation = generationGate.begin() else {
                MCLocalXPCPeerRequirementRelease(requirement)
                throw MacLocalXPCConstructionErrorV1.generationExhausted
            }
            gate = MacLocalXPCHandshakeGateV1()
            menuReadinessRequested = false
            menuReadinessPublished = false
            statusReadGate.invalidateAll()
            precondition(statusReadGate.bind(generation: generation))
            _ = menuPairingCommandGate.invalidate(
                generation: menuPairingCommandGate.generation ?? 0
            )
            precondition(menuPairingCommandGate.bind(generation: generation))
            _ = updateQuiescenceGate.invalidate(
                generation: updateQuiescenceGate.generation ?? 0
            )
            precondition(updateQuiescenceGate.bind(generation: generation))
            _ = interactiveAdmissionGate.invalidate(
                generation: interactiveAdmissionGate.generation ?? 0
            )
            precondition(
                interactiveAdmissionGate.bind(generation: generation)
            )
            _ = interactiveLeaseGate.invalidate(
                generation: interactiveLeaseGate.generation ?? 0
            )
            precondition(interactiveLeaseGate.bind(generation: generation))
            _ = interactiveMediaGate.invalidate(
                generation: interactiveMediaGate.generation ?? 0
            )
            precondition(interactiveMediaGate.bind(generation: generation))
            _ = interactiveInputGate.invalidate(
                generation: interactiveInputGate.generation ?? 0
            )
            precondition(interactiveInputGate.bind(generation: generation))
            statusReadDeadline?.cancel()
            statusReadDeadline = nil
            if presentationSurfaces != nil {
                presentationGeneration = generation
            }

            guard let candidate = MCLocalXPCSessionCreateInactive(
                serviceName,
                queue,
                &result
            ), result == MCLocalXPCResultOK else {
                _ = generationGate.invalidate(generation: generation)
                discardUnactivatedPresentationGeneration(
                    generation: generation
                )
                MCLocalXPCPeerRequirementRelease(requirement)
                throw MacLocalXPCConstructionErrorV1.sessionConstruction
            }
            MCLocalXPCSessionSetPeerRequirement(candidate, requirement)
            MCLocalXPCPeerRequirementRelease(requirement)
            MCLocalXPCSessionSetCancelHandler(candidate) {
                [weak self] in
                self?.handleInvalidation(generation: generation)
            }
            if presentationSurfaces != nil {
                presentationReceiver = makePresentationReceiver(
                    generation: generation
                )
            }
            // The incoming handler is installed before activation even for the
            // inert public initializer. Unexpected Agent-to-menu traffic then
            // fails closed instead of falling through an unowned XPC surface.
            MCLocalXPCSessionSetMessageHandler(candidate) {
                [weak self] message in
                self?.handleIncomingAgentMessage(
                    generation: generation,
                    message: message
                )
            }
            guard MCLocalXPCSessionActivate(candidate)
                    == MCLocalXPCResultOK else {
                _ = generationGate.invalidate(generation: generation)
                discardUnactivatedPresentationGeneration(
                    generation: generation
                )
                MCLocalXPCSessionDisposeAfterFailedActivation(candidate)
                throw MacLocalXPCConstructionErrorV1.activation
            }
            session = candidate
            MCLocalXPCSessionSendHello(candidate) {
                [weak self] reply, error in
                let acknowledgedBuild: UInt64?
                if let reply {
                    var build: UInt64 = 0
                    acknowledgedBuild =
                        MCLocalXPCMessageGetExactHelloAcknowledgementBuild(
                            reply,
                            &build
                        ) ? build : nil
                } else {
                    acknowledgedBuild = nil
                }
                self?.handleHelloReply(
                    generation: generation,
                    acknowledgedBuild: acknowledgedBuild,
                    hadError: error
                )
            }
        }
    }

    /// Requests menu-process readiness only after the authenticated-Agent event.
    /// The request is queued so it is safe to trigger from an event callback.
    /// A premature, duplicate, malformed, or rejected exchange invalidates the
    /// connection rather than manufacturing readiness.
    public func publishMenuReady() {
        queue.async { [weak self] in
            self?.sendMenuReady()
        }
    }

    /// Reads only the bounded content-free snapshot after menu readiness.
    /// Sequential reads are allowed; a concurrent or premature read fails the
    /// exact transport generation closed.
    public func readAgentStatus() {
        queue.async { [weak self] in
            self?.sendStatusRead()
        }
    }

    public func closeNetworkAdmissionForUpdate() async throws {
        try await sendUpdateQuiescenceCommand(
            .closeNetworkAdmission,
            authorizationMethod: .closeNetworkAdmissionForUpdate
        )
    }

    public func drainNetworkConnectionsForUpdate() async throws {
        try await sendUpdateQuiescenceCommand(
            .drainNetworkConnections,
            authorizationMethod: .drainNetworkConnectionsForUpdate
        )
    }

    public func reopenNetworkAdmissionAfterUpdateFailure() async throws {
        try await sendUpdateQuiescenceCommand(
            .reopenNetworkAdmission,
            authorizationMethod: .reopenNetworkAdmissionAfterUpdateFailure
        )
    }

    public func createPairingSession(
        _ command: LocalPairingSessionCreateCommandV0
    ) async throws -> LocalPairingSessionCreatedReceiptV0 {
        let payload: Data
        do {
            payload = try LocalMenuPairingCommandWireCodecV1
                .encodeCreateCommand(command)
        } catch {
            throw MacLocalXPCMenuPairingCommandErrorV1
                .malformedOrTransportError
        }
        let reply = try await sendMenuPairingCommand(
            kind: .create,
            authorizationMethod: .createPairingSession,
            payload: payload
        )
        do {
            let receipt = try LocalMenuPairingCommandWireCodecV1
                .decodeCreatedReceipt(reply)
            guard receipt.correlationID == command.commandID else {
                throw MacLocalXPCMenuPairingCommandErrorV1
                    .malformedOrTransportError
            }
            return receipt
        } catch {
            invalidateCurrentGenerationAfterMalformedCommandReply()
            throw MacLocalXPCMenuPairingCommandErrorV1
                .malformedOrTransportError
        }
    }

    public func dismissPairingSession(
        _ command: LocalPairingSessionDismissCommandV0
    ) async throws -> LocalPairingSessionDismissedReceiptV0 {
        let payload: Data
        do {
            payload = try LocalMenuPairingCommandWireCodecV1
                .encodeDismissCommand(command)
        } catch {
            throw MacLocalXPCMenuPairingCommandErrorV1
                .malformedOrTransportError
        }
        let reply = try await sendMenuPairingCommand(
            kind: .dismiss,
            authorizationMethod: .dismissPairingSession,
            payload: payload
        )
        do {
            let receipt = try LocalMenuPairingCommandWireCodecV1
                .decodeDismissedReceipt(reply)
            guard receipt.correlationID == command.commandID,
                  receipt.pairingID == command.pairingID else {
                throw MacLocalXPCMenuPairingCommandErrorV1
                    .malformedOrTransportError
            }
            return receipt
        } catch {
            invalidateCurrentGenerationAfterMalformedCommandReply()
            throw MacLocalXPCMenuPairingCommandErrorV1
                .malformedOrTransportError
        }
    }

    public func resolveLocalApproval(
        _ command: LocalPairingDecisionCommandV0
    ) async throws -> LocalPairingDecisionReceiptV0 {
        let payload: Data
        do {
            payload = try LocalMenuPairingCommandWireCodecV1
                .encodeDecisionCommand(command)
        } catch {
            throw MacLocalXPCMenuPairingCommandErrorV1
                .malformedOrTransportError
        }
        let reply = try await sendMenuPairingCommand(
            kind: .resolveDecision,
            authorizationMethod: .resolveLocalApproval,
            payload: payload
        )
        do {
            let receipt = try LocalMenuPairingCommandWireCodecV1
                .decodeDecisionReceipt(reply)
            try receipt.validate(against: command)
            return receipt
        } catch {
            invalidateCurrentGenerationAfterMalformedCommandReply()
            throw MacLocalXPCMenuPairingCommandErrorV1
                .malformedOrTransportError
        }
    }

    public func makeCapabilityGrantReview(_ request: LocalCapabilityGrantReviewRequestV1) async throws -> LocalCapabilityGrantReviewV1 {
        let payload: Data
        do { payload = try LocalMenuPairingCommandWireCodecV1.encodeCapabilityGrantReviewRequest(request) }
        catch { throw MacLocalXPCMenuPairingCommandErrorV1.malformedOrTransportError }
        let data = try await sendMenuPairingCommand(kind: .requestCapabilityGrantReview,
            authorizationMethod: .administerDevices, payload: payload)
        do {
            let review = try LocalMenuPairingCommandWireCodecV1.decodeCapabilityGrantReview(data)
            try review.validate(against: request)
            return review
        } catch {
            invalidateCurrentGenerationAfterMalformedCommandReply()
            throw MacLocalXPCMenuPairingCommandErrorV1.malformedOrTransportError
        }
    }

    public func decideCapabilityGrant(_ command: LocalGrantDecisionCommandV0) async throws -> LocalGrantDecisionReceiptV0 {
        let payload: Data
        do { payload = try LocalMenuPairingCommandWireCodecV1.encodeCapabilityGrantDecision(.init(decision: command)) }
        catch { throw MacLocalXPCMenuPairingCommandErrorV1.malformedOrTransportError }
        let data = try await sendMenuPairingCommand(kind: .decideCapabilityGrant,
            authorizationMethod: .decideGrantExpansion, payload: payload)
        do {
            let receipt = try LocalMenuPairingCommandWireCodecV1.decodeGrantDecisionReceipt(data)
            try receipt.validate(against: command)
            return receipt
        } catch {
            invalidateCurrentGenerationAfterMalformedCommandReply()
            throw MacLocalXPCMenuPairingCommandErrorV1.malformedOrTransportError
        }
    }

    public func makeDeviceRevocationReview(_ request: LocalDeviceRevocationReviewRequestV1) async throws -> LocalDeviceRevocationReviewReplyV1 {
        let payload: Data
        do { payload = try LocalMenuPairingCommandWireCodecV1.encodeDeviceRevocationReviewRequest(request) }
        catch { throw MacLocalXPCMenuPairingCommandErrorV1.malformedOrTransportError }
        let data = try await sendMenuPairingCommand(kind: .requestDeviceRevocationReview,
            authorizationMethod: .administerDevices, payload: payload)
        do {
            let reply = try LocalMenuPairingCommandWireCodecV1.decodeDeviceRevocationReviewReply(data)
            try reply.validate(against: request)
            return reply
        } catch {
            invalidateCurrentGenerationAfterMalformedCommandReply()
            throw MacLocalXPCMenuPairingCommandErrorV1.malformedOrTransportError
        }
    }

    public func revokeDevice(_ command: LocalDeviceRevocationCommandV0) async throws -> LocalDeviceRevokedReceiptV0 {
        let payload: Data
        do { payload = try LocalMenuPairingCommandWireCodecV1.encodeDeviceRevocationCommand(command) }
        catch { throw MacLocalXPCMenuPairingCommandErrorV1.malformedOrTransportError }
        let data = try await sendMenuPairingCommand(kind: .revokeDevice,
            authorizationMethod: .administerDevices, payload: payload)
        do {
            let receipt = try LocalMenuPairingCommandWireCodecV1.decodeDeviceRevokedReceipt(data)
            try receipt.validate(against: command)
            return receipt
        } catch {
            invalidateCurrentGenerationAfterMalformedCommandReply()
            throw MacLocalXPCMenuPairingCommandErrorV1.malformedOrTransportError
        }
    }

    public func makeInteractiveControlGrantReview(
        _ request: LocalInteractiveControlGrantReviewRequestV0
    ) async throws -> LocalInteractiveControlGrantReviewV0 {
        let payload: Data
        do {
            payload = try LocalMenuPairingCommandWireCodecV1
                .encodeInteractiveControlGrantReviewRequest(request)
        } catch {
            throw MacLocalXPCMenuPairingCommandErrorV1
                .malformedOrTransportError
        }
        let reply = try await sendMenuPairingCommand(
            kind: .requestInteractiveControlGrantReview,
            authorizationMethod: .administerDevices,
            payload: payload
        )
        do {
            let review = try LocalMenuPairingCommandWireCodecV1
                .decodeInteractiveControlGrantReview(reply)
            try review.validate(against: request)
            return review
        } catch {
            invalidateCurrentGenerationAfterMalformedCommandReply()
            throw MacLocalXPCMenuPairingCommandErrorV1
                .malformedOrTransportError
        }
    }

    public func decideInteractiveControlGrant(
        _ command: LocalGrantDecisionCommandV0
    ) async throws -> LocalGrantDecisionReceiptV0 {
        let payload: Data
        do {
            payload = try LocalMenuPairingCommandWireCodecV1
                .encodeGrantDecisionCommand(command)
        } catch {
            throw MacLocalXPCMenuPairingCommandErrorV1
                .malformedOrTransportError
        }
        let reply = try await sendMenuPairingCommand(
            kind: .decideInteractiveControlGrant,
            authorizationMethod: .decideGrantExpansion,
            payload: payload
        )
        do {
            let receipt = try LocalMenuPairingCommandWireCodecV1
                .decodeGrantDecisionReceipt(reply)
            try receipt.validate(against: command)
            return receipt
        } catch {
            invalidateCurrentGenerationAfterMalformedCommandReply()
            throw MacLocalXPCMenuPairingCommandErrorV1
                .malformedOrTransportError
        }
    }

    public func recoverHostIdentity(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) async throws -> LocalHostIdentityRecoveredReceiptV0 {
        let payload: Data
        do {
            payload = try LocalHostIdentityRecoveryWireCodecV1
                .encodeCommand(command)
        } catch {
            throw MacLocalXPCMenuPairingCommandErrorV1
                .malformedOrTransportError
        }
        let reply = try await sendMenuPairingCommand(
            kind: .recoverHostIdentity,
            authorizationMethod: .recoverHostIdentity,
            payload: payload
        )
        do {
            let receipt = try LocalHostIdentityRecoveryWireCodecV1
                .decodeReceipt(reply)
            try receipt.validate(against: command)
            let acknowledgementPayload = try
                LocalHostIdentityRecoveryWireCodecV1.encodeReceipt(receipt)
            let acknowledgementReply = try await sendMenuPairingCommand(
                kind: .acknowledgeHostIdentityRecoveryCompletion,
                authorizationMethod:
                    .acknowledgeHostIdentityRecoveryCompletion,
                payload: acknowledgementPayload
            )
            let acknowledged = try LocalHostIdentityRecoveryWireCodecV1
                .decodeReceipt(acknowledgementReply)
            guard acknowledged == receipt else {
                throw MacLocalXPCMenuPairingCommandErrorV1
                    .malformedOrTransportError
            }
            return receipt
        } catch {
            invalidateCurrentGenerationAfterMalformedCommandReply()
            throw MacLocalXPCMenuPairingCommandErrorV1
                .malformedOrTransportError
        }
    }

    public func publishInteractiveAdmission(
        _ publication: LocalInteractiveAdmissionPublicationV1
    ) async throws -> LocalInteractiveAdmissionPublishedReceiptV1 {
        let payload: Data
        do {
            payload = try LocalInteractiveAdmissionWireCodecV1
                .encodePublication(publication)
        } catch {
            throw MacLocalXPCInteractiveAdmissionErrorV1
                .malformedOrTransportError
        }
        let reply = try await sendInteractiveAdmissionPublication(
            payload: payload
        )
        do {
            let receipt = try LocalInteractiveAdmissionWireCodecV1
                .decodeReceipt(reply)
            try receipt.validate(against: publication)
            return receipt
        } catch {
            invalidateCurrentGenerationAfterMalformedAdmissionReply()
            throw MacLocalXPCInteractiveAdmissionErrorV1
                .malformedOrTransportError
        }
    }

    public func publishInteractiveMedia(
        header: MediaRecordHeader,
        payload: Data
    ) async throws {
        guard header.encode().count == MediaRecordHeader.byteCount,
              payload.count == Int(header.payloadLength),
              payload.count <= Int(
                MCLocalXPCMaximumInteractiveMediaPayloadBytes
              ) else {
            throw MacLocalXPCInteractiveRoleDataErrorV1
                .malformedOrTransportError
        }
        let requestID = UUID()
        let marker = MenuPairingCommandCancellationMarker()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                queue.async { [weak self] in
                    guard let self else {
                        continuation.resume(throwing:
                            MacLocalXPCInteractiveRoleDataErrorV1.unavailable
                        )
                        return
                    }
                    self.admitInteractiveMediaPublication(
                        requestID: requestID,
                        header: header.encode(),
                        payload: payload,
                        cancellationMarker: marker,
                        continuation: continuation
                    )
                }
            }
        } onCancel: { [weak self] in
            marker.markCancelled()
            self?.queue.async { [weak self] in
                self?.cancelInteractiveMediaPublication(
                    requestID: requestID
                )
            }
        }
    }

    private func admitInteractiveMediaPublication(
        requestID: UUID,
        header: Data,
        payload: Data,
        cancellationMarker: MenuPairingCommandCancellationMarker,
        continuation: CheckedContinuation<Void, any Error>
    ) {
        guard !cancellationMarker.isCancelled() else {
            continuation.resume(throwing: CancellationError())
            return
        }
        guard let generation = generationGate.currentGeneration,
              generationGate.admitsCallback(generation: generation),
              let session,
              gate.state == .authenticated,
              menuReadinessPublished,
              authorizesMenuCommandMethod(.publishInteractiveMedia),
              let transaction = interactiveMediaGate.begin(
                generation: generation,
                permitted: true
              ) else {
            continuation.resume(throwing:
                MacLocalXPCInteractiveRoleDataErrorV1.unavailable
            )
            return
        }
        let pending = PendingInteractiveMediaPublication(
            requestID: requestID,
            transaction: transaction,
            continuation: continuation
        )
        pendingInteractiveMediaPublication = pending
        let result = header.withUnsafeBytes { headerRaw in
            guard let headerBytes = headerRaw.bindMemory(
                to: UInt8.self
            ).baseAddress else { return MCLocalXPCResultConstructionFailed }
            return payload.withUnsafeBytes { payloadRaw in
                MCLocalXPCSessionSendInteractiveMediaPublication(
                    session,
                    headerBytes,
                    header.count,
                    payloadRaw.bindMemory(to: UInt8.self).baseAddress,
                    payload.count
                ) { [weak self] malformed in
                    self?.queue.async { [weak self] in
                        self?.handleInteractiveMediaReply(
                            generation: generation,
                            requestID: requestID,
                            transaction: transaction,
                            malformedOrTransportError: malformed
                        )
                    }
                }
            }
        }
        guard result == MCLocalXPCResultOK else {
            _ = interactiveMediaGate.finish(transaction)
            pendingInteractiveMediaPublication = nil
            continuation.resume(throwing:
                MacLocalXPCInteractiveRoleDataErrorV1
                    .malformedOrTransportError
            )
            invalidateOwnedSession(generation: generation)
            return
        }
        let deadline = DispatchWorkItem { [weak self] in
            self?.expireInteractiveMediaPublication(
                generation: generation,
                requestID: requestID,
                transaction: transaction
            )
        }
        pending.deadline = deadline
        queue.asyncAfter(
            deadline: .now() + interactiveMediaReplyTimeout,
            execute: deadline
        )
    }

    private func handleInteractiveMediaReply(
        generation: UInt64,
        requestID: UUID,
        transaction: MacLocalXPCInteractiveRoleDataTransactionGateV1.Active,
        malformedOrTransportError: Bool
    ) {
        guard generationGate.admitsCallback(generation: generation),
              let pending = pendingInteractiveMediaPublication,
              pending.requestID == requestID,
              pending.transaction == transaction,
              interactiveMediaGate.finish(transaction) else { return }
        pendingInteractiveMediaPublication = nil
        pending.deadline?.cancel()
        pending.deadline = nil
        guard !malformedOrTransportError else {
            pending.continuation.resume(throwing:
                MacLocalXPCInteractiveRoleDataErrorV1
                    .malformedOrTransportError
            )
            invalidateOwnedSession(generation: generation)
            return
        }
        pending.continuation.resume()
    }

    private func expireInteractiveMediaPublication(
        generation: UInt64,
        requestID: UUID,
        transaction: MacLocalXPCInteractiveRoleDataTransactionGateV1.Active
    ) {
        guard generationGate.admitsCallback(generation: generation),
              let pending = pendingInteractiveMediaPublication,
              pending.requestID == requestID,
              interactiveMediaGate.finish(transaction) else { return }
        pendingInteractiveMediaPublication = nil
        pending.deadline = nil
        pending.continuation.resume(throwing:
            MacLocalXPCInteractiveRoleDataErrorV1.replyTimedOut
        )
        invalidateOwnedSession(generation: generation)
    }

    private func cancelInteractiveMediaPublication(requestID: UUID) {
        guard let generation = generationGate.currentGeneration,
              let pending = pendingInteractiveMediaPublication,
              pending.requestID == requestID,
              interactiveMediaGate.finish(pending.transaction) else {
            return
        }
        pendingInteractiveMediaPublication = nil
        pending.deadline?.cancel()
        pending.deadline = nil
        pending.continuation.resume(throwing:
            MacLocalXPCInteractiveRoleDataErrorV1.cancelledAfterSend
        )
        invalidateOwnedSession(generation: generation)
    }

    public func cancel() {
        syncOnQueue {
            guard let session,
                  let generation = generationGate.currentGeneration else {
                return
            }
            self.session = nil
            _ = generationGate.invalidate(generation: generation)
            gate.invalidate()
            menuReadinessRequested = false
            menuReadinessPublished = false
            _ = statusReadGate.invalidate(generation: generation)
            statusReadDeadline?.cancel()
            statusReadDeadline = nil
            finishPendingMenuPairingCommand(
                generation: generation,
                error: .unavailable
            )
            finishPendingInteractiveAdmissionPublication(
                generation: generation,
                error: .unavailable
            )
            finishPendingInteractiveMediaPublication(
                generation: generation,
                error: .unavailable
            )
            invalidateIncomingInteractiveLease(
                generation: generation,
                notifyRuntime: true
            )
            invalidateIncomingInteractiveInput(generation: generation)
            retirePresentationReceiver(generation: generation)
            MCLocalXPCSessionCancelOwned(session)
        }
    }

    /// Initiates cancellation and returns only after any possibly retained
    /// presentation from that generation has been withdrawn by exact ID.
    package func finishMenuPresentationReceiver() async {
        cancel()
        let task = syncOnQueue { presentationRetirement?.task }
        await task?.value
    }

    private func sendInteractiveAdmissionPublication(
        payload: Data
    ) async throws -> Data {
        let requestID = UUID()
        let marker = MenuPairingCommandCancellationMarker()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [weak self] in
                    guard let self else {
                        continuation.resume(
                            throwing:
                                MacLocalXPCInteractiveAdmissionErrorV1
                                    .unavailable
                        )
                        return
                    }
                    self.admitInteractiveAdmissionPublication(
                        requestID: requestID,
                        payload: payload,
                        cancellationMarker: marker,
                        continuation: continuation
                    )
                }
            }
        } onCancel: { [weak self] in
            marker.markCancelled()
            self?.queue.async { [weak self] in
                self?.cancelInteractiveAdmissionPublication(
                    requestID: requestID
                )
            }
        }
    }

    private func admitInteractiveAdmissionPublication(
        requestID: UUID,
        payload: Data,
        cancellationMarker: MenuPairingCommandCancellationMarker,
        continuation: CheckedContinuation<Data, any Error>
    ) {
        guard !cancellationMarker.isCancelled() else {
            continuation.resume(throwing: CancellationError())
            return
        }
        guard let generation = generationGate.currentGeneration,
              let session,
              gate.state == .authenticated,
              menuReadinessPublished,
              payload.count > 0,
              payload.count <=
                LocalInteractiveAdmissionWireCodecV1.maximumEncodedBytes,
              authorizesMenuCommandMethod(.publishInteractiveState),
              let transaction = interactiveAdmissionGate.begin(
                generation: generation,
                permitted: true
              ) else {
            continuation.resume(
                throwing:
                    MacLocalXPCInteractiveAdmissionErrorV1.unavailable
            )
            return
        }

        let pending = PendingInteractiveAdmissionPublication(
            requestID: requestID,
            transaction: transaction,
            continuation: continuation
        )
        pendingInteractiveAdmissionPublication = pending
        let sendResult = payload.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress
            else { return MCLocalXPCResultConstructionFailed }
            return MCLocalXPCSessionSendInteractiveAdmissionPublication(
                session,
                bytes,
                payload.count
            ) { [weak self] bytes, length, malformed in
                let copiedPayload = bytes.map {
                    Data(bytes: $0, count: length)
                }
                self?.queue.async { [weak self] in
                    self?.handleInteractiveAdmissionReply(
                        generation: generation,
                        requestID: requestID,
                        transaction: transaction,
                        payload: copiedPayload,
                        malformedOrTransportError: malformed
                    )
                }
            }
        }
        guard sendResult == MCLocalXPCResultOK else {
            _ = interactiveAdmissionGate.finish(transaction)
            pendingInteractiveAdmissionPublication = nil
            continuation.resume(
                throwing: MacLocalXPCInteractiveAdmissionErrorV1
                    .malformedOrTransportError
            )
            invalidateOwnedSession(generation: generation)
            return
        }

        let deadline = DispatchWorkItem { [weak self] in
            self?.expireInteractiveAdmissionPublication(
                generation: generation,
                requestID: requestID,
                transaction: transaction
            )
        }
        pending.deadline = deadline
        queue.asyncAfter(
            deadline: .now() + interactiveAdmissionReplyTimeout,
            execute: deadline
        )
    }

    private func handleInteractiveAdmissionReply(
        generation: UInt64,
        requestID: UUID,
        transaction:
            MacLocalXPCInteractiveAdmissionTransactionGateV1.Active,
        payload: Data?,
        malformedOrTransportError: Bool
    ) {
        guard generationGate.admitsCallback(generation: generation),
              let pending = pendingInteractiveAdmissionPublication,
              pending.requestID == requestID,
              pending.transaction == transaction,
              interactiveAdmissionGate.finish(transaction) else { return }
        pendingInteractiveAdmissionPublication = nil
        pending.deadline?.cancel()
        pending.deadline = nil
        guard !malformedOrTransportError,
              let payload,
              !payload.isEmpty,
              payload.count <=
                LocalInteractiveAdmissionWireCodecV1.maximumEncodedBytes else {
            pending.continuation.resume(
                throwing: MacLocalXPCInteractiveAdmissionErrorV1
                    .malformedOrTransportError
            )
            invalidateOwnedSession(generation: generation)
            return
        }
        pending.continuation.resume(returning: payload)
    }

    private func expireInteractiveAdmissionPublication(
        generation: UInt64,
        requestID: UUID,
        transaction:
            MacLocalXPCInteractiveAdmissionTransactionGateV1.Active
    ) {
        guard generationGate.admitsCallback(generation: generation),
              let pending = pendingInteractiveAdmissionPublication,
              pending.requestID == requestID,
              pending.transaction == transaction,
              interactiveAdmissionGate.finish(transaction) else { return }
        pendingInteractiveAdmissionPublication = nil
        pending.deadline = nil
        pending.continuation.resume(
            throwing: MacLocalXPCInteractiveAdmissionErrorV1.replyTimedOut
        )
        invalidateOwnedSession(generation: generation)
    }

    private func cancelInteractiveAdmissionPublication(requestID: UUID) {
        guard let generation = generationGate.currentGeneration,
              let pending = pendingInteractiveAdmissionPublication,
              pending.requestID == requestID,
              interactiveAdmissionGate.finish(pending.transaction) else {
            return
        }
        pendingInteractiveAdmissionPublication = nil
        pending.deadline?.cancel()
        pending.deadline = nil
        pending.continuation.resume(
            throwing:
                MacLocalXPCInteractiveAdmissionErrorV1.cancelledAfterSend
        )
        invalidateOwnedSession(generation: generation)
    }

    private func finishPendingInteractiveAdmissionPublication(
        generation: UInt64,
        error: MacLocalXPCInteractiveAdmissionErrorV1
    ) {
        _ = interactiveAdmissionGate.invalidate(generation: generation)
        guard let pending = pendingInteractiveAdmissionPublication else {
            return
        }
        pendingInteractiveAdmissionPublication = nil
        pending.deadline?.cancel()
        pending.deadline = nil
        pending.continuation.resume(throwing: error)
    }

    private func finishPendingInteractiveMediaPublication(
        generation: UInt64,
        error: MacLocalXPCInteractiveRoleDataErrorV1
    ) {
        _ = interactiveMediaGate.invalidate(generation: generation)
        guard let pending = pendingInteractiveMediaPublication else { return }
        pendingInteractiveMediaPublication = nil
        pending.deadline?.cancel()
        pending.deadline = nil
        pending.continuation.resume(throwing: error)
    }

    private func invalidateCurrentGenerationAfterMalformedAdmissionReply() {
        queue.async { [weak self] in
            guard let self,
                  let generation = generationGate.currentGeneration else {
                return
            }
            self.invalidateOwnedSession(generation: generation)
        }
    }

    private func sendMenuPairingCommand(
        kind: MacLocalXPCMenuPairingCommandKindV1,
        authorizationMethod: LocalIPCMethod,
        payload: Data
    ) async throws -> Data {
        let requestID = UUID()
        let marker = MenuPairingCommandCancellationMarker()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [weak self] in
                    guard let self else {
                        continuation.resume(
                            throwing:
                                MacLocalXPCMenuPairingCommandErrorV1
                                    .unavailable
                        )
                        return
                    }
                    self.admitMenuPairingCommand(
                        requestID: requestID,
                        kind: kind,
                        authorizationMethod: authorizationMethod,
                        payload: payload,
                        cancellationMarker: marker,
                        continuation: continuation
                    )
                }
            }
        } onCancel: { [weak self] in
            marker.markCancelled()
            self?.queue.async { [weak self] in
                self?.cancelMenuPairingCommand(requestID: requestID)
            }
        }
    }

    private func sendUpdateQuiescenceCommand(
        _ command: MacLocalXPCUpdateQuiescenceCommandV0,
        authorizationMethod: LocalIPCMethod
    ) async throws {
        let requestID = UUID()
        let marker = MenuPairingCommandCancellationMarker()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                queue.async { [weak self] in
                    guard let self else {
                        continuation.resume(
                            throwing:
                                MacLocalXPCUpdateQuiescenceErrorV0.unavailable
                        )
                        return
                    }
                    self.admitUpdateQuiescenceCommand(
                        requestID: requestID,
                        command: command,
                        authorizationMethod: authorizationMethod,
                        cancellationMarker: marker,
                        continuation: continuation
                    )
                }
            }
        } onCancel: { [weak self] in
            marker.markCancelled()
            self?.queue.async { [weak self] in
                self?.cancelUpdateQuiescenceCommand(requestID: requestID)
            }
        }
    }

    private func admitUpdateQuiescenceCommand(
        requestID: UUID,
        command: MacLocalXPCUpdateQuiescenceCommandV0,
        authorizationMethod: LocalIPCMethod,
        cancellationMarker: MenuPairingCommandCancellationMarker,
        continuation: CheckedContinuation<Void, any Error>
    ) {
        guard !cancellationMarker.isCancelled() else {
            continuation.resume(throwing: CancellationError())
            return
        }
        guard let generation = generationGate.currentGeneration,
              let session,
              gate.state == .authenticated,
              menuReadinessPublished,
              authorizesMenuCommandMethod(authorizationMethod),
              let transaction = updateQuiescenceGate.begin(
                generation: generation,
                command: command,
                permitted: true
              ) else {
            continuation.resume(
                throwing: MacLocalXPCUpdateQuiescenceErrorV0.unavailable
            )
            return
        }

        let pending = PendingUpdateQuiescenceCommand(
            requestID: requestID,
            transaction: transaction,
            continuation: continuation
        )
        pendingUpdateQuiescenceCommand = pending
        let sendResult = MCLocalXPCSessionSendUpdateQuiescenceCommand(
            session,
            cUpdateQuiescenceCommand(command)
        ) { [weak self] failed, malformed in
            self?.queue.async { [weak self] in
                self?.handleUpdateQuiescenceReply(
                    generation: generation,
                    requestID: requestID,
                    transaction: transaction,
                    commandFailed: failed,
                    malformedOrTransportError: malformed
                )
            }
        }
        guard sendResult == MCLocalXPCResultOK else {
            _ = updateQuiescenceGate.finish(transaction)
            pendingUpdateQuiescenceCommand = nil
            continuation.resume(
                throwing: MacLocalXPCUpdateQuiescenceErrorV0
                    .malformedOrTransportError
            )
            invalidateOwnedSession(generation: generation)
            return
        }

        let deadline = DispatchWorkItem { [weak self] in
            self?.expireUpdateQuiescenceCommand(
                generation: generation,
                requestID: requestID,
                transaction: transaction
            )
        }
        pending.deadline = deadline
        queue.asyncAfter(
            deadline: .now() + updateQuiescenceReplyTimeout,
            execute: deadline
        )
    }

    private func handleUpdateQuiescenceReply(
        generation: UInt64,
        requestID: UUID,
        transaction: MacLocalXPCUpdateQuiescenceTransactionGateV0.Active,
        commandFailed: Bool,
        malformedOrTransportError: Bool
    ) {
        guard generationGate.admitsCallback(generation: generation),
              let pending = pendingUpdateQuiescenceCommand,
              pending.requestID == requestID,
              pending.transaction == transaction,
              updateQuiescenceGate.finish(transaction) else { return }
        pendingUpdateQuiescenceCommand = nil
        pending.deadline?.cancel()
        pending.deadline = nil
        if malformedOrTransportError {
            pending.continuation.resume(
                throwing: MacLocalXPCUpdateQuiescenceErrorV0
                    .malformedOrTransportError
            )
            invalidateOwnedSession(generation: generation)
        } else if commandFailed {
            pending.continuation.resume(
                throwing: MacLocalXPCUpdateQuiescenceErrorV0.commandFailed
            )
        } else {
            pending.continuation.resume()
        }
    }

    private func expireUpdateQuiescenceCommand(
        generation: UInt64,
        requestID: UUID,
        transaction: MacLocalXPCUpdateQuiescenceTransactionGateV0.Active
    ) {
        guard generationGate.admitsCallback(generation: generation),
              let pending = pendingUpdateQuiescenceCommand,
              pending.requestID == requestID,
              pending.transaction == transaction,
              updateQuiescenceGate.finish(transaction) else { return }
        pendingUpdateQuiescenceCommand = nil
        pending.deadline = nil
        pending.continuation.resume(
            throwing: MacLocalXPCUpdateQuiescenceErrorV0.replyTimedOut
        )
        invalidateOwnedSession(generation: generation)
    }

    private func cancelUpdateQuiescenceCommand(requestID: UUID) {
        guard let generation = generationGate.currentGeneration,
              let pending = pendingUpdateQuiescenceCommand,
              pending.requestID == requestID,
              updateQuiescenceGate.finish(pending.transaction) else { return }
        pendingUpdateQuiescenceCommand = nil
        pending.deadline?.cancel()
        pending.deadline = nil
        pending.continuation.resume(
            throwing:
                MacLocalXPCUpdateQuiescenceErrorV0.cancelledAfterSend
        )
        invalidateOwnedSession(generation: generation)
    }

    private func finishPendingUpdateQuiescenceCommand(
        generation: UInt64,
        error: MacLocalXPCUpdateQuiescenceErrorV0
    ) {
        _ = updateQuiescenceGate.invalidate(generation: generation)
        guard let pending = pendingUpdateQuiescenceCommand else { return }
        pendingUpdateQuiescenceCommand = nil
        pending.deadline?.cancel()
        pending.deadline = nil
        pending.continuation.resume(throwing: error)
    }

    private func admitMenuPairingCommand(
        requestID: UUID,
        kind: MacLocalXPCMenuPairingCommandKindV1,
        authorizationMethod: LocalIPCMethod,
        payload: Data,
        cancellationMarker: MenuPairingCommandCancellationMarker,
        continuation: CheckedContinuation<Data, any Error>
    ) {
        guard !cancellationMarker.isCancelled() else {
            continuation.resume(throwing: CancellationError())
            return
        }
        guard let generation = generationGate.currentGeneration,
              let session,
              gate.state == .authenticated,
              menuReadinessPublished,
              payload.count > 0,
              payload.count <=
                LocalMenuPairingCommandWireCodecV1.maximumEncodedBytes,
              authorizesMenuCommandMethod(authorizationMethod),
              let transaction = menuPairingCommandGate.begin(
                generation: generation,
                kind: kind,
                permitted: true
              ) else {
            continuation.resume(
                throwing: MacLocalXPCMenuPairingCommandErrorV1.unavailable
            )
            return
        }

        let pending = PendingMenuPairingCommand(
            requestID: requestID,
            transaction: transaction,
            continuation: continuation
        )
        pendingMenuPairingCommand = pending
        let cKind = cMenuPairingCommandKind(kind)
        let sendResult = payload.withUnsafeBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress
            else { return MCLocalXPCResultConstructionFailed }
            return MCLocalXPCSessionSendMenuPairingCommand(
                session,
                cKind,
                bytes,
                payload.count
            ) { [weak self] bytes, length, failed, malformed in
                let copiedPayload = bytes.map {
                    Data(bytes: $0, count: length)
                }
                self?.queue.async { [weak self] in
                    self?.handleMenuPairingCommandReply(
                        generation: generation,
                        requestID: requestID,
                        transaction: transaction,
                        payload: copiedPayload,
                        commandFailed: failed,
                        malformedOrTransportError: malformed
                    )
                }
            }
        }
        guard sendResult == MCLocalXPCResultOK else {
            _ = menuPairingCommandGate.finish(transaction)
            pendingMenuPairingCommand = nil
            continuation.resume(
                throwing: MacLocalXPCMenuPairingCommandErrorV1
                    .malformedOrTransportError
            )
            invalidateOwnedSession(generation: generation)
            return
        }

        let deadline = DispatchWorkItem { [weak self] in
            self?.expireMenuPairingCommand(
                generation: generation,
                requestID: requestID,
                transaction: transaction
            )
        }
        pending.deadline = deadline
        queue.asyncAfter(
            deadline: .now() + menuPairingCommandReplyTimeout,
            execute: deadline
        )
    }

    private func handleMenuPairingCommandReply(
        generation: UInt64,
        requestID: UUID,
        transaction: MacLocalXPCMenuPairingCommandTransactionGateV1.Active,
        payload: Data?,
        commandFailed: Bool,
        malformedOrTransportError: Bool
    ) {
        guard generationGate.admitsCallback(generation: generation),
              let pending = pendingMenuPairingCommand,
              pending.requestID == requestID,
              pending.transaction == transaction,
              menuPairingCommandGate.finish(transaction) else { return }
        pendingMenuPairingCommand = nil
        pending.deadline?.cancel()
        pending.deadline = nil

        if commandFailed {
            guard payload == nil, !malformedOrTransportError else {
                pending.continuation.resume(
                    throwing: MacLocalXPCMenuPairingCommandErrorV1
                        .malformedOrTransportError
                )
                invalidateOwnedSession(generation: generation)
                return
            }
            pending.continuation.resume(
                throwing: MacLocalXPCMenuPairingCommandErrorV1.commandFailed
            )
            return
        }
        guard !malformedOrTransportError,
              let payload,
              !payload.isEmpty,
              payload.count <=
                LocalMenuPairingCommandWireCodecV1.maximumEncodedBytes else {
            pending.continuation.resume(
                throwing: MacLocalXPCMenuPairingCommandErrorV1
                    .malformedOrTransportError
            )
            invalidateOwnedSession(generation: generation)
            return
        }
        pending.continuation.resume(returning: payload)
    }

    private func expireMenuPairingCommand(
        generation: UInt64,
        requestID: UUID,
        transaction: MacLocalXPCMenuPairingCommandTransactionGateV1.Active
    ) {
        guard generationGate.admitsCallback(generation: generation),
              let pending = pendingMenuPairingCommand,
              pending.requestID == requestID,
              pending.transaction == transaction,
              menuPairingCommandGate.finish(transaction) else { return }
        pendingMenuPairingCommand = nil
        pending.deadline = nil
        pending.continuation.resume(
            throwing: MacLocalXPCMenuPairingCommandErrorV1.replyTimedOut
        )
        invalidateOwnedSession(generation: generation)
    }

    private func cancelMenuPairingCommand(requestID: UUID) {
        guard let generation = generationGate.currentGeneration,
              let pending = pendingMenuPairingCommand,
              pending.requestID == requestID,
              menuPairingCommandGate.finish(pending.transaction) else { return }
        pendingMenuPairingCommand = nil
        pending.deadline?.cancel()
        pending.deadline = nil
        pending.continuation.resume(
            throwing: MacLocalXPCMenuPairingCommandErrorV1.cancelledAfterSend
        )
        invalidateOwnedSession(generation: generation)
    }

    private func finishPendingMenuPairingCommand(
        generation: UInt64,
        error: MacLocalXPCMenuPairingCommandErrorV1
    ) {
        _ = menuPairingCommandGate.invalidate(generation: generation)
        guard let pending = pendingMenuPairingCommand else { return }
        pendingMenuPairingCommand = nil
        pending.deadline?.cancel()
        pending.deadline = nil
        pending.continuation.resume(throwing: error)
    }

    private func invalidateCurrentGenerationAfterMalformedCommandReply() {
        queue.async { [weak self] in
            guard let self,
                  let generation = generationGate.currentGeneration else {
                return
            }
            self.invalidateOwnedSession(generation: generation)
        }
    }

    private func authorizesMenuCommandMethod(_ method: LocalIPCMethod) -> Bool {
        do {
            try LocalIPCAuthorizationPolicy.authorize(
                authenticatedCaller: .menuApp,
                endpoint: .agent,
                method: method,
                version: .init()
            )
            return true
        } catch {
            return false
        }
    }

    private func cUpdateQuiescenceCommand(
        _ command: MacLocalXPCUpdateQuiescenceCommandV0
    ) -> MCLocalXPCUpdateQuiescenceCommand {
        switch command {
        case .closeNetworkAdmission:
            MCLocalXPCUpdateQuiescenceCloseNetworkAdmission
        case .drainNetworkConnections:
            MCLocalXPCUpdateQuiescenceDrainNetworkConnections
        case .reopenNetworkAdmission:
            MCLocalXPCUpdateQuiescenceReopenNetworkAdmission
        }
    }

    private func cMenuPairingCommandKind(
        _ kind: MacLocalXPCMenuPairingCommandKindV1
    ) -> MCLocalXPCMenuPairingCommandKind {
        switch kind {
        case .create: MCLocalXPCMenuPairingCommandCreate
        case .dismiss: MCLocalXPCMenuPairingCommandDismiss
        case .resolveDecision: MCLocalXPCMenuPairingCommandResolveDecision
        case .recoverHostIdentity:
            MCLocalXPCMenuPairingCommandRecoverHostIdentity
        case .acknowledgeHostIdentityRecoveryCompletion:
            MCLocalXPCMenuPairingCommandAcknowledgeHostIdentityRecovery
        case .requestInteractiveControlGrantReview,
                .decideInteractiveControlGrant, .requestDeviceRevocationReview, .revokeDevice,
                .requestCapabilityGrantReview, .decideCapabilityGrant:
            MCLocalXPCMenuPairingCommandDeviceAdministration
        }
    }

    private func handleHelloReply(
        generation: UInt64,
        acknowledgedBuild: UInt64?,
        hadError: Bool
    ) {
        guard generationGate.admitsCallback(generation: generation) else {
            return
        }
        guard !hadError,
              let acknowledgedBuild,
              gate.receive(exactHello: true)
                == .acknowledgeAndAuthenticate else {
            invalidateOwnedSession(generation: generation)
            return
        }
        onEvent(.authenticatedAgent(build: acknowledgedBuild))
    }

    private func sendMenuReady() {
        guard let generation = generationGate.currentGeneration else {
            return
        }
        guard let session,
              gate.state == .authenticated,
              !menuReadinessRequested,
              !menuReadinessPublished else {
            invalidateOwnedSession(generation: generation)
            return
        }
        menuReadinessRequested = true
        MCLocalXPCSessionSendMenuReady(session) { [weak self] reply, error in
            let exactAcknowledgement: Bool
            if let reply {
                exactAcknowledgement =
                    MCLocalXPCMessageIsExactMenuReadyAcknowledgement(reply)
            } else {
                exactAcknowledgement = false
            }
            self?.handleMenuReadyReply(
                generation: generation,
                exactAcknowledgement: exactAcknowledgement,
                hadError: error
            )
        }
    }

    private func handleMenuReadyReply(
        generation: UInt64,
        exactAcknowledgement: Bool,
        hadError: Bool
    ) {
        guard generationGate.admitsCallback(generation: generation) else {
            return
        }
        guard session != nil,
              gate.state == .authenticated,
              menuReadinessRequested,
              !menuReadinessPublished,
              !hadError,
              exactAcknowledgement else {
            invalidateOwnedSession(generation: generation)
            return
        }
        menuReadinessRequested = false
        menuReadinessPublished = true
        onEvent(.menuReadyAcknowledged)
    }

    private func sendStatusRead() {
        guard let generation = generationGate.currentGeneration else {
            return
        }
        guard let session,
              let operation = statusReadGate.begin(
                generation: generation,
                permitted:
                    gate.state == .authenticated
                    && menuReadinessPublished
              ) else {
            invalidateOwnedSession(generation: generation)
            return
        }

        MCLocalXPCSessionSendStatusRead(session) {
            [weak self] payload, payloadLength, sourceUnavailable, malformed in
            let data = payload.map {
                Data(bytes: $0, count: payloadLength)
            }
            self?.handleStatusReadReply(
                generation: generation,
                operation: operation,
                payload: data,
                sourceUnavailable: sourceUnavailable,
                malformedOrTransportError: malformed
            )
        }
        let deadline = DispatchWorkItem { [weak self] in
            self?.expireStatusRead(
                generation: generation,
                operation: operation
            )
        }
        statusReadDeadline = deadline
        queue.asyncAfter(
            deadline: .now() + statusReadTimeout,
            execute: deadline
        )
    }

    private func handleStatusReadReply(
        generation: UInt64,
        operation: UInt64,
        payload: Data?,
        sourceUnavailable: Bool,
        malformedOrTransportError: Bool
    ) {
        guard generationGate.admitsCallback(generation: generation) else {
            return
        }
        // A reply may arrive after the diagnostic-only read deadline. The
        // timeout already completed that exact operation as unavailable and a
        // later retry may now be active. Ignore only the retired operation;
        // never let its late callback invalidate the current generation.
        guard statusReadGate.admits(
            generation: generation,
            operation: operation
        ) else {
            return
        }
        guard session != nil,
              gate.state == .authenticated,
              menuReadinessPublished,
              statusReadGate.finish(
                generation: generation,
                operation: operation
              ),
              !malformedOrTransportError else {
            invalidateOwnedSession(generation: generation)
            return
        }
        statusReadDeadline?.cancel()
        statusReadDeadline = nil

        if sourceUnavailable {
            guard payload == nil else {
                invalidateOwnedSession(generation: generation)
                return
            }
            onEvent(.agentStatusUnavailable(generation: generation))
            return
        }
        guard let payload,
              !payload.isEmpty,
              payload.count <= MacLocalXPCStatusWireV1.maximumPayloadBytes else {
            invalidateOwnedSession(generation: generation)
            return
        }
        guard let snapshot = try? LocalAgentStatusWireCodecV1.decode(
            payload
        ) else {
            invalidateOwnedSession(generation: generation)
            return
        }
        onEvent(
            .agentStatus(
                generation: generation,
                snapshot: snapshot
            )
        )
    }

    private func expireStatusRead(
        generation: UInt64,
        operation: UInt64
    ) {
        guard generationGate.admitsCallback(generation: generation),
              statusReadGate.admits(
                generation: generation,
                operation: operation
              ) else {
            return
        }
        guard statusReadGate.finish(
            generation: generation,
            operation: operation
        ) else {
            return
        }
        statusReadDeadline = nil
        // Preserve the authenticated transport and surface the closed
        // diagnostic failure. The dashboard retries sequentially on this same
        // generation; authorization and Control ownership are unchanged.
        onEvent(.agentStatusUnavailable(generation: generation))
    }

    private func handleIncomingAgentMessage(
        generation: UInt64,
        message: MCLocalXPCMessageRef
    ) {
        guard generationGate.admitsCallback(generation: generation) else {
            return
        }
        var inputPayload: UnsafePointer<UInt8>?
        var inputPayloadLength = 0
        if MCLocalXPCMessageGetExactInteractiveInput(
            message,
            &inputPayload,
            &inputPayloadLength
        ) {
            guard let inputPayload,
                  inputPayloadLength > 0,
                  inputPayloadLength <= Int(
                    MCLocalXPCMaximumInteractiveInputPayloadBytes
                  ),
                  let envelope = try? InteractiveInputCodec.decode(Data(
                    bytes: inputPayload,
                    count: inputPayloadLength
                  )),
                  beginIncomingInteractiveInput(
                    generation: generation,
                    request: message,
                    envelope: envelope
                  ) else {
                invalidateOwnedSession(generation: generation)
                return
            }
            return
        }
        var interactiveKind = MCLocalXPCInteractiveLeaseCommandInstall
        var interactivePayload: UnsafePointer<UInt8>?
        var interactivePayloadLength = 0
        if MCLocalXPCMessageGetExactInteractiveLeaseCommand(
            message,
            &interactiveKind,
            &interactivePayload,
            &interactivePayloadLength
        ) {
            guard let interactivePayload,
                  interactivePayloadLength > 0,
                  interactivePayloadLength <=
                    LocalInteractiveLeaseWireCodecV1.maximumEncodedBytes,
                  let command = decodeIncomingInteractiveLeaseCommand(
                    kind: interactiveKind,
                    payload: Data(
                        bytes: interactivePayload,
                        count: interactivePayloadLength
                    )
                  ),
                  beginIncomingInteractiveLeaseCommand(
                    generation: generation,
                    request: message,
                    command: command
                  ) else {
                invalidateOwnedSession(generation: generation)
                return
            }
            return
        }
        guard let presentationReceiver,
              presentationGeneration == generation else {
            invalidateOwnedSession(generation: generation)
            return
        }
        let request = MacLocalXPCMenuPresentationWireV1.copyExactRequest(
            message
        )
        let authenticatedAndReady = session != nil
            && gate.state == .authenticated
            && menuReadinessPublished
        let authorized = request.map {
            authorizesAgentPresentationMethod($0.authorizationMethod)
        } ?? false
        presentationReceiver.receive(
            copiedRequest: request,
            borrowedRequest: message,
            authenticatedAndReady: authenticatedAndReady,
            authorized: authorized
        )
    }

    private func beginIncomingInteractiveInput(
        generation: UInt64,
        request: MCLocalXPCMessageRef,
        envelope: InteractiveInputEnvelope
    ) -> Bool {
        guard let interactiveInputHandler,
              session != nil,
              gate.state == .authenticated,
              menuReadinessPublished,
              authorizesAgentPresentationMethod(.applyInteractiveInput),
              let transaction = interactiveInputGate.begin(
                generation: generation,
                permitted: true
              ) else {
            return false
        }
        let pending = PendingIncomingInteractiveInput(
            transaction: transaction,
            request: request
        )
        pendingIncomingInteractiveInput = pending
        let queue = self.queue
        let now = monotonicNowNanoseconds
        pending.task = Task { [weak self, interactiveInputHandler, queue] in
            do {
                try await interactiveInputHandler.applyInteractiveInput(
                    envelope,
                    nowMonotonicNanoseconds: now()
                )
                queue.async { [weak self] in
                    self?.completeIncomingInteractiveInput(
                        generation: generation,
                        transaction: transaction
                    )
                }
            } catch {
                macLocalXPCInteractiveInputLoggerV1.error(
                    "menu input rejected sequence=\(envelope.sequence, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
                queue.async { [weak self] in
                    self?.terminateIncomingInteractiveInput(
                        generation: generation,
                        transaction: transaction
                    )
                }
            }
        }
        let deadline = DispatchWorkItem { [weak self] in
            self?.terminateIncomingInteractiveInput(
                generation: generation,
                transaction: transaction
            )
        }
        pending.deadline = deadline
        queue.asyncAfter(
            deadline: .now() + interactiveInputOperationTimeout,
            execute: deadline
        )
        return true
    }

    private func completeIncomingInteractiveInput(
        generation: UInt64,
        transaction: MacLocalXPCInteractiveRoleDataTransactionGateV1.Active
    ) {
        guard generationGate.admitsCallback(generation: generation),
              gate.state == .authenticated,
              menuReadinessPublished,
              let session,
              let pending = pendingIncomingInteractiveInput,
              pending.transaction == transaction,
              interactiveInputGate.admits(transaction) else {
            terminateIncomingInteractiveInput(
                generation: generation,
                transaction: transaction
            )
            return
        }
        guard interactiveInputGate.finish(transaction),
              let request = takeIncomingInteractiveInputRequest(
                transaction: transaction
              ) else {
            invalidateOwnedSession(generation: generation)
            return
        }
        defer { MCLocalXPCMessageRelease(request) }
        guard MCLocalXPCSessionReplyToInteractiveInputSuccess(
            session,
            request
        ) == MCLocalXPCResultOK else {
            invalidateOwnedSession(generation: generation)
            return
        }
    }

    private func takeIncomingInteractiveInputRequest(
        transaction: MacLocalXPCInteractiveRoleDataTransactionGateV1.Active
    ) -> MCLocalXPCMessageRef? {
        guard let pending = pendingIncomingInteractiveInput,
              pending.transaction == transaction else { return nil }
        pendingIncomingInteractiveInput = nil
        pending.deadline?.cancel()
        pending.deadline = nil
        pending.task = nil
        return pending.takeOwnedRequest()
    }

    private func terminateIncomingInteractiveInput(
        generation: UInt64,
        transaction: MacLocalXPCInteractiveRoleDataTransactionGateV1.Active
    ) {
        guard generationGate.admitsCallback(generation: generation),
              interactiveInputGate.admits(transaction) else { return }
        invalidateOwnedSession(generation: generation)
    }

    private func invalidateIncomingInteractiveInput(generation: UInt64) {
        _ = interactiveInputGate.invalidate(generation: generation)
        guard let pending = pendingIncomingInteractiveInput else { return }
        pendingIncomingInteractiveInput = nil
        pending.deadline?.cancel()
        pending.deadline = nil
        pending.task?.cancel()
        pending.task = nil
        pending.releaseOwnedRequest()
    }

    private func decodeIncomingInteractiveLeaseCommand(
        kind: MCLocalXPCInteractiveLeaseCommandKind,
        payload: Data
    ) -> IncomingInteractiveLeaseCommand? {
        do {
            switch kind {
            case MCLocalXPCInteractiveLeaseCommandPrepareInitialDesktop:
                return .prepareInitialDesktop(
                    try LocalInteractiveLeaseWireCodecV1
                        .decodeInitialDesktopCommand(payload)
                )
            case MCLocalXPCInteractiveLeaseCommandInstall:
                return .install(
                    try LocalInteractiveLeaseWireCodecV1
                        .decodeInstallCommand(payload)
                )
            case MCLocalXPCInteractiveLeaseCommandRenew:
                return .renew(
                    try LocalInteractiveLeaseWireCodecV1
                        .decodeRenewal(payload)
                )
            case MCLocalXPCInteractiveLeaseCommandRevoke:
                return .revoke(
                    try LocalInteractiveLeaseWireCodecV1
                        .decodeRevokeCommand(payload)
                )
            case MCLocalXPCInteractiveLeaseCommandSurfaceTargets:
                return .surfaceTargets(
                    try LocalInteractiveLeaseWireCodecV1
                        .decodeSurfaceTargetsCommand(payload)
                )
            case MCLocalXPCInteractiveLeaseCommandSurfaceResolve:
                return .surfaceResolve(
                    try LocalInteractiveLeaseWireCodecV1
                        .decodeSurfaceResolveCommand(payload)
                )
            case MCLocalXPCInteractiveLeaseCommandSurfaceTransition:
                return .surfaceTransition(
                    try LocalInteractiveLeaseWireCodecV1
                        .decodeSurfaceTransitionCommand(payload)
                )
            case MCLocalXPCInteractiveLeaseCommandSurfaceAcknowledgement:
                return .surfaceAcknowledgement(
                    try LocalInteractiveLeaseWireCodecV1
                        .decodeSurfaceAcknowledgementCommand(payload)
                )
            case MCLocalXPCInteractiveLeaseCommandSurfaceFailure:
                return .surfaceFailure(
                    try LocalInteractiveLeaseWireCodecV1
                        .decodeSurfaceFailureCommand(payload)
                )
            case MCLocalXPCInteractiveLeaseCommandFocusSnapshot:
                return .focusSnapshot(
                    try LocalInteractiveLeaseWireCodecV1
                        .decodeFocusSnapshotCommand(payload)
                )
            case MCLocalXPCInteractiveLeaseCommandDisplayCatalog:
                return .displayCatalog(
                    try LocalInteractiveLeaseWireCodecV1
                        .decodeDisplayCatalogCommand(payload)
                )
            case MCLocalXPCInteractiveLeaseCommandDisplaySelect:
                return .displaySelect(
                    try LocalInteractiveLeaseWireCodecV1
                        .decodeDisplaySelectCommand(payload)
                )
            case MCLocalXPCInteractiveLeaseCommandNativeBackend:
                return .nativeBackend(try LocalInteractiveLeaseWireCodecV1.decodeNativeBackendCommand(payload))
            case MCLocalXPCInteractiveLeaseCommandNativeSnapshot:
                return .nativeSnapshot(try LocalInteractiveLeaseWireCodecV1.decodeNativeSnapshotCommand(payload))
            case MCLocalXPCInteractiveLeaseCommandWebRTCOffer:
                return .webRTCOffer(
                    try LocalInteractiveLeaseWireCodecV1
                        .decodeWebRTCOfferCommand(payload)
                )
            case MCLocalXPCInteractiveLeaseCommandWebRTCAnswer:
                return .webRTCAnswer(
                    try LocalInteractiveLeaseWireCodecV1
                        .decodeWebRTCAnswerCommand(payload)
                )
            case MCLocalXPCInteractiveLeaseCommandWebRTCClose:
                return .webRTCClose(
                    try LocalInteractiveLeaseWireCodecV1
                        .decodeWebRTCCloseCommand(payload)
                )
            default:
                return nil
            }
        } catch {
            return nil
        }
    }

    private func beginIncomingInteractiveLeaseCommand(
        generation: UInt64,
        request: MCLocalXPCMessageRef,
        command: IncomingInteractiveLeaseCommand
    ) -> Bool {
        guard let interactiveLeaseHandler,
              self.session != nil,
              gate.state == .authenticated,
              menuReadinessPublished,
              authorizesAgentPresentationMethod(
                command.authorizationMethod
              ),
              let transaction = interactiveLeaseGate.begin(
                generation: generation,
                kind: command.kind,
                permitted: true
              ) else {
            return false
        }

        let pending = PendingIncomingInteractiveLeaseCommand(
            transaction: transaction,
            command: command,
            request: request
        )
        pendingIncomingInteractiveLeaseCommand = pending
        let queue = self.queue
        let monotonicNowNanoseconds = self.monotonicNowNanoseconds
        pending.task = Task {
            [weak self, interactiveLeaseHandler, command, queue] in
            do {
                let result: IncomingInteractiveLeaseResult
                switch command {
                case .prepareInitialDesktop(let value):
                    result = .preparedInitialDesktop(
                        try await interactiveLeaseHandler
                            .prepareInitialInteractiveDesktop(
                                value,
                                nowMonotonicNanoseconds:
                                    monotonicNowNanoseconds()
                            )
                    )
                case .install(let value):
                    result = .install(
                        try await interactiveLeaseHandler
                            .installInteractiveLease(
                                value,
                                nowMonotonicNanoseconds:
                                    monotonicNowNanoseconds()
                            )
                    )
                case .renew(let value):
                    try await interactiveLeaseHandler
                        .renewInteractiveLease(
                            value,
                            nowMonotonicNanoseconds:
                                monotonicNowNanoseconds()
                        )
                    result = .renewed
                case .revoke(let value):
                    result = .revoked(
                        try await interactiveLeaseHandler
                            .revokeInteractiveLease(value)
                    )
                case .surfaceTargets(let value):
                    result = .surfaceTargets(
                        try await interactiveLeaseHandler
                            .interactiveSurfaceTargets(
                                value,
                                nowMonotonicNanoseconds:
                                    monotonicNowNanoseconds()
                            )
                    )
                case .surfaceResolve(let value):
                    result = .surfaceResolved(
                        try await interactiveLeaseHandler
                            .resolveInteractiveSurface(
                                value,
                                nowMonotonicNanoseconds:
                                    monotonicNowNanoseconds()
                            )
                    )
                case .surfaceTransition(let value):
                    result = .surfaceTransition(
                        try await interactiveLeaseHandler
                            .prepareInteractiveSurfaceTransition(
                                value,
                                nowMonotonicNanoseconds:
                                    monotonicNowNanoseconds()
                            )
                    )
                case .surfaceAcknowledgement(let value):
                    result = .surfaceAcknowledged(
                        try await interactiveLeaseHandler
                            .acknowledgeInteractiveSurface(
                                value,
                                nowMonotonicNanoseconds:
                                    monotonicNowNanoseconds()
                            )
                    )
                case .surfaceFailure(let value):
                    result = .surfaceFailure(
                        try await interactiveLeaseHandler
                            .terminateInteractiveSurfaceFailure(value)
                    )
                case .focusSnapshot(let value):
                    result = .focusSnapshot(
                        try await interactiveLeaseHandler
                            .interactiveFocusSnapshot(
                                value,
                                nowMonotonicNanoseconds:
                                    monotonicNowNanoseconds()
                            )
                    )
                case .displayCatalog(let value):
                    result = .displayCatalog(
                        try await interactiveLeaseHandler
                            .interactiveDisplayCatalog(
                                value,
                                nowMonotonicNanoseconds:
                                    monotonicNowNanoseconds()
                            )
                    )
                case .displaySelect(let value):
                    result = .displaySelected(
                        try await interactiveLeaseHandler
                            .selectInteractiveDisplay(
                                value,
                                nowMonotonicNanoseconds:
                                    monotonicNowNanoseconds()
                            )
                    )
                case .nativeBackend(let value):
                    result = .nativeBackend(try await interactiveLeaseHandler.nativeBackend(
                        value, nowMonotonicNanoseconds: monotonicNowNanoseconds()))
                case .nativeSnapshot(let value):
                    result = .nativeSnapshot(try await interactiveLeaseHandler.nativeRuntimeSnapshot(
                        value, nowMonotonicNanoseconds: monotonicNowNanoseconds()))
                case .webRTCOffer(let value):
                    result = .webRTCOffer(
                        try await interactiveLeaseHandler
                            .makeWebRTCOffer(
                                value,
                                nowMonotonicNanoseconds:
                                    monotonicNowNanoseconds()
                            )
                    )
                case .webRTCAnswer(let value):
                    try await interactiveLeaseHandler
                        .acceptWebRTCAnswer(
                            value,
                            nowMonotonicNanoseconds:
                                monotonicNowNanoseconds()
                        )
                    result = .webRTCAnswered
                case .webRTCClose(let value):
                    try await interactiveLeaseHandler.closeWebRTC(value)
                    result = .webRTCClosed
                }
                queue.async { [weak self] in
                    self?.completeIncomingInteractiveLeaseCommand(
                        generation: generation,
                        transaction: transaction,
                        result: result
                    )
                }
            } catch {
                macLocalXPCInteractiveLeaseLoggerV1.error(
                    "menu interactive command failed kind=\(String(describing: command.kind), privacy: .public) operation=\(transaction.operation, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
                queue.async { [weak self] in
                    self?.terminateIncomingInteractiveLeaseCommand(
                        generation: generation,
                        transaction: transaction
                    )
                }
            }
        }
        let deadline = DispatchWorkItem { [weak self] in
            self?.terminateIncomingInteractiveLeaseCommand(
                generation: generation,
                transaction: transaction
            )
        }
        pending.deadline = deadline
        queue.asyncAfter(
            deadline: .now() + interactiveLeaseOperationTimeout,
            execute: deadline
        )
        return true
    }

    private func completeIncomingInteractiveLeaseCommand(
        generation: UInt64,
        transaction: MacLocalXPCInteractiveLeaseTransactionGateV1.Active,
        result: IncomingInteractiveLeaseResult
    ) {
        guard generationGate.admitsCallback(generation: generation),
              gate.state == .authenticated,
              menuReadinessPublished,
              let session,
              let pending = pendingIncomingInteractiveLeaseCommand,
              pending.transaction == transaction,
              interactiveLeaseGate.admits(transaction),
              let payload = validatedIncomingInteractiveLeaseReply(
                command: pending.command,
                result: result
              ) else {
            macLocalXPCInteractiveLeaseLoggerV1.error(
                "menu could not complete interactive command kind=\(String(describing: transaction.kind), privacy: .public) operation=\(transaction.operation, privacy: .public)"
            )
            terminateIncomingInteractiveLeaseCommand(
                generation: generation,
                transaction: transaction
            )
            return
        }
        guard interactiveLeaseGate.finish(transaction),
              let request = takeIncomingInteractiveLeaseRequest(
                transaction: transaction
              ) else {
            invalidateOwnedSession(generation: generation)
            return
        }
        defer { MCLocalXPCMessageRelease(request) }
        let reply = MacLocalXPCReplyPayloadBytesV1.withBytes(payload) {
            bytes, length in
            return MCLocalXPCSessionReplyToInteractiveLeaseCommandSuccess(
                session,
                request,
                cInteractiveLeaseCommandKind(transaction.kind),
                bytes,
                length
            )
        }
        guard reply == MCLocalXPCResultOK else {
            macLocalXPCInteractiveLeaseLoggerV1.error(
                "menu interactive reply send failed kind=\(String(describing: transaction.kind), privacy: .public) operation=\(transaction.operation, privacy: .public) result=\(reply.rawValue, privacy: .public)"
            )
            invalidateOwnedSession(generation: generation)
            return
        }
        macLocalXPCInteractiveLeaseLoggerV1.notice(
            "menu sent interactive reply kind=\(String(describing: transaction.kind), privacy: .public) operation=\(transaction.operation, privacy: .public)"
        )
    }

    /// An empty value is the exact payload-free renewal acknowledgement.
    private func validatedIncomingInteractiveLeaseReply(
        command: IncomingInteractiveLeaseCommand,
        result: IncomingInteractiveLeaseResult
    ) -> Data? {
        do {
            switch (command, result) {
            case (
                .prepareInitialDesktop(let command),
                .preparedInitialDesktop(let receipt)
            ):
                try receipt.validate(against: command)
                return try LocalInteractiveLeaseWireCodecV1
                    .encodeInitialDesktopReceipt(receipt)
            case (.install(let command), .install(let receipt)):
                try receipt.validate(against: command)
                return try LocalInteractiveLeaseWireCodecV1
                    .encodeInstallReceipt(receipt)
            case (.renew, .renewed):
                return Data()
            case (.revoke(let command), .revoked(let receipt)):
                try receipt.validate(against: command)
                return try LocalInteractiveLeaseWireCodecV1
                    .encodeRevokedReceipt(receipt)
            case (.surfaceTargets(let command), .surfaceTargets(let receipt)):
                try receipt.validate(against: command)
                return try LocalInteractiveLeaseWireCodecV1
                    .encodeSurfaceTargetsReceipt(receipt)
            case (.surfaceResolve(let command), .surfaceResolved(let receipt)):
                try receipt.validate(against: command)
                return try LocalInteractiveLeaseWireCodecV1
                    .encodeSurfaceResolvedReceipt(receipt)
            case (
                .surfaceTransition(let command),
                .surfaceTransition(let receipt)
            ):
                try receipt.validate(against: command)
                return try LocalInteractiveLeaseWireCodecV1
                    .encodeSurfaceTransitionReceipt(receipt)
            case (
                .surfaceAcknowledgement(let command),
                .surfaceAcknowledged(let receipt)
            ):
                try receipt.validate(against: command)
                return try LocalInteractiveLeaseWireCodecV1
                    .encodeSurfaceAcknowledgementReceipt(receipt)
            case (.surfaceFailure(let command), .surfaceFailure(let receipt)):
                try receipt.validate(against: command)
                return try LocalInteractiveLeaseWireCodecV1
                    .encodeSurfaceFailureReceipt(receipt)
            case (.focusSnapshot(let command), .focusSnapshot(let receipt)):
                try receipt.validate(against: command)
                return try LocalInteractiveLeaseWireCodecV1
                    .encodeFocusSnapshotReceipt(receipt)
            case (.displayCatalog(let command), .displayCatalog(let receipt)):
                try receipt.validate(against: command)
                return try LocalInteractiveLeaseWireCodecV1
                    .encodeDisplayCatalogReceipt(receipt)
            case (.displaySelect(let command), .displaySelected(let receipt)):
                try receipt.validate(against: command)
                return try LocalInteractiveLeaseWireCodecV1
                    .encodeDisplaySelectedReceipt(receipt)
            case (.nativeBackend(let command), .nativeBackend(let receipt)):
                try receipt.validate(against: command)
                return try LocalInteractiveLeaseWireCodecV1.encodeNativeBackendReceipt(receipt)
            case (.nativeSnapshot(let command), .nativeSnapshot(let receipt)):
                try receipt.validate(against: command)
                return try LocalInteractiveLeaseWireCodecV1.encodeNativeSnapshotReceipt(receipt)
            case (.webRTCOffer(let command), .webRTCOffer(let receipt)):
                try receipt.validate(against: command)
                return try LocalInteractiveLeaseWireCodecV1
                    .encodeWebRTCOfferReceipt(receipt)
            case (.webRTCAnswer, .webRTCAnswered),
                 (.webRTCClose, .webRTCClosed):
                return Data()
            default:
                return nil
            }
        } catch {
            return nil
        }
    }

    private func terminateIncomingInteractiveLeaseCommand(
        generation: UInt64,
        transaction: MacLocalXPCInteractiveLeaseTransactionGateV1.Active
    ) {
        guard generationGate.admitsCallback(generation: generation),
              interactiveLeaseGate.admits(transaction) else { return }
        invalidateOwnedSession(generation: generation)
    }

    private func takeIncomingInteractiveLeaseRequest(
        transaction: MacLocalXPCInteractiveLeaseTransactionGateV1.Active
    ) -> MCLocalXPCMessageRef? {
        guard let pending = pendingIncomingInteractiveLeaseCommand,
              pending.transaction == transaction else { return nil }
        pendingIncomingInteractiveLeaseCommand = nil
        pending.deadline?.cancel()
        pending.deadline = nil
        pending.task = nil
        return pending.takeOwnedRequest()
    }

    private func invalidateIncomingInteractiveLease(
        generation: UInt64,
        notifyRuntime: Bool
    ) {
        let wasBound = interactiveLeaseGate.generation == generation
        _ = interactiveLeaseGate.invalidate(generation: generation)
        if let pending = pendingIncomingInteractiveLeaseCommand {
            pendingIncomingInteractiveLeaseCommand = nil
            pending.deadline?.cancel()
            pending.deadline = nil
            pending.task?.cancel()
            pending.task = nil
            pending.releaseOwnedRequest()
        }
        guard wasBound, notifyRuntime, let interactiveLeaseHandler else {
            return
        }
        Task { await interactiveLeaseHandler.invalidateAgentAuthority() }
    }

    private func cInteractiveLeaseCommandKind(
        _ kind: MacLocalXPCInteractiveLeaseCommandKindV1
    ) -> MCLocalXPCInteractiveLeaseCommandKind {
        switch kind {
        case .prepareInitialDesktop:
            MCLocalXPCInteractiveLeaseCommandPrepareInitialDesktop
        case .install: MCLocalXPCInteractiveLeaseCommandInstall
        case .renew: MCLocalXPCInteractiveLeaseCommandRenew
        case .revoke: MCLocalXPCInteractiveLeaseCommandRevoke
        case .surfaceTargets:
            MCLocalXPCInteractiveLeaseCommandSurfaceTargets
        case .surfaceResolve:
            MCLocalXPCInteractiveLeaseCommandSurfaceResolve
        case .surfaceTransition:
            MCLocalXPCInteractiveLeaseCommandSurfaceTransition
        case .surfaceAcknowledgement:
            MCLocalXPCInteractiveLeaseCommandSurfaceAcknowledgement
        case .surfaceFailure:
            MCLocalXPCInteractiveLeaseCommandSurfaceFailure
        case .focusSnapshot:
            MCLocalXPCInteractiveLeaseCommandFocusSnapshot
        case .displayCatalog:
            MCLocalXPCInteractiveLeaseCommandDisplayCatalog
        case .displaySelect:
            MCLocalXPCInteractiveLeaseCommandDisplaySelect
        case .nativeBackend:
            MCLocalXPCInteractiveLeaseCommandNativeBackend
        case .nativeSnapshot:
            MCLocalXPCInteractiveLeaseCommandNativeSnapshot
        case .webRTCOffer:
            MCLocalXPCInteractiveLeaseCommandWebRTCOffer
        case .webRTCAnswer:
            MCLocalXPCInteractiveLeaseCommandWebRTCAnswer
        case .webRTCClose:
            MCLocalXPCInteractiveLeaseCommandWebRTCClose
        }
    }

    private func makePresentationReceiver(
        generation: UInt64
    ) -> MacLocalXPCMenuPresentationReceiverGenerationV1<
        MCLocalXPCMessageRef
    >? {
        guard let presentationSurfaces else { return nil }
        let queue = self.queue
        return MacLocalXPCMenuPresentationReceiverGenerationV1(
            surfaces: presentationSurfaces,
            retainRequest: MCLocalXPCMessageRetain,
            releaseRequest: MCLocalXPCMessageRelease,
            reply: { [weak self] request, kind in
                self?.replyToIncomingMenuPresentation(
                    generation: generation,
                    request: request,
                    kind: kind
                ) ?? false
            },
            enqueue: { operation in
                queue.async(execute: operation)
            },
            scheduleDeadline: { interval, operation in
                let deadline = DispatchWorkItem(block: operation)
                queue.asyncAfter(
                    deadline: .now() + interval,
                    execute: deadline
                )
                return MacLocalXPCMenuPresentationScheduledDeadlineV1 {
                    deadline.cancel()
                }
            },
            onTerminal: { [weak self] in
                self?.invalidateOwnedSession(generation: generation)
            }
        )
    }

    private func replyToIncomingMenuPresentation(
        generation: UInt64,
        request: MCLocalXPCMessageRef,
        kind: MacLocalXPCMenuPresentationRequestV1
    ) -> Bool {
        guard generationGate.admitsCallback(generation: generation),
              presentationGeneration == generation,
              presentationReceiver != nil,
              gate.state == .authenticated,
              menuReadinessPublished,
              let session else {
            return false
        }
        let result: MCLocalXPCResult = switch kind {
        case .pairingReview:
            MCLocalXPCSessionReplyToPairingReviewPublishAcknowledgement(
                session,
                request
            )
        case .pairingWithdrawal:
            MCLocalXPCSessionReplyToPairingReviewWithdrawalAcknowledgement(
                session,
                request
            )
        case .hostRecoveryReview:
            MCLocalXPCSessionReplyToHostRecoveryReviewPublishAcknowledgement(
                session,
                request
            )
        case .hostRecoveryResume:
            MCLocalXPCSessionReplyToHostRecoveryResumePublishAcknowledgement(
                session,
                request
            )
        case .hostRecoveryWithdrawal:
            MCLocalXPCSessionReplyToHostRecoveryWithdrawalAcknowledgement(
                session,
                request
            )
        }
        return result == MCLocalXPCResultOK
    }

    private func authorizesAgentPresentationMethod(
        _ method: LocalIPCMethod
    ) -> Bool {
        do {
            try LocalIPCAuthorizationPolicy.authorize(
                authenticatedCaller: .agent,
                endpoint: .menuApp,
                method: method,
                version: .init()
            )
            return true
        } catch {
            return false
        }
    }

    private func discardUnactivatedPresentationGeneration(
        generation: UInt64
    ) {
        guard presentationGeneration == generation else { return }
        presentationGeneration = nil
        presentationReceiver = nil
    }

    private func retirePresentationReceiver(generation: UInt64) {
        guard presentationGeneration == generation,
              let presentationReceiver else {
            return
        }
        presentationGeneration = nil
        self.presentationReceiver = nil
        let cleanup = presentationReceiver.retire()

        let token = UUID()
        let queue = self.queue
        let task = Task { [weak self, cleanup, queue] in
            await cleanup.value
            queue.async { [weak self] in
                self?.completePresentationRetirement(token: token)
            }
        }
        presentationRetirement = (token, task)
    }

    private func completePresentationRetirement(token: UUID) {
        guard presentationRetirement?.token == token else { return }
        presentationRetirement = nil
    }

    private func invalidateOwnedSession(generation: UInt64) {
        guard generationGate.admitsCallback(generation: generation),
              let session else { return }
        _ = generationGate.invalidate(generation: generation)
        gate.invalidate()
        menuReadinessRequested = false
        menuReadinessPublished = false
        self.session = nil
        _ = statusReadGate.invalidate(generation: generation)
        statusReadDeadline?.cancel()
        statusReadDeadline = nil
        finishPendingMenuPairingCommand(
            generation: generation,
            error: .unavailable
        )
        finishPendingUpdateQuiescenceCommand(
            generation: generation,
            error: .unavailable
        )
        finishPendingInteractiveAdmissionPublication(
            generation: generation,
            error: .unavailable
        )
        finishPendingInteractiveMediaPublication(
            generation: generation,
            error: .unavailable
        )
        invalidateIncomingInteractiveLease(
            generation: generation,
            notifyRuntime: true
        )
        invalidateIncomingInteractiveInput(generation: generation)
        retirePresentationReceiver(generation: generation)
        MCLocalXPCSessionCancelOwned(session)
        onEvent(.invalidated)
    }

    private func handleInvalidation(generation: UInt64) {
        guard generationGate.admitsCallback(generation: generation),
              let session else { return }
        let shouldNotify = gate.state != .invalidated
        _ = generationGate.invalidate(generation: generation)
        gate.invalidate()
        menuReadinessRequested = false
        menuReadinessPublished = false
        self.session = nil
        _ = statusReadGate.invalidate(generation: generation)
        statusReadDeadline?.cancel()
        statusReadDeadline = nil
        finishPendingMenuPairingCommand(
            generation: generation,
            error: .unavailable
        )
        finishPendingUpdateQuiescenceCommand(
            generation: generation,
            error: .unavailable
        )
        finishPendingInteractiveAdmissionPublication(
            generation: generation,
            error: .unavailable
        )
        finishPendingInteractiveMediaPublication(
            generation: generation,
            error: .unavailable
        )
        invalidateIncomingInteractiveLease(
            generation: generation,
            notifyRuntime: true
        )
        invalidateIncomingInteractiveInput(generation: generation)
        retirePresentationReceiver(generation: generation)
        MCLocalXPCSessionRelease(session)
        if shouldNotify {
            onEvent(.invalidated)
        }
    }

    private func syncOnQueue<T>(
        _ body: () throws -> T
    ) rethrows -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try body()
        }
        return try queue.sync(execute: body)
    }
}
#endif
