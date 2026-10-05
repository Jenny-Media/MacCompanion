#if os(macOS)
import CompanionHostPlatform
import CompanionInteractiveRuntime
import CompanionInteractiveShared
import CompanionIPC
import Foundation
import OSLog

private let macNativeSelectionDiagnosticsLoggerV1 = Logger(
    subsystem: "media.jenny.maccompanion.mac", category: "native-selection-diagnostics"
)

/// Fixed local failure vocabulary only. Never describe an arbitrary Error:
/// associated payloads may contain identity, input or platform metadata.
package enum MacNativeFailureDiagnosticsV1 {
    package enum SelectionRejection: String, CaseIterable, Sendable {
        case admissionClosedBeforeSelection, admissionClosedAfterSelection
        case pendingSelection, uncommittedSelection, activeAbsent, leaseAbsent
        case hostMismatch, sessionMismatch, authorizationMismatch, displayMismatch
        case surfaceMismatch, surfaceRevisionMismatch, coordinateRevisionMismatch
        case encodedWidthMismatch, encodedHeightMismatch, logicalWidthMismatch, logicalHeightMismatch
        case rotationMismatch, leaseExpired, controlExpired
        case desktopSurfaceMismatch, unsupportedKind, selectedSurfaceAbsent, selectedDescriptorMismatch
        case geometryScopeMismatch, activationTargetInvalid, geometryInvalid
        case captureWindowDisplay, captureApplicationDisplay, captureKind, captureApplicationIdentity, captureScale
        case liveExpired, liveDisplay, liveApplication, liveScale, liveWindowInventory
        case liveWindowIdentity, liveWindowGeometry, liveWindowDisplay, liveApplicationGeometry
    }

    package static func recordSelectionRejection(_ code: SelectionRejection) {
        macNativeSelectionDiagnosticsLoggerV1.error("native-selection-rejected reason=\(code.rawValue, privacy: .public)")
    }

    package static func selectionUnavailable(_ code: SelectionRejection) -> LocalInteractiveNativeBackendErrorV1 {
        recordSelectionRejection(code)
        return .unavailable
    }

    package static func reason(_ error: any Error) -> String {
        if let value = error as? LocalInteractiveNativeBackendErrorV1 {
            switch value {
            case .invalidMaterial: return "local.invalidMaterial"
            case .bindingMismatch: return "local.bindingMismatch"
            case .unavailable: return "local.unavailable"
            }
        }
        if let value = error as? MacCoreGraphicsInteractiveInputAdapterErrorV1 {
            switch value {
            case .alreadyConfigured: return "input.alreadyConfigured"
            case .unavailable: return "input.unavailable"
            case .permissionDenied: return "input.permissionDenied"
            case .bindingMismatch: return "input.bindingMismatch"
            case .eventConstructionFailed: return "input.eventConstructionFailed"
            }
        }
        if let value = error as? CoreGraphicsInputConstructionErrorV0 {
            switch value {
            case .invalidDisplayBounds: return "constructor.invalidDisplayBounds"
            case .invalidCursorPosition: return "constructor.invalidCursorPosition"
            case .cursorOutsideSelectedDisplay: return "constructor.cursorOutsideSelectedDisplay"
            case .geometryFenceMismatch: return "constructor.geometryFenceMismatch"
            case .eventCreationFailed: return "constructor.eventCreationFailed"
            }
        }
        if let value = error as? MacInteractiveSelectedSurfaceActivatorErrorV1 {
            switch value {
            case .invalidTarget: return "activation.invalidTarget"
            case .activationFailed: return "activation.activationFailed"
            case .verificationFailed: return "activation.verificationFailed"
            }
        }
        if let value = error as? InteractiveRuntimeNativeInputPostingErrorV0 {
            switch value {
            case .bindingMismatch: return "posting.bindingMismatch"
            case .expired: return "posting.expired"
            case .unavailable: return "posting.unavailable"
            case .notPosted: return "posting.notPosted"
            }
        }
        if let value = error as? MacManagedSunshineEnrollmentBackendV1.Failure {
            switch value {
            case .invalidPhase: return "backend.invalidPhase"
            case .invalidCertificate: return "backend.invalidCertificate"
            case .startupFailed: return "backend.startupFailed"
            case .invalidPath: return "backend.invalidPath"
            }
        }
        if let value = error as? MacManagedCaptureHandoffV1.Failure {
            switch value {
            case .invalidDirectory: return "handoff.invalidDirectory"
            case .unavailable: return "handoff.unavailable"
            case .invalidRecord: return "handoff.invalidRecord"
            case .timedOut: return "handoff.timedOut"
            }
        }
        if let value = error as? InteractiveNativeVideoCaptureEvidenceErrorV0 {
            switch value {
            case .invalidPayload: return "evidence.invalidPayload"
            case .bindingMismatch: return "evidence.bindingMismatch"
            case .notCurrent: return "evidence.notCurrent"
            }
        }
        return "unclassified"
    }
}
#endif
