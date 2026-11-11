#if (os(iOS) || os(macOS) || os(visionOS)) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
struct TerminalIdentityGuide: View {
    let macName: String
    var presentedIdentity: TerminalSecretStore.HostIdentity? = nil
    var temporary = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "lock.shield").font(.largeTitle).foregroundStyle(.red)
                    Text("Verify \(macName) independently").font(.title2.bold())
                    DirectGuidanceRow(title: "Login is blocked", detail: "This key differs from the one you trusted. A reinstall or another computer at this address may explain it.", symbol: "hand.raised")
                    if let presentedIdentity {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Presented by the server").font(.headline)
                            Text(presentedIdentity.keyType).font(.subheadline).foregroundStyle(.secondary)
                            Text(presentedIdentity.fingerprint).font(.footnote.monospaced())
                                .fixedSize(horizontal: false, vertical: true)
                        }.textSelection(.enabled)
                    }
                    DirectGuidanceRow(title: "1. Check the remote Mac", detail: presentedIdentity == nil
                        ? "Get the SSH key fingerprint directly from your Mac so you can compare it when you reconnect."
                        : "Compare the fingerprint above with the matching key type on your Mac. Continue only if they match.", symbol: "desktopcomputer")
                    Text("ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub").font(.footnote.monospaced()).textSelection(.enabled)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    Text("Other key types are in /etc/ssh/ssh_host_*_key.pub.").font(.caption).foregroundStyle(.secondary)
                    #if os(iOS)
                    if temporary {
                        DirectGuidanceRow(title: "2. End the temporary session", detail: "Return to My Macs and start a new Quick Connect session.", symbol: "arrow.clockwise")
                    } else {
                        DirectGuidanceRow(title: "2. Forget the old key", detail: "My Macs → Edit Mac → Reset Login & Trust → Forget SSH Server Key.", symbol: "key")
                    }
                    #else
                    DirectGuidanceRow(title: "2. Forget the old key", detail: "Mac Settings → Saved Logins & Server Trust → Forget SSH Server Key.", symbol: "key")
                    #endif
                    DirectGuidanceRow(title: "3. Verify again", detail: "Reconnect and compare the new fingerprint before login.", symbol: "checkmark.shield")
                }.padding(24)
            }.navigationTitle("Verify Server Identity").directInlineNavigationTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

#endif
