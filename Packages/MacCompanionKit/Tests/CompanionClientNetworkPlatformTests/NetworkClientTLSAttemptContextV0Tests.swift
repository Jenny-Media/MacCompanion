import CompanionClientNetworkPlatform
import CompanionDiscovery
import Dispatch
import Foundation
import Network
import Testing

private enum ClientTLSTestError: Error {
    case evaluatorMustNotRun
}

private let clientTLSAttemptPin = Data(0xa0...0xbf)

private func clientTLSAttemptContext(
    endpoint: EndpointCandidate
) throws -> NetworkClientTLSAttemptContextV0 {
    try NetworkClientTLSAttemptContextV0(
        endpoint: endpoint,
        requiredHostFingerprint: clientTLSAttemptPin,
        verificationQueue: DispatchQueue(
            label: "MacCompanionTests.ClientTLSVerification"
        ),
        pinnedLeafEvaluator: { _ in
            throw ClientTLSTestError.evaluatorMustNotRun
        }
    )
}

@Test func clientTLSAttemptContextCreatesEveryClosedRouteWithoutStarting() throws {
    let endpoints = [
        try EndpointCandidate(
            kind: .bonjour,
            value: "mac-018f._maccompanion._tcp.local.",
            port: 47_474
        ),
        try EndpointCandidate(
            kind: .ipv4,
            value: "192.168.1.20",
            port: 47_474
        ),
        try EndpointCandidate(
            kind: .ipv6,
            value: "fd7a:115c:a1e0::20",
            port: 47_474
        ),
        try EndpointCandidate(
            kind: .dns,
            value: "mac.tail123.ts.net",
            port: 47_474
        ),
    ]

    for endpoint in endpoints {
        let context = try clientTLSAttemptContext(endpoint: endpoint)
        _ = try context.makeUnstartedConnection()
        #expect(context.endpoint == endpoint)
        #expect(context.requiredHostFingerprint == clientTLSAttemptPin)
        #expect(context.verificationStatus() == .pending)
    }
}

@Test func clientTLSAttemptContextIsOneConnectionAndOneHandoffOnly() throws {
    let endpoint = try EndpointCandidate(
        kind: .ipv4,
        value: "192.168.1.20",
        port: 47_474
    )
    let context = try clientTLSAttemptContext(endpoint: endpoint)
    let connection = try context.makeUnstartedConnection()

    #expect(
        throws: NetworkClientTLSAttemptContextErrorV0
            .connectionAlreadyCreated
    ) {
        _ = try context.makeUnstartedConnection()
    }
    #expect(
        throws: NetworkClientTLSAttemptContextErrorV0
            .verificationUnavailable
    ) {
        _ = try context.consumeVerifiedHandoff(for: connection)
    }
    #expect(context.verificationStatus() == .pending)
}

@Test func clientTLSAttemptContextRejectsWrongConnectionAndPinShape() throws {
    let endpoint = try EndpointCandidate(
        kind: .dns,
        value: "mac.tail123.ts.net",
        port: 47_474
    )
    let first = try clientTLSAttemptContext(endpoint: endpoint)
    let second = try clientTLSAttemptContext(endpoint: endpoint)
    _ = try first.makeUnstartedConnection()
    let otherConnection = try second.makeUnstartedConnection()

    #expect(throws: NetworkClientTLSAttemptContextErrorV0.wrongConnection) {
        _ = try first.consumeVerifiedHandoff(for: otherConnection)
    }
    #expect(throws: NetworkClientTLSAttemptContextErrorV0.invalidConfiguration) {
        _ = try NetworkClientTLSAttemptContextV0(
            endpoint: endpoint,
            requiredHostFingerprint: Data(repeating: 1, count: 31),
            verificationQueue: DispatchQueue(
                label: "MacCompanionTests.InvalidClientTLSPin"
            ),
            pinnedLeafEvaluator: { _ in
                throw ClientTLSTestError.evaluatorMustNotRun
            }
        )
    }
}
