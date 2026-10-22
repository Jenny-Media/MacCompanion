#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

/// Compact editor chrome remains usable at large accessibility sizes. Labels
/// remain available to VoiceOver; the editable keycaps retain their own scaling.
struct TerminalEditorToolbarStyle: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize
    @ViewBuilder func body(content: Content) -> some View {
        if typeSize > .xLarge {
            content.labelStyle(.iconOnly).font(.system(size: 22)).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        } else { content.font(.subheadline) }
    }
}

struct TerminalEditingBackdrop: View {
    var image: UIImage?
    var title = "Keyboard Preview"
    var showsGuidance = true
    var body: some View {
        GeometryReader { geometry in
            if let image {
                Image(uiImage: image).resizable().scaledToFit().frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading).clipped().accessibilityHidden(true)
            } else if showsGuidance {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(title, systemImage: "terminal").font(.headline)
                        Text("Arrange your controls below. Changes apply to every Mac on this device.").font(.subheadline).foregroundStyle(.secondary)
                    }.fixedSize(horizontal: false, vertical: true).padding(20).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }.background(Color(uiColor: .systemBackground))
    }
}

/// A separate, disposable preview never receives a session or a profile binding.
/// UIKit owns the keyboard/accessory join, so editor chrome cannot separate them.
struct TerminalDockedKeyboardPreview: View {
    let profile: TerminalControlsProfile
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                TerminalDockedKeyboardHost(profile: profile)
                Text("Preview only. Nothing is sent to your Mac.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(24).allowsHitTesting(false)
            }.navigationTitle("Keyboard Preview").directInlineNavigationTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() } } }
        }
    }
}

private struct TerminalDockedKeyboardHost: UIViewControllerRepresentable {
    let profile: TerminalControlsProfile
    func makeUIViewController(context: Context) -> TerminalDockedKeyboardController { .init(profile: profile) }
    func updateUIViewController(_ controller: TerminalDockedKeyboardController, context: Context) {}
    static func dismantleUIViewController(_ controller: TerminalDockedKeyboardController, coordinator: ()) { controller.stop() }
}

private final class TerminalPreviewAccessory: UIInputView {
    let bar = TerminalKeyboardBar(terminal: nil, preferences: .init())
    override init(frame: CGRect, inputViewStyle: UIInputView.Style) {
        super.init(frame: frame, inputViewStyle: inputViewStyle)
        allowsSelfSizing = true
        backgroundColor = .secondarySystemBackground
        bar.editingPreview = true; bar.presentationPreview = true
        bar.translatesAutoresizingMaskIntoConstraints = true
        bar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(bar)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { .init(width: UIView.noIntrinsicMetric, height: bar.height) }
    override func layoutSubviews() {
        super.layoutSubviews()
        bar.frame = bounds; bar.layoutRows()
    }
    func configure(_ profile: TerminalControlsProfile) {
        bar.configure(profile) { _ in }
        frame.size.height = bar.height
        invalidateIntrinsicContentSize(); setNeedsLayout()
    }
}

private final class TerminalPreviewInputField: UITextField {
    override func insertText(_ text: String) {}
    override func setMarkedText(_ markedText: String?, selectedRange: NSRange) {}
}

private final class TerminalDockedKeyboardController: UIViewController, UITextFieldDelegate {
    private var profile: TerminalControlsProfile
    private let field = TerminalPreviewInputField()
    private let accessory = TerminalPreviewAccessory(frame: .zero, inputViewStyle: .keyboard)
    init(profile: TerminalControlsProfile) { self.profile = profile; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        field.frame = .init(x: 0, y: 0, width: 1, height: 1)
        field.isAccessibilityElement = false; field.tintColor = .clear; field.textColor = .clear
        field.autocorrectionType = .no; field.autocapitalizationType = .none
        field.spellCheckingType = .no; field.delegate = self
        field.inputAssistantItem.leadingBarButtonGroups = []; field.inputAssistantItem.trailingBarButtonGroups = []
        field.inputAccessoryView = accessory; view.addSubview(field)
        accessory.bar.previewSelect = { [weak self] item, _ in
            guard let self, item == .control(.expand) else { return }
            profile.rowsExpanded = !(profile.rowsExpanded ?? false)
            accessory.configure(profile); field.reloadInputViews()
        }
        accessory.configure(profile)
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); field.becomeFirstResponder() }
    override func viewWillDisappear(_ animated: Bool) { stop(); super.viewWillDisappear(animated) }
    func stop() { field.resignFirstResponder(); field.text = nil }
    // Neither software keyboard input, dictation nor hardware keys are stored.
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool { false }
    func textFieldShouldReturn(_ textField: UITextField) -> Bool { false }
}

struct TerminalRowTemplate: View {
    let profile: TerminalControlsProfile
    let preset: TerminalRowPreset
    let arranging: Bool
    var dragBegan: (() -> Void)? = nil
    let add: () -> Void
    private var available: [TerminalBarItem] { profile.availableItems(for: preset) }
    private var canAdd: Bool { profile.resolvedRows.count < TerminalControlsProfile.maximumKeyboardRows && (preset == .blank || !available.isEmpty) }
    private var template: TerminalControlsProfile {
        var result = TerminalControlsProfile()
        // A template is a render value, not a newly saved profile on each pass.
        result.revision = TerminalKeyboardRow.mainID
        result.keyboardRows = [.init(id: TerminalKeyboardRow.mainID, kind: .custom, title: preset.rawValue, items: preset.items, preset: preset, expandedOnly: false)]
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(preset.rawValue).font(.subheadline.weight(.semibold))
                Spacer()
                Text(preset == .blank ? "Start empty" : available.isEmpty ? "All keys placed" : "\(available.count) new keys")
                    .font(.caption).foregroundStyle(.secondary)
            }.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            TerminalKeyboardBarPreview(profile: template, allRows: true, handles: true, preset: preset,
                unavailable: Set(preset.items).subtracting(available), canAddPreset: canAdd,
                addPreset: { _, _ in add() }, catalogDragBegan: dragBegan)
                .accessibilityIdentifier("terminal-row-template-" + preset.id)
                .disabled(!arranging)
                .allowsHitTesting(arranging)
        }.padding(.vertical, 4)
    }
}

/// Row controls belong to the row's own handle; they are also tap alternatives
/// to every row drag. Changes remain in the parent draft until Save.
struct TerminalKeyboardRowOptions: View {
    @Binding var profile: TerminalControlsProfile
    let rowID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var restoring = false
    private var row: TerminalKeyboardRow? { profile.resolvedRows.first { $0.id == rowID } }
    private func edit(_ change: (inout TerminalKeyboardRow) -> Void) {
        var rows = profile.resolvedRows
        if let index = rows.firstIndex(where: { $0.id == rowID }) { change(&rows[index]); profile.keyboardRows = rows }
    }
    var body: some View {
        NavigationStack {
            Form {
                if let row {
                    Section {
                        Text(profile.rowTitle(row.id)).font(.headline)
                        Picker("Alignment", selection: Binding(get: { self.row?.resolvedAlignment ?? .left }, set: { value in edit { $0.alignment = value } })) {
                            ForEach(TerminalKeyboardRow.Alignment.allCases, id: \.self) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                        }
                        Picker("Scroll Start", selection: Binding(get: { self.row?.scrollStart ?? .automatic }, set: { value in edit { $0.scrollStart = value } })) {
                            ForEach(TerminalKeyboardRow.ScrollStart.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        if row.kind != .main {
                            Picker("Visibility", selection: Binding(get: { self.row?.visibility ?? .always }, set: { value in edit { $0.visibility = value } })) {
                                ForEach(TerminalKeyboardRow.Visibility.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                        } else { Text("This row is always visible.").foregroundStyle(.secondary) }
                    }
                    Section("Position") {
                        Button("Move Row Up", systemImage: "arrow.up") { profile.moveRow(rowID, offset: -1) }
                            .disabled(profile.resolvedRows.first?.id == rowID)
                        Button("Move Row Down", systemImage: "arrow.down") { profile.moveRow(rowID, offset: 1) }
                            .disabled(profile.resolvedRows.last?.id == rowID)
                    }
                    Section {
                        Button("Restore This Row", systemImage: "arrow.counterclockwise") { restoring = true }.accessibilityIdentifier("terminal-restore-row")
                        if row.kind != .main {
                            Button("Remove Row", systemImage: "minus.circle", role: .destructive) { profile.removeRow(rowID); dismiss() }
                        }
                    } footer: { Text("Removing a row keeps its saved shortcuts, text and floating-menu favorites.") }
                }
            }.navigationTitle("Row Settings").directInlineNavigationTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.medium, .large])
            .confirmationDialog("Restore this row’s starting layout?", isPresented: $restoring, titleVisibility: .visible) {
                Button("Restore Layout") { profile.restoreRow(rowID) }
            } message: { Text("Keys already placed in other rows stay there. Saved items are kept.") }
    }
}

struct TerminalKeyboardBarPreview: UIViewRepresentable {
    struct Configuration: Equatable {
        let profile: TerminalControlsProfile
        let selected: TerminalBarItem?
        let row: UUID?
        let allRows: Bool
        let handles: Bool
        let rowAdditions: Bool
        let rowMenu: Bool
        let preset: TerminalRowPreset?
        let unavailable: Set<TerminalBarItem>
        let canAdd: Bool
        let enabled: Bool
        let textSize: DynamicTypeSize
    }
    final class Coordinator { var configuration: Configuration? }
    let profile: TerminalControlsProfile
    var selected: TerminalBarItem? = nil
    var row: UUID? = nil
    var allRows = false
    var handles = false
    var preset: TerminalRowPreset? = nil
    var unavailable: Set<TerminalBarItem> = []
    var canAddPreset = true
    var select: ((TerminalBarItem?, UUID) -> Void)? = nil
    var move: ((TerminalBarItem, UUID, UUID, TerminalBarItem?) -> Void)? = nil
    var remove: ((TerminalBarItem, UUID) -> Void)? = nil
    var selectRow: ((UUID) -> Void)? = nil
    var moveRow: ((UUID, UUID?) -> Void)? = nil
    var addPreset: ((TerminalRowPreset, UUID?) -> Void)? = nil
    var addItem: ((TerminalBarItem, UUID, TerminalBarItem?) -> Void)? = nil
    var catalogDragBegan: (() -> Void)? = nil
    var addToRow: ((UUID) -> Void)? = nil
    var rowAction: ((UUID, TerminalKeyboardRow.MenuAction) -> Void)? = nil
    var placementSelect: ((TerminalBarPlacement, UUID) -> Void)? = nil
    var placementMove: ((String, UUID, UUID, String?) -> Void)? = nil
    var placementRemove: ((String, UUID) -> Void)? = nil
    var placementAdd: ((TerminalBarItem, UUID, String?) -> Void)? = nil
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> TerminalKeyboardBar {
        let bar = TerminalKeyboardBar(terminal: nil, preferences: .init()); bar.editingPreview = true; return bar
    }
    func updateUIView(_ bar: TerminalKeyboardBar, context: Context) {
        let enabled = context.environment.isEnabled
        bar.isUserInteractionEnabled = enabled
        bar.selectedPreviewItem = selected; bar.selectedPreviewRow = row
        bar.previewShowsAllRows = allRows; bar.previewShowsRowHandles = handles; bar.previewPreset = preset
        bar.previewUnavailableItems = unavailable; bar.previewCanAddPreset = canAddPreset
        bar.previewPlacementSelect = enabled ? placementSelect : nil
        bar.previewPlacementMove = enabled ? placementMove : nil
        bar.previewPlacementRemove = enabled ? placementRemove : nil
        bar.previewPlacementAdd = enabled ? placementAdd : nil
        bar.previewSelect = enabled ? select : nil; bar.previewMove = enabled ? move : nil; bar.previewRemove = enabled ? remove : nil
        bar.previewSelectRow = enabled ? selectRow : nil; bar.previewMoveRow = enabled ? moveRow : nil
        bar.previewAddToRow = enabled ? addToRow : nil
        bar.previewRowAction = enabled ? rowAction : nil
        bar.previewAddPreset = enabled ? addPreset : nil; bar.previewAddItem = enabled ? addItem : nil
        bar.previewCatalogDragBegan = enabled ? catalogDragBegan : nil
        let configuration = Configuration(profile: profile, selected: selected, row: row, allRows: allRows, handles: handles, rowAdditions: addToRow != nil, rowMenu: rowAction != nil,
            preset: preset, unavailable: unavailable, canAdd: canAddPreset, enabled: enabled, textSize: context.environment.dynamicTypeSize)
        guard context.coordinator.configuration != configuration else { return }
        // UIKit invalidates intrinsic size during configuration. Rebuilding on
        // every SwiftUI layout pass creates a feedback loop and also destroys
        // the source/drop views during an active drag.
        context.coordinator.configuration = configuration
        bar.configure(profile) { _ in }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: TerminalKeyboardBar, context: Context) -> CGSize? {
        .init(width: proposal.width ?? 360, height: uiView.height)
    }
}
#endif
