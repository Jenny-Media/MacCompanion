#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import AppKit
import SwiftUI

struct MacMachineLibraryView: View {
    let library: DirectMacLibraryV1
    let tools: MacToolApplicationModel
    init(library: DirectMacLibraryV1, tools: MacToolApplicationModel? = nil) {
        self.library = library; self.tools = tools ?? MacToolApplicationModel(library: library)
    }
    @Environment(\.openWindow) private var openWindow
    @State private var selected: UUID?
    @State private var search = ""
    @State private var sheet: Sheet?
    @State private var removing: DirectMacRecordV1?
    @State private var connections = MacConnectionRegistry.shared
    @State private var cloud = DirectCloudSyncV1.shared
    private enum Sheet: Identifiable {
        case add, edit(DirectMacRecordV1), pro, setup
        var id: String { switch self { case .add: "add"; case .edit(let mac): "edit-" + mac.id.uuidString; case .pro: "pro"; case .setup: "setup" } }
    }
    private var selectedMac: DirectMacRecordV1? { library.macs.first { $0.id == selected } }
    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                ForEach(library.macs.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.addresses.contains(where: { $0.localizedCaseInsensitiveContains(search) }) }) { mac in
                    Label { VStack(alignment: .leading) {
                        Text(mac.name)
                        let count = connections.connections(for: mac.id).filter { $0.phase == .connected }.count
                        if count > 0 { Text("\(count) connected \(count == 1 ? "session" : "sessions")").font(.caption).foregroundStyle(.secondary) }
                    } }
                        icon: { Image(systemName: mac.family.symbol) }
                        .tag(mac.id)
                        .onTapGesture(count: 2) { selected = mac.id; open(mac, mode: MacConnectionMode(mac.preferredConnection)) }
                        .accessibilityAction(named: "Connect") { open(mac, mode: MacConnectionMode(mac.preferredConnection)) }
                        .contextMenu {
                            ForEach(MacConnectionMode.allCases) { mode in Button(mode.actionTitle) { open(mac, mode: mode) } }
                            Button("New Terminal Window", systemImage: "plus.rectangle") { open(mac, mode: .terminal, another: true) }
                            Button("Browse Files", systemImage: "folder") { openWindow(id: "direct-files", value: DirectFilesWindowRequest(macID: mac.id)) }
                            Divider()
                            Button("Connection Settings") { sheet = .edit(mac) }
                            Button("Use as My Free Mac") { DirectProAccess.shared.chooseFreeMac(mac.id) }
                            Button("Move Up") { move(mac, down: false) }.disabled(library.macs.first?.id == mac.id)
                            Button("Move Down") { move(mac, down: true) }.disabled(library.macs.last?.id == mac.id)
                            Button("Remove Mac", role: .destructive) { removing = mac }
                        }
                }.onMove { _ = library.move(fromOffsets: $0, toOffset: $1) }.moveDisabled(!search.isEmpty)
            }.onKeyPress(.return) {
                guard let mac = selectedMac else { return .ignored }
                open(mac, mode: MacConnectionMode(mac.preferredConnection)); return .handled
            }.navigationTitle("My Macs").searchable(text: $search)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
        } detail: {
            Group {
                if let mac = selectedMac {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            Label(mac.name, systemImage: mac.family.symbol).font(.largeTitle)
                            HStack(alignment: .top, spacing: 20) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Button { open(mac, mode: .desktop) } label: {
                                        HStack(spacing: 8) {
                                            Label("Screen Sharing", systemImage: "desktopcomputer")
                                            Image(systemName: "arrow.up.right").font(.caption).accessibilityHidden(true)
                                        }
                                    }.accessibilityIdentifier("mac-open-desktop")
                                        .accessibilityHint("Opens Apple Screen Sharing")
                                        .disabled(tools.coordinator?.states[mac.id] == .opening)
                                    Text("Opens Apple Screen Sharing").font(.caption).foregroundStyle(.secondary)
                                }
                                Button("Terminal", systemImage: "terminal") { open(mac, mode: .terminal) }
                                    .accessibilityIdentifier("mac-open-terminal")
                            }.buttonStyle(.bordered).controlSize(.large)
                            MacScreenSharingHandoffStatus(macID: mac.id, tools: tools)
                            Button("Connection Settings", systemImage: "gearshape") { sheet = .edit(mac) }
                                .accessibilityIdentifier("mac-connection-settings").buttonStyle(.link).font(.callout)
                            Button("Browse Files", systemImage: "folder") { openWindow(id: "direct-files", value: DirectFilesWindowRequest(macID: mac.id)) }
                                .buttonStyle(.link).font(.callout).help("Browse and transfer files using Remote Login")
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
                        }.padding(32).frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity, alignment: .center)
                    }
                } else if library.macs.isEmpty {
                    ContentUnavailableView { Label("Your Macs, within reach", systemImage: "desktopcomputer") }
                        description: { Text("Add a Mac on your local network or private VPN.") }
                        actions: { Button("Add Mac") { add() }.buttonStyle(.borderedProminent) }
                } else { ContentUnavailableView("Choose a Mac", systemImage: "desktopcomputer", description: Text("Open Screen Sharing or Terminal.")) }
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
            Menu("More", systemImage: "ellipsis.circle") {
                Button("Discover Macs", systemImage: "network") { library.discovery.start() }.disabled(library.discovery.scanning)
                Button("Setup Guide", systemImage: "questionmark.circle") { sheet = .setup }
                if cloud.enabled { Button("Refresh iCloud", systemImage: "arrow.triangle.2.circlepath") { cloud.refresh() }.disabled(cloud.busy) }
            }.help("Discovery, setup and sync")
        }
        .sheet(item: $sheet) { item in
            Group {
                switch item {
                case .add: MacMachineEditor(library: library)
                case .edit(let mac): MacMachineEditor(library: library, mac: mac)
                case .pro: DirectProView().frame(minWidth: 480, minHeight: 460)
                case .setup: DirectMacSetupGuide().frame(width: 560, height: 600)
                }
            }.modifier(MacSheetPrivacyCover())
        }
        .confirmationDialog("Remove this Mac and its local saved login?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove Mac", role: .destructive) { if DirectAppLockV1.shared.canAccess, let removing { library.remove(removing) }; removing = nil }
        } message: {
            Text("Terminal and Files connections will close and transfers will stop. Unsaved downloads stay available until you save or discard them. Apple Screen Sharing stays independent.")
        }
        .onAppear {
            tools.install { [openWindow] macID, windowID in
                openWindow(id: "direct-session", value: MacSessionRequest(id: windowID, macID: macID, mode: .terminal))
            }
            tools.coordinator?.recordsChanged(validIDs: Set(library.macs.map(\.id)))
            if selected == nil { selected = library.macs.first?.id }
        }
        .onChange(of: library.macs) { _, records in
            tools.coordinator?.recordsChanged(validIDs: Set(records.map(\.id)))
            if selected == nil || !records.contains(where: { $0.id == selected }) { selected = records.first?.id }
        }
        .onChange(of: DirectAppLockV1.shared.canAccess) { _, allowed in
            if !allowed { tools.coordinator?.invalidate(); sheet = nil; removing = nil }
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
    private func open(_ mac: DirectMacRecordV1, mode: MacConnectionMode, another: Bool = false) {
        Task {
            if !DirectProAccess.shared.ready { await DirectProAccess.shared.refresh() }
            guard DirectAppLockV1.shared.canAccess else { return }
            guard library.macs.contains(where: { $0.id == mac.id }) else { return }
            guard DirectProAccess.shared.canUseMac(mac.id, among: library.macs.map(\.id)) else { sheet = .pro; return }
            tools.coordinator?.open(MacToolApplicationModel.snapshot(mac), action: mode == .terminal ? (another ? .newTerminal : .terminal) : .desktop)
        }
    }
}

struct MacSessionWindow: View {
    let request: MacSessionRequest
    let library: DirectMacLibraryV1
    let tools: MacToolApplicationModel?
    @Environment(\.openWindow) private var openWindow
    @State private var mac: DirectMacRecordV1?
    @State private var admitted = false
    @State private var pro = false
    @State private var window = MacWindowHandle()
    init(request: MacSessionRequest, library: DirectMacLibraryV1, tools: MacToolApplicationModel? = nil) {
        self.request = request; self.library = library; self.tools = tools
        _mac = State(initialValue: library.macs.first { $0.id == request.macID })
    }
    var body: some View {
        Group {
            if let mac, admitted {
                if request.mode == .terminal { MacDirectTerminalView(mac: mac, sessionID: request.id, libraryURL: library.storageURL) }
                else { MacDirectDesktopView(mac: mac, sessionID: request.id, libraryURL: library.storageURL) }
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
            .onAppear {
                guard request.mode == .terminal, let tools else { return }
                tools.install { [openWindow] macID, windowID in
                    openWindow(id: "direct-session", value: MacSessionRequest(id: windowID, macID: macID, mode: .terminal))
                }
                tools.coordinator?.terminalOpened(macID: request.macID, windowID: request.id)
            }
            .background(MacWindowLifetime {
                if request.mode == .terminal { tools?.coordinator?.terminalClosed(macID: request.macID, windowID: request.id) }
            }.frame(width: 0, height: 0))
            .task { await admit() }
            .sheet(isPresented: $pro, onDismiss: { Task { await admit() } }) {
                DirectProView().frame(minWidth: 480, minHeight: 460).modifier(MacSheetPrivacyCover())
            }
            .onChange(of: DirectAppLockV1.shared.canAccess) { _, allowed in if !allowed { pro = false } }
            .background(MacWindowReader(handle: window).frame(width: 0, height: 0))
            .onChange(of: library.macs.map(\.id)) { _, _ in closeIfRemoved() }
            .onChange(of: window.window != nil) { _, _ in closeIfRemoved() }
    }
    private func closeIfRemoved() {
        if mac != nil, !library.macs.contains(where: { $0.id == request.macID }) { pro = false; window.window?.close() }
    }
    private func admit() async {
        guard !admitted else { return }
        if !DirectProAccess.shared.ready { await DirectProAccess.shared.refresh() }
        guard library.macs.contains(where: { $0.id == request.macID }) else { closeIfRemoved(); return }
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
