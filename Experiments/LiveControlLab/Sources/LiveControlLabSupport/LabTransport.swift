import CryptoKit
import Foundation
import Network

public enum LabError: Error { case closed, invalidFrame, unauthorized, deadline, unsupported }

/// Local test bootstrap only. Never accepted by a production app or Agent.
public struct LabFixture: Codable, Sendable {
    public var port: UInt16
    public let source: String
    public let token: String
    public let hostID: UUID
    public var clientID: UUID
    public var deviceID: UUID
    public let pairingID: UUID
    public var displayID: UUID
    public var connectionID: Data
    public var fingerprint: Data
    public let sessionKey: Data
    public let approvalKey: Data
    public var journeyPort: UInt16?
    public var approvalPublicKey: Data?
    public var authorizationEpoch: UInt64?
    public var grantRevision: UInt64?

    public init(port: UInt16 = 0, source: String = "generated") {
        self.port = port
        self.source = source
        token = UUID().uuidString + UUID().uuidString
        hostID = UUID(); clientID = UUID(); deviceID = UUID()
        pairingID = UUID(); displayID = UUID()
        connectionID = withUnsafeBytes(of: UUID().uuid) { Data($0) }
        fingerprint = Data(SHA256.hash(data: Data(token.utf8)))
        sessionKey = P256.Signing.PrivateKey().rawRepresentation
        approvalKey = P256.Signing.PrivateKey().rawRepresentation
    }
}

/// Byte boundary shared by the legacy lab and verified TLS role connections.
public protocol LabByteConnection: Sendable {
    func read(_ count: Int) async throws -> Data
    func readFrame() async throws -> Data
    func send(_ data: Data) async throws
    func sendFrame(_ data: Data) async throws
    func close() async
}

public struct LabHello: Codable, Sendable {
    public let token: String
    public let role: String
    public let connectionID: Data?
    public init(token: String, role: String, connectionID: Data? = nil) {
        self.token = token; self.role = role; self.connectionID = connectionID
    }
}

public struct LabCommand: Codable, Sendable {
    public let action: String
    public init(_ action: String) { self.action = action }
}

public struct JourneyReport: Codable, Sendable {
    public let qr: String?
    public let pairedDevices: Int
    public let tlsConnections: Int
    public let authentications: Int
    public let observations: Int
    public let control: LabStatus?
    public let bootID: UUID?
    public init(qr: String?, pairedDevices: Int, tlsConnections: Int, authentications: Int, observations: Int, control: LabStatus? = nil, bootID: UUID? = nil) {
        self.qr = qr; self.pairedDevices = pairedDevices; self.tlsConnections = tlsConnections
        self.authentications = authentications; self.observations = observations
        self.control = control
        self.bootID = bootID
    }
}

public struct LabStatus: Codable, Sendable {
    public var source = "generated"
    public var inputEvents = 0
    public var textMatches = false
    public var directTextMatches = false
    public var pointerDelivered = false
    public var returnKeyDelivered = false
    public var transitions = 0
    public var acknowledgements = 0
    public var mediaRecords = 0
    public var renewals = 0
    public var renewalAttempts = 0
    public var renewalFailure: String?
    public var closed = false
    public var captureActive = false
    public var runtimeIdle = false
    public var queuedMediaRecords = 0
    public var approvalVerified = false
    public var retiredSessions = 0
    public var uncleanRetirements = 0
    public var statusRequests = 0
    public var failure: String?
    public var selectedDisplayOrdinal: Int?
    public var activeDisplayOrdinal: Int?
    public var displayCatalogRequests = 0
    public init() {}
}

/// Bounded loopback transport. Each role has one reader; writes are serialized.
/// This intentionally is not a replacement for the product's TLS/auth layer.
public actor LabConnection: LabByteConnection {
    private let connection: NWConnection
    private var tail = Task<Void, Never> {}
    public init(_ connection: NWConnection) { self.connection = connection }

    public func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [connection] state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error), .waiting(let error):
                    connection.stateUpdateHandler = nil
                    connection.cancel()
                    continuation.resume(throwing: error)
                case .cancelled:
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: LabError.closed)
                default: break
                }
            }
            connection.start(queue: DispatchQueue(label: "MacCompanion.Lab.socket"))
        }
    }

    public func read(_ count: Int) async throws -> Data {
        guard count >= 0, count <= 4_194_304 else { throw LabError.invalidFrame }
        if count == 0 { return Data() }
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, complete, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, data.count == count { continuation.resume(returning: data) }
                else { continuation.resume(throwing: complete ? LabError.closed : LabError.invalidFrame) }
            }
        }
    }

    public func readFrame() async throws -> Data {
        let prefix = try await read(4)
        let count = prefix.reduce(0) { ($0 << 8) | Int($1) }
        return try await read(count)
    }

    public func send(_ data: Data) async throws {
        let predecessor = tail
        let connection = connection
        let operation = Task {
            await predecessor.value
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                })
            }
        }
        tail = Task { _ = try? await operation.value }
        try await operation.value
    }

    public func sendFrame(_ data: Data) async throws {
        guard data.count <= 4_194_304 else { throw LabError.invalidFrame }
        var count = UInt32(data.count).bigEndian
        var result = withUnsafeBytes(of: &count) { Data($0) }
        result.append(data)
        try await send(result)
    }
    public func close() { connection.cancel() }

    public static func connect(fixture: LabFixture, role: String, connectionID: Data? = nil,
                               setupTimeout: Duration = .seconds(5)) async throws -> LabConnection {
        let connection = LabConnection(NWConnection(
            host: "127.0.0.1", port: NWEndpoint.Port(rawValue: fixture.port)!, using: .tcp
        ))
        let deadline = Task {
            do { try await Task.sleep(for: setupTimeout) } catch { return }
            await connection.close()
        }
        defer { deadline.cancel() }
        do {
            try await connection.start()
            try await connection.sendFrame(JSONEncoder().encode(LabHello(token: fixture.token, role: role, connectionID: connectionID)))
            guard try await connection.readFrame() == Data("ready".utf8) else { throw LabError.unauthorized }
            try Task.checkCancellation()
            return connection
        } catch {
            await connection.close()
            throw error
        }
    }
}
