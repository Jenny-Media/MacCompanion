#if os(iOS)
import CompanionClient
import CompanionDiscovery
import SwiftUI

public struct ClientRouteConfigurationViewStateV1:
    Equatable, Sendable
{
    public let selectedType: ClientRouteConfigurationTypeV1
    public let selectedKind: EndpointKind
    public let endpointValue: String
    public let portText: String
    public let validationMessage: String?

    public init(
        selectedType: ClientRouteConfigurationTypeV1 = .privateDNS,
        selectedKind: EndpointKind = .dns,
        endpointValue: String = "",
        portText: String = "47474",
        validationMessage: String? = nil
    ) {
        self.selectedType = selectedType
        self.selectedKind = selectedType.allowedEndpointKinds.contains(
            selectedKind
        ) ? selectedKind : selectedType.allowedEndpointKinds[0]
        self.endpointValue = endpointValue
        self.portText = portText
        self.validationMessage = validationMessage
    }

    public func selecting(
        type: ClientRouteConfigurationTypeV1
    ) -> Self {
        Self(
            selectedType: type,
            selectedKind: selectedKind,
            endpointValue: endpointValue,
            portText: portText
        )
    }

    public func selecting(kind: EndpointKind) -> Self {
        Self(
            selectedType: selectedType,
            selectedKind: kind,
            endpointValue: endpointValue,
            portText: portText
        )
    }

    public func entering(endpoint: String) -> Self {
        Self(
            selectedType: selectedType,
            selectedKind: selectedKind,
            endpointValue: endpoint,
            portText: portText
        )
    }

    public func entering(port: String) -> Self {
        Self(
            selectedType: selectedType,
            selectedKind: selectedKind,
            endpointValue: endpointValue,
            portText: port
        )
    }

    public func reporting(_ message: String?) -> Self {
        Self(
            selectedType: selectedType,
            selectedKind: selectedKind,
            endpointValue: endpointValue,
            portText: portText,
            validationMessage: message
        )
    }
}

@available(iOS 17.0, *)
public struct ClientRouteConfigurationViewV1: View {
    private let projection: ClientRouteConfigurationProjectionV1
    private let routeSnapshot: ClientConfiguredRouteCatalogSnapshotV1
    private let state: ClientRouteConfigurationViewStateV1
    private let onStateChange: (ClientRouteConfigurationViewStateV1) -> Void
    private let onIntent: (ClientConfiguredRouteEditIntentV1) -> Void

    public init(
        snapshot: ClientConfiguredRouteCatalogSnapshotV1,
        state: ClientRouteConfigurationViewStateV1,
        onStateChange: @escaping (
            ClientRouteConfigurationViewStateV1
        ) -> Void,
        onIntent: @escaping (ClientConfiguredRouteEditIntentV1) -> Void
    ) {
        projection = ClientRouteConfigurationProjectionV1(snapshot: snapshot)
        routeSnapshot = snapshot
        self.state = state
        self.onStateChange = onStateChange
        self.onIntent = onIntent
    }

    public var body: some View {
        Form {
            Section {
                NavigationLink("Setup and Diagnostics") {
                    ClientPrivateRouteGuidanceViewV1(
                        projection: ClientPrivateRouteGuidanceProjectionV1(
                            snapshot: routeSnapshot
                        )
                    )
                }
            } header: {
                Text("Private Access")
            } footer: {
                Text("Mac Companion uses local or user-managed private routes and operates no network relay.")
            }

            Section("Saved Routes") {
                ForEach(projection.rows, id: \.record.configuredRouteID.rawValue) {
                    row in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.title)
                            Text(row.endpoint)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu("Edit", systemImage: "ellipsis.circle") {
                            ForEach(row.typeChoices) { choice in
                                Button("Use as \(choice.title)") {
                                    replace(row.record, with: choice)
                                }
                            }
                            Divider()
                            Button("Remove Route", role: .destructive) {
                                onIntent(.remove(
                                    configuredRouteID:
                                        row.record.configuredRouteID
                                ))
                            }
                            .disabled(projection.rows.count == 1)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            Section {
                Picker("Route Type", selection: typeBinding) {
                    ForEach(ClientRouteConfigurationTypeV1.allCases) {
                        Text($0.title).tag($0)
                    }
                }
                Picker("Endpoint Kind", selection: kindBinding) {
                    ForEach(state.selectedType.allowedEndpointKinds, id: \.rawValue) {
                        Text(kindTitle($0)).tag($0)
                    }
                }
                TextField("Endpoint", text: endpointBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Port", text: portBinding)
                    .keyboardType(.numberPad)
                if let validationMessage = state.validationMessage {
                    Text(validationMessage)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Route error")
                }
                Button("Add Route", systemImage: "plus") {
                    addRoute()
                }
            } header: {
                Text("Add Route")
            } footer: {
                Text("Choose the route type explicitly. Mac Companion does not classify DNS names, interfaces, installed apps, or resolved addresses.")
            }
        }
        .navigationTitle("Private Routes")
    }

    private func addRoute() {
        do {
            let draft = try ClientRouteConfigurationDraftV1(
                type: state.selectedType,
                endpointKind: state.selectedKind,
                value: state.endpointValue,
                portText: state.portText
            )
            onStateChange(state.reporting(nil))
            onIntent(draft.addIntent)
        } catch {
            onStateChange(state.reporting(
                "Enter a canonical endpoint and a valid port for the selected route type."
            ))
        }
    }

    private func replace(
        _ record: ClientConfiguredRouteRecordV1,
        with type: ClientRouteConfigurationTypeV1
    ) {
        do {
            let intent = try ClientRouteConfigurationDraftV1
                .replacementIntent(record: record, type: type)
            onStateChange(state.reporting(nil))
            onIntent(intent)
        } catch {
            onStateChange(state.reporting(
                "That route cannot use the selected type."
            ))
        }
    }

    private var typeBinding: Binding<ClientRouteConfigurationTypeV1> {
        Binding(
            get: { state.selectedType },
            set: { onStateChange(state.selecting(type: $0)) }
        )
    }

    private var kindBinding: Binding<EndpointKind> {
        Binding(
            get: { state.selectedKind },
            set: { onStateChange(state.selecting(kind: $0)) }
        )
    }

    private var endpointBinding: Binding<String> {
        Binding(
            get: { state.endpointValue },
            set: { onStateChange(state.entering(endpoint: $0)) }
        )
    }

    private var portBinding: Binding<String> {
        Binding(
            get: { state.portText },
            set: { onStateChange(state.entering(port: $0)) }
        )
    }

    private func kindTitle(_ kind: EndpointKind) -> String {
        switch kind {
        case .bonjour: "Bonjour Service"
        case .ipv4: "IPv4"
        case .ipv6: "IPv6"
        case .dns: "DNS Name"
        }
    }
}
#endif
