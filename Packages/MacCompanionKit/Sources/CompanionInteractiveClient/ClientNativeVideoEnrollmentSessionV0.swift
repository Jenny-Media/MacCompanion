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
    public let streamContinuity: Bool
}

/// Retains the enrollment/signing attempt for the normal Control product.
/// Closing fences first, cancels the primary waiter and signer, and joins the
/// same drain. A platform owns and erases its ephemeral native client identity.
public actor ClientNativeVideoEnrollmentSessionV0 {
    private let channel: ClientInteractivePrimaryChannelV0
    private let localOwnerID = UUID()
    private let signer: any ClientSessionAuthenticationSigningV0
    private let validateCertificate: @Sendable (Data) async throws -> Bool
    private let now: @Sendable () -> UInt64
    private var attempt: Task<ClientNativeVideoEnrolledSessionV0, Error>?
    private var retained = false
    private var enrolled: ClientNativeVideoEnrolledSessionV0?
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

    public func enroll(descriptor: AdaptiveSurfaceDescriptor, clientCertificateDER: Data, streamContinuity: Bool = false) async throws -> ClientNativeVideoEnrolledSessionV0 {
        guard !started, !closed else { throw ClientNativeVideoAttestationFailureV0.invalidPhase }
        started = true
        let task = Task { try await self.performEnrollment(descriptor: descriptor, clientCertificateDER: clientCertificateDER, streamContinuity: streamContinuity) }
        attempt = task
        return try await withTaskCancellationHandler {
            do { let result = try await task.value; attempt = nil; enrolled = result; return result }
            catch { await close(); throw error }
        } onCancel: { [weak self] in Task { await self?.close() } }
    }

    private func performEnrollment(descriptor: AdaptiveSurfaceDescriptor, clientCertificateDER: Data, streamContinuity: Bool) async throws -> ClientNativeVideoEnrolledSessionV0 {
        do {
            let challenge = try await channel.requestNativeEnrollment(for: descriptor,
                clientCertificateDER: clientCertificateDER, localOwnerID: localOwnerID, streamContinuity: streamContinuity)
            guard !closed, let authority = await channel.nativeAttestationAuthority(for: challenge) else {
                throw ClientNativeVideoAttestationFailureV0.authorizationLost
            }
            if retained, let previous = enrolled {
                guard authority.binding == previous.authority.binding,
                      authority.surface.encodedWidth == previous.authority.surface.encodedWidth,
                      authority.surface.encodedHeight == previous.authority.surface.encodedHeight,
                      try challenge.body.preparation().hostCertificateDER == previous.hostCertificateDER else {
                    throw ClientNativeVideoAttestationFailureV0.authorizationLost
                }
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
            if retained, ready.body.portBase != enrolled?.portBase || ready.body.streamContinuity != true {
                throw ClientNativeVideoAttestationFailureV0.authorizationLost
            }
            retained = false
            monitor?.cancel()
            monitor = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(50))
                    guard !Task.isCancelled, let self else { return }
                    if !(await self.isCurrent()) { await self.close(); return }
                }
            }
            return .init(authority: authority, hostCertificateDER: try challenge.body.preparation().hostCertificateDER,
                         portBase: ready.body.portBase, streamContinuity: ready.body.streamContinuity == true)
        } catch {
            throw error
        }
    }

    public func supportsStreamContinuity() async -> Bool {
        guard !closed, !retained, enrolled?.streamContinuity == true else { return false }
        return await channel.nativeStreamContinuityAvailable(ownedBy: localOwnerID)
    }

    public func retainStream() async throws {
        guard !closed, !retained, attempt == nil, await supportsStreamContinuity(), !closed else {
            throw ClientNativeVideoAttestationFailureV0.invalidPhase
        }
        retained = true // Monitor the original Control while the old surface is paused.
        do {
            try await channel.retainNativeEnrollment(ownedBy: localOwnerID)
            guard !closed, await isCurrent() else { throw ClientNativeVideoAttestationFailureV0.authorizationLost }
            await attestation?.retire(); attestation = nil
        } catch { await close(); throw error }
    }

    public func replaceSurface(descriptor: AdaptiveSurfaceDescriptor, clientCertificateDER: Data) async throws -> ClientNativeVideoEnrolledSessionV0 {
        guard !closed, retained, attempt == nil, enrolled != nil else { throw ClientNativeVideoAttestationFailureV0.invalidPhase }
        let task = Task { try await self.performEnrollment(descriptor: descriptor, clientCertificateDER: clientCertificateDER, streamContinuity: true) }
        attempt = task
        return try await withTaskCancellationHandler {
            do { let result = try await task.value; attempt = nil; enrolled = result; return result }
            catch { await close(); throw error }
        } onCancel: { [weak self] in Task { await self?.close() } }
    }

    @discardableResult
    public func acknowledgePresentation(nativeGeneration: Int64, encodedWidth: UInt16, encodedHeight: UInt16) async throws -> InteractiveNativeVideoPresentationReceiptBodyV0 {
        guard !retained, await isCurrent(), !Task.isCancelled else { throw ClientNativeVideoAttestationFailureV0.authorizationLost }
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
        guard !closed, let expected else { return false }
        if retained {
            let binding = await channel.currentNativeControlBinding()
            return !closed && binding == expected.binding
        }
        guard let challenge else { return false }
        let current = await channel.nativeAttestationAuthority(for: challenge)
        return !closed && current == expected
    }

    public func close() async {
        if let drain { await drain.value; return }
        closed = true
        guard started else { return }
        monitor?.cancel()
        monitor = nil
        let owner = attestation, channel = self.channel, pending = attempt, localOwnerID = self.localOwnerID
        pending?.cancel()
        attempt = nil
        attestation = nil
        challenge = nil
        expected = nil
        enrolled = nil; retained = false
        let task = Task {
            await owner?.retire()
            try? await channel.cancelNativeEnrollment(ownedBy: localOwnerID)
            _ = try? await pending?.value
            // A request suspended before reserving its fence may have finished
            // while cancellation was sent. Join then compensate once more.
            try? await channel.cancelNativeEnrollment(ownedBy: localOwnerID)
        }
        drain = task
        await task.value
    }
}
