import CompanionAgent
import CompanionDomain
import CompanionIPC
import CompanionPairing
import CryptoKit
import Foundation
import Testing

private enum LocalReviewServiceProbeErrorV0: Error {
    case injected
}

private actor LocalReviewServiceDecisionAuthorityV0:
    AgentLocalPairingDecisionManagingV0
{
    let clientID: UUID
    private var failNext = false
    private var cancellationCountStorage = 0

    init(clientID: UUID) { self.clientID = clientID }

    func failNextDecision() { failNext = true }
    func cancellationCount() -> Int { cancellationCountStorage }

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
        if failNext {
            failNext = false
            throw LocalReviewServiceProbeErrorV0.injected
        }
        guard approved, let displayName else {
            throw PairingSessionError.approvalRejected
        }
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
        cancellationCountStorage += 1
    }
}

private actor LocalReviewServiceSurfaceV0: LocalPairingReviewSurfaceV0 {
    private var presentedStorage: [LocalPairingReviewV0] = []
    private var withdrawnStorage: [UUID] = []
    private var shouldReject = false
    private var shouldSuspend = false
    private var presentationStarted = false
    private var continuation: CheckedContinuation<Void, Never>?

    func rejectNext() { shouldReject = true }
    func suspendNext() { shouldSuspend = true }
    func presented() -> [LocalPairingReviewV0] { presentedStorage }
    func withdrawn() -> [UUID] { withdrawnStorage }

    func presentLocalPairingReview(
        _ review: LocalPairingReviewV0
    ) async throws {
        presentationStarted = true
        if shouldReject {
            shouldReject = false
            throw LocalReviewServiceProbeErrorV0.injected
        }
        if shouldSuspend {
            shouldSuspend = false
            await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }
        presentedStorage.append(review)
    }

    func withdrawLocalPairingReview(reviewID: UUID) async {
        withdrawnStorage.append(reviewID)
    }

    func waitUntilPresentationStarted() async {
        while !presentationStarted { await Task.yield() }
    }

    func resumePresentation() {
        continuation?.resume()
        continuation = nil
    }
}

private let localReviewServicePairingID = UUID(
    uuidString: "018f4000-0000-7000-8000-0000000000e1"
)!
private let localReviewServiceClientID = UUID(
    uuidString: "018f2000-0000-7000-8000-0000000000e1"
)!
private let localReviewServiceReviewID = UUID(
    uuidString: "018f4300-0000-7000-8000-0000000000e1"
)!
private let localReviewServiceDeviceID = UUID(
    uuidString: "018f2100-0000-7000-8000-0000000000e1"
)!
private let localReviewServiceWall: Int64 = 1_787_198_400_100
private let localReviewServicePolicy = PolicyRevision(rawValue: 7)

private func localReviewServiceContextV0() throws -> PairingApprovalContext {
    let sessionKey = Data([0x04] + Array(repeating: 0x51, count: 64))
    let approvalKey = Data([0x04] + Array(repeating: 0x52, count: 64))
    return try PairingApprovalContext(
        pairingID: localReviewServicePairingID,
        clientID: localReviewServiceClientID,
        sessionPublicKeyX963: sessionKey,
        approvalPublicKeyX963: approvalKey,
        sessionPublicKeyFingerprint: Data(SHA256.hash(data: sessionKey)),
        approvalPublicKeyFingerprint: Data(SHA256.hash(data: approvalKey)),
        transcriptDigest: Data(repeating: 0x53, count: 32),
        authenticationString: "A13-F05",
        expiresAtUnixMilliseconds: localReviewServiceWall + 1_000,
        deadlineMonotonicMilliseconds: 2_000
    )
}

private func localReviewServiceHarnessV0() async throws -> (
    AgentLocalPairingReviewServiceV0,
    AgentLocalPairingDecisionHandlerV0,
    LocalReviewServiceDecisionAuthorityV0,
    LocalReviewServiceSurfaceV0,
    LocalPairingReviewV0
) {
    let authority = LocalReviewServiceDecisionAuthorityV0(
        clientID: localReviewServiceClientID
    )
    let decisions = AgentLocalPairingDecisionHandlerV0(
        authority: authority,
        timeSource: StaticAgentLocalPairingTimeSourceV0(try .init(
            wallNowUnixMilliseconds: localReviewServiceWall,
            monotonicNowMilliseconds: 1_000
        )),
        policySource: StaticAgentLocalPairingPolicySourceV0(
            localReviewServicePolicy
        ),
        makeDeviceID: { localReviewServiceDeviceID }
    )
    let review = try await decisions.registerCurrentPolicyReview(
        localReviewServiceContextV0(),
        reviewID: localReviewServiceReviewID
    )
    let surface = LocalReviewServiceSurfaceV0()
    let service = AgentLocalPairingReviewServiceV0(
        decisions: decisions,
        alreadyAuthorizedSurface: surface
    )
    return (service, decisions, authority, surface, review)
}

private func localReviewServiceCommandV0(
    review: LocalPairingReviewV0,
    commandID: UUID = UUID(),
    name: String = "Jenny's iPhone"
) throws -> LocalPairingDecisionCommandV0 {
    try LocalPairingDecisionCommandV0(
        commandID: commandID,
        review: review,
        deviceDisplayName: DeviceDisplayName(name),
        decision: .approve,
        decidedAtUnixMilliseconds: localReviewServiceWall - 1
    )
}

@Test func localReviewServicePublishesOnlyExactPendingReview() async throws {
    let (service, _, _, surface, review) =
        try await localReviewServiceHarnessV0()

    try await service.publishHostPairingReview(review)
    #expect(await service.visibleReview() == review)
    #expect(await surface.presented() == [review])

    try await service.publishHostPairingReview(review)
    #expect(await surface.presented() == [review])

    let other = try LocalPairingReviewV0(
        reviewID: UUID(),
        pairingID: review.pairingID,
        clientID: review.clientID,
        sessionPublicKeyFingerprint: review.sessionPublicKeyFingerprint,
        approvalPublicKeyFingerprint: review.approvalPublicKeyFingerprint,
        transcriptDigest: review.transcriptDigest,
        authenticationString: review.authenticationString,
        expectedPolicyRevision: review.expectedPolicyRevision,
        expiresAtUnixMilliseconds: review.expiresAtUnixMilliseconds
    )
    await #expect(throws: AgentLocalPairingReviewServiceErrorV0.self) {
        try await service.publishHostPairingReview(other)
    }
    #expect(await service.visibleReview() == review)
}

@Test func localReviewServiceRejectsUnregisteredAndRejectedDelivery() async throws {
    let (service, decisions, _, surface, review) =
        try await localReviewServiceHarnessV0()
    await decisions.cancel(reviewID: review.reviewID)

    await #expect(throws: AgentLocalPairingReviewServiceErrorV0.self) {
        try await service.publishHostPairingReview(review)
    }
    #expect(await surface.presented().isEmpty)

    let second = try await localReviewServiceHarnessV0()
    await second.3.rejectNext()
    await #expect(throws: LocalReviewServiceProbeErrorV0.injected) {
        try await second.0.publishHostPairingReview(second.4)
    }
    #expect(await second.0.visibleReview() == nil)
    #expect(await second.3.withdrawn() == [second.4.reviewID])
}

@Test func localReviewServiceApprovesWithdrawsAndReplaysExactReceipt() async throws {
    let (service, _, _, surface, review) =
        try await localReviewServiceHarnessV0()
    try await service.publishHostPairingReview(review)
    let commandID = UUID()
    let command = try localReviewServiceCommandV0(
        review: review,
        commandID: commandID
    )

    let receipt = try await service.resolveLocalApproval(command)
    try receipt.validate(against: command)
    #expect(receipt.deviceID == localReviewServiceDeviceID)
    #expect(await service.visibleReview() == nil)
    #expect(await surface.withdrawn() == [review.reviewID])
    #expect(try await service.resolveLocalApproval(command) == receipt)

    let changed = try localReviewServiceCommandV0(
        review: review,
        commandID: commandID,
        name: "Changed Name"
    )
    await #expect(
        throws: AgentLocalPairingDecisionHandlerErrorV0.commandMismatch
    ) {
        try await service.resolveLocalApproval(changed)
    }
}

@Test func localReviewServiceRetryableFailureRetainsExactReview() async throws {
    let (service, _, authority, surface, review) =
        try await localReviewServiceHarnessV0()
    try await service.publishHostPairingReview(review)
    let command = try localReviewServiceCommandV0(review: review)
    await authority.failNextDecision()

    await #expect(
        throws: AgentLocalPairingDecisionHandlerErrorV0.authorityUnavailable
    ) {
        try await service.resolveLocalApproval(command)
    }
    #expect(await service.visibleReview() == review)
    #expect(await surface.withdrawn().isEmpty)

    let receipt = try await service.resolveLocalApproval(command)
    try receipt.validate(against: command)
    #expect(await surface.withdrawn() == [review.reviewID])
}

@Test func localReviewServiceWithdrawalFencesSuspendedPublication() async throws {
    let (service, _, _, surface, review) =
        try await localReviewServiceHarnessV0()
    await surface.suspendNext()
    let publication = Task {
        try await service.publishHostPairingReview(review)
    }
    await surface.waitUntilPresentationStarted()
    await service.withdrawHostPairingReview(reviewID: review.reviewID)
    await surface.resumePresentation()

    await #expect(throws: AgentLocalPairingReviewServiceErrorV0.self) {
        try await publication.value
    }
    #expect(await service.visibleReview() == nil)
    #expect(await surface.withdrawn().count == 2)
}

@Test func localReviewServiceEndpointLossCancelsPendingAndStaysClosed() async throws {
    let (service, _, authority, surface, review) =
        try await localReviewServiceHarnessV0()
    try await service.publishHostPairingReview(review)

    await service.invalidate()
    #expect(await service.visibleReview() == nil)
    #expect(await surface.withdrawn() == [review.reviewID])
    #expect(await authority.cancellationCount() == 1)
    await #expect(throws: AgentLocalPairingReviewServiceErrorV0.invalidated) {
        try await service.publishHostPairingReview(review)
    }
}
