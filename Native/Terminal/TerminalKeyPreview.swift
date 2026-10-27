#if os(iOS) && MACCOMPANION_VNC_DEVELOPMENT
import UIKit

/// A passive visual echo of the pressed key. Input remains owned by the bar's
/// existing touch-up action; cancelling or scrolling never sends a key.
class TerminalKeyPreviewButton: UIButton {
    var previewsKey = false
    var previewTitle: String?
    var previewAllowed: (() -> Bool)?
    private var bubble: UIView?
    private var anchor: CGRect?
    private var paneAnchor: CGRect?
    private var shownAt: TimeInterval?
    private var dismissal: Task<Void, Never>?
    var keyPreviewVisible: Bool { bubble?.superview != nil }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addAction(UIAction { [weak self] _ in self?.showKeyPreview() }, for: [.touchDown, .touchDragEnter])
        addAction(UIAction { [weak self] _ in self?.finishKeyPreview() }, for: .touchUpInside)
        addAction(UIAction { [weak self] _ in self?.dismissKeyPreview() },
                  for: [.touchUpOutside, .touchCancel, .touchDragExit])
        NotificationCenter.default.addObserver(self, selector: #selector(dismissKeyPreview),
            name: UIApplication.willResignActiveNotification, object: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isEnabled: Bool { didSet { if !isEnabled { dismissKeyPreview() } } }
    override func didMoveToWindow() { super.didMoveToWindow(); dismissKeyPreview() }
    override func layoutSubviews() {
        super.layoutSubviews()
        dismissMovedKeyPreview()
    }
    func dismissMovedKeyPreview() {
        guard keyPreviewVisible else { return }
        guard let window, let anchor, let paneAnchor,
              convert(bounds, to: window) == anchor, previewPane(in: window) == paneAnchor else {
            dismissKeyPreview(); return
        }
    }
    private var keyBar: TerminalKeyboardBar? {
        sequence(first: superview, next: { $0?.superview }).compactMap({ $0 as? TerminalKeyboardBar }).first
    }
    private func previewPane(in window: UIWindow) -> CGRect? {
        guard let bar = keyBar else { return nil }
        return bar.convert(bar.bounds, to: window).intersection(window.bounds.inset(by: window.safeAreaInsets)).insetBy(dx: 4, dy: 0)
    }
    func showKeyPreview() {
        keyBar?.dismissKeyPreviews()
        dismissKeyPreview()
        guard previewsKey, isEnabled, previewAllowed?() == true, let window,
              let pane = previewPane(in: window), !UIAccessibility.isVoiceOverRunning else { return }
        let key = convert(bounds, to: window)
        guard pane.width >= 44, pane.intersects(key) else { return }
        let content = UIView()
        content.isUserInteractionEnabled = false; content.accessibilityElementsHidden = true
        content.backgroundColor = .secondarySystemBackground
        content.layer.cornerRadius = 12
        content.layer.shadowColor = UIColor.black.cgColor; content.layer.shadowOpacity = 0.22
        content.layer.shadowRadius = 5; content.layer.shadowOffset = CGSize(width: 0, height: 2)
        let label = UILabel()
        label.textAlignment = .center; label.textColor = .label
        label.font = .systemFont(ofSize: 29, weight: .medium)
        label.adjustsFontSizeToFitWidth = true; label.minimumScaleFactor = 0.55
        label.text = previewTitle ?? configuration?.title ?? accessibilityLabel
        let width = min(pane.width, max(62, min(144, label.intrinsicContentSize.width + 24)))
        let x = min(max(key.midX - width / 2, pane.minX), pane.maxX - width)
        let top = max(window.safeAreaInsets.top + 4, key.minY - 66)
        content.frame = CGRect(x: x, y: top, width: width, height: 58)
        if let image = configuration?.image, previewTitle == nil {
            let icon = UIImageView(image: image.withConfiguration(UIImage.SymbolConfiguration(pointSize: 29, weight: .medium)))
            icon.contentMode = .center; icon.tintColor = .label
            icon.frame = content.bounds.insetBy(dx: 10, dy: 6); content.addSubview(icon)
        } else { label.frame = content.bounds.insetBy(dx: 10, dy: 6); content.addSubview(label) }
        window.addSubview(content); bubble = content; anchor = key; paneAnchor = pane
        shownAt = ProcessInfo.processInfo.systemUptime
    }
    private func finishKeyPreview() {
        guard let bubble, let shownAt else { return }
        guard previewAllowed?() == true else { dismissKeyPreview(); return }
        // Give even a tap that ends within one display frame a visible echo.
        // Input still sends immediately on touch-up; only the passive visual waits.
        let remaining = 0.12 - (ProcessInfo.processInfo.systemUptime - shownAt)
        guard remaining > 0 else { dismissKeyPreview(); return }
        dismissal?.cancel()
        dismissal = Task { @MainActor [weak self, weak bubble] in
            do { try await Task.sleep(for: .seconds(remaining)) } catch { return }
            guard let self, let bubble, self.bubble === bubble else { return }
            self.dismissKeyPreview()
        }
    }
    @objc func dismissKeyPreview() {
        dismissal?.cancel(); dismissal = nil
        bubble?.removeFromSuperview(); bubble = nil; anchor = nil; paneAnchor = nil; shownAt = nil
    }
}
#endif
