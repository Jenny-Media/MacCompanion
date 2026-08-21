import CompanionIPC
import Foundation

public enum MacHostIdentityRecoveryConsequenceV0:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case stopRemoteAccess
    case invalidateAllPairedPhones
    case removeAllCapabilityGrants
    case fenceQueuedAndActiveRemoteWork
    case requireRepairingEveryPhone
}

public enum MacHostIdentityRecoveryPresentationErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidPhase
    case reviewMismatch
    case receiptMismatch
}

public enum MacHostIdentityRecoveryPresentationPhaseV0:
    Equatable,
    Sendable
{
    case idle
    case reviewing(LocalHostIdentityRecoveryReviewV0)
    case recovering(LocalHostIdentityRecoveryCommandV0)
    case recoveryFailed(LocalHostIdentityRecoveryCommandV0)
    case authorizationLost(LocalHostIdentityRecoveryCommandV0)
    case completed(
        LocalHostIdentityRecoveryCommandV0,
        LocalHostIdentityRecoveredReceiptV0
    )
}

/// Pure destructive-confirmation reducer. It can emit only the closed recovery
/// command and cannot authenticate IPC, inspect durable state, choose identity
/// material, or perform Keychain work.
public struct MacHostIdentityRecoveryPresentationV0: Equatable, Sendable {
    public static let requiredConsequences =
        MacHostIdentityRecoveryConsequenceV0.allCases

    public private(set) var phase: MacHostIdentityRecoveryPresentationPhaseV0

    public init() {
        phase = .idle
    }

    public var interactionEnabled: Bool {
        switch phase {
        case .reviewing, .recoveryFailed, .completed:
            true
        case .idle, .recovering, .authorizationLost:
            false
        }
    }

    public var exactRetryCommand: LocalHostIdentityRecoveryCommandV0? {
        switch phase {
        case let .recoveryFailed(command),
             let .authorizationLost(command):
            command
        case .idle, .reviewing, .recovering, .completed:
            nil
        }
    }

    public var currentReviewID: UUID? {
        switch phase {
        case let .reviewing(review):
            review.reviewID
        case let .recovering(command), let .recoveryFailed(command),
             let .authorizationLost(command), let .completed(command, _):
            command.review.reviewID
        case .idle:
            nil
        }
    }

    public mutating func present(
        _ review: LocalHostIdentityRecoveryReviewV0
    ) throws {
        switch phase {
        case .idle:
            phase = .reviewing(review)
        case let .reviewing(existing):
            guard existing == review else {
                throw MacHostIdentityRecoveryPresentationErrorV0.reviewMismatch
            }
        case let .authorizationLost(command):
            guard command.review == review else {
                throw MacHostIdentityRecoveryPresentationErrorV0.reviewMismatch
            }
            phase = .recoveryFailed(command)
        case let .recovering(command), let .recoveryFailed(command):
            guard command.review == review else {
                throw MacHostIdentityRecoveryPresentationErrorV0.reviewMismatch
            }
        case .completed:
            throw MacHostIdentityRecoveryPresentationErrorV0.invalidPhase
        }
    }

    public mutating func confirm(
        commandID: UUID,
        recoveryID: UUID,
        confirmedAtUnixMilliseconds: Int64
    ) throws -> LocalHostIdentityRecoveryCommandV0 {
        guard case let .reviewing(review) = phase else {
            throw MacHostIdentityRecoveryPresentationErrorV0.invalidPhase
        }
        let command = try LocalHostIdentityRecoveryCommandV0(
            commandID: commandID,
            recoveryID: recoveryID,
            review: review,
            confirmedAtUnixMilliseconds: confirmedAtUnixMilliseconds
        )
        phase = .recovering(command)
        return command
    }

    /// Adopts only an Agent-supplied command whose reviewed intent is already
    /// durable. This is distinct from ordinary review presentation and never
    /// creates or edits a command locally.
    public mutating func resume(
        _ command: LocalHostIdentityRecoveryCommandV0
    ) throws {
        switch phase {
        case .idle:
            phase = .recoveryFailed(command)
        case let .reviewing(review):
            guard review == command.review else {
                throw MacHostIdentityRecoveryPresentationErrorV0.reviewMismatch
            }
            phase = .recoveryFailed(command)
        case let .authorizationLost(existing),
             let .recoveryFailed(existing),
             let .recovering(existing):
            guard existing == command else {
                throw MacHostIdentityRecoveryPresentationErrorV0.reviewMismatch
            }
            if case .authorizationLost = phase {
                phase = .recoveryFailed(command)
            }
        case .completed:
            throw MacHostIdentityRecoveryPresentationErrorV0.invalidPhase
        }
    }

    public mutating func submissionFailed() throws {
        guard case let .recovering(command) = phase else {
            throw MacHostIdentityRecoveryPresentationErrorV0.invalidPhase
        }
        phase = .recoveryFailed(command)
    }

    public mutating func retry() throws
        -> LocalHostIdentityRecoveryCommandV0
    {
        guard case let .recoveryFailed(command) = phase else {
            throw MacHostIdentityRecoveryPresentationErrorV0.invalidPhase
        }
        phase = .recovering(command)
        return command
    }

    public mutating func receive(
        _ receipt: LocalHostIdentityRecoveredReceiptV0
    ) throws {
        guard case let .recovering(command) = phase else {
            throw MacHostIdentityRecoveryPresentationErrorV0.invalidPhase
        }
        do {
            try receipt.validate(against: command)
        } catch {
            throw MacHostIdentityRecoveryPresentationErrorV0.receiptMismatch
        }
        phase = .completed(command, receipt)
    }

    /// An unsubmitted review is discarded. A submitted command remains exact
    /// but cannot be retried until the authenticated Agent republishes the same
    /// review in-process or the exact durable command after a process restart.
    public mutating func agentInvalidated() {
        switch phase {
        case .idle:
            break
        case .reviewing:
            phase = .idle
        case let .recovering(command), let .recoveryFailed(command):
            phase = .authorizationLost(command)
        case .authorizationLost, .completed:
            break
        }
    }
}
