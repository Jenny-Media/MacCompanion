#if os(iOS)
import CompanionInteractiveShared
import CompanionInteractiveWire
import UIKit

public enum UIKitClientNativeVideoEventV0: Sendable {
    case connected
    case firstFrame(width: Int, height: Int)
    case failed
    case disconnected
}

/// Injection boundary for an admitted native dependency. Implementations must
/// deliver main-actor callbacks and complete Stop only after native drain.
@available(iOS 17.0, *)
@MainActor
public protocol UIKitClientNativeVideoDriverV0: AnyObject {
    func start(view: UIView, event: @escaping @MainActor (UIKitClientNativeVideoEventV0) -> Void) throws
    func stop() async
    var presentationIsReady: Bool { get }
}

@available(iOS 17.0, *)
public extension UIKitClientNativeVideoDriverV0 {
    var presentationIsReady: Bool { false }
}

/// Used by the normal Control product; engine-specific source stays outside
/// its release graph until dependency and endpoint admission are completed.
@available(iOS 17.0, *)
@MainActor
public final class UIKitClientNativeVideoOwnerV0: NSObject {
    public private(set) var lifecycle: InteractiveNativeVideoLifecycleV0
    private let surface: UIKitClientLiveSurfaceViewV0
    private let view = UIView()
    private let cover = UIView()
    private let driver: any UIKitClientNativeVideoDriverV0
    private let current: @MainActor () -> InteractiveNativeVideoBindingV0?
    private let now: @MainActor () -> UInt64
    private let changed: @MainActor (InteractiveNativeVideoPhaseV0, InteractiveNativeVideoFailureV0?) -> Void
    public private(set) var presentationAcknowledged = false
    private let acknowledgePresentation: (@MainActor (UInt64, InteractiveNativeVideoSurfaceV0) async throws -> InteractiveNativeVideoPresentationReceiptBodyV0)?
    private let expectedLogicalWidthPoints: UInt32?
    private let expectedLogicalHeightPoints: UInt32?
    private let inputAdmissionChanged: @MainActor (Bool) -> Void
    public var allowsInput: Bool { lifecycle.allowsInput && presentationAcknowledged && presentationIsCurrent() }
    private var presentationTask: Task<Void, Never>?
    private var presentationAttempted = false
    private var monitor: Task<Void, Never>?
    private var drain: Task<Void, Never>?

    public init(binding: InteractiveNativeVideoBindingV0,
                descriptor: InteractiveNativeVideoSurfaceV0,
                surface: UIKitClientLiveSurfaceViewV0,
                driver: any UIKitClientNativeVideoDriverV0,
                current: @escaping @MainActor () -> InteractiveNativeVideoBindingV0?,
                nowMonotonicMilliseconds: @escaping @MainActor () -> UInt64 = {
                    DispatchTime.now().uptimeNanoseconds / 1_000_000
                },
                changed: @escaping @MainActor (InteractiveNativeVideoPhaseV0, InteractiveNativeVideoFailureV0?) -> Void,
                logicalWidthPoints: UInt32? = nil, logicalHeightPoints: UInt32? = nil,
                inputAdmissionChanged: @escaping @MainActor (Bool) -> Void = { _ in },
                acknowledgePresentation: (@MainActor (UInt64, InteractiveNativeVideoSurfaceV0) async throws -> InteractiveNativeVideoPresentationReceiptBodyV0)? = nil) {
        self.acknowledgePresentation = acknowledgePresentation
        expectedLogicalWidthPoints = logicalWidthPoints; expectedLogicalHeightPoints = logicalHeightPoints
        self.inputAdmissionChanged = inputAdmissionChanged
        lifecycle = .init(binding: binding, surface: descriptor)
        self.surface = surface
        self.driver = driver
        self.current = current
        now = nowMonotonicMilliseconds
        self.changed = changed
        super.init()
        view.backgroundColor = .black
        cover.backgroundColor = .black
        cover.isOpaque = true
        view.frame = cover.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.addSubview(view)
    }

    public func start() throws {
        guard lifecycle.generation == 0 else {
            throw InteractiveNativeVideoFailureV0.connectionFailed
        }
        guard let current = current() else {
            lifecycle.authorizationLost()
            publish()
            throw InteractiveNativeVideoFailureV0.authorizationLost
        }
        guard let generation = lifecycle.begin(current: current, nowMonotonicMilliseconds: now()) else {
            publish()
            throw lifecycle.failure ?? InteractiveNativeVideoFailureV0.authorizationLost
        }
        guard surface.installNativeVideoView(cover) else {
            lifecycle.stop()
            // No driver was started, so there are no native resources to drain.
            _ = lifecycle.drained(generation: generation)
            publish()
            throw InteractiveNativeVideoFailureV0.connectionFailed
        }
        NotificationCenter.default.addObserver(self, selector: #selector(enteredBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        // The decoder hides its view until a frame arrives. Keep an opaque
        // parent visible so an old media role cannot show through underneath.
        cover.isHidden = false
        view.isHidden = true
        publish()
        refresh()
        guard !lifecycle.isTerminal, lifecycle.phase == .connecting else {
            throw lifecycle.failure ?? InteractiveNativeVideoFailureV0.authorizationLost
        }
        do {
            try driver.start(view: view) { [weak self] event in
                self?.receive(event, generation: generation)
            }
        } catch {
            _ = lifecycle.connectionFailed(generation: generation, current: current,
                                            nowMonotonicMilliseconds: now())
            retireViewAndDrain()
            throw error
        }
        guard lifecycle.phase == .connecting || lifecycle.phase == .connected || lifecycle.phase == .displaying,
              drain == nil else { return }
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, let self else { return }
                self.refresh()
            }
        }
    }

    /// Immediate local revocation/foreground invalidation uses the same path
    /// as the periodic deadline guard. Neither path restores input.
    public func refresh() {
        guard drain == nil, lifecycle.requiresDrain else { return }
        guard let current = current() else { stopAdmission(); return }
        if !lifecycle.revalidate(current: current, nowMonotonicMilliseconds: now()) {
            retireViewAndDrain()
        } else {
            if presentationAcknowledged && !presentationIsCurrent() { stopAdmission(); return }
            schedulePresentationAcknowledgement()
        }
    }

    private func presentationIsCurrent() -> Bool {
        guard drain == nil, lifecycle.phase == .displaying, !lifecycle.isTerminal,
              current() == lifecycle.binding, now() < lifecycle.binding.expiresAtMonotonicMilliseconds,
              driver.presentationIsReady, UIApplication.shared.applicationState == .active,
              let window = view.window, window.windowScene?.activationState == .foregroundActive,
              view.bounds.width > 0, view.bounds.height > 0 else { return false }
        var candidate: UIView? = view
        while let currentView = candidate {
            guard !currentView.isHidden, currentView.alpha > 0 else { return false }
            candidate = currentView.superview
        }
        return true
    }

    private func schedulePresentationAcknowledgement() {
        guard !presentationAttempted, let acknowledgePresentation, presentationIsCurrent() else { return }
        presentationAttempted = true
        let generation = lifecycle.generation, descriptor = lifecycle.surface
        presentationTask = Task { [weak self] in
            do {
                let receipt = try await acknowledgePresentation(generation, descriptor)
                guard let self, !Task.isCancelled, self.lifecycle.generation == generation,
                      self.lifecycle.surface == descriptor, self.presentationIsCurrent() else { return }
                try receipt.validate()
                guard receipt.nativeGeneration == Int64(exactly: generation),
                      receipt.fence.interactiveSessionID.rawValue == self.lifecycle.binding.interactiveSessionID,
                      receipt.fence.authorizationEpoch.rawValue == UInt64(self.lifecycle.binding.authorizationEpoch),
                      receipt.fence.surfaceID.rawValue == descriptor.surfaceID,
                      receipt.fence.surfaceRevision == descriptor.surfaceRevision,
                      receipt.fence.coordinateSpaceRevision == descriptor.coordinateSpaceRevision,
                      Int(receipt.encodedWidth) == descriptor.encodedWidth, Int(receipt.encodedHeight) == descriptor.encodedHeight else {
                    throw InteractiveNativeVideoFailureV0.authorizationLost
                }
                if receipt.inputAdmitted {
                    guard receipt.logicalWidthPoints == self.expectedLogicalWidthPoints,
                          receipt.logicalHeightPoints == self.expectedLogicalHeightPoints else { throw InteractiveNativeVideoFailureV0.invalidSurface }
                    let geometry = try InteractiveNativeVideoContentGeometryV0(encodedWidth: Int(receipt.encodedWidth),
                        encodedHeight: Int(receipt.encodedHeight), capturePixelWidth: Int(receipt.capturePixelWidth),
                        capturePixelHeight: Int(receipt.capturePixelHeight), logicalWidthPoints: Int(receipt.logicalWidthPoints),
                        logicalHeightPoints: Int(receipt.logicalHeightPoints))
                    try self.surface.stageNativeInputGeometry(geometry, expectedView: self.cover) { [weak self] in self?.allowsInput == true }
                    guard let current = self.current(), self.lifecycle.admitInput(generation: generation, surface: descriptor,
                        current: current, nowMonotonicMilliseconds: self.now()) else { throw InteractiveNativeVideoFailureV0.authorizationLost }
                }
                self.presentationAcknowledged = true
                self.surface.setInputEnabled(self.allowsInput)
                self.inputAdmissionChanged(self.allowsInput)
            } catch {
                guard let self, !Task.isCancelled, self.lifecycle.generation == generation, self.drain == nil else { return }
                self.stopAdmission()
            }
        }
    }

    public func close() async {
        lifecycle.stop()
        retireViewAndDrain()
        await drain?.value
        surface.removeNativeVideoView(cover)
    }

    private func receive(_ event: UIKitClientNativeVideoEventV0, generation: UInt64) {
        guard drain == nil, generation == lifecycle.generation,
              let current = current() else { refresh(); return }
        switch event {
        case .connected:
            _ = lifecycle.connected(generation: generation, current: current,
                                    nowMonotonicMilliseconds: now())
        case let .firstFrame(width, height):
            do {
                let frame = try InteractiveNativeVideoSurfaceV0(
                    surfaceID: lifecycle.surface.surfaceID,
                    surfaceRevision: lifecycle.surface.surfaceRevision,
                    coordinateSpaceRevision: lifecycle.surface.coordinateSpaceRevision,
                    encodedWidth: width, encodedHeight: height)
                if !lifecycle.frame(generation: generation, surface: frame, current: current,
                                    nowMonotonicMilliseconds: now()), lifecycle.phase == .connecting {
                    _ = lifecycle.connectionFailed(generation: generation, current: current,
                                                    nowMonotonicMilliseconds: now())
                }
            } catch {
                // Invalid dimensions cannot become a displayed frame.
                _ = lifecycle.connectionFailed(generation: generation, current: current,
                                                nowMonotonicMilliseconds: now())
            }
        case .failed, .disconnected:
            _ = lifecycle.connectionFailed(generation: generation, current: current,
                                            nowMonotonicMilliseconds: now())
        }
        // A decoder may reveal its own UIView before invoking its callback.
        // Only this owner's admitted displaying state may keep that view shown.
        view.isHidden = lifecycle.phase != .displaying
        if lifecycle.phase == .failed { retireViewAndDrain() }
        else { publish() }
    }

    @objc private func enteredBackground() {
        guard lifecycle.requiresDrain, !lifecycle.isTerminal else { return }
        stopAdmission()
    }

    private func stopAdmission() {
        lifecycle.authorizationLost()
        retireViewAndDrain()
    }

    private func retireViewAndDrain() {
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        presentationAcknowledged = false
        surface.clearNativeInputAdmission(cover)
        inputAdmissionChanged(false)
        presentationTask?.cancel()
        presentationTask = nil
        view.isHidden = true
        surface.setInputEnabled(false)
        monitor?.cancel()
        monitor = nil
        if drain == nil, lifecycle.requiresDrain {
            let generation = lifecycle.generation
            // Reserve teardown before notifying an external status consumer.
            // A consumer can synchronously refresh revoked authority again.
            drain = Task { [self] in
                await driver.stop()
                _ = lifecycle.drained(generation: generation)
                // Keep the black cover and typed failure visible until explicit
                // close; failed native media must not reveal legacy video.
                publish()
            }
        }
        publish()
    }

    private func publish() { changed(lifecycle.phase, lifecycle.failure) }
}
#endif
