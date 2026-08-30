import CompanionIPC
import CompanionLifecycle
import CompanionWire
import Foundation
import Testing

private func wireStatusSnapshotV1(
    consoleSession: ConsoleSessionState = .active
) throws -> LocalAgentStatusSnapshot {
    try LocalAgentStatusSnapshot(
        desiredEnabled: true,
        consoleSession: consoleSession,
        agentProcess: .ready,
        menuAppProcess: .starting,
        networkState: .listening,
        securityPosture: .nominal,
        routeKinds: [.privateNetwork, .lan],
        pairedDeviceCount: 2,
        interactiveControlGranted: true,
        activeRemoteSessionCount: 1,
        providerCount: 3,
        warningCodes: [.menuAppUnavailable],
        diagnosticSequence: 9,
        generatedAtUnixMilliseconds: 1_724_000_000_000
    )
}

@Test
func localAgentStatusWireCodecPreservesAmbiguousConsoleState() throws {
    let expected = try wireStatusSnapshotV1(
        consoleSession: .otherConsoleUserActive
    )
    let payload = try LocalAgentStatusWireCodecV1.encode(expected)
    let text = try #require(String(data: payload, encoding: .utf8))

    #expect(try CanonicalJSON.canonicalize(payload) == payload)
    #expect(text.contains("\"interactiveControlGranted\":true"))
    #expect(text.contains(
        "\"consoleSession\":\"otherConsoleUserActive\""
    ))
    #expect(try LocalAgentStatusWireCodecV1.decode(payload) == expected)
}

@Test
func localAgentStatusWireCodecRoundTripsCanonicalBoundedSnapshot() throws {
    let expected = try wireStatusSnapshotV1()
    let payload = try LocalAgentStatusWireCodecV1.encode(expected)

    #expect(payload.count <= LocalAgentStatusWireCodecV1.maximumEncodedBytes)
    #expect(try CanonicalJSON.canonicalize(payload) == payload)
    #expect(try LocalAgentStatusWireCodecV1.decode(payload) == expected)
}

@Test
func localAgentStatusWireCodecRejectsCanonicalUnknownMember() throws {
    let payload = try LocalAgentStatusWireCodecV1.encode(
        wireStatusSnapshotV1()
    )
    guard case let .object(members) = try CanonicalJSON.parse(payload) else {
        Issue.record("status payload was not an object")
        return
    }
    let openPayload = CanonicalJSON.canonicalData(
        for: .object(
            members + [
                CanonicalJSONMember(
                    key: "unexpected",
                    value: .boolean(true)
                )
            ]
        )
    )

    #expect(throws: LocalAgentStatusWireCodecErrorV1.nonCanonicalPayload) {
        try LocalAgentStatusWireCodecV1.decode(openPayload)
    }
}

@Test
func localAgentStatusWireCodecRejectsNonCanonicalAndOversizedPayloads() throws {
    let payload = try LocalAgentStatusWireCodecV1.encode(
        wireStatusSnapshotV1()
    )
    let padded = Data([0x20]) + payload
    #expect(throws: LocalAgentStatusWireCodecErrorV1.nonCanonicalPayload) {
        try LocalAgentStatusWireCodecV1.decode(padded)
    }

    let oversized = Data(
        repeating: 0x20,
        count: LocalAgentStatusWireCodecV1.maximumEncodedBytes + 1
    )
    #expect(throws: LocalAgentStatusWireCodecErrorV1.payloadTooLarge) {
        try LocalAgentStatusWireCodecV1.decode(oversized)
    }
}

@Test
func localAgentStatusWireCodecRejectsDuplicateMembers() throws {
    let payload = try LocalAgentStatusWireCodecV1.encode(
        wireStatusSnapshotV1()
    )
    let text = try #require(String(data: payload, encoding: .utf8))
    let duplicate = Data(
        text.replacingOccurrences(
            of: "{\"activeRemoteSessionCount\":1,",
            with: "{\"activeRemoteSessionCount\":1,\"activeRemoteSessionCount\":1,"
        ).utf8
    )

    #expect(throws: LocalAgentStatusWireCodecErrorV1.invalidSnapshot) {
        try LocalAgentStatusWireCodecV1.decode(duplicate)
    }
}
