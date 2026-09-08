#if !DEBUG
#error("The loopback test host must never be built for distribution")
#endif
import AppKit
@testable import CompanionAgent
import CompanionDomain
import CompanionHostPlatform
import CompanionIPC
import CompanionInteractiveRuntime
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionSecurity
import CompanionWire
import CoreMedia
import CoreVideo
import CryptoKit
import Foundation
import LiveControlLabSupport
import Network

private func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
private func wall() -> Int64 { Int64(Date().timeIntervalSince1970 * 1_000) }
private func labLog(_ value: String) { FileHandle.standardError.write(Data((value + "\n").utf8)) }
private func fence(_ lease: InteractiveExecutionLease) -> InteractiveCommandFence {
    .init(leaseID: lease.leaseID, hostID: lease.hostID, deviceID: lease.deviceID,
          interactiveSessionID: lease.interactiveSessionID, authorizationEpoch: lease.authorizationEpoch,
          selectedDisplayID: lease.selectedDisplayID, surfaceID: lease.surfaceID,
          surfaceRevision: lease.surfaceRevision, coordinateRevision: lease.coordinateRevision)
}

private struct LabObservedEncoder: ScreenCaptureKitVideoEncodingV0 {
    let encoder: VideoToolboxH264EncoderOwnerV0
    func submit(_ frame: VideoToolboxH264InputFrameV0, forceCleanKeyframe: Bool) async throws -> VideoToolboxH264FrameSubmissionV0 {
        do { return try await encoder.submit(frame, forceCleanKeyframe: forceCleanKeyframe) }
        catch { labLog("REAL_MAC_ENCODE_SUBMIT_FAILED \(error)"); throw error }
    }
    func stop() async { await encoder.stop() }
}

private struct LabObservedPublisherRuntime: InteractiveMediaRuntimePublishingV0 {
    let runtime: InteractiveMenuRuntimeOwnerV0
    func publishMedia(_ action: InteractiveRuntimeMediaActionV0, nowMonotonicNanoseconds: UInt64) async throws {
        do { try await runtime.publishMedia(action, nowMonotonicNanoseconds: nowMonotonicNanoseconds) }
        catch { labLog("LAB_MEDIA_REJECTED type=\(action.header.type.rawValue) reason=\(error)"); throw error }
    }
}

/// No input leaves the test process. Assertions expose counts/matches, not text.
final class InputSink: InteractiveRuntimeInputPostingV0, @unchecked Sendable {
    private let realTarget: RealMacTarget?
    init(realTarget: RealMacTarget?) { self.realTarget = realTarget }
    private let lock = NSLock()
    private var count = 0
    private var text = ""
    private var pointerTransitions = 0
    private var returnTransitions = 0
    func postInteractiveInput(
        _ envelope: InteractiveInputEnvelope
    ) async throws {
        if let realTarget { try realTarget.input.post(envelope); return }
        lock.withLock {
            count += 1
            if case let .text(value) = envelope.input { text += value }
            if case .button = envelope.input { pointerTransitions += 1 }
            if case let .physicalKey(usage, _, _) = envelope.input, usage == 0x28 { returnTransitions += 1 }
        }
    }
    func snapshot() -> (Int, Bool, Bool, Bool, Bool) {
        if let realTarget { return realTarget.feedback.snapshot() }
        return lock.withLock { (count, text.hasPrefix("hello world"), text == "hello worldabc ", pointerTransitions >= 2, returnTransitions >= 2) }
    }
}

actor GeneratedCapture: InteractiveRuntimeCaptureControllingV0,
    InteractiveRuntimeIndicatorControllingV0, InteractiveRuntimeInputControllingV0,
    InteractiveRuntimeFrameControllingV0 {
    var runtime: InteractiveMenuRuntimeOwnerV0?
    var queue: BoundedInteractiveMediaQueueV0?
    private var publisher: VideoToolboxInteractiveMediaPublisherV0?
    private var encoder: VideoToolboxH264EncoderOwnerV0?
    private var frames: Task<Void, Never>?
    private var prepared: InteractiveRuntimeSurfaceTransitionCommandV0?
    private var activeDescriptor: AdaptiveSurfaceDescriptor?
    private let realTarget: RealMacTarget?
    private var stream: ScreenCaptureKitStreamOwnerV0?
    init(realTarget: RealMacTarget?) { self.realTarget = realTarget }
    func bind(_ runtime: InteractiveMenuRuntimeOwnerV0, queue: BoundedInteractiveMediaQueueV0) {
        self.runtime = runtime; self.queue = queue
    }
    func unbind() { runtime = nil; queue = nil }
    func isCaptureActive() -> Bool { stream != nil || frames != nil || encoder != nil }
    func showInteractiveIndicator(deviceDisplayName: DeviceDisplayName, interactiveSessionID: UUID) async throws -> InteractiveRuntimeIndicatorSnapshotV0 {
        try .init(menuAppGeneration: UUID(), menuAppRevision: 1)
    }
    func clearInteractiveIndicator() async throws {}
    func releaseAllInteractiveInput() async throws { try realTarget?.input.release() }
    func blankLastInteractiveFrame() async throws { _ = queue?.purge() }
    func startInteractiveCapture(_ command: InteractiveRuntimeInstallCommandV0) async throws -> Set<SurfaceInteractionClass> {
        try await start(lease: command.lease, descriptor: command.surfaceDescriptor, after: nil)
        return Set(command.lease.allowedInteractionClasses)
    }
    func adoptInteractiveLeaseRenewal(_ renewal: InteractiveRuntimeLeaseRenewalV0) async throws {
        guard let publisher, let descriptor = activeDescriptor,
              await publisher.adoptLeaseRenewal(to: try .init(fence: fence(renewal.replacement), descriptor: descriptor)) else {
            throw LabError.closed
        }
        try realTarget?.input.configure(lease: renewal.replacement, descriptor: descriptor)
    }
    func prepareInteractiveCaptureTransition(_ command: InteractiveRuntimeSurfaceTransitionCommandV0) async throws -> Set<SurfaceInteractionClass> {
        try await stopInteractiveCapture()
        prepared = command
        return Set(command.replacement.allowedInteractionClasses)
    }
    func activatePreparedInteractiveCaptureTransition(_ command: InteractiveRuntimeSurfaceTransitionCommandV0, mediaSequenceBeforeTransition: UInt64) async throws {
        guard prepared == command else { throw LabError.invalidFrame }
        try await start(lease: command.replacement, descriptor: command.descriptor, after: mediaSequenceBeforeTransition)
        prepared = nil
    }
    func stopInteractiveCapture() async throws {
        frames?.cancel(); frames = nil
        if let stream { try await stream.stop(); self.stream = nil }
        await encoder?.stop(); encoder = nil; publisher = nil
    }
    private func start(lease: InteractiveExecutionLease, descriptor: AdaptiveSurfaceDescriptor, after: UInt64?) async throws {
        guard let runtime else { throw LabError.closed }
        activeDescriptor = descriptor
        let profile = try VideoToolboxH264EncoderProfileV0(
            capture: .init(width: Int(descriptor.encodedWidth), height: Int(descriptor.encodedHeight), framesPerSecond: 15, queueDepth: 3),
            targetBitrateBitsPerSecond: 500_000, keyframeIntervalMilliseconds: 1_000
        )
        let publisher = VideoToolboxInteractiveMediaPublisherV0(
            binding: try .init(fence: fence(lease), descriptor: descriptor), runtime: LabObservedPublisherRuntime(runtime: runtime),
            resumingAfterMediaSequence: after
        )
        let encoder = VideoToolboxH264EncoderOwnerV0(
            profile: profile, session: try VideoToolboxH264CompressionSessionV0(profile: profile),
            output: { await publisher.publish($0) },
            terminal: { labLog("LAB_ENCODER_TERMINATED \($0.rawValue)") }
        )
        self.publisher = publisher; self.encoder = encoder
        if let realTarget {
            try realTarget.input.configure(lease: lease, descriptor: descriptor)
            let session = try await realTarget.captureSession(profile: profile.capture, focused: descriptor.kind == .focusedRegion)
            let stream = ScreenCaptureKitStreamOwnerV0(session: session, encoder: LabObservedEncoder(encoder: encoder), terminal: { reason in
                labLog("REAL_MAC_CAPTURE_TERMINATED \(reason.rawValue)")
            })
            self.stream = stream
            try await stream.start()
            return
        }
        frames = Task {
            var sequence: UInt64 = 0
            while !Task.isCancelled {
                do {
                    sequence += 1
                    let pixel = try Self.pixel(width: Int(descriptor.encodedWidth), height: Int(descriptor.encodedHeight), tick: sequence)
                    _ = try await encoder.submit(.init(sourceSequence: sequence, pixelBuffer: pixel,
                        presentationTime: CMTime(value: Int64(now()), timescale: 1_000_000_000),
                        duration: CMTime(value: 1, timescale: 15)))
                    try await Task.sleep(for: .milliseconds(66))
                } catch { return }
            }
        }
    }
    private static func pixel(width: Int, height: Int, tick: UInt64) throws -> CVPixelBuffer {
        var result: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &result) == kCVReturnSuccess,
            let result else { throw LabError.unsupported }
        CVPixelBufferLockBaseAddress(result, [])
        defer { CVPixelBufferUnlockBaseAddress(result, []) }
        for plane in 0..<2 {
            guard let base = CVPixelBufferGetBaseAddressOfPlane(result, plane) else { throw LabError.unsupported }
            let rows = CVPixelBufferGetHeightOfPlane(result, plane)
            let stride = CVPixelBufferGetBytesPerRowOfPlane(result, plane)
            memset(base, plane == 0 ? Int32(40 + (tick % 150)) : 128, rows * stride)
        }
        return result
    }
}

actor HostSession {
    let fixture: LabFixture
    let primary: any LabByteConnection
    let queue: BoundedInteractiveMediaQueueV0
    let capture: GeneratedCapture
    let sink: InputSink
    let realTarget: RealMacTarget?
    let runtime: InteractiveMenuRuntimeOwnerV0
    var input: (any LabByteConnection)?
    var media: (any LabByteConnection)?
    var pump: Task<Void, Never>?
    var renewal: Task<Void, Never>?
    var agentRenewal: AgentInteractiveLeaseRenewalOwnerV1?
    let usesAgentRenewal: Bool
    var renewalFault: String?
    var lease: InteractiveExecutionLease?
    var descriptor: AdaptiveSurfaceDescriptor?
    var commandID: UUID?
    var sessionID = UUID()
    var activationID = WireUUID(UUID())
    var transitionID = WireUUID(UUID())
    var focus: SurfaceFocus?
    var focusTarget = WireUUID(UUID())
    var focusSequence: Int64 = 0
    var serverSequence: Int64 = 0
    var nextInputSequence: UInt64 = 1
    var deadline: UInt64 = 0
    var challenge: WireEnvelope<InteractiveApprovalChallengeBody>?
    var status = LabStatus()
    var closed = false
    var cleanupComplete = false
    var delaySelected = false
    var fallbackNextFocusedSelectionToDesktop = false
    var leaseMutationInProgress = false
    let secondDisplayID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000002"
    )!
    var selectedDisplayID: UUID
    var displayAdmissionRevision: Int64 = 1

    init(fixture: LabFixture, primary: any LabByteConnection, realTarget: RealMacTarget?, usesAgentRenewal: Bool = false) throws {
        self.fixture = fixture; self.primary = primary
        selectedDisplayID = fixture.displayID
        self.usesAgentRenewal = usesAgentRenewal
        self.realTarget = realTarget
        capture = GeneratedCapture(realTarget: realTarget)
        sink = InputSink(realTarget: realTarget)
        status.source = realTarget == nil ? "generated" : "real-mac-window"
        queue = try .init(maximumRecords: 64)
        runtime = .init(indicator: capture, capture: capture, input: capture, frame: capture, inputPoster: sink, mediaQueue: queue)
    }
    func prepare() async {
        await realTarget?.reset()
        await capture.bind(runtime, queue: queue)
    }
    func start() async {
        do { while !closed { try await handle(primary.readFrame()) } }
        catch { if !closed { status.failure = String(describing: error); labLog("LAB_PRIMARY_FAILURE \(error)") }; await close() }
    }
    func attach(_ connection: any LabByteConnection, role: String) async throws {
        guard !closed, status.approvalVerified else { throw LabError.unauthorized }
        if role == "input" {
            guard input == nil else { throw LabError.unauthorized }
            input = connection
            Task {
                do { while !closed { try await acceptInput(connection.readFrame()) } }
                catch { if !closed { status.failure = String(describing: error); labLog("LAB_INPUT_FAILURE \(error)") }; await close() }
            }
        } else {
            guard media == nil else { throw LabError.unauthorized }
            media = connection
            pump = Task {
                do {
                    while !Task.isCancelled {
                        if let record = queue.dequeue() {
                            var bytes = record.header.encode(); bytes.append(record.payload)
                            try await connection.send(bytes)
                            status.mediaRecords += 1
                        } else { try await Task.sleep(for: .milliseconds(3)) }
                    }
                } catch { if !closed { status.failure = String(describing: error) }; await close() }
            }
        }
    }
    func report() async -> LabStatus {
        var value = status
        (value.inputEvents, value.textMatches, value.directTextMatches, value.pointerDelivered, value.returnKeyDelivered) = sink.snapshot()
        value.closed = closed
        value.captureActive = await capture.isCaptureActive()
        if case .idle = await runtime.state() { value.runtimeIdle = true }
        value.queuedMediaRecords = queue.status().recordCount
        value.selectedDisplayOrdinal =
            selectedDisplayID == fixture.displayID ? 1 : 2
        return value
    }
    func control(_ action: String) async throws {
        if action != "status" { labLog("LAB_COMMAND \(action)") }
        switch action {
        case "focus": try await publishFocus()
        case "focus-stale-selection":
            fallbackNextFocusedSelectionToDesktop = true
            try await publishFocus()
        case "focus-churn": try await publishFocusChurn()
        case "desktop-focus-refreshes":
            Task { try? await publishDesktopFocusRefreshes() }
        case "delay-selected": delaySelected = true
        case "drop": await close()
        case "reject-renewal", "expire-renewal":
            guard usesAgentRenewal, agentRenewal != nil, !closed else { throw LabError.closed }
            renewalFault = action
        default: break
        }
    }
    func closeFromAgentScheduler() async {
        // An external close may be waiting for the scheduler itself. Never
        // wait back on that caller: it owns completion in that case.
        guard !closed else { return }
        await close(stopAgentScheduler: false)
    }
    func close(stopAgentScheduler: Bool = true) async {
        if closed {
            while !cleanupComplete { await Task.yield() }
            return
        }
        closed = true
        pump?.cancel(); renewal?.cancel()
        if stopAgentScheduler {
            await agentRenewal?.terminate(interactiveSessionID: sessionID,
                primaryConnectionID: fixture.connectionID, reason: .clientDisconnected)
        }
        while leaseMutationInProgress { await Task.yield() }
        // Close admission through the real serialized runtime before purging.
        // Stopping only the encoder leaves already-scheduled media callbacks
        // authorized to enqueue after the purge.
        do { try await runtime.invalidateAgentAuthority() }
        catch { status.failure = "cleanup: \(error)"; labLog("LAB_CLEANUP_FAILURE \(error)") }
        try? realTarget?.input.release()
        try? await capture.stopInteractiveCapture(); _ = queue.purge()
        await capture.unbind()
        await input?.close(); await media?.close(); await primary.close()
        cleanupComplete = true
    }
    private func reply<B: WireBody>(_ body: B, to requestID: WireUUID) async throws {
        try await primary.sendFrame(WireCodec.encode(WireEnvelope(messageID: WireUUID(UUID()), correlationID: requestID, sentAtUnixMilliseconds: wall(), body: body)))
    }
    private func advance() -> Int64 { serverSequence += 1; return serverSequence }
    private func makeDescriptor(kind: InteractiveSurfaceKind, revision: UInt64, focus: SurfaceFocus? = nil) throws -> AdaptiveSurfaceDescriptor {
        // Odd-sized sources exercise production pre-descriptor encoder sizing.
        let width = kind == .focusedRegion ? 321 : 641
        let height = kind == .focusedRegion ? 241 : 361
        let profile = try ScreenCaptureKitOpaqueTargetCatalogV0.captureProfile(
            logicalWidth: width, logicalHeight: height)
        return try .init(interactiveSessionID: sessionID, authorizationEpoch: .init(rawValue: fixture.authorizationEpoch ?? 1), surfaceID: UUID(), kind: kind,
            surfaceRevision: .init(rawValue: revision), coordinateSpaceRevision: .init(rawValue: revision),
            applicationToken: kind == .focusedRegion ? fixture.hostID : nil,
            parentSurfaceID: kind == .focusedRegion ? descriptor?.surfaceID : nil,
            fallbackSurfaceID: kind == .focusedRegion ? descriptor?.surfaceID : nil,
            encodedWidth: UInt16(profile.width), encodedHeight: UInt16(profile.height),
            logicalWidthPoints: UInt32(width), logicalHeightPoints: UInt32(height),
            interactionClasses: [.view, .pointer, .keyboard, .text], privacyProfile: focus == nil ? .visualOnly : .assistedVisual,
            metadataFields: focus == nil ? [] : [.focusCategory, .focusBounds, .editable, .secure], focus: focus,
            createdAtMonotonicMilliseconds: Int64(now() / 1_000_000), expiresAtMonotonicMilliseconds: Int64(now() / 1_000_000) + 600_000)
    }
    private func makeLease(_ descriptor: AdaptiveSurfaceDescriptor, counter: UInt64) throws -> InteractiveExecutionLease {
        let time = now()
        return try .init(leaseID: UUID(), hostID: fixture.hostID, deviceID: fixture.deviceID, interactiveSessionID: sessionID,
            authorizationEpoch: .init(rawValue: fixture.authorizationEpoch ?? 1), selectedDisplayID: selectedDisplayID, surfaceID: descriptor.surfaceID,
            surfaceRevision: .init(rawValue: descriptor.surfaceRevision.rawValue), coordinateRevision: .init(rawValue: descriptor.coordinateSpaceRevision.rawValue),
            allowedInteractionClasses: Set(descriptor.interactionClasses), renewalCounter: counter,
            issuedAtMonotonicNanoseconds: time, expiresAtMonotonicNanoseconds: min(time + 10_000_000_000, deadline))
    }
    private func handle(_ request: Data) async throws {
        FileHandle.standardError.write(Data("LAB_PRIMARY \(try WireCodec.messageKind(from: request))\n".utf8))
        switch try WireCodec.messageKind(from: request) {
        case .interactiveDisplayCatalogRequest:
            let message = try WireCodec.decode(
                WireEnvelope<InteractiveDisplayCatalogRequestBodyV1>.self,
                from: request
            )
            guard challenge == nil,
                  message.body.authorizationEpoch.rawValue
                    == (fixture.authorizationEpoch ?? 1) else {
                throw LabError.unauthorized
            }
            status.displayCatalogRequests += 1
            try await reply(
                InteractiveDisplayCatalogResponseBodyV1(
                    authorizationEpoch: message.body.authorizationEpoch,
                    admissionRevision: displayAdmissionRevision,
                    selectedDisplayID: WireUUID(selectedDisplayID),
                    validForMilliseconds: 5_000,
                    displays: [
                        try InteractiveDisplayCandidateV1(
                            displayID: WireUUID(fixture.displayID),
                            ordinal: 1,
                            pixelWidth: 1512,
                            pixelHeight: 982,
                            layoutX: 0,
                            layoutY: 0,
                            layoutWidth: 1512,
                            layoutHeight: 982,
                            isMain: true
                        ),
                        try InteractiveDisplayCandidateV1(
                            displayID: WireUUID(secondDisplayID),
                            ordinal: 2,
                            pixelWidth: 2560,
                            pixelHeight: 1440,
                            layoutX: 1512,
                            layoutY: -229,
                            layoutWidth: 2560,
                            layoutHeight: 1440,
                            isMain: false
                        ),
                    ]
                ),
                to: message.messageID
            )
        case .interactiveDisplaySelect:
            let message = try WireCodec.decode(
                WireEnvelope<InteractiveDisplaySelectBodyV1>.self,
                from: request
            )
            guard !status.approvalVerified,
                  challenge == nil,
                  message.body.authorizationEpoch.rawValue
                    == (fixture.authorizationEpoch ?? 1),
                  message.body.expectedAdmissionRevision
                    == displayAdmissionRevision,
                  message.body.displayID.rawValue == fixture.displayID
                    || message.body.displayID.rawValue == secondDisplayID,
                  message.body.displayID.rawValue != selectedDisplayID,
                  displayAdmissionRevision
                    < WireLimits.maximumSafeInteger else {
                throw LabError.unauthorized
            }
            selectedDisplayID = message.body.displayID.rawValue
            displayAdmissionRevision += 1
            try await reply(
                InteractiveDisplaySelectedBodyV1(
                    authorizationEpoch: message.body.authorizationEpoch,
                    admissionRevision: displayAdmissionRevision,
                    selectedDisplayID: message.body.displayID
                ),
                to: message.messageID
            )
        case .interactiveSessionRequest:
            let message = try WireCodec.decode(WireEnvelope<InteractiveSessionRequestBody>.self, from: request)
            let body = try InteractiveApprovalChallengeBody(hostID: WireUUID(fixture.hostID), hostFingerprint: WireFingerprint(fixture.fingerprint),
                clientID: WireUUID(fixture.clientID), primaryConnectionID: WireBytes16(fixture.connectionID), requestID: message.messageID,
                approvalID: WireUUID(UUID()), serverChallenge: WireBytes32(Data(SHA256.hash(data: Data(UUID().uuidString.utf8)))),
                authorizationEpoch: .init(rawValue: fixture.authorizationEpoch ?? 1), grantRevision: .init(rawValue: fixture.grantRevision ?? 1), policyRevision: .init(rawValue: 1),
                selectedDisplayID: WireUUID(selectedDisplayID), initialSurface: .desktop, effects: Set(message.body.effects),
                issuedAtUnixMilliseconds: wall(), expiresAtUnixMilliseconds: wall() + 60_000)
            let envelope = try WireEnvelope(messageID: WireUUID(UUID()), correlationID: message.messageID, sentAtUnixMilliseconds: wall(), body: body)
            challenge = envelope
            try await primary.sendFrame(WireCodec.encode(envelope))
        case .interactiveSessionApprove:
            let proof = try WireCodec.decode(WireEnvelope<InteractiveApprovalProofBody>.self, from: request)
            guard let challenge, proof.correlationID == challenge.messageID, proof.body.approvalID == challenge.body.approvalID else { throw LabError.unauthorized }
            let c = challenge.body
            let bytes = try c.signingInput(version: challenge.version)
            let publicKey = try fixture.approvalPublicKey.map { try P256.Signing.PublicKey(x963Representation: $0) }
                ?? P256.Signing.PrivateKey(rawRepresentation: fixture.approvalKey).publicKey
            guard publicKey.isValidSignature(try .init(rawRepresentation: proof.body.signature.rawValue), for: bytes) else { throw LabError.unauthorized }
            self.challenge = nil; status.approvalVerified = true
            status.activeDisplayOrdinal =
                selectedDisplayID == fixture.displayID ? 1 : 2
            deadline = now() + 600_000_000_000
            func offer(_ role: InteractiveChannelRoleName) throws -> InteractiveChannelOffer {
                try .init(channelID: WireUUID(UUID()), role: role, credential: WireBytes32(Data(SHA256.hash(data: Data(UUID().uuidString.utf8)))), issuedAtUnixMilliseconds: wall(), expiresAtUnixMilliseconds: wall() + 30_000)
            }
            try await reply(InteractiveSessionAcceptedBody(interactiveSessionID: WireUUID(sessionID), authorizationEpoch: .init(rawValue: fixture.authorizationEpoch ?? 1),
                expiresAtUnixMilliseconds: wall() + 600_000, inputChannel: offer(.input), mediaChannel: offer(.media)), to: proof.messageID)
        case .interactiveInitialSurfaceRequest:
            let message = try WireCodec.decode(WireEnvelope<InteractiveInitialSurfaceRequestBodyV0>.self, from: request)
            let descriptor = try makeDescriptor(kind: .desktop, revision: 1)
            let lease = try makeLease(descriptor, counter: 0)
            let command = try InteractiveRuntimeInstallCommandV0(commandID: UUID(), lease: lease, deviceDisplayName: DeviceDisplayName("Simulator test"), surfaceDescriptor: descriptor, sessionDeadlineMonotonicNanoseconds: deadline)
            _ = try await runtime.install(command, nowMonotonicNanoseconds: now())
            self.descriptor = descriptor; self.lease = lease; commandID = command.commandID
            try await reply(InteractiveInitialSurfaceDescriptorBodyV0(activationID: activationID,
                descriptor: .init(descriptor: descriptor, validForMilliseconds: 10_000), sequence: advance()), to: message.messageID)
            if usesAgentRenewal {
                let owner = AgentInteractiveLeaseRenewalOwnerV1(runtime: LabAgentLeaseRuntime(session: self))
                agentRenewal = owner
                try await owner.startForInstalledTestRuntime(interactiveSessionID: sessionID,
                    primaryConnectionID: fixture.connectionID)
            } else {
              renewal = Task {
                do {
                    let interval = max(100, min(3_000, Int(ProcessInfo.processInfo.environment["MACCOMPANION_LAB_RENEW_MS"] ?? "3000") ?? 3_000))
                    while !Task.isCancelled { try await Task.sleep(for: .milliseconds(interval)); try await renew() }
                }
                catch { if !closed { status.failure = String(describing: error); labLog("LAB_RENEW_FAILURE \(error)") }; await close() }
              }
            }
        case .interactiveInitialSurfaceAcknowledgement:
            let message = try WireCodec.decode(WireEnvelope<InteractiveInitialSurfaceAcknowledgementBodyV0>.self, from: request)
            try await acknowledge(UInt64(message.body.readyMediaSequence))
            try await reply(InteractiveInitialSurfaceAcknowledgedBodyV0(acknowledgement: message.body, inputResumed: true, sequence: advance()), to: message.messageID)
        case .interactiveSurfaceSelect:
            let message = try WireCodec.decode(WireEnvelope<InteractiveSurfaceSelectBodyV0>.self, from: request)
            try await acquireLeaseMutation()
            defer { leaseMutationInProgress = false }
            guard let prior = lease, let current = descriptor,
                  message.body.expectedSurfaceRevision == current.surfaceRevision,
                  message.body.expectedCoordinateSpaceRevision == current.coordinateSpaceRevision else { throw LabError.invalidFrame }
            if let displayID = message.body.targetDisplayID?.rawValue {
                guard message.body.targetKind == .desktop,
                      displayID == fixture.displayID
                        || displayID == secondDisplayID,
                      displayID != selectedDisplayID,
                      displayAdmissionRevision
                        < WireLimits.maximumSafeInteger else {
                    throw LabError.invalidFrame
                }
                selectedDisplayID = displayID
                displayAdmissionRevision += 1
            }
            let kind: InteractiveSurfaceKind
            if message.body.targetKind == .focusedRegion,
               fallbackNextFocusedSelectionToDesktop {
                // Model production focus churn after the phone has committed
                // to the authenticated focus token but before the Mac can
                // resolve it. Desktop is the safe, already-authorized result.
                kind = .desktop
                fallbackNextFocusedSelectionToDesktop = false
            } else {
                kind = message.body.targetKind
            }
            let replacement = try makeDescriptor(kind: kind, revision: current.surfaceRevision.rawValue + 1, focus: kind == .focusedRegion ? focus : nil)
            let nextLease = try makeLease(replacement, counter: prior.renewalCounter + 1)
            let command = try InteractiveRuntimeSurfaceTransitionCommandV0(commandID: UUID(), previousLeaseID: prior.leaseID, replacement: nextLease, descriptor: replacement)
            let receipt = try await runtime.prepareSurfaceTransition(command, nowMonotonicNanoseconds: now())
            descriptor = replacement; lease = nextLease; commandID = command.commandID; transitionID = WireUUID(UUID())
            status.transitions += 1
            if delaySelected { try await Task.sleep(for: .milliseconds(180)); delaySelected = false }
            try await reply(InteractiveSurfaceSelectedBodyV0(transitionID: transitionID, descriptor: .init(descriptor: replacement, validForMilliseconds: 10_000),
                mediaSequenceBeforeTransition: Int64(receipt.mediaSequenceBeforeTransition), sequence: advance()), to: message.messageID)
        case .interactiveSurfaceAcknowledgement:
            let message = try WireCodec.decode(WireEnvelope<InteractiveSurfaceAcknowledgementBodyV0>.self, from: request)
            try await acknowledge(UInt64(message.body.readyMediaSequence))
            try await reply(InteractiveSurfaceAcknowledgedBodyV0(acknowledgement: message.body, inputResumed: true, sequence: advance()), to: message.messageID)
        case .interactiveSessionEnd:
            let message = try WireCodec.decode(WireEnvelope<InteractiveSessionEndBodyV0>.self, from: request)
            try await reply(InteractiveSessionEndedBodyV0(interactiveSessionID: WireUUID(sessionID), authorizationEpoch: .init(rawValue: fixture.authorizationEpoch ?? 1), endedAtUnixMilliseconds: wall()), to: message.messageID)
            await close()
        case .statusSnapshotRequest:
            let message = try WireCodec.decode(WireEnvelope<StatusSnapshotRequestBody>.self, from: request)
            status.statusRequests += 1
            try await reply(StatusSnapshotBody(hostID: WireUUID(fixture.hostID),
                generation: WireUUID(sessionID), revision: Int64(status.statusRequests),
                observedAtUnixMilliseconds: wall(), validForMilliseconds: 30_000,
                hostState: .userSessionActive,
                system: SystemOverview(osName: "macOS", osVersion: "27.0", osBuild: "lab",
                    uptimeSeconds: 1, cpuUtilizationBasisPoints: 0, memoryTotalBytes: 1024,
                    memoryUsedBytes: 0, storageTotalBytes: 1024, storageAvailableBytes: 1024,
                    powerSource: .ac, batteryLevelPercent: nil)), to: message.messageID)
        default: throw LabError.unsupported
        }
    }
    private func acknowledge(_ sequence: UInt64) async throws {
        try await acquireLeaseMutation()
        defer { leaseMutationInProgress = false }
        guard let lease, let descriptor, let commandID else { throw LabError.closed }
        _ = try await runtime.acknowledgeSurface(.init(commandID: UUID(), transitionCommandID: commandID, leaseID: lease.leaseID,
            interactiveSessionID: sessionID, surfaceID: lease.surfaceID, surfaceRevision: lease.surfaceRevision,
            coordinateRevision: lease.coordinateRevision, focusToken: descriptor.focus?.token,
            focusRevision: descriptor.focus?.revision, readyMediaSequence: sequence), nowMonotonicNanoseconds: now())
        status.acknowledgements += 1
        status.activeDisplayOrdinal =
            selectedDisplayID == fixture.displayID ? 1 : 2
    }
    private func renew() async throws {
        guard !closed, !leaseMutationInProgress, let prior = lease, let descriptor else { return }
        leaseMutationInProgress = true
        defer { leaseMutationInProgress = false }
        let replacement = try makeLease(descriptor, counter: prior.renewalCounter + 1)
        _ = try await runtime.renew(.init(commandID: UUID(), previousLeaseID: prior.leaseID, replacement: replacement), nowMonotonicNanoseconds: now())
        status.renewals += 1
        lease = replacement
    }
    func leaseForAgentScheduling() -> InteractiveExecutionLease? { closed ? nil : lease }
    func matchesAgentSession(_ id: UUID, _ primaryID: Data) -> Bool {
        id == sessionID && primaryID == fixture.connectionID
    }
    func renewForAgentScheduler() async throws -> AgentInteractiveLeaseRenewalResultV1 {
        try await acquireLeaseMutation()
        defer { leaseMutationInProgress = false }
        guard let prior = lease, let descriptor else { throw LabError.closed }
        status.renewalAttempts += 1
        let fault = renewalFault; renewalFault = nil
        do {
            if fault == "expire-renewal" {
                let expiry = prior.expiresAtMonotonicNanoseconds
                let sample = now()
                if expiry > sample { try await Task.sleep(nanoseconds: expiry - sample + 50_000_000) }
            }
            guard !closed else { throw LabError.closed }
            let replacement = try makeLease(descriptor, counter: prior.renewalCounter + 1)
            let renewal = try InteractiveRuntimeLeaseRenewalV0(commandID: UUID(), previousLeaseID: prior.leaseID, replacement: replacement)
            _ = try await runtime.renew(renewal, nowMonotonicNanoseconds: now())
            if fault == "reject-renewal" {
                // Runtime adopted the lease, but its receipt is lost. No retry.
                throw LabError.closed
            }
            lease = replacement; status.renewals += 1
            return .init(previous: prior, renewal: renewal)
        } catch {
            status.renewalFailure = fault ?? "unexpected"
            throw error
        }
    }
    private func acquireLeaseMutation() async throws {
        while leaseMutationInProgress {
            guard !closed else { throw LabError.closed }
            try await Task.sleep(for: .milliseconds(5))
        }
        guard !closed else { throw LabError.closed }
        leaseMutationInProgress = true
    }
    private func acceptInput(_ bytes: Data) async throws {
        let envelope = try InteractiveInputCodec.decode(bytes)
        guard envelope.sequence == nextInputSequence, lease != nil else { throw LabError.invalidFrame }
        nextInputSequence += 1
        do { try await runtime.postInputEnvelope(envelope, nowMonotonicNanoseconds: now()) }
        catch {
            labLog("LAB_INPUT_REJECTED kind=\(envelope.input.kind.rawValue) receivedRevision=\(envelope.surfaceRevision.rawValue) currentRevision=\(descriptor?.surfaceRevision.rawValue ?? 0) mutating=\(leaseMutationInProgress) reason=\(error)")
            throw error
        }
    }
    private func publishFocus() async throws {
        guard let descriptor else { throw LabError.closed }
        if descriptor.kind == .focusedRegion {
            // Match the production host: release and close input BEFORE the
            // asynchronous focus event reaches the phone's input producer.
            _ = try await runtime.pauseInputForFocusChange(.init(commandID: UUID(),
                interactiveSessionID: descriptor.interactiveSessionID,
                authorizationEpoch: descriptor.authorizationEpoch, currentSurfaceID: descriptor.surfaceID,
                expectedSurfaceRevision: descriptor.surfaceRevision,
                expectedCoordinateSpaceRevision: descriptor.coordinateSpaceRevision))
        }
        focus = try .init(token: UUID(), revision: .init(rawValue: 1), category: .text,
            bounds: .init(x: 1_000, y: 1_000, width: 30_000, height: 12_000), editable: true, secure: false)
        focusTarget = WireUUID(UUID()); focusSequence += 1
        let body = try InteractiveSurfaceFocusChangedBodyV0(interactiveSessionID: WireUUID(sessionID), authorizationEpoch: .init(rawValue: fixture.authorizationEpoch ?? 1),
            currentSurfaceID: WireUUID(descriptor.surfaceID), currentSurfaceRevision: descriptor.surfaceRevision, currentCoordinateSpaceRevision: descriptor.coordinateSpaceRevision,
            recommendedTargetKind: .focusedRegion, targetToken: focusTarget, focus: InteractiveSurfaceWireFocusV0(focus!), inputPaused: descriptor.kind == .focusedRegion,
            reason: .verifiedFocus, validForMilliseconds: 2_000, eventSequence: focusSequence)
        try await primary.sendFrame(WireCodec.encode(WireEnvelope(messageID: WireUUID(UUID()), correlationID: nil, channel: .events, sentAtUnixMilliseconds: wall(), body: body)))
    }

    /// Reproduces production's one-second Desktop fallback authority refreshed
    /// every 350 ms. The client must preserve its original 750 ms debounce
    /// deadline instead of restarting it for each refreshed event.
    private func publishDesktopFocusRefreshes() async throws {
        guard let initial = descriptor,
              initial.kind == .focusedRegion else {
            throw LabError.invalidFrame
        }
        _ = try await runtime.pauseInputForFocusChange(.init(
            commandID: UUID(),
            interactiveSessionID: initial.interactiveSessionID,
            authorizationEpoch: initial.authorizationEpoch,
            currentSurfaceID: initial.surfaceID,
            expectedSurfaceRevision: initial.surfaceRevision,
            expectedCoordinateSpaceRevision:
                initial.coordinateSpaceRevision
        ))
        for index in 0..<12 {
            guard let current = descriptor,
                  current.surfaceID == initial.surfaceID,
                  current.surfaceRevision == initial.surfaceRevision,
                  current.coordinateSpaceRevision
                    == initial.coordinateSpaceRevision else {
                return
            }
            focusSequence += 1
            let body = try InteractiveSurfaceFocusChangedBodyV0(
                interactiveSessionID: WireUUID(sessionID),
                authorizationEpoch: .init(
                    rawValue: fixture.authorizationEpoch ?? 1
                ),
                currentSurfaceID: WireUUID(initial.surfaceID),
                currentSurfaceRevision: initial.surfaceRevision,
                currentCoordinateSpaceRevision:
                    initial.coordinateSpaceRevision,
                recommendedTargetKind: .desktop,
                targetToken: nil,
                focus: nil,
                inputPaused: true,
                reason: .noVerifiedFocus,
                validForMilliseconds: 1_000,
                eventSequence: focusSequence
            )
            try await primary.sendFrame(WireCodec.encode(WireEnvelope(
                messageID: WireUUID(UUID()),
                correlationID: nil,
                channel: .events,
                sentAtUnixMilliseconds: wall(),
                body: body
            )))
            if index < 11 {
                try await Task.sleep(for: .milliseconds(350))
            }
        }
    }

    /// Reproduces the production Accessibility pattern seen during a large UI
    /// hierarchy replacement: verified focus, a transient ambiguous Desktop,
    /// then a new verified focus, all before Smart Zoom's first transition can
    /// begin. The final target remains the only selectable authority.
    private func publishFocusChurn() async throws {
        guard let descriptor, descriptor.kind == .desktop else {
            throw LabError.invalidFrame
        }
        func send(
            kind: InteractiveSurfaceKind,
            target: WireUUID?,
            focus eventFocus: SurfaceFocus?,
            reason: InteractiveFocusEventReasonV0
        ) async throws {
            focusSequence += 1
            let body = try InteractiveSurfaceFocusChangedBodyV0(
                interactiveSessionID: WireUUID(sessionID),
                authorizationEpoch: .init(
                    rawValue: fixture.authorizationEpoch ?? 1
                ),
                currentSurfaceID: WireUUID(descriptor.surfaceID),
                currentSurfaceRevision: descriptor.surfaceRevision,
                currentCoordinateSpaceRevision:
                    descriptor.coordinateSpaceRevision,
                recommendedTargetKind: kind,
                targetToken: target,
                focus: eventFocus.map(
                    InteractiveSurfaceWireFocusV0.init
                ),
                inputPaused: false,
                reason: reason,
                validForMilliseconds: 2_000,
                eventSequence: focusSequence
            )
            try await primary.sendFrame(WireCodec.encode(WireEnvelope(
                messageID: WireUUID(UUID()),
                correlationID: nil,
                channel: .events,
                sentAtUnixMilliseconds: wall(),
                body: body
            )))
        }

        let firstFocus = try SurfaceFocus(
            token: UUID(),
            revision: .init(rawValue: 1),
            category: .text,
            bounds: .init(
                x: 1_000, y: 1_000, width: 30_000, height: 12_000
            ),
            editable: true,
            secure: false
        )
        try await send(
            kind: .focusedRegion,
            target: WireUUID(UUID()),
            focus: firstFocus,
            reason: .verifiedFocus
        )
        try await Task.sleep(for: .milliseconds(50))
        try await send(
            kind: .desktop,
            target: nil,
            focus: nil,
            reason: .ambiguousGeometry
        )
        try await Task.sleep(for: .milliseconds(50))
        focus = try SurfaceFocus(
            token: UUID(),
            revision: .init(rawValue: 1),
            category: .text,
            bounds: .init(
                x: 2_000, y: 2_000, width: 28_000, height: 10_000
            ),
            editable: true,
            secure: false
        )
        focusTarget = WireUUID(UUID())
        try await send(
            kind: .focusedRegion,
            target: focusTarget,
            focus: focus,
            reason: .verifiedFocus
        )
    }
}

private actor LabHost {
    let fixture: LabFixture
    let realTarget: RealMacTarget?
    var session: HostSession?
    var retiredSessions = 0
    var uncleanRetirements = 0
    var journey: AuthenticatedJourneyHost?
    func setJourney(_ value: AuthenticatedJourneyHost) { journey = value }
    init(_ fixture: LabFixture, realTarget: RealMacTarget?) { self.fixture = fixture; self.realTarget = realTarget }
    func accept(_ socket: NWConnection) async {
        let connection = LabConnection(socket)
        do {
            try await connection.start()
            let hello = try JSONDecoder().decode(LabHello.self, from: await connection.readFrame())
            guard hello.token == fixture.token else { throw LabError.unauthorized }
            if hello.role == "primary" {
                if let previous = session {
                    await previous.close()
                    let report = await previous.report()
                    retiredSessions += 1
                    if !report.runtimeIdle || report.captureActive || report.queuedMediaRecords != 0 {
                        uncleanRetirements += 1
                    }
                }
                var sessionFixture = fixture
                if let id = hello.connectionID {
                    guard id.count == 16 else { throw LabError.unauthorized }
                    sessionFixture.connectionID = id
                }
                let session = try HostSession(fixture: sessionFixture, primary: connection, realTarget: realTarget)
                await session.prepare()
                self.session = session
                try await connection.sendFrame(Data("ready".utf8))
                await session.start()
            } else if hello.role == "control" {
                try await connection.sendFrame(Data("ready".utf8))
                while true {
                    let command = try JSONDecoder().decode(LabCommand.self, from: await connection.readFrame())
                    if command.action.hasPrefix("journey-"), let journey {
                        try await connection.sendFrame(JSONEncoder().encode(journey.command(command.action)))
                        if command.action == "journey-restart-process" {
                            Task {
                                try await Task.sleep(for: .milliseconds(300))
                                // The runner reaps this exact child before
                                // launching a fresh process from saved state.
                                // Do not exec AppKit from a Swift worker thread.
                                exit(75)
                            }
                        }
                        continue
                    }
                    try await session?.control(command.action)
                    var report = await session?.report() ?? LabStatus()
                    report.retiredSessions = retiredSessions
                    report.uncleanRetirements = uncleanRetirements
                    try await connection.sendFrame(JSONEncoder().encode(report))
                }
            } else if let session, hello.role == "input" || hello.role == "media" {
                if let id = hello.connectionID {
                    guard id == session.fixture.connectionID else { throw LabError.unauthorized }
                }
                try await session.attach(connection, role: hello.role)
                try await connection.sendFrame(Data("ready".utf8))
            } else { throw LabError.unauthorized }
        } catch { if !(error is LabError) { labLog("LAB_CONNECTION_FAILURE \(error)") }; await connection.close() }
    }
}

@main private enum Main {
    @MainActor static func main() {
        let args = CommandLine.arguments
        guard args.count == 2 || (args.count == 3 && args[2] == "--real-mac") else { exit(2) }
        let real = args.count == 3
        let target: RealMacTarget?
        do { target = real ? try RealMacTarget() : nil }
        catch { labLog("REAL_MAC_BLOCKED \(error). Grant the lab Screen Recording and Accessibility, then rerun."); exit(77) }
        Task {
            do { try await serve(destination: args[1], realTarget: target) }
            catch { labLog("TEST_HOST_FAILED \(error)"); exit(1) }
        }
        if real { NSApplication.shared.run() } else { dispatchMain() }
    }
    private static func serve(destination: String, realTarget: RealMacTarget?) async throws {
        let saved: LabFixture? = ProcessInfo.processInfo.environment["MACCOMPANION_LAB_RESUME"] == "1"
            ? try JSONDecoder().decode(LabFixture.self, from: Data(contentsOf: URL(fileURLWithPath: destination))) : nil
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: saved?.port ?? 0) ?? .any)
        let listener = try NWListener(using: parameters)
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { state in
                if case .ready = state, let port = listener.port {
                    listener.stateUpdateHandler = nil; continuation.resume(returning: port.rawValue)
                } else if case .failed(let error) = state {
                    listener.stateUpdateHandler = nil; continuation.resume(throwing: error)
                }
            }
            listener.newConnectionHandler = { $0.cancel() }
            listener.start(queue: DispatchQueue(label: "MacCompanion.Lab.listener"))
        }
        var fixture = saved ?? LabFixture(port: port, source: realTarget == nil ? "generated" : "real-mac-window")
        let host = LabHost(fixture, realTarget: realTarget)
        if ProcessInfo.processInfo.environment["MACCOMPANION_LAB_JOURNEY"] == "1" {
            let journey = try AuthenticatedJourneyHost(fixture: fixture, realTarget: realTarget,
                directory: URL(fileURLWithPath: destination).deletingLastPathComponent().appendingPathComponent("journey"))
            fixture.journeyPort = try await journey.start()
            await host.setJourney(journey)
        }
        listener.newConnectionHandler = { connection in Task { await host.accept(connection) } }
        let destination = URL(fileURLWithPath: destination)
        try JSONEncoder().encode(fixture).write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        print("TEST_HOST_READY loopback-only source=\(fixture.source)")
        // The runner owns this foreground process and terminates it on exit.
        while !Task.isCancelled { try await Task.sleep(for: .seconds(1)) }
        listener.cancel()
    }
}
