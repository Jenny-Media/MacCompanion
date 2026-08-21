public enum HostState: String, Codable, CaseIterable, Sendable {
    case userSessionActive
    case userSessionLocked
    case otherConsoleUserActive
    case serviceStoppingForLogout
    case hostPreparingForSleep
}

public enum ClientReachabilityState: String, Codable, CaseIterable, Sendable {
    case reachable
    case unreachable
}
