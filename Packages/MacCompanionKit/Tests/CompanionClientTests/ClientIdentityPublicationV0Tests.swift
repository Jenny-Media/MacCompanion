@testable import CompanionClient
import CompanionDiscovery
import CompanionDomain
import CompanionSecurity
import CryptoKit
import Foundation
import Testing

private let identityPairingID = UUID(
    uuidString: "018f9400-0000-7000-8000-000000000001"
)!
private let identityClientID = UUID(
    uuidString: "018f9400-0000-7000-8000-000000000002"
)!
private let identityHostID = UUID(
    uuidString: "018f9400-0000-7000-8000-000000000003"
)!
private let identityDeviceID = UUID(
    uuidString: "018f9400-0000-7000-8000-000000000004"
)!

private enum IdentityTestFailure: Error {
    case injected
}

private func identityTestKey(_ scalar: UInt8) throws -> P256.Signing.PrivateKey {
    var bytes = Data(repeating: 0, count: 32)
    bytes[31] = scalar
    return try P256.Signing.PrivateKey(rawRepresentation: bytes)
}

private func identityTestPrepared() throws -> (
    ClientPreparedIdentityV0,
    P256.Signing.PrivateKey,
    P256.Signing.PrivateKey
) {
    let sessionPrivateKey = try identityTestKey(3)
    let approvalPrivateKey = try identityTestKey(4)
    let session = try ClientCustodiedPublicKeyV0(
        role: .session,
        reference: ClientSigningKeyReferenceV0(
            UUID(uuidString: "018f9400-0000-7000-8000-000000000005")!
        ),
        publicKeyX963: sessionPrivateKey.publicKey.x963Representation,
        protection: .afterFirstUnlockThisDeviceOnly
    )
    let approval = try ClientCustodiedPublicKeyV0(
        role: .approval,
        reference: ClientSigningKeyReferenceV0(
            UUID(uuidString: "018f9400-0000-7000-8000-000000000006")!
        ),
        publicKeyX963: approvalPrivateKey.publicKey.x963Representation,
        protection: .whenUnlockedThisDeviceOnlyUserPresence
    )
    return (
        try ClientPreparedIdentityV0(
            pairingID: identityPairingID,
            clientID: identityClientID,
            sessionKey: session,
            approvalKey: approval
        ),
        sessionPrivateKey,
        approvalPrivateKey
    )
}

private func identityTestHost(
    pairingID: UUID = identityPairingID,
    state: DeviceAuthorizationState = .activeMonitorOnly,
    epoch: UInt64 = 1,
    grant: UInt64 = 1
) throws -> ClientPairedHostV0 {
    ClientPairedHostV0(
        pairingID: pairingID,
        clientID: identityClientID,
        hostID: identityHostID,
        deviceID: identityDeviceID,
        hostFingerprint: Data(repeating: 0x55, count: 32),
        endpoints: [
            try EndpointCandidate(
                kind: .ipv4,
                value: "192.168.1.22",
                port: 47_474
            ),
        ],
        deviceState: state,
        authorizationEpoch: .init(rawValue: epoch),
        grantRevision: .init(rawValue: grant),
        policyRevision: .init(rawValue: 9)
    )
}

private actor IdentityTestCustody: ClientIdentityKeyCustodyV0 {
    let identity: ClientPreparedIdentityV0
    let sessionPrivateKey: P256.Signing.PrivateKey
    let approvalPrivateKey: P256.Signing.PrivateKey
    var validates = true
    var discarded = false
    var approvalReasons: [ClientApprovalPresenceReasonV0] = []

    init() throws {
        (identity, sessionPrivateKey, approvalPrivateKey) = try identityTestPrepared()
    }

    func prepareIdentity(
        pairingID: UUID,
        clientID: UUID
    ) async throws -> ClientPreparedIdentityV0 {
        identity
    }

    func validatePreparedIdentity(
        _ identity: ClientPreparedIdentityV0
    ) async throws -> Bool {
        validates && identity == self.identity && !discarded
    }

    func signSessionInput(
        _ input: Data,
        using reference: ClientSigningKeyReferenceV0
    ) async throws -> Data {
        guard reference == identity.sessionKey.reference else {
            throw IdentityTestFailure.injected
        }
        return try sessionPrivateKey.signature(for: input).rawRepresentation
    }

    func signApprovalInput(
        _ input: Data,
        using reference: ClientSigningKeyReferenceV0,
        reason: ClientApprovalPresenceReasonV0
    ) async throws -> Data {
        guard reference == identity.approvalKey.reference else {
            throw IdentityTestFailure.injected
        }
        approvalReasons.append(reason)
        return try approvalPrivateKey.signature(for: input).rawRepresentation
    }

    func discardPreparedIdentity(
        _ identity: ClientPreparedIdentityV0
    ) async throws {
        guard identity == self.identity else {
            throw IdentityTestFailure.injected
        }
        discarded = true
    }

    func setValidates(_ value: Bool) {
        validates = value
    }
}

private actor IdentityTestPersistence: ClientPairedHostPersistenceV0 {
    var failNextCommit = false
    var records: [ClientDurablePairedHostV0] = []

    func commitAtomically(
        _ record: ClientDurablePairedHostV0
    ) async throws -> ClientPairedHostCommitResultV0 {
        if failNextCommit {
            failNextCommit = false
            throw IdentityTestFailure.injected
        }
        if let existing = records.first(where: { $0.hostID == record.hostID }) {
            guard existing == record else {
                throw ClientIdentityPublicationErrorV0.persistenceConflict
            }
            return .alreadyPresentExactRecord
        }
        records.append(record)
        return .inserted
    }

    func injectCommitFailure() {
        failNextCommit = true
    }

    func snapshot() -> [ClientDurablePairedHostV0] {
        records
    }
}

@Test func keyRolesRequireDistinctKeysAndExactProtection() throws {
    let (identity, _, _) = try identityTestPrepared()
    #expect(identity.sessionKey.protection == .afterFirstUnlockThisDeviceOnly)
    #expect(identity.approvalKey.protection
        == .whenUnlockedThisDeviceOnlyUserPresence)

    #expect(throws: ClientIdentityPublicationErrorV0.invalidIdentity) {
        try ClientCustodiedPublicKeyV0(
            role: .approval,
            reference: identity.approvalKey.reference,
            publicKeyX963: identity.approvalKey.publicKeyX963,
            protection: .afterFirstUnlockThisDeviceOnly
        )
    }
    #expect(throws: ClientIdentityPublicationErrorV0.invalidIdentity) {
        try ClientPreparedIdentityV0(
            pairingID: identity.pairingID,
            clientID: identity.clientID,
            sessionKey: identity.sessionKey,
            approvalKey: ClientCustodiedPublicKeyV0(
                role: .approval,
                reference: identity.sessionKey.reference,
                publicKeyX963: identity.sessionKey.publicKeyX963,
                protection: .whenUnlockedThisDeviceOnlyUserPresence
            )
        )
    }
}

@Test func custodySignsOnlyByOpaqueReferenceAndRecordsClosedPresenceReason() async throws {
    let custody = try IdentityTestCustody()
    let identity = custody.identity
    let input = Data("bound-input".utf8)
    let sessionSigner = try ClientCustodiedSessionSignerV0(
        custody: custody,
        sessionKey: identity.sessionKey
    )
    let sessionSignature = try await sessionSigner.signPairingInput(input)
    let authenticationSignature = try await sessionSigner
        .signAuthenticationInput(input)
    let approvalSignature = try await custody.signApprovalInput(
        input,
        using: identity.approvalKey.reference,
        reason: .startInteractiveControl
    )
    #expect(sessionSignature.count == 64)
    #expect(authenticationSignature.count == 64)
    #expect(approvalSignature.count == 64)
    #expect(await custody.approvalReasons == [.startInteractiveControl])
}

@Test func publicationCreatesKeysBeforeOneCompleteDurableRecord() async throws {
    let custody = try IdentityTestCustody()
    let persistence = IdentityTestPersistence()
    let authority = ClientIdentityPublicationAuthorityV0(
        custody: custody,
        persistence: persistence
    )
    let prepared = try await authority.prepare(
        pairingID: identityPairingID,
        clientID: identityClientID
    )
    #expect(await authority.phase == .ready)

    let record = try await authority.publish(identityTestHost())
    #expect(record.sessionKey == prepared.sessionKey)
    #expect(record.approvalKey == prepared.approvalKey)
    #expect(record.deviceState == .activeMonitorOnly)
    #expect(await authority.phase == .published)
    #expect(await persistence.snapshot() == [record])
}

@Test func failedAtomicCommitPublishesNothingAndCanRetry() async throws {
    let custody = try IdentityTestCustody()
    let persistence = IdentityTestPersistence()
    await persistence.injectCommitFailure()
    let authority = ClientIdentityPublicationAuthorityV0(
        custody: custody,
        persistence: persistence
    )
    _ = try await authority.prepare(
        pairingID: identityPairingID,
        clientID: identityClientID
    )
    let host = try identityTestHost()

    await #expect(throws: IdentityTestFailure.injected) {
        _ = try await authority.publish(host)
    }
    #expect(await authority.phase == .ready)
    #expect(await persistence.snapshot().isEmpty)

    _ = try await authority.publish(host)
    #expect(await persistence.snapshot().count == 1)
    #expect(await authority.phase == .published)
}

@Test func missingKeyAndCompletionMismatchNeverReachPersistence() async throws {
    let custody = try IdentityTestCustody()
    let persistence = IdentityTestPersistence()
    let authority = ClientIdentityPublicationAuthorityV0(
        custody: custody,
        persistence: persistence
    )
    _ = try await authority.prepare(
        pairingID: identityPairingID,
        clientID: identityClientID
    )

    await #expect(throws: ClientIdentityPublicationErrorV0.completionMismatch) {
        _ = try await authority.publish(identityTestHost(pairingID: UUID()))
    }
    #expect(await authority.phase == .ready)
    #expect(await persistence.snapshot().isEmpty)

    await custody.setValidates(false)
    await #expect(throws: ClientIdentityPublicationErrorV0.keyUnavailable) {
        _ = try await authority.publish(identityTestHost())
    }
    #expect(await authority.phase == .ready)
    #expect(await persistence.snapshot().isEmpty)
}

@Test func discardedPendingIdentityCanNeverPublish() async throws {
    let custody = try IdentityTestCustody()
    let persistence = IdentityTestPersistence()
    let authority = ClientIdentityPublicationAuthorityV0(
        custody: custody,
        persistence: persistence
    )
    _ = try await authority.prepare(
        pairingID: identityPairingID,
        clientID: identityClientID
    )
    try await authority.discard()
    #expect(await authority.phase == .closed)
    #expect(await custody.discarded)
    await #expect(throws: ClientIdentityPublicationErrorV0.invalidPhase) {
        _ = try await authority.publish(identityTestHost())
    }
    #expect(await persistence.snapshot().isEmpty)
}
