#if os(macOS)
import CompanionIPC
import CompanionInteractiveShared
import CoreGraphics
@testable import CompanionMacApplicationPlatform
import Foundation
import Testing

@available(macOS 14.0, *)
private func desktopPreparationCommandV1(
    selectedDisplayID: UUID = UUID()
) throws -> LocalInteractiveInitialDesktopPreparationCommandV1 {
    try LocalInteractiveInitialDesktopPreparationCommandV1(
        commandID: UUID(),
        interactiveSessionID: UUID(),
        authorizationEpoch: .init(rawValue: 4),
        selectedDisplayID: selectedDisplayID,
        interactionClasses: [.view, .pointer, .keyboard]
    )
}

@available(macOS 14.0, *)
@Test func initialDesktopPreparerProjectsOnlyBoundedOpaqueDescriptor()
    async throws
{
    let command = try desktopPreparationCommandV1()
    let surfaceID = UUID()
    let preparer = MacInteractiveInitialDesktopPreparerV1(
        resolveDisplay: { selected in
            #expect(selected == command.selectedDisplayID)
            return 77
        },
        displayBounds: { display in
            #expect(display == 77)
            return CGRect(x: -1_440, y: 0, width: 1_440, height: 900)
        },
        pixelDimensions: { _ in (2_880, 1_800) },
        displayRotation: { _ in 90 },
        identifier: { surfaceID }
    )

    let receipt = try await preparer.prepareInitialInteractiveDesktop(
        command,
        nowMonotonicNanoseconds: 2_000_000_000
    )

    try receipt.validate(against: command)
    #expect(receipt.correlationID == command.commandID)
    #expect(receipt.descriptor.surfaceID == surfaceID)
    #expect(receipt.descriptor.encodedWidth == 1_920)
    #expect(receipt.descriptor.encodedHeight == 1_200)
    #expect(receipt.descriptor.logicalWidthPoints == 1_440)
    #expect(receipt.descriptor.logicalHeightPoints == 900)
    #expect(receipt.descriptor.rotation == .degrees90)
    #expect(receipt.descriptor.createdAtMonotonicMilliseconds == 2_000)
    #expect(receipt.descriptor.expiresAtMonotonicMilliseconds == 12_000)
    #expect(receipt.descriptor.metadataFields.isEmpty)
    #expect(receipt.descriptor.applicationToken == nil)
    #expect(receipt.descriptor.windowToken == nil)
    #expect(receipt.descriptor.focus == nil)
}

@available(macOS 14.0, *)
@Test func initialDesktopPreparerRejectsInvalidGeometryAndRotation()
    async throws
{
    let command = try desktopPreparationCommandV1()
    let invalidGeometry = MacInteractiveInitialDesktopPreparerV1(
        resolveDisplay: { _ in 77 },
        displayBounds: { _ in .zero },
        pixelDimensions: { _ in (1_440, 900) },
        displayRotation: { _ in 0 },
        identifier: { UUID() }
    )
    await #expect(
        throws: MacInteractiveInitialDesktopPreparerErrorV1.unavailable
    ) {
        try await invalidGeometry.prepareInitialInteractiveDesktop(
            command,
            nowMonotonicNanoseconds: 2_000_000_000
        )
    }

    let invalidRotation = MacInteractiveInitialDesktopPreparerV1(
        resolveDisplay: { _ in 77 },
        displayBounds: { _ in CGRect(x: 0, y: 0, width: 100, height: 100) },
        pixelDimensions: { _ in (100, 100) },
        displayRotation: { _ in 45 },
        identifier: { UUID() }
    )
    await #expect(
        throws: MacInteractiveInitialDesktopPreparerErrorV1.unavailable
    ) {
        try await invalidRotation.prepareInitialInteractiveDesktop(
            command,
            nowMonotonicNanoseconds: 2_000_000_000
        )
    }
}

@available(macOS 14.0, *)
@Test func initialDesktopPreparerReplacesUnleasedRetryDescriptor()
    async throws
{
    let selectedDisplayID = UUID()
    let first = try desktopPreparationCommandV1(
        selectedDisplayID: selectedDisplayID
    )
    let retry = try desktopPreparationCommandV1(
        selectedDisplayID: selectedDisplayID
    )
    let surfaceTargets = MacInteractiveSurfaceTargetOwnerV1(
        excludedProcessIdentifiers: [],
        identifier: { UUID() }
    )
    let preparer = MacInteractiveInitialDesktopPreparerV1(
        resolveDisplay: { selected in
            #expect(selected == selectedDisplayID)
            return CGMainDisplayID()
        },
        displayBounds: { _ in
            CGRect(x: 0, y: 0, width: 1_440, height: 900)
        },
        pixelDimensions: { _ in (2_880, 1_800) },
        displayRotation: { _ in 0 },
        surfaceTargets: surfaceTargets,
        identifier: { UUID() }
    )

    _ = try await preparer.prepareInitialInteractiveDesktop(
        first,
        nowMonotonicNanoseconds: 2_000_000_000
    )
    let replacement = try await preparer.prepareInitialInteractiveDesktop(
        retry,
        nowMonotonicNanoseconds: 2_001_000_000
    )

    #expect(replacement.correlationID == retry.commandID)
    #expect(replacement.descriptor.interactiveSessionID
        == retry.interactiveSessionID)
    #expect(replacement.descriptor.createdAtMonotonicMilliseconds == 2_001)
}
#endif
