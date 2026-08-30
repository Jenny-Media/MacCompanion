#if os(iOS)
import CompanionClientNetworkPlatform
import CompanionInteractiveClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import Foundation

@available(iOS 17.0, *)
@MainActor
private final class UIKitClientInitialRenderRelayV0 {
    typealias Failure = @MainActor (any Error) -> Void

    private let failure: Failure
    private var activation:
        NetworkClientInteractiveInitialDesktopActivationV0?
    private var pending: ClientDecodedFrameReceiptV0?
    private var closed = false

    init(failure: @escaping Failure) { self.failure = failure }

    func report(_ receipt: ClientDecodedFrameReceiptV0) {
        guard !closed else { return }
        guard let activation else {
            if pending == nil { pending = receipt }
            return
        }
        submit(receipt, to: activation)
    }

    func bind(
        _ value: NetworkClientInteractiveInitialDesktopActivationV0
    ) {
        guard !closed, activation == nil else { return }
        activation = value
        if let pending {
            self.pending = nil
            submit(pending, to: value)
        }
    }

    func close() {
        closed = true
        activation = nil
        pending = nil
    }

    private func submit(
        _ receipt: ClientDecodedFrameReceiptV0,
        to activation:
            NetworkClientInteractiveInitialDesktopActivationV0
    ) {
        Task { [weak self] in
            guard let self, !self.closed, self.activation === activation else { return }
            do {
                try await activation.reportRendered(receipt)
            } catch {
                guard !self.closed, self.activation === activation else { return }
                print(
                    "[MacCompanion live-control] render receipt failed error=\(String(describing: error))"
                )
                self.failure(error)
            }
        }
    }
}

@available(iOS 17.0, *)
@MainActor
private final class UIKitClientInitialInputRelayV0 {
    typealias Failure = @MainActor (any Error) -> Void

    private let failure: Failure
    private var activation:
        NetworkClientInteractiveInitialDesktopActivationV0?
    private var active = false

    init(failure: @escaping Failure) { self.failure = failure }

    func bind(
        _ value: NetworkClientInteractiveInitialDesktopActivationV0
    ) { activation = value }

    func setActive(_ value: Bool) { active = value }

    func submit(_ payloads: [InteractiveInputPayload]) {
        guard active, let activation, !payloads.isEmpty else { return }
        let kinds = payloads.map { $0.kind.rawValue }.joined(separator: ",")
        print(
            "[MacCompanion live-control] input relay submitted "
                + "count=\(payloads.count) kinds=\(kinds)"
        )
        Task { [weak self] in
            guard let self, self.active, self.activation === activation else { return }
            do { try await activation.sendInput(payloads) }
            catch {
                guard self.active, self.activation === activation else { return }
                print(
                    "[MacCompanion live-control] input submission error=\(String(describing: error)) disposition=\(String(describing: ClientInputSubmissionErrorPolicyV0.disposition(for: error)))"
                )
                switch ClientInputSubmissionErrorPolicyV0.disposition(
                    for: error
                ) {
                case .ignoreLocally:
                    return
                case .failClosed:
                    self.failure(error)
                }
            }
        }
    }

    func close() { active = false; activation = nil }
}

/// Main-actor bridge from admitted media records to the concrete
/// VideoToolbox/render coordinator. Render success is reported separately by
/// the coordinator callback; submission alone cannot acknowledge a surface.
@available(iOS 17.0, *)
@MainActor
public final class UIKitClientInitialMediaRendererV0:
    ClientInteractiveInitialMediaRenderingV0
{
    public let coordinator: UIKitClientDecodeRenderCoordinatorV0

    public init(coordinator: UIKitClientDecodeRenderCoordinatorV0) {
        self.coordinator = coordinator
    }

    public func process(
        header: MediaRecordHeader,
        payload: Data,
        admission: ClientMediaAdmissionV0
    ) async throws {
        try coordinator.process(
            header: header,
            payload: payload,
            admission: admission
        )
    }

    public func close() async { coordinator.closeAndBlank() }
}

@available(iOS 17.0, *)
@MainActor
public final class UIKitClientInitialDesktopProductV0 {
    public private(set) var descriptor: AdaptiveSurfaceDescriptor
    public let activation:
        NetworkClientInteractiveInitialDesktopActivationV0
    public let decoderRenderer: UIKitClientDecodeRenderCoordinatorV0
    public let surface: UIKitClientLiveSurfaceViewV0

    private let roles: NetworkClientInteractiveRoleProductBindingV0
    private let relay: UIKitClientInitialRenderRelayV0
    private let inputRelay: UIKitClientInitialInputRelayV0?
    private let failure: @MainActor (any Error) -> Void
    private var automaticZoomPolicy =
        UIKitClientAutomaticZoomSessionPolicyV0()
    private var surfaceTransitionInFlight = false
    private var latestAutomaticFocusEvent: ClientSurfaceFocusEventV0?
    private var pendingAutomaticFocusEvent: ClientSurfaceFocusEventV0?
    private var pendingAutomaticFocusIntent:
        UIKitClientAutomaticFocusIntentV0?
    private var automaticFocusTask: Task<Void, Never>?
    private var automaticFocusGeneration: UInt64 = 0
    private var visualSmartZoomFocus:
        UIKitClientFocusPresentationIdentityV0?

    fileprivate init(
        descriptor: AdaptiveSurfaceDescriptor,
        roles: NetworkClientInteractiveRoleProductBindingV0,
        activation:
            NetworkClientInteractiveInitialDesktopActivationV0,
        decoderRenderer: UIKitClientDecodeRenderCoordinatorV0,
        relay: UIKitClientInitialRenderRelayV0,
        surface: UIKitClientLiveSurfaceViewV0,
        inputRelay: UIKitClientInitialInputRelayV0?,
        failure: @escaping @MainActor (any Error) -> Void
    ) {
        self.descriptor = descriptor
        self.roles = roles
        self.activation = activation
        self.decoderRenderer = decoderRenderer
        self.relay = relay
        self.surface = surface
        self.inputRelay = inputRelay
        self.failure = failure
    }

    @discardableResult
    public func refreshPrimaryState() async -> Bool {
        let active = await roles.refreshInitialDesktopState()
        if active {
            inputRelay?.setActive(true)
            surface.setInputEnabled(true)
        }
        return active
    }

    public func sendInput(
        _ payloads: [InteractiveInputPayload]
    ) async throws {
        try await activation.sendInput(payloads)
    }

    public func requestSurfaceTargets() async throws
        -> [InteractiveSurfaceTargetCandidateV0]
    {
        try await activation.requestSurfaceTargets()
    }

    public func requestDisplayCatalog() async throws
        -> InteractiveDisplayCatalogResponseBodyV1
    {
        try await activation.requestDisplayCatalog()
    }

    public func selectDisplay(_ displayID: UUID) async throws {
        visualSmartZoomFocus = nil
        cancelPendingAutomaticFocusEvent()
        guard !surfaceTransitionInFlight else {
            throw NetworkClientInteractiveInitialDesktopErrorV0.invalidPhase
        }
        surfaceTransitionInFlight = true
        inputRelay?.setActive(false)
        surface.setInputEnabled(false)
        surface.hideSoftwareKeyboard()
        do {
            let next = try await activation.selectDisplay(displayID)
            apply(next)
        } catch {
            surfaceTransitionInFlight = false
            throw error
        }
        surfaceTransitionInFlight = false
        inputRelay?.setActive(true)
        surface.setInputEnabled(true)
    }

    public func setAutomaticSmartZoomEnabled(_ enabled: Bool) async throws {
        automaticZoomPolicy.setPreferenceEnabled(enabled)
        await activation.setAutomaticSmartZoomEnabled(enabled)
        cancelPendingAutomaticFocusEvent()
        if !enabled {
            visualSmartZoomFocus = nil
            surface.resetVisualZoom(animated: true)
            // A disabled preference still has to release an authenticated host
            // focus pause. The activation applies only that safety recovery
            // while disabled and otherwise leaves presentation unchanged.
            try await applyLatestAutomaticFocusEvent()
        }
    }

    public func resumeAutomaticSmartZoom() async throws {
        automaticZoomPolicy.resume()
        await activation.setAutomaticSmartZoomEnabled(true)
        cancelPendingAutomaticFocusEvent()
        if let latestAutomaticFocusEvent,
           !latestAutomaticFocusEvent.inputPaused {
            queueAutomaticFocusEvent(latestAutomaticFocusEvent)
        }
    }

    public func selectSurface(
        kind: InteractiveSurfaceKind,
        targetToken: UUID?
    ) async throws {
        visualSmartZoomFocus = nil
        try await performSurfaceSelection(
            kind: kind,
            targetToken: targetToken
        )
    }

    private func performSurfaceSelection(
        kind: InteractiveSurfaceKind,
        targetToken: UUID?
    ) async throws {
        guard !surfaceTransitionInFlight else {
            throw NetworkClientInteractiveInitialDesktopErrorV0.invalidPhase
        }
        // A manual App/Window/Desktop choice changes the visual base surface,
        // not the user's independent Smart Zoom preference. Pending focus for
        // the old surface is discarded; fresh focus on the acknowledged
        // replacement may still drive an automatic focused-region crop.
        cancelPendingAutomaticFocusEvent()
        surfaceTransitionInFlight = true
        inputRelay?.setActive(false)
        surface.setInputEnabled(false)
        surface.hideSoftwareKeyboard()
        let next: AdaptiveSurfaceDescriptor
        do {
            next = try await activation.selectSurface(
                targetKind: kind,
                targetToken: targetToken
            )
        } catch {
            print(
                "[MacCompanion live-control] automatic focus transition failed error=\(String(describing: error))"
            )
            surfaceTransitionInFlight = false
            throw error
        }
        apply(next)
        surfaceTransitionInFlight = false
        inputRelay?.setActive(true)
        surface.setInputEnabled(true)
    }

    /// Returns `false` only when the acknowledged surface lacks Keyboard/Text
    /// authority or positively identifies a secure focus. Missing or
    /// ambiguous Accessibility focus does not disable the remote keyboard.
    public func prepareTextInput() async throws -> Bool {
        guard !surfaceTransitionInFlight else { return false }
        guard let current = try await activation.prepareTextInput() else {
            return false
        }
        apply(current)
        return Self.authorizesText(descriptor)
    }

    /// Prefers a verified focused-region composer. If the latest admitted
    /// focus has not yet been applied, one automatic transition attempt is
    /// made before falling back to ordinary direct key input.
    public func prepareNativeTextComposer() async throws
        -> SurfaceInputFence?
    {
        guard !surfaceTransitionInFlight else { return nil }
        if let binding = try await activation.prepareNativeTextComposer() {
            return binding
        }
        guard automaticZoomPolicy.presentsAutomatically else { return nil }
        try await applyLatestAutomaticFocusEvent()
        return try await activation.prepareNativeTextComposer()
    }

    public func sendComposedText(
        _ text: String,
        boundTo binding: SurfaceInputFence
    ) async throws {
        guard !surfaceTransitionInFlight else {
            throw NetworkClientInteractiveInitialDesktopErrorV0.invalidPhase
        }
        try await activation.sendComposedText(text, boundTo: binding)
    }

    /// Coalesces advisory focus churn before changing the capture surface.
    /// The primary channel has already applied any input pause carried by the
    /// event, so delaying only the visual transition does not retain input
    /// authority. A transition already sent to the host is never cancelled.
    fileprivate func queueAutomaticFocusEvent(
        _ event: ClientSurfaceFocusEventV0
    ) {
        latestAutomaticFocusEvent = event
        guard automaticZoomPolicy.admitsFocusEvent(
            inputPaused: event.inputPaused
        ) else { return }
        let intent = UIKitClientAutomaticFocusIntentV0(event)
        let preservesScheduledDeadline = automaticFocusTask != nil
            && pendingAutomaticFocusIntent == intent
        pendingAutomaticFocusEvent = event
        pendingAutomaticFocusIntent = intent
        guard !surfaceTransitionInFlight else { return }
        guard !preservesScheduledDeadline else { return }
        schedulePendingAutomaticFocusEvent()
    }

    private func schedulePendingAutomaticFocusEvent() {
        guard automaticZoomPolicy.presentsAutomatically
                || pendingAutomaticFocusEvent?.inputPaused == true,
              !surfaceTransitionInFlight,
              let event = pendingAutomaticFocusEvent else { return }
        automaticFocusTask?.cancel()
        automaticFocusGeneration &+= 1
        let generation = automaticFocusGeneration
        let delay = automaticZoomPolicy.presentsAutomatically
            ? Self.automaticFocusDelay(for: event)
            : .zero
        automaticFocusTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.beginPendingAutomaticFocusEvent(
                generation: generation
            )
        }
    }

    private func beginPendingAutomaticFocusEvent(
        generation: UInt64
    ) async {
        guard generation == automaticFocusGeneration,
              automaticZoomPolicy.presentsAutomatically
                || pendingAutomaticFocusEvent?.inputPaused == true,
              !surfaceTransitionInFlight,
              let event = pendingAutomaticFocusEvent else { return }
        pendingAutomaticFocusEvent = nil
        pendingAutomaticFocusIntent = nil
        automaticFocusTask = nil
        do {
            try await performAutomaticFocusEvent(event)
        } catch {
            pendingAutomaticFocusEvent = nil
            pendingAutomaticFocusIntent = nil
            failure(error)
            return
        }
        schedulePendingAutomaticFocusEvent()
    }

    private func performAutomaticFocusEvent(
        _ event: ClientSurfaceFocusEventV0
    ) async throws {
        guard automaticZoomPolicy.admitsFocusEvent(
            inputPaused: event.inputPaused
        ),
              !surfaceTransitionInFlight else {
            return
        }
        // Ordinary Smart Zoom is a local, animated viewport operation. It
        // preserves the surrounding Desktop/App stream, avoids a capture
        // transition, and keeps input mapped through the inverse transform.
        // A paused focused-region authority still uses the exact host
        // transition below so input can be safely resumed.
        if automaticZoomPolicy.presentsAutomatically,
           !event.inputPaused,
           descriptor.kind != .focusedRegion {
            switch event.recommendedTargetKind {
            case .focusedRegion:
                guard event.reason == .verifiedFocus,
                      let focus = event.focus else { return }
                let identity = UIKitClientFocusPresentationIdentityV0(focus)
                guard visualSmartZoomFocus != identity else { return }
                do {
                    try surface.focusVisualZoom(on: focus.bounds)
                } catch UIKitClientLiveSurfaceFailureV0.invalidGeometry {
                    // Smart Zoom is local presentation. A focus refresh can
                    // arrive while SwiftUI is temporarily laying out a zero-
                    // sized surface; defer until the next refresh instead of
                    // revoking a healthy authenticated Control session.
                    print(
                        "[MacCompanion live-control] automatic visual zoom deferred error=invalidGeometry"
                    )
                    return
                }
                visualSmartZoomFocus = identity
            case .desktop:
                guard event.reason != .verifiedFocus,
                      event.focus == nil else { return }
                guard visualSmartZoomFocus != nil
                        || surface.isVisuallyZoomed else { return }
                visualSmartZoomFocus = nil
                surface.resetVisualZoom(animated: true)
            case .application, .window:
                break
            }
            return
        }
        surfaceTransitionInFlight = true
        inputRelay?.setActive(false)
        surface.setInputEnabled(false)
        surface.hideSoftwareKeyboard()
        do {
            if let next = try await activation.applyFocusEvent(event) {
                apply(next)
            }
        } catch {
            surfaceTransitionInFlight = false
            throw error
        }
        surfaceTransitionInFlight = false
        inputRelay?.setActive(true)
        surface.setInputEnabled(true)
    }

    private func cancelPendingAutomaticFocusEvent() {
        automaticFocusGeneration &+= 1
        automaticFocusTask?.cancel()
        automaticFocusTask = nil
        pendingAutomaticFocusEvent = nil
        pendingAutomaticFocusIntent = nil
    }

    private static func automaticFocusDelay(
        for event: ClientSurfaceFocusEventV0
    ) -> Duration {
        // Input pause is already enforced when the authenticated event is
        // admitted. Waiting longer before zooming back to Desktop preserves
        // context through transient Accessibility hierarchy replacement.
        switch event.recommendedTargetKind {
        case .desktop: .milliseconds(750)
        case .focusedRegion: .milliseconds(250)
        case .application, .window: .zero
        }
    }

    private func applyLatestAutomaticFocusEvent() async throws {
        guard !surfaceTransitionInFlight else {
            return
        }
        surfaceTransitionInFlight = true
        inputRelay?.setActive(false)
        surface.setInputEnabled(false)
        surface.hideSoftwareKeyboard()
        do {
            if let next = try await activation.applyLatestFocusEvent() {
                apply(next)
            }
        } catch {
            surfaceTransitionInFlight = false
            throw error
        }
        surfaceTransitionInFlight = false
        inputRelay?.setActive(true)
        surface.setInputEnabled(true)
    }

    private func apply(_ next: AdaptiveSurfaceDescriptor) {
        descriptor = next
        surface.setEncodedDimensions(
            width: next.encodedWidth,
            height: next.encodedHeight
        )
    }

    private static func authorizesText(
        _ descriptor: AdaptiveSurfaceDescriptor
    ) -> Bool {
        guard descriptor.interactionClasses.contains(.keyboard),
              descriptor.interactionClasses.contains(.text) else {
            return false
        }
        return descriptor.focus?.secure != true
    }

    public func showWiderContext() async {
        guard !surfaceTransitionInFlight else { return }
        let hadVisualSmartZoom = visualSmartZoomFocus != nil
        userChangedViewport()
        if hadVisualSmartZoom {
            surface.resetVisualZoom(animated: true)
            return
        }
        guard descriptor.kind == .focusedRegion else {
            surface.resetVisualZoom(animated: true)
            return
        }
        do {
            try await performSurfaceSelection(
                kind: .desktop,
                targetToken: nil
            )
        } catch {
            failure(error)
        }
    }

    fileprivate func userChangedViewport() {
        guard automaticZoomPolicy.presentsAutomatically else { return }
        automaticZoomPolicy.userChangedViewport()
        cancelPendingAutomaticFocusEvent()
        visualSmartZoomFocus = nil
    }

    public func close() async {
        cancelPendingAutomaticFocusEvent()
        surface.setZoomOutPastFitHandler(nil)
        surface.setManualViewportChangeHandler(nil)
        relay.close()
        inputRelay?.close()
        surface.resetInputAndBlank()
        await activation.close()
        decoderRenderer.closeAndBlank()
    }
}

@available(iOS 17.0, *)
@MainActor
public enum UIKitClientInitialDesktopProductFactoryV0 {
    public typealias Failure = @MainActor (any Error) -> Void

    public static func make(
        roles: NetworkClientInteractiveRoleProductBindingV0,
        mode: ClientInputInteractionModeV0,
        failure: @escaping Failure
    ) async throws -> UIKitClientInitialDesktopProductV0 {
        let inputRelay = UIKitClientInitialInputRelayV0(failure: failure)
        let surface = UIKitClientLiveSurfaceViewV0(
            mode: mode,
            onPayloads: { inputRelay.submit($0) },
            onFailure: { failure($0) }
        )
        return try await make(
            roles: roles,
            surface: surface,
            inputRelay: inputRelay,
            failure: failure
        )
    }

    public static func make(
        roles: NetworkClientInteractiveRoleProductBindingV0,
        surface: UIKitClientLiveSurfaceViewV0,
        failure: @escaping Failure
    ) async throws -> UIKitClientInitialDesktopProductV0 {
        try await make(
            roles: roles,
            surface: surface,
            inputRelay: nil,
            failure: failure
        )
    }

    private static func make(
        roles: NetworkClientInteractiveRoleProductBindingV0,
        surface: UIKitClientLiveSurfaceViewV0,
        inputRelay: UIKitClientInitialInputRelayV0?,
        failure: @escaping Failure
    ) async throws -> UIKitClientInitialDesktopProductV0 {
        surface.setInputEnabled(false)
        let relay = UIKitClientInitialRenderRelayV0(failure: failure)
        let coordinator = UIKitClientDecodeRenderCoordinatorV0(
            renderer: surface.videoView,
            rendered: { relay.report($0) }
        )
        let renderer = UIKitClientInitialMediaRendererV0(
            coordinator: coordinator
        )
        do {
            let start = try await roles.startInitialDesktop(
                renderer: renderer
            )
            let activation = start.activation
            let descriptor = start.descriptor
            surface.setEncodedDimensions(
                width: descriptor.encodedWidth,
                height: descriptor.encodedHeight
            )
            relay.bind(activation)
            inputRelay?.bind(activation)
            let product = UIKitClientInitialDesktopProductV0(
                descriptor: descriptor,
                roles: roles,
                activation: activation,
                decoderRenderer: coordinator,
                relay: relay,
                surface: surface,
                inputRelay: inputRelay,
                failure: failure
            )
            surface.setZoomOutPastFitHandler { [weak product] in
                Task { @MainActor [weak product] in
                    await product?.showWiderContext()
                }
            }
            surface.setManualViewportChangeHandler { [weak product] in
                product?.userChangedViewport()
            }
            try await roles.bindAutomaticFocusHandler(
                activation: activation,
                handler: { [weak product] event in
                    guard let product else {
                        throw NetworkClientInteractiveInitialDesktopErrorV0
                            .unavailable
                    }
                    await product.queueAutomaticFocusEvent(event)
                }
            )
            return product
        } catch {
            relay.close()
            coordinator.closeAndBlank()
            throw error
        }
    }

}
#endif
