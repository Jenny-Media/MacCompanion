import CompanionAuthentication
import CompanionDomain
import CompanionOperations
import CompanionPersistence
import CompanionWire
import CryptoKit
import Foundation
import Testing

private struct DiscoveryFixture {
    let directory: URL
    let store: SQLiteSecurityStore
    let principal: AuthenticatedDevicePrincipal
    let registry: CapabilityRegistrySnapshotV1

    static func create() async throws -> Self {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("maccompanion-discovery-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        let store = try SQLiteSecurityStore(
            path: directory.appendingPathComponent("security.sqlite3").path
        )
        let deviceID = UUID()
        let clientID = UUID()
        let sessionKey = P256.Signing.PrivateKey()
        let approvalKey = P256.Signing.PrivateKey()
        try await store.commitPairing(
            pairingID: UUID(),
            record: try StoredDeviceRecord(
                deviceID: deviceID,
                clientID: clientID,
                sessionPublicKeyX963: sessionKey.publicKey.x963Representation,
                approvalPublicKeyX963: approvalKey.publicKey.x963Representation,
                authorization: DeviceAuthorization(
                    state: .activeMonitorOnly,
                    authorizationEpoch: .init(rawValue: 1),
                    grantRevision: .init(rawValue: 1)
                ),
                policyRevision: .init(rawValue: 1),
                createdAtUnixMilliseconds: 1_000,
                updatedAtUnixMilliseconds: 1_000
            )
        )
        let visibleIDs = (0..<5).map {
            String(format: "maccompanion.test.capability%02d", $0)
        }
        let granted = try await store.replaceDeviceGrants(
            deviceID,
            grants: CapabilityGrantSet(
                visibleIDs + ["maccompanion.test.notInstalled"]
            ),
            occurredAtUnixMilliseconds: 2_000
        )
        let descriptors = try (0..<6).map {
            try discoveryDescriptor(index: $0)
        }
        return try Self(
            directory: directory,
            store: store,
            principal: AuthenticatedDevicePrincipal(
                deviceID: granted.deviceID,
                clientID: granted.clientID,
                deviceState: granted.authorization.state,
                authorizationEpoch: granted.authorization.authorizationEpoch,
                grantRevision: granted.authorization.grantRevision,
                policyRevision: granted.policyRevision
            ),
            registry: CapabilityRegistrySnapshotV1(
                generation: UUID(),
                capabilities: descriptors
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private func discoveryDescriptor(index: Int) throws -> CapabilityDescriptorV1 {
    let value = try CapabilitySchemaV1.object(properties: [
        CapabilitySchemaPropertyV1(
            name: "value",
            required: true,
            schema: .boolean()
        ),
    ])
    return try CapabilityDescriptorV1(
        capabilityID: String(
            format: "maccompanion.test.capability%02d",
            index
        ),
        schemaVersion: 1,
        providerID: "maccompanion.test",
        providerVersion: "1.0.0",
        providerGeneration: UUID(
            uuidString: "018f8100-0000-7000-8000-000000000001"
        )!,
        executionRevision: UUID(
            uuidString: "018f8200-0000-7000-8000-000000000001"
        )!,
        englishTitle: "Test capability \(index)",
        englishSummary: "A bounded test capability.",
        parameterSchema: value,
        resultSchema: value,
        effects: try CapabilityEffectFacts(
            dataAccess: .none,
            changesLocalState: .reversible,
            mayDisruptUser: false,
            invokesExternalService: false,
            usesCredentials: false,
            destructive: false,
            requiresForegroundSession: false,
            allowedWhileLocked: false,
            cancellation: .notApplicable
        )
    )
}

@Test func discoveryReturnsOnlyGrantedInstalledCapabilitiesInBoundedPages() async throws {
    let fixture = try await DiscoveryFixture.create()
    defer { fixture.remove() }
    let authority = CapabilityDiscoveryAuthorityV1(
        store: fixture.store,
        registry: fixture.registry
    )
    let first = try await authority.page(
        CapabilityRegistryRequestBody(),
        principal: fixture.principal
    )
    #expect(first.capabilities.count == 4)
    #expect(first.capabilities.map(\.capabilityID) == (0..<4).map {
        String(format: "maccompanion.test.capability%02d", $0)
    })
    #expect(first.nextAfterCapabilityID == "maccompanion.test.capability03")
    let second = try await authority.page(
        CapabilityRegistryRequestBody(
            expectedRegistryGeneration: first.registryGeneration,
            expectedGrantRevision: first.grantRevision,
            afterCapabilityID: first.nextAfterCapabilityID
        ),
        principal: fixture.principal
    )
    #expect(second.capabilities.map(\.capabilityID)
        == ["maccompanion.test.capability04"])
    #expect(second.nextAfterCapabilityID == nil)
    #expect(!second.capabilities.map(\.capabilityID)
        .contains("maccompanion.test.capability05"))
    #expect(!second.capabilities.map(\.capabilityID)
        .contains("maccompanion.test.notInstalled"))
}

@Test func staleRegistryCursorGetsOneClosedCorrelatedRetryResponse() async throws {
    let fixture = try await DiscoveryFixture.create()
    defer { fixture.remove() }
    let authority = CapabilityDiscoveryAuthorityV1(
        store: fixture.store,
        registry: fixture.registry
    )
    let dispatcher = CapabilityRegistryWireDispatcherV1(authority: authority)
    let request = try WireEnvelope(
        messageID: WireUUID(UUID()),
        correlationID: nil,
        sentAtUnixMilliseconds: 3_000,
        body: CapabilityRegistryRequestBody(
            expectedRegistryGeneration: WireUUID(UUID()),
            expectedGrantRevision: Int64(fixture.principal.grantRevision.rawValue),
            afterCapabilityID: "maccompanion.test.capability03"
        )
    )
    let responseData = try await dispatcher.dispatch(
        requestJSON: WireCodec.encode(request),
        principal: fixture.principal,
        responseMessageID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 3_001
    )
    let response = try WireCodec.decode(
        WireEnvelope<ProtocolErrorResponseBody>.self,
        from: responseData
    )
    #expect(response.correlationID == request.messageID)
    #expect(response.body.code == "capability.registryChanged")
    #expect(response.body.retry == .afterReconnect)
    #expect(response.body.safeArguments == .object([]))
}

@Test func grantChangeBetweenSessionAndDiscoveryClosesTheAuthorityView() async throws {
    let fixture = try await DiscoveryFixture.create()
    defer { fixture.remove() }
    let authority = CapabilityDiscoveryAuthorityV1(
        store: fixture.store,
        registry: fixture.registry
    )
    _ = try await fixture.store.replaceDeviceGrants(
        fixture.principal.deviceID,
        grants: CapabilityGrantSet([]),
        occurredAtUnixMilliseconds: 3_000
    )
    await #expect(throws: CapabilityDiscoveryErrorV1.authorizationChanged) {
        _ = try await authority.page(
            CapabilityRegistryRequestBody(),
            principal: fixture.principal
        )
    }
}
