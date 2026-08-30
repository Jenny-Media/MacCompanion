import CompanionClient
import CryptoKit
import Foundation
import LocalAuthentication
import OSLog
import Security

private let clientKeyCustodyLoggerV0 = Logger(
    subsystem: "media.jenny.maccompanion.ios",
    category: "approval-signing"
)

private func clientApprovalDebugTraceV0(_ message: String) {
#if DEBUG
    FileHandle.standardError.write(
        Data("[MacCompanion approval] \(message)\n".utf8)
    )
#endif
}

public enum SecurityClientKeyCustodyErrorV0: Error, Equatable, Sendable {
    case invalidConfiguration
    case randomFailure(OSStatus)
    case keyCreationFailed
    case keyNotFound
    case keyMismatch
    case signingFailed
    case deletionFailed(OSStatus)
}

public struct SecurityClientPresencePromptsV0: Equatable, Sendable {
    public let pairNewMac: String
    public let approveOperation: String
    public let startInteractiveControl: String
    public let expandGrant: String

    public init(
        pairNewMac: String,
        approveOperation: String,
        startInteractiveControl: String,
        expandGrant: String
    ) throws {
        let values = [
            pairNewMac, approveOperation, startInteractiveControl, expandGrant,
        ]
        guard values.allSatisfy({ value in
            !value.isEmpty
                && value.utf8.count <= 160
                && !value.unicodeScalars.contains(where: { $0.value < 0x20 })
        }) else {
            throw SecurityClientKeyCustodyErrorV0.invalidConfiguration
        }
        self.pairNewMac = pairNewMac
        self.approveOperation = approveOperation
        self.startInteractiveControl = startInteractiveControl
        self.expandGrant = expandGrant
    }

    fileprivate func value(
        for reason: ClientApprovalPresenceReasonV0
    ) -> String {
        switch reason {
        case .pairNewMac: pairNewMac
        case .approveOperation: approveOperation
        case .startInteractiveControl: startInteractiveControl
        case .expandGrant: expandGrant
        }
    }
}

public struct SecurityClientKeyCustodyConfigurationV0: Equatable, Sendable {
    public let applicationTagPrefix: String
    public let requireSecureEnclave: Bool
    public let prompts: SecurityClientPresencePromptsV0

    public init(
        applicationTagPrefix: String,
        requireSecureEnclave: Bool = true,
        prompts: SecurityClientPresencePromptsV0
    ) throws {
        guard (1...96).contains(applicationTagPrefix.utf8.count),
              applicationTagPrefix.utf8.allSatisfy({ byte in
                (0x30...0x39).contains(byte)
                    || (0x41...0x5A).contains(byte)
                    || (0x61...0x7A).contains(byte)
                    || byte == 0x2D || byte == 0x2E
              }) else {
            throw SecurityClientKeyCustodyErrorV0.invalidConfiguration
        }
        self.applicationTagPrefix = applicationTagPrefix
        self.requireSecureEnclave = requireSecureEnclave
        self.prompts = prompts
    }
}

public struct SecurityClientKeyCreationProfileV0: Equatable, Sendable {
    public let role: ClientSigningKeyRoleV0
    public let protection: ClientKeyProtectionV0
    public let requiresUserPresence: Bool
    public let requiresSecureEnclave: Bool

    public static func profile(
        for role: ClientSigningKeyRoleV0,
        requireSecureEnclave: Bool
    ) -> Self {
        switch role {
        case .session:
            Self(
                role: .session,
                protection: .afterFirstUnlockThisDeviceOnly,
                requiresUserPresence: false,
                requiresSecureEnclave: requireSecureEnclave
            )
        case .approval:
            Self(
                role: .approval,
                protection: .whenUnlockedThisDeviceOnlyUserPresence,
                requiresUserPresence: true,
                requiresSecureEnclave: requireSecureEnclave
            )
        }
    }
}

/// Security.framework implementation of the client custody boundary. Private
/// key bytes are never requested or returned. A release composition registers
/// each loaded durable record after restart, then this actor revalidates its
/// public keys before signing by opaque reference.
public actor SecurityClientIdentityKeyCustodyV0:
    ClientIdentityKeyCustodyV0
{
    private struct Binding: Sendable {
        let role: ClientSigningKeyRoleV0
        let tag: Data
        let publicKeyX963: Data
    }

    private let configuration: SecurityClientKeyCustodyConfigurationV0
    private var bindings: [ClientSigningKeyReferenceV0: Binding] = [:]

    public init(configuration: SecurityClientKeyCustodyConfigurationV0) {
        self.configuration = configuration
    }

    public func prepareIdentity(
        pairingID: UUID,
        clientID: UUID
    ) async throws -> ClientPreparedIdentityV0 {
        let sessionReference = try randomReference()
        var approvalReference = try randomReference()
        while approvalReference == sessionReference {
            approvalReference = try randomReference()
        }
        let session = try createKey(
            role: .session,
            reference: sessionReference
        )
        let approval: ClientCustodiedPublicKeyV0
        do {
            approval = try createKey(
                role: .approval,
                reference: approvalReference
            )
        } catch {
            try? deleteKey(tag: tag(role: .session, reference: session.reference))
            throw error
        }
        let identity: ClientPreparedIdentityV0
        do {
            identity = try ClientPreparedIdentityV0(
                pairingID: pairingID,
                clientID: clientID,
                sessionKey: session,
                approvalKey: approval
            )
        } catch {
            try? deleteKey(tag: tag(role: .session, reference: session.reference))
            try? deleteKey(tag: tag(role: .approval, reference: approval.reference))
            throw error
        }
        bindings[session.reference] = Binding(
            role: .session,
            tag: tag(role: .session, reference: session.reference),
            publicKeyX963: session.publicKeyX963
        )
        bindings[approval.reference] = Binding(
            role: .approval,
            tag: tag(role: .approval, reference: approval.reference),
            publicKeyX963: approval.publicKeyX963
        )
        return identity
    }

    public func validatePreparedIdentity(
        _ identity: ClientPreparedIdentityV0
    ) async throws -> Bool {
        guard let session = try validatedBinding(identity.sessionKey),
              let approval = try validatedBinding(identity.approvalKey) else {
            return false
        }
        bindings[identity.sessionKey.reference] = session
        bindings[identity.approvalKey.reference] = approval
        return true
    }

    /// Rehydrates opaque-reference routing from an already strict durable
    /// public record. Missing or substituted Keychain objects fail before any
    /// binding becomes usable.
    public func registerPublishedIdentity(
        _ record: ClientDurablePairedHostV0
    ) throws {
        guard let session = try validatedBinding(record.sessionKey),
              let approval = try validatedBinding(record.approvalKey) else {
            throw SecurityClientKeyCustodyErrorV0.keyMismatch
        }
        bindings[record.sessionKey.reference] = session
        bindings[record.approvalKey.reference] = approval
    }

    public func signSessionInput(
        _ input: Data,
        using reference: ClientSigningKeyReferenceV0
    ) async throws -> Data {
        try sign(input, reference: reference, role: .session, prompt: nil)
    }

    public func signApprovalInput(
        _ input: Data,
        using reference: ClientSigningKeyReferenceV0,
        reason: ClientApprovalPresenceReasonV0
    ) async throws -> Data {
        try sign(
            input,
            reference: reference,
            role: .approval,
            prompt: configuration.prompts.value(for: reason)
        )
    }

    public func discardPreparedIdentity(
        _ identity: ClientPreparedIdentityV0
    ) async throws {
        var firstError: Error?
        for key in [identity.sessionKey, identity.approvalKey] {
            let keyTag = tag(role: key.role, reference: key.reference)
            do { try deleteKey(tag: keyTag) } catch {
                if firstError == nil { firstError = error }
            }
            bindings.removeValue(forKey: key.reference)
        }
        if let firstError { throw firstError }
    }

    private func createKey(
        role: ClientSigningKeyRoleV0,
        reference: ClientSigningKeyReferenceV0
    ) throws -> ClientCustodiedPublicKeyV0 {
        let keyTag = tag(role: role, reference: reference)
        let profile = SecurityClientKeyCreationProfileV0.profile(
            for: role,
            requireSecureEnclave: configuration.requireSecureEnclave
        )
        let privateAttributes = try privateKeyAttributes(
            profile: profile,
            tag: keyTag
        )
        var attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecPrivateKeyAttrs: privateAttributes,
        ]
        if profile.requiresSecureEnclave {
            attributes[kSecAttrTokenID] = kSecAttrTokenIDSecureEnclave
        }
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(
            attributes as CFDictionary,
            &error
        ) else {
            _ = error?.takeRetainedValue()
            throw SecurityClientKeyCustodyErrorV0.keyCreationFailed
        }
        let publicBytes = try publicKeyBytes(privateKey)
        return try ClientCustodiedPublicKeyV0(
            role: role,
            reference: reference,
            publicKeyX963: publicBytes,
            protection: profile.protection
        )
    }

    private func privateKeyAttributes(
        profile: SecurityClientKeyCreationProfileV0,
        tag: Data
    ) throws -> [CFString: Any] {
        var value: [CFString: Any] = [
            kSecAttrIsPermanent: true,
            kSecAttrApplicationTag: tag,
        ]
        if profile.requiresUserPresence {
            var error: Unmanaged<CFError>?
            guard let control = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                [.privateKeyUsage, .userPresence],
                &error
            ) else {
                _ = error?.takeRetainedValue()
                throw SecurityClientKeyCustodyErrorV0.keyCreationFailed
            }
            value[kSecAttrAccessControl] = control
        } else {
            value[kSecAttrAccessible] =
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        return value
    }

    private func validatedBinding(
        _ value: ClientCustodiedPublicKeyV0
    ) throws -> Binding? {
        let keyTag = tag(role: value.role, reference: value.reference)
        guard let privateKey = try findKey(tag: keyTag, prompt: nil),
              try publicKeyBytes(privateKey) == value.publicKeyX963 else {
            return nil
        }
        return Binding(
            role: value.role,
            tag: keyTag,
            publicKeyX963: value.publicKeyX963
        )
    }

    private func sign(
        _ input: Data,
        reference: ClientSigningKeyReferenceV0,
        role: ClientSigningKeyRoleV0,
        prompt: String?
    ) throws -> Data {
        if role == .approval {
            clientKeyCustodyLoggerV0.info("approval key lookup started")
            clientApprovalDebugTraceV0("key lookup started")
        }
        guard let binding = bindings[reference], binding.role == role,
              let privateKey = try findKey(tag: binding.tag, prompt: prompt),
              try publicKeyBytes(privateKey) == binding.publicKeyX963 else {
            if role == .approval {
                clientKeyCustodyLoggerV0.error(
                    "approval key lookup or public-key check failed"
                )
                clientApprovalDebugTraceV0(
                    "key lookup or public-key check failed"
                )
            }
            throw SecurityClientKeyCustodyErrorV0.keyNotFound
        }
        if role == .approval {
            clientKeyCustodyLoggerV0.info("approval user presence satisfied")
            clientApprovalDebugTraceV0("user presence satisfied")
        }
        var error: Unmanaged<CFError>?
        guard let der = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            input as CFData,
            &error
        ) as Data? else {
            let retainedError = error?.takeRetainedValue()
            if role == .approval {
                clientKeyCustodyLoggerV0.error(
                    "approval signature creation failed: \(retainedError.map(CFErrorGetCode) ?? 0, privacy: .public)"
                )
                clientApprovalDebugTraceV0(
                    "signature creation failed code=\(retainedError.map(CFErrorGetCode) ?? 0)"
                )
            }
            throw SecurityClientKeyCustodyErrorV0.signingFailed
        }
        let signature = try Self.rawP256Signature(fromDER: der)
        if role == .approval {
            clientKeyCustodyLoggerV0.info("approval signature created")
            clientApprovalDebugTraceV0("signature created")
        }
        return signature
    }

    private func findKey(tag: Data, prompt: String?) throws -> SecKey? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag: tag,
            kSecReturnRef: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        if let prompt {
            let context = LAContext()
            context.localizedReason = prompt
            query[kSecUseAuthenticationContext] = context
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let result,
              CFGetTypeID(result) == SecKeyGetTypeID() else {
            if prompt != nil {
                clientKeyCustodyLoggerV0.error(
                    "approval key query failed: \(status, privacy: .public)"
                )
                clientApprovalDebugTraceV0("key query failed status=\(status)")
            }
            throw SecurityClientKeyCustodyErrorV0.keyNotFound
        }
        return (result as! SecKey)
    }

    private func deleteKey(tag: Data) throws {
        let status = SecItemDelete([
            kSecClass: kSecClassKey,
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrApplicationTag: tag,
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecurityClientKeyCustodyErrorV0.deletionFailed(status)
        }
    }

    private func publicKeyBytes(_ privateKey: SecKey) throws -> Data {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw SecurityClientKeyCustodyErrorV0.keyMismatch
        }
        var error: Unmanaged<CFError>?
        guard let bytes = SecKeyCopyExternalRepresentation(
            publicKey,
            &error
        ) as Data? else {
            _ = error?.takeRetainedValue()
            throw SecurityClientKeyCustodyErrorV0.keyMismatch
        }
        return bytes
    }

    private func tag(
        role: ClientSigningKeyRoleV0,
        reference: ClientSigningKeyReferenceV0
    ) -> Data {
        Data((
            configuration.applicationTagPrefix
                + "." + role.rawValue
                + "." + reference.rawValue.uuidString.lowercased()
        ).utf8)
    }

    private func randomReference() throws -> ClientSigningKeyReferenceV0 {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = bytes.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(
                kSecRandomDefault,
                buffer.count,
                buffer.baseAddress!
            )
        }
        guard status == errSecSuccess else {
            throw SecurityClientKeyCustodyErrorV0.randomFailure(status)
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x40
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return try ClientSigningKeyReferenceV0(UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )))
    }

    static func rawP256Signature(fromDER value: Data) throws -> Data {
        do {
            return try P256.Signing.ECDSASignature(
                derRepresentation: value
            ).rawRepresentation
        } catch {
            throw SecurityClientKeyCustodyErrorV0.signingFailed
        }
    }
}
