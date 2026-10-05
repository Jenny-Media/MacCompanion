#if os(iOS)
import CompanionClient
import SwiftUI

@available(iOS 17.0, *)
public struct ClientMacLibraryViewV1: View {
    private let macs: [ClientSavedMacV1]
    private let failed: Bool
    private let onConnect: @MainActor (UUID) async -> Void
    private let onPair: @MainActor () async -> Void
    private let onRename: @MainActor (UUID, String) async -> Void
    private let onForget: @MainActor (UUID) async -> Void
    @State private var renaming: ClientSavedMacV1?
    @State private var forgetting: ClientSavedMacV1?
    @State private var showingForget = false
    @State private var busy = false

    public init(macs: [ClientSavedMacV1], failed: Bool,
                onConnect: @escaping @MainActor (UUID) async -> Void,
                onPair: @escaping @MainActor () async -> Void,
                onRename: @escaping @MainActor (UUID, String) async -> Void,
                onForget: @escaping @MainActor (UUID) async -> Void) {
        self.macs = macs; self.failed = failed; self.onConnect = onConnect
        self.onPair = onPair; self.onRename = onRename; self.onForget = onForget
    }

    public var body: some View {
        NavigationStack {
            List {
                if failed {
                    Section {
                        Label("Couldn’t complete this change. Try again, or pair the Mac again if its keys are missing.",
                            systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    if macs.isEmpty {
                        ContentUnavailableView("No paired Macs", systemImage: "desktopcomputer",
                            description: Text("Pair with a Mac to control its desktop from here."))
                    }
                    ForEach(macs) { mac in
                        HStack(spacing: 12) {
                            Button {
                                perform { await onConnect(mac.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "desktopcomputer").font(.title2)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(mac.name).foregroundStyle(.primary)
                                        Text(mac.needsRouteSetup ? "Finish connection setup" : "Tap to connect")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("saved-mac-\(mac.id)")
                            Menu {
                                Button("Rename", systemImage: "pencil") {
                                    renaming = mac
                                }
                                Button("Forget This Mac", systemImage: "trash", role: .destructive) {
                                    forgetting = mac; showingForget = true
                                }
                            } label: { Image(systemName: "ellipsis.circle").padding(8) }
                            .accessibilityLabel("Manage \(mac.name)")
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    if !macs.isEmpty { Text("Each Mac has its own pairing and connection settings.") }
                }
                Section {
                    Button("Pair Another Mac", systemImage: "plus.circle") { perform { await onPair() } }
                        .accessibilityIdentifier("pair-another-mac")
                }
            }
            .disabled(busy)
            .navigationTitle("My Macs")
            .sheet(item: $renaming) { mac in
                ClientMacRenameViewV1(mac: mac) { newName in
                    perform { await onRename(mac.id, newName) }
                }
                .presentationDetents([.medium])
            }
            .confirmationDialog("Forget \(forgetting?.name ?? "this Mac")?",
                isPresented: $showingForget,
                titleVisibility: .visible) {
                Button("Forget This Mac", role: .destructive) {
                    guard let mac = forgetting else { return }
                    perform { await onForget(mac.id) }
                }
                Button("Cancel", role: .cancel) { forgetting = nil }
            } message: {
                Text("This removes the pairing from this iPhone. To connect again, pair with the Mac again. You can also remove this device in the Mac app.")
            }
        }
    }

    private func perform(_ action: @escaping @MainActor () async -> Void) {
        guard !busy else { return }
        busy = true
        Task { await action(); busy = false }
    }
}

@available(iOS 17.0, *)
private struct ClientMacRenameViewV1: View {
    let mac: ClientSavedMacV1
    let onSave: @MainActor (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @FocusState private var focused: Bool

    init(mac: ClientSavedMacV1, onSave: @escaping @MainActor (String) -> Void) {
        self.mac = mac
        self.onSave = onSave
        _name = State(initialValue: mac.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Mac name", text: $name)
                    .accessibilityIdentifier("mac-rename-name")
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(save)
            }
            .navigationTitle("Rename Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!validName)
                }
            }
            .onAppear { focused = true }
        }
    }

    private var validName: Bool {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...80).contains(value.count)
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }

    private func save() {
        guard validName else { return }
        onSave(name)
        dismiss()
    }
}
#endif
