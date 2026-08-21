import CompanionDiscovery
import CompanionTransport
import Dispatch
import Foundation
import Network
@preconcurrency import Security

public enum NetworkClientTLSAttemptContextErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidConfiguration
    case connectionAlreadyCreated
    case verificationUnavailable
    case verificationRejected
    case wrongConnection
    case handoffAlreadyConsumed
}

public enum NetworkClientTLSVerificationStatusV0:
    String,
    Equatable,
    Sendable
{
    case pending
    case accepted
    case rejected
    case consumed
}

/// A successful evaluator result means the live leaf passed the complete Mac
/// Companion pinned-leaf certificate profile. The callback still independently
/// binds the exact SPKI to `requiredHostFingerprint` before accepting TLS.
public typealias NetworkClientPinnedLeafEvaluatorV0 = @Sendable (
    SecTrust
) throws -> Data

private final class NetworkClientTLSVerificationStateV0:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var statusValue: NetworkClientTLSVerificationStatusV0 = .pending
    private var handoff: NetworkClientVerifiedTLSHandoffV0?

    func accept(_ value: NetworkClientVerifiedTLSHandoffV0) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard statusValue == .pending else { return false }
        handoff = value
        statusValue = .accepted
        return true
    }

    func reject() {
        lock.lock()
        defer { lock.unlock() }
        guard statusValue == .pending else { return }
        statusValue = .rejected
    }

    func status() -> NetworkClientTLSVerificationStatusV0 {
        lock.lock()
        defer { lock.unlock() }
        return statusValue
    }

    func consume() throws -> NetworkClientVerifiedTLSHandoffV0 {
        lock.lock()
        defer { lock.unlock() }
        switch statusValue {
        case .pending:
            throw NetworkClientTLSAttemptContextErrorV0.verificationUnavailable
        case .rejected:
            throw NetworkClientTLSAttemptContextErrorV0.verificationRejected
        case .consumed:
            throw NetworkClientTLSAttemptContextErrorV0.handoffAlreadyConsumed
        case .accepted:
            guard let handoff else {
                throw NetworkClientTLSAttemptContextErrorV0.verificationUnavailable
            }
            self.handoff = nil
            statusValue = .consumed
            return handoff
        }
    }
}

/// Role-neutral proof that the live connection's TLS callback accepted the
/// strict TLS profile and immutable paired-host pin. It grants no application,
/// pairing, input, or media traffic; the consuming role authority must replay
/// the evidence and complete its own authentication transition.
private struct NetworkClientVerifiedTLSHandoffV0: Sendable {
    let evidence: TLSPeerEvidence
    let hostFingerprint: Data

    init(
        evidence: TLSPeerEvidence,
        requiredHostFingerprint: Data
    ) throws {
        var authority = try PinnedTLSConnectionAuthority(
            role: .applicationPrimary,
            requiredHostFingerprint: requiredHostFingerprint
        )
        try authority.didConnectTCP()
        try authority.acceptPeer(evidence)
        guard authority.phase == .awaitingRoleAuthentication,
              authority.observedHostFingerprint
                == requiredHostFingerprint else {
            throw NetworkClientTLSAttemptContextErrorV0.invalidConfiguration
        }
        self.evidence = evidence
        hostFingerprint = requiredHostFingerprint
    }
}

/// One-shot construction authority tying one TLS verification callback, one
/// immutable paired-host pin, and one `NWConnection` object together. Creating
/// the context or connection starts no network activity. A caller may consume
/// the verified handoff only for that exact connection after it reaches ready.
public final class NetworkClientTLSAttemptContextV0: @unchecked Sendable {
    public let endpoint: EndpointCandidate
    public let requiredHostFingerprint: Data

    private let lock = NSLock()
    private let tlsOptions: NWProtocolTLS.Options
    private let verificationState: NetworkClientTLSVerificationStateV0
    private var createdConnection: NWConnection?
    private var handoffConsumed = false

    public init(
        endpoint: EndpointCandidate,
        requiredHostFingerprint: Data,
        verificationQueue: DispatchQueue,
        pinnedLeafEvaluator: @escaping NetworkClientPinnedLeafEvaluatorV0
    ) throws {
        guard requiredHostFingerprint.count == 32 else {
            throw NetworkClientTLSAttemptContextErrorV0.invalidConfiguration
        }
        self.endpoint = endpoint
        self.requiredHostFingerprint = requiredHostFingerprint

        let state = NetworkClientTLSVerificationStateV0()
        verificationState = state
        let tls = NWProtocolTLS.Options()
        tlsOptions = tls
        let securityOptions = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(
            securityOptions,
            .TLSv13
        )
        sec_protocol_options_set_max_tls_protocol_version(
            securityOptions,
            .TLSv13
        )
        sec_protocol_options_set_tls_resumption_enabled(
            securityOptions,
            false
        )
        sec_protocol_options_set_verify_block(
            securityOptions,
            { metadata, trust, complete in
                guard sec_protocol_metadata_get_negotiated_tls_protocol_version(
                    metadata
                ) == .TLSv13,
                !sec_protocol_metadata_get_early_data_accepted(metadata)
                else {
                    state.reject()
                    complete(false)
                    return
                }
                do {
                    let trustReference = sec_trust_copy_ref(trust)
                    let spki = try pinnedLeafEvaluator(
                        trustReference.takeRetainedValue()
                    )
                    let evidence = TLSPeerEvidence(
                        negotiatedTLSMajor: 1,
                        negotiatedTLSMinor: 3,
                        earlyDataAccepted: false,
                        pinnedLeafPolicyAccepted: true,
                        subjectPublicKeyInfoDER: spki
                    )
                    let handoff = try NetworkClientVerifiedTLSHandoffV0(
                        evidence: evidence,
                        requiredHostFingerprint: requiredHostFingerprint
                    )
                    let accepted = state.accept(handoff)
                    complete(accepted)
                } catch {
                    state.reject()
                    complete(false)
                }
            },
            verificationQueue
        )
    }

    public func makeUnstartedConnection() throws -> NWConnection {
        lock.lock()
        defer { lock.unlock() }
        guard createdConnection == nil else {
            throw NetworkClientTLSAttemptContextErrorV0
                .connectionAlreadyCreated
        }
        let parameters = NWParameters(
            tls: tlsOptions,
            tcp: NWProtocolTCP.Options()
        )
        parameters.allowLocalEndpointReuse = false
        let connection = NWConnection(
            to: try Self.networkEndpoint(endpoint),
            using: parameters
        )
        createdConnection = connection
        return connection
    }

    public func verificationStatus() -> NetworkClientTLSVerificationStatusV0 {
        verificationState.status()
    }

    public func consumeVerifiedHandoff(
        for connection: NWConnection
    ) throws -> NetworkClientApplicationTLSHandoffV0 {
        lock.lock()
        defer { lock.unlock() }
        guard let createdConnection, createdConnection === connection else {
            throw NetworkClientTLSAttemptContextErrorV0.wrongConnection
        }
        guard !handoffConsumed else {
            throw NetworkClientTLSAttemptContextErrorV0.handoffAlreadyConsumed
        }
        let verified = try verificationState.consume()
        handoffConsumed = true
        return try NetworkClientApplicationTLSHandoffV0(
            evidence: verified.evidence,
            requiredHostFingerprint: verified.hostFingerprint
        )
    }

    package func consumeVerifiedPeerEvidence(
        for connection: NWConnection
    ) throws -> TLSPeerEvidence {
        lock.lock()
        defer { lock.unlock() }
        guard let createdConnection, createdConnection === connection else {
            throw NetworkClientTLSAttemptContextErrorV0.wrongConnection
        }
        guard !handoffConsumed else {
            throw NetworkClientTLSAttemptContextErrorV0.handoffAlreadyConsumed
        }
        let verified = try verificationState.consume()
        handoffConsumed = true
        return verified.evidence
    }

    private static func networkEndpoint(
        _ endpoint: EndpointCandidate
    ) throws -> NWEndpoint {
        guard let port = NWEndpoint.Port(rawValue: endpoint.port) else {
            throw NetworkClientTLSAttemptContextErrorV0.invalidConfiguration
        }
        switch endpoint.kind {
        case .bonjour:
            let suffix = ".\(BonjourDiscoveryProfile.serviceType).\(BonjourDiscoveryProfile.domain)"
            guard endpoint.value.hasSuffix(suffix) else {
                throw NetworkClientTLSAttemptContextErrorV0.invalidConfiguration
            }
            let name = String(endpoint.value.dropLast(suffix.count))
            return .service(
                name: name,
                type: BonjourDiscoveryProfile.serviceType,
                domain: BonjourDiscoveryProfile.domain,
                interface: nil
            )
        case .ipv4, .ipv6, .dns:
            return .hostPort(
                host: NWEndpoint.Host(endpoint.value),
                port: port
            )
        }
    }
}
