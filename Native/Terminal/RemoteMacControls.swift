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
    private let trackpadDock = UIStackView()
    private let dockMenuAnchor = UIView()
    private let navigationViewport = UIScrollView()
    private let mediaViewport = UIScrollView()
    private let mediaStatus = UILabel()
    private var dockMedia: UIButton?
    private var mediaButtons: [UIButton] = []
    private var mediaRequest: UUID?
    private var mediaVolumeReadable = false
    private var showingMedia = false
    @objc private(set) var trackpadShowsKeyboardBar = false
    private var trackpadNavigation: [UIButton] = []
    private var dockCompose: UIButton?
    private var keyboardIsFocused = false
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
    private var sequenceTask: Task<Void, Never>?
    private var sequenceIdentifier: String?
    private var sequenceBanner: TerminalSequenceBannerController?
    private var shortcutConfirmations = TerminalShortcutConfirmations()
    @objc var bar: UIView { keyboardBar }
    @objc var menuAnchor: UIView { keyboardBar.compactContentsVisible ? dockMenuAnchor : keyboardBar.menuAnchor }
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
        configureTrackpadDock()
        keyboardBar.installCompactContents(trackpadDock)
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

    private func configureTrackpadDock() {
        trackpadDock.axis = .vertical
        trackpadDock.spacing = 3
        trackpadDock.isLayoutMarginsRelativeArrangement = true
        trackpadDock.directionalLayoutMargins = .init(top: 4, leading: 4, bottom: 4, trailing: 4)
        trackpadDock.accessibilityIdentifier = "trackpad-dock"
        let navigationRow = UIStackView()
        let keys: [(String, String, UInt32)] = [
            ("Escape", "escape", 0xff1b), ("Left Arrow", "arrow.left", 0xff51),
            ("Up Arrow", "arrow.up", 0xff52), ("Down Arrow", "arrow.down", 0xff54),
            ("Right Arrow", "arrow.right", 0xff53), ("Return", "return", 0xff0d)
        ]
        for (title, symbol, code) in keys {
            let button = dockButton(title, symbol: symbol) { [weak self] in
                guard let self, sendKey(code) else { return }
                keyboardBar.keyFeedback.feedback("key")
            }
            navigationRow.addArrangedSubview(button)
            trackpadNavigation.append(button)
        }
        installDockRow(navigationRow, in: navigationViewport)
        navigationViewport.accessibilityIdentifier = "trackpad-navigation-keys"
        let mediaRow = UIStackView()
        let volume: [(String, String, DirectTrackpadVolume)] = [
            ("Volume Down", "speaker.minus", .decrease), ("Mute or Unmute", "speaker.slash", .toggleMute),
            ("Volume Up", "speaker.plus", .increase)
        ]
        for (title, symbol, operation) in volume {
            let button = dockButton(title, symbol: symbol) { [weak self] in self?.runVolume(operation) }
            mediaRow.addArrangedSubview(button)
            mediaButtons.append(button)
        }
        installDockRow(mediaRow, in: mediaViewport)
        mediaStatus.font = .preferredFont(forTextStyle: .footnote)
        mediaStatus.adjustsFontForContentSizeCategory = true
        mediaStatus.numberOfLines = 0
        mediaStatus.textAlignment = .center
        mediaStatus.textColor = .secondaryLabel
        mediaStatus.isHidden = true
        let actions = UIStackView()
        let compose = dockButton("Compose Text", symbol: "square.and.pencil") { [weak self] in self?.viewer?.showControlsComposer() }
        compose.accessibilityHint = "Edit text on this device, then send it to the Mac."
        dockCompose = compose
        let type = dockButton("Type on Mac", symbol: "keyboard") { [weak self] in self?.viewer?.toggleControlsKeyboard() }
        type.accessibilityHint = "Open the keyboard and send keystrokes as you type."
        let media = dockButton("Media", symbol: "speaker.wave.2") { [weak self] in
            guard let self else { return }
            setMediaVisible(!showingMedia)
        }
        dockMedia = media
        for button in [type, compose, media] { actions.addArrangedSubview(button) }
        let actionViewport = UIScrollView()
        installDockRow(actions, in: actionViewport)
        let bottom = UIStackView(arrangedSubviews: [actionViewport, dockMenuAnchor])
        bottom.spacing = 4
        dockMenuAnchor.isUserInteractionEnabled = false
        dockMenuAnchor.widthAnchor.constraint(equalToConstant: 52).isActive = true
        trackpadDock.addArrangedSubview(navigationViewport)
        trackpadDock.addArrangedSubview(mediaStatus)
        trackpadDock.addArrangedSubview(bottom)
    }

    private func installDockRow(_ row: UIStackView, in scroll: UIScrollView) {
        row.distribution = .fillEqually
        row.spacing = 4
        row.translatesAutoresizingMaskIntoConstraints = false
        scroll.delaysContentTouches = false
        scroll.addSubview(row)
        let fillWidth = row.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        fillWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            row.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            row.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 44),
            fillWidth
        ])
    }

    private func dockButton(_ title: String, symbol: String, action: @escaping @MainActor () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.tinted()
        configuration.image = UIImage(systemName: symbol)
        configuration.cornerStyle = .medium
        configuration.contentInsets = .init(top: 0, leading: 0, bottom: 0, trailing: 0)
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.accessibilityLabel = title
        return button
    }

    private func refreshDock() {
        let compact = viewer?.inputOnly == true && !keyboardIsFocused && !trackpadShowsKeyboardBar && sequenceIdentifier == nil
        if showingMedia && (!compact || !ready) { setMediaVisible(false) }
        keyboardBar.setCompactContentsVisible(compact)
        for button in trackpadNavigation { button.isEnabled = ready }
        dockCompose?.isEnabled = ready
        dockMedia?.isEnabled = ready && viewer?.trackpadVolumeHandler != nil
        for button in mediaButtons { button.isEnabled = ready && mediaVolumeReadable && mediaRequest == nil }
    }

    @objc func toggleTrackpadKeyboardBar() {
        guard viewer?.inputOnly == true, sequenceIdentifier == nil else { return }
        trackpadShowsKeyboardBar.toggle()
        refreshDock()
    }

    private func setMediaVisible(_ visible: Bool) {
        guard showingMedia != visible else { return }
        showingMedia = visible
        let removed = visible ? navigationViewport : mediaViewport
        trackpadDock.removeArrangedSubview(removed)
        removed.removeFromSuperview()
        trackpadDock.insertArrangedSubview(visible ? mediaViewport : navigationViewport, at: 0)
        dockMedia?.accessibilityLabel = visible ? "Show Navigation Keys" : "Media"
        dockMedia?.configuration?.image = UIImage(systemName: visible ? "arrowkeys" : "speaker.wave.2")
        mediaStatus.isHidden = !visible
        mediaRequest = nil
        mediaVolumeReadable = false
        if visible { runVolume(.read) }
        viewer?.view.setNeedsLayout()
    }

    private func runVolume(_ operation: DirectTrackpadVolume) {
        guard showingMedia, ready, mediaRequest == nil, operation == .read || mediaVolumeReadable,
              let viewer, let handler = viewer.trackpadVolumeHandler else { return }
        let request = UUID(), epoch = viewer.controlsEpoch
        mediaRequest = request
        mediaStatus.text = operation == .read ? "Checking Mac volume…" : "Adjusting Mac volume…"
        refreshDock()
        handler(operation.rawValue) { [weak self, weak viewer] reply in
            MainActor.assumeIsolated {
                guard let self, let viewer, self.mediaRequest == request else { return }
                self.mediaRequest = nil
                guard viewer.controlsEpoch == epoch, self.showingMedia, self.ready else { self.setMediaVisible(false); return }
                if let reply, let reading = DirectTrackpadVolume.Reading(response: reply) {
                    self.mediaVolumeReadable = true
                    self.mediaStatus.text = reading.muted ? "Mac sound muted" : "Mac volume \(reading.level)%"
                    if operation != .read { self.keyboardBar.keyFeedback.feedback("selection") }
                } else {
                    self.mediaStatus.text = operation == .read ? "Mac volume unavailable" : "Volume change couldn’t be verified"
                }
                if let message = self.mediaStatus.text { UIAccessibility.post(notification: .announcement, argument: message) }
                self.refreshDock()
            }
        }
    }

    private var ready: Bool { sequenceIdentifier == nil && viewer?.controlsInputAvailable() == true && DirectAppLockV1.shared.canAccess }
    private func canUse(_ action: TerminalControlAction) -> Bool {
        sequenceIdentifier == nil && (action.isLocalKeyboardControl || ready && !(action.operation?.requiresScreen == true && viewer?.inputOnly == true)
            && (action.operation != .copyScreenText || viewer?.controlsCopyTextAvailable() == true))
    }
    @objc func reload() {
        do { profile = try activeStore.load(); readable = true }
        catch { readable = false; profile = .remoteDefaults }
        shortcutConfirmations.definitionsChanged(profile.actions)
        keyboardBar.configure(profile) { [weak self] in self?.use($0) }
        keyboardBar.showsExtraRows = profile.rowsExpanded ?? false
        refresh()
        viewer?.refreshControlsMenu()
    }
    @objc func refresh() {
        keyboardBar.refresh()
        refreshDock()
        keypad?.ready = ready && keypad?.ready == true
        keypad?.armed = state.armed; keypad?.locked = state.locked
    }
    /// Composer handoffs clear local modifiers without retiring their admission.
    @objc func clearModifiers() { state.reset(); refresh() }
    @objc func reset() {
        inputGeneration = UUID()
        sequenceTask?.cancel(); sequenceTask = nil
        if let sequenceIdentifier { viewer?.cancelControlSequence(sequenceIdentifier) }
        sequenceIdentifier = nil
        sequenceBanner?.close(restoreKeyboard: false); sequenceBanner = nil
        if customizing { customizing = false; viewer?.endKeyboardCustomization() }
        keypad?.ready = false; keypad = nil
        if let panel, viewer?.presentedViewController === panel { viewer?.dismiss(animated: false) }
        panel = nil; clearModifiers()
    }
    @objc func keyboardFocused(_ focused: Bool) {
        keyboardIsFocused = focused
        keyboardBar.setKeyboardFocused(focused)
        refreshDock()
    }
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
        action.steps = [.init(kind: .text, text: text)]; run(action, requiresPro: requiresPro, forceReview: true)
    }
    private func applyPointerSettings() {
        guard let viewer, let id = viewer.preferenceID.flatMap(UUID.init(uuidString:)) else { return }
        viewer.pointerSpeed = VNCSessionPreferences.speed(id)
        viewer.trackpadPrecisionAndReach = VNCSessionPreferences.precisionAndReach(id)
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
    private func run(_ action: TerminalControlAction, requiresPro: Bool = true, forceReview: Bool = false) {
        guard ready, let viewer else { return }
        guard let plan = try? action.remotePlan() else { notice("This shortcut is too large or contains an unsupported step. Nothing was sent."); return }
        let epoch = viewer.controlsEpoch, revision = profile.revision, token = inputGeneration
        let connectionID = viewer.controlsConnectionID
        let send = { [weak self, weak viewer] in
            guard let self, let viewer, ready, viewer.controlsEpoch == epoch, profile.revision == revision, inputGeneration == token, (!requiresPro || DirectProAccess.shared.hasPro) else { return }
            self.runOwned(action, plan: plan, requiresPro: requiresPro)

        }
        if forceReview || shortcutConfirmations.requiresReview(action, connectionID: connectionID) {
            present { [weak self] in UIHostingController(rootView: TerminalSequenceReview(action: action, allowsConnectionSkip: !forceReview, send: { [weak self] skip in
                guard let self, let viewer = self.viewer, viewer.controlsEpoch == epoch, profile.revision == revision, inputGeneration == token else { return }
                if skip && !forceReview { shortcutConfirmations.skip(action, connectionID: connectionID) }
                viewer.dismiss(animated: true, completion: send)
            }, cancel: { [weak self] in self?.viewer?.dismiss(animated: true) })) }
        } else { send() }
    }
    private func finishRun(_ identifier: String) {
        guard sequenceIdentifier == identifier else { return }
        viewer?.endControlSequence(identifier)
        sequenceIdentifier = nil; sequenceTask = nil
        sequenceBanner?.close(); sequenceBanner = nil; refresh()
    }
    private func runOwned(_ action: TerminalControlAction, plan: [TerminalSequenceOperation<[[String: Any]]>], requiresPro: Bool) {
        guard ready, let viewer, let identifier = viewer.beginControlSequence() else { notice("Input is busy. Nothing was queued."); return }
        sequenceIdentifier = identifier
        refreshDock()
        let epoch = viewer.controlsEpoch, token = inputGeneration
        let progress = TerminalSequenceProgress(action: action, batching: !action.hasSequenceWait)
        let keyboard = TerminalSequenceKeyboard(visible: { [weak viewer] in viewer?.controlsSoftwareKeyboardVisible() == true }, current: { [weak self, weak viewer] in
            guard let self, let viewer else { return false }
            return inputGeneration == token && viewer.controlsEpoch == epoch && viewer.controlsInputAvailable()
                && DirectAppLockV1.shared.canAccess && viewer.controlsExecutionKeyboardCurrent()
        }, hide: { [weak viewer] in viewer?.hideControlsExecutionKeyboard() == true }, restore: { [weak viewer] in viewer?.restoreControlsExecutionKeyboard() })
        let controller = TerminalSequenceBannerController(progress: progress, keyboard: keyboard, cancel: { [weak self, weak viewer] in
            guard let self, sequenceIdentifier == identifier else { return }
            progress.cancelled = true; sequenceTask?.cancel(); viewer?.cancelControlSequence(identifier)
            finishRun(identifier)
        })
        sequenceBanner = controller
        controller.attach(to: viewer, covering: keyboardBar, blocking: viewer.view.subviews.filter { $0 is CompanionVNCControls })
        let current: @MainActor () -> Bool = { [weak self, weak viewer] in
            guard let self, let viewer else { return false }
            return !progress.cancelled && viewer.controlsInputAvailable() && DirectAppLockV1.shared.canAccess
                && viewer.controlsEpoch == epoch && inputGeneration == token && sequenceIdentifier == identifier
                && profile.actions.contains { $0.id == action.id && $0.sameDefinition(as: action) }
                && (!requiresPro || DirectProAccess.shared.hasPro)
        }
        if !action.hasSequenceWait {
            // Preserve one compact native event batch; admission is still exclusive.
            let accepted = viewer.sendControlSequenceEvents(plan.compactMap(\.input).flatMap { $0 }, identifier: identifier) { [weak self, weak viewer] written in
                guard let self, sequenceIdentifier == identifier else { return }
                finishRun(identifier)
                if !written, !progress.cancelled, viewer?.controlsEpoch == epoch { notice("Sending stopped. Check the Mac before trying again. The shortcut will not be replayed.") }
            }
            if !accepted { finishRun(identifier); notice("Input is busy. Nothing was queued.") }
            else { keyboardBar.keyFeedback.feedback("commit") }
            refresh(); return
        }
        sequenceTask = Task { [weak self, weak viewer] in
            guard let self, let viewer else { return }
            defer { finishRun(identifier) }
            do {
                try await TerminalSequencePump.run(plan, current: current, progress: { progress.move(to: $0) }) { _, group in
                    try await withCheckedThrowingContinuation { (reply: CheckedContinuation<Void, Error>) in
                        if !viewer.sendControlSequenceEvents(group, identifier: identifier, completion: { written in
                            if written { reply.resume() } else { reply.resume(throwing: CancellationError()) }
                        }) { reply.resume(throwing: CancellationError()) }
                    }
                }
            } catch {
                guard sequenceIdentifier == identifier else { return }
                viewer.cancelControlSequence(identifier)
                if !progress.cancelled, viewer.controlsEpoch == epoch { notice("Shortcut stopped. Remaining steps will not be replayed.") }
            }
        }
        refresh()
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
