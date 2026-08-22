public enum ConsoleSessionState: String, Codable, CaseIterable, Sendable {
    case active
    case locked
    case otherConsoleUserActive
    case loggedOut
}

public enum ManagedProcessState: String, Codable, CaseIterable, Sendable {
    case stopped
    case starting
    case ready
}

public enum ProductLifecycleEvent: Equatable, Sendable {
    case enableRequested
    case disableRequested
    case userLoggedIn
    case userLocked
    case userUnlocked
    case otherConsoleUserBecameActive
    case configuredUserBecameActive
    case userLoggedOut
    case agentReady
    case agentExited
    case menuAppReady
    case menuAppExited
}

public enum ProductLifecycleEffect: String, Codable, CaseIterable, Sendable {
    case registerAgentLogin
    case registerMenuLogin
    case unregisterAgentLogin
    case unregisterMenuLogin
    case requestAgentStart
    case requestAgentRecovery
    case requestMenuStart
    case requestMenuRecovery
    case endInteractiveControl
    case closeAllRemoteSessions
}

public struct InvalidProductLifecycleTransition: Error, Equatable, Sendable {
    public let event: ProductLifecycleEvent

    public init(event: ProductLifecycleEvent) {
        self.event = event
    }
}

public struct ProductLifecycleState: Equatable, Sendable {
    public private(set) var desiredEnabled: Bool
    public private(set) var consoleSession: ConsoleSessionState
    public private(set) var agent: ManagedProcessState
    public private(set) var menuApp: ManagedProcessState

    public init(
        desiredEnabled: Bool = false,
        consoleSession: ConsoleSessionState,
        agent: ManagedProcessState = .stopped,
        menuApp: ManagedProcessState = .stopped
    ) {
        self.desiredEnabled = desiredEnabled
        self.consoleSession = consoleSession
        self.agent = agent
        self.menuApp = menuApp
    }

    public var observeAvailable: Bool {
        desiredEnabled && consoleSession != .loggedOut && agent == .ready
    }

    /// Whether a new Interactive Control session may be admitted.
    public var newInteractiveControlAvailable: Bool {
        observeAvailable && consoleSession == .active && menuApp == .ready
    }

    public var localAdministrationVisible: Bool {
        desiredEnabled && consoleSession == .active && menuApp == .ready
    }

    @discardableResult
    public mutating func apply(
        _ event: ProductLifecycleEvent
    ) throws -> [ProductLifecycleEffect] {
        switch event {
        case .enableRequested:
            guard !desiredEnabled, consoleSession != .loggedOut else {
                throw InvalidProductLifecycleTransition(event: event)
            }
            desiredEnabled = true
            agent = .starting
            menuApp = .starting
            return [
                .registerAgentLogin,
                .registerMenuLogin,
                .requestAgentStart,
                .requestMenuStart,
            ]

        case .disableRequested:
            guard desiredEnabled else {
                throw InvalidProductLifecycleTransition(event: event)
            }
            desiredEnabled = false
            agent = .stopped
            menuApp = .stopped
            return [
                .endInteractiveControl,
                .closeAllRemoteSessions,
                .unregisterAgentLogin,
                .unregisterMenuLogin,
            ]

        case .userLoggedIn:
            guard consoleSession == .loggedOut else {
                throw InvalidProductLifecycleTransition(event: event)
            }
            consoleSession = .active
            guard desiredEnabled else { return [] }
            agent = .starting
            menuApp = .starting
            return [.requestAgentStart, .requestMenuStart]

        case .userLocked:
            guard consoleSession == .active else {
                throw InvalidProductLifecycleTransition(event: event)
            }
            consoleSession = .locked
            return [.endInteractiveControl]

        case .userUnlocked:
            guard consoleSession == .locked else {
                throw InvalidProductLifecycleTransition(event: event)
            }
            consoleSession = .active
            return []

        case .otherConsoleUserBecameActive:
            guard consoleSession == .active || consoleSession == .locked else {
                throw InvalidProductLifecycleTransition(event: event)
            }
            consoleSession = .otherConsoleUserActive
            return [.endInteractiveControl]

        case .configuredUserBecameActive:
            guard consoleSession == .otherConsoleUserActive else {
                throw InvalidProductLifecycleTransition(event: event)
            }
            consoleSession = .active
            return []

        case .userLoggedOut:
            guard consoleSession != .loggedOut else {
                throw InvalidProductLifecycleTransition(event: event)
            }
            consoleSession = .loggedOut
            agent = .stopped
            menuApp = .stopped
            return [.endInteractiveControl, .closeAllRemoteSessions]

        case .agentReady:
            guard desiredEnabled, consoleSession != .loggedOut, agent == .starting else {
                throw InvalidProductLifecycleTransition(event: event)
            }
            agent = .ready
            return []

        case .agentExited:
            guard agent != .stopped else {
                throw InvalidProductLifecycleTransition(event: event)
            }
            if desiredEnabled && consoleSession != .loggedOut {
                agent = .starting
                return [.endInteractiveControl, .closeAllRemoteSessions, .requestAgentRecovery]
            }
            agent = .stopped
            return [.endInteractiveControl, .closeAllRemoteSessions]

        case .menuAppReady:
            guard desiredEnabled, consoleSession != .loggedOut, menuApp == .starting else {
                throw InvalidProductLifecycleTransition(event: event)
            }
            menuApp = .ready
            return []

        case .menuAppExited:
            guard menuApp != .stopped else {
                throw InvalidProductLifecycleTransition(event: event)
            }
            if desiredEnabled && consoleSession != .loggedOut {
                menuApp = .starting
                return [.endInteractiveControl, .requestMenuRecovery]
            }
            menuApp = .stopped
            return [.endInteractiveControl]
        }
    }
}
