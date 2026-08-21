import CompanionAuthentication
import CompanionDomain
import CompanionHostWire
import CompanionPersistence
import CompanionWire
import CryptoKit
import Foundation
import Testing

private struct AuditWireTemporaryDatabases {
    let directory: URL
    let security: URL
    let audit: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "maccompanion-audit-wire-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        security = directory.appendingPathComponent("security.sqlite3")
        audit = directory.appendingPathComponent("audit.sqlite3")
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct AuditWireIdentity {
    let deviceID = UUID(
        uuidString: "018f9900-0000-7000-8000-000000000001"
    )!
    let clientID = UUID(
        uuidString: "018f9900-0000-7000-8000-000000000002"
    )!
    let pairingID = UUID(
        uuidString: "018f9900-0000-7000-8000-000000000003"
    )!

    func record() throws -> StoredDeviceRecord {
        try StoredDeviceRecord(
            deviceID: deviceID,
            clientID: clientID,
            sessionPublicKeyX963: P256.Signing.PrivateKey()
                .publicKey.x963Representation,
            approvalPublicKeyX963: P256.Signing.PrivateKey()
                .publicKey.x963Representation,
            authorization: .init(
                state: .activeMonitorOnly,
                authorizationEpoch: .init(rawValue: 1),
                grantRevision: .init(rawValue: 1)
            ),
            policyRevision: .init(rawValue: 1),
            createdAtUnixMilliseconds: 1,
            updatedAtUnixMilliseconds: 1
        )
    }
}

private func auditWireRequest() throws -> WireEnvelope<AuditListRequestBodyV1> {
    try WireEnvelope(
        messageID: WireUUID(
            UUID(uuidString: "018f9900-0000-7000-8000-000000000010")!
        ),
        correlationID: nil,
        sentAtUnixMilliseconds: 100,
        body: AuditListRequestBodyV1(beforeSequence: nil, limit: 20)
    )
}

@Test func authenticatedGrantedAuditDispatchReturnsOnlySelfScopedPage() async throws {
    let temporary = try AuditWireTemporaryDatabases()
    defer { temporary.remove() }
    let identity = AuditWireIdentity()
    let security = try SQLiteSecurityStore(path: temporary.security.path)
    try await security.commitPairing(
        pairingID: identity.pairingID,
        record: identity.record()
    )
    let granted = try await security.replaceDeviceGrants(
        identity.deviceID,
        grants: CapabilityGrantSet([AuditSelfWireDispatcherV1.capabilityID]),
        occurredAtUnixMilliseconds: 2
    )
    let audit = try SQLiteBoundedAuditStoreV0(path: temporary.audit.path)
    let eventID = UUID()
    _ = try await audit.append(AuditEventDraftV0(
        eventID: eventID,
        observedAtUnixMilliseconds: 3,
        actor: .agent,
        visibility: .subjectDevice,
        subjectDeviceID: identity.deviceID,
        code: .operationCompleted,
        capabilityID: "maccompanion.system.setAudioMuted",
        policyRevision: granted.policyRevision,
        authorizationEpoch: granted.authorization.authorizationEpoch,
        grantRevision: granted.authorization.grantRevision,
        outcome: .succeeded,
        importance: .bestEffort
    ))
    let principal = AuthenticatedDevicePrincipal(
        deviceID: granted.deviceID,
        clientID: granted.clientID,
        deviceState: granted.authorization.state,
        authorizationEpoch: granted.authorization.authorizationEpoch,
        grantRevision: granted.authorization.grantRevision,
        policyRevision: granted.policyRevision
    )
    let dispatcher = AuditSelfWireDispatcherV1(
        securityStore: security,
        auditStore: audit
    )
    let request = try auditWireRequest()
    let responseJSON = try await dispatcher.dispatch(
        requestJSON: WireCodec.encode(request),
        principal: principal,
        responseMessageID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 101
    )
    let response = try WireCodec.decode(
        WireEnvelope<AuditListResponseBodyV1>.self,
        from: responseJSON
    )
    #expect(response.correlationID == request.messageID)
    #expect(response.body.events.count == 1)
    #expect(response.body.events.first?.eventID == WireUUID(eventID))
    #expect(response.body.events.first?.scope == .selfDevice)
    #expect(response.body.events.first?.capabilityID
        == "maccompanion.system.setAudioMuted")
}

@Test func missingGrantAndStalePrincipalReturnOnlyClosedPolicyDenial() async throws {
    let temporary = try AuditWireTemporaryDatabases()
    defer { temporary.remove() }
    let identity = AuditWireIdentity()
    let security = try SQLiteSecurityStore(path: temporary.security.path)
    try await security.commitPairing(
        pairingID: identity.pairingID,
        record: identity.record()
    )
    let audit = try SQLiteBoundedAuditStoreV0(path: temporary.audit.path)
    let dispatcher = AuditSelfWireDispatcherV1(
        securityStore: security,
        auditStore: audit
    )
    let request = try auditWireRequest()
    let responseJSON = try await dispatcher.dispatch(
        requestJSON: WireCodec.encode(request),
        principal: AuthenticatedDevicePrincipal(
            deviceID: identity.deviceID,
            clientID: identity.clientID,
            deviceState: .activeMonitorOnly,
            authorizationEpoch: .init(rawValue: 1),
            grantRevision: .init(rawValue: 1),
            policyRevision: .init(rawValue: 1)
        ),
        responseMessageID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 101
    )
    let denial = try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: responseJSON
    )
    #expect(denial.correlationID == request.messageID)
    #expect(denial.body.code == "policy.denied")
    #expect(denial.body.safeArguments == .object([
        .init(
            key: "capabilityID",
            value: .string("audit.readSelf")
        ),
    ]))
}
