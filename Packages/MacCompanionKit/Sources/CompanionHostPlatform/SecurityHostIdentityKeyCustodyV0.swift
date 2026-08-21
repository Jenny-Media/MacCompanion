import CompanionSecurity
import Foundation
import Security

public enum SecurityHostIdentityKeyCustodyErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidConfiguration
    case keyCreationFailed
    case keyNotFound
    case keyUnavailableBeforeFirstUnlock
    case keyMismatch
    case signingFailed
    case certificateInvalid
    case identityCreationFailed
    case randomFailure(OSStatus)
    case deletionFailed(OSStatus)
}

public enum SecurityHostIdentityKeyProtectionV0:
    String,
    Equatable,
    Sendable
{
    case afterFirstUnlockThisDeviceOnly
}

public struct SecurityHostIdentityKeyCreationProfileV0:
    Equatable,
    Sendable
{
    public let protection: SecurityHostIdentityKeyProtectionV0
    public let requiresSecureEnclave: Bool
    public let requiresPrivateKeyUsage: Bool
    public let requiresUserPresence: Bool
    public let synchronizable: Bool
    public let exportable: Bool

    public static func required(
        requireSecureEnclave: Bool = true
    ) -> Self {
        Self(
            protection: .afterFirstUnlockThisDeviceOnly,
            requiresSecureEnclave: requireSecureEnclave,
            requiresPrivateKeyUsage: true,
            requiresUserPresence: false,
            synchronizable: false,
            exportable: false
        )
    }
}

public struct SecurityHostIdentityKeyCustodyConfigurationV0:
    Equatable,
    Sendable
{
    public static let maximumApplicationTagBytes = 128
    public static let maximumApplicationTagPrefixBytes = 86

    public let applicationTagPrefix: String
    public let requireSecureEnclave: Bool

    public init(
        applicationTagPrefix: String,
        requireSecureEnclave: Bool = true
    ) throws {
        guard (1...Self.maximumApplicationTagPrefixBytes)
                .contains(applicationTagPrefix.utf8.count),
              applicationTagPrefix.utf8.allSatisfy({ byte in
                  (0x30...0x39).contains(byte)
                      || (0x41...0x5A).contains(byte)
                      || (0x61...0x7A).contains(byte)
                      || byte == 0x2D || byte == 0x2E
              }) else {
            throw SecurityHostIdentityKeyCustodyErrorV0.invalidConfiguration
        }
        self.applicationTagPrefix = applicationTagPrefix
        self.requireSecureEnclave = requireSecureEnclave
    }

    public func applicationTag(reference: UUID) throws -> Data {
        let value = Data((
            applicationTagPrefix
                + ".host."
                + reference.uuidString.lowercased()
        ).utf8)
        guard value.count <= Self.maximumApplicationTagBytes else {
            throw SecurityHostIdentityKeyCustodyErrorV0.invalidConfiguration
        }
        return value
    }

    fileprivate func accepts(applicationTag: Data) -> Bool {
        let prefix = Data((applicationTagPrefix + ".host.").utf8)
        guard applicationTag.count == prefix.count + 36,
              applicationTag.starts(with: prefix),
              let suffix = String(
                  data: applicationTag.suffix(36),
                  encoding: .utf8
              ),
              let identifier = UUID(uuidString: suffix)
        else { return false }
        return suffix == identifier.uuidString.lowercased()
    }
}

public struct SecurityHostPreparedIdentityKeyV0: Equatable, Sendable {
    public let applicationTag: Data
    public let publicKeyX963: Data
    public let subjectPublicKeyInfoDER: Data
    public let hostFingerprint: Data
}

/// Retains the exact Security.framework key/certificate pairing supplied to
/// the Network.framework TLS listener. It is deliberately platform-only and
/// never exposes private-key bytes.
public final class SecurityHostListenerIdentityV0: @unchecked Sendable {
    private let identity: SecIdentity

    fileprivate init(identity: SecIdentity) {
        self.identity = identity
    }

    public func copySecIdentity() -> SecIdentity {
        identity
    }
}

public struct SecurityHostIssuedIdentityV0: @unchecked Sendable {
    public let key: SecurityHostPreparedIdentityKeyV0
    public let certificateDER: Data
    public let validity: HostIdentityCertificateValidity
    public let listenerIdentity: SecurityHostListenerIdentityV0
}

/// Security.framework custody for the Agent's host-listener key. The stable
/// database stores only the application tag, public fingerprint, and public
/// certificate. Existing records are loaded by exact tag; missing established
/// keys are surfaced to the lifecycle authority and are never regenerated.
public actor SecurityHostIdentityKeyCustodyV0 {
    private let configuration: SecurityHostIdentityKeyCustodyConfigurationV0

    public init(
        configuration: SecurityHostIdentityKeyCustodyConfigurationV0
    ) {
        self.configuration = configuration
    }

    /// Creates a uniquely tagged pending key, or resumes that exact pending
    /// key after an interrupted bootstrap. This method must only be called for
    /// an identity reference selected by the durable bootstrap/recovery owner.
    public func prepareKey(
        reference: UUID
    ) throws -> SecurityHostPreparedIdentityKeyV0 {
        try prepareKey(
            applicationTag: configuration.applicationTag(reference: reference)
        )
    }

    /// Creates or resumes only the exact application tag that was durably
    /// selected before Keychain mutation.
    public func prepareKey(
        applicationTag: Data
    ) throws -> SecurityHostPreparedIdentityKeyV0 {
        guard configuration.accepts(applicationTag: applicationTag) else {
            throw SecurityHostIdentityKeyCustodyErrorV0.invalidConfiguration
        }
        if let existing = try findKey(applicationTag: applicationTag) {
            return try Self.preparedKey(
                existing,
                applicationTag: applicationTag
            )
        }
        let privateKey = try createKey(applicationTag: applicationTag)
        return try Self.preparedKey(
            privateKey,
            applicationTag: applicationTag
        )
    }

    /// Reconstructs the listener identity from the exact durable certificate
    /// and tagged private key. No renewal or key creation occurs on this path.
    public func loadListenerIdentity(
        applicationTag: Data,
        certificateDER: Data,
        wallNowUnixMilliseconds: Int64
    ) throws -> SecurityHostIssuedIdentityV0 {
        guard configuration.accepts(applicationTag: applicationTag),
              let privateKey = try findKey(applicationTag: applicationTag)
        else {
            throw SecurityHostIdentityKeyCustodyErrorV0.keyNotFound
        }
        let prepared = try Self.preparedKey(
            privateKey,
            applicationTag: applicationTag
        )
        let inspection: HostIdentityCertificateInspectionV0
        do {
            inspection = try HostIdentityCertificateInspectorV0.inspect(
                certificateDER: certificateDER,
                wallNowUnixMilliseconds: wallNowUnixMilliseconds
            )
        } catch {
            throw SecurityHostIdentityKeyCustodyErrorV0.certificateInvalid
        }
        guard inspection.publicKeyX963 == prepared.publicKeyX963,
              inspection.subjectPublicKeyInfoDER
                == prepared.subjectPublicKeyInfoDER,
              let certificate = SecCertificateCreateWithData(
                  nil,
                  certificateDER as CFData
              ),
              let identity = SecIdentityCreate(nil, certificate, privateKey)
        else {
            throw SecurityHostIdentityKeyCustodyErrorV0.keyMismatch
        }
        return SecurityHostIssuedIdentityV0(
            key: prepared,
            certificateDER: certificateDER,
            validity: inspection.validity,
            listenerIdentity: SecurityHostListenerIdentityV0(
                identity: identity
            )
        )
    }

    public func availability(
        applicationTag: Data
    ) throws -> HostIdentityKeyAvailability {
        guard configuration.accepts(applicationTag: applicationTag) else {
            return .invalid
        }
        do {
            guard let key = try findKey(applicationTag: applicationTag) else {
                return .missing
            }
            return .available(
                publicKeyX963: try Self.publicKeyBytes(key)
            )
        } catch SecurityHostIdentityKeyCustodyErrorV0
            .keyUnavailableBeforeFirstUnlock {
            return .unavailableBeforeFirstUnlock
        } catch {
            return .invalid
        }
    }

    /// Issues the exact v0.1 self-signed leaf around the existing key and
    /// creates an in-memory SecIdentity for a listener. The certificate is
    /// strictly re-inspected before the identity becomes usable.
    public func issueListenerIdentity(
        applicationTag: Data,
        issuanceTimeUnixMilliseconds: Int64
    ) throws -> SecurityHostIssuedIdentityV0 {
        guard configuration.accepts(applicationTag: applicationTag),
              let privateKey = try findKey(applicationTag: applicationTag)
        else {
            throw SecurityHostIdentityKeyCustodyErrorV0.keyNotFound
        }
        return try Self.assembleIssuedIdentity(
            privateKey: privateKey,
            applicationTag: applicationTag,
            serialNumber: randomSerialNumber(),
            issuanceTimeUnixMilliseconds: issuanceTimeUnixMilliseconds
        )
    }

    /// Internal no-Keychain seam used to prove Security.framework signing,
    /// strict certificate inspection, and SecIdentity construction with an
    /// ephemeral test key. Production reaches it only after an exact tag query.
    static func assembleIssuedIdentity(
        privateKey: SecKey,
        applicationTag: Data,
        serialNumber: Data,
        issuanceTimeUnixMilliseconds: Int64
    ) throws -> SecurityHostIssuedIdentityV0 {
        let prepared = try Self.preparedKey(
            privateKey,
            applicationTag: applicationTag
        )
        let signingInput = try HostIdentityCertificateV0
            .certificateSigningInput(
                publicKeyX963: prepared.publicKeyX963,
                serialNumber: serialNumber,
                issuanceTimeUnixMilliseconds: issuanceTimeUnixMilliseconds
            )
        var signingError: Unmanaged<CFError>?
        guard let signatureDER = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            signingInput as CFData,
            &signingError
        ) as Data? else {
            _ = signingError?.takeRetainedValue()
            throw SecurityHostIdentityKeyCustodyErrorV0.signingFailed
        }
        let certificateDER = try HostIdentityCertificateV0
            .assembleSelfSignedCertificate(
                certificateSigningInput: signingInput,
                publicKeyX963: prepared.publicKeyX963,
                signatureDER: signatureDER
            )
        let inspection: HostIdentityCertificateInspectionV0
        do {
            inspection = try HostIdentityCertificateInspectorV0.inspect(
                certificateDER: certificateDER,
                wallNowUnixMilliseconds: issuanceTimeUnixMilliseconds
            )
        } catch {
            throw SecurityHostIdentityKeyCustodyErrorV0.certificateInvalid
        }
        guard inspection.publicKeyX963 == prepared.publicKeyX963,
              inspection.subjectPublicKeyInfoDER
                == prepared.subjectPublicKeyInfoDER,
              let certificate = SecCertificateCreateWithData(
                  nil,
                  certificateDER as CFData
              ) else {
            throw SecurityHostIdentityKeyCustodyErrorV0.certificateInvalid
        }
        guard let identity = SecIdentityCreate(nil, certificate, privateKey)
        else {
            throw SecurityHostIdentityKeyCustodyErrorV0.identityCreationFailed
        }
        return SecurityHostIssuedIdentityV0(
            key: prepared,
            certificateDER: certificateDER,
            validity: inspection.validity,
            listenerIdentity: SecurityHostListenerIdentityV0(
                identity: identity
            )
        )
    }

    /// Removes only a still-uncommitted pending key selected by the recovery
    /// owner. Established identity deletion belongs to the separately
    /// confirmed destructive-reset flow.
    public func deletePendingKey(applicationTag: Data) throws {
        guard configuration.accepts(applicationTag: applicationTag) else {
            throw SecurityHostIdentityKeyCustodyErrorV0.invalidConfiguration
        }
        let status = SecItemDelete([
            kSecClass: kSecClassKey,
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag: applicationTag,
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecurityHostIdentityKeyCustodyErrorV0.deletionFailed(status)
        }
    }

    /// Idempotently deletes the retired established key only after the caller
    /// has durably fenced every authority for confirmed identity recovery.
    /// The fenced database row retains this exact tag until replacement
    /// commits, so a crash can safely repeat deletion.
    public func deleteRetiredKeyForConfirmedRecovery(
        applicationTag: Data
    ) throws {
        try deletePendingKey(applicationTag: applicationTag)
    }

    private func createKey(applicationTag: Data) throws -> SecKey {
        var accessError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            [.privateKeyUsage],
            &accessError
        ) else {
            _ = accessError?.takeRetainedValue()
            throw SecurityHostIdentityKeyCustodyErrorV0.keyCreationFailed
        }
        var attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecPrivateKeyAttrs: [
                kSecAttrIsPermanent: true,
                kSecAttrApplicationTag: applicationTag,
                kSecAttrAccessControl: access,
            ] as [CFString: Any],
        ]
        if configuration.requireSecureEnclave {
            attributes[kSecAttrTokenID] = kSecAttrTokenIDSecureEnclave
        }
        var creationError: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(
            attributes as CFDictionary,
            &creationError
        ) else {
            _ = creationError?.takeRetainedValue()
            throw SecurityHostIdentityKeyCustodyErrorV0.keyCreationFailed
        }
        return key
    }

    private func findKey(applicationTag: Data) throws -> SecKey? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            keyQuery(
                applicationTag: applicationTag,
                returnReference: true
            ) as CFDictionary,
            &result
        )
        if status == errSecItemNotFound { return nil }
        if status == errSecInteractionNotAllowed {
            throw SecurityHostIdentityKeyCustodyErrorV0
                .keyUnavailableBeforeFirstUnlock
        }
        guard status == errSecSuccess,
              let result,
              CFGetTypeID(result) == SecKeyGetTypeID() else {
            throw SecurityHostIdentityKeyCustodyErrorV0.keyNotFound
        }
        return (result as! SecKey)
    }

    private func keyQuery(
        applicationTag: Data,
        returnReference: Bool
    ) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag: applicationTag,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        if returnReference { query[kSecReturnRef] = true }
        return query
    }

    private static func preparedKey(
        _ privateKey: SecKey,
        applicationTag: Data
    ) throws -> SecurityHostPreparedIdentityKeyV0 {
        let publicKeyX963 = try Self.publicKeyBytes(privateKey)
        let subjectPublicKeyInfoDER: Data
        let hostFingerprint: Data
        do {
            subjectPublicKeyInfoDER = try CompanionSecurityV0
                .p256SubjectPublicKeyInfoDER(
                    publicKeyX963: publicKeyX963
                )
            hostFingerprint = try CompanionSecurityV0.hostFingerprint(
                subjectPublicKeyInfoDER: subjectPublicKeyInfoDER
            )
        } catch {
            throw SecurityHostIdentityKeyCustodyErrorV0.keyMismatch
        }
        return SecurityHostPreparedIdentityKeyV0(
            applicationTag: applicationTag,
            publicKeyX963: publicKeyX963,
            subjectPublicKeyInfoDER: subjectPublicKeyInfoDER,
            hostFingerprint: hostFingerprint
        )
    }

    private static func publicKeyBytes(_ privateKey: SecKey) throws -> Data {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw SecurityHostIdentityKeyCustodyErrorV0.keyMismatch
        }
        var error: Unmanaged<CFError>?
        guard let value = SecKeyCopyExternalRepresentation(
            publicKey,
            &error
        ) as Data? else {
            _ = error?.takeRetainedValue()
            throw SecurityHostIdentityKeyCustodyErrorV0.keyMismatch
        }
        return value
    }

    private func randomSerialNumber() throws -> Data {
        var serialNumber = Data(count: 16)
        let status = serialNumber.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(
                kSecRandomDefault,
                bytes.count,
                bytes.baseAddress!
            )
        }
        guard status == errSecSuccess else {
            throw SecurityHostIdentityKeyCustodyErrorV0.randomFailure(status)
        }
        if serialNumber.allSatisfy({ $0 == 0 }) {
            serialNumber[serialNumber.startIndex] = 1
        }
        return serialNumber
    }
}
