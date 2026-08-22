@testable import CompanionLocalXPCPlatform
import CompanionIPC
import Foundation
import Testing

@Test
@available(macOS 26.0, *)
func exactMessageParserRejectsAlternateScalarTypesAndOpenDictionaries() {
    #expect(MacLocalXPCExactMessageParserValidationV1.selfTest())
    #expect(
        MacLocalXPCStatusWireV1.maximumPayloadBytes
            == LocalAgentStatusWireCodecV1.maximumEncodedBytes
    )
    #expect(
        MacLocalXPCMenuPresentationWireV1.maximumPayloadBytes
            == LocalMenuPresentationWireCodecV1.maximumEncodedBytes
    )
    #expect(
        MacLocalXPCRemoteAccessBootstrapWireV1.maximumPayloadBytes
            == LocalRemoteAccessBootstrapWireCodecV1.maximumEncodedBytes
    )
}

@Test
@available(macOS 26.0, *)
func menuPresentationRequestKindsBindOnlyTheirClosedAuthorizationMethods() {
    let reviewID = UUID(
        uuidString: "018f4300-0000-7000-8000-0000000000c1"
    )!
    #expect(
        MacLocalXPCMenuPresentationRequestV1.pairingReview(Data([1]))
            .authorizationMethod == .publishPairingReview
    )
    #expect(
        MacLocalXPCMenuPresentationRequestV1.pairingWithdrawal(reviewID)
            .authorizationMethod == .withdrawPairingReview
    )
    #expect(
        MacLocalXPCMenuPresentationRequestV1.hostRecoveryReview(Data([2]))
            .authorizationMethod == .publishHostIdentityRecoveryReview
    )
    #expect(
        MacLocalXPCMenuPresentationRequestV1.hostRecoveryResume(Data([3]))
            .authorizationMethod == .publishHostIdentityRecoveryResume
    )
    #expect(
        MacLocalXPCMenuPresentationRequestV1.hostRecoveryWithdrawal(reviewID)
            .authorizationMethod == .withdrawHostIdentityRecovery
    )
}

@Test
@available(macOS 26.0, *)
func menuPresentationWireCopiesAllBorrowedPayloadKindsBeforeReturn() throws {
    for (kind, expected) in [
        (
            MacLocalXPCMenuPresentationPayloadKindV1.pairingReview,
            MacLocalXPCMenuPresentationRequestV1.pairingReview(Data([1, 2]))
        ),
        (
            .hostRecoveryReview,
            .hostRecoveryReview(Data([1, 2]))
        ),
        (
            .hostRecoveryResume,
            .hostRecoveryResume(Data([1, 2]))
        ),
    ] {
        var source: [UInt8] = [1, 2]
        let copied = source.withUnsafeBufferPointer { buffer in
            MacLocalXPCMenuPresentationWireV1.copyBorrowedPayload(
                try! #require(buffer.baseAddress),
                count: buffer.count,
                kind: kind
            )
        }
        source[0] = 9
        #expect(copied == expected)
    }

    let one = [UInt8](repeating: 1, count: 1)
    let empty = one.withUnsafeBufferPointer { buffer in
        MacLocalXPCMenuPresentationWireV1.copyBorrowedPayload(
            try! #require(buffer.baseAddress),
            count: 0,
            kind: .pairingReview
        )
    }
    #expect(empty == nil)
    let oversized = [UInt8](
        repeating: 1,
        count: MacLocalXPCMenuPresentationWireV1.maximumPayloadBytes + 1
    )
    let tooLarge = oversized.withUnsafeBufferPointer { buffer in
        MacLocalXPCMenuPresentationWireV1.copyBorrowedPayload(
            try! #require(buffer.baseAddress),
            count: buffer.count,
            kind: .pairingReview
        )
    }
    #expect(tooLarge == nil)
}

@Test
@available(macOS 26.0, *)
func menuPresentationWireCopiesExactBorrowedWithdrawalUUIDs() throws {
    let expected = UUID(
        uuidString: "018f4300-0000-7000-8000-0000000000c1"
    )!
    var source = withUnsafeBytes(of: expected.uuid) { Array($0) }
    let pairing = source.withUnsafeBufferPointer { buffer in
        MacLocalXPCMenuPresentationWireV1.copyBorrowedWithdrawal(
            try! #require(buffer.baseAddress),
            count: buffer.count,
            kind: .pairing
        )
    }
    let recovery = source.withUnsafeBufferPointer { buffer in
        MacLocalXPCMenuPresentationWireV1.copyBorrowedWithdrawal(
            try! #require(buffer.baseAddress),
            count: buffer.count,
            kind: .hostRecovery
        )
    }
    source[0] = 9
    #expect(pairing == .pairingWithdrawal(expected))
    #expect(recovery == .hostRecoveryWithdrawal(expected))

    let zero = [UInt8](repeating: 0, count: 17)
    for count in [15, 16, 17] {
        let copied = zero.withUnsafeBufferPointer { buffer in
            MacLocalXPCMenuPresentationWireV1.copyBorrowedWithdrawal(
                try! #require(buffer.baseAddress),
                count: count,
                kind: .pairing
            )
        }
        #expect(copied == nil)
    }
}

@Test
@available(macOS 26.0, *)
func productionMenuPresentationBuildersTraverseTheExactCopyParser() {
    let reviewID = UUID(
        uuidString: "018f4300-0000-7000-8000-0000000000c1"
    )!
    for request in [
        MacLocalXPCMenuPresentationRequestV1.pairingReview(Data([1, 2])),
        .pairingWithdrawal(reviewID),
        .hostRecoveryReview(Data([3, 4])),
        .hostRecoveryResume(Data([5, 6])),
        .hostRecoveryWithdrawal(reviewID),
    ] {
        #expect(
            MacLocalXPCMenuPresentationWireV1
                .copyExactConstructedRequest(request) == request
        )
    }
}

@Test
func delayedOldCancelCallbackCannotInvalidateRestartedClientGeneration() {
    var gate = MacLocalXPCClientGenerationGateV1()
    let old = gate.begin()
    #expect(old == 1)
    let oldInvalidation = gate.invalidate(generation: 1)
    #expect(oldInvalidation)
    let replacement = gate.begin()
    #expect(replacement == 2)

    let lateInvalidation = gate.invalidate(generation: 1)
    #expect(!lateInvalidation)
    #expect(gate.currentGeneration == 2)
    #expect(gate.admitsCallback(generation: 2))
}

@Test
func delayedOldHelloReplyCannotAuthenticateRestartedClientGeneration() {
    var gate = MacLocalXPCClientGenerationGateV1()
    _ = gate.begin()
    let oldInvalidation = gate.invalidate(generation: 1)
    #expect(oldInvalidation)
    _ = gate.begin()

    #expect(!gate.admitsCallback(generation: 1))
    #expect(gate.admitsCallback(generation: 2))
    #expect(gate.currentGeneration == 2)
}

@Test
func delayedOldReadyReplyCannotPublishForRestartedClientGeneration() {
    var gate = MacLocalXPCClientGenerationGateV1()
    _ = gate.begin()
    let oldInvalidation = gate.invalidate(generation: 1)
    #expect(oldInvalidation)
    _ = gate.begin()

    #expect(!gate.admitsCallback(generation: 1))
    #expect(gate.admitsCallback(generation: 2))
    #expect(gate.currentGeneration == 2)
}

@Test
func menuLifecycleAndStatusAreExplicitServerProfiles() {
    #expect(
        !MacLocalXPCServerProfileV1.authenticationOnly
            .admitsMenuLifecycleReadiness
    )
    #expect(
        !MacLocalXPCServerProfileV1.authenticationOnly
            .admitsAgentStatus
    )
    #expect(
        MacLocalXPCServerProfileV1.menuLifecycleReadiness
            .admitsMenuLifecycleReadiness
    )
    #expect(
        !MacLocalXPCServerProfileV1.menuLifecycleReadiness
            .admitsAgentStatus
    )
    #expect(
        MacLocalXPCServerProfileV1.menuLifecycleReadinessAndStatus
            .admitsMenuLifecycleReadiness
    )
    #expect(
        MacLocalXPCServerProfileV1.menuLifecycleReadinessAndStatus
            .admitsAgentStatus
    )
}

@Test
func statusTransactionCoversAdmissionSuccessUnavailableAndRecovery() throws {
    var gate = MacLocalXPCStatusReadTransactionGateV1()

    let bound = gate.bind(generation: 11)
    #expect(bound)
    let premature = gate.begin(generation: 11, permitted: false)
    #expect(premature == nil)

    let success = gate.begin(generation: 11, permitted: true)
    #expect(success == 1)
    let concurrent = gate.begin(generation: 11, permitted: true)
    #expect(concurrent == nil)
    let successOperation = try #require(success)
    let completedSuccess = gate.finish(
        generation: 11,
        operation: successOperation
    )
    #expect(completedSuccess)

    let unavailable = gate.begin(generation: 11, permitted: true)
    #expect(unavailable == 2)
    let unavailableOperation = try #require(unavailable)
    let completedUnavailable = gate.finish(
        generation: 11,
        operation: unavailableOperation
    )
    #expect(completedUnavailable)
    let recovery = gate.begin(generation: 11, permitted: true)
    #expect(recovery == 3)
}

@Test
func statusTimeoutAndReplacementFenceLateCompletion() throws {
    var gate = MacLocalXPCStatusReadTransactionGateV1()
    let boundOld = gate.bind(generation: 4)
    #expect(boundOld)
    let timedOutCandidate = gate.begin(
        generation: 4,
        permitted: true
    )
    let timedOut = try #require(timedOutCandidate)
    let invalidatedOld = gate.invalidate(generation: 4)
    #expect(invalidatedOld)
    let lateCompletion = gate.finish(
        generation: 4,
        operation: timedOut
    )
    #expect(!lateCompletion)

    let boundReplacement = gate.bind(generation: 5)
    #expect(boundReplacement)
    let replacementCandidate = gate.begin(
        generation: 5,
        permitted: true
    )
    let replacement = try #require(replacementCandidate)
    #expect(!gate.admits(generation: 4, operation: timedOut))
    let staleInvalidation = gate.invalidate(generation: 4)
    #expect(!staleInvalidation)
    #expect(gate.admits(generation: 5, operation: replacement))
}

private final class StatusRequestOwnershipCounterV1:
    @unchecked Sendable
{
    private(set) var retains = 0
    private(set) var releases = 0

    func retain(_: Int) {
        retains += 1
    }

    func release(_: Int) {
        releases += 1
    }
}

@Test
@available(macOS 26.0, *)
func statusRequestLeaseReleasesExactlyOnceOnEveryTerminalPath() {
    let counter = StatusRequestOwnershipCounterV1()
    do {
        let lease = MacLocalXPCStatusRequestLeaseV1(
            request: 7,
            retainRequest: counter.retain,
            releaseRequest: counter.release
        )
        #expect(counter.retains == 1)
        lease.releaseIfOwned()
        lease.releaseIfOwned()
        #expect(counter.releases == 1)
    }
    #expect(counter.releases == 1)

    do {
        let lease = MacLocalXPCStatusRequestLeaseV1(
            request: 8,
            retainRequest: counter.retain,
            releaseRequest: counter.release
        )
        let transferred = lease.takeOwnedRequest()
        #expect(transferred == 8)
        if let transferred {
            counter.release(transferred)
        }
    }
    #expect(counter.retains == 2)
    #expect(counter.releases == 2)

    do {
        _ = MacLocalXPCStatusRequestLeaseV1(
            request: 9,
            retainRequest: counter.retain,
            releaseRequest: counter.release
        )
    }
    #expect(counter.retains == 3)
    #expect(counter.releases == 3)
}

private struct UnavailableStatusReaderV1: MacLocalXPCStatusReadingV1 {
    func readStatus() async
        -> Result<LocalAgentStatusSnapshot, MacLocalXPCStatusReadErrorV1>
    {
        .failure(.sourceUnavailable)
    }
}

@Test
@available(macOS 26.0, *)
func statusAuthorityRequiresTheExactExplicitServerProfile() {
    let unexpectedReader = MacLocalXPCServerV1(
        profile: .authenticationOnly,
        statusReader: UnavailableStatusReaderV1()
    ) { _ in }
    #expect(throws: MacLocalXPCConstructionErrorV1.invalidProfile) {
        try unexpectedReader.start()
    }

    let missingReader = MacLocalXPCServerV1(
        profile: .menuLifecycleReadinessAndStatus
    ) { _ in }
    #expect(throws: MacLocalXPCConstructionErrorV1.invalidProfile) {
        try missingReader.start()
    }
}

@Test
func candidatePeerDoesNotDisplaceAuthenticatedGenerationBeforeHello() {
    var gate = MacLocalXPCPeerGenerationGateV1()

    #expect(gate.authenticate(generation: 3) == nil)
    #expect(gate.currentGeneration == 3)
    #expect(gate.admitsPostAuthenticationTraffic(generation: 3))

    // Generation 4 merely exists as a transport candidate here. The gate is
    // intentionally unchanged until its exact hello is acknowledged.
    #expect(gate.currentGeneration == 3)
    #expect(!gate.admitsPostAuthenticationTraffic(generation: 4))
}

@Test
func authenticatedReplacementFencesOldGenerationWithoutClearingNewOne() {
    var gate = MacLocalXPCPeerGenerationGateV1()
    _ = gate.authenticate(generation: 3)

    #expect(gate.authenticate(generation: 4) == 3)
    #expect(!gate.admitsPostAuthenticationTraffic(generation: 3))
    #expect(gate.admitsPostAuthenticationTraffic(generation: 4))
    let staleInvalidation = gate.invalidate(generation: 3)
    #expect(!staleInvalidation)
    #expect(gate.currentGeneration == 4)
    let currentInvalidation = gate.invalidate(generation: 4)
    #expect(currentInvalidation)
    #expect(gate.currentGeneration == nil)
}

@Test
func exactFirstHelloAuthenticatesExactlyOnce() {
    var gate = MacLocalXPCHandshakeGateV1()

    #expect(gate.state == .awaitingHello)
    #expect(gate.receive(exactHello: true) == .acknowledgeAndAuthenticate)
    #expect(gate.state == .authenticated)

    #expect(gate.receive(exactHello: true) == .reject)
    #expect(gate.state == .invalidated)
}

@Test
func malformedFirstMessagePermanentlyInvalidatesGate() {
    var gate = MacLocalXPCHandshakeGateV1()

    #expect(gate.receive(exactHello: false) == .reject)
    #expect(gate.state == .invalidated)
    #expect(gate.receive(exactHello: true) == .reject)
    #expect(gate.state == .invalidated)
}

@Test
func explicitInvalidationPreventsAuthentication() {
    var gate = MacLocalXPCHandshakeGateV1()

    gate.invalidate()

    #expect(gate.state == .invalidated)
    #expect(gate.receive(exactHello: true) == .reject)
}

@Test
func serverLifetimePublishesInvalidationOnlyAfterAuthenticationEvent() {
    var cancelledBeforeHello = MacLocalXPCAuthenticatedLifetimeV1()
    let cancelledInvalidation = cancelledBeforeHello.invalidate()
    #expect(cancelledInvalidation == false)

    var replyFailed = MacLocalXPCAuthenticatedLifetimeV1()
    let replyFailedHello = replyFailed.receiveHello(exact: true)
    #expect(replyFailedHello == .acknowledgeAndAuthenticate)
    let replyFailedInvalidation = replyFailed.invalidate()
    #expect(replyFailedInvalidation == false)

    var published = MacLocalXPCAuthenticatedLifetimeV1()
    let publishedHello = published.receiveHello(exact: true)
    #expect(publishedHello == .acknowledgeAndAuthenticate)
    let didPublish = published.publishAuthentication()
    #expect(didPublish)
    #expect(published.authenticationPublished)
    let publishedInvalidation = published.invalidate()
    #expect(publishedInvalidation)
    #expect(published.authenticationPublished == false)
    let repeatedInvalidation = published.invalidate()
    #expect(repeatedInvalidation == false)
}

@Test
func serverLifetimeCannotPublishBeforeOrTwice() {
    var lifetime = MacLocalXPCAuthenticatedLifetimeV1()
    let beforeHello = lifetime.publishAuthentication()
    #expect(beforeHello == false)
    let hello = lifetime.receiveHello(exact: true)
    #expect(hello == .acknowledgeAndAuthenticate)
    let firstPublication = lifetime.publishAuthentication()
    #expect(firstPublication)
    let repeatedPublication = lifetime.publishAuthentication()
    #expect(repeatedPublication == false)
}

@Test
func menuReadinessRequiresPublishedAuthenticationAndExactMessage() {
    var premature = MacLocalXPCAuthenticatedLifetimeV1()
    let prematureAction = premature.receiveMenuReady(exact: true)
    #expect(prematureAction == .reject)

    var malformed = MacLocalXPCAuthenticatedLifetimeV1()
    let hello = malformed.receiveHello(exact: true)
    #expect(hello == .acknowledgeAndAuthenticate)
    let authentication = malformed.publishAuthentication()
    #expect(authentication)
    let malformedAction = malformed.receiveMenuReady(exact: false)
    #expect(malformedAction == .reject)
    let malformedPublication = malformed.publishMenuReadiness()
    #expect(malformedPublication == false)
}

@Test
func menuReadinessPublishesOnlyAfterAcknowledgementAndOnlyOnce() {
    var lifetime = MacLocalXPCAuthenticatedLifetimeV1()
    let hello = lifetime.receiveHello(exact: true)
    #expect(hello == .acknowledgeAndAuthenticate)
    let authentication = lifetime.publishAuthentication()
    #expect(authentication)

    let ready = lifetime.receiveMenuReady(exact: true)
    #expect(ready == .acknowledgeAndPublish)
    #expect(lifetime.menuReadinessPublished == false)
    let publication = lifetime.publishMenuReadiness()
    #expect(publication)
    #expect(lifetime.menuReadinessPublished)

    let repeated = lifetime.receiveMenuReady(exact: true)
    #expect(repeated == .reject)
    let repeatedPublication = lifetime.publishMenuReadiness()
    #expect(repeatedPublication == false)
}

@Test
func invalidationClearsPublishedMenuReadinessButReportsAuthenticatedLifetime() {
    var lifetime = MacLocalXPCAuthenticatedLifetimeV1()
    _ = lifetime.receiveHello(exact: true)
    let authentication = lifetime.publishAuthentication()
    #expect(authentication)
    _ = lifetime.receiveMenuReady(exact: true)
    let publication = lifetime.publishMenuReadiness()
    #expect(publication)

    let shouldPublish = lifetime.invalidate()
    #expect(shouldPublish)
    #expect(lifetime.authenticationPublished == false)
    #expect(lifetime.menuReadinessPublished == false)
}

@Test
func identityConstantsMatchPermanentTargetsAndLaunchAgent() {
    #expect(
        MacLocalXPCIdentityV1.serviceName
            == "media.jenny.maccompanion.agent"
    )
    #expect(
        MacLocalXPCIdentityV1.menuSigningIdentifier
            == "media.jenny.maccompanion"
    )
    #expect(
        MacLocalXPCIdentityV1.agentSigningIdentifier
            == "media.jenny.maccompanion.agent"
    )
}

@Test
func authenticatedAndInvalidatedEventsRemainGenerationBound() {
    #expect(
        MacLocalXPCServerEventV1.authenticatedMenu(generation: 4)
            != .authenticatedMenu(generation: 5)
    )
    #expect(
        MacLocalXPCServerEventV1.authenticatedMenu(generation: 4)
            != .menuReady(generation: 4)
    )
    #expect(
        MacLocalXPCServerEventV1.menuReady(generation: 4)
            != .invalidatedMenu(generation: 4)
    )
    #expect(
        MacLocalXPCClientEventV1.authenticatedAgent
            != .menuReadyAcknowledged
    )
    #expect(
        MacLocalXPCClientEventV1.menuReadyAcknowledged
            != .invalidated
    )
    #expect(
        MacLocalXPCClientEventV1.agentStatusUnavailable(generation: 4)
            != .agentStatusUnavailable(generation: 5)
    )
}

@Test
func cancelledListenerRunRejectsDelayedCallbacksAndCannotEnterRestart() {
    var gate = MacLocalXPCServerRunGateV1()
    let oldRun = gate.begin()
    #expect(oldRun == 1)
    #expect(gate.admits(generation: 1))
    let endedOldRun = gate.end(generation: 1)
    #expect(endedOldRun)
    #expect(!gate.admits(generation: 1))

    let replacementRun = gate.begin()
    #expect(replacementRun == 2)
    #expect(!gate.admits(generation: 1))
    #expect(gate.admits(generation: 2))
    let staleEnd = gate.end(generation: 1)
    #expect(!staleEnd)
    #expect(gate.admits(generation: 2))
}

@Test
func pendingCandidateGateRejectsExcessPreHelloSessions() {
    var gate = MacLocalXPCPendingCandidateGateV1(limit: 2)

    let first = gate.admit(generation: 10)
    let second = gate.admit(generation: 11)
    let excess = gate.admit(generation: 12)
    #expect(first)
    #expect(second)
    #expect(!excess)
    #expect(gate.generations == [10, 11])
}

@Test
func generationBoundHelloExpiryCannotRemoveReplacementCandidate() {
    var gate = MacLocalXPCPendingCandidateGateV1(limit: 2)
    let first = gate.admit(generation: 20)
    #expect(first)
    gate.remove(generation: 20)
    let replacement = gate.admit(generation: 21)
    #expect(replacement)

    // A delayed deadline for generation 20 is harmless after replacement.
    gate.remove(generation: 20)
    #expect(gate.contains(generation: 21))
    let second = gate.admit(generation: 22)
    let excess = gate.admit(generation: 23)
    #expect(second)
    #expect(!excess)
}
