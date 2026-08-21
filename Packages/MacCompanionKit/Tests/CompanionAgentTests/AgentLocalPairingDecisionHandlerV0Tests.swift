import CompanionAgent
import CompanionDomain
import CompanionIPC
import CompanionPairing
import CompanionWire
import CryptoKit
import Foundation
import Testing

private enum PairingDecisionProbeErrorV0: Error {
    case injected
}

private final class FailOncePairingDecisionTimeSourceV0:
    AgentLocalPairingTimeSamplingV0,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var shouldFail = true
    private let sample: AgentLocalPairingTimeSampleV0

    init(_ sample: AgentLocalPairingTimeSampleV0) {
        self.sample = sample
    }

    func currentPairingTime() throws -> AgentLocalPairingTimeSampleV0 {
        lock.lock()
        defer { lock.unlock() }
        if shouldFail {
            shouldFail = false
            throw PairingDecisionProbeErrorV0.injected
        }
        return sample
    }
}

private struct PairingDecisionCallV0: Equatable, Sendable {
    let pairingID: UUID
    let transcriptDigest: Data
    let approved: Bool
    let deviceID: UUID
    let displayName: DeviceDisplayName?
    let policyRevision: PolicyRevision
    let wall: Int64
    let monotonic: Int64
}

private struct PairingDecisionCancellationV0: Equatable, Sendable {
    let pairingID: UUID
    let monotonic: Int64
}

private actor PairingDecisionAuthorityProbeV0:
    AgentLocalPairingDecisionManagingV0
{
    private let clientID: UUID
    private var failNext = false
    private var callsStorage: [PairingDecisionCallV0] = []
    private var cancellationsStorage: [PairingDecisionCancellationV0] = []

    init(clientID: UUID) {
        self.clientID = clientID
    }

    func failNextDecision() { failNext = true }
    func calls() -> [PairingDecisionCallV0] { callsStorage }
    func cancellations() -> [PairingDecisionCancellationV0] {
        cancellationsStorage
    }

    func decideLocalPairing(
        pairingID: UUID,
        approvedTranscriptDigest: Data,
        approved: Bool,
        deviceID: UUID,
        displayName: DeviceDisplayName?,
        policyRevision: PolicyRevision,
        wallNowUnixMilliseconds: Int64,
        monotonicNowMilliseconds: Int64
    ) async throws -> CompletedPairing {
        callsStorage.append(.init(
            pairingID: pairingID,
            transcriptDigest: approvedTranscriptDigest,
            approved: approved,
            deviceID: deviceID,
            displayName: displayName,
            policyRevision: policyRevision,
            wall: wallNowUnixMilliseconds,
            monotonic: monotonicNowMilliseconds
        ))
        if failNext {
            failNext = false
            throw PairingDecisionProbeErrorV0.injected
        }
        guard approved else { throw PairingSessionError.approvalRejected }
        guard let displayName else { throw PairingSessionError.invalidInput }
        return CompletedPairing(
            pairingID: pairingID,
            deviceID: deviceID,
            clientID: clientID,
            displayName: displayName,
            policyRevision: policyRevision
        )
    }

    func cancelLocalPairingDecision(
        pairingID: UUID,
        monotonicNowMilliseconds: Int64
    ) async throws {
        cancellationsStorage.append(.init(
            pairingID: pairingID,
            monotonic: monotonicNowMilliseconds
        ))
    }
}

private let pairingDecisionPairingID = UUID(
    uuidString: "018f4000-0000-7000-8000-0000000000d1"
)!
private let pairingDecisionClientID = UUID(
    uuidString: "018f2000-0000-7000-8000-0000000000d1"
)!
private let pairingDecisionReviewID = UUID(
    uuidString: "018f4300-0000-7000-8000-0000000000d1"
)!
private let pairingDecisionDeviceID = UUID(
    uuidString: "018f2100-0000-7000-8000-0000000000d1"
)!
private let pairingDecisionWall: Int64 = 1_787_198_400_100
private let pairingDecisionMonotonic: Int64 = 1_100
private let pairingDecisionPolicy = PolicyRevision(rawValue: 7)

private func pairingDecisionContextV0() throws -> PairingApprovalContext {
    let sessionKey = Data([0x04] + Array(repeating: 0x31, count: 64))
    let approvalKey = Data([0x04] + Array(repeating: 0x32, count: 64))
    return try PairingApprovalContext(
        pairingID: pairingDecisionPairingID,
        clientID: pairingDecisionClientID,
        sessionPublicKeyX963: sessionKey,
        approvalPublicKeyX963: approvalKey,
        sessionPublicKeyFingerprint: Data(SHA256.hash(data: sessionKey)),
        approvalPublicKeyFingerprint: Data(SHA256.hash(data: approvalKey)),
        transcriptDigest: Data(repeating: 0x44, count: 32),
        authenticationString: "23F-6F5",
        expiresAtUnixMilliseconds: pairingDecisionWall + 1_000,
        deadlineMonotonicMilliseconds: pairingDecisionMonotonic + 1_000
    )
}

private func pairingDecisionHandlerV0(
    authority: PairingDecisionAuthorityProbeV0,
    policy: PolicyRevision = pairingDecisionPolicy,
    wall: Int64 = pairingDecisionWall
) throws -> AgentLocalPairingDecisionHandlerV0 {
    AgentLocalPairingDecisionHandlerV0(
        authority: authority,
        timeSource: StaticAgentLocalPairingTimeSourceV0(try .init(
            wallNowUnixMilliseconds: wall,
            monotonicNowMilliseconds: pairingDecisionMonotonic
        )),
        policySource: StaticAgentLocalPairingPolicySourceV0(policy),
        makeDeviceID: { pairingDecisionDeviceID }
    )
}

private func pairingDecisionCommandV0(
    review: LocalPairingReviewV0,
    commandID: UUID = UUID(),
    decision: LocalPairingDecisionV0 = .approve
) throws -> LocalPairingDecisionCommandV0 {
    try LocalPairingDecisionCommandV0(
        commandID: commandID,
        review: review,
        deviceDisplayName: decision == .approve
            ? DeviceDisplayName("Jenny's iPhone")
            : nil,
        decision: decision,
        decidedAtUnixMilliseconds: pairingDecisionWall - 1
    )
}

@Test func localPairingApprovalBindsNameAndPublishesOneOutcome() async throws {
    let authority = PairingDecisionAuthorityProbeV0(
        clientID: pairingDecisionClientID
    )
    let handler = try pairingDecisionHandlerV0(authority: authority)
    let context = try pairingDecisionContextV0()
    let review = try await handler.register(
        context,
        reviewID: pairingDecisionReviewID,
        policyRevision: pairingDecisionPolicy
    )
    #expect(
        review.sessionPublicKeyFingerprint.rawValue
            == context.sessionPublicKeyFingerprint
    )
    #expect(
        review.approvalPublicKeyFingerprint.rawValue
            == context.approvalPublicKeyFingerprint
    )
    let commandID = UUID()
    let command = try pairingDecisionCommandV0(
        review: review,
        commandID: commandID
    )

    let receipt = try await handler.handle(command)
    #expect(receipt.deviceID == pairingDecisionDeviceID)
    #expect(receipt.storedDisplayName == command.deviceDisplayName)
    #expect(try await handler.handle(command) == receipt)
    #expect(await authority.calls().count == 1)
    #expect(await authority.calls().first?.policyRevision == pairingDecisionPolicy)

    guard case let .approved(completed)? = await handler.takeOutcome(
        reviewID: pairingDecisionReviewID
    ) else {
        Issue.record("Expected one approved remote outcome")
        return
    }
    #expect(completed.displayName == command.deviceDisplayName)
    #expect(await handler.takeOutcome(reviewID: pairingDecisionReviewID) == nil)

    let changed = try pairingDecisionCommandV0(
        review: review,
        commandID: commandID,
        decision: .decline
    )
    await #expect(
        throws: AgentLocalPairingDecisionHandlerErrorV0.commandMismatch
    ) {
        _ = try await handler.handle(changed)
    }
}

@Test func localPairingDeclineProducesNoDeviceOrName() async throws {
    let authority = PairingDecisionAuthorityProbeV0(
        clientID: pairingDecisionClientID
    )
    let handler = try pairingDecisionHandlerV0(authority: authority)
    let review = try await handler.register(
        pairingDecisionContextV0(),
        reviewID: pairingDecisionReviewID,
        policyRevision: pairingDecisionPolicy
    )
    let command = try pairingDecisionCommandV0(
        review: review,
        decision: .decline
    )

    let receipt = try await handler.handle(command)

    #expect(receipt.deviceID == nil)
    #expect(receipt.storedDisplayName == nil)
    #expect(await authority.calls().first?.approved == false)
    #expect(
        await handler.takeOutcome(reviewID: pairingDecisionReviewID)
            == .declined
    )
}

@Test func alteredPairingReviewFailsClosedAndCancelsAuthority() async throws {
    let authority = PairingDecisionAuthorityProbeV0(
        clientID: pairingDecisionClientID
    )
    let handler = try pairingDecisionHandlerV0(authority: authority)
    let review = try await handler.register(
        pairingDecisionContextV0(),
        reviewID: pairingDecisionReviewID,
        policyRevision: pairingDecisionPolicy
    )
    let altered = try LocalPairingReviewV0(
        reviewID: review.reviewID,
        pairingID: review.pairingID,
        clientID: review.clientID,
        sessionPublicKeyFingerprint: review.sessionPublicKeyFingerprint,
        approvalPublicKeyFingerprint: review.approvalPublicKeyFingerprint,
        transcriptDigest: WireBytes32(Data(repeating: 0x7f, count: 32)),
        authenticationString: review.authenticationString,
        expectedPolicyRevision: review.expectedPolicyRevision,
        expiresAtUnixMilliseconds: review.expiresAtUnixMilliseconds
    )
    let command = try pairingDecisionCommandV0(review: altered)

    await #expect(
        throws: AgentLocalPairingDecisionHandlerErrorV0.commandMismatch
    ) {
        _ = try await handler.handle(command)
    }
    #expect(await authority.calls().isEmpty)
    #expect(
        await authority.cancellations()
            == [.init(
                pairingID: pairingDecisionPairingID,
                monotonic: pairingDecisionMonotonic
            )]
    )
}

@Test func pairingPolicyDriftAndExpiryNeverReachCommit() async throws {
    let policyAuthority = PairingDecisionAuthorityProbeV0(
        clientID: pairingDecisionClientID
    )
    let policyHandler = try pairingDecisionHandlerV0(
        authority: policyAuthority,
        policy: .init(rawValue: 8)
    )
    let policyReview = try await policyHandler.register(
        pairingDecisionContextV0(),
        reviewID: pairingDecisionReviewID,
        policyRevision: pairingDecisionPolicy
    )
    await #expect(
        throws: AgentLocalPairingDecisionHandlerErrorV0.policyChanged
    ) {
        _ = try await policyHandler.handle(
            pairingDecisionCommandV0(review: policyReview)
        )
    }
    #expect(await policyAuthority.calls().isEmpty)

    let staleAuthority = PairingDecisionAuthorityProbeV0(
        clientID: pairingDecisionClientID
    )
    let context = try pairingDecisionContextV0()
    let staleHandler = try pairingDecisionHandlerV0(
        authority: staleAuthority,
        wall: context.expiresAtUnixMilliseconds
    )
    let staleReview = try await staleHandler.register(
        context,
        reviewID: pairingDecisionReviewID,
        policyRevision: pairingDecisionPolicy
    )
    await #expect(
        throws: AgentLocalPairingDecisionHandlerErrorV0.staleReview
    ) {
        _ = try await staleHandler.handle(
            pairingDecisionCommandV0(review: staleReview)
        )
    }
    #expect(await staleAuthority.calls().isEmpty)
}

@Test func pairingDurableFailureRestoresExactReviewForRetry() async throws {
    let authority = PairingDecisionAuthorityProbeV0(
        clientID: pairingDecisionClientID
    )
    await authority.failNextDecision()
    let handler = try pairingDecisionHandlerV0(authority: authority)
    let review = try await handler.register(
        pairingDecisionContextV0(),
        reviewID: pairingDecisionReviewID,
        policyRevision: pairingDecisionPolicy
    )
    let command = try pairingDecisionCommandV0(review: review)

    await #expect(
        throws: AgentLocalPairingDecisionHandlerErrorV0.authorityUnavailable
    ) {
        _ = try await handler.handle(command)
    }
    let receipt = try await handler.handle(command)
    #expect(receipt.deviceID == pairingDecisionDeviceID)
    #expect(await authority.calls().count == 2)
}

@Test func pairingClockFailureRestoresExactReviewForRetry() async throws {
    let authority = PairingDecisionAuthorityProbeV0(
        clientID: pairingDecisionClientID
    )
    let timeSource = FailOncePairingDecisionTimeSourceV0(try .init(
        wallNowUnixMilliseconds: pairingDecisionWall,
        monotonicNowMilliseconds: pairingDecisionMonotonic
    ))
    let handler = AgentLocalPairingDecisionHandlerV0(
        authority: authority,
        timeSource: timeSource,
        policySource: StaticAgentLocalPairingPolicySourceV0(
            pairingDecisionPolicy
        ),
        makeDeviceID: { pairingDecisionDeviceID }
    )
    let review = try await handler.register(
        pairingDecisionContextV0(),
        reviewID: pairingDecisionReviewID,
        policyRevision: pairingDecisionPolicy
    )
    let command = try pairingDecisionCommandV0(review: review)

    await #expect(
        throws: AgentLocalPairingDecisionHandlerErrorV0.invalidClock
    ) {
        _ = try await handler.handle(command)
    }
    let receipt = try await handler.handle(command)
    #expect(receipt.deviceID == pairingDecisionDeviceID)
    #expect(await authority.calls().count == 1)
}
