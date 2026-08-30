import Foundation
import Testing
@testable import LiveControlTestHost

@Test func journeyBridgeRoundTripAndCloseUnblockBothOwners() async throws {
    let bridge = JourneyCommandBridge(event: { _ in }, received: { _ in })
    let request = Data("request".utf8)
    let response = Data("{\"channel\":\"commands\"}".utf8)
    let worker = Task { () throws -> Data in
        #expect(try await bridge.readFrame() == request)
        try await bridge.sendFrame(response)
        return response
    }
    #expect(try await bridge.exchange(request) == response)
    _ = try await worker.value
    let pendingReader = Task { try await bridge.readFrame() }
    await bridge.close()
    await #expect(throws: (any Error).self) { _ = try await pendingReader.value }
    await #expect(throws: (any Error).self) { _ = try await bridge.exchange(request) }
    await bridge.close()
}

@Test func journeyBridgeCloseFailsPendingCommandInsteadOfHanging() async throws {
    let bridge = JourneyCommandBridge(event: { _ in }, received: { _ in })
    let pending = Task { try await bridge.exchange(Data("request".utf8)) }
    _ = try await bridge.readFrame()
    await bridge.close()
    await #expect(throws: (any Error).self) { _ = try await pending.value }
}
