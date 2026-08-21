#if os(macOS)
import CompanionAgent
import CompanionAgentPlatform
import ServiceManagement
import Testing

@Test func smAppServiceStatusProjectionIsClosedAndExact() {
    #expect(SMAppServiceRawLoginRoleV1.project(.notRegistered) == .notRegistered)
    #expect(SMAppServiceRawLoginRoleV1.project(.enabled) == .enabled)
    #expect(SMAppServiceRawLoginRoleV1.project(.requiresApproval) == .requiresApproval)
    #expect(SMAppServiceRawLoginRoleV1.project(.notFound) == .notFound)
}
#endif
