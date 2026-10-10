#if (os(iOS) || os(macOS)) && MACCOMPANION_VNC_DEVELOPMENT
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
                    Text("A server key can change after reinstalling macOS, or when an address reaches a different machine. Login stays blocked until the saved and presented identities agree.")
                    Text("On the Mac, inspect the SSH server keys in /etc/ssh/ssh_host_*_key.pub with ssh-keygen -lf and compare the matching fingerprint.").font(.body.monospaced())
                    Text("Only after checking the Mac independently, use Mac Settings → Saved Logins & Server Trust → Forget SSH Server Key. The next connection asks you to verify the new fingerprint before sending login.")
                        .foregroundStyle(.secondary)
                }.padding(24)
            }.navigationTitle("Verify Server Identity").directInlineNavigationTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

#endif
