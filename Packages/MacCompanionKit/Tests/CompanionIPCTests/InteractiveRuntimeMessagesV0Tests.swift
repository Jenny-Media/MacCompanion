import CompanionDomain
import CompanionIPC
import CompanionInteractiveShared
import Foundation
import Testing

private let runtimeHostID = UUID(uuidString: "018f1000-0000-7000-8000-000000000001")!
private let runtimeDeviceID = UUID(uuidString: "018f2100-0000-7000-8000-000000000001")!
private let runtimeSessionID = UUID(uuidString: "018f6000-0000-7000-8000-000000000001")!
private let runtimeDisplayID = UUID(uuidString: "018f6700-0000-7000-8000-000000000001")!
private let runtimeSurfaceID = UUID(uuidString: "018f6100-0000-7000-8000-000000000001")!

private func runtimeLease(
    leaseID: UUID = UUID(),
    allowedClasses: Set<SurfaceInteractionClass> = [
        .view, .pointer, .keyboard,
    ],
    surfaceID: UUID = runtimeSurfaceID,
    surfaceRevision: UInt64 = 1,
    coordinateRevision: UInt64 = 1,
    renewalCounter: UInt64 = 0,
    issuedAt: UInt64 = 1_000,
    expiresAt: UInt64 = 2_000
) throws -> InteractiveExecutionLease {
    try InteractiveExecutionLease(
        leaseID: leaseID,
        hostID: runtimeHostID,
        deviceID: runtimeDeviceID,
        interactiveSessionID: runtimeSessionID,
        authorizationEpoch: .init(rawValue: 4),
        selectedDisplayID: runtimeDisplayID,
        surfaceID: surfaceID,
        surfaceRevision: .init(rawValue: surfaceRevision),
        coordinateRevision: .init(rawValue: coordinateRevision),
        allowedInteractionClasses: allowedClasses,
        renewalCounter: renewalCounter,
        issuedAtMonotonicNanoseconds: issuedAt,
        expiresAtMonotonicNanoseconds: expiresAt
    )
}

private func runtimeDescriptor(
    lease: InteractiveExecutionLease
) throws -> AdaptiveSurfaceDescriptor {
    try AdaptiveSurfaceDescriptor(
        interactiveSessionID: lease.interactiveSessionID,
        authorizationEpoch: lease.authorizationEpoch,
        surfaceID: lease.surfaceID,
        kind: .desktop,
        surfaceRevision: .init(rawValue: lease.surfaceRevision.rawValue),
        coordinateSpaceRevision: .init(
            rawValue: lease.coordinateRevision.rawValue
        ),
        encodedWidth: 100,
        encodedHeight: 100,
        logicalWidthPoints: 100,
        logicalHeightPoints: 100,
        interactionClasses: Set(lease.allowedInteractionClasses),
        privacyProfile: .visualOnly,
        metadataFields: [],
        createdAtMonotonicMilliseconds: 0,
        expiresAtMonotonicMilliseconds: 10_000
    )
}

private func installCommand() throws -> InteractiveRuntimeInstallCommandV0 {
    try InteractiveRuntimeInstallCommandV0(
        commandID: UUID(),
        lease: runtimeLease(),
        deviceDisplayName: DeviceDisplayName("Jenny’s iPhone"),
        sessionDeadlineMonotonicNanoseconds: 100_000
    )
}

@Test func installReceiptRequiresExactLeaseIndicatorAndReadiness() throws {
    let command = try installCommand()
    let receipt = try InteractiveRuntimeInstallReceiptV0(
        correlationID: command.commandID,
        leaseID: command.lease.leaseID,
        interactiveSessionID: command.lease.interactiveSessionID,
        selectedDisplayID: command.lease.selectedDisplayID,
        menuAppGeneration: UUID(),
        menuAppRevision: 1,
        readyInteractionClasses: [.view, .pointer, .keyboard],
        indicatorVisible: true
    )
    try receipt.validate(against: command)

    #expect(throws: InteractiveRuntimeMessageErrorV0.readinessIncomplete) {
        try InteractiveRuntimeInstallReceiptV0(
            correlationID: command.commandID,
            leaseID: command.lease.leaseID,
            interactiveSessionID: command.lease.interactiveSessionID,
            selectedDisplayID: command.lease.selectedDisplayID,
            menuAppGeneration: UUID(),
            menuAppRevision: 1,
            readyInteractionClasses: [.view],
            indicatorVisible: true
        ).validate(against: command)
    }
    #expect(throws: InteractiveRuntimeMessageErrorV0.readinessIncomplete) {
        try InteractiveRuntimeInstallReceiptV0(
            correlationID: command.commandID,
            leaseID: command.lease.leaseID,
            interactiveSessionID: command.lease.interactiveSessionID,
            selectedDisplayID: command.lease.selectedDisplayID,
            menuAppGeneration: UUID(),
            menuAppRevision: 1,
            readyInteractionClasses: [.view, .pointer, .keyboard],
            indicatorVisible: false
        )
    }
}

@Test func leaseRenewalAdvancesOnlyCounterAndBoundedLifetime() throws {
    let current = try runtimeLease(leaseID: UUID())
    let replacement = try runtimeLease(
        leaseID: UUID(),
        renewalCounter: 1,
        issuedAt: 1_500,
        expiresAt: 2_500
    )
    let renewal = try InteractiveRuntimeLeaseRenewalV0(
        commandID: UUID(),
        previousLeaseID: current.leaseID,
        replacement: replacement
    )
    try renewal.validate(current: current)

    let skipped = try runtimeLease(
        leaseID: UUID(),
        renewalCounter: 2,
        issuedAt: 1_500,
        expiresAt: 2_500
    )
    #expect(throws: InteractiveRuntimeMessageErrorV0.invalidRenewal) {
        try InteractiveRuntimeLeaseRenewalV0(
            commandID: UUID(),
            previousLeaseID: current.leaseID,
            replacement: skipped
        ).validate(current: current)
    }
}

@Test func surfaceTransitionCommandAndReceiptBindExactSuccessor() throws {
    let current = try runtimeLease(leaseID: UUID())
    let replacement = try runtimeLease(
        leaseID: UUID(),
        surfaceID: UUID(),
        surfaceRevision: 2,
        coordinateRevision: 2,
        renewalCounter: 1,
        issuedAt: 1_500,
        expiresAt: 2_500
    )
    let command = try InteractiveRuntimeSurfaceTransitionCommandV0(
        commandID: UUID(),
        previousLeaseID: current.leaseID,
        replacement: replacement,
        descriptor: runtimeDescriptor(lease: replacement)
    )
    try command.validate(
        current: current,
        sessionAllowedInteractionClasses:
            Set(current.allowedInteractionClasses)
    )
    let receipt = try InteractiveRuntimeSurfaceTransitionReceiptV0(
        correlationID: command.commandID,
        previousLeaseID: command.previousLeaseID,
        replacementLeaseID: replacement.leaseID,
        interactiveSessionID: replacement.interactiveSessionID,
        surfaceID: replacement.surfaceID,
        surfaceRevision: replacement.surfaceRevision,
        coordinateRevision: replacement.coordinateRevision,
        mediaSequenceBeforeTransition: 7,
        inputReleased: true,
        captureSourcePrepared: true
    )
    try receipt.validate(against: command)

    #expect(
        try JSONDecoder().decode(
            InteractiveRuntimeSurfaceTransitionCommandV0.self,
            from: JSONEncoder().encode(command)
        ) == command
    )
    #expect(
        try JSONDecoder().decode(
            InteractiveRuntimeSurfaceTransitionReceiptV0.self,
            from: JSONEncoder().encode(receipt)
        ) == receipt
    )
}

@Test func surfaceTransitionRejectsSkippedRevisionAndAuthorityExpansion()
    throws
{
    let current = try runtimeLease(
        leaseID: UUID(),
        allowedClasses: [.view, .pointer]
    )
    let skipped = try runtimeLease(
        leaseID: UUID(),
        allowedClasses: [.view, .pointer],
        surfaceID: UUID(),
        surfaceRevision: 3,
        coordinateRevision: 2,
        renewalCounter: 1,
        issuedAt: 1_500,
        expiresAt: 2_500
    )
    #expect(
        throws:
            InteractiveRuntimeMessageErrorV0
                .invalidSurfaceTransition
    ) {
        try InteractiveRuntimeSurfaceTransitionCommandV0(
            commandID: UUID(),
            previousLeaseID: current.leaseID,
            replacement: skipped,
            descriptor: runtimeDescriptor(lease: skipped)
        ).validate(
            current: current,
            sessionAllowedInteractionClasses: [.view, .pointer]
        )
    }

    let expanded = try runtimeLease(
        leaseID: UUID(),
        allowedClasses: [.view, .pointer, .keyboard],
        surfaceID: UUID(),
        surfaceRevision: 2,
        coordinateRevision: 2,
        renewalCounter: 1,
        issuedAt: 1_500,
        expiresAt: 2_500
    )
    #expect(
        throws:
            InteractiveRuntimeMessageErrorV0
                .invalidSurfaceTransition
    ) {
        try InteractiveRuntimeSurfaceTransitionCommandV0(
            commandID: UUID(),
            previousLeaseID: current.leaseID,
            replacement: expanded,
            descriptor: runtimeDescriptor(lease: expanded)
        ).validate(
            current: current,
            sessionAllowedInteractionClasses: [.view, .pointer]
        )
    }
}

@Test func surfaceAcknowledgementAndReceiptBindExactReadySequence()
    throws
{
    let lease = try runtimeLease(
        leaseID: UUID(),
        surfaceID: UUID(),
        surfaceRevision: 2,
        coordinateRevision: 2,
        renewalCounter: 1
    )
    let transitionID = UUID()
    let command = try
        InteractiveRuntimeSurfaceAcknowledgementCommandV0(
            commandID: UUID(),
            transitionCommandID: transitionID,
            leaseID: lease.leaseID,
            interactiveSessionID: lease.interactiveSessionID,
            surfaceID: lease.surfaceID,
            surfaceRevision: lease.surfaceRevision,
            coordinateRevision: lease.coordinateRevision,
            readyMediaSequence: 9
        )
    try command.validate(
        current: lease,
        expectedTransitionCommandID: transitionID,
        expectedReadyMediaSequence: 9,
        expectedFocusToken: nil,
        expectedFocusRevision: nil
    )
    let receipt = try
        InteractiveRuntimeSurfaceAcknowledgementReceiptV0(
            correlationID: command.commandID,
            transitionCommandID: transitionID,
            leaseID: lease.leaseID,
            interactiveSessionID: lease.interactiveSessionID,
            surfaceID: lease.surfaceID,
            surfaceRevision: lease.surfaceRevision,
            coordinateRevision: lease.coordinateRevision,
            readyMediaSequence: 9,
            inputResumed: true
        )
    try receipt.validate(against: command)

    #expect(
        throws:
            InteractiveRuntimeMessageErrorV0
                .invalidSurfaceAcknowledgement
    ) {
        try command.validate(
            current: lease,
            expectedTransitionCommandID: transitionID,
            expectedReadyMediaSequence: 10,
            expectedFocusToken: nil,
            expectedFocusRevision: nil
        )
    }

    let focusToken = UUID()
    let focusRevision = CompanionInteractiveShared.FocusRevision(
        rawValue: 7
    )
    let focused = try InteractiveRuntimeSurfaceAcknowledgementCommandV0(
        commandID: UUID(),
        transitionCommandID: transitionID,
        leaseID: lease.leaseID,
        interactiveSessionID: lease.interactiveSessionID,
        surfaceID: lease.surfaceID,
        surfaceRevision: lease.surfaceRevision,
        coordinateRevision: lease.coordinateRevision,
        focusToken: focusToken,
        focusRevision: focusRevision,
        readyMediaSequence: 9
    )
    try focused.validate(
        current: lease,
        expectedTransitionCommandID: transitionID,
        expectedReadyMediaSequence: 9,
        expectedFocusToken: focusToken,
        expectedFocusRevision: focusRevision
    )
    #expect(
        throws:
            InteractiveRuntimeMessageErrorV0
                .invalidSurfaceAcknowledgement
    ) {
        try command.validate(
            current: lease,
            expectedTransitionCommandID: transitionID,
            expectedReadyMediaSequence: 9,
            expectedFocusToken: focusToken,
            expectedFocusRevision: focusRevision
        )
    }
}

@Test func revokeReceiptRequiresExactBindingAndEverySafetyEffect() throws {
    let command = try InteractiveRuntimeRevokeCommandV0(
        commandID: UUID(),
        leaseID: UUID(),
        interactiveSessionID: runtimeSessionID,
        reason: .clientDisconnected
    )
    let receipt = try InteractiveRuntimeRevokedReceiptV0(
        correlationID: command.commandID,
        leaseID: command.leaseID,
        interactiveSessionID: command.interactiveSessionID,
        inputReleased: true,
        captureStopped: true,
        lastFrameBlanked: true,
        indicatorCleared: true
    )
    try receipt.validate(against: command)

    #expect(throws: InteractiveRuntimeMessageErrorV0.teardownIncomplete) {
        try InteractiveRuntimeRevokedReceiptV0(
            correlationID: command.commandID,
            leaseID: command.leaseID,
            interactiveSessionID: command.interactiveSessionID,
            inputReleased: true,
            captureStopped: true,
            lastFrameBlanked: false,
            indicatorCleared: true
        )
    }
}

@Test func runtimeMessagesRoundTripWithoutDroppingAuthorityFields() throws {
    let command = try installCommand()
    let data = try JSONEncoder().encode(command)
    let decoded = try JSONDecoder().decode(
        InteractiveRuntimeInstallCommandV0.self,
        from: data
    )
    #expect(decoded == command)
    try decoded.validate()
}
