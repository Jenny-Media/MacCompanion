#if os(iOS)
import CompanionClientNetworkPlatform
import CompanionClientPlatform
import CompanionInteractiveClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import SwiftUI

public enum ClientPrimaryLiveControlPhaseV0: Equatable, Sendable {
    case idle
    case preparing
    case awaitingVerifiedFrame
    case active
    case ending
    case failed
    case closed
}

public enum ClientPrimaryLiveControlErrorV0: Error, Equatable, Sendable {
    case activationDeadlineExceeded
}

@available(iOS 17.0, *)
@MainActor
public protocol ClientPrimaryLiveControlProductV0: AnyObject {
    var descriptor: AdaptiveSurfaceDescriptor { get }
    var surface: UIKitClientLiveSurfaceViewV0 { get }
    func refreshPrimaryState() async -> Bool
    func activationFailedOrClosed() async -> Bool
    func close() async
}

@available(iOS 17.0, *)
extension UIKitClientInitialDesktopProductV0:
    ClientPrimaryLiveControlProductV0
{
    public func activationFailedOrClosed() async -> Bool {
        let phase = await activation.phase
        return phase == .failed || phase == .closed
    }
}

/// Main-actor owner for the one live product displayed by the selected-primary
/// workspace. Product preparation may outlive a SwiftUI destination task, but
/// never the coordinator. A local screen transition is not a remote Stop.
@available(iOS 17.0, *)
@MainActor
public final class ClientPrimaryLiveControlCoordinatorV0: ObservableObject {
    public typealias Failure = @MainActor @Sendable (any Error) -> Void
    public typealias ProductFactory = @MainActor @Sendable (
        ClientInputInteractionModeV0,
        @escaping Failure
    ) async throws -> any ClientPrimaryLiveControlProductV0

    @Published public private(set) var phase:
        ClientPrimaryLiveControlPhaseV0 = .idle
    @Published public private(set) var product:
        (any ClientPrimaryLiveControlProductV0)?

    private let productFactory: ProductFactory
    private let failure: Failure
    private var activationTask: Task<Void, Never>?

    public init(
        roles: NetworkClientInteractiveRoleProductBindingV0,
        failure: @escaping Failure = { _ in }
    ) {
        productFactory = { mode, productFailure in
            try await UIKitClientInitialDesktopProductFactoryV0.make(
                roles: roles,
                mode: mode,
                failure: productFailure
            )
        }
        self.failure = failure
    }

    public init(
        productFactory: @escaping ProductFactory,
        failure: @escaping Failure = { _ in }
    ) {
        self.productFactory = productFactory
        self.failure = failure
    }

    public func start(
        mode: ClientInputInteractionModeV0
    ) {
        switch phase {
        case .idle, .failed, .closed:
            break
        case .preparing, .awaitingVerifiedFrame, .active, .ending:
            return
        }
        activationTask?.cancel()
        phase = .preparing
        activationTask = Task { [weak self] in
            await self?.prepare(mode: mode)
        }
    }

    public func updateMode(_ mode: ClientInputInteractionModeV0) {
        product?.surface.setMode(mode)
    }

    public func acceptWorkspaceMode(
        _ mode: ClientControlWorkspaceModeV0
    ) {
        switch mode {
        case .active:
            if product != nil { phase = .active }
        case .ending:
            activationTask?.cancel()
            activationTask = nil
            product?.surface.setInputEnabled(false)
            phase = .ending
        case .endFailed, .preparationFailed, .rejected, .unavailable:
            activationTask?.cancel()
            activationTask = nil
            retireLocalProduct(as: .failed)
        case .ready:
            if phase == .ending { closeLocalProduct() }
        case .requesting, .awaitingAcceptance,
             .acceptedPreparingChannels, .channelsReady,
             .preparingInitialSurface:
            break
        }
    }

    public func closeLocalProduct() {
        activationTask?.cancel()
        activationTask = nil
        retireLocalProduct(as: .closed)
    }

    private func retireLocalProduct(
        as terminalPhase: ClientPrimaryLiveControlPhaseV0
    ) {
        let retiring = product
        product = nil
        phase = terminalPhase
        Task { await retiring?.close() }
    }

    private func prepare(
        mode: ClientInputInteractionModeV0
    ) async {
        do {
            let value = try await
                productFactory(
                    mode,
                    { [weak self] error in self?.fail(error) }
                )
            try Task.checkCancellation()
            product = value
            phase = .awaitingVerifiedFrame

            // The primary request tracker owns the protocol deadline. This
            // matching UI bound prevents an indefinitely optimistic screen if
            // its callback path is lost before a terminal publication arrives.
            for _ in 0..<600 {
                try Task.checkCancellation()
                if await value.refreshPrimaryState() {
                    guard product === value else { return }
                    phase = .active
                    return
                }
                if await value.activationFailedOrClosed() {
                    throw ClientPrimaryLiveControlErrorV0
                        .activationDeadlineExceeded
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            throw ClientPrimaryLiveControlErrorV0.activationDeadlineExceeded
        } catch is CancellationError {
            return
        } catch {
            if let product {
                await product.close()
                _ = await product.refreshPrimaryState()
            }
            self.product = nil
            phase = .failed
            failure(error)
        }
    }

    private func fail(_ error: any Error) {
        guard phase != .closed else { return }
        activationTask?.cancel()
        activationTask = nil
        let retiring = product
        product = nil
        phase = .failed
        Task {
            await retiring?.close()
            _ = await retiring?.refreshPrimaryState()
        }
        failure(error)
    }

    deinit { activationTask?.cancel() }
}

@available(iOS 17.0, *)
private struct ClientPrimaryInitialDesktopSurfaceV0: UIViewRepresentable {
    let product: any ClientPrimaryLiveControlProductV0
    let mode: ClientInputInteractionModeV0

    func makeUIView(context: Context) -> UIKitClientLiveSurfaceViewV0 {
        product.surface
    }

    func updateUIView(
        _ view: UIKitClientLiveSurfaceViewV0,
        context: Context
    ) {
        view.setMode(mode)
        view.setEncodedDimensions(
            width: product.descriptor.encodedWidth,
            height: product.descriptor.encodedHeight
        )
    }
}

/// Full-screen Control destination owned by, but not conflated with, the
/// selected-primary Observe/Act/Control workspace.
@available(iOS 17.0, *)
@MainActor
private final class ClientPrimaryLiveControlViewStateV0: ObservableObject {
    @Published var mode = ClientInputInteractionModeV0.directTouch
    @Published var stopSubmitted = false
}

@available(iOS 17.0, *)
public struct ClientPrimaryLiveControlViewV0: View {
    private let macName: String
    private let revision: UInt64
    private let control: ClientControlWorkspaceProjectionV0
    @ObservedObject private var coordinator:
        ClientPrimaryLiveControlCoordinatorV0
    @StateObject private var viewState: ClientPrimaryLiveControlViewStateV0
    @Environment(\.dismiss) private var dismiss
    private let onCommandFailure:
        @MainActor @Sendable (any Error) -> Void
    private let onStop:
        @MainActor @Sendable () async throws -> Void

    public init(
        macName: String,
        revision: UInt64,
        control: ClientControlWorkspaceProjectionV0,
        coordinator: ClientPrimaryLiveControlCoordinatorV0,
        onStop: @escaping @MainActor @Sendable () async throws -> Void,
        onCommandFailure: @escaping @MainActor @Sendable
            (any Error) -> Void = { _ in }
    ) {
        self.macName = macName
        self.revision = revision
        self.control = control
        _coordinator = ObservedObject(wrappedValue: coordinator)
        _viewState = StateObject(wrappedValue:
            ClientPrimaryLiveControlViewStateV0()
        )
        self.onStop = onStop
        self.onCommandFailure = onCommandFailure
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let product = coordinator.product {
                ClientPrimaryInitialDesktopSurfaceV0(
                    product: product,
                    mode: viewState.mode
                )
                .ignoresSafeArea()
            } else if coordinator.phase == .failed {
                ContentUnavailableView(
                    "Remote Control unavailable",
                    systemImage: "display.trianglebadge.exclamationmark",
                    description: Text(control.detail)
                )
                .foregroundStyle(.white)
            } else {
                ProgressView("Preparing a verified screen from \(macName)…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
        }
        .navigationTitle(macName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.black.opacity(0.75), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Picker("Pointer mode", selection: $viewState.mode) {
                    Text("Touch").tag(
                        ClientInputInteractionModeV0.directTouch
                    )
                    Text("Trackpad").tag(
                        ClientInputInteractionModeV0.trackpad
                    )
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("Pointer mode")
                .disabled(coordinator.phase != .active)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Keyboard", systemImage: "keyboard") {
                    coordinator.product?.surface
                        .toggleSoftwareKeyboard()
                }
                .disabled(coordinator.phase != .active)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(
                    viewState.stopSubmitted ? "Stopping…" : "Stop",
                    systemImage: "stop.circle.fill",
                    role: .destructive,
                    action: stopRemoteControl
                )
                .disabled(viewState.stopSubmitted || !canStop)
            }
        }
        .onAppear {
            coordinator.start(mode: viewState.mode)
            coordinator.acceptWorkspaceMode(
                control.mode
            )
        }
        .onChange(of: viewState.mode) { _, value in
            coordinator.updateMode(value)
        }
        .onChange(of: revision) { _, _ in
            let controlMode = control.mode
            coordinator.acceptWorkspaceMode(controlMode)
            switch controlMode {
            case .ready where viewState.stopSubmitted:
                viewState.stopSubmitted = false
                dismiss()
            case .endFailed:
                viewState.stopSubmitted = false
            default:
                break
            }
        }
    }

    private var canStop: Bool {
        switch control.mode {
        case .acceptedPreparingChannels, .channelsReady,
             .preparingInitialSurface, .active, .endFailed:
            true
        case .unavailable, .ready, .requesting, .awaitingAcceptance,
             .ending, .preparationFailed, .rejected:
            false
        }
    }

    private func stopRemoteControl() {
        viewState.stopSubmitted = true
        Task {
            do { try await onStop() }
            catch {
                viewState.stopSubmitted = false
                onCommandFailure(error)
            }
        }
    }
}
#endif
