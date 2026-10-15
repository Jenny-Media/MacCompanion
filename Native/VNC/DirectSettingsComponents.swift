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

struct DirectConnectionModePicker: View {
    @Binding var selection: DirectMacConnection
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Open on Tap")
            Menu {
                Picker("Open on Tap", selection: $selection) {
                    ForEach(DirectMacConnection.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(selection.title).multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold)).accessibilityHidden(true)
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }.accessibilityLabel("Open on Tap").accessibilityValue(selection.title)
                .accessibilityIdentifier("mac-open-on-tap")
        }
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

enum DirectUnlockMethod {
    case faceID, touchID, passcode
    static func current() -> Self {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return .passcode }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .passcode
        }
    }
    var symbol: String { switch self { case .faceID: "faceid"; case .touchID: "touchid"; case .passcode: "lock.fill" } }
    var returningDescription: String {
        switch self {
        case .faceID: "Use Face ID or your device passcode when you return."
        case .touchID: "Use Touch ID or your device passcode when you return."
        case .passcode: "Enter your device passcode when you return."
        }
    }
}

struct DirectAppUnlockSection: View {
    @State private var lock: DirectAppLockV1
    @State private var method = DirectUnlockMethod.current()
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
        }.onAppear { method = .current() }
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
