import Foundation
import Network
import CompanionWire
import OSLog

/// One bounded relay to the system Screen Sharing service. No caller-selected
/// endpoint, credential persistence, unbounded buffering, or upstream logging.
actor NetworkHostDesktopTunnelV1 {
    enum Failure: Error { case closed, sequence, unavailable }
    let tunnelID: UUID
    let sessionID: UUID
    private let connection = NWConnection(host: "127.0.0.1", port: 5900, using: .tcp)
    private let authorize: @Sendable () async throws -> Void
    private let emit: @Sendable (DesktopTunnelBodyV1) async throws -> Void
    private let windowLookup: @Sendable (DesktopWindowQueryV1) throws -> DesktopWindowGeometryV1
    private var incoming: Int64 = 1
    private var outgoing: Int64 = 0
    private var stopped = false
    private var ready: CheckedContinuation<Void, Error>?
    private var watchdog: Task<Void, Never>?
    private var reader: Task<Void, Never>?
    private var sendTail: Task<Void, Error>?

    init(body: DesktopTunnelBodyV1, authorize: @escaping @Sendable () async throws -> Void,
         emit: @escaping @Sendable (DesktopTunnelBodyV1) async throws -> Void,
         windowLookup: @escaping @Sendable (DesktopWindowQueryV1) throws -> DesktopWindowGeometryV1 = { try DesktopWindowBoundsProjectionV1.system($0) }) {
        tunnelID = body.tunnelID.rawValue; sessionID = body.interactiveSessionID.rawValue
        self.authorize = authorize; self.emit = emit
        self.windowLookup = windowLookup
    }

    func start() async throws {
        guard !stopped else { throw Failure.closed }
        connection.stateUpdateHandler = { [weak self] state in
            Task { await self?.state(state) }
        }
        let timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { await self?.close() }
        }
        defer { timeout.cancel() }
        do {
            try await withCheckedThrowingContinuation { continuation in
                ready = continuation
                connection.start(queue: DispatchQueue(label: "media.jenny.maccompanion.desktop.loopback"))
            }
            try await authorize()
            guard !stopped else { throw Failure.closed }
            // Reserve the terminal sequence before the send can suspend. Stop
            // may close this relay while opened is queued on the primary.
            outgoing = 1
            try await enqueue(DesktopTunnelBodyV1(tunnelID: tunnelID, interactiveSessionID: sessionID, operation: .opened, sequence: 0)).value
            guard !stopped else { throw Failure.closed }
            reader = Task { [weak self] in await self?.readLoop() }
            watchdog = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(200)); try await self?.check() }
                    catch { await self?.close(); return }
                }
            }
        } catch { await close(); throw error }
    }

    private func state(_ state: NWConnection.State) async {
        switch state {
        case .ready: ready?.resume(); ready = nil
        case .failed, .cancelled: await close()
        default: break
        }
    }

    private func check() async throws {
        guard !stopped else { throw Failure.closed }
        try await authorize()
        guard !stopped else { throw Failure.closed }
    }

    func receive(_ body: DesktopTunnelBodyV1) async throws {
        guard !stopped, body.tunnelID.rawValue == tunnelID, body.interactiveSessionID.rawValue == sessionID,
              body.sequence == incoming, incoming < WireLimits.maximumSafeInteger else { throw Failure.sequence }
        incoming += 1
        if body.operation == .close { await close(); return }
        try await check()
        if body.operation == .windowQuery {
            guard outgoing > 0 else { throw Failure.unavailable }
            let query = try DesktopWindowQueryV1(data: body.data)
            let geometry = try windowLookup(query)
            try await check()
            guard geometry.query == query, outgoing < WireLimits.maximumSafeInteger else { throw Failure.sequence }
            let response = try DesktopTunnelBodyV1(tunnelID: tunnelID, interactiveSessionID: sessionID,
                operation: .windowGeometry, sequence: outgoing, data: geometry.data)
            outgoing += 1; try await enqueue(response).value
            Logger(subsystem: "media.jenny.maccompanion", category: "desktop-window").info("window query completed hasWindow=\(geometry.hasWindow, privacy: .public)")
            return
        }
        guard body.operation == .data else { throw Failure.sequence }
        let data = body.data
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if error == nil { continuation.resume() } else { continuation.resume(throwing: Failure.unavailable) }
            })
        }
    }

    private func readLoop() async {
        do {
            while !stopped {
                let data: Data = try await withCheckedThrowingContinuation { continuation in
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, complete, error in
                        if error != nil || complete || data?.isEmpty != false { continuation.resume(throwing: Failure.closed) }
                        else { continuation.resume(returning: data!) }
                    }
                }
                try await check()
                guard outgoing < WireLimits.maximumSafeInteger else { throw Failure.sequence }
                let body = try DesktopTunnelBodyV1(tunnelID: tunnelID, interactiveSessionID: sessionID,
                    operation: .data, sequence: outgoing, data: data)
                outgoing += 1
                // A new socket read begins only after the encrypted send completes.
                try await enqueue(body).value
            }
        } catch { await close() }
    }

    private func enqueue(_ body: DesktopTunnelBodyV1, terminal: Bool = false) -> Task<Void, Error> {
        let predecessor = sendTail
        let emitter = emit
        let transmission = Task { [weak self] in
            if let predecessor {
                if terminal { _ = try? await predecessor.value }
                else { try await predecessor.value }
            }
            try Task.checkCancellation()
            if !terminal {
                guard let self else { throw Failure.closed }
                try await self.check()
            }
            try await emitter(body)
        }
        sendTail = transmission
        return transmission
    }

    func close() async {
        guard !stopped else { return }
        stopped = true
        ready?.resume(throwing: Failure.closed); ready = nil
        reader?.cancel(); watchdog?.cancel(); connection.cancel()
        if let body = try? DesktopTunnelBodyV1(tunnelID: tunnelID, interactiveSessionID: sessionID,
            operation: .closed, sequence: outgoing) {
            let terminal = enqueue(body, terminal: true)
            Task { try? await terminal.value }
        }
    }
}
