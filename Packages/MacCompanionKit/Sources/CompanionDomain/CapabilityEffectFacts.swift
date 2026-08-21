public enum CapabilityDataAccessEffect: UInt8, Codable, CaseIterable, Sendable {
    case none = 0
    case publicData = 1
    case privateData = 2
    case credentials = 3
}

public enum CapabilityLocalStateEffect: UInt8, Codable, CaseIterable, Sendable {
    case none = 0
    case reversible = 1
    case irreversible = 2
}

public enum CapabilityCancellationEffect: UInt8, Codable, CaseIterable, Sendable {
    case notApplicable = 0
    case bestEffort = 1
}

public enum CapabilityEffectFactsError: Error, Equatable, Sendable {
    case contradictorySessionRequirement
}

public struct CapabilityEffectFacts: Equatable, Sendable {
    public let dataAccess: CapabilityDataAccessEffect
    public let changesLocalState: CapabilityLocalStateEffect
    public let mayDisruptUser: Bool
    public let invokesExternalService: Bool
    public let usesCredentials: Bool
    public let destructive: Bool
    public let requiresForegroundSession: Bool
    public let allowedWhileLocked: Bool
    public let cancellation: CapabilityCancellationEffect

    public init(
        dataAccess: CapabilityDataAccessEffect,
        changesLocalState: CapabilityLocalStateEffect,
        mayDisruptUser: Bool,
        invokesExternalService: Bool,
        usesCredentials: Bool,
        destructive: Bool,
        requiresForegroundSession: Bool,
        allowedWhileLocked: Bool,
        cancellation: CapabilityCancellationEffect
    ) throws {
        guard !(requiresForegroundSession && allowedWhileLocked) else {
            throw CapabilityEffectFactsError.contradictorySessionRequirement
        }
        self.dataAccess = dataAccess
        self.changesLocalState = changesLocalState
        self.mayDisruptUser = mayDisruptUser
        self.invokesExternalService = invokesExternalService
        self.usesCredentials = usesCredentials
        self.destructive = destructive
        self.requiresForegroundSession = requiresForegroundSession
        self.allowedWhileLocked = allowedWhileLocked
        self.cancellation = cancellation
    }

    public var securityEncoding: [UInt8] {
        var flags: UInt8 = 0
        if mayDisruptUser { flags |= 1 << 0 }
        if invokesExternalService { flags |= 1 << 1 }
        if usesCredentials { flags |= 1 << 2 }
        if destructive { flags |= 1 << 3 }
        if requiresForegroundSession { flags |= 1 << 4 }
        if allowedWhileLocked { flags |= 1 << 5 }
        return [dataAccess.rawValue, changesLocalState.rawValue, flags, cancellation.rawValue]
    }
}
