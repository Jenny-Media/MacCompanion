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
            case .tooLarge(let mode): mode == .terminal ? "Terminal can send up to 4096 UTF-8 bytes at once." : "Screen Sharing input can send up to 256 Unicode characters at once."
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
    var docked = false
    var floatingAnchor = CGPoint(x: 0.5, y: 1)
    var expanded = false
    var compactLayout = false
    var narrowLayout = false
    var issue: String?
    var confirmation: DirectComposedText?
    @ObservationIgnored private var epoch = UUID()
    @ObservationIgnored private var available: () -> Bool = { false }
    @ObservationIgnored private var send: ((String, @escaping (String?) -> Void) -> Void)?
    @ObservationIgnored var close: (() -> Void)?
    @ObservationIgnored var sendingChanged: ((Bool) -> Void)?
    @ObservationIgnored var interrupted: (() -> Void)?
    init(macName: String, mode: DirectControlMode) { self.macName = macName; self.mode = mode }
    var presentationEpoch: UUID { epoch }
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
        epoch = UUID(); text = ""; issue = nil; confirmation = nil; active = false; expanded = false; docked = false; floatingAnchor = CGPoint(x: 0.5, y: 1)
        sending = false; available = { false }; send = nil; sendingChanged?(false); close?()
    }
}

/// Owned by one native session controller; closing the sheet retains only its
/// unsent draft. No credentials, persistence, clipboard polling or global state.
@MainActor @objc(DirectTextComposer) final class DirectTextComposer: NSObject {
    let draft: DirectTextComposerDraft
    @objc var interruptionHandler: (() -> Void)?
    @objc weak var shortcutBar: UIView?
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
        host.shortcutBar = shortcutBar
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

/// Geometry is shared by layout and native tests; positions are relative to the
/// keyboard-safe area so a bottom-snapped panel follows keyboard/orientation changes.
struct DirectComposerPlacement {
    static func area(safe: CGRect, keyboardTop: CGFloat) -> CGRect {
        let room = keyboardTop - safe.minY
        let top = safe.minY + (room < 284 ? 8 : 48)
        return CGRect(x: safe.minX + 8, y: top, width: max(0, safe.width - 16), height: max(0, keyboardTop - 8 - top))
    }
    static func area(safe: CGRect, keyboard: CGRect, shortcutBar: CGRect = .null) -> CGRect {
        // The app's shortcut row is separate from UIKit's keyboard. Reserve both
        // in the same coordinate space, including hardware/undocked keyboards.
        let visible = [keyboard, shortcutBar].map { $0.intersection(safe) }
            .filter { !$0.isNull && !$0.isEmpty }.reduce(CGRect.null) { $0.union($1) }
        guard !visible.isNull, !visible.isEmpty else { return area(safe: safe, keyboardTop: safe.maxY) }
        let above = area(safe: safe, keyboardTop: visible.minY)
        if above.height >= 180 { return above }
        let base = area(safe: safe, keyboardTop: safe.maxY)
        let belowY = max(base.minY, visible.maxY + 8)
        let below = CGRect(x: base.minX, y: belowY, width: base.width, height: max(0, base.maxY - belowY))
        let left = CGRect(x: base.minX, y: base.minY, width: max(0, visible.minX - 8 - base.minX), height: base.height)
        let rightX = max(base.minX, visible.maxX + 8)
        let right = CGRect(x: rightX, y: base.minY, width: max(0, base.maxX - rightX), height: base.height)
        let candidates = [above, below, left, right]
        // Prefer a region that can hold the compact editor and its actions;
        // moving an undocked keyboard near the top must not collapse the card.
        let readable = candidates.filter { $0.width >= 264 && $0.height >= 112 }
        return (readable.isEmpty ? candidates : readable).max {
            $0.width * min(324, $0.height) < $1.width * min(324, $1.height)
        } ?? above
    }
    static func dockedAnchor(area: CGRect, keyboard: CGRect) -> CGPoint {
        CGPoint(x: 0.5, y: !keyboard.isEmpty && area.minY >= keyboard.maxY ? 0 : 1)
    }
    static func frame(area: CGRect, size: CGSize, anchor: CGPoint) -> CGRect {
        let size = CGSize(width: min(area.width, max(0, size.width)), height: min(area.height, max(0, size.height)))
        return CGRect(x: area.minX + max(0, min(1, anchor.x)) * (area.width - size.width),
                      y: area.minY + max(0, min(1, anchor.y)) * (area.height - size.height), width: size.width, height: size.height)
    }
    static func anchor(origin: CGPoint, area: CGRect, size: CGSize, snap: Bool) -> CGPoint {
        func fraction(_ position: CGFloat, start: CGFloat, span: CGFloat) -> CGFloat {
            guard span > 0 else { return 0.5 }
            let offset = min(span, max(0, position - start))
            let distance = min(28, span / 3)
            if snap, offset <= distance { return 0 }
            if snap, span - offset <= distance { return 1 }
            return offset / span
        }
        return CGPoint(x: fraction(origin.x, start: area.minX, span: area.width - size.width),
                       y: fraction(origin.y, start: area.minY, span: area.height - size.height))
    }
}

/// One editor stays mounted through floating movement, expansion and docking.
/// UIKit's real keyboard guide bounds both presentations without resigning it.
@MainActor final class DirectTextComposerPanel: UIViewController, UIGestureRecognizerDelegate {
    let draft: DirectTextComposerDraft
    private let presentationEpoch: UUID
    private var usable: Bool { draft.active && draft.presentationEpoch == presentationEpoch && !draft.sending }
    private var placementConstraints: [NSLayoutConstraint] = []
    private var keyboardBottom: NSLayoutConstraint?
    private var safeBottom: NSLayoutConstraint?
    private var peek: NSLayoutConstraint?
    private var grabberHeight: NSLayoutConstraint?
    private var grabberWidth: NSLayoutConstraint?
    private var grabberCenter: NSLayoutConstraint?
    private var measuredText: String?
    private var measuredWidth: CGFloat = 0
    private var measuredCategory: UIContentSizeCategory?
    private var measuredEditorHeight: CGFloat = 0
    private var grabber: UIButton?
    private var closeButton: UIButton?
    private var editorHost: UIHostingController<AnyView>?
    private var card: UIView?
    private var sendBounds = CGRect.zero
    private var draggingHeight: CGFloat?
    private var initialFrame = CGRect.zero
    private var initialAnchor = CGPoint(x: 0.5, y: 1)
    private var initialExpanded = false
    private var dragging = false
    var deliveryActionFrame: CGRect { editorHost?.view.convert(sendBounds, to: view) ?? .zero }
    var panelFrame: CGRect { card?.frame ?? .zero }
    var closeActionFrame: CGRect { closeButton?.convert(closeButton?.bounds ?? .zero, to: view) ?? .zero }
    #if DEBUG
    // Controlled Simulator keyboard geometry; absent from release builds.
    var simulatedKeyboardFrame: CGRect? { didSet { view.setNeedsLayout() } }
    #endif
    private var keyboardFrame: CGRect {
        #if DEBUG
        if let simulatedKeyboardFrame { return simulatedKeyboardFrame }
        #endif
        return view.keyboardLayoutGuide.layoutFrame
    }
    weak var shortcutBar: UIView?
    var placementArea: CGRect {
        let bar: CGRect
        if let shortcutBar, shortcutBar.window === view.window, !shortcutBar.isHidden, shortcutBar.alpha > 0 {
            bar = view.convert(shortcutBar.bounds, from: shortcutBar)
        } else { bar = .null }
        return DirectComposerPlacement.area(safe: view.safeAreaLayoutGuide.layoutFrame, keyboard: keyboardFrame, shortcutBar: bar)
    }
    init(draft: DirectTextComposerDraft) { self.draft = draft; presentationEpoch = draft.presentationEpoch; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear; view.accessibilityViewIsModal = true
        view.keyboardLayoutGuide.followsUndockedKeyboard = true
        let backdrop = UIControl(); backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.12)
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addTarget(self, action: #selector(back), for: .touchUpInside)
        view.addSubview(backdrop)
        NSLayoutConstraint.activate([backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor), backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        let material: UIVisualEffect
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: .regular)
            // Editing stays visually quiet; only the existing handle moves the bubble.
            glass.isInteractive = false
            material = glass
        } else {
            material = UIBlurEffect(style: .systemMaterial)
        }
        let card = UIVisualEffectView(effect: material); self.card = card
        view.addSubview(card); card.translatesAutoresizingMaskIntoConstraints = false
        card.accessibilityIdentifier = "compose-bubble"
        card.accessibilityContainerType = .semanticGroup
        card.layer.cornerRadius = 20; card.clipsToBounds = true
        let grabber = UIButton(type: .custom); self.grabber = grabber; grabber.translatesAutoresizingMaskIntoConstraints = false
        grabber.accessibilityIdentifier = "compose-grabber"
        // VoiceOver can reposition the floating panel without a touch drag.
        grabber.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Move composer up", target: self, selector: #selector(moveUp)),
            UIAccessibilityCustomAction(name: "Move composer down", target: self, selector: #selector(moveDown)),
            UIAccessibilityCustomAction(name: "Move composer left", target: self, selector: #selector(moveLeft)),
            UIAccessibilityCustomAction(name: "Move composer right", target: self, selector: #selector(moveRight))]
        card.contentView.addSubview(grabber)
        let indicator = UIView(); indicator.backgroundColor = .tertiaryLabel; indicator.layer.cornerRadius = 2
        indicator.isUserInteractionEnabled = false; indicator.translatesAutoresizingMaskIntoConstraints = false; grabber.addSubview(indicator)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(resize(_:))); pan.delegate = self
        grabber.addGestureRecognizer(pan)
        let host = UIHostingController(rootView: AnyView(DirectTextComposerView(draft: draft,
            isCurrent: { [weak self] in self?.usable == true },
            requestLayout: { [weak self] in self?.view.setNeedsLayout() },
            reportSendBounds: { [weak self] in self?.sendBounds = $0 }).directAppearance()))
        editorHost = host; addChild(host); card.contentView.addSubview(host.view); host.didMove(toParent: self)
        host.view.translatesAutoresizingMaskIntoConstraints = false; host.view.backgroundColor = .clear
        host.view.accessibilityIdentifier = "compose-panel"
        let grabberHeight = grabber.heightAnchor.constraint(equalToConstant: 44); self.grabberHeight = grabberHeight
        let grabberWidth = grabber.widthAnchor.constraint(equalTo: card.widthAnchor, constant: -100); self.grabberWidth = grabberWidth
        let grabberCenter = grabber.centerXAnchor.constraint(equalTo: card.centerXAnchor); self.grabberCenter = grabberCenter
        let leading = card.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8)
        let bottom = card.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -8)
        let safeBottom = card.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8)
        self.keyboardBottom = bottom; self.safeBottom = safeBottom
        // A top-edge keyboard cannot force the editor above the safe area.
        // UIKit switches these before layout; both offsets follow the selected free region.
        view.keyboardLayoutGuide.setConstraints([bottom], activeWhenAwayFrom: .top)
        view.keyboardLayoutGuide.setConstraints([safeBottom], activeWhenNearEdge: .top)
        let close = UIButton(type: .system); closeButton = close
        close.setImage(UIImage(systemName: "xmark"), for: .normal); close.tintColor = .secondaryLabel
        close.setPreferredSymbolConfiguration(UIImage.SymbolConfiguration(pointSize: 18, weight: .regular), forImageIn: .normal)
        close.accessibilityLabel = "Close and keep draft"; close.accessibilityIdentifier = "compose-back"
        close.addTarget(self, action: #selector(back), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false; card.contentView.addSubview(close)
        NSLayoutConstraint.activate([close.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6),
            close.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 6),
            close.widthAnchor.constraint(equalToConstant: 44), close.heightAnchor.constraint(equalToConstant: 44)])
        let width = card.widthAnchor.constraint(equalToConstant: 284)
        let height = card.heightAnchor.constraint(equalToConstant: 324); height.priority = .defaultHigh
        let peek = card.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 48); self.peek = peek
        placementConstraints = [leading, width, height]
        NSLayoutConstraint.activate(placementConstraints + [peek,
            grabber.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6), grabberCenter,
            grabberWidth, grabberHeight,
            indicator.widthAnchor.constraint(equalToConstant: 28), indicator.heightAnchor.constraint(equalToConstant: 4),
            indicator.centerXAnchor.constraint(equalTo: grabber.centerXAnchor), indicator.centerYAnchor.constraint(equalTo: grabber.centerYAnchor),
            host.view.leadingAnchor.constraint(equalTo: card.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: card.topAnchor), host.view.bottomAnchor.constraint(equalTo: card.bottomAnchor)])
        card.contentView.bringSubviewToFront(grabber)
        card.contentView.bringSubviewToFront(close)
    }
    private var availableHeight: CGFloat { placementArea.height }
    private var compactHeight: CGFloat {
        let preferred = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        let font = draft.mode == .terminal ? UIFont.monospacedSystemFont(ofSize: preferred.pointSize, weight: .regular) : preferred
        let width = max(1, min(traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 360 : 284, placementArea.width) - 30)
        let category = traitCollection.preferredContentSizeCategory
        if measuredText != draft.text || measuredWidth != width || measuredCategory != category {
            // Trailing line breaks need one final insertion line. Nothing leaves this owner.
            let text = draft.text.isEmpty ? " " : draft.text + "\u{200B}"
            let bounds = (text as NSString).boundingRect(with: CGSize(width: width, height: font.lineHeight * 6),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil)
            measuredEditorHeight = min(font.lineHeight * 6, max(font.lineHeight * 2, ceil(bounds.height)))
            measuredText = draft.text; measuredWidth = width; measuredCategory = category
        }
        return min(availableHeight, max(112, measuredEditorHeight + 64))
    }
    @objc private func back() { if usable { draft.close?() } }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        usable && (draft.docked || !draft.expanded)
    }
    @objc func toggleExpansion() {
        guard usable else { return }
        cancelMovement(); draft.expanded.toggle(); settle()
    }
    @objc func toggleDock() {
        guard usable else { return }
        cancelMovement(); draft.docked.toggle(); draft.expanded = false; settle()
    }
    private func cancelMovement() { dragging = false; draggingHeight = nil }
    private func move(_ anchor: CGPoint) -> Bool {
        guard usable, !draft.docked, !draft.expanded else { return false }
        draft.floatingAnchor = anchor; settle(); return true
    }
    @objc private func moveUp() -> Bool { move(CGPoint(x: draft.floatingAnchor.x, y: 0)) }
    @objc private func moveDown() -> Bool { move(CGPoint(x: draft.floatingAnchor.x, y: 1)) }
    @objc private func moveLeft() -> Bool { move(CGPoint(x: 0, y: draft.floatingAnchor.y)) }
    @objc private func moveRight() -> Bool { move(CGPoint(x: 1, y: draft.floatingAnchor.y)) }
    private func settle() {
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.view.setNeedsLayout(); self.view.layoutIfNeeded()
        }
    }
    @objc private func resize(_ gesture: UIPanGestureRecognizer) {
        guard usable else { cancelMovement(); return }
        switch gesture.state {
        case .began:
            dragging = true; initialFrame = panelFrame; initialExpanded = draft.expanded; initialAnchor = draft.floatingAnchor
        case .changed, .ended:
            guard dragging else { return }
            let translation = gesture.translation(in: view)
            if draft.docked {
                draggingHeight = min(availableHeight, max(compactHeight, initialFrame.height - translation.y))
            } else {
                draft.floatingAnchor = DirectComposerPlacement.anchor(origin: CGPoint(x: initialFrame.minX + translation.x, y: initialFrame.minY + translation.y), area: placementArea, size: panelFrame.size, snap: gesture.state == .ended)
            }
            if gesture.state == .ended {
                dragging = false
                if draft.docked {
                    let current = draggingHeight ?? initialFrame.height, velocity = gesture.velocity(in: view).y
                    draggingHeight = nil
                    if !initialExpanded && translation.y > 110 { back(); return }
                    draft.expanded = velocity < -300 || (velocity <= 300 && current > (compactHeight + availableHeight) / 2)
                }
                settle()
            } else { view.setNeedsLayout(); view.layoutIfNeeded() }
        case .cancelled, .failed:
            guard dragging else { return }
            cancelMovement(); draft.expanded = initialExpanded; draft.floatingAnchor = initialAnchor; settle()
        default: break
        }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let area = placementArea
        let compact = area.height < 228 || (area.width < 360 && traitCollection.preferredContentSizeCategory.isAccessibilityCategory)
        if draft.compactLayout != compact { draft.compactLayout = compact }
        grabberHeight?.constant = 44
        let hasIssue = draft.issue != nil || (!draft.text.isEmpty && draft.validationIssue != nil)
        grabberWidth?.constant = hasIssue ? -144 : -100
        grabberCenter?.constant = hasIssue ? -22 : 0
        let accessibility = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        let expanded = draft.expanded
        let size = CGSize(width: min(draft.docked || expanded ? 640 : accessibility ? 360 : 284, area.width),
                          height: min(area.height, draggingHeight ?? (expanded ? area.height : compactHeight)))
        if draft.narrowLayout != (size.width < 360) { draft.narrowLayout = size.width < 360 }
        let target = DirectComposerPlacement.frame(area: area, size: size, anchor: draft.docked || expanded ? DirectComposerPlacement.dockedAnchor(area: area, keyboard: keyboardFrame) : draft.floatingAnchor)
        peek?.constant = area.minY - view.safeAreaInsets.top
        let values = [target.minX - view.safeAreaInsets.left, target.width, target.height]
        let keyboardOffset = target.maxY - view.keyboardLayoutGuide.layoutFrame.minY
        if keyboardBottom?.constant != keyboardOffset { keyboardBottom?.constant = keyboardOffset }
        let safeOffset = target.maxY - view.safeAreaLayoutGuide.layoutFrame.maxY
        if safeBottom?.constant != safeOffset { safeBottom?.constant = safeOffset }
        for (constraint, value) in zip(placementConstraints, values) where constraint.constant != value {
            constraint.constant = value
        }
        grabber?.isEnabled = usable
        closeButton?.isEnabled = usable
        grabber?.accessibilityLabel = draft.docked ? "Resize composer" : "Move composer"
        grabber?.accessibilityHint = draft.docked ? "Drag up or down to resize" : "Drag to move and snap to edges"
    }
}

private struct DirectTextComposerView: View {
    @Bindable var draft: DirectTextComposerDraft
    var isCurrent: () -> Bool
    var requestLayout: () -> Void
    var reportSendBounds: (CGRect) -> Void
    @FocusState private var editing: Bool
    @State private var showIssue = false
    private var issue: String? { draft.issue ?? (draft.text.isEmpty ? nil : draft.validationIssue) }
    private func confirmationMessage(_ reviewed: DirectComposedText) -> String {
        let explanation = draft.mode == .terminal
            ? "Without bracketed paste, line breaks can run commands and tabs can change terminal input."
            : "Line breaks press Return on your Mac and may submit content or run commands. Tabs press Tab and may change focus."
        return explanation + (reviewed.endsWithNewline ? " This draft ends with a line break." : "") + " Send Text adds no extra Return."
    }
    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: Binding(get: { draft.text }, set: draft.edit))
                .font(draft.mode == .terminal ? .body.monospaced() : .body)
                .frame(minHeight: 36, maxHeight: .infinity)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 4).padding(.top, 4)
                .autocorrectionDisabled(draft.mode == .terminal).textInputAutocapitalization(draft.mode == .terminal ? .never : .sentences)
                .focused($editing).disabled(draft.sending).scrollDismissesKeyboard(.never)
                .accessibilityLabel("Text to Send · " + draft.macName + " · " + draft.mode.title)
                .accessibilityHint(issue ?? "Nothing is sent until you choose Send Text")
                .accessibilityIdentifier("compose-text").privacySensitive()
            HStack(spacing: 0) {
                // Native Close occupies the first 44pt; its drag grip occupies this spacer.
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
                Spacer(minLength: 44)
                if let issue {
                    Button { if isCurrent() { showIssue = true } } label: {
                        Image(systemName: "exclamationmark.circle").font(.system(size: 20))
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(!isCurrent())
                        .accessibilityLabel(issue).accessibilityIdentifier("compose-error")
                        .popover(isPresented: $showIssue) {
                            VStack(spacing: 12) {
                                Text(issue)
                                Button("Done") { showIssue = false }.frame(minHeight: 44)
                                    .accessibilityIdentifier("compose-error-done")
                            }.padding().presentationCompactAdaptation(.popover)
                        }
                }
                Button { if isCurrent() { draft.requestSend() } } label: {
                    Group {
                        if draft.sending { ProgressView().tint(.primary) }
                        else { Image(systemName: "arrow.up").font(.system(size: 20, weight: .semibold)) }
                    }.frame(width: 32, height: 32)
                        .foregroundStyle(draft.canSend ? Color.white : Color.secondary)
                        .background(draft.canSend ? Color.accentColor : Color.secondary.opacity(0.18), in: .circle)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!draft.canSend || !isCurrent())
                    .accessibilityLabel(draft.sending ? "Sending…" : "Send Text").accessibilityIdentifier("compose-send")
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("composer-panel")) } action: { reportSendBounds($0) }
            }
        }
            .background(Color(uiColor: .secondarySystemBackground), in: .rect(cornerRadius: 16))
            .padding(6)
            .coordinateSpace(name: "composer-panel")
            .onAppear { editing = true }
            .onChange(of: draft.text) { _, _ in requestLayout() }
            .onChange(of: draft.issue) { _, _ in requestLayout() }
            .onChange(of: draft.sending) { _, _ in requestLayout() }
            .onChange(of: draft.active) { _, _ in requestLayout() }
            .alert("Send line breaks or tabs?", isPresented: Binding(get: { draft.confirmation != nil }, set: { if !$0 { draft.confirmation = nil } }), presenting: draft.confirmation) { reviewed in
                Button("Send Text") { if isCurrent() { draft.confirmSend(reviewed) } }
                Button("Cancel", role: .cancel) { draft.confirmation = nil }
            } message: { reviewed in Text(confirmationMessage(reviewed)) }
            .onChange(of: DirectAppLockV1.shared.canAccess) { _, value in if !value { draft.invalidate() } }
    }
}
#endif
