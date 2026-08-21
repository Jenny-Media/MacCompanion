import CompanionDomain
import CompanionInteractiveShared
import CompanionMacUI
import CompanionPresentation
import CompanionWire
import Foundation
import Testing

private let macUIDeviceID = UUID(
    uuidString: "018f9600-0000-7000-8000-000000000001"
)!
private let macUIDeviceName = try! DeviceDisplayName("Jenny’s iPhone")

private func macUIEffects() throws -> CapabilityEffectFacts {
    try CapabilityEffectFacts(
        dataAccess: .credentials,
        changesLocalState: .irreversible,
        mayDisruptUser: true,
        invokesExternalService: true,
        usesCredentials: true,
        destructive: true,
        requiresForegroundSession: true,
        allowedWhileLocked: false,
        cancellation: .bestEffort
    )
}

private func macUIGrantPresentation() throws -> LocalGrantExpansionPresentation {
    let descriptor = try CapabilityDescriptorV1(
        capabilityID: "maccompanion.test.powerful",
        schemaVersion: 1,
        providerID: "maccompanion.test",
        providerVersion: "1.0.0",
        providerGeneration: UUID(
            uuidString: "018f9600-0000-7000-8000-000000000002"
        )!,
        executionRevision: UUID(
            uuidString: "018f9600-0000-7000-8000-000000000003"
        )!,
        englishTitle: "Powerful test capability",
        englishSummary: "Exercises every visible effect fact.",
        parameterSchema: .object(properties: []),
        resultSchema: .object(properties: []),
        effects: macUIEffects()
    )
    return try LocalGrantExpansionPresentation(
        reviewID: UUID(
            uuidString: "018f9600-0000-7000-8000-000000000004"
        )!,
        deviceID: macUIDeviceID,
        deviceDisplayName: macUIDeviceName,
        expectedAuthorizationEpoch: .init(rawValue: 1),
        expectedGrantRevision: .init(rawValue: 1),
        expectedPolicyRevision: .init(rawValue: 1),
        currentGrants: CapabilityGrantSet(["maccompanion.status.read"]),
        requestedDescriptors: [descriptor]
    )
}

@Test func grantProjectionNamesDeviceAndPreservesEveryEffectFact() throws {
    let projection = MacGrantReviewProjectionV0(
        presentation: try macUIGrantPresentation()
    )
    #expect(projection.deviceDisplayName == "Jenny’s iPhone")
    #expect(projection.currentGrantCount == 1)
    #expect(projection.proposedGrantCount == 2)
    #expect(projection.status == .reviewing)
    #expect(projection.canApprove)
    #expect(projection.canDecline)

    let capability = try #require(projection.capabilities.first)
    #expect(capability.capabilityID == "maccompanion.test.powerful")
    #expect(capability.effects.count == 9)
    #expect(capability.effects.map(\.title) == [
        "Data access",
        "Changes this Mac",
        "May disrupt your work",
        "Uses an external service",
        "Uses credentials",
        "Can be destructive",
        "Requires an unlocked session",
        "Allowed while this Mac is locked",
        "Cancellation",
    ])
    #expect(capability.effects[0].detail == "Credential data")
    #expect(capability.effects[1].detail == "May make irreversible changes")
    #expect(capability.effects[7].detail == "No")
    #expect(capability.effects[8].detail == "Best effort after starting")
}

@Test func grantProjectionDisablesDecisionsWhileApplyingAndAfterSuccess() throws {
    var presentation = try macUIGrantPresentation()
    let decisionID = UUID()
    _ = try presentation.approve(decisionID: decisionID)

    var projection = MacGrantReviewProjectionV0(presentation: presentation)
    #expect(projection.status == .applying)
    #expect(!projection.canApprove)
    #expect(!projection.canDecline)

    try presentation.applicationSucceeded(
        decisionID: decisionID,
        storedGrants: presentation.proposedGrants,
        authorizationEpoch: .init(rawValue: 2),
        grantRevision: .init(rawValue: 2)
    )
    projection = MacGrantReviewProjectionV0(presentation: presentation)
    #expect(projection.status == .applied)
    #expect(!projection.canApprove)
    #expect(!projection.canDecline)
}

@Test func failedGrantProjectionAllowsAnExplicitRetryOrDecline() throws {
    var presentation = try macUIGrantPresentation()
    let decisionID = UUID()
    _ = try presentation.approve(decisionID: decisionID)
    try presentation.applicationFailed(decisionID: decisionID)

    let projection = MacGrantReviewProjectionV0(presentation: presentation)
    #expect(projection.status == .failed)
    #expect(projection.canApprove)
    #expect(projection.canDecline)
}

@Test func interactiveProjectionKeepsApprovalDistinctFromActiveControl() throws {
    var presentation = try LocalInteractiveWarningPresentation(
        deviceID: macUIDeviceID,
        deviceDisplayName: macUIDeviceName,
        requestID: UUID(),
        approvalID: UUID(),
        selectedDisplayID: UUID(),
        effects: [.keyboard, .pointer, .text, .view],
        issuedAtUnixMilliseconds: 1_000,
        expiresAtUnixMilliseconds: 61_000
    )

    var projection = MacInteractiveWarningProjectionV0(
        presentation: presentation
    )
    #expect(projection.status == .awaitingPhoneApproval)
    #expect(!projection.hasActiveSession)
    #expect(projection.canStop)
    #expect(projection.effectLabels == [
        "Press keyboard keys",
        "Move the pointer and click",
        "Insert eligible text",
        "View this Mac’s screen",
    ])

    try presentation.sessionAccepted(UUID())
    try presentation.captureBecameActive()
    projection = MacInteractiveWarningProjectionV0(presentation: presentation)
    #expect(projection.status == .active)
    #expect(projection.hasActiveSession)
    #expect(projection.canStop)
}

@Test func endingInteractiveProjectionCannotEmitAnotherStop() throws {
    var presentation = try LocalInteractiveWarningPresentation(
        deviceID: macUIDeviceID,
        deviceDisplayName: macUIDeviceName,
        requestID: UUID(),
        approvalID: UUID(),
        selectedDisplayID: UUID(),
        effects: [.view],
        issuedAtUnixMilliseconds: 1_000,
        expiresAtUnixMilliseconds: 2_000
    )
    _ = try presentation.requestStop(actionID: UUID())
    let projection = MacInteractiveWarningProjectionV0(
        presentation: presentation
    )
    #expect(projection.status == .ending)
    #expect(!projection.canStop)
}

@Test func deviceNameProjectionExposesOnlyValidatedSaveEligibility() throws {
    var presentation = DeviceNameAdministrationPresentation(
        deviceID: macUIDeviceID,
        locallyConfirmedName: macUIDeviceName
    )
    var projection = MacDeviceNameProjectionV0(presentation: presentation)
    #expect(!projection.isEditing)
    #expect(!projection.canSave)
    #expect(projection.confirmedName == "Jenny’s iPhone")

    try presentation.beginEditing()
    try presentation.updateDraft(" Jenny’s iPhone")
    projection = MacDeviceNameProjectionV0(presentation: presentation)
    #expect(projection.isEditing)
    #expect(projection.issue == .surroundingWhitespace)
    #expect(!projection.canSave)

    try presentation.updateDraft("Jenny’s iPad")
    projection = MacDeviceNameProjectionV0(presentation: presentation)
    #expect(projection.issue == nil)
    #expect(projection.canSave)
}
