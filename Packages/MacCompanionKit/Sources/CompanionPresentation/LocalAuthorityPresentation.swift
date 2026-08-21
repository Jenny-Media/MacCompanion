import CompanionDomain
import CompanionIPC
import CompanionInteractiveWire
import CompanionWire
import Foundation

public struct LocalCapabilityEffectPresentation: Equatable, Sendable {
    public let dataAccess: CapabilityDataAccessEffect
    public let changesLocalState: CapabilityLocalStateEffect
    public let mayDisruptUser: Bool
    public let invokesExternalService: Bool
    public let usesCredentials: Bool
    public let destructive: Bool
    public let requiresForegroundSession: Bool
    public let allowedWhileLocked: Bool
    public let cancellation: CapabilityCancellationEffect

    public init(_ facts: CapabilityEffectFacts) {
        dataAccess = facts.dataAccess
        changesLocalState = facts.changesLocalState
        mayDisruptUser = facts.mayDisruptUser
        invokesExternalService = facts.invokesExternalService
        usesCredentials = facts.usesCredentials
        destructive = facts.destructive
        requiresForegroundSession = facts.requiresForegroundSession
        allowedWhileLocked = facts.allowedWhileLocked
        cancellation = facts.cancellation
    }
}

public struct LocalCapabilityGrantReviewItem: Equatable, Sendable {
    public let capabilityID: String
    public let englishTitle: String
    public let englishSummary: String
    public let effects: LocalCapabilityEffectPresentation

    fileprivate init(_ descriptor: CapabilityDescriptorV1) {
        capabilityID = descriptor.capabilityID
        englishTitle = descriptor.englishTitle
        englishSummary = descriptor.englishSummary
        effects = LocalCapabilityEffectPresentation(descriptor.effects)
    }
}

public enum LocalGrantReviewPhase: Equatable, Sendable {
    case reviewing
    case applying(decisionID: UUID)
    case applied
    case declined
    case failed
}

public enum LocalAuthorityPresentationError: Error, Equatable, Sendable {
    case invalidRequest
    case invalidPhase
    case staleDecision
    case receiptMismatch
}

public struct LocalGrantExpansionIntent: Equatable, Sendable {
    public let decisionID: UUID
    public let reviewID: UUID
    public let deviceID: UUID
    public let deviceDisplayName: DeviceDisplayName
    public let decision: LocalGrantDecisionV0
    public let expectedAuthorizationEpoch: AuthorizationEpoch
    public let expectedGrantRevision: GrantRevision
    public let expectedPolicyRevision: PolicyRevision
    public let requestedCapabilities: [LocalCapabilityGrantReviewItem]
    public let currentGrants: CapabilityGrantSet
    public let proposedGrants: CapabilityGrantSet

    public func makeIPCCommand(
        decidedAtUnixMilliseconds: Int64
    ) throws -> LocalGrantDecisionCommandV0 {
        try LocalGrantDecisionCommandV0(
            commandID: decisionID,
            reviewID: reviewID,
            deviceID: deviceID,
            deviceDisplayName: deviceDisplayName,
            decision: decision,
            expectedAuthorizationEpoch: expectedAuthorizationEpoch,
            expectedGrantRevision: expectedGrantRevision,
            expectedPolicyRevision: expectedPolicyRevision,
            expectedCurrentGrants: currentGrants,
            proposedGrants: proposedGrants,
            decidedAtUnixMilliseconds: decidedAtUnixMilliseconds
        )
    }
}

/// Local Mac administration presentation for adding named capabilities to one
/// locally named device. Provider text reaches this type only through already
/// validated local registry descriptors, and every declared effect field is
/// retained rather than collapsed into an ambiguous risk score.
public struct LocalGrantExpansionPresentation: Equatable, Sendable {
    public let reviewID: UUID
    public let deviceID: UUID
    public let deviceDisplayName: DeviceDisplayName
    public let expectedAuthorizationEpoch: AuthorizationEpoch
    public let expectedGrantRevision: GrantRevision
    public let expectedPolicyRevision: PolicyRevision
    public let currentGrants: CapabilityGrantSet
    public let requestedCapabilities: [LocalCapabilityGrantReviewItem]
    public let proposedGrants: CapabilityGrantSet
    public private(set) var phase: LocalGrantReviewPhase = .reviewing

    public init(
        reviewID: UUID,
        deviceID: UUID,
        deviceDisplayName: DeviceDisplayName,
        expectedAuthorizationEpoch: AuthorizationEpoch,
        expectedGrantRevision: GrantRevision,
        expectedPolicyRevision: PolicyRevision,
        currentGrants: CapabilityGrantSet,
        requestedDescriptors: [CapabilityDescriptorV1]
    ) throws {
        let requestedIDs = requestedDescriptors.map(\.capabilityID)
        guard expectedAuthorizationEpoch.rawValue >= 1,
              expectedGrantRevision.rawValue >= 1,
              expectedPolicyRevision.rawValue >= 1,
              !requestedIDs.isEmpty,
              requestedIDs.count <= CapabilityGrantSet.maximumCount,
              Set(requestedIDs).count == requestedIDs.count,
              Set(requestedIDs).isDisjoint(with: currentGrants.capabilityIDs) else {
            throw LocalAuthorityPresentationError.invalidRequest
        }
        let combined: CapabilityGrantSet
        do {
            combined = try CapabilityGrantSet(
                currentGrants.capabilityIDs + requestedIDs
            )
        } catch {
            throw LocalAuthorityPresentationError.invalidRequest
        }
        self.reviewID = reviewID
        self.deviceID = deviceID
        self.deviceDisplayName = deviceDisplayName
        self.expectedAuthorizationEpoch = expectedAuthorizationEpoch
        self.expectedGrantRevision = expectedGrantRevision
        self.expectedPolicyRevision = expectedPolicyRevision
        self.currentGrants = currentGrants
        requestedCapabilities = requestedDescriptors
            .sorted { $0.capabilityID < $1.capabilityID }
            .map(LocalCapabilityGrantReviewItem.init)
        proposedGrants = combined
    }

    public mutating func approve(
        decisionID: UUID
    ) throws -> LocalGrantExpansionIntent {
        guard phase == .reviewing || phase == .failed else {
            throw LocalAuthorityPresentationError.invalidPhase
        }
        phase = .applying(decisionID: decisionID)
        return LocalGrantExpansionIntent(
            decisionID: decisionID,
            reviewID: reviewID,
            deviceID: deviceID,
            deviceDisplayName: deviceDisplayName,
            decision: .approve,
            expectedAuthorizationEpoch: expectedAuthorizationEpoch,
            expectedGrantRevision: expectedGrantRevision,
            expectedPolicyRevision: expectedPolicyRevision,
            requestedCapabilities: requestedCapabilities,
            currentGrants: currentGrants,
            proposedGrants: proposedGrants
        )
    }

    public mutating func applicationSucceeded(
        decisionID: UUID,
        storedGrants: CapabilityGrantSet,
        authorizationEpoch: AuthorizationEpoch,
        grantRevision: GrantRevision
    ) throws {
        guard phase == .applying(decisionID: decisionID) else {
            throw LocalAuthorityPresentationError.staleDecision
        }
        guard let nextEpoch = try? expectedAuthorizationEpoch.advanced(),
              let nextGrant = try? expectedGrantRevision.advanced(),
              storedGrants == proposedGrants,
              authorizationEpoch == nextEpoch,
              grantRevision == nextGrant else {
            throw LocalAuthorityPresentationError.receiptMismatch
        }
        phase = .applied
    }

    public mutating func applicationSucceeded(
        receipt: LocalGrantDecisionReceiptV0,
        command: LocalGrantDecisionCommandV0
    ) throws {
        guard command.reviewID == reviewID,
              command.deviceID == deviceID,
              command.deviceDisplayName == deviceDisplayName,
              command.decision == .approve,
              command.expectedAuthorizationEpoch == expectedAuthorizationEpoch,
              command.expectedGrantRevision == expectedGrantRevision,
              command.expectedPolicyRevision == expectedPolicyRevision,
              command.expectedCurrentGrantIDs == currentGrants.capabilityIDs,
              command.proposedGrantIDs == proposedGrants.capabilityIDs else {
            throw LocalAuthorityPresentationError.staleDecision
        }
        do {
            try receipt.validate(against: command)
        } catch {
            throw LocalAuthorityPresentationError.receiptMismatch
        }
        try applicationSucceeded(
            decisionID: command.commandID,
            storedGrants: try receipt.storedGrantSet(),
            authorizationEpoch: receipt.authorizationEpoch,
            grantRevision: receipt.grantRevision
        )
    }

    public mutating func applicationFailed(decisionID: UUID) throws {
        guard phase == .applying(decisionID: decisionID) else {
            throw LocalAuthorityPresentationError.staleDecision
        }
        phase = .failed
    }

    public mutating func decline(
        decisionID: UUID
    ) throws -> LocalGrantExpansionIntent {
        guard phase == .reviewing || phase == .failed else {
            throw LocalAuthorityPresentationError.invalidPhase
        }
        phase = .declined
        return LocalGrantExpansionIntent(
            decisionID: decisionID,
            reviewID: reviewID,
            deviceID: deviceID,
            deviceDisplayName: deviceDisplayName,
            decision: .decline,
            expectedAuthorizationEpoch: expectedAuthorizationEpoch,
            expectedGrantRevision: expectedGrantRevision,
            expectedPolicyRevision: expectedPolicyRevision,
            requestedCapabilities: requestedCapabilities,
            currentGrants: currentGrants,
            proposedGrants: proposedGrants
        )
    }
}

public enum LocalInteractiveWarningEffect: String, Codable, CaseIterable, Sendable {
    case viewMacScreen
    case movePointer
    case pressKeyboardKeys
    case insertText

    fileprivate init(_ effect: InteractiveControlEffect) {
        self = switch effect {
        case .view: .viewMacScreen
        case .pointer: .movePointer
        case .keyboard: .pressKeyboardKeys
        case .text: .insertText
        }
    }
}

public enum LocalInteractiveWarningPhase: String, Codable, CaseIterable, Sendable {
    case awaitingPhoneApproval
    case starting
    case active
    case paused
    case ending
    case ended
}

public struct LocalInteractiveStopIntent: Equatable, Sendable {
    public let actionID: UUID
    public let deviceID: UUID
    public let deviceDisplayName: DeviceDisplayName
    public let requestID: UUID
    public let approvalID: UUID
    public let interactiveSessionID: UUID?

    public func makeIPCCommand(
        reason: LocalInteractiveStopReasonV0 = .userRequested,
        occurredAtUnixMilliseconds: Int64
    ) throws -> LocalInteractiveStopCommandV0 {
        try LocalInteractiveStopCommandV0(
            commandID: actionID,
            deviceID: deviceID,
            deviceDisplayName: deviceDisplayName,
            requestID: requestID,
            approvalID: approvalID,
            interactiveSessionID: interactiveSessionID,
            reason: reason,
            occurredAtUnixMilliseconds: occurredAtUnixMilliseconds
        )
    }
}

/// Visible Mac warning for one session request. It presents exact effects and
/// a local stop path; it does not create or expand a durable grant and it does
/// not substitute for the phone's fresh-presence approval signature.
public struct LocalInteractiveWarningPresentation: Equatable, Sendable {
    public let deviceID: UUID
    public let deviceDisplayName: DeviceDisplayName
    public let requestID: UUID
    public let approvalID: UUID
    public let selectedDisplayID: UUID
    public let effects: [LocalInteractiveWarningEffect]
    public let expiresAtUnixMilliseconds: Int64
    public private(set) var phase: LocalInteractiveWarningPhase
    public private(set) var interactiveSessionID: UUID?
    private var pendingStopActionID: UUID?

    public init(
        deviceID: UUID,
        deviceDisplayName: DeviceDisplayName,
        requestID: UUID,
        approvalID: UUID,
        selectedDisplayID: UUID,
        effects: [InteractiveControlEffect],
        issuedAtUnixMilliseconds: Int64,
        expiresAtUnixMilliseconds: Int64
    ) throws {
        guard effects == effects.sorted(),
              Set(effects).count == effects.count,
              effects.contains(.view),
              !effects.contains(.text) || effects.contains(.keyboard),
              issuedAtUnixMilliseconds >= 0,
              expiresAtUnixMilliseconds > issuedAtUnixMilliseconds,
              expiresAtUnixMilliseconds - issuedAtUnixMilliseconds <= 60_000 else {
            throw LocalAuthorityPresentationError.invalidRequest
        }
        self.deviceID = deviceID
        self.deviceDisplayName = deviceDisplayName
        self.requestID = requestID
        self.approvalID = approvalID
        self.selectedDisplayID = selectedDisplayID
        self.effects = effects.map(LocalInteractiveWarningEffect.init)
        self.expiresAtUnixMilliseconds = expiresAtUnixMilliseconds
        phase = .awaitingPhoneApproval
        interactiveSessionID = nil
        pendingStopActionID = nil
    }

    public mutating func sessionAccepted(_ sessionID: UUID) throws {
        guard phase == .awaitingPhoneApproval else {
            throw LocalAuthorityPresentationError.invalidPhase
        }
        interactiveSessionID = sessionID
        phase = .starting
    }

    public mutating func captureBecameActive() throws {
        guard phase == .starting, interactiveSessionID != nil else {
            throw LocalAuthorityPresentationError.invalidPhase
        }
        phase = .active
    }

    public mutating func setPaused(_ paused: Bool) throws {
        switch (phase, paused) {
        case (.active, true): phase = .paused
        case (.paused, false): phase = .active
        default: throw LocalAuthorityPresentationError.invalidPhase
        }
    }

    public mutating func requestStop(
        actionID: UUID
    ) throws -> LocalInteractiveStopIntent {
        guard phase != .ending, phase != .ended else {
            throw LocalAuthorityPresentationError.invalidPhase
        }
        pendingStopActionID = actionID
        phase = .ending
        return LocalInteractiveStopIntent(
            actionID: actionID,
            deviceID: deviceID,
            deviceDisplayName: deviceDisplayName,
            requestID: requestID,
            approvalID: approvalID,
            interactiveSessionID: interactiveSessionID
        )
    }

    public mutating func stopCompleted(actionID: UUID) throws {
        guard phase == .ending, pendingStopActionID == actionID else {
            throw LocalAuthorityPresentationError.staleDecision
        }
        pendingStopActionID = nil
        phase = .ended
    }

    public mutating func stopCompleted(
        receipt: LocalInteractiveStoppedReceiptV0,
        command: LocalInteractiveStopCommandV0
    ) throws {
        guard command.deviceID == deviceID,
              command.deviceDisplayName == deviceDisplayName,
              command.requestID == requestID,
              command.approvalID == approvalID,
              command.interactiveSessionID == interactiveSessionID else {
            throw LocalAuthorityPresentationError.staleDecision
        }
        do {
            try receipt.validate(against: command)
        } catch {
            throw LocalAuthorityPresentationError.staleDecision
        }
        try stopCompleted(actionID: command.commandID)
    }
}
