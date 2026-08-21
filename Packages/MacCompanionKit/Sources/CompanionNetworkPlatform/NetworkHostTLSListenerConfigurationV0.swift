import CompanionDiscovery
import CompanionHostPlatform
import CompanionSecurity
import Foundation
import Network
import Security

public enum NetworkHostTLSListenerConfigurationErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidConfiguration
    case certificateInvalid
    case identityMismatch
    case protocolIdentityCreationFailed
    case listenerAlreadyCreated
}

public struct NetworkHostTLSListenerConfigurationFactsV0:
    Equatable,
    Sendable
{
    public let minimumTLSMajor: UInt16
    public let minimumTLSMinor: UInt16
    public let maximumTLSMajor: UInt16
    public let maximumTLSMinor: UInt16
    public let resumptionEnabled: Bool
    public let earlyDataEnabled: Bool
    public let localEndpointReuse: Bool

    public static let required = Self(
        minimumTLSMajor: 1,
        minimumTLSMinor: 3,
        maximumTLSMajor: 1,
        maximumTLSMinor: 3,
        resumptionEnabled: false,
        earlyDataEnabled: false,
        localEndpointReuse: false
    )
}

public struct NetworkHostBonjourConfigurationFactsV0:
    Equatable,
    Sendable
{
    public let instanceName: String
    public let serviceType: String
    public let domain: String
    public let protocolMajor: String
    public let hostHint: String
}

/// Builds the exact host-side TLS parameters from a strictly issued host
/// identity. Mutable parameters never escape. The configuration creates one
/// unstarted sealed listener owner, which wraps every accepted connection in
/// an authority that extracts negotiated metadata from that exact object.
public final class NetworkHostTLSListenerConfigurationV0:
    @unchecked Sendable
{
    public let hostFingerprint: Data
    public let certificateDER: Data
    public let facts: NetworkHostTLSListenerConfigurationFactsV0
    public let bonjourFacts: NetworkHostBonjourConfigurationFactsV0

    private let lock = NSLock()
    private let parameters: NWParameters
    private let servedSubjectPublicKeyInfoDER: Data
    private var listenerCreated = false

    public init(
        issuedIdentity: SecurityHostIssuedIdentityV0,
        requiredHostFingerprint: Data,
        wallNowUnixMilliseconds: Int64
    ) throws {
        guard requiredHostFingerprint.count == 32 else {
            throw NetworkHostTLSListenerConfigurationErrorV0
                .invalidConfiguration
        }
        let inspection: HostIdentityCertificateInspectionV0
        do {
            inspection = try HostIdentityCertificateInspectorV0.inspect(
                certificateDER: issuedIdentity.certificateDER,
                wallNowUnixMilliseconds: wallNowUnixMilliseconds
            )
        } catch {
            throw NetworkHostTLSListenerConfigurationErrorV0
                .certificateInvalid
        }
        let observedFingerprint: Data
        do {
            observedFingerprint = try CompanionSecurityV0.hostFingerprint(
                subjectPublicKeyInfoDER: inspection.subjectPublicKeyInfoDER
            )
        } catch {
            throw NetworkHostTLSListenerConfigurationErrorV0
                .certificateInvalid
        }
        guard inspection.publicKeyX963
                == issuedIdentity.key.publicKeyX963,
              inspection.subjectPublicKeyInfoDER
                == issuedIdentity.key.subjectPublicKeyInfoDER,
              inspection.validity == issuedIdentity.validity,
              observedFingerprint == issuedIdentity.key.hostFingerprint,
              observedFingerprint == requiredHostFingerprint else {
            throw NetworkHostTLSListenerConfigurationErrorV0.identityMismatch
        }
        guard let protocolIdentity = sec_identity_create(
            issuedIdentity.listenerIdentity.copySecIdentity()
        ) else {
            throw NetworkHostTLSListenerConfigurationErrorV0
                .protocolIdentityCreationFailed
        }

        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv13)
        sec_protocol_options_set_tls_resumption_enabled(options, false)
        sec_protocol_options_set_local_identity(options, protocolIdentity)

        let parameters = NWParameters(
            tls: tls,
            tcp: NWProtocolTCP.Options()
        )
        parameters.allowLocalEndpointReuse = false

        self.parameters = parameters
        servedSubjectPublicKeyInfoDER = inspection.subjectPublicKeyInfoDER
        hostFingerprint = observedFingerprint
        certificateDER = issuedIdentity.certificateDER
        facts = .required
        let hostHint = observedFingerprint.prefix(8).map {
            String(format: "%02x", $0)
        }.joined()
        bonjourFacts = NetworkHostBonjourConfigurationFactsV0(
            instanceName: "mac-\(hostHint)",
            serviceType: BonjourDiscoveryProfile.serviceType,
            domain: BonjourDiscoveryProfile.domain,
            protocolMajor: "0",
            hostHint: hostHint
        )
    }

    /// Creates at most one listener from the sealed TLS parameters. Creation
    /// does not start the listener; only the Agent lifecycle owner may later
    /// install handlers and call `start(queue:)`.
    public func makeUnstartedListenerOwner(
        port: NWEndpoint.Port
    ) throws -> NetworkHostListenerOwnerV0 {
        lock.lock()
        defer { lock.unlock() }
        guard !listenerCreated else {
            throw NetworkHostTLSListenerConfigurationErrorV0
                .listenerAlreadyCreated
        }
        let listener = try NWListener(using: parameters, on: port)
        listener.service = NWListener.Service(
            name: bonjourFacts.instanceName,
            type: bonjourFacts.serviceType,
            domain: bonjourFacts.domain,
            txtRecord: NWTXTRecord([
                BonjourDiscoveryProfile.protocolMajorKey:
                    bonjourFacts.protocolMajor,
                BonjourDiscoveryProfile.hostHintKey:
                    bonjourFacts.hostHint,
            ])
        )
        listenerCreated = true
        return NetworkHostListenerOwnerV0(
            listener: listener,
            servedSubjectPublicKeyInfoDER: servedSubjectPublicKeyInfoDER,
            requiredHostFingerprint: hostFingerprint,
            metadataEvaluator: NetworkHostTLSMetadataExtractorV0.extract
        )
    }
}
