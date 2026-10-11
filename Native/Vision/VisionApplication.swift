#if os(visionOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

enum VisionConnection: String, Codable { case desktop, terminal }
struct VisionSessionRequest: Codable, Hashable, Identifiable {
    let id: UUID
    let mac: DirectMacRecordV1
    let connection: VisionConnection
    init(mac: DirectMacRecordV1, connection: VisionConnection) { id = UUID(); self.mac = mac; self.connection = connection }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Discovery only. Each window still owns and retires its own connection.
@MainActor @Observable final class VisionSessionRegistry {
    private(set) var requests: [VisionSessionRequest] = []
    func add(_ request: VisionSessionRequest) { if !requests.contains(where: { $0.id == request.id }) { requests.append(request) } }
    func remove(_ id: UUID) { requests.removeAll { $0.id == id } }
    func existing(mac: UUID, connection: VisionConnection) -> VisionSessionRequest? {
        requests.first { $0.mac.id == mac && $0.connection == connection }
    }
}

@main struct MacCompanionVisionApplication: App {
    @State private var library = DirectMacLibraryV1(url: VisionDevelopmentQA.libraryURL)
    @State private var cloud = VisionDevelopmentQA.makeCloud()
    @State private var sessions = VisionSessionRegistry()
    var body: some Scene {
        Window("Mac Companion", id: "library") {
            VisionLibrary(library: library, cloud: cloud).directAppearance().visionPrivacy()
                .environment(sessions).modifier(VisionQALayout())
                .task { cloud.attach(library); DirectProAccess.shared.start(); library.discovery.start() }
        }.defaultSize(width: VisionDevelopmentQA.compactLargeText ? 600 : 760, height: VisionDevelopmentQA.compactLargeText ? 420 : 650)
        WindowGroup("Connection", id: "connection", for: VisionSessionRequest.self) { request in
            if let selection = request.wrappedValue {
                VisionSessionWindow(request: selection, library: library).id(selection.id).directAppearance().visionPrivacy()
                    .environment(sessions).modifier(VisionQALayout())
            } else { Text("Open a connection from your saved Macs.").padding() }
        }.defaultSize(width: VisionDevelopmentQA.compactLargeText ? 600 : 1200, height: VisionDevelopmentQA.compactLargeText ? 420 : 700)
        Window("Settings", id: "settings") {
            VisionSettings(cloud: cloud).directAppearance().visionPrivacy().modifier(VisionQALayout())
        }.defaultSize(width: 700, height: 650)
    }
}

struct VisionLibrary: View {
    @Bindable var library: DirectMacLibraryV1
    @Bindable var cloud: DirectCloudSyncV1
    @Environment(\.openWindow) private var openWindow
    @Environment(VisionSessionRegistry.self) private var sessions
    @State private var editing: DirectMacRecordV1?
    @State private var adding = false
    @State private var deleting: DirectMacRecordV1?
    @State private var pro = DirectProAccess.shared
    @State private var proShown = false
    var body: some View {
        NavigationStack {
            List {
                if !sessions.requests.isEmpty {
                    Section("Open Windows") {
                        ForEach(sessions.requests) { request in
                            Button(request.mac.name + " · " + (request.connection == .desktop ? "Desktop" : "Terminal")) {
                                openWindow(id: "connection", value: request)
                            }.accessibilityIdentifier("vision-existing-session-" + request.id.uuidString)
                        }
                    }
                }
                if let recovery = library.recovery {
                    DirectRecoveryCard(notice: recovery, primary: .init(title: "Retry", perform: { library.reload() }))
                        .accessibilityIdentifier("vision-library-recovery")
                }
                if library.macs.isEmpty {
                    ContentUnavailableView("Your Macs", systemImage: "desktopcomputer", description: Text("Add a Mac with Screen Sharing and Remote Login enabled."))
                }
                ForEach(library.macs) { mac in
                    VStack(alignment: .leading, spacing: 12) {
                        Label(mac.name, systemImage: mac.family.symbol).font(.headline)
                        Text(mac.address).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Desktop", systemImage: "desktopcomputer") { open(mac, .desktop) }
                                .accessibilityIdentifier("vision-open-desktop-" + mac.id.uuidString)
                            Button("Terminal", systemImage: "terminal") { open(mac, .terminal) }
                                .accessibilityIdentifier("vision-open-terminal-" + mac.id.uuidString)
                            Menu("Open Another Window", systemImage: "plus.rectangle.on.rectangle") {
                                Button("Another Desktop") { open(mac, .desktop, another: true) }
                                Button("Another Terminal") { open(mac, .terminal, another: true) }
                            }.labelStyle(.iconOnly).accessibilityIdentifier("vision-another-window-" + mac.id.uuidString)
                            Menu {
                                Button("Edit Mac") { editing = mac }.disabled(!library.readable)
                                if !pro.hasPro {
                                    Button("Use as My Free Mac") {
                                        guard library.readable, DirectAppLockV1.shared.canAccess else { return }
                                        pro.chooseFreeMac(mac.id)
                                    }.accessibilityIdentifier("vision-free-mac-" + mac.id.uuidString)
                                }
                                Button("Forget Desktop Login") { library.forgetLogin(mac) }
                                Button("Remove Mac", role: .destructive) { deleting = mac }
                            } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Manage " + mac.name)
                                .accessibilityIdentifier("vision-manage-mac-" + mac.id.uuidString)
                        }.buttonStyle(.bordered)
                    }.padding(.vertical, 8)
                }.onMove { library.move(fromOffsets: $0, toOffset: $1) }
            }.navigationTitle("Your Macs")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { Button("Add Mac", systemImage: "plus") {
                        if pro.ready && pro.canAddMac(count: library.macs.count) { adding = true } else { proShown = true }
                    }.disabled(!pro.ready || !library.readable).accessibilityIdentifier("vision-add-mac") }
                    ToolbarItem(placement: .secondaryAction) { Button("Settings", systemImage: "gearshape") { openWindow(id: "settings") } }
                }
                .sheet(isPresented: $adding) { VisionMacEditor(library: library, mac: nil) }
                .sheet(item: $editing) { VisionMacEditor(library: library, mac: $0) }
                .sheet(isPresented: $proShown) { DirectProView() }
                .confirmationDialog("Remove \(deleting?.name ?? "Mac") and its local saved logins?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                    Button("Remove Mac", role: .destructive) { if let deleting { library.remove(deleting) }; deleting = nil }
                }
        }
    }
    private func open(_ mac: DirectMacRecordV1, _ mode: VisionConnection, another: Bool = false) {
        guard DirectAppLockV1.shared.canAccess, pro.ready else { return }
        guard pro.canUseMac(mac.id, among: library.macs.map(\.id)) else { proShown = true; return }
        let request = another ? nil : sessions.existing(mac: mac.id, connection: mode)
        openWindow(id: "connection", value: request ?? VisionSessionRequest(mac: mac, connection: mode))
    }
}

struct VisionMacEditor: View {
    @Bindable var library: DirectMacLibraryV1
    let mac: DirectMacRecordV1?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var addresses = ""
    @State private var desktopPort = "5900"
    @State private var sshPort = "22"
    var body: some View {
        NavigationStack {
            Form {
                Section("Mac") {
                    TextField("Name", text: $name).accessibilityIdentifier("vision-mac-name")
                    TextField("Local or VPN addresses, separated by commas", text: $addresses).directNoAutocapitalization().autocorrectionDisabled()
                        .accessibilityIdentifier("vision-mac-address")
                }
                Section("Built-in Services") {
                    DirectServicePortField(title: "Screen Sharing", defaultPort: "5900", value: $desktopPort, identifier: "vision-desktop-port")
                    DirectServicePortField(title: "Remote Login", defaultPort: "22", value: $sshPort, identifier: "vision-ssh-port")
                    Text("Desktop uses verified SSH to forward to Screen Sharing on this Mac. Enable both services in System Settings → General → Sharing.").font(.footnote)
                }
                if let failure = library.failure { Text(failure).foregroundStyle(.red) }
            }.navigationTitle(mac == nil ? "Add Mac" : "Edit Mac")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!library.readable).accessibilityIdentifier("vision-save-mac") }
                }
        }.onAppear { name = mac?.name ?? ""; addresses = mac?.addresses.joined(separator: ", ") ?? ""; desktopPort = String(mac?.port ?? 5900); sshPort = String(mac?.sshPort ?? VisionDevelopmentQA.sshPort) }
    }
    private func save() {
        if VisionMacSaving.save(library: library, mac: mac, name: name, addresses: addresses,
                                desktopPort: desktopPort, sshPort: sshPort) { dismiss() }
    }
}

@MainActor enum VisionMacSaving {
    static func save(library: DirectMacLibraryV1, mac: DirectMacRecordV1?, name: String, addresses: String,
                     desktopPort: String, sshPort: String, access: DirectProAccess = .shared) -> Bool {
        guard DirectAppLockV1.shared.canAccess, library.readable else { return false }
        let sshInput = sshPort.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = DirectMacRecordV1.port(from: desktopPort), let ssh = sshInput.isEmpty ? 22 : DirectMacRecordV1.port(from: sshInput) else {
            library.failure = "Ports must be from 1 to 65535."; return false
        }
        let existing = mac.map { edited in library.macs.contains { $0.id == edited.id } } ?? false
        guard existing || access.canAddMac(count: library.macs.count) else {
            library.failure = "Adding another Mac requires Pro. Your existing Macs are kept."; return false
        }
        return library.save(id: mac?.id, name: name, addresses: addresses.split(separator: ",").map(String.init), port: port, sshPort: ssh)
    }
}

struct VisionSettings: View {
    @Bindable var cloud: DirectCloudSyncV1
    @State private var lock = DirectAppLockV1.shared
    @State private var appearance = DirectAppearanceV1.shared
    @State private var enableCloud = false
    @Environment(\.scenePhase) private var phase
    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("App", selection: $appearance.app) { ForEach(DirectAppAppearance.allCases) { Text($0.title).tag($0) } }
                    Picker("Terminal", selection: $appearance.terminal) { ForEach(DirectTerminalAppearance.allCases) { Text($0.title).tag($0) } }
                }
                Section {
                    Toggle("Require Unlock", isOn: Binding(get: { lock.enabled }, set: { lock.setEnabled($0) }))
                    Text("Use \(lock.method) when you return. Every connection window is covered while locked.").font(.footnote)
                } header: { Text("Privacy") }
                Section("Saved Macs") {
                    Toggle("Sync Mac Metadata with iCloud", isOn: Binding(get: { cloud.enabled }, set: {
                        if $0 { enableCloud = true } else { cloud.setEnabled(false) }
                    })).disabled(cloud.busy)
                    Text(cloud.status).font(.footnote)
                    Text("Only saved Mac metadata and supported preferences sync. Logins, private keys, trusted server keys and typed content stay on this device.").font(.footnote)
                    if let notice = cloud.recovery { DirectNoticeMessage(message: notice.message) }
                    Button("Retry Sync") { cloud.retry() }
                }
                Section("Connections") {
                    NavigationLink("SSH Keys") { TerminalKeySettings(embedded: true) }
                    NavigationLink("Desktop Quick Actions") { VisionQuickActionsSettings(mode: .desktop) }
                    NavigationLink("Terminal Quick Actions") { VisionQuickActionsSettings(mode: .terminal) }
                    NavigationLink("Mac Companion Pro") { DirectProView() }
                }
                Section("Desktop View") {
                    Text("Resize each window independently. Fit preserves wide and ultrawide desktop aspect ratios; Zoom and Pan affect only your local view.")
                    Text("Curved windows are currently unavailable through Apple’s public APIs for third-party apps.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Settings")
        }
        .alert("Enable iCloud Sync?", isPresented: $enableCloud) {
            Button("Enable Sync") { if phase == .active && lock.canAccess { cloud.setEnabled(true) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text(DirectCloudSyncV1.disclosure) }
        .onChange(of: lock.canAccess) { _, value in if !value { enableCloud = false } }
        .onChange(of: phase) { _, value in if value != .active { enableCloud = false } }
    }
}
struct VisionQuickActionsSettings: View {
    let mode: DirectControlMode
    @State private var actions: [VNCQuickAction] = []
    @State private var failure: String?
    @State private var readable = false
    var body: some View {
        VStack {
            if let failure { Text(failure).foregroundStyle(.red).padding() }
            VisionQuickActionsEditor(actions: $actions, mode: mode,
                canEdit: readable && DirectProAccess.shared.hasPro && DirectAppLockV1.shared.canAccess,
                hasPro: DirectProAccess.shared.hasPro)
        }.navigationTitle(mode.title + " Quick Actions")
            .onAppear { reload() }
            .toolbar {
                Button("Save") {
                    guard DirectAppLockV1.shared.canAccess, readable, DirectProAccess.shared.hasPro,
                          DirectQuickActionEditing.canSave(actions, mode: mode, hasPro: true) else { return }
                    do { try VNCSessionPreferences.saveProfile(actions, mode: mode); failure = nil }
                    catch { failure = "Quick actions couldn’t be saved. Try again when local storage is available." }
                }.disabled(!readable || !DirectProAccess.shared.hasPro || !DirectQuickActionEditing.canSave(actions, mode: mode, hasPro: DirectProAccess.shared.hasPro))
                    .accessibilityIdentifier("vision-save-quick-actions")
            }
            .visionSensitiveState {
                actions = []; readable = false; failure = nil
            }
            .onChange(of: DirectAppLockV1.shared.canAccess) { _, value in if value { reload() } }
            .onChange(of: scenePhase) { _, value in if value == .active { reload() } }
    }
    @Environment(\.scenePhase) private var scenePhase
    private func reload() {
        guard scenePhase == .active, DirectAppLockV1.shared.canAccess else { return }
        do { actions = try VNCSessionPreferences.profileActions(mode); readable = true; failure = nil }
        catch { readable = false; failure = "Quick actions couldn’t be read. Try again when local storage is available." }
    }
}

/// Presentation only: hidden legacy entries retain their storage identities and limits.
enum VisionQuickActionPresentation {
    static func supported(_ action: VNCQuickAction, mode: DirectControlMode) -> Bool {
        action.kind != .mode && action.kind != .copyText && action.compatible(with: mode)
    }
    static func presented(_ actions: [VNCQuickAction], mode: DirectControlMode) -> [VNCQuickAction] {
        actions.filter { supported($0, mode: mode) }
    }
    static func standards(_ mode: DirectControlMode) -> [VNCQuickAction] {
        presented(mode.builtIns, mode: mode)
    }
    static func restored(_ actions: [VNCQuickAction], mode: DirectControlMode) -> [VNCQuickAction] {
        actions.filter { !supported($0, mode: mode) } + presented(mode.defaults, mode: mode)
    }
}

/// Native forms and button alternatives keep customization reachable without input modes.
struct VisionQuickActionsEditor: View {
    @Binding var actions: [VNCQuickAction]
    let mode: DirectControlMode
    let canEdit: Bool
    let hasPro: Bool
    @State private var selected: UUID?
    @State private var restoring = false
    @State private var paywall = false
    @State private var automaticNames: Set<UUID> = []
    private var supported: [VNCQuickAction] { VisionQuickActionPresentation.presented(actions, mode: mode) }
    private var available: [VNCQuickAction] { supported.filter { hasPro || !$0.isCustom } }
    private var visible: [VNCQuickAction] { available.filter(\.enabled) }
    private var capacity: Int { VNCQuickAction.maximumCount - (actions.count - supported.count) }
    var body: some View {
        Form {
            Section("Your session layout") {
                ForEach(visible) { action in row(action) }
                if visible.isEmpty { Text("No quick actions. Add one below.") }
                Text("\(visible.count) of \(capacity) actions").font(.caption).foregroundStyle(.secondary)
            }
            if available.contains(where: { !$0.enabled }) {
                Section("Hidden actions") { ForEach(available.filter { !$0.enabled }) { action in row(action) } }
            }
            if !hasPro && supported.contains(where: \.isCustom) {
                Section("Saved Pro actions") {
                    ForEach(supported.filter(\.isCustom)) { action in DirectQuickActionLabel(action: action) }
                    Text("These saved actions require Pro to appear in your session.").font(.footnote)
                }
            }
            Section {
                Menu("Add Action", systemImage: "plus") {
                    ForEach(VisionQuickActionPresentation.standards(mode), id: \.kind) { candidate in
                        Button(candidate.displayTitle, systemImage: candidate.symbol) {
                            guard canEdit else { return }
                            selected = DirectQuickActionEditing.add(candidate, to: &actions, mode: mode)
                        }.disabled(actions.contains { $0.kind == candidate.kind && $0.enabled }
                            || (!actions.contains { $0.kind == candidate.kind } && actions.count >= VNCQuickAction.maximumCount))
                            .accessibilityIdentifier("add-action-" + candidate.kind.rawValue)
                    }
                    Divider()
                    Button("Shortcut", systemImage: "keyboard") { addCustom(.shortcut) }
                        .disabled(!VNCQuickAction.canAddCustom(to: actions))
                    Button("Saved Text", systemImage: "text.quote") { addCustom(.text) }
                        .disabled(!VNCQuickAction.canAddCustom(to: actions))
                }.disabled(!canEdit).accessibilityIdentifier("quick-action-add")
                Button("Restore Defaults") { restoring = true }
                    .disabled(!canEdit || VisionQuickActionPresentation.restored(actions, mode: mode).count > VNCQuickAction.maximumCount)
                if !hasPro {
                    Button("Customize with Pro", systemImage: "sparkles") { paywall = true }
                }
                Text("Changes stay in this draft until you save. No input is sent to your Mac.").font(.footnote)
            }
        }.accessibilityIdentifier("vision-quick-actions-settings")
            .sheet(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
                if let selected, let current = supported.first(where: { $0.id == selected }) {
                    NavigationStack {
                        Form {
                            DirectQuickActionInspector(action: Binding(get: {
                                actions.first { $0.id == selected } ?? current
                            }, set: { edited in
                                guard canEdit, let index = actions.firstIndex(where: { $0.id == selected }) else { return }
                                actions[index] = edited
                            }), mode: mode, automaticallyNamed: Binding(get: { automaticNames.contains(selected) }, set: {
                                if $0 { automaticNames.insert(selected) } else { automaticNames.remove(selected) }
                            }))
                            Toggle("Show in Quick Actions", isOn: Binding(get: {
                                actions.first { $0.id == selected }?.enabled ?? false
                            }, set: { value in
                                guard canEdit, let index = actions.firstIndex(where: { $0.id == selected }) else { return }
                                actions[index].enabled = value
                            }))
                            Button("Move Earlier") { move(selected, -1) }.disabled(supported.first?.id == selected)
                            Button("Move Later") { move(selected, 1) }.disabled(supported.last?.id == selected)
                            Button("Remove from Quick Actions", role: .destructive) {
                                guard canEdit else { return }
                                actions.removeAll { $0.id == selected }; automaticNames.remove(selected); self.selected = nil
                            }
                        }.disabled(!canEdit).navigationTitle("Edit Action")
                            .toolbar { Button("Done") { self.selected = nil } }
                    }.directAppearance().visionPrivacy()
                }
            }
            .confirmationDialog("Restore default quick actions?", isPresented: $restoring, titleVisibility: .visible) {
                Button("Restore Defaults") {
                    guard canEdit else { return }
                    let restored = VisionQuickActionPresentation.restored(actions, mode: mode)
                    guard DirectQuickActionEditing.valid(restored, mode: mode) else { return }
                    actions = restored; selected = nil; automaticNames.removeAll()
                }
            } message: { Text("Your supported draft shortcuts and saved text will be removed when you save.") }
            .sheet(isPresented: $paywall) { DirectProView().directAppearance().visionPrivacy() }
            .onChange(of: canEdit) { _, value in if !value { selected = nil; restoring = false } }
    }
    @ViewBuilder private func row(_ action: VNCQuickAction) -> some View {
        if canEdit {
            Button { selected = action.id } label: { DirectQuickActionLabel(action: action) }
                .accessibilityIdentifier("preview-action-" + action.id.uuidString)
                .accessibilityHint("Select to edit. No input is sent to your Mac.")
        } else { DirectQuickActionLabel(action: action) }
    }
    private func move(_ id: UUID, _ offset: Int) {
        guard canEdit, let index = supported.firstIndex(where: { $0.id == id }), supported.indices.contains(index + offset) else { return }
        DirectQuickActionEditing.move(id, to: supported[index + offset].id, in: &actions)
    }
    private func addCustom(_ kind: VNCQuickAction.Kind) {
        guard canEdit, VNCQuickAction.canAddCustom(to: actions) else { return }
        var action = VNCQuickAction(title: kind == .text ? "Saved Text" : "Shortcut", kind: kind,
            key: kind == .shortcut ? 0x63 : 0, modifiers: kind == .shortcut ? [mode == .terminal ? 0xffe3 : 0xffeb] : [])
        if kind == .shortcut { action.title = action.shortcutTitle; automaticNames.insert(action.id) }
        actions.append(action); selected = action.id
    }
}

#endif
