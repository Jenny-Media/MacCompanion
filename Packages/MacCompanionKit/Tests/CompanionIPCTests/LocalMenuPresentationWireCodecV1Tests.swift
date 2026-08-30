import CompanionDomain
import CompanionIPC
import CompanionWire
import Foundation
import Testing

private let menuPresentationReviewIDV1 = UUID(
    uuidString: "018f4300-0000-7000-8000-0000000000c1"
)!
private let menuPresentationPairingIDV1 = UUID(
    uuidString: "018f4000-0000-7000-8000-0000000000c1"
)!
private let menuPresentationClientIDV1 = UUID(
    uuidString: "018f2000-0000-7000-8000-0000000000c1"
)!
private let menuPresentationRecoveryReviewIDV1 = UUID(
    uuidString: "018f7100-0000-7000-8000-0000000000c1"
)!
private let menuPresentationHostIDV1 = UUID(
    uuidString: "018f1000-0000-7000-8000-0000000000c1"
)!

private func menuPresentationPairingReviewV1()
    throws -> LocalPairingReviewV0
{
    try LocalPairingReviewV0(
        reviewID: menuPresentationReviewIDV1,
        pairingID: menuPresentationPairingIDV1,
        clientID: menuPresentationClientIDV1,
        sessionPublicKeyFingerprint: WireFingerprint(
            Data(repeating: 0x31, count: 32)
        ),
        approvalPublicKeyFingerprint: WireFingerprint(
            Data(repeating: 0x32, count: 32)
        ),
        transcriptDigest: WireBytes32(Data(repeating: 0x33, count: 32)),
        authenticationString: PairingAuthenticationString("23F-6F5"),
        expectedPolicyRevision: PolicyRevision(rawValue: 7),
        expiresAtUnixMilliseconds: 1_787_198_700_000
    )
}

private func menuPresentationRecoveryReviewV1()
    throws -> LocalHostIdentityRecoveryReviewV0
{
    try LocalHostIdentityRecoveryReviewV0(
        reviewID: menuPresentationRecoveryReviewIDV1,
        hostID: menuPresentationHostIDV1,
        hostFingerprint: WireFingerprint(Data(repeating: 0x41, count: 32)),
        cause: .userRequestedReset,
        createdAtUnixMilliseconds: 1_787_198_400_000,
        expiresAtUnixMilliseconds: 1_787_198_700_000
    )
}

private func menuPresentationRecoveryResumeV1()
    throws -> LocalHostIdentityRecoveryCommandV0
{
    try LocalHostIdentityRecoveryCommandV0(
        commandID: UUID(
            uuidString: "018f7200-0000-7000-8000-0000000000c1"
        )!,
        recoveryID: UUID(
            uuidString: "018f7300-0000-7000-8000-0000000000c1"
        )!,
        review: menuPresentationRecoveryReviewV1(),
        confirmedAtUnixMilliseconds: 1_787_198_400_001
    )
}

@Test
func localMenuPresentationCodecRoundTripsAllClosedPayloads() throws {
    let pairing = try menuPresentationPairingReviewV1()
    let pairingBytes = try LocalMenuPresentationWireCodecV1
        .encodePairingReview(pairing)
    #expect(try CanonicalJSON.canonicalize(pairingBytes) == pairingBytes)
    #expect(
        try LocalMenuPresentationWireCodecV1
            .decodePairingReview(pairingBytes) == pairing
    )

    let recovery = try menuPresentationRecoveryReviewV1()
    let recoveryBytes = try LocalMenuPresentationWireCodecV1
        .encodeHostIdentityRecoveryReview(recovery)
    #expect(try CanonicalJSON.canonicalize(recoveryBytes) == recoveryBytes)
    #expect(
        try LocalMenuPresentationWireCodecV1
            .decodeHostIdentityRecoveryReview(recoveryBytes) == recovery
    )

    let resume = try menuPresentationRecoveryResumeV1()
    let resumeBytes = try LocalMenuPresentationWireCodecV1
        .encodeHostIdentityRecoveryResume(resume)
    #expect(try CanonicalJSON.canonicalize(resumeBytes) == resumeBytes)
    #expect(
        try LocalMenuPresentationWireCodecV1
            .decodeHostIdentityRecoveryResume(resumeBytes) == resume
    )

    #expect(pairingBytes.count <= 4_096)
    #expect(recoveryBytes.count <= 4_096)
    #expect(resumeBytes.count <= 4_096)
}

@Test
func localMenuPresentationCodecRejectsCrossKindPayloadSubstitution() throws {
    let pairingBytes = try LocalMenuPresentationWireCodecV1
        .encodePairingReview(menuPresentationPairingReviewV1())
    let recoveryBytes = try LocalMenuPresentationWireCodecV1
        .encodeHostIdentityRecoveryReview(
            menuPresentationRecoveryReviewV1()
        )
    let resumeBytes = try LocalMenuPresentationWireCodecV1
        .encodeHostIdentityRecoveryResume(
            menuPresentationRecoveryResumeV1()
        )

    #expect(throws: LocalMenuPresentationWireCodecErrorV1.invalidPayload) {
        try LocalMenuPresentationWireCodecV1
            .decodeHostIdentityRecoveryReview(pairingBytes)
    }
    #expect(throws: LocalMenuPresentationWireCodecErrorV1.invalidPayload) {
        try LocalMenuPresentationWireCodecV1
            .decodeHostIdentityRecoveryResume(pairingBytes)
    }
    #expect(throws: LocalMenuPresentationWireCodecErrorV1.invalidPayload) {
        try LocalMenuPresentationWireCodecV1.decodePairingReview(
            recoveryBytes
        )
    }
    #expect(throws: LocalMenuPresentationWireCodecErrorV1.invalidPayload) {
        try LocalMenuPresentationWireCodecV1
            .decodeHostIdentityRecoveryResume(recoveryBytes)
    }
    #expect(throws: LocalMenuPresentationWireCodecErrorV1.invalidPayload) {
        try LocalMenuPresentationWireCodecV1.decodePairingReview(resumeBytes)
    }
    #expect(throws: LocalMenuPresentationWireCodecErrorV1.invalidPayload) {
        try LocalMenuPresentationWireCodecV1
            .decodeHostIdentityRecoveryReview(resumeBytes)
    }
}

@Test
func localMenuPresentationCodecRejectsOpenAndDuplicatePayloads() throws {
    let payload = try LocalMenuPresentationWireCodecV1
        .encodePairingReview(menuPresentationPairingReviewV1())
    guard case let .object(members) = try CanonicalJSON.parse(payload) else {
        Issue.record("pairing presentation payload was not an object")
        return
    }
    let open = CanonicalJSON.canonicalData(
        for: .object(
            members + [
                CanonicalJSONMember(
                    key: "unexpected",
                    value: .boolean(true)
                )
            ]
        )
    )
    #expect(throws: LocalMenuPresentationWireCodecErrorV1.invalidPayload) {
        try LocalMenuPresentationWireCodecV1.decodePairingReview(open)
    }

    let text = try #require(String(data: payload, encoding: .utf8))
    let duplicate = Data(
        text.replacingOccurrences(
            of: "{\"approvalPublicKeyFingerprint\":",
            with:
                "{\"approvalPublicKeyFingerprint\":\"" +
                String(repeating: "A", count: 43) +
                "\",\"approvalPublicKeyFingerprint\":"
        ).utf8
    )
    #expect(throws: LocalMenuPresentationWireCodecErrorV1.invalidPayload) {
        try LocalMenuPresentationWireCodecV1.decodePairingReview(duplicate)
    }
}

@Test
func localMenuPresentationCodecRejectsNoncanonicalAndBoundViolations()
    throws
{
    let payload = try LocalMenuPresentationWireCodecV1
        .encodePairingReview(menuPresentationPairingReviewV1())
    let padded = Data([0x20]) + payload
    #expect(
        throws: LocalMenuPresentationWireCodecErrorV1.nonCanonicalPayload
    ) {
        try LocalMenuPresentationWireCodecV1.decodePairingReview(padded)
    }
    #expect(throws: LocalMenuPresentationWireCodecErrorV1.emptyPayload) {
        try LocalMenuPresentationWireCodecV1.decodePairingReview(Data())
    }
    let oversized = Data(
        repeating: 0x20,
        count: LocalMenuPresentationWireCodecV1.maximumEncodedBytes + 1
    )
    #expect(throws: LocalMenuPresentationWireCodecErrorV1.payloadTooLarge) {
        try LocalMenuPresentationWireCodecV1
            .decodePairingReview(oversized)
    }
}

@Test
func localMenuPresentationWithdrawalRequiresAnExactNonzeroReviewID() throws {
    let pairing = try LocalMenuPresentationWireCodecV1.validateWithdrawal(
        reviewID: menuPresentationReviewIDV1
    )
    let recovery = try LocalMenuPresentationWireCodecV1.validateWithdrawal(
        reviewID: menuPresentationRecoveryReviewIDV1
    )
    #expect(pairing.reviewID == menuPresentationReviewIDV1)
    #expect(recovery.reviewID == menuPresentationRecoveryReviewIDV1)

    let zero = UUID(uuid: (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    ))
    #expect(throws: LocalMenuPresentationWireCodecErrorV1.invalidWithdrawal) {
        try LocalMenuPresentationWireCodecV1.validateWithdrawal(
            reviewID: zero
        )
    }
}

@Test
func authoritativeMenuPresentationFixtureMatchesTheClosedCodeContract()
    throws
{
    var repository = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 {
        repository.deleteLastPathComponent()
    }
    let fixtureURL = repository
        .appendingPathComponent("spec/fixtures")
        .appendingPathComponent("local-xpc-menu-presentation-v0.1.json")
    let object = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL))
            as? [String: Any]
    )
    #expect(
        object["maximumPayloadBytes"] as? Int
            == LocalMenuPresentationWireCodecV1.maximumEncodedBytes
    )
    #expect(object["maximumAdmittedRequestsPerGeneration"] as? Int == 8)
    #expect(object["receiverOperationTimeoutMilliseconds"] as? Int == 2_000)
    #expect(object["senderReplyTimeoutMilliseconds"] as? Int == 3_000)
    let recovery = try #require(object["endpointFailureRecovery"] as? [String: Any])
    #expect(recovery["scope"] as? String == "exactAuthenticatedGeneration")
    #expect(recovery["freshGenerationWaitsForRetirementAndProductLoss"] as? Bool == true)
    #expect(recovery["explicitRouterShutdownIsPermanent"] as? Bool == true)
    #expect(
        object["recoverablePublishRejectionProof"] as? String
            == "rejectedWithoutRetainedState"
    )
    let requests = try #require(
        object["requests"] as? [[String: Any]]
    )
    let methods = Set(
        try requests.map {
            try #require($0["authorizationMethod"] as? String)
        }
    )
    #expect(methods == Set([
        LocalIPCMethod.publishPairingReview.rawValue,
        LocalIPCMethod.withdrawPairingReview.rawValue,
        LocalIPCMethod.publishHostIdentityRecoveryReview.rawValue,
        LocalIPCMethod.publishHostIdentityRecoveryResume.rawValue,
        LocalIPCMethod.withdrawHostIdentityRecovery.rawValue,
    ]))
    #expect(requests.count == 5)

    let withdrawalReplies = try requests
        .filter {
            ($0["authorizationMethod"] as? String)?.hasPrefix("withdraw")
                == true
        }
        .map { try #require($0["allowedReplies"] as? [String]) }
    #expect(withdrawalReplies.count == 2)
    #expect(withdrawalReplies.allSatisfy { $0.count == 1 })

    let payloadTypes = Set(
        requests.compactMap { $0["payloadType"] as? String }
    )
    #expect(payloadTypes == Set([
        "LocalPairingReviewV0",
        "LocalHostIdentityRecoveryReviewV0",
        "LocalHostIdentityRecoveryCommandV0",
    ]))
}
