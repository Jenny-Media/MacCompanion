@testable import CompanionClientNetworkPlatform
import CompanionWire
import CompanionTestSupport
import Foundation
import Testing

private actor DesktopTrafficV1 {
    var frames: [DesktopTunnelBodyV1] = []
    var bytes = Data()
    var ends = 0
    func sent(_ frame: Data) throws { frames.append(try WireCodec.decode(WireEnvelope<DesktopTunnelBodyV1>.self, from: frame).body) }
    func consumed(_ data: Data) { bytes.append(data) }
    func ended() { ends += 1 }
}

private actor DesktopSuspendedTrafficV1 {
    var frames: [DesktopTunnelBodyV1] = []
    var attempted: [Int64] = []
    private var firstWrite: CheckedContinuation<Void, Never>?
    func sent(_ frame: Data) async throws {
        let body = try WireCodec.decode(WireEnvelope<DesktopTunnelBodyV1>.self, from: frame).body
        attempted.append(body.sequence)
        if body.operation == .data && body.sequence == 1 {
            await withCheckedContinuation { firstWrite = $0 }
        }
        frames.append(body)
    }
    func release() { firstWrite?.resume(); firstWrite = nil }
}

@Test func desktopWindowQueryCannotOvertakeSuspendedVideoOrInputTraffic() async throws {
    let traffic = DesktopSuspendedTrafficV1()
    let lane = NetworkClientDesktopTunnelV1(send: { try await traffic.sent($0) })
    let opening = Task { try await lane.open(sessionID: UUID(), consume: { _ in }, ended: {}) }
    for _ in 0..<100 { if await !traffic.frames.isEmpty { break }; try await Task.sleep(for: .milliseconds(5)) }
    let open = try #require(await traffic.frames.first)
    try await lane.receive(desktopEventV1(open, operation: .opened, sequence: 0)); try await opening.value
    let first = Task { try await lane.sendBytes(Data([1])) }
    for _ in 0..<100 { if await traffic.attempted.contains(1) { break }; try await Task.sleep(for: .milliseconds(5)) }
    #expect(await traffic.attempted == [0, 1])
    let fixture = try Data(contentsOf: FixturePaths.authoritativeFixtures().appendingPathComponent("valid/desktop-window-geometry.json"))
    let golden = try DesktopWindowGeometryV1(data: WireCodec.decode(WireEnvelope<DesktopTunnelEventBodyV1>.self, from: fixture).body.stream.data)
    let lookup = Task { try await lane.windowAtPoint(x: golden.query.x, y: golden.query.y, width: golden.query.width, height: golden.query.height) }
    try await Task.sleep(for: .milliseconds(20))
    let second = Task { try await lane.sendBytes(Data([2])) }
    try await Task.sleep(for: .milliseconds(20))
    // A primary sender can suspend during authentication/admission. No later
    // tunnel operation may enter that sender before the predecessor completes.
    #expect(await traffic.attempted == [0, 1])
    await traffic.release(); try await first.value; try await second.value
    for _ in 0..<100 { if await traffic.frames.contains(where: { $0.operation == .windowQuery }) { break }; try await Task.sleep(for: .milliseconds(5)) }
    let request = try #require(await traffic.frames.first(where: { $0.operation == .windowQuery }))
    let geometry = try DesktopWindowGeometryV1(query: DesktopWindowQueryV1(data: request.data), rect: golden.rect)
    try await lane.receive(desktopEventV1(open, operation: .windowGeometry, sequence: 1, data: geometry.data))
    #expect(try await lookup.value == geometry)
    #expect(await traffic.frames.map(\.sequence) == [0, 1, 2, 3])
    await lane.close()
}

@Test func desktopTunnelRetirementRejectsWritesQueuedBehindSuspendedSend() async throws {
    let traffic = DesktopSuspendedTrafficV1()
    let lane = NetworkClientDesktopTunnelV1(send: { try await traffic.sent($0) })
    let opening = Task { try await lane.open(sessionID: UUID(), consume: { _ in }, ended: {}) }
    for _ in 0..<100 { if await !traffic.frames.isEmpty { break }; try await Task.sleep(for: .milliseconds(5)) }
    let open = try #require(await traffic.frames.first)
    try await lane.receive(desktopEventV1(open, operation: .opened, sequence: 0)); try await opening.value
    let first = Task { try await lane.sendBytes(Data([1])) }
    for _ in 0..<100 { if await traffic.attempted.contains(1) { break }; try await Task.sleep(for: .milliseconds(5)) }
    let queued = Task { try await lane.sendBytes(Data([2])) }
    try await Task.sleep(for: .milliseconds(20))
    await lane.invalidate(); await traffic.release()
    try await first.value
    await #expect(throws: (any Error).self) { try await queued.value }
    #expect(await traffic.attempted == [0, 1])
}

@Test func desktopTunnelClosePreventsRemainingChunksOfSuspendedWrite() async throws {
    let traffic = DesktopSuspendedTrafficV1()
    let lane = NetworkClientDesktopTunnelV1(send: { try await traffic.sent($0) })
    let opening = Task { try await lane.open(sessionID: UUID(), consume: { _ in }, ended: {}) }
    for _ in 0..<100 { if await !traffic.frames.isEmpty { break }; try await Task.sleep(for: .milliseconds(5)) }
    let open = try #require(await traffic.frames.first)
    try await lane.receive(desktopEventV1(open, operation: .opened, sequence: 0)); try await opening.value
    let chunks = Task { try await lane.sendBytes(Data(repeating: 1, count: 40_000)) }
    for _ in 0..<100 { if await traffic.attempted.contains(1) { break }; try await Task.sleep(for: .milliseconds(5)) }
    let closing = Task { await lane.close() }
    try await Task.sleep(for: .milliseconds(20))
    await traffic.release(); await closing.value
    await #expect(throws: (any Error).self) { try await chunks.value }
    #expect(await traffic.frames.map(\.operation) == [.open, .data, .close])
    #expect(await traffic.frames.map(\.sequence) == [0, 1, 2])
}

@Test func desktopWindowLookupKeepsVideoBytesSeparateAndRetirementReleasesItsWaiter() async throws {
    let traffic = DesktopTrafficV1()
    let lane = NetworkClientDesktopTunnelV1(send: { try await traffic.sent($0) })
    let opening = Task { try await lane.open(sessionID: UUID(), consume: { await traffic.consumed($0) }, ended: {}) }
    for _ in 0..<100 { if await !traffic.frames.isEmpty { break }; try await Task.sleep(for: .milliseconds(5)) }
    let open = try #require(await traffic.frames.first)
    try await lane.receive(desktopEventV1(open, operation: .opened, sequence: 0)); try await opening.value
    let fixture = try Data(contentsOf: FixturePaths.authoritativeFixtures().appendingPathComponent("valid/desktop-window-geometry.json"))
    let golden = try WireCodec.decode(WireEnvelope<DesktopTunnelEventBodyV1>.self, from: fixture).body.stream
    let geometry = try DesktopWindowGeometryV1(data: golden.data)
    let query = geometry.query
    let lookup = Task { try await lane.windowAtPoint(x: query.x, y: query.y, width: query.width, height: query.height) }
    for _ in 0..<100 { if await traffic.frames.last?.operation == .windowQuery { break }; try await Task.sleep(for: .milliseconds(5)) }
    #expect(await traffic.frames.last?.data == query.data)
    try await lane.receive(desktopEventV1(open, operation: .data, sequence: 1, data: Data([1, 2])))
    try await lane.receive(desktopEventV1(open, operation: .windowGeometry, sequence: 2, data: geometry.data))
    #expect(try await lookup.value == geometry)
    #expect(await traffic.bytes == Data([1, 2]))
    let pending = Task { try await lane.windowAtPoint(x: query.x, y: query.y, width: query.width, height: query.height) }
    for _ in 0..<100 { if await traffic.frames.count == 3 { break }; try await Task.sleep(for: .milliseconds(5)) }
    // A late result from the completed request cannot satisfy a later request.
    try await lane.receive(desktopEventV1(open, operation: .windowGeometry, sequence: 3, data: geometry.data))
    await lane.invalidate()
    await #expect(throws: (any Error).self) { try await pending.value }
    #expect(await traffic.bytes == Data([1, 2]))
}
private func desktopEventV1(_ open: DesktopTunnelBodyV1, operation: DesktopTunnelOperationV1, sequence: Int64, data: Data = Data()) throws -> Data {
    try WireCodec.encode(WireEnvelope(messageID: WireUUID(UUID()), correlationID: nil, channel: .events, sentAtUnixMilliseconds: 5_000,
        body: DesktopTunnelEventBodyV1(DesktopTunnelBodyV1(tunnelID: open.tunnelID.rawValue,
            interactiveSessionID: open.interactiveSessionID.rawValue, operation: operation, sequence: sequence, data: data))))
}

@Test func desktopTunnelStreamsInOrderAndRejectsSkippedOrRetiredFrames() async throws {
    let traffic = DesktopTrafficV1()
    let lane = NetworkClientDesktopTunnelV1(send: { try await traffic.sent($0) })
    let opening = Task { try await lane.open(sessionID: UUID(), consume: { await traffic.consumed($0) }, ended: { Task { await traffic.ended() } }) }
    for _ in 0..<100 { if await !traffic.frames.isEmpty { break }; try await Task.sleep(for: .milliseconds(5)) }
    let open = try #require(await traffic.frames.first)
    try await lane.receive(desktopEventV1(open, operation: .opened, sequence: 0))
    try await opening.value
    try await lane.sendBytes(Data(repeating: 0x31, count: 40_000))
    #expect(await traffic.frames.map(\.sequence) == [0, 1, 2, 3])
    #expect(await traffic.frames.dropFirst().map { $0.data.count } == [16_384, 16_384, 7_232])
    let bytes = Data([0, 1, 2, 3])
    try await lane.receive(desktopEventV1(open, operation: .data, sequence: 1, data: bytes))
    #expect(await traffic.bytes == bytes)
    await #expect(throws: (any Error).self) {
        try await lane.receive(desktopEventV1(open, operation: .data, sequence: 3, data: bytes))
    }
    await #expect(throws: (any Error).self) { try await lane.sendBytes(bytes) }
    try await lane.receive(desktopEventV1(open, operation: .data, sequence: 2, data: bytes))
    #expect(await traffic.bytes == bytes)
}

@Test func desktopTunnelOpeningFailureAndPrimaryLossReleaseWaiters() async throws {
    let traffic = DesktopTrafficV1()
    let lane = NetworkClientDesktopTunnelV1(send: { try await traffic.sent($0) })
    let opening = Task { try await lane.open(sessionID: UUID(), consume: { _ in }, ended: {}) }
    for _ in 0..<100 { if await !traffic.frames.isEmpty { break }; try await Task.sleep(for: .milliseconds(5)) }
    let open = try #require(await traffic.frames.first)
    try await lane.receive(desktopEventV1(open, operation: .closed, sequence: 0))
    await #expect(throws: (any Error).self) { try await opening.value }
    let replacement = Task { try await lane.open(sessionID: UUID(), consume: { _ in }, ended: {}) }
    try await Task.sleep(for: .milliseconds(10))
    await lane.invalidate()
    await #expect(throws: (any Error).self) { try await replacement.value }
    await #expect(throws: (any Error).self) { try await lane.sendBytes(Data([1])) }
}
