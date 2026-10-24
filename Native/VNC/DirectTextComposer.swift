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
    @ObservationIgnored private var deliveryID: UUID?
    @ObservationIgnored private var available: () -> Bool = { false }
    @ObservationIgnored private var send: ((String, @escaping (String?) -> Void) -> Void)?
    @ObservationIgnored var close: (() -> Void)?
    @ObservationIgnored var sendingChanged: ((Bool) -> Void)?
    @ObservationIgnored var interrupted: (() -> Void)?
    @ObservationIgnored var feedback: (String) -> Void = { _ in }
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
        let token = epoch, delivery = UUID()
        deliveryID = delivery
        sending = true; issue = nil; sendingChanged?(true)
        send(prepared.text) { [weak self] error in
            guard let self, self.epoch == token, self.active, self.sending, self.deliveryID == delivery else { return }
            guard self.available() else { self.invalidate(); return }
            self.deliveryID = nil; self.sending = false; self.sendingChanged?(false)
            if let error { self.issue = error; self.feedback("error") }
            else { self.feedback("success"); self.text = ""; self.close?() }
        }
    }
    func invalidate() {
        if sending { interrupted?() }
        epoch = UUID(); deliveryID = nil; text = ""; issue = nil; confirmation = nil; active = false; expanded = false; docked = false; floatingAnchor = CGPoint(x: 0.5, y: 1)
        sending = false; available = { false }; send = nil; sendingChanged?(false); close?()
    }
}

/// Owned by one native session controller; closing the sheet retains only its
/// unsent draft. No credentials, persistence, clipboard polling or global state.
@MainActor @objc(DirectTextComposer) final class DirectTextComposer: NSObject {
    let draft: DirectTextComposerDraft
    @objc var interruptionHandler: (() -> Void)?
    @objc weak var shortcutBar: UIView?
    var presentationChanged: ((Bool) -> Void)?
    private weak var host: UIViewController?
    private var invalidating = false
    private var presentationRequest = UUID()
    private weak var replacementPrompt: UIAlertController?
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
        presentationRequest = UUID()
        replacementPrompt?.dismiss(animated: false); replacementPrompt = nil
        invalidating = true; draft.invalidate(); invalidating = false
    }
    @objc static func desktopEvents(_ text: String) -> [[String: Any]] {
        (try? DirectComposedText(text, mode: .desktop))?.desktopEvents ?? []
    }
    @objc func present(from controller: UIViewController, available: @escaping () -> Bool,
                       send: @escaping (String, @escaping (String?) -> Void) -> Void) {
        present(from: controller, initialText: nil, savedTitle: nil, available: available, send: send)
    }
    @objc func present(from controller: UIViewController, initialText: String?, savedTitle: String?,
                       available: @escaping () -> Bool,
                       send: @escaping (String, @escaping (String?) -> Void) -> Void) {
        guard !draft.sending, DirectAppLockV1.shared.canAccess, available(), controller.presentedViewController == nil else { return }
        let request = UUID(), epoch = draft.presentationEpoch, previousText = draft.text
        presentationRequest = request
        let admitted = { [weak self] in
            self?.presentationRequest == request && DirectAppLockV1.shared.canAccess && DirectClientPlatformV1.sessionAvailable && available()
        }
        var pending = true
        let show = { [weak self, weak controller] in
            guard let self, let controller, pending, admitted(), draft.presentationEpoch == epoch,
                  draft.text == previousText, !draft.sending, controller.presentedViewController == nil else { return }
            pending = false
            draft.configure(available: admitted, send: send)
            if let initialText { draft.edit(initialText) }
            showPanel(from: controller)
        }
        if let initialText, !previousText.isEmpty, previousText != initialText {
            let message = savedTitle.map { "Your current draft has not been sent. Replace it with “" + $0 + "”?" }
                ?? "Your current draft has not been sent. Replace it with the selected saved text?"
            let alert = UIAlertController(title: "Replace unsent draft?", message: message, preferredStyle: .alert)
            alert.addAction(.init(title: "Keep Draft", style: .cancel) { [weak self] _ in pending = false; self?.replacementPrompt = nil })
            alert.addAction(.init(title: "Replace Draft", style: .destructive) { [weak alert] _ in
                // UIKit retires the alert after its action. Present the editor
                // only after that dismissal, then recheck the captured draft.
                alert?.dismiss(animated: true, completion: show)
            })
            replacementPrompt = alert
            controller.present(alert, animated: true)
        } else { show() }
    }
    private func showPanel(from controller: UIViewController) {
        let host = DirectTextComposerPanel(draft: draft)
        draft.feedback = { [weak host] kind in
            guard let host, host.viewIfLoaded?.window != nil else { return }
            host.interfaceFeedback.feedback(kind)
        }
        if draft.mode == .terminal { host.followAppearance(from: controller) }
        host.shortcutBar = shortcutBar
        host.visibilityChanged = { [weak self, weak host] visible in
            guard let self, let host, self.host === host else { return }
            self.presentationChanged?(visible)
        }
        controller.definesPresentationContext = true
        // Terminal can be nested in a SwiftUI presentation. Keep the composer
        // above that hosting context so its controls enter the accessibility tree.
        host.modalPresentationStyle = draft.mode == .terminal ? .overFullScreen : .overCurrentContext
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
        // Keep separate obstacles separate: an undocked keyboard can sit near
        // the top while the app's shortcut row remains at the bottom.
        let obstacles = [keyboard, shortcutBar].map { $0.intersection(safe) }
            .filter { !$0.isNull && !$0.isEmpty }
        guard let ceiling = obstacles.map(\.minY).min() else { return area(safe: safe, keyboardTop: safe.maxY) }
        let above = area(safe: safe, keyboardTop: ceiling)
        if above.height >= 180 { return above }
        let base = area(safe: safe, keyboardTop: safe.maxY)
        let free = obstacles.reduce([base]) { regions, obstacle in
            regions.flatMap { region -> [CGRect] in
                guard region.intersects(obstacle) else { return [region] }
                let belowY = max(region.minY, obstacle.maxY + 8)
                let rightX = max(region.minX, obstacle.maxX + 8)
                return [
                    CGRect(x: region.minX, y: region.minY, width: region.width, height: max(0, min(region.maxY, obstacle.minY - 8) - region.minY)),
                    CGRect(x: region.minX, y: belowY, width: region.width, height: max(0, region.maxY - belowY)),
                    CGRect(x: region.minX, y: region.minY, width: max(0, min(region.maxX, obstacle.minX - 8) - region.minX), height: region.height),
                    CGRect(x: rightX, y: region.minY, width: max(0, region.maxX - rightX), height: region.height)
                ].filter { !$0.isEmpty }
            }
        }
        let candidates = [above] + free
        let readable = candidates.filter { $0.width >= 264 && $0.height >= 112 }
        return (readable.isEmpty ? candidates : readable).max {
            $0.width * min(324, $0.height) < $1.width * min(324, $1.height)
        } ?? above
    }
    struct Region {
        let area: CGRect
        let yieldsShortcutBar: Bool
        let fitsEditor: Bool
    }
    /// Keep a divided workspace on one page. The input page owns composition
    /// unless its unobscured area cannot hold the editor and both 44-point actions.
    static func region(safe: CGRect, division: CGRect, keyboard: CGRect,
                       shortcutBar: CGRect, mayYieldShortcutBar: Bool, minimumHeight: CGFloat = 112) -> Region {
        var content = CGRect.null, input = CGRect.null
        guard CompanionVNCTabletopRegions(safe, division, &content, &input)
                || CompanionVNCBookRegions(safe, division, &content, &input) else {
            let result = area(safe: safe, keyboard: keyboard, shortcutBar: shortcutBar)
            return Region(area: result, yieldsShortcutBar: false, fitsEditor: result.width >= 264 && result.height >= minimumHeight)
        }
        func fits(_ rect: CGRect) -> Bool { rect.width >= 264 && rect.height >= minimumHeight }
        let preferred = area(safe: input, keyboard: keyboard, shortcutBar: shortcutBar)
        if fits(preferred) { return Region(area: preferred, yieldsShortcutBar: false, fitsEditor: true) }
        if mayYieldShortcutBar && !shortcutBar.isNull && !shortcutBar.isEmpty {
            let withoutStrip = area(safe: input, keyboard: keyboard)
            if fits(withoutStrip) { return Region(area: withoutStrip, yieldsShortcutBar: true, fitsEditor: true) }
        }
        // A tall or floating keyboard may cover the input page. Use a modal
        // editor in the other genuinely free page without remounting its owner.
        let alternate = area(safe: content, keyboard: keyboard, shortcutBar: shortcutBar)
        if fits(alternate) { return Region(area: alternate, yieldsShortcutBar: false, fitsEditor: true) }
        let bounded = [preferred, alternate].max { $0.width * $0.height < $1.width * $1.height } ?? preferred
        return Region(area: bounded, yieldsShortcutBar: false, fitsEditor: false)
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
    private var paneTop: NSLayoutConstraint?
    private var usesPanePosition = false
    private var keyboardObservations: [NSObjectProtocol] = []
    private var peek: NSLayoutConstraint?
    private var grabberHeight: NSLayoutConstraint?
    private var grabberWidth: NSLayoutConstraint?
    private var grabberCenter: NSLayoutConstraint?
    private var measuredText: String?
    private var measuredWidth: CGFloat = 0
    private var measuredCategory: UIContentSizeCategory?
    private var measuredEditorHeight: CGFloat = 0
    lazy var interfaceFeedback = CompanionVNCInterfaceFeedback(view: view)
    private var grabber: UIButton?
    private var closeButton: UIButton?
    private var editorHost: UIHostingController<AnyView>?
    private weak var appearancePresenter: UIViewController?
    private var appearanceObservation: (any UITraitChangeRegistration)?
    private var card: UIView?
    private var sendBounds = CGRect.zero
    private var expansionBounds = CGRect.zero
    private var draggingHeight: CGFloat?
    private var initialFrame = CGRect.zero
    private var initialAnchor = CGPoint(x: 0.5, y: 1)
    private var initialExpanded = false
    private var dragging = false
    var deliveryActionFrame: CGRect { editorHost?.view.convert(sendBounds, to: view) ?? .zero }
    var panelFrame: CGRect { card?.frame ?? .zero }
    var expansionActionFrame: CGRect { editorHost?.view.convert(expansionBounds, to: view) ?? .zero }
    var closeActionFrame: CGRect { closeButton?.convert(closeButton?.bounds ?? .zero, to: view) ?? .zero }
    #if DEBUG
    // Controlled Simulator keyboard geometry; absent from release builds.
    var simulatedKeyboardFrame: CGRect? { didSet { view.setNeedsLayout() } }
    private var simulatedDivision: CGRect?
    @objc(setDivisionForComposerTesting:) func setDivisionForComposerTesting(_ value: NSValue) {
        simulatedDivision = value.cgRectValue; view.setNeedsLayout()
    }
    #endif
    private var keyboardFrame: CGRect {
        #if DEBUG
        if let simulatedKeyboardFrame { return simulatedKeyboardFrame }
        #endif
        return view.keyboardLayoutGuide.layoutFrame
    }
    weak var shortcutBar: UIView?
    var visibilityChanged: ((Bool) -> Void)?
    private weak var yieldedShortcutBar: UIView?
    private var shortcutBarAlpha: CGFloat = 1
    private func restoreShortcutBar() {
        if let bar = yieldedShortcutBar, bar.alpha == 0 { bar.alpha = shortcutBarAlpha }
        yieldedShortcutBar = nil
    }
    private var division: CGRect {
        #if DEBUG
        if let simulatedDivision { return simulatedDivision }
        #endif
        return CompanionVNCActiveDivision(view)
    }
    var placementArea: CGRect {
        if yieldedShortcutBar !== shortcutBar { restoreShortcutBar() }
        let bar: CGRect
        if let shortcutBar, shortcutBar.window === view.window, !shortcutBar.isHidden,
           shortcutBar.alpha > 0 || yieldedShortcutBar === shortcutBar {
            bar = view.convert(shortcutBar.bounds, from: shortcutBar)
        } else { bar = .null }
        let executionActive = (shortcutBar as? TerminalKeyboardBar)?.executionActive == true
        let preferred = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        let minimumHeight = max(112, max(44, ceil(preferred.lineHeight) + 8) + 44 + 12)
        let decision = DirectComposerPlacement.region(safe: view.safeAreaLayoutGuide.layoutFrame,
            division: division, keyboard: keyboardFrame, shortcutBar: bar,
            mayYieldShortcutBar: !executionActive, minimumHeight: minimumHeight)
        if decision.yieldsShortcutBar, let shortcutBar {
            if yieldedShortcutBar == nil { shortcutBarAlpha = shortcutBar.alpha; yieldedShortcutBar = shortcutBar }
            shortcutBar.alpha = 0
        } else { restoreShortcutBar() }
        return decision.area
    }
    init(draft: DirectTextComposerDraft) {
        self.draft = draft; presentationEpoch = draft.presentationEpoch
        super.init(nibName: nil, bundle: nil)
        overrideUserInterfaceStyle = draft.mode == .terminal ? .unspecified : .dark
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    fileprivate func followAppearance(from presenter: UIViewController) {
        if let appearancePresenter, let appearanceObservation {
            appearancePresenter.unregisterForTraitChanges(appearanceObservation)
        }
        appearancePresenter = presenter
        // The overlay must follow both inherited system changes and explicit
        // Terminal palettes, which do not automatically reach this presentation.
        overrideUserInterfaceStyle = presenter.traitCollection.userInterfaceStyle
        appearanceObservation = presenter.registerForTraitChanges([UITraitUserInterfaceStyle.self]) { [weak self] (presenter: UIViewController, _: UITraitCollection) in
            self?.overrideUserInterfaceStyle = presenter.traitCollection.userInterfaceStyle
        }
    }
    isolated deinit {
        for token in keyboardObservations { NotificationCenter.default.removeObserver(token) }
        if let appearancePresenter, let appearanceObservation {
            appearancePresenter.unregisterForTraitChanges(appearanceObservation)
        }
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear; view.accessibilityViewIsModal = true
        CompanionVNCObserveDivision(view)
        view.keyboardLayoutGuide.followsUndockedKeyboard = true
        for name in [UIResponder.keyboardWillChangeFrameNotification, UIResponder.keyboardDidChangeFrameNotification] {
            keyboardObservations.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshPlacementAfterSystemUpdate() }
            })
        }
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
            reportSendBounds: { [weak self] in self?.sendBounds = $0 },
            toggleExpansion: { [weak self] in self?.toggleExpansion() },
            reportExpansionBounds: { [weak self] in self?.expansionBounds = $0 })))
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
        let paneTop = card.topAnchor.constraint(equalTo: view.topAnchor); self.paneTop = paneTop
        paneTop.identifier = "compose-pane-top"; bottom.identifier = "compose-keyboard-bottom"
        safeBottom.identifier = "compose-safe-bottom"
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
        let width = max(1, min(traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 360 : 284, placementArea.width) - 74)
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
        cancelMovement(); draft.expanded.toggle(); draft.feedback("selection"); settle()
    }
    @objc func toggleDock() {
        guard usable else { return }
        cancelMovement(); draft.docked.toggle(); draft.expanded = false; draft.feedback("selection"); settle()
    }
    private func cancelMovement() { dragging = false; draggingHeight = nil }
    private func move(_ anchor: CGPoint) -> Bool {
        guard usable, !draft.docked, !draft.expanded else { return false }
        guard draft.floatingAnchor != anchor else { return false }
        draft.floatingAnchor = anchor; draft.feedback("selection"); settle(); return true
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
                let changed = draft.docked ? draft.expanded != initialExpanded
                    : draft.floatingAnchor != initialAnchor && [CGFloat(0), 1].contains(where: { draft.floatingAnchor.x == $0 || draft.floatingAnchor.y == $0 })
                if changed { draft.feedback("selection") }
                settle()
            } else { view.setNeedsLayout(); view.layoutIfNeeded() }
        case .cancelled, .failed:
            guard dragging else { return }
            cancelMovement(); draft.expanded = initialExpanded; draft.floatingAnchor = initialAnchor; settle()
        default: break
        }
    }
    private var hasUsableDivision: Bool {
        var content = CGRect.null, input = CGRect.null
        let safe = view.safeAreaLayoutGuide.layoutFrame
        return CompanionVNCTabletopRegions(safe, division, &content, &input)
            || CompanionVNCBookRegions(safe, division, &content, &input)
    }
    private func refreshPlacementAfterSystemUpdate() {
        guard isViewLoaded else { return }
        view.setNeedsLayout()
        // The guide can commit its final frame after the controller's layout
        // callback. Reconcile after that commit without remounting the editor.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.viewIfLoaded?.window != nil else { return }
            self.view.setNeedsLayout(); self.view.layoutIfNeeded()
        }
    }
    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in self?.refreshPlacementAfterSystemUpdate() }
    }
    private func usePanePosition(_ divided: Bool) {
        guard usesPanePosition != divided, let keyboardBottom, let safeBottom, let paneTop else { return }
        usesPanePosition = divided
        if divided {
            // A pane solver already chooses the unobscured rectangle. Tracking
            // a separate keyboard bottom can otherwise compress that rectangle
            // to zero when the keyboard changes between layout callbacks.
            view.keyboardLayoutGuide.removeAllTrackedConstraints()
            NSLayoutConstraint.deactivate([keyboardBottom, safeBottom])
            peek?.isActive = false; paneTop.isActive = true
        } else {
            paneTop.isActive = false; peek?.isActive = true
            view.keyboardLayoutGuide.setConstraints([keyboardBottom], activeWhenAwayFrom: .top)
            view.keyboardLayoutGuide.setConstraints([safeBottom], activeWhenNearEdge: .top)
        }
        let height = placementConstraints[2]
        height.isActive = false; height.priority = divided ? .required : .defaultHigh; height.isActive = true
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated); visibilityChanged?(true)
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated); restoreShortcutBar(); visibilityChanged?(false)
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
        paneTop?.constant = target.minY
        peek?.constant = area.minY - view.safeAreaInsets.top
        usePanePosition(hasUsableDivision)
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
    var toggleExpansion: () -> Void
    var reportExpansionBounds: (CGRect) -> Void
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
            HStack(alignment: .top, spacing: 0) {
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
                // A reserved column keeps the toggle out of the editor without
                // adding a header that would squeeze short keyboard layouts.
                Button { if isCurrent() { toggleExpansion() } } label: {
                    Image(systemName: draft.expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 18, weight: .medium)).foregroundStyle(.secondary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!isCurrent())
                    .accessibilityLabel(draft.expanded ? "Collapse composer" : "Expand composer")
                    .accessibilityValue(draft.expanded ? "Expanded" : "Collapsed")
                    .accessibilityIdentifier("compose-expand")
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("composer-panel")) } action: { reportExpansionBounds($0) }
            }
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
