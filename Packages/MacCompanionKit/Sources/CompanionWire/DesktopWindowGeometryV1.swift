import Foundation

private func desktopWords(_ data: Data) -> [Int64] {
    let bytes = Array(data)
    return stride(from: 8, to: bytes.count, by: 2).map { Int64(bytes[$0]) << 8 | Int64(bytes[$0 + 1]) }
}
public struct DesktopWindowQueryV1: Equatable, Sendable {
    public let sequence: Int64
    public let x, y, width, height: Int64
    public init(sequence: Int64, x: Int64, y: Int64, width: Int64, height: Int64) throws {
        guard (1...WireLimits.maximumSafeInteger).contains(sequence), (1...16384).contains(width),
              (1...16384).contains(height), (0..<width).contains(x), (0..<height).contains(y) else {
            throw WireError.invalidFrame(reason: "invalid desktop window query")
        }
        self.sequence = sequence; self.x = x; self.y = y; self.width = width; self.height = height
    }
    public init(data: Data) throws {
        guard data.count == 16 else { throw WireError.invalidFrame(reason: "invalid desktop query size") }
        let token = data.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        guard token <= UInt64(WireLimits.maximumSafeInteger) else { throw WireError.invalidFrame(reason: "invalid desktop query sequence") }
        let words = desktopWords(data)
        try self.init(sequence: Int64(token), x: words[0], y: words[1], width: words[2], height: words[3])
    }
    public var data: Data {
        var result = Data((0..<8).reversed().map { UInt8(truncatingIfNeeded: UInt64(sequence) >> ($0 * 8)) })
        for value in [x, y, width, height] { result.append(UInt8(value >> 8)); result.append(UInt8(value & 255)) }
        return result
    }
}
public struct DesktopWindowGeometryV1: Equatable, Sendable {
    public let query: DesktopWindowQueryV1
    public let rect: [Int64]
    public var hasWindow: Bool { rect[2] > 0 }
    public init(query: DesktopWindowQueryV1, rect: [Int64]) throws {
        guard rect.count == 4,
              rect == [0, 0, 0, 0] || (rect[0] >= 0 && rect[1] >= 0 && rect[2] > 0 && rect[3] > 0
                && rect[0] <= query.width && rect[1] <= query.height
                && rect[2] <= query.width - rect[0] && rect[3] <= query.height - rect[1]) else {
            throw WireError.invalidFrame(reason: "invalid desktop window rectangle")
        }
        self.query = query; self.rect = rect
    }
    public init(data: Data) throws {
        guard data.count == 24 else { throw WireError.invalidFrame(reason: "invalid desktop geometry size") }
        let query = try DesktopWindowQueryV1(data: Data(data.prefix(16)))
        try self.init(query: query, rect: Array(desktopWords(data).suffix(4)))
    }
    public var data: Data {
        var result = query.data
        for value in rect { result.append(UInt8(value >> 8)); result.append(UInt8(value & 255)) }
        return result
    }
}
