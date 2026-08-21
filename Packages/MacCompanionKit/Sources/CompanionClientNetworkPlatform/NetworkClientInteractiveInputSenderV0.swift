import CompanionInteractiveWire
import Foundation

public enum NetworkClientInteractiveInputSenderErrorV0:
    Error, Equatable, Sendable
{
    case invalidRole
    case closed
    case invalidFrameLength
    case sendFailed
}

/// Serialized reliable-input owner. Payloads may be coalesced before this
/// actor, but once the primary authority assigns a sequence every framed byte
/// is sent in order or the channel closes.
package actor NetworkClientInteractiveInputSenderV0 {
    package static let maximumJSONBytes = 65_536

    private let connection: NetworkClientInteractiveReadyRoleConnectionV0
    private let primary:
        any NetworkClientInteractiveInitialPrimaryControllingV0
    private var closed = false

    package init(
        connection: NetworkClientInteractiveReadyRoleConnectionV0,
        primary: any NetworkClientInteractiveInitialPrimaryControllingV0
    ) throws {
        guard connection.role == .input else {
            throw NetworkClientInteractiveInputSenderErrorV0.invalidRole
        }
        self.connection = connection
        self.primary = primary
    }

    package func send(
        _ payloads: [InteractiveInputPayload]
    ) async throws {
        guard !closed else {
            throw NetworkClientInteractiveInputSenderErrorV0.closed
        }
        for payload in payloads {
            let body = try await primary.makeInitialInputFrame(payload)
            do {
                try await connection.sendRoleBytes(try frame(body))
            } catch {
                await failClosed()
                throw NetworkClientInteractiveInputSenderErrorV0.sendFailed
            }
        }
    }

    package func close() async {
        guard !closed else { return }
        do {
            if let reset = try await primary.closeInitialInputFrame(),
               let framed = try? frame(reset) {
                try? await connection.sendRoleBytes(framed)
            }
        } catch {}
        await failClosed()
    }

    private func frame(_ body: Data) throws -> Data {
        guard !body.isEmpty,
              body.count <= Self.maximumJSONBytes else {
            throw NetworkClientInteractiveInputSenderErrorV0
                .invalidFrameLength
        }
        let length = UInt32(body.count)
        return Data([
            UInt8(length >> 24),
            UInt8((length >> 16) & 0xff),
            UInt8((length >> 8) & 0xff),
            UInt8(length & 0xff),
        ]) + body
    }

    private func failClosed() async {
        guard !closed else { return }
        closed = true
        await connection.cancel()
    }
}
