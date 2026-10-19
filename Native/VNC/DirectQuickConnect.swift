#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import Observation

struct DirectQuickConnectRequest {
    let mac: DirectMacRecordV1
    let connection: DirectMacConnection
    let saveMac: Bool
}

struct DirectQuickConnectDraft: Equatable {
    var id = UUID()
    var name = "" {
        didSet { usesAutomaticName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    private(set) var usesAutomaticName = true
    var host = ""
    var additionalAddresses = ""
    var port = "5900"
    var sshPort = "22"
    var connection = DirectMacConnection.desktop
    var saveMac = true
    var choseConnection = false
    init() {}
    init(item: DirectMacDiscoveryItem) {
        name = item.name; host = item.host; usesAutomaticName = true
        if let desktop = item.services.first(where: { $0.connection == .desktop }) { port = String(desktop.port) }
        if let terminal = item.services.first(where: { $0.connection == .terminal }) { sshPort = String(terminal.port) }
        if !item.services.contains(where: { $0.connection == .desktop }) { connection = .terminal }
    }
    var record: DirectMacRecordV1? {
        guard let port = Int(port), let sshPort = Int(sshPort) else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? host.trimmingCharacters(in: .whitespacesAndNewlines) : trimmedName
        // The full hostname remains an endpoint even when its automatic label is shorter.
        let label = usesAutomaticName ? String(displayName.prefix(80)) : displayName
        guard var record = try? DirectMacRecordV1.normalized(id: id, name: label,
            addresses: [host] + additionalAddresses.split(separator: "\n").map(String.init), port: port, sshPort: sshPort) else { return nil }
        record.usesAutomaticName = usesAutomaticName
        return record
    }
    /// Only an unambiguous endpoint match reuses a saved identity. A Bonjour
    /// name is never enough to select credentials or bypass host verification.
    func savedMac(in macs: [DirectMacRecordV1]) -> DirectMacRecordV1? {
        guard let record else { return nil }
        let hosts = Set(record.addresses.map(DirectMacDetectedIdentity.endpointKey))
        let matches = macs.filter { mac in
            mac.addresses.contains { hosts.contains(DirectMacDetectedIdentity.endpointKey($0)) } &&
            (connection == .terminal ? mac.sshPort == record.sshPort : mac.port == record.port && mac.sshPort == record.sshPort)
        }
        return matches.count == 1 ? matches[0] : nil
    }
    func request(in macs: [DirectMacRecordV1]) -> DirectQuickConnectRequest? {
        guard let mac = savedMac(in: macs) ?? record else { return nil }
        let existing = savedMac(in: macs)
        return .init(mac: mac, connection: choseConnection ? connection : existing?.preferredConnection ?? connection, saveMac: saveMac)
    }
    func effectiveConnection(in macs: [DirectMacRecordV1]) -> DirectMacConnection {
        choseConnection ? connection : savedMac(in: macs)?.preferredConnection ?? connection
    }
}

struct DirectQuickConnectView: View {
    @Bindable var library: DirectMacLibraryV1
    let panel: DirectConnectionPanelHost
    let checkingPurchases: Bool
    let timedOut: Bool
    let retry: () -> Void
    let cancel: () -> Void
    let connect: (DirectQuickConnectRequest) -> Void
    @State private var draft = DirectQuickConnectDraft()
    @State private var options: DirectQuickConnectDraft?
    @FocusState private var hostFocused: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Hostname or IP address", text: $draft.host)
                            .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($hostFocused).submitLabel(.go).onSubmit { submit(draft) }
                            .disabled(checkingPurchases).accessibilityIdentifier("quick-connect-host")
                        Button { submit(draft) } label: {
                            Image(systemName: "arrow.right.circle.fill").font(.title2)
                                .foregroundStyle(draft.record == nil || checkingPurchases ? Color.secondary : Color.blue)
                                .frame(width: 44, height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Connect")
                            .disabled(draft.record == nil || checkingPurchases)
                            .accessibilityIdentifier("quick-connect-submit")
                    }
                    if !draft.host.isEmpty {
                        Button { hostFocused = false; options = draft; panel.expand() } label: {
                            HStack {
                                Label(draft.effectiveConnection(in: library.macs).title, systemImage: draft.effectiveConnection(in: library.macs).symbol)
                                    .foregroundStyle(Color.primary)
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.secondary)
                            }
                        }.accessibilityLabel("Connection Options")
                            .accessibilityValue(draft.effectiveConnection(in: library.macs).title)
                            .disabled(checkingPurchases).accessibilityIdentifier("quick-connect-options")
                    }
                } header: { Text("Quick Connect") }
                if checkingPurchases {
                    Section {
                        if timedOut {
                            Text("Purchases couldn’t be checked. Your connection hasn’t started.")

                        } else { HStack { ProgressView(); Text("Checking purchases…") }.accessibilityIdentifier("mac-access-progress") }

                    }
                }
                if draft.savedMac(in: library.macs) == nil {
                    Section {
                        Toggle("Save to My Macs", isOn: $draft.saveMac).disabled(checkingPurchases).accessibilityIdentifier("quick-connect-save-mac")
                    } footer: { Text(draft.saveMac ? "Saved after a successful connection." : "Connect without saving this Mac.") }
                } else {
                    Section { Label("Already in My Macs", systemImage: "checkmark.circle").foregroundStyle(.secondary) }
                }
                Section {
                    ForEach(DirectMacDiscoveryItem.group(library.discovery.visibleIdentities)) { item in
                        HStack(spacing: 12) {
                            Button {
                                var nearby = DirectQuickConnectDraft(item: item); nearby.saveMac = draft.saveMac; submit(nearby)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.family.symbol).font(.title2).frame(width: 32).foregroundStyle(.blue)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.name).foregroundStyle(.primary)
                                        Text(item.host).font(.subheadline).foregroundStyle(.secondary)
                                        Text(DirectQuickConnectDraft(item: item).effectiveConnection(in: library.macs).title).font(.caption).foregroundStyle(.secondary)
                                        if DirectQuickConnectDraft(item: item).savedMac(in: library.macs) != nil { Text("Saved in My Macs").font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer(minLength: 0)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(checkingPurchases)
                            Button("Connection Options", systemImage: "ellipsis.circle") {
                                var nearby = DirectQuickConnectDraft(item: item); nearby.saveMac = draft.saveMac; options = nearby; panel.expand()
                            }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).disabled(checkingPurchases)
                        }
                    }
                    if library.discovery.scanning { HStack { ProgressView(); Text("Looking for Macs…") } }
                    else if library.discovery.visibleIdentities.isEmpty { Text(library.discovery.unavailable ? "Nearby Macs unavailable. Enter an address above." : "No nearby Macs found. Enter an address above.").foregroundStyle(.secondary) }
                } header: {
                    HStack { Text("Nearby Macs"); Spacer(); Button("Refresh") { library.discovery.start() }.disabled(library.discovery.scanning) }
                }
            }.scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if checkingPurchases {
                        DirectConnectionFooter {
                            if timedOut { Button("Retry", action: retry).accessibilityIdentifier("mac-access-retry") }
                            Button("Cancel", action: cancel).font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                                .accessibilityIdentifier("mac-access-cancel")
                        }
                    }
                }
                .navigationTitle("Connect to Mac").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) {
                    if !checkingPurchases { Button("Cancel", action: cancel).accessibilityIdentifier("quick-connect-cancel") }
                } }
                .navigationDestination(isPresented: Binding(get: { options != nil }, set: { if !$0 { if let options { draft = options }; options = nil } })) {
                    if options != nil {
                        DirectQuickConnectOptions(macs: library.macs, draft: Binding(get: { options ?? draft }, set: { options = $0 }), checkingPurchases: checkingPurchases, timedOut: timedOut, retry: retry, cancel: cancel,
                            connect: { if let options { submit(options) } })
                    }
                }
        }.directAppearance()
            .onAppear { library.discovery.start() }
            .onDisappear { library.discovery.stop() }
            .onChange(of: options?.id) { _, value in if value == nil { panel.compact() } }
    }
    private func submit(_ value: DirectQuickConnectDraft) {
        guard !checkingPurchases, let request = value.request(in: library.macs) else { return }
        hostFocused = false; connect(request)
    }
}

private struct DirectQuickConnectOptions: View {
    let macs: [DirectMacRecordV1]
    @Binding var draft: DirectQuickConnectDraft
    let checkingPurchases: Bool
    let timedOut: Bool
    let retry: () -> Void
    let cancel: () -> Void
    let connect: () -> Void
    private enum Port: Hashable { case screenSharing, remoteLogin }
    @FocusState private var focusedPort: Port?
    var body: some View {
        ScrollViewReader { proxy in
        Form {
            if checkingPurchases {
                Section {
                    if timedOut { Text("Purchases couldn’t be checked. Your connection hasn’t started.") }
                    else { HStack { ProgressView(); Text("Checking purchases…") } }
                }
            }
            Section("Mac") {
                TextField("Name (optional)", text: $draft.name)
                TextField("Hostname or IP address", text: $draft.host).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Additional addresses, one per line", text: $draft.additionalAddresses, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled()
            }.disabled(checkingPurchases)
            Section("Open") { Picker("Connection", selection: Binding(get: { draft.choseConnection ? draft.connection : draft.savedMac(in: macs)?.preferredConnection ?? draft.connection }, set: { draft.connection = $0; draft.choseConnection = true })) { ForEach(DirectMacConnection.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) } }.pickerStyle(.inline).labelsHidden() }.disabled(checkingPurchases)
            Section("Service Ports") {
                LabeledContent("Screen Sharing") { TextField("5900", text: $draft.port).keyboardType(.numbersAndPunctuation).submitLabel(.done).onSubmit { focusedPort = nil }.focused($focusedPort, equals: .screenSharing).multilineTextAlignment(.trailing).accessibilityIdentifier("quick-connect-vnc-port") }.id(Port.screenSharing)
                LabeledContent("Remote Login") { TextField("22", text: $draft.sshPort).keyboardType(.numbersAndPunctuation).submitLabel(.done).onSubmit { focusedPort = nil }.focused($focusedPort, equals: .remoteLogin).multilineTextAlignment(.trailing).accessibilityIdentifier("quick-connect-ssh-port") }.id(Port.remoteLogin)
            }.disabled(checkingPurchases)
            if draft.savedMac(in: macs) == nil {
                Section { Toggle("Save to My Macs", isOn: $draft.saveMac).disabled(checkingPurchases) } footer: { Text("Added after you connect. Login saving is a separate choice.") }
            } else { Section { Label("Already in My Macs", systemImage: "checkmark.circle").foregroundStyle(.secondary) } }
        }.accessibilityIdentifier("quick-connect-options-form").scrollDismissesKeyboard(.interactively)
            .onChange(of: focusedPort) { _, _ in revealFocusedPort(using: proxy) }
            .onGeometryChange(for: CGSize.self) { CGSize(width: $0.size.height, height: $0.safeAreaInsets.bottom) } action: { _ in revealFocusedPort(using: proxy) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DirectConnectionFooter {
                    if !checkingPurchases {
                        Button(action: connect) { Text("Connect").font(.headline).frame(maxWidth: .infinity, minHeight: 32) }
                            .buttonStyle(.borderedProminent).controlSize(.large).disabled(draft.record == nil)
                            .accessibilityIdentifier("quick-connect-options-submit")
                    } else if timedOut {
                        Button("Retry", action: retry).buttonStyle(.borderedProminent).controlSize(.large)
                    }
                    Button("Cancel", action: cancel).font(.headline).foregroundStyle(.blue).frame(maxWidth: .infinity, minHeight: 48).buttonStyle(.plain)
                        .accessibilityIdentifier("quick-connect-options-cancel")
                }
            }.navigationTitle("Connection Options").navigationBarTitleDisplayMode(.inline)
        }
    }
    private func revealFocusedPort(using proxy: ScrollViewProxy) {
        guard let port = focusedPort else { return }
        Task { @MainActor in
            await Task.yield()
            guard focusedPort == port else { return }
            proxy.scrollTo(port, anchor: .center)
        }
    }
}
#endif
