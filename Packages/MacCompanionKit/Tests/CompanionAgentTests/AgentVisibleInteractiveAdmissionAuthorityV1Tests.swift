import CompanionAgent
import CompanionIPC
import Foundation
import Testing

private let visibleMenuGeneration = UUID()
private let visibleDisplayID = UUID()

private func visiblePublication(
    commandID: UUID = UUID(),
    menuGeneration: UUID = visibleMenuGeneration,
    revision: UInt64,
    displayID: UUID? = nil
) throws -> LocalInteractiveAdmissionPublicationV1 {
    try LocalInteractiveAdmissionPublicationV1(
        commandID: commandID,
        menuAppGeneration: menuGeneration,
        revision: revision,
        selectedDisplayID: displayID
    )
}

@Test func visibleAdmissionPublishesReplaysAndAdvancesExactly() async throws {
    let authority = AgentVisibleInteractiveAdmissionAuthorityV1()
    let first = try visiblePublication(revision: 1)
    let firstReceipt = try await authority.publish(
        first,
        transportGeneration: 4
    )
    #expect(
        try await authority.publish(first, transportGeneration: 4)
            == firstReceipt
    )
    #expect(try await authority.snapshot().selectedDisplayID == nil)

    let second = try visiblePublication(
        revision: 2,
        displayID: visibleDisplayID
    )
    let secondReceipt = try await authority.publish(
        second,
        transportGeneration: 4
    )
    try secondReceipt.validate(against: second)
    let snapshot = try await authority.snapshot()
    #expect(snapshot.generation == visibleMenuGeneration)
    #expect(snapshot.revision == 2)
    #expect(snapshot.visibleMenuAppAvailable)
    #expect(snapshot.selectedDisplayID == visibleDisplayID)
}

@Test func visibleAdmissionRejectsSkippedAndChangedMenuGeneration()
    async throws
{
    let authority = AgentVisibleInteractiveAdmissionAuthorityV1()
    _ = try await authority.publish(
        visiblePublication(revision: 1),
        transportGeneration: 1
    )
    await #expect(
        throws:
            AgentVisibleInteractiveAdmissionAuthorityErrorV1
                .staleOrSkippedRevision
    ) {
        try await authority.publish(
            visiblePublication(revision: 3),
            transportGeneration: 1
        )
    }
    await #expect(
        throws:
            AgentVisibleInteractiveAdmissionAuthorityErrorV1
                .menuGenerationChanged
    ) {
        try await authority.publish(
            visiblePublication(
                menuGeneration: UUID(),
                revision: 2
            ),
            transportGeneration: 1
        )
    }
}

@Test func visibleAdmissionInvalidationIsGenerationFenced() async throws {
    let authority = AgentVisibleInteractiveAdmissionAuthorityV1()
    _ = try await authority.publish(
        visiblePublication(revision: 1),
        transportGeneration: 2
    )
    #expect(await authority.invalidate(transportGeneration: 1) == false)
    #expect(try await authority.snapshot().visibleMenuAppAvailable)
    #expect(await authority.invalidate(transportGeneration: 2))
    await #expect(
        throws: AgentVisibleInteractiveAdmissionAuthorityErrorV1
            .unavailable
    ) {
        try await authority.snapshot()
    }

    let replacement = try visiblePublication(
        menuGeneration: UUID(),
        revision: 1,
        displayID: visibleDisplayID
    )
    _ = try await authority.publish(
        replacement,
        transportGeneration: 3
    )
    #expect(try await authority.snapshot().generation
        == replacement.menuAppGeneration)
}
