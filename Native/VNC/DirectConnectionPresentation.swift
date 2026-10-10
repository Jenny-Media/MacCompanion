#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import UIKit

/// Shared presentation only; connection ownership and server trust stay in their
/// existing controllers. Names are a passive view of the saved Mac list.
enum DirectConnectionStyle {
    // Resolve an elevated system surface even inside our custom presentation.
    static let panel = UIColor { traits in
        UIColor.systemBackground.resolvedColor(with: traits.modifyingTraits { $0.userInterfaceLevel = .elevated })
    }
    static let field = UIColor.tertiarySystemGroupedBackground
    static let border = UIColor { traits in
        traits.accessibilityContrast == .high
            ? UIColor.opaqueSeparator.resolvedColor(with: traits)
            : UIColor.separator.resolvedColor(with: traits).withAlphaComponent(0.20)
    }
    static let cornerRadius: CGFloat = 32
    static let shadowRadius: CGFloat = 24
    static let shadowOffset = CGSize(width: 0, height: 10)
    static func shadowOpacity(dark: Bool) -> Float { dark ? 0.28 : 0.14 }
    static func dimmingOpacity(dark: Bool) -> Double { dark ? 0.32 : 0.16 }
}

private struct DirectConnectionCardSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DirectConnectionStyle.cornerRadius)
        content.background(Color(uiColor: DirectConnectionStyle.panel), in: shape)
            .overlay(shape.strokeBorder(contrast == .increased
                ? Color(uiColor: .opaqueSeparator) : Color(uiColor: DirectConnectionStyle.border), lineWidth: 1))
            .shadow(color: .black.opacity(Double(DirectConnectionStyle.shadowOpacity(dark: colorScheme == .dark))),
                    radius: DirectConnectionStyle.shadowRadius,
                    x: DirectConnectionStyle.shadowOffset.width, y: DirectConnectionStyle.shadowOffset.height)
    }
}

extension View {
    func directConnectionCardSurface() -> some View { modifier(DirectConnectionCardSurface()) }
}

struct DirectConnectionBackdrop: View {
    let names: [String]
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
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
            }
            Color.black.opacity(DirectConnectionStyle.dimmingOpacity(dark: colorScheme == .dark)).ignoresSafeArea()
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
                DirectNoticeMessage(message: notice.connectionMessage).font(.subheadline)
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
    @objc static func styleCard(_ view: UIView) {
        let traits = view.traitCollection
        view.backgroundColor = DirectConnectionStyle.panel
        view.layer.cornerRadius = DirectConnectionStyle.cornerRadius
        view.layer.borderWidth = 1
        view.layer.borderColor = DirectConnectionStyle.border.resolvedColor(with: traits).cgColor
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = DirectConnectionStyle.shadowOpacity(dark: traits.userInterfaceStyle == .dark)
        view.layer.shadowRadius = DirectConnectionStyle.shadowRadius
        view.layer.shadowOffset = DirectConnectionStyle.shadowOffset
        view.layer.shadowPath = UIBezierPath(roundedRect: view.bounds, cornerRadius: DirectConnectionStyle.cornerRadius).cgPath
    }
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
