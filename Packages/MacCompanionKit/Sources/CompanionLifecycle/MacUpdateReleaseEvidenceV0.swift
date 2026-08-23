import Foundation

public enum MacUpdateReleaseEvidenceErrorV0:
    Error, Equatable, Sendable
{
    case invalidAttributes
    case invalidProfile
    case invalidEvidenceLevel
    case invalidCandidateEncoding
    case candidateMismatch
    case trustRequirementMissing
    case invalidDigest
}

/// Signed-publication projection of independently produced release evidence.
/// Construction validates only the closed claim and its exact candidate
/// binding. The protected release lane remains responsible for producing the
/// referenced records truthfully before the signed appcast publishes them.
public struct MacUpdateReleaseEvidenceV0: Equatable, Sendable {
    public static let profile =
        "maccompanion.update-release-evidence.v1"
    // The final signed appcast is itself publication evidence. Binding a
    // promotionReady manifest here would create a content-hash cycle because
    // that manifest also records the appcast. The attestation therefore binds
    // the complete signedCandidate record; publication authorization remains
    // an external release-lane gate.
    public static let evidenceLevel = "signedCandidate"

    public enum Attribute {
        public static let prefix = "maccompanion:"
        public static let profile = prefix + "evidenceProfile"
        public static let level = prefix + "evidenceLevel"
        public static let channel = prefix + "evidenceChannel"
        public static let build = prefix + "evidenceBuild"
        public static let displayVersion =
            prefix + "evidenceDisplayVersion"
        public static let archiveURL = prefix + "evidenceArchiveURL"
        public static let archiveLength =
            prefix + "evidenceArchiveLength"
        public static let archiveSignature =
            prefix + "evidenceArchiveEdSignature"
        public static let archiveSHA256 = prefix + "archiveSHA256"
        public static let releaseManifestSHA256 =
            prefix + "releaseManifestSHA256"
        public static let platformSigningRecordSHA256 =
            prefix + "platformSigningRecordSHA256"
        public static let notarizationRecordSHA256 =
            prefix + "notarizationRecordSHA256"
        public static let packagingReceiptSHA256 =
            prefix + "packagingEquivalenceReceiptSHA256"
        public static let developerIDGraph =
            prefix + "developerIDGraphEvidence"
        public static let notarization =
            prefix + "notarizationEvidence"
        public static let applicationStapling =
            prefix + "applicationStaplingEvidence"
        public static let wholeApplicationZIP =
            prefix + "wholeApplicationZIPEvidence"

        public static let all: Set<String> = [
            profile,
            level,
            channel,
            build,
            displayVersion,
            archiveURL,
            archiveLength,
            archiveSignature,
            archiveSHA256,
            releaseManifestSHA256,
            platformSigningRecordSHA256,
            notarizationRecordSHA256,
            packagingReceiptSHA256,
            developerIDGraph,
            notarization,
            applicationStapling,
            wholeApplicationZIP,
        ]
    }

    public let channel: MacUpdateChannelV0
    public let candidateBuild: UInt64
    public let displayVersion: String
    public let archiveURL: URL
    public let archiveContentLength: UInt64
    public let archiveEd25519Signature: String
    public let archiveSHA256: String
    public let releaseManifestSHA256: String
    public let platformSigningRecordSHA256: String
    public let notarizationRecordSHA256: String
    public let packagingEquivalenceReceiptSHA256: String

    public init(
        feedCandidate: MacUpdateFeedCandidateV0,
        attributes: [String: String]
    ) throws {
        guard Set(attributes.keys) == Attribute.all else {
            throw MacUpdateReleaseEvidenceErrorV0.invalidAttributes
        }
        guard attributes[Attribute.profile] == Self.profile else {
            throw MacUpdateReleaseEvidenceErrorV0.invalidProfile
        }
        guard attributes[Attribute.level] == Self.evidenceLevel else {
            throw MacUpdateReleaseEvidenceErrorV0.invalidEvidenceLevel
        }
        guard let channelText = attributes[Attribute.channel],
              let attestedChannel =
                MacUpdateChannelV0(rawValue: channelText),
              let buildText = attributes[Attribute.build],
              let attestedBuild = Self.canonicalUInt64(buildText),
              let attestedDisplayVersion =
                attributes[Attribute.displayVersion],
              let archiveURLText = attributes[Attribute.archiveURL],
              let attestedArchiveURL = URL(string: archiveURLText),
              attestedArchiveURL.absoluteString == archiveURLText,
              let archiveLengthText =
                attributes[Attribute.archiveLength],
              let attestedArchiveLength =
                Self.canonicalUInt64(archiveLengthText),
              let attestedArchiveSignature =
                attributes[Attribute.archiveSignature] else {
            throw MacUpdateReleaseEvidenceErrorV0
                .invalidCandidateEncoding
        }
        guard attestedChannel == feedCandidate.channel,
              attestedBuild == feedCandidate.candidateBuild,
              attestedDisplayVersion == feedCandidate.displayVersion,
              archiveURLText == feedCandidate.archiveURL.absoluteString,
              attestedArchiveLength
                == feedCandidate.archiveContentLength,
              attestedArchiveSignature
                == feedCandidate.archiveEd25519Signature else {
            throw MacUpdateReleaseEvidenceErrorV0.candidateMismatch
        }
        guard attributes[Attribute.developerIDGraph] == "passed",
              attributes[Attribute.notarization] == "passed",
              attributes[Attribute.applicationStapling] == "passed",
              attributes[Attribute.wholeApplicationZIP] == "passed" else {
            throw MacUpdateReleaseEvidenceErrorV0
                .trustRequirementMissing
        }
        guard let archiveSHA256 = attributes[Attribute.archiveSHA256],
              let releaseManifestSHA256 =
                attributes[Attribute.releaseManifestSHA256],
              let platformSigningRecordSHA256 =
                attributes[Attribute.platformSigningRecordSHA256],
              let notarizationRecordSHA256 =
                attributes[Attribute.notarizationRecordSHA256],
              let packagingReceiptSHA256 =
                attributes[Attribute.packagingReceiptSHA256],
              [
                  archiveSHA256,
                  releaseManifestSHA256,
                  platformSigningRecordSHA256,
                  notarizationRecordSHA256,
                  packagingReceiptSHA256,
              ].allSatisfy(Self.isCanonicalSHA256) else {
            throw MacUpdateReleaseEvidenceErrorV0.invalidDigest
        }

        channel = feedCandidate.channel
        candidateBuild = feedCandidate.candidateBuild
        displayVersion = feedCandidate.displayVersion
        archiveURL = feedCandidate.archiveURL
        archiveContentLength = feedCandidate.archiveContentLength
        archiveEd25519Signature =
            feedCandidate.archiveEd25519Signature
        self.archiveSHA256 = archiveSHA256
        self.releaseManifestSHA256 = releaseManifestSHA256
        self.platformSigningRecordSHA256 =
            platformSigningRecordSHA256
        self.notarizationRecordSHA256 = notarizationRecordSHA256
        self.packagingEquivalenceReceiptSHA256 =
            packagingReceiptSHA256
    }

    func isBound(to candidate: MacUpdateFeedCandidateV0) -> Bool {
        channel == candidate.channel
            && candidateBuild == candidate.candidateBuild
            && displayVersion == candidate.displayVersion
            && archiveURL == candidate.archiveURL
            && archiveContentLength == candidate.archiveContentLength
            && archiveEd25519Signature
                == candidate.archiveEd25519Signature
    }

    private static func canonicalUInt64(_ value: String) -> UInt64? {
        guard !value.isEmpty,
              value.utf8.count <= 20,
              value.first != "0" || value == "0",
              let result = UInt64(value),
              String(result) == value else {
            return nil
        }
        return result
    }

    private static func isCanonicalSHA256(_ value: String) -> Bool {
        guard value.utf8.count == 64,
              value.utf8.allSatisfy({ byte in
                  (48...57).contains(byte) || (97...102).contains(byte)
              }),
              Set(value.utf8).count > 1,
              value
                != "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        else {
            return false
        }
        return true
    }
}
