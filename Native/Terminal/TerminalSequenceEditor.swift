#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

struct TerminalSequenceEditor: View {
    @Binding var action: TerminalControlAction
    let edit: (TerminalShortcutStep) -> Void
    let add: (TerminalShortcutStep.Kind) -> Void
    var body: some View {
        Section {
            ForEach(action.steps ?? []) { step in
                HStack {
                    Button { edit(step) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: step.kind.symbol)
                            Text(step.label).foregroundStyle(.primary).lineLimit(2)
                        }.frame(minHeight: 44)
                    }.buttonStyle(.plain).accessibilityIdentifier("shortcut-step-" + step.id.uuidString)
                    Spacer(minLength: 8)
                    Menu {
                        Button("Duplicate", systemImage: "plus.square.on.square") {
                            guard let index = action.steps?.firstIndex(where: { $0.id == step.id }), (action.steps?.count ?? 0) < 32 else { return }
                            var copy = step; copy.id = UUID(); action.steps?.insert(copy, at: index + 1)
                        }
                        Button("Remove", systemImage: "trash", role: .destructive) { action.steps?.removeAll { $0.id == step.id } }
                    } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }
                    .buttonStyle(.borderless).accessibilityLabel("Options for " + step.label)
                }
            }.onMove { source, destination in action.steps?.move(fromOffsets: source, toOffset: destination) }
            Menu {
                Button("Return", systemImage: "return") { action.appendShortcutStep(.init(character: 0xff0d)) }
                    .accessibilityIdentifier("shortcut-add-return")
                Divider()
                ForEach(TerminalShortcutStep.Kind.allCases, id: \.self) { kind in
                    Button(kind.title + "…", systemImage: kind.symbol) { add(kind) }
                        .accessibilityIdentifier("shortcut-add-" + kind.rawValue)
                }
            } label: {
                Label("Add Step", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(.rect)
            }
                .buttonStyle(.borderless).menuOrder(.fixed).disabled((action.steps?.count ?? 0) >= 32).accessibilityIdentifier("shortcut-add-step")
        } header: { Text("Steps · \(action.steps?.count ?? 0) of 32") }
        footer: {
            Text("Drag to reorder. Add Return explicitly when needed. Enable Confirm Before Running below to review the shortcut before it runs.")
            if action.resolvedSteps.reduce(0, { $0 + ($1.waitMilliseconds ?? 0) }) > 60_000 {
                Text("Keep the total wait time within 60 seconds.").foregroundStyle(.red)
            } else if !action.resolvedSteps.isEmpty && action.resolvedSteps.allSatisfy({ $0.kind == .wait }) {
                Text("Add a key or text step to this shortcut.").foregroundStyle(.secondary)
            }
        }
        Section("Preview") { TerminalSequencePreview(action: action) }
    }
}

struct TerminalSequenceStepEditor: View {
    @State var step: TerminalShortcutStep
    var allowsCommand: Bool
    var creating: Bool
    let apply: (TerminalShortcutStep) -> Void
    @Environment(\.dismiss) private var dismiss
    private var chord: Binding<TerminalControlAction> {
        Binding(get: {
            var value = TerminalControlAction(title: "Step", kind: .shortcut)
            value.character = step.character; value.modifiers = step.modifiers; return value
        }, set: { step.character = $0.character; step.modifiers = $0.modifiers })
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Step Type", selection: Binding(get: { step.kind }, set: { kind in
                        if step.kind != kind {
                            if step.isText && (kind == .typeText || kind == .text) { step.kind = kind }
                            else { step = .init(id: step.id, kind: kind, waitMilliseconds: kind == .wait ? 1000 : nil) }
                        }
                    })) {
                        ForEach(TerminalShortcutStep.Kind.allCases, id: \.self) { kind in Label(kind.title, systemImage: kind.symbol).tag(kind) }
                    }.pickerStyle(.menu).accessibilityIdentifier("shortcut-step-type")
                }
                if step.kind == .key { Section("Key Combination") { TerminalShortcutCombination(action: chord, allowsCommand: allowsCommand) } }
                else if step.kind == .wait {
                    Section {
                        Stepper(value: Binding(get: { step.waitMilliseconds ?? 1000 }, set: { step.waitMilliseconds = $0 }), in: 100...30_000, step: 100) {
                            LabeledContent("Duration", value: (Double(step.waitMilliseconds ?? 1000) / 1000).formatted(.number.precision(.fractionLength(1))) + " seconds")
                        }.accessibilityIdentifier("shortcut-wait-duration")
                    } footer: { Text("Pauses before the next step. Cancel stops the remaining steps. Locking, leaving the app or disconnecting also stops the shortcut.") }
                }
                else { Section {
                    TextEditor(text: $step.text).frame(minHeight: 150).font(.body.monospaced()).autocorrectionDisabled().directNoAutocapitalization()
                        .accessibilityIdentifier("shortcut-step-text")
                } header: { Text(step.kind.title) } footer: {
                    Text(step.kind == .typeText ? "Types characters as keys, without paste formatting. Add Return or Tab as Press Key steps." : "Pastes text using the terminal’s paste mode. No Return is added.")
                    if step.kind == .typeText && step.hasTypingSeparators {
                        Text("Add Return and Tab as separate Press Key steps.").foregroundStyle(.red)
                    }
                } }
            }.navigationTitle(creating ? "Add Step" : "Edit Step").directInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(creating ? "Add" : "Done") { apply(step) }
                        .buttonStyle(.borderedProminent).disabled(!step.valid).accessibilityIdentifier("shortcut-step-save") }
                }
        }.privacySensitive().presentationSizing(.page)
    }
}

struct TerminalSequencePreview: View {
    let action: TerminalControlAction
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(action.resolvedSteps.enumerated()), id: \.offset) { index, step in
                    if index > 0 { Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary) }
                    Text(step.label).font(.body.monospaced().weight(.medium)).foregroundStyle(.tint)
                        .padding(.horizontal, 10).frame(minWidth: 44, minHeight: 44)
                        .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 8))
                }
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel(action.sequencePreview).accessibilityIdentifier("shortcut-sequence-preview")
    }
}

struct TerminalSequenceReview: View {
    let action: TerminalControlAction
    var allowsConnectionSkip = true
    let send: (Bool) -> Void
    let cancel: () -> Void
    @State private var skipForConnection = false
    var body: some View {
        NavigationStack {
            List {
                Section { Text(action.title).font(.headline); Text("Review every step before sending. Text and line breaks can run commands. Return is sent only where shown.") }
                ForEach(Array(action.resolvedSteps.enumerated()), id: \.offset) { index, step in
                    Section("Step \(index + 1) · " + step.kind.title) {
                        Text(step.isText ? ((try? DirectComposedText(step.text, mode: .terminal))?.text ?? step.text) : step.label).font(.body.monospaced()).textSelection(.enabled)
                    }
                }
                if allowsConnectionSkip {
                    Section {
                        Toggle("Don’t ask again for this connection", isOn: $skipForConnection)
                            .accessibilityIdentifier("shortcut-skip-connection-confirmation")
                    } footer: { Text("Applies to this shortcut until a new connection starts or its steps change.") }
                }
            }.navigationTitle("Review Shortcut").directInlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
                    ToolbarItem(placement: .confirmationAction) { Button("Run") { send(skipForConnection) }.buttonStyle(.borderedProminent).accessibilityLabel("Run Shortcut").accessibilityIdentifier("shortcut-sequence-send") }
                }
        }.privacySensitive().interactiveDismissDisabled().directAppearance()
    }
}

@MainActor @Observable final class TerminalSequenceProgress {
    let action: TerminalControlAction
    var index = 0
    var cancelled = false
    private var waitEndsAt: Date?
    private let batching: Bool
    init(action: TerminalControlAction, batching: Bool = false) { self.action = action; self.batching = batching; move(to: 0) }
    func move(to index: Int) {
        self.index = index
        waitEndsAt = action.resolvedSteps[index].waitMilliseconds.map { Date.now.addingTimeInterval(Double($0) / 1000) }
    }
    // Only earlier steps have completed. A wait's duration is not an estimate
    // of the shortcut's total duration, and batched writes have no step receipt.
    var completedStepFraction: Double? { batching ? nil : Double(index) / Double(action.resolvedSteps.count) }
    var symbol: String { batching ? "paperplane" : action.resolvedSteps[index].kind == .wait ? "hourglass" : action.resolvedSteps[index].kind.symbol }
    func status(at date: Date, compact: Bool = false) -> String {
        if batching { return "Sending · \(action.resolvedSteps.count) steps" }
        let step = action.resolvedSteps[index]
        if compact {
            let detail = waitEndsAt.map { "Wait · \(max(0, Int(ceil($0.timeIntervalSince(date))))) s" } ?? step.label
            return "\(index + 1)/\(action.resolvedSteps.count) · " + detail
        }
        let detail = waitEndsAt.map { "Wait · \(max(0, Int(ceil($0.timeIntervalSince(date))))) s remaining" } ?? step.label
        return "Step \(index + 1) of \(action.resolvedSteps.count) · " + detail
    }
}

struct TerminalSequenceRunning: View {
    let progress: TerminalSequenceProgress
    let cancel: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    private var cancelButton: some View {
        Button(role: .cancel, action: cancel) {
            Text("Cancel").fixedSize(horizontal: true, vertical: true)
                .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : nil)
                .padding(.horizontal, 10).frame(minHeight: 44)
                .background(Color(uiColor: .systemBackground)).contentShape(.rect)
        }.buttonStyle(.plain).foregroundStyle(.tint)
            .accessibilityLabel("Cancel Shortcut")
            .accessibilityIdentifier("shortcut-running-cancel")
    }
    private var status: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(progress.action.title).font(.subheadline.weight(.semibold)).lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                .accessibilityIdentifier("shortcut-running-title")
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(progress.status(at: context.date, compact: !typeSize.isAccessibilitySize)).font(.caption).foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .accessibilityLabel(progress.status(at: context.date))
                    .accessibilityIdentifier("shortcut-running-step")
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var content: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    ScrollView { status }.scrollIndicators(.hidden)
                    cancelButton.frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: progress.symbol).font(.body).foregroundStyle(.tint).frame(width: 22).accessibilityHidden(true)
                    status
                    cancelButton
                }
            }
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }
    var body: some View {
        ZStack(alignment: .top) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let fraction = progress.completedStepFraction {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Color.accentColor.opacity(0.12)
                        Color.accentColor.frame(width: geometry.size.width * fraction)
                    }
                }.frame(height: 2).allowsHitTesting(false).accessibilityHidden(true)
            }
        }.background(Color(uiColor: .systemBackground)).privacySensitive().accessibilityElement(children: .contain)
            .accessibilityIdentifier("shortcut-execution-overlay")
    }
}

/// Temporary presentation only: no input epoch, transport or saved preference changes.
@MainActor final class TerminalSequenceKeyboard {
    private let visible: () -> Bool
    private let current: () -> Bool
    private let hide: () -> Bool
    private let restore: () -> Void
    private var pending: Task<Void, Never>?
    private var closed = false
    private(set) var didHide = false
    init(visible: @escaping () -> Bool, current: @escaping () -> Bool,
         hide: @escaping () -> Bool, restore: @escaping () -> Void) {
        self.visible = visible; self.current = current; self.hide = hide; self.restore = restore
    }
    func start(delay: Duration = .milliseconds(500)) {
        guard !closed, pending == nil else { return }
        // Evaluate visibility at the deadline: a preceding Cancel may still
        // be animating its keyboard back when this run is accepted.
        pending = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, !closed, current(), visible() else { return }
            didHide = hide()
        }
    }
    func finish(restoring: Bool = true) {
        guard !closed else { return }; closed = true; pending?.cancel(); pending = nil
        let shouldRestore = restoring && didHide && current() && !visible()
        didHide = false
        if shouldRestore { restore() }
    }
    isolated deinit { pending?.cancel() }
    static func softwareVisible(in view: UIView, responder: UIResponder) -> Bool {
        guard responder.isFirstResponder, let window = view.window else { return false }
        // SwiftUI can already shrink the owner's safe area to the keyboard.
        // Compare its guide in window space, not against that reduced safe area.
        let top = view.convert(CGPoint(x: 0, y: view.keyboardLayoutGuide.layoutFrame.minY), to: window).y
        return top < window.bounds.maxY - window.safeAreaInsets.bottom - 100
    }
    static func presentationCurrent(in owner: UIViewController, responder: UIResponder) -> Bool {
        func focused(_ view: UIView) -> UIView? {
            if view.isFirstResponder { return view }
            return view.subviews.lazy.compactMap { focused($0) }.first
        }
        guard UIApplication.shared.applicationState == .active, owner.view.window != nil,
              owner.presentedViewController == nil, !owner.isBeingDismissed, !owner.isMovingFromParent else { return false }
        return focused(owner.view).map { $0 === responder } ?? true
    }
}

/// Blocks input immediately, then replaces the rows with a solid dock. Delayed
/// presentation avoids resizing or flashing for quick, non-wait shortcuts.
@MainActor final class TerminalSequenceBannerController: UIViewController {
    let rootView: TerminalSequenceRunning
    private var content: UIHostingController<TerminalSequenceRunning>?
    private weak var bar: TerminalKeyboardBar?
    private var blocked: [(UIView, Bool, Bool, CGFloat)] = []
    private var presentation: Task<Void, Never>?
    private let keyboard: TerminalSequenceKeyboard?
    private var closed = false
    private(set) var progressVisible = false
    init(progress: TerminalSequenceProgress, keyboard: TerminalSequenceKeyboard? = nil, cancel: @escaping () -> Void) {
        self.keyboard = keyboard
        rootView = TerminalSequenceRunning(progress: progress, cancel: cancel)
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func loadView() {
        view = UIView(); view.backgroundColor = .clear
        view.accessibilityIdentifier = "shortcut-execution-blocker"

    }
    func attach(to owner: UIViewController, covering bar: TerminalKeyboardBar, blocking otherViews: [UIView] = [], delay: Duration = .milliseconds(180)) {
        self.bar = bar
        blocked = ([bar] + otherViews).map { ($0, $0.isUserInteractionEnabled, $0.accessibilityElementsHidden, $0.alpha) }
        for (view, _, _, _) in blocked { view.isUserInteractionEnabled = false; view.accessibilityElementsHidden = true }
        bar.executionActive = true
        owner.addChild(self); view.translatesAutoresizingMaskIntoConstraints = false; owner.view.addSubview(view)
        NSLayoutConstraint.activate([view.leadingAnchor.constraint(equalTo: bar.leadingAnchor), view.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
                                     view.topAnchor.constraint(equalTo: bar.topAnchor), view.bottomAnchor.constraint(equalTo: bar.bottomAnchor)])
        didMove(toParent: owner)
        keyboard?.start()
        presentation = Task { [weak self, weak owner] in
            do { try await Task.sleep(for: delay) } catch { return }
            guard let self, !closed, let bar = self.bar, let owner else { return }
            view.backgroundColor = .systemBackground
            // Sibling floating controls must not remain visible outside the
            // smaller dock. Alpha survives keyboard-driven visibility updates.
            for (other, _, _, _) in blocked where other !== bar { other.alpha = 0 }
            // Fast shortcuts never construct the SwiftUI graph or change height.
            let hosted = UIHostingController(rootView: rootView); hosted.safeAreaRegions = []; content = hosted
            addChild(hosted); hosted.view.translatesAutoresizingMaskIntoConstraints = false; hosted.view.backgroundColor = .clear
            view.addSubview(hosted.view)
            NSLayoutConstraint.activate([hosted.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), hosted.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                                         hosted.view.topAnchor.constraint(equalTo: view.topAnchor), hosted.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
            hosted.didMove(toParent: self); progressVisible = true
            updateProgressHeight(); owner.view.setNeedsLayout()
        }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews(); updateProgressHeight()
    }
    private func updateProgressHeight() {
        guard progressVisible, !closed, let bar, let owner = parent else { return }
        let title = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: bar.traitCollection)
        let detail = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: bar.traitCollection)
        let cancel = UIFont.preferredFont(forTextStyle: .body, compatibleWith: bar.traitCollection)
        let desired = bar.traitCollection.preferredContentSizeCategory.isAccessibilityCategory
            ? ceil(title.lineHeight * 2 + detail.lineHeight * 3 + max(44, cancel.lineHeight) + 28)
            : max(64, ceil(title.lineHeight + detail.lineHeight + 22))
        let bottom = bar.convert(bar.bounds, to: owner.view).maxY
        let available = max(64, bottom - owner.view.safeAreaLayoutGuide.layoutFrame.minY - 4)
        let height = min(desired, available)
        if abs(bar.executionToolbarHeight - height) > 0.5 { bar.executionToolbarHeight = height }
    }
    func close(restoreKeyboard: Bool = true) {
        guard !closed else { return }; closed = true; presentation?.cancel(); presentation = nil
        bar?.executionActive = false; bar?.executionToolbarHeight = 0
        for (view, interaction, accessibility, alpha) in blocked { view.isUserInteractionEnabled = interaction; view.accessibilityElementsHidden = accessibility; view.alpha = alpha }
        blocked = []
        content?.willMove(toParent: nil); content?.view.removeFromSuperview(); content?.removeFromParent(); content = nil
        willMove(toParent: nil); view.removeFromSuperview(); removeFromParent()
        keyboard?.finish(restoring: restoreKeyboard)
    }
}
#endif
