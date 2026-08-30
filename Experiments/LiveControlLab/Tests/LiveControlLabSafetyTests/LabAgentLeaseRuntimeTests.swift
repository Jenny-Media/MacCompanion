import CompanionInteractiveShared
import Foundation
import LiveControlLabSupport
import Testing
@testable import LiveControlTestHost

@Test func labAgentRuntimeRejectsUninstalledAndForeignSession() async throws {
    let fixture = LabFixture()
    let bridge = JourneyCommandBridge(event: { _ in }, received: { _ in })
    let session = try HostSession(fixture: fixture, primary: bridge, realTarget: nil, usesAgentRenewal: true)
    let adapter = LabAgentLeaseRuntime(session: session)
    #expect(await adapter.activeLeaseForScheduling() == nil)
    await adapter.terminate(interactiveSessionID: UUID(), primaryConnectionID: fixture.connectionID, reason: .clientDisconnected)
    #expect(await session.report().closed == false)
    await session.close()
    #expect(await session.report().runtimeIdle)
}

@Test(.timeLimit(.minutes(1))) func labAgentRuntimeConcurrentTeardownDoesNotWaitOnItself() async throws {
    let fixture = LabFixture()
    let bridge = JourneyCommandBridge(event: { _ in }, received: { _ in })
    let session = try HostSession(fixture: fixture, primary: bridge, realTarget: nil, usesAgentRenewal: true)
    let adapter = LabAgentLeaseRuntime(session: session)
    let id = await session.sessionID
    async let external: Void = session.close()
    async let scheduler: Void = adapter.terminate(interactiveSessionID: id,
        primaryConnectionID: fixture.connectionID, reason: .protocolViolation)
    _ = await (external, scheduler)
    let report = await session.report()
    #expect(report.closed && report.runtimeIdle && !report.captureActive)
    #expect(report.queuedMediaRecords == 0)
}
