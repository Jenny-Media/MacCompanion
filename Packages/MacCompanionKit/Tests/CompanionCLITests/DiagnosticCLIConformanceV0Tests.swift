import CompanionCLI
import CompanionIPC
import CompanionTestSupport
import Foundation
import Testing

private struct CLIFixtureV0: Decodable {
    struct CommandCase: Decodable {
        let arguments: [String]
        let kind: DiagnosticCLICommandKindV0
        let format: DiagnosticCLIOutputFormatV0?
        let requestMethods: [LocalIPCMethod]
    }

    struct InvalidCommandCase: Decodable {
        let arguments: [String]
        let error: DiagnosticCLIParseErrorV0
    }

    struct ExpectedText: Decodable {
        let helpLines: [String]
        let versionLines: [String]
        let statusLines: [String]
        let exportLines: [String]
    }

    struct FailureCase: Decodable {
        let category: DiagnosticCLIFailureCategoryV0
        let exitStatus: Int32
        let message: String
    }

    let profile: String
    let validCommandCases: [CommandCase]
    let invalidCommandCases: [InvalidCommandCase]
    let expectedText: ExpectedText
    let failureCases: [FailureCase]
}

private func fixtureData(_ relativePath: String) throws -> Data {
    try Data(
        contentsOf: FixturePaths.authoritativeFixtures()
            .appendingPathComponent(relativePath)
    )
}

private func cliFixture() throws -> CLIFixtureV0 {
    try JSONDecoder().decode(
        CLIFixtureV0.self,
        from: fixtureData("cli-v0.1.json")
    )
}

private func diagnosticExport() throws -> LocalDiagnosticExport {
    try JSONDecoder().decode(
        LocalDiagnosticExport.self,
        from: fixtureData("valid/local-diagnostic-export.json")
    )
}

private func expectedText(_ lines: [String]) -> String {
    lines.joined(separator: "\n") + "\n"
}

@Test func authoritativeCLICommandsProduceExactAuthorizedPlans() throws {
    let fixture = try cliFixture()
    #expect(fixture.profile == "maccompanion.local-cli.v0.1")

    for value in fixture.validCommandCases {
        let command = try DiagnosticCLIParserV0.parse(
            arguments: value.arguments
        )
        #expect(command.kind == value.kind)
        #expect(command.format == value.format)

        let plan = DiagnosticCLIRequestPlanV0(command: command)
        #expect(plan.methods == value.requestMethods)
        for method in plan.methods {
            try LocalIPCAuthorizationPolicy.authorize(
                authenticatedCaller: .diagnosticCLI,
                endpoint: .agent,
                method: method,
                version: .init()
            )
        }
    }
}

@Test func authoritativeCLIInvalidArgumentsFailClosedWithoutRetention() throws {
    for value in try cliFixture().invalidCommandCases {
        #expect(throws: value.error) {
            try DiagnosticCLIParserV0.parse(arguments: value.arguments)
        }
    }
}

@Test func authoritativeCLITextRenderingMatchesTheClosedCorpus() throws {
    let fixture = try cliFixture()
    let diagnosticExport = try diagnosticExport()

    #expect(
        DiagnosticCLIRendererV0.helpText
            == expectedText(fixture.expectedText.helpLines)
    )
    #expect(
        DiagnosticCLIRendererV0.versionText
            == expectedText(fixture.expectedText.versionLines)
    )
    #expect(
        try DiagnosticCLIRendererV0.render(
            status: diagnosticExport.status,
            format: .text
        ) == expectedText(fixture.expectedText.statusLines)
    )
    #expect(
        try DiagnosticCLIRendererV0.render(
            diagnosticExport: diagnosticExport,
            format: .text
        ) == expectedText(fixture.expectedText.exportLines)
    )
}

@Test func CLIJSONRenderingIsCompactSortedValidatedAndRoundTrips() throws {
    let diagnosticExport = try diagnosticExport()
    let statusOutput = try DiagnosticCLIRendererV0.render(
        status: diagnosticExport.status,
        format: .json
    )
    let exportOutput = try DiagnosticCLIRendererV0.render(
        diagnosticExport: diagnosticExport,
        format: .json
    )

    #expect(statusOutput.hasSuffix("\n"))
    #expect(!statusOutput.dropLast().contains("\n"))
    #expect(statusOutput.hasPrefix("{\"activeRemoteSessionCount\":"))
    #expect(exportOutput.hasSuffix("\n"))
    #expect(!exportOutput.dropLast().contains("\n"))
    #expect(exportOutput.hasPrefix("{\"contentBearingDataOmitted\":"))

    let decodedStatus = try JSONDecoder().decode(
        LocalAgentStatusSnapshot.self,
        from: Data(statusOutput.utf8)
    )
    let decodedExport = try JSONDecoder().decode(
        LocalDiagnosticExport.self,
        from: Data(exportOutput.utf8)
    )
    #expect(decodedStatus == diagnosticExport.status)
    #expect(decodedExport == diagnosticExport)
}

@Test func CLIRendererRejectsSensitiveTypedExportBeforeOutput() throws {
    let sensitive = try JSONDecoder().decode(
        LocalDiagnosticExport.self,
        from: fixtureData("invalid/local-diagnostic-export-sensitive.json")
    )
    #expect(
        throws: LocalDiagnosticsValidationError.sensitiveDetailNotOmitted
    ) {
        try DiagnosticCLIRendererV0.render(
            diagnosticExport: sensitive,
            format: .text
        )
    }
    #expect(
        throws: LocalDiagnosticsValidationError.sensitiveDetailNotOmitted
    ) {
        try DiagnosticCLIRendererV0.render(
            diagnosticExport: sensitive,
            format: .json
        )
    }
}

@Test func CLIFailureStatusesAndMessagesMatchTheAuthoritativeCorpus() throws {
    let fixture = try cliFixture()
    #expect(
        Set(fixture.failureCases.map(\.category))
            == Set(DiagnosticCLIFailureCategoryV0.allCases)
    )
    #expect(Set(fixture.failureCases.map(\.exitStatus)).count == 8)

    for value in fixture.failureCases {
        #expect(value.category.exitStatus == value.exitStatus)
        #expect(value.category.message == value.message)
        #expect(!value.category.message.contains("\n"))
    }
}

@Test func CLITextUsesExplicitNoneForEmptyClosedLists() throws {
    let status = try LocalAgentStatusSnapshot(
        desiredEnabled: false,
        consoleSession: .loggedOut,
        agentProcess: .stopped,
        menuAppProcess: .stopped,
        networkState: .stopped,
        securityPosture: .nominal,
        routeKinds: [],
        pairedDeviceCount: 0,
        activeRemoteSessionCount: 0,
        providerCount: 0,
        warningCodes: [],
        diagnosticSequence: 0,
        generatedAtUnixMilliseconds: 0
    )
    let output = try DiagnosticCLIRendererV0.render(
        status: status,
        format: .text
    )
    #expect(output.contains("Routes: none\n"))
    #expect(output.contains("Warnings: none\n"))
}
