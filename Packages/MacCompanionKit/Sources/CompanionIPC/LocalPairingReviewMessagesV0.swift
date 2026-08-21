import CompanionDomain
import CompanionWire
import Foundation

public enum LocalPairingDecisionV0:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case approve
    case decline
}

private struct LocalPairingReviewAnyCodingKeyV0: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private func requireLocalPairingReviewKeysV0(
    _ decoder: Decoder,
    _ expected: Set<String>
) throws {
    let container = try decoder.container(
        keyedBy: LocalPairingReviewAnyCodingKeyV0.self
    )
    guard Set(container.allKeys.map(\.stringValue)) == expected else {
        throw LocalPairingSessionMessageErrorV0.unknownOrMissingField
    }
}

private let localPairingReviewMaximumTimeV0: Int64 =
    9_007_199_254_740_991

public struct LocalPairingReviewV0: Codable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, reviewID, pairingID, clientID
        case sessionPublicKeyFingerprint, approvalPublicKeyFingerprint
        case transcriptDigest, authenticationString
        case expectedPolicyRevision, expiresAtUnixMilliseconds
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let reviewID: UUID
    public let pairingID: UUID
    public let clientID: UUID
    public let sessionPublicKeyFingerprint: WireFingerprint
    public let approvalPublicKeyFingerprint: WireFingerprint
    public let transcriptDigest: WireBytes32
    public let authenticationString: PairingAuthenticationString
    public let expectedPolicyRevision: PolicyRevision
    public let expiresAtUnixMilliseconds: Int64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        reviewID: UUID,
        pairingID: UUID,
        clientID: UUID,
        sessionPublicKeyFingerprint: WireFingerprint,
        approvalPublicKeyFingerprint: WireFingerprint,
        transcriptDigest: WireBytes32,
        authenticationString: PairingAuthenticationString,
        expectedPolicyRevision: PolicyRevision,
        expiresAtUnixMilliseconds: Int64
    ) throws {
        guard protocolVersion == .init() else {
            throw LocalPairingSessionMessageErrorV0.invalidVersion
        }
        guard expectedPolicyRevision.rawValue >= 1 else {
            throw LocalPairingSessionMessageErrorV0.bindingMismatch
        }
        guard (1...localPairingReviewMaximumTimeV0).contains(
            expiresAtUnixMilliseconds
        ) else {
            throw LocalPairingSessionMessageErrorV0.invalidTime
        }
        self.protocolVersion = protocolVersion
        self.reviewID = reviewID
        self.pairingID = pairingID
        self.clientID = clientID
        self.sessionPublicKeyFingerprint = sessionPublicKeyFingerprint
        self.approvalPublicKeyFingerprint = approvalPublicKeyFingerprint
        self.transcriptDigest = transcriptDigest
        self.authenticationString = authenticationString
        self.expectedPolicyRevision = expectedPolicyRevision
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        try requireLocalPairingReviewKeysV0(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            protocolVersion: container.decode(
                LocalIPCProtocolVersion.self,
                forKey: .protocolVersion
            ),
            reviewID: container.decode(UUID.self, forKey: .reviewID),
            pairingID: container.decode(UUID.self, forKey: .pairingID),
            clientID: container.decode(UUID.self, forKey: .clientID),
            sessionPublicKeyFingerprint: container.decode(
                WireFingerprint.self,
                forKey: .sessionPublicKeyFingerprint
            ),
            approvalPublicKeyFingerprint: container.decode(
                WireFingerprint.self,
                forKey: .approvalPublicKeyFingerprint
            ),
            transcriptDigest: container.decode(
                WireBytes32.self,
                forKey: .transcriptDigest
            ),
            authenticationString: container.decode(
                PairingAuthenticationString.self,
                forKey: .authenticationString
            ),
            expectedPolicyRevision: container.decode(
                PolicyRevision.self,
                forKey: .expectedPolicyRevision
            ),
            expiresAtUnixMilliseconds: container.decode(
                Int64.self,
                forKey: .expiresAtUnixMilliseconds
            )
        )
    }
}

public struct LocalPairingDecisionCommandV0:
    Codable,
    Equatable,
    Sendable
{
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, commandID, reviewID, pairingID, clientID
        case sessionPublicKeyFingerprint, approvalPublicKeyFingerprint
        case transcriptDigest, authenticationString
        case expectedPolicyRevision, expiresAtUnixMilliseconds
        case deviceDisplayName, decision
        case decidedAtUnixMilliseconds
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let commandID: UUID
    public let reviewID: UUID
    public let pairingID: UUID
    public let clientID: UUID
    public let sessionPublicKeyFingerprint: WireFingerprint
    public let approvalPublicKeyFingerprint: WireFingerprint
    public let transcriptDigest: WireBytes32
    public let authenticationString: PairingAuthenticationString
    public let expectedPolicyRevision: PolicyRevision
    public let expiresAtUnixMilliseconds: Int64
    public let deviceDisplayName: DeviceDisplayName?
    public let decision: LocalPairingDecisionV0
    public let decidedAtUnixMilliseconds: Int64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        commandID: UUID,
        review: LocalPairingReviewV0,
        deviceDisplayName: DeviceDisplayName?,
        decision: LocalPairingDecisionV0,
        decidedAtUnixMilliseconds: Int64
    ) throws {
        guard protocolVersion == .init(),
              review.protocolVersion == protocolVersion else {
            throw LocalPairingSessionMessageErrorV0.invalidVersion
        }
        guard (0...localPairingReviewMaximumTimeV0).contains(
            decidedAtUnixMilliseconds
        ) else {
            throw LocalPairingSessionMessageErrorV0.invalidTime
        }
        switch decision {
        case .approve:
            guard deviceDisplayName != nil else {
                throw LocalPairingSessionMessageErrorV0.bindingMismatch
            }
        case .decline:
            guard deviceDisplayName == nil else {
                throw LocalPairingSessionMessageErrorV0.bindingMismatch
            }
        }
        self.protocolVersion = protocolVersion
        self.commandID = commandID
        reviewID = review.reviewID
        pairingID = review.pairingID
        clientID = review.clientID
        sessionPublicKeyFingerprint = review.sessionPublicKeyFingerprint
        approvalPublicKeyFingerprint = review.approvalPublicKeyFingerprint
        transcriptDigest = review.transcriptDigest
        authenticationString = review.authenticationString
        expectedPolicyRevision = review.expectedPolicyRevision
        expiresAtUnixMilliseconds = review.expiresAtUnixMilliseconds
        self.deviceDisplayName = deviceDisplayName
        self.decision = decision
        self.decidedAtUnixMilliseconds = decidedAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        try requireLocalPairingReviewKeysV0(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let review = try LocalPairingReviewV0(
            protocolVersion: container.decode(
                LocalIPCProtocolVersion.self,
                forKey: .protocolVersion
            ),
            reviewID: container.decode(UUID.self, forKey: .reviewID),
            pairingID: container.decode(UUID.self, forKey: .pairingID),
            clientID: container.decode(UUID.self, forKey: .clientID),
            sessionPublicKeyFingerprint: container.decode(
                WireFingerprint.self,
                forKey: .sessionPublicKeyFingerprint
            ),
            approvalPublicKeyFingerprint: container.decode(
                WireFingerprint.self,
                forKey: .approvalPublicKeyFingerprint
            ),
            transcriptDigest: container.decode(
                WireBytes32.self,
                forKey: .transcriptDigest
            ),
            authenticationString: container.decode(
                PairingAuthenticationString.self,
                forKey: .authenticationString
            ),
            expectedPolicyRevision: container.decode(
                PolicyRevision.self,
                forKey: .expectedPolicyRevision
            ),
            expiresAtUnixMilliseconds: container.decode(
                Int64.self,
                forKey: .expiresAtUnixMilliseconds
            )
        )
        try self.init(
            protocolVersion: review.protocolVersion,
            commandID: container.decode(UUID.self, forKey: .commandID),
            review: review,
            deviceDisplayName: container.decodeIfPresent(
                DeviceDisplayName.self,
                forKey: .deviceDisplayName
            ),
            decision: container.decode(
                LocalPairingDecisionV0.self,
                forKey: .decision
            ),
            decidedAtUnixMilliseconds: container.decode(
                Int64.self,
                forKey: .decidedAtUnixMilliseconds
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encode(commandID, forKey: .commandID)
        try container.encode(reviewID, forKey: .reviewID)
        try container.encode(pairingID, forKey: .pairingID)
        try container.encode(clientID, forKey: .clientID)
        try container.encode(
            sessionPublicKeyFingerprint,
            forKey: .sessionPublicKeyFingerprint
        )
        try container.encode(
            approvalPublicKeyFingerprint,
            forKey: .approvalPublicKeyFingerprint
        )
        try container.encode(transcriptDigest, forKey: .transcriptDigest)
        try container.encode(
            authenticationString,
            forKey: .authenticationString
        )
        try container.encode(
            expectedPolicyRevision,
            forKey: .expectedPolicyRevision
        )
        try container.encode(
            expiresAtUnixMilliseconds,
            forKey: .expiresAtUnixMilliseconds
        )
        try container.encode(deviceDisplayName, forKey: .deviceDisplayName)
        try container.encode(decision, forKey: .decision)
        try container.encode(
            decidedAtUnixMilliseconds,
            forKey: .decidedAtUnixMilliseconds
        )
    }

    public func matches(_ review: LocalPairingReviewV0) -> Bool {
        protocolVersion == review.protocolVersion
            && reviewID == review.reviewID
            && pairingID == review.pairingID
            && clientID == review.clientID
            && sessionPublicKeyFingerprint
                == review.sessionPublicKeyFingerprint
            && approvalPublicKeyFingerprint
                == review.approvalPublicKeyFingerprint
            && transcriptDigest == review.transcriptDigest
            && authenticationString == review.authenticationString
            && expectedPolicyRevision == review.expectedPolicyRevision
            && expiresAtUnixMilliseconds
                == review.expiresAtUnixMilliseconds
    }
}

public struct LocalPairingDecisionReceiptV0:
    Codable,
    Equatable,
    Sendable
{
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case protocolVersion, correlationID, reviewID, pairingID, clientID
        case decision, deviceID, storedDisplayName
        case completedAtUnixMilliseconds
    }

    public let protocolVersion: LocalIPCProtocolVersion
    public let correlationID: UUID
    public let reviewID: UUID
    public let pairingID: UUID
    public let clientID: UUID
    public let decision: LocalPairingDecisionV0
    public let deviceID: UUID?
    public let storedDisplayName: DeviceDisplayName?
    public let completedAtUnixMilliseconds: Int64

    public init(
        protocolVersion: LocalIPCProtocolVersion = .init(),
        correlationID: UUID,
        reviewID: UUID,
        pairingID: UUID,
        clientID: UUID,
        decision: LocalPairingDecisionV0,
        deviceID: UUID?,
        storedDisplayName: DeviceDisplayName?,
        completedAtUnixMilliseconds: Int64
    ) throws {
        guard protocolVersion == .init() else {
            throw LocalPairingSessionMessageErrorV0.invalidVersion
        }
        guard (0...localPairingReviewMaximumTimeV0).contains(
            completedAtUnixMilliseconds
        ) else {
            throw LocalPairingSessionMessageErrorV0.invalidTime
        }
        switch decision {
        case .approve:
            guard deviceID != nil, storedDisplayName != nil else {
                throw LocalPairingSessionMessageErrorV0.bindingMismatch
            }
        case .decline:
            guard deviceID == nil, storedDisplayName == nil else {
                throw LocalPairingSessionMessageErrorV0.bindingMismatch
            }
        }
        self.protocolVersion = protocolVersion
        self.correlationID = correlationID
        self.reviewID = reviewID
        self.pairingID = pairingID
        self.clientID = clientID
        self.decision = decision
        self.deviceID = deviceID
        self.storedDisplayName = storedDisplayName
        self.completedAtUnixMilliseconds = completedAtUnixMilliseconds
    }

    public init(from decoder: Decoder) throws {
        try requireLocalPairingReviewKeysV0(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue))
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            protocolVersion: container.decode(
                LocalIPCProtocolVersion.self,
                forKey: .protocolVersion
            ),
            correlationID: container.decode(UUID.self, forKey: .correlationID),
            reviewID: container.decode(UUID.self, forKey: .reviewID),
            pairingID: container.decode(UUID.self, forKey: .pairingID),
            clientID: container.decode(UUID.self, forKey: .clientID),
            decision: container.decode(
                LocalPairingDecisionV0.self,
                forKey: .decision
            ),
            deviceID: container.decodeIfPresent(UUID.self, forKey: .deviceID),
            storedDisplayName: container.decodeIfPresent(
                DeviceDisplayName.self,
                forKey: .storedDisplayName
            ),
            completedAtUnixMilliseconds: container.decode(
                Int64.self,
                forKey: .completedAtUnixMilliseconds
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolVersion, forKey: .protocolVersion)
        try container.encode(correlationID, forKey: .correlationID)
        try container.encode(reviewID, forKey: .reviewID)
        try container.encode(pairingID, forKey: .pairingID)
        try container.encode(clientID, forKey: .clientID)
        try container.encode(decision, forKey: .decision)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(storedDisplayName, forKey: .storedDisplayName)
        try container.encode(
            completedAtUnixMilliseconds,
            forKey: .completedAtUnixMilliseconds
        )
    }

    public func validate(
        against command: LocalPairingDecisionCommandV0
    ) throws {
        guard protocolVersion == command.protocolVersion,
              correlationID == command.commandID,
              reviewID == command.reviewID,
              pairingID == command.pairingID,
              clientID == command.clientID,
              decision == command.decision,
              completedAtUnixMilliseconds
                >= command.decidedAtUnixMilliseconds else {
            throw LocalPairingSessionMessageErrorV0.bindingMismatch
        }
        if decision == .approve,
           storedDisplayName != command.deviceDisplayName {
            throw LocalPairingSessionMessageErrorV0.bindingMismatch
        }
    }
}
