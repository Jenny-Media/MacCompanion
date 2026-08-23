import Foundation

public enum MacUpdateReleaseAuthorityErrorV0:
    Error, Equatable, Sendable
{
    case invalidProfile
    case invalidChannel
    case invalidFeedURL
    case invalidPublicKey
}

/// Public, release-injected authority needed before the containing app may
/// construct Sparkle. Absence is a supported inert state; partial or malformed
/// authority fails closed without starting an updater or touching the network.
public struct MacUpdateReleaseAuthorityV0: Equatable, Sendable {
    public static let profile =
        "maccompanion.sparkle-release-authority.v1"
    public static let maximumFeedURLUTF8Bytes = 2_048

    public let channel: MacUpdateChannelV0
    public let feedURL: URL
    public let publicEd25519KeyBase64: String

    public init(
        profile: String,
        channel: String,
        feedURL: String,
        publicEd25519KeyBase64: String
    ) throws {
        guard profile == Self.profile else {
            throw MacUpdateReleaseAuthorityErrorV0.invalidProfile
        }
        guard let parsedChannel = MacUpdateChannelV0(rawValue: channel)
        else {
            throw MacUpdateReleaseAuthorityErrorV0.invalidChannel
        }
        guard let parsedFeedURL = Self.validatedFeedURL(feedURL) else {
            throw MacUpdateReleaseAuthorityErrorV0.invalidFeedURL
        }
        guard let publicKey = Data(
            base64Encoded: publicEd25519KeyBase64,
            options: []
        ), publicKey.count == 32,
        publicKey.base64EncodedString() == publicEd25519KeyBase64 else {
            throw MacUpdateReleaseAuthorityErrorV0.invalidPublicKey
        }

        self.channel = parsedChannel
        self.feedURL = parsedFeedURL
        self.publicEd25519KeyBase64 = publicEd25519KeyBase64
    }

    private static func validatedFeedURL(_ value: String) -> URL? {
        guard !value.isEmpty,
              value.utf8.count <= maximumFeedURLUTF8Bytes,
              value.unicodeScalars.allSatisfy({ $0.isASCII }),
              !value.contains("\\"),
              let components = URLComponents(string: value),
              components.scheme == "https",
              let host = components.host,
              !host.isEmpty,
              host == host.lowercased(),
              host != "localhost",
              !host.hasSuffix(".local"),
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil,
              components.percentEncodedPath.hasPrefix("/"),
              components.percentEncodedPath.hasSuffix(".xml"),
              !components.percentEncodedPath.contains("//"),
              let url = components.url,
              url.absoluteString == value else {
            return nil
        }
        return url
    }
}
