import CompanionLifecycle
import Foundation
import Testing

private let updatePublicKeyV0 =
    Data(repeating: 0xA5, count: 32).base64EncodedString()

private func releaseAuthority(
    profile: String = MacUpdateReleaseAuthorityV0.profile,
    channel: String = "beta",
    feedURL: String = "https://updates.example.com/mac/beta/appcast.xml",
    key: String = updatePublicKeyV0
) throws -> MacUpdateReleaseAuthorityV0 {
    try MacUpdateReleaseAuthorityV0(
        profile: profile,
        channel: channel,
        feedURL: feedURL,
        publicEd25519KeyBase64: key
    )
}

@Test func releaseAuthorityAcceptsExactBetaAndStableFeeds() throws {
    let beta = try releaseAuthority()
    #expect(beta.channel == .beta)
    #expect(
        beta.feedURL.absoluteString
            == "https://updates.example.com/mac/beta/appcast.xml"
    )
    #expect(beta.publicEd25519KeyBase64 == updatePublicKeyV0)

    let stable = try releaseAuthority(
        channel: "stable",
        feedURL: "https://updates.example.com/mac/stable/appcast.xml"
    )
    #expect(stable.channel == .stable)
}

@Test func releaseAuthorityRejectsProfileAndChannelSubstitution() {
    #expect(throws: MacUpdateReleaseAuthorityErrorV0.invalidProfile) {
        try releaseAuthority(profile: "maccompanion.sparkle-release-authority.v2")
    }
    #expect(throws: MacUpdateReleaseAuthorityErrorV0.invalidChannel) {
        try releaseAuthority(channel: "internal")
    }
}

@Test(
    arguments: [
        "http://updates.example.com/mac/beta/appcast.xml",
        "https://user@updates.example.com/mac/beta/appcast.xml",
        "https://updates.example.com:443/mac/beta/appcast.xml",
        "https://updates.example.com/mac/beta/appcast.xml?device=1",
        "https://updates.example.com/mac/beta/appcast.xml#latest",
        "https://localhost/mac/beta/appcast.xml",
        "https://updates.local/mac/beta/appcast.xml",
        "https://UPDATES.example.com/mac/beta/appcast.xml",
        "https://updates.example.com/mac//beta/appcast.xml",
        "https://updates.example.com/mac/beta/appcast.json",
        " https://updates.example.com/mac/beta/appcast.xml",
    ]
)
func releaseAuthorityRejectsAmbiguousOrUnsafeFeedURLs(_ value: String) {
    #expect(throws: MacUpdateReleaseAuthorityErrorV0.invalidFeedURL) {
        try releaseAuthority(feedURL: value)
    }
}

@Test func releaseAuthorityRejectsNoncanonicalOrWrongWidthPublicKeys() {
    #expect(throws: MacUpdateReleaseAuthorityErrorV0.invalidPublicKey) {
        try releaseAuthority(key: " \(updatePublicKeyV0)")
    }
    #expect(throws: MacUpdateReleaseAuthorityErrorV0.invalidPublicKey) {
        try releaseAuthority(
            key: Data(repeating: 0xA5, count: 31).base64EncodedString()
        )
    }
    #expect(throws: MacUpdateReleaseAuthorityErrorV0.invalidPublicKey) {
        try releaseAuthority(key: "not-base64")
    }
}
