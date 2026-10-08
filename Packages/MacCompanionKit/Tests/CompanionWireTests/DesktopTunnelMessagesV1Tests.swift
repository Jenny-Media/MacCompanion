import CompanionTestSupport
import CompanionWire
import Foundation
import Testing

@Test func desktopTunnelAuthoritativeMessagesHaveClosedBounds() throws {
    let root = FixturePaths.authoritativeFixtures()
    for name in ["desktop-tunnel-open", "desktop-tunnel-data", "desktop-window-query"] {
        let data = try Data(contentsOf: root.appendingPathComponent("valid/\(name).json"))
        let envelope = try WireCodec.decode(WireEnvelope<DesktopTunnelBodyV1>.self, from: data)
        #expect(try WireCodec.routingMetadata(from: data).correlationID == nil)
        #expect(try WireCodec.decode(WireEnvelope<DesktopTunnelBodyV1>.self, from: WireCodec.encode(envelope)) == envelope)
    }
    for name in ["desktop-tunnel-opened", "desktop-tunnel-closed", "desktop-window-geometry"] {
        let data = try Data(contentsOf: root.appendingPathComponent("valid/\(name).json"))
        #expect(try WireCodec.decode(WireEnvelope<DesktopTunnelEventBodyV1>.self, from: data).channel == .events)
    }
    let fixture = try Data(contentsOf: root.appendingPathComponent("valid/desktop-tunnel-data.json"))
    for field in ["endpoint", "port", "password"] {
        var value = try JSONSerialization.jsonObject(with: fixture) as! [String: Any]
        var body = value["body"] as! [String: Any]; body[field] = "untrusted"; value["body"] = body
        let bad = try JSONSerialization.data(withJSONObject: value)
        #expect(throws: (any Error).self) { try WireCodec.decode(WireEnvelope<DesktopTunnelBodyV1>.self, from: bad) }
    }
    let id = UUID()
    #expect(throws: (any Error).self) {
        try DesktopTunnelBodyV1(tunnelID: id, interactiveSessionID: id, operation: .data, sequence: 1, data: Data(repeating: 0, count: 16_385))
    }
    #expect(throws: (any Error).self) {
        try DesktopTunnelBodyV1(tunnelID: id, interactiveSessionID: id, operation: .open, sequence: 1)
    }
}

@Test func desktopWindowQueriesAndRectanglesHaveIndexedClosedBounds() throws {
    let data = try Data(contentsOf: FixturePaths.authoritativeFixtures().appendingPathComponent("vnc-desktop-tunnel-v0.1.json"))
    let profile = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    for row in profile["windowQueryCases"] as! [[String: Any]] {
        let point = row["point"] as! [Int64], size = row["framebuffer"] as! [Int64]
        func construct() throws -> DesktopWindowGeometryV1 {
            let query = try DesktopWindowQueryV1(sequence: row["sequence"] as! Int64,
                x: point[0], y: point[1], width: size[0], height: size[1])
            #expect(try DesktopWindowQueryV1(data: query.data) == query)
            let geometry = try DesktopWindowGeometryV1(query: query, rect: row["rect"] as! [Int64])
            #expect(try DesktopWindowGeometryV1(data: geometry.data) == geometry)
            return geometry
        }
        if row["allowed"] as! Bool { _ = try construct() }
        else { #expect(throws: (any Error).self) { try construct() } }
    }
    for count in [0, 8, 15, 17, 64] {
        #expect(throws: (any Error).self) { try DesktopWindowQueryV1(data: Data(repeating: 0, count: count)) }
    }
}
