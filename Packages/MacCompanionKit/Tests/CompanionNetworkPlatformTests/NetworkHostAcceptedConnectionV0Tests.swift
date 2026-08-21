@testable import CompanionNetworkPlatform
import CompanionSecurity
import CompanionTransport
import CryptoKit
import Dispatch
import Foundation
import Network
import Testing

private final class NetworkHostAcceptedFakeIOV0:
    NetworkHostAcceptedConnectionIOV0,
    @unchecked Sendable
{
    let connection: NWConnection
    private let lock = NSLock()
    private var handler: (@Sendable (
        NetworkHostAcceptedConnectionIOStateV0
    ) -> Void)?
    private var starts = 0
    private var cancels = 0

    init(connection: NWConnection) {
        self.connection = connection
    }

    var startCount: Int { lock.withLock { starts } }
    var cancelCount: Int { lock.withLock { cancels } }

    func setStateUpdateHandler(
        _ handler: @escaping @Sendable (
            NetworkHostAcceptedConnectionIOStateV0
        ) -> Void
    ) {
        lock.withLock { self.handler = handler }
    }

    func start(queue: DispatchQueue) {
        lock.withLock { starts += 1 }
    }

    func cancel() {
        lock.withLock { cancels += 1 }
    }

    func emit(_ state: NetworkHostAcceptedConnectionIOStateV0) {
        let callback = lock.withLock { handler }
        callback?(state)
    }
}

private final class NetworkHostListenerFakeIOV0:
    NetworkHostListenerIOV0,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var stateHandler: (@Sendable (
        NetworkHostListenerIOStateV0
    ) -> Void)?
    private var connectionHandler: (@Sendable (NWConnection) -> Void)?
    private var advertisementHandler: (@Sendable (Bool) -> Void)?
    private var starts = 0
    private var cancels = 0

    var startCount: Int { lock.withLock { starts } }
    var cancelCount: Int { lock.withLock { cancels } }

    func setStateUpdateHandler(
        _ handler: @escaping @Sendable (
            NetworkHostListenerIOStateV0
        ) -> Void
    ) {
        lock.withLock { stateHandler = handler }
    }

    func setNewConnectionHandler(
        _ handler: @escaping @Sendable (NWConnection) -> Void
    ) {
        lock.withLock { connectionHandler = handler }
    }

    func setServiceRegistrationUpdateHandler(
        _ handler: @escaping @Sendable (Bool) -> Void
    ) {
        lock.withLock { advertisementHandler = handler }
    }

    func start(queue: DispatchQueue) {
        lock.withLock { starts += 1 }
    }

    func cancel() {
        lock.withLock { cancels += 1 }
    }

    func emit(_ state: NetworkHostListenerIOStateV0) {
        let callback = lock.withLock { stateHandler }
        callback?(state)
    }

    func accept(_ connection: NWConnection) {
        let callback = lock.withLock { connectionHandler }
        callback?(connection)
    }

    func emitAdvertisement(_ ready: Bool) {
        let callback = lock.withLock { advertisementHandler }
        callback?(ready)
    }
}

private final class NetworkHostAcceptedRecorderV0: @unchecked Sendable {
    private let lock = NSLock()
    private var readyStorage: [NetworkHostVerifiedReadyConnectionV0] = []
    private var terminalStorage:
        [NetworkHostAcceptedConnectionTerminationReasonV0] = []
    private var evaluatedStorage: [NWConnection] = []

    var ready: [NetworkHostVerifiedReadyConnectionV0] {
        lock.withLock { readyStorage }
    }
    var terminals: [NetworkHostAcceptedConnectionTerminationReasonV0] {
        lock.withLock { terminalStorage }
    }
    var evaluated: [NWConnection] { lock.withLock { evaluatedStorage } }

    func recordReady(_ value: NetworkHostVerifiedReadyConnectionV0) {
        lock.withLock { readyStorage.append(value) }
    }

    func recordTerminal(
        _ value: NetworkHostAcceptedConnectionTerminationReasonV0
    ) {
        lock.withLock { terminalStorage.append(value) }
    }

    func recordEvaluated(_ value: NWConnection) {
        lock.withLock { evaluatedStorage.append(value) }
    }
}

private final class NetworkHostListenerRecorderV0: @unchecked Sendable {
    private let lock = NSLock()
    private var acceptedStorage: [NetworkHostAcceptedConnectionV0] = []
    private var terminalStorage: [NetworkHostListenerTerminationReasonV0] = []
    private var advertisementStorage: [Bool] = []
    private var readyStorage = 0

    var accepted: [NetworkHostAcceptedConnectionV0] {
        lock.withLock { acceptedStorage }
    }
    var terminals: [NetworkHostListenerTerminationReasonV0] {
        lock.withLock { terminalStorage }
    }
    var readyCount: Int { lock.withLock { readyStorage } }
    var advertisementReadiness: [Bool] {
        lock.withLock { advertisementStorage }
    }

    func recordReady() {
        lock.withLock { readyStorage += 1 }
    }

    func recordAdvertisement(_ ready: Bool) {
        lock.withLock { advertisementStorage.append(ready) }
    }

    func recordAccepted(_ value: NetworkHostAcceptedConnectionV0) {
        lock.withLock { acceptedStorage.append(value) }
    }

    func recordTerminal(_ value: NetworkHostListenerTerminationReasonV0) {
        lock.withLock { terminalStorage.append(value) }
    }
}

private func networkHostAcceptedTestIdentity() throws -> (Data, Data) {
    let key = P256.Signing.PrivateKey()
    let spki = try CompanionSecurityV0.p256SubjectPublicKeyInfoDER(
        publicKeyX963: key.publicKey.x963Representation
    )
    return (
        spki,
        try CompanionSecurityV0.hostFingerprint(
            subjectPublicKeyInfoDER: spki
        )
    )
}

private func networkHostAcceptedTestConnection() -> NWConnection {
    NWConnection(host: "127.0.0.1", port: 9, using: .tcp)
}

@Test func acceptedConnectionEvaluatesTheExactReadyConnection() throws {
    let identity = try networkHostAcceptedTestIdentity()
    let connection = networkHostAcceptedTestConnection()
    let io = NetworkHostAcceptedFakeIOV0(connection: connection)
    let recorder = NetworkHostAcceptedRecorderV0()
    let authority = NetworkHostAcceptedConnectionV0(
        io: io,
        servedSubjectPublicKeyInfoDER: identity.0,
        requiredHostFingerprint: identity.1,
        metadataEvaluator: { evaluated in
            recorder.recordEvaluated(evaluated)
            return NetworkHostTLSMetadataFactsV0(
                negotiatedTLSMajor: 1,
                negotiatedTLSMinor: 3,
                earlyDataAccepted: false
            )
        }
    )

    try authority.start(
        queue: DispatchQueue(label: "MacCompanionTests.AcceptedReady"),
        ready: recorder.recordReady,
        terminal: recorder.recordTerminal
    )
    #expect(io.startCount == 1)
    #expect(throws: NetworkHostAcceptedConnectionErrorV0.alreadyStarted) {
        try authority.start(
            queue: DispatchQueue(label: "MacCompanionTests.AcceptedTwice"),
            ready: recorder.recordReady
        )
    }
    io.emit(.setup)
    io.emit(.preparing)
    io.emit(.waiting)
    #expect(recorder.ready.isEmpty)

    io.emit(.ready)

    #expect(recorder.evaluated.count == 1)
    #expect(recorder.evaluated.first === connection)
    #expect(recorder.ready.count == 1)
    #expect(recorder.ready.first?.tlsBinding.hostFingerprint == identity.1)
    #expect(recorder.terminals.isEmpty)
    #expect(io.cancelCount == 0)
    io.emit(.failed)
    #expect(recorder.ready.count == 1)
    #expect(recorder.terminals.isEmpty)
}

@Test(arguments: [
    NetworkHostTLSMetadataFactsV0(
        negotiatedTLSMajor: 1,
        negotiatedTLSMinor: 2,
        earlyDataAccepted: false
    ),
    NetworkHostTLSMetadataFactsV0(
        negotiatedTLSMajor: 1,
        negotiatedTLSMinor: 3,
        earlyDataAccepted: true
    ),
])
func acceptedConnectionRejectsUnsafeNegotiatedTLS(
    facts: NetworkHostTLSMetadataFactsV0
) throws {
    let identity = try networkHostAcceptedTestIdentity()
    let io = NetworkHostAcceptedFakeIOV0(
        connection: networkHostAcceptedTestConnection()
    )
    let recorder = NetworkHostAcceptedRecorderV0()
    let authority = NetworkHostAcceptedConnectionV0(
        io: io,
        servedSubjectPublicKeyInfoDER: identity.0,
        requiredHostFingerprint: identity.1,
        metadataEvaluator: { _ in facts }
    )
    try authority.start(
        queue: DispatchQueue(label: "MacCompanionTests.AcceptedReject"),
        ready: recorder.recordReady,
        terminal: recorder.recordTerminal
    )

    io.emit(.ready)
    io.emit(.cancelled)

    #expect(recorder.ready.isEmpty)
    #expect(recorder.terminals == [.tlsRejected])
    #expect(io.cancelCount == 1)
}

@Test func acceptedConnectionSeparatesMissingMetadataAndTearsDownOnce()
    throws
{
    let identity = try networkHostAcceptedTestIdentity()
    let io = NetworkHostAcceptedFakeIOV0(
        connection: networkHostAcceptedTestConnection()
    )
    let recorder = NetworkHostAcceptedRecorderV0()
    let authority = NetworkHostAcceptedConnectionV0(
        io: io,
        servedSubjectPublicKeyInfoDER: identity.0,
        requiredHostFingerprint: identity.1,
        metadataEvaluator: { _ in
            throw NetworkHostAcceptedConnectionErrorV0
                .tlsMetadataUnavailable
        }
    )
    try authority.start(
        queue: DispatchQueue(label: "MacCompanionTests.AcceptedMissing"),
        ready: recorder.recordReady,
        terminal: recorder.recordTerminal
    )

    io.emit(.ready)
    io.emit(.failed)
    authority.cancel()

    #expect(recorder.ready.isEmpty)
    #expect(recorder.terminals == [.tlsMetadataUnavailable])
    #expect(io.cancelCount == 1)
}

@Test func listenerOwnerWrapsExactConnectionAndTerminatesOnce() throws {
    let identity = try networkHostAcceptedTestIdentity()
    let io = NetworkHostListenerFakeIOV0()
    let recorder = NetworkHostListenerRecorderV0()
    let owner = NetworkHostListenerOwnerV0(
        io: io,
        servedSubjectPublicKeyInfoDER: identity.0,
        requiredHostFingerprint: identity.1,
        metadataEvaluator: { _ in
            NetworkHostTLSMetadataFactsV0(
                negotiatedTLSMajor: 1,
                negotiatedTLSMinor: 3,
                earlyDataAccepted: false
            )
        }
    )
    try owner.start(
        queue: DispatchQueue(label: "MacCompanionTests.ListenerOwner"),
        ready: recorder.recordReady,
        advertisementChanged: recorder.recordAdvertisement,
        accepted: recorder.recordAccepted,
        terminal: recorder.recordTerminal
    )
    #expect(io.startCount == 1)
    #expect(throws: NetworkHostListenerOwnerErrorV0.alreadyStarted) {
        try owner.start(
            queue: DispatchQueue(label: "MacCompanionTests.ListenerTwice"),
            accepted: recorder.recordAccepted
        )
    }
    let connection = networkHostAcceptedTestConnection()

    io.emit(.ready)
    io.emit(.ready)
    #expect(recorder.readyCount == 1)
    io.emitAdvertisement(true)
    io.emitAdvertisement(false)
    #expect(recorder.advertisementReadiness == [true, false])

    io.accept(connection)

    #expect(recorder.accepted.count == 1)
    #expect(recorder.accepted.first?.matches(connection) == true)
    owner.cancel()
    io.emit(.failed)
    owner.cancel()

    #expect(io.cancelCount == 1)
    #expect(recorder.terminals == [.localCancel])
    let late = networkHostAcceptedTestConnection()
    io.accept(late)
    #expect(recorder.accepted.count == 1)
}
