#if os(macOS)
import CompanionPresentation
import SwiftUI

@available(macOS 14.0, *)
public struct MacDeviceNameEditorViewV0: View {
    private let projection: MacDeviceNameProjectionV0
    private let onBeginEditing: () -> Void
    private let onDraftChanged: @MainActor @Sendable (String) -> Void
    private let onSave: () -> Void
    private let onCancel: () -> Void

    public init(
        presentation: DeviceNameAdministrationPresentation,
        onBeginEditing: @escaping () -> Void,
        onDraftChanged: @escaping @MainActor @Sendable (String) -> Void,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        projection = MacDeviceNameProjectionV0(presentation: presentation)
        self.onBeginEditing = onBeginEditing
        self.onDraftChanged = onDraftChanged
        self.onSave = onSave
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Device name")
                .font(.headline)
            Text("This locally confirmed name identifies the device in Mac approvals and warnings.")
                .foregroundStyle(.secondary)

            if projection.isEditing {
                TextField("For example, Jenny’s iPhone", text: Binding(
                    get: { projection.draft },
                    set: onDraftChanged
                ))
                if let issue = projection.issue {
                    Label(issueDetail(issue), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                HStack {
                    Button("Cancel", role: .cancel, action: onCancel)
                    Button("Save", action: onSave)
                        .buttonStyle(.borderedProminent)
                        .disabled(!projection.canSave)
                }
            } else {
                HStack {
                    Text(projection.confirmedName ?? "No confirmed name")
                        .foregroundStyle(projection.confirmedName == nil ? .secondary : .primary)
                    Spacer()
                    if case .saving = projection.phase {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Edit", action: onBeginEditing)
                    }
                }
            }

            if case let .saveFailed(reason) = projection.phase {
                Label(saveFailureDetail(reason), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .frame(minWidth: 360, idealWidth: 440)
    }

    private func issueDetail(_ issue: DeviceNameDraftIssue) -> String {
        switch issue {
        case .empty: "Enter a device name."
        case .tooLong: "Use a shorter device name."
        case .surroundingWhitespace: "Remove spaces at the beginning or end."
        case .nonCanonicalUnicode: "Use a standard Unicode spelling."
        case .unsupportedCharacters: "Remove unsupported or invisible characters."
        }
    }

    private func saveFailureDetail(_ failure: DeviceNameSaveFailure) -> String {
        switch failure {
        case .deviceRevoked: "This device is no longer paired."
        case .staleLocalState: "The device changed. Refresh before trying again."
        case .serviceUnavailable: "The local service is unavailable. Try again."
        case .unknown: "The name was not changed. Try again."
        }
    }
}
#endif
