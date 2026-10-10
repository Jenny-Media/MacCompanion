#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import AppKit
import SwiftUI

struct MacMachineLibraryView: View {
    let library: DirectMacLibraryV1
    @Environment(\.openWindow) private var openWindow
    @State private var selected: UUID?
    @State private var search = ""
    @State private var sheet: Sheet?
    @State private var removing: DirectMacRecordV1?
    @State private var connections = MacConnectionRegistry.shared
    @State private var cloud = DirectCloudSyncV1.shared
    private enum Sheet: Identifiable {
        case add, edit(DirectMacRecordV1), pro
        var id: String { switch self { case .add: "add"; case .edit(let mac): "edit-" + mac.id.uuidString; case .pro: "pro" } }
    }
    private var selectedMac: DirectMacRecordV1? { library.macs.first { $0.id == selected } }
    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                ForEach(library.macs.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.addresses.contains(where: { $0.localizedCaseInsensitiveContains(search) }) }) { mac in
                    Label { VStack(alignment: .leading) {
                        Text(mac.name)
                        Text("Default: " + MacConnectionMode(mac.preferredConnection).title).font(.caption).foregroundStyle(.secondary)
                        let count = connections.connections(for: mac.id).filter { $0.phase == .connected }.count
                        if count > 0 { Text("\(count) connected \(count == 1 ? "session" : "sessions")").font(.caption).foregroundStyle(.secondary) }
                    } }
                        icon: { Image(systemName: mac.family.symbol) }
                        .tag(mac.id)
                        .contextMenu {
                            ForEach(MacConnectionMode.allCases) { mode in Button(mode.actionTitle) { open(mac, mode: mode) } }
                            Divider()
                            Button("Connection Settings") { sheet = .edit(mac) }
                            Button("Use as My Free Mac") { DirectProAccess.shared.chooseFreeMac(mac.id) }
                            Button("Move Up") { move(mac, down: false) }.disabled(library.macs.first?.id == mac.id)
                            Button("Move Down") { move(mac, down: true) }.disabled(library.macs.last?.id == mac.id)
                            Button("Remove Mac", role: .destructive) { removing = mac }
                        }
                }.onMove { _ = library.move(fromOffsets: $0, toOffset: $1) }.moveDisabled(!search.isEmpty)
            }.navigationTitle("My Macs").searchable(text: $search)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
        } detail: {
            Group {
                if let mac = selectedMac {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            Label(mac.name, systemImage: mac.family.symbol).font(.largeTitle)
                            Text(mac.addresses.joined(separator: "\n")).foregroundStyle(.secondary).textSelection(.enabled)
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(MacConnectionMode.allCases) { mode in
                                    Button { open(mac, mode: mode) } label: { Label(mode.actionTitle, systemImage: mode.symbol).frame(maxWidth: .infinity, alignment: .leading) }
                                        .buttonStyle(.bordered).controlSize(.large)
                                        .accessibilityIdentifier("mac-open-" + mode.rawValue)
                                }
                            }.frame(maxWidth: 360)
                            Button("Connection Settings", systemImage: "gearshape") { sheet = .edit(mac) }
                                .accessibilityIdentifier("mac-connection-settings")
                            Text("Each connection opens in its own window.").font(.footnote).foregroundStyle(.secondary)
                            let open = connections.connections(for: mac.id)
                            if !open.isEmpty {
                                Divider()
                                Text("Connection Windows").font(.headline)
                                ForEach(open) { entry in
                                    HStack {
                                        Label(entry.mode.title, systemImage: entry.mode.symbol)
                                        Spacer()
                                        Text(entry.phase.title).foregroundStyle(.secondary)
                                        Button("Show Window") { entry.window.raise() }
                                            .help("Bring this existing \(entry.mode.title) window to the front")
                                    }
                                }
                            }
                        }.padding(32).frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else if library.macs.isEmpty {
                    ContentUnavailableView { Label("Your Macs, within reach", systemImage: "desktopcomputer") }
                        description: { Text("Enable Screen Sharing or Remote Login on your Mac, then add its local or private VPN address.") }
                        actions: { Button("Add Mac") { add() }.buttonStyle(.borderedProminent) }
                } else { ContentUnavailableView("Choose a Mac", systemImage: "desktopcomputer", description: Text("Open Desktop or Terminal.")) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                    if let notice = library.recovery { DirectRecoveryCard(notice: notice, primary: .init(title: "Retry", perform: { library.reload() })).padding() }
                    MacCloudStatusView()
                }
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .toolbar {
            Button("Add Mac", systemImage: "plus") { add() }.disabled(!library.readable).accessibilityIdentifier("mac-add-machine").help("Add a Mac by its local or private VPN address")
            Button("Discover Macs", systemImage: "network") { library.discovery.start() }.disabled(library.discovery.scanning).help("Discover Screen Sharing and Remote Login services on your local network")
            Button("Refresh iCloud", systemImage: "arrow.triangle.2.circlepath") { cloud.refresh() }
                .disabled(!cloud.enabled || cloud.busy).help("Refresh saved Macs in iCloud Keychain. Enable sync in Settings first.")
        }
        .sheet(item: $sheet) { item in
            Group {
                switch item {
                case .add: MacMachineEditor(library: library)
                case .edit(let mac): MacMachineEditor(library: library, mac: mac)
                case .pro: DirectProView().frame(minWidth: 480, minHeight: 460)
                }
            }.modifier(MacSheetPrivacyCover())
        }
        .confirmationDialog("Remove this Mac and its local saved login?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove Mac", role: .destructive) { if DirectAppLockV1.shared.canAccess, let removing { library.remove(removing) }; removing = nil }
        }
        .onChange(of: DirectAppLockV1.shared.canAccess) { _, allowed in
            if !allowed { sheet = nil; removing = nil }
        }
    }
    private func move(_ mac: DirectMacRecordV1, down: Bool) {
        guard DirectAppLockV1.shared.canAccess, let i = library.macs.firstIndex(where: { $0.id == mac.id }) else { return }
        _ = library.move(fromOffsets: IndexSet(integer: i), toOffset: down ? i + 2 : i - 1)
    }
    private func add() {
        Task {
            if !DirectProAccess.shared.ready { await DirectProAccess.shared.refresh() }
            guard DirectAppLockV1.shared.canAccess else { return }
            sheet = DirectProAccess.shared.canAddMac(count: library.macs.count) ? .add : .pro
        }
    }
    private func open(_ mac: DirectMacRecordV1, mode: MacConnectionMode) {
        Task {
            if !DirectProAccess.shared.ready { await DirectProAccess.shared.refresh() }
            guard DirectAppLockV1.shared.canAccess else { return }
            guard DirectProAccess.shared.canUseMac(mac.id, among: library.macs.map(\.id)) else { sheet = .pro; return }
            openWindow(id: "direct-session", value: MacSessionRequest(macID: mac.id, mode: mode))
        }
    }
}

struct MacSessionWindow: View {
    let request: MacSessionRequest
    let library: DirectMacLibraryV1
    @State private var mac: DirectMacRecordV1?
    @State private var admitted = false
    @State private var pro = false
    init(request: MacSessionRequest, library: DirectMacLibraryV1) {
        self.request = request; self.library = library
        _mac = State(initialValue: library.macs.first { $0.id == request.macID })
    }
    var body: some View {
        Group {
            if let mac, admitted {
                if request.mode == .terminal { MacDirectTerminalView(mac: mac, sessionID: request.id) }
                else { MacDirectDesktopView(mac: mac, sessionID: request.id) }
            } else if mac != nil {
                ContentUnavailableView { Label("Open this Mac", systemImage: "desktopcomputer") }
                    description: { Text("Choose this Mac as your free Mac in My Macs, or use Pro to connect to all your saved Macs.") }
                    actions: { Button("Review Pro") { pro = true } }
                    .frame(minWidth: 520, minHeight: 360)
            } else {
                ContentUnavailableView("Mac unavailable", systemImage: "desktopcomputer", description: Text("This Mac was removed from your library."))
                    .frame(minWidth: 520, minHeight: 360)
            }
        }.id(request.id).directAppearance().modifier(MacPrivacyCover())
            .task { await admit() }
            .sheet(isPresented: $pro, onDismiss: { Task { await admit() } }) {
                DirectProView().frame(minWidth: 480, minHeight: 460).modifier(MacSheetPrivacyCover())
            }
            .onChange(of: DirectAppLockV1.shared.canAccess) { _, allowed in if !allowed { pro = false } }
    }
    private func admit() async {
        guard !admitted else { return }
        if !DirectProAccess.shared.ready { await DirectProAccess.shared.refresh() }
        admitted = DirectProAccess.shared.canUseMac(request.macID, among: library.macs.map(\.id))
    }
}

struct MacPrivacyCover: ViewModifier {
    @State private var lock = DirectAppLockV1.shared
    func body(content: Content) -> some View {
        content.opacity(lock.canAccess ? 1 : 0).allowsHitTesting(lock.canAccess).accessibilityHidden(!lock.canAccess).overlay {
            if !lock.canAccess {
                VStack(spacing: 18) {
                    Image(systemName: "lock.fill").font(.largeTitle)
                    Text(lock.message)
                    if lock.authenticating { ProgressView() }
                    else { Button("Unlock") { lock.authenticate() }.buttonStyle(.borderedProminent) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .windowBackgroundColor))
                    .accessibilityIdentifier("mac-app-privacy-cover")
            }
        }.onAppear { lock.install() }
    }
}

// Unlike the window cover, a sheet removes its sensitive subtree on lock.
// This also tears down nested presentations and their cached editor state.
struct MacSheetPrivacyContent<Content: View>: View {
    let canAccess: Bool
    let content: Content
    var body: some View { Group { if canAccess { content } } }
}

struct MacSheetPrivacyCover: ViewModifier {
    @State private var lock = DirectAppLockV1.shared
    func body(content: Content) -> some View {
        MacSheetPrivacyContent(canAccess: lock.canAccess, content: content)
            .frame(minWidth: 380, minHeight: 260).modifier(MacPrivacyCover())
            // Respect the editor's declared size instead of the narrower default Mac form width.
            .presentationSizing(.fitted)
    }
}
#endif
