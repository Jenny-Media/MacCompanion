#if os(macOS) && DEBUG
import Foundation
@testable import CompanionLocalXPCPlatform
import Testing

@Test func isolatedXPCAddressCannotSelectPermanentService() {
    let first = UUID()
    let second = UUID()
    let name = MacLocalXPCIsolatedTestAddressV1.serviceName(first)
    #expect(name == "media.jenny.maccompanion.xpc-test.\(first.uuidString.lowercased())")
    #expect(name != MacLocalXPCIdentityV1.serviceName)
    #expect(name != MacLocalXPCIsolatedTestAddressV1.serviceName(second))
    #expect(name == MacLocalXPCIsolatedTestAddressV1.serviceName(first))
}

@available(macOS 26.0, *)
@Test func isolatedXPCStillRejectsInvalidProfileAndBuildBeforeActivation() {
    let invalidProfile = MacLocalXPCServerV1(
        isolatedTestID: UUID(), profile: .disabledRemoteAccessBootstrap, onEvent: { _ in })
    #expect(throws: MacLocalXPCConstructionErrorV1.invalidProfile) { try invalidProfile.start() }
    let invalidBuild = MacLocalXPCServerV1(
        isolatedTestID: UUID(), profile: .authenticationOnly, agentBuild: nil, onEvent: { _ in })
    #expect(throws: MacLocalXPCConstructionErrorV1.invalidAgentBuild) { try invalidBuild.start() }
}
#endif
