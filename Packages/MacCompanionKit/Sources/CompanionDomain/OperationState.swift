public enum OperationState: String, Codable, CaseIterable, Sendable {
    case pendingPolicy
    case denied
    case awaitingApproval
    case expired
    case queued
    case running
    case cancelRequested
    case succeeded
    case failed
    case cancelled
    case outcomeUnknown

    public var isTerminal: Bool {
        switch self {
        case .denied, .expired, .succeeded, .failed, .cancelled, .outcomeUnknown:
            true
        case .pendingPolicy, .awaitingApproval, .queued, .running, .cancelRequested:
            false
        }
    }

    public func canTransition(to next: Self) -> Bool {
        switch (self, next) {
        case (.pendingPolicy, .denied),
             (.pendingPolicy, .awaitingApproval),
             (.pendingPolicy, .queued),
             (.awaitingApproval, .denied),
             (.awaitingApproval, .expired),
             (.awaitingApproval, .queued),
             (.queued, .running),
             (.queued, .cancelled),
             (.queued, .failed),
             (.running, .cancelRequested),
             (.running, .succeeded),
             (.running, .failed),
             (.running, .outcomeUnknown),
             (.cancelRequested, .cancelled),
             (.cancelRequested, .succeeded),
             (.cancelRequested, .failed),
             (.cancelRequested, .outcomeUnknown):
            true
        default:
            false
        }
    }
}

public struct InvalidOperationTransition: Error, Equatable, Sendable {
    public let from: OperationState
    public let to: OperationState

    public init(from: OperationState, to: OperationState) {
        self.from = from
        self.to = to
    }
}

public struct OperationLifecycle: Codable, Equatable, Sendable {
    public let state: OperationState

    public init(state: OperationState = .pendingPolicy) {
        self.state = state
    }

    public func transitioning(to next: OperationState) throws -> Self {
        guard state.canTransition(to: next) else {
            throw InvalidOperationTransition(from: state, to: next)
        }
        return Self(state: next)
    }
}
