#if !DEBUG || !os(macOS)
#error("Disposable Interactive menu is macOS Debug only")
#endif
import CompanionDomain
import CompanionHostPlatform
import CompanionIPC
import CompanionInteractiveRuntime
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionLocalXPCPlatform
import CompanionMacApplicationPlatform
import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

private func probeFence(_ lease: InteractiveExecutionLease) -> InteractiveCommandFence {
    .init(leaseID: lease.leaseID, hostID: lease.hostID, deviceID: lease.deviceID,
          interactiveSessionID: lease.interactiveSessionID, authorizationEpoch: lease.authorizationEpoch,
          selectedDisplayID: lease.selectedDisplayID, surfaceID: lease.surfaceID,
          surfaceRevision: lease.surfaceRevision, coordinateRevision: lease.coordinateRevision)
}

private struct ProbePublisherRuntime: InteractiveMediaRuntimePublishingV0 {
    let runtime: InteractiveMenuRuntimeOwnerV0
    func publishMedia(_ action: InteractiveRuntimeMediaActionV0,
                      nowMonotonicNanoseconds: UInt64) async throws {
        try await runtime.publishMedia(action, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
    }
}

/// Disposable lab latch for a real normal-client background/selection race.
/// It owns no approval or capture and times out instead of retaining work.
actor ProbeNativeSelectionHold {
    enum Failure: Error { case invalidPhase, timeout }
    private var armed = false
    private var waiting = false
    func arm() throws {
        guard !armed, !waiting else { throw Failure.invalidPhase }
        armed = true
    }
    func requireWaiting() async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !waiting, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard waiting else { throw Failure.timeout }
    }
    func release() { armed = false }
    func waitIfArmed() async throws {
        guard armed else { return }
        waiting = true
        defer { armed = false; waiting = false }
        let deadline = ContinuousClock.now + .seconds(8)
        while armed, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        guard !armed else { throw Failure.timeout }
    }
}

/// Keeps the production lease/runtime adapter while supplying one generated,
/// privacy-filtered editable focus. This exercises the signed focus/Smart Zoom
/// and keyboard paths without querying Accessibility or naming a real app.
/// Omitting this authenticated method makes the Agent invalidate the entire
/// menu generation when its automatic focus observer first samples.
@available(macOS 26.0, *)
private struct ProbeInteractiveLeaseHandler: MacLocalXPCInteractiveLeaseHandlingV1 {
    let base: MacInteractiveLeaseRuntimeAdapterV1
    let effects: ProbeInteractiveEffects
    let focus: SurfaceFocus
    let syntheticNativeDesktopSelection: Bool
    let displaySelection: MacInteractiveOpaqueDisplaySelectionV1?
    let surfaceTargets: MacInteractiveSurfaceTargetOwnerV1?
    let selectionHold: ProbeNativeSelectionHold

    init(base: MacInteractiveLeaseRuntimeAdapterV1, effects: ProbeInteractiveEffects,
         syntheticNativeDesktopSelection: Bool = false,
         displaySelection: MacInteractiveOpaqueDisplaySelectionV1? = nil,
         surfaceTargets: MacInteractiveSurfaceTargetOwnerV1? = nil,
         selectionHold: ProbeNativeSelectionHold) throws {
        self.base = base
        self.effects = effects
        self.syntheticNativeDesktopSelection = syntheticNativeDesktopSelection
        self.displaySelection = displaySelection
        self.surfaceTargets = surfaceTargets
        self.selectionHold = selectionHold
        focus = try SurfaceFocus(
            token: UUID(),
            revision: .init(rawValue: 1),
            category: .text,
            bounds: NormalizedSurfaceRect(
                x: 8_192,
                y: 12_288,
                width: 32_768,
                height: 16_384
            ),
            editable: true,
            secure: false
        )
    }

    func prepareInitialInteractiveDesktop(
        _ command: LocalInteractiveInitialDesktopPreparationCommandV1,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
        try await base.prepareInitialInteractiveDesktop(
            command, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
    }

    func installInteractiveLease(
        _ command: InteractiveRuntimeInstallCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeInstallReceiptV0 {
        FileHandle.standardError.write(Data("native-bootstrap-runtime-install-entered\n".utf8))
        do {
            let receipt = try await base.installInteractiveLease(command, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
            try await surfaceTargets?.bindInstalledLease(command)
            FileHandle.standardError.write(Data("native-bootstrap-runtime-install-completed\n".utf8))
            return receipt
        } catch {
            FileHandle.standardError.write(Data("native-bootstrap-runtime-install-failed type=\(String(reflecting: type(of: error)))\n".utf8))
            throw error
        }
    }

    func renewInteractiveLease(
        _ renewal: InteractiveRuntimeLeaseRenewalV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws {
        try await base.renewInteractiveLease(
            renewal, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
        try await surfaceTargets?.adoptRenewedLease(renewal)
    }

    func revokeInteractiveLease(
        _ command: InteractiveRuntimeRevokeCommandV0
    ) async throws -> InteractiveRuntimeRevokedReceiptV0 {
        try await base.revokeInteractiveLease(command)
    }

    func interactiveSurfaceTargets(
        _ command: LocalInteractiveSurfaceTargetsCommandV1,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> LocalInteractiveSurfaceTargetsReceiptV1 {
        if syntheticNativeDesktopSelection {
            let now = Int64(nowMonotonicNanoseconds / 1_000_000)
            let snapshot = try AdaptiveSurfaceTargetInventorySnapshotV0(
                interactiveSessionID: command.interactiveSessionID,
                authorizationEpoch: command.authorizationEpoch,
                revision: 1, createdAtMonotonicMilliseconds: now,
                expiresAtMonotonicMilliseconds: now + 10_000, candidates: [])
            let receipt = try LocalInteractiveSurfaceTargetsReceiptV1(
                correlationID: command.commandID, snapshot: snapshot)
            try receipt.validate(against: command)
            return receipt
        }
        return try await base.interactiveSurfaceTargets(
            command, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
    }

    func resolveInteractiveSurface(
        _ command: LocalInteractiveSurfaceResolveCommandV1,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> LocalInteractiveSurfaceResolvedReceiptV1 {
        try await selectionHold.waitIfArmed()
        if syntheticNativeDesktopSelection && command.targetKind == .desktop {
            FileHandle.standardError.write(Data("native-surface-resolve-entered\n".utf8))
            guard let displaySelection,
                  let selectedID = displaySelection.opaqueSelectedDisplayID(),
                  let display = displaySelection.availableDisplays().first(where: { $0.id == selectedID }) else {
                throw LocalInteractiveSurfaceRuntimeErrorV1.invalidCommand
            }
            let profile = try ScreenCaptureKitOpaqueTargetCatalogV0.captureProfile(
                logicalWidth: display.pixelWidth, logicalHeight: display.pixelHeight)
            let now = Int64(nowMonotonicNanoseconds / 1_000_000)
            let descriptor = try AdaptiveSurfaceDescriptor(
                interactiveSessionID: command.interactiveSessionID,
                authorizationEpoch: command.authorizationEpoch,
                surfaceID: UUID(), kind: .desktop,
                surfaceRevision: try command.expectedSurfaceRevision.advanced(),
                coordinateSpaceRevision: try command.expectedCoordinateSpaceRevision.advanced(),
                encodedWidth: UInt16(profile.width), encodedHeight: UInt16(profile.height),
                logicalWidthPoints: UInt32(display.layoutWidth),
                logicalHeightPoints: UInt32(display.layoutHeight),
                interactionClasses: [.view, .pointer, .keyboard, .text],
                privacyProfile: .visualOnly, metadataFields: [],
                createdAtMonotonicMilliseconds: now,
                expiresAtMonotonicMilliseconds: now + 60_000)
            let receipt = try LocalInteractiveSurfaceResolvedReceiptV1(
                correlationID: command.commandID, descriptor: descriptor)
            try receipt.validate(against: command)
            FileHandle.standardError.write(Data("native-surface-resolve-completed\n".utf8))
            return receipt
        }
        if command.targetKind == .focusedRegion {
            guard let targetToken = command.targetToken else {
                throw LocalInteractiveSurfaceRuntimeErrorV1.invalidCommand
            }
            let nextSurfaceRevision = try command.expectedSurfaceRevision.advanced()
            let nextCoordinateRevision = try command
                .expectedCoordinateSpaceRevision.advanced()
            let nowMilliseconds = Int64(
                min(nowMonotonicNanoseconds / 1_000_000, UInt64(Int64.max - 10_000))
            )
            let descriptor = try AdaptiveSurfaceDescriptor(
                interactiveSessionID: command.interactiveSessionID,
                authorizationEpoch: command.authorizationEpoch,
                surfaceID: targetToken,
                kind: .focusedRegion,
                surfaceRevision: nextSurfaceRevision,
                coordinateSpaceRevision: nextCoordinateRevision,
                applicationToken: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!,
                parentSurfaceID: command.currentSurfaceID,
                fallbackSurfaceID: command.currentSurfaceID,
                encodedWidth: 64,
                encodedHeight: 48,
                logicalWidthPoints: 640,
                logicalHeightPoints: 480,
                interactionClasses: [.view, .pointer, .keyboard, .text],
                privacyProfile: .assistedVisual,
                metadataFields: [.focusCategory, .focusBounds, .editable, .secure],
                focus: focus,
                createdAtMonotonicMilliseconds: nowMilliseconds,
                expiresAtMonotonicMilliseconds: nowMilliseconds + 10_000
            )
            let receipt = try LocalInteractiveSurfaceResolvedReceiptV1(
                correlationID: command.commandID,
                descriptor: descriptor
            )
            try receipt.validate(against: command)
            return receipt
        }
        return try await base.resolveInteractiveSurface(
            command, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
    }

    func prepareInteractiveSurfaceTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeSurfaceTransitionReceiptV0 {
        FileHandle.standardError.write(Data("native-surface-prepare-entered\n".utf8))
        do {
            if let surfaceTargets {
                _ = try await surfaceTargets.takePreparedSurface(for: command)
            }
            let receipt = try await base.prepareInteractiveSurfaceTransition(
                command, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
            try await surfaceTargets?.commit(command)
            FileHandle.standardError.write(Data("native-surface-prepare-completed\n".utf8))
            return receipt
        } catch {
            await surfaceTargets?.invalidate()
            FileHandle.standardError.write(Data("native-surface-prepare-failed type=\(String(reflecting: type(of: error)))\n".utf8))
            throw error
        }
    }

    func acknowledgeInteractiveSurface(
        _ command: InteractiveRuntimeSurfaceAcknowledgementCommandV0,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> InteractiveRuntimeSurfaceAcknowledgementReceiptV0 {
        let receipt = try await base.acknowledgeInteractiveSurface(
            command, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
        await effects.recordSurfaceAcknowledgement()
        return receipt
    }

    func terminateInteractiveSurfaceFailure(
        _ command: LocalInteractiveSurfaceFailureCommandV1
    ) async throws -> LocalInteractiveSurfaceFailureReceiptV1 {
        try await base.terminateInteractiveSurfaceFailure(command)
    }

    func interactiveFocusSnapshot(
        _ command: LocalInteractiveFocusSnapshotCommandV1,
        nowMonotonicNanoseconds _: UInt64
    ) async throws -> LocalInteractiveFocusSnapshotReceiptV1 {
        let candidate = try LocalInteractiveFocusCandidateV1(
            recommendedTargetKind: .focusedRegion,
            focus: focus,
            inputPaused: false,
            reason: .verifiedFocus,
            validForMilliseconds: 1_000)
        let receipt = LocalInteractiveFocusSnapshotReceiptV1(
            correlationID: command.commandID,
            command: command,
            candidate: candidate)
        try receipt.validate(against: command)
        return receipt
    }

    func invalidateAgentAuthority() async {
        await base.invalidateAgentAuthority()
    }

    func nativeBackend(_ command: LocalInteractiveNativeBackendCommandV1,
        nowMonotonicNanoseconds: UInt64) async throws -> LocalInteractiveNativeBackendReceiptV1 {
        FileHandle.standardError.write(Data("native-local-backend-\(command.operation.rawValue)\n".utf8))
        do {
            let receipt = try await base.nativeBackend(command, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
            if command.operation == .retire {
                FileHandle.standardError.write(Data("native-local-backend-retire-completed\n".utf8))
            }
            if command.operation == .present, receipt.inputAdmitted == true {
                await effects.recordNativePresentation()
                FileHandle.standardError.write(Data("native-local-presentation-input-admitted\n".utf8))
            }
            return receipt
        }
        catch {
            let closedCase = (error as? LocalInteractiveNativeBackendErrorV1)
                .map { String(describing: $0) } ?? "other"
            FileHandle.standardError.write(Data("native-local-backend-failed type=\(String(reflecting: type(of: error))) case=\(closedCase)\n".utf8))
            if command.operation == .prepare, let surfaceTargets {
                do {
                    let surface = try await surfaceTargets.nativeCaptureTarget(
                        scope: command.scope,
                        nowMonotonicNanoseconds: DispatchTime.now().uptimeNanoseconds)
                    FileHandle.standardError.write(Data("native-selected-capture-retained=\(surface != nil)\n".utf8))
                    if let surface {
                        _ = try MacInteractiveNativeCaptureGeometryV1.readSelectedSurface(
                            surface, scope: command.scope)
                        FileHandle.standardError.write(Data("native-selected-capture-geometry-current\n".utf8))
                        if case let .application(processID, bundleID) = surface.localActivationTarget {
                            let running = NSRunningApplication(processIdentifier: processID)
                            FileHandle.standardError.write(Data(
                                "native-selected-capture-process-current=\(running != nil && running?.isTerminated == false) bundle-current=\(running?.bundleIdentifier == bundleID) launch-current=\(running?.launchDate != nil)\n".utf8))
                        }
                        _ = try MacManagedNativeSelectedCaptureV1(
                            surface: surface, scope: command.scope,
                            selectedPhysicalDisplayID: CGMainDisplayID())
                        FileHandle.standardError.write(Data("native-selected-capture-context-current\n".utf8))
                    }
                } catch {
                    FileHandle.standardError.write(Data("native-selected-capture-diagnostic-failed type=\(String(reflecting: type(of: error)))\n".utf8))
                }
            }
            throw error
        }
    }

    func interactiveDisplayCatalog(_ command: LocalInteractiveDisplayCatalogCommandV1,
        nowMonotonicNanoseconds: UInt64) async throws -> LocalInteractiveDisplayCatalogReceiptV1 {
        try await base.interactiveDisplayCatalog(command, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
    }

    func selectInteractiveDisplay(_ command: LocalInteractiveDisplaySelectCommandV1,
        nowMonotonicNanoseconds: UInt64) async throws -> LocalInteractiveDisplaySelectedReceiptV1 {
        try await base.selectInteractiveDisplay(command, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
    }

    func nativeRuntimeSnapshot(_ command: LocalInteractiveNativeSnapshotCommandV1,
        nowMonotonicNanoseconds: UInt64) async throws -> LocalInteractiveNativeSnapshotReceiptV1 {
        FileHandle.standardError.write(Data("native-local-snapshot-request admission=\(await effects.nativeAdmissionPhase())\n".utf8))
        return try await base.nativeRuntimeSnapshot(command, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
    }

    func makeWebRTCOffer(
        _ command: LocalInteractiveWebRTCOfferCommandV1,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> LocalInteractiveWebRTCOfferReceiptV1 {
        try await base.makeWebRTCOffer(
            command, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
    }

    func acceptWebRTCAnswer(
        _ command: LocalInteractiveWebRTCAnswerCommandV1,
        nowMonotonicNanoseconds: UInt64
    ) async throws {
        try await base.acceptWebRTCAnswer(
            command, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
    }

    func closeWebRTC(_ command: LocalInteractiveWebRTCCloseCommandV1) async throws {
        try await base.closeWebRTC(command)
    }
}

private final class ProbeInteractiveInputSink: InteractiveRuntimeInputPostingV0, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func postInteractiveInput(
        _ envelope: InteractiveInputEnvelope
    ) async throws {
        lock.withLock { count += 1 }
    }
    func postInteractiveInput(_ envelope: InteractiveInputEnvelope,
        nativeAuthorization: InteractiveRuntimeNativeInputPostingAuthorizationV0,
        beforeDeadlineNanoseconds: UInt64) async throws {
        try await nativeAuthorization.perform(envelope, beforeDeadlineNanoseconds: beforeDeadlineNanoseconds) {
            self.lock.withLock { self.count += 1 }
        }
    }
    func snapshot() -> Int { lock.withLock { count } }
}

/// Explicit substitutes for display/capture/indicator/input. No screen access,
/// CGEvent, user app, permission, or real frame is involved in this lease lane.
@available(macOS 26.0, *)
actor ProbeInteractiveEffects: InteractiveRuntimeIndicatorControllingV0,
    InteractiveRuntimeCaptureControllingV0, InteractiveRuntimeInputControllingV0,
    InteractiveRuntimeFrameControllingV0, MacInteractiveInitialDesktopPreparingV1 {
    enum Failure: Error { case unsupported, badBinding }
    struct Snapshot: Sendable {
        let started: Int
        let renewed: Int
        let stopped: Int
        let released: Int
        let blanked: Int
        let cleared: Int
        let encodedFrames: Int
        let acknowledgements: Int
    }
    nonisolated let menuGeneration = UUID()
    nonisolated let displayID: UUID
    private var started = 0, renewed = 0, stopped = 0, released = 0, blanked = 0, cleared = 0
    private var encodedFrames = 0
    private var acknowledgements = 0
    private var nativePresentations = 0
    private var lease: InteractiveExecutionLease?
    private weak var runtime: InteractiveMenuRuntimeOwnerV0?
    private let queue: BoundedInteractiveMediaQueueV0
    private let streamsMedia: Bool
    private let bootstrapOnly: Bool
    private let encodedWidth: UInt16
    private let encodedHeight: UInt16
    private var publisher: VideoToolboxInteractiveMediaPublisherV0?
    private var encoder: VideoToolboxH264EncoderOwnerV0?
    private var encoderGeneration: UUID?
    private var frames: Task<Void, Never>?
    private var pendingTransition: InteractiveRuntimeSurfaceTransitionCommandV0?
    private var pauseDesktop = false
    private(set) var desktopIsWaiting = false
    private var displayAdmissionUpdate: (@Sendable (UUID) async throws -> Void)?
    func bindDisplayAdmissionUpdate(_ update: @escaping @Sendable (UUID) async throws -> Void) {
        displayAdmissionUpdate = update
    }
    func updateSelectedDisplay(_ displayID: UUID) async throws {
        guard let displayAdmissionUpdate else { throw Failure.badBinding }
        try await displayAdmissionUpdate(displayID)
    }
    func pauseNextDesktop() { pauseDesktop = true }
    func resumeDesktop() { pauseDesktop = false }

    init(queue: BoundedInteractiveMediaQueueV0, streamsMedia: Bool, bootstrapOnly: Bool = false, displayID: UUID = UUID(), encodedWidth: UInt16 = 64, encodedHeight: UInt16 = 48) {
        self.bootstrapOnly = bootstrapOnly
        self.encodedWidth = encodedWidth; self.encodedHeight = encodedHeight
        self.displayID = displayID; self.queue = queue; self.streamsMedia = streamsMedia
    }
    func bind(_ runtime: InteractiveMenuRuntimeOwnerV0) { self.runtime = runtime }
    func snapshot() -> Snapshot {
        .init(started: started, renewed: renewed, stopped: stopped,
              released: released, blanked: blanked, cleared: cleared,
              encodedFrames: encodedFrames, acknowledgements: acknowledgements)
    }
    func nativeAdmissionPhase() async -> String { String(describing: await runtime?.surfaceAdmissionState()) }
    func recordNativePresentation() { nativePresentations += 1 }
    func nativePresentationCount() -> Int { nativePresentations }
    func recordSurfaceAcknowledgement() {
        acknowledgements += 1
        if bootstrapOnly {
            // Generated pixels only bootstrap the authenticated native lane.
            // Keep queued records available to the real role/XPC drain; the
            // managed host becomes the actual continuing video source.
            frames?.cancel(); frames = nil
            retireEncoderWithoutWaitingForPublication()
            encoder = nil
        }
    }
    func prepareInitialInteractiveDesktop(_ command: LocalInteractiveInitialDesktopPreparationCommandV1,
        nowMonotonicNanoseconds: UInt64) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
        guard command.selectedDisplayID == displayID else { throw Failure.badBinding }
        if pauseDesktop {
            desktopIsWaiting = true
            defer { desktopIsWaiting = false }
            let deadline = ContinuousClock.now + .seconds(2)
            while pauseDesktop, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            guard !pauseDesktop else { throw Failure.unsupported }
        }
        let now = Int64(nowMonotonicNanoseconds / 1_000_000)
        return try .init(correlationID: command.commandID, descriptor: AdaptiveSurfaceDescriptor(
            interactiveSessionID: command.interactiveSessionID, authorizationEpoch: command.authorizationEpoch,
            surfaceID: UUID(), kind: .desktop, surfaceRevision: .init(rawValue: 1),
            coordinateSpaceRevision: .init(rawValue: 1), encodedWidth: encodedWidth, encodedHeight: encodedHeight,
            logicalWidthPoints: UInt32(encodedWidth), logicalHeightPoints: UInt32(encodedHeight),
            interactionClasses: Set(command.interactionClasses), privacyProfile: .visualOnly,
            metadataFields: [], createdAtMonotonicMilliseconds: now, expiresAtMonotonicMilliseconds: now + 60_000))
    }
    func showInteractiveIndicator(deviceDisplayName: DeviceDisplayName,
        interactiveSessionID: UUID) throws -> InteractiveRuntimeIndicatorSnapshotV0 {
        try .init(menuAppGeneration: menuGeneration, menuAppRevision: 1)
    }
    func clearInteractiveIndicator() { cleared += 1 }
    func startInteractiveCapture(_ command: InteractiveRuntimeInstallCommandV0) async throws -> Set<SurfaceInteractionClass> {
        guard lease == nil, command.lease.selectedDisplayID == displayID else { throw Failure.badBinding }
        lease = command.lease
        started += 1
        if streamsMedia { try await startMedia(command) }
        return Set(command.surfaceDescriptor.interactionClasses)
    }
    func adoptInteractiveLeaseRenewal(_ renewal: InteractiveRuntimeLeaseRenewalV0) async throws {
        guard let lease else { throw Failure.badBinding }
        try renewal.validate(current: lease)
        if let publisher {
            guard await publisher.adoptLeaseRenewal(to: try .init(
                fence: probeFence(renewal.replacement), descriptor: try currentDescriptor())) else {
                throw Failure.badBinding
            }
        }
        self.lease = renewal.replacement
        renewed += 1
    }
    func prepareInteractiveCaptureTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0
    ) async throws -> Set<SurfaceInteractionClass> {
        FileHandle.standardError.write(Data("native-capture-transition-prepare-entered\n".utf8))
        guard let lease, publisher != nil, pendingTransition == nil,
              command.previousLeaseID == lease.leaseID,
              command.replacement.interactiveSessionID == lease.interactiveSessionID,
              command.descriptor.surfaceID == command.replacement.surfaceID else {
            throw Failure.badBinding
        }
        frames?.cancel()
        frames = nil
        retireEncoderWithoutWaitingForPublication()
        encoder = nil
        pendingTransition = command
        FileHandle.standardError.write(Data("native-capture-transition-prepare-completed\n".utf8))
        return Set(command.descriptor.interactionClasses)
    }
    func activatePreparedInteractiveCaptureTransition(
        _ command: InteractiveRuntimeSurfaceTransitionCommandV0,
        mediaSequenceBeforeTransition: UInt64
    ) async throws {
        FileHandle.standardError.write(Data("native-capture-transition-activate-entered\n".utf8))
        guard pendingTransition == command, publisher != nil, let runtime else {
            throw Failure.badBinding
        }
        let replacement = try InteractiveMediaPublicationBindingV0(
            fence: probeFence(command.replacement),
            descriptor: command.descriptor
        )
        // Do not await the retired publisher here: an in-flight sample may be
        // awaiting this same runtime actor. The replacement publisher resumes
        // the exact media sequence and emits its discontinuity with its first
        // clean frame, which is the transition-safe path provided by the
        // production media publisher.
        let replacementPublisher = VideoToolboxInteractiveMediaPublisherV0(
            binding: replacement,
            runtime: ProbePublisherRuntime(runtime: runtime),
            resumingAfterMediaSequence: mediaSequenceBeforeTransition
        )
        publisher = replacementPublisher
        lease = command.replacement
        descriptor = command.descriptor
        try startEncoderAndFrames(
            publisher: replacementPublisher,
            descriptor: command.descriptor
        )
        pendingTransition = nil
        FileHandle.standardError.write(Data("native-capture-transition-activate-completed\n".utf8))
    }
    func stopInteractiveCapture() async {
        frames?.cancel(); frames = nil
        retireEncoderWithoutWaitingForPublication()
        encoder = nil; publisher = nil
        pendingTransition = nil; descriptor = nil; lease = nil; stopped += 1
    }
    func releaseAllInteractiveInput() { released += 1 }
    func blankLastInteractiveFrame() { _ = queue.purge(); blanked += 1 }

    private var descriptor: AdaptiveSurfaceDescriptor?
    private func currentDescriptor() throws -> AdaptiveSurfaceDescriptor {
        guard let descriptor else { throw Failure.badBinding }
        return descriptor
    }
    private func startMedia(_ command: InteractiveRuntimeInstallCommandV0) async throws {
        guard let runtime else { throw Failure.badBinding }
        descriptor = command.surfaceDescriptor
        let publisher = VideoToolboxInteractiveMediaPublisherV0(
            binding: try .init(fence: probeFence(command.lease), descriptor: command.surfaceDescriptor),
            runtime: ProbePublisherRuntime(runtime: runtime))
        self.publisher = publisher
        try startEncoderAndFrames(
            publisher: publisher,
            descriptor: command.surfaceDescriptor
        )
    }

    private func startEncoderAndFrames(
        publisher: VideoToolboxInteractiveMediaPublisherV0,
        descriptor: AdaptiveSurfaceDescriptor
    ) throws {
        let profile = try VideoToolboxH264EncoderProfileV0(
            capture: .init(width: Int(descriptor.encodedWidth),
                           height: Int(descriptor.encodedHeight),
                           framesPerSecond: 15, queueDepth: 3),
            targetBitrateBitsPerSecond: 350_000,
            keyframeIntervalMilliseconds: 1_000)
        let generation = UUID()
        encoderGeneration = generation
        let encoder = VideoToolboxH264EncoderOwnerV0(
            profile: profile,
            session: try VideoToolboxH264CompressionSessionV0(profile: profile),
            output: { [weak self] sample in
                guard await self?.isCurrentEncoder(generation) == true else {
                    return false
                }
                return await publisher.publish(sample)
            })
        self.encoder = encoder
        frames = Task { [weak self] in
            var sequence: UInt64 = 0
            while !Task.isCancelled {
                do {
                    sequence += 1
                    let pixel = try Self.pixel(width: profile.capture.width,
                                               height: profile.capture.height,
                                               tick: sequence)
                    _ = try await encoder.submit(.init(sourceSequence: sequence, pixelBuffer: pixel,
                        presentationTime: CMTime(value: Int64(DispatchTime.now().uptimeNanoseconds),
                                                timescale: 1_000_000_000),
                        duration: CMTime(value: 1, timescale: 15)))
                    await self?.recordEncodedFrame()
                    try await Task.sleep(for: .milliseconds(66))
                } catch {
                    if !Task.isCancelled {
                        FileHandle.standardError.write(Data("native-bootstrap-frame-submit-failed type=\(String(reflecting: type(of: error)))\n".utf8))
                    }
                    return
                }
            }
        }
    }
    private func isCurrentEncoder(_ generation: UUID) -> Bool {
        encoderGeneration == generation
    }
    /// The encoder serializes publication inside its own actor. Waiting for
    /// `stop()` while the Agent runtime is synchronously asking this seam to
    /// transition can deadlock an in-flight publisher on that runtime actor.
    /// Fence the generation first, then retire outside this call chain.
    private func retireEncoderWithoutWaitingForPublication() {
        encoderGeneration = nil
        guard let encoder else { return }
        Task { await encoder.stop() }
    }
    private func recordEncodedFrame() { encodedFrames += 1 }
    private static func pixel(width: Int, height: Int, tick: UInt64) throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, width, height,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &result) == kCVReturnSuccess, let result else { throw Failure.unsupported }
        CVPixelBufferLockBaseAddress(result, [])
        defer { CVPixelBufferUnlockBaseAddress(result, []) }
        for plane in 0..<2 {
            guard let base = CVPixelBufferGetBaseAddressOfPlane(result, plane) else {
                throw Failure.unsupported
            }
            let rows = CVPixelBufferGetHeightOfPlane(result, plane)
            let stride = CVPixelBufferGetBytesPerRowOfPlane(result, plane)
            memset(base, plane == 0 ? Int32(45 + (tick % 140)) : 128, rows * stride)
        }
        return result
    }
}

@available(macOS 26.0, *)
final class ProbeInteractiveMenu: Sendable {
    enum Scenario: String, Sendable { case lifecycle, admissionRace, menuLoss, revoke, revocationRace, simulator, native, nativeContinuous }
    let scenario: Scenario
    let effects: ProbeInteractiveEffects
    private let input: ProbeInteractiveInputSink
    let mediaQueue: BoundedInteractiveMediaQueueV0
    let runtime: InteractiveMenuRuntimeOwnerV0
    let adapter: MacInteractiveLeaseRuntimeAdapterV1
    let leaseHandler: any MacLocalXPCInteractiveLeaseHandlingV1
    let selectionHold = ProbeNativeSelectionHold()
    init(scenario: Scenario = .lifecycle) throws {
        self.scenario = scenario
        let queue = try BoundedInteractiveMediaQueueV0(maximumRecords: 64,
                                                       maximumBytes: 16 * 1_024 * 1_024)
        let isNative = scenario == .native || scenario == .nativeContinuous
        let selection = isNative ? try MacInteractiveOpaqueDisplaySelectionV1() : nil
        let realSelectedTargets = isNative
            && ProcessInfo.processInfo.environment["MACCOMPANION_NATIVE_LAB_SELECTED_SURFACES"] == "1"
        let surfaceTargets = realSelectedTargets ? MacInteractiveSurfaceTargetOwnerV1() : nil
        let effects = ProbeInteractiveEffects(queue: queue, streamsMedia: scenario == .simulator || isNative,
            bootstrapOnly: scenario == .native,
            displayID: selection?.opaqueSelectedDisplayID() ?? UUID())
        let input = ProbeInteractiveInputSink()
        let runtime = InteractiveMenuRuntimeOwnerV0(indicator: effects, capture: effects,
            input: effects, frame: effects, inputPoster: input, mediaQueue: queue)
        self.effects = effects; self.input = input; mediaQueue = queue
        self.runtime = runtime
        let adapter: MacInteractiveLeaseRuntimeAdapterV1
        if let selection {
            adapter = MacInteractiveLeaseRuntimeAdapterV1(runtime: runtime,
                desktop: ProbeNativeDesktopPreparer(selection: selection, surfaceTargets: surfaceTargets),
                surfaceTargets: surfaceTargets,
                displaySelection: selection, updateSelectedDisplay: { displayID in
                    guard let displayID else { throw ProbeInteractiveEffects.Failure.badBinding }
                    try await effects.updateSelectedDisplay(displayID)
                }, nativeBackendFactory: try ProbeNativeFlow.factory())
        } else {
            adapter = MacInteractiveLeaseRuntimeAdapterV1(runtime: runtime, desktop: effects)
        }
        self.adapter = adapter
        leaseHandler = try ProbeInteractiveLeaseHandler(base: adapter, effects: effects,
            syntheticNativeDesktopSelection: isNative && !realSelectedTargets,
            displaySelection: selection, surfaceTargets: surfaceTargets, selectionHold: selectionHold)
        Task { await effects.bind(runtime) }
    }

    func simulatorSnapshot() async -> (captureActive: Bool, inputEvents: Int,
                                       encodedFrames: Int, runtimeIdle: Bool,
                                       queuedRecords: Int, acknowledgements: Int, nativePresentations: Int) {
        let effects = await effects.snapshot()
        let state = await runtime.state()
        return (effects.started > effects.stopped, input.snapshot(), effects.encodedFrames,
                state == .idle, mediaQueue.status().recordCount, effects.acknowledgements,
                await self.effects.nativePresentationCount())
    }
}

/// Native experiments use the same physical Desktop projection as the normal
/// Mac composition. Generated bootstrap pixels do not define input geometry.
@available(macOS 26.0, *)
private struct ProbeNativeDesktopPreparer: MacInteractiveInitialDesktopPreparingV1 {
    let selection: MacInteractiveOpaqueDisplaySelectionV1
    let surfaceTargets: MacInteractiveSurfaceTargetOwnerV1?
    func prepareInitialInteractiveDesktop(
        _ command: LocalInteractiveInitialDesktopPreparationCommandV1,
        nowMonotonicNanoseconds: UInt64
    ) async throws -> LocalInteractiveInitialDesktopPreparedReceiptV1 {
        let receipt = try await MacInteractiveInitialDesktopPreparerV1(
            displaySelection: selection, surfaceTargets: surfaceTargets
        ).prepareInitialInteractiveDesktop(command, nowMonotonicNanoseconds: nowMonotonicNanoseconds)
        guard let display = selection.availableDisplays().first(where: { $0.id == command.selectedDisplayID }),
              receipt.descriptor.logicalWidthPoints == UInt32(display.layoutWidth),
              receipt.descriptor.logicalHeightPoints == UInt32(display.layoutHeight) else {
            throw ProbeInteractiveEffects.Failure.badBinding
        }
        let profile = try ScreenCaptureKitOpaqueTargetCatalogV0.captureProfile(
            logicalWidth: display.pixelWidth, logicalHeight: display.pixelHeight)
        guard Int(receipt.descriptor.encodedWidth) == profile.width,
              Int(receipt.descriptor.encodedHeight) == profile.height else {
            throw ProbeInteractiveEffects.Failure.badBinding
        }
        FileHandle.standardError.write(Data("native-production-desktop-geometry-verified\n".utf8))
        return receipt
    }
}
