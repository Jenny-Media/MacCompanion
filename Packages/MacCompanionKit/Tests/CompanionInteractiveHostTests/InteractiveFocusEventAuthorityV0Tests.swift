import CompanionDomain
import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionWire
import Foundation
import Testing

private let focusAuthoritySessionID = UUID()
private let focusAuthorityEpoch = AuthorizationEpoch(rawValue: 4)

private final class FocusAuthorityIdentifierSequenceV0:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var values: [UUID]

    init(_ values: [UUID]) { self.values = values }

    func next() -> UUID {
        lock.lock()
        defer { lock.unlock() }
        return values.removeFirst()
    }
}

private func focusAuthorityFocus(
    token: UUID = UUID(),
    revision: UInt64 = 1
) throws -> SurfaceFocus {
    try SurfaceFocus(
        token: token,
        revision: .init(rawValue: revision),
        category: .text,
        bounds: NormalizedSurfaceRect(
            x: 12_000,
            y: 20_000,
            width: 30_000,
            height: 8_000
        ),
        editable: true,
        secure: false
    )
}

private func focusAuthorityDesktop(
    surfaceID: UUID = UUID(),
    surfaceRevision: UInt64 = 1,
    coordinateRevision: UInt64 = 1,
    createdAtMonotonicMilliseconds: Int64 = 100,
    expiresAtMonotonicMilliseconds: Int64 = 10_000
) throws -> AdaptiveSurfaceDescriptor {
    try AdaptiveSurfaceDescriptor(
        interactiveSessionID: focusAuthoritySessionID,
        authorizationEpoch: focusAuthorityEpoch,
        surfaceID: surfaceID,
        kind: .desktop,
        surfaceRevision: .init(rawValue: surfaceRevision),
        coordinateSpaceRevision: .init(rawValue: coordinateRevision),
        encodedWidth: 1_280,
        encodedHeight: 720,
        logicalWidthPoints: 1_280,
        logicalHeightPoints: 720,
        interactionClasses: [.view, .pointer, .keyboard],
        privacyProfile: .visualOnly,
        metadataFields: [],
        createdAtMonotonicMilliseconds: createdAtMonotonicMilliseconds,
        expiresAtMonotonicMilliseconds: expiresAtMonotonicMilliseconds
    )
}

@Test func unchangedFocusRefreshRetainsUnconsumedTargetAndExtendsExpiry()
    throws
{
    let descriptor = try focusAuthorityDesktop()
    let focus = try focusAuthorityFocus()
    let targetToken = UUID()
    let unusedReplacementToken = UUID()
    let identifiers = FocusAuthorityIdentifierSequenceV0([
        targetToken, unusedReplacementToken,
    ])
    var authority = try InteractiveFocusEventAuthorityV0(
        interactiveSessionID: focusAuthoritySessionID,
        authorizationEpoch: focusAuthorityEpoch,
        targetIdentifier: { identifiers.next() }
    )
    let candidate = try InteractiveFocusEventCandidateV0(
        recommendedTargetKind: .focusedRegion,
        focus: focus,
        inputPaused: false,
        reason: .verifiedFocus,
        validForMilliseconds: 1_000
    )
    let first = try authority.prepare(
        candidate: candidate,
        current: descriptor,
        eventMessageID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 1_000,
        hostMonotonicNowMilliseconds: 500
    )
    let refreshed = try authority.prepare(
        candidate: candidate,
        current: descriptor,
        eventMessageID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 1_400,
        hostMonotonicNowMilliseconds: 900
    )

    #expect(first.eventSequence == 1)
    #expect(refreshed.eventSequence == 2)
    #expect(first.targetToken == WireUUID(targetToken))
    #expect(refreshed.targetToken == first.targetToken)
    #expect(try authority.consume(
        focusAuthoritySelection(
            descriptor: descriptor,
            targetToken: WireUUID(targetToken)
        ),
        current: descriptor,
        hostMonotonicNowMilliseconds: 1_899
    ) == focus)
}

@Test func focusPreparationUsesRenewedLeaseRatherThanDescriptorFreshness()
    throws
{
    let descriptor = try focusAuthorityDesktop(
        createdAtMonotonicMilliseconds: 100,
        expiresAtMonotonicMilliseconds: 600
    )
    var authority = try InteractiveFocusEventAuthorityV0(
        interactiveSessionID: focusAuthoritySessionID,
        authorizationEpoch: focusAuthorityEpoch
    )

    let prepared = try authority.prepare(
        candidate: try InteractiveFocusEventCandidateV0(
            recommendedTargetKind: .focusedRegion,
            focus: try focusAuthorityFocus(),
            inputPaused: false,
            reason: .verifiedFocus
        ),
        current: descriptor,
        eventMessageID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 2_000,
        hostMonotonicNowMilliseconds: 1_500
    )

    #expect(prepared.eventSequence == 1)
    #expect(prepared.targetToken != nil)
}

private func focusAuthorityFocused(
    focus: SurfaceFocus
) throws -> AdaptiveSurfaceDescriptor {
    try AdaptiveSurfaceDescriptor(
        interactiveSessionID: focusAuthoritySessionID,
        authorizationEpoch: focusAuthorityEpoch,
        surfaceID: UUID(),
        kind: .focusedRegion,
        surfaceRevision: .init(rawValue: 2),
        coordinateSpaceRevision: .init(rawValue: 2),
        applicationToken: UUID(),
        parentSurfaceID: UUID(),
        fallbackSurfaceID: UUID(),
        encodedWidth: 1_000,
        encodedHeight: 500,
        logicalWidthPoints: 1_000,
        logicalHeightPoints: 500,
        interactionClasses: [.view, .pointer, .keyboard],
        privacyProfile: .assistedVisual,
        metadataFields: [.focusCategory, .focusBounds, .editable, .secure],
        focus: focus,
        createdAtMonotonicMilliseconds: 100,
        expiresAtMonotonicMilliseconds: 10_000
    )
}

private func focusAuthoritySelection(
    descriptor: AdaptiveSurfaceDescriptor,
    targetToken: WireUUID
) throws -> InteractiveSurfaceSelectBodyV0 {
    try InteractiveSurfaceSelectBodyV0(
        interactiveSessionID: WireUUID(descriptor.interactiveSessionID),
        authorizationEpoch: descriptor.authorizationEpoch,
        currentSurfaceID: WireUUID(descriptor.surfaceID),
        expectedSurfaceRevision: descriptor.surfaceRevision,
        expectedCoordinateSpaceRevision:
            descriptor.coordinateSpaceRevision,
        targetKind: .focusedRegion,
        targetToken: targetToken,
        sequence: 1
    )
}

@Test func focusAuthorityIssuesCanonicalOneUseBoundTarget() throws {
    let descriptor = try focusAuthorityDesktop()
    let focus = try focusAuthorityFocus()
    let targetToken = UUID()
    let eventMessageID = WireUUID(UUID())
    var authority = try InteractiveFocusEventAuthorityV0(
        interactiveSessionID: focusAuthoritySessionID,
        authorizationEpoch: focusAuthorityEpoch,
        targetIdentifier: { targetToken }
    )
    let prepared = try authority.prepare(
        candidate: try InteractiveFocusEventCandidateV0(
            recommendedTargetKind: .focusedRegion,
            focus: focus,
            inputPaused: false,
            reason: .verifiedFocus
        ),
        current: descriptor,
        eventMessageID: eventMessageID,
        sentAtUnixMilliseconds: 1_000,
        hostMonotonicNowMilliseconds: 500
    )
    let event = try WireCodec.decode(
        WireEnvelope<InteractiveSurfaceFocusChangedBodyV0>.self,
        from: prepared.eventJSON
    )
    #expect(event.messageID == eventMessageID)
    #expect(event.channel == .events)
    #expect(event.body.eventSequence == 1)
    #expect(event.body.targetToken == WireUUID(targetToken))
    #expect(try event.body.focus?.materialize() == focus)

    let request = try focusAuthoritySelection(
        descriptor: descriptor,
        targetToken: WireUUID(targetToken)
    )
    #expect(try authority.consume(
        request,
        current: descriptor,
        hostMonotonicNowMilliseconds: 1_499
    ) == focus)
    #expect(throws: InteractiveFocusEventAuthorityErrorV0.unavailable) {
        try authority.consume(
            request,
            current: descriptor,
            hostMonotonicNowMilliseconds: 1_499
        )
    }
}

@Test func newerFocusEventSupersedesOlderTargetWithoutTokenReuse() throws {
    let descriptor = try focusAuthorityDesktop()
    let firstToken = UUID()
    let secondToken = UUID()
    let identifiers = FocusAuthorityIdentifierSequenceV0([
        firstToken, secondToken,
    ])
    var authority = try InteractiveFocusEventAuthorityV0(
        interactiveSessionID: focusAuthoritySessionID,
        authorizationEpoch: focusAuthorityEpoch,
        targetIdentifier: { identifiers.next() }
    )
    for revision in 1...2 {
        let prepared = try authority.prepare(
            candidate: try InteractiveFocusEventCandidateV0(
                recommendedTargetKind: .focusedRegion,
                focus: try focusAuthorityFocus(revision: UInt64(revision)),
                inputPaused: false,
                reason: .verifiedFocus
            ),
            current: descriptor,
            eventMessageID: WireUUID(UUID()),
            sentAtUnixMilliseconds: Int64(revision),
            hostMonotonicNowMilliseconds: 500
        )
        #expect(prepared.eventSequence == Int64(revision))
    }
    #expect(throws: InteractiveFocusEventAuthorityErrorV0.tokenMismatch) {
        try authority.consume(
            try focusAuthoritySelection(
                descriptor: descriptor,
                targetToken: WireUUID(firstToken)
            ),
            current: descriptor,
            hostMonotonicNowMilliseconds: 600
        )
    }
    _ = try authority.consume(
        try focusAuthoritySelection(
            descriptor: descriptor,
            targetToken: WireUUID(secondToken)
        ),
        current: descriptor,
        hostMonotonicNowMilliseconds: 600
    )
}

@Test func focusedSurfaceChangeRequiresPausedDifferentFocus() throws {
    let currentFocus = try focusAuthorityFocus()
    let descriptor = try focusAuthorityFocused(focus: currentFocus)
    var authority = try InteractiveFocusEventAuthorityV0(
        interactiveSessionID: focusAuthoritySessionID,
        authorizationEpoch: focusAuthorityEpoch
    )
    #expect(throws: InteractiveFocusEventAuthorityErrorV0.fenceMismatch) {
        try authority.prepare(
            candidate: try InteractiveFocusEventCandidateV0(
                recommendedTargetKind: .focusedRegion,
                focus: currentFocus,
                inputPaused: false,
                reason: .verifiedFocus
            ),
            current: descriptor,
            eventMessageID: WireUUID(UUID()),
            sentAtUnixMilliseconds: 1_000,
            hostMonotonicNowMilliseconds: 500
        )
    }
    let recovery = try authority.prepare(
        candidate: try InteractiveFocusEventCandidateV0(
            recommendedTargetKind: .desktop,
            focus: nil,
            inputPaused: true,
            reason: .targetDisappeared
        ),
        current: descriptor,
        eventMessageID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 1_000,
        hostMonotonicNowMilliseconds: 500
    )
    let event = try WireCodec.decode(
        WireEnvelope<InteractiveSurfaceFocusChangedBodyV0>.self,
        from: recovery.eventJSON
    )
    #expect(event.body.recommendedTargetKind == .desktop)
    #expect(event.body.inputPaused)
    #expect(event.body.targetToken == nil)
}

@Test func focusAuthorityRejectsExpiryAndChangedFence() throws {
    let descriptor = try focusAuthorityDesktop()
    let targetToken = UUID()
    var authority = try InteractiveFocusEventAuthorityV0(
        interactiveSessionID: focusAuthoritySessionID,
        authorizationEpoch: focusAuthorityEpoch,
        targetIdentifier: { targetToken }
    )
    _ = try authority.prepare(
        candidate: try InteractiveFocusEventCandidateV0(
            recommendedTargetKind: .focusedRegion,
            focus: try focusAuthorityFocus(),
            inputPaused: false,
            reason: .verifiedFocus,
            validForMilliseconds: 100
        ),
        current: descriptor,
        eventMessageID: WireUUID(UUID()),
        sentAtUnixMilliseconds: 1_000,
        hostMonotonicNowMilliseconds: 500
    )
    let request = try focusAuthoritySelection(
        descriptor: descriptor,
        targetToken: WireUUID(targetToken)
    )
    #expect(throws: InteractiveFocusEventAuthorityErrorV0.expired) {
        try authority.consume(
            request,
            current: descriptor,
            hostMonotonicNowMilliseconds: 600
        )
    }
    let changed = try focusAuthorityDesktop(
        surfaceID: descriptor.surfaceID,
        surfaceRevision: 2,
        coordinateRevision: 1
    )
    #expect(throws: InteractiveFocusEventAuthorityErrorV0.fenceMismatch) {
        try authority.consume(
            request,
            current: changed,
            hostMonotonicNowMilliseconds: 550
        )
    }
}
