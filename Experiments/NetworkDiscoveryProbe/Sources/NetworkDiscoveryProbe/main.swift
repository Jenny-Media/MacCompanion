import CompanionDiscovery
import Foundation
import Network

@main
private enum NetworkDiscoveryProbe {
    static func main() throws {
        let fingerprint = Data(0x80...0x9f)
        let modelTXT = try BonjourDiscoveryProfile.txtRecord(
            hostFingerprint: fingerprint
        )
        try BonjourDiscoveryProfile.validateTXTRecord(modelTXT)
        let networkTXT = NWTXTRecord([
            BonjourDiscoveryProfile.protocolMajorKey: "0",
            BonjourDiscoveryProfile.hostHintKey: "8081828384858687",
        ])

        let advertisedService = NWListener.Service(
            name: "mac-018f",
            type: BonjourDiscoveryProfile.serviceType,
            domain: BonjourDiscoveryProfile.domain,
            txtRecord: networkTXT
        )
        let browser = NWBrowser(
            for: .bonjour(
                type: BonjourDiscoveryProfile.serviceType,
                domain: BonjourDiscoveryProfile.domain
            ),
            using: .tcp
        )
        let unresolvedCandidate = NWEndpoint.service(
            name: advertisedService.name ?? "mac-018f",
            type: advertisedService.type,
            domain: advertisedService.domain ?? BonjourDiscoveryProfile.domain,
            interface: nil
        )

        // Construction only: this disposable default path never starts the
        // browser or listener and therefore does not request Local Network
        // access or advertise on the current network.
        browser.cancel()
        let report: [String: Any] = [
            "experimentOnly": true,
            "startedNetworkActivity": false,
            "serviceType": advertisedService.type,
            "domain": advertisedService.domain ?? "",
            "candidate": String(describing: unresolvedCandidate),
        ]
        let data = try JSONSerialization.data(
            withJSONObject: report,
            options: [.prettyPrinted, .sortedKeys]
        )
        print(String(decoding: data, as: UTF8.self))
    }
}
