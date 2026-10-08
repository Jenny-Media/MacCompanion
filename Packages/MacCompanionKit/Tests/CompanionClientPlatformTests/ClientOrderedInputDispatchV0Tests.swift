import CompanionClientPlatform
import CompanionInteractiveWire
import CompanionInteractiveShared
import Foundation
import Testing

@MainActor private final class InputDispatchProbeV0 {
    var sent: [InteractiveInputPayload] = []
    var holdFirst = true
    var continuation: CheckedContinuation<Void, Never>?
    var failures = 0
    func send(_ payloads: [InteractiveInputPayload]) async {
        sent += payloads
        if holdFirst { holdFirst = false; await withCheckedContinuation { continuation = $0 } }
    }
    func release() { continuation?.resume(); continuation = nil }
}

@MainActor private func awaitFirstInputV0(_ probe: InputDispatchProbeV0) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while probe.continuation == nil, ContinuousClock.now < deadline { await Task.yield() }
    try #require(probe.continuation != nil)
}

@MainActor @Test func pendingMovesCoalesceWithoutCrossingButtonsOrKeys() async throws {
    let probe = InputDispatchProbeV0()
    let queue = ClientOrderedInputDispatchV0(send: { await probe.send($0) }, failure: { _ in probe.failures += 1 })
    queue.setActive(true)
    queue.submit([.pointerMove(x: 1, y: 1)])
    try await awaitFirstInputV0(probe)
    queue.submit((2...100).map { .pointerMove(x: UInt16($0), y: 2) })
    let down = InteractiveInputPayload.button(button: .primary, transition: .down)
    let up = InteractiveInputPayload.button(button: .primary, transition: .up)
    let key = InteractiveInputPayload.physicalKey(usage: 0x2b, transition: .down, modifiers: [])
    queue.submit([down, .pointerMove(x: 200, y: 2), .pointerMove(x: 201, y: 3), up, key])
    probe.release()
    try await queue.submitAndDrain([])
    #expect(probe.sent == [.pointerMove(x: 1, y: 1), .pointerMove(x: 100, y: 2), down,
                          .pointerMove(x: 201, y: 3), up, key])
    #expect(probe.failures == 0)
    queue.close()
}

@MainActor @Test func surfaceFenceJoinsIssuedInputAndDiscardsPendingOldGeometry() async throws {
    let probe = InputDispatchProbeV0()
    let queue = ClientOrderedInputDispatchV0(send: { await probe.send($0) }, failure: { _ in probe.failures += 1 })
    queue.setActive(true); queue.submit([.pointerMove(x: 1, y: 1)])
    try await awaitFirstInputV0(probe)
    queue.submit([.pointerMove(x: 100, y: 100), .button(button: .primary, transition: .down)])
    var drained = false
    let fence = Task { await queue.fenceAndDrain(); drained = true }
    for _ in 0..<20 { await Task.yield() }
    #expect(!drained)
    probe.release(); await fence.value
    queue.setActive(true)
    try await queue.submitAndDrain([.pointerMove(x: 2, y: 2)])
    #expect(probe.sent == [.pointerMove(x: 1, y: 1), .pointerMove(x: 2, y: 2)])
    #expect(probe.failures == 0)
    queue.close()
}

@MainActor @Test func inputQueueOverflowFailsClosedInsteadOfDroppingKeyTransitions() async throws {
    let probe = InputDispatchProbeV0()
    let queue = ClientOrderedInputDispatchV0(send: { await probe.send($0) }, failure: { _ in probe.failures += 1 })
    queue.setActive(true); queue.submit([.pointerMove(x: 1, y: 1)])
    try await awaitFirstInputV0(probe)
    queue.submit((0..<257).map { .physicalKey(usage: 0x2b, transition: $0.isMultiple(of: 2) ? .down : .up, modifiers: []) })
    #expect(probe.failures == 1)
    probe.release(); await queue.fenceAndDrain()
    #expect(probe.sent == [.pointerMove(x: 1, y: 1)])
    queue.close()
}

@Test func nativeSurfaceRecoveryRequiresCurrentForegroundControlAndOriginalDeadline() {
    for kind in [InteractiveSurfaceKind.desktop, .application, .window] {
        for failure in [InteractiveNativeVideoFailureV0.connectionFailed, .incompatibleFrame, .authorizationLost] {
            #expect(ClientNativeSurfaceRecoveryPolicyV0.permitsDesktopRecovery(kind: kind, failure: failure,
                primaryCurrent: true, foreground: true, now: 10, expiry: 20))
            #expect(!ClientNativeSurfaceRecoveryPolicyV0.permitsDesktopRecovery(kind: kind, failure: failure,
                primaryCurrent: false, foreground: true, now: 10, expiry: 20))
            #expect(!ClientNativeSurfaceRecoveryPolicyV0.permitsDesktopRecovery(kind: kind, failure: failure,
                primaryCurrent: true, foreground: false, now: 10, expiry: 20))
            #expect(!ClientNativeSurfaceRecoveryPolicyV0.permitsDesktopRecovery(kind: kind, failure: failure,
                primaryCurrent: true, foreground: true, now: 20, expiry: 20))
        }
    }
    for failure in [InteractiveNativeVideoFailureV0.expired, .generationExhausted, .invalidSurface] {
        #expect(!ClientNativeSurfaceRecoveryPolicyV0.permitsDesktopRecovery(kind: .window, failure: failure,
            primaryCurrent: true, foreground: true, now: 10, expiry: 20))
    }
    #expect(!ClientNativeSurfaceRecoveryPolicyV0.permitsDesktopRecovery(kind: .focusedRegion, failure: .connectionFailed,
        primaryCurrent: true, foreground: true, now: 10, expiry: 20))
}

@Test func nativeRecoveryBudgetCannotLoopAcrossReplacementDescriptors() {
    var budget = ClientNativeSurfaceRecoveryBudgetV1()
    budget.presented(now: 1_000)
    let first = budget.take(now: 1_100)
    #expect(first)
    budget.presented(now: 1_200)
    let immediateRetry = budget.take(now: 1_300)
    #expect(!immediateRetry)
    budget.presented(now: 2_000)
    let healthyRetry = budget.take(now: 32_000)
    #expect(healthyRetry)
    let repeatedRetry = budget.take(now: 32_001)
    #expect(!repeatedRetry)
    budget.userSelectedView()
    let userRetry = budget.take(now: 32_002)
    #expect(userRetry)
}

@Test func backgroundAndClockRollbackCannotRearmRecovery() {
    var budget = ClientNativeSurfaceRecoveryBudgetV1()
    let first = budget.take(now: 1_000)
    #expect(first)
    budget.presented(now: 2_000)
    budget.interrupted()
    let backgroundRetry = budget.take(now: 40_000)
    #expect(!backgroundRetry)
    budget.presented(now: 50_000)
    let rollbackRetry = budget.take(now: 49_000)
    #expect(!rollbackRetry)
}
