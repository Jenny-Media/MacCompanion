#if os(macOS)
import AppKit
@testable import CompanionAgentProductPlatform
import CompanionDomain
import CompanionLifecycle
import CompanionWire
import Foundation
import Testing

private final class FacadeProbeV1: @unchecked Sendable {
    private let lock = NSLock()
    private var factReads = 0
    private var nextIDValue: UInt8 = 1

    func recordFactRead() -> MacAgentPublicConsoleSessionFactsV1 {
        lock.lock()
        defer { lock.unlock() }
        factReads += 1
        return MacAgentPublicConsoleSessionFactsV1(
            processUserID: 501,
            windowSessionUserID: 501,
            onConsole: true,
            loginDone: true,
            primaryConsoleUserID: 501
        )
    }

    func nextID() -> WireUUID {
        lock.lock()
        defer { lock.unlock() }
        let suffix = String(format: "%012llx", UInt64(nextIDValue))
        nextIDValue &+= 1
        return WireUUID(
            UUID(uuidString: "018f5000-0000-7000-8000-\(suffix)")!
        )
    }

    var factReadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return factReads
    }
}

private func makeFacadeV1(
    center: NotificationCenter = NotificationCenter(),
    probe: FacadeProbeV1 = FacadeProbeV1()
) -> MacAgentApplicationLifecycleFacadeV1 {
    MacAgentApplicationLifecycleFacadeV1(
        requestContexts: MacAgentConservativeRequestContextProductV1(
            notificationCenter: center,
            observedObject: nil,
            facts: { probe.recordFactRead() },
            wallNow: { 1_787_385_600_123 },
            monotonicNow: { 78_901 },
            makeMessageID: { probe.nextID() }
        )
    )
}

@Test
func applicationLifecycleFacadeConstructionIsSafeDisabledAndInert() {
    let probe = FacadeProbeV1()
    let facade = makeFacadeV1(probe: probe)

    #expect(probe.factReadCount == 0)
    #expect(
        facade.initialLifecycleState
            == ProductLifecycleState(
                desiredEnabled: false,
                consoleSession: .otherConsoleUserActive,
                agent: .stopped,
                menuApp: .stopped
            )
    )
    #expect(!facade.initialLifecycleState.observeAvailable)
    #expect(!facade.initialLifecycleState.newInteractiveControlAvailable)
    #expect(!facade.initialLifecycleState.localAdministrationVisible)
    #expect(
        facade.snapshot().requestContexts
            == MacAgentConservativeRequestContextSnapshotV1(
                hostState: .otherConsoleUserActive,
                revision: 0,
                started: false,
                finished: false
            )
    )
}

@Test
func applicationLifecycleFacadeStartsOnceAndPublishesVerifiedSession() throws {
    let center = NotificationCenter()
    let probe = FacadeProbeV1()
    let facade = makeFacadeV1(center: center, probe: probe)

    try facade.start()
    #expect(probe.factReadCount == 1)
    #expect(facade.snapshot().requestContexts.started)
    #expect(
        throws:
            MacAgentConservativeRequestContextProductErrorV1.alreadyStarted
    ) {
        try facade.start()
    }

    center.post(
        name: NSWorkspace.sessionDidBecomeActiveNotification,
        object: nil
    )
    center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
    #expect(probe.factReadCount == 3)
    #expect(
        facade.snapshot().requestContexts.hostState
            == .userSessionActive
    )
    #expect(
        facade.initialLifecycleState.consoleSession
            == .otherConsoleUserActive
    )
    facade.finish()
}

@Test
func applicationLifecycleFacadeRetainsOneContextOwnerAndIssuesFreshContexts() {
    let facade = makeFacadeV1()
    let first = facade.primaryContext()
    let second = facade.primaryContext()
    let pairing = facade.pairingContext()

    #expect(first.hostState == .otherConsoleUserActive)
    #expect(second.hostState == .otherConsoleUserActive)
    #expect(first.responseMessageID != second.responseMessageID)
    #expect(pairing.responseMessageID != second.responseMessageID)
    #expect(first.wallNowUnixMilliseconds == pairing.wallNowUnixMilliseconds)
    #expect(
        first.monotonicNowMilliseconds
            == pairing.monotonicNowMilliseconds
    )
}

@Test
func applicationLifecycleFacadeFinishIsIdempotentTerminalAndFailClosed() throws {
    let center = NotificationCenter()
    let facade = makeFacadeV1(center: center)
    try facade.start()

    facade.finish()
    facade.finish()
    let terminal = facade.snapshot()
    #expect(terminal.requestContexts.finished)
    #expect(
        terminal.requestContexts.hostState
            == .serviceStoppingForLogout
    )
    #expect(
        facade.primaryContext().hostState
            == .serviceStoppingForLogout
    )

    center.post(name: NSWorkspace.didWakeNotification, object: nil)
    #expect(facade.snapshot() == terminal)
    #expect(
        throws: MacAgentConservativeRequestContextProductErrorV1.terminal
    ) {
        try facade.start()
    }
}

@Test
func applicationLifecycleFacadeFinishBeforeStartIsTerminal() {
    let facade = makeFacadeV1()
    facade.finish()
    facade.finish()

    #expect(facade.snapshot().requestContexts.finished)
    #expect(
        throws: MacAgentConservativeRequestContextProductErrorV1.terminal
    ) {
        try facade.start()
    }
}

@Test
func escapedContextClosuresFailClosedWhenFacadeOwnerIsReleased() throws {
    let center = NotificationCenter()
    var facade: MacAgentApplicationLifecycleFacadeV1? = makeFacadeV1(
        center: center
    )
    weak let weakFacade = facade
    try facade?.start()
    let primary = facade!.primaryContext
    let pairing = facade!.pairingContext

    #expect(primary().hostState == .userSessionActive)
    facade = nil
    #expect(weakFacade == nil)
    #expect(primary().hostState == .serviceStoppingForLogout)

    let contentFreePairing = pairing()
    #expect(contentFreePairing.wallNowUnixMilliseconds == 1_787_385_600_123)
    #expect(contentFreePairing.monotonicNowMilliseconds == 78_901)
    center.post(name: NSWorkspace.didWakeNotification, object: nil)
    center.post(
        name: NSWorkspace.sessionDidBecomeActiveNotification,
        object: nil
    )
    #expect(primary().hostState == .serviceStoppingForLogout)
}
#endif
