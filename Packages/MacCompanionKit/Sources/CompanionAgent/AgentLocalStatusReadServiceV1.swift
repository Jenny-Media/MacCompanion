import CompanionIPC
import Foundation

public enum AgentLocalStatusReadServiceErrorV1:
    Error,
    Equatable,
    Sendable
{
    case sourceUnavailable
}

public protocol AgentLocalStatusWallClockV1: Sendable {
    func nowUnixMilliseconds() -> Int64
}

public struct SystemAgentLocalStatusWallClockV1:
    AgentLocalStatusWallClockV1
{
    public init() {}

    public func nowUnixMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1_000).rounded(.down))
    }
}

public protocol AgentLocalStatusReadingV1: Sendable {
    func read() async throws -> LocalAgentStatusSnapshot
}

/// Bundle-independent read boundary for an already-authorized local IPC
/// adapter. It intentionally accepts no caller role, token, identifier, or
/// method name: platform peer authentication and LocalIPCAuthorizationPolicy
/// must succeed before the future XPC adapter receives this capability.
public struct AgentLocalStatusReadServiceV1:
    AgentLocalStatusReadingV1,
    Sendable
{
    private let status: AgentLocalStatusAuthorityV1
    private let wallClock: any AgentLocalStatusWallClockV1

    public init(
        status: AgentLocalStatusAuthorityV1,
        wallClock: any AgentLocalStatusWallClockV1 =
            SystemAgentLocalStatusWallClockV1()
    ) {
        self.status = status
        self.wallClock = wallClock
    }

    public func read() async throws -> LocalAgentStatusSnapshot {
        let observedAt = wallClock.nowUnixMilliseconds()
        do {
            return try await status.snapshot(
                generatedAtUnixMilliseconds: observedAt
            )
        } catch {
            throw AgentLocalStatusReadServiceErrorV1.sourceUnavailable
        }
    }
}
