import CompanionTransport
import Dispatch
import Foundation
import Network
import Security

public enum NetworkHostAcceptedConnectionErrorV0:
    Error,
    Equatable,
    Sendable
{
    case alreadyStarted
    case tlsMetadataUnavailable
    case verifiedConnectionAlreadyConsumed
}

public enum NetworkHostAcceptedConnectionTerminationReasonV0:
    String,
    Equatable,
    Sendable
{
    case localCancel
    case connectionFailed
    case connectionCancelled
    case unknownConnectionState
    case tlsMetadataUnavailable
    case tlsRejected
}

public struct NetworkHostTLSMetadataFactsV0: Equatable, Sendable {
    public let negotiatedTLSMajor: UInt16
    public let negotiatedTLSMinor: UInt16
    public let earlyDataAccepted: Bool

    public init(
        negotiatedTLSMajor: UInt16,
        negotiatedTLSMinor: UInt16,
        earlyDataAccepted: Bool
    ) {
        self.negotiatedTLSMajor = negotiatedTLSMajor
        self.negotiatedTLSMinor = negotiatedTLSMinor
        self.earlyDataAccepted = earlyDataAccepted
    }
}

public typealias NetworkHostTLSMetadataEvaluatingV0 = @Sendable (
    NWConnection
) throws -> NetworkHostTLSMetadataFactsV0

public enum NetworkHostTLSMetadataExtractorV0 {
    public static func extract(
        from connection: NWConnection
    ) throws -> NetworkHostTLSMetadataFactsV0 {
        guard let tls = connection.metadata(
            definition: NWProtocolTLS.definition
        ) as? NWProtocolTLS.Metadata else {
            throw NetworkHostAcceptedConnectionErrorV0
                .tlsMetadataUnavailable
        }
        let metadata = tls.securityProtocolMetadata
        let version = sec_protocol_metadata_get_negotiated_tls_protocol_version(
            metadata
        )
        let negotiated: (UInt16, UInt16)
        if version == .TLSv13 {
            negotiated = (1, 3)
        } else if version == .TLSv12 {
            negotiated = (1, 2)
        } else {
            negotiated = (0, 0)
        }
        return NetworkHostTLSMetadataFactsV0(
            negotiatedTLSMajor: negotiated.0,
            negotiatedTLSMinor: negotiated.1,
            earlyDataAccepted:
                sec_protocol_metadata_get_early_data_accepted(metadata)
        )
    }
}

enum NetworkHostAcceptedConnectionIOStateV0: Equatable, Sendable {
    case setup
    case preparing
    case waiting
    case ready
    case failed
    case cancelled
    case invalid
}

protocol NetworkHostAcceptedConnectionIOV0: Sendable {
    var connection: NWConnection { get }
    func setStateUpdateHandler(
        _ handler: @escaping @Sendable (
            NetworkHostAcceptedConnectionIOStateV0
        ) -> Void
    )
    func start(queue: DispatchQueue)
    func cancel()
}

private final class NetworkHostAcceptedNWConnectionIOV0:
    NetworkHostAcceptedConnectionIOV0,
    @unchecked Sendable
{
    let connection: NWConnection

    init(connection: NWConnection) {
        self.connection = connection
    }

    func setStateUpdateHandler(
        _ handler: @escaping @Sendable (
            NetworkHostAcceptedConnectionIOStateV0
        ) -> Void
    ) {
        connection.stateUpdateHandler = { state in
            switch state {
            case .setup:
                handler(.setup)
            case .preparing:
                handler(.preparing)
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

    func start(queue: DispatchQueue) {
        connection.start(queue: queue)
    }

    func cancel() {
        connection.cancel()
    }
}

/// A verified-ready host connection can only be produced by the exact
/// accepted-connection authority created by the sealed listener owner. Its
/// connection reference is intentionally internal so only this module can
/// construct a byte pump from the connection/binding pair.
public final class NetworkHostVerifiedReadyConnectionV0:
    @unchecked Sendable
{
    public let tlsBinding: HostApplicationTLSBinding
    private let lock = NSLock()
    private var connection: NWConnection?

    init(
        connection: NWConnection,
        tlsBinding: HostApplicationTLSBinding
    ) {
        self.connection = connection
        self.tlsBinding = tlsBinding
    }

    func consumeConnection() throws -> NWConnection {
        lock.lock()
        defer { lock.unlock() }
        guard let connection else {
            throw NetworkHostAcceptedConnectionErrorV0
                .verifiedConnectionAlreadyConsumed
        }
        self.connection = nil
        return connection
    }

    /// Terminates an unconsumed verified-ready connection when a later
    /// listener generation supersedes it before pump construction.
    public func cancel() {
        lock.lock()
        let connection = self.connection
        self.connection = nil
        lock.unlock()
        connection?.cancel()
    }
}

/// One-shot owner for a connection delivered by the sealed NWListener. It
/// starts that exact connection, waits for `.ready`, extracts negotiated TLS
/// metadata from the same object, binds the configured served SPKI, and only
/// then transfers a verified-ready connection to session composition.
public final class NetworkHostAcceptedConnectionV0: @unchecked Sendable {
    private enum State {
        case idle
        case running
        case transferred
        case terminal
    }

    private let lock = NSLock()
    private let io: any NetworkHostAcceptedConnectionIOV0
    private let servedSubjectPublicKeyInfoDER: Data
    private let requiredHostFingerprint: Data
    private let metadataEvaluator: NetworkHostTLSMetadataEvaluatingV0
    private let ownershipEnded: @Sendable () -> Void
    private var state: State = .idle
    private var readyHandler: (@Sendable (
        NetworkHostVerifiedReadyConnectionV0
    ) -> Void)?
    private var terminalHandler: (@Sendable (
        NetworkHostAcceptedConnectionTerminationReasonV0
    ) -> Void)?

    convenience init(
        connection: NWConnection,
        servedSubjectPublicKeyInfoDER: Data,
        requiredHostFingerprint: Data,
        metadataEvaluator: @escaping NetworkHostTLSMetadataEvaluatingV0,
        ownershipEnded: @escaping @Sendable () -> Void
    ) {
        self.init(
            io: NetworkHostAcceptedNWConnectionIOV0(
                connection: connection
            ),
            servedSubjectPublicKeyInfoDER: servedSubjectPublicKeyInfoDER,
            requiredHostFingerprint: requiredHostFingerprint,
            metadataEvaluator: metadataEvaluator,
            ownershipEnded: ownershipEnded
        )
    }

    init(
        io: any NetworkHostAcceptedConnectionIOV0,
        servedSubjectPublicKeyInfoDER: Data,
        requiredHostFingerprint: Data,
        metadataEvaluator: @escaping NetworkHostTLSMetadataEvaluatingV0,
        ownershipEnded: @escaping @Sendable () -> Void = {}
    ) {
        self.io = io
        self.servedSubjectPublicKeyInfoDER = servedSubjectPublicKeyInfoDER
        self.requiredHostFingerprint = requiredHostFingerprint
        self.metadataEvaluator = metadataEvaluator
        self.ownershipEnded = ownershipEnded
    }

    public func start(
        queue: DispatchQueue,
        ready: @escaping @Sendable (
            NetworkHostVerifiedReadyConnectionV0
        ) -> Void,
        terminal: @escaping @Sendable (
            NetworkHostAcceptedConnectionTerminationReasonV0
        ) -> Void = { _ in }
    ) throws {
        lock.lock()
        guard case .idle = state else {
            lock.unlock()
            throw NetworkHostAcceptedConnectionErrorV0.alreadyStarted
        }
        state = .running
        readyHandler = ready
        terminalHandler = terminal
        lock.unlock()

        io.setStateUpdateHandler { [weak self] state in
            self?.stateChanged(state)
        }
        io.start(queue: queue)
    }

    public func cancel() {
        terminate(reason: .localCancel, cancelConnection: true)
    }

    func matches(_ connection: NWConnection) -> Bool {
        io.connection === connection
    }

    private func stateChanged(
        _ connectionState: NetworkHostAcceptedConnectionIOStateV0
    ) {
        switch connectionState {
        case .setup, .preparing, .waiting:
            break
        case .ready:
            connectionReady()
        case .failed:
            terminate(reason: .connectionFailed, cancelConnection: true)
        case .cancelled:
            terminate(
                reason: .connectionCancelled,
                cancelConnection: false
            )
        case .invalid:
            terminate(
                reason: .unknownConnectionState,
                cancelConnection: true
            )
        }
    }

    private func connectionReady() {
        let binding: HostApplicationTLSBinding
        do {
            let metadata = try metadataEvaluator(io.connection)
            binding = try HostApplicationTLSBinding(
                evidence: HostTLSListenerEvidence(
                    negotiatedTLSMajor: metadata.negotiatedTLSMajor,
                    negotiatedTLSMinor: metadata.negotiatedTLSMinor,
                    earlyDataAccepted: metadata.earlyDataAccepted,
                    servedSubjectPublicKeyInfoDER:
                        servedSubjectPublicKeyInfoDER
                ),
                requiredHostFingerprint: requiredHostFingerprint
            )
        } catch NetworkHostAcceptedConnectionErrorV0
            .tlsMetadataUnavailable {
            terminate(
                reason: .tlsMetadataUnavailable,
                cancelConnection: true
            )
            return
        } catch {
            terminate(reason: .tlsRejected, cancelConnection: true)
            return
        }

        lock.lock()
        guard case .running = state else {
            lock.unlock()
            return
        }
        state = .transferred
        let ready = readyHandler
        readyHandler = nil
        terminalHandler = nil
        lock.unlock()

        ownershipEnded()
        ready?(
            NetworkHostVerifiedReadyConnectionV0(
                connection: io.connection,
                tlsBinding: binding
            )
        )
    }

    private func terminate(
        reason: NetworkHostAcceptedConnectionTerminationReasonV0,
        cancelConnection: Bool
    ) {
        lock.lock()
        let mayTerminate: Bool
        switch state {
        case .idle, .running:
            mayTerminate = true
        case .transferred, .terminal:
            mayTerminate = false
        }
        guard mayTerminate else {
            lock.unlock()
            return
        }
        state = .terminal
        let terminal = terminalHandler
        readyHandler = nil
        terminalHandler = nil
        lock.unlock()

        if cancelConnection { io.cancel() }
        ownershipEnded()
        terminal?(reason)
    }
}
