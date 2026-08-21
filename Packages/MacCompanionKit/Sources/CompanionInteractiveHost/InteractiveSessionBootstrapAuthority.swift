import CompanionDomain
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionSecurity
import CompanionWire
import Foundation

public enum InteractiveSessionBootstrapError: Error, Equatable, Sendable {
    case alreadyCreated
    case invalidTime
}

public struct InteractiveSessionBootstrapMaterials: Equatable, Sendable {
    public let interactiveSessionID: UUID
    public let inputChannelID: UUID
    public let inputCredential: Data
    public let mediaChannelID: UUID
    public let mediaCredential: Data

    public init(
        interactiveSessionID: UUID,
        inputChannelID: UUID,
        inputCredential: Data,
        mediaChannelID: UUID,
        mediaCredential: Data
    ) {
        self.interactiveSessionID = interactiveSessionID
        self.inputChannelID = inputChannelID
        self.inputCredential = inputCredential
        self.mediaChannelID = mediaChannelID
        self.mediaCredential = mediaCredential
    }
}

public struct InteractiveSessionBootstrap: Equatable, Sendable {
    public var session: InteractiveSessionStateMachine
    public var inputChannelAuthority: InteractiveChannelCredentialAuthority
    public var mediaChannelAuthority: InteractiveChannelCredentialAuthority
    /// Exact effect authority consumed from the verified approval signature.
    /// Runtime lease construction must not recover this from request JSON.
    public let approvedEffects: InteractiveApprovalEffects
    public let acceptedBody: InteractiveSessionAcceptedBody
    public let effects: [InteractiveSessionEffect]

    /// Closed lease-class projection of the already verified approval. The
    /// security construction rejects unknown effects and text without
    /// keyboard before this bootstrap can exist.
    public var approvedInteractionClasses: Set<SurfaceInteractionClass> {
        var classes: Set<SurfaceInteractionClass> = []
        if approvedEffects.contains(.view) { classes.insert(.view) }
        if approvedEffects.contains(.pointer) { classes.insert(.pointer) }
        if approvedEffects.contains(.keyboard) { classes.insert(.keyboard) }
        if approvedEffects.contains(.text) { classes.insert(.text) }
        return classes
    }
}

/// Owns the single non-suspending transition from an approval proof to a
/// starting session and two role-bound, single-use channel authorities.
public struct InteractiveSessionBootstrapAuthority: Equatable, Sendable {
    public private(set) var approvalAuthority: InteractiveApprovalAuthority
    public private(set) var didCreateSession = false

    public init(approvalAuthority: InteractiveApprovalAuthority) {
        self.approvalAuthority = approvalAuthority
    }

    public mutating func verifyAndCreate(
        rawApprovalSignature: Data,
        current: InteractiveApprovalCurrentState,
        materials: InteractiveSessionBootstrapMaterials,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: UInt64
    ) throws -> InteractiveSessionBootstrap {
        guard !didCreateSession else {
            throw InteractiveSessionBootstrapError.alreadyCreated
        }
        guard wallNowUnixMilliseconds >= 0,
              wallNowUnixMilliseconds <= WireLimits.maximumSafeInteger
                - InteractiveSessionStateMachine.maximumDurationMilliseconds,
              monotonicNowMilliseconds <= UInt64(Int64.max)
                - UInt64(InteractiveSessionStateMachine.maximumDurationMilliseconds) else {
            throw InteractiveSessionBootstrapError.invalidTime
        }

        var stagedApproval = approvalAuthority
        let intent: InteractiveApprovedSessionIntent
        do {
            intent = try stagedApproval.verifyAndConsume(
                rawSignature: rawApprovalSignature,
                current: current,
                monotonicNowMilliseconds: monotonicNowMilliseconds
            )
        } catch {
            // A proof or live-state failure is terminal in the approval
            // authority even though it creates no session.
            approvalAuthority = stagedApproval
            throw error
        }

        let epoch = AuthorizationEpoch(rawValue: intent.authorizationEpoch)
        var stagedSession = InteractiveSessionStateMachine()
        _ = try stagedSession.apply(.request(
            sessionID: materials.interactiveSessionID,
            authorizationEpoch: epoch,
            approvalDeadlineMonotonicMilliseconds: Int64(
                intent.approvalDeadlineMonotonicMilliseconds
            )
        ))
        let effects = try stagedSession.apply(.approvalConsumed(
            monotonicNowMilliseconds: Int64(monotonicNowMilliseconds)
        ))

        let channelExpiresAtMonotonicMilliseconds = monotonicNowMilliseconds + 30_000
        let inputAuthority = try InteractiveChannelCredentialAuthority(
            channelID: materials.inputChannelID,
            role: .input,
            credential: materials.inputCredential,
            hostID: intent.hostID,
            hostFingerprint: intent.hostFingerprint,
            clientID: intent.clientID,
            primaryConnectionID: intent.primaryConnectionID,
            interactiveSessionID: materials.interactiveSessionID,
            authorizationEpoch: intent.authorizationEpoch,
            selectedMajor: intent.selectedMajor,
            selectedMinor: intent.selectedMinor,
            issuedAtMonotonicMilliseconds: monotonicNowMilliseconds,
            expiresAtMonotonicMilliseconds: channelExpiresAtMonotonicMilliseconds
        )
        let mediaAuthority = try InteractiveChannelCredentialAuthority(
            channelID: materials.mediaChannelID,
            role: .media,
            credential: materials.mediaCredential,
            hostID: intent.hostID,
            hostFingerprint: intent.hostFingerprint,
            clientID: intent.clientID,
            primaryConnectionID: intent.primaryConnectionID,
            interactiveSessionID: materials.interactiveSessionID,
            authorizationEpoch: intent.authorizationEpoch,
            selectedMajor: intent.selectedMajor,
            selectedMinor: intent.selectedMinor,
            issuedAtMonotonicMilliseconds: monotonicNowMilliseconds,
            expiresAtMonotonicMilliseconds: channelExpiresAtMonotonicMilliseconds
        )

        let channelExpiresAtUnixMilliseconds = wallNowUnixMilliseconds + 30_000
        let inputOffer = try InteractiveChannelOffer(
            channelID: WireUUID(materials.inputChannelID),
            role: .input,
            credential: WireBytes32(materials.inputCredential),
            issuedAtUnixMilliseconds: wallNowUnixMilliseconds,
            expiresAtUnixMilliseconds: channelExpiresAtUnixMilliseconds
        )
        let mediaOffer = try InteractiveChannelOffer(
            channelID: WireUUID(materials.mediaChannelID),
            role: .media,
            credential: WireBytes32(materials.mediaCredential),
            issuedAtUnixMilliseconds: wallNowUnixMilliseconds,
            expiresAtUnixMilliseconds: channelExpiresAtUnixMilliseconds
        )
        let acceptedBody = try InteractiveSessionAcceptedBody(
            interactiveSessionID: WireUUID(materials.interactiveSessionID),
            authorizationEpoch: epoch,
            expiresAtUnixMilliseconds: wallNowUnixMilliseconds
                + InteractiveSessionStateMachine.maximumDurationMilliseconds,
            inputChannel: inputOffer,
            mediaChannel: mediaOffer
        )

        // Nothing above mutates externally visible bootstrap state. Commit all
        // authorities only after the complete accepted response is valid.
        approvalAuthority = stagedApproval
        didCreateSession = true
        return InteractiveSessionBootstrap(
            session: stagedSession,
            inputChannelAuthority: inputAuthority,
            mediaChannelAuthority: mediaAuthority,
            approvedEffects: intent.effects,
            acceptedBody: acceptedBody,
            effects: effects
        )
    }
}
