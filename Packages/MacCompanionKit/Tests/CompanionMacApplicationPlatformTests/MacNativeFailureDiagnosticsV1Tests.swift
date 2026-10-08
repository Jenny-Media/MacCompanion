#if os(macOS)
@testable import CompanionMacApplicationPlatform
import CompanionHostPlatform
import CompanionInteractiveRuntime
import CompanionInteractiveShared
import CompanionIPC
import Foundation
import Testing

@Test func nativeFailureDiagnosticsMatchIndexedVocabulary() throws {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while !FileManager.default.fileExists(atPath: root.appendingPathComponent("spec/fixtures/manifest.json").path) {
        let parent = root.deletingLastPathComponent()
        try #require(parent != root)
        root = parent
    }
    let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf:
        root.appendingPathComponent("spec/fixtures/local-xpc-native-backend-v0.1.json"))) as? [String: Any])
    let profile = try #require(fixture["failureDiagnostics"] as? [String: Any])
    let reasons = try #require(profile["reasons"] as? [String: [String]])
    let expected = Set(reasons.flatMap { family, codes in codes.map { family + "." + $0 } })
    let errors: [any Error] = [
        LocalInteractiveNativeBackendErrorV1.invalidMaterial, LocalInteractiveNativeBackendErrorV1.bindingMismatch,
        LocalInteractiveNativeBackendErrorV1.unavailable,
        MacCoreGraphicsInteractiveInputAdapterErrorV1.alreadyConfigured, MacCoreGraphicsInteractiveInputAdapterErrorV1.unavailable,
        MacCoreGraphicsInteractiveInputAdapterErrorV1.permissionDenied, MacCoreGraphicsInteractiveInputAdapterErrorV1.bindingMismatch,
        MacCoreGraphicsInteractiveInputAdapterErrorV1.eventConstructionFailed,
        CoreGraphicsInputConstructionErrorV0.invalidDisplayBounds, CoreGraphicsInputConstructionErrorV0.invalidCursorPosition,
        CoreGraphicsInputConstructionErrorV0.cursorOutsideSelectedDisplay, CoreGraphicsInputConstructionErrorV0.geometryFenceMismatch,
        CoreGraphicsInputConstructionErrorV0.eventCreationFailed,
        MacInteractiveSelectedSurfaceActivatorErrorV1.invalidTarget, MacInteractiveSelectedSurfaceActivatorErrorV1.activationFailed,
        MacInteractiveSelectedSurfaceActivatorErrorV1.verificationFailed,
        InteractiveRuntimeNativeInputPostingErrorV0.bindingMismatch, InteractiveRuntimeNativeInputPostingErrorV0.expired,
        InteractiveRuntimeNativeInputPostingErrorV0.unavailable, InteractiveRuntimeNativeInputPostingErrorV0.notPosted,
        MacManagedSunshineEnrollmentBackendV1.Failure.invalidPhase, MacManagedSunshineEnrollmentBackendV1.Failure.invalidCertificate,
        MacManagedSunshineEnrollmentBackendV1.Failure.startupFailed, MacManagedSunshineEnrollmentBackendV1.Failure.invalidPath,
        MacManagedCaptureHandoffV1.Failure.invalidDirectory, MacManagedCaptureHandoffV1.Failure.unavailable,
        MacManagedCaptureHandoffV1.Failure.invalidRecord, MacManagedCaptureHandoffV1.Failure.timedOut,
        InteractiveNativeVideoCaptureEvidenceErrorV0.invalidPayload, InteractiveNativeVideoCaptureEvidenceErrorV0.bindingMismatch,
        InteractiveNativeVideoCaptureEvidenceErrorV0.notCurrent,
    ]
    #expect(Set(errors.map(MacNativeFailureDiagnosticsV1.reason)) == expected)
    #expect(profile["arbitraryErrorDescriptionAllowed"] as? Bool == false)
    #expect(profile["unknownReason"] as? String == "unclassified")
    let selectionRejections = try #require(profile["selectionRejections"] as? [String])
    #expect(Set(MacNativeFailureDiagnosticsV1.SelectionRejection.allCases.map(\.rawValue)) == Set(selectionRejections))
}

private struct UnrecognizedNativeDiagnosticError: Error, CustomStringConvertible {
    var description: String { fatalError("Diagnostics must not describe an unrecognized error") }
}

@Test func nativeFailureDiagnosticsNeverDescribeAnUnrecognizedError() {
    #expect(MacNativeFailureDiagnosticsV1.reason(UnrecognizedNativeDiagnosticError()) == "unclassified")
    #expect(MacNativeFailureDiagnosticsV1.reason(NSError(domain: "private-platform-metadata", code: 7,
        userInfo: [NSLocalizedDescriptionKey: "private input and identity"])) == "unclassified")
}
#endif
