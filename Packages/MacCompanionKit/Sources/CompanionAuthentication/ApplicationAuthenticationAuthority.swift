import CompanionDomain
import CompanionPersistence
import CompanionSecurity
import CryptoKit
import Foundation

public protocol AuthenticationDeviceReader: Sendable {
    func device(clientID: UUID) async throws -> StoredDeviceRecord?
}

extension SQLiteSecurityStore: AuthenticationDeviceReader {}

public enum ApplicationAuthenticationError: Error, Equatable, Sendable {
    case invalidInput
    case capacityExceeded
    case challengeNotFound
    case challengeExpired
    case authenticationFailed
}

public struct ApplicationAuthenticationChallenge: Equatable, Sendable {
    public let connectionID: Data
    public let serverNonce: Data
    public let hostFingerprint: Data
    public let selectedMajor: UInt16
    public let selectedMinor: UInt16
}

public struct AuthenticatedDevicePrincipal: Equatable, Sendable {
    public let deviceID: UUID
    public let clientID: UUID
    public let deviceState: DeviceAuthorizationState
    public let authorizationEpoch: AuthorizationEpoch
    public let grantRevision: GrantRevision
    public let policyRevision: PolicyRevision

    public init(
        deviceID: UUID,
        clientID: UUID,
        deviceState: DeviceAuthorizationState,
        authorizationEpoch: AuthorizationEpoch,
        grantRevision: GrantRevision,
        policyRevision: PolicyRevision
    ) {
        self.deviceID = deviceID
        self.clientID = clientID
        self.deviceState = deviceState
        self.authorizationEpoch = authorizationEpoch
        self.grantRevision = grantRevision
        self.policyRevision = policyRevision
    }
}

public actor ApplicationAuthenticationAuthority {
    public static let challengeLifetimeMilliseconds: Int64 = 10_000
    public static let maximumPendingChallenges = 128

    private struct Candidate: Sendable {
        let deviceID: UUID
        let clientID: UUID
        let sessionPublicKeyX963: Data
        let authorizationEpoch: AuthorizationEpoch
    }

    private struct PendingChallenge: Sendable {
        let connectionID: Data
        let clientID: UUID
        let clientNonce: Data
        let serverNonce: Data
        let hostFingerprint: Data
        let deadlineMonotonicMilliseconds: Int64
        let verificationPublicKeyX963: Data
        let candidate: Candidate?
    }

    private let deviceReader: any AuthenticationDeviceReader
    private var pending: [Data: PendingChallenge] = [:]

    public init(deviceReader: any AuthenticationDeviceReader) {
        self.deviceReader = deviceReader
    }

    public func challenge(
        clientID: UUID,
        clientNonce: Data,
        hostFingerprint: Data,
        monotonicNowMilliseconds: Int64,
        connectionID: Data? = nil,
        serverNonce: Data? = nil
    ) async throws -> ApplicationAuthenticationChallenge {
        guard clientNonce.count == 32,
              hostFingerprint.count == 32,
              monotonicNowMilliseconds >= 0,
              monotonicNowMilliseconds <= Int64.max - Self.challengeLifetimeMilliseconds else {
            throw ApplicationAuthenticationError.invalidInput
        }
        expireChallenges(monotonicNowMilliseconds: monotonicNowMilliseconds)
        guard pending.count < Self.maximumPendingChallenges else {
            throw ApplicationAuthenticationError.capacityExceeded
        }
        let connection = connectionID ?? Self.randomBytes(count: 16)
        let nonce = serverNonce ?? Self.randomBytes(count: 32)
        guard connection.count == 16, nonce.count == 32, pending[connection] == nil else {
            throw ApplicationAuthenticationError.invalidInput
        }

        let record = try await deviceReader.device(clientID: clientID)
        let eligible = record.flatMap { value in
            value.authorization.state.canAuthenticate ? value : nil
        }
        let dummyPublicKey = P256.Signing.PrivateKey().publicKey.x963Representation
        let candidate = eligible.map {
            Candidate(
                deviceID: $0.deviceID,
                clientID: $0.clientID,
                sessionPublicKeyX963: $0.sessionPublicKeyX963,
                authorizationEpoch: $0.authorization.authorizationEpoch
            )
        }
        pending[connection] = PendingChallenge(
            connectionID: connection,
            clientID: clientID,
            clientNonce: clientNonce,
            serverNonce: nonce,
            hostFingerprint: hostFingerprint,
            deadlineMonotonicMilliseconds: monotonicNowMilliseconds + Self.challengeLifetimeMilliseconds,
            verificationPublicKeyX963: eligible?.sessionPublicKeyX963 ?? dummyPublicKey,
            candidate: candidate
        )
        return ApplicationAuthenticationChallenge(
            connectionID: connection,
            serverNonce: nonce,
            hostFingerprint: hostFingerprint,
            selectedMajor: 0,
            selectedMinor: 1
        )
    }

    public func prove(
        connectionID: Data,
        signature: Data,
        monotonicNowMilliseconds: Int64
    ) async throws -> AuthenticatedDevicePrincipal {
        guard connectionID.count == 16, signature.count == 64,
              monotonicNowMilliseconds >= 0 else {
            throw ApplicationAuthenticationError.invalidInput
        }
        guard let challenge = pending.removeValue(forKey: connectionID) else {
            throw ApplicationAuthenticationError.challengeNotFound
        }
        guard monotonicNowMilliseconds < challenge.deadlineMonotonicMilliseconds else {
            throw ApplicationAuthenticationError.challengeExpired
        }
        let signingInput: Data
        do {
            signingInput = try CompanionSecurityV0.authenticationSigningInput(
                clientID: challenge.clientID,
                connectionID: challenge.connectionID,
                clientNonce: challenge.clientNonce,
                serverNonce: challenge.serverNonce,
                hostFingerprint: challenge.hostFingerprint,
                selectedMajor: 0,
                selectedMinor: 1
            )
        } catch {
            throw ApplicationAuthenticationError.authenticationFailed
        }
        let signatureValid = (try? CompanionSecurityV0.verifySignature(
            rawSignature: signature,
            signingInput: signingInput,
            publicKeyX963: challenge.verificationPublicKeyX963
        )) == true
        guard signatureValid, let candidate = challenge.candidate,
              let current = try await deviceReader.device(clientID: candidate.clientID),
              current.deviceID == candidate.deviceID,
              current.sessionPublicKeyX963 == candidate.sessionPublicKeyX963,
              current.authorization.state.canAuthenticate,
              current.authorization.authorizationEpoch == candidate.authorizationEpoch else {
            throw ApplicationAuthenticationError.authenticationFailed
        }
        return AuthenticatedDevicePrincipal(
            deviceID: current.deviceID,
            clientID: current.clientID,
            deviceState: current.authorization.state,
            authorizationEpoch: current.authorization.authorizationEpoch,
            grantRevision: current.authorization.grantRevision,
            policyRevision: current.policyRevision
        )
    }

    /// Revalidates an established connection principal against durable state.
    /// Any security-relevant revision change invalidates the boot-scoped
    /// authenticated session instead of silently widening or narrowing it.
    public func revalidate(
        _ principal: AuthenticatedDevicePrincipal
    ) async throws -> AuthenticatedDevicePrincipal {
        guard let current = try await deviceReader.device(clientID: principal.clientID),
              current.deviceID == principal.deviceID,
              current.authorization.state.canAuthenticate,
              current.authorization.state == principal.deviceState,
              current.authorization.authorizationEpoch == principal.authorizationEpoch,
              current.authorization.grantRevision == principal.grantRevision,
              current.policyRevision == principal.policyRevision else {
            throw ApplicationAuthenticationError.authenticationFailed
        }
        return principal
    }

    private func expireChallenges(monotonicNowMilliseconds: Int64) {
        pending = pending.filter {
            monotonicNowMilliseconds < $0.value.deadlineMonotonicMilliseconds
        }
    }

    private static func randomBytes(count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in
            UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
        })
    }
}
