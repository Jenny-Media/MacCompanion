import CompanionInteractiveHost
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionWire
import Foundation
import Testing

private let composedSessionID = UUID(uuidString: "018f6000-0000-7000-8000-000000000001")!
private let composedSurfaceID = UUID(uuidString: "018f6100-0000-7000-8000-000000000001")!

private func composedSession() throws -> InteractiveSessionStateMachine {
    var value = InteractiveSessionStateMachine()
    _ = try value.apply(.request(
        sessionID: composedSessionID,
        authorizationEpoch: .init(rawValue: 4),
        approvalDeadlineMonotonicMilliseconds: 60_000
    ))
    _ = try value.apply(.approvalConsumed(monotonicNowMilliseconds: 1_000))
    _ = try value.apply(.executorReadyUnlocked(monotonicNowMilliseconds: 2_000))
    return value
}

private func composedSurface(secure: Bool = false) throws
    -> AdaptiveSurfaceDescriptor
{
    let focus = secure ? try SurfaceFocus(
        token: UUID(),
        revision: .init(rawValue: 1),
        category: .text,
        bounds: NormalizedSurfaceRect(x: 1, y: 1, width: 100, height: 100),
        editable: true,
        secure: true
    ) : nil
    return try AdaptiveSurfaceDescriptor(
        interactiveSessionID: composedSessionID,
        authorizationEpoch: .init(rawValue: 4),
        surfaceID: secure ? UUID() : composedSurfaceID,
        kind: secure ? .focusedRegion : .desktop,
        surfaceRevision: .init(rawValue: secure ? 2 : 1),
        coordinateSpaceRevision: .init(rawValue: secure ? 2 : 1),
        applicationToken: secure ? UUID() : nil,
        parentSurfaceID: secure ? composedSurfaceID : nil,
        fallbackSurfaceID: secure ? composedSurfaceID : nil,
        encodedWidth: 1_920,
        encodedHeight: 1_080,
        logicalWidthPoints: 1_440,
        logicalHeightPoints: 900,
        interactionClasses: [.view, .pointer, .keyboard, .text],
        privacyProfile: secure ? .secureOpaque : .visualOnly,
        metadataFields: secure
            ? [.focusCategory, .focusBounds, .editable, .secure]
            : [],
        focus: focus,
        createdAtMonotonicMilliseconds: 1_000,
        expiresAtMonotonicMilliseconds: 10_000
    )
}

@Test func textAllowsMissingFocusButDeniesPositiveSecureFocus() throws {
    let session = try composedSession()
    var authority = InteractiveInputAdmissionAuthority()
    let ordinary = try AdaptiveSurfaceAuthority(
        desktop: composedSurface(),
        monotonicNowMilliseconds: 2_000
    )
    try authority.admit(
        composedEnvelope(input: .text("hello")),
        session: session,
        surfaces: ordinary,
        hostMonotonicMilliseconds: 2_000
    )
    #expect(authority.stream.lastSequence == 1)

    let secureDescriptor = try composedSurface(secure: true)
    var secureSurface = try AdaptiveSurfaceAuthority(
        desktop: composedSurface(),
        monotonicNowMilliseconds: 2_000
    )
    _ = try secureSurface.requestSelection(
        target: secureDescriptor,
        expectedSurfaceRevision: .init(rawValue: 1),
        expectedCoordinateSpaceRevision: .init(rawValue: 1),
        monotonicNowMilliseconds: 2_000
    )
    _ = try secureSurface.executorCommitted(
        descriptor: secureDescriptor,
        monotonicNowMilliseconds: 2_000
    )
    _ = try secureSurface.acknowledge(
        SurfaceInputFence(
            interactiveSessionID: composedSessionID,
            authorizationEpoch: .init(rawValue: 4),
            surfaceID: secureDescriptor.surfaceID,
            surfaceRevision: secureDescriptor.surfaceRevision,
            coordinateSpaceRevision:
                secureDescriptor.coordinateSpaceRevision,
            focusToken: secureDescriptor.focus?.token,
            focusRevision: secureDescriptor.focus?.revision
        ),
        monotonicNowMilliseconds: 2_000
    )
    var secureAuthority = InteractiveInputAdmissionAuthority()
    #expect(throws: InteractiveInputAdmissionError.secureTextFocusDenied) {
        try secureAuthority.admit(
            InteractiveInputEnvelope(
                messageID: WireUUID(UUID()),
                interactiveSessionID: WireUUID(composedSessionID),
                authorizationEpoch: .init(rawValue: 4),
                sequence: 1,
                clientMonotonicMilliseconds: 1,
                surfaceID: WireUUID(secureDescriptor.surfaceID),
                surfaceRevision: secureDescriptor.surfaceRevision,
                coordinateSpaceRevision:
                    secureDescriptor.coordinateSpaceRevision,
                focusToken: secureDescriptor.focus.map { WireUUID($0.token) },
                focusRevision: secureDescriptor.focus?.revision,
                input: .text("secret")
            ),
            session: session,
            surfaces: secureSurface,
            hostMonotonicMilliseconds: 2_000
        )
    }
    #expect(secureAuthority.stream.lastSequence == 0)
}

private func composedEnvelope(
    sequence: UInt64 = 1,
    epoch: UInt64 = 4,
    surfaceRevision: UInt64 = 1,
    input: InteractiveInputPayload = .pointerMove(x: 1, y: 1)
) throws -> InteractiveInputEnvelope {
    try InteractiveInputEnvelope(
        messageID: WireUUID(UUID()),
        interactiveSessionID: WireUUID(composedSessionID),
        authorizationEpoch: .init(rawValue: epoch),
        sequence: sequence,
        clientMonotonicMilliseconds: sequence,
        surfaceID: WireUUID(composedSurfaceID),
        surfaceRevision: .init(rawValue: surfaceRevision),
        coordinateSpaceRevision: .init(rawValue: 1),
        input: input
    )
}

@Test func surfaceFenceFailureDoesNotConsumeInputSequence() throws {
    let session = try composedSession()
    let surfaces = try AdaptiveSurfaceAuthority(
        desktop: composedSurface(),
        monotonicNowMilliseconds: 2_000
    )
    var authority = InteractiveInputAdmissionAuthority()
    #expect(throws: AdaptiveSurfaceError.staleSurface) {
        try authority.admit(
            composedEnvelope(surfaceRevision: 2),
            session: session,
            surfaces: surfaces,
            hostMonotonicMilliseconds: 2_000
        )
    }
    #expect(authority.stream.lastSequence == 0)
    try authority.admit(
        composedEnvelope(),
        session: session,
        surfaces: surfaces,
        hostMonotonicMilliseconds: 2_000
    )
    #expect(authority.stream.lastSequence == 1)
}

@Test func inactiveSessionAndChangedEpochFailBeforeStreamMutation() throws {
    var inactive = try composedSession()
    _ = try inactive.apply(.suspend(.authorizationChanged))
    let surfaces = try AdaptiveSurfaceAuthority(
        desktop: composedSurface(),
        monotonicNowMilliseconds: 2_000
    )
    var authority = InteractiveInputAdmissionAuthority()
    #expect(throws: InteractiveInputAdmissionError.sessionInactive) {
        try authority.admit(
            composedEnvelope(),
            session: inactive,
            surfaces: surfaces,
            hostMonotonicMilliseconds: 2_000
        )
    }

    let active = try composedSession()
    #expect(throws: InteractiveInputAdmissionError.authorizationChanged) {
        try authority.admit(
            composedEnvelope(epoch: 5),
            session: active,
            surfaces: surfaces,
            hostMonotonicMilliseconds: 2_000
        )
    }
    #expect(authority.stream.lastSequence == 0)
}

@Test func expiredDescriptorDeniesOtherwiseValidInput() throws {
    let session = try composedSession()
    let surfaces = try AdaptiveSurfaceAuthority(
        desktop: composedSurface(),
        monotonicNowMilliseconds: 2_000
    )
    var authority = InteractiveInputAdmissionAuthority()
    #expect(throws: AdaptiveSurfaceError.expired) {
        try authority.admit(
            composedEnvelope(),
            session: session,
            surfaces: surfaces,
            hostMonotonicMilliseconds: 10_000
        )
    }
    #expect(authority.stream.lastSequence == 0)
}

@Test func exactSessionDeadlineDeniesInputEvenBeforeReducerTick() throws {
    let session = try composedSession()
    let surfaces = try AdaptiveSurfaceAuthority(
        desktop: composedSurface(),
        monotonicNowMilliseconds: 2_000
    )
    var authority = InteractiveInputAdmissionAuthority()
    let deadline = session.sessionDeadlineMonotonicMilliseconds!
    #expect(throws: InteractiveInputAdmissionError.sessionExpired) {
        try authority.admit(
            composedEnvelope(),
            session: session,
            surfaces: surfaces,
            hostMonotonicMilliseconds: UInt64(deadline)
        )
    }
    #expect(authority.stream.lastSequence == 0)
}
