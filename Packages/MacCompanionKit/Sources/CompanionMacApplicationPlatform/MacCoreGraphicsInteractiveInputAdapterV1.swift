#if os(macOS)
import CompanionHostPlatform
import CompanionIPC
import CompanionInteractiveRuntime
import CompanionInteractiveShared
import CompanionInteractiveWire
import CoreGraphics
import Foundation

public enum MacCoreGraphicsInteractiveInputAdapterErrorV1:
    Error, Equatable, Sendable
{
    case alreadyConfigured
    case unavailable
    case permissionDenied
    case bindingMismatch
    case eventConstructionFailed
}

private final class MacCoreGraphicsPostingSinkV1:
    CoreGraphicsConstructedEventSinkV0
{
    func receiveConstructedEvent(_ event: CGEvent) {
        event.post(tap: .cghidEventTap)
    }
}

/// The only release composition boundary permitted to call `CGEventPost`.
/// Planning, complete-batch construction, posting, and planner commit occur
/// under one lock. Runtime validation precedes this adapter and the adapter
/// independently reconstructs and checks the exact active fence again.
@available(macOS 14.0, *)
public final class MacCoreGraphicsInteractiveInputAdapterV1:
    InteractiveRuntimeInputPostingV0,
    InteractiveRuntimeInputControllingV0,
    @unchecked Sendable
{
    private struct Configuration {
        let fence: InteractiveCommandFence
        let geometry: MacDisplayGeometrySnapshotV0
        let activationTarget:
            ScreenCaptureKitLocalActivationTargetV0?
    }

    private let lock = NSLock()
    private let preflightPostEventAccess: @Sendable () -> Bool
    private let displayBounds: @Sendable (CGDirectDisplayID) -> CGRect
    private let displayPixels:
        @Sendable (CGDirectDisplayID) -> (wide: Int, high: Int)
    private let cursorPosition: @Sendable () -> CGPoint?
    private let constructor = CoreGraphicsNoPostInputConstructorV0()
    private let sink: any CoreGraphicsConstructedEventSinkV0
    private let surfaceActivator:
        MacInteractiveSelectedSurfaceActivatorV1
    private var planner = MacInteractiveInputPlannerV0()
    private var clickStateTracker = MacInteractiveClickStateTrackerV0()
    private var configuration: Configuration?

    public convenience init() {
        self.init(
            preflightPostEventAccess: { CGPreflightPostEventAccess() },
            displayBounds: { CGDisplayBounds($0) },
            displayPixels: {
                (Int(CGDisplayPixelsWide($0)), Int(CGDisplayPixelsHigh($0)))
            },
            cursorPosition: { CGEvent(source: nil)?.location },
            sink: MacCoreGraphicsPostingSinkV1(),
            surfaceActivator: MacInteractiveSelectedSurfaceActivatorV1()
        )
    }

    package init(
        preflightPostEventAccess: @escaping @Sendable () -> Bool,
        displayBounds:
            @escaping @Sendable (CGDirectDisplayID) -> CGRect,
        displayPixels:
            @escaping @Sendable (CGDirectDisplayID)
                -> (wide: Int, high: Int),
        cursorPosition: @escaping @Sendable () -> CGPoint?,
        sink: any CoreGraphicsConstructedEventSinkV0,
        surfaceActivator:
            MacInteractiveSelectedSurfaceActivatorV1 =
                MacInteractiveSelectedSurfaceActivatorV1()
    ) {
        self.preflightPostEventAccess = preflightPostEventAccess
        self.displayBounds = displayBounds
        self.displayPixels = displayPixels
        self.cursorPosition = cursorPosition
        self.sink = sink
        self.surfaceActivator = surfaceActivator
    }

    package func configure(
        command: InteractiveRuntimeInstallCommandV0,
        physicalDisplayID: CGDirectDisplayID,
        inputBounds: CGRect? = nil,
        inputBackingScaleFactor: Double? = nil,
        activationTarget:
            ScreenCaptureKitLocalActivationTargetV0? = nil
    ) throws -> Set<SurfaceInteractionClass> {
        try lock.withLock {
            guard configuration == nil,
                  planner.pressedButtons.isEmpty,
                  planner.pressedHIDUsages.isEmpty,
                  planner.modifiers.isEmpty else {
                throw MacCoreGraphicsInteractiveInputAdapterErrorV1
                    .alreadyConfigured
            }
            try command.validate()
            let requested = Set(command.lease.allowedInteractionClasses)
            let inputClasses: Set<SurfaceInteractionClass> = [
                .pointer, .keyboard, .text,
            ]
            if !requested.intersection(inputClasses).isEmpty,
               !preflightPostEventAccess() {
                throw MacCoreGraphicsInteractiveInputAdapterErrorV1
                    .permissionDenied
            }
            let physicalDisplayBounds = displayBounds(physicalDisplayID)
            let bounds = inputBounds ?? physicalDisplayBounds
            let pixels = displayPixels(physicalDisplayID)
            guard physicalDisplayID != 0,
                  bounds.origin.x.isFinite,
                  bounds.origin.y.isFinite,
                  bounds.width.isFinite,
                  bounds.height.isFinite,
                  bounds.width.rounded(.up)
                    == Double(command.surfaceDescriptor.logicalWidthPoints),
                  bounds.height.rounded(.up)
                    == Double(command.surfaceDescriptor.logicalHeightPoints),
                  pixels.wide > 0,
                  pixels.high > 0,
                  bounds.width > 0,
                  bounds.height > 0 else {
                throw MacCoreGraphicsInteractiveInputAdapterErrorV1
                    .bindingMismatch
            }
            let scale: Double
            if let inputBackingScaleFactor {
                scale = inputBackingScaleFactor
            } else {
                guard physicalDisplayBounds.width > 0,
                      physicalDisplayBounds.height > 0 else {
                    throw MacCoreGraphicsInteractiveInputAdapterErrorV1
                        .bindingMismatch
                }
                scale = max(
                    Double(pixels.wide) / physicalDisplayBounds.width,
                    Double(pixels.high) / physicalDisplayBounds.height
                )
            }
            guard scale.isFinite, scale > 0 else {
                throw MacCoreGraphicsInteractiveInputAdapterErrorV1
                    .bindingMismatch
            }
            let geometry = try MacDisplayGeometrySnapshotV0(
                selectedDisplayID: command.lease.selectedDisplayID,
                coordinateRevision: command.lease.coordinateRevision,
                logicalBounds: bounds,
                backingScaleFactor: scale,
                rotation: command.surfaceDescriptor.rotation
            )
            let fence = Self.fence(command.lease)
            guard Self.validActivationBinding(
                activationTarget,
                descriptorKind: command.surfaceDescriptor.kind
            ) else {
                throw MacCoreGraphicsInteractiveInputAdapterErrorV1
                    .bindingMismatch
            }
            configuration = Configuration(
                fence: fence,
                geometry: geometry,
                activationTarget: activationTarget
            )
            return requested
        }
    }

    public func postInteractiveInput(
        _ envelope: InteractiveInputEnvelope
    ) async throws {
        try await postAfterActivation(envelope, nativeAuthorization: nil, beforeDeadlineNanoseconds: UInt64.max)
    }

    public func postInteractiveInput(_ envelope: InteractiveInputEnvelope,
        nativeAuthorization: InteractiveRuntimeNativeInputPostingAuthorizationV0,
        beforeDeadlineNanoseconds: UInt64) async throws {
        try await postAfterActivation(envelope, nativeAuthorization: nativeAuthorization,
            beforeDeadlineNanoseconds: beforeDeadlineNanoseconds)
    }

    private func postAfterActivation(_ envelope: InteractiveInputEnvelope,
        nativeAuthorization: InteractiveRuntimeNativeInputPostingAuthorizationV0?,
        beforeDeadlineNanoseconds: UInt64) async throws {
        let activationTarget = try lock.withLock {
            guard let configuration else {
                throw MacCoreGraphicsInteractiveInputAdapterErrorV1
                    .unavailable
            }
            try envelope.validate()
            guard envelope.interactiveSessionID.rawValue
                    == configuration.fence.interactiveSessionID,
                  envelope.authorizationEpoch
                    == configuration.fence.authorizationEpoch,
                  envelope.surfaceID.rawValue
                    == configuration.fence.surfaceID,
                  envelope.surfaceRevision.rawValue
                    == configuration.fence.surfaceRevision.rawValue,
                  envelope.coordinateSpaceRevision.rawValue
                    == configuration.fence.coordinateRevision.rawValue else {
                throw MacCoreGraphicsInteractiveInputAdapterErrorV1
                    .bindingMismatch
            }
            return Self.requiresSelectedSurfaceActivation(envelope.input)
                ? configuration.activationTarget : nil
        }
        do {
            try await surfaceActivator.activate(activationTarget)
        } catch {
            throw MacCoreGraphicsInteractiveInputAdapterErrorV1
                .bindingMismatch
        }
        if let nativeAuthorization {
            try await nativeAuthorization.perform(envelope, beforeDeadlineNanoseconds: beforeDeadlineNanoseconds) {
                try self.postCurrentInput(envelope)
            }
        } else { try postCurrentInput(envelope) }
    }

    private func postCurrentInput(_ envelope: InteractiveInputEnvelope) throws {
        try lock.withLock {
            guard let configuration else {
                throw MacCoreGraphicsInteractiveInputAdapterErrorV1
                    .unavailable
            }
            guard preflightPostEventAccess() else {
                throw MacCoreGraphicsInteractiveInputAdapterErrorV1
                    .permissionDenied
            }
            try envelope.validate()
            guard envelope.interactiveSessionID.rawValue
                    == configuration.fence.interactiveSessionID,
                  envelope.authorizationEpoch
                    == configuration.fence.authorizationEpoch,
                  envelope.surfaceID.rawValue
                    == configuration.fence.surfaceID,
                  envelope.surfaceRevision.rawValue
                    == configuration.fence.surfaceRevision.rawValue,
                  envelope.coordinateSpaceRevision.rawValue
                    == configuration.fence.coordinateRevision.rawValue,
                  let cursor = cursorPosition() else {
                throw MacCoreGraphicsInteractiveInputAdapterErrorV1
                    .bindingMismatch
            }
            var nextPlanner = planner
            let events = try nextPlanner.plan(envelope.input)
            var nextClickStateTracker = clickStateTracker
            let buttonClickState = nextClickStateTracker.clickState(
                for: envelope.input,
                clientMonotonicMilliseconds:
                    envelope.clientMonotonicMilliseconds
            )
            do {
                _ = try constructor.construct(
                    events,
                    fence: configuration.fence,
                    geometry: configuration.geometry,
                    currentCursorPosition: cursor,
                    buttonClickState: buttonClickState,
                    sink: sink
                )
            } catch {
                throw MacCoreGraphicsInteractiveInputAdapterErrorV1
                    .eventConstructionFailed
            }
            planner = nextPlanner
            clickStateTracker = nextClickStateTracker
        }
    }

    public func releaseAllInteractiveInput() async throws {
        try lock.withLock {
            guard let configuration else {
                guard planner.pressedButtons.isEmpty,
                      planner.pressedHIDUsages.isEmpty,
                      planner.modifiers.isEmpty else {
                    throw MacCoreGraphicsInteractiveInputAdapterErrorV1
                        .unavailable
                }
                return
            }
            guard !planner.pressedButtons.isEmpty
                    || !planner.pressedHIDUsages.isEmpty
                    || !planner.modifiers.isEmpty else {
                return
            }
            guard preflightPostEventAccess(),
                  let cursor = cursorPosition() else {
                throw MacCoreGraphicsInteractiveInputAdapterErrorV1
                    .permissionDenied
            }
            var nextPlanner = planner
            let events = nextPlanner.releaseAll()
            do {
                _ = try constructor.construct(
                    events,
                    fence: configuration.fence,
                    geometry: configuration.geometry,
                    currentCursorPosition: cursor,
                    sink: sink
                )
            } catch {
                throw MacCoreGraphicsInteractiveInputAdapterErrorV1
                    .eventConstructionFailed
            }
            planner = nextPlanner
            clickStateTracker.reset()
        }
    }

    package func retireConfiguration() {
        lock.withLock {
            guard planner.pressedButtons.isEmpty,
                  planner.pressedHIDUsages.isEmpty,
                  planner.modifiers.isEmpty else { return }
            configuration = nil
            clickStateTracker.reset()
        }
    }

    private static func fence(
        _ lease: InteractiveExecutionLease
    ) -> InteractiveCommandFence {
        InteractiveCommandFence(
            leaseID: lease.leaseID,
            hostID: lease.hostID,
            deviceID: lease.deviceID,
            interactiveSessionID: lease.interactiveSessionID,
            authorizationEpoch: lease.authorizationEpoch,
            selectedDisplayID: lease.selectedDisplayID,
            surfaceID: lease.surfaceID,
            surfaceRevision: lease.surfaceRevision,
            coordinateRevision: lease.coordinateRevision
        )
    }

    private static func requiresSelectedSurfaceActivation(
        _ input: InteractiveInputPayload
    ) -> Bool {
        switch input {
        case .pointerMove, .reset:
            false
        case .button, .scroll, .physicalKey, .modifiers, .text:
            true
        }
    }

    private static func validActivationBinding(
        _ target: ScreenCaptureKitLocalActivationTargetV0?,
        descriptorKind: InteractiveSurfaceKind
    ) -> Bool {
        switch descriptorKind {
        case .desktop:
            target == nil
        case .application:
            if case .application = target { true } else { false }
        case .window:
            if case .window = target { true } else { false }
        case .focusedRegion:
            true
        }
    }
}
#endif
