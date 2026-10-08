#if os(macOS)
import CompanionAgentNetworkPlatform
@testable import CompanionAgentProductPlatform
import CompanionDomain
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionLocalXPCPlatform
@testable import CompanionNetworkPlatform
import CompanionSecurity
import CompanionTransport
import CompanionWire
import CryptoKit
import Foundation
import Testing

private actor InteractiveRoleDataInputSenderV1:
    MacLocalXPCInteractiveInputSendingV1
{
    private(set) var values: [InteractiveInputEnvelope] = []

    func applyInteractiveInput(
        _ envelope: InteractiveInputEnvelope
    ) {
        values.append(envelope)
    }
}

private actor InteractiveRoleDataCompletionV1 {
    private(set) var completed = false
    func complete() { completed = true }
}

private func interactiveRoleDataPairV1(
    sessionID: UUID,
    epoch: AuthorizationEpoch
) throws -> AgentInteractiveReadyRolePairV0 {
    func connection(
        role: InteractiveChannelRoleName
    ) throws -> NetworkHostInteractiveReadyRoleConnectionV0 {
        let key = P256.Signing.PrivateKey()
        let spki = try CompanionSecurityV0.p256SubjectPublicKeyInfoDER(
            publicKeyX963: key.publicKey.x963Representation
        )
        let binding = try HostApplicationTLSBinding(
            evidence: HostTLSListenerEvidence(
                negotiatedTLSMajor: 1,
                negotiatedTLSMinor: 3,
                earlyDataAccepted: false,
                servedSubjectPublicKeyInfoDER: spki
            ),
            requiredHostFingerprint: CompanionSecurityV0.hostFingerprint(
                subjectPublicKeyInfoDER: spki
            )
        )
        let channel = HostInteractiveReadyRoleChannelV0(hello:
            try InteractiveChannelHelloBody(
                channelID: WireUUID(UUID()),
                role: role,
                clientID: WireUUID(UUID(uuidString:
                    "11111111-1111-4111-8111-111111111111"
                )!),
                primaryConnectionID: try WireBytes16(
                    Data(repeating: 1, count: 16)
                ),
                interactiveSessionID: WireUUID(sessionID),
                authorizationEpoch: epoch,
                clientNonce: try WireBytes32(Data(repeating: 2, count: 32))
            )
        )
        return NetworkHostInteractiveReadyRoleConnectionV0(
            tlsBinding: binding,
            channel: channel,
            receive: { _ in
                NetworkHostInteractiveRoleTrafficChunkV0(
                    data: Data(),
                    isComplete: true
                )
            },
            send: { _ in },
            cancel: {}
        )
    }
    return try AgentInteractiveReadyRolePairV0(
        input: connection(role: .input),
        media: connection(role: .media)
    )
}

@available(macOS 26.0, *)
@Test func localXPCInteractiveRoleDataRouteRendezvousAndInputAreFenced()
    async throws
{
    let generation: UInt64 = 7
    let sessionID = UUID()
    let epoch = AuthorizationEpoch(rawValue: 4)
    let surfaceID = UUID()
    let pair = try interactiveRoleDataPairV1(
        sessionID: sessionID,
        epoch: epoch
    )
    let sender = InteractiveRoleDataInputSenderV1()
    let route = MacLocalXPCInteractiveRoleDataRouteV1()
    try await route.bind(generation: generation, input: sender)

    let envelope = try InteractiveInputEnvelope(
        messageID: WireUUID(UUID()),
        interactiveSessionID: WireUUID(sessionID),
        authorizationEpoch: epoch,
        sequence: 1,
        clientMonotonicMilliseconds: 1,
        surfaceID: WireUUID(surfaceID),
        surfaceRevision: SurfaceRevision(rawValue: 1),
        coordinateSpaceRevision: CoordinateSpaceRevision(rawValue: 1),
        input: .reset
    )
    try await route.applyInteractiveInput(
        envelope,
        pair: pair,
        nowMonotonicNanoseconds: 1
    )
    #expect(await sender.values == [envelope])

    let header = try MediaRecordHeader(
        type: .discontinuity,
        payloadLength: 0,
        interactiveSessionID: sessionID,
        authorizationEpoch: epoch,
        surfaceID: surfaceID,
        surfaceRevision: SurfaceRevision(rawValue: 1),
        coordinateSpaceRevision: CoordinateSpaceRevision(rawValue: 1),
        mediaSequence: 1,
        presentationTimeNanoseconds: 0,
        encodedWidth: 0,
        encodedHeight: 0
    )
    let completion = InteractiveRoleDataCompletionV1()
    let publication = Task {
        try await route.publishInteractiveMedia(
            header: header,
            payload: Data(),
            transportGeneration: generation
        )
        await completion.complete()
    }
    await Task.yield()
    #expect(!(await completion.completed))

    let received = try #require(
        try await route.nextInteractiveMediaRecord(pair: pair)
    )
    try await publication.value
    #expect(await completion.completed)
    #expect(received.header == header)
    #expect(received.payload.isEmpty)

    await route.invalidate(generation: generation)
    await #expect(throws:
        MacLocalXPCInteractiveRoleDataRouteErrorV1.staleGeneration
    ) {
        try await route.applyInteractiveInput(
            envelope,
            pair: pair,
            nowMonotonicNanoseconds: 2
        )
    }
}

@available(macOS 26.0, *)
@Test func localXPCInteractiveRoleDataRendezvousCancellationNeverHangs()
    async throws
{
    let sessionID = UUID()
    let epoch = AuthorizationEpoch(rawValue: 2)
    let pair = try interactiveRoleDataPairV1(
        sessionID: sessionID,
        epoch: epoch
    )
    let route = MacLocalXPCInteractiveRoleDataRouteV1()
    try await route.bind(
        generation: 9,
        input: InteractiveRoleDataInputSenderV1()
    )
    let header = try MediaRecordHeader(
        type: .end,
        payloadLength: 0,
        interactiveSessionID: sessionID,
        authorizationEpoch: epoch,
        surfaceID: UUID(),
        surfaceRevision: SurfaceRevision(rawValue: 1),
        coordinateSpaceRevision: CoordinateSpaceRevision(rawValue: 1),
        mediaSequence: 1,
        presentationTimeNanoseconds: 0,
        encodedWidth: 0,
        encodedHeight: 0
    )
    let publication = Task {
        try await route.publishInteractiveMedia(
            header: header,
            payload: Data(),
            transportGeneration: 9
        )
    }
    publication.cancel()
    await #expect(throws: CancellationError.self) {
        try await publication.value
    }

    let consumer = Task {
        try await route.nextInteractiveMediaRecord(pair: pair)
    }
    consumer.cancel()
    await #expect(throws: CancellationError.self) {
        _ = try await consumer.value
    }
}

private func retirementMediaHeader(_ pair: AgentInteractiveReadyRolePairV0) throws -> MediaRecordHeader {
    try .init(type: .discontinuity, payloadLength: 0,
        interactiveSessionID: pair.interactiveSessionID, authorizationEpoch: pair.authorizationEpoch,
        surfaceID: UUID(), surfaceRevision: .init(rawValue: 1), coordinateSpaceRevision: .init(rawValue: 1),
        mediaSequence: 1, presentationTimeNanoseconds: 0, encodedWidth: 0, encodedHeight: 0)
}

@available(macOS 26.0, *)
@Test func retiredRoleMediaIsDischargedWithoutReachingReplacementPair() async throws {
    let route = MacLocalXPCInteractiveRoleDataRouteV1()
    try await route.bind(generation: 1, input: InteractiveRoleDataInputSenderV1())
    let old = try interactiveRoleDataPairV1(sessionID: UUID(), epoch: .init(rawValue: 1))
    let fresh = try interactiveRoleDataPairV1(sessionID: UUID(), epoch: .init(rawValue: 1))
    let oldHeader = try retirementMediaHeader(old), freshHeader = try retirementMediaHeader(fresh)
    // Establish the exact old source, then put its next publication in flight.
    let first = Task { try await route.nextInteractiveMediaRecord(pair: old) }
    try await route.publishInteractiveMedia(header: oldHeader, payload: Data(), transportGeneration: 1)
    _ = try await first.value
    let pending = Task { try await route.publishInteractiveMedia(header: oldHeader, payload: Data(), transportGeneration: 1) }
    try await Task.sleep(for: .milliseconds(20))
    await route.retireInteractiveMedia(pair: old)
    try await pending.value
    let completion = InteractiveRoleDataCompletionV1()
    let replacement = Task {
        let record = try await route.nextInteractiveMediaRecord(pair: fresh)
        await completion.complete()
        return record
    }
    try await Task.sleep(for: .milliseconds(20))
    try await route.publishInteractiveMedia(header: oldHeader, payload: Data(), transportGeneration: 1)
    await route.retireInteractiveMedia(pair: old)
    #expect(!(await completion.completed))
    let foreign = try interactiveRoleDataPairV1(sessionID: UUID(), epoch: .init(rawValue: 1))
    await #expect(throws: MacLocalXPCInteractiveRoleDataRouteErrorV1.pairMismatch) {
        try await route.publishInteractiveMedia(header: retirementMediaHeader(foreign), payload: Data(), transportGeneration: 1)
    }
    try await route.publishInteractiveMedia(header: freshHeader, payload: Data(), transportGeneration: 1)
    #expect(try await replacement.value?.header == freshHeader)
    await route.invalidate(generation: 1)
}

@available(macOS 26.0, *)
@Test func menuGenerationReplacementClearsRetiredMediaExceptions() async throws {
    let route = MacLocalXPCInteractiveRoleDataRouteV1()
    let input = InteractiveRoleDataInputSenderV1()
    try await route.bind(generation: 1, input: input)
    let old = try interactiveRoleDataPairV1(sessionID: UUID(), epoch: .init(rawValue: 1))
    let oldHeader = try retirementMediaHeader(old)
    let first = Task { try await route.nextInteractiveMediaRecord(pair: old) }
    try await route.publishInteractiveMedia(header: oldHeader, payload: Data(), transportGeneration: 1)
    _ = try await first.value
    await route.retireInteractiveMedia(pair: old)
    await route.invalidate(generation: 1)
    try await route.bind(generation: 2, input: input)
    let fresh = try interactiveRoleDataPairV1(sessionID: UUID(), epoch: .init(rawValue: 2))
    let freshHeader = try retirementMediaHeader(fresh)
    let replacement = Task { try await route.nextInteractiveMediaRecord(pair: fresh) }
    try await Task.sleep(for: .milliseconds(20))
    await route.retireInteractiveMedia(pair: old)
    await #expect(throws: MacLocalXPCInteractiveRoleDataRouteErrorV1.pairMismatch) {
        try await route.publishInteractiveMedia(header: oldHeader, payload: Data(), transportGeneration: 2)
    }
    try await route.publishInteractiveMedia(header: freshHeader, payload: Data(), transportGeneration: 2)
    #expect(try await replacement.value?.header == freshHeader)
    await route.invalidate(generation: 2)
}

#endif
