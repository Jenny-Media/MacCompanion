#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Security
import SwiftUI

enum DirectControlMode: String, CaseIterable, Identifiable, Sendable {
    case desktop, terminal, trackpad
    var id: String { rawValue }
    var title: String { switch self { case .desktop: "Desktop"; case .terminal: "Terminal"; case .trackpad: "Trackpad & Keyboard" } }
    // Stable local Keychain accounts; these are control profiles, never Mac IDs.
    var profileID: UUID { UUID(uuidString: "C063A810-0710-4000-8000-00000000000" + (self == .desktop ? "1" : self == .terminal ? "2" : "3"))! }
    var defaults: [VNCQuickAction] {
        switch self {
        case .desktop: VNCQuickAction.defaults
        case .trackpad: [.init(title: "Right Click", kind: .rightClick), .init(title: "Return", kind: .returnKey)]
        case .terminal: [.init(title: "Paste", kind: .paste), .init(title: "Interrupt · Ctrl-C", kind: .interrupt)]
        }
    }
    var builtIns: [VNCQuickAction] {
        defaults + [.init(title: "Escape", kind: .escape), .init(title: "Tab", kind: .tab)] + (self == .trackpad ? [] : [.init(title: "Return", kind: .returnKey)])
    }
}

struct VNCQuickAction: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable { case mode, fit, rightClick, shortcut, text, paste, interrupt, escape, tab, returnKey }
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
    func compatible(with mode: DirectControlMode) -> Bool {
        if mode == .terminal { return ![.mode, .fit, .rightClick].contains(kind) && !modifiers.contains(0xffeb) && (kind != .text || !text.contains("\u{1b}")) }
        return ![.paste, .interrupt].contains(kind) && (mode != .trackpad || ![.mode, .fit].contains(kind))
    }
    var symbol: String {
        switch kind {
        case .mode: "cursorarrow.motionlines"; case .fit: "arrow.down.right.and.arrow.up.left"
        case .rightClick: "cursorarrow.click"; case .shortcut: "keyboard"; case .text: "text.quote"
        case .paste: "document.on.clipboard"; case .interrupt: "stop.circle"
        case .escape: "escape"; case .tab: "arrow.right.to.line"; case .returnKey: "return"
        }
    }
    var native: [String: Any] { ["id": id.uuidString, "title": title, "kind": kind.rawValue, "symbol": symbol, "key": key, "modifiers": modifiers, "text": text, "enabled": enabled] }
}

@MainActor enum VNCSessionPreferences {
    static let actionsChanged = Notification.Name("DirectControlActionsChanged")
    static let scrollSpeedChanged = Notification.Name("DirectScrollSpeedChanged")
    static let scrollSpeedKey = "direct-controls-scroll-speed"
    static let trackpadFeedbackChanged = Notification.Name("DirectTrackpadFeedbackChanged")
    static let touchPointsKey = "direct-controls-trackpad-touch-points"
    static let trackpadHapticsKey = "direct-controls-trackpad-haptics"
    static var showsTouchPoints: Bool { UserDefaults.standard.object(forKey: touchPointsKey) as? Bool ?? true }
    static var trackpadHaptics: Bool { UserDefaults.standard.object(forKey: trackpadHapticsKey) as? Bool ?? true }
    static func setTrackpadFeedback(showsTouchPoints: Bool, haptics: Bool) {
        UserDefaults.standard.set(showsTouchPoints, forKey: touchPointsKey)
        UserDefaults.standard.set(haptics, forKey: trackpadHapticsKey)
        NotificationCenter.default.post(name: trackpadFeedbackChanged, object: nil)
    }
    static let scrollSpeedRange = 0.25...4.0
    static var scrollSpeed: Double {
        let value = UserDefaults.standard.object(forKey: scrollSpeedKey) as? Double ?? 1
        return value.isFinite ? min(scrollSpeedRange.upperBound, max(scrollSpeedRange.lowerBound, value)) : 1
    }
    static func setScrollSpeed(_ value: Double) {
        guard value.isFinite else { return }
        UserDefaults.standard.set(min(scrollSpeedRange.upperBound, max(scrollSpeedRange.lowerBound, value)), forKey: scrollSpeedKey)
        NotificationCenter.default.post(name: scrollSpeedChanged, object: nil)
    }
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
    static func actions(_ id: UUID) -> [VNCQuickAction] {
        let saved = (try? readActions(id)) ?? VNCQuickAction.defaults
        return DirectProAccess.shared.hasPro ? saved : saved.filter { $0.kind != .shortcut && $0.kind != .text }
    }
    static func profileActions(_ mode: DirectControlMode, legacyMac: UUID? = nil) throws -> [VNCQuickAction] {
        guard DirectAppLockV1.shared.canAccess else { throw CocoaError(.fileReadNoPermission) }
        if let saved = try storedActions(mode.profileID) {
            guard saved.filter({ $0.kind == .shortcut || $0.kind == .text }).count <= 12, saved.allSatisfy({ $0.compatible(with: mode) }) else { throw CocoaError(.fileReadCorruptFile) }
            return saved
        }
        // Keep pre-existing Desktop customizations until a shared profile is saved.
        if mode == .desktop, let legacyMac, let legacy = try storedActions(legacyMac) { return legacy }
        return mode.defaults
    }
    static func actions(_ mode: DirectControlMode, legacyMac: UUID? = nil) -> [VNCQuickAction] {
        let saved = (try? profileActions(mode, legacyMac: legacyMac)) ?? mode.defaults
        return DirectProAccess.shared.hasPro ? saved : saved.filter { $0.kind != .shortcut && $0.kind != .text }
    }
    static func saveProfile(_ actions: [VNCQuickAction], mode: DirectControlMode) throws {
        _ = try profileActions(mode)
        guard actions.filter({ $0.kind == .shortcut || $0.kind == .text }).count <= 12, actions.allSatisfy({ $0.compatible(with: mode) }) else { throw CocoaError(.fileWriteUnknown) }
        try saveActions(actions, mac: mode.profileID)
        NotificationCenter.default.post(name: actionsChanged, object: mode)
    }
    static func readActions(_ id: UUID) throws -> [VNCQuickAction] { try storedActions(id) ?? VNCQuickAction.defaults }
    private static func storedActions(_ id: UUID) throws -> [VNCQuickAction]? {
        var q = query(id); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
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
    let macID: UUID?
    let mode: DirectControlMode
    let changed: @MainActor () -> Void
    @State private var speed: Double
    @State private var scrollSpeed: Double
    @State private var showsTouchPoints: Bool
    @State private var trackpadHaptics: Bool
    @State private var followCursor: Bool
    @State private var actions: [VNCQuickAction]
    @State private var editor: VNCQuickAction?
    @State private var issue: DirectRecoveryNotice?
    @State private var actionEditMode: EditMode = .inactive
    @State private var paywall = false
    @State private var actionsReadable: Bool
    init(macID: UUID? = nil, mode: DirectControlMode = .desktop, changed: @escaping @MainActor () -> Void = {}) {
        self.macID = macID; self.mode = mode; self.changed = changed
        _scrollSpeed = State(initialValue: VNCSessionPreferences.scrollSpeed)
        _showsTouchPoints = State(initialValue: VNCSessionPreferences.showsTouchPoints)
        _trackpadHaptics = State(initialValue: VNCSessionPreferences.trackpadHaptics)
        _speed = State(initialValue: macID.map(VNCSessionPreferences.speed) ?? 1.5)
        _followCursor = State(initialValue: macID.map(VNCSessionPreferences.followCursor) ?? true)
        let loaded = try? VNCSessionPreferences.profileActions(mode, legacyMac: macID)
        _actionsReadable = State(initialValue: loaded != nil)
        _actions = State(initialValue: loaded ?? [])
    }
    var body: some View {
        NavigationStack {
            Form {
                if !actionsReadable { Section { DirectRecoveryCard(notice: .make(.controlsUnavailable), primary: .init(title: "Retry", perform: reload)) } }
                if let issue { Section { DirectRecoveryCard(notice: issue, primary: .init(title: "Retry Save", perform: save), secondary: .init(title: "Keep Editing", perform: { self.issue = nil })) } }
                if macID != nil && mode != .terminal {
                    Section {
                        HStack { Text("Pointer Speed"); Spacer(); Text(speed, format: .number.precision(.fractionLength(1))).foregroundStyle(.secondary) }
                        Slider(value: $speed, in: 0.5...3, step: 0.1).accessibilityLabel("Pointer Speed")
                        Button("Reset to Default") { speed = 1.5 }
                    } footer: { Text("Slow movement stays precise. Faster swipes travel farther. Speed is saved for this Mac.") }
                    if mode == .desktop {
                        Section {
                            Toggle("Follow Cursor", isOn: $followCursor).accessibilityIdentifier("follow-cursor-toggle")
                        } footer: { Text("In zoomed Trackpad mode, move the view to keep the cursor visible. Manual pan or zoom pauses following until your next trackpad movement. Saved for this Mac.") }
                    }
                }
                if mode != .terminal {
                    Section {
                        HStack { Text("Scroll Speed"); Spacer(); Text(scrollSpeed.formatted(.number.precision(.fractionLength(0...2))) + "×").foregroundStyle(.secondary) }
                        Slider(value: $scrollSpeed, in: VNCSessionPreferences.scrollSpeedRange, step: 0.25)
                            .accessibilityLabel("Scroll Speed").accessibilityIdentifier("scroll-speed-slider")
                        Button("Reset to Default") { scrollSpeed = 1 }
                    } footer: { Text("Two-finger scrolling in Desktop and Trackpad. Applies to all Macs.") }
                    Section {
                        Toggle("Show Touch Points", isOn: $showsTouchPoints).accessibilityIdentifier("trackpad-touch-points-toggle")
                        Toggle("Trackpad Haptics", isOn: $trackpadHaptics).accessibilityIdentifier("trackpad-haptics-toggle")
                    } header: { Text("Touch Feedback") }
                    footer: { Text("Touch rings and tap or drag feedback. Applies to all trackpad surfaces.") }
                }
                Section {
                    ForEach($actions) { $action in
                        HStack {
                            Toggle(isOn: $action.enabled) {
                                Button(action.title) { if action.kind == .shortcut || action.kind == .text { editor = action } }
                                    .buttonStyle(.plain)
                            }
                        }
                    }.onMove { actions.move(fromOffsets: $0, toOffset: $1) }.onDelete { actions.remove(atOffsets: $0) }
                    if DirectProAccess.shared.hasPro && actions.count < 15 {
                        Menu("Add Standard Action") {
                            ForEach(mode.builtIns.filter { candidate in !actions.contains { $0.kind == candidate.kind } }) { candidate in
                                Button(candidate.title, systemImage: candidate.symbol) { actions.append(candidate) }
                            }
                        }
                    }
                    if DirectProAccess.shared.hasPro && actions.count < 15 && actions.filter({ $0.kind == .shortcut || $0.kind == .text }).count < 12 {
                        Button("Add Shortcut", systemImage: "keyboard") { editor = .init(title: "", kind: .shortcut, key: 0x63, modifiers: [mode == .terminal ? 0xffe3 : 0xffeb]) }
                        Button("Add Saved Text", systemImage: "text.quote") { editor = .init(title: "", kind: .text) }
                    }
                    if DirectProAccess.shared.hasPro { Button("Restore Default Actions") { actions = mode.defaults } }
                } header: {
                    HStack {
                        Text("Quick Actions"); Spacer()
                        if DirectProAccess.shared.hasPro {
                            Button(actionEditMode.isEditing ? "Done" : "Reorder") {
                                withAnimation { actionEditMode = actionEditMode.isEditing ? .inactive : .active }
                            }.textCase(nil).accessibilityIdentifier("quick-actions-reorder")
                        }
                    }
                } footer: {
                    Text("Applies to all Macs in this mode. Saved text stays on this iPhone.")
                }.disabled(!actionsReadable || !DirectProAccess.shared.hasPro)
                if !DirectProAccess.shared.hasPro { Section { Button("Customize Quick Actions with Pro") { paywall = true } } }
            }
            .navigationTitle(mode == .trackpad ? "Trackpad Controls" : mode.title + " Controls").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!actionsReadable || (!DirectProAccess.shared.hasPro && macID == nil && mode == .terminal)) }
            }
            .sheet(item: $editor) { action in VNCActionEditor(action: action, mode: mode) { edited in
                if let index = actions.firstIndex(where: { $0.id == edited.id }) { actions[index] = edited } else { actions.append(edited) }
            } }
            .sheet(isPresented: $paywall) { DirectProView() }
            .environment(\.editMode, $actionEditMode)

        }
        .interactiveDismissDisabled()
    }
    private func reload() {
        do { actions = try VNCSessionPreferences.profileActions(mode, legacyMac: macID); actionsReadable = true; issue = nil }
        catch { actionsReadable = false }
    }
    private func save() {
        do {
            if DirectProAccess.shared.hasPro { try VNCSessionPreferences.saveProfile(actions, mode: mode) }
            if let macID, mode != .terminal {
                VNCSessionPreferences.setSpeed(speed, mac: macID)
                if mode == .desktop { VNCSessionPreferences.setFollowCursor(followCursor, mac: macID) }
            }
            if mode != .terminal {
                VNCSessionPreferences.setScrollSpeed(scrollSpeed)
                VNCSessionPreferences.setTrackpadFeedback(showsTouchPoints: showsTouchPoints, haptics: trackpadHaptics)
            }
            changed(); dismiss()
        } catch { issue = .make(.saveFailed) }
    }
}

private struct VNCActionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var action: VNCQuickAction
    let mode: DirectControlMode
    let save: (VNCQuickAction) -> Void
    @State private var letter = ""
    private let modifierKeys: [(String, UInt32)] = [("Shift", 0xffe1), ("Control", 0xffe3), ("Option", 0xffe9), ("Command", 0xffeb)]
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Action Name", text: $action.title)
                    if !action.valid || !action.compatible(with: mode) { Text("Use a name from 1 to 40 characters and a valid shortcut or saved text up to 256 characters.").font(.footnote).foregroundStyle(.secondary) }
                }
                if action.kind == .text {
                    Section {
                        TextEditor(text: $action.text).frame(minHeight: 140).accessibilityLabel("Saved Text").autocorrectionDisabled().textInputAutocapitalization(.never).privacySensitive()
                        Text("\(action.text.unicodeScalars.count)/256 characters").foregroundStyle(.secondary)
                    } footer: { Text(mode == .terminal ? "Sent to the active shell only when selected. A trailing newline can run a command." : "Sent only when you select this action. Check the focused field on your Mac before sending.") }
                } else {
                    Section("Modifiers") {
                        ForEach(modifierKeys.filter { mode != .terminal || $0.1 != 0xffeb }, id: \.0) { title, key in
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
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(action); dismiss() }.disabled(!action.valid || !action.compatible(with: mode)) }
            }
            .onAppear { if action.key < 0xff00, let scalar = UnicodeScalar(action.key) { letter = String(scalar) } }
        }
    }
}
#endif
