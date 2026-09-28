import Foundation
import CompanionClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionWire

/// Enrollment completion only. A native TLS/launch adapter must still use the
/// selected verified primary route, exact certificate pin, and client identity.
/// This result grants neither presentation nor input.
public struct ClientNativeVideoEnrolledSessionV0: Sendable {
    public let authority: ClientNativeVideoAttestationAuthorityV0
    public let hostCertificateDER: Data
    public let portBase: UInt16
}

/// Retains the enrollment/signing attempt for the normal Control product.
/// Closing fences first, cancels the primary waiter and signer, and joins the
/// same drain. A platform owns and erases its ephemeral native client identity.
public actor ClientNativeVideoEnrollmentSessionV0 {
    private let channel: ClientInteractivePrimaryChannelV0
    private let signer: any ClientSessionAuthenticationSigningV0
    private let validateCertificate: @Sendable (Data) async throws -> Bool
    private let now: @Sendable () -> UInt64
    private var attempt: Task<ClientNativeVideoEnrolledSessionV0, Error>?
    private var started = false
    private var closed = false
    private var attestation: ClientNativeVideoAttestationOwnerV0?
    private var challenge: WireEnvelope<InteractiveNativeVideoEnrollmentChallengeBodyV0>?
    private var expected: ClientNativeVideoAttestationAuthorityV0?
    private var drain: Task<Void, Never>?
    private var monitor: Task<Void, Never>?

    public init(channel: ClientInteractivePrimaryChannelV0,
                signer: any ClientSessionAuthenticationSigningV0,
                validateCertificate: @escaping @Sendable (Data) async throws -> Bool,
                monotonicMilliseconds: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds / 1_000_000 }) {
        self.channel = channel
        self.signer = signer
        self.validateCertificate = validateCertificate
        self.now = monotonicMilliseconds
    }

    public func enroll(descriptor: AdaptiveSurfaceDescriptor, clientCertificateDER: Data) async throws -> ClientNativeVideoEnrolledSessionV0 {
        guard !started, !closed else { throw ClientNativeVideoAttestationFailureV0.invalidPhase }
        started = true
        let task = Task { try await self.performEnrollment(descriptor: descriptor, clientCertificateDER: clientCertificateDER) }
        attempt = task
        return try await withTaskCancellationHandler {
            do { return try await task.value }
            catch { await close(); throw error }
        } onCancel: { [weak self] in Task { await self?.close() } }
    }

    private func performEnrollment(descriptor: AdaptiveSurfaceDescriptor, clientCertificateDER: Data) async throws -> ClientNativeVideoEnrolledSessionV0 {
        do {
            let challenge = try await channel.requestNativeEnrollment(for: descriptor, clientCertificateDER: clientCertificateDER)
            guard !closed, let authority = await channel.nativeAttestationAuthority(for: challenge) else {
                throw ClientNativeVideoAttestationFailureV0.authorizationLost
            }
            self.challenge = challenge
            expected = authority
            let channel = self.channel
            let owner = try ClientNativeVideoAttestationOwnerV0(authority: authority, clientCertificateDER: clientCertificateDER,
                signer: signer, readAuthority: { await channel.nativeAttestationAuthority(for: challenge) },
                validateCertificate: validateCertificate, monotonicMilliseconds: now)
            attestation = owner
            let signature = try await owner.attest(challenge.body.preparation())
            guard !closed, await channel.nativeAttestationAuthority(for: challenge) == authority else {
                throw ClientNativeVideoAttestationFailureV0.authorizationLost
            }
            let ready = try await channel.submitNativeEnrollmentProof(for: challenge, signature: signature)
            guard !closed, await channel.nativeAttestationAuthority(for: challenge) == authority else {
                throw ClientNativeVideoAttestationFailureV0.authorizationLost
            }
            monitor = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(50))
                    guard !Task.isCancelled, let self else { return }
                    if !(await self.isCurrent()) { await self.close(); return }
                }
            }
            return .init(authority: authority, hostCertificateDER: try challenge.body.preparation().hostCertificateDER,
                         portBase: ready.body.portBase)
        } catch {
            throw error
        }
    }

    @discardableResult
    public func acknowledgePresentation(nativeGeneration: Int64, encodedWidth: UInt16, encodedHeight: UInt16) async throws -> InteractiveNativeVideoPresentationReceiptBodyV0 {
        guard await isCurrent(), !Task.isCancelled else { throw ClientNativeVideoAttestationFailureV0.authorizationLost }
        do {
            let receipt = try await channel.acknowledgeNativePresentation(nativeGeneration: nativeGeneration,
                encodedWidth: encodedWidth, encodedHeight: encodedHeight)
            guard await isCurrent(), !Task.isCancelled else { throw ClientNativeVideoAttestationFailureV0.authorizationLost }
            return receipt.body
        } catch {
            await close()
            throw error
        }
    }

    public func isCurrent() async -> Bool {
        guard !closed, let challenge, let expected else { return false }
        let current = await channel.nativeAttestationAuthority(for: challenge)
        return !closed && current == expected
    }

    public func close() async {
        if let drain { await drain.value; return }
        closed = true
        guard started else { return }
        monitor?.cancel()
        monitor = nil
        let owner = attestation, channel = self.channel, pending = attempt
        pending?.cancel()
        attempt = nil
        attestation = nil
        challenge = nil
        expected = nil
        let task = Task {
            await owner?.retire()
            try? await channel.cancelNativeEnrollment()
            _ = try? await pending?.value
            // A request suspended before reserving its fence may have finished
            // while cancellation was sent. Join then compensate once more.
            try? await channel.cancelNativeEnrollment()
        }
        drain = task
        await task.value
    }
}
