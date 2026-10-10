#if os(macOS) && MACCOMPANION_VNC_DEVELOPMENT
import AppKit
import SwiftUI

/// Keep the credential pair in one AppKit subtree. Autofill can update either
/// control without typing, so synchronize value changes as well as edit events.
struct MacCredentialFields: NSViewRepresentable {
    @Binding var username: String
    @Binding var password: String
    var showsPassword = true
    var enabled = true
    let prefix: String
    var submit: @MainActor () -> Void = {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> Fields {
        let view = Fields()
        context.coordinator.attach(view)
        updateNSView(view, context: context)
        return view
    }
    func updateNSView(_ view: Fields, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(view)
    }
    static func dismantleNSView(_ view: Fields, coordinator: Coordinator) { coordinator.detach(); view.clear() }

    @MainActor final class Fields: NSStackView {
        let account = NSTextField()
        let secret = NSSecureTextField()
        private let secretRow = NSStackView()
        override init(frame: NSRect) {
            super.init(frame: frame)
            orientation = .vertical; alignment = .leading; spacing = 14
            for (label, field, row) in [("Mac account", account, NSStackView()), ("Password", secret as NSTextField, secretRow)] {
                row.orientation = .vertical; row.alignment = .leading; row.spacing = 5
                let title = NSTextField(labelWithString: label); title.font = .systemFont(ofSize: 12); title.textColor = .secondaryLabelColor
                field.controlSize = .large; field.font = .systemFont(ofSize: 14)
                field.isBezeled = true; field.bezelStyle = .roundedBezel
                field.placeholderString = label; field.setAccessibilityLabel(label)
                row.addArrangedSubview(title); row.addArrangedSubview(field); addArrangedSubview(row)
                row.translatesAutoresizingMaskIntoConstraints = false; field.translatesAutoresizingMaskIntoConstraints = false
                row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
                field.widthAnchor.constraint(equalTo: row.widthAnchor).isActive = true
            }
            account.contentType = .username; secret.contentType = .password
            account.nextKeyView = secret
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        func showPassword(_ show: Bool) { secretRow.isHidden = !show }
        func clear() { window?.endEditing(for: self); account.stringValue = ""; secret.stringValue = "" }
    }
    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: MacCredentialFields
        private weak var view: Fields?
        private var observations: [NSKeyValueObservation] = []
        private var updating = false
        private var previousUsername: String?
        private var previousPassword: String?
        init(_ parent: MacCredentialFields) { self.parent = parent }
        func attach(_ view: Fields) {
            self.view = view
            for field in [view.account, view.secret] {
                field.delegate = self; field.target = self; field.action = #selector(commit(_:))
                observations.append(field.observe(\.stringValue, options: [.new]) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.synchronize() }
                })
            }
        }
        func update(_ view: Fields) {
            updating = true
            defer { updating = false }
            // Only an actual application-state change may replace native text.
            // Unrelated session redraws must not overwrite an autofill update.
            if previousUsername != parent.username { view.account.stringValue = parent.username; previousUsername = parent.username }
            if previousPassword != parent.password { view.secret.stringValue = parent.password; previousPassword = parent.password }
            view.account.isEnabled = parent.enabled; view.secret.isEnabled = parent.enabled
            if !parent.enabled { view.window?.endEditing(for: view) }
            view.showPassword(parent.showsPassword)
            view.account.setAccessibilityIdentifier(parent.prefix + "-account")
            view.secret.setAccessibilityIdentifier(parent.prefix + "-password")
        }
        func synchronize() {
            guard !updating, let view else { return }
            let account = view.account.stringValue, secret = view.secret.stringValue
            previousUsername = account; previousPassword = secret
            if parent.username != account { parent.username = account }
            if parent.password != secret { parent.password = secret }
        }
        func controlTextDidChange(_ notification: Notification) { synchronize() }
        func controlTextDidEndEditing(_ notification: Notification) { synchronize() }
        @objc private func commit(_ sender: NSTextField) {
            synchronize()
            if sender === view?.account && parent.showsPassword { view?.window?.makeFirstResponder(view?.secret) }
            else { parent.submit() }
        }
        func detach() { observations.removeAll(); view?.account.delegate = nil; view?.secret.delegate = nil; view = nil; previousUsername = nil; previousPassword = nil }
    }
}

struct MacSignInPanel<Content: View, Status: View>: View {
    let mac: DirectMacRecordV1
    let mode: MacConnectionMode
    @ViewBuilder var content: () -> Content
    @ViewBuilder var status: () -> Status
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Image(systemName: mode.symbol).font(.system(size: 28)).foregroundStyle(.tint)
                        .frame(width: 52, height: 52).background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mac.name).font(.title2.bold())
                        Text(mode == .desktop ? "Desktop · Screen Sharing" : "Terminal · Remote Login").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                content()
                status().frame(maxWidth: .infinity, alignment: .leading)
            }.padding(28).frame(width: 440)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary))
                .padding(24).frame(maxWidth: .infinity)
        }.scrollBounceBehavior(.basedOnSize)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}
#endif
