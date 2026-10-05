#if os(macOS)
import CompanionDomain
import CompanionIPC
import CompanionInteractiveRuntime
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionTestSupport
@testable import CompanionMacApplicationPlatform
import Foundation
import Testing

private func screenSharingCommand() throws -> InteractiveRuntimeInstallCommandV0 {
    let classes: Set<SurfaceInteractionClass> = [.view, .pointer, .keyboard, .text]
    let lease = try InteractiveExecutionLease(leaseID: UUID(), hostID: UUID(), deviceID: UUID(),
        interactiveSessionID: UUID(), authorizationEpoch: .init(rawValue: 1), selectedDisplayID: UUID(),
        surfaceID: UUID(), surfaceRevision: .init(rawValue: 1), coordinateRevision: .init(rawValue: 1),
        allowedInteractionClasses: classes, renewalCounter: 0,
        issuedAtMonotonicNanoseconds: 1_000_000_000, expiresAtMonotonicNanoseconds: 5_000_000_000)
    let descriptor = try AdaptiveSurfaceDescriptor(interactiveSessionID: lease.interactiveSessionID,
        authorizationEpoch: lease.authorizationEpoch, surfaceID: lease.surfaceID, kind: .desktop,
        surfaceRevision: .init(rawValue: 1), coordinateSpaceRevision: .init(rawValue: 1),
        encodedWidth: 100, encodedHeight: 100, logicalWidthPoints: 100, logicalHeightPoints: 100,
        interactionClasses: classes, privacyProfile: .visualOnly, metadataFields: [],
        createdAtMonotonicMilliseconds: 1_000, expiresAtMonotonicMilliseconds: 10_000)
    return try InteractiveRuntimeInstallCommandV0(commandID: UUID(), lease: lease,
        deviceDisplayName: .init("Test iPhone"), surfaceDescriptor: descriptor,
        sessionDeadlineMonotonicNanoseconds: 20_000_000_000)
}

private func screenSharingRenewal(_ command: InteractiveRuntimeInstallCommandV0) throws -> InteractiveRuntimeLeaseRenewalV0 {
    let current = command.lease
    return try .init(commandID: UUID(), previousLeaseID: current.leaseID,
        replacement: InteractiveExecutionLease(leaseID: UUID(), hostID: current.hostID, deviceID: current.deviceID,
            interactiveSessionID: current.interactiveSessionID, authorizationEpoch: current.authorizationEpoch,
            selectedDisplayID: current.selectedDisplayID, surfaceID: current.surfaceID,
            surfaceRevision: current.surfaceRevision, coordinateRevision: current.coordinateRevision,
            allowedInteractionClasses: Set(current.allowedInteractionClasses), renewalCounter: 1,
            issuedAtMonotonicNanoseconds: 3_000_000_000, expiresAtMonotonicNanoseconds: 7_000_000_000))
}

@available(macOS 26.0, *)
@Test func screenSharingRuntimeIndexedLeaseAdmissionAndRetirement() async throws {
    struct Profile: Decodable {
        struct Case: Decodable, Sendable { let name: String; let allowed: Bool }
        let hostRuntimeCases: [Case]
    }
    let profile = try JSONDecoder().decode(Profile.self, from: Data(contentsOf:
        FixturePaths.authoritativeFixtures().appendingPathComponent("vnc-desktop-tunnel-v0.1.json")))
    for item in profile.hostRuntimeCases {
        let command = try screenSharingCommand()
        let adapter = MacScreenSharingLeaseAdapterV1(screenPermission: { item.name != "screen-permission-denied" })
        var accepted = true
        do {
            switch item.name {
            case "current-desktop-lease", "screen-permission-denied":
                #expect(try await adapter.startInteractiveCapture(command) == Set(command.lease.allowedInteractionClasses))
            case "duplicate-active-install":
                _ = try await adapter.startInteractiveCapture(command)
                _ = try await adapter.startInteractiveCapture(command)
            case "exact-renewal", "stale-renewal", "renewal-after-stop":
                _ = try await adapter.startInteractiveCapture(command)
                let renewal = try screenSharingRenewal(command)
                if item.name == "renewal-after-stop" { try await adapter.stopInteractiveCapture() }
                try await adapter.adoptInteractiveLeaseRenewal(renewal)
                if item.name == "stale-renewal" { try await adapter.adoptInteractiveLeaseRenewal(renewal) }
            default:
                Issue.record("Unexercised authoritative VNC runtime case")
            }
        } catch { accepted = false }
        #expect(accepted == item.allowed)
        try await adapter.stopInteractiveCapture()
    }
}

private actor ScreenSharingRuntimeEffects: InteractiveRuntimeIndicatorControllingV0,
    InteractiveRuntimeInputControllingV0, InteractiveRuntimeFrameControllingV0,
    InteractiveRuntimeInputPostingV0 {
    var visible = false
    var releases = 0
    func showInteractiveIndicator(deviceDisplayName: DeviceDisplayName, interactiveSessionID: UUID) throws -> InteractiveRuntimeIndicatorSnapshotV0 {
        visible = true
        return try .init(menuAppGeneration: UUID(), menuAppRevision: 1)
    }
    func clearInteractiveIndicator() { visible = false }
    func releaseAllInteractiveInput() { releases += 1 }
    func blankLastInteractiveFrame() {}
    func postInteractiveInput(_ envelope: InteractiveInputEnvelope) throws {
        throw InteractiveMenuRuntimeErrorV0.interactionClassDenied
    }
}

@available(macOS 26.0, *)
@Test func screenSharingRuntimeProducesNoLegacyMediaAndPreservesLeaseExpiry() async throws {
    let effects = ScreenSharingRuntimeEffects()
    let adapter = MacScreenSharingLeaseAdapterV1(screenPermission: { true })
    let queue = try BoundedInteractiveMediaQueueV0()
    let runtime = InteractiveMenuRuntimeOwnerV0(indicator: effects, capture: adapter,
        input: effects, frame: effects, inputPoster: effects, mediaQueue: queue)
    let command = try screenSharingCommand()
    _ = try await runtime.install(command, nowMonotonicNanoseconds: 1_000_000_000)
    #expect(await effects.visible)
    #expect(queue.dequeue() == nil)
    let renewal = try screenSharingRenewal(command)
    try await runtime.renew(renewal, nowMonotonicNanoseconds: 3_000_000_000)
    // The old lease has expired, while the exact adopted replacement is current.
    #expect(try await runtime.expireLeaseIfRequired(nowMonotonicNanoseconds: 5_000_000_000) == false)
    #expect(queue.dequeue() == nil)
    #expect(try await runtime.expireLeaseIfRequired(nowMonotonicNanoseconds: 7_000_000_000))
    #expect(await runtime.state() == .idle)
    #expect(await effects.visible == false)
    #expect(await effects.releases == 1)
    await #expect(throws: (any Error).self) { try await adapter.adoptInteractiveLeaseRenewal(renewal) }
}
#endif
