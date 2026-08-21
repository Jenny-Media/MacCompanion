import CompanionLifecycle
import Testing

private func readyLifecycle() throws -> ProductLifecycleState {
    var state = ProductLifecycleState(consoleSession: .active)
    _ = try state.apply(.enableRequested)
    _ = try state.apply(.agentReady)
    _ = try state.apply(.menuAppReady)
    return state
}

@Test func explicitEnableRequiresBothProcessesBeforeControlIsAvailable() throws {
    var state = ProductLifecycleState(consoleSession: .active)
    let effects = try state.apply(.enableRequested)
    #expect(effects == [
        .registerAgentLogin,
        .registerMenuLogin,
        .requestAgentStart,
        .requestMenuStart,
    ])
    #expect(!state.observeAvailable)
    #expect(!state.interactiveControlAvailable)

    _ = try state.apply(.agentReady)
    #expect(state.observeAvailable)
    #expect(!state.interactiveControlAvailable)
    _ = try state.apply(.menuAppReady)
    #expect(state.interactiveControlAvailable)
    #expect(state.localAdministrationVisible)
}

@Test func menuCrashStopsControlButPreservesEligibleObserveAndRequestsVisibleRecovery() throws {
    var state = try readyLifecycle()
    let effects = try state.apply(.menuAppExited)
    #expect(effects == [.endInteractiveControl, .requestMenuRecovery])
    #expect(state.observeAvailable)
    #expect(!state.interactiveControlAvailable)
    #expect(!state.localAdministrationVisible)
    #expect(state.menuApp == .starting)
}

@Test func agentCrashClosesEveryRemoteSessionAndNeverLeavesControlAvailable() throws {
    var state = try readyLifecycle()
    let effects = try state.apply(.agentExited)
    #expect(effects == [
        .endInteractiveControl,
        .closeAllRemoteSessions,
        .requestAgentRecovery,
    ])
    #expect(!state.observeAvailable)
    #expect(!state.interactiveControlAvailable)
    #expect(state.agent == .starting)
}

@Test func explicitDisableUnregistersBothRolesAndCannotBeMistakenForCrash() throws {
    var state = try readyLifecycle()
    let effects = try state.apply(.disableRequested)
    #expect(effects == [
        .endInteractiveControl,
        .closeAllRemoteSessions,
        .unregisterAgentLogin,
        .unregisterMenuLogin,
    ])
    #expect(!state.desiredEnabled)
    #expect(state.agent == .stopped)
    #expect(state.menuApp == .stopped)
    #expect(throws: InvalidProductLifecycleTransition(event: .agentExited)) {
        try state.apply(.agentExited)
    }
}

@Test func logoutIsOfflineWhileLoginRestoresEnabledIntentAndLockDoesNotKillProcesses() throws {
    var state = try readyLifecycle()
    #expect(try state.apply(.userLocked).isEmpty)
    #expect(state.observeAvailable)
    #expect(state.interactiveControlAvailable)
    #expect(try state.apply(.userUnlocked).isEmpty)

    #expect(try state.apply(.userLoggedOut) == [
        .endInteractiveControl,
        .closeAllRemoteSessions,
    ])
    #expect(state.desiredEnabled)
    #expect(!state.observeAvailable)
    #expect(try state.apply(.userLoggedIn) == [
        .requestAgentStart,
        .requestMenuStart,
    ])
    #expect(state.agent == .starting)
    #expect(state.menuApp == .starting)
}
