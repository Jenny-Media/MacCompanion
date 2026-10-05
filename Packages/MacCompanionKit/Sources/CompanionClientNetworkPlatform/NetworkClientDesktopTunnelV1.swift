import CompanionWire
import Foundation

/// Exact-primary stream lane. Frames are consumed with backpressure, and never
/// rerouted to another saved Mac or a later primary connection.
public actor NetworkClientDesktopTunnelV1 {
    public enum Failure: Error { case unavailable, invalidSequence, timeout }
    private let send: @Sendable (Data) async throws -> Void
    private var tunnelID: UUID?
    private var sessionID: UUID?
    private var incoming: Int64 = 0
    private var outgoing: Int64 = 1
    private var opening: CheckedContinuation<Void, Error>?
    private var consume: (@Sendable (Data) async throws -> Void)?
    private var ended: (@Sendable () -> Void)?
    private var invalidated = false
    private var closing = false
    private var sendTail: Task<Void, Error>?
    private var windowQuery: (DesktopWindowQueryV1, CheckedContinuation<DesktopWindowGeometryV1?, Error>)?

    init(send: @escaping @Sendable (Data) async throws -> Void) { self.send = send }

    public func open(sessionID: UUID, consume: @escaping @Sendable (Data) async throws -> Void,
                     ended: @escaping @Sendable () -> Void) async throws {
        guard !invalidated, !closing, tunnelID == nil else { throw Failure.unavailable }
        let id = UUID(); tunnelID = id; self.sessionID = sessionID
        incoming = 0; outgoing = 1; self.consume = consume; self.ended = ended
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            if !Task.isCancelled { await self?.failOpening(id) }
        }
        defer { timeout.cancel() }
        try await withCheckedThrowingContinuation { continuation in
            opening = continuation
            Task {
                do { try await self.transmit(.open, sequence: 0) }
                catch { self.failOpening(id) }
            }
        }
    }

    private func failOpening(_ id: UUID) {
        guard tunnelID == id else { return }
        finish()
    }

    public func sendBytes(_ data: Data) async throws {
        guard !invalidated, !closing, tunnelID != nil, opening == nil, incoming > 0,
              outgoing < WireLimits.maximumSafeInteger else { throw Failure.unavailable }
        for start in stride(from: 0, to: data.count, by: 16_384) {
            guard !invalidated, !closing, tunnelID != nil, opening == nil, incoming > 0,
                  outgoing < WireLimits.maximumSafeInteger else { throw Failure.unavailable }
            let chunk = data.subdata(in: start..<min(data.count, start + 16_384))
            let sequence = outgoing; outgoing += 1
            try await transmit(.data, sequence: sequence, data: chunk)
        }
    }

    public func windowAtPoint(x: Int64, y: Int64, width: Int64, height: Int64) async throws -> DesktopWindowGeometryV1? {
        guard !invalidated, !closing, tunnelID != nil, opening == nil, incoming > 0,
              windowQuery == nil, outgoing < WireLimits.maximumSafeInteger else { throw Failure.unavailable }
        let query = try DesktopWindowQueryV1(sequence: outgoing, x: x, y: y, width: width, height: height)
        // Reserve send order alongside stream order, before a child task or
        // suspended primary admission lets later input enter the sender.
        let transmission = try enqueue(.windowQuery, sequence: query.sequence, data: query.data)
        outgoing += 1
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { await self?.expireWindowQuery(query) }
        }
        defer { timeout.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            windowQuery = (query, continuation)
            Task {
                do { try await transmission.value }
                catch { self.expireWindowQuery(query) }
            }
        }
    }
    private func expireWindowQuery(_ query: DesktopWindowQueryV1) {
        guard let pending = windowQuery, pending.0 == query else { return }
        windowQuery = nil; pending.1.resume(returning: nil)
    }

    private func transmit(_ operation: DesktopTunnelOperationV1, sequence: Int64, data: Data = Data()) async throws {
        try await enqueue(operation, sequence: sequence, data: data).value
    }

    private func enqueue(_ operation: DesktopTunnelOperationV1, sequence: Int64, data: Data = Data()) throws -> Task<Void, Error> {
        guard !invalidated, let tunnelID, let sessionID else { throw Failure.unavailable }
        let frame = try WireCodec.encode(WireEnvelope(messageID: WireUUID(UUID()), correlationID: nil,
            sentAtUnixMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000),
            body: DesktopTunnelBodyV1(tunnelID: tunnelID, interactiveSessionID: sessionID,
                operation: operation, sequence: sequence, data: data)))
        let predecessor = sendTail
        let sender = send
        let transmission = Task { [weak self] in
            if let predecessor { try await predecessor.value }
            try Task.checkCancellation()
            guard let self, await self.isCurrent(tunnelID, sessionID: sessionID) else { throw Failure.unavailable }
            try await sender(frame)
        }
        sendTail = transmission
        return transmission
    }

    private func isCurrent(_ id: UUID, sessionID: UUID) -> Bool {
        !invalidated && tunnelID == id && self.sessionID == sessionID
    }

    func receive(_ frame: Data) async throws {
        let event = try WireCodec.decode(WireEnvelope<DesktopTunnelEventBodyV1>.self, from: frame).body.stream
        // A terminal event from an already locally closed tunnel is harmless.
        guard !invalidated, let tunnelID, event.tunnelID.rawValue == tunnelID else { return }
        guard event.interactiveSessionID.rawValue == sessionID, event.sequence == incoming,
              incoming < WireLimits.maximumSafeInteger else { finish(); throw Failure.invalidSequence }
        incoming += 1
        switch event.operation {
        case .opened:
            guard let opening, event.sequence == 0 else { finish(); throw Failure.invalidSequence }
            self.opening = nil; opening.resume()
        case .data:
            guard opening == nil, let consume else { finish(); throw Failure.invalidSequence }
            try await consume(event.data)
        case .closed: finish()
        case .windowGeometry:
            let geometry = try DesktopWindowGeometryV1(data: event.data)
            if let pending = windowQuery, pending.0 == geometry.query {
                windowQuery = nil; pending.1.resume(returning: geometry.hasWindow ? geometry : nil)
            }
        default: finish(); throw Failure.invalidSequence
        }
    }

    public func close() async {
        guard !closing else { return }
        let id = tunnelID
        let terminal = id != nil && !invalidated ? try? enqueue(.close, sequence: outgoing) : nil
        closing = true
        try? await terminal?.value
        if tunnelID == id { finish() }
    }
    func invalidate() { invalidated = true; finish() }
    private func finish() {
        let callback = ended; ended = nil; consume = nil
        opening?.resume(throwing: Failure.unavailable); opening = nil
        windowQuery?.1.resume(throwing: Failure.unavailable); windowQuery = nil
        sendTail?.cancel(); sendTail = nil; closing = false
        tunnelID = nil; sessionID = nil
        callback?()
    }
}
