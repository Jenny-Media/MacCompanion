import Foundation
import CryptoKit
import CompanionInteractiveShared
import CompanionSecurity

/// The trusted Control composition supplies these facts, never a remote request.
public struct InteractiveNativeVideoAuthorityV0: Equatable, Sendable {
    public let binding: InteractiveNativeVideoBindingV0
    public let surface: InteractiveNativeVideoSurfaceV0
    public let sessionPublicKeyX963: Data

    public init(binding: InteractiveNativeVideoBindingV0,
                surface: InteractiveNativeVideoSurfaceV0, sessionPublicKeyX963: Data) throws {
        try CompanionSecurityV0.validateSigningPublicKey(sessionPublicKeyX963)
        self.binding = binding
        self.surface = surface
        self.sessionPublicKeyX963 = sessionPublicKeyX963
    }
}

public struct InteractiveNativeVideoEndpointV0: Equatable, Sendable {
    public let portBase: UInt16
    public init(portBase: UInt16) throws {
        guard portBase > 1029, portBase < 65500 else {
            throw InteractiveNativeVideoCoordinatorFailureV0.invalidMaterial
        }
        self.portBase = portBase
    }
}

public protocol InteractiveNativeVideoEnrollmentBackendV0: Sendable {
    /// Validate complete DER; prepare isolated credentials without listeners,
    /// capture, or registration. Return the actual complete host certificate DER.
    func prepare(operationID: UUID, authority: InteractiveNativeVideoAuthorityV0,
                 clientCertificateDER: Data) async throws -> Data
    /// Register only the prepared certificate and launch under the original lease.
    func activate(operationID: UUID) async throws -> InteractiveNativeVideoEndpointV0
    /// Ready and running for this exact operation, without granting authority.
    func isActive(operationID: UUID) async -> Bool
    /// Fresh actual sample metadata, while pending capture may return nil.
    /// This observation grants neither presentation nor input.
    func captureEvidence(operationID: UUID) async throws -> InteractiveNativeVideoCaptureEvidenceV0?
    /// Explicit backend support for the current operation's atomic posting.
    func canPostInput(operationID: UUID) async -> Bool
    /// Correlated local presentation handoff. False remains observation only.
    func admitPresentation(operationID: UUID, nativeGeneration: Int64, presentationID: UUID) async throws -> Bool
    /// Trusted local posting seam, requiring final process/sample/geometry
    /// validation under a revocable permit. This is not presentation admission.
    func postInputBatch(operationID: UUID, beforeDeadlineNanoseconds: UInt64,
                        batch: @escaping @Sendable () throws -> Void) async throws
    /// Fence before suspending; cancel preparation/activation, reap the helper,
    /// and destroy owned credentials. Idempotent even before preparation starts.
    func retire(operationID: UUID) async
}
public extension InteractiveNativeVideoEnrollmentBackendV0 {
    func canPostInput(operationID: UUID) async -> Bool { false }
    func admitPresentation(operationID: UUID, nativeGeneration: Int64, presentationID: UUID) async throws -> Bool { false }
    func postInputBatch(operationID: UUID, beforeDeadlineNanoseconds: UInt64,
                        batch: @escaping @Sendable () throws -> Void) async throws {
        throw InteractiveNativeVideoCoordinatorFailureV0.backendUnavailable
    }
    func captureEvidence(operationID: UUID) async throws -> InteractiveNativeVideoCaptureEvidenceV0? { nil }
}


public enum InteractiveNativeVideoCoordinatorFailureV0: Error, Equatable, Sendable {
    case invalidPhase, invalidMaterial, authorizationLost, invalidProof, backendUnavailable
}

/// One generation, one challenge, one backend drain. This is a local host seam;
/// callers still need the normative authenticated primary message composition.
public actor InteractiveNativeVideoEnrollmentCoordinatorV0 {
    public enum Phase: Sendable { case idle, preparing, challenged, proving, active, retiring, retired }
    public private(set) var phase: Phase = .idle
    private let operationID = UUID()
    public let logicalWidthPoints: UInt32?
    public let logicalHeightPoints: UInt32?
    private let monotonicNanoseconds: @Sendable () -> UInt64
    public let authority: InteractiveNativeVideoAuthorityV0
    private let readAuthority: @Sendable () async throws -> InteractiveNativeVideoAuthorityV0?
    private let monotonicMilliseconds: @Sendable () -> UInt64
    private let unixMilliseconds: @Sendable () -> UInt64
    private let backend: any InteractiveNativeVideoEnrollmentBackendV0
    private let initialMonotonicMilliseconds: UInt64
    private let conformanceChallenge: Data?
    private var challenge: InteractiveNativeVideoEnrollmentChallengeV0?
    private var drain: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?

    public init(authority: InteractiveNativeVideoAuthorityV0,
                backend: any InteractiveNativeVideoEnrollmentBackendV0,
                readAuthority: @escaping @Sendable () async throws -> InteractiveNativeVideoAuthorityV0?,
                monotonicMilliseconds: @escaping @Sendable () -> UInt64,
                unixMilliseconds: @escaping @Sendable () -> UInt64,
                conformanceChallenge: Data? = nil,
                logicalWidthPoints: UInt32? = nil, logicalHeightPoints: UInt32? = nil,
                monotonicNanoseconds: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }) {
        self.logicalWidthPoints = logicalWidthPoints
        self.logicalHeightPoints = logicalHeightPoints
        self.monotonicNanoseconds = monotonicNanoseconds
        self.authority = authority
        self.backend = backend
        self.readAuthority = readAuthority
        self.monotonicMilliseconds = monotonicMilliseconds
        self.unixMilliseconds = unixMilliseconds
        self.initialMonotonicMilliseconds = monotonicMilliseconds()
        self.conformanceChallenge = conformanceChallenge
    }

    public func prepare(clientCertificateDER: Data) async throws -> InteractiveNativeVideoEnrollmentPreparationV0 {
        guard phase == .idle else { throw InteractiveNativeVideoCoordinatorFailureV0.invalidPhase }
        phase = .preparing
        do {
            guard (1...4096).contains(clientCertificateDER.count) else {
                throw InteractiveNativeVideoCoordinatorFailureV0.invalidMaterial
            }
            try await checkAuthority(expected: .preparing)
            let hostDER = try await backend.prepare(operationID: operationID,
                authority: authority, clientCertificateDER: clientCertificateDER)
            try await checkAuthority(expected: .preparing)
            guard (1...4096).contains(hostDER.count) else {
                throw InteractiveNativeVideoCoordinatorFailureV0.invalidMaterial
            }
            let proof = try InteractiveNativeVideoEnrollmentChallengeV0(
                binding: authority.binding, surface: authority.surface,
                sessionPublicKeyX963: authority.sessionPublicKeyX963,
                clientCertificateSHA256: Data(SHA256.hash(data: clientCertificateDER)),
                hostCertificateSHA256: Data(SHA256.hash(data: hostDER)),
                issuedAtUnixMilliseconds: unixMilliseconds(),
                issuedAtMonotonicMilliseconds: monotonicMilliseconds(),
                conformanceChallenge: conformanceChallenge)
            challenge = proof
            phase = .challenged
            startWatchdog()
            return try InteractiveNativeVideoEnrollmentPreparationV0(hostCertificateDER: hostDER,
                signingInput: proof.signingInput, hostChallenge: proof.challenge,
                issuedAtUnixMilliseconds: proof.issuedAtUnixMilliseconds,
                expiresAtUnixMilliseconds: proof.expiresAtUnixMilliseconds)
        } catch {
            await retire()
            throw error
        }
    }

    public func activate(rawSignature: Data) async throws -> InteractiveNativeVideoEndpointV0 {
        guard phase == .challenged, let challenge else {
            throw InteractiveNativeVideoCoordinatorFailureV0.invalidPhase
        }
        // Reserve before the authority read; parallel proofs cannot replay it.
        phase = .proving
        do {
            try await checkAuthority(expected: .proving, proofDeadline: true)
            guard challenge.consume(rawSignature: rawSignature, currentBinding: authority.binding,
                currentSurface: authority.surface, currentSessionPublicKeyX963: authority.sessionPublicKeyX963,
                nowMonotonicMilliseconds: monotonicMilliseconds()) else {
                throw InteractiveNativeVideoCoordinatorFailureV0.invalidProof
            }
            let endpoint = try await backend.activate(operationID: operationID)
            guard await backend.isActive(operationID: operationID) else {
                throw InteractiveNativeVideoCoordinatorFailureV0.backendUnavailable
            }
            try await checkAuthority(expected: .proving, proofDeadline: true)
            phase = .active
            return endpoint
        } catch {
            await retire()
            throw error
        }
    }

    public func acknowledgePresentation(encodedWidth: Int, encodedHeight: Int,
        nativeGeneration: Int64, presentationID: UUID) async throws -> (evidence: InteractiveNativeVideoCaptureEvidenceV0, inputAdmitted: Bool) {
        guard (1...9_007_199_254_740_991).contains(nativeGeneration) else {
            throw InteractiveNativeVideoCoordinatorFailureV0.invalidMaterial
        }
        do {
            let evidence = try await presentationEvidence(encodedWidth: encodedWidth, encodedHeight: encodedHeight)
            try await checkAuthority(expected: .active)
            let admitted = try await backend.admitPresentation(operationID: operationID,
                nativeGeneration: nativeGeneration, presentationID: presentationID)
            try await checkAuthority(expected: .active)
            guard await backend.isActive(operationID: operationID) else {
                throw InteractiveNativeVideoCoordinatorFailureV0.backendUnavailable
            }
            try await checkAuthority(expected: .active)
            try evidence.validate(operationID: operationID, encodedWidth: encodedWidth, encodedHeight: encodedHeight,
                nowMonotonicNanoseconds: monotonicNanoseconds())
            return (evidence, admitted)
        } catch { await retire(); throw error }
    }

    /// Correlates an already presented client frame with the exact current host
    /// sample. This observation never releases the runtime's input pause.
    public func presentationEvidence(encodedWidth: Int, encodedHeight: Int) async throws
        -> InteractiveNativeVideoCaptureEvidenceV0 {
        guard phase == .active, encodedWidth == authority.surface.encodedWidth,
              encodedHeight == authority.surface.encodedHeight,
              let logicalWidthPoints, logicalWidthPoints > 0,
              let logicalHeightPoints, logicalHeightPoints > 0 else {
            throw InteractiveNativeVideoCoordinatorFailureV0.invalidMaterial
        }
        do {
            try await checkAuthority(expected: .active)
            guard await backend.isActive(operationID: operationID) else {
                throw InteractiveNativeVideoCoordinatorFailureV0.backendUnavailable
            }
            try await checkAuthority(expected: .active)
            guard let evidence = try await backend.captureEvidence(operationID: operationID) else {
                throw InteractiveNativeVideoCoordinatorFailureV0.backendUnavailable
            }
            try evidence.validate(operationID: operationID, encodedWidth: encodedWidth,
                encodedHeight: encodedHeight, nowMonotonicNanoseconds: monotonicNanoseconds())
            try await checkAuthority(expected: .active)
            guard await backend.isActive(operationID: operationID) else {
                throw InteractiveNativeVideoCoordinatorFailureV0.backendUnavailable
            }
            try await checkAuthority(expected: .active)
            // Neither the final activity await nor admission read can age the
            // sample past its permitted lifetime before the receipt is returned.
            try evidence.validate(operationID: operationID, encodedWidth: encodedWidth,
                encodedHeight: encodedHeight, nowMonotonicNanoseconds: monotonicNanoseconds())
            return evidence
        } catch {
            await retire()
            throw error
        }
    }

    /// Explicit Stop, disconnect, or surface replacement is terminal. All callers
    /// join the same drain, including an activation completing after cancellation.
    public func retire() async {
        if phase == .retired { return }
        if let drain { await drain.value; phase = .retired; return }
        phase = .retiring
        challenge?.cancel()
        watchdog?.cancel()
        watchdog = nil
        let backend = self.backend, operationID = self.operationID
        let task = Task { await backend.retire(operationID: operationID) }
        drain = task
        await task.value
        phase = .retired
    }

    private func checkAuthority(expected: Phase, proofDeadline: Bool = false) async throws {
        guard phase == expected, clockIsValid(proofDeadline: proofDeadline) else {
            throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost
        }
        let current = try await readAuthority()
        guard phase == expected, current == authority, clockIsValid(proofDeadline: proofDeadline) else {
            throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost
        }
    }

    private func clockIsValid(proofDeadline: Bool) -> Bool {
        let now = monotonicMilliseconds()
        guard now >= initialMonotonicMilliseconds,
              now < authority.binding.expiresAtMonotonicMilliseconds else { return false }
        if proofDeadline, let challenge { return now < challenge.expiresAtMonotonicMilliseconds }
        return true
    }

    private func startWatchdog() {
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, let self else { return }
                if !(await self.refreshAuthority()) { return }
            }
        }
    }

    /// Also permits a trusted owner to force an immediate check on grant changes.
    @discardableResult public func refreshAuthority() async -> Bool {
        let expected = phase
        if expected == .retiring { await retire(); return false }
        guard expected == .challenged || expected == .proving || expected == .active else { return false }
        do {
            try await checkAuthority(expected: expected, proofDeadline: expected != .active)
            if expected == .active {
                guard await backend.isActive(operationID: operationID) else {
                    throw InteractiveNativeVideoCoordinatorFailureV0.backendUnavailable
                }
                try await checkAuthority(expected: expected)
            }
            return true
        } catch {
            // A legitimate phase advance during this read is not revocation.
            // Its own transition performs fresh authority checks.
            if phase != expected, phase != .retiring, phase != .retired { return true }
            await retire()
            return false
        }
    }
}
