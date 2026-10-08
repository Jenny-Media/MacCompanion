import CompanionInteractiveClient
import CompanionInteractiveWire
import Foundation

public enum NetworkClientInteractiveMediaRecordPumpErrorV0:
    Error, Equatable, Sendable
{
    case alreadyStarted
    case invalidRole
    case invalidRead
    case remoteClosed
    case invalidHeader
    case consumerRejected
    case cancelled
}

public enum NetworkClientInteractiveMediaRecordPumpPhaseV0:
    String, Equatable, Sendable
{
    case idle
    case reading
    case ended
    case closed
}

/// Downstream admission boundary for one already bounded media record. The
/// consumer still owns session/surface admission, AVCC validation, decoding,
/// and render proof.
public protocol ClientInteractiveMediaRecordConsumingV0: Sendable {
    func consume(
        header: MediaRecordHeader,
        payload: Data
    ) async throws
}

/// Exact-read binary media owner for an authenticated media-role connection.
/// It validates the fixed header before reserving payload storage and never
/// asks the socket for bytes beyond the current header or payload.
package actor NetworkClientInteractiveMediaRecordPumpV0 {
    package private(set) var phase:
        NetworkClientInteractiveMediaRecordPumpPhaseV0 = .idle

    private let connection: NetworkClientInteractiveReadyRoleConnectionV0
    private let consumer: any ClientInteractiveMediaRecordConsumingV0
    private var remoteComplete = false

    package init(
        connection: NetworkClientInteractiveReadyRoleConnectionV0,
        consumer: any ClientInteractiveMediaRecordConsumingV0
    ) throws {
        guard connection.role == .media else {
            throw NetworkClientInteractiveMediaRecordPumpErrorV0.invalidRole
        }
        self.connection = connection
        self.consumer = consumer
    }

    package func run() async throws {
        guard phase == .idle else {
            throw NetworkClientInteractiveMediaRecordPumpErrorV0.alreadyStarted
        }
        phase = .reading
        do {
            while !Task.isCancelled {
                let headerBytes = try await readExactly(
                    MediaRecordHeader.byteCount
                )
                let header: MediaRecordHeader
                do {
                    header = try MediaRecordHeader.decode(headerBytes)
                } catch {
                    throw NetworkClientInteractiveMediaRecordPumpErrorV0
                        .invalidHeader
                }
                let payload = try await readExactly(Int(header.payloadLength))
                do {
                    try await consumer.consume(
                        header: header,
                        payload: payload
                    )
                } catch {
                    throw NetworkClientInteractiveMediaRecordPumpErrorV0
                        .consumerRejected
                }
                if header.type == .end {
                    phase = .ended
                    await connection.cancel()
                    return
                }
            }
            throw NetworkClientInteractiveMediaRecordPumpErrorV0.cancelled
        } catch {
            if let reason = error as? NetworkClientInteractiveMediaRecordPumpErrorV0 {
                IOSClientRuntimeDiagnosticLogV0.record(
                    "interactive.media-pump.reason.\(reason)"
                )
            }
            IOSClientRuntimeDiagnosticLogV0.record(
                "interactive.media-pump.terminal",
                error: error
            )
            await failClosed()
            throw error
        }
    }

    package func close() async {
        guard phase != .closed else { return }
        await failClosed()
    }

    private func readExactly(_ count: Int) async throws -> Data {
        guard count >= 0 else {
            throw NetworkClientInteractiveMediaRecordPumpErrorV0.invalidRead
        }
        if count == 0 { return Data() }
        var result = Data()
        result.reserveCapacity(count)
        while result.count < count {
            guard phase == .reading, !Task.isCancelled else {
                throw NetworkClientInteractiveMediaRecordPumpErrorV0.cancelled
            }
            guard !remoteComplete else {
                throw NetworkClientInteractiveMediaRecordPumpErrorV0
                    .remoteClosed
            }
            let remaining = count - result.count
            let chunk: ClientInteractiveRoleReadChunkV0
            do {
                chunk = try await connection.receiveRoleBytes(
                    maximumLength: remaining
                )
            } catch {
                throw NetworkClientInteractiveMediaRecordPumpErrorV0
                    .invalidRead
            }
            guard !chunk.data.isEmpty,
                  chunk.data.count <= remaining else {
                throw NetworkClientInteractiveMediaRecordPumpErrorV0
                    .invalidRead
            }
            result.append(chunk.data)
            remoteComplete = chunk.isComplete
            if remoteComplete, result.count < count {
                throw NetworkClientInteractiveMediaRecordPumpErrorV0
                    .remoteClosed
            }
        }
        return result
    }

    private func failClosed() async {
        guard phase != .closed else { return }
        phase = .closed
        await connection.cancel()
    }
}
