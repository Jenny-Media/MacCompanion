#if !DEBUG || !os(macOS)
#error("Disposable adversarial Act client is macOS Debug only")
#endif
@testable import CompanionClient
import CompanionClientNetworkPlatform
import CompanionNativeProviders
import CompanionWire
import CryptoKit
import Foundation
import Network

/// Uses real pinned TLS and application authentication, but deliberately omits
/// the UI/catalog guard so host-side denials and concurrent commands are tested.
actor ProbeActWireClient {
    enum Failure: Error { case connection, correlation, timeout, unexpectedResult }
    private actor Inbox {
        var ready = false
        var closed = false
        var frames: [WireUUID: Data] = [:]
        func becameReady() { ready = true }
        func becameClosed() { closed = true }
        func receive(_ frame: Data) throws {
            let metadata = try WireCodec.routingMetadata(from: frame)
            guard let correlation = metadata.correlationID, frames.count < 32, frames[correlation] == nil else {
                throw Failure.correlation
            }
            frames[correlation] = frame
        }
        func take(_ id: WireUUID) throws -> Data? {
            if let frame = frames.removeValue(forKey: id) { return frame }
            guard !closed else { throw Failure.connection }
            return nil
        }
    }
    private let pump: NetworkClientPrimaryFramePumpV0
    private let inbox: Inbox
    private init(pump: NetworkClientPrimaryFramePumpV0, inbox: Inbox) { self.pump = pump; self.inbox = inbox }

    static func connect(record: ClientDurablePairedHostV0, custody: any ClientIdentityKeyCustodyV0) async throws -> ProbeActWireClient {
        guard record.endpoints.count == 1, record.endpoints[0].value == "127.0.0.1",
              record.endpoints[0].port == 59_654 else { throw Failure.connection }
        let context = try NetworkClientTLSAttemptContextV0(endpoint: record.endpoints[0],
            requiredHostFingerprint: record.hostFingerprint, verificationQueue: DispatchQueue(label: "Probe.act.pin"),
            pinnedLeafEvaluator: SecurityClientPinnedLeafEvaluatorV0.make(wallNowUnixMilliseconds: ProbePairingClient.wall))
        let connection = try context.makeUnstartedConnection()
        connection.start(queue: DispatchQueue(label: "Probe.act.raw"))
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if case .ready = connection.state { break }
            if case .failed = connection.state { connection.cancel(); throw Failure.connection }
            try await Task.sleep(for: .milliseconds(10))
        }
        guard case .ready = connection.state else { connection.cancel(); throw Failure.timeout }
        do {
            let session = try ClientPrimarySessionV0(clientID: record.clientID, expectedHostID: record.hostID,
                expectedDeviceID: record.deviceID, requiredHostFingerprint: record.hostFingerprint,
                signer: ClientCustodiedSessionSignerV0(custody: custody, sessionKey: record.sessionKey))
            let inbox = Inbox()
            let pump = NetworkClientPrimaryFramePumpV0(connection: connection,
                tlsHandoff: try context.consumeVerifiedHandoff(for: connection), session: session,
                clock: { .init(wallNowUnixMilliseconds: ProbePairingClient.wall(), monotonicNowMilliseconds: ProbePairingClient.mono()) },
                readyForAuthenticatedTraffic: { Task { await inbox.becameReady() } },
                receivedCommand: { try await inbox.receive($0) }, terminal: { _ in Task { await inbox.becameClosed() } })
            let client = ProbeActWireClient(pump: pump, inbox: inbox)
            do {
                try await pump.beginOnVerifiedReadyConnection(.init(clientNonce: WireBytes32(P256.Signing.PrivateKey().rawRepresentation),
                    helloMessageID: WireUUID(UUID()), proofMessageID: WireUUID(UUID()),
                    wallNowUnixMilliseconds: ProbePairingClient.wall(), monotonicNowMilliseconds: ProbePairingClient.mono()))
                let authDeadline = ContinuousClock.now + .seconds(5)
                while !(await inbox.ready), !(await inbox.closed), ContinuousClock.now < authDeadline {
                    try await Task.sleep(for: .milliseconds(10))
                }
                guard await inbox.ready, !(await inbox.closed), await session.authenticatedSession?.deviceID == record.deviceID else { throw Failure.connection }
                return client
            } catch { await pump.cancel(); throw error }
        } catch { connection.cancel(); throw error }
    }

    func send<B: WireBody>(_ body: B) async throws -> WireUUID {
        let id = WireUUID(UUID())
        try await pump.sendAuthenticatedCommand(WireCodec.encode(WireEnvelope(messageID: id, correlationID: nil,
            sentAtUnixMilliseconds: ProbePairingClient.wall(), body: body)))
        return id
    }
    func reply<B: WireBody>(_ type: B.Type, to id: WireUUID) async throws -> B {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if let frame = try await inbox.take(id) {
                let response = try WireCodec.decode(WireEnvelope<B>.self, from: frame)
                guard response.correlationID == id else { throw Failure.correlation }
                return response.body
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw Failure.timeout
    }
    func close() async { await pump.cancel() }

    private func waitForClose() async throws {
        let deadline = ContinuousClock.now + .seconds(8)
        while !(await inbox.closed), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard await inbox.closed else { throw Failure.timeout }
    }

    static func fault(record: ClientDurablePairedHostV0, custody: any ClientIdentityKeyCustodyV0,
                      directory: URL, mode: String, emit: @escaping @Sendable (String) -> Void) async throws {
        let client = try await connect(record: record, custody: custody)
        do {
            let checkpoint = directory.appendingPathComponent("interrupted-act-operation.json")
            let operation: WireUUID
            if mode == "recover" {
                operation = WireUUID(try JSONDecoder().decode(UUID.self, from: Data(contentsOf: checkpoint)))
            } else {
                operation = WireUUID(UUID())
                if mode == "interrupt" {
                    try JSONEncoder().encode(operation.rawValue).write(to: checkpoint, options: .withoutOverwriting)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: checkpoint.path)
                }
            }
            let invoke = try OperationInvokeRequestBody(operationID: operation,
                capabilityID: NativeAudioMuteCapabilityV1.capabilityID,
                parameters: .object([.init(key: "muted", value: .boolean(true))]))
            if mode == "recover" {
                let statusID = try await client.send(OperationStatusRequestBody(operationID: operation))
                let status = try await client.reply(OperationStatusResponseBody.self, to: statusID)
                let invokeID = try await client.send(invoke)
                let replay = try await client.reply(OperationStatusResponseBody.self, to: invokeID)
                guard status.state == .outcomeUnknown, replay.state == .outcomeUnknown,
                      status.result == nil, replay.result == nil else { throw Failure.unexpectedResult }
                emit("act-interrupted-outcome-unknown-no-retry")
            } else {
                let invokeID = try await client.send(invoke)
                let agentDirectory = directory.appendingPathComponent("media.jenny.maccompanion/Agent/v1")
                let deadline = ContinuousClock.now + .seconds(3)
                let marker = agentDirectory.appendingPathComponent("audio-effect-reached")
                while !FileManager.default.fileExists(atPath: marker.path), ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(10))
                }
                guard FileManager.default.fileExists(atPath: marker.path) else { throw Failure.timeout }
                emit("act-provider-effect-observed")
                if mode == "interrupt" {
                    try await client.waitForClose()
                    emit("act-interrupted-primary-closed")
                } else if mode == "cancel" {
                    let statusID = try await client.send(OperationStatusRequestBody(operationID: operation))
                    let running = try await client.reply(OperationStatusResponseBody.self, to: statusID)
                    guard running.state == .running else { throw Failure.unexpectedResult }
                    for _ in 0..<2 {
                        let cancelID = try await client.send(OperationCancelRequestBody(operationID: operation))
                        let requested = try await client.reply(OperationStatusResponseBody.self, to: cancelID)
                        guard requested.state == .cancelRequested else { throw Failure.unexpectedResult }
                    }
                    emit("act-same-primary-running-status-and-cancel-requested")
                    let release = agentDirectory.appendingPathComponent("audio-effect-release")
                    try Data().write(to: release, options: .withoutOverwriting)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: release.path)
                    let completed = try await client.reply(OperationStatusResponseBody.self, to: invokeID)
                    guard completed.state == .succeeded else { throw Failure.unexpectedResult }
                    emit("act-cancel-request-not-false-cancellation-success")
                } else { throw Failure.unexpectedResult }
            }
            await client.close()
        } catch { await client.close(); throw error }
    }

    static func denied(record: ClientDurablePairedHostV0, custody: any ClientIdentityKeyCustodyV0,
                       emit: @escaping @Sendable (String) -> Void) async throws {
        let client = try await connect(record: record, custody: custody)
        do {
            let id = try await client.send(OperationInvokeRequestBody(operationID: WireUUID(UUID()),
                capabilityID: NativeAudioMuteCapabilityV1.capabilityID,
                parameters: .object([.init(key: "muted", value: .boolean(true))])))
            let response = try await client.reply(ProtocolErrorResponseBody.self, to: id)
            guard response.code == "policy.denied", response.retry == .afterUserAction else { throw Failure.unexpectedResult }
            emit("act-host-ungranted-invoke-denied")
            let foreign = WireUUID(UUID())
            let statusID = try await client.send(OperationStatusRequestBody(operationID: foreign))
            let status = try await client.reply(ProtocolErrorResponseBody.self, to: statusID)
            let cancelID = try await client.send(OperationCancelRequestBody(operationID: foreign))
            let cancel = try await client.reply(ProtocolErrorResponseBody.self, to: cancelID)
            guard status.code == "operation.notFound", cancel.code == status.code else { throw Failure.unexpectedResult }
            emit("act-host-unknown-status-and-cancel-opaque")
            await client.close()
        } catch { await client.close(); throw error }
    }
}
