import CompanionSecurity
import Foundation
@preconcurrency import Security

public enum SecurityClientPinnedLeafEvaluatorErrorV0:
    Error,
    Equatable,
    Sendable
{
    case invalidCertificateChain
    case invalidLeafCertificate
}

/// Thin Security.framework extraction boundary. The pure inspector owns the
/// complete certificate profile, signature, validity, and canonical SPKI
/// decision; the TLS callback independently matches the returned SPKI to the
/// immutable paired-host pin.
public enum SecurityClientPinnedLeafEvaluatorV0 {
    public typealias WallNow = @Sendable () -> Int64

    public static func make(
        wallNowUnixMilliseconds: @escaping WallNow
    ) -> NetworkClientPinnedLeafEvaluatorV0 {
        { trust in
            try subjectPublicKeyInfoDER(
                from: trust,
                wallNowUnixMilliseconds: wallNowUnixMilliseconds()
            )
        }
    }

    public static func subjectPublicKeyInfoDER(
        from trust: SecTrust,
        wallNowUnixMilliseconds: Int64
    ) throws -> Data {
        guard let chain = SecTrustCopyCertificateChain(trust)
                as? [SecCertificate],
              chain.count == 1,
              let leaf = chain.first else {
            throw SecurityClientPinnedLeafEvaluatorErrorV0
                .invalidCertificateChain
        }
        let certificateDER = SecCertificateCopyData(leaf) as Data
        guard !certificateDER.isEmpty,
              certificateDER.count
                <= HostIdentityCertificateInspectorV0.maximumCertificateBytes
        else {
            throw SecurityClientPinnedLeafEvaluatorErrorV0
                .invalidLeafCertificate
        }
        return try HostIdentityCertificateInspectorV0.inspect(
            certificateDER: certificateDER,
            wallNowUnixMilliseconds: wallNowUnixMilliseconds
        ).subjectPublicKeyInfoDER
    }
}
