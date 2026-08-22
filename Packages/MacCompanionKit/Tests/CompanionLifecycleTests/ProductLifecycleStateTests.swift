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
    #expect(!state.newInteractiveControlAvailable)

    _ = try state.apply(.agentReady)
    #expect(state.observeAvailable)
    #expect(!state.newInteractiveControlAvailable)
    _ = try state.apply(.menuAppReady)
    #expect(state.newInteractiveControlAvailable)
    #expect(state.localAdministrationVisible)
}

@Test func menuCrashStopsControlButPreservesEligibleObserveAndRequestsVisibleRecovery() throws {
    var state = try readyLifecycle()
    let effects = try state.apply(.menuAppExited)
    #expect(effects == [.endInteractiveControl, .requestMenuRecovery])
    #expect(state.observeAvailable)
    #expect(!state.newInteractiveControlAvailable)
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
    #expect(!state.newInteractiveControlAvailable)
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
    #expect(try state.apply(.userLocked) == [.endInteractiveControl])
    #expect(state.observeAvailable)
    #expect(!state.newInteractiveControlAvailable)
    #expect(!state.localAdministrationVisible)
    #expect(try state.apply(.userUnlocked).isEmpty)
    #expect(state.newInteractiveControlAvailable)

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

@Test func otherConsoleUserPreservesObserveButFailsControlClosed() throws {
    var state = try readyLifecycle()

    #expect(try state.apply(.otherConsoleUserBecameActive) == [
        .endInteractiveControl,
    ])
    #expect(state.consoleSession == .otherConsoleUserActive)
    #expect(state.observeAvailable)
    #expect(!state.newInteractiveControlAvailable)
    #expect(!state.localAdministrationVisible)
    #expect(state.agent == .ready)
    #expect(state.menuApp == .ready)

    #expect(try state.apply(.configuredUserBecameActive).isEmpty)
    #expect(state.consoleSession == .active)
    #expect(state.observeAvailable)
    #expect(state.newInteractiveControlAvailable)
    #expect(state.localAdministrationVisible)
}

@Test func ambiguousInitialConsoleStateCanServeObserveWithoutControl() {
    let state = ProductLifecycleState(
        desiredEnabled: true,
        consoleSession: .otherConsoleUserActive,
        agent: .ready,
        menuApp: .ready
    )

    #expect(state.observeAvailable)
    #expect(!state.newInteractiveControlAvailable)
    #expect(!state.localAdministrationVisible)
}

@Test func otherConsoleTransitionsRejectUnsupportedSources() throws {
    var loggedOut = ProductLifecycleState(consoleSession: .loggedOut)
    #expect(throws: InvalidProductLifecycleTransition(
        event: .otherConsoleUserBecameActive
    )) {
        try loggedOut.apply(.otherConsoleUserBecameActive)
    }

    var active = ProductLifecycleState(consoleSession: .active)
    #expect(throws: InvalidProductLifecycleTransition(
        event: .configuredUserBecameActive
    )) {
        try active.apply(.configuredUserBecameActive)
    }

    var locked = ProductLifecycleState(
        desiredEnabled: true,
        consoleSession: .locked,
        agent: .ready,
        menuApp: .ready
    )
    #expect(try locked.apply(.otherConsoleUserBecameActive) == [
        .endInteractiveControl,
    ])
    #expect(locked.consoleSession == .otherConsoleUserActive)
    #expect(locked.observeAvailable)
    #expect(throws: InvalidProductLifecycleTransition(
        event: .otherConsoleUserBecameActive
    )) {
        try locked.apply(.otherConsoleUserBecameActive)
    }
    #expect(try locked.apply(.userLoggedOut) == [
        .endInteractiveControl,
        .closeAllRemoteSessions,
    ])
    #expect(!locked.observeAvailable)
    #expect(locked.agent == .stopped)
    #expect(locked.menuApp == .stopped)
}
