#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import Observation
import SwiftUI
import UIKit

/// Plain text only. These bounds are independent of the saved-action library.
struct DirectComposedText: Equatable {
    let text: String
    var needsConfirmation: Bool { text.contains("\n") || text.contains("\t") }
    var endsWithNewline: Bool { text.hasSuffix("\n") }
    enum Failure: Error {
        case empty, controls, tooLarge(DirectControlMode)
        var message: String {
            switch self {
            case .empty: "Enter some text first."
            case .controls: "Remove control characters before sending. Line breaks and tabs are supported."
            case .tooLarge(let mode): mode == .terminal ? "Terminal can send up to 4096 UTF-8 bytes at once." : "Desktop input can send up to 256 Unicode characters at once."
            }
        }
    }
    init(_ draft: String, mode: DirectControlMode) throws {
        let text = draft.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
        guard !text.isEmpty else { throw Failure.empty }
        guard !text.unicodeScalars.contains(where: { scalar in
            (scalar.value < 32 && scalar.value != 9 && scalar.value != 10) || (127...159).contains(scalar.value)
        }) else { throw Failure.controls }
        guard mode == .terminal ? text.utf8.count <= 4096 : text.unicodeScalars.count <= 256 else { throw Failure.tooLarge(mode) }
        self.text = text
    }
    var desktopEvents: [[String: Any]] {
        text.unicodeScalars.flatMap { scalar in
            let value = scalar.value
            let key: UInt32 = value == 10 ? 0xff0d : value == 9 ? 0xff09 : value < 256 ? value : 0x01000000 | value
            return [["key": key, "down": true], ["key": key, "down": false]]
        }
    }
    func terminalBytes(bracketedPaste: Bool) -> [UInt8] {
        Array((bracketedPaste ? "\u{1b}[200~" + text + "\u{1b}[201~" : text).utf8)
    }
}

@MainActor @Observable final class DirectTextComposerDraft {
    let macName: String
    let mode: DirectControlMode
    private(set) var text = ""
    private(set) var sending = false
    private(set) var active = false
    var expanded = false
    var compactLayout = false
    var issue: String?
    var confirmation: DirectComposedText?
    @ObservationIgnored private var epoch = UUID()
    @ObservationIgnored private var available: () -> Bool = { false }
    @ObservationIgnored private var send: ((String, @escaping (String?) -> Void) -> Void)?
    @ObservationIgnored var close: (() -> Void)?
    @ObservationIgnored var sendingChanged: ((Bool) -> Void)?
    @ObservationIgnored var interrupted: (() -> Void)?
    init(macName: String, mode: DirectControlMode) { self.macName = macName; self.mode = mode }
    var validationIssue: String? {
        do { _ = try DirectComposedText(text, mode: mode); return nil }
        catch let failure as DirectComposedText.Failure { return failure.message }
        catch { return "Review the draft before sending." }
    }
    var canSend: Bool { active && !sending && validationIssue == nil }
    func configure(available: @escaping () -> Bool, send: @escaping (String, @escaping (String?) -> Void) -> Void) {
        epoch = UUID(); self.available = available; self.send = send; active = true; confirmation = nil; issue = nil
    }
    func edit(_ value: String) {
        guard active, !sending else { return }
        guard value.utf8.count <= 16384 else { issue = "The draft is too large. Paste a smaller selection; no text was added."; return }
        text = value; issue = nil; confirmation = nil
    }
    func requestSend() {
        guard canSend else { return }
        guard available() else { invalidate(); return }
        guard let prepared = try? DirectComposedText(text, mode: mode) else { return }
        if prepared.needsConfirmation { confirmation = prepared }
        else { deliver(prepared) }
    }
    func confirmSend(_ reviewed: DirectComposedText? = nil) {
        guard active, !sending else { return }
        guard let reviewed = reviewed ?? confirmation else { return }
        confirmation = nil
        guard let current = try? DirectComposedText(text, mode: mode), current == reviewed else {
            issue = "The draft changed. Review it and tap Send Text again."; return
        }
        deliver(reviewed)
    }
    private func deliver(_ prepared: DirectComposedText) {
        guard canSend, available(), let send else { invalidate(); return }
        let token = epoch
        sending = true; issue = nil; sendingChanged?(true)
        send(prepared.text) { [weak self] error in
            guard let self, self.epoch == token, self.active else { return }
            self.sending = false; self.sendingChanged?(false)
            if let error { self.issue = error }
            else { self.text = ""; self.close?() }
        }
    }
    func invalidate() {
        if sending { interrupted?() }
        epoch = UUID(); text = ""; issue = nil; confirmation = nil; active = false; expanded = false
        sending = false; available = { false }; send = nil; sendingChanged?(false); close?()
    }
}

/// Owned by one native session controller; closing the sheet retains only its
/// unsent draft. No credentials, persistence, clipboard polling or global state.
@MainActor @objc(DirectTextComposer) final class DirectTextComposer: NSObject {
    let draft: DirectTextComposerDraft
    @objc var interruptionHandler: (() -> Void)?
    private weak var host: UIViewController?
    private var invalidating = false
    private var observers: [NSObjectProtocol] = []
    @objc init(macName: String, mode: String) {
        draft = DirectTextComposerDraft(macName: macName, mode: DirectControlMode(rawValue: mode) ?? .desktop)
        super.init()
        draft.close = { [weak self] in
            guard let self else { return }
            self.host?.dismiss(animated: !self.invalidating)
        }
        draft.sendingChanged = { [weak self] value in self?.host?.isModalInPresentation = value }
        draft.interrupted = { [weak self] in self?.interruptionHandler?() }
        observers = [NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.invalidate() }
        }, NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if !DirectAppLockV1.shared.canAccess { self?.invalidate() } }
        }]
        observeUnlock()
    }
    private func observeUnlock() {
        // canAccess short-circuits while app unlock is disabled. Track the stored
        // admission state so enabling unlock also retires a hidden draft.
        withObservationTracking { _ = DirectAppLockV1.shared.allowed } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if !DirectAppLockV1.shared.canAccess { self.invalidate() }
                self.observeUnlock()
            }
        }
    }
    isolated deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    @objc var sending: Bool { draft.sending }
    @objc func invalidate() {
        // Background/lock teardown must not leave a dismissing controller
        // blocking the first action on return.
        invalidating = true; draft.invalidate(); invalidating = false
    }
    @objc static func desktopEvents(_ text: String) -> [[String: Any]] {
        (try? DirectComposedText(text, mode: .desktop))?.desktopEvents ?? []
    }
    @objc func present(from controller: UIViewController, available: @escaping () -> Bool,
                       send: @escaping (String, @escaping (String?) -> Void) -> Void) {
        guard !draft.sending, DirectAppLockV1.shared.canAccess, available(), controller.presentedViewController == nil else { return }
        draft.configure(available: { DirectAppLockV1.shared.canAccess && DirectClientPlatformV1.sessionAvailable && available() }, send: send)
        let host = DirectTextComposerPanel(draft: draft)
        controller.definesPresentationContext = true
        host.modalPresentationStyle = .overCurrentContext
        host.modalTransitionStyle = .crossDissolve
        self.host = host
        controller.present(host, animated: true) { [weak self, weak host] in
            guard let self, let host, self.host === host else { return }
            // UIKit may defer a dismissal issued during its presentation
            // transition. Finish retired presentation before the next action.
            if !self.draft.active { host.dismiss(animated: false) }
        }
    }
}

/// The panel follows UIKit's real keyboard guide, so presenting the keyboard
/// cannot promote it to a full-screen sheet or scroll its delivery action away.
@MainActor final class DirectTextComposerPanel: UIViewController {
    let draft: DirectTextComposerDraft
    private var height: NSLayoutConstraint?
    private var peek: NSLayoutConstraint?
    private var editorHost: UIHostingController<AnyView>?
    private var sendBounds = CGRect.zero
    var deliveryActionFrame: CGRect { editorHost?.view.convert(sendBounds, to: view) ?? .zero }
    init(draft: DirectTextComposerDraft) { self.draft = draft; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear; view.accessibilityViewIsModal = true
        let backdrop = UIControl(); backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.12)
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addTarget(self, action: #selector(back), for: .touchUpInside)
        view.addSubview(backdrop)
        NSLayoutConstraint.activate([backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor), backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor), backdrop.topAnchor.constraint(equalTo: view.topAnchor), backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        let host = UIHostingController(rootView: AnyView(DirectTextComposerView(draft: draft, expand: { [weak self] in self?.toggleExpansion() }, reportSendBounds: { [weak self] in self?.sendBounds = $0 }).directAppearance()))
        editorHost = host; addChild(host); view.addSubview(host.view); host.didMove(toParent: self)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .secondarySystemBackground; host.view.layer.cornerRadius = 20; host.view.clipsToBounds = true
        host.view.accessibilityIdentifier = "compose-panel"
        let preferredHeight = host.view.heightAnchor.constraint(equalToConstant: 280); preferredHeight.priority = .defaultHigh; height = preferredHeight
        let peek = host.view.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 48); self.peek = peek
        NSLayoutConstraint.activate([
            host.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            host.view.widthAnchor.constraint(lessThanOrEqualToConstant: 640),
            host.view.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            host.view.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            host.view.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
            peek, preferredHeight
        ])
        let width = host.view.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, constant: -16); width.priority = .defaultHigh; width.isActive = true
    }
    @objc private func back() { if !draft.sending { draft.close?() } }
    func toggleExpansion() { draft.expanded.toggle(); view.setNeedsLayout() }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let room = view.keyboardLayoutGuide.layoutFrame.minY - view.safeAreaInsets.top
        let compact = room < 240
        if draft.compactLayout != compact { draft.compactLayout = compact }
        peek?.constant = compact ? 8 : 48
        let available = max(0, room - (compact ? 16 : 56))
        let accessibility = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        let desired: CGFloat = draft.expanded || accessibility ? available : (compact ? 144 : 280)
        let newHeight = min(available, desired)
        if height?.constant != newHeight { height?.constant = newHeight }
    }
}

private struct DirectTextComposerView: View {
    @Bindable var draft: DirectTextComposerDraft
    var expand: () -> Void
    var reportSendBounds: (CGRect) -> Void
    @FocusState private var editing: Bool
    @State private var discard = false
    @State private var showIssue = false
    private func confirmationMessage(_ reviewed: DirectComposedText) -> String {
        let explanation = draft.mode == .terminal
            ? "Without bracketed paste, line breaks can run commands and tabs can change terminal input."
            : "Line breaks press Return on your Mac and may submit content or run commands. Tabs press Tab and may change focus."
        return explanation + (reviewed.endsWithNewline ? " This draft ends with a line break." : "") + " Send Text adds no extra Return."
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
          if !draft.compactLayout {
            HStack {
                Button("Back", systemImage: "chevron.down") { editing = false; draft.close?() }
                    .labelStyle(.iconOnly).disabled(draft.sending).accessibilityLabel("Back to Session").accessibilityIdentifier("compose-back")
                Spacer()
                Text("Compose Text").font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Button(draft.expanded ? "Collapse" : "Expand", systemImage: draft.expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", action: expand)
                    .labelStyle(.iconOnly).accessibilityIdentifier("compose-expand")
            }
            Label(draft.macName + " · " + draft.mode.title, systemImage: draft.mode == .terminal ? "terminal" : "desktopcomputer")
                .font(.caption).foregroundStyle(.secondary).lineLimit(1).accessibilityIdentifier("compose-destination")
          }
            TextEditor(text: Binding(get: { draft.text }, set: draft.edit))
                .font(draft.mode == .terminal ? .body.monospaced() : .body)
                .frame(minHeight: 36, maxHeight: .infinity).padding(4)
                .background(.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.4)))
                .autocorrectionDisabled(draft.mode == .terminal).textInputAutocapitalization(draft.mode == .terminal ? .never : .sentences)
                .focused($editing).disabled(draft.sending)
                .accessibilityLabel(draft.compactLayout ? "Text to Send · " + draft.macName + " · " + draft.mode.title : "Text to Send")
                .accessibilityHint(draft.issue ?? draft.validationIssue ?? "")
                .accessibilityIdentifier("compose-text").privacySensitive()
            if !draft.compactLayout, let issue = draft.issue ?? (draft.text.isEmpty ? nil : draft.validationIssue) {
                Text(issue).font(.caption).foregroundStyle(.red).lineLimit(2).accessibilityIdentifier("compose-error")
            }
            HStack {
                if draft.compactLayout {
                    Button { editing = false; draft.close?() } label: {
                        Image(systemName: "chevron.down").font(.system(size: 20)).frame(width: 44, height: 44)
                    }.disabled(draft.sending).accessibilityLabel("Back to Session").accessibilityIdentifier("compose-back")
                    Button(role: .destructive) { discard = true } label: {
                        Image(systemName: "trash").font(.system(size: 20)).frame(width: 44, height: 44)
                    }.disabled(draft.text.isEmpty || draft.sending).accessibilityLabel("Discard Draft").accessibilityIdentifier("compose-discard")
                } else {
                    Button("Discard", role: .destructive) { discard = true }.font(.footnote)
                        .disabled(draft.text.isEmpty || draft.sending).accessibilityIdentifier("compose-discard")
                }
                Spacer()
                if draft.compactLayout, let issue = draft.issue ?? (draft.text.isEmpty ? nil : draft.validationIssue) {
                    Button { showIssue = true } label: {
                        Image(systemName: "exclamationmark.circle").font(.system(size: 20)).frame(width: 44, height: 44)
                    }.accessibilityLabel(issue).accessibilityIdentifier("compose-error")
                        .popover(isPresented: $showIssue) { Text(issue).padding().presentationCompactAdaptation(.popover) }
                }
                Button { draft.requestSend() } label: {
                    if draft.compactLayout {
                        Group {
                            if draft.sending { ProgressView() }
                            else { Image(systemName: "paperplane.fill").font(.system(size: 20)) }
                        }.frame(width: 20, height: 20)
                    } else {
                        HStack { if draft.sending { ProgressView() }; Text(draft.sending ? "Sending…" : "Send Text") }
                    }
                }.buttonStyle(.borderedProminent).frame(minWidth: 44, minHeight: 44)
                    .disabled(!draft.canSend).accessibilityLabel(draft.sending ? "Sending…" : "Send Text").accessibilityIdentifier("compose-send")
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("composer-panel")) } action: { reportSendBounds($0) }
            }

        }.padding(draft.compactLayout ? 8 : 12).background(.background).coordinateSpace(name: "composer-panel")
            .onAppear { editing = true }
            .alert("Send line breaks or tabs?", isPresented: Binding(get: { draft.confirmation != nil }, set: { if !$0 { draft.confirmation = nil } }), presenting: draft.confirmation) { reviewed in
                Button("Send Text") { draft.confirmSend(reviewed) }
                Button("Cancel", role: .cancel) { draft.confirmation = nil }
            } message: { reviewed in Text(confirmationMessage(reviewed)) }
            .confirmationDialog("Discard this draft?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { draft.invalidate() }
            }
            .onChange(of: DirectAppLockV1.shared.canAccess) { _, value in if !value { draft.invalidate() } }
    }
}
#endif
