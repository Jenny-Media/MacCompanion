import CompanionLocalXPCPlatform
import Testing

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
            != .invalidatedMenu(generation: 4)
    )
    #expect(
        MacLocalXPCClientEventV1.authenticatedAgent
            != .invalidated
    )
}
