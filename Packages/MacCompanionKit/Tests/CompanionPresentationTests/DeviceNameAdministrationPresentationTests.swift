import CompanionDomain
import CompanionPresentation
import Foundation
import Testing

@Test func localNameEditorStartsOnlyFromLocalPersistence() throws {
    let deviceID = UUID()
    let localName = try DeviceDisplayName("Jenny’s iPhone")
    let named = DeviceNameAdministrationPresentation(
        deviceID: deviceID,
        locallyConfirmedName: localName
    )
    #expect(named.confirmedName == localName)
    #expect(named.draft == localName.rawValue)

    let unnamed = DeviceNameAdministrationPresentation(
        deviceID: deviceID,
        locallyConfirmedName: nil
    )
    #expect(unnamed.confirmedName == nil)
    #expect(unnamed.draft.isEmpty)
}

@Test func localNameSaveIsCorrelatedAndDoesNotPublishBeforeReceipt() throws {
    var model = DeviceNameAdministrationPresentation(
        deviceID: UUID(),
        locallyConfirmedName: nil
    )
    try model.beginEditing()
    try model.updateDraft("Local iPhone")
    let requestID = UUID()
    let intent = try model.submit(requestID: requestID)
    let expected = try DeviceDisplayName("Local iPhone")
    #expect(intent.displayName == expected)
    #expect(model.confirmedName == nil)
    #expect(model.phase == .saving(requestID: requestID))

    try model.saveSucceeded(
        requestID: requestID,
        storedName: intent.displayName
    )
    #expect(model.confirmedName == intent.displayName)
    #expect(model.phase == .viewing)
}

@Test func invalidLocalNameDraftsHaveClosedPresentationIssues() throws {
    var model = DeviceNameAdministrationPresentation(
        deviceID: UUID(),
        locallyConfirmedName: nil
    )
    try model.beginEditing()
    try model.updateDraft(" iPhone")
    #expect(model.draftIssue() == .surroundingWhitespace)
    #expect(throws: DeviceNameEditorError.invalidDraft(
        .surroundingWhitespace
    )) {
        try model.submit(requestID: UUID())
    }
    #expect(model.phase == .editing)
}

@Test func staleOrMismatchedSaveResponsesCannotRenameTheDevice() throws {
    let original = try DeviceDisplayName("Original")
    var model = DeviceNameAdministrationPresentation(
        deviceID: UUID(),
        locallyConfirmedName: original
    )
    try model.beginEditing()
    try model.updateDraft("Replacement")
    let requestID = UUID()
    _ = try model.submit(requestID: requestID)

    #expect(throws: DeviceNameEditorError.staleResponse) {
        try model.saveSucceeded(
            requestID: UUID(),
            storedName: DeviceDisplayName("Replacement")
        )
    }
    #expect(throws: DeviceNameEditorError.responseMismatch) {
        try model.saveSucceeded(
            requestID: requestID,
            storedName: DeviceDisplayName("Different")
        )
    }
    #expect(model.confirmedName == original)
}

@Test func failedRenamePreservesDraftButRejectsTheOldCorrelation() throws {
    let original = try DeviceDisplayName("Original")
    var model = DeviceNameAdministrationPresentation(
        deviceID: UUID(),
        locallyConfirmedName: original
    )
    try model.beginEditing()
    try model.updateDraft("Replacement")
    let failedRequestID = UUID()
    _ = try model.submit(requestID: failedRequestID)
    try model.saveFailed(
        requestID: failedRequestID,
        reason: .serviceUnavailable
    )
    #expect(model.confirmedName == original)
    #expect(model.draft == "Replacement")
    #expect(model.phase == .saveFailed(.serviceUnavailable))

    try model.beginEditing()
    #expect(model.draft == "Replacement")
    let retryID = UUID()
    _ = try model.submit(requestID: retryID)
    #expect(throws: DeviceNameEditorError.staleResponse) {
        try model.saveSucceeded(
            requestID: failedRequestID,
            storedName: DeviceDisplayName("Replacement")
        )
    }
}
