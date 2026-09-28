import Foundation
import CryptoKit
import CompanionClient
import CompanionSecurity
import CompanionInteractiveShared

public struct ClientNativeVideoAttestationAuthorityV0: Equatable, Sendable {
    public let binding: InteractiveNativeVideoBindingV0
    public let surface: InteractiveNativeVideoSurfaceV0
    public let sessionPublicKeyX963: Data
    public init(binding: InteractiveNativeVideoBindingV0, surface: InteractiveNativeVideoSurfaceV0,
                sessionPublicKeyX963: Data) throws {
        try CompanionSecurityV0.validateSigningPublicKey(sessionPublicKeyX963)
        self.binding = binding; self.surface = surface; self.sessionPublicKeyX963 = sessionPublicKeyX963
    }
}

public enum ClientNativeVideoAttestationFailureV0: Error, Equatable, Sendable {
    case invalidPhase, authorizationLost, invalidMaterial, invalidSignature
}

/// Signs only the reconstructed enrollment profile, using existing session-key
/// custody. Neither returned native material nor a signature creates Control.
public actor ClientNativeVideoAttestationOwnerV0 {
    public enum Phase: Sendable { case idle, signing, complete, retired }
    public private(set) var phase: Phase = .idle
    private let authority: ClientNativeVideoAttestationAuthorityV0
    private let clientDER: Data
    private let signer: any ClientSessionAuthenticationSigningV0
    private let readAuthority: @Sendable () async throws -> ClientNativeVideoAttestationAuthorityV0?
    private let validateCertificate: @Sendable (Data) async throws -> Bool
    private let monotonicMilliseconds: @Sendable () -> UInt64
    private let initialMonotonicMilliseconds: UInt64
    private var proofDeadline: UInt64?

    public init(authority: ClientNativeVideoAttestationAuthorityV0, clientCertificateDER: Data,
                signer: any ClientSessionAuthenticationSigningV0,
                readAuthority: @escaping @Sendable () async throws -> ClientNativeVideoAttestationAuthorityV0?,
                validateCertificate: @escaping @Sendable (Data) async throws -> Bool,
                monotonicMilliseconds: @escaping @Sendable () -> UInt64) throws {
        guard (1...4096).contains(clientCertificateDER.count) else { throw ClientNativeVideoAttestationFailureV0.invalidMaterial }
        self.authority = authority; clientDER = clientCertificateDER; self.signer = signer
        self.readAuthority = readAuthority; self.validateCertificate = validateCertificate
        self.monotonicMilliseconds = monotonicMilliseconds
        initialMonotonicMilliseconds = monotonicMilliseconds()
    }

    public func attest(_ preparation: InteractiveNativeVideoEnrollmentPreparationV0) async throws -> Data {
        guard phase == .idle else { throw ClientNativeVideoAttestationFailureV0.invalidPhase }
        phase = .signing
        do {
            let (deadline, overflow) = monotonicMilliseconds().addingReportingOverflow(
                preparation.expiresAtUnixMilliseconds - preparation.issuedAtUnixMilliseconds)
            guard !overflow else { throw ClientNativeVideoAttestationFailureV0.authorizationLost }
            proofDeadline = min(deadline, authority.binding.expiresAtMonotonicMilliseconds)
            try await checkAuthority()
            guard try await validateCertificate(clientDER) else { throw ClientNativeVideoAttestationFailureV0.invalidMaterial }
            try await checkAuthority()
            guard try await validateCertificate(preparation.hostCertificateDER) else { throw ClientNativeVideoAttestationFailureV0.invalidMaterial }
            try await checkAuthority()
            let b = authority.binding, s = authority.surface
            let expected = try CompanionSecurityV0.nativeVideoEnrollmentSigningInput(hostID: b.hostID,
                hostFingerprint: b.hostFingerprint, clientID: b.clientID, primaryConnectionID: b.primaryConnectionID,
                interactiveSessionID: b.interactiveSessionID, authorizationEpoch: UInt64(b.authorizationEpoch),
                grantRevision: UInt64(b.grantRevision), policyRevision: UInt64(b.policyRevision), streamGeneration: b.controlGeneration,
                surfaceID: s.surfaceID, surfaceRevision: UInt64(s.surfaceRevision), coordinateSpaceRevision: UInt64(s.coordinateSpaceRevision),
                encodedWidth: UInt16(s.encodedWidth), encodedHeight: UInt16(s.encodedHeight),
                clientCertificateSHA256: Data(SHA256.hash(data: clientDER)),
                hostCertificateSHA256: Data(SHA256.hash(data: preparation.hostCertificateDER)), hostChallenge: preparation.hostChallenge,
                issuedAtUnixMilliseconds: preparation.issuedAtUnixMilliseconds, expiresAtUnixMilliseconds: preparation.expiresAtUnixMilliseconds)
            guard expected == preparation.signingInput else { throw ClientNativeVideoAttestationFailureV0.invalidMaterial }
            let signature = try await signer.signAuthenticationInput(expected)
            try await checkAuthority()
            guard try CompanionSecurityV0.verifySignature(rawSignature: signature, signingInput: expected,
                    publicKeyX963: authority.sessionPublicKeyX963) else { throw ClientNativeVideoAttestationFailureV0.invalidSignature }
            phase = .complete
            return signature
        } catch {
            phase = .retired
            throw error
        }
    }

    public func retire() { phase = .retired }

    private func checkAuthority() async throws {
        guard phase == .signing, clockIsValid() else { throw ClientNativeVideoAttestationFailureV0.authorizationLost }
        let current = try await readAuthority()
        guard phase == .signing, current == authority, clockIsValid() else { throw ClientNativeVideoAttestationFailureV0.authorizationLost }
    }
    private func clockIsValid() -> Bool {
        let now = monotonicMilliseconds()
        return now >= initialMonotonicMilliseconds && now < authority.binding.expiresAtMonotonicMilliseconds && now < (proofDeadline ?? 0)
    }
}
