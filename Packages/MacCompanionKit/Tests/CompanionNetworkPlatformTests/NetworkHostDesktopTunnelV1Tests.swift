@testable import CompanionNetworkPlatform
import CompanionWire
import CompanionTestSupport
import Foundation
import Testing

private actor DesktopLoopbackProbeV1 {
    var allowed = true
    var events: [DesktopTunnelBodyV1] = []
    func authorize() throws { if !allowed { throw NetworkHostDesktopTunnelV1.Failure.unavailable } }
    func emit(_ body: DesktopTunnelBodyV1) { events.append(body) }
    func revoke() { allowed = false }
    var greeting: Data { events.filter { $0.operation == .data }.reduce(into: Data()) { $0.append($1.data) } }
    var closed: Bool { events.contains { $0.operation == .closed } }
}

private actor DesktopSuspendedEventV1 {
    var events: [DesktopTunnelBodyV1] = []
    var attempted: [Int64] = []
    private var firstRead: CheckedContinuation<Void, Never>?
    func emit(_ body: DesktopTunnelBodyV1) async {
        attempted.append(body.sequence)
        if body.operation == .data && body.sequence == 1 {
            await withCheckedContinuation { firstRead = $0 }
        }
        events.append(body)
    }
    func release() { firstRead?.resume(); firstRead = nil }
}

// Greeting-only probe, with synthetic window geometry; no Mac login or pixels.
@Test(.enabled(if: ProcessInfo.processInfo.environment["MACCOMPANION_VNC_HOST_PROBE"] == "1"))
func desktopWindowResponseCannotOvertakeSuspendedRFBGreeting() async throws {
    let probe = DesktopSuspendedEventV1()
    let open = try DesktopTunnelBodyV1(tunnelID: UUID(), interactiveSessionID: UUID(), operation: .open, sequence: 0)
    let fixture = try Data(contentsOf: FixturePaths.authoritativeFixtures().appendingPathComponent("valid/desktop-window-geometry.json"))
    let golden = try DesktopWindowGeometryV1(data: WireCodec.decode(WireEnvelope<DesktopTunnelEventBodyV1>.self, from: fixture).body.stream.data)
    let relay = NetworkHostDesktopTunnelV1(body: open, authorize: {}, emit: { await probe.emit($0) },
        windowLookup: { try DesktopWindowGeometryV1(query: $0, rect: golden.rect) })
    try await relay.start()
    for _ in 0..<100 { if await probe.attempted.contains(1) { break }; try await Task.sleep(for: .milliseconds(5)) }
    #expect(await probe.attempted == [0, 1])
    let request = try DesktopTunnelBodyV1(tunnelID: open.tunnelID.rawValue, interactiveSessionID: open.interactiveSessionID.rawValue,
        operation: .windowQuery, sequence: 1, data: golden.query.data)
    let lookup = Task { try await relay.receive(request) }
    try await Task.sleep(for: .milliseconds(20))
    #expect(await probe.attempted == [0, 1])
    await probe.release(); try await lookup.value
    #expect(await probe.events.map(\.sequence) == [0, 1, 2])
    #expect(await probe.events.last?.data == golden.data)
    await relay.close()
}

@Test func desktopTunnelClosedBeforeStartDoesNotLeaveReadinessWaiter() async throws {
    let body = try DesktopTunnelBodyV1(tunnelID: UUID(), interactiveSessionID: UUID(), operation: .open, sequence: 0)
    let relay = NetworkHostDesktopTunnelV1(body: body, authorize: {}, emit: { _ in })
    await relay.close()
    await #expect(throws: (any Error).self) { try await relay.start() }
}

// Opt-in local check against the already enabled system service. It exchanges
// only the RFB greeting: no authentication, framebuffer or input is requested.
@Test(.enabled(if: ProcessInfo.processInfo.environment["MACCOMPANION_VNC_HOST_PROBE"] == "1"))
func desktopTunnelSystemGreetingAndIdleAuthorityLossCloseLoopback() async throws {
    let probe = DesktopLoopbackProbeV1()
    let relay = NetworkHostDesktopTunnelV1(body: try DesktopTunnelBodyV1(tunnelID: UUID(), interactiveSessionID: UUID(), operation: .open, sequence: 0),
        authorize: { try await probe.authorize() }, emit: { await probe.emit($0) })
    try await relay.start()
    for _ in 0..<100 { if await probe.greeting.count >= 12 { break }; try await Task.sleep(for: .milliseconds(10)) }
    #expect(await probe.greeting.prefix(4) == Data("RFB ".utf8))
    #expect(await probe.events.first?.operation == .opened)
    await probe.revoke()
    for _ in 0..<100 { if await probe.closed { break }; try await Task.sleep(for: .milliseconds(10)) }
    #expect(await probe.closed)
    #expect(await probe.events.last?.operation == .closed)
    await relay.close()
}
