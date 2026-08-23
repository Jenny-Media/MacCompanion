public enum MacUpdateUserInitiatedCheckAuthorityErrorV0:
    Error, Equatable, Sendable
{
    case invalidProfile
}

/// Release-injected authority for one visible user-initiated full Sparkle
/// check. It never permits a background or automatic check. Absence leaves the
/// same visible action information-only; a malformed profile fails the updater
/// configuration closed.
public struct MacUpdateUserInitiatedCheckAuthorityV0:
    Equatable, Sendable
{
    public static let profile =
        "maccompanion.user-initiated-full-update-check.v1"

    public let channel: MacUpdateChannelV0
    public let currentBuild: UInt64

    public init(
        profile: String,
        releaseAuthority: MacUpdateReleaseAuthorityV0,
        currentBuild: UInt64
    ) throws {
        guard profile == Self.profile else {
            throw MacUpdateUserInitiatedCheckAuthorityErrorV0
                .invalidProfile
        }
        channel = releaseAuthority.channel
        self.currentBuild = currentBuild
    }
}
