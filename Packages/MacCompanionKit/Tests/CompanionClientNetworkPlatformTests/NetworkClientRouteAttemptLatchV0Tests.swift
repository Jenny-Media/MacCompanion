@testable import CompanionClientNetworkPlatform
import Foundation
import Network
import Testing

@Test func readinessLatchContinuesWaitingUntilReadyOrTerminalFailure() async {
    let readyLatch = NetworkClientConnectionReadinessLatchV0()
    let readyTask = Task {
        await readyLatch.wait(timeoutMilliseconds: 10_000)
    }
    readyLatch.observe(.setup)
    readyLatch.observe(.preparing)
    readyLatch.observe(.waiting(.posix(.EAGAIN)))
    await Task.yield()
    readyLatch.observe(.ready)
    #expect(await readyTask.value == .ready)

    let failedLatch = NetworkClientConnectionReadinessLatchV0()
    let failedTask = Task {
        await failedLatch.wait(timeoutMilliseconds: 10_000)
    }
    failedLatch.observe(.failed(.posix(.ECONNREFUSED)))
    #expect(await failedTask.value == .failed)
}

@Test func readinessLatchTimesOutAndCancellationWinsExactlyOnce() async {
    let timedOut = NetworkClientConnectionReadinessLatchV0()
    #expect(await timedOut.wait(timeoutMilliseconds: 1) == .timedOut)
    timedOut.observe(.ready)
    #expect(await timedOut.wait(timeoutMilliseconds: 1) == .timedOut)

    let cancelled = NetworkClientConnectionReadinessLatchV0()
    let task = Task {
        await cancelled.wait(timeoutMilliseconds: 10_000)
    }
    await Task.yield()
    task.cancel()
    #expect(await task.value == .cancelled)
    cancelled.observe(.ready)
    #expect(await cancelled.wait(timeoutMilliseconds: 1) == .cancelled)
}

@Test func authenticationLatchPreservesFirstTerminalResultAndCancellation() async {
    let denied = NetworkClientAuthenticationLatchV0()
    let deniedTask = Task { await denied.wait() }
    denied.finish(.authenticationDenied)
    denied.finish(.authenticated)
    guard case .authenticationDenied = await deniedTask.value else {
        Issue.record("first authentication result was not preserved")
        return
    }

    let cancelled = NetworkClientAuthenticationLatchV0()
    let cancelledTask = Task { await cancelled.wait() }
    await Task.yield()
    cancelledTask.cancel()
    guard case .cancelled = await cancelledTask.value else {
        Issue.record("cancellation did not release authentication wait")
        return
    }
    cancelled.finish(.authenticated)
    guard case .cancelled = await cancelled.wait() else {
        Issue.record("late success replaced cancellation")
        return
    }
}
