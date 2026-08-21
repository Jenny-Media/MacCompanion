@testable import CompanionLocalXPCPlatform
import Testing

@Test
@available(macOS 26.0, *)
func exactMessageParserRejectsAlternateScalarTypesAndOpenDictionaries() {
    #expect(MacLocalXPCExactMessageParserValidationV1.selfTest())
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
func menuLifecycleReadinessIsAnExplicitServerProfile() {
    #expect(
        !MacLocalXPCServerProfileV1.authenticationOnly
            .admitsMenuLifecycleReadiness
    )
    #expect(
        MacLocalXPCServerProfileV1.menuLifecycleReadiness
            .admitsMenuLifecycleReadiness
    )
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
