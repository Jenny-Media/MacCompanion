import CompanionLocalXPCPlatformC
import Dispatch

public enum MacLocalXPCIdentityV1 {
    public static let serviceName = "media.jenny.maccompanion.agent"
    public static let menuSigningIdentifier = "media.jenny.maccompanion"
    public static let agentSigningIdentifier =
        "media.jenny.maccompanion.agent"
}

public enum MacLocalXPCServerEventV1: Equatable, Sendable {
    case authenticatedMenu(generation: UInt64)
    case invalidatedMenu(generation: UInt64)
}

public enum MacLocalXPCClientEventV1: Equatable, Sendable {
    case authenticatedAgent
    case invalidated
}

public enum MacLocalXPCConstructionErrorV1: Error, Equatable, Sendable {
    case alreadyStarted
    case listenerConstruction
    case sessionConstruction
    case peerRequirement
    case activation
}

public enum MacLocalXPCHandshakeActionV1: Equatable, Sendable {
    case acknowledgeAndAuthenticate
    case reject
}

/// Pure one-use gate shared by the platform listener and its focused tests.
/// An exact hello is the only value that can cross the pre-authentication
/// boundary. Every later message is rejected until a separately reviewed
/// authenticated method adapter is installed.
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

    public mutating func invalidate() -> Bool {
        let shouldPublishInvalidation = authenticationPublished
        authenticationPublished = false
        handshake.invalidate()
        return shouldPublishInvalidation
    }
}

@available(macOS 26.0, *)
public final class MacLocalXPCServerV1: @unchecked Sendable {
    public typealias EventHandler = @Sendable (MacLocalXPCServerEventV1) -> Void

    private final class PeerState: @unchecked Sendable {
        let generation: UInt64
        var lifetime = MacLocalXPCAuthenticatedLifetimeV1()

        init(generation: UInt64) {
            self.generation = generation
        }
    }

    private let queue = DispatchQueue(
        label: "media.jenny.maccompanion.local-xpc.agent"
    )
    private let onEvent: EventHandler
    private var listener: MCLocalXPCListenerRef?
    private var nextGeneration: UInt64 = 0

    public init(onEvent: @escaping EventHandler) {
        self.onEvent = onEvent
    }

    public func start() throws {
        try queue.sync {
            guard listener == nil else {
                throw MacLocalXPCConstructionErrorV1.alreadyStarted
            }

            var result = MCLocalXPCResultOK
            guard let candidate = MCLocalXPCListenerCreateInactive(
                MacLocalXPCIdentityV1.serviceName,
                queue,
                { [weak self] peer in
                    self?.accept(peer: peer)
                },
                &result
            ), result == MCLocalXPCResultOK else {
                throw MacLocalXPCConstructionErrorV1.listenerConstruction
            }
            guard MCLocalXPCListenerRequireSameTeamIdentifier(
                candidate,
                MacLocalXPCIdentityV1.menuSigningIdentifier
            ) == MCLocalXPCResultOK else {
                MCLocalXPCListenerCancel(candidate)
                throw MacLocalXPCConstructionErrorV1.peerRequirement
            }
            guard MCLocalXPCListenerActivate(candidate)
                    == MCLocalXPCResultOK else {
                MCLocalXPCListenerCancel(candidate)
                throw MacLocalXPCConstructionErrorV1.activation
            }
            listener = candidate
        }
    }

    public func cancel() {
        queue.sync {
            guard let listener else { return }
            self.listener = nil
            MCLocalXPCListenerCancel(listener)
        }
    }

    private func accept(peer: MCLocalXPCSessionRef) {
        guard nextGeneration < UInt64.max else {
            MCLocalXPCSessionCancel(peer)
            return
        }
        nextGeneration += 1
        let state = PeerState(generation: nextGeneration)

        guard MCLocalXPCSessionRequireSameTeamIdentifier(
            peer,
            MacLocalXPCIdentityV1.menuSigningIdentifier
        ) == MCLocalXPCResultOK else {
            MCLocalXPCSessionCancel(peer)
            return
        }
        MCLocalXPCSessionSetCancelHandler(peer) { [weak self, state] in
            let wasAuthenticated = state.lifetime.invalidate()
            if wasAuthenticated {
                self?.onEvent(
                    .invalidatedMenu(generation: state.generation)
                )
            }
        }
        MCLocalXPCSessionSetMessageHandler(peer) { [weak self, state] message in
            let exact = MCLocalXPCMessageIsExactHello(message)
            guard state.lifetime.receiveHello(exact: exact)
                    == .acknowledgeAndAuthenticate,
                  MCLocalXPCSessionReplyToHello(peer, message)
                    == MCLocalXPCResultOK,
                  state.lifetime.publishAuthentication() else {
                MCLocalXPCSessionCancel(peer)
                return
            }
            self?.onEvent(.authenticatedMenu(generation: state.generation))
        }
    }
}

@available(macOS 26.0, *)
public final class MacLocalXPCClientV1: @unchecked Sendable {
    public typealias EventHandler = @Sendable (MacLocalXPCClientEventV1) -> Void

    private let queue = DispatchQueue(
        label: "media.jenny.maccompanion.local-xpc.menu"
    )
    private let onEvent: EventHandler
    private var session: MCLocalXPCSessionRef?
    private var gate = MacLocalXPCHandshakeGateV1()

    public init(onEvent: @escaping EventHandler) {
        self.onEvent = onEvent
    }

    public func start() throws {
        try queue.sync {
            guard session == nil else {
                throw MacLocalXPCConstructionErrorV1.alreadyStarted
            }
            gate = MacLocalXPCHandshakeGateV1()

            var result = MCLocalXPCResultOK
            guard let candidate = MCLocalXPCSessionCreateInactive(
                MacLocalXPCIdentityV1.serviceName,
                queue,
                &result
            ), result == MCLocalXPCResultOK else {
                throw MacLocalXPCConstructionErrorV1.sessionConstruction
            }
            guard MCLocalXPCSessionRequireSameTeamIdentifier(
                candidate,
                MacLocalXPCIdentityV1.agentSigningIdentifier
            ) == MCLocalXPCResultOK else {
                MCLocalXPCSessionCancelOwned(candidate)
                throw MacLocalXPCConstructionErrorV1.peerRequirement
            }
            MCLocalXPCSessionSetCancelHandler(candidate) { [weak self] in
                self?.handleInvalidation()
            }
            guard MCLocalXPCSessionActivate(candidate)
                    == MCLocalXPCResultOK else {
                MCLocalXPCSessionCancelOwned(candidate)
                throw MacLocalXPCConstructionErrorV1.activation
            }
            session = candidate
            MCLocalXPCSessionSendHello(candidate) { [weak self] reply, error in
                let exactAcknowledgement: Bool
                if let reply {
                    exactAcknowledgement =
                        MCLocalXPCMessageIsExactHelloAcknowledgement(reply)
                } else {
                    exactAcknowledgement = false
                }
                self?.handleHelloReply(
                    exactAcknowledgement: exactAcknowledgement,
                    hadError: error
                )
            }
        }
    }

    public func cancel() {
        queue.sync {
            guard let session else { return }
            self.session = nil
            gate.invalidate()
            MCLocalXPCSessionCancelOwned(session)
        }
    }

    private func handleHelloReply(
        exactAcknowledgement: Bool,
        hadError: Bool
    ) {
        guard !hadError, gate.receive(exactHello: exactAcknowledgement)
                == .acknowledgeAndAuthenticate else {
            guard let session else { return }
            gate.invalidate()
            self.session = nil
            MCLocalXPCSessionCancelOwned(session)
            onEvent(.invalidated)
            return
        }
        onEvent(.authenticatedAgent)
    }

    private func handleInvalidation() {
        guard let session else { return }
        let shouldNotify = gate.state != .invalidated
        gate.invalidate()
        self.session = nil
        MCLocalXPCSessionRelease(session)
        if shouldNotify {
            onEvent(.invalidated)
        }
    }
}
