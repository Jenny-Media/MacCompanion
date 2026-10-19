#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI
import UIKit
import Observation

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

/// A connection attempt owns its clock and monotonic presentation milestones.
/// This observes the existing transport; it never drives authentication or retry.
@objc(DirectConnectionProgressState) @MainActor @Observable final class DirectConnectionProgressState: NSObject {
    enum Stage: Int { case restoringDisplays = -1, contacting, securing, signingIn, startingSession }
    enum Status: Equatable { case complete, active, pending }
    struct Step: Identifiable {
        let stage: Stage
        let title: String
        let status: Status
        var id: Int { stage.rawValue }
    }
    private(set) var attempt = UUID()
    private(set) var stage = Stage.contacting
    private(set) var encrypted = false
    private(set) var restoresDisplays = false
    private(set) var startedAt = ProcessInfo.processInfo.systemUptime

    @objc(beginWaitingForDisplays:) func begin(waitingForDisplays: Bool) {
        attempt = UUID(); startedAt = ProcessInfo.processInfo.systemUptime
        restoresDisplays = waitingForDisplays; encrypted = false
        stage = waitingForDisplays ? .restoringDisplays : .contacting
    }
    func advance(to next: Stage) {
        guard next.rawValue > stage.rawValue else { return }
        stage = next
    }
    // These are closed, local transport events, never server-provided strings.
    @objc(recordTransportMessage:) func recordTransportMessage(_ message: String) {
        switch message {
        case "Connecting to Remote Login…": advance(to: .contacting)
        case "Verifying SSH server…": advance(to: .securing)
        case "Signing in to Remote Login…", "Opening encrypted connection…":
            encrypted = true; advance(to: .signingIn)
        default: break
        }
    }
    @objc(recordNativeState:) func recordNativeState(_ state: String) {
        guard encrypted else { return }
        switch state {
        case "Signing in", "Authenticating with macOS": advance(to: .signingIn)
        case "Opening desktop", "Connected": advance(to: .startingSession)
        default: break
        }
    }
    @objc func finishedRestoringDisplays() { advance(to: .contacting) }
    func elapsedSeconds(at uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Int {
        max(0, Int(uptime - startedAt))
    }
    func steps(service: String) -> [Step] {
        let final: String = service == "Terminal" ? "Opening Terminal" : service == "Trackpad & Keyboard" ? "Enabling controls" : "Starting desktop"
        let milestones: [(Stage, String, String)] = (restoresDisplays ? [(.restoringDisplays, "Ready to reconnect", "Waiting for Mac displays")] : []) + [
            (.contacting, "Mac reached", "Contacting Mac"),
            (.securing, "Connection secured", "Securing connection"),
            (.signingIn, "Signed in", "Signing in"),
            (.startingSession, final, final)
        ]
        return milestones.map { value, complete, current in
            let status: Status = value.rawValue < stage.rawValue ? .complete : value == stage ? .active : .pending
            return Step(stage: value, title: status == .complete ? complete : current + (status == .active ? "…" : ""), status: status)
        }
    }
}

struct DirectConnectionProgress: View {
    let name: String
    let service: String
    let symbol: String
    let progress: DirectConnectionProgressState
    var displayMode: String? = nil
    var message = "Connecting…"
    var addresses: [String] = []
    var sshPort = 22
    var screenSharingPort: Int? = nil
    let cancel: () -> Void
    var contentHeightChanged: (CGFloat) -> Void = { _ in }
    @State private var detailsExpanded = false
    @State private var headerHeight: CGFloat = 0
    @State private var statusHeight: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    @State private var safeAreaHeight: CGFloat = 0
    private func reportHeight() {
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
                    VStack(spacing: 20) {
                        Text(message).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: 0) {
                            ForEach(progress.steps(service: service)) { step in
                                if step.id != progress.steps(service: service).first?.id {
                                    Divider().padding(.leading, 52)
                                }
                                stepRow(step)
                            }
                        }.background(Color(uiColor: DirectConnectionStyle.field), in: RoundedRectangle(cornerRadius: 20))
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            let seconds = progress.elapsedSeconds()
                            Text("\(seconds) seconds elapsed").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                // Reserve the line so tablet sheets do not grow when it appears.
                                .opacity(seconds >= 5 ? 1 : 0).accessibilityHidden(seconds < 5)
                                .accessibilityIdentifier("connection-progress-elapsed")
                        }
                        VStack(spacing: 12) {
                            Button { detailsExpanded.toggle() } label: {
                                HStack(spacing: 8) {
                                    Text("Connection Details")
                                    Image(systemName: detailsExpanded ? "chevron.up" : "chevron.down").font(.caption.weight(.semibold))
                                }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                            }.font(.subheadline).foregroundStyle(.blue).buttonStyle(.plain)
                                .accessibilityIdentifier("connection-progress-details")
                                .accessibilityValue(detailsExpanded ? "Expanded" : "Collapsed")
                            if detailsExpanded { details }
                        }
                    }.frame(maxWidth: .infinity).padding(.vertical, 4)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("connection-progress-status")
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
        }.onChange(of: progress.attempt) { detailsExpanded = false }
            .directAppearance()
    }
    private func stepRow(_ step: DirectConnectionProgressState.Step) -> some View {
        HStack(spacing: 14) {
            Group {
                switch step.status {
                case .complete: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
                case .active: ProgressView().tint(.blue)
                case .pending: Image(systemName: "circle").foregroundStyle(.tertiary).font(.title3)
                }
            }.frame(width: 24).accessibilityHidden(true)
            Text(step.title).font(.body.weight(step.status == .active ? .medium : .regular))
                .foregroundStyle(step.status == .pending ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.padding(.horizontal, 16).padding(.vertical, 14)
            .accessibilityElement(children: .combine)
            .accessibilityValue(step.status == .complete ? "Complete" : step.status == .active ? "In progress" : "Pending")
            .accessibilityIdentifier("connection-progress-step-\(step.id)")
    }
    private var details: some View {
        VStack(spacing: 0) {
            if let first = addresses.first { detailRow("Configured address", value: first) }
            if addresses.count > 1 { detailRow("Other addresses", value: addresses.dropFirst().joined(separator: ", ")) }
            detailRow("Remote Login", value: "SSH · \(sshPort)")
            if let screenSharingPort { detailRow("Screen Sharing", value: "Port \(screenSharingPort)") }
            detailRow("Encryption", value: progress.encrypted ? "Encrypted" : "Establishing…", last: true)
        }.background(Color(uiColor: DirectConnectionStyle.field), in: RoundedRectangle(cornerRadius: 16))
    }
    private func detailRow(_ label: String, value: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(label).foregroundStyle(.secondary).fixedSize()
                    Spacer(minLength: 0)
                    Text(value).multilineTextAlignment(.trailing).fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).foregroundStyle(.secondary)
                    Text(value).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.font(.subheadline).padding(14)
            if !last { Divider().padding(.leading, 14) }
        }.accessibilityElement(children: .combine)
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
    @objc(updateProgress:name:inputOnly:desktopSize:message:progress:addresses:sshPort:screenSharingPort:cancel:heightChanged:) static func updateProgress(_ controller: UIViewController?, name: String, inputOnly: Bool, desktopSize: Int, message: String, progress: DirectConnectionProgressState, addresses: [String], sshPort: Int, screenSharingPort: Int, cancel: @escaping () -> Void, heightChanged: @escaping (CGFloat) -> Void) -> UIViewController {
        let view = DirectConnectionProgress(name: name, service: inputOnly ? "Trackpad & Keyboard" : "Screen Sharing",
            symbol: inputOnly ? "rectangle.and.hand.point.up.left" : "desktopcomputer", progress: progress,
            displayMode: inputOnly ? nil : desktopSize == 0 ? "Mirror Mac Screen" : "Virtual Display",
            message: message, addresses: addresses, sshPort: sshPort, screenSharingPort: screenSharingPort, cancel: cancel, contentHeightChanged: heightChanged)
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
