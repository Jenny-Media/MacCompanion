import CompanionDomain
import CompanionIPC
import CompanionTestSupport
import Foundation
import Testing

private func localIPCFixture(_ relativePath: String) throws -> Data {
    try Data(contentsOf: FixturePaths.authoritativeFixtures().appendingPathComponent(relativePath))
}

@Test func authoritativeLocalDiagnosticExportIsBoundedAndSanitized() throws {
    let value = try JSONDecoder().decode(
        LocalDiagnosticExport.self,
        from: localIPCFixture("valid/local-diagnostic-export.json")
    )
    try value.validate()
    #expect(value.events.map(\.sequence) == [3, 4])
    #expect(value.status.routeKinds == [.lan, .privateNetwork])
    #expect(value.privateRouteDetailsOmitted)
    #expect(value.contentBearingDataOmitted)
}

@Test func authoritativeSensitiveDiagnosticExportIsRejected() throws {
    let value = try JSONDecoder().decode(
        LocalDiagnosticExport.self,
        from: localIPCFixture("invalid/local-diagnostic-export-sensitive.json")
    )
    #expect(throws: LocalDiagnosticsValidationError.sensitiveDetailNotOmitted) {
        try value.validate()
    }
}

@Test func diagnosticQueryAndCountsAreStrictlyBounded() throws {
    #expect(throws: LocalDiagnosticsValidationError.boundsExceeded) {
        try SanitizedDiagnosticQuery(afterSequence: 0, limit: 0)
    }
    #expect(throws: LocalDiagnosticsValidationError.boundsExceeded) {
        try SanitizedDiagnosticQuery(afterSequence: 0, limit: 257)
    }
    #expect(throws: LocalDiagnosticsValidationError.invalidCount) {
        try SanitizedDiagnosticEvent(
            sequence: 1,
            occurredAtUnixMilliseconds: 1,
            component: .network,
            severity: .warning,
            code: .routeUnavailable,
            occurrenceCount: 0
        )
    }
}

@Test func diagnosticTimesRejectValuesOutsideTheSafeIntegerProfile() throws {
    let unsafeTime = Int64(
        MonotonicRevision<AuthorizationEpochTag>.maximumWireValue + 1
    )
    #expect(throws: LocalDiagnosticsValidationError.invalidTime) {
        try SanitizedDiagnosticEvent(
            sequence: 1,
            occurredAtUnixMilliseconds: unsafeTime,
            component: .network,
            severity: .warning,
            code: .routeUnavailable
        )
    }
    #expect(throws: LocalDiagnosticsValidationError.invalidTime) {
        try LocalAgentStatusSnapshot(
            desiredEnabled: true,
            consoleSession: .active,
            agentProcess: .ready,
            menuAppProcess: .ready,
            networkState: .listening,
            securityPosture: .nominal,
            routeKinds: [],
            pairedDeviceCount: 0,
            activeRemoteSessionCount: 0,
            providerCount: 0,
            warningCodes: [],
            diagnosticSequence: 1,
            generatedAtUnixMilliseconds: unsafeTime
        )
    }
}

@Test func diagnosticExportRejectsReorderedOrDuplicateEvents() throws {
    let status = try JSONDecoder().decode(
        LocalDiagnosticExport.self,
        from: localIPCFixture("valid/local-diagnostic-export.json")
    ).status
    let event = try SanitizedDiagnosticEvent(
        sequence: 2,
        occurredAtUnixMilliseconds: 1,
        component: .localIPC,
        severity: .warning,
        code: .versionMismatch
    )
    #expect(throws: LocalDiagnosticsValidationError.invalidOrdering) {
        try LocalDiagnosticExport(status: status, events: [event, event])
    }
}

@Test func statusConstructionSortsClosedRouteAndWarningSets() throws {
    let value = try LocalAgentStatusSnapshot(
        desiredEnabled: true,
        consoleSession: .active,
        agentProcess: .ready,
        menuAppProcess: .starting,
        networkState: .listening,
        securityPosture: .nominal,
        routeKinds: [.privateNetwork, .lan],
        pairedDeviceCount: 2,
        activeRemoteSessionCount: 1,
        providerCount: 0,
        warningCodes: [.menuAppUnavailable, .localNetworkDenied],
        diagnosticSequence: 4,
        generatedAtUnixMilliseconds: 1_724_000_000_000
    )
    #expect(value.routeKinds == [.lan, .privateNetwork])
    #expect(value.warningCodes == [.localNetworkDenied, .menuAppUnavailable])
}
