import CompanionDomain
import CompanionIPC
import CompanionInteractiveShared
import Foundation
import Testing

private let leaseID = UUID(uuidString: "018f5000-0000-7000-8000-000000000001")!
private let hostID = UUID(uuidString: "018f1000-0000-7000-8000-000000000001")!
private let deviceID = UUID(uuidString: "018f2000-0000-7000-8000-000000000001")!
private let sessionID = UUID(uuidString: "018f6000-0000-7000-8000-000000000001")!
private let displayID = UUID(uuidString: "018f6700-0000-7000-8000-000000000001")!
private let surfaceID = UUID(uuidString: "018f6100-0000-7000-8000-000000000001")!

private func lease() throws -> InteractiveExecutionLease {
    try InteractiveExecutionLease(
        leaseID: leaseID,
        hostID: hostID,
        deviceID: deviceID,
        interactiveSessionID: sessionID,
        authorizationEpoch: .init(rawValue: 7),
        selectedDisplayID: displayID,
        surfaceID: surfaceID,
        surfaceRevision: .init(rawValue: 11),
        coordinateRevision: .init(rawValue: 13),
        allowedInteractionClasses: [.view, .pointer, .keyboard, .text],
        renewalCounter: 0,
        issuedAtMonotonicNanoseconds: 1_000,
        expiresAtMonotonicNanoseconds: 2_000
    )
}

private func fence(
    leaseID selectedLeaseID: UUID = leaseID,
    hostID selectedHostID: UUID = hostID,
    authorizationEpoch: UInt64 = 7,
    selectedDisplayID: UUID = displayID,
    selectedSurfaceID: UUID = surfaceID,
    surfaceRevision: UInt64 = 11,
    coordinateRevision: UInt64 = 13
) -> InteractiveCommandFence {
    InteractiveCommandFence(
        leaseID: selectedLeaseID,
        hostID: selectedHostID,
        deviceID: deviceID,
        interactiveSessionID: sessionID,
        authorizationEpoch: .init(rawValue: authorizationEpoch),
        selectedDisplayID: selectedDisplayID,
        surfaceID: selectedSurfaceID,
        surfaceRevision: .init(rawValue: surfaceRevision),
        coordinateRevision: .init(rawValue: coordinateRevision)
    )
}

@Test func currentInteractiveFenceIsAcceptedOnlyInsideLeaseLifetime() throws {
    let value = try lease()
    try value.validate(fence: fence(), nowMonotonicNanoseconds: 1_999)

    #expect(throws: InteractiveLeaseError.expired) {
        try value.validate(fence: fence(), nowMonotonicNanoseconds: 2_000)
    }
}

@Test func everyInteractiveFenceDimensionFailsIndependently() throws {
    let value = try lease()
    let staleLeaseID = UUID(uuidString: "018f5000-0000-7000-8000-000000000002")!

    #expect(throws: InteractiveLeaseError.staleLease) {
        try value.validate(fence: fence(leaseID: staleLeaseID), nowMonotonicNanoseconds: 1_500)
    }
    #expect(throws: InteractiveLeaseError.staleAuthorizationEpoch) {
        try value.validate(fence: fence(authorizationEpoch: 6), nowMonotonicNanoseconds: 1_500)
    }
    #expect(throws: InteractiveLeaseError.wrongHost) {
        try value.validate(
            fence: fence(hostID: UUID()),
            nowMonotonicNanoseconds: 1_500
        )
    }
    #expect(throws: InteractiveLeaseError.wrongDisplay) {
        try value.validate(
            fence: fence(selectedDisplayID: UUID()),
            nowMonotonicNanoseconds: 1_500
        )
    }
    #expect(throws: InteractiveLeaseError.wrongSurface) {
        try value.validate(
            fence: fence(selectedSurfaceID: UUID()),
            nowMonotonicNanoseconds: 1_500
        )
    }
    #expect(throws: InteractiveLeaseError.staleSurfaceRevision) {
        try value.validate(fence: fence(surfaceRevision: 10), nowMonotonicNanoseconds: 1_500)
    }
    #expect(throws: InteractiveLeaseError.staleCoordinateRevision) {
        try value.validate(fence: fence(coordinateRevision: 12), nowMonotonicNanoseconds: 1_500)
    }
}

@Test func leaseLifetimeAndInteractionClassesAreClosedAndBounded() throws {
    let value = try lease()
    #expect(value.admits(.view))
    #expect(value.admits(.text))

    #expect(throws: InteractiveLeaseError.invalidLease) {
        try InteractiveExecutionLease(
            leaseID: leaseID,
            hostID: hostID,
            deviceID: deviceID,
            interactiveSessionID: sessionID,
            authorizationEpoch: .init(rawValue: 7),
            selectedDisplayID: displayID,
            surfaceID: surfaceID,
            surfaceRevision: .init(rawValue: 11),
            coordinateRevision: .init(rawValue: 13),
            allowedInteractionClasses: [.view, .text],
            renewalCounter: 0,
            issuedAtMonotonicNanoseconds: 0,
            expiresAtMonotonicNanoseconds:
                InteractiveExecutionLease.maximumLifetimeNanoseconds + 1
        )
    }
}

@Test func decodingCannotBypassInteractiveLeaseInvariants() throws {
    let encoded = try JSONEncoder().encode(lease())
    var object = try #require(
        JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object["expiresAtMonotonicNanoseconds"] =
        InteractiveExecutionLease.maximumLifetimeNanoseconds + 1_002
    let excessiveLifetime = try JSONSerialization.data(withJSONObject: object)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(
            InteractiveExecutionLease.self,
            from: excessiveLifetime
        )
    }

    object["expiresAtMonotonicNanoseconds"] = 2_000
    object["allowedInteractionClasses"] = ["view", "view"]
    let duplicateClasses = try JSONSerialization.data(withJSONObject: object)

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(
            InteractiveExecutionLease.self,
            from: duplicateClasses
        )
    }
}
