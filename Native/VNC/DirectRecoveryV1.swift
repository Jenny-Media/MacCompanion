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
        case .setupVerified: copy = ("Public key installed", "A fresh key-only login worked and the preferred Terminal key was saved. Your private key stays on this iPhone.", .success)
        case .importUnsupported: copy = ("This key format isn’t supported", "Use an Ed25519 private key in OpenSSH format. RSA, ECDSA and hardware-backed keys aren’t currently supported.", .warning)
        case .importInvalid: copy = ("Key couldn’t be imported", "The file isn’t a valid supported OpenSSH private key. Choose another file; no key was added.", .warning)
        case .importTooLarge: copy = ("Key file is too large", "Choose an Ed25519 OpenSSH private key no larger than 32 KiB.", .warning)
        case .importUnlock: copy = ("Key couldn’t be unlocked", "The passphrase may be incorrect, or the encrypted file may be damaged. Re-enter the passphrase or choose another file.", .warning)
        case .importWorkLimit: copy = ("Key encryption settings aren’t supported", "Re-export this key with supported OpenSSH encryption settings, then import again.", .warning)
        case .exportCancelled: copy = ("Export cancelled", "No backup was exported. The original key is still available on this iPhone.", .information)
        case .exportFailed: copy = ("Backup wasn’t exported", "The backup couldn’t be prepared or saved. Your original key is kept; try exporting again.", .warning)
        case .controlsUnavailable: copy = ("Saved controls unavailable", "The app couldn’t read your custom controls. Existing data is kept; standard controls remain available where safe.", .warning)
        case .cloudUnavailable: copy = ("iCloud Sync unavailable", "The app couldn’t access sync data. Local Macs and logins are kept. Check iCloud Keychain in Settings, then retry.", .warning)
        case .cloudRemoval: copy = ("Cloud removal didn’t finish", "Sync is off and local data is kept. Some cloud copies may remain; retry removal when Keychain is available.", .warning)
        case .storeUnavailable: copy = ("App Store unavailable", "Some purchases couldn’t be loaded. Reload the store when internet access is available. Free features remain available.", .warning)
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

#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import UIKit
import LocalAuthentication
import StoreKit

struct DirectRecoveryAction {
    let title: String
    var symbol: String? = nil
    var pro = false
    let perform: @MainActor () -> Void
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
            Text(notice.message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
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
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(color.opacity(0.17)))
            .accessibilityIdentifier("recovery-" + notice.reason.rawValue)
            .onAppear { UIAccessibility.post(notification: .announcement, argument: notice.title) }
            .onChange(of: notice.reason) { _, _ in UIAccessibility.post(notification: .announcement, argument: notice.title) }
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
            }.navigationTitle("Verify This Mac").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { answer(false) } } }
        }.interactiveDismissDisabled()
    }
}
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
