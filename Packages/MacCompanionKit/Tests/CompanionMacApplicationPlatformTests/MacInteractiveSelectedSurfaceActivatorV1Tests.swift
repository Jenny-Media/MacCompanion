#if os(macOS)
import CompanionHostPlatform
import CoreGraphics
@testable import CompanionMacApplicationPlatform
import Foundation
import Testing

@MainActor
private final class SelectedSurfaceActivationProbeV1 {
    var performed: [ScreenCaptureKitLocalActivationTargetV0] = []
    var verified: [ScreenCaptureKitLocalActivationTargetV0] = []
    var waits = 0
    var performResult = true
    var verificationResults: [Bool] = [true]

    func perform(_ target: ScreenCaptureKitLocalActivationTargetV0) -> Bool {
        performed.append(target)
        return performResult
    }

    func verify(_ target: ScreenCaptureKitLocalActivationTargetV0) -> Bool {
        verified.append(target)
        return verificationResults.isEmpty
            ? false : verificationResults.removeFirst()
    }
}

@available(macOS 14.0, *)
@Test @MainActor
func selectedSurfaceActivatorDoesNothingForDesktopOrFocusedCrop()
    async throws
{
    let probe = SelectedSurfaceActivationProbeV1()
    let activator = MacInteractiveSelectedSurfaceActivatorV1(
        performActivation: { probe.perform($0) },
        verifyActivation: { probe.verify($0) },
        wait: { probe.waits += 1 }
    )

    try await activator.activate(nil)

    #expect(probe.performed.isEmpty)
    #expect(probe.verified.isEmpty)
    #expect(probe.waits == 0)
}

@available(macOS 14.0, *)
@Test @MainActor
func selectedWindowActivationRetainsExactLocalIdentityUntilVerified()
    async throws
{
    let probe = SelectedSurfaceActivationProbeV1()
    probe.verificationResults = [false, false, true]
    let target = ScreenCaptureKitLocalActivationTargetV0.window(
        windowID: 77,
        processID: 88,
        bundleIdentifier: "example.target",
        globalBounds: CGRect(x: 100, y: 200, width: 800, height: 600)
    )
    let activator = MacInteractiveSelectedSurfaceActivatorV1(
        performActivation: { probe.perform($0) },
        verifyActivation: { probe.verify($0) },
        maximumVerificationAttempts: 4,
        wait: { probe.waits += 1 }
    )

    try await activator.activate(target)

    #expect(probe.performed == [target])
    #expect(probe.verified == [target, target, target])
    #expect(probe.waits == 2)
}

@available(macOS 14.0, *)
@Test @MainActor
func selectedSurfaceActivationFailsClosedForInvalidOrUnverifiedTarget()
    async
{
    let invalidProbe = SelectedSurfaceActivationProbeV1()
    let invalid = MacInteractiveSelectedSurfaceActivatorV1(
        performActivation: { invalidProbe.perform($0) },
        verifyActivation: { invalidProbe.verify($0) },
        wait: { invalidProbe.waits += 1 }
    )
    await #expect(throws:
        MacInteractiveSelectedSurfaceActivatorErrorV1.invalidTarget
    ) {
        try await invalid.activate(.application(
            processID: 0,
            bundleIdentifier: "example.target"
        ))
    }
    #expect(invalidProbe.performed.isEmpty)

    let unverifiedProbe = SelectedSurfaceActivationProbeV1()
    unverifiedProbe.verificationResults = [false, false]
    let unverified = MacInteractiveSelectedSurfaceActivatorV1(
        performActivation: { unverifiedProbe.perform($0) },
        verifyActivation: { unverifiedProbe.verify($0) },
        maximumVerificationAttempts: 2,
        wait: { unverifiedProbe.waits += 1 }
    )
    await #expect(throws:
        MacInteractiveSelectedSurfaceActivatorErrorV1.verificationFailed
    ) {
        try await unverified.activate(.application(
            processID: 42,
            bundleIdentifier: "example.target"
        ))
    }
    #expect(unverifiedProbe.performed.count == 1)
    #expect(unverifiedProbe.verified.count == 2)
    #expect(unverifiedProbe.waits == 1)
}
#endif
