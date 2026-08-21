import CompanionDomain
import Testing

@Test func capabilityEffectFactsHaveOneClosedSecurityEncoding() throws {
    let facts = try CapabilityEffectFacts(
        dataAccess: .privateData,
        changesLocalState: .reversible,
        mayDisruptUser: true,
        invokesExternalService: false,
        usesCredentials: true,
        destructive: false,
        requiresForegroundSession: true,
        allowedWhileLocked: false,
        cancellation: .bestEffort
    )
    #expect(facts.securityEncoding == [2, 1, 0b0001_0101, 1])
}

@Test func foregroundAndLockedEligibilityCannotBothBeClaimed() {
    #expect(throws: CapabilityEffectFactsError.contradictorySessionRequirement) {
        try CapabilityEffectFacts(
            dataAccess: .none,
            changesLocalState: .none,
            mayDisruptUser: false,
            invokesExternalService: false,
            usesCredentials: false,
            destructive: false,
            requiresForegroundSession: true,
            allowedWhileLocked: true,
            cancellation: .notApplicable
        )
    }
}
