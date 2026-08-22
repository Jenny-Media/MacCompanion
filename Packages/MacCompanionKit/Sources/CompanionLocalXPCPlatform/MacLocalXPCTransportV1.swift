#if os(macOS)
import CompanionIPC
import CompanionLocalXPCPlatformC
import Dispatch
import Foundation

public enum MacLocalXPCIdentityV1 {
    public static let serviceName = "media.jenny.maccompanion.agent"
    public static let menuSigningIdentifier = "media.jenny.maccompanion"
    public static let agentSigningIdentifier =
        "media.jenny.maccompanion.agent"
}

public enum MacLocalXPCServerEventV1: Equatable, Sendable {
    case authenticatedMenu(generation: UInt64)
    case menuReady(generation: UInt64)
    case invalidatedMenu(generation: UInt64)
}

public enum MacLocalXPCClientEventV1: Equatable, Sendable {
    case authenticatedAgent
    case menuReadyAcknowledged
    case agentStatus(
        generation: UInt64,
        snapshot: LocalAgentStatusSnapshot
    )
    case agentStatusUnavailable(generation: UInt64)
    case invalidated
}

public enum MacLocalXPCServerProfileV1: Equatable, Sendable {
    /// The permanent target default: authenticate and reject every later
    /// message until a complete authority owner is composed.
    case authenticationOnly

    /// Enables only the exact one-use lifecycle.menu-ready exchange.
    case menuLifecycleReadiness

    /// Enables readiness followed by bounded, content-free status reads.
    /// This profile requires an injected reader from the complete Agent root.
    case menuLifecycleReadinessAndStatus

    /// Package-only construction profile that additionally issues the five
    /// authenticated Agent-to-menu presentation capabilities after readiness.
    /// Permanent product roots must opt in explicitly.
    case menuLifecycleReadinessStatusAndPresentation

    var admitsMenuLifecycleReadiness: Bool {
        self != .authenticationOnly
    }

    var admitsAgentStatus: Bool {
        self == .menuLifecycleReadinessAndStatus
            || self == .menuLifecycleReadinessStatusAndPresentation
    }

    var admitsMenuPresentation: Bool {
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
    MacLocalXPCMenuPresentationSendingV1
{
    public typealias EventHandler = @Sendable (MacLocalXPCServerEventV1) -> Void
    package static let maximumAdmittedPresentationsPerGeneration = 8
    package static let presentationReplyTimeoutSeconds = 3

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
        var statusReadGate = MacLocalXPCStatusReadTransactionGateV1()
        var pendingStatusRead: PendingStatusRead?
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
            precondition(statusReadGate.bind(generation: generation))
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
    private let statusReader: (any MacLocalXPCStatusReadingV1)?
    private let profile: MacLocalXPCServerProfileV1
    private let statusReadTimeout: DispatchTimeInterval = .seconds(2)
    private let handshakeTimeout: DispatchTimeInterval = .seconds(10)
    private var generationGate = MacLocalXPCPeerGenerationGateV1()
    private var listenerRunGate = MacLocalXPCServerRunGateV1()
    private var pendingGate = MacLocalXPCPendingCandidateGateV1(limit: 8)
    private var peerStates: [UInt64: PeerState] = [:]

    public init(
        profile: MacLocalXPCServerProfileV1 = .authenticationOnly,
        statusReader: (any MacLocalXPCStatusReadingV1)? = nil,
        onEvent: @escaping EventHandler
    ) {
        self.profile = profile
        self.statusReader = statusReader
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
                MacLocalXPCIdentityV1.serviceName,
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
        state.cancelPendingStatusRead()
        fencePresentations(state, error: presentationError)
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
                      MCLocalXPCSessionReplyToHello(peer, message)
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
        state.cancelPendingStatusRead()
        cancelAuthenticatedPeer(
            state,
            presentationError: .transportFailure
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
public final class MacLocalXPCClientV1: @unchecked Sendable {
    public typealias EventHandler = @Sendable (MacLocalXPCClientEventV1) -> Void

    private let queue = DispatchQueue(
        label: "media.jenny.maccompanion.local-xpc.menu"
    )
    private let queueKey = DispatchSpecificKey<UInt8>()
    private let onEvent: EventHandler
    private var session: MCLocalXPCSessionRef?
    private var gate = MacLocalXPCHandshakeGateV1()
    private var menuReadinessRequested = false
    private var menuReadinessPublished = false
    private var generationGate = MacLocalXPCClientGenerationGateV1()
    private var statusReadGate = MacLocalXPCStatusReadTransactionGateV1()
    private var statusReadDeadline: DispatchWorkItem?
    private let statusReadTimeout: DispatchTimeInterval = .seconds(3)

    public init(onEvent: @escaping EventHandler) {
        self.onEvent = onEvent
        queue.setSpecific(key: queueKey, value: 1)
    }

    deinit {
        cancel()
    }

    public func start() throws {
        try syncOnQueue {
            guard session == nil else {
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
            statusReadDeadline?.cancel()
            statusReadDeadline = nil

            guard let candidate = MCLocalXPCSessionCreateInactive(
                MacLocalXPCIdentityV1.serviceName,
                queue,
                &result
            ), result == MCLocalXPCResultOK else {
                _ = generationGate.invalidate(generation: generation)
                MCLocalXPCPeerRequirementRelease(requirement)
                throw MacLocalXPCConstructionErrorV1.sessionConstruction
            }
            MCLocalXPCSessionSetPeerRequirement(candidate, requirement)
            MCLocalXPCPeerRequirementRelease(requirement)
            MCLocalXPCSessionSetCancelHandler(candidate) {
                [weak self] in
                self?.handleInvalidation(generation: generation)
            }
            guard MCLocalXPCSessionActivate(candidate)
                    == MCLocalXPCResultOK else {
                _ = generationGate.invalidate(generation: generation)
                MCLocalXPCSessionDisposeAfterFailedActivation(candidate)
                throw MacLocalXPCConstructionErrorV1.activation
            }
            session = candidate
            MCLocalXPCSessionSendHello(candidate) {
                [weak self] reply, error in
                let exactAcknowledgement: Bool
                if let reply {
                    exactAcknowledgement =
                        MCLocalXPCMessageIsExactHelloAcknowledgement(reply)
                } else {
                    exactAcknowledgement = false
                }
                self?.handleHelloReply(
                    generation: generation,
                    exactAcknowledgement: exactAcknowledgement,
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
            MCLocalXPCSessionCancelOwned(session)
        }
    }

    private func handleHelloReply(
        generation: UInt64,
        exactAcknowledgement: Bool,
        hadError: Bool
    ) {
        guard generationGate.admitsCallback(generation: generation) else {
            return
        }
        guard !hadError, gate.receive(exactHello: exactAcknowledgement)
                == .acknowledgeAndAuthenticate else {
            invalidateOwnedSession(generation: generation)
            return
        }
        onEvent(.authenticatedAgent)
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
        invalidateOwnedSession(generation: generation)
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
