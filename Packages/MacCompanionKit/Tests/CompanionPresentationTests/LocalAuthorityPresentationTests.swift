import CompanionDomain
import CompanionIPC
import CompanionInteractiveWire
import CompanionPresentation
import CompanionWire
import Foundation
import Testing

private let localAuthorityDeviceID = UUID(
    uuidString: "018f9500-0000-7000-8000-000000000001"
)!
private let localAuthorityRequestID = UUID(
    uuidString: "018f9500-0000-7000-8000-000000000002"
)!
private let localAuthorityApprovalID = UUID(
    uuidString: "018f9500-0000-7000-8000-000000000003"
)!
private let localAuthorityDisplayID = UUID(
    uuidString: "018f9500-0000-7000-8000-000000000004"
)!
private let localAuthorityDeviceName = try! DeviceDisplayName("Yihong’s iPhone")

private func localAuthorityDescriptor(
    id: String,
    title: String,
    effects: CapabilityEffectFacts
) throws -> CapabilityDescriptorV1 {
    try CapabilityDescriptorV1(
        capabilityID: id,
        schemaVersion: 1,
        providerID: "maccompanion.native",
        providerVersion: "1.0.0",
        providerGeneration: UUID(
            uuidString: "018f9500-0000-7000-8000-000000000010"
        )!,
        executionRevision: UUID(
            uuidString: "018f9500-0000-7000-8000-000000000011"
        )!,
        englishTitle: title,
        englishSummary: "A bounded locally reviewed capability.",
        parameterSchema: .object(properties: []),
        resultSchema: .object(properties: []),
        effects: effects
    )
}

private func localAuthorityEffects(
    data: CapabilityDataAccessEffect = .none,
    state: CapabilityLocalStateEffect = .none,
    disruptive: Bool = false,
    external: Bool = false,
    credentials: Bool = false,
    destructive: Bool = false,
    foreground: Bool = false,
    locked: Bool = false,
    cancellation: CapabilityCancellationEffect = .notApplicable
) throws -> CapabilityEffectFacts {
    try CapabilityEffectFacts(
        dataAccess: data,
        changesLocalState: state,
        mayDisruptUser: disruptive,
        invokesExternalService: external,
        usesCredentials: credentials,
        destructive: destructive,
        requiresForegroundSession: foreground,
        allowedWhileLocked: locked,
        cancellation: cancellation
    )
}

private func localGrantPresentation() throws -> LocalGrantExpansionPresentation {
    try LocalGrantExpansionPresentation(
        reviewID: UUID(
            uuidString: "018f9500-0000-7000-8000-000000000020"
        )!,
        deviceID: localAuthorityDeviceID,
        deviceDisplayName: localAuthorityDeviceName,
        expectedAuthorizationEpoch: .init(rawValue: 5),
        expectedGrantRevision: .init(rawValue: 8),
        expectedPolicyRevision: .init(rawValue: 3),
        currentGrants: CapabilityGrantSet(["maccompanion.status.read"]),
        requestedDescriptors: [
            localAuthorityDescriptor(
                id: "maccompanion.system.setAudioMuted",
                title: "Set audio mute",
                effects: localAuthorityEffects(
                    state: .reversible,
                    disruptive: true,
                    foreground: true,
                    cancellation: .bestEffort
                )
            ),
            localAuthorityDescriptor(
                id: "maccompanion.private.inspect",
                title: "Inspect private data",
                effects: localAuthorityEffects(
                    data: .privateData,
                    external: true,
                    credentials: true
                )
            ),
        ]
    )
}

@Test func grantReviewKeepsLocalDeviceIdentityAndEveryExactEffectFact() throws {
    let value = try localGrantPresentation()
    #expect(value.deviceID == localAuthorityDeviceID)
    #expect(value.deviceDisplayName == localAuthorityDeviceName)
    #expect(value.requestedCapabilities.map(\.capabilityID) == [
        "maccompanion.private.inspect",
        "maccompanion.system.setAudioMuted",
    ])
    #expect(value.proposedGrants.capabilityIDs == [
        "maccompanion.private.inspect",
        "maccompanion.status.read",
        "maccompanion.system.setAudioMuted",
    ])
    let privateAccess = try #require(value.requestedCapabilities.first)
    #expect(privateAccess.effects.dataAccess == .privateData)
    #expect(privateAccess.effects.invokesExternalService)
    #expect(privateAccess.effects.usesCredentials)
    #expect(!privateAccess.effects.destructive)

    let audio = try #require(value.requestedCapabilities.last)
    #expect(audio.effects.changesLocalState == .reversible)
    #expect(audio.effects.mayDisruptUser)
    #expect(audio.effects.requiresForegroundSession)
    #expect(audio.effects.cancellation == .bestEffort)
}

@Test func grantReviewRejectsEmptyDuplicateOrAlreadyGrantedRequests() throws {
    let effects = try localAuthorityEffects()
    let descriptor = try localAuthorityDescriptor(
        id: "maccompanion.status.read",
        title: "Read status",
        effects: effects
    )
    #expect(throws: LocalAuthorityPresentationError.invalidRequest) {
        try LocalGrantExpansionPresentation(
            reviewID: UUID(),
            deviceID: localAuthorityDeviceID,
            deviceDisplayName: localAuthorityDeviceName,
            expectedAuthorizationEpoch: .init(rawValue: 1),
            expectedGrantRevision: .init(rawValue: 1),
            expectedPolicyRevision: .init(rawValue: 1),
            currentGrants: CapabilityGrantSet(["maccompanion.status.read"]),
            requestedDescriptors: [descriptor]
        )
    }
    #expect(throws: LocalAuthorityPresentationError.invalidRequest) {
        try LocalGrantExpansionPresentation(
            reviewID: UUID(),
            deviceID: localAuthorityDeviceID,
            deviceDisplayName: localAuthorityDeviceName,
            expectedAuthorizationEpoch: .init(rawValue: 1),
            expectedGrantRevision: .init(rawValue: 1),
            expectedPolicyRevision: .init(rawValue: 1),
            currentGrants: CapabilityGrantSet([]),
            requestedDescriptors: []
        )
    }
}

@Test func grantExpansionRequiresExplicitDecisionAndExactReceipt() throws {
    var value = try localGrantPresentation()
    let decisionID = UUID()
    let intent = try value.approve(decisionID: decisionID)
    #expect(value.phase == .applying(decisionID: decisionID))
    #expect(intent.deviceID == localAuthorityDeviceID)
    #expect(intent.expectedAuthorizationEpoch.rawValue == 5)
    #expect(intent.proposedGrants == value.proposedGrants)
    let command = try intent.makeIPCCommand(decidedAtUnixMilliseconds: 1_000)
    #expect(command.commandID == decisionID)
    #expect(command.reviewID == value.reviewID)
    #expect(command.deviceDisplayName == localAuthorityDeviceName)
    #expect(command.decision == .approve)
    #expect(command.expectedCurrentGrantIDs == value.currentGrants.capabilityIDs)

    #expect(throws: LocalAuthorityPresentationError.staleDecision) {
        try value.applicationSucceeded(
            decisionID: UUID(),
            storedGrants: value.proposedGrants,
            authorizationEpoch: .init(rawValue: 6),
            grantRevision: .init(rawValue: 9)
        )
    }
    #expect(throws: LocalAuthorityPresentationError.receiptMismatch) {
        try value.applicationSucceeded(
            decisionID: decisionID,
            storedGrants: value.proposedGrants,
            authorizationEpoch: .init(rawValue: 6),
            grantRevision: .init(rawValue: 10)
        )
    }
    let receipt = try LocalGrantDecisionReceiptV0(
        correlationID: decisionID,
        reviewID: value.reviewID,
        deviceID: localAuthorityDeviceID,
        decision: .approve,
        storedGrants: value.proposedGrants,
        authorizationEpoch: .init(rawValue: 6),
        grantRevision: .init(rawValue: 9),
        policyRevision: .init(rawValue: 3),
        completedAtUnixMilliseconds: 1_001
    )
    try value.applicationSucceeded(receipt: receipt, command: command)
    #expect(value.phase == .applied)
}

@Test func decliningGrantReviewCannotLaterEmitApproval() throws {
    var value = try localGrantPresentation()
    let intent = try value.decline(decisionID: UUID())
    #expect(value.phase == .declined)
    #expect(intent.decision == .decline)
    #expect(try intent.makeIPCCommand(
        decidedAtUnixMilliseconds: 1_000
    ).decision == .decline)
    #expect(throws: LocalAuthorityPresentationError.invalidPhase) {
        _ = try value.approve(decisionID: UUID())
    }
}

@Test func interactiveWarningNamesDeviceAndMapsEveryRequestedEffectExactly() throws {
    var value = try LocalInteractiveWarningPresentation(
        deviceID: localAuthorityDeviceID,
        deviceDisplayName: localAuthorityDeviceName,
        requestID: localAuthorityRequestID,
        approvalID: localAuthorityApprovalID,
        selectedDisplayID: localAuthorityDisplayID,
        effects: [.keyboard, .pointer, .text, .view],
        issuedAtUnixMilliseconds: 1_000,
        expiresAtUnixMilliseconds: 61_000
    )
    #expect(value.deviceDisplayName == localAuthorityDeviceName)
    #expect(value.effects == [
        .pressKeyboardKeys, .movePointer, .insertText, .viewMacScreen,
    ])
    #expect(value.phase == .awaitingPhoneApproval)

    let sessionID = UUID()
    try value.sessionAccepted(sessionID)
    try value.captureBecameActive()
    try value.setPaused(true)
    try value.setPaused(false)
    #expect(value.phase == .active)

    let actionID = UUID()
    let stop = try value.requestStop(actionID: actionID)
    #expect(stop.deviceID == localAuthorityDeviceID)
    #expect(stop.requestID == localAuthorityRequestID)
    #expect(stop.approvalID == localAuthorityApprovalID)
    #expect(stop.interactiveSessionID == sessionID)
    let command = try stop.makeIPCCommand(occurredAtUnixMilliseconds: 2_000)
    #expect(command.deviceDisplayName == localAuthorityDeviceName)
    #expect(command.interactiveSessionID == sessionID)
    #expect(throws: LocalAuthorityPresentationError.staleDecision) {
        try value.stopCompleted(actionID: UUID())
    }
    let receipt = try LocalInteractiveStoppedReceiptV0(
        correlationID: actionID,
        deviceID: localAuthorityDeviceID,
        requestID: localAuthorityRequestID,
        approvalID: localAuthorityApprovalID,
        interactiveSessionID: sessionID,
        reason: .userRequested,
        remoteAuthorityEnded: true,
        runtimeTeardownComplete: true,
        completedAtUnixMilliseconds: 2_001
    )
    try value.stopCompleted(receipt: receipt, command: command)
    #expect(value.phase == .ended)
}

@Test func interactiveWarningRejectsEffectBroadeningAndLongApproval() throws {
    #expect(throws: LocalAuthorityPresentationError.invalidRequest) {
        try LocalInteractiveWarningPresentation(
            deviceID: localAuthorityDeviceID,
            deviceDisplayName: localAuthorityDeviceName,
            requestID: localAuthorityRequestID,
            approvalID: localAuthorityApprovalID,
            selectedDisplayID: localAuthorityDisplayID,
            effects: [.pointer],
            issuedAtUnixMilliseconds: 1_000,
            expiresAtUnixMilliseconds: 2_000
        )
    }
    #expect(throws: LocalAuthorityPresentationError.invalidRequest) {
        try LocalInteractiveWarningPresentation(
            deviceID: localAuthorityDeviceID,
            deviceDisplayName: localAuthorityDeviceName,
            requestID: localAuthorityRequestID,
            approvalID: localAuthorityApprovalID,
            selectedDisplayID: localAuthorityDisplayID,
            effects: [.view],
            issuedAtUnixMilliseconds: 1_000,
            expiresAtUnixMilliseconds: 61_001
        )
    }
}
