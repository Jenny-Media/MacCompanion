import CompanionDomain
import CompanionIPC
import Foundation
import Testing

private let controlReviewRequestID = UUID(
    uuidString: "018f9900-0000-7000-8000-000000000001"
)!
private let controlReviewDeviceID = UUID(
    uuidString: "018f9900-0000-7000-8000-000000000002"
)!
private let controlReviewID = UUID(
    uuidString: "018f9900-0000-7000-8000-000000000003"
)!

@Test func interactiveControlGrantReviewRoundTripsAndBindsRequest() throws {
    let request = try LocalInteractiveControlGrantReviewRequestV0(
        commandID: controlReviewRequestID,
        requestedAtUnixMilliseconds: 1_787_601_600_000
    )
    let review = try LocalInteractiveControlGrantReviewV0(
        correlationID: request.commandID,
        reviewID: controlReviewID,
        deviceID: controlReviewDeviceID,
        deviceDisplayName: DeviceDisplayName("iPhone"),
        authorizationEpoch: .init(rawValue: 1),
        grantRevision: .init(rawValue: 1),
        policyRevision: .init(rawValue: 1),
        currentGrants: CapabilityGrantSet([]),
        createdAtUnixMilliseconds: 1_787_601_600_000,
        expiresAtUnixMilliseconds: 1_787_601_900_000
    )

    let encoded = try LocalMenuPairingCommandWireCodecV1
        .encodeInteractiveControlGrantReview(review)
    let decoded = try LocalMenuPairingCommandWireCodecV1
        .decodeInteractiveControlGrantReview(encoded)
    #expect(decoded == review)
    try decoded.validate(against: request)
    let proposed = try decoded.proposedGrantSet()
    #expect(proposed.capabilityIDs == [
        InteractiveControlDurableGrantV0.identifier,
    ])
}

@Test func interactiveControlDescriptorIsFixedAndNotLockEligible() throws {
    let descriptor = try InteractiveControlDurableGrantV0.descriptor()
    #expect(
        descriptor.capabilityID
            == "maccompanion.interactive.control"
    )
    #expect(descriptor.effects.dataAccess == .privateData)
    #expect(descriptor.effects.requiresForegroundSession)
    #expect(!descriptor.effects.allowedWhileLocked)
    #expect(!descriptor.effects.invokesExternalService)
}

@Test func interactiveControlReviewRejectsExistingControlGrant() throws {
    #expect(throws: LocalInteractiveControlGrantErrorV0.invalidReview) {
        _ = try LocalInteractiveControlGrantReviewV0(
            correlationID: controlReviewRequestID,
            reviewID: controlReviewID,
            deviceID: controlReviewDeviceID,
            deviceDisplayName: DeviceDisplayName("iPhone"),
            authorizationEpoch: .init(rawValue: 2),
            grantRevision: .init(rawValue: 2),
            policyRevision: .init(rawValue: 1),
            currentGrants: CapabilityGrantSet([
                InteractiveControlDurableGrantV0.identifier,
            ]),
            createdAtUnixMilliseconds: 2_000,
            expiresAtUnixMilliseconds: 302_000
        )
    }
}
