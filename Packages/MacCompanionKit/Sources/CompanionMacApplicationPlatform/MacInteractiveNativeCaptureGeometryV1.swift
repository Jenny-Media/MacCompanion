#if os(macOS)
import CompanionIPC
import CompanionHostPlatform
import CompanionInteractiveShared
import CoreGraphics

/// Menu-local display measurement. This is not backend clean-aperture proof or
/// authority to accept remote input. The first native path is unrotated Desktop.
public enum MacInteractiveNativeCaptureGeometryV1 {
    /// Geometry for a retained menu-local selection. This neither starts a
    /// stream nor relaxes the existing Desktop-only native enrollment gate.
    @available(macOS 13.0, *)
    public static func readSelectedSurface(
        _ surface: ScreenCaptureKitResolvedSurfaceV0,
        scope: LocalInteractiveNativeBackendScopeV1
    ) throws -> InteractiveNativeVideoContentGeometryV0 {
        try projectSelectedSurface(scope: scope, descriptor: surface.descriptor,
            bounds: surface.inputBounds, backingScale: surface.inputBackingScaleFactor,
            activationTarget: surface.localActivationTarget)
    }

    package static func projectSelectedSurface(
        scope: LocalInteractiveNativeBackendScopeV1,
        descriptor: AdaptiveSurfaceDescriptor,
        bounds: CGRect,
        backingScale: Double,
        activationTarget: ScreenCaptureKitLocalActivationTargetV0?
    ) throws -> InteractiveNativeVideoContentGeometryV0 {
        try scope.validate()
        try descriptor.validate()
        guard descriptor.interactiveSessionID == scope.interactiveSessionID,
              descriptor.authorizationEpoch.rawValue == UInt64(scope.authorizationEpoch),
              descriptor.surfaceID == scope.surfaceID,
              descriptor.surfaceRevision.rawValue == UInt64(scope.surfaceRevision),
              descriptor.coordinateSpaceRevision.rawValue == UInt64(scope.coordinateSpaceRevision),
              Int(descriptor.encodedWidth) == scope.encodedWidth,
              Int(descriptor.encodedHeight) == scope.encodedHeight,
              descriptor.logicalWidthPoints == scope.logicalWidthPoints,
              descriptor.logicalHeightPoints == scope.logicalHeightPoints,
              descriptor.rotation == .degrees0, scope.rotation == .degrees0 else {
            MacNativeFailureDiagnosticsV1.recordSelectionRejection(.geometryScopeMismatch)
            throw LocalInteractiveNativeBackendErrorV1.bindingMismatch
        }
        switch (descriptor.kind, activationTarget) {
        case let (.window, .window(windowID, processID, bundleIdentifier, globalBounds)):
            guard windowID > 0, processID > 0, !bundleIdentifier.isEmpty,
                  globalBounds == bounds else { throw MacNativeFailureDiagnosticsV1.selectionUnavailable(.activationTargetInvalid) }
        case let (.application, .application(processID, bundleIdentifier)):
            guard processID > 0, !bundleIdentifier.isEmpty else { throw MacNativeFailureDiagnosticsV1.selectionUnavailable(.activationTargetInvalid) }
        default:
            throw MacNativeFailureDiagnosticsV1.selectionUnavailable(.activationTargetInvalid)
        }
        guard bounds.origin.x.isFinite, bounds.origin.y.isFinite,
              bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0,
              bounds.width.rounded(.up) == Double(scope.logicalWidthPoints),
              bounds.height.rounded(.up) == Double(scope.logicalHeightPoints),
              backingScale.isFinite, backingScale > 0,
              let width = Int(exactly: (bounds.width * backingScale).rounded(.up)),
              let height = Int(exactly: (bounds.height * backingScale).rounded(.up)) else {
            throw MacNativeFailureDiagnosticsV1.selectionUnavailable(.geometryInvalid)
        }
        return try .init(encodedWidth: scope.encodedWidth, encodedHeight: scope.encodedHeight,
            capturePixelWidth: width, capturePixelHeight: height,
            logicalWidthPoints: Int(scope.logicalWidthPoints), logicalHeightPoints: Int(scope.logicalHeightPoints))
    }

    public static func read(
        physicalDisplayID: UInt32,
        scope: LocalInteractiveNativeBackendScopeV1
    ) throws -> InteractiveNativeVideoContentGeometryV0 {
        guard physicalDisplayID != 0, let mode = CGDisplayCopyDisplayMode(physicalDisplayID) else {
            throw LocalInteractiveNativeBackendErrorV1.unavailable
        }
        return try project(scope: scope, bounds: CGDisplayBounds(physicalDisplayID),
            capturePixelWidth: mode.pixelWidth, capturePixelHeight: mode.pixelHeight,
            rotationDegrees: CGDisplayRotation(physicalDisplayID))
    }

    package static func project(
        scope: LocalInteractiveNativeBackendScopeV1,
        bounds: CGRect,
        capturePixelWidth: Int,
        capturePixelHeight: Int,
        rotationDegrees: Double
    ) throws -> InteractiveNativeVideoContentGeometryV0 {
        try scope.validate()
        guard scope.rotation == .degrees0, rotationDegrees == 0,
              bounds.origin.x.isFinite, bounds.origin.y.isFinite,
              bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0,
              bounds.width.rounded(.up) == Double(scope.logicalWidthPoints),
              bounds.height.rounded(.up) == Double(scope.logicalHeightPoints) else {
            throw LocalInteractiveNativeBackendErrorV1.unavailable
        }
        return try .init(encodedWidth: scope.encodedWidth, encodedHeight: scope.encodedHeight,
            capturePixelWidth: capturePixelWidth, capturePixelHeight: capturePixelHeight,
            logicalWidthPoints: Int(scope.logicalWidthPoints), logicalHeightPoints: Int(scope.logicalHeightPoints))
    }
}
#endif
