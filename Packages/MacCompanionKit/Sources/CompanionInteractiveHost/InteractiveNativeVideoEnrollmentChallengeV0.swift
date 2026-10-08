import Foundation
import CompanionInteractiveShared
import CompanionSecurity

public enum InteractiveNativeVideoEnrollmentErrorV0: Error, Equatable, Sendable {
    case expiredControl
    case invalidClock
}

/// A local, single-use attestation verifier. Success is not registration,
/// launch, Control approval, or input admission. Construct and retain this
/// owner only from the authenticated primary and approved Control authority.
public final class InteractiveNativeVideoEnrollmentChallengeV0: @unchecked Sendable {
    public let signingInput: Data
    public let challenge: Data
    public let issuedAtUnixMilliseconds: UInt64
    public let expiresAtUnixMilliseconds: UInt64
    public let expiresAtMonotonicMilliseconds: UInt64

    private let binding: InteractiveNativeVideoBindingV0
    private let surface: InteractiveNativeVideoSurfaceV0
    private let sessionPublicKeyX963: Data
    private let issuedAtMonotonicMilliseconds: UInt64
    private let lock = NSLock()
    // This is the sole mutable field; all access is serialized by lock.
    private var consumed = false

    public init(
        binding: InteractiveNativeVideoBindingV0,
        surface: InteractiveNativeVideoSurfaceV0,
        sessionPublicKeyX963: Data,
        clientCertificateSHA256: Data, hostCertificateSHA256: Data,
        issuedAtUnixMilliseconds: UInt64,
        issuedAtMonotonicMilliseconds: UInt64,
        conformanceChallenge: Data? = nil
    ) throws {
        guard issuedAtMonotonicMilliseconds < binding.expiresAtMonotonicMilliseconds else {
            throw InteractiveNativeVideoEnrollmentErrorV0.expiredControl
        }
        try CompanionSecurityV0.validateSigningPublicKey(sessionPublicKeyX963)
        let duration = min(15_000, binding.expiresAtMonotonicMilliseconds - issuedAtMonotonicMilliseconds)
        let (unixExpiry, overflow) = issuedAtUnixMilliseconds.addingReportingOverflow(duration)
        guard !overflow else { throw InteractiveNativeVideoEnrollmentErrorV0.invalidClock }
        var generator = SystemRandomNumberGenerator()
        let nonce = conformanceChallenge ?? Data((0..<32).map { _ in
            UInt8.random(in: .min ... .max, using: &generator)
        })
        let message = try CompanionSecurityV0.nativeVideoEnrollmentSigningInput(
            hostID: binding.hostID, hostFingerprint: binding.hostFingerprint,
            clientID: binding.clientID, primaryConnectionID: binding.primaryConnectionID,
            interactiveSessionID: binding.interactiveSessionID,
            authorizationEpoch: UInt64(binding.authorizationEpoch),
            grantRevision: UInt64(binding.grantRevision), policyRevision: UInt64(binding.policyRevision),
            streamGeneration: binding.controlGeneration, surfaceID: surface.surfaceID,
            surfaceRevision: UInt64(surface.surfaceRevision),
            coordinateSpaceRevision: UInt64(surface.coordinateSpaceRevision),
            encodedWidth: UInt16(surface.encodedWidth), encodedHeight: UInt16(surface.encodedHeight),
            clientCertificateSHA256: clientCertificateSHA256,
            hostCertificateSHA256: hostCertificateSHA256,
            hostChallenge: nonce, issuedAtUnixMilliseconds: issuedAtUnixMilliseconds,
            expiresAtUnixMilliseconds: unixExpiry)
        self.binding = binding
        self.surface = surface
        self.sessionPublicKeyX963 = sessionPublicKeyX963
        self.issuedAtMonotonicMilliseconds = issuedAtMonotonicMilliseconds
        self.issuedAtUnixMilliseconds = issuedAtUnixMilliseconds
        self.expiresAtUnixMilliseconds = unixExpiry
        self.expiresAtMonotonicMilliseconds = issuedAtMonotonicMilliseconds + duration
        self.challenge = nonce
        self.signingInput = message
    }

    /// Obtain all current values from the authoritative owner immediately
    /// before calling. Verification has no suspension or registration effects.
    /// Every attempt, including a malformed signature, consumes the challenge.
    public func consume(
        rawSignature: Data,
        currentBinding: InteractiveNativeVideoBindingV0?,
        currentSurface: InteractiveNativeVideoSurfaceV0?,
        currentSessionPublicKeyX963: Data?,
        nowMonotonicMilliseconds: UInt64
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !consumed else { return false }
        consumed = true
        guard currentBinding == binding, currentSurface == surface,
              currentSessionPublicKeyX963 == sessionPublicKeyX963,
              nowMonotonicMilliseconds >= issuedAtMonotonicMilliseconds,
              nowMonotonicMilliseconds < expiresAtMonotonicMilliseconds,
              nowMonotonicMilliseconds < binding.expiresAtMonotonicMilliseconds else { return false }
        return (try? CompanionSecurityV0.verifySignature(rawSignature: rawSignature,
            signingInput: signingInput, publicKeyX963: sessionPublicKeyX963)) == true
    }

    public func cancel() {
        lock.lock()
        consumed = true
        lock.unlock()
    }
}
