import CompanionDomain
import CompanionInteractiveShared
import CompanionTestSupport
import Foundation
import Testing

private let surfaceSessionID = UUID(uuidString: "018f6000-0000-7000-8000-000000000001")!
private let desktopSurfaceID = UUID(uuidString: "018f6100-0000-7000-8000-000000000001")!
private let appSurfaceID = UUID(uuidString: "018f6100-0000-7000-8000-000000000002")!
private let focusSurfaceID = UUID(uuidString: "018f6100-0000-7000-8000-000000000003")!
private let applicationToken = UUID(uuidString: "018f6200-0000-7000-8000-000000000001")!
private let focusToken = UUID(uuidString: "018f6300-0000-7000-8000-000000000001")!
private let surfaceNow: Int64 = 2_000

private func descriptor(
    kind: InteractiveSurfaceKind,
    surfaceID: UUID,
    surfaceRevision: UInt64,
    coordinateRevision: UInt64,
    privacy: SurfacePrivacyProfile = .visualOnly,
    metadata: Set<SurfaceMetadataField> = [],
    focus: SurfaceFocus? = nil,
    parent: UUID? = nil,
    fallback: UUID? = nil,
    windowToken: UUID? = nil,
    createdAtMonotonicMilliseconds: Int64 = 1_000,
    expiresAtMonotonicMilliseconds: Int64 = 11_000
) throws -> AdaptiveSurfaceDescriptor {
    try AdaptiveSurfaceDescriptor(
        interactiveSessionID: surfaceSessionID,
        authorizationEpoch: .init(rawValue: 4),
        surfaceID: surfaceID,
        kind: kind,
        surfaceRevision: .init(rawValue: surfaceRevision),
        coordinateSpaceRevision: .init(rawValue: coordinateRevision),
        applicationToken: kind == .desktop ? nil : applicationToken,
        windowToken: windowToken,
        parentSurfaceID: parent,
        fallbackSurfaceID: fallback,
        encodedWidth: 1_920,
        encodedHeight: 1_080,
        logicalWidthPoints: 1_440,
        logicalHeightPoints: 900,
        interactionClasses: [.view, .pointer, .keyboard],
        privacyProfile: privacy,
        metadataFields: metadata,
        focus: focus,
        createdAtMonotonicMilliseconds: createdAtMonotonicMilliseconds,
        expiresAtMonotonicMilliseconds: expiresAtMonotonicMilliseconds
    )
}

@Test func selectionUsesAcknowledgedCurrentFenceAndFreshTargetLifetime()
    throws
{
    let current = try descriptor(
        kind: .desktop,
        surfaceID: desktopSurfaceID,
        surfaceRevision: 1,
        coordinateRevision: 1,
        expiresAtMonotonicMilliseconds: 2_100
    )
    let target = try descriptor(
        kind: .application,
        surfaceID: appSurfaceID,
        surfaceRevision: 2,
        coordinateRevision: 2,
        expiresAtMonotonicMilliseconds: 4_000
    )
    var authority = try AdaptiveSurfaceAuthority(
        desktop: current,
        monotonicNowMilliseconds: surfaceNow
    )

    #expect(try authority.requestSelection(
        target: target,
        expectedSurfaceRevision: current.surfaceRevision,
        expectedCoordinateSpaceRevision: current.coordinateSpaceRevision,
        monotonicNowMilliseconds: 2_200
    ) == [.pauseInput, .releaseAllInput, .applyCaptureSource])
}

private func desktop(
    revision: UInt64 = 1,
    coordinate: UInt64 = 1,
    id: UUID = desktopSurfaceID
) throws -> AdaptiveSurfaceDescriptor {
    try descriptor(
        kind: .desktop,
        surfaceID: id,
        surfaceRevision: revision,
        coordinateRevision: coordinate
    )
}

private func fence(
    _ value: AdaptiveSurfaceDescriptor,
    focusToken: UUID? = nil,
    focusRevision: UInt64? = nil
) -> SurfaceInputFence {
    SurfaceInputFence(
        interactiveSessionID: value.interactiveSessionID,
        authorizationEpoch: value.authorizationEpoch,
        surfaceID: value.surfaceID,
        surfaceRevision: value.surfaceRevision,
        coordinateSpaceRevision: value.coordinateSpaceRevision,
        focusToken: focusToken,
        focusRevision: focusRevision.map { .init(rawValue: $0) }
    )
}

@Test func selectionPausesInputUntilDescriptorKeyframeBoundaryIsAcknowledged() throws {
    let initial = try desktop()
    let app = try descriptor(
        kind: .application,
        surfaceID: appSurfaceID,
        surfaceRevision: 2,
        coordinateRevision: 2,
        metadata: [.applicationName, .applicationIcon, .windowCount]
    )
    var authority = try AdaptiveSurfaceAuthority(desktop: initial, monotonicNowMilliseconds: surfaceNow)
    #expect(try authority.requestSelection(
        target: app,
        expectedSurfaceRevision: initial.surfaceRevision,
        expectedCoordinateSpaceRevision: initial.coordinateSpaceRevision,
        monotonicNowMilliseconds: surfaceNow
    ) == [.pauseInput, .releaseAllInput, .applyCaptureSource])
    #expect(throws: AdaptiveSurfaceError.notActive) {
        try authority.validateInput(
            fence(initial),
            requiresFocusBinding: false,
            monotonicNowMilliseconds: surfaceNow
        )
    }
    #expect(try authority.executorCommitted(
        descriptor: app,
        monotonicNowMilliseconds: surfaceNow
    ) == [
        .emitVideoDiscontinuity, .publishDescriptor, .requestCleanKeyframe,
    ])
    #expect(try authority.acknowledge(
        fence(app),
        monotonicNowMilliseconds: surfaceNow
    ) == [.resumeInput])
    try authority.validateInput(
        fence(app),
        requiresFocusBinding: false,
        monotonicNowMilliseconds: surfaceNow
    )
    #expect(throws: AdaptiveSurfaceError.staleSurface) {
        try authority.validateInput(
            fence(initial),
            requiresFocusBinding: false,
            monotonicNowMilliseconds: surfaceNow
        )
    }
}

@Test func staleSelectionRevisionsNeverApplyToAReplacementSurface() throws {
    let initial = try desktop()
    let app = try descriptor(
        kind: .application,
        surfaceID: appSurfaceID,
        surfaceRevision: 2,
        coordinateRevision: 2
    )
    var authority = try AdaptiveSurfaceAuthority(desktop: initial, monotonicNowMilliseconds: surfaceNow)
    #expect(throws: AdaptiveSurfaceError.staleSurface) {
        try authority.requestSelection(
            target: app,
            expectedSurfaceRevision: .init(rawValue: 0),
            expectedCoordinateSpaceRevision: initial.coordinateSpaceRevision,
            monotonicNowMilliseconds: surfaceNow
        )
    }
    #expect(throws: AdaptiveSurfaceError.staleCoordinateSpace) {
        try authority.requestSelection(
            target: app,
            expectedSurfaceRevision: initial.surfaceRevision,
            expectedCoordinateSpaceRevision: .init(rawValue: 0),
            monotonicNowMilliseconds: surfaceNow
        )
    }
}

@Test func focusDerivedInputRequiresExactOpaqueFocusBinding() throws {
    let initial = try desktop()
    let focus = try SurfaceFocus(
        token: focusToken,
        revision: .init(rawValue: 7),
        category: .text,
        bounds: NormalizedSurfaceRect(x: 10_000, y: 10_000, width: 20_000, height: 5_000),
        editable: true,
        secure: false
    )
    let focused = try descriptor(
        kind: .focusedRegion,
        surfaceID: focusSurfaceID,
        surfaceRevision: 2,
        coordinateRevision: 2,
        privacy: .assistedVisual,
        metadata: [.focusCategory, .focusBounds, .editable, .secure],
        focus: focus,
        parent: desktopSurfaceID,
        fallback: desktopSurfaceID
    )
    var authority = try AdaptiveSurfaceAuthority(desktop: initial, monotonicNowMilliseconds: surfaceNow)
    _ = try authority.requestSelection(
        target: focused,
        expectedSurfaceRevision: initial.surfaceRevision,
        expectedCoordinateSpaceRevision: initial.coordinateSpaceRevision,
        monotonicNowMilliseconds: surfaceNow
    )
    _ = try authority.executorCommitted(descriptor: focused, monotonicNowMilliseconds: surfaceNow)
    #expect(throws: AdaptiveSurfaceError.staleFocus) {
        try authority.acknowledge(
            fence(focused),
            monotonicNowMilliseconds: surfaceNow
        )
    }
    _ = try authority.acknowledge(
        fence(focused, focusToken: focusToken, focusRevision: 7),
        monotonicNowMilliseconds: surfaceNow
    )

    #expect(throws: AdaptiveSurfaceError.staleFocus) {
        try authority.validateInput(
            fence(focused),
            requiresFocusBinding: true,
            monotonicNowMilliseconds: surfaceNow
        )
    }
    try authority.validateInput(
        fence(focused, focusToken: focusToken, focusRevision: 7),
        requiresFocusBinding: true,
        monotonicNowMilliseconds: surfaceNow
    )
    #expect(throws: AdaptiveSurfaceError.staleFocus) {
        try authority.validateInput(
            fence(focused, focusToken: focusToken, focusRevision: 6),
            requiresFocusBinding: true,
            monotonicNowMilliseconds: surfaceNow
        )
    }
}

@Test func fallbackDuringSwitchAdvancesFromNewestIssuedRevision() throws {
    let initial = try desktop()
    let app = try descriptor(
        kind: .application,
        surfaceID: appSurfaceID,
        surfaceRevision: 2,
        coordinateRevision: 2
    )
    let fallback = try desktop(revision: 3, coordinate: 3, id: UUID())
    var authority = try AdaptiveSurfaceAuthority(desktop: initial, monotonicNowMilliseconds: surfaceNow)
    _ = try authority.requestSelection(
        target: app,
        expectedSurfaceRevision: initial.surfaceRevision,
        expectedCoordinateSpaceRevision: initial.coordinateSpaceRevision,
        monotonicNowMilliseconds: surfaceNow
    )
    #expect(try authority.beginFallback(
        target: fallback,
        reason: .modalRelationshipAmbiguous,
        monotonicNowMilliseconds: surfaceNow
    ) == [.pauseInput, .releaseAllInput, .applyCaptureSource])
    _ = try authority.executorCommitted(descriptor: fallback, monotonicNowMilliseconds: surfaceNow)
    _ = try authority.acknowledge(fence(fallback), monotonicNowMilliseconds: surfaceNow)
    try authority.validateInput(
        fence(fallback),
        requiresFocusBinding: false,
        monotonicNowMilliseconds: surfaceNow
    )
}

@Test func privacyAllowlistRejectsTitlesValuesAndIncorrectSecureClassification() throws {
    #expect(throws: AdaptiveSurfaceError.forbiddenMetadata) {
        _ = try descriptor(
            kind: .application,
            surfaceID: appSurfaceID,
            surfaceRevision: 2,
            coordinateRevision: 2,
            metadata: [.focusCategory]
        )
    }
    let secureFocus = try SurfaceFocus(
        token: focusToken,
        revision: .init(rawValue: 1),
        category: .text,
        bounds: NormalizedSurfaceRect(x: 0, y: 0, width: 100, height: 100),
        editable: true,
        secure: true
    )
    #expect(throws: AdaptiveSurfaceError.invalidDescriptor) {
        _ = try descriptor(
            kind: .focusedRegion,
            surfaceID: focusSurfaceID,
            surfaceRevision: 2,
            coordinateRevision: 2,
            privacy: .assistedVisual,
            metadata: [.focusCategory, .focusBounds, .editable, .secure],
            focus: secureFocus,
            parent: desktopSurfaceID,
            fallback: desktopSurfaceID
        )
    }
}

@Test func suspensionInvalidatesEverySurfaceAndCannotResumeInPlace() throws {
    let initial = try desktop()
    var authority = try AdaptiveSurfaceAuthority(desktop: initial, monotonicNowMilliseconds: surfaceNow)
    #expect(try authority.suspend() == [
        .pauseInput, .releaseAllInput, .invalidateAllTokens, .stopCapture,
    ])
    #expect(throws: AdaptiveSurfaceError.notActive) {
        try authority.validateInput(
            fence(initial),
            requiresFocusBinding: false,
            monotonicNowMilliseconds: surfaceNow
        )
    }
    #expect(throws: AdaptiveSurfaceError.notActive) {
        try authority.beginFallback(
            target: try desktop(revision: 2, coordinate: 2),
            reason: .sourceUnavailable,
            monotonicNowMilliseconds: surfaceNow
        )
    }
    #expect(throws: AdaptiveSurfaceError.notActive) {
        try authority.suspend()
    }
}

@Test func descriptorLifetimeIsCheckedAtEveryAuthorityBoundary() throws {
    let initial = try desktop()
    #expect(throws: AdaptiveSurfaceError.expired) {
        try AdaptiveSurfaceAuthority(desktop: initial, monotonicNowMilliseconds: 999)
    }

    let authority = try AdaptiveSurfaceAuthority(
        desktop: initial,
        monotonicNowMilliseconds: surfaceNow
    )
    #expect(throws: AdaptiveSurfaceError.expired) {
        try authority.validateInput(
            fence(initial),
            requiresFocusBinding: false,
            monotonicNowMilliseconds: 11_000
        )
    }
}

@Test func authoritativeDesktopSurfaceFixtureDecodesAndValidates() throws {
    let url = FixturePaths.authoritativeFixtures()
        .appendingPathComponent("valid/interactive-desktop-surface.json")
    let descriptor = try JSONDecoder().decode(
        AdaptiveSurfaceDescriptor.self,
        from: Data(contentsOf: url)
    )
    try descriptor.validate()
    #expect(descriptor.kind == .desktop)
    #expect(descriptor.interactionClasses == [.keyboard, .pointer, .view])
}

@Test func authoritativeForbiddenMetadataFixtureIsRejected() throws {
    let url = FixturePaths.authoritativeFixtures()
        .appendingPathComponent("invalid/interactive-surface-forbidden-metadata.json")
    let descriptor = try JSONDecoder().decode(
        AdaptiveSurfaceDescriptor.self,
        from: Data(contentsOf: url)
    )
    #expect(throws: AdaptiveSurfaceError.forbiddenMetadata) {
        try descriptor.validate()
    }
}
