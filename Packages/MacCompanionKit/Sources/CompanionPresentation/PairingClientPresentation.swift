import CompanionClient
import CompanionDiscovery
import CompanionDomain
import CompanionWire
import Foundation

public enum PairingFingerprintTrust: String, Codable, CaseIterable, Sendable {
    /// A claim carried by a scanned code. It is visible for identification but
    /// is not trusted until the live TLS peer proves possession of that key.
    case unverifiedScan
    case pinnedTLSVerified
}

public enum PairingSecurityProgress: String, Codable, CaseIterable, Sendable {
    case connecting
    case pinnedTLSVerified
    case verifyingTranscript
}

public enum PairingClientPresentationPhase: String, Codable, CaseIterable, Sendable {
    case scanning
    case preview
    case starting
    case securing
    case compareOnMac
    case recovering
    case saving
    case paired
    case failed
}

public enum PairingClientPresentationFailure: String, Codable, CaseIterable, Sendable {
    case invalidOrExpiredCode
    case connectionFailed
    case identityVerificationFailed
    case hostRejected
    case clientStorageUnavailable
    case unknown
}

public enum PairingClientPresentationError: Error, Equatable, Sendable {
    case invalidPhase
    case invalidOrExpiredQRCode
    case staleRequest
    case pairingMismatch
    case invalidVerifiedCompletion
    case persistenceMismatch
}

public struct PairingScanPreview: Equatable, Sendable {
    public let pairingID: UUID
    public let expiresAtUnixMilliseconds: Int64
    public let fingerprint: String
    public let fingerprintTrust: PairingFingerprintTrust
    public let routeKinds: [EndpointKind]
    public let routeCandidateCount: Int

    fileprivate init(
        qr: PairingQRCodePayload,
        fingerprintTrust: PairingFingerprintTrust
    ) {
        pairingID = qr.pairingID.rawValue
        expiresAtUnixMilliseconds = qr.expiresAtUnixMilliseconds
        fingerprint = Self.displayFingerprint(qr.hostFingerprint.rawValue)
        self.fingerprintTrust = fingerprintTrust
        routeKinds = qr.endpoints.map(\.kind)
        routeCandidateCount = qr.endpoints.count
    }

    fileprivate func withTrust(
        _ trust: PairingFingerprintTrust
    ) -> PairingScanPreview {
        PairingScanPreview(
            pairingID: pairingID,
            expiresAtUnixMilliseconds: expiresAtUnixMilliseconds,
            fingerprint: fingerprint,
            fingerprintTrust: trust,
            routeKinds: routeKinds,
            routeCandidateCount: routeCandidateCount
        )
    }

    private init(
        pairingID: UUID,
        expiresAtUnixMilliseconds: Int64,
        fingerprint: String,
        fingerprintTrust: PairingFingerprintTrust,
        routeKinds: [EndpointKind],
        routeCandidateCount: Int
    ) {
        self.pairingID = pairingID
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
        self.fingerprint = fingerprint
        self.fingerprintTrust = fingerprintTrust
        self.routeKinds = routeKinds
        self.routeCandidateCount = routeCandidateCount
    }

    private static func displayFingerprint(_ value: Data) -> String {
        value.enumerated().map { index, byte in
            let separator = index > 0 && index.isMultiple(of: 4) ? ":" : ""
            return separator + String(format: "%02x", byte)
        }.joined()
    }
}

/// Security-sensitive handoff to the client pairing authority. Callers pass
/// this value directly to that owner and never log or persist the QR payload.
public struct PairingStartIntent: Equatable, Sendable {
    public let requestID: UUID
    public let qr: PairingQRCodePayload
}

public struct PairingAuthenticationPresentation: Equatable, Sendable {
    public let pairingID: UUID
    public let authenticationString: String
    public let expiresAtUnixMilliseconds: Int64
}

/// Handoff to the client persistence owner. The private keys stay in Keychain;
/// this intent contains only the verified public paired-host record.
public struct PairedHostCommitIntent: Equatable, Sendable {
    public let pairingRequestID: UUID
    public let commitID: UUID
    public let host: ClientPairedHostV0
}

public struct PairedHostPresentation: Equatable, Sendable {
    public let hostID: UUID
    public let deviceID: UUID
    public let fingerprint: String
    public let access: DeviceAuthorizationState
}

/// Pure client UI reducer. It never publishes a transport-start intent until
/// explicit scan acceptance, never exposes the QR secret in presentation
/// state, and never claims pairing success before the verified host record has
/// been durably committed.
public struct PairingClientPresentation: Equatable, Sendable {
    public private(set) var phase: PairingClientPresentationPhase = .scanning
    public private(set) var preview: PairingScanPreview?
    public private(set) var securityProgress: PairingSecurityProgress?
    public private(set) var authentication: PairingAuthenticationPresentation?
    public private(set) var pairedHost: PairedHostPresentation?
    public private(set) var failure: PairingClientPresentationFailure?

    private var scannedQR: PairingQRCodePayload?
    private var requestID: UUID?
    private var verifiedApproval: ClientPairingApprovalV0?
    private var pendingCommitID: UUID?
    private var pendingHost: ClientPairedHostV0?

    public init() {}

    public mutating func receiveScan(
        _ text: String,
        nowUnixMilliseconds: Int64
    ) throws {
        guard phase == .scanning || phase == .failed else {
            throw PairingClientPresentationError.invalidPhase
        }
        clearAttempt()
        do {
            let qr = try PairingQRCodeCodec.decode(
                text,
                nowUnixMilliseconds: nowUnixMilliseconds
            )
            scannedQR = qr
            preview = PairingScanPreview(
                qr: qr,
                fingerprintTrust: .unverifiedScan
            )
            phase = .preview
        } catch {
            failure = .invalidOrExpiredCode
            phase = .failed
            throw PairingClientPresentationError.invalidOrExpiredQRCode
        }
    }

    public mutating func acceptPreview(
        requestID: UUID
    ) throws -> PairingStartIntent {
        guard phase == .preview, let qr = scannedQR,
              preview?.pairingID == qr.pairingID.rawValue else {
            throw PairingClientPresentationError.invalidPhase
        }
        self.requestID = requestID
        scannedQR = nil
        phase = .starting
        return PairingStartIntent(requestID: requestID, qr: qr)
    }

    public mutating func transportStarted(
        requestID: UUID,
        pairingID: UUID
    ) throws {
        try requireAttempt(
            phase: .starting,
            requestID: requestID,
            pairingID: pairingID
        )
        securityProgress = .connecting
        self.phase = .securing
    }

    public mutating func pinnedTLSAccepted(
        requestID: UUID,
        pairingID: UUID
    ) throws {
        try requireAttempt(
            phase: .securing,
            requestID: requestID,
            pairingID: pairingID
        )
        preview = preview?.withTrust(.pinnedTLSVerified)
        securityProgress = .pinnedTLSVerified
    }

    public mutating func transcriptVerificationStarted(
        requestID: UUID,
        pairingID: UUID
    ) throws {
        try requireAttempt(
            phase: .securing,
            requestID: requestID,
            pairingID: pairingID
        )
        guard securityProgress == .pinnedTLSVerified else {
            throw PairingClientPresentationError.invalidPhase
        }
        securityProgress = .verifyingTranscript
    }

    /// This accepts only the approval value published by the pairing authority
    /// after transcript, SAS, expiry, pin, and correlation verification.
    public mutating func receiveVerifiedApproval(
        requestID: UUID,
        approval: ClientPairingApprovalV0
    ) throws {
        try requireAttempt(
            phase: .securing,
            requestID: requestID,
            pairingID: approval.pairingID
        )
        guard securityProgress == .verifyingTranscript else {
            throw PairingClientPresentationError.invalidPhase
        }
        verifiedApproval = approval
        authentication = PairingAuthenticationPresentation(
            pairingID: approval.pairingID,
            authenticationString: approval.authenticationString,
            expiresAtUnixMilliseconds: approval.expiresAtUnixMilliseconds
        )
        securityProgress = nil
        phase = .compareOnMac
    }

    /// A completion is not shown as paired. It first becomes an atomic durable
    /// commit intent correlated to this exact accepted scan and verified SAS.
    public mutating func receiveVerifiedCompletion(
        requestID: UUID,
        host: ClientPairedHostV0,
        commitID: UUID
    ) throws -> PairedHostCommitIntent {
        guard phase == .compareOnMac || phase == .recovering else {
            throw PairingClientPresentationError.invalidPhase
        }
        guard self.requestID == requestID else {
            throw PairingClientPresentationError.staleRequest
        }
        guard preview?.pairingID == host.pairingID else {
            throw PairingClientPresentationError.pairingMismatch
        }
        guard verifiedApproval?.pairingID == host.pairingID,
              host.deviceState == .activeMonitorOnly,
              host.authorizationEpoch.rawValue == 1,
              host.grantRevision.rawValue == 1 else {
            throw PairingClientPresentationError.invalidVerifiedCompletion
        }
        pendingCommitID = commitID
        pendingHost = host
        authentication = nil
        phase = .saving
        return PairedHostCommitIntent(
            pairingRequestID: requestID,
            commitID: commitID,
            host: host
        )
    }

    public mutating func completionRecoveryStarted(
        requestID: UUID,
        pairingID: UUID
    ) throws {
        try requireAttempt(
            phase: .compareOnMac,
            requestID: requestID,
            pairingID: pairingID
        )
        phase = .recovering
    }

    public mutating func durableCommitSucceeded(
        commitID: UUID,
        storedHost: ClientPairedHostV0
    ) throws {
        guard phase == .saving, pendingCommitID == commitID,
              pendingHost == storedHost else {
            throw PairingClientPresentationError.persistenceMismatch
        }
        pairedHost = PairedHostPresentation(
            hostID: storedHost.hostID,
            deviceID: storedHost.deviceID,
            fingerprint: Self.displayFingerprint(storedHost.hostFingerprint),
            access: storedHost.deviceState
        )
        preview = nil
        requestID = nil
        verifiedApproval = nil
        pendingCommitID = nil
        pendingHost = nil
        phase = .paired
    }

    public mutating func fail(
        _ reason: PairingClientPresentationFailure
    ) throws {
        guard phase != .scanning, phase != .paired else {
            throw PairingClientPresentationError.invalidPhase
        }
        clearAttempt()
        failure = reason
        phase = .failed
    }

    public mutating func reset() {
        clearAttempt()
        phase = .scanning
    }

    private mutating func requireAttempt(
        phase expectedPhase: PairingClientPresentationPhase,
        requestID expectedRequestID: UUID,
        pairingID expectedPairingID: UUID
    ) throws {
        guard phase == expectedPhase else {
            throw PairingClientPresentationError.invalidPhase
        }
        guard requestID == expectedRequestID else {
            throw PairingClientPresentationError.staleRequest
        }
        guard preview?.pairingID == expectedPairingID else {
            throw PairingClientPresentationError.pairingMismatch
        }
    }

    private mutating func clearAttempt() {
        preview = nil
        securityProgress = nil
        authentication = nil
        pairedHost = nil
        failure = nil
        scannedQR = nil
        requestID = nil
        verifiedApproval = nil
        pendingCommitID = nil
        pendingHost = nil
    }

    private static func displayFingerprint(_ value: Data) -> String {
        value.enumerated().map { index, byte in
            let separator = index > 0 && index.isMultiple(of: 4) ? ":" : ""
            return separator + String(format: "%02x", byte)
        }.joined()
    }
}
