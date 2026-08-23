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

@Test func interactiveLeaseCodecRoundTripsSurfaceRuntimeFamily() throws {
    let targets = try LocalInteractiveSurfaceTargetsCommandV1(
        commandID: UUID(),
        interactiveSessionID: codecSessionID,
        authorizationEpoch: .init(rawValue: 4)
    )
    let targetsData = try LocalInteractiveLeaseWireCodecV1
        .encodeSurfaceTargetsCommand(targets)
    #expect(
        try LocalInteractiveLeaseWireCodecV1
            .decodeSurfaceTargetsCommand(targetsData) == targets
    )

    let applicationToken = UUID()
    let snapshot = try AdaptiveSurfaceTargetInventorySnapshotV0(
        interactiveSessionID: codecSessionID,
        authorizationEpoch: .init(rawValue: 4),
        revision: 1,
        createdAtMonotonicMilliseconds: 1_000,
        expiresAtMonotonicMilliseconds: 11_000,
        candidates: [try AdaptiveSurfaceTargetCandidateV0(
            targetToken: applicationToken,
            kind: .application,
            applicationToken: applicationToken,
            applicationName: "Notes",
            windowOrdinal: nil,
            currentWindowAvailable: true
        )]
    )
    let targetsReceipt = try LocalInteractiveSurfaceTargetsReceiptV1(
        correlationID: targets.commandID,
        snapshot: snapshot
    )
    let targetsReceiptData = try LocalInteractiveLeaseWireCodecV1
        .encodeSurfaceTargetsReceipt(targetsReceipt)
    let decodedTargetsReceipt = try LocalInteractiveLeaseWireCodecV1
        .decodeSurfaceTargetsReceipt(targetsReceiptData)
    #expect(decodedTargetsReceipt == targetsReceipt)
    try decodedTargetsReceipt.validate(against: targets)

    let resolve = try LocalInteractiveSurfaceResolveCommandV1(
        commandID: UUID(),
        interactiveSessionID: codecSessionID,
        authorizationEpoch: .init(rawValue: 4),
        currentSurfaceID: codecSurfaceID,
        expectedSurfaceRevision: .init(rawValue: 1),
        expectedCoordinateSpaceRevision: .init(rawValue: 1),
        targetKind: .application,
        targetToken: applicationToken
    )
    let resolveData = try LocalInteractiveLeaseWireCodecV1
        .encodeSurfaceResolveCommand(resolve)
    #expect(
        try LocalInteractiveLeaseWireCodecV1
            .decodeSurfaceResolveCommand(resolveData) == resolve
    )

    let nextSurfaceID = UUID()
    let descriptor = try AdaptiveSurfaceDescriptor(
        interactiveSessionID: codecSessionID,
        authorizationEpoch: .init(rawValue: 4),
        surfaceID: nextSurfaceID,
        kind: .application,
        surfaceRevision: .init(rawValue: 2),
        coordinateSpaceRevision: .init(rawValue: 2),
        applicationToken: applicationToken,
        parentSurfaceID: codecSurfaceID,
        fallbackSurfaceID: codecSurfaceID,
        encodedWidth: 1_440,
        encodedHeight: 900,
        logicalWidthPoints: 1_440,
        logicalHeightPoints: 900,
        interactionClasses: [.view, .pointer, .keyboard],
        privacyProfile: .visualOnly,
        metadataFields: [.applicationName, .currentWindowAvailable],
        createdAtMonotonicMilliseconds: 1_000,
        expiresAtMonotonicMilliseconds: 11_000
    )
    let resolvedReceipt = try LocalInteractiveSurfaceResolvedReceiptV1(
        correlationID: resolve.commandID,
        descriptor: descriptor
    )
    let resolvedData = try LocalInteractiveLeaseWireCodecV1
        .encodeSurfaceResolvedReceipt(resolvedReceipt)
    let decodedResolved = try LocalInteractiveLeaseWireCodecV1
        .decodeSurfaceResolvedReceipt(resolvedData)
    #expect(decodedResolved == resolvedReceipt)
    try decodedResolved.validate(against: resolve)

    let replacement = try InteractiveExecutionLease(
        leaseID: UUID(),
        hostID: codecHostID,
        deviceID: codecDeviceID,
        interactiveSessionID: codecSessionID,
        authorizationEpoch: .init(rawValue: 4),
        selectedDisplayID: codecDisplayID,
        surfaceID: nextSurfaceID,
        surfaceRevision: .init(rawValue: 2),
        coordinateRevision: .init(rawValue: 2),
        allowedInteractionClasses: [.view, .pointer, .keyboard],
        renewalCounter: 1,
        issuedAtMonotonicNanoseconds: 1_500,
        expiresAtMonotonicNanoseconds: 2_500
    )
    let transition = try InteractiveRuntimeSurfaceTransitionCommandV0(
        commandID: UUID(),
        previousLeaseID: try codecLease().leaseID,
        replacement: replacement,
        descriptor: descriptor
    )
    let transitionData = try LocalInteractiveLeaseWireCodecV1
        .encodeSurfaceTransitionCommand(transition)
    #expect(
        try LocalInteractiveLeaseWireCodecV1
            .decodeSurfaceTransitionCommand(transitionData) == transition
    )
    let transitionReceipt = try InteractiveRuntimeSurfaceTransitionReceiptV0(
        correlationID: transition.commandID,
        previousLeaseID: transition.previousLeaseID,
        replacementLeaseID: replacement.leaseID,
        interactiveSessionID: codecSessionID,
        surfaceID: nextSurfaceID,
        surfaceRevision: .init(rawValue: 2),
        coordinateRevision: .init(rawValue: 2),
        mediaSequenceBeforeTransition: 4,
        inputReleased: true,
        captureSourcePrepared: true
    )
    let transitionReceiptData = try LocalInteractiveLeaseWireCodecV1
        .encodeSurfaceTransitionReceipt(transitionReceipt)
    let decodedTransitionReceipt = try LocalInteractiveLeaseWireCodecV1
        .decodeSurfaceTransitionReceipt(transitionReceiptData)
    #expect(decodedTransitionReceipt == transitionReceipt)
    try decodedTransitionReceipt.validate(against: transition)

    let acknowledgement = try InteractiveRuntimeSurfaceAcknowledgementCommandV0(
        commandID: UUID(),
        transitionCommandID: transition.commandID,
        leaseID: replacement.leaseID,
        interactiveSessionID: codecSessionID,
        surfaceID: nextSurfaceID,
        surfaceRevision: .init(rawValue: 2),
        coordinateRevision: .init(rawValue: 2),
        readyMediaSequence: 7
    )
    let acknowledgementData = try LocalInteractiveLeaseWireCodecV1
        .encodeSurfaceAcknowledgementCommand(acknowledgement)
    #expect(
        try LocalInteractiveLeaseWireCodecV1
            .decodeSurfaceAcknowledgementCommand(acknowledgementData)
            == acknowledgement
    )
    let acknowledgementReceipt = try
        InteractiveRuntimeSurfaceAcknowledgementReceiptV0(
            correlationID: acknowledgement.commandID,
            transitionCommandID: transition.commandID,
            leaseID: replacement.leaseID,
            interactiveSessionID: codecSessionID,
            surfaceID: nextSurfaceID,
            surfaceRevision: .init(rawValue: 2),
            coordinateRevision: .init(rawValue: 2),
            readyMediaSequence: 7,
            inputResumed: true
        )
    let acknowledgementReceiptData = try LocalInteractiveLeaseWireCodecV1
        .encodeSurfaceAcknowledgementReceipt(acknowledgementReceipt)
    let decodedAcknowledgementReceipt = try LocalInteractiveLeaseWireCodecV1
        .decodeSurfaceAcknowledgementReceipt(acknowledgementReceiptData)
    #expect(decodedAcknowledgementReceipt == acknowledgementReceipt)
    try decodedAcknowledgementReceipt.validate(against: acknowledgement)

    let failure = LocalInteractiveSurfaceFailureCommandV1(
        commandID: UUID(),
        interactiveSessionID: codecSessionID,
        reason: .protocolViolation
    )
    let failureData = try LocalInteractiveLeaseWireCodecV1
        .encodeSurfaceFailureCommand(failure)
    #expect(
        try LocalInteractiveLeaseWireCodecV1
            .decodeSurfaceFailureCommand(failureData) == failure
    )
    let failureReceipt = try LocalInteractiveSurfaceFailureReceiptV1(
        correlationID: failure.commandID,
        interactiveSessionID: codecSessionID,
        terminated: true
    )
    let failureReceiptData = try LocalInteractiveLeaseWireCodecV1
        .encodeSurfaceFailureReceipt(failureReceipt)
    let decodedFailureReceipt = try LocalInteractiveLeaseWireCodecV1
        .decodeSurfaceFailureReceipt(failureReceiptData)
    #expect(decodedFailureReceipt == failureReceipt)
    try decodedFailureReceipt.validate(against: failure)

    let focusSnapshot = try LocalInteractiveFocusSnapshotCommandV1(
        commandID: UUID(),
        interactiveSessionID: codecSessionID,
        authorizationEpoch: .init(rawValue: 4),
        currentSurfaceID: nextSurfaceID,
        expectedSurfaceRevision: .init(rawValue: 2),
        expectedCoordinateSpaceRevision: .init(rawValue: 2)
    )
    let focusSnapshotData = try LocalInteractiveLeaseWireCodecV1
        .encodeFocusSnapshotCommand(focusSnapshot)
    #expect(
        try LocalInteractiveLeaseWireCodecV1
            .decodeFocusSnapshotCommand(focusSnapshotData) == focusSnapshot
    )
    let focus = try SurfaceFocus(
        token: UUID(),
        revision: .init(rawValue: 3),
        category: .text,
        bounds: NormalizedSurfaceRect(
            x: 100,
            y: 200,
            width: 300,
            height: 400
        ),
        editable: true,
        secure: false
    )
    let focusCandidate = try LocalInteractiveFocusCandidateV1(
        recommendedTargetKind: .focusedRegion,
        focus: focus,
        inputPaused: false,
        reason: .verifiedFocus,
        validForMilliseconds: 1_000
    )
    let focusReceipt = LocalInteractiveFocusSnapshotReceiptV1(
        correlationID: focusSnapshot.commandID,
        command: focusSnapshot,
        candidate: focusCandidate
    )
    let focusReceiptData = try LocalInteractiveLeaseWireCodecV1
        .encodeFocusSnapshotReceipt(focusReceipt)
    let decodedFocusReceipt = try LocalInteractiveLeaseWireCodecV1
        .decodeFocusSnapshotReceipt(focusReceiptData)
    #expect(decodedFocusReceipt == focusReceipt)
    try decodedFocusReceipt.validate(against: focusSnapshot)
}

@Test func localFocusSnapshotRejectsBroadenedOrMismatchedShapes() throws {
    let command = try LocalInteractiveFocusSnapshotCommandV1(
        commandID: UUID(),
        interactiveSessionID: codecSessionID,
        authorizationEpoch: .init(rawValue: 4),
        currentSurfaceID: codecSurfaceID,
        expectedSurfaceRevision: .init(rawValue: 1),
        expectedCoordinateSpaceRevision: .init(rawValue: 1)
    )
    #expect(throws: LocalInteractiveSurfaceRuntimeErrorV1.invalidReceipt) {
        _ = try LocalInteractiveFocusCandidateV1(
            recommendedTargetKind: .application,
            focus: nil,
            inputPaused: false,
            reason: .noVerifiedFocus,
            validForMilliseconds: 1_000
        )
    }
    let desktop = try LocalInteractiveFocusCandidateV1(
        recommendedTargetKind: .desktop,
        focus: nil,
        inputPaused: true,
        reason: .targetDisappeared,
        validForMilliseconds: 1_000
    )
    let mismatched = LocalInteractiveFocusSnapshotReceiptV1(
        correlationID: UUID(),
        command: command,
        candidate: desktop
    )
    #expect(throws: LocalInteractiveSurfaceRuntimeErrorV1.invalidReceipt) {
        try mismatched.validate(against: command)
    }
}

@Test func surfaceTargetReceiptMaximalNamesRemainWithinXPCBound() throws {
    let command = try LocalInteractiveSurfaceTargetsCommandV1(
        commandID: UUID(),
        interactiveSessionID: codecSessionID,
        authorizationEpoch: .init(rawValue: 4)
    )
    let name = String(repeating: "M", count: 128)
    let candidates = try (0..<9).map { _ in
        let token = UUID()
        return try AdaptiveSurfaceTargetCandidateV0(
            targetToken: token,
            kind: .application,
            applicationToken: token,
            applicationName: name,
            windowOrdinal: nil,
            currentWindowAvailable: true
        )
    }
    let snapshot = try AdaptiveSurfaceTargetInventorySnapshotV0(
        interactiveSessionID: codecSessionID,
        authorizationEpoch: .init(rawValue: 4),
        revision: 1,
        createdAtMonotonicMilliseconds: 1_000,
        expiresAtMonotonicMilliseconds: 11_000,
        candidates: candidates
    )
    let receipt = try LocalInteractiveSurfaceTargetsReceiptV1(
        correlationID: command.commandID,
        snapshot: snapshot
    )
    let encoded = try LocalInteractiveLeaseWireCodecV1
        .encodeSurfaceTargetsReceipt(receipt)
    #expect(receipt.candidates.count == 8)
    #expect(encoded.count <= LocalInteractiveLeaseWireCodecV1.maximumEncodedBytes)
    try LocalInteractiveLeaseWireCodecV1
        .decodeSurfaceTargetsReceipt(encoded)
        .validate(against: command)
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
