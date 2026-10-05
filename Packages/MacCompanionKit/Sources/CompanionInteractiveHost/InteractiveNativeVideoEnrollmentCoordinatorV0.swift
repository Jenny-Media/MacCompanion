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
    /// Admission is explicit, and defaults off until the full adapter exists.
    func supportsStreamContinuity(operationID: UUID) async -> Bool
    /// Revoke input and pause capture before returning. Keep the exact owned
    /// certificate/process/socket resources, bounded by the original lease.
    func retainStream(operationID: UUID) async throws
    func isStreamRetained(operationID: UUID) async -> Bool
    /// Fence before suspending; cancel preparation/activation, reap the helper,
    /// and destroy owned credentials. Idempotent even before preparation starts.
    func retire(operationID: UUID) async
}
public extension InteractiveNativeVideoEnrollmentBackendV0 {
    func supportsStreamContinuity(operationID: UUID) async -> Bool { false }
    func retainStream(operationID: UUID) async throws { throw InteractiveNativeVideoCoordinatorFailureV0.backendUnavailable }
    func isStreamRetained(operationID: UUID) async -> Bool { false }
    func canPostInput(operationID: UUID) async -> Bool { false }
    func admitPresentation(operationID: UUID, nativeGeneration: Int64, presentationID: UUID) async throws -> Bool { false }
    func postInputBatch(operationID: UUID, beforeDeadlineNanoseconds: UInt64,
                        batch: @escaping @Sendable () throws -> Void) async throws {
        throw InteractiveNativeVideoCoordinatorFailureV0.backendUnavailable
    }
    func captureEvidence(operationID: UUID) async throws -> InteractiveNativeVideoCaptureEvidenceV0? { nil }
}

/// Local retained-resource capsule. It is never decoded from a peer. Every
/// replacement still uses the existing golden proof for its new surface.
public struct InteractiveNativeVideoRetainedEnrollmentV1: Sendable {
    public let operationID: UUID
    public let authority: InteractiveNativeVideoAuthorityV0
    public let clientCertificateDER: Data
    public let hostCertificateDER: Data
    public let backend: any InteractiveNativeVideoEnrollmentBackendV0
    public let handoffDeadlineMonotonicMilliseconds: UInt64
    fileprivate init(operationID: UUID, authority: InteractiveNativeVideoAuthorityV0,
        clientCertificateDER: Data, hostCertificateDER: Data,
        backend: any InteractiveNativeVideoEnrollmentBackendV0,
        handoffDeadlineMonotonicMilliseconds: UInt64) {
        self.operationID = operationID; self.authority = authority
        self.clientCertificateDER = clientCertificateDER; self.hostCertificateDER = hostCertificateDER
        self.backend = backend; self.handoffDeadlineMonotonicMilliseconds = handoffDeadlineMonotonicMilliseconds
    }
}


public enum InteractiveNativeVideoCoordinatorFailureV0: Error, Equatable, Sendable {
    case invalidPhase, invalidMaterial, authorizationLost, invalidProof, backendUnavailable
}

/// One generation, one challenge, one backend drain. This is a local host seam;
/// callers still need the normative authenticated primary message composition.
public actor InteractiveNativeVideoEnrollmentCoordinatorV0 {
    public enum Phase: Sendable { case idle, preparing, challenged, proving, active, retaining, retained, retiring, retired }
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
    private let readRetainedAuthority: @Sendable () async throws -> Bool
    private let predecessor: InteractiveNativeVideoRetainedEnrollmentV1?
    private var clientCertificateDER: Data?
    private var hostCertificateDER: Data?
    private var retentionDeadline: UInt64?
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
                monotonicNanoseconds: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
                readRetainedAuthority: @escaping @Sendable () async throws -> Bool = { false },
                predecessor: InteractiveNativeVideoRetainedEnrollmentV1? = nil) {
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
        self.readRetainedAuthority = readRetainedAuthority
        self.predecessor = predecessor
    }

    public func prepare(clientCertificateDER: Data) async throws -> InteractiveNativeVideoEnrollmentPreparationV0 {
        guard phase == .idle else { throw InteractiveNativeVideoCoordinatorFailureV0.invalidPhase }
        phase = .preparing
        do {
            guard (1...4096).contains(clientCertificateDER.count) else {
                throw InteractiveNativeVideoCoordinatorFailureV0.invalidMaterial
            }
            if let predecessor {
                guard authority.binding == predecessor.authority.binding,
                      authority.sessionPublicKeyX963 == predecessor.authority.sessionPublicKeyX963,
                      authority.surface != predecessor.authority.surface,
                      authority.surface.encodedWidth == predecessor.authority.surface.encodedWidth,
                      authority.surface.encodedHeight == predecessor.authority.surface.encodedHeight,
                      clientCertificateDER == predecessor.clientCertificateDER else {
                    throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost
                }
            }
            try await checkAuthority(expected: .preparing)
            let hostDER = try await backend.prepare(operationID: operationID,
                authority: authority, clientCertificateDER: clientCertificateDER)
            try await checkAuthority(expected: .preparing)
            guard (1...4096).contains(hostDER.count) else {
                throw InteractiveNativeVideoCoordinatorFailureV0.invalidMaterial
            }
            guard predecessor == nil || hostDER == predecessor?.hostCertificateDER else {
                throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost
            }
            self.clientCertificateDER = clientCertificateDER
            self.hostCertificateDER = hostDER
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

    public func supportsStreamContinuity() async -> Bool {
        guard phase == .active else { return false }
        let supported = await backend.supportsStreamContinuity(operationID: operationID)
        return supported && phase == .active
    }

    /// The old exact-surface reader is checked before suspension. Once capture
    /// is paused, the retained reader checks the original Control/key/primary
    /// independently of a view that is about to change.
    public func retainStream() async throws {
        guard phase == .active, clientCertificateDER != nil, hostCertificateDER != nil else {
            throw InteractiveNativeVideoCoordinatorFailureV0.invalidPhase
        }
        do {
            try await checkAuthority(expected: .active)
            guard await supportsStreamContinuity() else { throw InteractiveNativeVideoCoordinatorFailureV0.backendUnavailable }
            try await checkAuthority(expected: .active)
            phase = .retaining
            let now = monotonicMilliseconds()
            retentionDeadline = min(authority.binding.expiresAtMonotonicMilliseconds,
                now > UInt64.max - 15_000 ? UInt64.max : now + 15_000)
            try await checkRetainedAuthority(expected: .retaining)
            try await backend.retainStream(operationID: operationID)
            try await checkRetainedAuthority(expected: .retaining)
            guard await backend.isStreamRetained(operationID: operationID) else {
                throw InteractiveNativeVideoCoordinatorFailureV0.backendUnavailable
            }
            try await checkRetainedAuthority(expected: .retaining)
            phase = .retained
        } catch { await retire(); throw error }
    }

    public func retainedEnrollment() async throws -> InteractiveNativeVideoRetainedEnrollmentV1 {
        try await checkRetainedAuthority(expected: .retained)
        guard let clientCertificateDER, let hostCertificateDER, let retentionDeadline,
              await backend.isStreamRetained(operationID: operationID) else {
            throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost
        }
        try await checkRetainedAuthority(expected: .retained)
        return .init(operationID: operationID, authority: authority,
            clientCertificateDER: clientCertificateDER, hostCertificateDER: hostCertificateDER,
            backend: backend, handoffDeadlineMonotonicMilliseconds: retentionDeadline)
    }

    /// Only the trusted bridge calls this after replacement preparation has
    /// transferred resource ownership. It does not admit presentation or input.
    package func relinquishRetainedEnrollment() {
        guard phase == .retained else { return }
        watchdog?.cancel(); watchdog = nil
        challenge?.cancel(); challenge = nil
        phase = .retired
        clientCertificateDER = nil; hostCertificateDER = nil
    }

    private func checkRetainedAuthority(expected: Phase) async throws {
        guard !Task.isCancelled, phase == expected, clockIsValid(proofDeadline: false),
              let retentionDeadline, monotonicMilliseconds() < retentionDeadline,
              try await readRetainedAuthority(), !Task.isCancelled, phase == expected,
              clockIsValid(proofDeadline: false), monotonicMilliseconds() < retentionDeadline else {
            throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost
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
            let evidence = try await waitForCaptureEvidence()
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

    /// A client frame can precede the child's first evidence publication. An
    /// absent observation is pending, never admission. Every await remains
    /// fenced by the original authority, backend and Control deadline.
    private func waitForCaptureEvidence() async throws -> InteractiveNativeVideoCaptureEvidenceV0 {
        let deadline = ContinuousClock.now + .seconds(2)
        repeat {
            try Task.checkCancellation()
            try await checkAuthority(expected: .active)
            let evidence = try await backend.captureEvidence(operationID: operationID)
            try await checkAuthority(expected: .active)
            guard await backend.isActive(operationID: operationID) else {
                throw InteractiveNativeVideoCoordinatorFailureV0.backendUnavailable
            }
            try await checkAuthority(expected: .active)
            // A backend read can finish after the pending observation window.
            // Its late sample must not turn an expired wait into admission.
            guard ContinuousClock.now < deadline else { break }
            if let evidence { return evidence }
            try await Task.sleep(for: .milliseconds(25))
        } while ContinuousClock.now < deadline
        throw InteractiveNativeVideoCoordinatorFailureV0.backendUnavailable
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
        guard !Task.isCancelled, phase == expected, clockIsValid(proofDeadline: proofDeadline) else {
            throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost
        }
        let current = try await readAuthority()
        guard !Task.isCancelled, phase == expected, current == authority, clockIsValid(proofDeadline: proofDeadline) else {
            throw InteractiveNativeVideoCoordinatorFailureV0.authorizationLost
        }
    }

    private func clockIsValid(proofDeadline: Bool) -> Bool {
        let now = monotonicMilliseconds()
        guard now >= initialMonotonicMilliseconds,
              now < authority.binding.expiresAtMonotonicMilliseconds else { return false }
        if (phase == .preparing || phase == .challenged || phase == .proving), let predecessor,
           now >= predecessor.handoffDeadlineMonotonicMilliseconds { return false }
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
        guard expected == .challenged || expected == .proving || expected == .active
            || expected == .retaining || expected == .retained else { return false }
        do {
            if expected == .retaining || expected == .retained {
                try await checkRetainedAuthority(expected: expected)
                if expected == .retained {
                    guard await backend.isStreamRetained(operationID: operationID) else {
                        throw InteractiveNativeVideoCoordinatorFailureV0.backendUnavailable
                    }
                    try await checkRetainedAuthority(expected: expected)
                }
                return true
            }
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
