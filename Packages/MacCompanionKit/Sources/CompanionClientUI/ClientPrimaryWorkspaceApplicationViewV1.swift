#if os(iOS)
import CompanionClient
import CompanionClientNetworkPlatform
import CompanionWire
import SwiftUI

@available(iOS 17.0, *)
private struct ClientApprovedActionDestinationV1: Identifiable {
    let id: String
    let descriptor: CapabilityDiscoveryDescriptorV1

    init(_ descriptor: CapabilityDiscoveryDescriptorV1) {
        id = descriptor.capabilityID
        self.descriptor = descriptor
    }
}

/// Remote-desktop MVP shell over the authenticated primary workspace.
/// Deferred action-sheet plumbing remains for protocol compatibility.
@available(iOS 17.0, *)
public struct ClientPrimaryWorkspaceApplicationViewV1: View {
    private let macName: String
    @ObservedObject private var model: ClientPrimaryWorkspaceModelV0
    private let interactiveRoles:
        NetworkClientInteractiveRoleProductBindingV0
    private let liveProductFactory: ClientPrimaryLiveControlCoordinatorV0.ProductFactory?
    private let onCommandFailure:
        @MainActor @Sendable (any Error) -> Void
    private let onReconnect: @MainActor @Sendable () async -> Void
    private let onShowMacLibrary: @MainActor @Sendable () async -> Void
    @State private var selectedAction:
        ClientApprovedActionDestinationV1?

    public init(
        macName: String,
        model: ClientPrimaryWorkspaceModelV0,
        interactiveRoles:
            NetworkClientInteractiveRoleProductBindingV0,
        liveProductFactory: ClientPrimaryLiveControlCoordinatorV0.ProductFactory? = nil,
        onReconnect: @escaping @MainActor @Sendable () async -> Void = {},
        onShowMacLibrary: @escaping @MainActor @Sendable () async -> Void = {},
        onCommandFailure: @escaping @MainActor @Sendable
            (any Error) -> Void = { _ in }
    ) {
        self.macName = macName
        _model = ObservedObject(wrappedValue: model)
        self.interactiveRoles = interactiveRoles
        self.liveProductFactory = liveProductFactory
        self.onReconnect = onReconnect
        self.onShowMacLibrary = onShowMacLibrary
        self.onCommandFailure = onCommandFailure
    }

    public var body: some View {
        ClientPrimaryWorkspaceViewV0(
            macName: macName,
            model: model,
            interactiveRoles: interactiveRoles,
            liveProductFactory: liveProductFactory,
            onSelectAction: selectAction,
            onReconnect: onReconnect,
            onShowMacLibrary: onShowMacLibrary,
            onCommandFailure: onCommandFailure
        )
        .sheet(item: $selectedAction) { destination in
            NavigationStack {
                ClientApprovedActionApplicationDetailV1(
                    macName: macName,
                    descriptor: destination.descriptor,
                    model: model,
                    onCommandFailure: onCommandFailure
                )
            }
        }
    }

    private func selectAction(
        _ descriptor: CapabilityDiscoveryDescriptorV1
    ) {
        guard (try? ClientCapabilityParameterDraftV1(
            schema: CapabilitySchemaV1(
                wireValue: descriptor.parameterSchema
            )
        )) != nil else {
            onCommandFailure(ClientCapabilityParameterDraftErrorV1
                .schemaViolation)
            return
        }
        selectedAction = ClientApprovedActionDestinationV1(descriptor)
    }
}

@available(iOS 17.0, *)
private struct ClientApprovedActionApplicationDetailV1: View {
    private let macName: String
    private let descriptor: CapabilityDiscoveryDescriptorV1
    @ObservedObject private var model: ClientPrimaryWorkspaceModelV0
    private let onCommandFailure:
        @MainActor @Sendable (any Error) -> Void
    @State private var draft: ClientCapabilityParameterDraftV1?
    @State private var explicitEffectReview = false
    @State private var studyJobRecorded = false
    @Environment(\.dismiss) private var dismiss

    init(
        macName: String,
        descriptor: CapabilityDiscoveryDescriptorV1,
        model: ClientPrimaryWorkspaceModelV0,
        onCommandFailure: @escaping @MainActor @Sendable
            (any Error) -> Void
    ) {
        self.macName = macName
        self.descriptor = descriptor
        _model = ObservedObject(wrappedValue: model)
        self.onCommandFailure = onCommandFailure
        _draft = State(initialValue: try? ClientCapabilityParameterDraftV1(
            schema: CapabilitySchemaV1(
                wireValue: descriptor.parameterSchema
            )
        ))
    }

    var body: some View {
        Group {
            if let draft {
                ClientApprovedActionDetailViewV1(
                    macName: macName,
                    descriptor: descriptor,
                    draft: Binding(
                        get: { draft },
                        set: { self.draft = $0 }
                    ),
                    operationState: model.projection.operationState ?? .idle,
                    explicitEffectReview: $explicitEffectReview,
                    onInvoke: invoke,
                    onCancel: cancel,
                    onQuery: query
                )
            } else {
                ContentUnavailableView(
                    "Action unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(
                        "The granted action schema could not be prepared."
                    )
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            if canRecordStudyJob {
                VStack(alignment: .leading, spacing: 8) {
                    Button(
                        studyJobRecorded
                            ? "Study Result Added"
                            : "Add Result to Active Study Session",
                        systemImage: studyJobRecorded
                            ? "checkmark.circle" : "checkmark.circle.badge.questionmark"
                    ) {
                        recordStudyJob()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(studyJobRecorded)
                    Text(
                        "Use only when this was a real mute/unmute job. The report stores the closed outcome, never the requested or prior audio value."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding()
                .background(.bar)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onDisappear {
            guard shouldFinishOperation else { return }
            Task { try? await model.finishOperation() }
        }
    }

    private func invoke(_ parameters: CanonicalJSONValue) {
        perform {
            _ = try await model.beginOperation(
                capabilityID: descriptor.capabilityID,
                parameters: parameters,
                operationID: WireUUID(UUID())
            )
        }
    }

    private func cancel() {
        perform { _ = try await model.cancelOperation() }
    }

    private func query() {
        perform { _ = try await model.queryOperation() }
    }

    private func perform(
        _ command: @escaping @MainActor () async throws -> Void
    ) {
        Task {
            do { try await command() }
            catch { onCommandFailure(error) }
        }
    }

    private var shouldFinishOperation: Bool {
        switch model.projection.operationState {
        case .terminal, .remoteRejected:
            true
        case .idle, .awaitingInvokeReply, .awaitingUserPresence,
             .awaitingApprovalReply, .observing, .awaitingStatusReply,
             .awaitingCancelReply, .deliveryUnknown, .invalidated, nil:
            false
        }
    }

    private var canRecordStudyJob: Bool {
        guard descriptor.capabilityID
                == ClientStage3StudyActJobProjectionV1
                    .setAudioMutedCapabilityID,
              let operationState = model.projection.operationState else {
            return false
        }
        return ClientStage3StudyActJobProjectionV1.result(
            capabilityID: descriptor.capabilityID,
            state: operationState
        ) != nil
    }

    private func recordStudyJob() {
        Task {
            do {
                _ = try await model.recordSetAudioMutedStudyJob(
                    capabilityID: descriptor.capabilityID
                )
                studyJobRecorded = true
            } catch {
                onCommandFailure(error)
            }
        }
    }
}
#endif
