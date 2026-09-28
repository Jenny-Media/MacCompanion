import CompanionDomain
import CompanionInteractiveShared
import Foundation
import Testing

private final class InventoryTokenSource: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID]

    init(_ values: [UUID]) { self.values = values }

    func next() -> UUID {
        lock.withLock { values.removeFirst() }
    }
}

private let inventorySessionID = UUID(
    uuidString: "019d6000-0000-7000-8000-000000000001"
)!
private let inventoryAppSource = UUID(
    uuidString: "019d7000-0000-7000-8000-000000000001"
)!
private let inventoryWindowSource = UUID(
    uuidString: "019d7100-0000-7000-8000-000000000001"
)!
private let inventoryAppToken = UUID(
    uuidString: "019d7200-0000-7000-8000-000000000001"
)!
private let inventoryWindowToken = UUID(
    uuidString: "019d7200-0000-7000-8000-000000000002"
)!

private func inventoryObservations()
    throws -> [AdaptiveSurfaceTargetObservationV0]
{
    [
        try AdaptiveSurfaceTargetObservationV0(
            sourceReference: inventoryAppSource,
            kind: .application,
            applicationSourceReference: inventoryAppSource,
            applicationName: "Notes",
            currentWindowAvailable: true
        ),
        try AdaptiveSurfaceTargetObservationV0(
            sourceReference: inventoryWindowSource,
            kind: .window,
            applicationSourceReference: inventoryAppSource,
            applicationName: "ignored window title",
            currentWindowAvailable: true
        ),
    ]
}

@Test func targetInventoryPublishesOnlySanitizedAppAndOrdinalFacts() throws {
    let tokens = InventoryTokenSource([
        inventoryAppToken, inventoryWindowToken,
    ])
    var inventory = try AdaptiveSurfaceTargetInventoryV0(
        interactiveSessionID: inventorySessionID,
        authorizationEpoch: .init(rawValue: 4),
        tokenGenerator: tokens.next
    )
    let snapshot = try inventory.replace(
        observations: inventoryObservations(),
        nowMonotonicMilliseconds: 100
    )
    #expect(snapshot.revision == 1)
    #expect(snapshot.expiresAtMonotonicMilliseconds == 120_100)
    #expect(snapshot.candidates.count == 2)
    #expect(snapshot.candidates[0].kind == .application)
    #expect(snapshot.candidates[0].applicationName == "Notes")
    #expect(snapshot.candidates[0].windowOrdinal == nil)
    #expect(snapshot.candidates[1].kind == .window)
    #expect(snapshot.candidates[1].applicationName == "Notes")
    #expect(snapshot.candidates[1].windowOrdinal == 1)
    #expect(snapshot.candidates[1].applicationToken == inventoryAppToken)
}

@Test func genericWindowOrdinalsUseOnlyMenuLocalSortOrder() throws {
    let application = UUID()
    let laterUUID = UUID(uuidString: "ffffffff-ffff-4fff-8fff-ffffffffffff")!
    let earlierUUID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    let tokenSource = InventoryTokenSource([
        UUID(), UUID(), UUID(),
    ])
    var inventory = try AdaptiveSurfaceTargetInventoryV0(
        interactiveSessionID: UUID(),
        authorizationEpoch: .init(rawValue: 1),
        tokenGenerator: tokenSource.next
    )
    let snapshot = try inventory.replace(
        observations: [
            try AdaptiveSurfaceTargetObservationV0(
                sourceReference: application,
                kind: .application,
                applicationSourceReference: application,
                applicationName: "Notes",
                currentWindowAvailable: true,
                localSortOrder: 50
            ),
            try AdaptiveSurfaceTargetObservationV0(
                sourceReference: earlierUUID,
                kind: .window,
                applicationSourceReference: application,
                applicationName: "not transmitted",
                currentWindowAvailable: true,
                localSortOrder: 20
            ),
            try AdaptiveSurfaceTargetObservationV0(
                sourceReference: laterUUID,
                kind: .window,
                applicationSourceReference: application,
                applicationName: "not transmitted",
                currentWindowAvailable: true,
                localSortOrder: 10
            ),
        ],
        nowMonotonicMilliseconds: 1
    )
    #expect(snapshot.candidates.compactMap(\.windowOrdinal) == [1, 2])
    let first = try inventory.consume(
        targetToken: snapshot.candidates[1].targetToken,
        expectedKind: .window,
        nowMonotonicMilliseconds: 2
    )
    #expect(first.sourceReference == laterUUID)
}

@Test func selectionConsumesEveryTokenAndChecksKindAndHalfOpenExpiry() throws {
    let tokens = InventoryTokenSource([
        inventoryAppToken, inventoryWindowToken,
    ])
    var inventory = try AdaptiveSurfaceTargetInventoryV0(
        interactiveSessionID: inventorySessionID,
        authorizationEpoch: .init(rawValue: 4),
        tokenGenerator: tokens.next
    )
    _ = try inventory.replace(
        observations: inventoryObservations(),
        nowMonotonicMilliseconds: 100,
        lifetimeMilliseconds: 50
    )
    #expect(throws: AdaptiveSurfaceTargetInventoryErrorV0.kindMismatch) {
        try inventory.consume(
            targetToken: inventoryWindowToken,
            expectedKind: .application,
            nowMonotonicMilliseconds: 149
        )
    }
    let resolved = try inventory.consume(
        targetToken: inventoryWindowToken,
        expectedKind: .window,
        nowMonotonicMilliseconds: 149
    )
    #expect(resolved.sourceReference == inventoryWindowSource)
    #expect(throws: AdaptiveSurfaceTargetInventoryErrorV0.staleInventory) {
        try inventory.consume(
            targetToken: inventoryAppToken,
            expectedKind: .application,
            nowMonotonicMilliseconds: 149
        )
    }

    let refreshedTokens = InventoryTokenSource([
        UUID(), UUID(),
    ])
    var expiring = try AdaptiveSurfaceTargetInventoryV0(
        interactiveSessionID: inventorySessionID,
        authorizationEpoch: .init(rawValue: 4),
        tokenGenerator: refreshedTokens.next
    )
    _ = try expiring.replace(
        observations: inventoryObservations(),
        nowMonotonicMilliseconds: 100,
        lifetimeMilliseconds: 50
    )
    #expect(throws: AdaptiveSurfaceTargetInventoryErrorV0.staleInventory) {
        try expiring.snapshot(nowMonotonicMilliseconds: 150)
    }
}

@Test func unavailableCandidateCannotBeConsumed() throws {
    let application = UUID()
    var inventory = try AdaptiveSurfaceTargetInventoryV0(
        interactiveSessionID: UUID(),
        authorizationEpoch: AuthorizationEpoch(rawValue: 4),
        tokenGenerator: InventoryTokenSource(
            [UUID(uuidString: "40000000-0000-4000-8000-000000000001")!]
        ).next
    )
    let snapshot = try inventory.replace(
        observations: [
            try AdaptiveSurfaceTargetObservationV0(
                sourceReference: application,
                kind: .application,
                applicationSourceReference: application,
                applicationName: "No Windows",
                currentWindowAvailable: false
            ),
        ],
        nowMonotonicMilliseconds: 100
    )

    #expect(throws: AdaptiveSurfaceTargetInventoryErrorV0.unavailable) {
        try inventory.consume(
            targetToken: snapshot.candidates[0].targetToken,
            expectedKind: .application,
            nowMonotonicMilliseconds: 101
        )
    }
}

@Test func targetInventoryRejectsNamesOwnershipAndTokenCollisions() throws {
    #expect(throws: AdaptiveSurfaceTargetInventoryErrorV0.invalidObservation) {
        try AdaptiveSurfaceTargetObservationV0(
            sourceReference: UUID(),
            kind: .application,
            applicationSourceReference: UUID(),
            applicationName: "Notes\nSecret",
            currentWindowAvailable: true
        )
    }

    let collision = UUID()
    let tokens = InventoryTokenSource([collision, collision])
    var inventory = try AdaptiveSurfaceTargetInventoryV0(
        interactiveSessionID: inventorySessionID,
        authorizationEpoch: .init(rawValue: 4),
        tokenGenerator: tokens.next
    )
    #expect(throws: AdaptiveSurfaceTargetInventoryErrorV0.tokenCollision) {
        try inventory.replace(
            observations: inventoryObservations(),
            nowMonotonicMilliseconds: 100
        )
    }

    let orphan = try AdaptiveSurfaceTargetObservationV0(
        sourceReference: UUID(),
        kind: .window,
        applicationSourceReference: UUID(),
        applicationName: "Notes",
        currentWindowAvailable: true
    )
    let orphanTokens = InventoryTokenSource([UUID()])
    var orphanInventory = try AdaptiveSurfaceTargetInventoryV0(
        interactiveSessionID: inventorySessionID,
        authorizationEpoch: .init(rawValue: 4),
        tokenGenerator: orphanTokens.next
    )
    #expect(throws: AdaptiveSurfaceTargetInventoryErrorV0.invalidObservation) {
        try orphanInventory.replace(
            observations: [orphan],
            nowMonotonicMilliseconds: 100
        )
    }
}
