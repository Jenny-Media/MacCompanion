#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import SwiftUI

/// Presentation adapter only. The VNC viewer retains admission and transport.
@MainActor final class TerminalRemoteInput {
    var ready: () -> Bool = { false }
    var state: () -> TerminalKeyboardState = { .init() }
    var toggle: (TerminalModifiers, Bool) -> Void = { _, _ in }
    var send: (TerminalPaletteKey) -> Void = { _ in }
    var toggleKeyboard: () -> Void = {}
    var canUse: (TerminalControlAction) -> Bool = { _ in true }
}

@MainActor @objc final class RemoteMacControls: NSObject {
    private weak var viewer: CompanionVNCViewer?
    let keyboardBar = TerminalKeyboardBar(terminal: nil, preferences: .init())
    private var state = TerminalKeyboardState()
    private var profile = TerminalControlsProfile.remoteDefaults
    private var readable = false
    private var inputGeneration = UUID()
    private var customizing = false
    private let store: TerminalControlsStore
    private var activeStore: TerminalControlsStore {
        var scoped = store; scoped.remoteMode = viewer?.inputOnly == true ? .trackpad : .desktop; return scoped
    }
    private var observation: NSObjectProtocol?
    private weak var panel: UIViewController?
    private var keypad: TerminalKeypadState?
    @objc var bar: UIView { keyboardBar }
    @objc var menuAnchor: UIView { keyboardBar.menuAnchor }
    @objc func layoutRows() { keyboardBar.layoutIfNeeded(); keyboardBar.layoutRows() }
    @objc var keyboardButton: UIButton { keyboardBar.keyboardButton }
    @objc var modifierButtons: [UIButton] { keyboardBar.renderedModifiers }
    @objc static var navigationItems: [[String: Any]] { TerminalControlNavigation.items(for: .remoteMac) }
    @objc func setInterfaceFeedback(_ feedback: CompanionVNCInterfaceFeedback) { keyboardBar.keyFeedback = feedback }

    @objc convenience init(viewer: CompanionVNCViewer) {
        self.init(viewer: viewer, store: .remoteMac(legacyMac: viewer.preferenceID.flatMap(UUID.init(uuidString:))))
    }
    init(viewer: CompanionVNCViewer, store: TerminalControlsStore) {
        self.viewer = viewer; self.store = store
        super.init()
        keyboardBar.keyFeedback = viewer.controlsFeedback
        let input = TerminalRemoteInput()
        input.ready = { [weak self] in self?.ready == true }
        input.state = { [weak self] in self?.state ?? .init() }
        input.toggle = { [weak self] modifier, lock in self?.state.toggle(modifier, lock: lock) }
        input.send = { [weak self] key in self?.sendPalette(key) }
        input.toggleKeyboard = { [weak viewer] in viewer?.toggleControlsKeyboard() }
        input.canUse = { [weak self] action in self?.canUse(action) == true }
        keyboardBar.remoteInput = input
        keyboardBar.openKeypad = { [weak self] _ in self?.showKeypad() }
        keyboardBar.layoutChanged = { [weak self, weak viewer] in
            guard let self else { return }
            if readable, DirectProAccess.shared.hasPro, var saved = try? activeStore.load() {
                saved.rowsExpanded = keyboardBar.showsExtraRows; _ = try? activeStore.save(saved)
            }
            viewer?.view.setNeedsLayout()
        }
        observation = NotificationCenter.default.addObserver(forName: TerminalControlsStore.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        reload()
    }
    isolated deinit { if let observation { NotificationCenter.default.removeObserver(observation) } }
    private var ready: Bool { viewer?.controlsInputAvailable() == true && DirectAppLockV1.shared.canAccess }
    private func canUse(_ action: TerminalControlAction) -> Bool {
        action.isLocalKeyboardControl || ready && !(action.operation?.requiresScreen == true && viewer?.inputOnly == true)
            && (action.operation != .copyScreenText || viewer?.controlsCopyTextAvailable() == true)
    }
    @objc func reload() {
        do { profile = try activeStore.load(); readable = true }
        catch { readable = false; profile = .remoteDefaults }
        keyboardBar.configure(profile) { [weak self] in self?.use($0) }
        keyboardBar.showsExtraRows = profile.rowsExpanded ?? false
        refresh()
        viewer?.refreshControlsMenu()
    }
    @objc func refresh() {
        keyboardBar.refresh()
        keypad?.ready = ready && keypad?.ready == true
        keypad?.armed = state.armed; keypad?.locked = state.locked
    }
    /// Composer handoffs clear local modifiers without retiring their admission.
    @objc func clearModifiers() { state.reset(); refresh() }
    @objc func reset() {
        inputGeneration = UUID()
        if customizing { customizing = false; viewer?.endKeyboardCustomization() }
        keypad?.ready = false; keypad = nil
        if let panel, viewer?.presentedViewController === panel { viewer?.dismiss(animated: false) }
        panel = nil; clearModifiers()
    }
    @objc func keyboardFocused(_ focused: Bool) { keyboardBar.setKeyboardFocused(focused) }
    private func modifiers(_ flags: TerminalModifiers) -> [UInt32] {
        [(TerminalModifiers.shift, UInt32(0xffe1)), (.ctrl, 0xffe3), (.alt, 0xffe9), (.command, 0xffeb)].compactMap { flags.contains($0.0) ? $0.1 : nil }
    }
    @discardableResult private func admit(_ events: [[String: Any]]) -> Bool {
        guard ready, let viewer else { return false }
        return viewer.sendControlEvents(events) { _ in }
    }
    private func sendPalette(_ key: TerminalPaletteKey) {
        guard ready else { return }
        let current = state
        let step = TerminalShortcutStep(character: key.shortcutCode, modifiers: Array(Set(modifiers(state.active) + key.modifiers)).sorted())
        if admit(step.remoteEvents) { _ = state.consume(); keyboardBar.keyFeedback.feedback("key") }
        else { state = current }
        refresh()
    }
    @objc func typeText(_ text: String) {
        guard ready else { return }
        for scalar in text.unicodeScalars {
            let keyboard = CompanionVNCKeyboard { [weak self] events in
                guard let self, let viewer, ready else { return }
                viewer.sendOrdinaryControlEvents(events)
            }
            for modifier in modifiers(state.consume()) { keyboard.toggleModifier(modifier) }
            keyboard.text(String(scalar))
        }
        refresh()
    }

    @objc func deleteBackward() {
        guard ready, let viewer else { return }
        let events = TerminalShortcutStep(character: 0xff08, modifiers: modifiers(state.consume())).remoteEvents
        viewer.sendOrdinaryControlEvents(events); refresh()
    }
    @objc func sendKey(_ code: UInt32) -> Bool {
        guard ready else { return false }
        let step = TerminalShortcutStep(character: code, modifiers: modifiers(state.active))
        let accepted = admit(step.remoteEvents)
        if accepted { _ = state.consume() }
        refresh(); return accepted
    }
    @objc func sendModifierAlone(_ code: UInt32) -> Bool {
        guard [UInt32(0xffe3), 0xffe9, 0xffe1, 0xffeb].contains(code) else { return false }
        let accepted = admit([["key": code, "down": true], ["key": code, "down": false]])
        if accepted { keyboardBar.keyFeedback.feedback("key") }
        return accepted
    }
    @objc func showSettings() { showSettings(library: nil) }
    private func showSettings(library: TerminalSavedItemsSection?) {
        guard !customizing, let viewer else { return }
        viewer.beginKeyboardCustomization(); customizing = true
        let token = inputGeneration
        keypad?.ready = false; keypad = nil
        present { [weak self] in
            guard let self else { return UIViewController() }
            return UIHostingController(rootView: TerminalControlsSettings(store: activeStore, initialLibrary: library,
                remoteMacID: viewer.preferenceID.flatMap(UUID.init(uuidString:)), behaviorChanged: { [weak self] in self?.applyPointerSettings() }, close: { [weak self] in
                guard let self, customizing, inputGeneration == token else { return }
                self.viewer?.dismiss(animated: true) { [weak self] in
                    guard let self, customizing, inputGeneration == token else { return }
                    customizing = false; self.viewer?.endKeyboardCustomization(); reload()
                }
            }))
        }
    }
    @objc func showKeypad() {
        guard let viewer else { return }
        let epoch = viewer.controlsEpoch, token = inputGeneration
        let state = TerminalKeypadState(); state.remoteMac = true; state.profileRevision = profile.revision; state.supportsCommand = true; state.ready = ready
        state.armed = self.state.armed; state.locked = self.state.locked
        state.canPin = readable && DirectProAccess.shared.hasPro; state.items = state.canPin ? profile.actions : []
        keypad = state
        let admitted = { [weak self, weak viewer, weak state] in self?.ready == true && state?.ready == true && self?.keypad === state && viewer?.controlsEpoch == epoch && self?.profile.revision == state?.profileRevision && self?.inputGeneration == token }
        state.toggle = { [weak self] modifier, lock in guard admitted() else { return }; self?.keyboardBar.toggle(modifier, lock: lock); self?.refresh() }
        state.send = { [weak self, weak viewer] kind in
            guard admitted() else { return }
            if let id = kind.split(separator: "-", maxSplits: 1).last,
               kind.hasPrefix("paletteKey-"), let key = TerminalKeyCatalog.key(String(id)) { self?.sendPalette(key) }
            else if kind == "paste", let text = UIPasteboard.general.string { self?.reviewText(text) }
            else if kind == "composeText" { viewer?.showControlsComposer() }
        }
        state.alone = { [weak self] action in
            guard admitted(), let code = action.modifierAlone else { return }
            _ = self?.sendModifierAlone(code)
        }
        state.pin = { [weak self, weak state] id, destination in
            guard let self, let state, admitted(), readable, DirectProAccess.shared.hasPro, let key = TerminalKeyCatalog.key(id), var draft = try? activeStore.load() else { return }
            _ = draft.pin(key, in: destination)
            if (try? activeStore.save(draft)) != nil { reload(); state.profileRevision = profile.revision; state.notice = "Added to " + destination.title }
        }
        state.useSaved = { [weak self] id in guard admitted() else { return }; self?.use(id) }
        state.compose = { [weak viewer] in guard admitted() else { return }; viewer?.showControlsComposer() }
        present { UIHostingController(rootView: TerminalKeypad(state: state, macName: "Remote Mac")) }
    }
    private func reviewText(_ text: String, requiresPro: Bool = false) {
        var action = TerminalControlAction(title: "Paste Text", kind: .shortcut)
        action.steps = [.init(kind: .text, text: text)]; run(action, requiresPro: requiresPro)
    }
    private func applyPointerSettings() {
        guard let viewer, let id = viewer.preferenceID.flatMap(UUID.init(uuidString:)) else { return }
        viewer.pointerSpeed = VNCSessionPreferences.speed(id)
        viewer.followCursorEnabled = VNCSessionPreferences.followCursor(id)
        if !viewer.inputOnly { viewer.performSharedControlAction(VNCSessionPreferences.trackpad(id) ? "setTrackpad" : "setPointer") }
    }
    @objc func menuActions() -> [[String: Any]] {
        guard DirectProAccess.shared.hasPro else { return activeStore.remoteMode.defaults.map(\.native) }
        guard readable else { return [] }
        return profile.resolvedMenuPlacements.compactMap { placement in
            guard let action = profile.actions.first(where: { $0.id == placement.actionID }) else { return nil }
            var item = action.native
            item["kind"] = "remoteSavedAction"; item["id"] = placement.id.uuidString
            item["definitionID"] = action.id.uuidString; item["controlsRevision"] = profile.revision.uuidString
            item["controlsGeneration"] = inputGeneration.uuidString; item["inputEpoch"] = viewer?.controlsEpoch ?? 0
            item["disabled"] = !canUse(action)
            if action.operation == .rightClick || action.operation?.modifierAlone != nil { item["inputAction"] = true }
            if action.operation == .pointerMode { item["defersInterfaceFeedback"] = true }
            if action.operation == .keyboard { item["title"] = keyboardBar.keyboardButton.accessibilityLabel }
            if action.operation == .expandRows { item["title"] = keyboardBar.showsExtraRows ? "Collapse Rows" : "Expand Rows" }
            return item
        }
    }
    @objc func performMenuAction(_ item: [String: Any]) {
        guard item["controlsGeneration"] as? String == inputGeneration.uuidString,
              item["controlsRevision"] as? String == profile.revision.uuidString,
              (item["inputEpoch"] as? NSNumber)?.uintValue == viewer?.controlsEpoch,
              let placementID = (item["id"] as? String).flatMap(UUID.init(uuidString:)),
              let placement = profile.resolvedMenuPlacements.first(where: { $0.id == placementID }),
              item["definitionID"] as? String == placement.actionID.uuidString else { return }
        use(placement.actionID)
    }
    @objc func showShortcuts() { showSavedItems(.shortcuts) }
    @objc func showText() { showSavedItems(.text) }
    private func showSavedItems(_ section: TerminalSavedItemsSection) {
        let token = inputGeneration, epoch = viewer?.controlsEpoch, revision = profile.revision
        let current = { [weak self] in self?.inputGeneration == token && self?.viewer?.controlsEpoch == epoch && self?.profile.revision == revision }
        present { [weak self] in
            guard let self else { return UIViewController() }
            return UIHostingController(rootView: TerminalSavedItems(section: section,
                items: readable && DirectProAccess.shared.hasPro ? profile.savedItems(section) : [],
                macName: viewer?.macName ?? "Mac", supportsCommand: true, select: { [weak self] id in
                    guard current() else { return }
                    self?.viewer?.dismiss(animated: true) { [weak self] in if current() { self?.use(id) } }
                }, customize: { [weak self] in
                    guard current() else { return }; self?.showSettings(library: section)
                }, compose: { [weak self] in guard current() else { return }; self?.viewer?.showControlsComposer() }))
        }
    }
    private func use(_ id: UUID) {
        guard readable, DirectProAccess.shared.hasPro, DirectAppLockV1.shared.canAccess,
              let action = profile.actions.first(where: { $0.id == id }), action.valid,
              canUse(action) else { return }
        switch action.kind {
        case .shortcut: run(action)
        case .text:
            let token = inputGeneration, epoch = viewer?.controlsEpoch, revision = profile.revision
            viewer?.showControlsComposer(text: action.text, title: action.title, available: { [weak self] in
                guard let self else { return false }
                return ready && readable && DirectProAccess.shared.hasPro && inputGeneration == token
                    && viewer?.controlsEpoch == epoch && profile.revision == revision
            })
        case .key: if let key = action.key, sendKey(key.shortcutCode) { keyboardBar.keyFeedback.feedback("key") }
        case .builtIn:
            if let code = action.operation?.modifierAlone { _ = sendModifierAlone(code) }
            else if action.operation == .keyboard { viewer?.toggleControlsKeyboard() }
            else if action.operation == .expandRows { keyboardBar.showsExtraRows.toggle(); keyboardBar.layoutChanged?() }
            else if action.operation == .paste, let text = UIPasteboard.general.string { reviewText(text) }
            else if action.operation == .composeText { viewer?.showControlsComposer() }
            else if let operation = action.operation {
                let kinds: [TerminalAppAction: String] = [.rightClick: "rightClick", .copyScreenText: "copyText", .fitToWindow: "fit", .pointerMode: "mode"]
                if let kind = kinds[operation], !(operation.requiresScreen && viewer?.inputOnly == true) { viewer?.performSharedControlAction(kind) }
            }
        }
    }
    private func run(_ action: TerminalControlAction, requiresPro: Bool = true) {
        guard ready, let viewer else { return }
        guard let events = try? action.remoteSequence() else { notice("This shortcut is too large or contains an unsupported step. Nothing was sent."); return }
        let epoch = viewer.controlsEpoch, revision = profile.revision, token = inputGeneration
        let send = { [weak self, weak viewer] in
            guard let self, let viewer, ready, viewer.controlsEpoch == epoch, profile.revision == revision, inputGeneration == token, (!requiresPro || DirectProAccess.shared.hasPro) else { return }
            if !viewer.sendControlEvents(events, completion: { [weak self, weak viewer] written in
                guard viewer?.controlsEpoch == epoch else { return }
                if !written { self?.notice("Sending stopped. Check the Mac before trying again. The shortcut will not be replayed.") }
            }) { notice("Input is busy. Nothing was queued.") }
            else { keyboardBar.keyFeedback.feedback("commit") }
        }
        if action.hasSequenceText {
            present { [weak self] in UIHostingController(rootView: TerminalSequenceReview(action: action, send: { [weak self] in
                self?.viewer?.dismiss(animated: true, completion: send)
            }, cancel: { [weak self] in self?.viewer?.dismiss(animated: true) })) }
        } else { send() }
    }
    private func notice(_ message: String) {
        guard viewer?.presentedViewController == nil else { keypad?.notice = message; return }
        let alert = UIAlertController(title: "Shortcut", message: message, preferredStyle: .alert)
        alert.addAction(.init(title: "OK", style: .default)); viewer?.present(alert, animated: true)
    }
    private func present(_ make: @escaping () -> UIViewController) {
        guard let viewer, DirectAppLockV1.shared.canAccess else { return }
        let token = inputGeneration
        let show = { [weak self, weak viewer] in
            guard let self, let viewer, inputGeneration == token, DirectAppLockV1.shared.canAccess else { return }
            let controller = make(); panel = controller
            controller.modalPresentationStyle = .pageSheet
            controller.sheetPresentationController?.detents = customizing ? [.large()] : [.medium(), .large()]
            controller.sheetPresentationController?.prefersGrabberVisible = true
            viewer.present(controller, animated: true)
        }
        if viewer.presentedViewController != nil { viewer.dismiss(animated: true, completion: show) } else { show() }
    }
}
#endif
