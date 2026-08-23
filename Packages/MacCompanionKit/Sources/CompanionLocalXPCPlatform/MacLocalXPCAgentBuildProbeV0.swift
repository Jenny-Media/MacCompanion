#if os(macOS)
import Foundation

public enum MacLocalXPCAgentBuildProbeErrorV0:
    Error, Equatable, Sendable
{
    case invalidTimeout
    case startFailed
    case timedOut
    case invalidated
    case unexpectedEvent
}

@available(macOS 26.0, *)
package protocol MacLocalXPCAgentBuildProbeClientV0:
    AnyObject, Sendable
{
    func start() throws
    func cancel()
}

@available(macOS 26.0, *)
extension MacLocalXPCClientV1: MacLocalXPCAgentBuildProbeClientV0 {}

/// A one-use, startup-only build observation. The signed local-XPC peer
/// requirement authenticates the Agent before its exact hello acknowledgement
/// yields the build. This probe must run before the dashboard client starts,
/// because the Agent intentionally owns only one authenticated menu lifetime.
@available(macOS 26.0, *)
public struct MacLocalXPCAgentBuildProbeV0: Sendable {
    package typealias ClientFactory = @Sendable (
        @escaping MacLocalXPCClientV1.EventHandler
    ) -> any MacLocalXPCAgentBuildProbeClientV0

    public static let defaultTimeoutNanoseconds: UInt64 = 3_000_000_000

    private let clientFactory: ClientFactory

    public init() {
        clientFactory = { MacLocalXPCClientV1(onEvent: $0) }
    }

    package init(clientFactory: @escaping ClientFactory) {
        self.clientFactory = clientFactory
    }

    public func readBuild(
        timeoutNanoseconds: UInt64 = Self.defaultTimeoutNanoseconds
    ) async throws -> UInt64 {
        guard timeoutNanoseconds > 0 else {
            throw MacLocalXPCAgentBuildProbeErrorV0.invalidTimeout
        }

        let pair = AsyncStream<
            Result<UInt64, MacLocalXPCAgentBuildProbeErrorV0>
        >.makeStream(bufferingPolicy: .bufferingOldest(1))
        let resultGate = MacLocalXPCAgentBuildProbeResultGateV0(
            continuation: pair.continuation
        )
        let client = clientFactory { event in
            resultGate.receive(event)
        }

        do {
            try client.start()
        } catch {
            resultGate.finish()
            client.cancel()
            throw MacLocalXPCAgentBuildProbeErrorV0.startFailed
        }
        defer {
            resultGate.finish()
            client.cancel()
        }

        return try await withThrowingTaskGroup(of: UInt64.self) { group in
            group.addTask {
                var iterator = pair.stream.makeAsyncIterator()
                guard let result = await iterator.next() else {
                    throw MacLocalXPCAgentBuildProbeErrorV0.invalidated
                }
                return try result.get()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw MacLocalXPCAgentBuildProbeErrorV0.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else {
                throw MacLocalXPCAgentBuildProbeErrorV0.invalidated
            }
            return first
        }
    }
}

@available(macOS 26.0, *)
private final class MacLocalXPCAgentBuildProbeResultGateV0:
    @unchecked Sendable
{
    typealias ProbeResult =
        Result<UInt64, MacLocalXPCAgentBuildProbeErrorV0>

    private let lock = NSLock()
    private var terminal = false
    private let continuation: AsyncStream<ProbeResult>.Continuation

    init(continuation: AsyncStream<ProbeResult>.Continuation) {
        self.continuation = continuation
    }

    func receive(_ event: MacLocalXPCClientEventV1) {
        let result: ProbeResult
        switch event {
        case let .authenticatedAgent(build):
            result = .success(build)
        case .invalidated:
            result = .failure(.invalidated)
        case .menuReadyAcknowledged, .agentStatus,
                .agentStatusUnavailable:
            result = .failure(.unexpectedEvent)
        }

        lock.lock()
        guard !terminal else {
            lock.unlock()
            return
        }
        terminal = true
        lock.unlock()
        continuation.yield(result)
        continuation.finish()
    }

    func finish() {
        lock.lock()
        guard !terminal else {
            lock.unlock()
            return
        }
        terminal = true
        lock.unlock()
        continuation.finish()
    }
}
#endif
