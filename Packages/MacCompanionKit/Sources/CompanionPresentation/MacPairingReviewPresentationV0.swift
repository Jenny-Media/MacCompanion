import CompanionDomain
import CompanionIPC
import Foundation

public enum MacPairingReviewPresentationErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidPhase
    case reviewMismatch
    case invalidDraft(DeviceNameDraftIssue)
    case receiptMismatch
}

public enum MacPairingReviewPresentationPhaseV0:
    Equatable,
    Sendable
{
    case idle
    case reviewing
    case deciding(LocalPairingDecisionCommandV0)
    case decisionFailed(LocalPairingDecisionCommandV0)
}

/// Pure trusted-menu presentation for one Agent-issued pairing review. It
/// owns no peer trust, clock, pairing authority, or durable device state.
public struct MacPairingReviewPresentationV0: Equatable, Sendable {
    public private(set) var phase: MacPairingReviewPresentationPhaseV0 = .idle
    public private(set) var review: LocalPairingReviewV0?
    public private(set) var deviceNameDraft = ""

    public init() {}

    public var interactionEnabled: Bool {
        switch phase {
        case .reviewing, .decisionFailed:
            true
        case .idle, .deciding:
            false
        }
    }

    public mutating func receive(
        _ review: LocalPairingReviewV0
    ) throws {
        if self.review == review { return }
        guard case .idle = phase, self.review == nil else {
            throw MacPairingReviewPresentationErrorV0.reviewMismatch
        }
        self.review = review
        deviceNameDraft = ""
        phase = .reviewing
    }

    public mutating func updateDeviceNameDraft(_ value: String) throws {
        guard case .reviewing = phase else {
            throw MacPairingReviewPresentationErrorV0.invalidPhase
        }
        deviceNameDraft = value
    }

    public func deviceNameDraftIssue() -> DeviceNameDraftIssue? {
        do {
            _ = try DeviceDisplayName(deviceNameDraft)
            return nil
        } catch let error as DeviceDisplayNameError {
            return Self.map(error)
        } catch {
            return .unsupportedCharacters
        }
    }

    public mutating func approve(
        commandID: UUID,
        decidedAtUnixMilliseconds: Int64
    ) throws -> LocalPairingDecisionCommandV0 {
        guard case .reviewing = phase, let review else {
            throw MacPairingReviewPresentationErrorV0.invalidPhase
        }
        let name: DeviceDisplayName
        do {
            name = try DeviceDisplayName(deviceNameDraft)
        } catch let error as DeviceDisplayNameError {
            throw MacPairingReviewPresentationErrorV0.invalidDraft(
                Self.map(error)
            )
        } catch {
            throw MacPairingReviewPresentationErrorV0.invalidDraft(
                .unsupportedCharacters
            )
        }
        let command = try LocalPairingDecisionCommandV0(
            commandID: commandID,
            review: review,
            deviceDisplayName: name,
            decision: .approve,
            decidedAtUnixMilliseconds: decidedAtUnixMilliseconds
        )
        phase = .deciding(command)
        return command
    }

    public mutating func decline(
        commandID: UUID,
        decidedAtUnixMilliseconds: Int64
    ) throws -> LocalPairingDecisionCommandV0 {
        guard case .reviewing = phase, let review else {
            throw MacPairingReviewPresentationErrorV0.invalidPhase
        }
        let command = try LocalPairingDecisionCommandV0(
            commandID: commandID,
            review: review,
            deviceDisplayName: nil,
            decision: .decline,
            decidedAtUnixMilliseconds: decidedAtUnixMilliseconds
        )
        phase = .deciding(command)
        return command
    }

    public mutating func decisionFailed() throws {
        guard case let .deciding(command) = phase else {
            throw MacPairingReviewPresentationErrorV0.invalidPhase
        }
        phase = .decisionFailed(command)
    }

    public mutating func retryDecision() throws
        -> LocalPairingDecisionCommandV0
    {
        guard case let .decisionFailed(command) = phase else {
            throw MacPairingReviewPresentationErrorV0.invalidPhase
        }
        phase = .deciding(command)
        return command
    }

    public mutating func receiveDecisionReceipt(
        _ receipt: LocalPairingDecisionReceiptV0
    ) throws {
        guard case let .deciding(command) = phase else {
            throw MacPairingReviewPresentationErrorV0.invalidPhase
        }
        do {
            try receipt.validate(against: command)
        } catch {
            throw MacPairingReviewPresentationErrorV0.receiptMismatch
        }
        reset()
    }

    /// Returns true only when the exact current review was removed.
    @discardableResult
    public mutating func withdraw(reviewID: UUID) -> Bool {
        guard review?.reviewID == reviewID else { return false }
        reset()
        return true
    }

    public mutating func invalidate() {
        reset()
    }

    private mutating func reset() {
        phase = .idle
        review = nil
        deviceNameDraft = ""
    }

    private static func map(
        _ error: DeviceDisplayNameError
    ) -> DeviceNameDraftIssue {
        switch error {
        case .empty: .empty
        case .tooLong: .tooLong
        case .surroundingWhitespace: .surroundingWhitespace
        case .nonCanonicalUnicode: .nonCanonicalUnicode
        case .forbiddenScalar: .unsupportedCharacters
        }
    }
}
