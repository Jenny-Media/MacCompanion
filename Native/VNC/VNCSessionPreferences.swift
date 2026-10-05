#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Security
import SwiftUI

struct VNCQuickAction: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable { case mode, fit, rightClick, shortcut, text }
    var id: UUID = UUID()
    var title: String
    var kind: Kind
    var enabled = true
    var key: UInt32 = 0
    var modifiers: [UInt32] = []
    var text = ""
    static var defaults: [Self] { [.init(title: "Mouse Mode", kind: .mode), .init(title: "Fit View", kind: .fit), .init(title: "Right Click", kind: .rightClick)] }
    var valid: Bool {
        let allowed: Set<UInt32> = [0xffe1, 0xffe3, 0xffe9, 0xffeb]
        let keyValid = (0x20...0x7e).contains(key) || [UInt32(0xff1b), 0xff09, 0xff0d, 0xff08, 0xffff, 0xff51, 0xff52, 0xff53, 0xff54].contains(key)
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 40
            && modifiers.count <= 4 && Set(modifiers).count == modifiers.count && Set(modifiers).isSubset(of: allowed)
            && text.unicodeScalars.count <= 256 && !text.unicodeScalars.contains(where: { $0.value == 0 })
            && (kind != .shortcut || keyValid) && (kind != .text || !text.isEmpty)
    }
    var native: [String: Any] { ["id": id.uuidString, "title": title, "kind": kind.rawValue, "key": key, "modifiers": modifiers, "text": text, "enabled": enabled] }
}

@MainActor enum VNCSessionPreferences {
    private static func changed(_ id: UUID) { NotificationCenter.default.post(name: DirectCloudSyncV1.preferenceChanged, object: id) }
    private static func prefix(_ id: UUID) -> String { "direct-session-\(id.uuidString.lowercased())-" }
    static func speed(_ id: UUID) -> Double {
        let value = UserDefaults.standard.object(forKey: prefix(id) + "speed") as? Double ?? 1.5
        return value.isFinite ? min(3, max(0.5, value)) : 1.5
    }
    static func setSpeed(_ value: Double, mac id: UUID) { if value.isFinite { UserDefaults.standard.set(min(3, max(0.5, value)), forKey: prefix(id) + "speed"); changed(id) } }
    static func display(_ id: UUID) -> NSNumber? { UserDefaults.standard.object(forKey: prefix(id) + "display") as? NSNumber }
    static func setDisplay(_ value: NSNumber?, mac id: UUID) { UserDefaults.standard.set(value, forKey: prefix(id) + "display"); changed(id) }
    static func fullscreen(_ id: UUID) -> Bool { UserDefaults.standard.bool(forKey: prefix(id) + "fullscreen") }
    static func setFullscreen(_ value: Bool, mac id: UUID) { UserDefaults.standard.set(value, forKey: prefix(id) + "fullscreen"); changed(id) }
    static func trackpad(_ id: UUID) -> Bool { UserDefaults.standard.bool(forKey: prefix(id) + "trackpad") }
    static func setTrackpad(_ value: Bool, mac id: UUID) { UserDefaults.standard.set(value, forKey: prefix(id) + "trackpad"); changed(id) }
    static func followCursor(_ id: UUID) -> Bool { UserDefaults.standard.object(forKey: prefix(id) + "follow-cursor") as? Bool ?? true }
    static func setFollowCursor(_ value: Bool, mac id: UUID) { UserDefaults.standard.set(value, forKey: prefix(id) + "follow-cursor"); changed(id) }
    private static func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "media.jenny.maccompanion.direct-actions.v1",
         kSecAttrAccount as String: id.uuidString.lowercased(), kSecAttrSynchronizable as String: false]
    }
    static func actions(_ id: UUID) -> [VNCQuickAction] { (try? readActions(id)) ?? VNCQuickAction.defaults }
    static func readActions(_ id: UUID) throws -> [VNCQuickAction] {
        var q = query(id); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return VNCQuickAction.defaults }
        guard status == errSecSuccess, let data = result as? Data,
              let actions = try? JSONDecoder().decode([VNCQuickAction].self, from: data),
              actions.count <= 15, Set(actions.map(\.id)).count == actions.count, actions.allSatisfy(\.valid) else { throw CocoaError(.fileReadCorruptFile) }
        return actions
    }
    static func saveActions(_ actions: [VNCQuickAction], mac id: UUID) throws {
        // Never replace an unreadable saved entry with presentation defaults.
        _ = try readActions(id)
        guard actions.count <= 15, Set(actions.map(\.id)).count == actions.count, actions.allSatisfy(\.valid) else { throw CocoaError(.fileWriteUnknown) }
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(actions), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query(id) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query(id).merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw CocoaError(.fileWriteUnknown) }
        } else if status != errSecSuccess { throw CocoaError(.fileWriteUnknown) }
    }
    static func clear(_ id: UUID) {
        for suffix in ["speed", "display", "trackpad", "follow-cursor", "fullscreen"] { UserDefaults.standard.removeObject(forKey: prefix(id) + suffix) }
        SecItemDelete(query(id) as CFDictionary)
    }
}

struct VNCInputSettings: View {
    @Environment(\.dismiss) private var dismiss
    let macID: UUID
    let changed: @MainActor () -> Void
    @State private var speed: Double
    @State private var followCursor: Bool
    @State private var actions: [VNCQuickAction]
    @State private var editor: VNCQuickAction?
    @State private var error: String?
    @State private var actionEditMode: EditMode = .inactive
    private let actionsReadable: Bool
    init(macID: UUID, changed: @escaping @MainActor () -> Void) {
        self.macID = macID; self.changed = changed
        _speed = State(initialValue: VNCSessionPreferences.speed(macID))
        _followCursor = State(initialValue: VNCSessionPreferences.followCursor(macID))
        let loaded = try? VNCSessionPreferences.readActions(macID)
        actionsReadable = loaded != nil
        _actions = State(initialValue: loaded ?? [])
    }
    var body: some View {
        NavigationStack {
            Form {
                if !actionsReadable { Section { Text("Saved quick actions could not be read. They have been preserved. Unlock your iPhone and try again.").foregroundStyle(.secondary) } }
                Section {
                    HStack { Text("Pointer Speed"); Spacer(); Text(speed, format: .number.precision(.fractionLength(1))).foregroundStyle(.secondary) }
                    Slider(value: $speed, in: 0.5...3, step: 0.1).accessibilityLabel("Pointer Speed")
                    Button("Reset to Default") { speed = 1.5 }
                } footer: { Text("Slow movement stays precise. Faster swipes travel farther. Speed is saved for this Mac.") }
                Section {
                    Toggle("Follow Cursor", isOn: $followCursor).accessibilityIdentifier("follow-cursor-toggle")
                } footer: { Text("In zoomed Trackpad mode, move the view to keep the cursor visible. Manual pan or zoom pauses following until your next trackpad movement. Saved for this Mac.") }
                Section {
                    ForEach($actions) { $action in
                        HStack {
                            Toggle(isOn: $action.enabled) {
                                Button(action.title) { if action.kind == .shortcut || action.kind == .text { editor = action } }
                                    .buttonStyle(.plain)
                            }
                        }
                    }.onMove { actions.move(fromOffsets: $0, toOffset: $1) }.onDelete { actions.remove(atOffsets: $0) }
                    if actions.filter({ $0.kind == .shortcut || $0.kind == .text }).count < 12 {
                        Button("Add Shortcut", systemImage: "command") { editor = .init(title: "", kind: .shortcut, key: 0x63, modifiers: [0xffeb]) }
                        Button("Add Saved Text", systemImage: "text.quote") { editor = .init(title: "", kind: .text) }
                    }
                    Button("Restore Default Actions") { actions = VNCQuickAction.defaults }
                } header: {
                    HStack {
                        Text("Quick Actions"); Spacer()
                        Button(actionEditMode.isEditing ? "Done" : "Reorder") {
                            withAnimation { actionEditMode = actionEditMode.isEditing ? .inactive : .active }
                        }.textCase(nil).accessibilityIdentifier("quick-actions-reorder")
                    }
                } footer: {
                    Text("Use Reorder to arrange or remove actions. Press the controls button, slide to an action and release. Saved text is stored on this iPhone and sent as typing to the focused Mac field.")
                }.disabled(!actionsReadable)
            }
            .navigationTitle("Input & Quick Actions").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!actionsReadable) }
            }
            .sheet(item: $editor) { action in VNCActionEditor(action: action) { edited in
                if let index = actions.firstIndex(where: { $0.id == edited.id }) { actions[index] = edited } else { actions.append(edited) }
            } }
            .environment(\.editMode, $actionEditMode)
            .alert("Could Not Save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        }
        .interactiveDismissDisabled()
    }
    private func save() {
        do { try VNCSessionPreferences.saveActions(actions, mac: macID); VNCSessionPreferences.setSpeed(speed, mac: macID); VNCSessionPreferences.setFollowCursor(followCursor, mac: macID); changed(); dismiss() }
        catch { self.error = "Quick actions could not be saved. Your previous actions are preserved." }
    }
}

private struct VNCActionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var action: VNCQuickAction
    let save: (VNCQuickAction) -> Void
    @State private var letter = ""
    private let modifierKeys: [(String, UInt32)] = [("Shift", 0xffe1), ("Control", 0xffe3), ("Option", 0xffe9), ("Command", 0xffeb)]
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Action Name", text: $action.title) }
                if action.kind == .text {
                    Section {
                        TextEditor(text: $action.text).frame(minHeight: 140).accessibilityLabel("Saved Text")
                        Text("\(action.text.unicodeScalars.count)/256 characters").foregroundStyle(.secondary)
                    } footer: { Text("Sent only when you select this action. Check the focused field on your Mac before sending.") }
                } else {
                    Section("Modifiers") {
                        ForEach(modifierKeys, id: \.0) { title, key in
                            Toggle(title, isOn: Binding(get: { action.modifiers.contains(key) }, set: { enabled in
                                action.modifiers.removeAll { $0 == key }; if enabled { action.modifiers.append(key) }
                            }))
                        }
                    }
                    Section("Key") {
                        TextField("Letter or symbol", text: $letter).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .onChange(of: letter) { _, text in if text.unicodeScalars.count == 1, let value = text.unicodeScalars.first?.value { action.key = value } else { action.key = 0 } }
                        Picker("Special Key", selection: $action.key) {
                            Text("Character").tag(action.key < 0xff00 ? action.key : 0)
                            ForEach([("Escape", UInt32(0xff1b)), ("Tab", 0xff09), ("Return", 0xff0d), ("Backspace", 0xff08), ("Delete", 0xffff), ("Left", 0xff51), ("Up", 0xff52), ("Right", 0xff53), ("Down", 0xff54)], id: \.1) { title, key in Text(title).tag(key) }
                        }
                    }
                }
            }
            .navigationTitle(action.kind == .text ? "Saved Text" : "Shortcut").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(action); dismiss() }.disabled(!action.valid) }
            }
            .onAppear { if action.key < 0xff00, let scalar = UnicodeScalar(action.key) { letter = String(scalar) } }
        }
    }
}
#endif
