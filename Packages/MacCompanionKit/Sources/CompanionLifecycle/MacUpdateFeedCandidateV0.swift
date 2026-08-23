import Foundation

public enum MacUpdateFeedCandidateErrorV0:
    Error, Equatable, Sendable
{
    case channelMismatch
    case invalidBuild
    case nonIncreasingBuild
    case unsupportedItem
    case invalidArchiveURL
    case invalidDisplayVersion
}

/// Bounded projection of an informational Sparkle item. Construction proves
/// only signed-feed metadata shape; it is not archive, notarization, or install
/// authority and cannot be passed directly to the installation gate.
public struct MacUpdateFeedCandidateV0: Equatable, Sendable {
    public static let maximumDisplayVersionUTF8Bytes = 64
    public static let maximumArchiveURLUTF8Bytes = 2_048

    public let channel: MacUpdateChannelV0
    public let currentBuild: UInt64
    public let candidateBuild: UInt64
    public let displayVersion: String
    public let archiveURL: URL

    public init(
        authority: MacUpdateReleaseAuthorityV0,
        currentBuild: UInt64,
        itemChannel: String?,
        candidateBuild: String,
        displayVersion: String,
        archiveURL: String,
        informationOnly: Bool,
        installationType: String,
        deltaCount: Int
    ) throws {
        let channelMatches: Bool
        switch authority.channel {
        case .beta:
            channelMatches = itemChannel == "beta"
        case .stable:
            channelMatches = itemChannel == nil
        }
        guard channelMatches else {
            throw MacUpdateFeedCandidateErrorV0.channelMismatch
        }
        guard let build = Self.canonicalBuild(candidateBuild) else {
            throw MacUpdateFeedCandidateErrorV0.invalidBuild
        }
        guard build > currentBuild else {
            throw MacUpdateFeedCandidateErrorV0.nonIncreasingBuild
        }
        guard !informationOnly,
              installationType == "application",
              deltaCount == 0 else {
            throw MacUpdateFeedCandidateErrorV0.unsupportedItem
        }
        guard let parsedArchiveURL = Self.validatedArchiveURL(archiveURL)
        else {
            throw MacUpdateFeedCandidateErrorV0.invalidArchiveURL
        }
        guard !displayVersion.isEmpty,
              displayVersion.utf8.count
                <= Self.maximumDisplayVersionUTF8Bytes,
              displayVersion.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0)
              }) else {
            throw MacUpdateFeedCandidateErrorV0.invalidDisplayVersion
        }

        channel = authority.channel
        self.currentBuild = currentBuild
        self.candidateBuild = build
        self.displayVersion = displayVersion
        self.archiveURL = parsedArchiveURL
    }

    private static func canonicalBuild(_ value: String) -> UInt64? {
        guard !value.isEmpty,
              value.utf8.count <= 20,
              value.first != "0" || value == "0",
              let build = UInt64(value),
              String(build) == value else {
            return nil
        }
        return build
    }

    private static func validatedArchiveURL(_ value: String) -> URL? {
        guard !value.isEmpty,
              value.utf8.count <= maximumArchiveURLUTF8Bytes,
              value.unicodeScalars.allSatisfy({ $0.isASCII }),
              !value.contains("\\"),
              !value.contains("%"),
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
              components.percentEncodedPath.hasSuffix(".zip"),
              !components.percentEncodedPath.contains("//"),
              let url = components.url,
              url.absoluteString == value else {
            return nil
        }
        return url
    }
}
