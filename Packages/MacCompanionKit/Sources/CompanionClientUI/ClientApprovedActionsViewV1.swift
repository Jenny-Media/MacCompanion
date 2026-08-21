#if os(iOS)
import CompanionClient
import CompanionWire
import SwiftUI

@available(iOS 17.0, *)
public struct ClientApprovedActionsViewV1: View {
    private let macName: String
    private let catalog: GrantedCapabilityCatalogV1
    private let projection: ClientApprovedActionsProjectionV1
    private let onSelect: (CapabilityDiscoveryDescriptorV1) -> Void
    private let onReload: () -> Void

    public init(
        macName: String,
        catalog: GrantedCapabilityCatalogV1,
        onSelect: @escaping (CapabilityDiscoveryDescriptorV1) -> Void,
        onReload: @escaping () -> Void
    ) {
        self.macName = macName
        self.catalog = catalog
        projection = ClientApprovedActionsProjectionV1(catalog: catalog)
        self.onSelect = onSelect
        self.onReload = onReload
    }

    public var body: some View {
        Group {
            if projection.rows.isEmpty {
                ContentUnavailableView(
                    "No Approved Actions",
                    systemImage: "checklist.unchecked",
                    description: Text(
                        "Grant bounded actions from Mac Companion on \(macName). Remote Control is not required."
                    )
                )
            } else {
                List {
                    Section {
                        ForEach(projection.rows) { row in
                            Button {
                                if let descriptor = catalog.capability(row.id) {
                                    onSelect(descriptor)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(row.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                    Text(row.summary)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text(row.effectSummary)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(row.title)
                            .accessibilityHint("Review parameters and effects")
                        }
                    } header: {
                        Text("Granted by \(macName)")
                    } footer: {
                        Text("These actions use their own grants and do not start or authorize Remote Control.")
                    }
                }
            }
        }
        .navigationTitle("Approved Actions")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reload", systemImage: "arrow.clockwise", action: onReload)
            }
        }
    }
}

@available(iOS 17.0, *)
public struct ClientApprovedActionDetailViewV1: View {
    private let macName: String
    private let descriptor: CapabilityDiscoveryDescriptorV1
    private let draft: Binding<ClientCapabilityParameterDraftV1>
    private let operationState: ClientOperationSessionStateV1
    private let explicitEffectReview: Binding<Bool>
    private let onInvoke: (CanonicalJSONValue) -> Void
    private let onCancel: () -> Void
    private let onQuery: () -> Void

    public init(
        macName: String,
        descriptor: CapabilityDiscoveryDescriptorV1,
        draft: Binding<ClientCapabilityParameterDraftV1>,
        operationState: ClientOperationSessionStateV1,
        explicitEffectReview: Binding<Bool>,
        onInvoke: @escaping (CanonicalJSONValue) -> Void,
        onCancel: @escaping () -> Void,
        onQuery: @escaping () -> Void
    ) {
        self.macName = macName
        self.descriptor = descriptor
        self.draft = draft
        self.operationState = operationState
        self.explicitEffectReview = explicitEffectReview
        self.onInvoke = onInvoke
        self.onCancel = onCancel
        self.onQuery = onQuery
    }

    public var body: some View {
        let effects = ClientApprovedActionEffectProjectionV1(descriptor.effects)
        let status = ClientApprovedActionStateProjectionV1(operationState)
        let currentDraft = draft.wrappedValue
        Form {
            Section("Target") {
                LabeledContent("Mac", value: macName)
                Text(descriptor.englishSummary)
                    .foregroundStyle(.secondary)
            }

            Section("Parameters") {
                ClientCapabilityParameterEditorV1(
                    schema: currentDraft.schema,
                    value: currentDraft.value,
                    path: [],
                    label: nil,
                    enabled: status.canInvoke,
                    onUpdate: updateValue,
                    onIncludeOptional: includeOptional,
                    onRemoveOptional: removeOptional,
                    onAppendArrayItem: appendArrayItem,
                    onRemoveArrayItem: removeArrayItem
                )
            }

            Section("Effects") {
                ForEach(effects.facts, id: \.self) { fact in
                    Label(fact, systemImage: effectSystemImage(fact))
                }
                if effects.requiresExplicitReview {
                    Toggle(
                        "I reviewed these effects",
                        isOn: explicitEffectReview
                    )
                    .accessibilityIdentifier("Explicit effect review")
                }
            }

            Section("Operation") {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: status.systemImage)
                        .foregroundStyle(statusColor(status))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(status.title)
                            .font(.headline)
                        Text(status.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("Action status")

                if status.isBusy {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
                if status.canInvoke {
                    Button("Run Approved Action", systemImage: "play.fill") {
                        if let parameters = try? currentDraft.validatedParameters() {
                            onInvoke(parameters)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        effects.requiresExplicitReview
                            && !explicitEffectReview.wrappedValue
                    )
                    .frame(maxWidth: .infinity)
                }
                if status.canCancel {
                    Button("Request Cancellation", role: .destructive) {
                        onCancel()
                    }
                    .frame(maxWidth: .infinity)
                }
                if status.canQuery {
                    Button("Check Same Operation", systemImage: "arrow.clockwise") {
                        onQuery()
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            if let result = status.verifiedResult {
                Section("Verified Transient Result") {
                    ForEach(ClientVerifiedResultProjectionV1.rows(result)) { row in
                        LabeledContent(row.label, value: row.value)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("Verified result \(row.id)")
                    }
                    Text("Use Observe to verify the current Mac state before relying on this result later.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(descriptor.englishTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func updateValue(
        _ value: CanonicalJSONValue,
        at path: [ClientCapabilityParameterPathComponentV1]
    ) {
        var next = draft.wrappedValue
        guard (try? next.setValue(value, at: path)) != nil else { return }
        draft.wrappedValue = next
    }

    private func includeOptional(
        _ name: String,
        at path: [ClientCapabilityParameterPathComponentV1]
    ) {
        var next = draft.wrappedValue
        guard (try? next.includeOptionalProperty(name, inObjectAt: path)) != nil else {
            return
        }
        draft.wrappedValue = next
    }

    private func removeOptional(
        _ name: String,
        at path: [ClientCapabilityParameterPathComponentV1]
    ) {
        var next = draft.wrappedValue
        guard (try? next.removeOptionalProperty(name, inObjectAt: path)) != nil else {
            return
        }
        draft.wrappedValue = next
    }

    private func appendArrayItem(
        at path: [ClientCapabilityParameterPathComponentV1]
    ) {
        var next = draft.wrappedValue
        guard (try? next.appendArrayItem(at: path)) != nil else { return }
        draft.wrappedValue = next
    }

    private func removeArrayItem(
        _ index: Int,
        at path: [ClientCapabilityParameterPathComponentV1]
    ) {
        var next = draft.wrappedValue
        guard (try? next.removeArrayItem(at: index, inArrayAt: path)) != nil else {
            return
        }
        draft.wrappedValue = next
    }

    private func effectSystemImage(_ fact: String) -> String {
        if fact.contains("destroy") || fact.contains("irreversible") {
            return "exclamationmark.octagon"
        }
        if fact.contains("credential") { return "key" }
        if fact.contains("locked") { return "lock" }
        if fact.contains("external") { return "network" }
        if fact.contains("change") { return "arrow.triangle.2.circlepath" }
        return "info.circle"
    }

    private func statusColor(
        _ status: ClientApprovedActionStateProjectionV1
    ) -> Color {
        switch status.title {
        case "Completed": .green
        case "Failed", "Denied", "Outcome Unknown": .red
        default: .accentColor
        }
    }
}

@available(iOS 17.0, *)
private struct ClientCapabilityParameterEditorV1: View {
    let schema: CapabilitySchemaV1
    let value: CanonicalJSONValue
    let path: [ClientCapabilityParameterPathComponentV1]
    let label: String?
    let enabled: Bool
    let onUpdate: (
        CanonicalJSONValue,
        [ClientCapabilityParameterPathComponentV1]
    ) -> Void
    let onIncludeOptional: (
        String,
        [ClientCapabilityParameterPathComponentV1]
    ) -> Void
    let onRemoveOptional: (
        String,
        [ClientCapabilityParameterPathComponentV1]
    ) -> Void
    let onAppendArrayItem: ([ClientCapabilityParameterPathComponentV1]) -> Void
    let onRemoveArrayItem: (
        Int,
        [ClientCapabilityParameterPathComponentV1]
    ) -> Void

    var body: some View { content() }

    private func content() -> AnyView {
        switch schema.presentationNode {
        case .boolean:
            let current = if case let .boolean(value) = value { value } else { false }
            return AnyView(Toggle(
                label ?? "Enabled",
                isOn: Binding(
                    get: { current },
                    set: { onUpdate(.boolean($0), path) }
                )
            ).disabled(!enabled))

        case let .integer(minimum, maximum):
            let current = if case let .integer(value) = value { value } else { minimum }
            return AnyView(HStack {
                Text(label ?? "Value")
                Spacer()
                TextField(
                    "Value",
                    value: Binding(
                        get: { current },
                        set: { replacement in
                            guard (minimum...maximum).contains(replacement) else { return }
                            onUpdate(.integer(replacement), path)
                        }
                    ),
                    format: .number
                )
                .multilineTextAlignment(.trailing)
                .keyboardType(.numbersAndPunctuation)
                .frame(maxWidth: 160)
                .disabled(!enabled)
            })

        case let .string(maximumUTF8Bytes, allowedValues):
            let current = if case let .string(value) = value { value } else { "" }
            if let allowedValues {
                return AnyView(Picker(
                    label ?? "Value",
                    selection: Binding(
                        get: { current },
                        set: { onUpdate(.string($0), path) }
                    )
                ) {
                    ForEach(allowedValues, id: \.self) {
                        Text($0).tag($0)
                    }
                }.disabled(!enabled))
            }
            return AnyView(HStack {
                Text(label ?? "Value")
                Spacer()
                TextField(
                    "Value",
                    text: Binding(
                        get: { current },
                        set: { replacement in
                            guard replacement.utf8.count <= maximumUTF8Bytes else { return }
                            onUpdate(.string(replacement), path)
                        }
                    )
                )
                .multilineTextAlignment(.trailing)
                .disabled(!enabled)
            })

        case let .array(maximumItems, item):
            let values: [CanonicalJSONValue] = if case let .array(values) = value {
                values
            } else {
                []
            }
            return AnyView(VStack(alignment: .leading, spacing: 12) {
                if let label { Text(label).font(.headline) }
                ForEach(values.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 8) {
                        ClientCapabilityParameterEditorV1(
                            schema: item,
                            value: values[index],
                            path: path + [.index(index)],
                            label: "Item \(index + 1)",
                            enabled: enabled,
                            onUpdate: onUpdate,
                            onIncludeOptional: onIncludeOptional,
                            onRemoveOptional: onRemoveOptional,
                            onAppendArrayItem: onAppendArrayItem,
                            onRemoveArrayItem: onRemoveArrayItem
                        )
                        Button("Remove Item", role: .destructive) {
                            onRemoveArrayItem(index, path)
                        }
                        .disabled(!enabled)
                    }
                    .padding(.leading, 12)
                }
                Button("Add Item", systemImage: "plus") {
                    onAppendArrayItem(path)
                }
                .disabled(!enabled || values.count >= maximumItems)
            })

        case let .object(properties):
            let members: [CanonicalJSONMember] = if case let .object(members) = value {
                members
            } else {
                []
            }
            return AnyView(VStack(alignment: .leading, spacing: 14) {
                if let label { Text(label).font(.headline) }
                ForEach(properties, id: \.name) { property in
                    let member = members.first(where: { $0.key == property.name })
                    let childPath = path + [.property(property.name)]
                    if let member {
                        VStack(alignment: .leading, spacing: 8) {
                            ClientCapabilityParameterEditorV1(
                                schema: property.schema,
                                value: member.value,
                                path: childPath,
                                label: ClientVerifiedResultProjectionV1.displayName(
                                    property.name
                                ),
                                enabled: enabled,
                                onUpdate: onUpdate,
                                onIncludeOptional: onIncludeOptional,
                                onRemoveOptional: onRemoveOptional,
                                onAppendArrayItem: onAppendArrayItem,
                                onRemoveArrayItem: onRemoveArrayItem
                            )
                            if !property.required {
                                Button("Remove \(ClientVerifiedResultProjectionV1.displayName(property.name))") {
                                    onRemoveOptional(property.name, path)
                                }
                                .disabled(!enabled)
                            }
                        }
                    } else if !property.required {
                        Button(
                            "Add \(ClientVerifiedResultProjectionV1.displayName(property.name))",
                            systemImage: "plus"
                        ) {
                            onIncludeOptional(property.name, path)
                        }
                        .disabled(!enabled)
                    }
                }
            })
        }
    }
}
#endif
