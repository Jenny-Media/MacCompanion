import CompanionDomain
import CompanionHostPlatform
import CompanionInteractiveHost
import CompanionPersistence
import CryptoKit
import Foundation
import Testing

private let platformAdmissionDeviceID = UUID(uuidString: "018f2100-0000-7000-8000-000000000001")!
private let platformAdmissionClientID = UUID(uuidString: "018f2000-0000-7000-8000-000000000001")!
private let platformAdmissionPairingID = UUID(uuidString: "018f4000-0000-7000-8000-000000000001")!
private let platformAdmissionDisplayID = UUID(uuidString: "018f6700-0000-7000-8000-000000000001")!

private actor PlatformVisibleAdmission: VisibleInteractiveAdmissionReadingV0 {
    private var values: [VisibleInteractiveAdmissionStateV0]

    init(_ values: [VisibleInteractiveAdmissionStateV0]) {
        self.values = values
    }

    func snapshot() async throws -> VisibleInteractiveAdmissionStateV0 {
        values.count == 1 ? values[0] : values.removeFirst()
    }
}

private struct PlatformAdmissionFixture {
    let directory: URL
    let store: SQLiteSecurityStore
    let approvalPublicKey: Data

    static func create(confirmDisplayName: Bool = true) async throws -> Self {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "maccompanion-platform-admission-\(UUID())",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        let store = try SQLiteSecurityStore(
            path: directory.appendingPathComponent("security.sqlite3").path
        )
        let sessionKey = P256.Signing.PrivateKey()
        let approvalKey = P256.Signing.PrivateKey()
        try await store.commitPairing(
            pairingID: platformAdmissionPairingID,
            record: try StoredDeviceRecord(
                deviceID: platformAdmissionDeviceID,
                clientID: platformAdmissionClientID,
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
        _ = try await store.replaceDeviceGrants(
            platformAdmissionDeviceID,
            grants: CapabilityGrantSet([
                InteractiveControlCapabilityV0.identifier,
            ]),
            occurredAtUnixMilliseconds: 1_001
        )
        if confirmDisplayName {
            try await store.setDeviceDisplayName(
                platformAdmissionDeviceID,
                displayName: DeviceDisplayName("Jenny’s iPhone"),
                occurredAtUnixMilliseconds: 1_002
            )
        }
        return Self(
            directory: directory,
            store: store,
            approvalPublicKey: approvalKey.publicKey.x963Representation
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private func platformVisibleState(
    revision: UInt64 = 1,
    available: Bool = true
) -> VisibleInteractiveAdmissionStateV0 {
    VisibleInteractiveAdmissionStateV0(
        generation: UUID(uuidString: "018f3000-0000-7000-8000-000000000001")!,
        revision: revision,
        visibleMenuAppAvailable: available,
        selectedDisplayID: available ? platformAdmissionDisplayID : nil
    )
}

@Test func sqliteAdmissionJoinsExactDurableGrantAndStableVisibleRevision() async throws {
    let fixture = try await PlatformAdmissionFixture.create()
    defer { fixture.remove() }
    let reader = SQLiteInteractiveSessionAdmissionReaderV0(
        store: fixture.store,
        visible: PlatformVisibleAdmission([platformVisibleState()])
    )

    let value = try #require(try await reader.snapshot(
        deviceID: platformAdmissionDeviceID
    ))
    #expect(value.deviceID == platformAdmissionDeviceID)
    #expect(value.clientID == platformAdmissionClientID)
    #expect(value.deviceState == .activeGranted)
    #expect(value.authorizationEpoch.rawValue == 2)
    #expect(value.grantRevision.rawValue == 2)
    #expect(value.approvalPublicKeyX963 == fixture.approvalPublicKey)
    #expect(value.grants.capabilityIDs == [
        InteractiveControlCapabilityV0.identifier,
    ])
    let expectedName = try DeviceDisplayName("Jenny’s iPhone")
    #expect(value.deviceDisplayName == expectedName)
    #expect(value.visibleMenuAppAvailable)
    #expect(value.visibleMenuAppGeneration
        == platformVisibleState().generation)
    #expect(value.visibleMenuAppRevision == 1)
    #expect(value.selectedDisplayID == platformAdmissionDisplayID)
}

@Test func sqliteAdmissionRejectsTornVisibleMenuRevision() async throws {
    let fixture = try await PlatformAdmissionFixture.create()
    defer { fixture.remove() }
    let reader = SQLiteInteractiveSessionAdmissionReaderV0(
        store: fixture.store,
        visible: PlatformVisibleAdmission([
            platformVisibleState(revision: 1),
            platformVisibleState(revision: 2),
        ])
    )

    #expect(try await reader.snapshot(deviceID: platformAdmissionDeviceID) == nil)
}

@Test func sqliteAdmissionRequiresLocallyConfirmedDeviceDisplayName() async throws {
    let fixture = try await PlatformAdmissionFixture.create(
        confirmDisplayName: false
    )
    defer { fixture.remove() }
    let reader = SQLiteInteractiveSessionAdmissionReaderV0(
        store: fixture.store,
        visible: PlatformVisibleAdmission([platformVisibleState()])
    )

    #expect(try await reader.snapshot(deviceID: platformAdmissionDeviceID) == nil)
}
