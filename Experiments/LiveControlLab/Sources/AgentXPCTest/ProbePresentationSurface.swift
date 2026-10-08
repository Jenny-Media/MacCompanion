#if !DEBUG || !os(macOS)
#error("Disposable menu presentation is macOS Debug only")
#endif
import CompanionIPC
import CompanionWire
import Foundation

/// Generated transport-only review. It cannot authorize a real pairing or
/// grant, and it is never printed or placed in a second fixture corpus.
func probePresentationReview(testID: UUID) throws -> LocalPairingReviewV0 {
    try LocalPairingReviewV0(reviewID: testID, pairingID: testID, clientID: testID,
        sessionPublicKeyFingerprint: .init(Data(repeating: 1, count: 32)),
        approvalPublicKeyFingerprint: .init(Data(repeating: 2, count: 32)),
        transcriptDigest: .init(Data(repeating: 3, count: 32)),
        authenticationString: .init("ABC-123"), expectedPolicyRevision: .init(rawValue: 1),
        expiresAtUnixMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000) + 60_000)
}

actor ProbePresentationSurface: LocalPairingReviewSurfaceV0, LocalHostIdentityRecoverySurfaceV0 {
    enum Event: Equatable, Sendable { case presented(LocalPairingReviewV0), withdrawn(UUID) }
    enum Failure: Error { case timeout, unexpectedRecovery }
    private var events: [Event] = []
    func presentLocalPairingReview(_ review: LocalPairingReviewV0) { events.append(.presented(review)) }
    func withdrawLocalPairingReview(reviewID: UUID) { events.append(.withdrawn(reviewID)) }
    func next(timeout: Duration = .seconds(12)) async throws -> Event {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if !events.isEmpty { return events.removeFirst() }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw Failure.timeout
    }
    var isEmpty: Bool { events.isEmpty }
    func presentHostIdentityRecoveryReview(_ review: LocalHostIdentityRecoveryReviewV0) throws {
        throw Failure.unexpectedRecovery
    }
    func presentHostIdentityRecoveryResume(_ command: LocalHostIdentityRecoveryCommandV0) throws {
        throw Failure.unexpectedRecovery
    }
    func withdrawHostIdentityRecovery(reviewID: UUID) {}
}
