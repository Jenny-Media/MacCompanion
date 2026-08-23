#if os(macOS)
import CompanionDomain
@testable import CompanionMacApplicationPlatform
import Foundation
import Testing

@available(macOS 26.0, *)
private enum ActivityIndicatorProbeErrorV1: Error {
    case rejected
}

@available(macOS 26.0, *)
@MainActor
@Test func activityIndicatorIsNamedRevisionedAndIdempotent() async throws {
    let generation = UUID()
    let sessionID = UUID()
    let indicator = MacInteractiveActivityIndicatorV1(
        menuAppGeneration: generation
    )
    let name = try DeviceDisplayName("Jenny's iPhone")

    let first = try await indicator.showInteractiveIndicator(
        deviceDisplayName: name,
        interactiveSessionID: sessionID
    )
    let replay = try await indicator.showInteractiveIndicator(
        deviceDisplayName: name,
        interactiveSessionID: sessionID
    )
    #expect(first == replay)
    #expect(first.menuAppGeneration == generation)
    #expect(first.menuAppRevision == 1)
    #expect(indicator.phase == .active)
    #expect(indicator.deviceDisplayName == name.rawValue)
    #expect(indicator.interactiveSessionID == sessionID)
    #expect(indicator.updateControlState == .active)

    await #expect(
        throws: MacInteractiveActivityIndicatorErrorV1.alreadyVisible
    ) {
        try await indicator.showInteractiveIndicator(
            deviceDisplayName: name,
            interactiveSessionID: UUID()
        )
    }

    try await indicator.clearInteractiveIndicator()
    try await indicator.clearInteractiveIndicator()
    #expect(indicator.phase == .inactive)
    #expect(indicator.deviceDisplayName == nil)
    #expect(indicator.interactiveSessionID == nil)
    #expect(indicator.updateControlState == .inactive)

    let replacement = try await indicator.showInteractiveIndicator(
        deviceDisplayName: name,
        interactiveSessionID: UUID()
    )
    #expect(replacement.menuAppRevision == 3)
}

@available(macOS 26.0, *)
@MainActor
@Test func activityIndicatorStopRemainsVisibleUntilCleanupClears()
    async throws
{
    let indicator = MacInteractiveActivityIndicatorV1()
    _ = try await indicator.showInteractiveIndicator(
        deviceDisplayName: try DeviceDisplayName("Test iPhone"),
        interactiveSessionID: UUID()
    )
    indicator.installStopAction { [weak indicator] in
        #expect(indicator?.phase == .stopping)
        #expect(indicator?.updateControlState == .cleanupUncertain)
        try await indicator?.clearInteractiveIndicator()
    }

    try await indicator.requestStop()
    #expect(indicator.phase == .inactive)
}

@available(macOS 26.0, *)
@MainActor
@Test func activityIndicatorFailedStopRestoresVisibleActiveState()
    async throws
{
    let indicator = MacInteractiveActivityIndicatorV1()
    let sessionID = UUID()
    _ = try await indicator.showInteractiveIndicator(
        deviceDisplayName: try DeviceDisplayName("Test iPad"),
        interactiveSessionID: sessionID
    )
    indicator.installStopAction {
        throw ActivityIndicatorProbeErrorV1.rejected
    }

    await #expect(throws: ActivityIndicatorProbeErrorV1.self) {
        try await indicator.requestStop()
    }
    #expect(indicator.phase == .active)
    #expect(indicator.isVisible)
    #expect(indicator.interactiveSessionID == sessionID)
}
#endif
