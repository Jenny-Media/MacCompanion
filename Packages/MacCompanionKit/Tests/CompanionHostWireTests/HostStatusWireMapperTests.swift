import CompanionHost
import CompanionHostWire
import CompanionWire
@testable import CompanionAuthentication
import Foundation
import Testing

private struct FixedClock: HostStatusClock {
    func nowUnixMilliseconds() -> Int64 { 1_787_198_400_900 }
}

private struct FixedSampler: HostSystemSampling {
    func sample() async throws -> HostSystemMeasurement {
        try HostSystemMeasurement(
            osName: "macOS",
            osVersion: "26.6",
            osBuild: "25G100",
            uptimeSeconds: 86_400,
            cpuUtilizationBasisPoints: 1_250,
            memoryTotalBytes: 34_359_738_368,
            memoryUsedBytes: 12_884_901_888,
            storageTotalBytes: 994_662_584_320,
            storageAvailableBytes: 536_870_912_000,
            powerSource: .ac,
            batteryLevelPercent: nil
        )
    }
}

private actor AcceptingSequenceCommitter: StatusSequenceCommitting {
    func commit(
        expected: StatusSequenceState,
        replacement: StatusSequenceState
    ) async throws {}
}

@Test func hostSnapshotMapsToCorrelatedValidatedWireResponse() async throws {
    let hostID = UUID(uuidString: "018f1000-0000-7000-8000-000000000001")!
    let requestMessageID = UUID(uuidString: "018f0000-0000-7000-8000-000000000003")!
    let authority = try HostStatusAuthority(
        hostID: hostID,
        sequence: StatusSequenceState(
            generation: UUID(uuidString: "018f3000-0000-7000-8000-000000000001")!,
            nextRevision: 42
        ),
        sampler: FixedSampler(),
        clock: FixedClock(),
        sequenceCommitter: AcceptingSequenceCommitter()
    )
    let request = try WireEnvelope(
        messageID: WireUUID(requestMessageID),
        correlationID: nil,
        sentAtUnixMilliseconds: 1_787_198_400_800,
        body: StatusSnapshotRequestBody()
    )
    let snapshot = try await authority.snapshot(hostState: .userSessionActive)

    let response = try HostStatusWireMapper.response(
        for: request,
        snapshot: snapshot,
        responseMessageID: UUID(uuidString: "018f0000-0000-7000-8000-000000000004")!,
        sentAtUnixMilliseconds: 1_787_198_401_000
    )
    let encoded = try WireCodec.encode(response)
    let decoded = try WireCodec.decode(
        WireEnvelope<StatusSnapshotBody>.self,
        from: encoded
    )

    #expect(decoded.correlationID == WireUUID(requestMessageID))
    #expect(decoded.body.hostID == WireUUID(hostID))
    #expect(decoded.body.revision == 42)
    #expect(decoded.body.resourceID == "host.status")
    #expect(decoded.body.system.batteryLevelPercent == nil)
}

@Test func authenticatedPrincipalMapsToSessionDescriptionCorrelatedToProof() throws {
    let proofMessageID = UUID(uuidString: "018f0000-0000-7000-8000-000000001003")!
    let proof = try WireEnvelope(
        messageID: WireUUID(proofMessageID),
        correlationID: WireUUID(UUID(uuidString: "018f0000-0000-7000-8000-000000001002")!),
        sentAtUnixMilliseconds: 1_787_198_400_020,
        body: AuthProofBody(signature: try WireBytes64(Data(repeating: 0, count: 64)))
    )
    let principal = AuthenticatedDevicePrincipal(
        deviceID: UUID(uuidString: "018f2100-0000-7000-8000-000000000001")!,
        clientID: UUID(uuidString: "018f2000-0000-7000-8000-000000000001")!,
        deviceState: .activeMonitorOnly,
        authorizationEpoch: .init(rawValue: 2),
        grantRevision: .init(rawValue: 3),
        policyRevision: .init(rawValue: 4)
    )

    let response = try SessionDescriptionWireMapper.response(
        for: proof,
        principal: principal,
        hostID: UUID(uuidString: "018f1000-0000-7000-8000-000000000001")!,
        hostState: .userSessionActive,
        responseMessageID: UUID(uuidString: "018f0000-0000-7000-8000-000000001004")!,
        sentAtUnixMilliseconds: 1_787_198_400_030
    )

    #expect(response.correlationID == WireUUID(proofMessageID))
    #expect(response.body.deviceState == .activeMonitorOnly)
    #expect(response.body.authorizationEpoch.rawValue == 2)
    #expect(response.body.features == ["audit.readSelf", "status.snapshot"])
}
