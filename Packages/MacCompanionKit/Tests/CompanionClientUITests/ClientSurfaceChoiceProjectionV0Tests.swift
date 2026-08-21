import CompanionClientUI
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionWire
import Foundation
import Testing

private let surfaceUIAppToken = UUID()
private let surfaceUIWindowToken = UUID()

private func surfaceUICandidate(
    kind: InteractiveSurfaceKind,
    targetToken: UUID,
    ordinal: Int64?,
    available: Bool = true
) throws -> InteractiveSurfaceTargetCandidateV0 {
    try .init(
        targetToken: .init(targetToken),
        kind: kind,
        applicationToken: .init(surfaceUIAppToken),
        applicationName: "Notes",
        windowOrdinal: ordinal,
        currentWindowAvailable: available
    )
}

@Test func surfaceChoicesAlwaysBeginWithDesktop() {
    let choices = ClientSurfaceChoiceProjectionV0.make(candidates: [])
    #expect(choices == [.desktop])
}

@Test func applicationChoiceCarriesOnlyOpaqueTokenAndSafeName() throws {
    let choices = ClientSurfaceChoiceProjectionV0.make(candidates: [
        try surfaceUICandidate(
            kind: .application,
            targetToken: surfaceUIAppToken,
            ordinal: nil
        ),
    ])
    #expect(choices.count == 2)
    #expect(choices[1].id == .opaqueTarget(surfaceUIAppToken))
    #expect(choices[1].applicationName == "Notes")
    #expect(choices[1].windowOrdinal == nil)
}

@Test func windowChoiceUsesOrdinalInsteadOfAWindowTitle() throws {
    let choices = ClientSurfaceChoiceProjectionV0.make(candidates: [
        try surfaceUICandidate(
            kind: .window,
            targetToken: surfaceUIWindowToken,
            ordinal: 3
        ),
    ])
    #expect(choices[1].kind == .window)
    #expect(choices[1].applicationName == "Notes")
    #expect(choices[1].windowOrdinal == 3)
    #expect(choices[1].targetToken == surfaceUIWindowToken)
}

@Test func unavailableTargetRemainsVisibleButDisabledByProjection() throws {
    let choices = ClientSurfaceChoiceProjectionV0.make(candidates: [
        try surfaceUICandidate(
            kind: .window,
            targetToken: surfaceUIWindowToken,
            ordinal: 1,
            available: false
        ),
    ])
    #expect(choices[1].available == false)
}
