#if os(macOS)
import CompanionHostPlatform
import CompanionIPC
import CompanionInteractiveShared
import CoreGraphics
import Foundation

public enum MacInteractiveInitialDesktopPreparerErrorV1:
    Error,
    Equatable,
    Sendable
{
    case unavailable
}

/// Menu-only Core Graphics projection for the first Desktop descriptor. It
/// performs no ScreenCaptureKit enumeration and starts no capture or input.
@available(macOS 14.0, *)
public final class MacInteractiveInitialDesktopPreparerV1:
    MacInteractiveInitialDesktopPreparingV1,
    @unchecked Sendable
{
    private let resolveDisplay:
        @Sendable (UUID) throws -> CGDirectDisplayID
    private let displayBounds: @Sendable (CGDirectDisplayID) -> CGRect
    private let pixelDimensions:
        @Sendable (CGDirectDisplayID) -> (width: Int, height: Int)
    private let displayRotation: @Sendable (CGDirectDisplayID) -> Double
    private let identifier: @Sendable () -> UUID
    private let surfaceTargets: MacInteractiveSurfaceTargetOwnerV1?

    public convenience init(
        displaySelection: MacInteractiveOpaqueDisplaySelectionV1,
        surfaceTargets: MacInteractiveSurfaceTargetOwnerV1? = nil,
        identifier: @escaping @Sendable () -> UUID = { UUID() }
    ) {
        self.init(
            resolveDisplay: {
                try displaySelection.resolvePhysicalDisplayID(
                    selectedDisplayID: $0
                )
            },
            displayBounds: { CGDisplayBounds($0) },
            pixelDimensions: {
                (Int(CGDisplayPixelsWide($0)), Int(CGDisplayPixelsHigh($0)))
            },
            displayRotation: { CGDisplayRotation($0) },
            surfaceTargets: surfaceTargets,
            identifier: identifier
        )
    }

    package init(
        resolveDisplay:
            @escaping @Sendable (UUID) throws -> CGDirectDisplayID,
        displayBounds:
            @escaping @Sendable (CGDirectDisplayID) -> CGRect,
        pixelDimensions:
            @escaping @Sendable (CGDirectDisplayID)
                -> (width: Int, height: Int),
        displayRotation:
            @escaping @Sendable (CGDirectDisplayID) -> Double,
        surfaceTargets: MacInteractiveSurfaceTargetOwnerV1? = nil,
        identifier: @escaping @Sendable () -> UUID
    ) {
        self.resolveDisplay = resolveDisplay
        self.displayBounds = displayBounds
        self.pixelDimensions = pixelDimensions
        self.displayRotation = displayRotation
        self.surfaceTargets = surfaceTargets
        self.identifier = identifier
    }

    public func prepareInitialInteractiveDesktop(
        _ command: LocalInteractiveInitialDesktopPreparationCommandV1,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
        let displayID = try resolveDisplay(command.selectedDisplayID)
        let bounds = displayBounds(displayID)
        let pixels = pixelDimensions(displayID)
        guard displayID != 0,
              bounds.origin.x.isFinite,
              bounds.origin.y.isFinite,
              bounds.width.isFinite,
              bounds.height.isFinite,
              bounds.width > 0,
              bounds.height > 0,
              bounds.width.rounded(.up) <= Double(UInt32.max),
              bounds.height.rounded(.up) <= Double(UInt32.max),
              pixels.width > 0,
              pixels.height > 0,
              nowMonotonicNanoseconds / 1_000_000
                <= UInt64(Int64.max - 10_000),
              let rotation = Self.rotation(displayRotation(displayID)) else {
            throw MacInteractiveInitialDesktopPreparerErrorV1.unavailable
        }
        let profile = try ScreenCaptureKitOpaqueTargetCatalogV0.captureProfile(
            logicalWidth: pixels.width,
            logicalHeight: pixels.height
        )
        let nowMilliseconds = Int64(
            nowMonotonicNanoseconds / 1_000_000
        )
        let descriptor = try AdaptiveSurfaceDescriptor(
            interactiveSessionID: command.interactiveSessionID,
            authorizationEpoch: command.authorizationEpoch,
            surfaceID: identifier(),
            kind: .desktop,
            surfaceRevision: .init(rawValue: 1),
            coordinateSpaceRevision: .init(rawValue: 1),
            encodedWidth: UInt16(profile.width),
            encodedHeight: UInt16(profile.height),
            logicalWidthPoints: UInt32(bounds.width.rounded(.up)),
            logicalHeightPoints: UInt32(bounds.height.rounded(.up)),
            rotation: rotation,
            interactionClasses: Set(command.interactionClasses),
            privacyProfile: .visualOnly,
            metadataFields: [],
            createdAtMonotonicMilliseconds: nowMilliseconds,
            expiresAtMonotonicMilliseconds: nowMilliseconds + 10_000
        )
        let receipt = try LocalInteractiveInitialDesktopPreparedReceiptV1(
            correlationID: command.commandID,
            descriptor: descriptor
        )
        try receipt.validate(against: command)
        if let surfaceTargets {
            try await surfaceTargets.bindInitialDesktop(
                command: command,
                descriptor: descriptor,
                physicalDisplayID: displayID
            )
        }
        return receipt
    }

    private static func rotation(_ value: Double) -> SurfaceRotation? {
        guard value.isFinite else { return nil }
        return switch Int(value.rounded()) {
        case 0, 360, -360: .degrees0
        case 90, -270: .degrees90
        case 180, -180: .degrees180
        case 270, -90: .degrees270
        default: nil
        }
    }
}
#endif
