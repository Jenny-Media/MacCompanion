import CompanionLifecycle
import Foundation
import Testing

private func userCheckReleaseAuthority(
    channel: String = "beta"
) throws -> MacUpdateReleaseAuthorityV0 {
    try MacUpdateReleaseAuthorityV0(
        profile: MacUpdateReleaseAuthorityV0.profile,
        channel: channel,
        feedURL: "https://updates.example.com/mac/\(channel)/appcast.xml",
        publicEd25519KeyBase64:
            Data(repeating: 0x73, count: 32).base64EncodedString()
    )
}

@Test func userInitiatedCheckAuthorityBindsReleaseChannelAndBuild() throws {
    let beta = try MacUpdateUserInitiatedCheckAuthorityV0(
        profile: MacUpdateUserInitiatedCheckAuthorityV0.profile,
        releaseAuthority: userCheckReleaseAuthority(),
        currentBuild: 41
    )
    #expect(beta.channel == .beta)
    #expect(beta.currentBuild == 41)

    let stable = try MacUpdateUserInitiatedCheckAuthorityV0(
        profile: MacUpdateUserInitiatedCheckAuthorityV0.profile,
        releaseAuthority: userCheckReleaseAuthority(channel: "stable"),
        currentBuild: 42
    )
    #expect(stable.channel == .stable)
    #expect(stable.currentBuild == 42)
}

@Test func userInitiatedCheckAuthorityRejectsProfileSubstitution() throws {
    #expect(
        throws: MacUpdateUserInitiatedCheckAuthorityErrorV0.invalidProfile
    ) {
        try MacUpdateUserInitiatedCheckAuthorityV0(
            profile: "maccompanion.user-initiated-full-update-check.v2",
            releaseAuthority: userCheckReleaseAuthority(),
            currentBuild: 41
        )
    }
}
