import CompanionAuthentication
import CompanionDomain
import CompanionPersistence
import Foundation
import Testing

private let authClientID = UUID(uuidString: "018f2000-0000-7000-8000-000000000001")!
private let authDeviceID = UUID(uuidString: "018f2100-0000-7000-8000-000000000001")!
private let authPairingID = UUID(uuidString: "018f4000-0000-7000-8000-000000000001")!
private let authConnectionID = Data(base64URL: "AAECAwQFBgcICQoLDA0ODw")
private let authClientNonce = Data(base64URL: "EBESExQVFhcYGRobHB0eHyAhIiMkJSYnKCkqKywtLi8")
private let authServerNonce = Data(base64URL: "MDEyMzQ1Njc4OTo7PD0-P0BBQkNERUZHSElKS0xNTk8")
private let authHostFingerprint = Data(hex: "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f")
private let authSessionPublicKey = Data(base64URL: "BGsX0fLhLEJH-Lzm5WOkQPJ3A32BLeszoPShOUXYmMKWT-NC4v4af5uO5-tKfA-eFivOM1drMV7Oy7ZAaDe_UfU")
private let authApprovalPublicKey = Data(base64URL: "BHzyexiNA09-ilI4AwS1GsPAiWnid_IbNaYLSPxHZpl4B3dVENuO0EApPZrGn3Qw27p9reY86YIpngS3nSJ4c9E")
private let authSignature = Data(base64URL: "2apPB6dwlPRHWiNFe5-oZmVFtjSdhHPH7RyDfJMwUoJi4_bEQ38VZkXqLmlmpDsBecyyzs6ESV-we-6DYuPmhQ")

private struct AuthenticationTestStore {
    let directory: URL
    let store: SQLiteSecurityStore

    static func create() async throws -> Self {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("maccompanion-auth-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let store = try SQLiteSecurityStore(
            path: directory.appendingPathComponent("security.sqlite3").path
        )
        let record = try StoredDeviceRecord(
            deviceID: authDeviceID,
            clientID: authClientID,
            sessionPublicKeyX963: authSessionPublicKey,
            approvalPublicKeyX963: authApprovalPublicKey,
            authorization: DeviceAuthorization(
                state: .activeMonitorOnly,
                authorizationEpoch: .init(rawValue: 1),
                grantRevision: .init(rawValue: 1)
            ),
            policyRevision: .init(rawValue: 4),
            createdAtUnixMilliseconds: 1_000,
            updatedAtUnixMilliseconds: 1_000
        )
        try await store.commitPairing(pairingID: authPairingID, record: record)
        return Self(directory: directory, store: store)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private func goldenChallenge(
    authority: ApplicationAuthenticationAuthority,
    clientID: UUID = authClientID,
    monotonicNowMilliseconds: Int64 = 100
) async throws -> ApplicationAuthenticationChallenge {
    try await authority.challenge(
        clientID: clientID,
        clientNonce: authClientNonce,
        hostFingerprint: authHostFingerprint,
        monotonicNowMilliseconds: monotonicNowMilliseconds,
        connectionID: authConnectionID,
        serverNonce: authServerNonce
    )
}

@Test func goldenAuthenticationVectorReturnsEpochFencedPrincipal() async throws {
    let fixture = try await AuthenticationTestStore.create()
    defer { fixture.remove() }
    let authority = ApplicationAuthenticationAuthority(deviceReader: fixture.store)
    let challenge = try await goldenChallenge(authority: authority)
    #expect(challenge.connectionID == authConnectionID)
    #expect(challenge.serverNonce == authServerNonce)

    let principal = try await authority.prove(
        connectionID: authConnectionID,
        signature: authSignature,
        monotonicNowMilliseconds: 101
    )
    #expect(principal.deviceID == authDeviceID)
    #expect(principal.clientID == authClientID)
    #expect(principal.authorizationEpoch.rawValue == 1)
    #expect(principal.grantRevision.rawValue == 1)
    #expect(principal.policyRevision.rawValue == 4)
}

@Test func authorizationChangeBetweenChallengeAndProofFailsClosed() async throws {
    let fixture = try await AuthenticationTestStore.create()
    defer { fixture.remove() }
    let authority = ApplicationAuthenticationAuthority(deviceReader: fixture.store)
    _ = try await goldenChallenge(authority: authority)
    _ = try await fixture.store.transitionDevice(
        authDeviceID,
        event: .suspend,
        occurredAtUnixMilliseconds: 2_000
    )

    await #expect(throws: ApplicationAuthenticationError.authenticationFailed) {
        _ = try await authority.prove(
            connectionID: authConnectionID,
            signature: authSignature,
            monotonicNowMilliseconds: 101
        )
    }
}

@Test func unknownClientStillReceivesOpaqueChallengeButCannotAuthenticate() async throws {
    let fixture = try await AuthenticationTestStore.create()
    defer { fixture.remove() }
    let authority = ApplicationAuthenticationAuthority(deviceReader: fixture.store)
    let challenge = try await goldenChallenge(
        authority: authority,
        clientID: UUID(uuidString: "018f2000-0000-7000-8000-000000000099")!
    )
    #expect(challenge.connectionID.count == 16)
    #expect(challenge.serverNonce.count == 32)

    await #expect(throws: ApplicationAuthenticationError.authenticationFailed) {
        _ = try await authority.prove(
            connectionID: authConnectionID,
            signature: authSignature,
            monotonicNowMilliseconds: 101
        )
    }
}

@Test func challengeIsSingleUseAndExpiresAtExactMonotonicDeadline() async throws {
    let fixture = try await AuthenticationTestStore.create()
    defer { fixture.remove() }
    let authority = ApplicationAuthenticationAuthority(deviceReader: fixture.store)
    _ = try await goldenChallenge(authority: authority)

    await #expect(throws: ApplicationAuthenticationError.authenticationFailed) {
        _ = try await authority.prove(
            connectionID: authConnectionID,
            signature: Data(repeating: 0, count: 64),
            monotonicNowMilliseconds: 101
        )
    }
    await #expect(throws: ApplicationAuthenticationError.challengeNotFound) {
        _ = try await authority.prove(
            connectionID: authConnectionID,
            signature: authSignature,
            monotonicNowMilliseconds: 102
        )
    }

    _ = try await goldenChallenge(authority: authority, monotonicNowMilliseconds: 200)
    await #expect(throws: ApplicationAuthenticationError.challengeExpired) {
        _ = try await authority.prove(
            connectionID: authConnectionID,
            signature: authSignature,
            monotonicNowMilliseconds: 200
                + ApplicationAuthenticationAuthority.challengeLifetimeMilliseconds
        )
    }
}

private extension Data {
    init(hex: String) {
        self.init()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
    }

    init(base64URL: String) {
        var text = base64URL
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        text.append(String(repeating: "=", count: (4 - text.count % 4) % 4))
        self = Data(base64Encoded: text)!
    }
}
