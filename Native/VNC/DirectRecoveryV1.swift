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
        case .desktopDisconnected: copy = ("Desktop disconnected", "Reconnect to continue. Your display and zoom will be restored when the Mac’s display layout is compatible.", .warning)
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

#if (os(iOS) || os(macOS)) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
#if os(iOS)
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
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.tint).frame(width: 26).accessibilityHidden(true)
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
                    #if os(iOS)
                    DirectGuidanceRow(title: "Remote Login · All modes", detail: "Turn on Remote Login and allow your Mac account.", symbol: "terminal")
                    DirectGuidanceRow(title: "Desktop & Trackpad", detail: "Also turn on Screen Sharing and allow your Mac account.", symbol: "macwindow")
                    #else
                    DirectGuidanceRow(title: "Desktop", detail: "Turn on Screen Sharing and allow your Mac account.", symbol: "macwindow")
                    DirectGuidanceRow(title: "Terminal", detail: "Turn on Remote Login and allow your Mac account.", symbol: "terminal")
                    #endif
                    Label("System Settings → General → Sharing", systemImage: "gearshape").font(.footnote).foregroundStyle(.secondary)
                }
                Section("2. Add its address") {
                    DirectGuidanceRow(title: "Local or private VPN address", detail: "Use your Mac’s hostname or IP address from Sharing settings. For a private VPN, connect both devices to the same network.", symbol: "network")
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

/// Shared presentation; the opt-in disclosure and confirmed removal remain unchanged.
struct DirectCloudSettingsSection: View {
    @State private var cloud = DirectCloudSyncV1.shared
    @State private var lock = DirectAppLockV1.shared
    @State private var enableCloud = false
    @State private var removeCloud = false
    var body: some View {
        Section {
            Toggle("iCloud Sync", isOn: Binding(get: { cloud.enabled }, set: {
                if $0 { enableCloud = true } else if lock.canAccess { cloud.setEnabled(false) }
            })).disabled(cloud.busy).accessibilityIdentifier("icloud-library-toggle")
            if let notice = cloud.recovery {
                DirectRecoveryCard(notice: notice, primary: .init(title: notice.reason == .cloudRemoval ? "Retry Removal" : "Retry") {
                    guard lock.canAccess else { return }
                    if notice.reason == .cloudRemoval { cloud.removeCloudCopies() } else { cloud.retry() }
                })
            } else { Text(cloud.status).font(.footnote).foregroundStyle(.secondary) }
            DisclosureGroup("What syncs") {
                DirectGuidanceRow(title: "Saved Macs & preferences", detail: "Names, detected models, addresses, ports, connection defaults and display/input preferences.", symbol: "icloud")
                DirectGuidanceRow(title: "Stays on this device", detail: "Passwords, private keys, key-file references, server trust, saved text, custom actions, appearance and app-lock settings.", symbol: "lock.shield")
                Text("Protected by iCloud Keychain, your Apple Account and trusted devices.").font(.footnote).foregroundStyle(.secondary)
            }
            DisclosureGroup("Manage Sync") {
                if cloud.enabled {
                    Button("Refresh iCloud", systemImage: "arrow.triangle.2.circlepath") { if lock.canAccess { cloud.refresh() } }.disabled(cloud.busy)
                }
                if cloud.busy { ProgressView("Updating Keychain…") }
                Button("Remove iCloud Copies", systemImage: "icloud.slash", role: .destructive) { removeCloud = true }.disabled(cloud.busy)
                Text("Turning sync off keeps existing cloud copies. Removal is a separate action.").font(.footnote).foregroundStyle(.secondary)
                Link("iCloud security", destination: URL(string: "https://support.apple.com/en-us/102651")!)
            }
        } header: { Text("iCloud") } footer: {
            Text("Credentials stay on this device.")
        }
        .alert("Enable iCloud Sync?", isPresented: $enableCloud) {
            Button("Enable Sync") { if lock.canAccess { cloud.setEnabled(true) } }
            Button("Cancel", role: .cancel) {}
        } message: { Text(DirectCloudSyncV1.disclosure) }
        .confirmationDialog("Remove saved Mac copies from iCloud?", isPresented: $removeCloud, titleVisibility: .visible) {
            Button("Turn Off Sync & Remove Cloud Copies", role: .destructive) { if lock.canAccess { cloud.removeCloudCopies() } }
        } message: {
            Text("Local Macs and logins stay on this device. Turn off sync on your other devices first; otherwise they may upload the saved Macs again. Apple manages when removal reaches other devices.")
        }
        .onChange(of: lock.canAccess) { _, allowed in if !allowed { enableCloud = false; removeCloud = false } }
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
        #if os(iOS)
        Color(uiColor: .secondarySystemBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
    private func announce() {
        #if os(iOS)
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
                    Image(systemName: "lock.shield").font(.largeTitle).foregroundStyle(.blue)
                    Text("Is this your Mac?").font(.title.bold())
                    Text("You’re connecting to \(macName). Independently check this SSH server fingerprint on your Mac before trusting it.")
                    Text(fingerprint).font(.footnote.monospaced()).textSelection(.enabled).padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                    Text("On the Mac, compare the matching server key with ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub. If the server uses another key type, compare that matching host key instead.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Trust & Connect") { answer(true) }.buttonStyle(.borderedProminent).controlSize(.large).frame(minHeight: 44)
                    Text("No login is sent until you approve.").font(.footnote).foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: 520)
            }.navigationTitle("Verify This Mac")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { answer(false) } } }
        }.interactiveDismissDisabled()
    }
}
#if os(iOS)
/// UIKit Desktop uses the same copy and actions as the SwiftUI recovery screens.
@objc(DirectRecoveryBridgeV1) @MainActor final class DirectRecoveryBridgeV1: NSObject {
    static func desktopReason(stage: Int, hadFrame: Bool) -> DirectRecoveryNotice.Reason {
        switch stage {
        case 10: return .addressNotFound
        case 11, 110: return .macUnreachable
        case 2: return .unsupportedConnection
        case 7, 8, 111: return .loginRejected
        case 112: return .serverChanged
        case 113: return .connectionCancelled
        case 114: return .desktopUnavailable
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
        let notice = desktopNotice(stage: stage, hadFrame: hadFrame, port: port)
        let reason = notice.reason
        if !hadFrame {
            let controller = UIHostingController(rootView: DirectConnectionNotice(notice: notice).directAppearance())
            controller.sizingOptions = .intrinsicContentSize; controller.view.backgroundColor = .clear
            return controller
        }
        let controller = UIHostingController(rootView: DirectRecoveryCard(notice: notice,
            primary: .init(title: reason == .loginRejected ? "Edit Login" : hadFrame ? "Reconnect" : "Try Again", perform: reason == .loginRejected ? edit : retry),
            secondary: reason == .loginRejected ? nil : .init(title: "Edit Login", perform: edit)).directAppearance())
        controller.sizingOptions = .intrinsicContentSize
        controller.view.backgroundColor = .clear
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
