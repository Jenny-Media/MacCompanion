import CompanionSecurity
import Foundation

public enum PinnedTLSConnectionRole: String, Equatable, Sendable {
    case pairingPrimary
    case applicationPrimary
    case interactiveInput
    case interactiveMedia
}

public enum PinnedTLSConnectionPhase: String, Equatable, Sendable {
    case awaitingTCP
    case awaitingPinnedTLS
    case awaitingRoleAuthentication
    case ready
    case closed
}

public enum PinnedTLSTrafficClass: String, Equatable, Sendable {
    case pairingHandshake
    case applicationAuthentication
    case interactiveChannelAuthentication
    case commandFrame
    case eventFrame
    case inputFrame
    case mediaRecord
}

public enum PinnedTLSAuthorityError: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidPeerEvidence
    case invalidTransition(PinnedTLSConnectionPhase)
    case unsupportedTLSVersion
    case earlyDataAccepted
    case pinnedLeafPolicyRejected
    case hostFingerprintMismatch
    case trafficNotAuthorized(
        role: PinnedTLSConnectionRole,
        phase: PinnedTLSConnectionPhase,
        traffic: PinnedTLSTrafficClass
    )
}

public struct TLSPeerEvidence: Equatable, Sendable {
    public let negotiatedTLSMajor: UInt16
    public let negotiatedTLSMinor: UInt16
    public let earlyDataAccepted: Bool
    public let pinnedLeafPolicyAccepted: Bool
    public let subjectPublicKeyInfoDER: Data

    public init(
        negotiatedTLSMajor: UInt16,
        negotiatedTLSMinor: UInt16,
        earlyDataAccepted: Bool,
        pinnedLeafPolicyAccepted: Bool,
        subjectPublicKeyInfoDER: Data
    ) {
        self.negotiatedTLSMajor = negotiatedTLSMajor
        self.negotiatedTLSMinor = negotiatedTLSMinor
        self.earlyDataAccepted = earlyDataAccepted
        self.pinnedLeafPolicyAccepted = pinnedLeafPolicyAccepted
        self.subjectPublicKeyInfoDER = subjectPublicKeyInfoDER
    }
}

public struct HostTLSListenerEvidence: Equatable, Sendable {
    public let negotiatedTLSMajor: UInt16
    public let negotiatedTLSMinor: UInt16
    public let earlyDataAccepted: Bool
    public let servedSubjectPublicKeyInfoDER: Data

    public init(
        negotiatedTLSMajor: UInt16,
        negotiatedTLSMinor: UInt16,
        earlyDataAccepted: Bool,
        servedSubjectPublicKeyInfoDER: Data
    ) {
        self.negotiatedTLSMajor = negotiatedTLSMajor
        self.negotiatedTLSMinor = negotiatedTLSMinor
        self.earlyDataAccepted = earlyDataAccepted
        self.servedSubjectPublicKeyInfoDER = servedSubjectPublicKeyInfoDER
    }
}

public enum HostTLSListenerBindingError: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidEvidence
    case unsupportedTLSVersion
    case earlyDataAccepted
    case servedHostIdentityMismatch
}

/// Validated facts for one accepted host-side application connection.
///
/// This is deliberately separate from `PinnedTLSConnectionAuthority`: the
/// client pins the host certificate, while the host authenticates the client
/// at the application layer. This value proves only that the listener served
/// the expected host identity with the required TLS profile.
public struct HostApplicationTLSBinding: Equatable, Sendable {
    public let hostFingerprint: Data

    public init(
        evidence: HostTLSListenerEvidence,
        requiredHostFingerprint: Data
    ) throws {
        guard requiredHostFingerprint.count == 32 else {
            throw HostTLSListenerBindingError.invalidConfiguration
        }
        guard evidence.negotiatedTLSMajor == 1,
              evidence.negotiatedTLSMinor == 3 else {
            throw HostTLSListenerBindingError.unsupportedTLSVersion
        }
        guard !evidence.earlyDataAccepted else {
            throw HostTLSListenerBindingError.earlyDataAccepted
        }
        let observed: Data
        do {
            observed = try CompanionSecurityV0.hostFingerprint(
                subjectPublicKeyInfoDER: evidence.servedSubjectPublicKeyInfoDER
            )
        } catch {
            throw HostTLSListenerBindingError.invalidEvidence
        }
        guard observed == requiredHostFingerprint else {
            throw HostTLSListenerBindingError.servedHostIdentityMismatch
        }
        hostFingerprint = observed
    }
}

/// Bundle-independent admission authority for one TLS connection.
///
/// The Network.framework adapter must produce `TLSPeerEvidence` from the live
/// connection's verify block. No application bytes are admitted before this
/// type has independently recomputed and matched the pinned SPKI fingerprint.
public struct PinnedTLSConnectionAuthority: Equatable, Sendable {
    public static let maximumSubjectPublicKeyInfoBytes =
        CompanionSecurityV0.maximumSubjectPublicKeyInfoBytes

    public let role: PinnedTLSConnectionRole
    public let requiredHostFingerprint: Data
    public private(set) var phase: PinnedTLSConnectionPhase = .awaitingTCP
    public private(set) var observedHostFingerprint: Data?

    public init(role: PinnedTLSConnectionRole, requiredHostFingerprint: Data) throws {
        guard requiredHostFingerprint.count == 32 else {
            throw PinnedTLSAuthorityError.invalidConfiguration
        }
        self.role = role
        self.requiredHostFingerprint = requiredHostFingerprint
    }

    public static func hostFingerprint(subjectPublicKeyInfoDER: Data) throws -> Data {
        do {
            return try CompanionSecurityV0.hostFingerprint(
                subjectPublicKeyInfoDER: subjectPublicKeyInfoDER
            )
        } catch {
            throw PinnedTLSAuthorityError.invalidPeerEvidence
        }
    }

    public mutating func didConnectTCP() throws {
        guard phase == .awaitingTCP else { throw invalidTransition() }
        phase = .awaitingPinnedTLS
    }

    public mutating func acceptPeer(_ evidence: TLSPeerEvidence) throws {
        guard phase == .awaitingPinnedTLS else { throw invalidTransition() }
        do {
            guard evidence.negotiatedTLSMajor == 1,
                  evidence.negotiatedTLSMinor == 3 else {
                throw PinnedTLSAuthorityError.unsupportedTLSVersion
            }
            guard !evidence.earlyDataAccepted else {
                throw PinnedTLSAuthorityError.earlyDataAccepted
            }
            guard evidence.pinnedLeafPolicyAccepted else {
                throw PinnedTLSAuthorityError.pinnedLeafPolicyRejected
            }
            let observed = try Self.hostFingerprint(
                subjectPublicKeyInfoDER: evidence.subjectPublicKeyInfoDER
            )
            observedHostFingerprint = observed
            guard observed == requiredHostFingerprint else {
                throw PinnedTLSAuthorityError.hostFingerprintMismatch
            }
            phase = .awaitingRoleAuthentication
        } catch {
            phase = .closed
            throw error
        }
    }

    public mutating func admit(_ traffic: PinnedTLSTrafficClass) throws {
        let permitted: Bool
        switch (phase, role, traffic) {
        case (.awaitingRoleAuthentication, .pairingPrimary, .pairingHandshake),
             (.awaitingRoleAuthentication, .applicationPrimary, .applicationAuthentication),
             (.awaitingRoleAuthentication, .interactiveInput, .interactiveChannelAuthentication),
             (.awaitingRoleAuthentication, .interactiveMedia, .interactiveChannelAuthentication),
             (.ready, .applicationPrimary, .commandFrame),
             (.ready, .applicationPrimary, .eventFrame),
             (.ready, .interactiveInput, .inputFrame),
             (.ready, .interactiveMedia, .mediaRecord):
            permitted = true
        default:
            permitted = false
        }
        guard permitted else {
            let rejectedPhase = phase
            phase = .closed
            throw PinnedTLSAuthorityError.trafficNotAuthorized(
                role: role,
                phase: rejectedPhase,
                traffic: traffic
            )
        }
    }

    public mutating func roleAuthenticationSucceeded() throws {
        guard phase == .awaitingRoleAuthentication else { throw invalidTransition() }
        phase = .ready
    }

    public mutating func close() {
        phase = .closed
    }

    private func invalidTransition() -> PinnedTLSAuthorityError {
        .invalidTransition(phase)
    }
}
