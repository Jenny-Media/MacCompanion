import CompanionDomain
import Foundation

public enum InteractiveSessionState: String, Codable, CaseIterable, Sendable {
    case idle
    case approvalRequired
    case starting
    case activeUnlocked
    case activeLocked
    case lockedInteractionUnavailable
    case suspended
    case ending
    case ended
}

public enum InteractiveSessionEndReason: String, Codable, CaseIterable, Sendable {
    case approvalExpired
    case clientRequested
    case clientDisconnected
    case maximumDurationReached
    case localSuspension
    case authorizationChanged
    case menuAppUnavailable
    case permissionLost
    case configuredUserUnavailable
    case hostStateAmbiguous
    case displayUnavailable
    case protocolViolation
}

public enum InteractiveSessionEvent: Equatable, Sendable {
    case request(
        sessionID: UUID,
        authorizationEpoch: AuthorizationEpoch,
        approvalDeadlineMonotonicMilliseconds: Int64
    )
    case approvalConsumed(monotonicNowMilliseconds: Int64)
    case executorReadyUnlocked(monotonicNowMilliseconds: Int64)
    case hostLocked(lockSurfaceSupported: Bool)
    case hostUnlocked
    case suspend(InteractiveSessionEndReason)
    case end(InteractiveSessionEndReason)
    case tick(monotonicNowMilliseconds: Int64)
    case teardownFinished(endedAtUnixMilliseconds: Int64)
    case releaseTerminalRecord
}

public enum InteractiveSessionEffect: String, Codable, CaseIterable, Sendable {
    case requestUserPresence
    case beginExecutorSetup
    case publishState
    case pauseInput
    case releaseAllInput
    case invalidateAllSurfaceTokens
    case stopCapture
    case blankLastFrame
    case beginLockSurfaceCapture
    case requireFreshDesktopDescriptorAndKeyframe
    case closeChannels
    case persistTerminalRecord
}

public enum InteractiveSessionTransitionError: Error, Equatable, Sendable {
    case invalidTransition(state: InteractiveSessionState)
    case invalidTime
    case invalidAuthorizationEpoch
}

public struct InteractiveSessionStateMachine: Equatable, Sendable {
    public static let maximumDurationMilliseconds: Int64 = 4 * 60 * 60 * 1_000

    public private(set) var state: InteractiveSessionState = .idle
    public private(set) var sessionID: UUID?
    public private(set) var authorizationEpoch: AuthorizationEpoch?
    public private(set) var approvalDeadlineMonotonicMilliseconds: Int64?
    public private(set) var sessionDeadlineMonotonicMilliseconds: Int64?
    public private(set) var terminalReason: InteractiveSessionEndReason?
    public private(set) var endedAtUnixMilliseconds: Int64?

    public init() {}

    public var admitsPointerAndPhysicalKeyInput: Bool {
        state == .activeUnlocked || state == .activeLocked
    }

    public var admitsTextInput: Bool {
        state == .activeUnlocked
    }

    @discardableResult
    public mutating func apply(
        _ event: InteractiveSessionEvent
    ) throws -> [InteractiveSessionEffect] {
        switch event {
        case let .request(sessionID, epoch, deadline):
            guard state == .idle else { throw invalidTransition() }
            guard epoch.rawValue >= 1 else {
                throw InteractiveSessionTransitionError.invalidAuthorizationEpoch
            }
            guard deadline >= 0 else { throw InteractiveSessionTransitionError.invalidTime }
            self.sessionID = sessionID
            authorizationEpoch = epoch
            approvalDeadlineMonotonicMilliseconds = deadline
            sessionDeadlineMonotonicMilliseconds = nil
            terminalReason = nil
            endedAtUnixMilliseconds = nil
            state = .approvalRequired
            return [.requestUserPresence, .publishState]

        case let .approvalConsumed(now):
            guard state == .approvalRequired,
                  let deadline = approvalDeadlineMonotonicMilliseconds else {
                throw invalidTransition()
            }
            guard now >= 0, now <= Int64.max - Self.maximumDurationMilliseconds else {
                throw InteractiveSessionTransitionError.invalidTime
            }
            guard now < deadline else {
                return beginEnding(reason: .approvalExpired)
            }
            sessionDeadlineMonotonicMilliseconds = now + Self.maximumDurationMilliseconds
            state = .starting
            return [.beginExecutorSetup, .publishState]

        case let .executorReadyUnlocked(now):
            guard state == .starting else { throw invalidTransition() }
            guard now >= 0 else {
                throw InteractiveSessionTransitionError.invalidTime
            }
            guard let sessionDeadlineMonotonicMilliseconds,
                  now < sessionDeadlineMonotonicMilliseconds else {
                return beginEnding(reason: .maximumDurationReached)
            }
            state = .activeUnlocked
            return [.requireFreshDesktopDescriptorAndKeyframe, .publishState]

        case let .hostLocked(lockSurfaceSupported):
            guard state == .activeUnlocked else { throw invalidTransition() }
            let common: [InteractiveSessionEffect] = [
                .pauseInput,
                .releaseAllInput,
                .invalidateAllSurfaceTokens,
                .stopCapture,
                .blankLastFrame,
            ]
            if lockSurfaceSupported {
                state = .activeLocked
                return common + [.beginLockSurfaceCapture, .publishState]
            }
            state = .lockedInteractionUnavailable
            return common + [.publishState]

        case .hostUnlocked:
            switch state {
            case .activeLocked, .lockedInteractionUnavailable:
                state = .starting
                return [
                    .pauseInput,
                    .releaseAllInput,
                    .invalidateAllSurfaceTokens,
                    .stopCapture,
                    .blankLastFrame,
                    .beginExecutorSetup,
                    .publishState,
                ]
            default:
                throw invalidTransition()
            }

        case let .suspend(reason):
            guard Self.suspendibleStates.contains(state) else { throw invalidTransition() }
            terminalReason = reason
            state = .suspended
            return stopAuthorityEffects() + [.publishState]

        case let .end(reason):
            guard Self.endableStates.contains(state) else { throw invalidTransition() }
            return beginEnding(reason: reason)

        case let .tick(now):
            guard now >= 0 else { throw InteractiveSessionTransitionError.invalidTime }
            if state == .approvalRequired,
               let deadline = approvalDeadlineMonotonicMilliseconds,
               now >= deadline {
                return beginEnding(reason: .approvalExpired)
            }
            if Self.durationBoundStates.contains(state),
               let deadline = sessionDeadlineMonotonicMilliseconds,
               now >= deadline {
                return beginEnding(reason: .maximumDurationReached)
            }
            return []

        case let .teardownFinished(endedAt):
            guard state == .ending, endedAt >= 0, terminalReason != nil else {
                if endedAt < 0 { throw InteractiveSessionTransitionError.invalidTime }
                throw invalidTransition()
            }
            endedAtUnixMilliseconds = endedAt
            state = .ended
            return [.persistTerminalRecord, .publishState]

        case .releaseTerminalRecord:
            guard state == .ended else { throw invalidTransition() }
            state = .idle
            sessionID = nil
            authorizationEpoch = nil
            approvalDeadlineMonotonicMilliseconds = nil
            sessionDeadlineMonotonicMilliseconds = nil
            terminalReason = nil
            endedAtUnixMilliseconds = nil
            return [.publishState]
        }
    }

    private mutating func beginEnding(
        reason: InteractiveSessionEndReason
    ) -> [InteractiveSessionEffect] {
        terminalReason = reason
        state = .ending
        return stopAuthorityEffects() + [.closeChannels, .publishState]
    }

    private func stopAuthorityEffects() -> [InteractiveSessionEffect] {
        [
            .pauseInput,
            .releaseAllInput,
            .invalidateAllSurfaceTokens,
            .stopCapture,
            .blankLastFrame,
        ]
    }

    private func invalidTransition() -> InteractiveSessionTransitionError {
        .invalidTransition(state: state)
    }

    private static let durationBoundStates: Set<InteractiveSessionState> = [
        .starting, .activeUnlocked, .activeLocked, .lockedInteractionUnavailable,
    ]
    private static let suspendibleStates: Set<InteractiveSessionState> = [
        .approvalRequired, .starting, .activeUnlocked, .activeLocked,
        .lockedInteractionUnavailable,
    ]
    private static let endableStates: Set<InteractiveSessionState> = suspendibleStates.union([.suspended])
}
