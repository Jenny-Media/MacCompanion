import CompanionDomain
import CompanionIPC
import CompanionInteractiveShared
import Foundation
import Testing

private let codecHostID = UUID(
    uuidString: "018f1000-0000-7000-8000-000000000001"
)!
private let codecDeviceID = UUID(
    uuidString: "018f2100-0000-7000-8000-000000000001"
)!
private let codecSessionID = UUID(
    uuidString: "018f6000-0000-7000-8000-000000000001"
)!
private let codecDisplayID = UUID(
    uuidString: "018f6700-0000-7000-8000-000000000001"
)!
private let codecSurfaceID = UUID(
    uuidString: "018f6100-0000-7000-8000-000000000001"
)!

private func codecLease(
    leaseID: UUID = UUID(
        uuidString: "018f6200-0000-7000-8000-000000000001"
    )!,
    renewalCounter: UInt64 = 0,
    issuedAt: UInt64 = 1_000,
    expiresAt: UInt64 = 2_000
) throws -> InteractiveExecutionLease {
    try InteractiveExecutionLease(
        leaseID: leaseID,
        hostID: codecHostID,
        deviceID: codecDeviceID,
        interactiveSessionID: codecSessionID,
        authorizationEpoch: .init(rawValue: 4),
        selectedDisplayID: codecDisplayID,
        surfaceID: codecSurfaceID,
        surfaceRevision: .init(rawValue: 1),
        coordinateRevision: .init(rawValue: 1),
        allowedInteractionClasses: [.view, .pointer, .keyboard],
        renewalCounter: renewalCounter,
        issuedAtMonotonicNanoseconds: issuedAt,
        expiresAtMonotonicNanoseconds: expiresAt
    )
}

private func codecInstallCommand()
    throws -> InteractiveRuntimeInstallCommandV0
{
    try InteractiveRuntimeInstallCommandV0(
        commandID: UUID(
            uuidString: "018f6300-0000-7000-8000-000000000001"
        )!,
        lease: codecLease(),
        deviceDisplayName: DeviceDisplayName("Jenny’s iPhone"),
        surfaceDescriptor: codecDesktopDescriptor(),
        sessionDeadlineMonotonicNanoseconds: 10_000
    )
}

private func codecDesktopDescriptor()
    throws -> AdaptiveSurfaceDescriptor
{
    try AdaptiveSurfaceDescriptor(
        interactiveSessionID: codecSessionID,
        authorizationEpoch: .init(rawValue: 4),
        surfaceID: codecSurfaceID,
        kind: .desktop,
        surfaceRevision: .init(rawValue: 1),
        coordinateSpaceRevision: .init(rawValue: 1),
        encodedWidth: 1_440,
        encodedHeight: 900,
        logicalWidthPoints: 1_440,
        logicalHeightPoints: 900,
        interactionClasses: [.view, .pointer, .keyboard],
        privacyProfile: .visualOnly,
        metadataFields: [],
        createdAtMonotonicMilliseconds: 1_000,
        expiresAtMonotonicMilliseconds: 11_000
    )
}

@Test func interactiveLeaseCodecRoundTripsInitialDesktopPreparation()
    throws
{
    let command = try LocalInteractiveInitialDesktopPreparationCommandV1(
        commandID: UUID(),
        interactiveSessionID: codecSessionID,
        authorizationEpoch: .init(rawValue: 4),
        selectedDisplayID: codecDisplayID,
        interactionClasses: [.view, .pointer, .keyboard]
    )
    let commandData = try LocalInteractiveLeaseWireCodecV1
        .encodeInitialDesktopCommand(command)
    #expect(
        try LocalInteractiveLeaseWireCodecV1
            .decodeInitialDesktopCommand(commandData) == command
    )

    let receipt = try LocalInteractiveInitialDesktopPreparedReceiptV1(
        correlationID: command.commandID,
        descriptor: codecDesktopDescriptor()
    )
    let receiptData = try LocalInteractiveLeaseWireCodecV1
        .encodeInitialDesktopReceipt(receipt)
    let decoded = try LocalInteractiveLeaseWireCodecV1
        .decodeInitialDesktopReceipt(receiptData)
    #expect(decoded == receipt)
    try decoded.validate(against: command)
}

@Test func interactiveLeaseCodecRoundTripsInstallRenewAndRevoke()
    throws
{
    let install = try codecInstallCommand()
    let encodedInstall = try LocalInteractiveLeaseWireCodecV1
        .encodeInstallCommand(install)
    #expect(
        try LocalInteractiveLeaseWireCodecV1
            .decodeInstallCommand(encodedInstall) == install
    )

    let installReceipt = try InteractiveRuntimeInstallReceiptV0(
        correlationID: install.commandID,
        leaseID: install.lease.leaseID,
        interactiveSessionID: install.lease.interactiveSessionID,
        selectedDisplayID: install.lease.selectedDisplayID,
        menuAppGeneration: UUID(
            uuidString: "018f6400-0000-7000-8000-000000000001"
        )!,
        menuAppRevision: 1,
        readyInteractionClasses: [.view, .pointer, .keyboard],
        indicatorVisible: true
    )
    let encodedInstallReceipt = try LocalInteractiveLeaseWireCodecV1
        .encodeInstallReceipt(installReceipt)
    let decodedInstallReceipt = try LocalInteractiveLeaseWireCodecV1
        .decodeInstallReceipt(encodedInstallReceipt)
    #expect(decodedInstallReceipt == installReceipt)
    try decodedInstallReceipt.validate(against: install)

    let replacement = try codecLease(
        leaseID: UUID(
            uuidString: "018f6200-0000-7000-8000-000000000002"
        )!,
        renewalCounter: 1,
        issuedAt: 1_500,
        expiresAt: 2_500
    )
    let renewal = try InteractiveRuntimeLeaseRenewalV0(
        commandID: UUID(
            uuidString: "018f6300-0000-7000-8000-000000000002"
        )!,
        previousLeaseID: install.lease.leaseID,
        replacement: replacement
    )
    let encodedRenewal = try LocalInteractiveLeaseWireCodecV1
        .encodeRenewal(renewal)
    #expect(
        try LocalInteractiveLeaseWireCodecV1
            .decodeRenewal(encodedRenewal) == renewal
    )

    let revoke = try InteractiveRuntimeRevokeCommandV0(
        commandID: UUID(
            uuidString: "018f6300-0000-7000-8000-000000000003"
        )!,
        leaseID: replacement.leaseID,
        interactiveSessionID: replacement.interactiveSessionID,
        reason: .clientDisconnected
    )
    let encodedRevoke = try LocalInteractiveLeaseWireCodecV1
        .encodeRevokeCommand(revoke)
    #expect(
        try LocalInteractiveLeaseWireCodecV1
            .decodeRevokeCommand(encodedRevoke) == revoke
    )

    let revoked = try InteractiveRuntimeRevokedReceiptV0(
        correlationID: revoke.commandID,
        leaseID: revoke.leaseID,
        interactiveSessionID: revoke.interactiveSessionID,
        inputReleased: true,
        captureStopped: true,
        lastFrameBlanked: true,
        indicatorCleared: true
    )
    let encodedRevoked = try LocalInteractiveLeaseWireCodecV1
        .encodeRevokedReceipt(revoked)
    let decodedRevoked = try LocalInteractiveLeaseWireCodecV1
        .decodeRevokedReceipt(encodedRevoked)
    #expect(decodedRevoked == revoked)
    try decodedRevoked.validate(against: revoke)
}

@Test func interactiveLeaseCodecRejectsNoncanonicalUnknownAndOversizedData()
    throws
{
    let canonical = try LocalInteractiveLeaseWireCodecV1
        .encodeInstallCommand(codecInstallCommand())
    let spaced = Data(" \n".utf8) + canonical
    #expect(
        throws: LocalInteractiveLeaseWireCodecErrorV1
            .nonCanonicalPayload
    ) {
        try LocalInteractiveLeaseWireCodecV1.decodeInstallCommand(spaced)
    }

    var object = try #require(
        JSONSerialization.jsonObject(with: canonical)
            as? [String: Any]
    )
    object["unexpected"] = true
    let unknown = try JSONSerialization.data(
        withJSONObject: object,
        options: [.sortedKeys, .withoutEscapingSlashes]
    )
    #expect(
        throws: LocalInteractiveLeaseWireCodecErrorV1
            .nonCanonicalPayload
    ) {
        try LocalInteractiveLeaseWireCodecV1.decodeInstallCommand(unknown)
    }

    let oversized = Data(
        repeating: 0x61,
        count: LocalInteractiveLeaseWireCodecV1.maximumEncodedBytes + 1
    )
    #expect(
        throws: LocalInteractiveLeaseWireCodecErrorV1.payloadTooLarge
    ) {
        try LocalInteractiveLeaseWireCodecV1
            .decodeInstallCommand(oversized)
    }
}
