#if (os(iOS) || os(macOS) || os(visionOS)) && MACCOMPANION_VNC_DEVELOPMENT
import LocalAuthentication
import SwiftUI

#if os(iOS)
/// Keep discovery's refresh environment inside the list. Presentations attached
/// by callers must not inherit a network scan as their own refresh action.
struct DirectMacDiscoveryList<Rows: View>: View {
    let refresh: @Sendable () async -> Void
    let rows: Rows
    init(refresh: @escaping @Sendable () async -> Void, @ViewBuilder content: () -> Rows) {
        self.refresh = refresh; rows = content()
    }
    var body: some View { List { rows }.refreshable(action: refresh) }
}

/// The list row owns every route, including native full-swipe actions. Each
/// route uses the same admission path supplied by the library, never a direct connect.
struct DirectMacLibraryRow: View {
    let mac: DirectMacRecordV1
    let reordering: Bool
    let canChooseFreeMac: Bool
    let open: (DirectMacConnection) -> Void
    let browseFiles: () -> Void
    let edit: () -> Void
    let remove: () -> Void
    let chooseFreeMac: () -> Void
    @ScaledMetric(relativeTo: .title2) private var menuIconSize = 22
    @AppStorage private var desktopSize: Int

    init(mac: DirectMacRecordV1, reordering: Bool, canChooseFreeMac: Bool,
         open: @escaping (DirectMacConnection) -> Void, browseFiles: @escaping () -> Void,
         edit: @escaping () -> Void, remove: @escaping () -> Void, chooseFreeMac: @escaping () -> Void) {
        self.mac = mac; self.reordering = reordering; self.canChooseFreeMac = canChooseFreeMac
        self.open = open; self.browseFiles = browseFiles; self.edit = edit
        self.remove = remove; self.chooseFreeMac = chooseFreeMac
        _desktopSize = AppStorage(wrappedValue: 2, VNCSessionPreferences.desktopSizeKey(mac.id))
    }
    private var displayMode: String { desktopSize == 0 ? "Mirror Mac Screen" : "Virtual Display" }
    private var connectionSummary: String {
        mac.preferredConnection == .desktop ? displayMode : mac.preferredConnection.title
    }
    var body: some View {
        HStack(spacing: 12) {
            Button { open(mac.preferredConnection) } label: { DirectMacListRowLabel(mac: mac, connectionSummary: connectionSummary) }
                .buttonStyle(.plain).disabled(reordering)
                .accessibilityLabel("Connect to " + mac.name + " using " + mac.preferredConnection.title)
                .accessibilityValue(mac.preferredConnection == .desktop ? displayMode : "")
                .accessibilityHint(mac.family.title)
                .accessibilityIdentifier("mac-connect-" + mac.id.uuidString)
            if !reordering {
                Menu {
                    Section("Connect") {
                        Button("Screen Sharing", systemImage: DirectMacConnection.desktop.symbol) { open(.desktop) }
                            .accessibilityHint("View and control this Mac")
                        Button("Trackpad & Keyboard", systemImage: DirectMacConnection.trackpad.symbol) { open(.trackpad) }
                        Button("Terminal", systemImage: DirectMacConnection.terminal.symbol) { open(.terminal) }
                    }
                    Button("Browse Files", systemImage: "folder", action: browseFiles)
                    Section("Manage Mac") {
                        Button("Mac Settings", systemImage: "gearshape", action: edit)
                        if canChooseFreeMac { Button("Use as My Free Mac", action: chooseFreeMac) }
                        Button("Remove Mac", systemImage: "trash", role: .destructive, action: remove)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: min(menuIconSize, 32))).frame(width: 44, height: 44)
                }.accessibilityLabel("Manage " + mac.name)
                    .accessibilityIdentifier("mac-manage-" + mac.id.uuidString)
            }
        }.padding(.vertical, 4)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if !reordering, let connection = mac.swipeLeft.connection {
                    Button(connection.title, systemImage: connection.symbol) { open(connection) }
                        .tint(connection.shortcutColor).accessibilityIdentifier("mac-swipe-left-" + mac.id.uuidString)
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if !reordering, let connection = mac.swipeRight.connection {
                    Button(connection.title, systemImage: connection.symbol) { open(connection) }
                        .tint(connection.shortcutColor).accessibilityIdentifier("mac-swipe-right-" + mac.id.uuidString)
                }
            }
    }
}

/// A draft binding keeps Cancel independent from the saved per-Mac preference.
struct DirectDesktopDisplaySection: View {
    @Binding var selection: Int
    var body: some View {
        Section {
            choice("Virtual Display", detail: "Landscape desktop sized for remote use.", symbol: "display", selected: selection != 0) {
                if selection == 0 { selection = 2 }
            }
            choice("Mirror Mac Screen", detail: "Use the Mac’s screen resolution and layout.", symbol: "display.2", selected: selection == 0) { selection = 0 }
            if selection != 0 {
                DisclosureGroup("Advanced") {
                    Picker("Desktop Size", selection: $selection) {
                        Text("Larger Text").tag(1)
                        Text("Balanced").tag(2)
                        Text("More Space").tag(3)
                    }.accessibilityIdentifier("mac-desktop-size")
                }
            }
        } header: { Text("Screen Sharing Display") }
        footer: {
            Text(selection == 0
                 ? "The Mac’s screen stays visible. Large displays may use more data."
                 : "Recommended. The Mac’s screen may go dark while connected. Rotating your iPhone or opening the keyboard won’t resize the desktop.")
        }
    }
    private func choice(_ title: String, detail: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 28).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).foregroundStyle(.primary)
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Color.accentColor : .secondary)
            }.padding(.vertical, 4).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(selectionID(title))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func selectionID(_ title: String) -> String { title == "Virtual Display" ? "mac-display-virtual" : "mac-display-mirror" }
}

/// Keep each destination's identity consistent in settings, practice and My Macs.
extension DirectMacConnection {
    var shortcutColor: Color {
        switch self { case .desktop: .blue; case .terminal: .purple; case .trackpad: .teal }
    }
}

/// All three mappings are edited together; changes remain the editor's draft
/// until Save. Practice has no connection callback or library/session reference.
struct DirectMacShortcutsSection: View {
    let open: () -> Void
    var body: some View {
        Section {
            Button(action: open) {
                HStack(spacing: 12) {
                    Image(systemName: "hand.tap").foregroundStyle(.tint).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tap & Swipe Shortcuts").foregroundStyle(Color.primary)
                        Text("Choose what opens and try each gesture").font(.subheadline).foregroundStyle(Color.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.secondary.opacity(0.5)).accessibilityHidden(true)
                }.padding(.vertical, 4)
            }.accessibilityIdentifier("mac-shortcuts-open")
        } header: { Text("My Macs Shortcuts") }
    }
}

private enum DirectMacShortcutGesture: String, CaseIterable, Identifiable {
    case tap, left, right
    var id: String { rawValue }
    var title: String { switch self { case .tap: "Open on Tap"; case .left: "Swipe Left"; case .right: "Swipe Right" } }
    var symbol: String { switch self { case .tap: "hand.tap"; case .left: "arrow.left"; case .right: "arrow.right" } }
    var identifier: String { switch self { case .tap: "mac-open-on-tap"; case .left: "mac-swipe-left"; case .right: "mac-swipe-right" } }
}

struct DirectMacShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let macName: String
    let family: DirectMacFamily
    @Binding var tap: DirectMacConnection
    @Binding var swipeLeft: DirectMacSwipeAction
    @Binding var swipeRight: DirectMacSwipeAction
    @State private var tried: DirectMacShortcutGesture?
    @State private var highlighted: DirectMacShortcutGesture?
    @State private var attempt = 0
    @ScaledMetric(relativeTo: .body) private var iconWidth = 24.0
    private var name: String { macName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "This Mac" : macName }
    private func action(_ gesture: DirectMacShortcutGesture) -> DirectMacSwipeAction {
        switch gesture { case .tap: .init(connection: tap); case .left: swipeLeft; case .right: swipeRight }
    }
    private func choose(_ value: DirectMacSwipeAction, for gesture: DirectMacShortcutGesture) {
        guard value != action(gesture) else { return }
        switch gesture { case .tap: if let connection = value.connection { tap = connection }; case .left: swipeLeft = value; case .right: swipeRight = value }
        tried = nil; highlighted = nil; attempt += 1
        CompanionVNCPlayInterfaceFeedback("selection")
    }
    private func practice(_ gesture: DirectMacShortcutGesture) {
        guard action(gesture).connection != nil else { return }
        tried = gesture; highlighted = gesture; attempt += 1
        CompanionVNCPlayInterfaceFeedback("open")
        UIAccessibility.post(notification: .announcement, argument: result)
    }
    private var result: String {
        guard let tried else { return "Tap or swipe this row to try your shortcuts." }
        return tried.title + " → " + action(tried).title
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { practice(.tap) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: family.symbol).font(.title2).foregroundStyle(.blue).accessibilityHidden(true)
                            Text(name).fontWeight(.semibold).foregroundStyle(Color.primary).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                        }.padding(.vertical, 12).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel(name + ", gesture preview")
                        .accessibilityHint("Tap to preview " + tap.title + ". Swipe actions preview your other shortcuts without connecting.")
                        .accessibilityIdentifier("mac-swipe-preview")
                        .accessibilityActions {
                            if swipeLeft.connection != nil { Button("Preview Swipe Left") { practice(.left) } }
                            if swipeRight.connection != nil { Button("Preview Swipe Right") { practice(.right) } }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if let connection = swipeLeft.connection {
                                Button(connection.title, systemImage: connection.symbol) { practice(.left) }
                                    .tint(connection.shortcutColor).accessibilityIdentifier("mac-preview-left")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if let connection = swipeRight.connection {
                                Button(connection.title, systemImage: connection.symbol) { practice(.right) }
                                    .tint(connection.shortcutColor).accessibilityIdentifier("mac-preview-right")
                            }
                        }
                        // A changed assignment closes any revealed old action.
                        .id("\(tap.rawValue)-\(swipeLeft.rawValue)-\(swipeRight.rawValue)")
                } header: { Text("Try It Here") } footer: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: tried?.symbol ?? "hand.draw").accessibilityHidden(true)
                            Text(result).accessibilityIdentifier("mac-preview-status")
                        }.foregroundStyle(tried.flatMap { action($0).connection?.shortcutColor } ?? .secondary)
                        Text("Preview only. No connection will open. Swipe fully, or swipe partway and tap.")
                    }
                }
                Section {
                    ForEach(DirectMacShortcutGesture.allCases) { gesture in
                        shortcut(gesture)
                            .listRowBackground(highlighted == gesture ? (action(gesture).connection?.shortcutColor ?? .secondary).opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
                    }
                } header: { Text("Open This Mac With") } footer: {
                    Text("Changes are saved when you tap Save in Edit Mac.")
                }
            }.navigationTitle("My Macs Shortcuts").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("mac-shortcut-done")
                } }
                .task(id: attempt) {
                    guard highlighted != nil else { return }
                    do { try await Task.sleep(for: .seconds(1.2)) } catch { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { highlighted = nil }
                }
        }
    }
    private func shortcut(_ gesture: DirectMacShortcutGesture) -> some View {
        Menu {
            ForEach(DirectMacSwipeAction.allCases.filter { gesture != .tap || $0 != .disabled }) { value in
                Button { choose(value, for: gesture) } label: {
                    Label(value.title, systemImage: action(gesture) == value ? "checkmark" : value.symbol)
                }.accessibilityIdentifier("mac-shortcut-option-" + value.rawValue)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: gesture.symbol).frame(width: iconWidth).foregroundStyle(Color.secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(gesture.title).foregroundStyle(Color.primary)
                    Label(action(gesture).title, systemImage: action(gesture).symbol)
                        .font(.subheadline).foregroundStyle(action(gesture).connection?.shortcutColor ?? .secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.up.chevron.down").font(.footnote).foregroundStyle(Color.secondary.opacity(0.5)).accessibilityHidden(true)
            }.padding(.vertical, 4)
        }.accessibilityLabel(gesture.title).accessibilityValue(action(gesture).title).accessibilityIdentifier(gesture.identifier)
    }
}

#endif

/// Port fields reserve only the space needed for five digits, leaving labels free to wrap.
struct DirectServicePortField: View {
    let title: String
    let defaultPort: String
    @Binding var value: String
    let identifier: String
    @ScaledMetric(relativeTo: .body) private var fieldWidth = 80.0
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            TextField(defaultPort, text: $value)
                .multilineTextAlignment(.trailing).frame(width: fieldWidth)
                .accessibilityLabel(title + " Port").accessibilityIdentifier(identifier)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
        }
    }
}

/// An intrinsic-height stack avoids a Form disclosure distributing spare height between rows.
struct DirectMacDetailsContent: View {
    let name: String?
    let model: String?
    let scanning: Bool
    let unavailable: Bool
    let refresh: () -> Void
    @ScaledMetric(relativeTo: .body) private var iconWidth = 26.0
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let name {
                HStack(alignment: .firstTextBaseline) {
                    Text("Detected Name")
                    Spacer(minLength: 12)
                    Text(name).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                }
                Divider()
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Mac Type")
                Spacer(minLength: 12)
                Image(systemName: DirectMacFamily.detect(model).symbol).frame(width: iconWidth).foregroundStyle(.tint).accessibilityHidden(true)
                Text(model == nil ? "Not detected" : DirectMacFamily.detect(model).title)
                    .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Button("Refresh Details", systemImage: "arrow.clockwise", action: refresh)
                .disabled(scanning).accessibilityIdentifier("mac-refresh-details")
            if scanning { ProgressView("Looking for Mac details…") }
            if unavailable { Text("Allow Local Network access in Settings to refresh.").font(.footnote).foregroundStyle(.secondary) }
        }.padding(.vertical, 8).fixedSize(horizontal: false, vertical: true)
    }
}

enum DirectUnlockMethod: Equatable, Sendable {
    case faceID, touchID, passcode, unavailable
    static func current(context: LAContext = LAContext()) -> Self {
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) ? .passcode : .unavailable
        }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .passcode
        }
    }
    static func available() async -> Self {
        // Capability discovery is presentation work, not authentication
        // preflight. Keep LocalAuthentication's synchronous IPC off the UI actor.
        await Task.detached(priority: .userInitiated) { current() }.value
    }
    var symbol: String { switch self { case .faceID: "faceid"; case .touchID: "touchid"; case .passcode, .unavailable: "lock.fill" } }
    var buttonTitle: String { switch self { case .faceID: "Unlock with Face ID"; case .touchID: "Unlock with Touch ID"; case .passcode, .unavailable: "Unlock" } }
    var returningDescription: String {
        switch self {
        case .faceID: "Use Face ID or your device passcode when you return."
        case .touchID: "Use Touch ID or your device passcode when you return."
        case .passcode: "Enter your device passcode when you return."
        case .unavailable: "Set up a device passcode to use app unlock."
        }
    }
}

struct DirectAppUnlockSection: View {
    @State private var lock: DirectAppLockV1
    @State private var method = DirectUnlockMethod.passcode
    @Environment(\.scenePhase) private var scenePhase
    init(lock: DirectAppLockV1 = .shared) { _lock = State(initialValue: lock) }
    var body: some View {
        Section {
            Toggle("Require Unlock", isOn: Binding(get: { lock.enabled }, set: { lock.setEnabled($0) }))
                .accessibilityIdentifier("app-lock-toggle")
            #if os(iOS)
            if lock.enabled {
                Picker("Lock After", selection: Binding(get: { lock.graceSeconds }, set: { lock.setGraceSeconds($0) })) {
                    Text("Immediately").tag(0)
                    Text("30 seconds").tag(30)
                }.accessibilityIdentifier("app-lock-delay")
            }
            #endif
            if lock.message.contains("before enabling") { Text(lock.message).font(.footnote).foregroundStyle(.secondary) }
        } header: { Text("App Unlock") } footer: {
            #if os(iOS)
            Text(lock.graceSeconds == 0 ? method.returningDescription : "Short returns can reuse your recent unlock. Content stays covered while away; protected-data loss requires a new unlock.")
            #else
            Text("Unlock again after screen sleep or locking your Mac.")
            #endif
        }.task(id: scenePhase) {
            let refreshed = await DirectUnlockMethod.available()
            guard !Task.isCancelled else { return }
            method = refreshed
        }
    }
}

/// Shared informational layout. Bullets are content, never disguised buttons.
struct DirectInformationGroup: View {
    let title: String
    let symbol: String
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.headline)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").accessibilityHidden(true)
                    Text(item).fixedSize(horizontal: false, vertical: true)
                }.font(.subheadline).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
    }
}
#endif

#if os(iOS)
struct DirectGestureGuide: View {
    var body: some View {
        Form {
            Section("Screen Sharing") {
                DirectGuidanceRow(title: "Move the pointer", detail: "Pointer: tap where you want to click. Trackpad: slide to move.", symbol: "cursorarrow")
                DirectGuidanceRow(title: "Click and drag", detail: "Tap to click. Hold and move to drag. Two-finger tap to right-click.", symbol: "hand.tap")
                DirectGuidanceRow(title: "Scroll", detail: "In Trackpad, scroll with two fingers.", symbol: "arrow.up.arrow.down")
                DirectGuidanceRow(title: "Zoom", detail: "Pinch the desktop image. Two-finger double-tap to zoom in or fit.", symbol: "plus.magnifyingglass")
                DirectGuidanceRow(title: "Pan the zoomed view", detail: "Use two fingers in Pointer or three in Trackpad.", symbol: "hand.draw")
            }
            Section("Trackpad & Keyboard Only") {
                DirectGuidanceRow(title: "Move, click and drag", detail: "Slide to move. Tap to click. Hold and move to drag.", symbol: "cursorarrow.motionlines")
                DirectGuidanceRow(title: "Two-finger gestures", detail: "Tap to right-click. Slide to scroll.", symbol: "hand.draw")
                DirectGuidanceRow(title: "Zoom Mac apps", detail: "On supported connections, pinch at the cursor.", symbol: "plus.magnifyingglass")
            }
            Section("Session Controls") {
                DirectGuidanceRow(title: "Open controls", detail: "Tap More. Or hold, slide to an action and release. Slide away to cancel.", symbol: "ellipsis.circle")
                DirectGuidanceRow(title: "Customize", detail: "Arrange quick actions in Customize. Change input in App Settings → Controls.", symbol: "slider.horizontal.3")
            }
        }.navigationTitle("Gesture Guide").navigationBarTitleDisplayMode(.inline)
    }
}
#endif
