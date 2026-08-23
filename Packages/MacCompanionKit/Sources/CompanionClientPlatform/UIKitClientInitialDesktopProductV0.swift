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
            do {
                try await activation.reportRendered(receipt)
            } catch {
                self?.failure(error)
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
        Task { [weak self] in
            do { try await activation.sendInput(payloads) }
            catch { self?.failure(error) }
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

    fileprivate init(
        descriptor: AdaptiveSurfaceDescriptor,
        roles: NetworkClientInteractiveRoleProductBindingV0,
        activation:
            NetworkClientInteractiveInitialDesktopActivationV0,
        decoderRenderer: UIKitClientDecodeRenderCoordinatorV0,
        relay: UIKitClientInitialRenderRelayV0,
        surface: UIKitClientLiveSurfaceViewV0,
        inputRelay: UIKitClientInitialInputRelayV0?
    ) {
        self.descriptor = descriptor
        self.roles = roles
        self.activation = activation
        self.decoderRenderer = decoderRenderer
        self.relay = relay
        self.surface = surface
        self.inputRelay = inputRelay
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

    public func selectSurface(
        kind: InteractiveSurfaceKind,
        targetToken: UUID?
    ) async throws {
        inputRelay?.setActive(false)
        surface.setInputEnabled(false)
        surface.hideSoftwareKeyboard()
        let next = try await activation.selectSurface(
            targetKind: kind,
            targetToken: targetToken
        )
        descriptor = next
        surface.setEncodedDimensions(
            width: next.encodedWidth,
            height: next.encodedHeight
        )
        inputRelay?.setActive(true)
        surface.setInputEnabled(true)
    }

    public func close() async {
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
            return UIKitClientInitialDesktopProductV0(
                descriptor: descriptor,
                roles: roles,
                activation: activation,
                decoderRenderer: coordinator,
                relay: relay,
                surface: surface,
                inputRelay: inputRelay
            )
        } catch {
            relay.close()
            coordinator.closeAndBlank()
            throw error
        }
    }

}
#endif
