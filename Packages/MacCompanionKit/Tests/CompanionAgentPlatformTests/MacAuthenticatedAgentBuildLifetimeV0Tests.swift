#if os(macOS)
@testable import CompanionAgentPlatform
import Testing

@Test
@available(macOS 26.0, *)
func authenticatedAgentBuildLifetimePublishesOnceAndRetiresClosed() throws {
    let lifetime = MacAuthenticatedAgentBuildLifetimeV0()

    #expect(lifetime.currentBuild() == nil)
    try lifetime.authenticate(build: 42)
    #expect(lifetime.currentBuild() == 42)
    lifetime.retire()
    #expect(lifetime.currentBuild() == nil)
    #expect(throws: MacAuthenticatedAgentBuildLifetimeErrorV0.invalidPhase) {
        try lifetime.authenticate(build: 43)
    }
    #expect(lifetime.currentBuild() == nil)
}

@Test
@available(macOS 26.0, *)
func duplicateAuthenticatedAgentBuildRetiresExistingEvidence() throws {
    let lifetime = MacAuthenticatedAgentBuildLifetimeV0()

    try lifetime.authenticate(build: 42)
    #expect(throws: MacAuthenticatedAgentBuildLifetimeErrorV0.invalidPhase) {
        try lifetime.authenticate(build: 42)
    }
    #expect(lifetime.currentBuild() == nil)
}
#endif
