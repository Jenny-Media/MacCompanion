import Foundation

/// Public preparation material; the single-use verifier stays on the host.
/// Construction is not certificate validation, authentication, or approval.
public struct InteractiveNativeVideoEnrollmentPreparationV0: Sendable {
    public let hostCertificateDER: Data
    public let signingInput: Data
    public let hostChallenge: Data
    public let issuedAtUnixMilliseconds: UInt64
    public let expiresAtUnixMilliseconds: UInt64

    public init(hostCertificateDER: Data, signingInput: Data, hostChallenge: Data,
                issuedAtUnixMilliseconds: UInt64, expiresAtUnixMilliseconds: UInt64) throws {
        guard (1...4096).contains(hostCertificateDER.count), (1...1024).contains(signingInput.count),
              hostChallenge.count == 32, issuedAtUnixMilliseconds > 0,
              expiresAtUnixMilliseconds <= 9_007_199_254_740_991,
              expiresAtUnixMilliseconds > issuedAtUnixMilliseconds,
              expiresAtUnixMilliseconds - issuedAtUnixMilliseconds <= 15_000 else {
            throw InteractiveNativeVideoFailureV0.authorizationLost
        }
        self.hostCertificateDER = hostCertificateDER
        self.signingInput = signingInput
        self.hostChallenge = hostChallenge
        self.issuedAtUnixMilliseconds = issuedAtUnixMilliseconds
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
    }
}
