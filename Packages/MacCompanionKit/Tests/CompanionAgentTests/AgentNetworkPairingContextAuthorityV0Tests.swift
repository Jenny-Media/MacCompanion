import CompanionAgent
import CompanionAgentNetworkPlatform
import CompanionDiscovery
import Foundation
import Testing

private func networkPairingContextV0() throws -> AgentLocalPairingContextV0 {
    try AgentLocalPairingContextV0(
        hostFingerprint: Data(0x60...0x7f),
        endpoints: [
            try EndpointCandidate(
                kind: .bonjour,
                value: "office._maccompanion._tcp.local.",
                port: 47_474
            ),
            try EndpointCandidate(
                kind: .ipv4,
                value: "192.168.20.40",
                port: 47_474
            ),
        ]
    )
}

@Test func pairingContextRequiresExactListenerAndAdvertisementReadiness() async throws {
    let context = try networkPairingContextV0()
    let authority = AgentNetworkPairingContextAuthorityV0(context: context)

    await #expect(throws: AgentNetworkPairingContextErrorV0.unavailable) {
        _ = try await authority.currentPairingContext()
    }
    try await authority.publishAdvertisementReadiness(
        ready: true,
        generation: 1
    )
    await #expect(throws: AgentNetworkPairingContextErrorV0.unavailable) {
        _ = try await authority.currentPairingContext()
    }
    try await authority.publishListenerReadiness(ready: true, generation: 1)
    #expect(try await authority.currentPairingContext() == context)
    #expect((await authority.snapshot()).pairingAvailable)

    try await authority.publishAdvertisementReadiness(
        ready: false,
        generation: 2
    )
    await #expect(throws: AgentNetworkPairingContextErrorV0.unavailable) {
        _ = try await authority.currentPairingContext()
    }
}

@Test func pairingContextRejectsStaleCallbacksAndTerminalResurrection() async throws {
    let authority = AgentNetworkPairingContextAuthorityV0(
        context: try networkPairingContextV0()
    )
    try await authority.publishListenerReadiness(ready: true, generation: 2)
    await #expect(
        throws: AgentNetworkPairingContextErrorV0.staleListenerGeneration
    ) {
        try await authority.publishListenerReadiness(
            ready: false,
            generation: 2
        )
    }
    try await authority.publishAdvertisementReadiness(
        ready: true,
        generation: 3
    )
    await authority.stop()

    let snapshot = await authority.snapshot()
    #expect(snapshot.terminal)
    #expect(!snapshot.pairingAvailable)
    await #expect(
        throws: AgentNetworkPairingContextErrorV0
            .staleAdvertisementGeneration
    ) {
        try await authority.publishAdvertisementReadiness(
            ready: true,
            generation: 4
        )
    }
    await #expect(throws: AgentNetworkPairingContextErrorV0.unavailable) {
        _ = try await authority.currentPairingContext()
    }
}
