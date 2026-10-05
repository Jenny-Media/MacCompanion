#if os(iOS)
import CompanionClientNetworkPlatform
import CompanionClientPlatform
import CompanionInteractiveClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionStudy
import Dispatch
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
    case unavailable
    case viewTransitionInProgress
}

@available(iOS 17.0, *)
@MainActor
public protocol ClientPrimaryLiveControlProductV0: AnyObject {
    var descriptor: AdaptiveSurfaceDescriptor { get }
    var surface: UIKitClientLiveSurfaceViewV0 { get }
    func observeVideoRecovery(_ changed: @escaping @MainActor (Bool) -> Void)
    func observeSurfaceTransition(_ changed: @escaping @MainActor (Bool, String?) -> Void)
    func refreshPrimaryState() async -> Bool
    func activationFailedOrClosed() async -> Bool
    func requestSurfaceTargets() async throws
        -> [InteractiveSurfaceTargetCandidateV0]
    func requestDisplayCatalog() async throws
        -> InteractiveDisplayCatalogResponseBodyV1
    func selectDisplay(_ displayID: UUID) async throws
    func setAutomaticSmartZoomEnabled(_ enabled: Bool) async throws
    func showWiderContext() async
    func resumeAutomaticSmartZoom() async throws
    func prepareNativeTextComposer() async throws -> SurfaceInputFence?
    func sendComposedText(
        _ text: String,
        boundTo binding: SurfaceInputFence
    ) async throws
    func prepareTextInput() async throws -> Bool
    func selectSurface(
        kind: InteractiveSurfaceKind,
        targetToken: UUID?
    ) async throws
    func close() async
}

@available(iOS 17.0, *)
extension ClientPrimaryLiveControlProductV0 {
    public func observeSurfaceTransition(_ changed: @escaping @MainActor (Bool, String?) -> Void) {
        changed(false, nil)
    }
    public func observeVideoRecovery(
        _ changed: @escaping @MainActor (Bool) -> Void
    ) {
        changed(false)
    }

    public func showWiderContext() async {
        surface.resetVisualZoom(animated: true)
    }

    public func resumeAutomaticSmartZoom() async throws {
        try await setAutomaticSmartZoomEnabled(true)
    }
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
    public typealias FailureRetirementFactory = @MainActor @Sendable () async
        -> (@Sendable () async -> Void)?

    @Published public private(set) var phase:
        ClientPrimaryLiveControlPhaseV0 = .idle
    @Published public private(set) var product:
        (any ClientPrimaryLiveControlProductV0)?
    @Published public private(set) var videoRequiresRestart = false
    @Published public private(set) var isViewTransitioning = false
    @Published public private(set) var viewTransitionMessage: String?

    private let productFactory: ProductFactory
    private let failureRetirementFactory: FailureRetirementFactory
    private let failure: Failure
    private var failureRetirement: (@Sendable () async -> Void)?
    private var activationTask: Task<Void, Never>?
    private var productGeneration = UUID()
    private var selectionID: UUID?

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
        failureRetirementFactory = {
            await roles.makeFailedSessionRetirement()
        }
        self.failure = failure
    }

    public init(
        productFactory: @escaping ProductFactory,
        failureRetirementFactory: @escaping FailureRetirementFactory = { nil },
        failure: @escaping Failure = { _ in }
    ) {
        self.productFactory = productFactory
        self.failureRetirementFactory = failureRetirementFactory
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
        productGeneration = UUID()
        let generation = productGeneration
        videoRequiresRestart = false
        isViewTransitioning = false
        viewTransitionMessage = nil
        phase = .preparing
        activationTask = Task { [weak self] in
            await self?.prepare(mode: mode, generation: generation)
        }
    }

    public func updateMode(_ mode: ClientInputInteractionModeV0) {
        product?.surface.setMode(mode)
    }

    public func requestSurfaceTargets() async throws
        -> [InteractiveSurfaceTargetCandidateV0]
    {
        guard phase == .active, let product else {
            throw ClientPrimaryLiveControlErrorV0.unavailable
        }
        return try await product.requestSurfaceTargets()
    }

    public func requestDisplayCatalog() async throws
        -> InteractiveDisplayCatalogResponseBodyV1
    {
        guard phase == .active, let product else {
            throw ClientPrimaryLiveControlErrorV0.unavailable
        }
        return try await product.requestDisplayCatalog()
    }

    public func selectDisplay(_ displayID: UUID) async throws {
        guard selectionID == nil, !isViewTransitioning else {
            throw ClientPrimaryLiveControlErrorV0.viewTransitionInProgress
        }
        guard phase == .active, let product else {
            throw ClientPrimaryLiveControlErrorV0.unavailable
        }
        phase = .awaitingVerifiedFrame
        let selectionID = UUID()
        self.selectionID = selectionID
        defer { if self.selectionID == selectionID { self.selectionID = nil } }
        do {
            try await product.selectDisplay(displayID)
            try await awaitViewPresentation(of: product)
            guard self.product === product else {
                throw ClientPrimaryLiveControlErrorV0.unavailable
            }
            phase = .active
        } catch is CancellationError {
            // The product already fenced input. Background recovery owns the
            // fresh presentation; local cancellation must not end Control.
            if self.product === product, phase == .awaitingVerifiedFrame { phase = .active }
            throw CancellationError()
        } catch {
            if self.product === product { fail(error) }
            throw error
        }
    }

    public func setAutomaticSmartZoomEnabled(_ enabled: Bool) async throws {
        try await product?.setAutomaticSmartZoomEnabled(enabled)
    }

    public func resumeAutomaticSmartZoom() async throws {
        try await product?.resumeAutomaticSmartZoom()
    }

    public func prepareTextInput() async throws -> Bool {
        guard phase == .active, let product else {
            throw ClientPrimaryLiveControlErrorV0.unavailable
        }
        let prepared = try await product.prepareTextInput()
        guard phase == .active, self.product === product else {
            throw ClientPrimaryLiveControlErrorV0.unavailable
        }
        return prepared
    }

    public func prepareNativeTextComposer() async throws
        -> SurfaceInputFence?
    {
        guard phase == .active, let product else {
            throw ClientPrimaryLiveControlErrorV0.unavailable
        }
        let binding = try await product.prepareNativeTextComposer()
        guard phase == .active, self.product === product else {
            throw ClientPrimaryLiveControlErrorV0.unavailable
        }
        return binding
    }

    public func sendComposedText(
        _ text: String,
        boundTo binding: SurfaceInputFence
    ) async throws {
        guard phase == .active, let product else {
            throw ClientPrimaryLiveControlErrorV0.unavailable
        }
        try await product.sendComposedText(text, boundTo: binding)
        guard phase == .active, self.product === product else {
            throw ClientPrimaryLiveControlErrorV0.unavailable
        }
    }

    public func selectSurface(_ choice: ClientSurfaceChoiceV0) async throws {
        guard selectionID == nil, !isViewTransitioning else {
            throw ClientPrimaryLiveControlErrorV0.viewTransitionInProgress
        }
        guard phase == .active, let product else {
            throw ClientPrimaryLiveControlErrorV0.unavailable
        }
        phase = .awaitingVerifiedFrame
        let selectionID = UUID()
        self.selectionID = selectionID
        defer { if self.selectionID == selectionID { self.selectionID = nil } }
        do {
            try await product.selectSurface(
                kind: choice.kind,
                targetToken: choice.targetToken
            )
            try await awaitViewPresentation(of: product)
            guard self.product === product else {
                throw ClientPrimaryLiveControlErrorV0.unavailable
            }
            phase = .active
        } catch is CancellationError {
            if self.product === product, phase == .awaitingVerifiedFrame { phase = .active }
            throw CancellationError()
        } catch {
            if self.product === product { fail(error) }
            throw error
        }
    }

    public func acceptWorkspaceMode(
        _ mode: ClientControlWorkspaceModeV0
    ) {
        switch mode {
        case .active:
            if product != nil, phase != .active, selectionID == nil, !isViewTransitioning {
                phase = .active
            }
        case .ending:
            guard phase != .ending, phase != .failed else { return }
            productGeneration = UUID()
            activationTask?.cancel()
            activationTask = nil
            product?.surface.setInputEnabled(false)
            phase = .ending
        case .preparationFailed:
            if phase != .failed && phase != .closed {
                fail(ClientPrimaryLiveControlErrorV0.unavailable)
            }
        case .endFailed, .rejected, .unavailable,
             .grantRequired:
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

    private func awaitViewPresentation(of expected: any ClientPrimaryLiveControlProductV0) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while isViewTransitioning {
            try Task.checkCancellation()
            guard product === expected, phase != .ending, phase != .failed, phase != .closed,
                  !videoRequiresRestart, ContinuousClock.now < deadline,
                  !(await expected.activationFailedOrClosed()) else {
                throw ClientPrimaryLiveControlErrorV0.unavailable
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func retireLocalProduct(
        as terminalPhase: ClientPrimaryLiveControlPhaseV0
    ) {
        guard product != nil || phase != terminalPhase else { return }
        productGeneration = UUID()
        selectionID = nil
        failureRetirement = nil
        let retiring = product
        product = nil
        phase = terminalPhase
        Task { await retiring?.close() }
    }

    private func prepare(
        mode: ClientInputInteractionModeV0,
        generation: UUID
    ) async {
        do {
            let retirement = await failureRetirementFactory()
            guard productGeneration == generation, !Task.isCancelled else { return }
            failureRetirement = retirement
            let value = try await
                productFactory(
                    mode,
                    { [weak self] error in
                        guard let self, self.productGeneration == generation else { return }
                        self.fail(error)
                    }
                )
            guard productGeneration == generation, !Task.isCancelled else {
                await value.close()
                return
            }
            product = value
            value.observeVideoRecovery { [weak self] required in
                guard let self, self.productGeneration == generation else { return }
                self.videoRequiresRestart = required
            }
            value.observeSurfaceTransition { [weak self] busy, message in
                guard let self, self.productGeneration == generation else { return }
                self.isViewTransitioning = busy
                self.viewTransitionMessage = message
            }
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
            guard productGeneration == generation, !Task.isCancelled else { return }
            fail(error)
        }
    }

    private func fail(_ error: any Error) {
        guard phase != .closed else { return }
        IOSClientRuntimeDiagnosticLogV0.record(
            "ui.live-control-coordinator.terminal",
            error: error
        )
        productGeneration = UUID()
        print(
            "[MacCompanion live-control] coordinator failed phase=\(String(describing: phase)) error=\(String(describing: error))"
        )
        activationTask?.cancel()
        activationTask = nil
        let retiring = product
        let retirement = failureRetirement
        failureRetirement = nil
        retiring?.surface.setInputEnabled(false)
        retiring?.surface.hideSoftwareKeyboard()
        product = nil
        phase = .failed
        Task {
            await retirement?()
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
    let viewState: ClientPrimaryLiveControlViewStateV0
    let keyboardModifiers: InteractiveModifierMask

    func makeUIView(context: Context) -> UIKitClientLiveSurfaceViewV0 {
        let view = product.surface
        view.useExternalSoftwareKeyboardBar()
        view.onSoftwareKeyboardVisibilityChanged = { [weak viewState] visible in
            viewState?.softwareKeyboardVisible = visible
            viewState?.keyboardInputNotice = nil
        }
        view.onSoftwareKeyboardInputOmitted = { [weak viewState] in
            viewState?.keyboardInputNotice = "This character couldn’t be sent with the Mac’s current keyboard access."
        }
        view.onSoftwareKeyboardModifiersCleared = { [weak viewState] in
            viewState?.remoteKeyboardModifiers = []
        }
        return view
    }

    func updateUIView(
        _ view: UIKitClientLiveSurfaceViewV0,
        context: Context
    ) {
        view.setMode(mode)
        view.setSoftwareKeyboardModifiers(keyboardModifiers)
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
    enum OptionsDestination { case display, surface, shortcuts, composer, study }
    @Published var mode = ClientInputInteractionModeV0.trackpad
    @Published var stopSubmitted = false
    @Published var showingSessionOptions = false
    var optionsDestination: OptionsDestination?
    @Published var showingSurfacePicker = false
    @Published var surfaceCandidates:
        [InteractiveSurfaceTargetCandidateV0] = []
    @Published var surfaceRequestInFlight = false
    @Published var surfaceCatalogNeedsRefresh = false
    var surfaceCatalogGeneration = UUID()
    @Published var displayCatalog:
        InteractiveDisplayCatalogResponseBodyV1?
    @Published var displayRequestInFlight = false
    @Published var pendingDisplayID: UUID?
    @Published var displayStatusMessage: String?
    @Published var showingDisplayPicker = false
    @Published var automaticSmartZoomEnabled = true
    @Published var showingRemoteKeyboard = false
    @Published var remoteKeyboardModifiers: InteractiveModifierMask = []
    @Published var softwareKeyboardVisible = false
    @Published var textComposer: ClientNativeTextComposerPresentationV0?
    @Published var keyboardPreparationInFlight = false
    @Published var showingComposerFocusHelp = false
    @Published var keyboardInputNotice: String?
    @Published var showingStudyJob = false
    @Published var studyJobInFlight = false
    @Published var studyJobRecorded = false
    @Published var selectedStudyCategory =
        Stage3StudyJobCategoryV1.controlUnexpectedDialog
    var studyControlAccumulator = ClientStage3StudyControlAccumulatorV1()
    var studyControlSurfaceKind = InteractiveSurfaceKind.desktop
    var studyControlIsActive = false
    var restoreKeyboardAfterViewPicker = false
    var surfaceSelectionInFlight = false
    var pendingTextPresentation: ClientPendingTextPresentationV0?

    var displaySelectionInFlight: Bool { pendingDisplayID != nil }
}

@available(iOS 17.0, *)
private enum ClientPendingTextPresentationV0 {
    case composer(SurfaceInputFence)
    case directKeyboard
}

@available(iOS 17.0, *)
private struct ClientNativeTextComposerPresentationV0:
    Identifiable, Equatable
{
    let binding: SurfaceInputFence
    var id: UUID { binding.focusToken ?? binding.surfaceID }
}

@available(iOS 17.0, *)
private struct ClientRemotePhysicalKeyV0: Identifiable {
    let label: String
    let usage: UInt16
    var id: UInt16 { usage }
}

@available(iOS 17.0, *)
struct ClientRemoteShortcutV0: Identifiable, Equatable {
    let id: String
    let label: String
    let systemImage: String
    let usage: UInt16
    let modifiers: InteractiveModifierMask
}

@available(iOS 17.0, *)
enum ClientRemoteShortcutCatalogV0 {
    static let appNext = ClientRemoteShortcutV0(
        id: "app-next", label: "App", systemImage: "app",
        usage: 0x2b, modifiers: [.leftCommand]
    )
    static let appPrevious = ClientRemoteShortcutV0(
        id: "app-previous", label: "Previous App", systemImage: "app",
        usage: 0x2b, modifiers: [.leftCommand, .leftShift]
    )
    static let tabNext = ClientRemoteShortcutV0(
        id: "tab-next", label: "Tab", systemImage: "rectangle.on.rectangle",
        usage: 0x2b, modifiers: [.leftControl]
    )
    static let tabPrevious = ClientRemoteShortcutV0(
        id: "tab-previous", label: "Previous Tab",
        systemImage: "rectangle.on.rectangle",
        usage: 0x2b, modifiers: [.leftControl, .leftShift]
    )
    static let windowNext = ClientRemoteShortcutV0(
        id: "window-next", label: "Next Window", systemImage: "macwindow",
        usage: 0x35, modifiers: [.leftCommand]
    )
    static let selectAll = ClientRemoteShortcutV0(
        id: "select-all", label: "Select", systemImage: "selection.pin.in.out",
        usage: 0x04, modifiers: [.leftCommand]
    )
    static let copy = ClientRemoteShortcutV0(
        id: "copy", label: "Copy", systemImage: "doc.on.doc",
        usage: 0x06, modifiers: [.leftCommand]
    )
    static let paste = ClientRemoteShortcutV0(
        id: "paste", label: "Paste", systemImage: "clipboard",
        usage: 0x19, modifiers: [.leftCommand]
    )
    static let screenshotFull = ClientRemoteShortcutV0(
        id: "screenshot-full", label: "Full Screen",
        systemImage: "camera", usage: 0x20,
        modifiers: [.leftCommand, .leftShift]
    )
    static let screenshotSelection = ClientRemoteShortcutV0(
        id: "screenshot-selection", label: "Screenshot",
        systemImage: "camera.viewfinder", usage: 0x21,
        modifiers: [.leftCommand, .leftShift]
    )
    static let screenshotOptions = ClientRemoteShortcutV0(
        id: "screenshot-options", label: "Screenshot Options",
        systemImage: "camera.badge.ellipsis", usage: 0x22,
        modifiers: [.leftCommand, .leftShift]
    )

    static let quick: [ClientRemoteShortcutV0] = [
        appNext, tabNext, selectAll, copy, paste, screenshotSelection,
    ]
    static let navigation: [ClientRemoteShortcutV0] = [
        appNext, appPrevious, tabNext, tabPrevious, windowNext,
    ]
    static let screenshots: [ClientRemoteShortcutV0] = [
        screenshotFull, screenshotSelection, screenshotOptions,
    ]
}

/// Remote physical-key controls are deliberately separate from Unicode text
/// insertion. These keys and shortcuts need Keyboard authority, but no text
/// field or focus token.
@available(iOS 17.0, *)
private struct ClientRemoteKeyboardViewV0: View {
    @Binding var modifiers: InteractiveModifierMask
    let textPreparationInFlight: Bool
    let onKey: (ClientKeyboardActionV0, InteractiveModifierMask) -> Void
    let onTypeText: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingMorePhysicalKeys = false

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 6
    )

    private var letters: [ClientRemotePhysicalKeyV0] {
        (0..<26).map { index in
            ClientRemotePhysicalKeyV0(
                label: String(UnicodeScalar(65 + index)!),
                usage: UInt16(0x04 + index)
            )
        }
    }

    private var digits: [ClientRemotePhysicalKeyV0] {
        (1...9).map { value in
            ClientRemotePhysicalKeyV0(
                label: String(value),
                usage: UInt16(0x1d + value)
            )
        } + [ClientRemotePhysicalKeyV0(label: "0", usage: 0x27)]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(
                        "Keys and shortcuts work in the active Mac app. "
                            + "They do not require an input field."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Button(
                        textPreparationInFlight
                            ? "Checking Keyboard Access…"
                            : "Use iOS Keyboard",
                        systemImage: "keyboard.badge.ellipsis",
                        action: onTypeText
                    )
                    .buttonStyle(.borderedProminent)
                    .disabled(textPreparationInFlight)

                    keySection("Modifiers") {
                        LazyVGrid(columns: Array(
                            repeating: GridItem(.flexible(), spacing: 8),
                            count: 4
                        ), spacing: 8) {
                            modifierButton("control", mask: .leftControl)
                            modifierButton("option", mask: .leftOption)
                            modifierButton("shift", mask: .leftShift)
                            modifierButton("command", mask: .leftCommand)
                        }
                    }

                    keySection("Common Shortcuts") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                shortcutButton("Select All", usage: 0x04)
                                shortcutButton("Copy", usage: 0x06)
                                shortcutButton("Paste", usage: 0x19)
                                shortcutButton("Cut", usage: 0x1b)
                                shortcutButton("Undo", usage: 0x1d)
                                shortcutButton(
                                    "Redo",
                                    usage: 0x1d,
                                    modifiers: [.leftCommand, .leftShift]
                                )
                                shortcutButton("Save", usage: 0x16)
                                shortcutButton("Find", usage: 0x09)
                                shortcutButton("Close", usage: 0x1a)
                            }
                        }
                    }

                    keySection("Navigate") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(ClientRemoteShortcutCatalogV0.navigation) {
                                    shortcutButton($0)
                                }
                            }
                        }
                    }

                    keySection("Screenshots") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(ClientRemoteShortcutCatalogV0.screenshots) {
                                    shortcutButton($0)
                                }
                            }
                        }
                    }

                    keySection("Special Keys") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                actionButton("esc", action: .escape)
                                actionButton("tab", action: .tab)
                                actionButton("return", action: .returnKey)
                                actionButton("delete", action: .deleteBackward)
                                actionButton("left", action: .arrowLeft)
                                actionButton("down", action: .arrowDown)
                                actionButton("up", action: .arrowUp)
                                actionButton("right", action: .arrowRight)
                            }
                        }
                    }

                    DisclosureGroup(
                        "More Physical Keys",
                        isExpanded: $showingMorePhysicalKeys
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            keySection("Letters") {
                                LazyVGrid(columns: columns, spacing: 8) {
                                    ForEach(letters) { key in
                                        physicalKeyButton(key)
                                    }
                                }
                            }
                            keySection("Numbers") {
                                LazyVGrid(columns: columns, spacing: 8) {
                                    ForEach(digits) { key in
                                        physicalKeyButton(key)
                                    }
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                .padding()
            }
            .navigationTitle("Keys & Shortcuts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func keySection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func modifierButton(
        _ label: String,
        mask: InteractiveModifierMask
    ) -> some View {
        let selected = modifiers.contains(mask)
        return Button(label) {
            if selected { modifiers.remove(mask) }
            else { modifiers.insert(mask) }
        }
        .buttonStyle(.bordered)
        .tint(selected ? .accentColor : .secondary)
        .accessibilityValue(selected ? "On" : "Off")
    }

    private func shortcutButton(
        _ label: String,
        usage: UInt16,
        modifiers: InteractiveModifierMask = [.leftCommand]
    ) -> some View {
        Button(label) {
            onKey(.physicalKey(usage: usage), modifiers)
        }
        .buttonStyle(.bordered)
    }

    private func shortcutButton(
        _ shortcut: ClientRemoteShortcutV0
    ) -> some View {
        Button(shortcut.label, systemImage: shortcut.systemImage) {
            onKey(
                .physicalKey(usage: shortcut.usage),
                shortcut.modifiers
            )
        }
        .buttonStyle(.bordered)
    }

    private func actionButton(
        _ label: String,
        action: ClientKeyboardActionV0
    ) -> some View {
        Button(label) { onKey(action, modifiers) }
            .buttonStyle(.bordered)
    }

    private func physicalKeyButton(
        _ key: ClientRemotePhysicalKeyV0
    ) -> some View {
        Button(key.label) {
            onKey(.physicalKey(usage: key.usage), modifiers)
        }
        .buttonStyle(.bordered)
    }
}

/// A phone-local composing surface for one exact verified Mac text focus. It
/// never displays or reads the Mac field value; only the uncommitted local
/// draft exists here, and it is sent once under the original focus fence.
@available(iOS 17.0, *)
private struct ClientNativeTextComposerViewV0: View {
    let onSend: @MainActor (String) async throws -> Void
    let onUseDirectKeyboard: () -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var editorFocused: Bool
    @State private var draft = ""
    @State private var sending = false
    @State private var errorText: String?

    private var utf8ByteCount: Int { draft.utf8.count }
    private var canSend: Bool {
        !draft.isEmpty && utf8ByteCount <= 4_096 && !sending
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    "Compose privately on this iPhone, then send the draft "
                        + "to the verified Mac input field. Mac Companion "
                        + "does not read the field's existing text."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                TextEditor(text: $draft)
                    .focused($editorFocused)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    .privacySensitive()
                    .accessibilityLabel("Text to send to Mac")

                HStack {
                    Text("\(utf8ByteCount) / 4096 bytes")
                        .foregroundStyle(
                            utf8ByteCount <= 4_096
                                ? Color.secondary : Color.red
                        )
                    Spacer()
                    Button("Use Direct Keyboard") {
                        onUseDirectKeyboard()
                        dismiss()
                    }
                    .disabled(sending)
                }
                .font(.caption)

                if let errorText {
                    Label(errorText, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("Composer send error")
                }
            }
            .padding()
            .navigationTitle("Type on Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(sending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "Sending…" : "Send") {
                        send()
                    }
                    .disabled(!canSend)
                    .accessibilityIdentifier("Send composed text")
                }
            }
            .task {
                editorFocused = true
            }
        }
        .interactiveDismissDisabled(sending)
    }

    private func send() {
        guard canSend else { return }
        sending = true
        errorText = nil
        let value = draft
        Task {
            do {
                try await onSend(value)
                draft = ""
                sending = false
                dismiss()
            } catch is CancellationError {
                sending = false
            } catch {
                sending = false
                errorText = "The Mac focus changed. Reopen the composer and try again."
            }
        }
    }
}

@available(iOS 17.0, *)
private struct ClientPrimaryControlStudyJobViewV1: View {
    @Binding var category: Stage3StudyJobCategoryV1
    let inFlight: Bool
    let recorded: Bool
    let onRecord: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Completed job") {
                    Picker("Category", selection: $category) {
                        Text("Handle an unexpected dialog").tag(
                            Stage3StudyJobCategoryV1
                                .controlUnexpectedDialog
                        )
                        Text("Use a development app").tag(
                            Stage3StudyJobCategoryV1.controlDevelopmentApp
                        )
                        Text("Use another app you own").tag(
                            Stage3StudyJobCategoryV1.controlOtherOwnedApp
                        )
                    }
                    .pickerStyle(.inline)
                }
                Section {
                    Button(
                        recorded ? "Job Added" : "Add Completed Job",
                        systemImage: recorded
                            ? "checkmark.circle.fill" : "plus.circle",
                        action: onRecord
                    )
                    .disabled(inFlight || recorded)
                } footer: {
                    Text(
                        "Only confirm a real completed job. The report adds "
                            + "closed surface kinds and aggregate active "
                            + "durations; it does not store the screen, input, "
                            + "window titles, or app identity."
                    )
                }
            }
            .navigationTitle("Study Job")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

@available(iOS 17.0, *)
public struct ClientPrimaryLiveControlViewV0: View {
    private let macName: String
    private let revision: UInt64
    private let control: ClientControlWorkspaceProjectionV0
    @ObservedObject private var coordinator:
        ClientPrimaryLiveControlCoordinatorV0
    @StateObject private var viewState: ClientPrimaryLiveControlViewStateV0
    @AppStorage("media.jenny.maccompanion.pointer-mode")
    private var preferredPointerModeRaw =
        ClientInputInteractionModeV0.trackpad.rawValue
    @Environment(\.dismiss) private var dismiss
    private let onCommandFailure:
        @MainActor @Sendable (any Error) -> Void
    private let onStop:
        @MainActor @Sendable () async throws -> Void
    private let onRecordStudyJob: @MainActor @Sendable (
        Stage3StudyJobCategoryV1,
        ClientStage3StudyControlSnapshotV1
    ) async throws -> Void

    public init(
        macName: String,
        revision: UInt64,
        control: ClientControlWorkspaceProjectionV0,
        coordinator: ClientPrimaryLiveControlCoordinatorV0,
        onStop: @escaping @MainActor @Sendable () async throws -> Void,
        onRecordStudyJob: @escaping @MainActor @Sendable (
            Stage3StudyJobCategoryV1,
            ClientStage3StudyControlSnapshotV1
        ) async throws -> Void,
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
        self.onRecordStudyJob = onRecordStudyJob
        self.onCommandFailure = onCommandFailure
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                if let product = coordinator.product {
                    ClientPrimaryInitialDesktopSurfaceV0(
                        product: product,
                        mode: viewState.mode,
                        viewState: viewState,
                        keyboardModifiers: viewState.remoteKeyboardModifiers
                    )
                    .allowsHitTesting(!coordinator.videoRequiresRestart && !coordinator.isViewTransitioning)
                    if coordinator.isViewTransitioning {
                        ProgressView(coordinator.viewTransitionMessage ?? "Switching view…")
                            .tint(.white).foregroundStyle(.white)
                            .padding().background(.black.opacity(0.8), in: Capsule())
                            .accessibilityIdentifier("Remote view switching")
                    } else if let message = coordinator.viewTransitionMessage {
                        VStack {
                            Spacer()
                            Text(message).font(.footnote).foregroundStyle(.white)
                                .padding().background(.black.opacity(0.8), in: Capsule())
                        }.padding()
                    }
                    if coordinator.videoRequiresRestart {
                        ContentUnavailableView(
                            "Remote Control needs to restart",
                            systemImage: "display.trianglebadge.exclamationmark",
                            description: Text(
                                "Tap Stop, then request Remote Control again to resume."
                            )
                        )
                        .foregroundStyle(.white)
                        .background(Color.black)
                        .accessibilityIdentifier("Remote Control restart required")
                    }
                } else if coordinator.phase == .failed {
                    ContentUnavailableView(
                        "Remote Control unavailable",
                        systemImage: "display.trianglebadge.exclamationmark",
                        description: Text(
                            "The selected view stopped streaming. Close this screen "
                                + "and request Remote Control again. You can then "
                                + "choose Desktop or another window."
                        )
                    )
                    .foregroundStyle(.white)
                } else {
                    ProgressView("Preparing a verified screen from \(macName)…")
                        .tint(.white)
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

        }
        .background(Color.black.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ClientRemoteSessionBarV0(
                modifiers: $viewState.remoteKeyboardModifiers,
                keyboardVisible: viewState.softwareKeyboardVisible,
                keyboardDisabled: coordinator.product == nil || viewState.stopSubmitted
                    || coordinator.phase == .failed || coordinator.phase == .ending || coordinator.phase == .closed,
                disabled: coordinator.phase != .active || coordinator.videoRequiresRestart || coordinator.isViewTransitioning
                    || viewState.surfaceSelectionInFlight || viewState.displaySelectionInFlight,
                onKeyboard: toggleSoftwareKeyboard,
                onKey: sendRemoteKey,
                onOptions: showSessionOptions
            )
        }
        .overlay(alignment: .bottom) {
            if let notice = viewState.keyboardInputNotice {
                Text(notice).font(.caption).foregroundStyle(.white)
                    .padding(10).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 66).allowsHitTesting(false)
                    .accessibilityIdentifier("Keyboard input notice")
            }
        }
        .navigationTitle(macName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.black.opacity(0.75), for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(canStop ? "Stop Remote Control" : "Close Remote Control", systemImage: "xmark") {
                    if canStop { stopRemoteControl() }
                    else { coordinator.closeLocalProduct(); dismiss() }
                }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("Stop Remote Control")
                    .disabled(viewState.stopSubmitted || (!canStop && coordinator.phase != .failed))
            }
        }
        .onAppear {
            let preferredMode = ClientInputInteractionModeV0(
                rawValue: preferredPointerModeRaw
            ) ?? .trackpad
            viewState.mode = preferredMode
            coordinator.start(mode: preferredMode)
            coordinator.acceptWorkspaceMode(
                control.mode
            )
            synchronizeStudyControlTiming()
        }
        .onChange(of: viewState.mode) { _, value in
            preferredPointerModeRaw = value.rawValue
            coordinator.updateMode(value)
        }
        .onChange(of: viewState.automaticSmartZoomEnabled) { _, value in
            Task {
                do {
                    try await coordinator
                        .setAutomaticSmartZoomEnabled(value)
                } catch {
                    onCommandFailure(error)
                }
            }
        }
        .onChange(of: coordinator.phase) { _, value in
            if value == .failed || value == .ending || value == .closed {
                viewState.showingRemoteKeyboard = false
                viewState.showingSurfacePicker = false
                viewState.showingDisplayPicker = false
                viewState.showingSessionOptions = false
                viewState.optionsDestination = nil
                viewState.textComposer = nil
                viewState.pendingTextPresentation = nil
                viewState.remoteKeyboardModifiers = []
                coordinator.product?.surface.hideSoftwareKeyboard()
            }
            synchronizeStudyControlTiming()
        }
        .onChange(of: coordinator.videoRequiresRestart) { _, required in
            guard required else { return }
            viewState.showingRemoteKeyboard = false
            viewState.showingDisplayPicker = false
            viewState.textComposer = nil
            viewState.pendingTextPresentation = nil
        }
        .onChange(of: coordinator.isViewTransitioning) { _, busy in
            if busy {
                // Inventory tokens are bound to the surface being replaced.
                // Keep an open picker fenced through fresh presentation and
                // the subsequent inventory read, including a late old read.
                viewState.surfaceCatalogGeneration = UUID()
                if viewState.showingSurfacePicker || viewState.surfaceRequestInFlight {
                    viewState.surfaceCatalogNeedsRefresh = true
                }
            } else if coordinator.phase == .active {
                if viewState.showingSurfacePicker && !viewState.surfaceSelectionInFlight {
                    requestSurfaceTargets(showPicker: false)
                }
                if viewState.showingDisplayPicker && !viewState.displaySelectionInFlight {
                    refreshDisplays(reportFailure: true)
                }
            }
        }
        .onChange(of: viewState.showingStudyJob) { _, value in
            if value {
                pauseStudyControlTiming()
            } else {
                synchronizeStudyControlTiming()
            }
        }
        .onChange(of: revision) { _, _ in
            let controlMode = control.mode
            coordinator.acceptWorkspaceMode(controlMode)
            if controlMode != .active {
                pauseStudyControlTiming()
            }
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
        .sheet(isPresented: $viewState.showingSessionOptions, onDismiss: finishSessionOptions) {
            NavigationStack {
                Form { sessionOptions }
                    .navigationTitle("Session Options")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { viewState.showingSessionOptions = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewState.showingSurfacePicker, onDismiss: restoreKeyboardAfterViewPicker) {
            ClientSurfacePickerViewV0(
                candidates: viewState.surfaceCandidates,
                isBusy: coordinator.isViewTransitioning || viewState.surfaceRequestInFlight
                    || viewState.surfaceCatalogNeedsRefresh,
                statusMessage: coordinator.viewTransitionMessage,
                onSelect: selectSurface,
                onRefresh: {
                    requestSurfaceTargets(showPicker: false)
                },
                onCancel: {
                    viewState.showingSurfacePicker = false
                }
            )
            .interactiveDismissDisabled(viewState.surfaceRequestInFlight)
        }
        // Preserve the admitted renderer's visible window hierarchy while
        // choosing a display. A full-screen cover can detach or hide it and
        // correctly trigger the native owner's irreversible presentation fence.
        .sheet(isPresented: $viewState.showingDisplayPicker, onDismiss: restoreKeyboardAfterViewPicker) {
            ClientSharedDisplayPickerV0(
                catalog: viewState.displayCatalog,
                requestInFlight: viewState.displayRequestInFlight || coordinator.isViewTransitioning,
                pendingDisplayID: viewState.pendingDisplayID,
                statusMessage: coordinator.viewTransitionMessage ?? viewState.displayStatusMessage,
                onSelect: { displayID in
                    selectDisplay(displayID)
                },
                onRefresh: {
                    refreshDisplays(reportFailure: true)
                },
                onCancel: {
                    viewState.showingDisplayPicker = false
                }
            )
            .interactiveDismissDisabled(
                viewState.displaySelectionInFlight
            )
        }
        .sheet(
            isPresented: $viewState.showingRemoteKeyboard,
            onDismiss: presentPendingTextPresentation
        ) {
            ClientRemoteKeyboardViewV0(
                modifiers: $viewState.remoteKeyboardModifiers,
                textPreparationInFlight:
                    viewState.keyboardPreparationInFlight,
                onKey: sendRemoteKey,
                onTypeText: prepareSoftwareKeyboard
            )
            .presentationDetents([.height(340), .medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $viewState.showingStudyJob) {
            ClientPrimaryControlStudyJobViewV1(
                category: $viewState.selectedStudyCategory,
                inFlight: viewState.studyJobInFlight,
                recorded: viewState.studyJobRecorded,
                onRecord: recordStudyJob
            )
            .interactiveDismissDisabled(viewState.studyJobInFlight)
        }
        .sheet(
            item: $viewState.textComposer,
            onDismiss: presentPendingTextPresentation
        ) { presentation in
            ClientNativeTextComposerViewV0(
                onSend: { value in
                    try await coordinator.sendComposedText(
                        value,
                        boundTo: presentation.binding
                    )
                },
                onUseDirectKeyboard: {
                    viewState.pendingTextPresentation = .directKeyboard
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert(
            "Text composer unavailable",
            isPresented: $viewState.showingComposerFocusHelp
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                "Choose an editable text field to use the composer. "
                    + "The keyboard and shortcuts remain available."
            )
        }
        .onDisappear {
            pauseStudyControlTiming()
        }
        .task(id: coordinator.phase) {
            guard coordinator.phase == .active else { return }
            while !Task.isCancelled, coordinator.phase == .active {
                refreshDisplays(reportFailure: false)
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    return
                }
            }
        }
    }

    @ViewBuilder
    private var sessionOptions: some View {
        Button("Shared Display", systemImage: "display.2") {
            leaveSessionOptions(for: .display)
        }
        .accessibilityIdentifier("Shared Display")
        .disabled(viewState.displaySelectionInFlight)
        Button("Choose Surface", systemImage: "rectangle.stack") {
            leaveSessionOptions(for: .surface)
        }
        .accessibilityIdentifier("Choose Surface")
        .disabled(viewState.surfaceRequestInFlight)
        Picker("Pointer mode", selection: $viewState.mode) {
            Text("Touch").tag(ClientInputInteractionModeV0.directTouch)
            Text("Trackpad").tag(ClientInputInteractionModeV0.trackpad)
        }
        .accessibilityIdentifier("Pointer mode")
        Divider()
        Button("Keys & Shortcuts", systemImage: "command") { leaveSessionOptions(for: .shortcuts) }
            .accessibilityIdentifier("All remote shortcuts")
        if let descriptor = coordinator.product?.descriptor,
           descriptor.kind == .focusedRegion,
           descriptor.focus?.category == .text,
           descriptor.focus?.editable == true,
           descriptor.focus?.secure == false {
            Button("Compose Text", systemImage: "square.and.pencil") { leaveSessionOptions(for: .composer) }
                .disabled(viewState.keyboardPreparationInFlight)
        }
        Button("Fit Screen", systemImage: "arrow.down.right.and.arrow.up.left", action: fitScreen)
        Toggle("Zoom to Focus Automatically", isOn: $viewState.automaticSmartZoomEnabled)
        Button("Resume Smart Zoom", systemImage: "scope", action: resumeSmartZoom)
        #if DEBUG
        Divider()
        Button("Record Test Job", systemImage: "checklist") {
            leaveSessionOptions(for: .study)
        }
        .disabled(viewState.studyJobInFlight)
        #endif
    }

    private func showSessionOptions() {
        guard coordinator.phase == .active, !coordinator.isViewTransitioning else { return }
        viewState.optionsDestination = nil
        viewState.restoreKeyboardAfterViewPicker = coordinator.product?.surface.isSoftwareKeyboardVisible == true
        coordinator.product?.surface.hideSoftwareKeyboard()
        viewState.showingSessionOptions = true
    }

    private func leaveSessionOptions(for destination: ClientPrimaryLiveControlViewStateV0.OptionsDestination) {
        viewState.optionsDestination = destination
        viewState.showingSessionOptions = false
    }

    private func finishSessionOptions() {
        let destination = viewState.optionsDestination
        viewState.optionsDestination = nil
        guard coordinator.phase == .active, !viewState.stopSubmitted else {
            viewState.restoreKeyboardAfterViewPicker = false
            return
        }
        // Present the next sheet only after options dismissal completes. This
        // avoids competing UIKit presentations and preserves the native view.
        switch destination {
        case .display:
            viewState.showingDisplayPicker = true
            refreshDisplays(reportFailure: true)
        case .surface:
            requestSurfaceTargets(showPicker: true)
        case .shortcuts:
            viewState.restoreKeyboardAfterViewPicker = false
            showRemoteKeyboard()
        case .composer:
            viewState.restoreKeyboardAfterViewPicker = false
            prepareTextComposer()
        case .study:
            viewState.restoreKeyboardAfterViewPicker = false
            viewState.studyJobRecorded = false
            viewState.showingStudyJob = true
        case nil:
            restoreKeyboardAfterViewPicker()
        }
    }

    private var canStop: Bool {
        switch control.mode {
        case .acceptedPreparingChannels, .channelsReady,
             .preparingInitialSurface, .active, .endFailed:
            true
        case .unavailable, .grantRequired, .ready, .requesting,
             .awaitingAcceptance,
             .ending, .preparationFailed, .rejected:
            false
        }
    }

    private var currentDisplayLabel: String {
        guard let catalog = viewState.displayCatalog,
              let selected = catalog.displays.first(where: {
                  $0.displayID == catalog.selectedDisplayID
              }) else {
            return viewState.displayRequestInFlight
                ? "Displays…" : "Display"
        }
        return "Display \(selected.ordinal)"
    }

    private func refreshDisplays(reportFailure: Bool) {
        guard coordinator.phase == .active,
              !viewState.displayRequestInFlight,
              !viewState.displaySelectionInFlight else { return }
        viewState.displayRequestInFlight = true
        if reportFailure {
            viewState.displayStatusMessage = nil
        }
        Task {
            do {
                viewState.displayCatalog = try await coordinator
                    .requestDisplayCatalog()
                viewState.displayRequestInFlight = false
                viewState.displayStatusMessage = nil
            } catch is CancellationError {
                viewState.displayRequestInFlight = false
            } catch {
                viewState.displayRequestInFlight = false
                print(
                    "[MacCompanion live-control] display catalog failed "
                        + "error=\(String(describing: error))"
                )
                if reportFailure {
                    viewState.displayStatusMessage =
                        "Couldn’t refresh displays. Try again."
                    onCommandFailure(error)
                }
            }
        }
    }

    private func selectDisplay(_ displayID: UUID) {
        guard coordinator.phase == .active,
              !coordinator.isViewTransitioning,
              !viewState.displaySelectionInFlight,
              viewState.displayCatalog?.selectedDisplayID.rawValue
                != displayID else { return }
        pauseStudyControlTiming()
        viewState.remoteKeyboardModifiers = []
        viewState.pendingDisplayID = displayID
        viewState.displayStatusMessage = nil
        Task {
            do {
                try await coordinator.selectDisplay(displayID)
                viewState.displayCatalog = try await coordinator
                    .requestDisplayCatalog()
                viewState.pendingDisplayID = nil
                synchronizeStudyControlTiming()
            } catch {
                viewState.pendingDisplayID = nil
                guard !(error is CancellationError) else { return }
                viewState.displayStatusMessage =
                    "Couldn’t confirm the display switch. Try again."
                synchronizeStudyControlTiming()
                onCommandFailure(error)
            }
        }
    }

    private func restoreKeyboardAfterViewPicker() {
        guard viewState.restoreKeyboardAfterViewPicker else { return }
        viewState.restoreKeyboardAfterViewPicker = false
        guard coordinator.phase == .active || coordinator.phase == .awaitingVerifiedFrame,
              !viewState.stopSubmitted else { return }
        coordinator.product?.surface.showSoftwareKeyboard()
    }

    private func fitScreen() {
        Task {
            await coordinator.product?.showWiderContext()
        }
    }

    private func resumeSmartZoom() {
        guard viewState.automaticSmartZoomEnabled else {
            // The existing on-change path enables and resumes automation.
            viewState.automaticSmartZoomEnabled = true
            return
        }
        Task {
            do {
                try await coordinator.resumeAutomaticSmartZoom()
            } catch {
                onCommandFailure(error)
            }
        }
    }

    private func stopRemoteControl() {
        pauseStudyControlTiming()
        // Stop must not depend on UIKit first retiring an active direct-keyboard
        // responder. Dismiss local input immediately; the authenticated End
        // command remains the only operation that retires remote Control.
        coordinator.product?.surface.hideSoftwareKeyboard()
        viewState.pendingTextPresentation = nil
        viewState.textComposer = nil
        viewState.showingRemoteKeyboard = false
        viewState.stopSubmitted = true
        Task {
            do { try await onStop() }
            catch {
                viewState.stopSubmitted = false
                onCommandFailure(error)
            }
        }
    }

    private func requestSurfaceTargets(showPicker: Bool) {
        guard !viewState.surfaceRequestInFlight else { return }
        guard !coordinator.isViewTransitioning else {
            viewState.surfaceCatalogNeedsRefresh = true
            if showPicker { viewState.showingSurfacePicker = true }
            return
        }
        IOSClientRuntimeDiagnosticLogV0.record("view-picker.requested")
        viewState.surfaceRequestInFlight = true
        let generation = viewState.surfaceCatalogGeneration
        if showPicker {
            viewState.restoreKeyboardAfterViewPicker = viewState.restoreKeyboardAfterViewPicker
                || coordinator.product?.surface.isSoftwareKeyboardVisible == true
        }
        Task {
            do {
                let candidates = try await coordinator.requestSurfaceTargets()
                guard generation == viewState.surfaceCatalogGeneration else {
                    finishObsoleteSurfaceInventory(showPicker: showPicker)
                    return
                }
                viewState.surfaceCandidates = candidates
                viewState.surfaceCatalogNeedsRefresh = false
                viewState.surfaceRequestInFlight = false
                if showPicker { viewState.showingSurfacePicker = true }
                IOSClientRuntimeDiagnosticLogV0.record("view-picker.ready")
            } catch {
                guard generation == viewState.surfaceCatalogGeneration else {
                    finishObsoleteSurfaceInventory(showPicker: showPicker)
                    return
                }
                IOSClientRuntimeDiagnosticLogV0.record("view-picker.failed", error: error)
                viewState.surfaceRequestInFlight = false
                viewState.showingSurfacePicker = false
                onCommandFailure(error)
            }
        }
    }

    private func finishObsoleteSurfaceInventory(showPicker: Bool) {
        viewState.surfaceRequestInFlight = false
        guard coordinator.phase == .active, !viewState.stopSubmitted else { return }
        if viewState.showingSurfacePicker || showPicker {
            requestSurfaceTargets(showPicker: showPicker)
        }
    }

    private func selectSurface(_ choice: ClientSurfaceChoiceV0) {
        guard coordinator.phase == .active, !coordinator.isViewTransitioning,
              !viewState.surfaceRequestInFlight, !viewState.surfaceCatalogNeedsRefresh else { return }
        pauseStudyControlTiming()
        viewState.remoteKeyboardModifiers = []
        viewState.surfaceSelectionInFlight = true
        viewState.surfaceRequestInFlight = true
        Task {
            do {
                try await coordinator.selectSurface(choice)
                viewState.studyControlSurfaceKind = choice.kind
                viewState.surfaceSelectionInFlight = false
                synchronizeStudyControlTiming()
                viewState.surfaceRequestInFlight = false
                viewState.showingSurfacePicker = false
            } catch {
                viewState.surfaceSelectionInFlight = false
                viewState.surfaceRequestInFlight = false
                viewState.showingSurfacePicker = false
                guard !(error is CancellationError) else { return }
                onCommandFailure(error)
            }
        }
    }

    private func showRemoteKeyboard() {
        coordinator.product?.surface.hideSoftwareKeyboard()
        viewState.pendingTextPresentation = nil
        viewState.textComposer = nil
        viewState.showingRemoteKeyboard = true
    }

    private func sendRemoteKey(
        _ action: ClientKeyboardActionV0,
        modifiers: InteractiveModifierMask
    ) {
        coordinator.product?.surface.sendKeyboardAction(
            action,
            modifiers: modifiers
        )
        viewState.remoteKeyboardModifiers = []
    }

    private func sendRemoteShortcut(_ shortcut: ClientRemoteShortcutV0) {
        sendRemoteKey(
            .physicalKey(usage: shortcut.usage),
            modifiers: shortcut.modifiers
        )
    }

    private func prepareSoftwareKeyboard() {
        prepareSoftwareKeyboard(dismissingShortcuts: true)
    }

    private func toggleSoftwareKeyboard() {
        guard let surface = coordinator.product?.surface else { return }
        if surface.isSoftwareKeyboardVisible {
            surface.hideSoftwareKeyboard()
            return
        }
        prepareSoftwareKeyboard(dismissingShortcuts: false)
    }

    private func prepareSoftwareKeyboard(dismissingShortcuts: Bool) {
        // Opening local UI has no Text, focus, or renderer preflight. Delivery
        // still requires current admitted Control/Keyboard authority.
        if dismissingShortcuts {
            viewState.pendingTextPresentation = .directKeyboard
            viewState.showingRemoteKeyboard = false
        } else {
            presentTextPresentation(.directKeyboard)
        }
    }

    private func prepareTextComposer() {
        guard !viewState.keyboardPreparationInFlight else { return }
        viewState.keyboardPreparationInFlight = true
        Task {
            defer { viewState.keyboardPreparationInFlight = false }
            do {
                if let binding = try await coordinator.prepareNativeTextComposer() {
                    presentTextPresentation(.composer(binding))
                } else { viewState.showingComposerFocusHelp = true }
            } catch { onCommandFailure(error) }
        }
    }

    private func presentPendingTextPresentation() {
        guard let pending = viewState.pendingTextPresentation else { return }
        viewState.pendingTextPresentation = nil
        presentTextPresentation(pending)
    }

    private func presentTextPresentation(
        _ presentation: ClientPendingTextPresentationV0
    ) {
        switch presentation {
        case let .composer(binding):
            coordinator.product?.surface.hideSoftwareKeyboard()
            viewState.textComposer = ClientNativeTextComposerPresentationV0(
                binding: binding
            )
        case .directKeyboard:
            coordinator.product?.surface.showSoftwareKeyboard()
        }
    }

    private func synchronizeStudyControlTiming() {
        guard coordinator.phase == .active,
              !viewState.surfaceSelectionInFlight,
              !viewState.showingStudyJob else {
            pauseStudyControlTiming()
            return
        }
        guard !viewState.studyControlIsActive else { return }
        do {
            try viewState.studyControlAccumulator.resume(
                surfaceKind: viewState.studyControlSurfaceKind,
                at: studyMonotonicMilliseconds()
            )
            viewState.studyControlIsActive = true
        } catch {
            onCommandFailure(error)
        }
    }

    private func pauseStudyControlTiming() {
        guard viewState.studyControlIsActive else { return }
        do {
            try viewState.studyControlAccumulator.pause(
                at: studyMonotonicMilliseconds()
            )
            viewState.studyControlIsActive = false
        } catch {
            onCommandFailure(error)
        }
    }

    private func recordStudyJob() {
        guard !viewState.studyJobInFlight,
              !viewState.studyJobRecorded else { return }
        let recordedAt = studyMonotonicMilliseconds()
        let snapshot: ClientStage3StudyControlSnapshotV1
        do {
            snapshot = try viewState.studyControlAccumulator.snapshot(
                at: recordedAt
            )
        } catch {
            onCommandFailure(error)
            return
        }
        viewState.studyJobInFlight = true
        Task {
            do {
                try await onRecordStudyJob(
                    viewState.selectedStudyCategory,
                    snapshot
                )
                viewState.studyControlAccumulator =
                    ClientStage3StudyControlAccumulatorV1()
                viewState.studyControlIsActive = false
                viewState.studyJobRecorded = true
                viewState.studyJobInFlight = false
                synchronizeStudyControlTiming()
            } catch {
                viewState.studyJobInFlight = false
                onCommandFailure(error)
            }
        }
    }

    private func studyMonotonicMilliseconds() -> Int64 {
        let value = DispatchTime.now().uptimeNanoseconds / 1_000_000
        guard value <= UInt64(Int64.max) else { return -1 }
        return Int64(value)
    }
}
#endif
