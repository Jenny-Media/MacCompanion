import CompanionClient
import CompanionClientPlatform
import CompanionClientUI
import CompanionDiscovery
import CompanionInteractiveClient
import CompanionInteractiveShared
import CompanionInteractiveWire
import CompanionPresentation
import CompanionWire
import Foundation
import SwiftUI
import UIKit

struct HarnessContentView: View {
    @State private var showingSurfacePicker = false
    @EnvironmentObject private var lifecycle:
        HarnessApplicationLifecycleModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("No networking or credentials", systemImage: "network.slash")
                    Text("This disposable target renders closed package states only.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Simulator Harness")
                }

                Section("Observe and Act") {
                    NavigationLink("Host Summary") {
                        HostStateHarnessView()
                    }
                    NavigationLink("Mac Status") {
                        ObserveHarnessView()
                    }
                    NavigationLink("Approved Actions") {
                        ApprovedActionsHarnessView()
                    }
                    NavigationLink("Pairing Entry") {
                        ClientPairingViewV0(
                            presentation: PairingClientPresentation(),
                            onScan: {},
                            onAcceptPreview: {},
                            onCancel: {},
                            onRetry: {},
                            onDone: {}
                        )
                    }
                }

                Section("Private Routes") {
                    NavigationLink("Private Access Guidance") {
                        RouteGuidanceHarnessView()
                    }
                    NavigationLink("Application Lifecycle") {
                        HarnessApplicationLifecycleView()
                    }
                    NavigationLink("First-Pairing Route Choices") {
                        RouteBootstrapHarnessView()
                    }
                    NavigationLink("Edit Saved Routes") {
                        RouteEditorHarnessView()
                    }
                }

                Section("Optional Control") {
                    NavigationLink("Retired Control Callbacks") {
                        RetiredControlCallbackHarnessView()
                    }
                    NavigationLink("Live Control Screen") {
                        LiveControlHarnessView()
                    }
                    Button("Choose Mac View") {
                        showingSurfacePicker = true
                    }
                    Text("Remote Control is one independently authorized capability, not the app shell.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Mac Companion")
        }
        .sheet(isPresented: $showingSurfacePicker) {
            SurfacePickerHarnessView()
        }
    }
}

private struct RouteGuidanceHarnessView: View {
    @EnvironmentObject private var lifecycle:
        HarnessApplicationLifecycleModel

    var body: some View {
        ClientPrivateRouteGuidanceViewV1(
            projection: lifecycle.routeGuidance
        )
    }
}

@MainActor
private final class HarnessLiveControlProduct:
    ClientPrimaryLiveControlProductV0
{
    let descriptor: AdaptiveSurfaceDescriptor
    let surface: UIKitClientLiveSurfaceViewV0
    private let composerBinding: SurfaceInputFence
    private let onPayloads: ([InteractiveInputPayload]) -> Void
    private(set) var closeCount = 0

    init(onPayloads: @escaping ([InteractiveInputPayload]) -> Void) {
        self.onPayloads = onPayloads
        descriptor = try! AdaptiveSurfaceDescriptor(
            interactiveSessionID: UUID(
                uuidString: "018f6000-0000-7000-8000-000000000001"
            )!,
            authorizationEpoch: .init(rawValue: 4),
            surfaceID: UUID(
                uuidString: "018f6100-0000-7000-8000-000000000001"
            )!,
            kind: .desktop,
            surfaceRevision: .init(rawValue: 1),
            coordinateSpaceRevision: .init(rawValue: 1),
            encodedWidth: 1_280,
            encodedHeight: 720,
            logicalWidthPoints: 1_280,
            logicalHeightPoints: 720,
            interactionClasses: [.view, .pointer, .keyboard, .text],
            privacyProfile: .visualOnly,
            metadataFields: [],
            createdAtMonotonicMilliseconds: 1_000,
            expiresAtMonotonicMilliseconds: 61_000
        )
        composerBinding = SurfaceInputFence(
            interactiveSessionID: descriptor.interactiveSessionID,
            authorizationEpoch: descriptor.authorizationEpoch,
            surfaceID: descriptor.surfaceID,
            surfaceRevision: descriptor.surfaceRevision,
            coordinateSpaceRevision: descriptor.coordinateSpaceRevision
        )
        surface = UIKitClientLiveSurfaceViewV0(
            mode: .directTouch,
            onPayloads: onPayloads,
            onFailure: { _ in }
        )
        let simulatedDesktop = UILabel()
        simulatedDesktop.translatesAutoresizingMaskIntoConstraints = false
        simulatedDesktop.text = "Synthetic Desktop\nNo network or captured pixels"
        simulatedDesktop.numberOfLines = 2
        simulatedDesktop.textAlignment = .center
        simulatedDesktop.textColor = .white
        simulatedDesktop.font = .preferredFont(forTextStyle: .title2)
        simulatedDesktop.isUserInteractionEnabled = false
        simulatedDesktop.accessibilityIdentifier = "Synthetic desktop"
        surface.addSubview(simulatedDesktop)
        NSLayoutConstraint.activate([
            simulatedDesktop.centerXAnchor.constraint(
                equalTo: surface.centerXAnchor
            ),
            simulatedDesktop.centerYAnchor.constraint(
                equalTo: surface.centerYAnchor
            ),
        ])
    }

    func refreshPrimaryState() async -> Bool {
        surface.setInputEnabled(true)
        return true
    }

    func activationFailedOrClosed() async -> Bool { false }

    func requestSurfaceTargets() async throws
        -> [InteractiveSurfaceTargetCandidateV0]
    {
        HarnessFixtures.surfaceCandidates
    }

    func requestDisplayCatalog() async throws
        -> InteractiveDisplayCatalogResponseBodyV1
    {
        let displayID = UUID(
            uuidString: "018f6700-0000-7000-8000-000000000001"
        )!
        return try InteractiveDisplayCatalogResponseBodyV1(
            authorizationEpoch: descriptor.authorizationEpoch,
            admissionRevision: 1,
            selectedDisplayID: WireUUID(displayID),
            validForMilliseconds: 5_000,
            displays: [
                try InteractiveDisplayCandidateV1(
                    displayID: WireUUID(displayID),
                    ordinal: 1,
                    pixelWidth: 1_280,
                    pixelHeight: 720,
                    layoutX: 0,
                    layoutY: 0,
                    layoutWidth: 1_280,
                    layoutHeight: 720,
                    isMain: true
                ),
            ]
        )
    }

    func selectDisplay(_ displayID: UUID) async throws {}

    func setAutomaticSmartZoomEnabled(_ enabled: Bool) async throws {}

    func prepareNativeTextComposer() async throws -> SurfaceInputFence? {
        composerBinding
    }

    func sendComposedText(
        _ text: String,
        boundTo binding: SurfaceInputFence
    ) async throws {
        guard binding == composerBinding else {
            throw ClientPrimaryLiveControlErrorV0.unavailable
        }
        let payload = InteractiveInputPayload.text(text)
        try payload.validate()
        onPayloads([payload])
    }

    func prepareTextInput() async throws -> Bool { true }

    func selectSurface(
        kind: InteractiveSurfaceKind,
        targetToken: UUID?
    ) async throws {}

    func close() async {
        closeCount += 1
        surface.resetInputAndBlank()
    }
}

@MainActor
private final class RetiredControlCallbackHarnessModel: ObservableObject {
    @Published var result = "Running"
    var callbacks: [ClientPrimaryLiveControlCoordinatorV0.Failure] = []
    var failures = 0
    var continuation: CheckedContinuation<Void, Never>?

    func run() async {
        let coordinator = ClientPrimaryLiveControlCoordinatorV0(
            productFactory: { [self] _, callback in
                callbacks.append(callback)
                return HarnessLiveControlProduct(onPayloads: { _ in })
            }, failure: { [self] _ in failures += 1 })
        coordinator.start(mode: .directTouch)
        guard await eventually({ coordinator.phase == .active }) else { result = "Initial activation failed"; return }
        coordinator.acceptWorkspaceMode(.unavailable)
        callbacks[0](ClientPrimaryLiveControlErrorV0.unavailable)
        guard failures == 0, coordinator.phase == .failed else { result = "Retired callback escaped"; return }
        coordinator.start(mode: .directTouch)
        guard await eventually({ coordinator.phase == .active }) else { result = "Replacement failed"; return }
        callbacks[0](ClientPrimaryLiveControlErrorV0.unavailable)
        guard failures == 0, coordinator.phase == .active else { result = "Old callback retired replacement"; return }
        callbacks[1](ClientPrimaryLiveControlErrorV0.unavailable)
        guard failures == 1, coordinator.phase == .failed else { result = "Current failure was hidden"; return }

        let late = HarnessLiveControlProduct(onPayloads: { _ in })
        let delayed = ClientPrimaryLiveControlCoordinatorV0(
            productFactory: { [self] _, callback in
                callbacks.append(callback)
                await withCheckedContinuation { continuation = $0 }
                return late
            }, failure: { [self] _ in failures += 1 })
        delayed.start(mode: .directTouch)
        guard await eventually({ self.continuation != nil }) else { result = "Delayed factory did not start"; return }
        delayed.closeLocalProduct()
        continuation?.resume(); continuation = nil
        guard await eventually({ late.closeCount == 1 }) else { result = "Late product was leaked"; return }
        callbacks[2](ClientPrimaryLiveControlErrorV0.unavailable)
        guard failures == 1, delayed.phase == .closed else { result = "Closed coordinator changed"; return }
        result = "Passed"
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

private struct RetiredControlCallbackHarnessView: View {
    @StateObject private var model = RetiredControlCallbackHarnessModel()
    var body: some View {
        Text(model.result).accessibilityIdentifier("Retired callback regression")
            .navigationTitle("Retired Control Callbacks")
            .task { await model.run() }
    }
}

@MainActor
private final class HarnessLiveControlModel: ObservableObject {
    @Published private(set) var revision: UInt64 = 1
    @Published private(set) var control =
        ClientControlWorkspaceProjectionV0(
            connected: true,
            deviceState: .activeGranted,
            state: .active(
                interactiveSessionID: UUID(
                    uuidString:
                        "018f6000-0000-7000-8000-000000000001"
                )!,
                expiresAtUnixMilliseconds: 1_725_000_060_000,
                effects: [.view, .pointer, .keyboard, .text]
            )
        )
    @Published private(set) var inputPayloadCount = 0
    @Published private(set) var textEventCount = 0
    @Published private(set) var textScalarCount = 0
    @Published private(set) var whitespaceTextEventCount = 0
    @Published private(set) var expectedWordMatched = false
    @Published private(set) var expectedWordAndSpaceMatched = false

    private var receivedText = ""
    private static let expectedWord = "hello"

    private lazy var product = HarnessLiveControlProduct {
        [weak self] payloads in self?.record(payloads)
    }
    lazy var coordinator = ClientPrimaryLiveControlCoordinatorV0(
        productFactory: { [weak self] _, _ in
            guard let self else {
                throw ClientPrimaryLiveControlErrorV0
                    .activationDeadlineExceeded
            }
            return self.product
        }
    )

    private func record(_ payloads: [InteractiveInputPayload]) {
        inputPayloadCount += payloads.count
        for payload in payloads {
            guard case let .text(value) = payload else { continue }
            textEventCount += 1
            textScalarCount += value.unicodeScalars.count
            if !value.isEmpty,
               value.unicodeScalars.allSatisfy({
                   CharacterSet.whitespacesAndNewlines.contains($0)
               }) {
                whitespaceTextEventCount += 1
            }
            receivedText += value
        }
        expectedWordMatched = receivedText == Self.expectedWord
        expectedWordAndSpaceMatched =
            receivedText == Self.expectedWord + " "
    }

    func stop() async throws {
        control = ClientControlWorkspaceProjectionV0(
            connected: true,
            deviceState: .activeGranted,
            state: .ending(
                interactiveSessionID: UUID(
                    uuidString:
                        "018f6000-0000-7000-8000-000000000001"
                )!,
                effects: [.view, .pointer, .keyboard, .text]
            )
        )
        revision += 1
        try await Task.sleep(for: .milliseconds(150))
        control = ClientControlWorkspaceProjectionV0(
            connected: true,
            deviceState: .activeGranted,
            state: .inactive
        )
        revision += 1
    }
}

private struct LiveControlHarnessView: View {
    @StateObject private var model = HarnessLiveControlModel()

    var body: some View {
        ClientPrimaryLiveControlViewV0(
            macName: "Studio Mac",
            revision: model.revision,
            control: model.control,
            coordinator: model.coordinator,
            onStop: { try await model.stop() },
            onRecordStudyJob: { _, _ in }
        )
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Synthetic input payloads: \(model.inputPayloadCount)")
                    .accessibilityLabel(
                        "Synthetic input payloads, \(model.inputPayloadCount)"
                    )
                    .accessibilityIdentifier("Synthetic input payload count")
                Text("Synthetic text events: \(model.textEventCount)")
                    .accessibilityLabel(
                        "Synthetic text events, \(model.textEventCount)"
                    )
                    .accessibilityIdentifier("Synthetic text event count")
                Text("Synthetic text scalars: \(model.textScalarCount)")
                    .accessibilityLabel(
                        "Synthetic text scalars, \(model.textScalarCount)"
                    )
                    .accessibilityIdentifier("Synthetic text scalar count")
                Text(
                    "Synthetic whitespace events: \(model.whitespaceTextEventCount)"
                )
                .accessibilityLabel(
                    "Synthetic whitespace events, \(model.whitespaceTextEventCount)"
                )
                .accessibilityIdentifier("Synthetic whitespace event count")
                Text(
                    "Synthetic word sequence: \(model.expectedWordMatched ? "Matched" : "Not matched")"
                )
                .accessibilityLabel(
                    "Synthetic word sequence, \(model.expectedWordMatched ? "Matched" : "Not matched")"
                )
                .accessibilityIdentifier("Synthetic word sequence match")
                Text(
                    "Synthetic word plus space sequence: \(model.expectedWordAndSpaceMatched ? "Matched" : "Not matched")"
                )
                .accessibilityLabel(
                    "Synthetic word plus space sequence, \(model.expectedWordAndSpaceMatched ? "Matched" : "Not matched")"
                )
                .accessibilityIdentifier(
                    "Synthetic word plus space sequence match"
                )
            }
            // Test evidence only: never obstruct product controls underneath.
            .allowsHitTesting(false)
            .font(.caption2)
            .foregroundStyle(.white)
            .padding(8)
            .background(.black.opacity(0.7))
        }
    }
}

private struct ObserveHarnessView: View {
    @State private var refreshCount = 0
    @State private var activityCount = 0

    var body: some View {
        ClientObserveViewV0(
            projection: HarnessFixtures.observeProjection,
            onRefreshStatus: { refreshCount += 1 },
            onLoadActivity: { activityCount += 1 },
            onLoadOlderActivity: { activityCount += 1 },
            onRecordStudyJob: { _ in }
        )
        .safeAreaInset(edge: .bottom) {
            Text("Typed synthetic Observe flow; no socket or Remote Control. Refreshes: \(refreshCount), activity requests: \(activityCount)")
                .font(.footnote)
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(.regularMaterial)
                .accessibilityIdentifier("Observe harness limitation")
        }
    }
}

private struct ApprovedActionsHarnessView: View {
    @State private var selectedCapabilityID: String?
    @State private var reloadCount = 0

    var body: some View {
        ClientApprovedActionsViewV1(
            macName: "Studio Mac",
            catalog: HarnessFixtures.approvedActionCatalog,
            onSelect: { selectedCapabilityID = $0.capabilityID },
            onReload: { reloadCount += 1 }
        )
        .safeAreaInset(edge: .bottom) {
            Text("Typed synthetic Act flow; no socket, credential, or signer. Reloads: \(reloadCount)")
                .font(.footnote)
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(.regularMaterial)
                .accessibilityIdentifier("Act harness limitation")
        }
        .navigationDestination(item: $selectedCapabilityID) { capabilityID in
            if let descriptor = HarnessFixtures.approvedActionCatalog
                .capability(capabilityID) {
                ApprovedActionDetailHarnessView(descriptor: descriptor)
            }
        }
    }
}

private struct ApprovedActionDetailHarnessView: View {
    let descriptor: CapabilityDiscoveryDescriptorV1
    @State private var draft: ClientCapabilityParameterDraftV1
    @State private var operationState: ClientOperationSessionStateV1 = .idle
    @State private var explicitEffectReview = false

    init(descriptor: CapabilityDiscoveryDescriptorV1) {
        self.descriptor = descriptor
        _draft = State(initialValue: try! ClientCapabilityParameterDraftV1(
            schema: CapabilitySchemaV1(wireValue: descriptor.parameterSchema)
        ))
    }

    var body: some View {
        ClientApprovedActionDetailViewV1(
            macName: "Studio Mac",
            descriptor: descriptor,
            draft: $draft,
            operationState: operationState,
            explicitEffectReview: $explicitEffectReview,
            onInvoke: { parameters in
                // This harness owns no command or signing authority. It feeds
                // one typed, schema-validated result into the real projection.
                operationState = .terminal(.succeeded(
                    verifiedResult: parameters
                ))
            },
            onCancel: {
                operationState = .terminal(.cancelled)
            },
            onQuery: {
                operationState = .observing(.queued)
            }
        )
    }
}

private struct HarnessApplicationLifecycleView: View {
    @EnvironmentObject private var lifecycle:
        HarnessApplicationLifecycleModel

    var body: some View {
        List {
            LabeledContent("Binding", value: lifecycle.bindingState)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("Lifecycle binding")
            LabeledContent(
                "App state",
                value: lifecycle.foreground ? "Foreground" : "Background"
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("Lifecycle app state")
            LabeledContent(
                "Injected network",
                value: lifecycle.networkReachable
                    ? "Reachable" : "Not reachable"
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("Lifecycle network")
            LabeledContent(
                "Synthetic dial rounds",
                value: String(lifecycle.dialRounds)
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("Lifecycle dial rounds")
            LabeledContent(
                "Terminal failures",
                value: String(lifecycle.terminalFailures)
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("Lifecycle terminal failures")
            LabeledContent(
                "Private access",
                value: lifecycle.routeGuidance.status.title
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("Lifecycle private access")
            Button(
                lifecycle.networkReachable
                    ? "Set Not Reachable" : "Set Reachable"
            ) {
                lifecycle.toggleReachability()
            }
            Text("The adapter receives UIKit app-active notifications and an injected Boolean reachability stream. Dial outcomes are synthetic; this screen never opens a socket.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .navigationTitle("Application Lifecycle")
    }
}

private struct HostStateHarnessView: View {
    @State private var sample = HarnessHostSample.ready

    var body: some View {
        VStack(spacing: 0) {
            Picker("Host state", selection: $sample) {
                ForEach(HarnessHostSample.allCases) { value in
                    Text(value.rawValue).tag(value)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal)

            ClientHostSummaryViewV0(
                snapshot: HarnessFixtures.hostSnapshot(sample),
                onPrimaryAction: { _ in }
            )
        }
    }
}

private struct RouteBootstrapHarnessView: View {
    @State private var selections: [
        EndpointCandidate: ClientRouteConfigurationTypeV1
    ] = [:]
    @State private var result: String?

    var body: some View {
        ClientRouteBootstrapChoiceViewV1(
            plan: HarnessFixtures.bootstrapPlan,
            selections: selections,
            onSelect: { endpoint, selection in
                selections[endpoint] = selection
                result = nil
            },
            onCancel: {
                selections.removeAll()
                result = "Cancelled: no route configuration was published."
            },
            onComplete: { choices in
                result = "Validated \(choices.count) explicit route choices; no network started."
            }
        )
        .safeAreaInset(edge: .bottom) {
            if let result {
                Text(result)
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(.regularMaterial)
                    .accessibilityLabel("Harness result")
            }
        }
    }
}

private struct RouteEditorHarnessView: View {
    @State private var snapshot = HarnessFixtures.initialRouteSnapshot
    @State private var editorState = ClientRouteConfigurationViewStateV1()
    @State private var result: String?

    var body: some View {
        ClientRouteConfigurationViewV1(
            snapshot: snapshot,
            state: editorState,
            onStateChange: { editorState = $0 },
            onIntent: apply
        )
        .safeAreaInset(edge: .bottom) {
            if let result {
                Text(result)
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(.regularMaterial)
                    .accessibilityLabel("Harness result")
            }
        }
    }

    private func apply(_ intent: ClientConfiguredRouteEditIntentV1) {
        do {
            let nextByte = UInt8(snapshot.catalog.records.count + 10)
            snapshot = try ClientConfiguredRouteEditorV1.apply(
                intent,
                to: snapshot,
                newRouteID: {
                    try WireBytes16(Data(repeating: nextByte, count: 16))
                }
            )
            editorState = editorState.reporting(nil)
            result = "Applied in memory at revision \(snapshot.revision)."
        } catch {
            result = "Rejected without changing the in-memory catalog."
        }
    }
}

private struct SurfacePickerHarnessView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var result = "No surface selected."

    var body: some View {
        VStack(spacing: 0) {
            ClientSurfacePickerViewV0(
                candidates: HarnessFixtures.surfaceCandidates,
                onSelect: { choice in
                    result = "Selected \(String(describing: choice.kind)); no session started."
                },
                onRefresh: {
                    result = "Refreshed the static privacy-limited fixture."
                },
                onCancel: {
                    dismiss()
                }
            )
            Text(result)
                .font(.footnote)
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(.regularMaterial)
                .accessibilityIdentifier("Harness result")
        }
    }
}
