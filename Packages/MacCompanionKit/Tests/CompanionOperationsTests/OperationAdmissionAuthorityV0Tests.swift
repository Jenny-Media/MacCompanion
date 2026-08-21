import CompanionAuthentication
import CompanionDomain
import CompanionOperations
import CompanionPersistence
import CompanionSecurity
import CompanionWire
import CryptoKit
import Foundation
import Testing

private struct OperationTemporaryDatabase {
    let directory: URL
    let database: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("maccompanion-operations-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        database = directory.appendingPathComponent("security.sqlite3")
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private struct OperationTestDevice {
    let pairingID = UUID(uuidString: "018f4000-0000-7000-8000-000000000001")!
    let deviceID = UUID(uuidString: "018f2100-0000-7000-8000-000000000001")!
    let clientID = UUID(uuidString: "018f2000-0000-7000-8000-000000000001")!
    let sessionKey: Data
    let approvalKey: Data

    init(
        approvalPrivateKey: P256.Signing.PrivateKey = .init()
    ) {
        sessionKey = P256.Signing.PrivateKey().publicKey.x963Representation
        approvalKey = approvalPrivateKey.publicKey.x963Representation
    }

    func record() throws -> StoredDeviceRecord {
        try StoredDeviceRecord(
            deviceID: deviceID,
            clientID: clientID,
            sessionPublicKeyX963: sessionKey,
            approvalPublicKeyX963: approvalKey,
            authorization: DeviceAuthorization(
                state: .activeMonitorOnly,
                authorizationEpoch: .init(rawValue: 1),
                grantRevision: .init(rawValue: 1)
            ),
            policyRevision: .init(rawValue: 1),
            createdAtUnixMilliseconds: 1_000,
            updatedAtUnixMilliseconds: 1_000
        )
    }
}

private func operationHostIdentity() throws -> StoredHostIdentityRecord {
    try StoredHostIdentityRecord(
        hostID: UUID(uuidString: "018f1000-0000-7000-8000-000000000001")!,
        keyApplicationTag: Data(repeating: 1, count: 16),
        hostFingerprint: Data(repeating: 2, count: 32),
        certificateDER: Data([0x30, 0x00]),
        certificateNotBeforeUnixMilliseconds: 0,
        certificateNotAfterUnixMilliseconds: 100_000,
        establishedAtUnixMilliseconds: 500,
        updatedAtUnixMilliseconds: 500
    )
}

private func operationEffects(
    destructive: Bool = false
) throws -> CapabilityEffectFacts {
    try CapabilityEffectFacts(
        dataAccess: .none,
        changesLocalState: destructive ? .irreversible : .reversible,
        mayDisruptUser: false,
        invokesExternalService: false,
        usesCredentials: false,
        destructive: destructive,
        requiresForegroundSession: false,
        allowedWhileLocked: true,
        cancellation: .notApplicable
    )
}

private func operationDescriptor(
    destructive: Bool = false
) throws -> CapabilityDescriptorV1 {
    try CapabilityDescriptorV1(
        capabilityID: "maccompanion.system.setAudioMuted",
        schemaVersion: 1,
        providerID: "maccompanion.native",
        providerVersion: "1.0.0",
        providerGeneration: UUID(
            uuidString: "018f8100-0000-7000-8000-000000000001"
        )!,
        executionRevision: UUID(
            uuidString: "018f8200-0000-7000-8000-000000000001"
        )!,
        englishTitle: "Set audio mute",
        englishSummary: "Set the default output mute state.",
        parameterSchema: .object(properties: [
            CapabilitySchemaPropertyV1(
                name: "muted",
                required: true,
                schema: .boolean()
            ),
        ]),
        resultSchema: .object(properties: [
            CapabilitySchemaPropertyV1(
                name: "muted",
                required: true,
                schema: .boolean()
            ),
        ]),
        effects: operationEffects(destructive: destructive)
    )
}

private func setupOperationAuthority(
    grants: [String] = ["maccompanion.system.setAudioMuted"],
    destructive: Bool = false,
    approvalPrivateKey: P256.Signing.PrivateKey = .init()
) async throws -> (
    OperationTemporaryDatabase,
    SQLiteSecurityStore,
    OperationAdmissionAuthorityV0,
    AuthenticatedDevicePrincipal
) {
    let temporary = try OperationTemporaryDatabase()
    let device = OperationTestDevice(approvalPrivateKey: approvalPrivateKey)
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    try await store.establishHostIdentity(operationHostIdentity())
    try await store.commitPairing(pairingID: device.pairingID, record: device.record())
    let granted = try await store.replaceDeviceGrants(
        device.deviceID,
        grants: CapabilityGrantSet(grants),
        occurredAtUnixMilliseconds: 2_000
    )
    let principal = AuthenticatedDevicePrincipal(
        deviceID: granted.deviceID,
        clientID: granted.clientID,
        deviceState: granted.authorization.state,
        authorizationEpoch: granted.authorization.authorizationEpoch,
        grantRevision: granted.authorization.grantRevision,
        policyRevision: granted.policyRevision
    )
    let registry = try CapabilityRegistrySnapshotV1(
        generation: UUID(),
        capabilities: [operationDescriptor(destructive: destructive)]
    )
    return (
        temporary,
        store,
        OperationAdmissionAuthorityV0(store: store, registry: registry),
        principal
    )
}

@Test func lowRiskGrantedOperationCanonicalizesBindsAndAdmitsOnce() async throws {
    let (temporary, store, authority, principal) = try await setupOperationAuthority()
    defer { temporary.remove() }
    let operationID = UUID(uuidString: "018f8000-0000-7000-8000-000000000001")!
    let created = try await authority.admitWithoutFreshApproval(
        operationID: operationID,
        parametersJSON: Data(" { \"muted\" : true } ".utf8),
        capabilityID: "maccompanion.system.setAudioMuted",
        principal: principal,
        hostState: .userSessionLocked,
        wallNowUnixMilliseconds: 3_000
    )
    guard case let .created(record) = created else {
        Issue.record("expected durable creation")
        return
    }
    #expect(record.state == .queued)
    #expect(record.requiredHostState == .userSessionLocked)
    #expect(record.authorizationEpoch == 2)
    #expect(record.grantRevision == 2)
    #expect(record.expiresAtUnixMilliseconds == 33_000)
    #expect(try await store.durableOperation(operationID) == record)

    let replay = try await authority.admitWithoutFreshApproval(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        capabilityID: "maccompanion.system.setAudioMuted",
        principal: principal,
        hostState: .userSessionLocked,
        wallNowUnixMilliseconds: 9_000
    )
    #expect(replay == .existing(record))
}

@Test func schemaGrantAndCapabilityFailuresNeverCreateDurableWork() async throws {
    let (temporary, store, authority, principal) = try await setupOperationAuthority(
        grants: ["maccompanion.test.secondaryAction"]
    )
    defer { temporary.remove() }
    let operationID = UUID()
    await #expect(throws: OperationAdmissionError.capabilityNotGranted) {
        _ = try await authority.admitWithoutFreshApproval(
            operationID: operationID,
            parametersJSON: Data("{\"muted\":true}".utf8),
            capabilityID: "maccompanion.system.setAudioMuted",
            principal: principal,
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 3_000
        )
    }
    #expect(try await store.durableOperation(operationID) == nil)

    await #expect(throws: OperationAdmissionError.schemaRejected) {
        _ = try await authority.admitWithoutFreshApproval(
            operationID: UUID(),
            parametersJSON: Data("{\"muted\":true,\"extra\":1}".utf8),
            capabilityID: "maccompanion.system.setAudioMuted",
            principal: principal,
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 3_000
        )
    }
    await #expect(throws: OperationAdmissionError.capabilityUnavailable) {
        _ = try await authority.admitWithoutFreshApproval(
            operationID: UUID(),
            parametersJSON: Data("{}".utf8),
            capabilityID: "unknown.capability",
            principal: principal,
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 3_000
        )
    }
}

@Test func stalePrincipalAndUnsafeHostStateFailBeforeAdmission() async throws {
    let (temporary, store, authority, principal) = try await setupOperationAuthority()
    defer { temporary.remove() }
    _ = try await store.replaceDeviceGrants(
        principal.deviceID,
        grants: CapabilityGrantSet([
            "maccompanion.system.setAudioMuted",
            "maccompanion.test.secondaryAction",
        ]),
        occurredAtUnixMilliseconds: 2_500
    )
    await #expect(throws: OperationAdmissionError.deviceAuthorizationChanged) {
        _ = try await authority.admitWithoutFreshApproval(
            operationID: UUID(),
            parametersJSON: Data("{\"muted\":true}".utf8),
            capabilityID: "maccompanion.system.setAudioMuted",
            principal: principal,
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 3_000
        )
    }

    let current = try #require(try await store.device(principal.deviceID))
    let currentPrincipal = AuthenticatedDevicePrincipal(
        deviceID: current.deviceID,
        clientID: current.clientID,
        deviceState: current.authorization.state,
        authorizationEpoch: current.authorization.authorizationEpoch,
        grantRevision: current.authorization.grantRevision,
        policyRevision: current.policyRevision
    )
    await #expect(throws: OperationAdmissionError.hostStateDenied) {
        _ = try await authority.admitWithoutFreshApproval(
            operationID: UUID(),
            parametersJSON: Data("{\"muted\":true}".utf8),
            capabilityID: "maccompanion.system.setAudioMuted",
            principal: currentPrincipal,
            hostState: .otherConsoleUserActive,
            wallNowUnixMilliseconds: 3_000
        )
    }
}

@Test func elevatedEffectsRequireTheUnimplementedFreshApprovalProfile() async throws {
    let (temporary, store, authority, principal) = try await setupOperationAuthority(
        destructive: true
    )
    defer { temporary.remove() }
    let operationID = UUID()
    await #expect(throws: OperationAdmissionError.approvalRequired) {
        _ = try await authority.admitWithoutFreshApproval(
            operationID: operationID,
            parametersJSON: Data("{\"muted\":true}".utf8),
            capabilityID: "maccompanion.system.setAudioMuted",
            principal: principal,
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 3_000
        )
    }
    #expect(try await store.durableOperation(operationID) == nil)
}

@Test func elevatedOperationApprovalRetriesExactlyAndThenAdmitsOnce() async throws {
    let temporary = try OperationTemporaryDatabase()
    defer { temporary.remove() }
    let approvalPrivateKey = P256.Signing.PrivateKey()
    let device = OperationTestDevice(approvalPrivateKey: approvalPrivateKey)
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    let host = try operationHostIdentity()
    try await store.establishHostIdentity(host)
    try await store.commitPairing(pairingID: device.pairingID, record: device.record())
    let granted = try await store.replaceDeviceGrants(
        device.deviceID,
        grants: CapabilityGrantSet(["maccompanion.system.setAudioMuted"]),
        occurredAtUnixMilliseconds: 2_000
    )
    let principal = AuthenticatedDevicePrincipal(
        deviceID: granted.deviceID,
        clientID: granted.clientID,
        deviceState: granted.authorization.state,
        authorizationEpoch: granted.authorization.authorizationEpoch,
        grantRevision: granted.authorization.grantRevision,
        policyRevision: granted.policyRevision
    )
    let descriptor = try operationDescriptor(destructive: true)
    let authority = OperationAdmissionAuthorityV0(
        store: store,
        registry: try CapabilityRegistrySnapshotV1(
            generation: UUID(),
            capabilities: [descriptor]
        )
    )
    let operationID = UUID()
    let approvalID = UUID()
    let connectionID = Data((0..<16).map(UInt8.init))
    let serverChallenge = Data((0x80..<0xA0).map(UInt8.init))
    let preparation = try await authority.prepareAdmission(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        capabilityID: descriptor.capabilityID,
        principal: principal,
        primaryConnectionID: connectionID,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_000,
        monotonicNowMilliseconds: 10_000,
        approvalID: approvalID,
        serverChallenge: serverChallenge
    )
    guard case let .approvalRequired(challenge) = preparation else {
        Issue.record("expected fresh approval challenge")
        return
    }
    #expect(try await authority.prepareAdmission(
        operationID: operationID,
        parametersJSON: Data(" { \"muted\" : true } ".utf8),
        capabilityID: descriptor.capabilityID,
        principal: principal,
        primaryConnectionID: connectionID,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_500,
        monotonicNowMilliseconds: 10_500
    ) == .approvalRequired(challenge))
    await #expect(throws: SecurityStoreError.operationIDConflict(operationID)) {
        _ = try await authority.prepareAdmission(
            operationID: operationID,
            parametersJSON: Data("{\"muted\":false}".utf8),
            capabilityID: descriptor.capabilityID,
            principal: principal,
            primaryConnectionID: connectionID,
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 3_500,
            monotonicNowMilliseconds: 10_500
        )
    }

    let signingInput = try CompanionSecurityV0.operationApprovalSigningInput(
        hostFingerprint: host.hostFingerprint,
        clientID: device.clientID,
        primaryConnectionID: connectionID,
        approvalID: challenge.approvalID,
        operationDigest: challenge.operationDigest,
        serverChallenge: challenge.serverChallenge,
        issuedAtUnixMilliseconds: challenge.issuedAtUnixMilliseconds,
        expiresAtUnixMilliseconds: challenge.expiresAtUnixMilliseconds,
        selectedMajor: 0,
        selectedMinor: 1
    )
    let signature = try approvalPrivateKey.signature(for: signingInput)
        .rawRepresentation
    guard case let .created(record) = try await authority.completeApproval(
        approvalID: approvalID,
        rawSignature: signature,
        primaryConnectionID: connectionID,
        monotonicNowMilliseconds: 11_000
    ) else {
        Issue.record("expected approved durable admission")
        return
    }
    #expect(record.requestDigest == challenge.operationDigest)
    #expect(record.state == .queued)
    #expect(try await store.durableOperation(operationID) == record)
    await #expect(throws: OperationAdmissionError.approvalNotFound) {
        _ = try await authority.completeApproval(
            approvalID: approvalID,
            rawSignature: signature,
            primaryConnectionID: connectionID,
            monotonicNowMilliseconds: 12_000
        )
    }
}

@Test func approvalIsConsumedWithoutAdmissionWhenAuthorizationChanges() async throws {
    let temporary = try OperationTemporaryDatabase()
    defer { temporary.remove() }
    let approvalPrivateKey = P256.Signing.PrivateKey()
    let device = OperationTestDevice(approvalPrivateKey: approvalPrivateKey)
    let store = try SQLiteSecurityStore(path: temporary.database.path)
    try await store.establishHostIdentity(operationHostIdentity())
    try await store.commitPairing(pairingID: device.pairingID, record: device.record())
    let granted = try await store.replaceDeviceGrants(
        device.deviceID,
        grants: CapabilityGrantSet(["maccompanion.system.setAudioMuted"]),
        occurredAtUnixMilliseconds: 2_000
    )
    let principal = AuthenticatedDevicePrincipal(
        deviceID: granted.deviceID,
        clientID: granted.clientID,
        deviceState: granted.authorization.state,
        authorizationEpoch: granted.authorization.authorizationEpoch,
        grantRevision: granted.authorization.grantRevision,
        policyRevision: granted.policyRevision
    )
    let descriptor = try operationDescriptor(destructive: true)
    let authority = OperationAdmissionAuthorityV0(
        store: store,
        registry: try CapabilityRegistrySnapshotV1(
            generation: UUID(),
            capabilities: [descriptor]
        )
    )
    let operationID = UUID()
    let connectionID = Data(repeating: 1, count: 16)
    guard case let .approvalRequired(challenge) = try await authority.prepareAdmission(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        capabilityID: descriptor.capabilityID,
        principal: principal,
        primaryConnectionID: connectionID,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_000,
        monotonicNowMilliseconds: 10_000
    ) else {
        Issue.record("expected approval")
        return
    }
    _ = try await store.transitionDevice(
        device.deviceID,
        event: .suspend,
        occurredAtUnixMilliseconds: 3_100
    )
    let signingInput = try CompanionSecurityV0.operationApprovalSigningInput(
        hostFingerprint: (try operationHostIdentity()).hostFingerprint,
        clientID: device.clientID,
        primaryConnectionID: connectionID,
        approvalID: challenge.approvalID,
        operationDigest: challenge.operationDigest,
        serverChallenge: challenge.serverChallenge,
        issuedAtUnixMilliseconds: challenge.issuedAtUnixMilliseconds,
        expiresAtUnixMilliseconds: challenge.expiresAtUnixMilliseconds,
        selectedMajor: 0,
        selectedMinor: 1
    )
    let signature = try approvalPrivateKey.signature(for: signingInput)
        .rawRepresentation
    await #expect(throws: OperationAdmissionError.deviceAuthorizationChanged) {
        _ = try await authority.completeApproval(
            approvalID: challenge.approvalID,
            rawSignature: signature,
            primaryConnectionID: connectionID,
            monotonicNowMilliseconds: 11_000
        )
    }
    #expect(try await store.durableOperation(operationID) == nil)
    await #expect(throws: OperationAdmissionError.approvalNotFound) {
        _ = try await authority.completeApproval(
            approvalID: challenge.approvalID,
            rawSignature: signature,
            primaryConnectionID: connectionID,
            monotonicNowMilliseconds: 11_500
        )
    }
}

@Test func pendingApprovalCannotCrossProviderPublicationRemoval() async throws {
    let (temporary, store, _, principal) = try await setupOperationAuthority(
        destructive: true
    )
    defer { temporary.remove() }
    let descriptor = try operationDescriptor(destructive: true)
    let provider = FakeCapabilityProvider(
        descriptor: descriptor,
        outcome: .failed(.unavailable)
    )
    let publication = CapabilityRegistryPublicationAuthorityV1(
        initial: try CapabilityRegistryPublicationV1(
            registry: CapabilityRegistrySnapshotV1(
                generation: UUID(),
                capabilities: [descriptor]
            ),
            providers: [provider]
        )
    )
    let admission = OperationAdmissionAuthorityV0(
        store: store,
        registryReader: publication
    )
    let connectionID = Data(repeating: 9, count: 16)
    let operationID = UUID()
    guard case let .approvalRequired(challenge) = try await admission
        .prepareAdmission(
            operationID: operationID,
            parametersJSON: Data("{\"muted\":true}".utf8),
            capabilityID: descriptor.capabilityID,
            principal: principal,
            primaryConnectionID: connectionID,
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 3_000,
            monotonicNowMilliseconds: 10_000
        ) else {
        Issue.record("expected pending approval")
        return
    }
    _ = try await publication.replace(with: CapabilityRegistryPublicationV1(
        registry: CapabilityRegistrySnapshotV1(
            generation: UUID(),
            capabilities: []
        ),
        providers: []
    ))

    await #expect(throws: OperationAdmissionError.capabilityUnavailable) {
        _ = try await admission.completeApproval(
            approvalID: challenge.approvalID,
            rawSignature: Data(repeating: 0, count: 64),
            primaryConnectionID: connectionID,
            monotonicNowMilliseconds: 10_100
        )
    }
    #expect(try await store.durableOperation(operationID) == nil)
}

private actor FakeCapabilityProvider: CapabilityProviderV1 {
    nonisolated let identity: CapabilityProviderIdentityV1
    private let outcome: CapabilityProviderOutcomeV1
    private let cancellationAccepted: Bool
    private var requests: [CapabilityProviderRequestV1] = []
    private var cancellationRequests: [UUID] = []

    init(
        descriptor: CapabilityDescriptorV1,
        outcome: CapabilityProviderOutcomeV1,
        cancellationAccepted: Bool = false
    ) {
        identity = CapabilityProviderIdentityV1(
            providerID: descriptor.providerID,
            providerVersion: descriptor.providerVersion,
            providerGeneration: descriptor.providerGeneration,
            executionRevision: descriptor.executionRevision
        )
        self.outcome = outcome
        self.cancellationAccepted = cancellationAccepted
    }

    func execute(
        _ request: CapabilityProviderRequestV1
    ) async -> CapabilityProviderOutcomeV1 {
        requests.append(request)
        return outcome
    }

    func requestCount() -> Int { requests.count }

    func requestCancellation(operationID: UUID) async -> Bool {
        cancellationRequests.append(operationID)
        return cancellationAccepted
    }

    func cancellationRequestCount() -> Int { cancellationRequests.count }
}

private actor SequencedPublicationReaderV1:
    CapabilityRegistryPublicationReadingV1
{
    private let first: CapabilityRegistryPublicationV1
    private let later: CapabilityRegistryPublicationV1
    private var reads = 0

    init(
        first: CapabilityRegistryPublicationV1,
        later: CapabilityRegistryPublicationV1
    ) {
        self.first = first
        self.later = later
    }

    func publicationSnapshot() -> CapabilityRegistryPublicationV1 {
        reads += 1
        return reads == 1 ? first : later
    }

    func registrySnapshot() -> CapabilityRegistrySnapshotV1 {
        publicationSnapshot().registry
    }

    func readCount() -> Int { reads }
}

private actor ForcedDeadlineRunner: CapabilityProviderDeadlineRunningV1 {
    private var observedTimeouts: [UInt64] = []

    func run(
        timeoutMilliseconds: UInt64,
        operation: @escaping @Sendable () async -> CapabilityProviderOutcomeV1
    ) async -> CapabilityProviderDeadlineResultV1 {
        observedTimeouts.append(timeoutMilliseconds)
        _ = await operation()
        return .deadlineExceeded
    }

    func timeouts() -> [UInt64] { observedTimeouts }
}

private actor ControlledCapabilityProvider: CapabilityProviderV1 {
    nonisolated let identity: CapabilityProviderIdentityV1
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var outcomeWaiter: CheckedContinuation<CapabilityProviderOutcomeV1, Never>?
    private var cancellationRequests = 0

    init(descriptor: CapabilityDescriptorV1) {
        identity = CapabilityProviderIdentityV1(
            providerID: descriptor.providerID,
            providerVersion: descriptor.providerVersion,
            providerGeneration: descriptor.providerGeneration,
            executionRevision: descriptor.executionRevision
        )
    }

    func execute(
        _ request: CapabilityProviderRequestV1
    ) async -> CapabilityProviderOutcomeV1 {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        return await withCheckedContinuation { continuation in
            outcomeWaiter = continuation
        }
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finish(_ outcome: CapabilityProviderOutcomeV1) {
        outcomeWaiter?.resume(returning: outcome)
        outcomeWaiter = nil
    }

    func requestCancellation(operationID: UUID) async -> Bool {
        cancellationRequests += 1
        return true
    }

    func cancellationRequestCount() -> Int { cancellationRequests }
}

private func operationRegistry() throws -> CapabilityRegistrySnapshotV1 {
    try CapabilityRegistrySnapshotV1(
        generation: UUID(),
        capabilities: [operationDescriptor()]
    )
}

@Test func onePublicationReplacementFencesDiscoveryAdmissionAndExecution() async throws {
    let (temporary, store, _, principal) = try await setupOperationAuthority()
    defer { temporary.remove() }
    let descriptor = try operationDescriptor()
    let provider = FakeCapabilityProvider(
        descriptor: descriptor,
        outcome: .succeeded(resultJSON: Data("{\"muted\":true}".utf8))
    )
    let initial = try CapabilityRegistryPublicationV1(
        registry: CapabilityRegistrySnapshotV1(
            generation: UUID(),
            capabilities: [descriptor]
        ),
        providers: [provider]
    )
    let publication = CapabilityRegistryPublicationAuthorityV1(initial: initial)
    let discovery = CapabilityDiscoveryAuthorityV1(
        store: store,
        registryReader: publication
    )
    let admission = OperationAdmissionAuthorityV0(
        store: store,
        registryReader: publication
    )
    let execution = OperationExecutionAuthorityV0(
        store: store,
        publicationReader: publication
    )

    #expect(try await discovery.page(
        CapabilityRegistryRequestBody(),
        principal: principal
    ).capabilities.map(\.capabilityID) == [descriptor.capabilityID])

    let queuedID = UUID()
    _ = try await admission.admitWithoutFreshApproval(
        operationID: queuedID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        capabilityID: descriptor.capabilityID,
        principal: principal,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_000
    )

    let retired = try CapabilityRegistryPublicationV1(
        registry: CapabilityRegistrySnapshotV1(
            generation: UUID(),
            capabilities: []
        ),
        providers: []
    )
    _ = try await publication.replace(with: retired)

    #expect(try await discovery.page(
        CapabilityRegistryRequestBody(),
        principal: principal
    ).capabilities.isEmpty)
    await #expect(throws: OperationAdmissionError.capabilityUnavailable) {
        _ = try await admission.admitWithoutFreshApproval(
            operationID: UUID(),
            parametersJSON: Data("{\"muted\":false}".utf8),
            capabilityID: descriptor.capabilityID,
            principal: principal,
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 3_100
        )
    }
    await #expect(throws: OperationExecutionError.capabilityUnavailable) {
        _ = try await execution.execute(
            operationID: queuedID,
            parametersJSON: Data("{\"muted\":true}".utf8),
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 3_200
        )
    }
    #expect(await provider.requestCount() == 0)
    #expect(try await store.durableOperation(queuedID)?.state == .queued)
}

@Test func executionClaimsOnceAndReturnsOnlyCanonicalSchemaValidResult() async throws {
    let (temporary, store, admission, principal) = try await setupOperationAuthority()
    defer { temporary.remove() }
    let operationID = UUID()
    _ = try await admission.admitWithoutFreshApproval(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        capabilityID: "maccompanion.system.setAudioMuted",
        principal: principal,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_000
    )
    let descriptor = try operationDescriptor()
    let provider = FakeCapabilityProvider(
        descriptor: descriptor,
        outcome: .succeeded(resultJSON: Data(" { \"muted\" : true } ".utf8))
    )
    let execution = OperationExecutionAuthorityV0(
        store: store,
        registry: try operationRegistry()
    )
    let result = try await execution.execute(
        operationID: operationID,
        parametersJSON: Data(" { \"muted\" : true } ".utf8),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_100,
        provider: provider
    )
    guard case let .succeeded(record, canonicalResult) = result else {
        Issue.record("expected successful execution")
        return
    }
    #expect(record.state == .succeeded)
    #expect(String(decoding: canonicalResult, as: UTF8.self) == "{\"muted\":true}")
    #expect(await provider.requestCount() == 1)
    #expect(try await store.durableOperation(operationID)?.state == .succeeded)

    #expect(try await execution.execute(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_200,
        provider: provider
    ) == .alreadyTerminal(record))
    #expect(await provider.requestCount() == 1)
}

@Test func invalidProviderResultFailsWithHostOwnedCode() async throws {
    let (temporary, store, admission, principal) = try await setupOperationAuthority()
    defer { temporary.remove() }
    let operationID = UUID()
    _ = try await admission.admitWithoutFreshApproval(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":false}".utf8),
        capabilityID: "maccompanion.system.setAudioMuted",
        principal: principal,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_000
    )
    let provider = FakeCapabilityProvider(
        descriptor: try operationDescriptor(),
        outcome: .succeeded(resultJSON: Data("{\"rawProviderText\":\"secret path\"}".utf8))
    )
    let execution = OperationExecutionAuthorityV0(
        store: store,
        registry: try operationRegistry()
    )
    guard case let .failed(record, code) = try await execution.execute(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":false}".utf8),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_100,
        provider: provider
    ) else {
        Issue.record("expected invalid result failure")
        return
    }
    #expect(record.state == .failed)
    #expect(code == "provider.invalidResult")
    #expect(record.terminalCode == "provider.invalidResult")
}

@Test func requestBindingMismatchNeverClaimsOrCallsProvider() async throws {
    let (temporary, store, admission, principal) = try await setupOperationAuthority()
    defer { temporary.remove() }
    let operationID = UUID()
    _ = try await admission.admitWithoutFreshApproval(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        capabilityID: "maccompanion.system.setAudioMuted",
        principal: principal,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_000
    )
    let provider = FakeCapabilityProvider(
        descriptor: try operationDescriptor(),
        outcome: .succeeded(resultJSON: Data("{\"muted\":false}".utf8))
    )
    let execution = OperationExecutionAuthorityV0(
        store: store,
        registry: try operationRegistry()
    )
    await #expect(throws: OperationExecutionError.requestBindingMismatch) {
        _ = try await execution.execute(
            operationID: operationID,
            parametersJSON: Data("{\"muted\":false}".utf8),
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 3_100,
            provider: provider
        )
    }
    #expect(await provider.requestCount() == 0)
    #expect(try await store.durableOperation(operationID)?.state == .queued)
}

@Test func revokedGrantFencesQueuedExecutionBeforeProviderCall() async throws {
    let (temporary, store, admission, principal) = try await setupOperationAuthority()
    defer { temporary.remove() }
    let operationID = UUID()
    _ = try await admission.admitWithoutFreshApproval(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        capabilityID: "maccompanion.system.setAudioMuted",
        principal: principal,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_000
    )
    _ = try await store.replaceDeviceGrants(
        principal.deviceID,
        grants: CapabilityGrantSet(["maccompanion.test.secondaryAction"]),
        occurredAtUnixMilliseconds: 3_050
    )
    let provider = FakeCapabilityProvider(
        descriptor: try operationDescriptor(),
        outcome: .succeeded(resultJSON: Data("{\"muted\":true}".utf8))
    )
    let execution = OperationExecutionAuthorityV0(
        store: store,
        registry: try operationRegistry()
    )
    guard case let .alreadyTerminal(record) = try await execution.execute(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_100,
        provider: provider
    ) else {
        Issue.record("expected atomically fenced terminal operation")
        return
    }
    #expect(record.state == .failed)
    #expect(record.terminalCode == "operation.authorizationRevoked")
    #expect(await provider.requestCount() == 0)
}

@Test func providerFailurePersistsOnlyItsClosedHostKnownCode() async throws {
    let (temporary, store, admission, principal) = try await setupOperationAuthority()
    defer { temporary.remove() }
    let operationID = UUID()
    _ = try await admission.admitWithoutFreshApproval(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        capabilityID: "maccompanion.system.setAudioMuted",
        principal: principal,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_000
    )
    let provider = FakeCapabilityProvider(
        descriptor: try operationDescriptor(),
        outcome: .failed(.permissionDenied)
    )
    let execution = OperationExecutionAuthorityV0(
        store: store,
        registry: try operationRegistry()
    )
    guard case let .failed(record, code) = try await execution.execute(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_100,
        provider: provider
    ) else {
        Issue.record("expected closed provider failure")
        return
    }
    #expect(code == "provider.permissionDenied")
    #expect(record.terminalCode == code)
    #expect(try await store.durableOperation(operationID)?.terminalCode == code)
}

@Test func queuedAndRunningCancellationUseOnlyLegalDurableTransitions() async throws {
    let (temporary, store, admission, principal) = try await setupOperationAuthority()
    defer { temporary.remove() }
    let descriptor = try operationDescriptor()
    let provider = FakeCapabilityProvider(
        descriptor: descriptor,
        outcome: .failed(.executionFailed),
        cancellationAccepted: true
    )
    let execution = OperationExecutionAuthorityV0(
        store: store,
        registry: try operationRegistry()
    )

    let queuedID = UUID()
    _ = try await admission.admitWithoutFreshApproval(
        operationID: queuedID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        capabilityID: descriptor.capabilityID,
        principal: principal,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_000
    )
    guard case let .cancelled(cancelled) = try await execution.requestCancellation(
        operationID: queuedID,
        wallNowUnixMilliseconds: 3_050,
        provider: provider
    ) else {
        Issue.record("expected queued cancellation")
        return
    }
    #expect(cancelled.state == .cancelled)
    #expect(await provider.cancellationRequestCount() == 0)

    let runningID = UUID()
    _ = try await admission.admitWithoutFreshApproval(
        operationID: runningID,
        parametersJSON: Data("{\"muted\":false}".utf8),
        capabilityID: descriptor.capabilityID,
        principal: principal,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_100
    )
    _ = try await store.claimDurableOperationExecution(
        runningID,
        snapshot: DurableOperationExecutionSnapshot(
            providerGeneration: descriptor.providerGeneration,
            executionRevision: descriptor.executionRevision,
            hostState: .userSessionActive,
            nowUnixMilliseconds: 3_150
        )
    )
    guard case let .requested(requested, accepted) = try await execution.requestCancellation(
        operationID: runningID,
        wallNowUnixMilliseconds: 3_200,
        provider: provider
    ) else {
        Issue.record("expected running cancellation request")
        return
    }
    #expect(requested.state == .cancelRequested)
    #expect(accepted)
    #expect(await provider.cancellationRequestCount() == 1)
    #expect(try await execution.requestCancellation(
        operationID: runningID,
        wallNowUnixMilliseconds: 3_300,
        provider: provider
    ) == .alreadyRequested(requested))
    #expect(await provider.cancellationRequestCount() == 1)
}

@Test func providerCancellationOutcomeTraversesCancelRequestedBeforeTerminal() async throws {
    let (temporary, store, admission, principal) = try await setupOperationAuthority()
    defer { temporary.remove() }
    let operationID = UUID()
    _ = try await admission.admitWithoutFreshApproval(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        capabilityID: "maccompanion.system.setAudioMuted",
        principal: principal,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_000
    )
    let provider = FakeCapabilityProvider(
        descriptor: try operationDescriptor(),
        outcome: .cancelled
    )
    let execution = OperationExecutionAuthorityV0(
        store: store,
        registry: try operationRegistry()
    )
    guard case let .cancelled(record) = try await execution.execute(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_100,
        provider: provider
    ) else {
        Issue.record("expected terminal cancellation")
        return
    }
    #expect(record.state == .cancelled)
    #expect(record.terminalCode == "operation.cancelled")
}

@Test func systemProviderDeadlineRunnerReturnsWithoutWaitingForSlowWork() async {
    let runner = SystemCapabilityProviderDeadlineRunnerV1()
    #expect(await runner.run(timeoutMilliseconds: 1_000) {
        .failed(.rejected)
    } == .completed(.failed(.rejected)))

    let timedOut = await runner.run(timeoutMilliseconds: 1) {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        return .succeeded(resultJSON: Data("{\"late\":true}".utf8))
    }
    #expect(timedOut == .deadlineExceeded)
}

@Test func hostDeadlinePersistsUnknownOutcomeAndNeverReportsProviderTimeout() async throws {
    let (temporary, store, admission, principal) = try await setupOperationAuthority()
    defer { temporary.remove() }
    let operationID = UUID()
    _ = try await admission.admitWithoutFreshApproval(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        capabilityID: "maccompanion.system.setAudioMuted",
        principal: principal,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_000
    )
    let provider = FakeCapabilityProvider(
        descriptor: try operationDescriptor(),
        outcome: .succeeded(resultJSON: Data("{\"muted\":true}".utf8))
    )
    let deadline = ForcedDeadlineRunner()
    let execution = OperationExecutionAuthorityV0(
        store: store,
        registry: try operationRegistry(),
        deadlineRunner: deadline
    )

    guard case let .outcomeUnknown(record) = try await execution.execute(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_100,
        provider: provider
    ) else {
        Issue.record("expected conservative unknown outcome")
        return
    }
    #expect(await deadline.timeouts() == [29_900])
    #expect(await provider.requestCount() == 1)
    #expect(record.state == .outcomeUnknown)
    #expect(record.terminalCode == "operation.outcomeUnknown")
    #expect(record.terminalAtUnixMilliseconds == 33_000)
    #expect(try await store.durableOperation(operationID) == record)
}

@Test func providerCompletionAfterCancellationUsesTheLatestDurableTimestamp() async throws {
    let (temporary, store, admission, principal) = try await setupOperationAuthority()
    defer { temporary.remove() }
    let operationID = UUID()
    _ = try await admission.admitWithoutFreshApproval(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        capabilityID: "maccompanion.system.setAudioMuted",
        principal: principal,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_000
    )
    let provider = ControlledCapabilityProvider(
        descriptor: try operationDescriptor()
    )
    let execution = OperationExecutionAuthorityV0(
        store: store,
        registry: try operationRegistry()
    )
    let executionTask = Task {
        try await execution.execute(
            operationID: operationID,
            parametersJSON: Data("{\"muted\":true}".utf8),
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 3_100,
            provider: provider
        )
    }
    await provider.waitUntilStarted()
    guard case .requested = try await execution.requestCancellation(
        operationID: operationID,
        wallNowUnixMilliseconds: 3_200,
        provider: provider
    ) else {
        Issue.record("expected cancellation request")
        return
    }
    await provider.finish(
        .succeeded(resultJSON: Data("{\"muted\":true}".utf8))
    )

    guard case let .succeeded(record, _) = try await executionTask.value else {
        Issue.record("expected provider success after cancellation request")
        return
    }
    #expect(record.state == .succeeded)
    #expect(record.updatedAtUnixMilliseconds == 3_200)
}

@Test func runningOperationRetainsCancellationRouteAcrossProviderRemoval() async throws {
    let (temporary, store, _, principal) = try await setupOperationAuthority()
    defer { temporary.remove() }
    let descriptor = try operationDescriptor()
    let provider = ControlledCapabilityProvider(descriptor: descriptor)
    let initial = try CapabilityRegistryPublicationV1(
        registry: CapabilityRegistrySnapshotV1(
            generation: UUID(),
            capabilities: [descriptor]
        ),
        providers: [provider]
    )
    let publication = CapabilityRegistryPublicationAuthorityV1(initial: initial)
    let admission = OperationAdmissionAuthorityV0(
        store: store,
        registryReader: publication
    )
    let execution = OperationExecutionAuthorityV0(
        store: store,
        publicationReader: publication
    )
    let operationID = UUID()
    _ = try await admission.admitWithoutFreshApproval(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        capabilityID: descriptor.capabilityID,
        principal: principal,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_000
    )
    let running = Task {
        try await execution.execute(
            operationID: operationID,
            parametersJSON: Data("{\"muted\":true}".utf8),
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 3_100
        )
    }
    await provider.waitUntilStarted()
    _ = try await publication.replace(with: CapabilityRegistryPublicationV1(
        registry: CapabilityRegistrySnapshotV1(
            generation: UUID(),
            capabilities: []
        ),
        providers: []
    ))

    guard case let .requested(record, accepted) = try await execution
        .requestCancellation(
            operationID: operationID,
            wallNowUnixMilliseconds: 3_200
        ) else {
        Issue.record("expected retained-provider cancellation")
        return
    }
    #expect(record.state == .cancelRequested)
    #expect(accepted)
    #expect(await provider.cancellationRequestCount() == 1)
    await provider.finish(.cancelled)
    guard case .cancelled = try await running.value else {
        Issue.record("expected cancelled terminal result")
        return
    }
}

@Test func startupReconciliationIsRequiredAtomicAndIdempotent() async throws {
    let (temporary, store, admission, principal) = try await setupOperationAuthority()
    defer { temporary.remove() }
    let descriptor = try operationDescriptor()
    let queuedID = UUID()
    let runningID = UUID()
    let cancellingID = UUID()
    for operationID in [queuedID, runningID, cancellingID] {
        _ = try await admission.admitWithoutFreshApproval(
            operationID: operationID,
            parametersJSON: Data("{\"muted\":true}".utf8),
            capabilityID: descriptor.capabilityID,
            principal: principal,
            hostState: .userSessionActive,
            wallNowUnixMilliseconds: 3_000
        )
    }
    for operationID in [runningID, cancellingID] {
        _ = try await store.claimDurableOperationExecution(
            operationID,
            snapshot: DurableOperationExecutionSnapshot(
                providerGeneration: descriptor.providerGeneration,
                executionRevision: descriptor.executionRevision,
                hostState: .userSessionActive,
                nowUnixMilliseconds: 3_100
            )
        )
    }
    _ = try await store.transitionDurableOperation(
        cancellingID,
        to: .cancelRequested,
        occurredAtUnixMilliseconds: 3_200
    )

    let reconciler = OperationStartupReconcilerV0(store: store)
    await #expect(throws: OperationStartupError.reconciliationRequired) {
        _ = try await reconciler.requireReconciled()
    }
    let report = try await reconciler.reconcileBeforeOpeningIngress(
        wallNowUnixMilliseconds: 4_000
    )
    #expect(report == DurableOperationStartupReconciliation(
        queuedFailed: 1,
        inFlightOutcomeUnknown: 2
    ))
    #expect(report.totalReconciled == 3)
    #expect(try await store.durableOperation(queuedID)?.state == .failed)
    #expect(try await store.durableOperation(queuedID)?.terminalCode
        == "operation.hostRestarted")
    #expect(try await store.durableOperation(runningID)?.state == .outcomeUnknown)
    #expect(try await store.durableOperation(cancellingID)?.state == .outcomeUnknown)
    #expect(try await reconciler.reconcileBeforeOpeningIngress(
        wallNowUnixMilliseconds: 5_000
    ) == report)
    #expect(try await reconciler.requireReconciled() == report)
}

@Test func commandCoordinatorGatesIngressExecutesAndReplaysWithoutDuplication() async throws {
    let (temporary, store, admission, principal) = try await setupOperationAuthority()
    defer { temporary.remove() }
    let descriptor = try operationDescriptor()
    let provider = FakeCapabilityProvider(
        descriptor: descriptor,
        outcome: .succeeded(resultJSON: Data("{\"muted\":true}".utf8))
    )
    let startup = OperationStartupReconcilerV0(store: store)
    let coordinator = OperationCommandCoordinatorV0(
        store: store,
        startup: startup,
        admission: admission,
        execution: OperationExecutionAuthorityV0(
            store: store,
            registry: try operationRegistry()
        ),
        providers: try CapabilityProviderCatalogV1(providers: [provider])
    )
    let connectionID = Data((0..<16).map(UInt8.init))
    let context = try AuthenticatedOperationCommandContextV0(
        principal: principal,
        primaryConnectionID: connectionID,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_000,
        monotonicNowMilliseconds: 10_000
    )
    let operationID = UUID()
    let invoke = try OperationInvokeRequestBody(
        operationID: WireUUID(operationID),
        capabilityID: descriptor.capabilityID,
        parameters: CanonicalJSON.parse(Data("{\"muted\":true}".utf8))
    )

    await #expect(throws: OperationStartupError.reconciliationRequired) {
        _ = try await coordinator.invoke(invoke, context: context)
    }
    #expect(try await coordinator.reconcileBeforeOpeningIngress(
        wallNowUnixMilliseconds: 2_500
    ).totalReconciled == 0)
    guard case let .status(success) = try await coordinator.invoke(
        invoke,
        context: context
    ) else {
        Issue.record("expected successful status")
        return
    }
    #expect(success.state == .succeeded)
    #expect(success.result != nil)
    #expect(await provider.requestCount() == 1)

    let lateContext = try AuthenticatedOperationCommandContextV0(
        principal: principal,
        primaryConnectionID: connectionID,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 9_000,
        monotonicNowMilliseconds: 16_000
    )
    guard case let .status(replayed) = try await coordinator.invoke(
        invoke,
        context: lateContext
    ) else {
        Issue.record("expected terminal replay status")
        return
    }
    #expect(replayed.state == .succeeded)
    #expect(replayed.result == nil)
    #expect(await provider.requestCount() == 1)

    let statusRequest = OperationStatusRequestBody(operationID: WireUUID(operationID))
    guard case let .status(observed) = try await coordinator.status(
        statusRequest,
        context: lateContext
    ) else {
        Issue.record("expected observed status")
        return
    }
    #expect(observed == replayed)

    let foreign = AuthenticatedDevicePrincipal(
        deviceID: UUID(),
        clientID: principal.clientID,
        deviceState: principal.deviceState,
        authorizationEpoch: principal.authorizationEpoch,
        grantRevision: principal.grantRevision,
        policyRevision: principal.policyRevision
    )
    let foreignContext = try AuthenticatedOperationCommandContextV0(
        principal: foreign,
        primaryConnectionID: connectionID,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 9_000,
        monotonicNowMilliseconds: 16_000
    )
    await #expect(throws: OperationCommandError.operationNotFound) {
        _ = try await coordinator.status(statusRequest, context: foreignContext)
    }
}

@Test func releaseCoordinatorRetainsOnePublicationAcrossInvokeAndEffect() async throws {
    let (temporary, store, _, principal) = try await setupOperationAuthority()
    defer { temporary.remove() }
    let descriptor = try operationDescriptor()
    let provider = FakeCapabilityProvider(
        descriptor: descriptor,
        outcome: .succeeded(resultJSON: Data("{\"muted\":true}".utf8))
    )
    let initial = try CapabilityRegistryPublicationV1(
        registry: CapabilityRegistrySnapshotV1(
            generation: UUID(),
            capabilities: [descriptor]
        ),
        providers: [provider]
    )
    let retired = try CapabilityRegistryPublicationV1(
        registry: CapabilityRegistrySnapshotV1(
            generation: UUID(),
            capabilities: []
        ),
        providers: []
    )
    let publicationReader = SequencedPublicationReaderV1(
        first: initial,
        later: retired
    )
    let startup = OperationStartupReconcilerV0(store: store)
    let auditStore = try SQLiteBoundedAuditStoreV0(
        path: temporary.directory.appendingPathComponent("audit.sqlite3").path
    )
    let coordinator = OperationCommandCoordinatorV0(
        store: store,
        startup: startup,
        publicationReader: publicationReader,
        auditWriter: BoundedOperationAuditWriterV0(store: auditStore)
    )
    _ = try await coordinator.reconcileBeforeOpeningIngress(
        wallNowUnixMilliseconds: 2_500
    )
    let context = try AuthenticatedOperationCommandContextV0(
        principal: principal,
        primaryConnectionID: Data((0..<16).map(UInt8.init)),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_000,
        monotonicNowMilliseconds: 10_000
    )
    let operationID = UUID()
    let invoke = try OperationInvokeRequestBody(
        operationID: WireUUID(operationID),
        capabilityID: descriptor.capabilityID,
        parameters: CanonicalJSON.parse(Data("{\"muted\":true}".utf8))
    )

    guard case let .status(status) = try await coordinator.invoke(
        invoke,
        context: context
    ) else {
        Issue.record("expected successful status")
        return
    }
    #expect(status.state == .succeeded)
    #expect(await provider.requestCount() == 1)
    #expect(await publicationReader.readCount() == 1)
}

@Test func commandCoordinatorApprovalExecutesTheOriginallyBoundParameters() async throws {
    let approvalPrivateKey = P256.Signing.PrivateKey()
    let (temporary, store, admission, principal) = try await setupOperationAuthority(
        destructive: true,
        approvalPrivateKey: approvalPrivateKey
    )
    defer { temporary.remove() }
    let descriptor = try operationDescriptor(destructive: true)
    let provider = FakeCapabilityProvider(
        descriptor: descriptor,
        outcome: .succeeded(resultJSON: Data("{\"muted\":true}".utf8))
    )
    let startup = OperationStartupReconcilerV0(store: store)
    let coordinator = OperationCommandCoordinatorV0(
        store: store,
        startup: startup,
        admission: admission,
        execution: OperationExecutionAuthorityV0(
            store: store,
            registry: try CapabilityRegistrySnapshotV1(
                generation: UUID(),
                capabilities: [descriptor]
            )
        ),
        providers: try CapabilityProviderCatalogV1(providers: [provider])
    )
    _ = try await coordinator.reconcileBeforeOpeningIngress(
        wallNowUnixMilliseconds: 2_500
    )
    let connectionID = Data((0..<16).map(UInt8.init))
    let context = try AuthenticatedOperationCommandContextV0(
        principal: principal,
        primaryConnectionID: connectionID,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_000,
        monotonicNowMilliseconds: 10_000
    )
    let operationID = UUID()
    let invoke = try OperationInvokeRequestBody(
        operationID: WireUUID(operationID),
        capabilityID: descriptor.capabilityID,
        parameters: CanonicalJSON.parse(Data(" { \"muted\" : true } ".utf8))
    )
    guard case let .approvalRequired(required) = try await coordinator.invoke(
        invoke,
        context: context
    ) else {
        Issue.record("expected approval challenge")
        return
    }
    #expect(try await store.durableOperation(operationID) == nil)
    let host = try #require(try await store.hostIdentity())
    let signingInput = try CompanionSecurityV0.operationApprovalSigningInput(
        hostFingerprint: host.hostFingerprint,
        clientID: principal.clientID,
        primaryConnectionID: connectionID,
        approvalID: required.approvalID.rawValue,
        operationDigest: required.operationDigest.rawValue,
        serverChallenge: required.serverChallenge.rawValue,
        issuedAtUnixMilliseconds: UInt64(required.issuedAtUnixMilliseconds),
        expiresAtUnixMilliseconds: UInt64(required.expiresAtUnixMilliseconds),
        selectedMajor: 0,
        selectedMinor: 1
    )
    let signature = try approvalPrivateKey.signature(for: signingInput)
        .rawRepresentation
    let approval = OperationApproveRequestBody(
        approvalID: required.approvalID,
        signature: try WireBytes64(signature)
    )
    let approvalContext = try AuthenticatedOperationCommandContextV0(
        principal: principal,
        primaryConnectionID: connectionID,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_100,
        monotonicNowMilliseconds: 11_000
    )
    guard case let .status(success) = try await coordinator.approve(
        approval,
        context: approvalContext
    ) else {
        Issue.record("expected approved execution")
        return
    }
    #expect(success.state == .succeeded)
    #expect(success.result != nil)
    #expect(await provider.requestCount() == 1)
    #expect(try await store.durableOperation(operationID)?.state == .succeeded)
}

@Test func commandCoordinatorFailsMissingProviderAndCancelsQueuedWithoutOne() async throws {
    let (temporary, store, admission, principal) = try await setupOperationAuthority()
    defer { temporary.remove() }
    let startup = OperationStartupReconcilerV0(store: store)
    let coordinator = OperationCommandCoordinatorV0(
        store: store,
        startup: startup,
        admission: admission,
        execution: OperationExecutionAuthorityV0(
            store: store,
            registry: try operationRegistry()
        ),
        providers: try CapabilityProviderCatalogV1()
    )
    _ = try await coordinator.reconcileBeforeOpeningIngress(
        wallNowUnixMilliseconds: 2_500
    )
    let connectionID = Data((0..<16).map(UInt8.init))
    let context = try AuthenticatedOperationCommandContextV0(
        principal: principal,
        primaryConnectionID: connectionID,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_000,
        monotonicNowMilliseconds: 10_000
    )
    let missingProviderID = UUID()
    let invoke = try OperationInvokeRequestBody(
        operationID: WireUUID(missingProviderID),
        capabilityID: "maccompanion.system.setAudioMuted",
        parameters: CanonicalJSON.parse(Data("{\"muted\":true}".utf8))
    )
    guard case let .status(unavailable) = try await coordinator.invoke(
        invoke,
        context: context
    ) else {
        Issue.record("expected unavailable terminal status")
        return
    }
    #expect(unavailable.state == .failed)
    #expect(unavailable.terminalCode == "provider.unavailable")

    let queuedID = UUID()
    _ = try await admission.admitWithoutFreshApproval(
        operationID: queuedID,
        parametersJSON: Data("{\"muted\":false}".utf8),
        capabilityID: "maccompanion.system.setAudioMuted",
        principal: principal,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_100
    )
    guard case let .status(cancelled) = try await coordinator.cancel(
        OperationCancelRequestBody(operationID: WireUUID(queuedID)),
        context: context
    ) else {
        Issue.record("expected queued cancellation")
        return
    }
    #expect(cancelled.state == .cancelled)
    #expect(cancelled.terminalCode == "operation.cancelled")
}

@Test func wireDispatcherProducesCorrelatedStatusAndOpaqueNotFoundError() async throws {
    let (temporary, store, admission, principal) = try await setupOperationAuthority()
    defer { temporary.remove() }
    let descriptor = try operationDescriptor()
    let provider = FakeCapabilityProvider(
        descriptor: descriptor,
        outcome: .succeeded(resultJSON: Data("{\"muted\":true}".utf8))
    )
    let startup = OperationStartupReconcilerV0(store: store)
    let coordinator = OperationCommandCoordinatorV0(
        store: store,
        startup: startup,
        admission: admission,
        execution: OperationExecutionAuthorityV0(
            store: store,
            registry: try operationRegistry()
        ),
        providers: try CapabilityProviderCatalogV1(providers: [provider])
    )
    _ = try await coordinator.reconcileBeforeOpeningIngress(
        wallNowUnixMilliseconds: 2_500
    )
    let dispatcher = OperationWireCommandDispatcherV0(coordinator: coordinator)
    let context = try AuthenticatedOperationCommandContextV0(
        principal: principal,
        primaryConnectionID: Data((0..<16).map(UInt8.init)),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_000,
        monotonicNowMilliseconds: 10_000
    )
    let requestID = WireUUID(UUID())
    let operationID = WireUUID(UUID())
    let request = try WireEnvelope(
        messageID: requestID,
        correlationID: nil,
        sentAtUnixMilliseconds: 3_000,
        body: OperationInvokeRequestBody(
            operationID: operationID,
            capabilityID: descriptor.capabilityID,
            parameters: CanonicalJSON.parse(Data("{\"muted\":true}".utf8))
        )
    )
    let responseID = WireUUID(UUID())
    let responseData = try await dispatcher.dispatch(
        requestJSON: WireCodec.encode(request),
        context: context,
        responseMessageID: responseID
    )
    let response = try WireCodec.decode(
        WireEnvelope<OperationStatusResponseBody>.self,
        from: responseData
    )
    #expect(response.messageID == responseID)
    #expect(response.correlationID == requestID)
    #expect(response.body.operationID == operationID)
    #expect(response.body.state == .succeeded)
    #expect(response.body.result != nil)

    let missingRequestID = WireUUID(UUID())
    let missingOperationID = WireUUID(UUID())
    let missing = try WireEnvelope(
        messageID: missingRequestID,
        correlationID: nil,
        sentAtUnixMilliseconds: 3_100,
        body: OperationStatusRequestBody(operationID: missingOperationID)
    )
    let errorData = try await dispatcher.dispatch(
        requestJSON: WireCodec.encode(missing),
        context: context,
        responseMessageID: WireUUID(UUID())
    )
    let error = try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: errorData
    )
    #expect(error.correlationID == missingRequestID)
    #expect(error.body.code == "operation.notFound")
    #expect(error.body.retry == .never)
    #expect(error.body.safeArguments == .object([
        .init(
            key: "operationID",
            value: .string(missingOperationID.description)
        ),
    ]))
}

@Test func wireDispatcherReturnsSafeStartupErrorAndRejectsResponseKinds() async throws {
    let (temporary, store, admission, principal) = try await setupOperationAuthority()
    defer { temporary.remove() }
    let coordinator = OperationCommandCoordinatorV0(
        store: store,
        startup: OperationStartupReconcilerV0(store: store),
        admission: admission,
        execution: OperationExecutionAuthorityV0(
            store: store,
            registry: try operationRegistry()
        ),
        providers: try CapabilityProviderCatalogV1()
    )
    let dispatcher = OperationWireCommandDispatcherV0(coordinator: coordinator)
    let context = try AuthenticatedOperationCommandContextV0(
        principal: principal,
        primaryConnectionID: Data((0..<16).map(UInt8.init)),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_000,
        monotonicNowMilliseconds: 10_000
    )
    let invoke = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 3_000,
        body: OperationInvokeRequestBody(
            operationID: WireUUID(UUID()),
            capabilityID: "maccompanion.system.setAudioMuted",
            parameters: CanonicalJSON.parse(Data("{\"muted\":true}".utf8))
        )
    )
    let errorData = try await dispatcher.dispatch(
        requestJSON: WireCodec.encode(invoke),
        context: context,
        responseMessageID: WireUUID(UUID())
    )
    let error = try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: errorData
    )
    #expect(error.body.code == "storage.securityUnavailable")
    #expect(error.body.retry == .afterUserAction)

    let response = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 3_000,
        body: OperationStatusResponseBody(
            operationID: WireUUID(UUID()),
            state: .queued,
            terminalCode: nil,
            result: nil
        )
    )
    await #expect(throws: OperationWireDispatchError.unsupportedKind) {
        _ = try await dispatcher.dispatch(
            requestJSON: WireCodec.encode(response),
            context: context,
            responseMessageID: WireUUID(UUID())
        )
    }
}

@Test func requiredOperationAuditPrecedesEffectAndTerminalRetryIsIdempotent() async throws {
    let (temporary, store, admission, principal) = try await setupOperationAuthority()
    defer { temporary.remove() }
    let operationID = UUID()
    _ = try await admission.admitWithoutFreshApproval(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        capabilityID: "maccompanion.system.setAudioMuted",
        principal: principal,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_000
    )
    let auditStore = try SQLiteBoundedAuditStoreV0(
        path: temporary.directory.appendingPathComponent("audit.sqlite3").path
    )
    let auditWriter = BoundedOperationAuditWriterV0(store: auditStore)
    let provider = FakeCapabilityProvider(
        descriptor: try operationDescriptor(),
        outcome: .succeeded(resultJSON: Data("{\"muted\":true}".utf8))
    )
    let execution = OperationExecutionAuthorityV0(
        store: store,
        registry: try operationRegistry(),
        auditWriter: auditWriter
    )

    guard case let .succeeded(terminal, _) = try await execution.execute(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_100,
        provider: provider
    ) else {
        Issue.record("expected success")
        return
    }
    let page = try await auditStore.page(
        scope: .localAdministration,
        limit: 10
    )
    #expect(page.events.map(\.draft.code) == [
        .operationCompleted,
        .operationAdmitted,
    ])
    #expect(page.events.allSatisfy {
        $0.draft.subjectDeviceID == principal.deviceID
            && $0.draft.operationID == operationID
            && $0.draft.capabilityID == "maccompanion.system.setAudioMuted"
    })
    #expect(page.events.last?.draft.importance == .requiredBeforeEffect)
    #expect(await provider.requestCount() == 1)

    #expect(try await execution.execute(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_200,
        provider: provider
    ) == .alreadyTerminal(terminal))
    #expect(try await auditStore.page(
        scope: .localAdministration,
        limit: 10
    ).events.count == 2)
    #expect(await auditWriter.health() == .healthy)
}

@Test func requiredAuditFailureDurablyFailsBeforeProviderEffect() async throws {
    let (temporary, store, admission, principal) = try await setupOperationAuthority()
    defer { temporary.remove() }
    let operationID = UUID()
    _ = try await admission.admitWithoutFreshApproval(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":false}".utf8),
        capabilityID: "maccompanion.system.setAudioMuted",
        principal: principal,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_000
    )
    let auditStore = try SQLiteBoundedAuditStoreV0(
        path: temporary.directory.appendingPathComponent("audit.sqlite3").path,
        injectedFaults: [.afterCompaction]
    )
    let auditWriter = BoundedOperationAuditWriterV0(store: auditStore)
    let provider = FakeCapabilityProvider(
        descriptor: try operationDescriptor(),
        outcome: .succeeded(resultJSON: Data("{\"muted\":false}".utf8))
    )
    let execution = OperationExecutionAuthorityV0(
        store: store,
        registry: try operationRegistry(),
        auditWriter: auditWriter
    )

    guard case let .failed(record, code) = try await execution.execute(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":false}".utf8),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_100,
        provider: provider
    ) else {
        Issue.record("expected audit-gated failure")
        return
    }
    #expect(code == "audit.requiredUnavailable")
    #expect(record.state == .failed)
    #expect(record.terminalCode == "audit.requiredUnavailable")
    #expect(try await store.durableOperation(operationID) == record)
    #expect(await provider.requestCount() == 0)
    #expect(await auditWriter.health() == .degraded)
    #expect(try await auditStore.page(
        scope: .localAdministration,
        limit: 10
    ).events.isEmpty)
}

@Test func terminalAuditFailureDegradesHealthWithoutRewritingOutcome() async throws {
    let (temporary, store, admission, principal) = try await setupOperationAuthority()
    defer { temporary.remove() }
    let operationID = UUID()
    _ = try await admission.admitWithoutFreshApproval(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        capabilityID: "maccompanion.system.setAudioMuted",
        principal: principal,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_000
    )
    let provider = FakeCapabilityProvider(
        descriptor: try operationDescriptor(),
        outcome: .succeeded(resultJSON: Data("{\"muted\":true}".utf8))
    )
    let execution = OperationExecutionAuthorityV0(
        store: store,
        registry: try operationRegistry()
    )
    guard case let .succeeded(terminal, _) = try await execution.execute(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_100,
        provider: provider
    ) else {
        Issue.record("expected success")
        return
    }
    let auditStore = try SQLiteBoundedAuditStoreV0(
        path: temporary.directory.appendingPathComponent("audit.sqlite3").path,
        injectedFaults: [.afterCompaction]
    )
    let auditWriter = BoundedOperationAuditWriterV0(store: auditStore)

    await auditWriter.recordTerminal(terminal)

    #expect(await auditWriter.health() == .degraded)
    #expect(try await store.durableOperation(operationID) == terminal)
    #expect(terminal.state == .succeeded)
    #expect(await provider.requestCount() == 1)
}

@Test func droppedTerminalAuditDegradesHealthWithoutRewritingOutcome() async throws {
    let (temporary, store, admission, principal) = try await setupOperationAuthority()
    defer { temporary.remove() }
    let operationID = UUID()
    _ = try await admission.admitWithoutFreshApproval(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        capabilityID: "maccompanion.system.setAudioMuted",
        principal: principal,
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_000
    )
    let auditStore = try SQLiteBoundedAuditStoreV0(
        path: temporary.directory.appendingPathComponent("audit.sqlite3").path,
        configuration: try AuditStoreConfigurationV0(
            logicalByteLimit: 16 * 1_024 * 1_024,
            retainedRowLimit: 50_000,
            retentionMilliseconds: 30 * 24 * 60 * 60 * 1_000,
            rateLimitAttempts: 1,
            rateLimitWindowMilliseconds: 60_000
        )
    )
    let auditWriter = BoundedOperationAuditWriterV0(store: auditStore)
    let provider = FakeCapabilityProvider(
        descriptor: try operationDescriptor(),
        outcome: .succeeded(resultJSON: Data("{\"muted\":true}".utf8))
    )
    let execution = OperationExecutionAuthorityV0(
        store: store,
        registry: try operationRegistry(),
        auditWriter: auditWriter
    )

    guard case let .succeeded(terminal, _) = try await execution.execute(
        operationID: operationID,
        parametersJSON: Data("{\"muted\":true}".utf8),
        hostState: .userSessionActive,
        wallNowUnixMilliseconds: 3_100,
        provider: provider
    ) else {
        Issue.record("expected successful execution")
        return
    }

    #expect(terminal.state == .succeeded)
    #expect(try await store.durableOperation(operationID) == terminal)
    #expect(await provider.requestCount() == 1)
    #expect(await auditWriter.health() == .degraded)
    let page = try await auditStore.page(
        scope: .localAdministration,
        limit: 10
    )
    #expect(page.events.map(\.draft.code) == [.operationAdmitted])
    #expect(page.gaps.droppedEventCount == 1)
}
