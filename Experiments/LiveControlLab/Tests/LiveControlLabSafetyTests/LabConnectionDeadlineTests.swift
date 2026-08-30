import Foundation
import LiveControlLabSupport
import Network
import Testing

@Test func labBootstrapThatNeverRepliesHasBoundedSetup() async throws {
    let parameters = NWParameters.tcp
    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    let listener = try NWListener(using: parameters)
    let connections = AsyncStream<NWConnection>.makeStream()
    listener.newConnectionHandler = { connection in
        connection.start(queue: DispatchQueue(label: "Lab.deadline.accepted"))
        connections.continuation.yield(connection)
    }
    let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                listener.stateUpdateHandler = nil
                continuation.resume(returning: listener.port!.rawValue)
            case .failed(let error):
                listener.stateUpdateHandler = nil
                continuation.resume(throwing: error)
            default: break
            }
        }
        listener.start(queue: DispatchQueue(label: "Lab.deadline.listener"))
    }
    defer { listener.cancel(); connections.continuation.finish() }
    let peer = Task {
        // Keep the peer open without replying until the bounded client fails.
        var iterator = connections.stream.makeAsyncIterator()
        return await iterator.next()
    }
    await #expect(throws: (any Error).self) {
        _ = try await LabConnection.connect(fixture: LabFixture(port: port), role: "control",
            setupTimeout: .milliseconds(100))
    }
    connections.continuation.finish()
    await peer.value?.cancel()
}
