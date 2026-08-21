import CompanionIPC

public enum DiagnosticCLIOutputFormatV0:
    String, Codable, Equatable, Hashable, Sendable
{
    case text
    case json
}

public enum DiagnosticCLICommandKindV0:
    String, Codable, Equatable, Hashable, Sendable
{
    case status
    case exportDiagnostics
    case help
    case version
}

public enum DiagnosticCLICommandV0: Equatable, Sendable {
    case status(format: DiagnosticCLIOutputFormatV0)
    case exportDiagnostics(format: DiagnosticCLIOutputFormatV0)
    case help
    case version

    public var kind: DiagnosticCLICommandKindV0 {
        switch self {
        case .status: .status
        case .exportDiagnostics: .exportDiagnostics
        case .help: .help
        case .version: .version
        }
    }

    public var format: DiagnosticCLIOutputFormatV0? {
        switch self {
        case let .status(format), let .exportDiagnostics(format): format
        case .help, .version: nil
        }
    }
}

public enum DiagnosticCLIParseErrorV0:
    String, Error, Codable, Equatable, Sendable
{
    case missingCommand
    case unknownCommand
    case incompleteCommand
    case unexpectedArgument
    case duplicateOption
}

public enum DiagnosticCLIParserV0 {
    /// Parses arguments after the executable name. The accepted grammar is
    /// deliberately closed; rejected input is never retained in the error.
    public static func parse(
        arguments: [String]
    ) throws -> DiagnosticCLICommandV0 {
        guard let root = arguments.first else {
            throw DiagnosticCLIParseErrorV0.missingCommand
        }

        switch root {
        case "help", "--help", "-h":
            guard arguments.count == 1 else {
                throw DiagnosticCLIParseErrorV0.unexpectedArgument
            }
            return .help

        case "version", "--version":
            guard arguments.count == 1 else {
                throw DiagnosticCLIParseErrorV0.unexpectedArgument
            }
            return .version

        case "status":
            return .status(
                format: try outputFormat(options: arguments.dropFirst())
            )

        case "diagnostics":
            guard arguments.count >= 2 else {
                throw DiagnosticCLIParseErrorV0.incompleteCommand
            }
            guard arguments[1] == "export" else {
                throw DiagnosticCLIParseErrorV0.unexpectedArgument
            }
            return .exportDiagnostics(
                format: try outputFormat(options: arguments.dropFirst(2))
            )

        default:
            throw DiagnosticCLIParseErrorV0.unknownCommand
        }
    }

    private static func outputFormat<Options: Collection>(
        options: Options
    ) throws -> DiagnosticCLIOutputFormatV0
    where Options.Element == String {
        let values = Array(options)
        let jsonCount = values.filter { $0 == "--json" }.count
        guard jsonCount <= 1 else {
            throw DiagnosticCLIParseErrorV0.duplicateOption
        }
        switch values {
        case []:
            return .text
        case ["--json"]:
            return .json
        default:
            throw DiagnosticCLIParseErrorV0.unexpectedArgument
        }
    }
}

public struct DiagnosticCLIRequestPlanV0: Equatable, Sendable {
    public let methods: [LocalIPCMethod]

    public init(command: DiagnosticCLICommandV0) {
        switch command {
        case .status:
            methods = [.negotiateProtocol, .readAgentStatus]
        case .exportDiagnostics:
            methods = [.negotiateProtocol, .exportDiagnostics]
        case .help, .version:
            methods = []
        }
    }
}

public enum DiagnosticCLIFailureCategoryV0:
    String, Codable, CaseIterable, Equatable, Hashable, Sendable
{
    case usage
    case peerAuthentication
    case protocolIncompatible
    case serviceUnavailable
    case requestDenied
    case invalidResponse
    case outputFailure
    case internalFailure

    public var exitStatus: Int32 {
        switch self {
        case .usage: 2
        case .peerAuthentication: 3
        case .protocolIncompatible: 4
        case .serviceUnavailable: 5
        case .requestDenied: 6
        case .invalidResponse: 7
        case .outputFailure: 8
        case .internalFailure: 9
        }
    }

    public var message: String {
        switch self {
        case .usage:
            "Invalid maccompanionctl command."
        case .peerAuthentication:
            "Mac Companion rejected the CLI signing identity."
        case .protocolIncompatible:
            "Mac Companion local protocol is incompatible."
        case .serviceUnavailable:
            "Mac Companion Agent is unavailable."
        case .requestDenied:
            "Mac Companion denied the diagnostic request."
        case .invalidResponse:
            "Mac Companion returned an invalid diagnostic response."
        case .outputFailure:
            "maccompanionctl could not write its output."
        case .internalFailure:
            "maccompanionctl failed."
        }
    }
}
