import CompanionDomain
import Testing

@Test func operationHappyPathIsExplicit() throws {
    let queued = try OperationLifecycle().transitioning(to: .queued)
    let running = try queued.transitioning(to: .running)
    let succeeded = try running.transitioning(to: .succeeded)

    #expect(succeeded.state.isTerminal)
}

@Test func staleQueuedOperationMayFailBeforeExecution() throws {
    let queued = try OperationLifecycle().transitioning(to: .queued)
    let failed = try queued.transitioning(to: .failed)

    #expect(failed.state == .failed)
    #expect(failed.state.isTerminal)
}

@Test func terminalOperationCannotRestart() {
    let terminal = OperationLifecycle(state: .denied)
    #expect(throws: InvalidOperationTransition.self) {
        try terminal.transitioning(to: .queued)
    }
}

@Test func everyDeclaredTerminalStateHasNoSuccessor() {
    for state in OperationState.allCases where state.isTerminal {
        for candidate in OperationState.allCases {
            #expect(!state.canTransition(to: candidate))
        }
    }
}
