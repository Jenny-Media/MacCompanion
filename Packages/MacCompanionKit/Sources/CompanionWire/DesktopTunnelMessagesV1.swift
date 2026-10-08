import Foundation

public enum DesktopTunnelOperationV1: String, Codable, Sendable {
    case open, opened, data, close, closed, windowQuery, windowGeometry
}

public struct DesktopTunnelBodyV1: WireBody {
    public static let kind = WireMessageKind.desktopTunnel
    public let tunnelID: WireUUID
    public let interactiveSessionID: WireUUID
    public let operation: DesktopTunnelOperationV1
    public let sequence: Int64
    public let bytes: [String]
    private enum CodingKeys: String, CodingKey { case tunnelID, interactiveSessionID, operation, sequence, bytes }
    public init(tunnelID: UUID, interactiveSessionID: UUID, operation: DesktopTunnelOperationV1,
                sequence: Int64, data: Data = Data()) throws {
        self.tunnelID = WireUUID(tunnelID); self.interactiveSessionID = WireUUID(interactiveSessionID)
        self.operation = operation; self.sequence = sequence; bytes = stride(from: 0, to: data.count, by: 3072).map { data.subdata(in: $0..<min($0 + 3072, data.count)).base64EncodedString() }
        try validate()
    }
    public init(from decoder: Decoder) throws {
        try requireExactKeys(decoder, ["tunnelID", "interactiveSessionID", "operation", "sequence", "bytes"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tunnelID = try c.decode(WireUUID.self, forKey: .tunnelID)
        interactiveSessionID = try c.decode(WireUUID.self, forKey: .interactiveSessionID)
        operation = try c.decode(DesktopTunnelOperationV1.self, forKey: .operation)
        sequence = try c.decode(Int64.self, forKey: .sequence); bytes = try c.decode([String].self, forKey: .bytes)
        try validate()
    }
    public var data: Data { bytes.reduce(into: Data()) { $0.append(Data(base64Encoded: $1) ?? Data()) } }
    public func validate() throws {
        guard bytes.count <= 6 else { throw WireError.invalidFrame(reason: "too many desktop segments") }
        for (index, segment) in bytes.enumerated() {
            guard segment.utf8.count <= 4096, let decoded = Data(base64Encoded: segment),
                  !decoded.isEmpty, decoded.count <= 3072, decoded.base64EncodedString() == segment,
                  index == bytes.count - 1 || decoded.count == 3072 else {
                throw WireError.invalidFrame(reason: "invalid desktop segment")
            }
        }
        let decoded = data
        guard sequence >= 0, sequence <= WireLimits.maximumSafeInteger, decoded.count <= 16_384,
              [.data, .windowQuery, .windowGeometry].contains(operation) ? !decoded.isEmpty : decoded.isEmpty,
              (operation == .open || operation == .opened) ? sequence == 0 : (operation == .closed || sequence > 0) else {
            throw WireError.invalidFrame(reason: "invalid desktop stream body")
        }
        if operation == .windowQuery {
            guard try DesktopWindowQueryV1(data: decoded).sequence == sequence else {
                throw WireError.invalidFrame(reason: "desktop query sequence mismatch")
            }
        } else if operation == .windowGeometry { _ = try DesktopWindowGeometryV1(data: decoded) }
    }
}

public struct DesktopTunnelEventBodyV1: WireBody {
    public static let kind = WireMessageKind.desktopTunnelEvent
    public let stream: DesktopTunnelBodyV1
    public init(_ stream: DesktopTunnelBodyV1) throws { self.stream = stream; try validate() }
    public init(from decoder: Decoder) throws { stream = try DesktopTunnelBodyV1(from: decoder); try validate() }
    public func encode(to encoder: Encoder) throws { try stream.encode(to: encoder) }
    public func validate() throws {
        try stream.validate()
        guard [.opened, .data, .closed, .windowGeometry].contains(stream.operation) else {
            throw WireError.invalidFrame(reason: "invalid desktop event operation")
        }
    }
}
