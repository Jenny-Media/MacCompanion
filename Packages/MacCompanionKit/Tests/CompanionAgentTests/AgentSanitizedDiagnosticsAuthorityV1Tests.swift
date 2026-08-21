import CompanionAgent
import CompanionDomain
import CompanionIPC
import CompanionLifecycle
import CompanionPersistence
import Foundation
import Testing

private enum DiagnosticSourceTestErrorV1: Error {
    case unavailable
}

private struct FixedDiagnosticStatusReaderV1: AgentLocalStatusReadingV1 {
    let value: LocalAgentStatusSnapshot

    func read() async throws -> LocalAgentStatusSnapshot { value }
}

private struct FailingDiagnosticStatusReaderV1: AgentLocalStatusReadingV1 {
    func read() async throws -> LocalAgentStatusSnapshot {
        throw DiagnosticSourceTestErrorV1.unavailable
    }
}

private struct FailingDiagnosticEventReaderV1:
    AgentSanitizedDiagnosticEventReadingV1
{
    func readAll() async throws -> [SanitizedDiagnosticEvent] {
        throw DiagnosticSourceTestErrorV1.unavailable
    }
}

private struct FixedDiagnosticEventReaderV1:
    AgentSanitizedDiagnosticEventReadingV1
{
    let values: [SanitizedDiagnosticEvent]

    func readAll() async throws -> [SanitizedDiagnosticEvent] { values }
}

private struct DiagnosticRootPairedCountV1:
    AgentActivePairedDeviceCountReadingV1
{
    func activePairedDeviceCount() async throws -> Int { 0 }
}

private struct DiagnosticRootProviderCountV1:
    AgentActiveProviderCountReadingV1
{
    func activeProviderCount() async -> Int { 0 }
}

private struct DiagnosticRootClockV1: AgentLocalStatusWallClockV1 {
    func nowUnixMilliseconds() -> Int64 { 9_000 }
}

private func diagnosticStatusV1() throws -> LocalAgentStatusSnapshot {
    try LocalAgentStatusSnapshot(
        desiredEnabled: true,
        consoleSession: .active,
        agentProcess: .ready,
        menuAppProcess: .ready,
        networkState: .listening,
        securityPosture: .nominal,
        routeKinds: [.lan],
        pairedDeviceCount: 0,
        activeRemoteSessionCount: 0,
        providerCount: 1,
        warningCodes: [],
        diagnosticSequence: 4,
        generatedAtUnixMilliseconds: 8_000
    )
}

private func diagnosticRootDirectoryV1() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "maccompanion-diagnostics-\(UUID())",
            isDirectory: true
        )
    try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: false
    )
    return directory
}

@Test func sanitizedDiagnosticAuthorityAssignsOrderedContentFreeEvents() async throws {
    let authority = AgentSanitizedDiagnosticsAuthorityV1()
    let first = try await authority.record(
        occurredAtUnixMilliseconds: 100,
        component: .network,
        severity: .warning,
        code: .routeUnavailable
    )
    let second = try await authority.record(
        occurredAtUnixMilliseconds: 101,
        component: .security,
        severity: .error,
        code: .storageUnavailable
    )

    #expect(first.sequence == 1)
    #expect(first.occurrenceCount == 1)
    #expect(second.sequence == 2)
    #expect(await authority.readAll() == [first, second])
}

@Test func sanitizedDiagnosticAuthorityRetainsOnlyNewestBoundedEvents() async throws {
    let authority = AgentSanitizedDiagnosticsAuthorityV1()
    for index in 1...300 {
        _ = try await authority.record(
            occurredAtUnixMilliseconds: Int64(index),
            component: .lifecycle,
            severity: .information,
            code: .authorizationChanged
        )
    }

    let values = await authority.readAll()
    #expect(values.count == 256)
    #expect(values.first?.sequence == 45)
    #expect(values.last?.sequence == 300)
}

@Test func sanitizedDiagnosticAuthorityRejectsInvalidTimeWithoutMutation() async throws {
    let authority = AgentSanitizedDiagnosticsAuthorityV1()
    await #expect(
        throws: AgentSanitizedDiagnosticsAuthorityErrorV1.invalidTime
    ) {
        _ = try await authority.record(
            occurredAtUnixMilliseconds: -1,
            component: .localIPC,
            severity: .warning,
            code: .versionMismatch
        )
    }
    #expect(await authority.readAll().isEmpty)

    let first = try await authority.record(
        occurredAtUnixMilliseconds: 1,
        component: .localIPC,
        severity: .warning,
        code: .versionMismatch
    )
    #expect(first.sequence == 1)
}

@Test func sanitizedDiagnosticAuthorityFailsClosedAtSequenceExhaustion() async throws {
    let authority = AgentSanitizedDiagnosticsAuthorityV1(
        startingAfter:
            MonotonicRevision<AuthorizationEpochTag>.maximumWireValue
    )
    await #expect(
        throws: AgentSanitizedDiagnosticsAuthorityErrorV1.sequenceExhausted
    ) {
        _ = try await authority.record(
            occurredAtUnixMilliseconds: 1,
            component: .security,
            severity: .error,
            code: .denyLatchArmed
        )
    }
    #expect(await authority.readAll().isEmpty)
}

@Test func localDiagnosticExportServiceReturnsValidatedStatusAndEvents() async throws {
    let event = try SanitizedDiagnosticEvent(
        sequence: 7,
        occurredAtUnixMilliseconds: 7_000,
        component: .persistence,
        severity: .warning,
        code: .auditHistoryDegraded
    )
    let service = AgentLocalDiagnosticExportServiceV1(
        status: FixedDiagnosticStatusReaderV1(value: try diagnosticStatusV1()),
        events: FixedDiagnosticEventReaderV1(values: [event])
    )

    let value = try await service.export()
    try value.validate()
    #expect(value.status.diagnosticSequence == 4)
    #expect(value.events == [event])
    #expect(value.privateRouteDetailsOmitted)
    #expect(value.contentBearingDataOmitted)
}

@Test func localDiagnosticExportServiceMapsEverySourceFailureClosed() async throws {
    let validStatus = FixedDiagnosticStatusReaderV1(
        value: try diagnosticStatusV1()
    )
    await #expect(
        throws: AgentLocalDiagnosticExportServiceErrorV1.sourceUnavailable
    ) {
        _ = try await AgentLocalDiagnosticExportServiceV1(
            status: FailingDiagnosticStatusReaderV1(),
            events: FixedDiagnosticEventReaderV1(values: [])
        ).export()
    }
    await #expect(
        throws: AgentLocalDiagnosticExportServiceErrorV1.sourceUnavailable
    ) {
        _ = try await AgentLocalDiagnosticExportServiceV1(
            status: validStatus,
            events: FailingDiagnosticEventReaderV1()
        ).export()
    }
}

@Test func localServiceRootIssuesOneSanitizedDiagnosticExportCapability() async throws {
    let directory = try diagnosticRootDirectoryV1()
    defer { try? FileManager.default.removeItem(at: directory) }
    let root = try await AgentLocalServiceRootV1.bootstrap(
        lifecycle: ProductLifecycleState(
            desiredEnabled: true,
            consoleSession: .active,
            agent: .ready,
            menuApp: .ready
        ),
        pairedDevices: DiagnosticRootPairedCountV1(),
        capabilities: DiagnosticRootProviderCountV1(),
        denyLatch: try EmergencyDenyLatch(
            url: directory.appendingPathComponent("deny.latch")
        ),
        auditHistoryDegraded: false,
        wallClock: DiagnosticRootClockV1()
    )
    let event = try await root.diagnosticEvents.publish(
        occurredAtUnixMilliseconds: 8_500,
        component: .network,
        severity: .information,
        code: .routeUnavailable
    )

    let value = try await root.diagnosticExporter.export()
    #expect(value.status.generatedAtUnixMilliseconds == 9_000)
    #expect(value.status.diagnosticSequence == 1)
    #expect(value.events == [event])
}
