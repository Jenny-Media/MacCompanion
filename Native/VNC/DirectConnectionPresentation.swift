#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import UIKit

/// Shared presentation only; connection ownership and server trust stay in their
/// existing controllers. Names are a passive view of the saved Mac list.
enum DirectConnectionStyle {
    static let panel = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.094, green: 0.11, blue: 0.133, alpha: 1)
        : UIColor(red: 0.973, green: 0.977, blue: 0.985, alpha: 1) }
    static let field = UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.141, green: 0.161, blue: 0.188, alpha: 1) : .white }
}

struct DirectConnectionBackdrop: View {
    let names: [String]
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            if !reduceTransparency {
                VStack(alignment: .leading, spacing: 20) {
                    HStack { Text("My Macs").font(.largeTitle.bold()); Spacer(); Image(systemName: "plus.circle.fill").font(.title).foregroundStyle(.blue) }
                    ForEach(Array(names.prefix(8).enumerated()), id: \.offset) { _, name in
                        HStack(spacing: 14) {
                            Image(systemName: "desktopcomputer").font(.title2).foregroundStyle(.blue)
                                .frame(width: 44, height: 44).background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            Text(name).font(.headline).lineLimit(2)
                            Spacer()
                        }.padding(16).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    }
                    Spacer()
                }.padding(.horizontal, 24).padding(.top, 30).blur(radius: 6)
                Color(uiColor: .systemGroupedBackground).opacity(0.36).ignoresSafeArea()
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct DirectConnectionIdentity: View {
    let name: String
    let service: String
    let symbol: String
    var compact = false
    var cancel: (() -> Void)?
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: compact ? 20 : 24)).foregroundStyle(.blue)
                .frame(width: compact ? 40 : 52, height: compact ? 40 : 52)
                .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: compact ? 12 : 16))
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text(service).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let cancel {
                Button(action: cancel) { Image(systemName: "xmark").font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary).frame(width: 44, height: 44).background(.quaternary, in: Circle()) }
                    .buttonStyle(.plain).accessibilityLabel("Cancel connection").accessibilityIdentifier("terminal-login-close")
            }
        }
    }
}

extension DirectRecoveryNotice {
    var connectionTitle: String {
        switch reason { case .loginRejected: title == Self.make(.loginRejected).title ? "Couldn’t sign in" : title; case .keyRejected: "Mac didn’t accept this key"; default: title }
    }
    var connectionMessage: String {
        switch reason {
        case .loginRejected: title == Self.make(.loginRejected).title ? "Check your Mac account and password." : message
        case .keyRejected: "Set it up for this account, or use a password."
        default: message
        }
    }
}

struct DirectConnectionNotice: View {
    let notice: DirectRecoveryNotice
    private var color: Color { notice.severity == .critical ? .red : .orange }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notice.severity == .critical ? "exclamationmark.shield" : "exclamationmark.circle").font(.body).foregroundStyle(color).padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(notice.connectionTitle).font(.subheadline.weight(.semibold))
                Text(notice.connectionMessage).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(color.opacity(0.22)))
            .accessibilityIdentifier("recovery-" + notice.reason.rawValue)
            .onAppear { UIAccessibility.post(notification: .announcement, argument: notice.connectionTitle) }
    }
}

struct DirectConnectionPasswordField: UIViewRepresentable {
    @Binding var text: String
    let secure: Bool
    let submit: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = "Mac account password"; field.textContentType = .password
        field.autocapitalizationType = .none; field.autocorrectionType = .no; field.returnKeyType = .go
        field.font = .preferredFont(forTextStyle: .body); field.adjustsFontForContentSizeCategory = true
        field.delegate = context.coordinator; field.accessibilityIdentifier = "terminal-login-password"
        field.addTarget(context.coordinator, action: #selector(Coordinator.edited(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.isSecureTextEntry != secure { field.isSecureTextEntry = secure }
        if field.text != text { field.text = text }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        // A representable otherwise accepts the ScrollView's proposed height,
        // stretching the password row and pushing the sheet off screen.
        CGSize(width: proposal.width ?? 200, height: max(32, uiView.intrinsicContentSize.height))
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: DirectConnectionPasswordField
        init(_ parent: DirectConnectionPasswordField) { self.parent = parent }
        @objc func edited(_ field: UITextField) { parent.text = field.text ?? "" }
        func textFieldShouldReturn(_ field: UITextField) -> Bool { field.resignFirstResponder(); parent.submit(); return true }
    }
}

@objc(DirectConnectionBridge) @MainActor final class DirectConnectionBridge: NSObject {
    @objc static var panelColor: UIColor { DirectConnectionStyle.panel }
    @objc static var fieldColor: UIColor { DirectConnectionStyle.field }
    @objc static func background(names: [String]) -> UIViewController {
        let host = UIHostingController(rootView: DirectConnectionBackdrop(names: names).directAppearance())
        host.view.backgroundColor = .clear; host.view.isUserInteractionEnabled = false
        return host
    }
    @objc static func validation() -> UIViewController {
        let notice = DirectRecoveryNotice(reason: .loginRejected, title: "Check your login", message: "Enter a Mac account and password, each no longer than 63 UTF-8 bytes. Your draft is kept.")
        let host = UIHostingController(rootView: DirectConnectionNotice(notice: notice).directAppearance())
        host.sizingOptions = .intrinsicContentSize; host.view.backgroundColor = .clear
        return host
    }
}
#endif
