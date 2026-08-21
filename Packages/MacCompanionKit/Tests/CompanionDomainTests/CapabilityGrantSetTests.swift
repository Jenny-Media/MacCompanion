import CompanionDomain
import Testing

@Test func capabilityGrantSetIsCanonicalBoundedAndClosed() throws {
    let grants = try CapabilityGrantSet([
        "maccompanion.system.setAudioMuted",
        "maccompanion.test.secondaryAction",
    ])
    #expect(grants.capabilityIDs == [
        "maccompanion.system.setAudioMuted",
        "maccompanion.test.secondaryAction",
    ])
    #expect(throws: CapabilityGrantSetError.duplicate("a")) {
        try CapabilityGrantSet(["a", "a"])
    }
    #expect(throws: CapabilityGrantSetError.invalidIdentifier("not allowed/space")) {
        try CapabilityGrantSet(["not allowed/space"])
    }
    #expect(throws: CapabilityGrantSetError.tooMany) {
        try CapabilityGrantSet((0...CapabilityGrantSet.maximumCount).map { "cap.\($0)" })
    }
}

@Test func replacingActiveGrantAdvancesBothFences() throws {
    let granted = DeviceAuthorization(
        state: .activeGranted,
        authorizationEpoch: .init(rawValue: 4),
        grantRevision: .init(rawValue: 7)
    )
    let replaced = try granted.applying(.replaceGrant)
    #expect(replaced.state == .activeGranted)
    #expect(replaced.authorizationEpoch.rawValue == 5)
    #expect(replaced.grantRevision.rawValue == 8)
}
