import Foundation

public struct LengthPrefixedFrameDecoder: Sendable {
    private var buffer = Data()
    private var expectedPayloadLength: Int?

    public init() {}

    public mutating func append(_ bytes: Data) throws -> [Data] {
        var frames: [Data] = []
        var cursor = bytes.startIndex

        while cursor < bytes.endIndex {
            if expectedPayloadLength == nil {
                let headerBytesNeeded = 4 - buffer.count
                let headerEnd = bytes.index(
                    cursor,
                    offsetBy: min(headerBytesNeeded, bytes.distance(from: cursor, to: bytes.endIndex))
                )
                buffer.append(contentsOf: bytes[cursor..<headerEnd])
                cursor = headerEnd
                guard buffer.count == 4 else { break }

                let length = buffer.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
                buffer.removeAll(keepingCapacity: true)

                guard length > 0 else {
                    throw WireError.invalidFrame(reason: "zero-length frame")
                }
                guard length <= WireLimits.maximumFrameBytes else {
                    throw WireError.boundsExceeded(
                        field: "frame",
                        limit: WireLimits.maximumFrameBytes
                    )
                }
                expectedPayloadLength = length
            }

            guard let expectedPayloadLength else {
                continue
            }
            let payloadBytesNeeded = expectedPayloadLength - buffer.count
            let payloadEnd = bytes.index(
                cursor,
                offsetBy: min(payloadBytesNeeded, bytes.distance(from: cursor, to: bytes.endIndex))
            )
            buffer.append(contentsOf: bytes[cursor..<payloadEnd])
            cursor = payloadEnd

            if buffer.count == expectedPayloadLength {
                frames.append(buffer)
                buffer.removeAll(keepingCapacity: true)
                self.expectedPayloadLength = nil
            }
        }

        return frames
    }

    public static func encode(_ payload: Data) throws -> Data {
        guard !payload.isEmpty else {
            throw WireError.invalidFrame(reason: "zero-length frame")
        }
        guard payload.count <= WireLimits.maximumFrameBytes else {
            throw WireError.boundsExceeded(
                field: "frame",
                limit: WireLimits.maximumFrameBytes
            )
        }

        let length = UInt32(payload.count)
        return Data([
            UInt8(length >> 24),
            UInt8((length >> 16) & 0xff),
            UInt8((length >> 8) & 0xff),
            UInt8(length & 0xff),
        ]) + payload
    }
}
