import Foundation

/// Presentation only. Local details never include raw errors, secrets or input.
struct DirectRecoveryNotice: Equatable, Sendable {
    enum Reason: String, Sendable {
        case terminalConnection, keyRejected, loginRejected, unsupportedConnection
        case addressNotFound, macUnreachable, desktopUnavailable, desktopDisconnected, terminalEnded, inputPaused
        case serverChanged, connectionCancelled, savedDataUnavailable, saveFailed, removeFailed
        case setupIncomplete, setupUncertain, setupLoginUnverified, setupPreferenceUnverified, setupVerified
        case importUnsupported, importInvalid, importTooLarge, importUnlock, importWorkLimit
        case exportCancelled, exportFailed, controlsUnavailable, cloudUnavailable, cloudRemoval
        case storeUnavailable, purchasePending, purchaseUnconfirmed, restoreFailed, noPurchase, trialEnded
    }
    enum Severity: Sendable { case information, warning, critical, success }
    struct Detail: Equatable, Sendable { let name: String; let value: String }
    let reason: Reason
    let title: String
    let message: String
    var severity: Severity = .warning
    var details: [Detail] = []
    static func macSaveFailed(loginRequested: Bool) -> Self {
        .init(reason: .saveFailed, title: "Mac wasn’t saved",
            message: "Your connection is open, but this Mac couldn’t be added to My Macs."
                + (loginRequested ? " Your login wasn’t saved." : "")
                + " You can keep using this session.")
    }
    static func make(_ reason: Reason, message: String? = nil, details: [Detail] = []) -> Self {
        let copy: (String, String, Severity)
        switch reason {
        case .terminalConnection: copy = ("Couldn’t connect to Terminal", "The connection ended before a Terminal session could open.", .warning)
        case .keyRejected: copy = ("SSH key wasn’t accepted", "The Mac didn’t accept this key for the account. Its public key may need to be added, or the account’s Remote Login access may need checking.", .warning)
        case .loginRejected: copy = ("Mac login wasn’t accepted", "Check the account and password, and that this account is allowed to use the sharing service.", .warning)
        case .unsupportedConnection: copy = ("This connection isn’t supported", "The server didn’t accept the authentication method used by this app. Check the Mac setup guide.", .warning)
        case .addressNotFound: copy = ("Address couldn’t be found", "Check the saved hostname or use a reachable local or private VPN address.", .warning)
        case .macUnreachable: copy = ("Couldn’t reach this Mac", "The sharing service didn’t respond. Check the Mac’s network route, sharing settings and service port.", .warning)
        case .desktopUnavailable: copy = ("Couldn’t open the desktop", "Screen Sharing ended before the desktop was ready. Your login and view settings are kept.", .warning)
        case .desktopDisconnected: copy = ("Screen Sharing disconnected", "Reconnect to continue. Your display and zoom will be restored when the Mac’s display layout is compatible.", .warning)
        case .terminalEnded: copy = ("Terminal session ended", "Open a new shell to continue. The previous shell won’t be restored and input won’t be replayed.", .information)
        case .inputPaused: copy = ("Input paused", "The connection couldn’t accept more input. Reconnect before continuing; input won’t be replayed.", .warning)
        case .serverChanged: copy = ("This Mac’s identity changed", "Login was stopped because the SSH server key differs from the one you trusted. Independently verify the Mac before changing saved server trust.", .critical)
        case .connectionCancelled: copy = ("Connection cancelled", "The server key wasn’t trusted. No login was sent.", .information)
        case .savedDataUnavailable: copy = ("Saved data unavailable", "The saved data couldn’t be read. Existing data has been kept. Retry when device storage is available; unreadable data won’t be replaced.", .warning)
        case .saveFailed: copy = ("Couldn’t save this change", "Your draft is kept. Check device storage, then retry.", .warning)
        case .removeFailed: copy = ("Removal didn’t finish", "Some saved entries may already have been removed. Review what remains, then retry.", .warning)
        case .setupIncomplete: copy = ("Key setup didn’t finish", "No installation command was sent. Correct the login or connection before trying again.", .warning)
        case .setupUncertain: copy = ("Key setup wasn’t verified", "The public key may already have been added. Your preferred login hasn’t changed. Test key login before repeating setup.", .warning)
        case .setupLoginUnverified: copy = ("Key was added; login wasn’t verified", "The Mac confirmed the public key was present, but key login hasn’t been verified. Your preferred login hasn’t changed.", .warning)
        case .setupPreferenceUnverified: copy = ("Key login worked; preference wasn’t saved", "The key signed in, but the app couldn’t save it as preferred. Test key login again when device storage is available.", .warning)
        case .setupVerified:
            #if os(macOS)
            copy = ("Public key installed", "A fresh key-only login worked and the preferred Terminal key was saved. Your private key stays on this Mac.", .success)
            #else
            copy = ("Public key installed", "A fresh key-only login worked and the preferred Terminal key was saved. Your private key stays on this iPhone.", .success)
            #endif
        case .importUnsupported: copy = ("This key format isn’t supported", "Use an Ed25519 private key in OpenSSH format. RSA, ECDSA and hardware-backed keys aren’t currently supported.", .warning)
        case .importInvalid: copy = ("Key couldn’t be imported", "The file isn’t a valid supported OpenSSH private key. Choose another file; no key was added.", .warning)
        case .importTooLarge: copy = ("Key file is too large", "Choose an Ed25519 OpenSSH private key no larger than 32 KiB.", .warning)
        case .importUnlock: copy = ("Key couldn’t be unlocked", "The passphrase may be incorrect, or the encrypted file may be damaged. Re-enter the passphrase or choose another file.", .warning)
        case .importWorkLimit: copy = ("Key encryption settings aren’t supported", "Re-export this key with supported OpenSSH encryption settings, then import again.", .warning)
        case .exportCancelled:
            #if os(macOS)
            copy = ("Export cancelled", "No backup was exported. The original key is still available on this Mac.", .information)
            #else
            copy = ("Export cancelled", "No backup was exported. The original key is still available on this iPhone.", .information)
            #endif
        case .exportFailed: copy = ("Backup wasn’t exported", "The backup couldn’t be prepared or saved. Your original key is kept; try exporting again.", .warning)
        case .controlsUnavailable: copy = ("Saved controls unavailable", "The app couldn’t read your custom controls. Existing data is kept; standard controls remain available where safe.", .warning)
        case .cloudUnavailable: copy = ("iCloud Sync unavailable", "The app couldn’t access sync data. Local Macs and logins are kept. Check iCloud Keychain in Settings, then retry.", .warning)
        case .cloudRemoval: copy = ("Cloud removal didn’t finish", "Sync is off and local data is kept. Some cloud copies may remain; retry removal when Keychain is available.", .warning)
        case .storeUnavailable: copy = ("App Store unavailable", "Purchases couldn’t be loaded. Try again; free features remain available.", .warning)
        case .purchasePending: copy = ("Purchase awaiting approval", "Apple hasn’t completed this purchase yet. Pro will unlock when a verified purchase is available. You don’t need to buy again.", .information)
        case .purchaseUnconfirmed: copy = ("Purchase couldn’t be confirmed", "Check your Apple purchase history before buying again, or restore purchases. Saved data and previously verified access are kept.", .warning)
        case .restoreFailed: copy = ("Couldn’t restore Pro", "Your current access and saved data are kept. Check your Apple Account and internet access, then restore again.", .warning)
        case .noPurchase: copy = ("No Pro purchase found", "No verified Pro purchase was found for this Apple Account. Check the account used for the purchase.", .information)
        case .trialEnded: copy = ("Your Pro trial has ended", "Basic features remain free. Your saved Macs, keys and settings are kept.", .information)
        }
        return .init(reason: reason, title: copy.0, message: message ?? copy.1, severity: copy.2, details: details)
    }
}

enum TerminalSetupPhase: String, Sendable {
    case notSent, sent, acknowledged, verified
    var failure: DirectRecoveryNotice.Reason {
        switch self {
        case .notSent: .setupIncomplete
        case .sent: .setupUncertain
        case .acknowledged: .setupLoginUnverified
        case .verified: .setupPreferenceUnverified
        }
    }
    var mayBeInstalled: Bool { self != .notSent }
}

#if (os(iOS) || os(macOS) || os(visionOS)) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
#if os(iOS) || os(visionOS)
import UIKit
#else
import AppKit
#endif
import LocalAuthentication
import StoreKit

struct DirectRecoveryAction {
    let title: String
    var symbol: String? = nil
    var pro = false
    let perform: @MainActor () -> Void
}

struct DirectGuidanceRow: View {
    let title: String
    let detail: String
    let symbol: String
    @ScaledMetric(relativeTo: .title3) private var symbolWidth = 26
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.tint).frame(width: symbolWidth).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 3)
    }
}

struct DirectMacSetupGuide: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("1. Enable access on your Mac") {
                    #if os(iOS) || os(visionOS)
                    DirectGuidanceRow(title: "Remote Login · All modes", detail: "Turn on Remote Login and allow your Mac account.", symbol: "terminal")
                    DirectGuidanceRow(title: "Screen Sharing & Trackpad", detail: "Also turn on Screen Sharing and allow your Mac account.", symbol: "macwindow")
                    #else
                    DirectGuidanceRow(title: "Screen Sharing", detail: "Turn on Screen Sharing and allow your Mac account.", symbol: "macwindow")
                    DirectGuidanceRow(title: "Terminal", detail: "Turn on Remote Login and allow your Mac account.", symbol: "terminal")
                    #endif
                    Label("System Settings → General → Sharing", systemImage: "gearshape").font(.footnote).foregroundStyle(.secondary)
                }
                Section("2. Add its address") {
                    DirectGuidanceRow(title: "Mac address", detail: "Use the hostname or IP address shown in Sharing settings.", symbol: "network")
                    DirectGuidanceRow(title: "Using a private VPN?", detail: "Connect both devices to the same private VPN.", symbol: "lock.shield")
                }
                Section("3. Sign in") {
                    DirectGuidanceRow(title: "Your Mac account", detail: "Enter your Mac username and password.", symbol: "person.badge.key")
                }
                Section {} footer: { Text("Uses built-in Mac services. No helper installation needed.") }
            }.directGroupedForm().navigationTitle("Set Up Your Mac").directInlineNavigationTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

extension View {
    @ViewBuilder func directGroupedForm() -> some View {
        #if os(macOS)
        formStyle(.grouped)
        #else
        self
        #endif
    }
}

/// Metadata sync and local credentials have separate, explicit explanations.
struct DirectSyncSecurityForm: View {
    @State private var cloud: DirectCloudSyncV1
    @State private var lock = DirectAppLockV1.shared
    #if !os(iOS)
    @State private var enableCloud = false
    #endif
    @State private var sheet: DirectCloudSheet?
    #if os(iOS)
    @State private var recovered: DirectControlsRecoveryLibrary
    init(cloud: DirectCloudSyncV1 = .shared, recovered: DirectControlsRecoveryLibrary = .init()) {
        _cloud = State(initialValue: cloud); _recovered = State(initialValue: recovered)
    }
    #else
    init(cloud: DirectCloudSyncV1 = .shared) { _cloud = State(initialValue: cloud) }
    #endif
    var body: some View {
        Form {
            DirectCloudSettingsSection(cloud: cloud, enable: {
                #if os(iOS)
                sheet = .enableSync
                #else
                enableCloud = true
                #endif
            }, present: { sheet = $0 })
            #if os(iOS)
            if !recovered.entries.isEmpty || recovered.error != nil {
                Section { DirectControlsRecoveryNotice(library: recovered) }
            }
            #endif
            DirectAppUnlockSection()
        }.directGroupedForm()
        .sheet(item: $sheet) { item in
            #if os(iOS)
            if item == .enableSync {
                DirectCloudEnableSheet(cloud: cloud).directAppearance()
            } else {
                DirectCloudInformationSheet(kind: item, cloud: cloud).directAppearance()
            }
            #else
            DirectCloudInformationSheet(kind: item, cloud: cloud).directAppearance()
                #if os(macOS)
                .modifier(MacSheetPrivacyCover())
                #endif
            #endif
        }
        #if !os(iOS)
        .alert("Enable iCloud Sync?", isPresented: $enableCloud) {
            Button("Enable Sync") { if lock.canAccess { cloud.setEnabled(true) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text(DirectCloudSyncV1.disclosure) }
        #endif
        .onChange(of: lock.canAccess) { _, allowed in
            if !allowed {
                #if !os(iOS)
                enableCloud = false
                #endif
                sheet = nil
            }
        }
    }
}

private struct DirectCloudSettingsSection: View {
    let cloud: DirectCloudSyncV1
    let enable: () -> Void
    let present: (DirectCloudSheet) -> Void
    @State private var lock = DirectAppLockV1.shared
    private var syncedItems: [String] {
        #if os(iOS)
        ["Saved Macs and connection details", "My Macs tap and swipe shortcuts", "Screen Sharing preferences",
         "Keyboard layouts and built-in keys", "Saved shortcuts, text and button positions"]
        #else
        ["Saved Macs, names and models", "Addresses and service ports", "My Macs tap and swipe shortcuts",
         "Display selection and fullscreen", "Pointer speed, input mode and cursor following"]
        #endif
    }
    private var localItems: [String] {
        ["Passwords and SSH keys", "Trusted Mac identities", "Appearance and app-lock settings"]
    }
    var body: some View {
        #if os(iOS)
        DirectIOSCloudSettingsSection(cloud: cloud, enable: enable, present: present)
        #else
        Section {
            Toggle("iCloud Sync", isOn: Binding(get: { cloud.enabled }, set: {
                if $0 { enable() } else if lock.canAccess { cloud.setEnabled(false) }
            })).disabled(cloud.busy).accessibilityIdentifier("icloud-library-toggle")
            if let notice = cloud.recovery {
                DirectRecoveryCard(notice: notice, primary: .init(title: notice.reason == .cloudRemoval ? "Retry Removal" : "Retry") {
                    guard lock.canAccess else { return }
                    if notice.reason == .cloudRemoval { present(.deleteData) } else { cloud.retry() }
                })
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    #if os(iOS)
                    Text("Sync Macs, controls and saved text.")
                    if cloud.enabled {
                        if let keyboardStatus = cloud.keyboardSyncStatus { Label(keyboardStatus, systemImage: "keyboard") }
                        if let contentStatus = cloud.savedControlsSyncStatus { Label(contentStatus, systemImage: "text.quote") }
                    }
                    #else
                    Text("Sync saved Macs across your devices.")
                    #endif
                    Text(cloud.status)
                }.font(.footnote).foregroundStyle(.secondary)
            }
            DisclosureGroup("What Syncs") {
                VStack(alignment: .leading, spacing: 12) {
                    DirectInformationGroup(title: "Across devices", symbol: "icloud", items: syncedItems)
                    Divider()
                    #if os(iOS)
                    DirectInformationGroup(title: "On this device", symbol: "icloud.slash", items: localItems)
                    #else
                    DirectInformationGroup(title: "On this device", symbol: "lock.shield", items: [
                        "Passwords and SSH keys", "Trusted Mac identities", "Saved shortcuts, text and their keyboard buttons", "Appearance and app-lock settings"])
                    #endif
                }
            }
            DisclosureGroup("Manage Sync") {
                if cloud.enabled {
                    Button("Refresh iCloud", systemImage: "arrow.triangle.2.circlepath") { if lock.canAccess { cloud.retry() } }.disabled(cloud.busy)
                }
                if cloud.busy { ProgressView("Updating iCloud data…") }
                Button("Delete Mac Data from iCloud…", systemImage: "icloud.slash", role: .destructive) { present(.deleteData) }
                    .disabled(cloud.busy).accessibilityIdentifier("icloud-delete-data")
                Text("Turning sync off doesn’t delete iCloud data.").font(.footnote).foregroundStyle(.secondary)
            }
            Button { present(.credentials) } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label("Passwords and private keys stay on this device", systemImage: "lock.shield")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Spacer(minLength: 4)
                    Image(systemName: "info.circle").foregroundStyle(.tint)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("icloud-credentials-info")
                .accessibilityHint("Explains which information stays local and why")
        } header: { Text("iCloud") }
        #endif
    }
}

#if os(iOS)
private struct DirectIOSCloudSettingsSection: View {
    let cloud: DirectCloudSyncV1
    let enable: () -> Void
    let present: (DirectCloudSheet) -> Void
    @State private var lock = DirectAppLockV1.shared
    var body: some View {
        Section {
            Toggle("iCloud Sync", isOn: Binding(get: { cloud.enabled }, set: {
                if $0 { enable() } else if lock.canAccess { cloud.setEnabled(false) }
            })).disabled(cloud.busy).accessibilityIdentifier("icloud-library-toggle")
            Text(cloud.summary).font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("icloud-summary")
            NavigationLink { DirectCloudScopeForm(present: present) } label: { Text("What Syncs") }
                .accessibilityIdentifier("icloud-what-syncs")
            NavigationLink { DirectCloudManagementForm(cloud: cloud, present: present) } label: {
                HStack {
                    Text("Manage Sync")
                    if cloud.syncNeedsAttention { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange) }
                }
            }.accessibilityIdentifier("icloud-manage-sync")
            if cloud.syncNeedsAttention {
                Button(cloud.recovery?.reason == .cloudRemoval ? "Retry Removal" : "Retry Sync", systemImage: "arrow.clockwise") {
                    if cloud.recovery?.reason == .cloudRemoval { present(.deleteData) } else { cloud.retry() }
                }.disabled(cloud.busy || !lock.canAccess)
            }
        } header: { Text("iCloud") } footer: { Text("Sync Macs, controls and saved text.") }
    }
}

private struct DirectCloudScopeForm: View {
    let present: (DirectCloudSheet) -> Void
    var body: some View {
        Form {
            Section {
                DirectInformationGroup(title: "Across devices", symbol: "icloud", items: [
                    "Saved Macs and connection details", "My Macs tap and swipe shortcuts", "Screen Sharing preferences",
                    "Keyboard layouts and built-in keys", "Saved shortcuts, text and button positions"])
            }
            Section {
                DirectInformationGroup(title: "On this device", symbol: "icloud.slash", items: [
                    "Passwords and SSH keys", "Trusted Mac identities", "Appearance and app-lock settings"])
                Button("About Local Logins", systemImage: "info.circle") { present(.credentials) }
                    .accessibilityIdentifier("icloud-credentials-info")
            }
            Section {
                Text("Uses iCloud Keychain with the same Apple Account on each device.")
                Text("Enable iCloud Keychain on each device. Changes may take a moment to appear.")
            } header: { Text("How it works") }
        }.navigationTitle("What Syncs").directInlineNavigationTitle()
    }
}

private struct DirectCloudManagementForm: View {
    @State private var recovered = DirectControlsRecoveryLibrary()
    let cloud: DirectCloudSyncV1
    let present: (DirectCloudSheet) -> Void
    @State private var lock = DirectAppLockV1.shared
    var body: some View {
        Form {
            Section("Status") {
                Text(cloud.summary)
                if let notice = cloud.recovery {
                    DirectRecoveryCard(notice: notice, primary: nil)
                }
                if cloud.enabled {
                    if let value = cloud.keyboardSyncStatus { Label(value, systemImage: "keyboard") }
                    if let value = cloud.savedControlsSyncStatus { Label(value, systemImage: "text.quote") }
                    Button("Refresh iCloud", systemImage: "arrow.triangle.2.circlepath") { cloud.retry() }
                        .disabled(cloud.syncInProgress || !lock.canAccess)
                }
            }
            if !recovered.entries.isEmpty || recovered.error != nil {
                Section {
                    NavigationLink { DirectRecoveredChangesForm(library: recovered) } label: {
                        Label("Recovered Changes", systemImage: "clock.arrow.circlepath")
                    }.accessibilityIdentifier("icloud-recovered-changes")
                } footer: { Text("Another version was kept. Review or restore it whenever you’re ready.") }
            }
            Section {
                Button(role: .destructive) { present(.deleteData) } label: {
                    Label("Delete Synced Data from iCloud…", systemImage: "trash").foregroundStyle(.red)
                }.disabled(cloud.busy || !lock.canAccess).accessibilityIdentifier("icloud-delete-data")
            } header: { Text("Start over with iCloud") }
            footer: { Text("Deletes the synced copies and turns sync off here. Current data and recovered changes stay on this device.") }
        }.navigationTitle("Manage Sync").directInlineNavigationTitle()
    }
}

private struct DirectControlsRecoveryNotice: View {
    let library: DirectControlsRecoveryLibrary
    private var layout: DirectControlsRecoveredChange? {
        library.error == nil && library.entries.count == 1 && library.entries[0].layout != nil ? library.entries[0] : nil
    }
    var body: some View {
        NavigationLink {
            DirectControlsRecoveryDestination(library: library)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(layout != nil ? "Review Layout" : "Review Recovered Changes")
                    Text(library.error != nil ? "Recovery copies couldn’t be read. Retry here."
                         : layout != nil ? "A keyboard layout was kept for recovery." : "Other versions were kept during sync.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } icon: { Image(systemName: "clock.arrow.circlepath") }
        }.accessibilityIdentifier("icloud-recovery-notice")
    }
}

/// Keep the selected route stable while restoring/discarding changes the list.
private struct DirectControlsRecoveryDestination: View {
    let library: DirectControlsRecoveryLibrary
    @State private var layout: DirectControlsRecoveredChange?
    init(library: DirectControlsRecoveryLibrary) {
        self.library = library
        _layout = State(initialValue: library.error == nil && library.entries.count == 1 && library.entries[0].layout != nil
            ? library.entries[0] : nil)
    }
    var body: some View {
        if let layout { DirectRecoveredChangeDetail(entry: layout, library: library) }
        else { DirectRecoveredChangesForm(library: library) }
    }
}

struct DirectRecoveredChangesForm: View {
    let library: DirectControlsRecoveryLibrary
    @State private var confirmDiscardAll = false
    @State private var lock = DirectAppLockV1.shared
    var body: some View {
        Form {
            Section {
                if library.entries.isEmpty && library.error == nil {
                    Label("No recovered changes", systemImage: "checkmark.circle")
                } else {
                    ForEach(library.entries) { entry in
                        NavigationLink { DirectRecoveredChangeDetail(entry: entry, library: library) } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title)
                                    Text(entry.location).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: entry.symbol) }
                        }.accessibilityIdentifier("icloud-recovered-" + entry.id)
                    }
                }
            } footer: {
                if !library.entries.isEmpty { Text("These copies were kept so you can review or restore another version.") }
                else if library.error == nil { Text("Your current versions are in use.") }
            }
            if !library.entries.isEmpty {
                Section {
                    Button("Discard All Recovered Changes…", systemImage: "trash", role: .destructive) { confirmDiscardAll = true }
                        .disabled(!lock.canAccess).accessibilityIdentifier("icloud-recovered-discard-all")
                } header: { Text("Keep current versions") }
                footer: { Text("Clears these recovery copies. Your current layouts, shortcuts and saved text stay as they are.") }
            }
            if let error = library.error {
                Section {
                    Label(error, systemImage: "exclamationmark.circle")
                    Button("Reload Recovered Changes", systemImage: "arrow.clockwise") { library.reload() }.disabled(!lock.canAccess)
                }
            }
        }
        .navigationTitle("Recovered Changes").directInlineNavigationTitle()
        .alert("Discard all recovered changes?", isPresented: $confirmDiscardAll) {
            Button("Discard Recovery Copies", role: .destructive) { library.discardAll() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Only recovery copies are removed. Your current data and iCloud data are kept.") }
    }
}

private struct DirectRecoveredChangeDetail: View {
    let entry: DirectControlsRecoveredChange
    let library: DirectControlsRecoveryLibrary
    @Environment(\.dismiss) private var dismiss
    @State private var lock = DirectAppLockV1.shared
    private enum Confirmation { case layout, discard }
    @State private var confirmation: Confirmation?
    var body: some View {
        Form {
            if lock.canAccess {
                Section {
                    Label(entry.location, systemImage: entry.symbol)
                    if let layout = entry.layout {
                        ForEach(layout.rows, id: \.id) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.title)
                                Text(row.keys.map { $0.title(in: .defaults) }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(row.visibility).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else if let control = entry.control {
                        if control.action.kind == .text {
                            Text(control.action.text).textSelection(.enabled)
                        } else {
                            if control.action.kind == .shortcut {
                                ForEach(control.action.resolvedSteps) { step in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Label(step.isText ? step.kind.title : step.label, systemImage: step.kind.symbol)
                                        if step.isText { Text(step.text).font(.body.monospaced()).textSelection(.enabled) }
                                    }
                                }
                            } else { Text(control.action.detail) }
                            Text("\(control.bar.count) keyboard buttons · \(control.menus.count) menu favorites")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: { Text("Recovered version") }
                footer: { Text(entry.layout != nil
                    ? "This is a saved alternative. Your current layout is still in use."
                    : "This copy stays separate until you restore it.") }
                Section {
                    Button(entry.layout != nil ? "Use This Layout…" : "Restore as Copy", systemImage: "arrow.uturn.backward") {
                        if entry.layout != nil { confirmation = .layout }
                        else if library.restore(entry) { dismiss() }
                    }.accessibilityIdentifier("icloud-recovered-restore")
                    Button("Discard This Recovery…", systemImage: "trash", role: .destructive) { confirmation = .discard }
                        .accessibilityIdentifier("icloud-recovered-discard")
                } footer: {
                    Text(entry.layout != nil
                        ? "Your current layout will be kept here so you can undo the change. Saved items stay."
                        : "Adds a separate recovered copy, including its button positions. It won’t run a shortcut or send text.")
                }
                if let error = library.error { Section { Label(error, systemImage: "exclamationmark.circle") } }
            } else { Text("Unlock the app to view recovered changes.") }
        }
        .navigationTitle(entry.title).directInlineNavigationTitle()
        .alert(confirmation == .layout ? "Use this keyboard layout?" : "Discard this recovered version?",
            isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })) {
            if confirmation == .layout {
                Button("Use Layout") { if library.restore(entry) { dismiss() }; confirmation = nil }
            } else {
                Button("Discard Recovery Copy", role: .destructive) { if library.discard(entry) { dismiss() }; confirmation = nil }
            }
            Button("Cancel", role: .cancel) { confirmation = nil }
        } message: {
            Text(confirmation == .layout ? "Your current layout stays recoverable. Saved items are kept."
                : "Your current data and iCloud data are kept.")
        }
    }
}

#endif

enum DirectCloudSheet: String, Identifiable {
    case credentials, deleteData
    #if os(iOS)
    case enableSync
    #endif
    var id: String { rawValue }
}

#if os(iOS)
private struct DirectCloudEnableSheet: View {
    let cloud: DirectCloudSyncV1
    @State private var lock = DirectAppLockV1.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var symbolWidth = 28

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Enable iCloud Sync?").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                summary("Syncs", symbol: "icloud", detail: "Saved Macs, keyboard layouts, shortcuts and saved text.")
                    .accessibilityIdentifier("icloud-enable-synced")
                summary("Stays on this device", symbol: "icloud.slash", detail: "Passwords, SSH keys and trusted Mac identities.")
                    .accessibilityIdentifier("icloud-enable-local")
                Text("Encrypted iCloud sync").font(.footnote).foregroundStyle(.secondary)
            }.padding(24).padding(.bottom, 12).frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                Button {
                    guard lock.canAccess, !cloud.busy else { return }
                    cloud.setEnabled(true)
                    dismiss()
                } label: {
                    Text("Enable Sync").font(.headline).frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(cloud.busy || !lock.canAccess)
                .accessibilityIdentifier("icloud-enable-confirm")
                Button("Cancel", role: .cancel) { dismiss() }
                    .frame(maxWidth: .infinity, minHeight: 44).buttonStyle(.plain)
                    .accessibilityIdentifier("icloud-enable-cancel")
            }.padding(.horizontal, 24).padding(.vertical, 12).background(.bar)
        }
        .presentationSizing(.form)
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(540), .large])
        .presentationDragIndicator(.visible)
    }

    private func summary(_ title: LocalizedStringKey, symbol: String, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.secondary)
                .frame(width: symbolWidth).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }
}
#endif

struct DirectCloudInformationSheet: View {
    let kind: DirectCloudSheet
    let cloud: DirectCloudSyncV1
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDeletion = false
    @State private var lock = DirectAppLockV1.shared
    #if os(visionOS)
    @Environment(\.scenePhase) private var phase
    @State private var deletion = VisionCloudDeletion()
    #endif
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if kind == .credentials {
                        DirectInformationGroup(title: "Your logins stay local", symbol: "lock.shield", items: [
                            "Passwords, SSH keys and trusted Mac identities don’t sync.",
                            "Set up a login or SSH key on each device."])
                        #if !os(iOS)
                        DirectInformationGroup(title: "Local storage", symbol: "internaldrive", items: [
                            "Passwords and imported keys use this device’s Keychain.",
                            "Referenced keys stay in their original files."])
                        #endif
                        DirectInformationGroup(title: "How sync works", symbol: "icloud", items: [
                            "Uses iCloud Keychain with your Apple Account.",
                            "Enable iCloud Keychain on each device."])
                        Link("About iCloud Keychain security", destination: URL(string: "https://support.apple.com/en-us/102651")!)
                    } else {
                        #if os(iOS)
                        DirectInformationGroup(title: "Delete from iCloud", symbol: "trash", items: [
                            "Saved Macs, preferences, keyboard layouts, shortcuts and saved text."])
                        #else
                        DirectInformationGroup(title: "Delete from iCloud", symbol: "icloud.slash", items: [
                            "Saved Mac entries and their synced desktop preferences."])
                        #endif
                        DirectInformationGroup(title: "Keep on this device", symbol: "internaldrive", items: [
                            "Your local Macs, controls, text, logins and preferences."])
                        DirectInformationGroup(title: "Before you continue", symbol: "exclamationmark.triangle", items: [
                            "Turn off sync on your other devices first.",
                            "Sync turns off here; cloud deletion may take time.",
                            "Re-enabling sync can upload local data again."])
                    }
                }.padding(24).frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity)
            }.navigationTitle(kind == .credentials ? "Credentials & iCloud" : "Delete iCloud Data")
                .directInlineNavigationTitle()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(kind == .credentials ? "Done" : "Cancel") { dismiss() } } }
                .safeAreaInset(edge: .bottom) {
                    if kind == .deleteData {
                        VStack(spacing: 8) {
                            Button("Continue to Confirmation", role: .destructive) {
                                #if os(visionOS)
                                deletion.review(unlocked: lock.canAccess, busy: cloud.busy)
                                #else
                                confirmDeletion = true
                                #endif
                            }
                                .buttonStyle(.borderedProminent).disabled(cloud.busy || !lock.canAccess)
                                .accessibilityIdentifier("icloud-review-continue")
                        }.padding(16).frame(maxWidth: .infinity).background(.bar)
                    }
                }
        }
        #if os(macOS)
        .frame(width: 540, height: 580)
        #endif
        .background(.background)
        #if os(visionOS)
        .background {
            if let token = deletion.confirmation {
                VisionCloudDeletionAlert(token: token, deletion: deletion, cloud: cloud, done: { dismiss() })
                    .id(token)
            }
        }
        .onAppear { deletion.scenePhase = phase }
        .onChange(of: phase) { _, value in deletion.scenePhase = value }
        .onDisappear { deletion.invalidate() }
        .visionSensitiveState { deletion.invalidate(); dismiss() }
        #else
        .alert("Delete Synced Data from iCloud?", isPresented: $confirmDeletion) {
            Button("Delete iCloud Data", role: .destructive) {
                guard lock.canAccess, !cloud.busy else { return }
                cloud.removeCloudCopies(); dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Synced data is deleted; sync turns off here. Local data is kept. Other devices can upload data again.") }
        #endif
        .onChange(of: lock.canAccess) { _, allowed in if !allowed { confirmDeletion = false; dismiss() } }
    }
}

struct DirectConnectionDetailsRows: View {
    let mac: DirectMacRecordV1
    let desktop: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(mac.addresses.enumerated()), id: \.offset) { index, address in
                LabeledContent(index == 0 ? "Address" : "Fallback \(index)", value: address)
                    .textSelection(.enabled)
            }
            #if os(macOS)
            if desktop {
                LabeledContent("Screen Sharing", value: String(mac.port))
                Label("Built-in macOS Screen Sharing", systemImage: "display")
                    .font(.caption).foregroundStyle(.secondary)
            } else { sshDetails }
            #else
            sshDetails
            if desktop { LabeledContent("Screen Sharing", value: String(mac.port)) }
            #endif
        }
    }
    private var sshDetails: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Remote Login · SSH", value: String(mac.sshPort))
            Label("Server identity is verified before login.", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct DirectSettingsRow: View {
    let title: String
    let symbol: String
    var body: some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true)
        }.contentShape(Rectangle())
    }
}

struct DirectStoreRecoveryBanner: View {
    let retry: @MainActor () -> Void
    let busy: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("App Store unavailable", systemImage: "exclamationmark.circle").font(.headline)
                Spacer()
                Button("Retry", action: retry).disabled(busy)
            }
            Text("Purchases couldn’t be loaded. Free features remain available.").font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 4).accessibilityIdentifier("recovery-storeUnavailable")
    }
}

/// Preserve every instruction, with one visible row per sentence.
struct DirectNoticeMessage: View {
    let message: String
    var body: some View {
        let parts = message.components(separatedBy: ". ")
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if parts.count > 1 { Image(systemName: "circle.fill").font(.system(size: 4)).accessibilityHidden(true) }
                    Text(part + (index < parts.count - 1 ? "." : "")).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct DirectRecoveryCard: View {
    let notice: DirectRecoveryNotice
    var primary: DirectRecoveryAction? = nil
    var secondary: DirectRecoveryAction? = nil
    private var color: Color {
        switch notice.severity { case .information: .blue; case .warning: .orange; case .critical: .red; case .success: .green }
    }
    private var symbol: String {
        switch notice.severity { case .information: "info.circle"; case .warning: "exclamationmark.circle"; case .critical: "exclamationmark.shield"; case .success: "checkmark.circle" }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(notice.title, systemImage: symbol).font(.headline).foregroundStyle(.primary)
            DirectNoticeMessage(message: notice.message).font(.subheadline)
            if let primary { action(primary, prominent: true) }
            if let secondary { action(secondary, prominent: false) }
            if !notice.details.isEmpty {
                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(notice.details.enumerated()), id: \.offset) { _, detail in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(detail.name).font(.caption).foregroundStyle(.secondary)
                                Text(detail.value).font(.footnote).textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.padding(.top, 8)
                }.font(.footnote).frame(minHeight: 44).tint(.secondary)
            }
        }.padding(17).frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
            .background(recoveryBackground, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(color.opacity(0.17)))
            .accessibilityIdentifier("recovery-" + notice.reason.rawValue)
            .onAppear { announce() }
            .onChange(of: notice.reason) { _, _ in announce() }
    }
    private var recoveryBackground: Color {
        #if os(iOS) || os(visionOS)
        Color(uiColor: .secondarySystemBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
    private func announce() {
        #if os(iOS) || os(visionOS)
        UIAccessibility.post(notification: .announcement, argument: notice.title)
        #endif
    }
    @ViewBuilder private func action(_ value: DirectRecoveryAction, prominent: Bool) -> some View {
        let button = Button(action: value.perform) {
            HStack {
                if let symbol = value.symbol { Image(systemName: symbol) }
                Text(value.title).multilineTextAlignment(.center)
                if value.pro { Spacer(minLength: 4); DirectProBadge() }
            }.frame(maxWidth: .infinity, minHeight: 32)
        }.controlSize(.large)
        if prominent { button.buttonStyle(.borderedProminent) }
        else { button.buttonStyle(.bordered) }
    }
}
struct DirectProBadge: View {
    var body: some View { Text("PRO").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 3).background(.tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 5)).accessibilityLabel("Requires Pro or an active trial") }
}
enum DirectCancellation {
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let value = error as? StoreKitError, case .userCancelled = value { return true }
        let value = error as NSError
        if value.domain == NSCocoaErrorDomain && value.code == NSUserCancelledError { return true }
        if value.domain == LAError.errorDomain {
            return [LAError.userCancel.rawValue, LAError.appCancel.rawValue, LAError.systemCancel.rawValue].contains(value.code)
        }
        return false
    }
}
struct TerminalServerTrustView: View {
    let macName: String
    let fingerprint: String
    let answer: @MainActor (Bool) -> Void
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    #if os(iOS)
                    DirectConnectionIdentity(name: macName, service: "Verify Mac", symbol: "lock.shield")
                    #else
                    Image(systemName: "lock.shield").font(.largeTitle).foregroundStyle(.blue)
                    #endif
                    Text("Is this your Mac?").font(.title.bold())
                    #if os(iOS)
                    DirectGuidanceRow(title: "1. Check on your Mac", detail: "Compare this fingerprint with the matching SSH server key on \(macName).", symbol: "desktopcomputer")
                    #else
                    Text("You’re connecting to \(macName). Independently check this SSH server fingerprint on your Mac before trusting it.")
                    #endif
                    Text(fingerprint).font(.footnote.monospaced()).textSelection(.enabled).padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                    #if os(iOS)
                    Text("ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub")
                        .font(.footnote.monospaced()).textSelection(.enabled)
                    DirectGuidanceRow(title: "2. Match the key type", detail: "For another SSH key type, check its matching host-key file instead.", symbol: "key")
                    #else
                    Text("On the Mac, compare the matching server key with ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub. If the server uses another key type, compare that matching host key instead.")
                        .font(.footnote).foregroundStyle(.secondary)
                    #endif
                    #if !os(iOS)
                    Button("Trust & Connect") { answer(true) }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity, minHeight: 44)
                    #endif
                    Text("No login is sent until you approve.").font(.footnote).foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: 520).frame(maxWidth: .infinity)
            }
            #if os(iOS)
            .background(Color(uiColor: DirectConnectionStyle.panel))
            .toolbarBackground(Color(uiColor: DirectConnectionStyle.panel), for: .navigationBar)
            #endif
            .navigationTitle("Verify This Mac")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(iOS)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DirectConnectionFooter {
                    Button { answer(true) } label: { Text("Trust & Connect").font(.headline).frame(maxWidth: .infinity, minHeight: 32) }
                        .buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("server-trust-approve")
                    Button("Cancel") { answer(false) }.font(.headline).foregroundStyle(.blue).frame(maxWidth: .infinity, minHeight: 48).buttonStyle(.plain)
                        .accessibilityIdentifier("server-trust-cancel")
                }
            }
            #else
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { answer(false) } } }
            #endif
        }.interactiveDismissDisabled()
        #if os(iOS)
        .presentationSizing(.form)
        #endif
    }
}
#if os(iOS)
/// UIKit Desktop uses the same copy and actions as the SwiftUI recovery screens.
@objc(DirectRecoveryBridgeV1) @MainActor final class DirectRecoveryBridgeV1: NSObject {
    @objc(canOfferInputOnlyRecoveryAtStage:) static func canOfferInputOnlyRecovery(stage: Int) -> Bool {
        [9, 103, 116, 117, 118].contains(stage)
    }
    static func desktopReason(stage: Int, hadFrame: Bool) -> DirectRecoveryNotice.Reason {
        switch stage {
        case 10: return .addressNotFound
        case 11, 110: return .macUnreachable
        case 2: return .unsupportedConnection
        case 7, 8, 111: return .loginRejected
        case 112: return .serverChanged
        case 113: return .connectionCancelled
        case 114, 116, 117, 118: return .desktopUnavailable
        case 115: return .savedDataUnavailable
        case 101: return .inputPaused
        default: return hadFrame ? .desktopDisconnected : .desktopUnavailable
        }
    }
    private static func desktopNotice(stage: Int, hadFrame: Bool, port: Int) -> DirectRecoveryNotice {
        let reason = desktopReason(stage: stage, hadFrame: hadFrame)
        let message: String?
        switch stage {
        case 110: message = "A verified SSH connection couldn’t be established. Enable Remote Login in System Settings → General → Sharing, and check the saved SSH port and network route."
        case 111: message = "The Mac didn’t accept this account and password for Remote Login. Check the login and allow this account in Remote Login settings."
        case 114: message = "SSH connected, but Screen Sharing wasn’t available through it. Enable Screen Sharing, check its saved port, and allow SSH forwarding on the Mac."
        case 115: message = "The SSH server trust couldn’t be read or saved. Unlock this iPhone and retry. The saved Mac is kept."
        case 116: message = "The Mac is still using a virtual display. Mirror Mac Screen couldn’t be opened. Reconnect to try again."
        case 117: message = "The Mac didn’t finish opening the virtual display. Reconnect to try again."
        case 118: message = "The Mac didn’t provide display information for this mode. Reconnect to try again."
        case 103: message = "The desktop image couldn’t be decoded. Reconnect to request a fresh image. Your login and view settings are kept."
        case 9: message = "This desktop exceeds the supported size limit. Reduce the Mac’s shared desktop size before retrying."
        default: message = nil
        }
        return DirectRecoveryNotice.make(reason, message: message,
            details: [.init(name: "Service", value: (stage == 10 || stage == 11 || (110...115).contains(stage)) ? "Remote Login (SSH)" : "Screen Sharing over SSH"), .init(name: "Port", value: String(port)), .init(name: "Stage", value: String(stage))])
    }
    @objc static func desktopDetails(stage: Int, hadFrame: Bool, port: Int) -> String {
        let notice = desktopNotice(stage: stage, hadFrame: hadFrame, port: port)
        return ([notice.title, notice.message] + notice.details.map { "\($0.name): \($0.value)" }).joined(separator: "\n")
    }
    @objc static func desktop(stage: Int, hadFrame: Bool, port: Int, retry: @escaping @MainActor @Sendable () -> Void, edit: @escaping @MainActor @Sendable () -> Void) -> UIViewController {
        desktop(stage: stage, hadFrame: hadFrame, port: port, textInterrupted: false, retry: retry, edit: edit)
    }
    @objc static func desktop(stage: Int, hadFrame: Bool, port: Int, textInterrupted: Bool, retry: @escaping @MainActor @Sendable () -> Void, edit: @escaping @MainActor @Sendable () -> Void) -> UIViewController {
        desktop(stage: stage, hadFrame: hadFrame, port: port, textInterrupted: textInterrupted, retry: retry, edit: edit, inputOnly: nil)
    }
    @objc static func desktop(stage: Int, hadFrame: Bool, port: Int, textInterrupted: Bool, retry: @escaping @MainActor @Sendable () -> Void, edit: @escaping @MainActor @Sendable () -> Void, inputOnly: (@MainActor @Sendable () -> Void)?) -> UIViewController {
        let inputOnly = canOfferInputOnlyRecovery(stage: stage) ? inputOnly : nil
        let modeFailure = (116...118).contains(stage)
        let base = desktopNotice(stage: stage, hadFrame: hadFrame, port: port)
        let original = modeFailure ? DirectRecoveryNotice(reason: base.reason, title: "Couldn’t switch display mode", message: base.message, details: base.details) : base
        let notice = textInterrupted ? DirectRecoveryNotice.make(original.reason,
            message: original.message + " Text may have been partially sent. Check your Mac before sending it again; input won’t be replayed.", details: original.details) : original
        let reason = notice.reason
        if !hadFrame {
            let controller = UIHostingController(rootView: VStack(alignment: .leading, spacing: 12) {
                DirectConnectionNotice(notice: notice)
                if let inputOnly {
                    Button("Use Trackpad & Keyboard", action: inputOnly)
                        .buttonStyle(.bordered).frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("recovery-inputOnly")
                }
            }.directAppearance())
            controller.sizingOptions = .intrinsicContentSize; controller.view.backgroundColor = .clear
            return controller
        }
        let controller = UIHostingController(rootView: DirectRecoveryCard(notice: notice,
            primary: .init(title: reason == .loginRejected ? "Edit Login" : hadFrame ? "Reconnect" : "Try Again", perform: reason == .loginRejected ? edit : retry),
            secondary: inputOnly.map { .init(title: "Use Trackpad & Keyboard", perform: $0) }
                ?? (reason == .loginRejected || modeFailure ? nil : .init(title: "Edit Login", perform: edit))).directAppearance())
        controller.sizingOptions = .intrinsicContentSize
        controller.view.backgroundColor = .clear
        return controller
    }
    @objc static func interruptedText(done: @escaping @MainActor @Sendable () -> Void) -> UIViewController {
        let notice = DirectRecoveryNotice(reason: .inputPaused, title: "Check the sent text",
            message: "Sending text was interrupted. It may have been partially sent. Check your Mac before sending it again; input won’t be replayed.")
        let controller = UIHostingController(rootView: DirectRecoveryCard(notice: notice,
            primary: .init(title: "Continue", perform: done), secondary: nil).directAppearance())
        controller.sizingOptions = .intrinsicContentSize; controller.view.backgroundColor = .clear
        return controller
    }
    @objc static func macSaveFailed(loginRequested: Bool, done: @escaping @MainActor @Sendable () -> Void) -> UIViewController {
        let controller = UIHostingController(rootView: DirectRecoveryCard(notice: .macSaveFailed(loginRequested: loginRequested),
            primary: .init(title: "Continue", perform: done), secondary: nil).directAppearance())
        controller.sizingOptions = .intrinsicContentSize; controller.view.backgroundColor = .clear
        return controller
    }
    @objc static func savedLogin(connected: Bool, done: @escaping @MainActor @Sendable () -> Void) -> UIViewController {
        if !connected {
            let controller = UIHostingController(rootView: DirectConnectionNotice(notice: .make(.saveFailed,
                message: "The login wasn’t saved, so this connection wasn’t started. Your fields are kept. Review device storage, then retry.")).directAppearance())
            controller.sizingOptions = .intrinsicContentSize; controller.view.backgroundColor = .clear
            return controller
        }
        let controller = UIHostingController(rootView: DirectRecoveryCard(notice: .make(.saveFailed,
            message: connected ? "The desktop can still be used, but this login change wasn’t saved. Re-enter it next time if needed." : "The saved login couldn’t be updated, so this connection wasn’t started. Your fields are kept. Review the login and device storage, then retry."), primary: .init(title: connected ? "Continue" : "Review Login", perform: done)).directAppearance())
        controller.sizingOptions = .intrinsicContentSize; controller.view.backgroundColor = .clear
        return controller
    }
}
#endif

#endif
