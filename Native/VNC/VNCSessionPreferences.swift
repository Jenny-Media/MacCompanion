#if (os(iOS) || os(macOS) || os(visionOS)) && MACCOMPANION_VNC_DEVELOPMENT
import Foundation
import Security
import SwiftUI

enum DirectControlMode: String, CaseIterable, Identifiable, Sendable {
    case desktop, terminal, trackpad
    var id: String { rawValue }
    var title: String { switch self { case .desktop: "Screen Sharing"; case .terminal: "Terminal"; case .trackpad: "Trackpad & Keyboard" } }
    // Stable local Keychain accounts; these are control profiles, never Mac IDs.
    var profileID: UUID { UUID(uuidString: "C063A810-0710-4000-8000-00000000000" + (self == .desktop ? "1" : self == .terminal ? "2" : "3"))! }
    var legacyDefaults: [VNCQuickAction] {
        switch self {
        case .desktop: VNCQuickAction.legacyDefaults
        case .trackpad: [.init(title: "Right Click", kind: .rightClick), .init(title: "Return", kind: .returnKey)]
        case .terminal: [.init(title: "Paste", kind: .paste), .init(title: "Interrupt · Ctrl-C", kind: .interrupt)]
        }
    }
    var defaults: [VNCQuickAction] {
        #if os(iOS)
        if self == .desktop {
            [VNCQuickAction.composeText, .init(title: "Copy Text", kind: .copyText), .init(title: "Right Click", kind: .rightClick)]
        } else { [VNCQuickAction.composeText] + legacyDefaults }
        #else
        legacyDefaults
        #endif
    }
    func upgradingUntouchedDefaults(_ saved: [VNCQuickAction]) -> [VNCQuickAction] {
        #if os(iOS)
        // Ignore generated UUIDs, but retain any user choice including title,
        // disabled state, order, shortcut and snippet data. Do not write on read.
        let legacy = legacyDefaults
        func matches(_ expected: [VNCQuickAction]) -> Bool {
            saved.count == expected.count && zip(saved, expected).allSatisfy { a, b in
                a.title == b.title && a.kind == b.kind && a.enabled == b.enabled &&
                a.key == b.key && a.modifiers == b.modifiers && a.text == b.text
            }
        }
        if self == .desktop && (matches(legacy) || matches([VNCQuickAction.composeText] + legacy)) {
            let retained = saved.filter { [.composeText, .copyText, .rightClick].contains($0.kind) }
            return retained.first?.kind == .composeText ? retained : [VNCQuickAction.composeText] + retained
        }
        if matches(legacy) { return [VNCQuickAction.composeText] + saved }
        #endif
        return saved
    }
    var builtIns: [VNCQuickAction] {
        defaults + (self == .desktop ? legacyDefaults.filter { action in !defaults.contains { $0.kind == action.kind } } : [])
            + [.init(title: "Escape", kind: .escape), .init(title: "Tab", kind: .tab)]
            + (self == .trackpad ? [] : [.init(title: "Return", kind: .returnKey)])
    }
}

struct VNCQuickAction: Codable, Identifiable, Equatable, Sendable {
    static var composeText: Self { .init(id: UUID(uuidString: "C063A810-0710-4000-9000-000000000004")!, title: "Compose Text", kind: .composeText) }
    static let maximumCount = 15
    static let maximumCustomCount = 12
    enum Kind: String, Codable, CaseIterable, Sendable { case mode, fit, copyText, composeText, rightClick, shortcut, text, paste, interrupt, escape, tab, returnKey }
    var id: UUID = UUID()
    var title: String
    var kind: Kind
    var enabled = true
    var key: UInt32 = 0
    var modifiers: [UInt32] = []
    var text = ""
    var isCustom: Bool { kind == .shortcut || kind == .text }
    var displayTitle: String { kind == .fit ? "Fit to Window" : title }
    static func canAddCustom(to actions: [Self]) -> Bool {
        actions.count < maximumCount && actions.filter(\.isCustom).count < maximumCustomCount
    }
    static var defaults: [Self] {
        DirectControlMode.desktop.defaults
    }
    static var legacyDefaults: [Self] {
        var actions = [Self(title: "Mouse Mode", kind: .mode)]
        #if os(iOS)
        actions.append(.init(title: "Copy Text", kind: .copyText))
        #endif
        return actions + [.init(title: "Fit to Window", kind: .fit), .init(title: "Right Click", kind: .rightClick)]
    }
    var valid: Bool {
        let allowed: Set<UInt32> = [0xffe1, 0xffe3, 0xffe9, 0xffeb]
        let keyValid = (0x20...0x7e).contains(key) || [UInt32(0xff1b), 0xff09, 0xff0d, 0xff08, 0xffff, 0xff51, 0xff52, 0xff53, 0xff54].contains(key)
        return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 40
            && modifiers.count <= 4 && Set(modifiers).count == modifiers.count && Set(modifiers).isSubset(of: allowed)
            && text.unicodeScalars.count <= 256 && !text.unicodeScalars.contains(where: { $0.value == 0 })
            && (kind != .shortcut || keyValid) && (kind != .text || !text.isEmpty)
    }
    func compatible(with mode: DirectControlMode) -> Bool {
        #if !os(iOS)
        if kind == .composeText { return false }
        #endif
        #if os(macOS)
        if kind == .copyText { return false }
        #endif
        #if !os(iOS)
        if mode == .terminal && modifiers.contains(0xffeb) { return false }
        #endif
        if mode == .terminal { return ![.mode, .fit, .copyText, .rightClick].contains(kind) && (kind != .text || !text.contains("\u{1b}")) }
        return ![.paste, .interrupt].contains(kind) && (mode != .trackpad || ![.mode, .fit, .copyText].contains(kind))
    }
    var symbol: String {
        switch kind {
        case .mode: "cursorarrow.motionlines"; case .fit: "arrow.down.right.and.arrow.up.left"
        case .copyText: "text.viewfinder"
        case .composeText: "square.and.pencil"
        case .rightClick: "cursorarrow.click"; case .shortcut: "keyboard"; case .text: "text.quote"
        case .paste: "document.on.clipboard"; case .interrupt: "stop.circle"
        case .escape: "escape"; case .tab: "arrow.right.to.line"; case .returnKey: "return"
        }
    }
    var native: [String: Any] { ["id": id.uuidString, "title": displayTitle, "kind": kind.rawValue, "symbol": symbol, "key": key, "modifiers": modifiers, "text": text, "enabled": enabled] }
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
    // Device-local mode: zero mirrors the Mac; 1–3 choose a virtual landscape size.
    static func desktopSizeKey(_ id: UUID) -> String { prefix(id) + "desktop-size" }
    static func desktopSize(_ id: UUID) -> Int {
        guard let value = UserDefaults.standard.object(forKey: desktopSizeKey(id)) as? Int,
              (0...3).contains(value) else { return 2 }
        return value
    }
    static func setDesktopSize(_ value: Int, mac id: UUID) {
        guard (0...3).contains(value) else { return }
        UserDefaults.standard.set(value, forKey: desktopSizeKey(id))
    }
    static func fullscreen(_ id: UUID) -> Bool { UserDefaults.standard.bool(forKey: prefix(id) + "fullscreen") }
    static func setFullscreen(_ value: Bool, mac id: UUID) { UserDefaults.standard.set(value, forKey: prefix(id) + "fullscreen"); changed(id) }
    static func trackpad(_ id: UUID) -> Bool { UserDefaults.standard.bool(forKey: prefix(id) + "trackpad") }
    static func setTrackpad(_ value: Bool, mac id: UUID) { UserDefaults.standard.set(value, forKey: prefix(id) + "trackpad"); changed(id) }
    static func followCursor(_ id: UUID) -> Bool { UserDefaults.standard.object(forKey: prefix(id) + "follow-cursor") as? Bool ?? true }
    static func setFollowCursor(_ value: Bool, mac id: UUID) { UserDefaults.standard.set(value, forKey: prefix(id) + "follow-cursor"); changed(id) }
    private static func query(_ id: UUID) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "media.jenny.maccompanion.direct-actions.v1",
         kSecAttrAccount as String: id.uuidString.lowercased(), kSecAttrSynchronizable as String: false]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }
    static func actions(_ id: UUID) -> [VNCQuickAction] {
        let saved = (try? readActions(id)) ?? VNCQuickAction.defaults
        return DirectProAccess.shared.hasPro ? saved : saved.filter { $0.kind != .shortcut && $0.kind != .text }
    }
    static func profileActions(_ mode: DirectControlMode, legacyMac: UUID? = nil) throws -> [VNCQuickAction] {
        guard DirectAppLockV1.shared.canAccess else { throw CocoaError(.fileReadNoPermission) }
        if let saved = try storedActions(mode.profileID) {
            guard saved.filter(\.isCustom).count <= VNCQuickAction.maximumCustomCount, saved.allSatisfy({ $0.compatible(with: mode) }) else { throw CocoaError(.fileReadCorruptFile) }
            return mode.upgradingUntouchedDefaults(saved)
        }
        // Keep pre-existing Desktop customizations until a shared profile is saved.
        if mode == .desktop, let legacyMac, let legacy = try storedActions(legacyMac) { return mode.upgradingUntouchedDefaults(legacy) }
        return mode.defaults
    }
    static func actions(_ mode: DirectControlMode, legacyMac: UUID? = nil) -> [VNCQuickAction] {
        let saved = (try? profileActions(mode, legacyMac: legacyMac)) ?? mode.defaults
        return DirectProAccess.shared.hasPro ? saved : saved.filter { $0.kind != .shortcut && $0.kind != .text }
    }
    static func saveProfile(_ actions: [VNCQuickAction], mode: DirectControlMode) throws {
        _ = try profileActions(mode)
        guard actions.filter(\.isCustom).count <= VNCQuickAction.maximumCustomCount, actions.allSatisfy({ $0.compatible(with: mode) }) else { throw CocoaError(.fileWriteUnknown) }
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
              actions.count <= VNCQuickAction.maximumCount, Set(actions.map(\.id)).count == actions.count, actions.allSatisfy(\.valid) else { throw CocoaError(.fileReadCorruptFile) }
        return actions
    }
    static func saveActions(_ actions: [VNCQuickAction], mac id: UUID) throws {
        // Never replace an unreadable saved entry with presentation defaults.
        _ = try readActions(id)
        guard actions.count <= VNCQuickAction.maximumCount, Set(actions.map(\.id)).count == actions.count, actions.allSatisfy(\.valid) else { throw CocoaError(.fileWriteUnknown) }
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(actions), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query(id) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query(id).merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw CocoaError(.fileWriteUnknown) }
        } else if status != errSecSuccess { throw CocoaError(.fileWriteUnknown) }
    }
    static func clearTemporary(_ id: UUID) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CocoaError(.fileWriteUnknown) }
        clear(id)
    }
    static func clear(_ id: UUID) {
        for suffix in ["speed", "display", "trackpad", "follow-cursor", "fullscreen", "desktop-size"] { UserDefaults.standard.removeObject(forKey: prefix(id) + suffix) }
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
    @State private var issue: DirectRecoveryNotice?
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
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if !actionsReadable { DirectRecoveryCard(notice: .make(.controlsUnavailable), primary: .init(title: "Retry", perform: reload)) }
                        if let issue { DirectRecoveryCard(notice: issue, primary: .init(title: "Retry Save", perform: save), secondary: .init(title: "Keep Editing", perform: { self.issue = nil })) }
                        DirectQuickActionsEditor(actions: $actions, mode: mode, readable: actionsReadable, macID: macID,
                            selectionChanged: { withAnimation { scroll.scrollTo("quick-action-inspector", anchor: .top) } })
                            .padding(12).background(.background, in: RoundedRectangle(cornerRadius: 20))
                        if macID != nil && mode != .terminal {
                            controlsCard("Pointer · This Mac", footer: "Adjust trackpad movement for this Mac.") {
                                HStack { Text("Pointer Speed"); Spacer(); Text(speed, format: .number.precision(.fractionLength(1))).foregroundStyle(.secondary) }
                                Slider(value: $speed, in: 0.5...3, step: 0.1).accessibilityLabel("Pointer Speed")
                                Button("Reset to Default") { speed = 1.5 }
                                if mode == .desktop {
                                    Divider()
                                    Toggle("Keep Pointer Visible", isOn: $followCursor).accessibilityIdentifier("follow-cursor-toggle")
                                    Text("Keep the cursor visible in zoomed Trackpad mode. Pan or zoom pauses following until the next pointer movement.").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        if mode != .terminal {
                            controlsCard("Scrolling", footer: localScopeDescription) {
                                HStack { Text("Scroll Speed"); Spacer(); Text(scrollSpeed.formatted(.number.precision(.fractionLength(0...2))) + "×").foregroundStyle(.secondary) }
                                Slider(value: $scrollSpeed, in: VNCSessionPreferences.scrollSpeedRange, step: 0.25)
                                    .accessibilityLabel("Scroll Speed").accessibilityIdentifier("scroll-speed-slider")
                                Button("Reset to Default") { scrollSpeed = 1 }
                            }
                            #if os(iOS)
                            controlsCard("Touch & Haptics", footer: localScopeDescription) {
                                Toggle("Show Touch Indicators", isOn: $showsTouchPoints).accessibilityIdentifier("trackpad-touch-points-toggle")
                                Toggle("Haptic Feedback", isOn: $trackpadHaptics).accessibilityIdentifier("trackpad-haptics-toggle")
                            }
                            #endif
                        }
                    }.padding(16)
                }
                #if !os(visionOS)
                .scrollDismissesKeyboard(.interactively)
                #endif
                .background(pageBackground)
            }
            .navigationTitle(mode == .trackpad ? "Trackpad Controls" : mode.title + " Controls").directInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!actionsReadable || !DirectQuickActionEditing.canSave(actions, mode: mode, hasPro: DirectProAccess.shared.hasPro)) }
            }
        }.interactiveDismissDisabled().directAppearance()
    }
    private var localScopeDescription: String {
        #if os(iOS)
        "Applies to all Mac connections on this \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")."
        #elseif os(visionOS)
        "Applies to all Mac connections on this Vision Pro."
        #else
        "Applies to all Mac connections on this Mac."
        #endif
    }
    private var pageBackground: Color {
        #if os(iOS) || os(visionOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
    private func controlsCard<Content: View>(_ title: String, footer: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
            Text(footer).font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }
    private func reload() {
        do { actions = try VNCSessionPreferences.profileActions(mode, legacyMac: macID); actionsReadable = true; issue = nil }
        catch { actionsReadable = false }
    }
    private func save() {
        guard DirectAppLockV1.shared.canAccess, actionsReadable,
              DirectQuickActionEditing.canSave(actions, mode: mode, hasPro: DirectProAccess.shared.hasPro) else { return }
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

#endif
