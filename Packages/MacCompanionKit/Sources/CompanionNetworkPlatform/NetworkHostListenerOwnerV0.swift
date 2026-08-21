import Dispatch
import Foundation
import Network

public enum NetworkHostListenerOwnerErrorV0:
    Error,
    Equatable,
    Sendable
{
    case alreadyStarted
}

public enum NetworkHostListenerTerminationReasonV0:
    String,
    Equatable,
    Sendable
{
    case localCancel
    case listenerFailed
    case listenerCancelled
    case unknownListenerState
}

enum NetworkHostListenerIOStateV0: Equatable, Sendable {
    case setup
    case waiting
    case ready
    case failed
    case cancelled
    case invalid
}

protocol NetworkHostListenerIOV0: Sendable {
    func setStateUpdateHandler(
        _ handler: @escaping @Sendable (
            NetworkHostListenerIOStateV0
        ) -> Void
    )
    func setNewConnectionHandler(
        _ handler: @escaping @Sendable (NWConnection) -> Void
    )
    func setServiceRegistrationUpdateHandler(
        _ handler: @escaping @Sendable (Bool) -> Void
    )
    func start(queue: DispatchQueue)
    func cancel()
}

private final class NetworkHostNWListenerIOV0:
    NetworkHostListenerIOV0,
    @unchecked Sendable
{
    private let listener: NWListener
    private let lock = NSLock()
    private var advertisedEndpoints: Set<NWEndpoint> = []

    init(listener: NWListener) {
        self.listener = listener
    }

    func setStateUpdateHandler(
        _ handler: @escaping @Sendable (
            NetworkHostListenerIOStateV0
        ) -> Void
    ) {
        listener.stateUpdateHandler = { state in
            switch state {
            case .setup:
                handler(.setup)
            case .waiting:
                handler(.waiting)
            case .ready:
                handler(.ready)
            case .failed:
                handler(.failed)
            case .cancelled:
                handler(.cancelled)
            @unknown default:
                handler(.invalid)
            }
        }
    }

    func setNewConnectionHandler(
        _ handler: @escaping @Sendable (NWConnection) -> Void
    ) {
        listener.newConnectionHandler = handler
    }

    func setServiceRegistrationUpdateHandler(
        _ handler: @escaping @Sendable (Bool) -> Void
    ) {
        listener.serviceRegistrationUpdateHandler = { [weak self] change in
            guard let self else { return }
            let readiness = lock.withLock {
                let wasReady = !advertisedEndpoints.isEmpty
                switch change {
                case let .add(endpoint):
                    advertisedEndpoints.insert(endpoint)
                case let .remove(endpoint):
                    advertisedEndpoints.remove(endpoint)
                @unknown default:
                    advertisedEndpoints.removeAll()
                }
                let isReady = !advertisedEndpoints.isEmpty
                return wasReady == isReady ? nil : isReady
            }
            if let readiness { handler(readiness) }
        }
    }

    func start(queue: DispatchQueue) {
        listener.start(queue: queue)
    }

    func cancel() {
        listener.cancel()
    }
}

/// Sole lifecycle owner for the sealed host listener. Every accepted
/// connection is wrapped immediately in a one-shot authority bound to this
/// listener's configured SPKI and fingerprint. Pending, not-yet-transferred
/// connections are cancelled when the listener terminates.
public final class NetworkHostListenerOwnerV0: @unchecked Sendable {
    private enum State {
        case idle
        case running
        case terminal
    }

    private let lock = NSLock()
    private let io: any NetworkHostListenerIOV0
    private let servedSubjectPublicKeyInfoDER: Data
    private let requiredHostFingerprint: Data
    private let metadataEvaluator: NetworkHostTLSMetadataEvaluatingV0
    private var state: State = .idle
    private var acceptedHandler: (@Sendable (
        NetworkHostAcceptedConnectionV0
    ) -> Void)?
    private var readyHandler: (@Sendable () -> Void)?
    private var terminalHandler: (@Sendable (
        NetworkHostListenerTerminationReasonV0
    ) -> Void)?
    private var advertisementHandler: (@Sendable (Bool) -> Void)?
    private var pending: [UUID: NetworkHostAcceptedConnectionV0] = [:]

    convenience init(
        listener: NWListener,
        servedSubjectPublicKeyInfoDER: Data,
        requiredHostFingerprint: Data,
        metadataEvaluator: @escaping NetworkHostTLSMetadataEvaluatingV0
    ) {
        self.init(
            io: NetworkHostNWListenerIOV0(listener: listener),
            servedSubjectPublicKeyInfoDER: servedSubjectPublicKeyInfoDER,
            requiredHostFingerprint: requiredHostFingerprint,
            metadataEvaluator: metadataEvaluator
        )
    }

    init(
        io: any NetworkHostListenerIOV0,
        servedSubjectPublicKeyInfoDER: Data,
        requiredHostFingerprint: Data,
        metadataEvaluator: @escaping NetworkHostTLSMetadataEvaluatingV0
    ) {
        self.io = io
        self.servedSubjectPublicKeyInfoDER = servedSubjectPublicKeyInfoDER
        self.requiredHostFingerprint = requiredHostFingerprint
        self.metadataEvaluator = metadataEvaluator
    }

    public func start(
        queue: DispatchQueue,
        ready: @escaping @Sendable () -> Void = {},
        advertisementChanged: @escaping @Sendable (Bool) -> Void = { _ in },
        accepted: @escaping @Sendable (
            NetworkHostAcceptedConnectionV0
        ) -> Void,
        terminal: @escaping @Sendable (
            NetworkHostListenerTerminationReasonV0
        ) -> Void = { _ in }
    ) throws {
        lock.lock()
        guard case .idle = state else {
            lock.unlock()
            throw NetworkHostListenerOwnerErrorV0.alreadyStarted
        }
        state = .running
        readyHandler = ready
        advertisementHandler = advertisementChanged
        acceptedHandler = accepted
        terminalHandler = terminal
        lock.unlock()

        io.setStateUpdateHandler { [weak self] state in
            self?.listenerStateChanged(state)
        }
        io.setNewConnectionHandler { [weak self] connection in
            self?.accepted(connection)
        }
        io.setServiceRegistrationUpdateHandler { [weak self] ready in
            self?.advertisementChanged(ready)
        }
        io.start(queue: queue)
    }

    public func cancel() {
        terminate(reason: .localCancel, cancelListener: true)
    }

    private func accepted(_ connection: NWConnection) {
        lock.lock()
        guard case .running = state else {
            lock.unlock()
            connection.cancel()
            return
        }
        let token = UUID()
        let authority = NetworkHostAcceptedConnectionV0(
            connection: connection,
            servedSubjectPublicKeyInfoDER: servedSubjectPublicKeyInfoDER,
            requiredHostFingerprint: requiredHostFingerprint,
            metadataEvaluator: metadataEvaluator,
            ownershipEnded: { [weak self] in
                self?.removePending(token)
            }
        )
        pending[token] = authority
        let handler = acceptedHandler
        lock.unlock()
        handler?(authority)
    }

    private func removePending(_ token: UUID) {
        lock.lock()
        pending.removeValue(forKey: token)
        lock.unlock()
    }

    private func advertisementChanged(_ ready: Bool) {
        lock.lock()
        guard case .running = state else {
            lock.unlock()
            return
        }
        let advertisement = advertisementHandler
        lock.unlock()
        advertisement?(ready)
    }

    private func listenerStateChanged(_ listenerState: NetworkHostListenerIOStateV0) {
        switch listenerState {
        case .setup, .waiting:
            break
        case .ready:
            lock.lock()
            guard case .running = state else {
                lock.unlock()
                return
            }
            let ready = readyHandler
            readyHandler = nil
            lock.unlock()
            ready?()
        case .failed:
            terminate(reason: .listenerFailed, cancelListener: true)
        case .cancelled:
            terminate(
                reason: .listenerCancelled,
                cancelListener: false
            )
        case .invalid:
            terminate(
                reason: .unknownListenerState,
                cancelListener: true
            )
        }
    }

    private func terminate(
        reason: NetworkHostListenerTerminationReasonV0,
        cancelListener: Bool
    ) {
        lock.lock()
        let mayTerminate: Bool
        switch state {
        case .idle, .running:
            mayTerminate = true
        case .terminal:
            mayTerminate = false
        }
        guard mayTerminate else {
            lock.unlock()
            return
        }
        state = .terminal
        let pending = Array(pending.values)
        self.pending.removeAll()
        let terminal = terminalHandler
        readyHandler = nil
        advertisementHandler = nil
        acceptedHandler = nil
        terminalHandler = nil
        lock.unlock()

        if cancelListener { io.cancel() }
        for authority in pending { authority.cancel() }
        terminal?(reason)
    }
}
