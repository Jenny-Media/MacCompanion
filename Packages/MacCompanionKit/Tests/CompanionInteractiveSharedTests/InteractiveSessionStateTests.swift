import CompanionDomain
import CompanionInteractiveShared
import Foundation
import Testing

private let interactiveSessionID = UUID(uuidString: "018f6000-0000-7000-8000-000000000001")!

private func activeSession() throws -> InteractiveSessionStateMachine {
    var value = InteractiveSessionStateMachine()
    _ = try value.apply(.request(
        sessionID: interactiveSessionID,
        authorizationEpoch: .init(rawValue: 4),
        approvalDeadlineMonotonicMilliseconds: 60_000
    ))
    _ = try value.apply(.approvalConsumed(monotonicNowMilliseconds: 1_000))
    _ = try value.apply(.executorReadyUnlocked(monotonicNowMilliseconds: 2_000))
    return value
}

@Test func approvalAndExecutorSetupAreRequiredBeforeInput() throws {
    var value = InteractiveSessionStateMachine()
    #expect(try value.apply(.request(
        sessionID: interactiveSessionID,
        authorizationEpoch: .init(rawValue: 4),
        approvalDeadlineMonotonicMilliseconds: 60_000
    )) == [.requestUserPresence, .publishState])
    #expect(!value.admitsPointerAndPhysicalKeyInput)
    #expect(try value.apply(.approvalConsumed(monotonicNowMilliseconds: 1_000)) == [
        .beginExecutorSetup, .publishState,
    ])
    #expect(try value.apply(.executorReadyUnlocked(monotonicNowMilliseconds: 2_000)) == [
        .requireFreshDesktopDescriptorAndKeyframe, .publishState,
    ])
    #expect(value.admitsPointerAndPhysicalKeyInput)
    #expect(value.admitsTextInput)
}

@Test func unsupportedLockBlanksDesktopAndUnlockRequiresFreshSetup() throws {
    var value = try activeSession()
    let lockEffects = try value.apply(.hostLocked(lockSurfaceSupported: false))
    #expect(value.state == .lockedInteractionUnavailable)
    #expect(lockEffects.contains(.blankLastFrame))
    #expect(lockEffects.contains(.invalidateAllSurfaceTokens))
    #expect(!value.admitsPointerAndPhysicalKeyInput)

    let unlockEffects = try value.apply(.hostUnlocked)
    #expect(value.state == .starting)
    #expect(unlockEffects.contains(.beginExecutorSetup))
    #expect(unlockEffects.contains(.requireFreshDesktopDescriptorAndKeyframe) == false)
    #expect(!value.admitsPointerAndPhysicalKeyInput)
    _ = try value.apply(.executorReadyUnlocked(monotonicNowMilliseconds: 5_000))
    #expect(value.state == .activeUnlocked)
    #expect(value.sessionDeadlineMonotonicMilliseconds ==
        1_000 + InteractiveSessionStateMachine.maximumDurationMilliseconds)
}

@Test func supportedLockAllowsOnlyPointerAndPhysicalKeysNotText() throws {
    var value = try activeSession()
    let effects = try value.apply(.hostLocked(lockSurfaceSupported: true))
    #expect(value.state == .activeLocked)
    #expect(effects.contains(.beginLockSurfaceCapture))
    #expect(value.admitsPointerAndPhysicalKeyInput)
    #expect(!value.admitsTextInput)
}

@Test func suspensionCannotResumeRemotelyAndMustEnd() throws {
    var value = try activeSession()
    let effects = try value.apply(.suspend(.authorizationChanged))
    #expect(value.state == .suspended)
    #expect(effects.contains(.releaseAllInput))
    #expect(throws: InteractiveSessionTransitionError.self) {
        try value.apply(.executorReadyUnlocked(monotonicNowMilliseconds: 3_000))
    }
    _ = try value.apply(.end(.authorizationChanged))
    #expect(value.state == .ending)
    _ = try value.apply(.teardownFinished(endedAtUnixMilliseconds: 10_000))
    #expect(value.state == .ended)
    _ = try value.apply(.releaseTerminalRecord)
    #expect(value.state == .idle)
    #expect(value.sessionID == nil)
}

@Test func approvalAndSessionDeadlinesEndAtExactBoundary() throws {
    var approval = InteractiveSessionStateMachine()
    _ = try approval.apply(.request(
        sessionID: interactiveSessionID,
        authorizationEpoch: .init(rawValue: 1),
        approvalDeadlineMonotonicMilliseconds: 60_000
    ))
    let approvalEffects = try approval.apply(.tick(monotonicNowMilliseconds: 60_000))
    #expect(approval.state == .ending)
    #expect(approval.terminalReason == .approvalExpired)
    #expect(approvalEffects.contains(.closeChannels))

    var active = try activeSession()
    let deadline = 1_000 + InteractiveSessionStateMachine.maximumDurationMilliseconds
    #expect(try active.apply(.tick(monotonicNowMilliseconds: deadline - 1)).isEmpty)
    _ = try active.apply(.tick(monotonicNowMilliseconds: deadline))
    #expect(active.state == .ending)
    #expect(active.terminalReason == .maximumDurationReached)
}

@Test func setupAndLockTransitionsCannotExtendMaximumDuration() throws {
    var value = try activeSession()
    let deadline = 1_000 + InteractiveSessionStateMachine.maximumDurationMilliseconds
    _ = try value.apply(.hostLocked(lockSurfaceSupported: false))
    _ = try value.apply(.hostUnlocked)
    #expect(value.sessionDeadlineMonotonicMilliseconds == deadline)
    _ = try value.apply(.tick(monotonicNowMilliseconds: deadline))
    #expect(value.state == .ending)
    #expect(value.terminalReason == .maximumDurationReached)
}
