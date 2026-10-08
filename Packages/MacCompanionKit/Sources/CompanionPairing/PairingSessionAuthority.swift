import CompanionDomain
import CompanionPersistence
import CompanionSecurity
import CryptoKit
import Foundation

public protocol PairingCommitter: Sendable {
    func commitPairing(
        pairingID: UUID,
        record: StoredDeviceRecord,
        displayName: DeviceDisplayName
    ) async throws
}

extension SQLiteSecurityStore: PairingCommitter {
    public func commitPairing(
        pairingID: UUID,
        record: StoredDeviceRecord,
        displayName: DeviceDisplayName
    ) async throws {
        try commitPairing(
            pairingID: pairingID,
            record: record,
            displayName: Optional(displayName)
        )
    }
}

public enum PairingSessionError: Error, Equatable, Sendable {
    case invalidInput
    case capacityExceeded
    case notFound
    case expired
    case alreadyConsumed
    case invalidState
    case invalidProof(remainingAttempts: Int)
    case transcriptMismatch
    case approvalRejected
}

public struct PairingAdvertisement: Equatable, Sendable {
    public let pairingID: UUID
    public let oneTimeSecret: Data
    public let hostFingerprint: Data
    public let expiresAtUnixMilliseconds: Int64
}

public struct PairingChallenge: Equatable, Sendable {
    public let hostNonce: Data
    public let hostFingerprint: Data
    public let selectedMajor: UInt16
    public let selectedMinor: UInt16
}

public struct PairingApprovalContext: Equatable, Sendable {
    public let pairingID: UUID
    public let clientID: UUID
    public let sessionPublicKeyX963: Data
    public let approvalPublicKeyX963: Data
    public let sessionPublicKeyFingerprint: Data
    public let approvalPublicKeyFingerprint: Data
    public let transcriptDigest: Data
    public let authenticationString: String
    public let expiresAtUnixMilliseconds: Int64
    public let deadlineMonotonicMilliseconds: Int64

    public init(
        pairingID: UUID,
        clientID: UUID,
        sessionPublicKeyX963: Data,
        approvalPublicKeyX963: Data,
        sessionPublicKeyFingerprint: Data,
        approvalPublicKeyFingerprint: Data,
        transcriptDigest: Data,
        authenticationString: String,
        expiresAtUnixMilliseconds: Int64,
        deadlineMonotonicMilliseconds: Int64
    ) throws {
        let authenticationBytes = Array(authenticationString.utf8)
        let isAuthenticationString = authenticationBytes.count == 7
            && authenticationBytes[3] == 0x2d
            && authenticationBytes.enumerated().allSatisfy { index, byte in
                index == 3
                    || (byte >= 0x30 && byte <= 0x39)
                    || (byte >= 0x41 && byte <= 0x46)
            }
        guard sessionPublicKeyX963.count == 65,
              sessionPublicKeyX963.first == 0x04,
              approvalPublicKeyX963.count == 65,
              approvalPublicKeyX963.first == 0x04,
              sessionPublicKeyFingerprint
                == Data(SHA256.hash(data: sessionPublicKeyX963)),
              approvalPublicKeyFingerprint
                == Data(SHA256.hash(data: approvalPublicKeyX963)),
              transcriptDigest.count == 32,
              isAuthenticationString,
              expiresAtUnixMilliseconds > 0,
              expiresAtUnixMilliseconds <= 9_007_199_254_740_991,
              deadlineMonotonicMilliseconds > 0 else {
            throw PairingSessionError.invalidInput
        }
        self.pairingID = pairingID
        self.clientID = clientID
        self.sessionPublicKeyX963 = sessionPublicKeyX963
        self.approvalPublicKeyX963 = approvalPublicKeyX963
        self.sessionPublicKeyFingerprint = sessionPublicKeyFingerprint
        self.approvalPublicKeyFingerprint = approvalPublicKeyFingerprint
        self.transcriptDigest = transcriptDigest
        self.authenticationString = authenticationString
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
        self.deadlineMonotonicMilliseconds = deadlineMonotonicMilliseconds
    }
}

public struct CompletedPairing: Equatable, Sendable {
    public let pairingID: UUID
    public let deviceID: UUID
    public let clientID: UUID
    public let displayName: DeviceDisplayName
    public let policyRevision: PolicyRevision
    public let deviceState: DeviceAuthorizationState

    public init(
        pairingID: UUID,
        deviceID: UUID,
        clientID: UUID,
        displayName: DeviceDisplayName,
        policyRevision: PolicyRevision,
        deviceState: DeviceAuthorizationState = .activeMonitorOnly
    ) {
        self.pairingID = pairingID
        self.deviceID = deviceID
        self.clientID = clientID
        self.displayName = displayName
        self.policyRevision = policyRevision
        self.deviceState = deviceState
    }
}

public actor PairingSessionAuthority {
    public static let lifetimeMilliseconds: Int64 = 5 * 60 * 1_000
    public static let maximumFailedProofs = 5
    public static let maximumActiveSessions = 8

    private enum Phase: Sendable {
        case advertised
        case challenged(Binding)
        case proved(Binding, PairingApprovalContext)
        case committing(Binding, PairingApprovalContext)
    }

    private struct Binding: Sendable {
        let clientID: UUID
        let sessionPublicKeyX963: Data
        let approvalPublicKeyX963: Data
        let clientNonce: Data
        let hostNonce: Data
        let transcriptDigest: Data
    }

    private struct Session: Sendable {
        let pairingID: UUID
        let oneTimeSecret: Data
        let hostFingerprint: Data
        let expiresAtUnixMilliseconds: Int64
        let deadlineMonotonicMilliseconds: Int64
        var failedProofs: Int
        var phase: Phase
    }

    private struct Tombstone: Sendable {
        let error: PairingSessionError
        let removeAfterMonotonicMilliseconds: Int64
    }

    private let committer: any PairingCommitter
    private let auditWriter: (any PairingAuditWritingV0)?
    private let accessProfile: PairingAccessProfileV1
    private var sessions: [UUID: Session] = [:]
    private var tombstones: [UUID: Tombstone] = [:]

    public init(
        committer: any PairingCommitter,
        auditWriter: (any PairingAuditWritingV0)? = nil,
        accessProfile: PairingAccessProfileV1 = .monitorOnly
    ) {
        self.committer = committer
        self.auditWriter = auditWriter
        self.accessProfile = accessProfile
    }

    public func createSession(
        pairingID: UUID = UUID(),
        hostFingerprint: Data,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: Int64,
        oneTimeSecret: Data? = nil
    ) throws -> PairingAdvertisement {
        try validateTimes(
            wallNowUnixMilliseconds: wallNowUnixMilliseconds,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
        purgeTombstones(monotonicNowMilliseconds: monotonicNowMilliseconds)
        guard sessions.count < Self.maximumActiveSessions else {
            throw PairingSessionError.capacityExceeded
        }
        guard sessions[pairingID] == nil, tombstones[pairingID] == nil,
              hostFingerprint.count == 32 else {
            throw PairingSessionError.invalidInput
        }
        let secret = oneTimeSecret ?? Self.randomBytes(count: 32)
        guard secret.count == 32,
              wallNowUnixMilliseconds <= Int64.max - Self.lifetimeMilliseconds,
              monotonicNowMilliseconds <= Int64.max - Self.lifetimeMilliseconds else {
            throw PairingSessionError.invalidInput
        }
        let expiresAt = wallNowUnixMilliseconds + Self.lifetimeMilliseconds
        let deadline = monotonicNowMilliseconds + Self.lifetimeMilliseconds
        sessions[pairingID] = Session(
            pairingID: pairingID,
            oneTimeSecret: secret,
            hostFingerprint: hostFingerprint,
            expiresAtUnixMilliseconds: expiresAt,
            deadlineMonotonicMilliseconds: deadline,
            failedProofs: 0,
            phase: .advertised
        )
        return PairingAdvertisement(
            pairingID: pairingID,
            oneTimeSecret: secret,
            hostFingerprint: hostFingerprint,
            expiresAtUnixMilliseconds: expiresAt
        )
    }

    public func begin(
        pairingID: UUID,
        clientID: UUID,
        sessionPublicKeyX963: Data,
        approvalPublicKeyX963: Data,
        clientNonce: Data,
        monotonicNowMilliseconds: Int64,
        hostNonce: Data? = nil
    ) throws -> PairingChallenge {
        var session = try liveSession(
            pairingID: pairingID,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
        guard case .advertised = session.phase else {
            throw PairingSessionError.invalidState
        }
        let nonce = hostNonce ?? Self.randomBytes(count: 32)
        guard clientNonce.count == 32, nonce.count == 32 else {
            throw PairingSessionError.invalidInput
        }
        let transcript: Data
        do {
            transcript = try CompanionSecurityV0.pairingTranscriptInput(
                pairingID: pairingID,
                hostFingerprint: session.hostFingerprint,
                clientID: clientID,
                sessionPublicKeyX963: sessionPublicKeyX963,
                approvalPublicKeyX963: approvalPublicKeyX963,
                clientNonce: clientNonce,
                hostNonce: nonce,
                selectedMajor: 0,
                selectedMinor: 1
            )
        } catch {
            throw PairingSessionError.invalidInput
        }
        let binding = Binding(
            clientID: clientID,
            sessionPublicKeyX963: sessionPublicKeyX963,
            approvalPublicKeyX963: approvalPublicKeyX963,
            clientNonce: clientNonce,
            hostNonce: nonce,
            transcriptDigest: CompanionSecurityV0.pairingTranscriptDigest(transcript)
        )
        session.phase = .challenged(binding)
        sessions[pairingID] = session
        return PairingChallenge(
            hostNonce: nonce,
            hostFingerprint: session.hostFingerprint,
            selectedMajor: 0,
            selectedMinor: 1
        )
    }

    public func prove(
        pairingID: UUID,
        secretProof: Data,
        signature: Data,
        monotonicNowMilliseconds: Int64
    ) throws -> PairingApprovalContext {
        var session = try liveSession(
            pairingID: pairingID,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
        guard case let .challenged(binding) = session.phase else {
            throw PairingSessionError.invalidState
        }

        let validProof = (try? CompanionSecurityV0.verifyPairingSecretProof(
            secretProof,
            oneTimeSecret: session.oneTimeSecret,
            transcriptDigest: binding.transcriptDigest
        )) == true
        let signingInput = try? CompanionSecurityV0.pairingSignatureInput(
            transcriptDigest: binding.transcriptDigest
        )
        let validSignature = signingInput.flatMap {
            try? CompanionSecurityV0.verifySignature(
                rawSignature: signature,
                signingInput: $0,
                publicKeyX963: binding.sessionPublicKeyX963
            )
        } == true

        guard validProof && validSignature else {
            session.failedProofs += 1
            let remaining = max(0, Self.maximumFailedProofs - session.failedProofs)
            if remaining == 0 {
                consume(
                    pairingID: pairingID,
                    error: .alreadyConsumed,
                    monotonicNowMilliseconds: monotonicNowMilliseconds
                )
            } else {
                sessions[pairingID] = session
            }
            throw PairingSessionError.invalidProof(remainingAttempts: remaining)
        }

        let authenticationString: String
        do {
            authenticationString = try CompanionSecurityV0.authenticationString(
                oneTimeSecret: session.oneTimeSecret,
                transcriptDigest: binding.transcriptDigest
            )
        } catch {
            throw PairingSessionError.invalidInput
        }
        let context: PairingApprovalContext
        do {
            context = try PairingApprovalContext(
                pairingID: pairingID,
                clientID: binding.clientID,
                sessionPublicKeyX963: binding.sessionPublicKeyX963,
                approvalPublicKeyX963: binding.approvalPublicKeyX963,
                sessionPublicKeyFingerprint: Data(SHA256.hash(
                    data: binding.sessionPublicKeyX963
                )),
                approvalPublicKeyFingerprint: Data(SHA256.hash(
                    data: binding.approvalPublicKeyX963
                )),
                transcriptDigest: binding.transcriptDigest,
                authenticationString: authenticationString,
                expiresAtUnixMilliseconds:
                    session.expiresAtUnixMilliseconds,
                deadlineMonotonicMilliseconds:
                    session.deadlineMonotonicMilliseconds
            )
        } catch {
            throw PairingSessionError.invalidInput
        }
        session.phase = .proved(binding, context)
        sessions[pairingID] = session
        return context
    }

    public func decideApproval(
        pairingID: UUID,
        approvedTranscriptDigest: Data,
        approved: Bool,
        deviceID: UUID,
        displayName: DeviceDisplayName?,
        policyRevision: PolicyRevision,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: Int64
    ) async throws -> CompletedPairing {
        try validateTimes(
            wallNowUnixMilliseconds: wallNowUnixMilliseconds,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
        var session = try liveSession(
            pairingID: pairingID,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
        guard case let .proved(binding, context) = session.phase else {
            throw PairingSessionError.invalidState
        }
        guard approvedTranscriptDigest == binding.transcriptDigest else {
            throw PairingSessionError.transcriptMismatch
        }
        guard approved else {
            guard displayName == nil else {
                throw PairingSessionError.invalidInput
            }
            consume(
                pairingID: pairingID,
                error: .alreadyConsumed,
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
            throw PairingSessionError.approvalRejected
        }
        guard let displayName else {
            throw PairingSessionError.invalidInput
        }
        guard policyRevision.rawValue >= 1 else {
            throw PairingSessionError.invalidInput
        }

        let record: StoredDeviceRecord
        do {
            record = try StoredDeviceRecord(
                deviceID: deviceID,
                clientID: binding.clientID,
                sessionPublicKeyX963: binding.sessionPublicKeyX963,
                approvalPublicKeyX963: binding.approvalPublicKeyX963,
                authorization: DeviceAuthorization(
                    state: accessProfile.initialState,
                    authorizationEpoch: .init(rawValue: 1),
                    grantRevision: .init(rawValue: 1)
                ),
                policyRevision: policyRevision,
                createdAtUnixMilliseconds: wallNowUnixMilliseconds,
                updatedAtUnixMilliseconds: wallNowUnixMilliseconds
            )
        } catch {
            throw PairingSessionError.invalidInput
        }
        session.phase = .committing(binding, context)
        sessions[pairingID] = session
        do {
            try await committer.commitPairing(
                pairingID: pairingID,
                record: record,
                displayName: displayName
            )
        } catch {
            if var current = sessions[pairingID],
               case .committing = current.phase {
                current.phase = .proved(binding, context)
                sessions[pairingID] = current
            }
            throw error
        }
        await auditWriter?.recordApprovedPairing(
            pairingID: pairingID,
            device: record
        )
        consume(
            pairingID: pairingID,
            error: .alreadyConsumed,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
        return CompletedPairing(
            pairingID: pairingID,
            deviceID: deviceID,
            clientID: binding.clientID,
            displayName: displayName,
            policyRevision: policyRevision,
            deviceState: record.authorization.state
        )
    }

    /// Invalidates a locally dismissed pairing presentation. Cancellation is
    /// allowed before durable commit begins and is retained as a tombstone so
    /// a client that already scanned the code cannot continue afterward.
    public func cancel(
        pairingID: UUID,
        monotonicNowMilliseconds: Int64
    ) throws {
        let session = try liveSession(
            pairingID: pairingID,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
        if case .committing = session.phase {
            throw PairingSessionError.invalidState
        }
        consume(
            pairingID: pairingID,
            error: .alreadyConsumed,
            monotonicNowMilliseconds: monotonicNowMilliseconds
        )
    }

    private func liveSession(
        pairingID: UUID,
        monotonicNowMilliseconds: Int64
    ) throws -> Session {
        guard monotonicNowMilliseconds >= 0 else {
            throw PairingSessionError.invalidInput
        }
        purgeTombstones(monotonicNowMilliseconds: monotonicNowMilliseconds)
        if let tombstone = tombstones[pairingID] {
            throw tombstone.error
        }
        guard let session = sessions[pairingID] else {
            throw PairingSessionError.notFound
        }
        guard monotonicNowMilliseconds < session.deadlineMonotonicMilliseconds else {
            consume(
                pairingID: pairingID,
                error: .expired,
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
            throw PairingSessionError.expired
        }
        return session
    }

    private func consume(
        pairingID: UUID,
        error: PairingSessionError,
        monotonicNowMilliseconds: Int64
    ) {
        sessions[pairingID] = nil
        let removeAfter = monotonicNowMilliseconds <= Int64.max - Self.lifetimeMilliseconds
            ? monotonicNowMilliseconds + Self.lifetimeMilliseconds
            : Int64.max
        tombstones[pairingID] = Tombstone(
            error: error,
            removeAfterMonotonicMilliseconds: removeAfter
        )
    }

    private func purgeTombstones(monotonicNowMilliseconds: Int64) {
        tombstones = tombstones.filter {
            monotonicNowMilliseconds < $0.value.removeAfterMonotonicMilliseconds
        }
    }

    private func validateTimes(
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: Int64
    ) throws {
        guard wallNowUnixMilliseconds >= 0,
              wallNowUnixMilliseconds <= 9_007_199_254_740_991,
              monotonicNowMilliseconds >= 0 else {
            throw PairingSessionError.invalidInput
        }
    }

    private static func randomBytes(count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in
            UInt8.random(in: UInt8.min...UInt8.max, using: &generator)
        })
    }
}
