import Foundation

public enum HostIdentityKeyAvailability: Equatable, Sendable {
    case missing
    case unavailableBeforeFirstUnlock
    case available(publicKeyX963: Data)
    case invalid
}

public enum HostIdentityCertificateAvailability: Equatable, Sendable {
    case missing
    case invalid
    case available(
        subjectPublicKeyInfoDER: Data,
        notBeforeUnixMilliseconds: Int64,
        notAfterUnixMilliseconds: Int64
    )
}

public struct HostIdentityInventory: Equatable, Sendable {
    public let establishedIdentity: Bool
    public let key: HostIdentityKeyAvailability
    public let certificate: HostIdentityCertificateAvailability

    public init(
        establishedIdentity: Bool,
        key: HostIdentityKeyAvailability,
        certificate: HostIdentityCertificateAvailability
    ) {
        self.establishedIdentity = establishedIdentity
        self.key = key
        self.certificate = certificate
    }
}

public enum HostCertificateIssueReason: String, Equatable, Sendable {
    case bootstrapContinuation
    case missing
    case invalid
    case keyMismatch
    case notCurrentlyValid
    case lifetimeOutOfProfile
}

public enum HostIdentityRecoveryReason: String, Equatable, Sendable {
    case missingEstablishedKey
    case invalidEstablishedKey
}

public enum HostIdentityLifecycleDisposition: Equatable, Sendable {
    case bootstrapNewIdentity
    case waitForFirstUnlock
    case requireLocalRecovery(HostIdentityRecoveryReason)
    case issueCertificate(
        hostFingerprint: Data,
        reason: HostCertificateIssueReason
    )
    case ready(
        hostFingerprint: Data,
        certificateNotAfterUnixMilliseconds: Int64,
        renewalRecommended: Bool
    )
}

public enum HostIdentityLifecycleError: Error, Equatable, Sendable {
    case invalidTime
}

public enum HostIdentityLifecycleV0 {
    public static let renewalWindowMilliseconds: Int64 = 30 * 24 * 60 * 60 * 1_000
    public static let certificateLifetimeMilliseconds: Int64 = 90 * 24 * 60 * 60 * 1_000
    public static let notBeforeBackdateMilliseconds: Int64 = 5 * 60 * 1_000
    public static let maximumCertificateIntervalMilliseconds: Int64 =
        certificateLifetimeMilliseconds + notBeforeBackdateMilliseconds
    public static let maximumSafeUnixMilliseconds: Int64 = 9_007_199_254_740_991

    public static func evaluate(
        _ inventory: HostIdentityInventory,
        wallNowUnixMilliseconds: Int64
    ) throws -> HostIdentityLifecycleDisposition {
        guard wallNowUnixMilliseconds >= 0,
              wallNowUnixMilliseconds <= maximumSafeUnixMilliseconds else {
            throw HostIdentityLifecycleError.invalidTime
        }

        switch inventory.key {
        case .unavailableBeforeFirstUnlock:
            return .waitForFirstUnlock
        case .missing:
            return inventory.establishedIdentity
                ? .requireLocalRecovery(.missingEstablishedKey)
                : .bootstrapNewIdentity
        case .invalid:
            return inventory.establishedIdentity
                ? .requireLocalRecovery(.invalidEstablishedKey)
                : .bootstrapNewIdentity
        case let .available(publicKeyX963):
            let expectedSPKI: Data
            let fingerprint: Data
            do {
                expectedSPKI = try CompanionSecurityV0.p256SubjectPublicKeyInfoDER(
                    publicKeyX963: publicKeyX963
                )
                fingerprint = try CompanionSecurityV0.hostFingerprint(
                    subjectPublicKeyInfoDER: expectedSPKI
                )
            } catch {
                return inventory.establishedIdentity
                    ? .requireLocalRecovery(.invalidEstablishedKey)
                    : .bootstrapNewIdentity
            }

            switch inventory.certificate {
            case .missing:
                return .issueCertificate(
                    hostFingerprint: fingerprint,
                    reason: inventory.establishedIdentity ? .missing : .bootstrapContinuation
                )
            case .invalid:
                return .issueCertificate(
                    hostFingerprint: fingerprint,
                    reason: .invalid
                )
            case let .available(spki, notBefore, notAfter):
                guard spki == expectedSPKI else {
                    return .issueCertificate(
                        hostFingerprint: fingerprint,
                        reason: .keyMismatch
                    )
                }
                guard notBefore >= 0,
                      notAfter > notBefore,
                      notAfter <= maximumSafeUnixMilliseconds,
                      notAfter - notBefore <= maximumCertificateIntervalMilliseconds else {
                    return .issueCertificate(
                        hostFingerprint: fingerprint,
                        reason: .lifetimeOutOfProfile
                    )
                }
                guard wallNowUnixMilliseconds >= notBefore,
                      wallNowUnixMilliseconds < notAfter else {
                    return .issueCertificate(
                        hostFingerprint: fingerprint,
                        reason: .notCurrentlyValid
                    )
                }
                return .ready(
                    hostFingerprint: fingerprint,
                    certificateNotAfterUnixMilliseconds: notAfter,
                    renewalRecommended: notAfter - wallNowUnixMilliseconds
                        <= renewalWindowMilliseconds
                )
            }
        }
    }
}
