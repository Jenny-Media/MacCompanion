import CompanionDiscovery
import Foundation
import Testing

@Test func closedDiscoveryProfileAcceptsOnlyCanonicalRoutes() throws {
    let candidates = [
        try EndpointCandidate(
            kind: .bonjour,
            value: "mac-018f._maccompanion._tcp.local.",
            port: 47_474
        ),
        try EndpointCandidate(kind: .ipv4, value: "192.168.1.20", port: 47_474),
        try EndpointCandidate(kind: .ipv6, value: "fd7a:115c:a1e0::20", port: 47_474),
        try EndpointCandidate(kind: .dns, value: "mac.tail123.ts.net", port: 47_474),
    ]

    #expect(candidates.map(\.kind) == [.bonjour, .ipv4, .ipv6, .dns])
    #expect(BonjourDiscoveryProfile.serviceType == "_maccompanion._tcp")
    #expect(BonjourDiscoveryProfile.domain == "local.")
}

@Test func ambiguousOrNoncanonicalRouteTextIsRejected() {
    let invalid: [(EndpointKind, String)] = [
        (.bonjour, "Jenny Mac._maccompanion._tcp.local."),
        (.bonjour, "Mac-018f._maccompanion._tcp.local."),
        (.bonjour, "mac-018f._other._tcp.local."),
        (.ipv4, "192.168.001.020"),
        (.ipv4, "192.168.1.20:47474"),
        (.ipv6, "FD7A:115C:A1E0::20"),
        (.ipv6, "fd7a:115c:a1e0:0:0:0:0:20"),
        (.dns, "Mac.tail123.ts.net"),
        (.dns, "mac.tail123.ts.net."),
        (.dns, "mac..tail123.ts.net"),
    ]
    for (kind, value) in invalid {
        #expect(throws: EndpointValidationError.invalidValue) {
            _ = try EndpointCandidate(kind: kind, value: value, port: 47_474)
        }
    }
    #expect(throws: EndpointValidationError.invalidPort) {
        _ = try EndpointCandidate(kind: .ipv4, value: "192.168.1.20", port: 0)
    }
}

@Test func boundedTXTRecordContainsOnlyVersionAndTruncatedUntrustedHint() throws {
    let fingerprint = Data(0x80...0x9f)
    let record = try BonjourDiscoveryProfile.txtRecord(hostFingerprint: fingerprint)
    try BonjourDiscoveryProfile.validateTXTRecord(record)
    #expect(record["v"] == Data("0".utf8))
    #expect(record["h"] == Data("8081828384858687".utf8))

    var injected = record
    injected["name"] = Data("private-hostname".utf8)
    #expect(throws: EndpointValidationError.invalidTXTRecord) {
        try BonjourDiscoveryProfile.validateTXTRecord(injected)
    }
}
