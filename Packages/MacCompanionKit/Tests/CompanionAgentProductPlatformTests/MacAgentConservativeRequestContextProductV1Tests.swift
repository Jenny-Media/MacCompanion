#if os(macOS)
import AppKit
@testable import CompanionAgentProductPlatform
import CompanionDomain
import CompanionWire
import Foundation
import Testing

private final class ContextMessageIDSequenceV1: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID]

    init(_ values: [UUID]) {
        self.values = values
    }

    func next() -> WireUUID {
        lock.lock()
        defer { lock.unlock() }
        return WireUUID(values.removeFirst())
    }
}

private func publicFactsV1(
    processUserID: UInt32 = 501,
    windowSessionUserID: UInt32? = 501,
    onConsole: Bool? = true,
    loginDone: Bool? = true
) -> MacAgentPublicConsoleSessionFactsV1 {
    MacAgentPublicConsoleSessionFactsV1(
        processUserID: processUserID,
        windowSessionUserID: windowSessionUserID,
        onConsole: onConsole,
        loginDone: loginDone
    )
}

@Test
func publicConsoleFactsNeverPromoteAnAmbiguousSessionToUnlocked() {
    let variants = [
        publicFactsV1(),
        publicFactsV1(windowSessionUserID: 502),
        publicFactsV1(onConsole: false),
        publicFactsV1(windowSessionUserID: nil, onConsole: nil),
        publicFactsV1(loginDone: nil),
        publicFactsV1(loginDone: false),
    ]

    for facts in variants {
        #expect(
            MacAgentConservativeRequestContextProductV1
                .conservativeHostState(for: facts)
                == .otherConsoleUserActive
        )
    }
}

@Test
func conservativeContextProductOwnsClocksIDsAndTerminalLifecycle() throws {
    let center = NotificationCenter()
    let ids = ContextMessageIDSequenceV1([
        UUID(uuidString: "018f5000-0000-7000-8000-000000000001")!,
        UUID(uuidString: "018f5000-0000-7000-8000-000000000002")!,
        UUID(uuidString: "018f5000-0000-7000-8000-000000000003")!,
    ])
    let product = MacAgentConservativeRequestContextProductV1(
        notificationCenter: center,
        observedObject: nil,
        facts: { publicFactsV1() },
        wallNow: { 1_787_299_200_123 },
        monotonicNow: { 45_678 },
        makeMessageID: { ids.next() }
    )

    try product.start()
    #expect(
        product.snapshot()
            == MacAgentConservativeRequestContextSnapshotV1(
                hostState: .otherConsoleUserActive,
                revision: 0,
                started: true,
                finished: false
            )
    )
    #expect(
        throws:
            MacAgentConservativeRequestContextProductErrorV1.alreadyStarted
    ) {
        try product.start()
    }

    let primary = product.primaryContext()
    #expect(primary.hostState == .otherConsoleUserActive)
    #expect(primary.wallNowUnixMilliseconds == 1_787_299_200_123)
    #expect(primary.monotonicNowMilliseconds == 45_678)
    #expect(
        primary.responseMessageID
            == WireUUID(
                UUID(uuidString: "018f5000-0000-7000-8000-000000000001")!
            )
    )
    let pairing = product.pairingContext()
    #expect(pairing.wallNowUnixMilliseconds == 1_787_299_200_123)
    #expect(pairing.monotonicNowMilliseconds == 45_678)
    #expect(
        pairing.responseMessageID
            == WireUUID(
                UUID(uuidString: "018f5000-0000-7000-8000-000000000002")!
            )
    )

    center.post(name: NSWorkspace.willSleepNotification, object: nil)
    #expect(product.snapshot().hostState == .hostPreparingForSleep)
    center.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
    #expect(product.snapshot().hostState == .hostPreparingForSleep)
    center.post(name: NSWorkspace.didWakeNotification, object: nil)
    #expect(product.snapshot().hostState == .otherConsoleUserActive)

    center.post(name: NSWorkspace.willPowerOffNotification, object: nil)
    let terminal = product.snapshot()
    #expect(terminal.hostState == .serviceStoppingForLogout)
    center.post(name: NSWorkspace.didWakeNotification, object: nil)
    #expect(product.snapshot() == terminal)

    product.finish()
    product.finish()
    #expect(product.snapshot().finished)
    #expect(
        throws: MacAgentConservativeRequestContextProductErrorV1.terminal
    ) {
        try product.start()
    }
}

@Test
func lifecycleNotificationDuringInitialSamplingWinsTheStartupRace() throws {
    let center = NotificationCenter()
    let product = MacAgentConservativeRequestContextProductV1(
        notificationCenter: center,
        observedObject: nil,
        facts: {
            center.post(name: NSWorkspace.willSleepNotification, object: nil)
            return publicFactsV1()
        },
        wallNow: { 10 },
        monotonicNow: { 20 },
        makeMessageID: {
            WireUUID(
                UUID(uuidString: "018f5000-0000-7000-8000-000000000020")!
            )
        }
    )

    try product.start()
    #expect(product.snapshot().hostState == .hostPreparingForSleep)
    product.finish()
}

@Test
func finishRemovesSessionObserversAndMakesTheContextFailClosed() throws {
    let center = NotificationCenter()
    let product = MacAgentConservativeRequestContextProductV1(
        notificationCenter: center,
        observedObject: nil,
        facts: { publicFactsV1() },
        wallNow: { 10 },
        monotonicNow: { 20 },
        makeMessageID: {
            WireUUID(
                UUID(uuidString: "018f5000-0000-7000-8000-000000000010")!
            )
        }
    )
    try product.start()
    product.finish()
    let finished = product.snapshot()
    center.post(name: NSWorkspace.willSleepNotification, object: nil)
    center.post(name: NSWorkspace.didWakeNotification, object: nil)
    #expect(product.snapshot() == finished)
    #expect(product.primaryRequestContext().hostState == .serviceStoppingForLogout)
}
#endif
