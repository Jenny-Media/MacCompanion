import CompanionTransport
import Dispatch
import Foundation
import Network
import Security

@main
private enum NetworkTLSProbe {
    static func main() throws {
        let fixtureSPKI = Data((0x00...0x5a).map(UInt8.init))
        let pin = try PinnedTLSConnectionAuthority.hostFingerprint(
            subjectPublicKeyInfoDER: fixtureSPKI
        )
        _ = try PinnedTLSConnectionAuthority(
            role: .applicationPrimary,
            requiredHostFingerprint: pin
        )

        let tls = NWProtocolTLS.Options()
        let securityOptions = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(securityOptions, .TLSv13)
        sec_protocol_options_set_max_tls_protocol_version(securityOptions, .TLSv13)
        sec_protocol_options_set_tls_resumption_enabled(securityOptions, false)
        sec_protocol_options_set_verify_block(
            securityOptions,
            { metadata, trust, complete in
                _ = sec_protocol_metadata_get_negotiated_tls_protocol_version(metadata)
                _ = sec_protocol_metadata_get_early_data_accepted(metadata)
                _ = sec_trust_copy_ref(trust)

                // Construction proof only. Until exact certificate parsing,
                // pinned-leaf trust, and identity custody are implemented,
                // this callback must never accept a peer.
                complete(false)
            },
            DispatchQueue(label: "MacCompanion.NetworkTLSProbe.verify")
        )

        let parameters = NWParameters(
            tls: tls,
            tcp: NWProtocolTCP.Options()
        )
        parameters.allowLocalEndpointReuse = false

        // The probe constructs options but never creates or starts a listener
        // or connection, so it performs no network or trust evaluation.
        let report: [String: Any] = [
            "experimentOnly": true,
            "startedNetworkActivity": false,
            "tlsMinimum": "1.3",
            "tlsMaximum": "1.3",
            "tlsResumptionEnabled": false,
            "verifyBlockInstalled": true,
            "verifyBlockAcceptsPeers": false,
        ]
        let data = try JSONSerialization.data(
            withJSONObject: report,
            options: [.prettyPrinted, .sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
