import AppKit
import Observation
import SwiftUI

struct WorkspaceTerminalRequest: Codable, Hashable { let id: UUID; let macID: UUID }

@MainActor @Observable final class WorkspacePrototypeModel {
    let library: DirectMacLibraryV1
    var coordinator: WorkspaceCoordinator?
    init() {
        let root = URL.applicationSupportDirectory.appending(path: "MacCompanionWorkspacePrototype", directoryHint: .isDirectory)
        // Redirect only this process's shared SSH metadata. No production Mac
        // library, saved login, key selection or cloud preference is imported.
        setenv("MACCOMPANION_DIRECT_DATA_DIRECTORY", root.path, 1)
        library = DirectMacLibraryV1(url: root.appending(path: "macs-v1.json"))
    }
    static func snapshot(_ mac: DirectMacRecordV1) -> WorkspaceMachine {
        .init(id: mac.id, name: mac.name, addresses: mac.addresses, desktopPort: mac.port, sshPort: mac.sshPort)
    }
    func install(openTerminal: @escaping @MainActor (UUID, UUID) -> Void) {
        guard coordinator == nil else { return }
        let library = library
        coordinator = WorkspaceCoordinator(openDesktop: AppleScreenSharing.open, openTerminal: openTerminal,
            canAccess: { DirectAppLockV1.shared.canAccess }, isCurrent: { target in
                library.readable && library.macs.contains { Self.snapshot($0) == target }
            })
    }
}

@main struct WorkspacePrototypeApplication: App {
    @State private var model = WorkspacePrototypeModel()
    var body: some Scene {
        Window("Mac Companion Prototype", id: "workspace-library") {
            WorkspaceLibraryView(model: model).directAppearance().modifier(MacPrivacyCover())
        }.defaultSize(width: 850, height: 560)
        WindowGroup("Terminal", id: "workspace-terminal", for: WorkspaceTerminalRequest.self) { $request in
            if let request {
                WorkspaceTerminalWindow(request: request, model: model)
            } else {
                ContentUnavailableView("Mac unavailable", systemImage: "terminal")
            }
        }.defaultSize(width: 1000, height: 680)
        WindowGroup("Files", id: "direct-files", for: DirectFilesWindowRequest.self) { $request in
            if let request {
                MacFilesWindow(mac: model.library.macs.first { $0.id == request.macID })
                    .directAppearance().modifier(MacPrivacyCover())
            }
        }.defaultSize(width: 720, height: 640)
        Settings {
            Form {
                Toggle("Require unlock", isOn: Binding(get: { DirectAppLockV1.shared.enabled }, set: { DirectAppLockV1.shared.setEnabled($0) }))
                Text("Unlock protects this app and its Terminal windows. Apple Screen Sharing remains independent.")
                    .foregroundStyle(.secondary)
                Text("Saved Macs and settings are local to this prototype.").font(.caption).foregroundStyle(.secondary)
            }.padding(24).frame(width: 400).modifier(MacPrivacyCover())
        }
    }
}

private struct WorkspaceTerminalWindow: View {
    let request: WorkspaceTerminalRequest
    let model: WorkspacePrototypeModel
    @State private var nativeRequest: MacSessionRequest
    init(request: WorkspaceTerminalRequest, model: WorkspacePrototypeModel) {
        self.request = request; self.model = model
        _nativeRequest = State(initialValue: MacSessionRequest(macID: request.macID, mode: .terminal))
    }
    var body: some View {
        MacSessionWindow(request: nativeRequest, library: model.library)
            .background(MacWindowLifetime {
                model.coordinator?.terminalClosed(macID: request.macID, windowID: request.id)
            }.frame(width: 0, height: 0))
    }
}

private struct WorkspaceLibraryView: View {
    let model: WorkspacePrototypeModel
    @Environment(\.openWindow) private var openWindow
    @State private var selected: UUID?
    @State private var search = ""
    @State private var editor: Editor?
    @State private var needsFreeMac: DirectMacRecordV1?
    @State private var pendingAction = WorkspaceCoordinator.Action.desktop
    private struct Editor: Identifiable { let id = UUID(); let mac: DirectMacRecordV1? }
    private var selectedMac: DirectMacRecordV1? { model.library.macs.first { $0.id == selected } }
    var body: some View {
        NavigationSplitView {
            List(selection: $selected) {
                ForEach(model.library.macs.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { mac in
                    Label(mac.name, systemImage: mac.family.symbol).tag(mac.id)
                        .contextMenu { Button("Connection Settings") { editor = Editor(mac: mac) } }
                }
            }.navigationTitle("My Macs").searchable(text: $search)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            if let mac = selectedMac {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Label(mac.name, systemImage: mac.family.symbol).font(.largeTitle)
                        HStack(alignment: .top, spacing: 20) {
                            VStack(alignment: .leading, spacing: 8) {
                                Button { open(mac, .desktop) } label: {
                                    HStack(spacing: 8) {
                                        Label("Screen Sharing", systemImage: "desktopcomputer")
                                        Image(systemName: "arrow.up.right").font(.caption).accessibilityHidden(true)
                                    }
                                }
                                .accessibilityIdentifier("prototype-screen-sharing")
                                .accessibilityHint("Opens Apple Screen Sharing")
                                .disabled(model.coordinator?.states[mac.id] == .opening)
                                Text("Opens Apple Screen Sharing").font(.caption).foregroundStyle(.secondary)
                            }
                            Button("Terminal", systemImage: "terminal") { open(mac, .terminal) }
                                .accessibilityIdentifier("prototype-terminal")
                        }.buttonStyle(.bordered).controlSize(.large)
                        let state = model.coordinator?.states[mac.id] ?? .idle
                        if state != .idle {
                            Label(state.title, systemImage: state == .opening ? "hourglass" : "arrow.up.forward.app")
                                .font(.callout).foregroundStyle(.secondary)
                                .accessibilityIdentifier("workspace-desktop-status")
                        }
                        if case .failed(let reason) = state {
                            Text(reason.message).font(.callout).foregroundStyle(.secondary)
                            Button("Retry Screen Sharing") { open(mac, .desktop) }
                        }
                        Button("Connection Settings", systemImage: "gearshape") { editor = Editor(mac: mac) }
                            .buttonStyle(.link).font(.callout)
                    }.padding(32).frame(maxWidth: 620, alignment: .leading)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("Your Macs", systemImage: "desktopcomputer")
                } description: {
                    Text("Add a Mac to use Screen Sharing or Terminal.")
                } actions: {
                    Button("Add Mac") { editor = Editor(mac: nil) }.disabled(!model.library.readable)
                }
            }
        }
        .frame(minWidth: 720, minHeight: 460)
        .toolbar {
            Button("Add Mac", systemImage: "plus") { editor = Editor(mac: nil) }.disabled(!model.library.readable)
        }
        .safeAreaInset(edge: .bottom) {
            if let recovery = model.library.recovery {
                DirectRecoveryCard(notice: recovery, primary: .init(title: "Retry", perform: { model.library.reload() })).padding()
            }
        }
        .sheet(item: $editor) { value in
            MacMachineEditor(library: model.library, mac: value.mac).modifier(MacSheetPrivacyCover())
        }
        .confirmationDialog("Use this as your free Mac?", isPresented: Binding(get: { needsFreeMac != nil }, set: { if !$0 { needsFreeMac = nil } }), titleVisibility: .visible) {
            Button("Use as My Free Mac") {
                guard DirectAppLockV1.shared.canAccess, let mac = needsFreeMac else { return }
                DirectProAccess.shared.chooseFreeMac(mac.id); needsFreeMac = nil
                model.coordinator?.open(WorkspacePrototypeModel.snapshot(mac), action: pendingAction)
            }
        }
        .onAppear {
            model.install { macID, windowID in
                openWindow(id: "workspace-terminal", value: WorkspaceTerminalRequest(id: windowID, macID: macID))
            }
            if selected == nil { selected = model.library.macs.first?.id }
        }
        .onChange(of: model.library.macs) { _, records in
            model.coordinator?.recordsChanged(validIDs: Set(records.map(\.id)))
            if selected == nil || !records.contains(where: { $0.id == selected }) { selected = records.first?.id }
        }
        .onChange(of: DirectAppLockV1.shared.canAccess) { _, allowed in
            if !allowed { model.coordinator?.invalidate(); editor = nil; needsFreeMac = nil }
        }
    }
    private func open(_ mac: DirectMacRecordV1, _ action: WorkspaceCoordinator.Action) {
        guard DirectAppLockV1.shared.canAccess, model.library.readable else { return }
        guard DirectProAccess.shared.canUseMac(mac.id, among: model.library.macs.map(\.id)) else {
            needsFreeMac = mac; pendingAction = action; return
        }
        model.coordinator?.open(WorkspacePrototypeModel.snapshot(mac), action: action)
    }
}
