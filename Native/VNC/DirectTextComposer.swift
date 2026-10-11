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
        epoch = UUID(); text = ""; issue = nil; confirmation = nil; active = false
        sending = false; available = { false }; send = nil; sendingChanged?(false); close?()
    }
}

/// Owned by one native session controller; closing the sheet retains only its
/// unsent draft. No credentials, persistence, clipboard polling or global state.
@MainActor @objc(DirectTextComposer) final class DirectTextComposer: NSObject {
    let draft: DirectTextComposerDraft
    @objc var interruptionHandler: (() -> Void)?
    private weak var host: UIViewController?
    private var observers: [NSObjectProtocol] = []
    @objc init(macName: String, mode: String) {
        draft = DirectTextComposerDraft(macName: macName, mode: DirectControlMode(rawValue: mode) ?? .desktop)
        super.init()
        draft.close = { [weak self] in self?.host?.dismiss(animated: true) }
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
    @objc func invalidate() { draft.invalidate() }
    @objc static func desktopEvents(_ text: String) -> [[String: Any]] {
        (try? DirectComposedText(text, mode: .desktop))?.desktopEvents ?? []
    }
    @objc func present(from controller: UIViewController, available: @escaping () -> Bool,
                       send: @escaping (String, @escaping (String?) -> Void) -> Void) {
        guard !draft.sending, DirectAppLockV1.shared.canAccess, available(), controller.presentedViewController == nil else { return }
        draft.configure(available: { DirectAppLockV1.shared.canAccess && DirectClientPlatformV1.sessionAvailable && available() }, send: send)
        let host = UIHostingController(rootView: DirectTextComposerView(draft: draft).directAppearance())
        host.modalPresentationStyle = .pageSheet
        host.sheetPresentationController?.detents = [.large()]
        self.host = host
        controller.present(host, animated: true)
    }
}

private struct DirectTextComposerView: View {
    @Bindable var draft: DirectTextComposerDraft
    @FocusState private var editing: Bool
    @State private var discard = false
    private func confirmationMessage(_ reviewed: DirectComposedText) -> String {
        let explanation = draft.mode == .terminal
            ? "Without bracketed paste, line breaks can run commands and tabs can change terminal input."
            : "Line breaks press Return on your Mac and may submit content or run commands. Tabs press Tab and may change focus."
        return explanation + (reviewed.endsWithNewline ? " This draft ends with a line break." : "") + " Send Text adds no extra Return."
    }
    var body: some View {
        NavigationStack {
            if draft.active {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Label(draft.macName + " · " + draft.mode.title, systemImage: draft.mode == .terminal ? "terminal" : "desktopcomputer")
                            .font(.headline).accessibilityIdentifier("compose-destination")
                        Text(draft.mode == .terminal ? "Send to this Terminal session." : "Types into whatever has focus on your Mac. Use Back to Session to choose the destination without losing your draft.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        TextEditor(text: Binding(get: { draft.text }, set: draft.edit))
                            .font(draft.mode == .terminal ? .body.monospaced() : .body)
                            .frame(minHeight: 200, maxHeight: 280).padding(6)
                            .background(.background, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.secondary.opacity(0.4)))
                            .autocorrectionDisabled(draft.mode == .terminal).textInputAutocapitalization(draft.mode == .terminal ? .never : .sentences)
                            .focused($editing).disabled(draft.sending)
                            .accessibilityLabel("Text to Send").accessibilityIdentifier("compose-text").privacySensitive()
                        Text("Use the editor’s Paste menu to add clipboard text. Nothing is sent while you edit.")
                            .font(.caption).foregroundStyle(.secondary)
                        if draft.mode == .terminal {
                            Text("Uses bracketed paste when requested by the remote program. Line breaks may run commands. Send Text adds no extra Return.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Line breaks press Return; tabs press Tab. Send Text adds no extra Return.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let issue = draft.issue ?? (draft.text.isEmpty ? nil : draft.validationIssue) {
                            Text(issue).foregroundStyle(.red).accessibilityIdentifier("compose-error")
                        }
                        Button { editing = false; draft.requestSend() } label: {
                            HStack { if draft.sending { ProgressView() }; Text(draft.sending ? "Sending…" : "Send Text") }
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }.buttonStyle(.borderedProminent).disabled(!draft.canSend).accessibilityIdentifier("compose-send")
                        Text("Temporary draft · Cleared when you leave the app or session")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(16)
                }.scrollDismissesKeyboard(.interactively)
                    .navigationTitle("Compose Text").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Back to Session") { editing = false; draft.close?() }.disabled(draft.sending)
                                .accessibilityIdentifier("compose-back")
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Discard", role: .destructive) { discard = true }.disabled(draft.text.isEmpty || draft.sending)
                                .accessibilityIdentifier("compose-discard")
                        }
                    }
                    .alert("Send line breaks or tabs?", isPresented: Binding(get: { draft.confirmation != nil }, set: { if !$0 { draft.confirmation = nil } }), presenting: draft.confirmation) { reviewed in
                        Button("Send Text") { draft.confirmSend(reviewed) }
                        Button("Cancel", role: .cancel) { draft.confirmation = nil }
                    } message: { reviewed in Text(confirmationMessage(reviewed)) }
                    .confirmationDialog("Discard this draft?", isPresented: $discard, titleVisibility: .visible) {
                        Button("Discard", role: .destructive) { draft.invalidate() }
                    }
                    .onChange(of: DirectAppLockV1.shared.canAccess) { _, value in if !value { draft.invalidate() } }
            } else { Color(uiColor: .systemBackground) }
        }
    }
}
#endif
