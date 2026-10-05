import CompanionClient
import CompanionDiscovery
import CompanionDomain
import CompanionTestSupport
import CompanionWire
import Foundation
import Testing

private struct ConfiguredRouteCatalogFixtureV1: Decodable {
    struct InvalidPair: Decodable {
        let endpointKind: EndpointKind
        let provenance: ClientConfiguredRouteProvenanceV1
    }

    struct InvalidRecord: Decodable {
        let endpoint: EndpointCandidate
        let provenance: ClientConfiguredRouteProvenanceV1
    }

    let validRecords: [ClientConfiguredRouteRecordV1]
    let invalidProvenancePairs: [InvalidPair]
    let invalidRecords: [InvalidRecord]
}

private func configuredRouteCatalogFixtureV1() throws
    -> ConfiguredRouteCatalogFixtureV1
{
    try JSONDecoder().decode(
        ConfiguredRouteCatalogFixtureV1.self,
        from: Data(contentsOf: FixturePaths.authoritativeFixtures()
            .appendingPathComponent("client-configured-routes-v0.1.json"))
    )
}

private func endpointForConfiguredRouteKindV1(
    _ kind: EndpointKind
) throws -> EndpointCandidate {
    switch kind {
    case .bonjour:
        try EndpointCandidate(
            kind: .bonjour,
            value: "mac-test._maccompanion._tcp.local.",
            port: 443
        )
    case .ipv4:
        try EndpointCandidate(kind: .ipv4, value: "10.0.0.2", port: 443)
    case .ipv6:
        try EndpointCandidate(kind: .ipv6, value: "fd00::2", port: 443)
    case .dns:
        try EndpointCandidate(kind: .dns, value: "mac.example.net", port: 443)
    }
}

@Test func configuredRouteFixtureBindsExactWinnerAndClosedObservationClass()
    throws
{
    let fixture = try configuredRouteCatalogFixtureV1()
    let catalog = try ClientConfiguredRouteCatalogV1(
        records: fixture.validRecords
    )
    #expect(catalog.records.count == 4)

    for record in fixture.validRecords {
        #expect(try catalog.exactRecord(forWinningEndpoint: record.endpoint)
            == record)
    }
    #expect(fixture.validRecords[0].observedRouteClass == nil)
    #expect(fixture.validRecords[1].observedRouteClass == nil)
    #expect(fixture.validRecords[2].observedRouteClass == .privateDNS)
    #expect(fixture.validRecords[3].observedRouteClass == .privateNetwork)
}

@Test func configuredRouteRejectsEveryFixtureMismatchAndUnknownWinner()
    throws
{
    let fixture = try configuredRouteCatalogFixtureV1()
    for (index, pair) in fixture.invalidProvenancePairs.enumerated() {
        #expect(throws: ClientConfiguredRouteCatalogErrorV1.invalidRecord) {
            _ = try ClientConfiguredRouteRecordV1(
                configuredRouteID: WireBytes16(
                    Data(repeating: UInt8(index + 1), count: 16)
                ),
                endpoint: endpointForConfiguredRouteKindV1(pair.endpointKind),
                provenance: pair.provenance
            )
        }
    }
    for (index, record) in fixture.invalidRecords.enumerated() {
        #expect(throws: ClientConfiguredRouteCatalogErrorV1.invalidRecord) {
            _ = try ClientConfiguredRouteRecordV1(
                configuredRouteID: WireBytes16(
                    Data(repeating: UInt8(index + 100), count: 16)
                ),
                endpoint: record.endpoint,
                provenance: record.provenance
            )
        }
    }

    let catalog = try ClientConfiguredRouteCatalogV1(
        records: fixture.validRecords
    )
    #expect(throws: ClientConfiguredRouteCatalogErrorV1.winnerNotConfigured) {
        _ = try catalog.exactRecord(
            forWinningEndpoint: EndpointCandidate(
                kind: .dns,
                value: "other.example.net",
                port: 443
            )
        )
    }
}

@Test func configuredRouteCatalogRejectsReusedIDAndEndpoint() throws {
    let fixture = try configuredRouteCatalogFixtureV1()
    let first = fixture.validRecords[0]
    let second = fixture.validRecords[1]
    let reusedID = try ClientConfiguredRouteRecordV1(
        configuredRouteID: first.configuredRouteID,
        endpoint: second.endpoint,
        provenance: second.provenance
    )
    #expect(throws: ClientConfiguredRouteCatalogErrorV1.duplicateRouteID) {
        _ = try ClientConfiguredRouteCatalogV1(records: [first, reusedID])
    }

    let reusedEndpoint = try ClientConfiguredRouteRecordV1(
        configuredRouteID: second.configuredRouteID,
        endpoint: first.endpoint,
        provenance: first.provenance
    )
    #expect(throws: ClientConfiguredRouteCatalogErrorV1.duplicateEndpoint) {
        _ = try ClientConfiguredRouteCatalogV1(
            records: [first, reusedEndpoint]
        )
    }
}

@Test func directPrivateAddressRejectsPublicAndAcceptsOnlyPrivateLiterals()
    throws
{
    for value in ["8.8.8.8", "172.32.0.1", "203.0.113.5"] {
        #expect(throws: ClientConfiguredRouteCatalogErrorV1.invalidRecord) {
            _ = try ClientConfiguredRouteRecordV1(
                configuredRouteID: WireBytes16(
                    Data(repeating: 1, count: 16)
                ),
                endpoint: EndpointCandidate(
                    kind: .ipv4,
                    value: value,
                    port: 443
                ),
                provenance: .directPrivateAddress
            )
        }
    }
    for value in ["10.0.0.1", "172.16.0.1", "192.168.1.1", "fd00::1"] {
        let kind: EndpointKind = value.contains(":") ? .ipv6 : .ipv4
        #expect(throws: Never.self) {
            _ = try ClientConfiguredRouteRecordV1(
                configuredRouteID: WireBytes16(
                    Data(repeating: 2, count: 16)
                ),
                endpoint: EndpointCandidate(
                    kind: kind,
                    value: value,
                    port: 443
                ),
                provenance: .directPrivateAddress
            )
        }
    }
    #expect(throws: ClientConfiguredRouteCatalogErrorV1.invalidRecord) {
        _ = try ClientConfiguredRouteRecordV1(
            configuredRouteID: WireBytes16(
                Data(repeating: 3, count: 16)
            ),
            endpoint: EndpointCandidate(
                kind: .ipv6,
                value: "2001:db8::1",
                port: 443
            ),
            provenance: .directPrivateAddress
        )
    }
}

private func configuredRouteSnapshotV1(
    hostID: UUID,
    revision: UInt64,
    records: [ClientConfiguredRouteRecordV1]
) throws -> ClientConfiguredRouteCatalogSnapshotV1 {
    try ClientConfiguredRouteCatalogSnapshotV1(
        hostID: hostID,
        revision: revision,
        catalog: ClientConfiguredRouteCatalogV1(records: records)
    )
}

@Test func configuredRouteStorageIsCanonicalRevisionFencedAndRestartSafe()
    async throws
{
    let fixture = try configuredRouteCatalogFixtureV1()
    let hostID = UUID()
    let first = try configuredRouteSnapshotV1(
        hostID: hostID,
        revision: 1,
        records: Array(fixture.validRecords.prefix(2))
    )
    let encoded = try ClientConfiguredRouteCatalogStorageCodecV1.encode(first)
    #expect(try ClientConfiguredRouteCatalogStorageCodecV1.decode(encoded) == first)

    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-configured-routes-\(UUID())",
        isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try AtomicFileClientConfiguredRouteStoreV1(directory: root)
    #expect(try await store.replaceAtomically(
        first,
        expectedRevision: nil
    ) == .inserted)
    #expect(try await store.replaceAtomically(
        first,
        expectedRevision: nil
    ) == .alreadyPresentExactSnapshot)

    let second = try configuredRouteSnapshotV1(
        hostID: hostID,
        revision: 2,
        records: fixture.validRecords
    )
    await #expect(
        throws: ClientConfiguredRouteFileStoreErrorV1.revisionConflict
    ) {
        _ = try await store.replaceAtomically(second, expectedRevision: 0)
    }
    #expect(try await store.replaceAtomically(
        second,
        expectedRevision: 1
    ) == .replaced)

    let restarted = try AtomicFileClientConfiguredRouteStoreV1(directory: root)
    #expect(try await restarted.snapshot(hostID: hostID) == second)
}

@Test func configuredRouteStorageFaultsConvergeAtRenameBoundary()
    async throws
{
    let fixture = try configuredRouteCatalogFixtureV1()
    let hostID = UUID()
    let first = try configuredRouteSnapshotV1(
        hostID: hostID,
        revision: 1,
        records: [fixture.validRecords[0]]
    )
    let second = try configuredRouteSnapshotV1(
        hostID: hostID,
        revision: 2,
        records: [fixture.validRecords[1]]
    )
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-configured-route-faults-\(UUID())",
        isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let initial = try AtomicFileClientConfiguredRouteStoreV1(directory: root)
    _ = try await initial.replaceAtomically(first, expectedRevision: nil)

    let before = try AtomicFileClientConfiguredRouteStoreV1(
        directory: root,
        injectedFaults: [.beforeRename]
    )
    await #expect(throws: ClientConfiguredRouteFileStoreErrorV1.injectedFault(
        .beforeRename
    )) {
        _ = try await before.replaceAtomically(second, expectedRevision: 1)
    }
    #expect(try await initial.snapshot(hostID: hostID) == first)

    let after = try AtomicFileClientConfiguredRouteStoreV1(
        directory: root,
        injectedFaults: [.afterRenameBeforeDirectorySync]
    )
    await #expect(throws: ClientConfiguredRouteFileStoreErrorV1.injectedFault(
        .afterRenameBeforeDirectorySync
    )) {
        _ = try await after.replaceAtomically(second, expectedRevision: 1)
    }
    let restarted = try AtomicFileClientConfiguredRouteStoreV1(directory: root)
    #expect(try await restarted.snapshot(hostID: hostID) == second)
}

@Test func macLibraryForgetRemovesOnlySelectedHostRoutesAndSurvivesRestart() async throws {
    let fixture = try configuredRouteCatalogFixtureV1()
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("maccompanion-route-removal-\(UUID())")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try AtomicFileClientConfiguredRouteStoreV1(directory: root)
    let forgotten = try configuredRouteSnapshotV1(hostID: UUID(), revision: 1, records: [fixture.validRecords[0]])
    let retained = try configuredRouteSnapshotV1(hostID: UUID(), revision: 1, records: [fixture.validRecords[1]])
    _ = try await store.replaceAtomically(forgotten, expectedRevision: nil)
    _ = try await store.replaceAtomically(retained, expectedRevision: nil)
    try await store.remove(hostID: forgotten.hostID)
    try await store.remove(hostID: forgotten.hostID)
    let restarted = try AtomicFileClientConfiguredRouteStoreV1(directory: root)
    #expect(try await restarted.snapshot(hostID: forgotten.hostID) == nil)
    #expect(try await restarted.snapshot(hostID: retained.hostID) == retained)
}

private enum ConfiguredRouteConcurrentReplaceOutcomeV1: Equatable {
    case replaced
    case conflict
    case unexpectedFailure
}

@Test func configuredRouteStorageSerializesIndependentStoreInstances()
    async throws
{
    let fixture = try configuredRouteCatalogFixtureV1()
    let hostID = UUID()
    let first = try configuredRouteSnapshotV1(
        hostID: hostID,
        revision: 1,
        records: [fixture.validRecords[0]]
    )
    let replacementA = try configuredRouteSnapshotV1(
        hostID: hostID,
        revision: 2,
        records: Array(fixture.validRecords.prefix(2))
    )
    let replacementB = try configuredRouteSnapshotV1(
        hostID: hostID,
        revision: 2,
        records: Array(fixture.validRecords.prefix(3))
    )
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-configured-route-lock-\(UUID())",
        isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let initial = try AtomicFileClientConfiguredRouteStoreV1(directory: root)
    _ = try await initial.replaceAtomically(first, expectedRevision: nil)
    let storeA = try AtomicFileClientConfiguredRouteStoreV1(directory: root)
    let storeB = try AtomicFileClientConfiguredRouteStoreV1(directory: root)

    let taskA = Task {
        do {
            _ = try await storeA.replaceAtomically(
                replacementA,
                expectedRevision: 1
            )
            return ConfiguredRouteConcurrentReplaceOutcomeV1.replaced
        } catch ClientConfiguredRouteFileStoreErrorV1.revisionConflict {
            return ConfiguredRouteConcurrentReplaceOutcomeV1.conflict
        } catch {
            return ConfiguredRouteConcurrentReplaceOutcomeV1.unexpectedFailure
        }
    }
    let taskB = Task {
        do {
            _ = try await storeB.replaceAtomically(
                replacementB,
                expectedRevision: 1
            )
            return ConfiguredRouteConcurrentReplaceOutcomeV1.replaced
        } catch ClientConfiguredRouteFileStoreErrorV1.revisionConflict {
            return ConfiguredRouteConcurrentReplaceOutcomeV1.conflict
        } catch {
            return ConfiguredRouteConcurrentReplaceOutcomeV1.unexpectedFailure
        }
    }
    let outcomes = [await taskA.value, await taskB.value]
    #expect(outcomes.filter { $0 == .replaced }.count == 1)
    #expect(outcomes.filter { $0 == .conflict }.count == 1)
    #expect(!outcomes.contains(.unexpectedFailure))
}

@Test func configuredRouteStorageRecoversOnlyOwnedPendingFilesAndRejectsSiblings()
    async throws
{
    let fixture = try configuredRouteCatalogFixtureV1()
    let hostID = UUID()
    let snapshot = try configuredRouteSnapshotV1(
        hostID: hostID,
        revision: 1,
        records: [fixture.validRecords[0]]
    )
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "maccompanion-configured-route-recovery-\(UUID())",
        isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let initial = try AtomicFileClientConfiguredRouteStoreV1(directory: root)
    _ = try await initial.replaceAtomically(snapshot, expectedRevision: nil)

    let pending = root.appendingPathComponent(
        ".pending-\(UUID().uuidString.lowercased())"
    )
    try Data([0]).write(to: pending)
    let restarted = try AtomicFileClientConfiguredRouteStoreV1(directory: root)
    #expect(!FileManager.default.fileExists(atPath: pending.path))
    #expect(try await restarted.snapshot(hostID: hostID) == snapshot)

    let unknown = root.appendingPathComponent(".unexpected")
    try Data([0]).write(to: unknown)
    await #expect(
        throws: ClientConfiguredRouteFileStoreErrorV1.unsafeStorage
    ) {
        _ = try await restarted.snapshot(hostID: hostID)
    }
}

@Test func configuredRouteEditorAppliesExplicitProvenanceWithOneRevision()
    throws
{
    let fixture = try configuredRouteCatalogFixtureV1()
    let hostID = UUID()
    let initial = try configuredRouteSnapshotV1(
        hostID: hostID,
        revision: 4,
        records: [fixture.validRecords[0]]
    )
    let newID = try WireBytes16(Data(repeating: 0xaa, count: 16))
    let added = try ClientConfiguredRouteEditorV1.apply(
        .add(
            endpoint: fixture.validRecords[3].endpoint,
            provenance: .privateNetwork
        ),
        to: initial,
        newRouteID: { newID }
    )
    #expect(added.hostID == hostID)
    #expect(added.revision == 5)
    #expect(added.catalog.records.map(\.configuredRouteID) == [
        fixture.validRecords[0].configuredRouteID,
        newID,
    ])
    #expect(added.catalog.records[1].provenance == .privateNetwork)

    let replaced = try ClientConfiguredRouteEditorV1.apply(
        .replace(
            configuredRouteID: newID,
            endpoint: fixture.validRecords[2].endpoint,
            provenance: .privateDNS
        ),
        to: added
    )
    #expect(replaced.revision == 6)
    #expect(replaced.catalog.records[1].configuredRouteID == newID)
    #expect(replaced.catalog.records[1].provenance == .privateDNS)

    let removed = try ClientConfiguredRouteEditorV1.apply(
        .remove(configuredRouteID: newID),
        to: replaced
    )
    #expect(removed.revision == 7)
    #expect(removed.catalog.records == [fixture.validRecords[0]])
}

@Test func configuredRouteEditorNeverInfersOrBroadensProvenance() throws {
    let fixture = try configuredRouteCatalogFixtureV1()
    let snapshot = try configuredRouteSnapshotV1(
        hostID: UUID(),
        revision: 1,
        records: [fixture.validRecords[0]]
    )
    #expect(throws: ClientConfiguredRouteCatalogErrorV1.invalidRecord) {
        _ = try ClientConfiguredRouteEditorV1.apply(
            .add(
                endpoint: fixture.validRecords[0].endpoint,
                provenance: .privateNetwork
            ),
            to: snapshot,
            newRouteID: {
                try WireBytes16(Data(repeating: 0xbb, count: 16))
            }
        )
    }
    #expect(throws: ClientConfiguredRouteEditErrorV1.routeNotFound) {
        _ = try ClientConfiguredRouteEditorV1.apply(
            .remove(configuredRouteID: WireBytes16(
                Data(repeating: 0xcc, count: 16)
            )),
            to: snapshot
        )
    }
    #expect(throws: ClientConfiguredRouteEditErrorV1.noChange) {
        _ = try ClientConfiguredRouteEditorV1.apply(
            .replace(
                configuredRouteID:
                    fixture.validRecords[0].configuredRouteID,
                endpoint: fixture.validRecords[0].endpoint,
                provenance: fixture.validRecords[0].provenance
            ),
            to: snapshot
        )
    }
    #expect(throws: ClientConfiguredRouteCatalogErrorV1.boundsExceeded) {
        _ = try ClientConfiguredRouteEditorV1.apply(
            .remove(
                configuredRouteID:
                    fixture.validRecords[0].configuredRouteID
            ),
            to: snapshot
        )
    }
}
