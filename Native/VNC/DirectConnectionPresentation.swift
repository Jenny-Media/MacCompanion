#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import UIKit

/// Shared presentation only; connection ownership and server trust stay in their
/// existing controllers. Names are a passive view of the saved Mac list.
enum DirectConnectionStyle {
    // Keep the same grouped surface in native sheets and hosted presentations.
    static let panel = UIColor { traits in
        UIColor.systemGroupedBackground.resolvedColor(with: traits.modifyingTraits { $0.userInterfaceLevel = .base })
    }
    // Field fill is independent of the sheet's inherited elevation and tint.
    static let field = UIColor { traits in
        UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits.modifyingTraits { $0.userInterfaceLevel = .base })
    }
    // A remote Mac account is not an account for this app's bundle identifier.
    // An explicit empty type opts out of app-account QuickType suggestions;
    // the system's manual AutoFill/Paste menu and per-Mac Save Login remain.
    static let remoteCredentialContentType = UITextContentType(rawValue: "")
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

/// A grouped input row keeps the full width available for its editable value.
/// Its input reserves the caption's space in every state, so rows never jump.
struct DirectCredentialRow<Input: View>: View {
    @ViewBuilder let input: () -> Input
    var body: some View {
        input().frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 4)
    }
}

/// The same caption/value layout is used by UIKit Screen Sharing and the
/// SwiftUI Terminal and Saved Login forms. Focus and reveal keep one editor.
@MainActor final class DirectCredentialInput: UIView, UIGestureRecognizerDelegate {
    let field: UITextField
    let caption = UILabel()
    private let title: String
    private var captionHeight: CGFloat { ceil(caption.font.lineHeight) }
    private var editorHeight: CGFloat { max(44, ceil(field.font?.lineHeight ?? 0) + 4) }
    private var showsCaption: Bool { field.hasText || field.isFirstResponder }

    init(field: UITextField, title: String) {
        self.field = field; self.title = title
        super.init(frame: .zero)
        caption.text = title; caption.textColor = .secondaryLabel
        caption.isAccessibilityElement = false; caption.accessibilityElementsHidden = true
        field.accessibilityLabel = title
        addSubview(caption); addSubview(field)
        field.addTarget(self, action: #selector(refresh), for: [.editingDidBegin, .editingDidEnd, .editingChanged])
        let focusTap = UITapGestureRecognizer(target: self, action: #selector(focusEditor))
        focusTap.delegate = self; addGestureRecognizer(focusTap)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: DirectCredentialInput, _: UITraitCollection) in
            view.updateFonts(); view.invalidateIntrinsicContentSize(); view.setNeedsLayout()
        }
        updateFonts(); refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func updateFonts() {
        caption.font = .preferredFont(forTextStyle: .caption1, compatibleWith: traitCollection)
        field.font = .preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
    }
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: captionHeight + 2 + editorHeight)
    }
    @objc func refresh() {
        caption.isHidden = !showsCaption
        field.placeholder = showsCaption ? nil : title
        setNeedsLayout()
    }
    @objc private func focusEditor() { if field.isEnabled { field.becomeFirstResponder() } }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Let the editor retain its native caret, selection and AutoFill gestures.
        !(touch.view?.isDescendant(of: field) ?? false)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        // Programmatic draft updates also get the correct label on layout.
        caption.isHidden = !showsCaption; field.placeholder = showsCaption ? nil : title
        caption.frame = CGRect(x: 0, y: 0, width: bounds.width, height: captionHeight)
        field.frame = CGRect(x: 0, y: showsCaption ? captionHeight + 2 : (bounds.height - editorHeight) / 2,
                             width: bounds.width, height: editorHeight)
    }
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
    var body: some View { Color(uiColor: .systemGroupedBackground).ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true) }
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

/// Actions reserve their own space above the safe area or keyboard. The fields
/// and status above them can scroll without moving the connection actions.
struct DirectConnectionFooter<Actions: View>: View {
    var contentHeightChanged: (CGFloat) -> Void = { _ in }
    @ViewBuilder let actions: () -> Actions
    var body: some View {
        VStack(spacing: 8, content: actions)
            .padding(.horizontal, 24).padding(.vertical, 8)
            .frame(maxWidth: 520).frame(maxWidth: .infinity)
            .background(Color(uiColor: DirectConnectionStyle.panel))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeightChanged($0) }
    }
}

struct DirectConnectionProgress: View {
    let name: String
    let service: String
    let symbol: String
    var displayMode: String? = nil
    var message = "Connecting…"
    let cancel: () -> Void
    var contentHeightChanged: (CGFloat) -> Void = { _ in }
    @State private var headerHeight: CGFloat = 0
    @State private var statusHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    @State private var safeAreaHeight: CGFloat = 0
    private func reportHeight() {
        // Report natural content, independently of the extra room used to
        // center progress in a tall phone sheet. This keeps tablet forms fitted.
        contentHeightChanged(headerHeight + statusHeight + 48 + 28 + footerHeight + safeAreaHeight)
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    DirectConnectionIdentity(name: name, service: displayMode ?? service, symbol: symbol)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            headerHeight = $0; reportHeight()
                        }
                    Spacer(minLength: 24)
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.regular)
                        Text(message).font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity).padding(.vertical, 4)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            statusHeight = $0; reportHeight()
                        }
                    Spacer(minLength: 24)
                }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 8)
                    .frame(maxWidth: 520, minHeight: geometry.size.height)
                    .frame(maxWidth: .infinity)
            }.scrollBounceBehavior(.basedOnSize)
        }.safeAreaInset(edge: .bottom, spacing: 0) {
            DirectConnectionFooter(contentHeightChanged: {
                footerHeight = $0; reportHeight()
            }) {
                Button("Cancel", action: cancel).font(.headline).foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, minHeight: 48).buttonStyle(.plain)
                    .accessibilityIdentifier(service == "Terminal" ? "terminal-login-cancel" : "mac-login-cancel")
            }
        }.onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top + $0.safeAreaInsets.bottom } action: {
            safeAreaHeight = $0; reportHeight()
        }.directAppearance()
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
    var color: Color {
        switch notice.severity { case .information: .blue; case .warning: .orange; case .critical: .red; case .success: .green }
    }
    var symbol: String {
        switch notice.severity {
        case .information: "info.circle"
        case .warning: "exclamationmark.circle"
        case .critical: "exclamationmark.shield"
        case .success: "checkmark.circle"
        }
    }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.body).foregroundStyle(color).padding(.top, 2)
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

struct DirectConnectionCredentialField: UIViewRepresentable {
    @Binding var text: String
    let secure: Bool
    var title = "Password"
    var returnKey = UIReturnKeyType.go
    var identifier = "terminal-login-password"
    let submit: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> DirectCredentialInput {
        let field = UITextField()
        field.textContentType = DirectConnectionStyle.remoteCredentialContentType
        field.autocapitalizationType = .none; field.autocorrectionType = .no; field.returnKeyType = returnKey
        field.font = .preferredFont(forTextStyle: .body); field.adjustsFontForContentSizeCategory = true
        field.delegate = context.coordinator; field.accessibilityIdentifier = identifier
        field.accessibilityLabel = title
        field.addTarget(context.coordinator, action: #selector(Coordinator.edited(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return DirectCredentialInput(field: field, title: title)
    }
    func updateUIView(_ input: DirectCredentialInput, context: Context) {
        let field = input.field
        context.coordinator.parent = self
        field.isEnabled = context.environment.isEnabled
        if field.isSecureTextEntry != secure { field.isSecureTextEntry = secure }
        if field.text != text { field.text = text }
        input.refresh()
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: DirectCredentialInput, context: Context) -> CGSize? {
        // A representable otherwise accepts the ScrollView's proposed height,
        // stretching the password row and pushing the sheet off screen.
        CGSize(width: proposal.width ?? 200, height: uiView.intrinsicContentSize.height)
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: DirectConnectionCredentialField
        init(_ parent: DirectConnectionCredentialField) { self.parent = parent }
        @objc func edited(_ field: UITextField) { parent.text = field.text ?? "" }
        func textFieldShouldReturn(_ field: UITextField) -> Bool { field.resignFirstResponder(); parent.submit(); return true }
    }
}

@objc(DirectConnectionBridge) @MainActor final class DirectConnectionBridge: NSObject {
    @objc(updateProgress:name:inputOnly:desktopSize:message:cancel:heightChanged:) static func updateProgress(_ controller: UIViewController?, name: String, inputOnly: Bool, desktopSize: Int, message: String, cancel: @escaping () -> Void, heightChanged: @escaping (CGFloat) -> Void) -> UIViewController {
        let view = DirectConnectionProgress(name: name, service: inputOnly ? "Trackpad & Keyboard" : "Screen Sharing",
            symbol: inputOnly ? "rectangle.and.hand.point.up.left" : "desktopcomputer",
            displayMode: inputOnly ? nil : desktopSize == 0 ? "Mirror Mac Screen" : "Virtual Display",
            message: message, cancel: cancel, contentHeightChanged: heightChanged)
        if let host = controller as? UIHostingController<DirectConnectionProgress> {
            host.rootView = view; return host
        }
        let host = UIHostingController(rootView: view); host.view.backgroundColor = .clear; return host
    }
    @objc(defaultQuickActionsForInputOnly:) static func defaultQuickActions(inputOnly: Bool) -> [[String: Any]] {
        (inputOnly ? DirectControlMode.trackpad : .desktop).defaults.map(\.native)
    }

    @objc(credentialInputForField:title:) static func credentialInput(field: UITextField, title: String) -> UIView {
        DirectCredentialInput(field: field, title: title)
    }
    @objc(refreshCredentialInputForField:) static func refreshCredentialInput(field: UITextField) {
        (field.superview as? DirectCredentialInput)?.refresh()
    }
    @objc static var panelColor: UIColor { DirectConnectionStyle.panel }
    @objc static var fieldColor: UIColor { DirectConnectionStyle.field }
    @objc static var remoteCredentialContentType: UITextContentType { DirectConnectionStyle.remoteCredentialContentType }
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
