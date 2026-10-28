#if (os(iOS) || os(macOS) || os(visionOS)) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
struct TerminalIdentityGuide: View {
    let macName: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "lock.shield").font(.largeTitle).foregroundStyle(.red)
                    Text("Verify \(macName) independently").font(.title2.bold())
                    DirectGuidanceRow(title: "Login is blocked", detail: "This key differs from the one you trusted. A reinstall or another computer at this address may explain it.", symbol: "hand.raised")
                    DirectGuidanceRow(title: "1. Check the remote Mac", detail: "Inspect its SSH server keys and compare the fingerprint for the matching key type.", symbol: "desktopcomputer")
                    Text("ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub").font(.footnote.monospaced()).textSelection(.enabled)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                    Text("Other key types are in /etc/ssh/ssh_host_*_key.pub.").font(.caption).foregroundStyle(.secondary)
                    DirectGuidanceRow(title: "2. Forget the old key", detail: "Mac Settings → Saved Logins & Server Trust → Forget SSH Server Key.", symbol: "key")
                    DirectGuidanceRow(title: "3. Verify again", detail: "Reconnect and compare the new fingerprint before login.", symbol: "checkmark.shield")
                }.padding(24)
            }.navigationTitle("Verify Server Identity").directInlineNavigationTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

#endif
