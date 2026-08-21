import CompanionIPC
import Foundation

public enum DiagnosticCLIRendererV0 {
    public static let helpText = lines([
        "Usage:",
        "  maccompanionctl status [--json]",
        "  maccompanionctl diagnostics export [--json]",
        "  maccompanionctl help",
        "  maccompanionctl version",
    ])

    public static let versionText = lines([
        "maccompanionctl local protocol 0.1",
    ])

    public static func render(
        status: LocalAgentStatusSnapshot,
        format: DiagnosticCLIOutputFormatV0
    ) throws -> String {
        try status.validate()
        switch format {
        case .text:
            return lines(statusLines(status))
        case .json:
            return try encodedJSON(status)
        }
    }

    public static func render(
        diagnosticExport: LocalDiagnosticExport,
        format: DiagnosticCLIOutputFormatV0
    ) throws -> String {
        try diagnosticExport.validate()
        switch format {
        case .text:
            var result = statusLines(diagnosticExport.status)
            result.append("Diagnostic events: \(diagnosticExport.events.count)")
            result.append(contentsOf: diagnosticExport.events.map(eventLine))
            result.append(
                "Private route details omitted: "
                    + yesNo(diagnosticExport.privateRouteDetailsOmitted)
            )
            result.append(
                "Content-bearing data omitted: "
                    + yesNo(diagnosticExport.contentBearingDataOmitted)
            )
            return lines(result)
        case .json:
            return try encodedJSON(diagnosticExport)
        }
    }

    private static func statusLines(
        _ status: LocalAgentStatusSnapshot
    ) -> [String] {
        [
            "Mac Companion Agent",
            "Protocol: \(status.protocolVersion.major).\(status.protocolVersion.minor)",
            "Enabled: \(yesNo(status.desiredEnabled))",
            "Console session: \(status.consoleSession.rawValue)",
            "Agent process: \(status.agentProcess.rawValue)",
            "Menu app process: \(status.menuAppProcess.rawValue)",
            "Network: \(status.networkState.rawValue)",
            "Security: \(status.securityPosture.rawValue)",
            "Routes: \(joined(status.routeKinds.map(\.rawValue)))",
            "Paired devices: \(status.pairedDeviceCount)",
            "Active remote sessions: \(status.activeRemoteSessionCount)",
            "Providers: \(status.providerCount)",
            "Warnings: \(joined(status.warningCodes.map(\.rawValue)))",
            "Diagnostic sequence: \(status.diagnosticSequence)",
            "Generated at Unix ms: \(status.generatedAtUnixMilliseconds)",
        ]
    }

    private static func eventLine(_ event: SanitizedDiagnosticEvent) -> String {
        "Event \(event.sequence): \(event.severity.rawValue) "
            + "\(event.component.rawValue) \(event.code.rawValue) "
            + "x\(event.occurrenceCount) at Unix ms "
            + "\(event.occurredAtUnixMilliseconds)"
    }

    private static func encodedJSON<Value: Encodable>(
        _ value: Value
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    private static func yesNo(_ value: Bool) -> String {
        value ? "yes" : "no"
    }

    private static func joined(_ values: [String]) -> String {
        values.isEmpty ? "none" : values.joined(separator: ", ")
    }

    private static func lines(_ values: [String]) -> String {
        values.joined(separator: "\n") + "\n"
    }
}
